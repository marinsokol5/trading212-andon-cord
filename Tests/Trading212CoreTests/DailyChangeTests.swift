import Foundation
import XCTest
@testable import Trading212Core

final class DailyChangeTests: XCTestCase {
    private let anchor = Date(timeIntervalSince1970: 1_752_900_000)

    private func portfolio(
        accountID: String = "account",
        currency: String = "EUR",
        value: Decimal = 100_000,
        unrealizedPnL: Decimal? = nil,
        capturedAt: Date? = nil
    ) -> CurrentPortfolio {
        CurrentPortfolio(
            environment: .demo,
            account: AccountIdentity(id: accountID, currency: currency),
            accountValue: value, freeCash: 10, sellablePositionsValue: 0,
            unrealizedProfitLoss: unrealizedPnL,
            positions: [], capturedAt: capturedAt ?? anchor)
    }

    private func baseline(
        accountID: String = "account",
        currency: String = "EUR",
        value: Decimal = 100_000,
        unrealizedPnL: Decimal? = nil,
        age: TimeInterval = 0
    ) -> DailyBaseline {
        DailyBaseline(
            accountID: accountID, totalValue: value,
            unrealizedProfitLoss: unrealizedPnL, currencyCode: currency,
            asOf: anchor.addingTimeInterval(-age))
    }

    // MARK: Rolling

    func testNoExistingBaselineAnchorsToCurrent() {
        let current = portfolio(value: 123, unrealizedPnL: 45)
        let rolled = DailyBaseline.rolled(existing: nil, current: current)
        XCTAssertEqual(rolled, DailyBaseline(portfolio: current))
        XCTAssertEqual(rolled.totalValue, 123)
        XCTAssertEqual(rolled.unrealizedProfitLoss, 45)
        XCTAssertEqual(rolled.asOf, anchor)
    }

    func testKeepsBaselineWithinWindow() {
        let existing = baseline(value: 90_000, unrealizedPnL: 1, age: 3600)
        let rolled = DailyBaseline.rolled(
            existing: existing, current: portfolio(unrealizedPnL: 2))
        XCTAssertEqual(rolled, existing)
    }

    func testReanchorsOncePastWindow() {
        let existing = baseline(value: 90_000, age: 25 * 3600)
        let current = portfolio()
        XCTAssertEqual(
            DailyBaseline.rolled(existing: existing, current: current),
            DailyBaseline(portfolio: current))
    }

    func testReanchorsOnCurrencyChange() {
        let existing = baseline(currency: "USD", age: 3600)
        let current = portfolio(currency: "EUR")
        XCTAssertEqual(
            DailyBaseline.rolled(existing: existing, current: current),
            DailyBaseline(portfolio: current))
    }

    func testReanchorsOnAccountChange() {
        let existing = baseline(accountID: "old", age: 3600)
        let current = portfolio(accountID: "new")
        XCTAssertEqual(
            DailyBaseline.rolled(existing: existing, current: current),
            DailyBaseline(portfolio: current))
    }

    func testReanchorsWhenPnLAvailabilityFlips() {
        let existing = baseline(unrealizedPnL: nil, age: 3600)
        let current = portfolio(unrealizedPnL: 500)
        XCTAssertEqual(
            DailyBaseline.rolled(existing: existing, current: current),
            DailyBaseline(portfolio: current))
    }

    // MARK: Change

    func testUpwardChange() throws {
        let change = try XCTUnwrap(DailyChange.between(
            baseline: baseline(value: 100_000),
            current: portfolio(value: 101_300)))
        XCTAssertEqual(change.absolute, 1300)
        XCTAssertEqual(change.fraction, Decimal(string: "0.013"))
        XCTAssertTrue(change.isUp)
        XCTAssertFalse(change.isDown)
        XCTAssertEqual(change.since, anchor)
    }

    func testDownwardChange() throws {
        let change = try XCTUnwrap(DailyChange.between(
            baseline: baseline(value: 100_000),
            current: portfolio(value: 97_000)))
        XCTAssertEqual(change.absolute, -3000)
        XCTAssertTrue(change.isDown)
    }

    func testCurrencyMismatchYieldsNoChange() {
        XCTAssertNil(DailyChange.between(
            baseline: baseline(currency: "USD"),
            current: portfolio(currency: "EUR")))
    }

    func testAccountMismatchYieldsNoChange() {
        XCTAssertNil(DailyChange.between(
            baseline: baseline(accountID: "old"),
            current: portfolio(accountID: "new")))
    }

    func testZeroBaselineHasNoFraction() throws {
        let change = try XCTUnwrap(DailyChange.between(
            baseline: baseline(value: 0),
            current: portfolio(value: 1300)))
        XCTAssertEqual(change.absolute, 1300)
        XCTAssertNil(change.fraction)
    }

    func testUsesPnLDeltaWhenBothPresent() throws {
        let change = try XCTUnwrap(DailyChange.between(
            baseline: baseline(value: 100_000, unrealizedPnL: 30_000),
            current: portfolio(value: 100_000, unrealizedPnL: 32_155)))
        XCTAssertEqual(change.absolute, 2155)
        XCTAssertEqual(change.fraction, Decimal(2155) / Decimal(100_000))
    }

    func testCashDepositDoesNotMovePnLChange() throws {
        let change = try XCTUnwrap(DailyChange.between(
            baseline: baseline(value: 100_000, unrealizedPnL: 30_000),
            current: portfolio(value: 150_000, unrealizedPnL: 30_000)))
        XCTAssertEqual(change.absolute, 0)
        XCTAssertFalse(change.isUp)
        XCTAssertFalse(change.isDown)
    }

    func testFallsBackToTotalValueWhenPnLMissing() throws {
        let change = try XCTUnwrap(DailyChange.between(
            baseline: baseline(value: 100_000, unrealizedPnL: 30_000),
            current: portfolio(value: 101_300, unrealizedPnL: nil)))
        XCTAssertEqual(change.absolute, 1300)
    }

    // MARK: Store

    func testFileStoreRoundTripAndRemove() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(component: "DailyChangeTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let workspace = Workspace(rootURL: directory)
        try workspace.prepare()
        let store = FileDailyBaselineStore(workspace: workspace)
        XCTAssertNil(store.baseline(for: .demo))

        let demo = baseline(value: 100, unrealizedPnL: 5)
        let live = baseline(value: 200)
        try store.save(demo, for: .demo)
        try store.save(live, for: .live)
        XCTAssertEqual(store.baseline(for: .demo), demo)
        XCTAssertEqual(store.baseline(for: .live), live)

        try store.remove(for: .demo)
        XCTAssertNil(store.baseline(for: .demo))
        XCTAssertEqual(store.baseline(for: .live), live)
    }
}
