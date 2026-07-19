import Foundation
import XCTest
import Trading212Core
@testable import Trading212Trading

final class AndonArgumentParserTests: XCTestCase {
    func testAccountAndPortfolioCommands() throws {
        XCTAssertEqual(
            try AndonArgumentParser.parse(["account", "--json"]),
            AndonInvocation(command: .account(json: true))
        )

        let portfolio = try AndonArgumentParser.parse([
            "portfolio", "--output=portfolio.json",
        ])
        guard case .portfolio(let json, let output) = portfolio.command else {
            return XCTFail("expected portfolio")
        }
        XCTAssertFalse(json)
        XCTAssertEqual(output?.lastPathComponent, "portfolio.json")
    }

    func testSnapshotViewAndCredentialCommands() throws {
        let view = try AndonArgumentParser.parse([
            "snapshot", "view", "--input", "x.json", "--json",
        ])
        guard case .snapshotView(let input, let json) = view.command else {
            return XCTFail("expected snapshot view")
        }
        XCTAssertEqual(input.lastPathComponent, "x.json")
        XCTAssertTrue(json)

        XCTAssertEqual(
            try AndonArgumentParser.parse([
                "credentials", "set-trading",
            ]).command,
            .credentialsSetTrading
        )
        XCTAssertEqual(
            try AndonArgumentParser.parse([
                "credentials", "status", "--json",
            ]).command,
            .credentialsStatus(json: true)
        )
        XCTAssertEqual(
            try AndonArgumentParser.parse([
                "credentials", "delete",
            ]).command,
            .credentialsDeleteTrading
        )
    }

    func testSellAndBuyOptionsParseAsDecimalWithoutDouble() throws {
        let sell = try AndonArgumentParser.parse([
            "sell-all", "--dry-run", "--output", "out.json",
        ])
        guard case .sellAll(let output, let dryRun) = sell.command else {
            return XCTFail("expected sell-all")
        }
        XCTAssertEqual(output?.lastPathComponent, "out.json")
        XCTAssertTrue(dryRun)

        let buy = try AndonArgumentParser.parse([
            "buy-all", "--input=in.json", "--cash-fraction=0.975",
            "--min-order", "2.5", "--precision", "4",
        ])
        guard case .buyAll(let input, let options, let dryRun) = buy.command else {
            return XCTFail("expected buy-all")
        }
        XCTAssertEqual(input.lastPathComponent, "in.json")
        XCTAssertEqual(options.cashFraction, decimal("0.975"))
        XCTAssertEqual(options.minimumOrderValue, decimal("2.5"))
        XCTAssertEqual(options.quantityPrecision, 4)
        XCTAssertFalse(dryRun)
    }

    func testFlagsMayAppearBeforeCommand() throws {
        let invocation = try AndonArgumentParser.parse([
            "--dry-run", "buy-all", "--input", "in.json",
        ])
        guard case .buyAll(_, _, let dryRun) = invocation.command else {
            return XCTFail("expected buy-all")
        }
        XCTAssertTrue(dryRun)
    }

    func testRejectsUnknownMissingAndRemovedFlags() {
        XCTAssertThrowsError(try AndonArgumentParser.parse(["portfolio", "--bogus"]))
        XCTAssertThrowsError(try AndonArgumentParser.parse(["portfolio", "--output"]))
        // Environment selection and the demo bypass are gone entirely.
        XCTAssertThrowsError(try AndonArgumentParser.parse(["portfolio", "--live"]))
        XCTAssertThrowsError(try AndonArgumentParser.parse(["portfolio", "--demo"]))
        XCTAssertThrowsError(try AndonArgumentParser.parse(["sell-all", "--yes"]))
        XCTAssertThrowsError(try AndonArgumentParser.parse(["sell-all", "-y"]))
        XCTAssertThrowsError(try AndonArgumentParser.parse([
            "portfolio", "--json", "--output", "x",
        ]))
        XCTAssertThrowsError(try AndonArgumentParser.parse([
            "snapshot", "view",
        ]))
        XCTAssertThrowsError(try AndonArgumentParser.parse([
            "buy-all", "--input", "x", "--cash-fraction", "not-a-number",
        ]))
        // Legacy verb aliases and dead flags are gone.
        XCTAssertThrowsError(try AndonArgumentParser.parse(["whoami"]))
        XCTAssertThrowsError(try AndonArgumentParser.parse(["status"]))
        XCTAssertThrowsError(try AndonArgumentParser.parse(["save"]))
        XCTAssertThrowsError(try AndonArgumentParser.parse(["view"]))
        XCTAssertThrowsError(try AndonArgumentParser.parse(["credentials", "delete-trading"]))
        XCTAssertThrowsError(try AndonArgumentParser.parse([
            "credentials", "set-trading", "--stdin-json",
        ]))
        XCTAssertThrowsError(try AndonArgumentParser.parse([
            "credentials", "delete", "--trading",
        ]))
        XCTAssertThrowsError(try AndonArgumentParser.parse([
            "portfolio", "--out", "x.json",
        ]))
        XCTAssertThrowsError(try AndonArgumentParser.parse([
            "snapshot", "view", "--in", "x.json",
        ]))
    }

    func testRejectsInvalidBuyOptionRangesDuringParsing() {
        XCTAssertThrowsError(try AndonArgumentParser.parse([
            "buy-all", "--input", "x", "--cash-fraction", "1.1",
        ]))
        XCTAssertThrowsError(try AndonArgumentParser.parse([
            "buy-all", "--input", "x", "--min-order", "-1",
        ]))
        XCTAssertThrowsError(try AndonArgumentParser.parse([
            "buy-all", "--input", "x", "--precision", "13",
        ]))
    }

    func testNoCommandShowsHelpAndVersionIsStandalone() throws {
        XCTAssertEqual(try AndonArgumentParser.parse([]).command, .help)
        XCTAssertEqual(try AndonArgumentParser.parse(["--help"]).command, .help)
        XCTAssertEqual(try AndonArgumentParser.parse(["--version"]).command, .version)
        XCTAssertThrowsError(try AndonArgumentParser.parse(["portfolio", "--version"]))
    }
}

private func decimal(_ string: String) -> Decimal {
    Decimal(string: string, locale: Locale(identifier: "en_US_POSIX"))!
}
