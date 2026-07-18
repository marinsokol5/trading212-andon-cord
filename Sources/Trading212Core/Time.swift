import Foundation

public protocol DateProviding: Sendable {
    func now() -> Date
}

public struct SystemDateProvider: DateProviding, Sendable {
    public init() {}
    public func now() -> Date { Date() }
}

public struct FixedDateProvider: DateProviding, Sendable {
    public let date: Date
    public init(_ date: Date) { self.date = date }
    public func now() -> Date { date }
}

public protocol Sleeping: Sendable {
    func sleep(for duration: TimeInterval) async throws
}

public struct TaskSleeper: Sleeping, Sendable {
    public init() {}

    public func sleep(for duration: TimeInterval) async throws {
        guard duration > 0 else { return }
        try await Task.sleep(for: .seconds(duration))
    }
}
