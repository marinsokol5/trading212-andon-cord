import Foundation
import Observation
import Trading212Core

typealias RefreshCadence = Trading212Core.RefreshInterval
typealias MenuBarLayout = Trading212Core.MenuBarLayout
typealias MenuBarSymbol = Trading212Core.MenuBarSymbol
typealias MenuBarTint = Trading212Core.MenuBarTint
typealias ValueStyle = Trading212Core.ValueDisplayStyle
typealias NumberSeparators = Trading212Core.SeparatorStyle

extension Trading212Core.ValueDisplayStyle {
    var displayName: String {
        switch self {
        case .compact: "Compact (€50K)"
        case .compactDecimal: "Compact, one decimal (€49.9K)"
        case .full: "Full (€50,000)"
        case .fullWithCents: "Full with cents (€50,000.50)"
        }
    }
}

extension Trading212Core.SeparatorStyle {
    var displayName: String {
        switch self {
        case .commaDot: "1,234.50"
        case .dotComma: "1.234,50"
        case .system: "Follow macOS"
        }
    }
}

extension Trading212Core.MenuBarLayout {
    var displayName: String { self == .stacked ? "Stacked" : "Side by side" }
}

extension Trading212Core.MenuBarSymbol {
    var displayName: String { self == .icon ? "Andon cord mark" : "T212 label" }
}

extension Trading212Core.MenuBarTint {
    var displayName: String { self == .adaptive ? "Adaptive" : "Always bright" }
}

struct ShortcutDefinition: Codable, Equatable, Sendable {
    var keyCode: UInt32
    var modifiers: UInt32

    /// Carbon virtual-key code for P with Command + Option.
    static let defaultPrivacy = ShortcutDefinition(keyCode: 35, modifiers: 0x0100 | 0x0800)

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    init(_ settings: ShortcutSettings) {
        self.keyCode = Self.keyCodes[settings.key.lowercased()] ?? Self.defaultPrivacy.keyCode
        var value: UInt32 = 0
        if settings.command { value |= 0x0100 }
        if settings.option { value |= 0x0800 }
        if settings.control { value |= 0x1000 }
        if settings.shift { value |= 0x0200 }
        self.modifiers = value
    }

    var coreSettings: ShortcutSettings {
        ShortcutSettings(
            key: Self.keyCodes.first(where: { $0.value == keyCode })?.key ?? "p",
            command: modifiers & 0x0100 != 0,
            option: modifiers & 0x0800 != 0,
            control: modifiers & 0x1000 != 0,
            shift: modifiers & 0x0200 != 0)
    }

    private static let keyCodes: [String: UInt32] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6,
        "x": 7, "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14,
        "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20,
        "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26,
        "-": 27, "8": 28, "0": 29, "]": 30, "o": 31, "u": 32,
        "[": 33, "i": 34, "p": 35, "l": 37, "j": 38, "'": 39,
        "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44, "n": 45,
        "m": 46, ".": 47, "space": 49, "`": 50,
    ]
}

/// GUI-only preferences. Secrets are never persisted here; the read pair is in
/// Core's read-only Keychain service and the trading pair is CLI-owned.
@MainActor
@Observable
final class GUISettings {
    private let settingsStore: any SettingsStore
    private let metadataStore: any AccountMetadataStoring

    /// Fixed by the build variant: development is Demo, production is Live.
    /// Not persisted and not user-selectable.
    let environment: Trading212Environment = AppVariant.current.environment
    var refreshCadence: RefreshCadence { didSet { persistSettings() } }
    var privacyMode: Bool { didSet { persistSettings() } }
    var menuBarLayout: MenuBarLayout { didSet { persistSettings() } }
    var menuBarSymbol: MenuBarSymbol { didSet { persistSettings() } }
    var menuBarTint: MenuBarTint { didSet { persistSettings() } }
    var valueStyle: ValueStyle { didSet { persistSettings() } }
    var separators: NumberSeparators { didSet { persistSettings() } }
    var privacyShortcut: ShortcutDefinition { didSet { persistSettings() } }
    var launchAtLogin: Bool { didSet { persistSettings() } }
    private(set) var tradeCredentialConfiguredByEnvironment: [String: Bool]

    init(
        settingsStore: (any SettingsStore)? = nil,
        metadataStore: (any AccountMetadataStoring)? = nil
    ) {
        let stores = Self.defaultStores()
        self.settingsStore = settingsStore ?? stores.settings
        self.metadataStore = metadataStore ?? stores.metadata

        let loaded = (try? self.settingsStore.load()) ?? .defaults()
        self.refreshCadence = loaded.refreshInterval
        self.privacyMode = loaded.privacyEnabled
        self.menuBarLayout = loaded.menuBarLayout
        self.menuBarSymbol = loaded.menuBarSymbol
        self.menuBarTint = loaded.menuBarTint
        self.valueStyle = loaded.displayStyle
        self.separators = loaded.separatorStyle
        self.privacyShortcut = ShortcutDefinition(loaded.privacyShortcut)
        self.launchAtLogin = loaded.launchAtLogin
        var configured: [String: Bool] = [:]
        for candidate in Trading212Environment.allCases {
            configured[candidate.rawValue] =
                (try? self.metadataStore.isTradeCredentialConfigured(for: candidate)) == true
        }
        self.tradeCredentialConfiguredByEnvironment = configured
    }

    func isTradeCredentialConfigured(for environment: Trading212Environment) -> Bool {
        tradeCredentialConfiguredByEnvironment[environment.rawValue] == true
    }

    /// When the saved credentials last validated against the API, if known.
    func validatedAt(for environment: Trading212Environment) -> Date? {
        ((try? metadataStore.metadata(for: environment)) ?? nil)?.validatedAt
    }

    func setTradeCredentialConfigured(_ configured: Bool, for environment: Trading212Environment) {
        var updated = tradeCredentialConfiguredByEnvironment
        updated[environment.rawValue] = configured
        tradeCredentialConfiguredByEnvironment = updated
        var metadata = (try? metadataStore.metadata(for: environment))
            ?? AccountMetadata(environment: environment)
        metadata.tradeCredentialConfigured = configured
        try? metadataStore.save(metadata)
    }

    func setReadCredentialConfigured(
        _ configured: Bool,
        for environment: Trading212Environment,
        portfolio: CurrentPortfolio? = nil
    ) {
        var metadata = (try? metadataStore.metadata(for: environment))
            ?? AccountMetadata(environment: environment)
        metadata.readCredentialConfigured = configured
        if let portfolio {
            metadata.accountID = portfolio.account.id
            metadata.currency = portfolio.account.currency
            metadata.validatedAt = portfolio.capturedAt
        } else if !configured {
            metadata.accountID = nil
            metadata.currency = nil
            metadata.validatedAt = nil
        }
        try? metadataStore.save(metadata)
    }

    private func persistSettings() {
        let value = AppSettings(
            refreshInterval: refreshCadence,
            displayStyle: valueStyle,
            separatorStyle: separators,
            menuBarLayout: menuBarLayout,
            menuBarSymbol: menuBarSymbol,
            menuBarTint: menuBarTint,
            privacyEnabled: privacyMode,
            privacyShortcut: privacyShortcut.coreSettings,
            launchAtLogin: launchAtLogin)
        try? settingsStore.save(value)
    }

    private static func defaultStores() -> (
        settings: any SettingsStore,
        metadata: any AccountMetadataStoring
    ) {
        do {
            let workspace = try Workspace(variant: .current)
            try workspace.prepare()
            return (
                JSONSettingsStore(workspace: workspace),
                JSONAccountMetadataStore(workspace: workspace))
        } catch {
            return (InMemorySettingsStore(), InMemoryAccountMetadataStore())
        }
    }
}

enum GUIValueFormatter {
    static func string(
        _ amount: Decimal,
        currency: String,
        style: ValueStyle,
        separators: NumberSeparators,
        locale: Locale = .current
    ) -> String {
        CurrencyDisplay.string(
            amount,
            currencyCode: currency,
            style: style,
            separators: separators,
            locale: locale)
    }
}

final class InMemoryAccountMetadataStore: AccountMetadataStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Trading212Environment: AccountMetadata] = [:]

    func metadata(for environment: Trading212Environment) throws -> AccountMetadata? {
        lock.withLock { values[environment] }
    }

    func save(_ metadata: AccountMetadata) throws {
        lock.withLock { values[metadata.environment] = metadata }
    }

    func isTradeCredentialConfigured(for environment: Trading212Environment) throws -> Bool {
        lock.withLock { values[environment]?.tradeCredentialConfigured == true }
    }
}
