import Foundation
import Observation
import Trading212Core

/// Sidebar routes, in display order. Account leads: it is the first thing a
/// new user must configure before anything else has data.
enum AppRoute: String, CaseIterable, Identifiable, Hashable {
    case account
    case portfolio
    case positions
    case snapshots
    case display
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .account: "Account"
        case .portfolio: "Portfolio"
        case .positions: "Positions"
        case .snapshots: "Snapshots"
        case .display: "Display"
        case .about: "About"
        }
    }

    var systemImage: String {
        switch self {
        case .account: "key.horizontal.fill"
        case .portfolio: "chart.pie.fill"
        case .positions: "list.bullet.rectangle.fill"
        case .snapshots: "square.stack.3d.up.fill"
        case .display: "slider.horizontal.3"
        case .about: "info.circle.fill"
        }
    }
}

@MainActor
@Observable
final class AppModel {
    static let hiddenText = "••••••"

    let settings: GUISettings

    private(set) var activeRoute: AppRoute = .account

    private(set) var currentPortfolio: CurrentPortfolio?
    private(set) var isRefreshing = false
    private(set) var errorMessage: String?
    private(set) var hasReadCredential = false
    /// Last characters of the saved viewing key ID, for "which key is this"
    /// display. The key ID is not a secret; the secret is never read back.
    private(set) var readKeyHint: String?

    private let credentialStore: any CredentialStore
    private let snapshotCache: any SnapshotCache
    private let makeProvider: @Sendable (
        Trading212Environment,
        Trading212Credentials
    ) -> any PortfolioProvider
    private let minimumRefreshInterval: TimeInterval

    private var refreshLoop: Task<Void, Never>?
    private var lastAttempt: Date?
    private var rateLimitAttempt = 0
    private var rateLimitDelay: TimeInterval?
    private var hasStarted = false
    private var stateGeneration = 0
    private var globalShortcut: GlobalShortcut?

    var environment: Trading212Environment { settings.environment }
    var isPrivate: Bool { settings.privacyMode }
    var hasTradeCredential: Bool {
        settings.isTradeCredentialConfigured(for: environment)
    }
    var displaySnapshot: AccountSnapshot? {
        currentPortfolio.map { AccountSnapshot(portfolio: $0) }
    }

    var menuBarValue: String {
        if isPrivate, displaySnapshot != nil { return Self.hiddenText }
        if let snapshot = displaySnapshot {
            return GUIValueFormatter.string(
                snapshot.totalValue,
                currency: snapshot.currencyCode,
                style: settings.valueStyle,
                separators: settings.separators)
        }
        if !hasReadCredential { return "—" }
        return isRefreshing ? "…" : "⚠"
    }

    init(
        settings: GUISettings = GUISettings(),
        credentialStore: any CredentialStore = KeychainCredentialStore(),
        snapshotCache: (any SnapshotCache)? = nil,
        minimumRefreshInterval: TimeInterval = 5,
        makeProvider: @escaping @Sendable (
            Trading212Environment,
            Trading212Credentials
        ) -> any PortfolioProvider = { environment, credentials in
            Trading212Client(
                environment: environment,
                credentials: credentials,
                variant: AppVariant.current)
        }
    ) {
        self.settings = settings
        self.credentialStore = credentialStore
        self.snapshotCache = snapshotCache ?? Self.makeFileCache()
        self.minimumRefreshInterval = minimumRefreshInterval
        self.makeProvider = makeProvider
        self.currentPortfolio = nil
        let saved = try? credentialStore.credentials(
            for: .read,
            environment: settings.environment)
        self.hasReadCredential = saved != nil
        self.readKeyHint = Self.keyHint(saved?.key)
        // A configured install lands on the portfolio; a fresh one starts on
        // Account, the only screen that can do anything yet.
        self.activeRoute = self.hasReadCredential ? .portfolio : .account
        self.globalShortcut = nil
        settings.launchAtLogin = LaunchAtLogin.isEnabled
        self.globalShortcut = GlobalShortcut(shortcut: settings.privacyShortcut) { [weak self] in
            self?.togglePrivacy()
        }
    }

    func navigate(to route: AppRoute) {
        activeRoute = route
    }

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        currentPortfolio = snapshotCache.portfolio(for: environment)
        updateCredentialPresence()
        await refreshCredentialStatusFromCLI()
        await refresh(force: true)
        scheduleRefreshLoop()
    }

    func refresh(force: Bool = false) async {
        guard !isRefreshing else { return }
        if !force, let lastAttempt,
           Date().timeIntervalSince(lastAttempt) < minimumRefreshInterval {
            return
        }

        let credentials: Trading212Credentials
        let requestedEnvironment = environment
        let requestedGeneration = stateGeneration
        do {
            guard let saved = try credentialStore.credentials(
                for: .read,
                environment: environment) else {
                hasReadCredential = false
                readKeyHint = nil
                errorMessage = nil
                return
            }
            credentials = saved
            hasReadCredential = true
            readKeyHint = Self.keyHint(saved.key)
        } catch {
            hasReadCredential = false
            readKeyHint = nil
            errorMessage = sanitized(error, credentials: [])
            return
        }

        isRefreshing = true
        lastAttempt = Date()
        defer { isRefreshing = false }

        do {
            let portfolio = try await makeProvider(requestedEnvironment, credentials).fetchPortfolio()
            guard requestedGeneration == stateGeneration,
                  requestedEnvironment == environment else { return }
            currentPortfolio = portfolio
            settings.setReadCredentialConfigured(
                true,
                for: environment,
                portfolio: portfolio)
            errorMessage = nil
            rateLimitAttempt = 0
            rateLimitDelay = nil
            do { try snapshotCache.save(portfolio) }
            catch {
                // A fresh reading remains useful even if its local cache cannot
                // be updated. Surface the storage problem without discarding it.
                errorMessage = "Portfolio updated, but its local cache could not be saved."
            }
        } catch let error as Trading212APIError {
            guard requestedGeneration == stateGeneration,
                  requestedEnvironment == environment else { return }
            errorMessage = sanitized(error, credentials: [credentials])
            if case let .rateLimited(info) = error {
                rateLimitAttempt += 1
                rateLimitDelay = info.delay()
            } else {
                rateLimitAttempt = 0
                rateLimitDelay = nil
            }
        } catch {
            guard requestedGeneration == stateGeneration,
                  requestedEnvironment == environment else { return }
            errorMessage = sanitized(error, credentials: [credentials])
            rateLimitAttempt = 0
            rateLimitDelay = nil
        }
    }

    func validateAndSaveRead(key: String, secret: String) async throws {
        let candidate = Trading212Credentials(
            key: key.trimmingCharacters(in: .whitespacesAndNewlines),
            secret: secret.trimmingCharacters(in: .whitespacesAndNewlines))
        guard candidate.isComplete else { throw CredentialStoreError.incompleteCredentials }
        let targetEnvironment = environment
        try AppVariant.current.validate(environment: targetEnvironment)
        stateGeneration += 1
        let targetGeneration = stateGeneration

        // Validate before changing the Keychain, so a typo cannot overwrite the
        // last working pair.
        let portfolio: CurrentPortfolio
        do {
            portfolio = try await makeProvider(targetEnvironment, candidate).fetchPortfolio()
        } catch {
            throw AppModelError.message(sanitized(error, credentials: [candidate]))
        }
        guard targetEnvironment == environment, targetGeneration == stateGeneration else {
            throw AppModelError.message("The account state changed during validation. Try again.")
        }

        try credentialStore.set(candidate, for: .read, environment: targetEnvironment)
        hasReadCredential = true
        readKeyHint = Self.keyHint(candidate.key)
        currentPortfolio = portfolio
        settings.setReadCredentialConfigured(true, for: targetEnvironment, portfolio: portfolio)
        errorMessage = nil
        lastAttempt = Date()
        try? snapshotCache.save(portfolio)
        scheduleRefreshLoop()
    }

    func removeReadCredential() throws {
        stateGeneration += 1
        try credentialStore.delete(kind: .read, environment: environment)
        let cacheError: Error?
        do {
            try snapshotCache.remove(for: environment)
            cacheError = nil
        } catch {
            cacheError = error
        }
        hasReadCredential = false
        readKeyHint = nil
        settings.setReadCredentialConfigured(false, for: environment)
        currentPortfolio = nil
        errorMessage = nil
        refreshLoop?.cancel()
        if let cacheError { throw cacheError }
    }

    func validateAndSaveTrade(key: String, secret: String) async -> CLIInvocationResult {
        let targetEnvironment = environment
        do {
            try AppVariant.current.validate(environment: targetEnvironment)
        } catch {
            return CLIInvocationResult(exitCode: 4, output: error.localizedDescription)
        }

        let result = await TradingCredentialCLI.setTradingCredential(
            key: key.trimmingCharacters(in: .whitespacesAndNewlines),
            secret: secret.trimmingCharacters(in: .whitespacesAndNewlines))
        if result.succeeded {
            settings.setTradeCredentialConfigured(true, for: targetEnvironment)
        }
        return result
    }

    func removeTradeCredential() async -> CLIInvocationResult {
        let targetEnvironment = environment
        let result = await TradingCredentialCLI.deleteTradingCredential()
        if result.succeeded {
            settings.setTradeCredentialConfigured(false, for: targetEnvironment)
        }
        return result
    }

    func setPrivacy(_ privateMode: Bool) { settings.privacyMode = privateMode }
    func togglePrivacy() { settings.privacyMode.toggle() }

    func setPrivacyShortcut(_ shortcut: ShortcutDefinition) {
        settings.privacyShortcut = shortcut
        globalShortcut?.update(shortcut)
    }

    func setRefreshCadence(_ cadence: RefreshCadence) {
        settings.refreshCadence = cadence
        scheduleRefreshLoop()
    }

    func privateAmount(
        _ amount: Decimal,
        currency: String,
        style: ValueStyle? = nil
    ) -> String {
        guard !isPrivate else { return Self.hiddenText }
        return GUIValueFormatter.string(
            amount,
            currency: currency,
            style: style ?? settings.valueStyle,
            separators: settings.separators)
    }

    private func updateCredentialPresence() {
        let saved = try? credentialStore.credentials(for: .read, environment: environment)
        hasReadCredential = saved != nil
        readKeyHint = Self.keyHint(saved?.key)
    }

    private static func keyHint(_ key: String?) -> String? {
        // Too-short values are not worth hinting: the suffix would be most of
        // the identifier rather than a recognizable tail.
        guard let key, key.count >= 8 else { return nil }
        return String(key.suffix(4))
    }

    private func refreshCredentialStatusFromCLI() async {
        let targetEnvironment = environment
        guard let status = await TradingCredentialCLI.credentialStatus() else {
            return
        }
        hasReadCredential = status.readConfigured
        if status.readConfigured {
            if readKeyHint == nil {
                readKeyHint = Self.keyHint(
                    (try? credentialStore.credentials(for: .read, environment: targetEnvironment))?.key)
            }
        } else {
            readKeyHint = nil
        }
        settings.setReadCredentialConfigured(status.readConfigured, for: targetEnvironment)
        settings.setTradeCredentialConfigured(status.tradingConfigured, for: targetEnvironment)
    }

    private func scheduleRefreshLoop() {
        refreshLoop?.cancel()
        guard settings.refreshCadence.seconds != nil, hasReadCredential else { return }
        refreshLoop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let delay = self.nextRefreshDelay() else { return }
                do { try await Task.sleep(for: .seconds(delay)) }
                catch { return }
                guard !Task.isCancelled else { return }
                await self.refresh()
            }
        }
    }

    private func nextRefreshDelay() -> TimeInterval? {
        guard let base = settings.refreshCadence.seconds else { return nil }
        guard rateLimitAttempt > 0 else { return base }
        let exponential = min(base * pow(2, Double(rateLimitAttempt)), 15 * 60)
        return max(exponential, rateLimitDelay ?? 0)
    }

    private func sanitized(
        _ error: Error,
        credentials: [Trading212Credentials]
    ) -> String {
        Redactor.redact(error.localizedDescription, credentials: credentials)
    }

    private static func makeFileCache() -> any SnapshotCache {
        do {
            let workspace = try Workspace(variant: .current)
            try workspace.prepare()
            return FileSnapshotCache(workspace: workspace)
        } catch {
            // The UI remains usable for the current process, but will have no
            // launch cache. The next refresh can still provide a live value.
            return InMemorySnapshotCache()
        }
    }
}

private enum AppModelError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case let .message(message): message
        }
    }
}
