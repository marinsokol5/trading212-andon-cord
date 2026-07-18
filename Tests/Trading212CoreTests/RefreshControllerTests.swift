import Foundation
import XCTest
@testable import Trading212Core

final class RefreshBackoffTests: XCTestCase {
    func testManualNeverSchedules() {
        XCTAssertNil(RefreshBackoff.delay(
            interval: .manual, lastError: nil, consecutiveRateLimits: 0))
        XCTAssertNil(RefreshBackoff.delay(
            interval: .manual,
            lastError: .rateLimited(RateLimitInfo(retryAfter: 5)),
            consecutiveRateLimits: 1))
    }

    func testNormalAndExponentialDelay() {
        XCTAssertEqual(RefreshBackoff.delay(
            interval: .fiveMinutes, lastError: nil,
            consecutiveRateLimits: 0), 300)
        XCTAssertEqual(RefreshBackoff.delay(
            interval: .fiveMinutes,
            lastError: .rateLimited(RateLimitInfo()),
            consecutiveRateLimits: 1), 600)
        XCTAssertEqual(RefreshBackoff.delay(
            interval: .fiveMinutes,
            lastError: .rateLimited(RateLimitInfo()),
            consecutiveRateLimits: 4), 900)
    }

    func testBrokerResetIsNeverCappedByLocalMaximum() {
        XCTAssertEqual(RefreshBackoff.delay(
            interval: .oneMinute,
            lastError: .rateLimited(RateLimitInfo(retryAfter: 1_800)),
            consecutiveRateLimits: 1, maximumDelay: 900), 1_800)
    }
}

@MainActor
final class RefreshControllerTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_700_000_000)

    func testLoadsCacheImmediatelyAndKeepsItAfterFailure() async {
        let cached = portfolio(value: 42)
        let cache = InMemorySnapshotCache()
        try? cache.save(cached)
        let provider = StubPortfolioProvider([.failure(.network(.offline))])
        let controller = RefreshController(
            provider: provider, environment: .demo, cache: cache,
            minimumInterval: 0, dateProvider: FixedDateProvider(date))

        let initial = await controller.state
        XCTAssertEqual(initial.portfolio, cached)
        _ = await controller.refresh()
        guard case let .failed(error, lastGood) = await controller.state else {
            return XCTFail("Expected failed state")
        }
        XCTAssertEqual(error, .network(.offline))
        XCTAssertEqual(lastGood, cached)
    }

    func testSuccessfulRefreshUpdatesCacheAndClearsError() async {
        let updated = portfolio(value: 100)
        let cache = InMemorySnapshotCache()
        let provider = StubPortfolioProvider([.success(updated)])
        let controller = RefreshController(
            provider: provider, environment: .demo, cache: cache,
            minimumInterval: 0, dateProvider: FixedDateProvider(date))
        let refreshed = await controller.refresh()
        let lastError = await controller.lastError
        let state = await controller.state
        XCTAssertEqual(refreshed, updated)
        XCTAssertEqual(cache.portfolio(for: .demo), updated)
        XCTAssertNil(lastError)
        XCTAssertEqual(state, .loaded(updated))
    }

    func testMinimumIntervalDeduplicatesSequentialRefreshes() async {
        let current = portfolio(value: 100)
        let provider = StubPortfolioProvider([.success(current)])
        let controller = RefreshController(
            provider: provider, environment: .demo,
            cache: InMemorySnapshotCache(), minimumInterval: 2,
            dateProvider: FixedDateProvider(date))
        _ = await controller.refresh()
        _ = await controller.refresh()
        XCTAssertEqual(provider.callCount, 1)
    }

    func testRateLimitChangesNextDelay() async {
        let provider = StubPortfolioProvider([
            .failure(.rateLimited(RateLimitInfo(retryAfter: 500))),
        ])
        let controller = RefreshController(
            provider: provider, environment: .demo,
            cache: InMemorySnapshotCache(), interval: .oneMinute,
            minimumInterval: 0, dateProvider: FixedDateProvider(date))
        _ = await controller.refresh()
        let delay = await controller.nextDelay()
        XCTAssertEqual(delay, 500)
    }

    private func portfolio(value: Decimal) -> CurrentPortfolio {
        CurrentPortfolio(
            environment: .demo,
            account: AccountIdentity(id: "test", currency: "EUR"),
            accountValue: value, freeCash: 10, sellablePositionsValue: 0,
            positions: [], capturedAt: date)
    }
}
