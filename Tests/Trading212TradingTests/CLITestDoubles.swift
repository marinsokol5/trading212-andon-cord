import Foundation
import Trading212Core
import Trading212Trading
@testable import andon

final class TestConsole: AndonConsole, @unchecked Sendable {
    private let lock = NSLock()
    private var outputStorage = ""
    private var errorStorage = ""
    private var prompts: [String?]
    private let hasControllingTTY: Bool
    var inputData: Data

    init(
        inputData: Data = Data(),
        prompts: [String?] = [],
        hasControllingTTY: Bool = true
    ) {
        self.inputData = inputData
        self.prompts = prompts
        self.hasControllingTTY = hasControllingTTY
    }

    func output(_ text: String) {
        lock.lock(); defer { lock.unlock() }
        outputStorage += text
    }

    func error(_ text: String) {
        lock.lock(); defer { lock.unlock() }
        errorStorage += text
    }

    func prompt(_ text: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        errorStorage += text
        return prompts.isEmpty ? nil : prompts.removeFirst()
    }

    func terminalConfirmation(_ text: String) -> String? {
        guard hasControllingTTY else {
            error(text)
            return nil
        }
        return prompt(text)
    }

    func standardInput(limit: Int) throws -> Data {
        guard inputData.count <= limit else { throw CLIError.inputTooLarge }
        return inputData
    }

    func outputText() -> String {
        lock.lock(); defer { lock.unlock() }
        return outputStorage
    }

    func errorText() -> String {
        lock.lock(); defer { lock.unlock() }
        return errorStorage
    }
}

final class CountingCredentialStore: CredentialStore, TradeCredentialStatusProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Trading212Credentials] = [:]
    private var retrievals: [String: Int] = [:]
    private(set) var setCount = 0

    init(
        read: Trading212Credentials? = nil,
        trading: Trading212Credentials? = nil,
        environment: Trading212Environment = .demo
    ) {
        if let read { values[key(.read, environment)] = read }
        if let trading { values[key(.trading, environment)] = trading }
    }

    func credentials(
        for kind: CredentialKind,
        environment: Trading212Environment
    ) throws -> Trading212Credentials? {
        lock.lock(); defer { lock.unlock() }
        let key = key(kind, environment)
        retrievals[key, default: 0] += 1
        return values[key]
    }

    func set(
        _ credentials: Trading212Credentials,
        for kind: CredentialKind,
        environment: Trading212Environment
    ) throws {
        lock.lock(); defer { lock.unlock() }
        values[key(kind, environment)] = credentials
        setCount += 1
    }

    func delete(kind: CredentialKind, environment: Trading212Environment) throws {
        lock.lock(); defer { lock.unlock() }
        values.removeValue(forKey: key(kind, environment))
    }

    func isTradeCredentialConfigured(for environment: Trading212Environment) throws -> Bool {
        lock.lock(); defer { lock.unlock() }
        return values[key(.trading, environment)]?.isComplete == true
    }

    func retrievalCount(_ kind: CredentialKind, _ environment: Trading212Environment) -> Int {
        lock.lock(); defer { lock.unlock() }
        return retrievals[key(kind, environment), default: 0]
    }

    private func key(_ kind: CredentialKind, _ environment: Trading212Environment) -> String {
        "\(kind.rawValue).\(environment.rawValue)"
    }
}

final class TestMetadataStore: AccountMetadataStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: AccountMetadata] = [:]

    func metadata(for environment: Trading212Environment) throws -> AccountMetadata? {
        lock.lock(); defer { lock.unlock() }
        return values[environment.rawValue]
    }

    func save(_ metadata: AccountMetadata) throws {
        lock.lock(); defer { lock.unlock() }
        values[metadata.environment.rawValue] = metadata
    }

    func isTradeCredentialConfigured(for environment: Trading212Environment) throws -> Bool {
        try metadata(for: environment)?.tradeCredentialConfigured == true
    }
}

final class RecordingFileSystem: FileSystem, @unchecked Sendable {
    private let lock = NSLock()
    private var files: [URL: Data]
    private(set) var writeCount = 0
    private(set) var removeCount = 0

    init(files: [URL: Data] = [:]) { self.files = files }

    func data(at url: URL) throws -> Data {
        lock.lock(); defer { lock.unlock() }
        guard let data = files[url] else { throw CocoaError(.fileNoSuchFile) }
        return data
    }

    func fileExists(at url: URL) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return files[url] != nil
    }

    func createDirectory(at url: URL, permissions: FilePermissions) throws {}

    func removeItem(at url: URL) throws {
        lock.lock(); defer { lock.unlock() }
        files.removeValue(forKey: url)
        removeCount += 1
    }

    @discardableResult
    func writeAtomically(
        _ data: Data,
        to url: URL,
        permissions: FilePermissions,
        backupExisting: Bool
    ) throws -> URL? {
        lock.lock(); defer { lock.unlock() }
        var backup: URL?
        if backupExisting, let old = files[url] {
            let backupURL = URL(fileURLWithPath: url.path + ".backup")
            files[backupURL] = old
            backup = backupURL
        }
        files[url] = data
        writeCount += 1
        return backup
    }

    func writes() -> Int {
        lock.lock(); defer { lock.unlock() }
        return writeCount
    }
}

actor RoutingHTTPTransport: HTTPTransport {
    struct Response: Sendable {
        let status: Int
        let body: Data
        let headers: [String: String]

        init(status: Int = 200, body: Data, headers: [String: String] = [:]) {
            self.status = status
            self.body = body
            self.headers = headers
        }
    }

    private var routes: [String: [Response]]
    private(set) var requests: [CapturedRequest] = []

    init(routes: [String: [Response]]) { self.routes = routes }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let path = request.url!.path
        requests.append(.init(
            url: request.url!,
            method: request.httpMethod ?? "GET",
            headers: request.allHTTPHeaderFields ?? [:],
            body: request.httpBody
        ))
        guard var responses = routes[path], !responses.isEmpty else {
            throw MockFailure.unexpectedCall
        }
        let response = responses.removeFirst()
        routes[path] = responses
        return (
            response.body,
            HTTPURLResponse(
                url: request.url!,
                statusCode: response.status,
                httpVersion: "HTTP/1.1",
                headerFields: response.headers
            )!
        )
    }

    func capturedRequests() -> [CapturedRequest] { requests }
}

final class ThreadSafeCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func increment() {
        lock.lock(); defer { lock.unlock() }
        value += 1
    }

    func count() -> Int {
        lock.lock(); defer { lock.unlock() }
        return value
    }
}

func accountSummaryData(id: String = "account-1", free: String = "1000") -> Data {
    Data("""
    {
      "id":"\(id)",
      "currency":"GBP",
      "cash":{"availableToTrade":"\(free)","inPies":"0","reservedForOrders":"0"},
      "investments":{"currentValue":"3200","totalCost":"2700","unrealizedProfitLoss":"500","realizedProfitLoss":"0"},
      "totalValue":"4200"
    }
    """.utf8)
}

func positionsData() -> Data {
    Data("""
    [
      {
        "instrument":{"ticker":"AAPL_US_EQ","currency":"USD","name":"Apple","isin":"US0378331005"},
        "quantity":"10","quantityAvailableForTrading":"8","quantityInPies":"2",
        "currentPrice":"180",
        "walletImpact":{"currency":"GBP","currentValue":"1500"}
      },
      {
        "instrument":{"ticker":"MSFT_US_EQ","currency":"USD","name":"Microsoft"},
        "quantity":"5","quantityAvailableForTrading":"5","quantityInPies":"0",
        "currentPrice":"400",
        "walletImpact":{"currency":"GBP","currentValue":"2000"}
      },
      {
        "instrument":{"ticker":"VUSA_EQ","currency":"GBP","name":"Vanguard"},
        "quantity":"3","quantityAvailableForTrading":"0","quantityInPies":"3",
        "currentPrice":"80",
        "walletImpact":{"currency":"GBP","currentValue":"240"}
      }
    ]
    """.utf8)
}
