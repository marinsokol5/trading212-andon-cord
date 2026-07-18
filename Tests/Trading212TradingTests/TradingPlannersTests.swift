import Foundation
import XCTest
@testable import Trading212Trading

final class TradingPlannersTests: XCTestCase {
    func testFloorToPrecisionAlwaysRoundsDown() {
        XCTAssertEqual(DecimalMath.floor(d("1.2345678"), scale: 6), d("1.234567"))
        XCTAssertEqual(DecimalMath.floor(d("1.9999999"), scale: 2), d("1.99"))
        XCTAssertEqual(DecimalMath.floor(10, scale: 6), 10)
        XCTAssertEqual(DecimalMath.floor(d("0.0000004"), scale: 6), 0)
        XCTAssertEqual(DecimalMath.floor(-5, scale: 6), 0)
    }

    func testSellPlanUsesOnlySellableQuantityAndSignsRequestsNegative() throws {
        let plan = try SellPlanner.plan(positions: [
            .init(
                ticker: "AAPL_US_EQ",
                name: "Apple",
                quantity: 8,
                pieQuantity: 2,
                accountPricePerShare: 150,
                sellableAccountValue: 1_200
            ),
            .init(
                ticker: "VUSA_EQ",
                quantity: 0,
                pieQuantity: 3,
                accountPricePerShare: 80,
                sellableAccountValue: 0
            ),
        ])

        XCTAssertEqual(plan.orders.count, 1)
        XCTAssertEqual(plan.orders[0].quantity, 8)
        XCTAssertEqual(plan.requests[0].quantity, -8)
        XCTAssertEqual(plan.estimatedAccountValue, 1_200)
        XCTAssertEqual(plan.piesExcluded, [
            .init(ticker: "AAPL_US_EQ", quantity: 2),
            .init(ticker: "VUSA_EQ", quantity: 3),
        ])
    }

    func testSellPlanRejectsDuplicateTickers() {
        let input = [
            SellablePosition(
                ticker: "A",
                quantity: 1,
                accountPricePerShare: 1,
                sellableAccountValue: 1
            ),
            SellablePosition(
                ticker: "A",
                quantity: 2,
                accountPricePerShare: 1,
                sellableAccountValue: 2
            ),
        ]
        XCTAssertThrowsError(try SellPlanner.plan(positions: input)) { error in
            XCTAssertEqual(error as? TradingValidationError, .duplicateTicker("A"))
        }
    }

    func testBuyPlanCashBufferWeightsAndDownwardPrecision() throws {
        let plan = try BuyPlanner.plan(
            allocations: [
                .init(
                    ticker: "AAPL_US_EQ",
                    name: "Apple",
                    savedAccountPrice: 150,
                    savedValue: 1_200,
                    savedWeight: d("0.375")
                ),
                .init(
                    ticker: "MSFT_US_EQ",
                    name: "Microsoft",
                    savedAccountPrice: 400,
                    savedValue: 2_000,
                    savedWeight: d("0.625")
                ),
            ],
            freeCash: 1_000,
            options: .init(cashFraction: d("0.99"), minimumOrderValue: 1, quantityPrecision: 6)
        )

        XCTAssertEqual(plan.investableCash, 990)
        XCTAssertEqual(plan.orders[0].targetAccountValue, d("371.25"))
        XCTAssertEqual(plan.orders[0].quantity, d("2.475"))
        XCTAssertEqual(plan.orders[1].targetAccountValue, d("618.75"))
        XCTAssertEqual(plan.orders[1].quantity, d("1.546875"))
        XCTAssertLessThanOrEqual(plan.allocatedAtStalePrices, plan.investableCash)
        XCTAssertGreaterThanOrEqual(plan.estimatedCashRemaining, 10)
        XCTAssertTrue(plan.requests.allSatisfy { $0.quantity > 0 })
    }

    func testBuyPlanRenormalizesAfterHoldingWasDeleted() throws {
        let plan = try BuyPlanner.plan(
            allocations: [
                .init(
                    ticker: "AAPL_US_EQ",
                    savedAccountPrice: 150,
                    savedValue: 1_200,
                    savedWeight: d("0.375")
                ),
            ],
            freeCash: 1_000,
            options: .init(cashFraction: 1, minimumOrderValue: 1, quantityPrecision: 6)
        )
        XCTAssertEqual(plan.orders[0].normalizedWeight, 1)
        XCTAssertEqual(plan.orders[0].targetAccountValue, 1_000)
        XCTAssertEqual(plan.orders[0].quantity, d("6.666666"))
    }

    func testBuyPlanUsesValuesWhenWeightsAreMissing() throws {
        let plan = try BuyPlanner.plan(
            allocations: [
                .init(ticker: "A", savedAccountPrice: 10, savedValue: 30, savedWeight: 0),
                .init(ticker: "B", savedAccountPrice: 10, savedValue: 70, savedWeight: 0),
            ],
            freeCash: 100,
            options: .init(cashFraction: 1, minimumOrderValue: 0, quantityPrecision: 2)
        )
        XCTAssertEqual(plan.orders[0].normalizedWeight, d("0.3"))
        XCTAssertEqual(plan.orders[1].normalizedWeight, d("0.7"))
    }

    func testBuyPlanReportsMinimumPriceAndRoundedZeroSkips() throws {
        let plan = try BuyPlanner.plan(
            allocations: [
                .init(ticker: "BIG", savedAccountPrice: 10, savedValue: 999, savedWeight: d("0.998999")),
                .init(ticker: "TINY", savedAccountPrice: 10, savedValue: 1, savedWeight: d("0.001")),
                .init(ticker: "NOPRICE", savedAccountPrice: 0, savedValue: 1, savedWeight: d("0.0000005")),
                .init(ticker: "EXPENSIVE", savedAccountPrice: d("10000000000"), savedValue: 1, savedWeight: d("0.0000005")),
            ],
            freeCash: 1_000,
            options: .init(cashFraction: 1, minimumOrderValue: d("0.0001"), quantityPrecision: 6)
        )
        XCTAssertTrue(plan.skipped.contains { item in
            item.ticker == "NOPRICE" && item.reason == .nonPositivePrice
        })
        XCTAssertTrue(plan.skipped.contains { item in
            guard item.ticker == "EXPENSIVE" else { return false }
            if case .quantityRoundedToZero = item.reason { return true }
            return false
        })
    }

    func testBuyPlanSkipsTargetBelowMinimum() throws {
        let plan = try BuyPlanner.plan(
            allocations: [
                .init(ticker: "BIG", savedAccountPrice: 10, savedValue: 999, savedWeight: d("0.999")),
                .init(ticker: "TINY", savedAccountPrice: 10, savedValue: 1, savedWeight: d("0.001")),
            ],
            freeCash: 1_000,
            options: .init(cashFraction: 1, minimumOrderValue: 5, quantityPrecision: 6)
        )
        XCTAssertEqual(plan.orders.map(\.ticker), ["BIG"])
        guard case .belowMinimum(let target, let minimum) = plan.skipped[0].reason else {
            return XCTFail("expected below-minimum skip")
        }
        XCTAssertEqual(target, 1)
        XCTAssertEqual(minimum, 5)
    }

    func testBuyOptionsAndFreeCashValidation() {
        XCTAssertThrowsError(try BuyPlanningOptions(cashFraction: 0).validate())
        XCTAssertThrowsError(try BuyPlanningOptions(cashFraction: d("1.01")).validate())
        XCTAssertThrowsError(try BuyPlanningOptions(minimumOrderValue: -1).validate())
        XCTAssertThrowsError(try BuyPlanningOptions(quantityPrecision: 13).validate())
        XCTAssertThrowsError(try BuyPlanner.plan(allocations: [
            .init(ticker: "A", savedAccountPrice: 1, savedValue: 1, savedWeight: 1),
        ], freeCash: 0))
    }
}

private func d(_ value: String) -> Decimal {
    Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))!
}
