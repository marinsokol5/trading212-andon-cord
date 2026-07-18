import Foundation
import XCTest
@testable import Trading212Core

final class WorkspaceAndSettingsTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(component: "Trading212CoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory { try? FileManager.default.removeItem(at: temporaryDirectory) }
        temporaryDirectory = nil
    }

    func testWorkspaceCreatesOwnerOnlyDirectories() throws {
        let workspace = Workspace(rootURL: temporaryDirectory.appending(component: "workspace"))
        try workspace.prepare()
        for url in [workspace.rootURL, workspace.cacheDirectoryURL,
                    workspace.snapshotsDirectoryURL, workspace.receiptsDirectoryURL] {
            var isDirectory: ObjCBool = false
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory))
            XCTAssertTrue(isDirectory.boolValue)
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)
        }
    }

    func testAtomicWriteUses0600AndBacksUpExistingDestination() throws {
        let fileSystem = LocalFileSystem()
        let destination = temporaryDirectory.appending(component: "portfolio.json")
        XCTAssertNil(try fileSystem.writeAtomically(Data("first".utf8), to: destination,
                                                     permissions: .ownerReadWrite,
                                                     backupExisting: true))
        let backup = try XCTUnwrap(fileSystem.writeAtomically(
            Data("second".utf8), to: destination,
            permissions: .ownerReadWrite, backupExisting: true))
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "second")
        XCTAssertEqual(try String(contentsOf: backup, encoding: .utf8), "first")
        let attributes = try FileManager.default.attributesOfItem(atPath: destination.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func testFileSnapshotCacheSeparatesEnvironments() throws {
        let cache = FileSnapshotCache(workspace: Workspace(rootURL: temporaryDirectory))
        let live = samplePortfolio(environment: .live, value: 100)
        let demo = samplePortfolio(environment: .demo, value: 200)
        try cache.save(live)
        try cache.save(demo)
        XCTAssertEqual(cache.portfolio(for: .live), live)
        XCTAssertEqual(cache.portfolio(for: .demo), demo)
        try cache.remove(for: .live)
        XCTAssertNil(cache.portfolio(for: .live))
        XCTAssertEqual(cache.portfolio(for: .demo), demo)
    }

    func testSettingsRoundTripAndLegacyEnvironmentKeyIsIgnored() throws {
        let workspace = Workspace(rootURL: temporaryDirectory)
        let store = JSONSettingsStore(workspace: workspace)
        var settings = AppSettings.defaults()
        settings.privacyEnabled = true
        settings.refreshInterval = .oneMinute
        try store.save(settings)
        XCTAssertEqual(try store.load(), settings)

        // Settings no longer carry an environment. A file written when they
        // did must still load, with the stale key simply ignored.
        let saved = try Data(contentsOf: workspace.settingsURL)
        var object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: saved) as? [String: Any])
        XCTAssertNil(object["environment"])
        object["environment"] = "live"
        try JSONSerialization.data(withJSONObject: object)
            .write(to: workspace.settingsURL)
        XCTAssertEqual(try store.load(), settings)
    }

    func testAccountMetadataContainsNoCredentialsAndMarkerRoundTrips() throws {
        let workspace = Workspace(rootURL: temporaryDirectory)
        let store = JSONAccountMetadataStore(workspace: workspace)
        try store.save(AccountMetadata(
            environment: .demo, accountID: "account-1", currency: "eur",
            readCredentialConfigured: true, tradeCredentialConfigured: false,
            validatedAt: Date(timeIntervalSince1970: 123)))
        XCTAssertFalse(try store.isTradeCredentialConfigured(for: .demo))
        try store.setTradeCredentialConfigured(true, for: .demo)
        XCTAssertTrue(try store.isTradeCredentialConfigured(for: .demo))
        XCTAssertEqual(try store.metadata(for: .demo)?.currency, "EUR")

        let bytes = try Data(contentsOf: workspace.accountMetadataURL)
        let text = String(decoding: bytes, as: UTF8.self)
        XCTAssertFalse(text.localizedCaseInsensitiveContains("secret"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("authorization"))
    }

    func testAtomicJSONDeterministicallySortsKeys() throws {
        struct Record: Codable, Equatable { let z: Int; let a: Int }
        let url = temporaryDirectory.appending(component: "record.json")
        try AtomicJSONFile.write(Record(z: 1, a: 2), to: url)
        let text = try String(contentsOf: url, encoding: .utf8)
        let a = try XCTUnwrap(text.range(of: "\"a\""))
        let z = try XCTUnwrap(text.range(of: "\"z\""))
        XCTAssertLessThan(a.lowerBound, z.lowerBound)
        XCTAssertEqual(try AtomicJSONFile.read(Record.self, from: url), Record(z: 1, a: 2))
    }

    private func samplePortfolio(environment: Trading212Environment,
                                 value: Decimal) -> CurrentPortfolio {
        CurrentPortfolio(
            environment: environment,
            account: AccountIdentity(id: "account", currency: "EUR"),
            accountValue: value, freeCash: 10, sellablePositionsValue: 0,
            positions: [], capturedAt: Date(timeIntervalSince1970: 123))
    }
}
