import Foundation

public enum RefreshInterval: String, Codable, CaseIterable, Identifiable, Sendable {
    case manual
    case oneMinute
    case fiveMinutes
    case fifteenMinutes

    public var id: String { rawValue }
    public var seconds: TimeInterval? {
        switch self {
        case .manual: nil
        case .oneMinute: 60
        case .fiveMinutes: 300
        case .fifteenMinutes: 900
        }
    }
    public var displayName: String {
        switch self {
        case .manual: "Manual"
        case .oneMinute: "Every minute"
        case .fiveMinutes: "Every 5 minutes"
        case .fifteenMinutes: "Every 15 minutes"
        }
    }
}

public enum ValueDisplayStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case compact
    case compactDecimal
    case full
    case fullWithCents
    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .compact: "Compact (€50K)"
        case .compactDecimal: "Compact with decimal (€49.9K)"
        case .full: "Full (€50,000)"
        case .fullWithCents: "Full with cents (€50,000.50)"
        }
    }
}

public enum SeparatorStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case commaDot
    case dotComma
    case system
    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .commaDot: "1,234.50"
        case .dotComma: "1.234,50"
        case .system: "Follow macOS"
        }
    }
}

public enum MenuBarLayout: String, Codable, CaseIterable, Identifiable, Sendable {
    case stacked
    case inline
    public var id: String { rawValue }
    public var displayName: String { self == .stacked ? "Stacked" : "Side by side" }
}

public enum MenuBarSymbol: String, Codable, CaseIterable, Identifiable, Sendable {
    case icon
    case label
    public var id: String { rawValue }
    public var displayName: String { self == .icon ? "Icon" : "Label" }
}

public enum MenuBarTint: String, Codable, CaseIterable, Identifiable, Sendable {
    case adaptive
    case solid
    public var id: String { rawValue }
    public var displayName: String { self == .adaptive ? "Adaptive" : "Always bright" }
}

/// Foundation representation of the configurable global privacy shortcut.
public struct ShortcutSettings: Codable, Equatable, Sendable {
    public var key: String
    public var command: Bool
    public var option: Bool
    public var control: Bool
    public var shift: Bool

    public init(key: String = "p", command: Bool = true, option: Bool = true,
                control: Bool = false, shift: Bool = false) {
        self.key = key.lowercased()
        self.command = command
        self.option = option
        self.control = control
        self.shift = shift
    }

    public static let defaultPrivacy = ShortcutSettings()
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var refreshInterval: RefreshInterval
    public var displayStyle: ValueDisplayStyle
    public var separatorStyle: SeparatorStyle
    public var menuBarLayout: MenuBarLayout
    public var menuBarSymbol: MenuBarSymbol
    public var menuBarTint: MenuBarTint
    public var privacyEnabled: Bool
    public var privacyShortcut: ShortcutSettings
    public var launchAtLogin: Bool

    public init(refreshInterval: RefreshInterval = .fiveMinutes,
                displayStyle: ValueDisplayStyle = .compactDecimal,
                separatorStyle: SeparatorStyle = .commaDot,
                menuBarLayout: MenuBarLayout = .stacked,
                menuBarSymbol: MenuBarSymbol = .icon,
                menuBarTint: MenuBarTint = .adaptive,
                privacyEnabled: Bool = false,
                privacyShortcut: ShortcutSettings = .defaultPrivacy,
                launchAtLogin: Bool = false) {
        self.refreshInterval = refreshInterval
        self.displayStyle = displayStyle
        self.separatorStyle = separatorStyle
        self.menuBarLayout = menuBarLayout
        self.menuBarSymbol = menuBarSymbol
        self.menuBarTint = menuBarTint
        self.privacyEnabled = privacyEnabled
        self.privacyShortcut = privacyShortcut
        self.launchAtLogin = launchAtLogin
    }

    // Older settings files may still carry an `environment` key from the era
    // of runtime environment selection; unknown keys are ignored on decode.
    private enum CodingKeys: String, CodingKey {
        case refreshInterval, displayStyle, separatorStyle
        case menuBarLayout, menuBarSymbol, menuBarTint, privacyEnabled
        case privacyShortcut, launchAtLogin
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        refreshInterval = try values.decodeIfPresent(
            RefreshInterval.self, forKey: .refreshInterval) ?? .fiveMinutes
        displayStyle = try values.decodeIfPresent(
            ValueDisplayStyle.self, forKey: .displayStyle) ?? .compactDecimal
        separatorStyle = try values.decodeIfPresent(
            SeparatorStyle.self, forKey: .separatorStyle) ?? .commaDot
        menuBarLayout = try values.decodeIfPresent(
            MenuBarLayout.self, forKey: .menuBarLayout) ?? .stacked
        menuBarSymbol = try values.decodeIfPresent(
            MenuBarSymbol.self, forKey: .menuBarSymbol) ?? .icon
        menuBarTint = try values.decodeIfPresent(
            MenuBarTint.self, forKey: .menuBarTint) ?? .adaptive
        privacyEnabled = try values.decodeIfPresent(Bool.self, forKey: .privacyEnabled) ?? false
        privacyShortcut = try values.decodeIfPresent(
            ShortcutSettings.self, forKey: .privacyShortcut) ?? .defaultPrivacy
        launchAtLogin = try values.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
    }

    public static func defaults() -> AppSettings {
        AppSettings()
    }

    /// Compatibility with the original menu-bar terminology.
    public var incognito: Bool {
        get { privacyEnabled }
        set { privacyEnabled = newValue }
    }
}

public protocol SettingsStore: Sendable {
    func load() throws -> AppSettings
    func save(_ settings: AppSettings) throws
}

public struct JSONSettingsStore: SettingsStore, Sendable {
    public let url: URL
    private let fileSystem: any FileSystem

    public init(workspace: Workspace, fileSystem: any FileSystem = LocalFileSystem()) {
        self.url = workspace.settingsURL
        self.fileSystem = fileSystem
    }

    public func load() throws -> AppSettings {
        guard fileSystem.fileExists(at: url) else { return .defaults() }
        return try AtomicJSONFile.read(AppSettings.self, from: url, fileSystem: fileSystem)
    }

    public func save(_ settings: AppSettings) throws {
        try AtomicJSONFile.write(settings, to: url, fileSystem: fileSystem)
    }
}

public final class InMemorySettingsStore: SettingsStore, @unchecked Sendable {
    private let lock = NSLock()
    private var value: AppSettings

    public init(_ value: AppSettings = .defaults()) { self.value = value }
    public func load() throws -> AppSettings { lock.withLock { value } }
    public func save(_ settings: AppSettings) throws { lock.withLock { value = settings } }
}

public struct AccountMetadata: Codable, Equatable, Sendable {
    public var environment: Trading212Environment
    public var accountID: String?
    public var currency: String?
    public var readCredentialConfigured: Bool
    public var tradeCredentialConfigured: Bool
    public var validatedAt: Date?

    public init(environment: Trading212Environment, accountID: String? = nil,
                currency: String? = nil, readCredentialConfigured: Bool = false,
                tradeCredentialConfigured: Bool = false, validatedAt: Date? = nil) {
        self.environment = environment
        self.accountID = accountID
        self.currency = currency?.uppercased()
        self.readCredentialConfigured = readCredentialConfigured
        self.tradeCredentialConfigured = tradeCredentialConfigured
        self.validatedAt = validatedAt
    }
}

public protocol AccountMetadataStoring: TradeCredentialStatusProviding {
    func metadata(for environment: Trading212Environment) throws -> AccountMetadata?
    func save(_ metadata: AccountMetadata) throws
}

public final class JSONAccountMetadataStore: AccountMetadataStoring, @unchecked Sendable {
    private struct Document: Codable { var environments: [String: AccountMetadata] = [:] }
    private let lock = NSLock()
    private let url: URL
    private let fileSystem: any FileSystem

    public init(workspace: Workspace, fileSystem: any FileSystem = LocalFileSystem()) {
        self.url = workspace.accountMetadataURL
        self.fileSystem = fileSystem
    }

    public func metadata(for environment: Trading212Environment) throws -> AccountMetadata? {
        try lock.withLock { try loadDocument().environments[environment.rawValue] }
    }

    public func save(_ metadata: AccountMetadata) throws {
        try lock.withLock {
            var document = try loadDocument()
            document.environments[metadata.environment.rawValue] = metadata
            try AtomicJSONFile.write(document, to: url, fileSystem: fileSystem)
        }
    }

    public func isTradeCredentialConfigured(for environment: Trading212Environment) throws -> Bool {
        try metadata(for: environment)?.tradeCredentialConfigured == true
    }

    public func setTradeCredentialConfigured(_ configured: Bool,
                                             for environment: Trading212Environment) throws {
        var value = try metadata(for: environment) ?? AccountMetadata(environment: environment)
        value.tradeCredentialConfigured = configured
        try save(value)
    }

    private func loadDocument() throws -> Document {
        guard fileSystem.fileExists(at: url) else { return Document() }
        return try AtomicJSONFile.read(Document.self, from: url, fileSystem: fileSystem)
    }
}
