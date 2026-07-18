import Foundation
import XCTest
@testable import Trading212Core

final class PortfolioBuilderTests: XCTestCase {
    private let summary = AccountSummary(
        id: "account-1", currency: "EUR",
        cash: AccountCashSummary(availableToTrade: 100),
        investments: AccountInvestmentsSummary(currentValue: 300),
        totalValue: 400)

    private func position(_ ticker: String, quantity: Decimal, sellable: Decimal,
                          pies: Decimal, currentValue: Decimal) -> Trading212Position {
        Trading212Position(
            instrument: Trading212Instrument(ticker: ticker, name: ticker, currency: "USD"),
            quantity: quantity, quantityAvailableForTrading: sellable, quantityInPies: pies,
            currentPrice: 100,
            walletImpact: Trading212WalletImpact(currency: "EUR", currentValue: currentValue))
    }

    func testWeightsUseOnlySellableAccountCurrencyValue() throws {
        let portfolio = try CurrentPortfolioBuilder.build(
            summary: summary,
            positions: [
                position("AAA", quantity: 10, sellable: 8, pies: 2, currentValue: 100),
                position("BBB", quantity: 4, sellable: 4, pies: 0, currentValue: 100),
                position("PIE", quantity: 2, sellable: 0, pies: 2, currentValue: 50),
            ], environment: .demo)

        // AAA account price = 10, sellable value 80. BBB = 25 * 4 = 100.
        XCTAssertEqual(portfolio.sellablePositionsValue, 180)
        XCTAssertEqual(portfolio.positions[0].sellableWeight, Decimal(80) / Decimal(180))
        XCTAssertEqual(portfolio.positions[1].sellableWeight, Decimal(100) / Decimal(180))
        XCTAssertEqual(portfolio.positions[2].sellableWeight, 0)
    }

    func testDuplicateTickerRejected() {
        XCTAssertThrowsError(try CurrentPortfolioBuilder.build(
            summary: summary,
            positions: [
                position("AAA", quantity: 1, sellable: 1, pies: 0, currentValue: 10),
                position("AAA", quantity: 1, sellable: 1, pies: 0, currentValue: 10),
            ], environment: .demo)) {
                XCTAssertEqual($0 as? PortfolioBuilderError, .duplicateTicker("AAA"))
            }
    }

    func testWalletCurrencyMismatchRejected() {
        let position = Trading212Position(
            instrument: Trading212Instrument(ticker: "AAA"),
            quantity: 1, quantityAvailableForTrading: 1,
            walletImpact: Trading212WalletImpact(currency: "GBP", currentValue: 10))
        XCTAssertThrowsError(try CurrentPortfolioBuilder.build(
            summary: summary, positions: [position], environment: .demo)) {
                XCTAssertEqual($0 as? PortfolioBuilderError,
                               .walletCurrencyMismatch(ticker: "AAA", expected: "EUR", actual: "GBP"))
            }
    }

    func testSellableQuantityCannotExceedTotal() {
        XCTAssertThrowsError(try CurrentPortfolioBuilder.build(
            summary: summary,
            positions: [position("AAA", quantity: 1, sellable: 2, pies: 0, currentValue: 10)],
            environment: .demo)) {
                XCTAssertEqual($0 as? PortfolioBuilderError, .sellableQuantityExceedsTotal("AAA"))
            }
    }

    func testPortfolioCodableRoundTripKeepsDecimalValues() throws {
        let original = try CurrentPortfolioBuilder.build(
            summary: summary,
            positions: [position("AAA", quantity: 3, sellable: 2, pies: 1,
                                  currentValue: Decimal(string: "33.333333")!)],
            environment: .demo,
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(CurrentPortfolio.self, from: data), original)
    }
}
