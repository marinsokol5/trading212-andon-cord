import Foundation
import XCTest
import Trading212Core
@testable import Trading212Trading

@MainActor
final class TradeJournalTests: XCTestCase {
    func testFileJournalAtomicallyReplacesReceiptAndAppendsJSONLWithOwnerPermissions() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let receiptURL = directory.appending(path: "receipts/run.json")
        let auditURL = directory.appending(path: "audit.jsonl")
        let journal = FileTradeJournal(receiptURL: receiptURL, auditURL: auditURL)
        let date = Date(timeIntervalSince1970: 100)
        var receipt = TradeReceipt(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            action: .sellAll,
            environment: .demo,
            accountID: "account",
            snapshotPath: "/snapshot.json",
            startedAt: date,
            requests: [.init(ticker: "A", quantity: -1)]
        )
        let started = TradeAuditEvent(
            timestamp: date,
            receiptID: receipt.id,
            action: receipt.action,
            environment: receipt.environment,
            kind: .runStarted
        )
        try await journal.record(receipt: receipt, event: started)

        receipt.orders[0].state = .submitting(at: date)
        receipt.updatedAt = date
        let submitting = TradeAuditEvent(
            timestamp: date,
            receiptID: receipt.id,
            action: receipt.action,
            environment: receipt.environment,
            kind: .orderSubmitting,
            ticker: "A",
            orderIndex: 0
        )
        try await journal.record(receipt: receipt, event: submitting)

        let receiptData = try Data(contentsOf: receiptURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let stored = try decoder.decode(TradeReceipt.self, from: receiptData)
        guard case .submitting = stored.orders[0].state else {
            return XCTFail("receipt should contain latest incremental state")
        }

        let lines = try String(contentsOf: auditURL, encoding: .utf8)
            .split(separator: "\n")
        XCTAssertEqual(lines.count, 2)
        for line in lines {
            XCTAssertNoThrow(try JSONSerialization.jsonObject(with: Data(line.utf8)))
        }

        let receiptMode = try FileManager.default.attributesOfItem(atPath: receiptURL.path)
        let auditMode = try FileManager.default.attributesOfItem(atPath: auditURL.path)
        XCTAssertEqual((receiptMode[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        XCTAssertEqual((auditMode[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func testReceiptContainsNoCredentialFields() throws {
        let receipt = TradeReceipt(
            action: .buyAll,
            environment: .live,
            accountID: "account",
            snapshotPath: "/snapshot.json",
            startedAt: Date(),
            requests: [.init(ticker: "A", quantity: 1)]
        )
        let text = String(decoding: try JSONEncoder().encode(receipt), as: UTF8.self)
        XCTAssertFalse(text.lowercased().contains("authorization"))
        XCTAssertFalse(text.lowercased().contains("secret"))
        XCTAssertFalse(text.lowercased().contains("apikey"))
    }

    func testTradingCredentialConfigurationUsesDistinctVariantGroups() {
        let production = TradingCredentialStoreConfiguration(variant: .production)
        let development = TradingCredentialStoreConfiguration(variant: .development)
        XCTAssertEqual(production.service,
                       "com.marinsokol.trading212andoncord.credentials.trading")
        XCTAssertEqual(production.accessGroup,
                       "H33MHC4C79.com.marinsokol.trading212andoncord.trade")
        XCTAssertTrue(production.useDataProtectionKeychain)
        XCTAssertEqual(development.service,
                       "com.marinsokol.trading212andoncord.dev.credentials.trading")
        XCTAssertNil(development.accessGroup)
        XCTAssertFalse(development.useDataProtectionKeychain)
        XCTAssertNotEqual(production.service, AppVariant.production.readKeychainService)
        XCTAssertNotEqual(production.accessGroup, AppVariant.production.readKeychainAccessGroup)
    }
}
