import Darwin
import Foundation
import Trading212Core

public struct TradeReceipt: Codable, Equatable, Sendable {
    public static let schemaIdentifier = "com.marinsokol.trading212andoncord.trade-receipt"
    public static let currentVersion = 1

    public enum RunStatus: String, Codable, Sendable {
        case running
        case completed
        case completedWithRejections
        case stoppedBeforeSubmission
        case stoppedAmbiguous
    }

    public enum OrderState: Codable, Equatable, Sendable {
        case notSent
        /// Persisted before calling the non-idempotent endpoint. A process death in
        /// this state is ambiguous and must be reconciled in the broker app.
        case submitting(at: Date)
        case accepted(orderID: String?, brokerStatus: MarketOrderStatus, at: Date)
        case rejected(message: String, brokerStatus: MarketOrderStatus?, at: Date)
        case notSubmitted(message: String, at: Date)
        case ambiguous(message: String, at: Date)
    }

    /// Broker fields retained for post-interruption reconciliation. These are
    /// deliberately non-secret and mirror the response that caused the state
    /// transition, including partial-fill information.
    public struct BrokerResult: Codable, Equatable, Sendable {
        public let orderID: String?
        public let ticker: String?
        public let quantity: Decimal?
        public let filledQuantity: Decimal?
        public let filledValue: Decimal?
        public let status: MarketOrderStatus
        public let side: String?
        public let currency: String?
        public let createdAt: Date?

        public init(response: MarketOrderResponse) {
            orderID = response.id
            ticker = response.ticker
            quantity = response.quantity
            filledQuantity = response.filledQuantity
            filledValue = response.filledValue
            status = response.status
            side = response.side
            currency = response.currency
            createdAt = response.createdAt
        }
    }

    public struct Order: Codable, Equatable, Sendable {
        public let index: Int
        public let ticker: String
        public let quantity: Decimal
        public var state: OrderState
        public var brokerResult: BrokerResult?

        public init(
            index: Int,
            ticker: String,
            quantity: Decimal,
            state: OrderState = .notSent,
            brokerResult: BrokerResult? = nil
        ) {
            self.index = index
            self.ticker = ticker
            self.quantity = quantity
            self.state = state
            self.brokerResult = brokerResult
        }
    }

    public let schema: String
    public let version: Int
    public let id: UUID
    public let action: TradingAction
    public let environment: Trading212Environment
    public let accountID: String
    public let snapshotPath: String?
    public let startedAt: Date
    public var updatedAt: Date
    public var completedAt: Date?
    public var status: RunStatus
    public var orders: [Order]

    public init(
        id: UUID = UUID(),
        action: TradingAction,
        environment: Trading212Environment,
        accountID: String,
        snapshotPath: String?,
        startedAt: Date,
        requests: [MarketOrderRequest]
    ) {
        schema = Self.schemaIdentifier
        version = Self.currentVersion
        self.id = id
        self.action = action
        self.environment = environment
        self.accountID = accountID
        self.snapshotPath = snapshotPath
        self.startedAt = startedAt
        updatedAt = startedAt
        completedAt = nil
        status = .running
        orders = requests.enumerated().map { index, request in
            Order(index: index, ticker: request.ticker, quantity: request.quantity)
        }
    }

    public var acceptedCount: Int {
        orders.count { order in
            if case .accepted = order.state { return true }
            return false
        }
    }

    public var rejectedCount: Int {
        orders.count { order in
            if case .rejected = order.state { return true }
            return false
        }
    }

    public var notSent: [Order] {
        orders.filter { order in
            switch order.state {
            case .notSent, .notSubmitted:
                return true
            default:
                return false
            }
        }
    }
}

public struct TradeAuditEvent: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case runStarted
        case orderSubmitting
        case orderAccepted
        case orderRejected
        case runStopped
        case runCompleted
    }

    public let timestamp: Date
    public let receiptID: UUID
    public let action: TradingAction
    public let environment: Trading212Environment
    public let kind: Kind
    public let ticker: String?
    public let orderIndex: Int?
    public let message: String?

    public init(
        timestamp: Date,
        receiptID: UUID,
        action: TradingAction,
        environment: Trading212Environment,
        kind: Kind,
        ticker: String? = nil,
        orderIndex: Int? = nil,
        message: String? = nil
    ) {
        self.timestamp = timestamp
        self.receiptID = receiptID
        self.action = action
        self.environment = environment
        self.kind = kind
        self.ticker = ticker
        self.orderIndex = orderIndex
        self.message = message
    }
}

public protocol TradeJournaling: Sendable {
    /// Implementations persist the complete receipt atomically, then append the
    /// corresponding redacted audit event before returning.
    func record(receipt: TradeReceipt, event: TradeAuditEvent) async throws
}

public enum TradeJournalError: Error, Equatable, Sendable, CustomStringConvertible {
    case createDirectory(String)
    case encode
    case writeReceipt(String)
    case appendAudit(String)

    public var description: String {
        switch self {
        case .createDirectory(let path): "could not create private receipt directory at \(path)"
        case .encode: "could not encode the trade receipt"
        case .writeReceipt(let path): "could not atomically write trade receipt at \(path)"
        case .appendAudit(let path): "could not append the trade audit at \(path)"
        }
    }
}

public actor FileTradeJournal: TradeJournaling {
    public let receiptURL: URL
    public let auditURL: URL
    private let fileManager: FileManager

    public init(receiptURL: URL, auditURL: URL, fileManager: FileManager = .default) {
        self.receiptURL = receiptURL
        self.auditURL = auditURL
        self.fileManager = fileManager
    }

    public func record(receipt: TradeReceipt, event: TradeAuditEvent) async throws {
        do {
            try ensurePrivateDirectory(receiptURL.deletingLastPathComponent())
            try ensurePrivateDirectory(auditURL.deletingLastPathComponent())
        } catch {
            throw TradeJournalError.createDirectory(receiptURL.deletingLastPathComponent().path)
        }

        let receiptData: Data
        let auditData: Data
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            receiptData = try encoder.encode(receipt) + Data([0x0A])

            let auditEncoder = JSONEncoder()
            auditEncoder.dateEncodingStrategy = .iso8601
            auditEncoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            auditData = try auditEncoder.encode(event) + Data([0x0A])
        } catch {
            throw TradeJournalError.encode
        }

        do {
            try atomicPrivateWrite(receiptData, to: receiptURL)
        } catch {
            throw TradeJournalError.writeReceipt(receiptURL.path)
        }
        do {
            try appendPrivate(auditData, to: auditURL)
        } catch {
            throw TradeJournalError.appendAudit(auditURL.path)
        }
    }

    private func ensurePrivateDirectory(_ url: URL) throws {
        try fileManager.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }

    private func atomicPrivateWrite(_ data: Data, to destination: URL) throws {
        _ = try LocalFileSystem().writeAtomically(
            data,
            to: destination,
            permissions: .ownerReadWrite,
            backupExisting: false
        )
    }

    private func appendPrivate(_ data: Data, to destination: URL) throws {
        let descriptor = Darwin.open(
            destination.path,
            O_WRONLY | O_CREAT | O_APPEND,
            mode_t(S_IRUSR | S_IWUSR)
        )
        guard descriptor >= 0 else { throw TradeJournalError.appendAudit(destination.path) }
        defer { _ = Darwin.close(descriptor) }
        guard Darwin.lockf(descriptor, F_LOCK, 0) == 0 else {
            throw TradeJournalError.appendAudit(destination.path)
        }
        defer { _ = Darwin.lockf(descriptor, F_ULOCK, 0) }

        let wroteAll = data.withUnsafeBytes { bytes -> Bool in
            guard let base = bytes.baseAddress else { return data.isEmpty }
            var offset = 0
            while offset < bytes.count {
                let written = Darwin.write(
                    descriptor,
                    base.advanced(by: offset),
                    bytes.count - offset
                )
                if written > 0 {
                    offset += written
                } else if written < 0, errno == EINTR {
                    continue
                } else {
                    return false
                }
            }
            return true
        }
        guard Darwin.fchmod(descriptor, mode_t(S_IRUSR | S_IWUSR)) == 0,
              wroteAll,
              Darwin.fsync(descriptor) == 0 else {
            throw TradeJournalError.appendAudit(destination.path)
        }
        try syncParentDirectory(of: destination)
    }

    private func syncParentDirectory(of destination: URL) throws {
        let parent = destination.deletingLastPathComponent()
        let descriptor = Darwin.open(parent.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard descriptor >= 0 else {
            throw TradeJournalError.appendAudit(destination.path)
        }
        defer { _ = Darwin.close(descriptor) }
        guard Darwin.fsync(descriptor) == 0 else {
            throw TradeJournalError.appendAudit(destination.path)
        }
    }
}

public actor InMemoryTradeJournal: TradeJournaling {
    public private(set) var records: [(TradeReceipt, TradeAuditEvent)] = []

    public init() {}

    public func record(receipt: TradeReceipt, event: TradeAuditEvent) async throws {
        records.append((receipt, event))
    }
}
