import Foundation
import Security

public struct Trading212Credentials: Codable, Equatable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible {
    public let key: String
    public let secret: String

    public init(key: String, secret: String) {
        self.key = key
        self.secret = secret
    }

    public var isComplete: Bool {
        !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Intended only for constructing an HTTP request. Do not log this value.
    public var authorizationHeaderValue: String {
        "Basic " + Data("\(key):\(secret)".utf8).base64EncodedString()
    }

    public var description: String { "Trading212Credentials(<redacted>)" }
    public var debugDescription: String { description }
}

public enum CredentialKind: String, Codable, CaseIterable, Sendable {
    case read
    case trading

    /// Compatibility with the product copy's older term for a read credential.
    public static var viewing: CredentialKind { .read }
}

/// Credential storage abstraction shared by the app, CLI, and offline tests.
/// The Core Keychain implementation supports `.read` only. The CLI supplies a
/// separate `.trading` implementation with user-presence access control.
public protocol CredentialStore: Sendable {
    func credentials(for kind: CredentialKind,
                     environment: Trading212Environment) throws -> Trading212Credentials?
    func set(_ credentials: Trading212Credentials,
             for kind: CredentialKind,
             environment: Trading212Environment) throws
    func delete(kind: CredentialKind, environment: Trading212Environment) throws
}

public typealias CredentialStoring = CredentialStore

public extension CredentialStore {
    func load(kind: CredentialKind,
              environment: Trading212Environment) throws -> Trading212Credentials? {
        try credentials(for: kind, environment: environment)
    }

    func save(_ credentials: Trading212Credentials,
              kind: CredentialKind,
              environment: Trading212Environment) throws {
        try set(credentials, for: kind, environment: environment)
    }

    func contains(kind: CredentialKind, environment: Trading212Environment) -> Bool {
        guard let credentials = try? credentials(for: kind, environment: environment) else {
            return false
        }
        return credentials.isComplete
    }
}

public enum CredentialStoreError: Error, Equatable, Sendable, LocalizedError {
    case incompleteCredentials
    case unsupportedCredentialKind(CredentialKind)
    case encoding
    case decoding
    case keychainStatus(Int32)

    public var errorDescription: String? {
        switch self {
        case .incompleteCredentials: "Both an API key and API secret are required."
        case let .unsupportedCredentialKind(kind):
            "The \(kind.rawValue) credential is not available from this credential store."
        case .encoding: "The credentials could not be encoded."
        case .decoding: "The stored credentials could not be decoded."
        case let .keychainStatus(status): "Keychain operation failed (status \(status))."
        }
    }
}

/// Device-local Keychain storage for the read credential only.
///
/// A production build can pass its read-only Keychain access group. Passing
/// `nil` is useful for ad-hoc development signing, while the service remains
/// isolated by build variant. This type contains no trading service name or
/// trade-credential retrieval path.
public struct KeychainCredentialStore: CredentialStore, Sendable {
    public let service: String
    public let accessGroup: String?
    public let useDataProtectionKeychain: Bool

    /// Production uses its profile-authorized access group. Development uses
    /// the legacy local Keychain without a restricted entitlement so an ad-hoc
    /// open-source build can run without the maintainer's Apple team.
    public init(variant: AppVariant = .current) {
        self.service = variant.readKeychainService
        self.accessGroup = variant.usesProvisionedKeychain
            ? variant.readKeychainAccessGroup
            : nil
        self.useDataProtectionKeychain = variant.usesProvisionedKeychain
    }

    /// Explicit configuration for ad-hoc signing and tests. A nil access group
    /// and `false` data-protection flag select the legacy local Keychain.
    public init(variant: AppVariant,
                accessGroup: String?,
                useDataProtectionKeychain: Bool) {
        self.service = variant.readKeychainService
        self.accessGroup = accessGroup
        self.useDataProtectionKeychain = useDataProtectionKeychain
    }

    public init(service: String,
                accessGroup: String? = nil,
                useDataProtectionKeychain: Bool = false) {
        self.service = service
        self.accessGroup = accessGroup
        self.useDataProtectionKeychain = useDataProtectionKeychain
    }

    public func credentials(for kind: CredentialKind,
                            environment: Trading212Environment) throws -> Trading212Credentials? {
        try requireRead(kind)
        var query = baseQuery(environment: environment)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { throw CredentialStoreError.decoding }
            do {
                return try JSONDecoder().decode(Trading212Credentials.self, from: data)
            } catch {
                throw CredentialStoreError.decoding
            }
        case errSecItemNotFound:
            return nil
        default:
            throw CredentialStoreError.keychainStatus(status)
        }
    }

    public func set(_ credentials: Trading212Credentials,
                    for kind: CredentialKind,
                    environment: Trading212Environment) throws {
        try requireRead(kind)
        guard credentials.isComplete else { throw CredentialStoreError.incompleteCredentials }

        let data: Data
        do { data = try JSONEncoder().encode(credentials) }
        catch { throw CredentialStoreError.encoding }

        let query = baseQuery(environment: environment)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var add = query
            add.merge(attributes) { _, new in new }
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw CredentialStoreError.keychainStatus(addStatus)
            }
        default:
            throw CredentialStoreError.keychainStatus(updateStatus)
        }
    }

    public func delete(kind: CredentialKind, environment: Trading212Environment) throws {
        try requireRead(kind)
        let status = SecItemDelete(baseQuery(environment: environment) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialStoreError.keychainStatus(status)
        }
    }

    private func requireRead(_ kind: CredentialKind) throws {
        guard kind == .read else { throw CredentialStoreError.unsupportedCredentialKind(kind) }
    }

    private func baseQuery(environment: Trading212Environment) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "trading212.\(environment.rawValue)",
        ]
        if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
        if useDataProtectionKeychain {
            query[kSecUseDataProtectionKeychain as String] = true
        }
        return query
    }
}

/// Thread-safe test double. Unlike the Core Keychain store it supports both
/// kinds, which is useful to test CLI orchestration without touching Keychain.
public final class InMemoryCredentialStore: CredentialStore, @unchecked Sendable {
    private struct Key: Hashable { let kind: CredentialKind; let environment: Trading212Environment }
    private let lock = NSLock()
    private var values: [Key: Trading212Credentials] = [:]

    public init() {}

    public func credentials(for kind: CredentialKind,
                            environment: Trading212Environment) throws -> Trading212Credentials? {
        lock.withLock { values[Key(kind: kind, environment: environment)] }
    }

    public func set(_ credentials: Trading212Credentials,
                    for kind: CredentialKind,
                    environment: Trading212Environment) throws {
        guard credentials.isComplete else { throw CredentialStoreError.incompleteCredentials }
        lock.withLock { values[Key(kind: kind, environment: environment)] = credentials }
    }

    public func delete(kind: CredentialKind, environment: Trading212Environment) throws {
        _ = lock.withLock { values.removeValue(forKey: Key(kind: kind, environment: environment)) }
    }
}

/// Lets the GUI show that a trading credential exists without being able to
/// retrieve it. Implementations must persist only this boolean metadata.
public protocol TradeCredentialStatusProviding: Sendable {
    func isTradeCredentialConfigured(for environment: Trading212Environment) throws -> Bool
}
