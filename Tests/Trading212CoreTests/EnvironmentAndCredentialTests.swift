import Foundation
import XCTest
@testable import Trading212Core

final class EnvironmentAndCredentialTests: XCTestCase {
    func testBuildVariantDefaultsFailClosed() {
        #if ANDON_PROD
        XCTAssertEqual(AppVariant.current, .production)
        #else
        XCTAssertEqual(AppVariant.current, .development)
        #endif
    }

    func testEnvironmentURLs() {
        XCTAssertEqual(Trading212Environment.live.baseURL.absoluteString, "https://live.trading212.com")
        XCTAssertEqual(Trading212Environment.demo.baseURL.absoluteString, "https://demo.trading212.com")
    }

    func testDevelopmentVariantIsDemoOnlyAndIsolated() throws {
        XCTAssertEqual(AppVariant.development.environment, .demo)
        XCTAssertEqual(AppVariant.production.environment, .live)
        XCTAssertNoThrow(try AppVariant.development.validate(environment: .demo))
        XCTAssertThrowsError(try AppVariant.development.validate(environment: .live)) {
            XCTAssertEqual($0 as? AppVariantError, .liveEnvironmentDisabledInDevelopment)
        }
        XCTAssertNotEqual(AppVariant.development.bundleIdentifier, AppVariant.production.bundleIdentifier)
        XCTAssertNotEqual(AppVariant.development.workspaceDirectoryName,
                          AppVariant.production.workspaceDirectoryName)
        XCTAssertNotEqual(AppVariant.development.readKeychainService,
                          AppVariant.production.readKeychainService)
        XCTAssertEqual(AppVariant.production.readKeychainAccessGroup,
                       "H33MHC4C79.com.marinsokol.trading212andoncord.read")
        XCTAssertFalse(AppVariant.development.usesProvisionedKeychain)
        XCTAssertTrue(AppVariant.production.usesProvisionedKeychain)

        let developmentStore = KeychainCredentialStore(variant: .development)
        XCTAssertNil(developmentStore.accessGroup)
        XCTAssertFalse(developmentStore.useDataProtectionKeychain)
        let productionStore = KeychainCredentialStore(variant: .production)
        XCTAssertEqual(productionStore.accessGroup,
                       AppVariant.production.readKeychainAccessGroup)
        XCTAssertTrue(productionStore.useDataProtectionKeychain)
    }

    func testBasicAuthorizationAndRedactedDescriptions() {
        let credentials = Trading212Credentials(key: "abc", secret: "xyz")
        XCTAssertEqual(credentials.authorizationHeaderValue, "Basic YWJjOnh5eg==")
        XCTAssertFalse(credentials.description.contains("abc"))
        XCTAssertFalse(credentials.debugDescription.contains("xyz"))
    }

    func testInMemoryCredentialKindsAndEnvironmentsAreIndependent() throws {
        let store = InMemoryCredentialStore()
        let read = Trading212Credentials(key: "read-key", secret: "read-secret")
        let trade = Trading212Credentials(key: "trade-key", secret: "trade-secret")

        try store.save(read, kind: .read, environment: .live)
        try store.save(trade, kind: .trading, environment: .live)
        XCTAssertEqual(try store.load(kind: .read, environment: .live), read)
        XCTAssertEqual(try store.load(kind: .trading, environment: .live), trade)
        XCTAssertNil(try store.load(kind: .read, environment: .demo))

        try store.delete(kind: .trading, environment: .live)
        XCTAssertFalse(store.contains(kind: .trading, environment: .live))
        XCTAssertTrue(store.contains(kind: .read, environment: .live))
    }

    func testCoreKeychainStoreRejectsTradingKindBeforeKeychainAccess() {
        let store = KeychainCredentialStore(
            variant: .development, accessGroup: nil,
            useDataProtectionKeychain: false)
        XCTAssertThrowsError(try store.credentials(for: .trading, environment: .demo)) {
            XCTAssertEqual($0 as? CredentialStoreError, .unsupportedCredentialKind(.trading))
        }
    }

    func testRedactorRemovesAllCredentialRepresentationsAndHeaderLines() {
        let credentials = Trading212Credentials(key: "my-key", secret: "my-secret")
        let token = Data("my-key:my-secret".utf8).base64EncodedString()
        let input = """
        key=my-key secret=my-secret raw=\(token)
        authorization: bAsIc \(token)
        """
        let output = Redactor.redact(input, credentials: [credentials])
        XCTAssertFalse(output.contains("my-key"))
        XCTAssertFalse(output.contains("my-secret"))
        XCTAssertFalse(output.contains("YWJ"))
        XCTAssertTrue(output.contains(Redactor.marker))
    }
}
