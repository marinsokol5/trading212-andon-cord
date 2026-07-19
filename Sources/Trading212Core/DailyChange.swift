import Foundation

/// The rolling anchor a "daily change" figure is measured *from*: one saved
/// portfolio reading, kept until it ages past the window (~24h) or stops being
/// comparable, then re-anchored to the next reading.
public struct DailyBaseline: Codable, Equatable, Sendable {
    /// The window after which the anchor rolls forward to the current reading.
    public static let window: TimeInterval = 24 * 60 * 60

    public let accountID: String
    public let totalValue: Decimal
    /// Open-position P/L at the anchor. When both the anchor and the current
    /// reading carry it, the change is the P/L delta, so cash deposits and
    /// withdrawals leave the figure unmoved.
    public let unrealizedProfitLoss: Decimal?
    public let currencyCode: String
    public let asOf: Date

    public init(
        accountID: String,
        totalValue: Decimal,
        unrealizedProfitLoss: Decimal?,
        currencyCode: String,
        asOf: Date
    ) {
        self.accountID = accountID
        self.totalValue = totalValue
        self.unrealizedProfitLoss = unrealizedProfitLoss
        self.currencyCode = currencyCode
        self.asOf = asOf
    }

    public init(portfolio: CurrentPortfolio) {
        self.init(
            accountID: portfolio.account.id,
            totalValue: portfolio.accountValue,
            unrealizedProfitLoss: portfolio.unrealizedProfitLoss,
            currencyCode: portfolio.account.currency,
            asOf: portfolio.capturedAt)
    }

    /// Keeps `existing` only while it stays comparable to `current`: same
    /// account and currency, unchanged P/L availability (a flip would switch
    /// the change basis mid-window), and younger than `window`. Anything else
    /// re-anchors to the current reading.
    public static func rolled(
        existing: DailyBaseline?,
        current: CurrentPortfolio,
        window: TimeInterval = DailyBaseline.window
    ) -> DailyBaseline {
        if let existing,
           existing.accountID == current.account.id,
           existing.currencyCode == current.account.currency,
           (existing.unrealizedProfitLoss == nil) == (current.unrealizedProfitLoss == nil),
           current.capturedAt.timeIntervalSince(existing.asOf) < window {
            return existing
        }
        return DailyBaseline(portfolio: current)
    }
}

/// The change from a `DailyBaseline` to a current reading: signed amount plus,
/// when the baseline value is non-zero, the fraction for a "%" display.
public struct DailyChange: Equatable, Sendable {
    /// `current − baseline`, negative when down.
    public let absolute: Decimal
    /// `absolute / baseline value`; nil when the baseline value is zero.
    public let fraction: Decimal?
    public let currencyCode: String
    /// When the baseline was anchored — the moment the change is measured from.
    public let since: Date

    public var isUp: Bool { absolute > 0 }
    public var isDown: Bool { absolute < 0 }

    /// Nil when the account or currency differ — that difference would be
    /// meaningless, and the next refresh re-anchors anyway. Prefers the
    /// unrealized-P/L delta (deposit-proof); falls back to the total-value
    /// delta. The percentage is always taken against the window-start value.
    public static func between(
        baseline: DailyBaseline,
        current: CurrentPortfolio
    ) -> DailyChange? {
        guard baseline.accountID == current.account.id,
              baseline.currencyCode == current.account.currency else { return nil }
        let absolute: Decimal
        if let basePnL = baseline.unrealizedProfitLoss,
           let currentPnL = current.unrealizedProfitLoss {
            absolute = currentPnL - basePnL
        } else {
            absolute = current.accountValue - baseline.totalValue
        }
        return DailyChange(
            absolute: absolute,
            fraction: baseline.totalValue == 0 ? nil : absolute / baseline.totalValue,
            currencyCode: baseline.currencyCode,
            since: baseline.asOf)
    }
}

public protocol DailyBaselineStore: Sendable {
    func baseline(for environment: Trading212Environment) -> DailyBaseline?
    func save(_ baseline: DailyBaseline, for environment: Trading212Environment) throws
    func remove(for environment: Trading212Environment) throws
}

public struct FileDailyBaselineStore: DailyBaselineStore, Sendable {
    public let workspace: Workspace
    private let fileSystem: any FileSystem

    public init(workspace: Workspace, fileSystem: any FileSystem = LocalFileSystem()) {
        self.workspace = workspace
        self.fileSystem = fileSystem
    }

    public func baseline(for environment: Trading212Environment) -> DailyBaseline? {
        try? AtomicJSONFile.read(
            DailyBaseline.self,
            from: workspace.dailyBaselineURL(for: environment),
            fileSystem: fileSystem)
    }

    public func save(_ baseline: DailyBaseline, for environment: Trading212Environment) throws {
        try AtomicJSONFile.write(
            baseline,
            to: workspace.dailyBaselineURL(for: environment),
            fileSystem: fileSystem)
    }

    public func remove(for environment: Trading212Environment) throws {
        try fileSystem.removeItem(at: workspace.dailyBaselineURL(for: environment))
    }
}

public final class InMemoryDailyBaselineStore: DailyBaselineStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Trading212Environment: DailyBaseline] = [:]

    public init() {}

    public func baseline(for environment: Trading212Environment) -> DailyBaseline? {
        lock.withLock { values[environment] }
    }

    public func save(_ baseline: DailyBaseline, for environment: Trading212Environment) throws {
        lock.withLock { values[environment] = baseline }
    }

    public func remove(for environment: Trading212Environment) throws {
        _ = lock.withLock { values.removeValue(forKey: environment) }
    }
}
