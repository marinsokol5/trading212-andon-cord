import Foundation

public enum RefreshBackoff {
    public static func delay(interval: RefreshInterval,
                             lastError: Trading212APIError?,
                             consecutiveRateLimits: Int,
                             maximumDelay: TimeInterval = 15 * 60,
                             now: Date = Date()) -> TimeInterval? {
        guard let normal = interval.seconds else { return nil }
        guard case let .rateLimited(info)? = lastError else { return normal }
        let exponent = min(max(consecutiveRateLimits, 1), 20)
        let exponential = normal * pow(2, Double(exponent))
        return max(info.delay(at: now) ?? 0, min(maximumDelay, exponential))
    }
}

public enum RefreshState: Equatable, Sendable {
    case needsCredentials
    case idle(CurrentPortfolio?)
    case refreshing(CurrentPortfolio?)
    case loaded(CurrentPortfolio)
    case failed(error: Trading212APIError, lastGood: CurrentPortfolio?)

    public var portfolio: CurrentPortfolio? {
        switch self {
        case .needsCredentials: nil
        case let .idle(value), let .refreshing(value): value
        case let .loaded(value): value
        case let .failed(_, value): value
        }
    }
}

/// Serializes refreshes, preserves the last good value, and calculates the
/// next rate-limit-aware delay. UI ownership remains outside this actor.
public actor RefreshController {
    public private(set) var state: RefreshState
    public private(set) var lastAttempt: Date?
    public private(set) var lastError: Trading212APIError?

    private let provider: any PortfolioProvider
    private let environment: Trading212Environment
    private let cache: any SnapshotCache
    private let dateProvider: any DateProviding
    private let sleeper: any Sleeping
    private let minimumInterval: TimeInterval
    private var interval: RefreshInterval
    private var consecutiveRateLimits = 0
    private var isRefreshing = false
    private var loopTask: Task<Void, Never>?

    public init(provider: any PortfolioProvider,
                environment: Trading212Environment,
                cache: any SnapshotCache,
                interval: RefreshInterval = .fiveMinutes,
                minimumInterval: TimeInterval = 5,
                dateProvider: any DateProviding = SystemDateProvider(),
                sleeper: any Sleeping = TaskSleeper()) {
        self.provider = provider
        self.environment = environment
        self.cache = cache
        self.interval = interval
        self.minimumInterval = minimumInterval
        self.dateProvider = dateProvider
        self.sleeper = sleeper
        let cached = cache.portfolio(for: environment)
        self.state = .idle(cached)
    }

    deinit { loopTask?.cancel() }

    public func setInterval(_ interval: RefreshInterval) {
        self.interval = interval
        restartLoop()
    }

    @discardableResult
    public func refresh(force: Bool = false) async -> CurrentPortfolio? {
        let now = dateProvider.now()
        if !force, let lastAttempt,
           now.timeIntervalSince(lastAttempt) < minimumInterval {
            return state.portfolio
        }
        guard !isRefreshing else { return state.portfolio }

        isRefreshing = true
        lastAttempt = now
        state = .refreshing(state.portfolio)
        defer { isRefreshing = false }

        do {
            let portfolio = try await provider.fetchPortfolio()
            try? cache.save(portfolio)
            state = .loaded(portfolio)
            lastError = nil
            consecutiveRateLimits = 0
            return portfolio
        } catch let error as Trading212APIError {
            if case .rateLimited = error { consecutiveRateLimits += 1 }
            else { consecutiveRateLimits = 0 }
            lastError = error
            state = .failed(error: error, lastGood: state.portfolio)
            return state.portfolio
        } catch {
            let mapped = Trading212APIError.network(.other)
            consecutiveRateLimits = 0
            lastError = mapped
            state = .failed(error: mapped, lastGood: state.portfolio)
            return state.portfolio
        }
    }

    public func nextDelay() -> TimeInterval? {
        RefreshBackoff.delay(
            interval: interval, lastError: lastError,
            consecutiveRateLimits: consecutiveRateLimits,
            now: dateProvider.now())
    }

    public func start() {
        guard loopTask == nil else { return }
        loopTask = Task { [weak self] in
            _ = await self?.refresh(force: true)
            while !Task.isCancelled {
                guard let delay = await self?.nextDelay(),
                      let sleeper = await self?.configuredSleeper() else { return }
                do { try await sleeper.sleep(for: delay) }
                catch { return }
                guard !Task.isCancelled else { return }
                _ = await self?.refresh(force: true)
            }
        }
    }

    public func stop() {
        loopTask?.cancel()
        loopTask = nil
    }

    private func restartLoop() {
        let wasRunning = loopTask != nil
        stop()
        if wasRunning { start() }
    }

    private func configuredSleeper() -> any Sleeping { sleeper }
}
