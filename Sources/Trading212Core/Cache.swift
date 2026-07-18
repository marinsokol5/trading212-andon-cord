import Foundation

public protocol SnapshotCache: Sendable {
    func portfolio(for environment: Trading212Environment) -> CurrentPortfolio?
    func save(_ portfolio: CurrentPortfolio) throws
    func remove(for environment: Trading212Environment) throws
}

public struct FileSnapshotCache: SnapshotCache, Sendable {
    public let workspace: Workspace
    private let fileSystem: any FileSystem

    public init(workspace: Workspace, fileSystem: any FileSystem = LocalFileSystem()) {
        self.workspace = workspace
        self.fileSystem = fileSystem
    }

    public func portfolio(for environment: Trading212Environment) -> CurrentPortfolio? {
        try? AtomicJSONFile.read(
            CurrentPortfolio.self,
            from: workspace.accountSnapshotURL(for: environment),
            fileSystem: fileSystem)
    }

    public func save(_ portfolio: CurrentPortfolio) throws {
        try AtomicJSONFile.write(
            portfolio,
            to: workspace.accountSnapshotURL(for: portfolio.environment),
            fileSystem: fileSystem)
    }

    public func remove(for environment: Trading212Environment) throws {
        try fileSystem.removeItem(at: workspace.accountSnapshotURL(for: environment))
    }
}

public final class InMemorySnapshotCache: SnapshotCache, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Trading212Environment: CurrentPortfolio] = [:]

    public init() {}

    public func portfolio(for environment: Trading212Environment) -> CurrentPortfolio? {
        lock.withLock { values[environment] }
    }

    public func save(_ portfolio: CurrentPortfolio) throws {
        lock.withLock { values[portfolio.environment] = portfolio }
    }

    public func remove(for environment: Trading212Environment) throws {
        _ = lock.withLock { values.removeValue(forKey: environment) }
    }
}

/// Generic actor for small Codable records that require serialized updates.
public actor JSONFileStore<Value: Codable & Sendable> {
    public let url: URL
    private let fileSystem: any FileSystem

    public init(url: URL, fileSystem: any FileSystem = LocalFileSystem()) {
        self.url = url
        self.fileSystem = fileSystem
    }

    public func load() throws -> Value? {
        guard fileSystem.fileExists(at: url) else { return nil }
        return try AtomicJSONFile.read(Value.self, from: url, fileSystem: fileSystem)
    }

    public func save(_ value: Value) throws {
        try AtomicJSONFile.write(value, to: url, fileSystem: fileSystem)
    }

    public func remove() throws { try fileSystem.removeItem(at: url) }
}
