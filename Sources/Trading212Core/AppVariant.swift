import Foundation

/// The installed build's identity and safety boundary.
///
/// Development builds deliberately cannot contact the live Trading 212 API.
/// They also use a different workspace and Keychain service, so installing a
/// development build never exposes production state or credentials to it.
public enum AppVariant: String, Codable, CaseIterable, Sendable {
    case development
    case production

    // Production is deliberately opt-in. Plain `swift build`, IDE builds, and
    // any packaging invocation that forgets its define remain Demo-only.
    #if ANDON_PROD
    public static let current: AppVariant = .production
    #else
    public static let current: AppVariant = .development
    #endif

    public static let teamIdentifier = "H33MHC4C79"

    public var appName: String {
        return switch self {
        case .development: "Trading212 Andon Cord (Dev)"
        case .production: "Trading212 Andon Cord"
        }
    }

    public var bundleIdentifier: String {
        switch self {
        case .development: "com.marinsokol.trading212andoncord.dev"
        case .production: "com.marinsokol.trading212andoncord"
        }
    }

    public var workspaceDirectoryName: String {
        switch self {
        case .development: "Trading212AndonCord-dev"
        case .production: "Trading212AndonCord"
        }
    }

    /// The read-only credential service. Trading credentials intentionally use
    /// a service owned by `Trading212Trading`, which is not linked into the app.
    public var readKeychainService: String { "\(bundleIdentifier).credentials.read" }

    /// Must stay in lockstep with `Support/Identity.*.mk` and the app/CLI
    /// entitlements. The trading group intentionally lives outside Core.
    public var readKeychainAccessGroup: String {
        if self == Self.current,
           let configured = AppRuntimeConfiguration.string(
               forInfoDictionaryKey: "AndonReadKeychainAccessGroup"
           ) {
            return configured
        }
        return switch self {
        case .development:
            "\(Self.teamIdentifier).com.marinsokol.trading212andoncord.dev.read"
        case .production:
            "\(Self.teamIdentifier).com.marinsokol.trading212andoncord.read"
        }
    }

    /// Only the shipped build claims restricted, profile-authorized Keychain
    /// groups. Development uses the local login Keychain so open-source builds
    /// need neither the maintainer's Apple team nor provisioning profiles.
    public var usesProvisionedKeychain: Bool { self == .production }

    /// The build's one fixed Trading 212 environment. There is no runtime
    /// selection: development builds always target Demo, production builds
    /// always target Live. Multi-account support may relax this later.
    public var environment: Trading212Environment {
        switch self {
        case .development: .demo
        case .production: .live
        }
    }

    /// Enforces the hard development-build live-network prohibition.
    public func validate(environment: Trading212Environment) throws {
        #if ANDON_PROD
        let livePermitted = self == .production
        #else
        // This is compile-unit-wide, not merely the default enum value: code
        // in an unmarked build cannot opt itself into Live by passing
        // `.production` to a client initializer.
        let livePermitted = false
        #endif
        if environment == .live, !livePermitted {
            throw AppVariantError.liveEnvironmentDisabledInDevelopment
        }
    }
}

/// Non-secret build identity values embedded in the assembled app's plist.
/// Reading the enclosing plist also lets the bundled CLI use the exact same
/// access-group values as its generated entitlements.
public enum AppRuntimeConfiguration {
    public static func string(forInfoDictionaryKey key: String) -> String? {
        if let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
           !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return value
        }

        guard let executable = Bundle.main.executableURL?.resolvingSymlinksInPath() else {
            return nil
        }
        let contents = executable.deletingLastPathComponent().deletingLastPathComponent()
        let plistURL = contents.appending(path: "Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let object = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dictionary = object as? [String: Any],
              let value = dictionary[key] as? String,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return value
    }
}

public enum AppVariantError: Error, Equatable, Sendable, LocalizedError {
    case liveEnvironmentDisabledInDevelopment

    public var errorDescription: String? {
        switch self {
        case .liveEnvironmentDisabledInDevelopment:
            "Development builds are restricted to the Trading 212 Demo environment."
        }
    }
}
