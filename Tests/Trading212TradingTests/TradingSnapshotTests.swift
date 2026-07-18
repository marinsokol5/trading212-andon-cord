import Foundation
import XCTest
import Trading212Core
@testable import Trading212Trading

final class TradingSnapshotTests: XCTestCase {
    func testCanonicalRoundTripUsesDecimalStringsAndTrailingNewline() throws {
        let snapshot = fixture()
        let data = try TradingSnapshotCodec.encode(snapshot)
        XCTAssertEqual(data.last, 0x0A)

        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let totals = try XCTUnwrap(object["totals"] as? [String: Any])
        XCTAssertEqual(totals["accountValue"] as? String, "4200")
        let positions = try XCTUnwrap(object["positions"] as? [[String: Any]])
        XCTAssertEqual(positions[0]["sellableQuantity"] as? String, "8")
        XCTAssertEqual(positions[0]["accountPricePerShare"] as? String, "150")

        let decoded = try TradingSnapshotCodec.decode(
            data,
            expectedEnvironment: .demo,
            expectedAccountID: "account-1"
        )
        XCTAssertEqual(decoded.document, snapshot)
        XCTAssertEqual(decoded.source, .canonical)
        XCTAssertTrue(decoded.accountIdentityVerified)
    }

    func testCanonicalDecoderAcceptsTimestampWithoutFractionalSeconds() throws {
        var text = String(decoding: try TradingSnapshotCodec.encode(fixture()), as: UTF8.self)
        text = text.replacingOccurrences(of: ".000Z", with: "Z")
        let decoded = try TradingSnapshotCodec.decode(Data(text.utf8))
        XCTAssertEqual(decoded.document.account.id, "account-1")
    }

    func testCanonicalDecoderRejectsUnknownSchemaBeforeOtherFields() throws {
        let data = Data("""
        {"schema":"example.invalid","version":1}
        """.utf8)
        XCTAssertThrowsError(try TradingSnapshotCodec.decode(data)) { error in
            XCTAssertEqual(error as? TradingSnapshotError, .unknownSchema("example.invalid"))
        }
    }

    func testCanonicalDecoderRejectsUnknownVersion() throws {
        let data = Data("""
        {"schema":"com.marinsokol.trading212andoncord.portfolio-snapshot","version":99}
        """.utf8)
        XCTAssertThrowsError(try TradingSnapshotCodec.decode(data)) { error in
            XCTAssertEqual(error as? TradingSnapshotError, .unsupportedVersion(99))
        }
    }

    func testCanonicalDecoderRejectsNumericInsteadOfStringDecimal() throws {
        let encoded = try TradingSnapshotCodec.encode(fixture())
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        var totals = try XCTUnwrap(object["totals"] as? [String: Any])
        totals["accountValue"] = 4200
        object["totals"] = totals
        let altered = try JSONSerialization.data(withJSONObject: object)
        XCTAssertThrowsError(try TradingSnapshotCodec.decode(altered))
    }

    func testCanonicalDecoderRejectsEnvironmentAccountAndDuplicateTicker() throws {
        let data = try TradingSnapshotCodec.encode(fixture())
        XCTAssertThrowsError(try TradingSnapshotCodec.decode(
            data,
            expectedEnvironment: .live
        )) { error in
            XCTAssertEqual(
                error as? TradingSnapshotError,
                .environmentMismatch(expected: .live, actual: .demo)
            )
        }
        XCTAssertThrowsError(try TradingSnapshotCodec.decode(
            data,
            expectedAccountID: "other"
        )) { error in
            XCTAssertEqual(
                error as? TradingSnapshotError,
                .accountMismatch(expected: "other", actual: "account-1")
            )
        }

        let original = fixture()
        let duplicate = TradingSnapshotDocument(
            kind: original.kind,
            capturedAt: original.capturedAt,
            environment: original.environment,
            account: original.account,
            totals: original.totals,
            positions: [original.positions[0], original.positions[0]]
        )
        XCTAssertThrowsError(try TradingSnapshotCodec.decode(
            TradingSnapshotCodec.encode(duplicate)
        )) { error in
            XCTAssertEqual(error as? TradingSnapshotError, .duplicateTicker("AAPL_US_EQ"))
        }
    }

    func testAllocationsRejectNonPositiveCanonicalPriceAndWeight() throws {
        let original = fixture()
        let badPrice = copy(original.positions[0], price: 0, weight: d("0.375"))
        XCTAssertThrowsError(try TradingSnapshotCodec.encode(
            replacePositions(original, [badPrice])
        )) { error in
            XCTAssertEqual(error as? TradingSnapshotError, .nonPositivePrice("AAPL_US_EQ"))
        }

        let badWeight = copy(original.positions[0], price: 150, weight: 0)
        XCTAssertThrowsError(try TradingSnapshotCodec.encode(
            replacePositions(original, [badWeight])
        )) { error in
            XCTAssertEqual(error as? TradingSnapshotError, .nonPositiveWeight("AAPL_US_EQ"))
        }
    }

    func testLegacyDecoderMergesRepeatedPieTickerAndUsesValuesForAllFallbackWeights() throws {
        let data = Data("""
        {
          "version": 1,
          "saved_at": "2026-06-22T14:30:00Z",
          "environment": "demo",
          "account_currency": "GBP",
          "total_value": 3200,
          "holdings": [
            {"ticker":"AAPL_US_EQ","name":"Apple","currency":"USD","quantity":8,"price":150,"value":1200,"weight":0.9},
            {"ticker":"MSFT_US_EQ","name":"Microsoft","currency":"USD","quantity":5,"price":400,"value":2000}
          ],
          "pies_skipped": [
            {"ticker":"AAPL_US_EQ","quantityInPies":2},
            {"ticker":"VUSA_EQ","quantityInPies":3}
          ]
        }
        """.utf8)

        let decoded = try TradingSnapshotCodec.decode(
            data,
            expectedEnvironment: .demo,
            expectedAccountID: "cannot-be-verified-in-legacy"
        )
        XCTAssertEqual(decoded.source, .legacyAndonV1)
        XCTAssertFalse(decoded.accountIdentityVerified)
        XCTAssertEqual(decoded.document.positions.count, 3)

        let aapl = try XCTUnwrap(decoded.document.positions.first { $0.ticker == "AAPL_US_EQ" })
        XCTAssertEqual(aapl.quantity, 10)
        XCTAssertEqual(aapl.sellableQuantity, 8)
        XCTAssertEqual(aapl.pieQuantity, 2)
        XCTAssertNil(aapl.nativePrice, "legacy price is account currency, never native currency")
        XCTAssertEqual(aapl.sellableWeight, d("0.375"), "one missing weight forces value basis for all")

        let msft = try XCTUnwrap(decoded.document.positions.first { $0.ticker == "MSFT_US_EQ" })
        XCTAssertEqual(msft.sellableWeight, d("0.625"))
        XCTAssertEqual(try decoded.allocationsForBuy().count, 2)
    }

    func testCorePortfolioBridgeSortsPositionsDeterministically() throws {
        let portfolio = CurrentPortfolio(
            environment: .demo,
            account: .init(id: "1", currency: "GBP"),
            accountValue: 30,
            freeCash: 0,
            sellablePositionsValue: 30,
            positions: [
                corePosition(ticker: "ZZZ", value: 20, weight: d("0.666666")),
                corePosition(ticker: "AAA", value: 10, weight: d("0.333334")),
            ],
            capturedAt: Date(timeIntervalSince1970: 0)
        )
        let document = TradingSnapshotDocument(portfolio: portfolio)
        XCTAssertEqual(document.positions.map(\.ticker), ["AAA", "ZZZ"])
    }

    func testDeletingHoldingKeepsOriginalTotalsAndRenormalizesRemainingPosition() throws {
        let original = fixture()
        let edited = replacePositions(original, [original.positions[1]])
        let decoded = try TradingSnapshotCodec.decode(
            TradingSnapshotCodec.encode(edited)
        )
        let plan = try BuyPlanner.plan(
            allocations: decoded.allocationsForBuy(),
            freeCash: 100
        )
        XCTAssertEqual(plan.orders.count, 1)
        XCTAssertEqual(plan.orders[0].ticker, "MSFT_US_EQ")
        XCTAssertEqual(plan.orders[0].normalizedWeight, 1)
    }

    func testCanonicalRelationshipsFailClosed() throws {
        let original = fixture()
        let invalid = TradingSnapshotDocument.Position(
            ticker: "AAPL_US_EQ",
            name: "Apple",
            instrumentCurrency: "USD",
            quantity: 10,
            sellableQuantity: 9,
            pieQuantity: 2,
            nativePrice: 180,
            accountPricePerShare: 150,
            sellableAccountValue: 1_350,
            sellableWeight: d("0.421875")
        )
        XCTAssertThrowsError(try TradingSnapshotCodec.encode(
            replacePositions(original, [invalid])
        )) { error in
            XCTAssertEqual(
                error as? TradingSnapshotError,
                .invalidQuantityRelationship("AAPL_US_EQ")
            )
        }
    }

    func testSnapshotStoreBacksUpExistingAndKeepsOwnerOnlyPermissions() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "portfolio.json")
        let store = TradingSnapshotStore()

        XCTAssertNil(try store.write(fixture(), to: url, backupExisting: true))
        let backup = try XCTUnwrap(store.write(fixture(), to: url, backupExisting: true))
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path))
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    private func fixture() -> TradingSnapshotDocument {
        TradingSnapshotDocument(
            kind: .preSale,
            capturedAt: Date(timeIntervalSince1970: 1_783_945_200),
            environment: .demo,
            account: .init(id: "account-1", currency: "GBP"),
            totals: .init(accountValue: 4_200, freeCash: 1_000, sellablePositionsValue: 3_200),
            positions: [
                .init(
                    ticker: "AAPL_US_EQ",
                    isin: "US0378331005",
                    name: "Apple",
                    instrumentCurrency: "USD",
                    quantity: 10,
                    sellableQuantity: 8,
                    pieQuantity: 2,
                    nativePrice: 180,
                    accountPricePerShare: 150,
                    sellableAccountValue: 1_200,
                    sellableWeight: d("0.375")
                ),
                .init(
                    ticker: "MSFT_US_EQ",
                    name: "Microsoft",
                    instrumentCurrency: "USD",
                    quantity: 5,
                    sellableQuantity: 5,
                    pieQuantity: 0,
                    nativePrice: 400,
                    accountPricePerShare: 400,
                    sellableAccountValue: 2_000,
                    sellableWeight: d("0.625")
                ),
            ]
        )
    }

    private func copy(
        _ value: TradingSnapshotDocument.Position,
        price: Decimal,
        weight: Decimal
    ) -> TradingSnapshotDocument.Position {
        .init(
            ticker: value.ticker,
            isin: value.isin,
            name: value.name,
            instrumentCurrency: value.instrumentCurrency,
            quantity: value.quantity,
            sellableQuantity: value.sellableQuantity,
            pieQuantity: value.pieQuantity,
            nativePrice: value.nativePrice,
            accountPricePerShare: price,
            sellableAccountValue: value.sellableAccountValue,
            sellableWeight: weight
        )
    }

    private func replacePositions(
        _ value: TradingSnapshotDocument,
        _ positions: [TradingSnapshotDocument.Position]
    ) -> TradingSnapshotDocument {
        .init(
            kind: value.kind,
            capturedAt: value.capturedAt,
            environment: value.environment,
            account: value.account,
            totals: value.totals,
            positions: positions
        )
    }

    private func corePosition(ticker: String, value: Decimal, weight: Decimal) -> PortfolioPosition {
        .init(
            ticker: ticker,
            name: ticker,
            instrumentCurrency: "GBP",
            quantity: 1,
            sellableQuantity: 1,
            pieQuantity: 0,
            nativePrice: value,
            accountPricePerShare: value,
            sellableAccountValue: value,
            sellableWeight: weight
        )
    }
}

private func d(_ value: String) -> Decimal {
    Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))!
}
