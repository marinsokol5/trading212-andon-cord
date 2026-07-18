import Foundation
import LocalAuthentication
import Security
import Trading212Core

public struct TradingCredentialStoreConfiguration: Equatable, Sendable {
    public let service: String
    public let accessGroup: String?
    public let useDataProtectionKeychain: Bool
    public let authenticationPrompt: String

    public init(
        variant: AppVariant = .current,
        useDataProtectionKeychain: Bool? = nil,
        authenticationPrompt: String = "Allow Trading212 Andon Cord to access the trading credential"
    ) {
        service = "\(variant.bundleIdentifier).credentials.trading"
        if variant.usesProvisionedKeychain {
            accessGroup = variant == .current
                ? AppRuntimeConfiguration.string(
                    forInfoDictionaryKey: "AndonTradeKeychainAccessGroup"
                ) ?? "\(AppVariant.teamIdentifier).\(variant.bundleIdentifier).trade"
                : "\(AppVariant.teamIdentifier).\(variant.bundleIdentifier).trade"
        } else {
            accessGroup = nil
        }
        self.useDataProtectionKeychain = useDataProtectionKeychain
            ?? variant.usesProvisionedKeychain
        self.authenticationPrompt = authenticationPrompt
    }

    public init(
        service: String,
        accessGroup: String? = nil,
        useDataProtectionKeychain: Bool = true,
        authenticationPrompt: String = "Allow Trading212 Andon Cord to access the trading credential"
    ) {
        self.service = service
        self.accessGroup = accessGroup
        self.useDataProtectionKeychain = useDataProtectionKeychain
        self.authenticationPrompt = authenticationPrompt
    }
}

public enum TradingCredentialStoreError: Error, Equatable, Sendable, CustomStringConvertible {
    case unsupportedCredentialKind
    case incompleteCredentials
    case accessControl(Int32)
    case encoding
    case decoding
    case authenticationCancelled
    case keychain(Int32)

    public var description: String {
        switch self {
        case .unsupportedCredentialKind:
            "this CLI-only store accepts trading credentials only"
        case .incompleteCredentials:
            "both a trading API key and secret are required"
        case .accessControl(let status):
            "could not create user-presence Keychain access control (status \(status))"
        case .encoding:
            "could not encode the trading credential"
        case .decoding:
            "the stored trading credential is unreadable"
        case .authenticationCancelled:
            "trading credential access was cancelled"
        case .keychain(let status):
            "Keychain operation failed (status \(status))"
        }
    }
}

/// CLI-only Keychain vault. Its service name and retrieval path live in the
/// Trading library, which the GUI target never links.
public struct CLITradingCredentialStore: CredentialStore, TradeCredentialStatusProviding, Sendable {
    public let configuration: TradingCredentialStoreConfiguration

    public init(configuration: TradingCredentialStoreConfiguration = .init()) {
        self.configuration = configuration
    }

    public func credentials(
        for kind: CredentialKind,
        environment: Trading212Environment
    ) throws -> Trading212Credentials? {
        try requireTrading(kind)
        var query = baseQuery(environment: environment)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let context = LAContext()
        context.localizedReason = configuration.authenticationPrompt
        query[kSecUseAuthenticationContext as String] = context

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw TradingCredentialStoreError.decoding
            }
            do {
                let credentials = try JSONDecoder().decode(Trading212Credentials.self, from: data)
                guard credentials.isComplete else {
                    throw TradingCredentialStoreError.incompleteCredentials
                }
                return credentials
            } catch let error as TradingCredentialStoreError {
                throw error
            } catch {
                throw TradingCredentialStoreError.decoding
            }
        case errSecItemNotFound:
            return nil
        case errSecUserCanceled, errSecAuthFailed:
            throw TradingCredentialStoreError.authenticationCancelled
        default:
            throw TradingCredentialStoreError.keychain(status)
        }
    }

    public func set(
        _ credentials: Trading212Credentials,
        for kind: CredentialKind,
        environment: Trading212Environment
    ) throws {
        try requireTrading(kind)
        guard credentials.isComplete else {
            throw TradingCredentialStoreError.incompleteCredentials
        }

        let data: Data
        do {
            data = try JSONEncoder().encode(credentials)
        } catch {
            throw TradingCredentialStoreError.encoding
        }

        var accessError: Unmanaged<CFError>?
        guard let accessControl = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .userPresence,
            &accessError
        ) else {
            _ = accessError?.takeRetainedValue()
            throw TradingCredentialStoreError.accessControl(errSecParam)
        }

        // Re-add rather than update so every saved credential is guaranteed to
        // carry the current user-presence policy.
        let deleteStatus = SecItemDelete(baseQuery(environment: environment) as CFDictionary)
        guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound else {
            throw TradingCredentialStoreError.keychain(deleteStatus)
        }

        var query = baseQuery(environment: environment)
        query[kSecValueData as String] = data
        query[kSecAttrAccessControl as String] = accessControl
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw TradingCredentialStoreError.keychain(status)
        }
    }

    public func delete(kind: CredentialKind, environment: Trading212Environment) throws {
        try requireTrading(kind)
        let status = SecItemDelete(baseQuery(environment: environment) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw TradingCredentialStoreError.keychain(status)
        }
    }

    /// Checks for a matching item without requesting its secret data, and thus
    /// without presenting Touch ID/password UI.
    public func isTradeCredentialConfigured(
        for environment: Trading212Environment
    ) throws -> Bool {
        var query = baseQuery(environment: environment)
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let context = LAContext()
        context.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = context

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess, errSecInteractionNotAllowed:
            return true
        case errSecItemNotFound:
            return false
        default:
            throw TradingCredentialStoreError.keychain(status)
        }
    }

    private func requireTrading(_ kind: CredentialKind) throws {
        guard kind == .trading else {
            throw TradingCredentialStoreError.unsupportedCredentialKind
        }
    }

    private func baseQuery(environment: Trading212Environment) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: configuration.service,
            kSecAttrAccount as String: "trading212.\(environment.rawValue)",
        ]
        if let accessGroup = configuration.accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        if configuration.useDataProtectionKeychain {
            query[kSecUseDataProtectionKeychain as String] = true
        }
        return query
    }
}
