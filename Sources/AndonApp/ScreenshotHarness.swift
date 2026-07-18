import AppKit
import SwiftUI
import Trading212Core

/// Offscreen screenshot mode: `AndonApp --screenshots [--real] [--output dir]`.
///
/// Renders every sidebar route (plus the menu-bar popover and a privacy-mode
/// shot) through `NSHostingView` into PNGs, in light and dark appearance, so
/// UI changes can be reviewed without launching the app.
///
/// Two data modes:
/// - Default: deterministic fixture data through in-memory stores. Touches no
///   Keychain item, workspace file, or network endpoint.
/// - `--real`: the app's normal startup path — your saved viewing key, cache,
///   and one live portfolio fetch — so the shots show your actual account.
///   Read-only, like the app itself; a dev build still reaches Demo only.
@MainActor
enum ScreenshotHarness {
    static func runIfRequested() {
        guard CommandLine.arguments.contains("--screenshots") else { return }
        exit(run(arguments: CommandLine.arguments))
    }

    private static let defaultWindowSize = NSSize(width: 1150, height: 740)

    /// `--size WxH` overrides the captured window size — the usual use is
    /// checking layouts at the window's minimum.
    private static func windowSize(from arguments: [String]) -> NSSize {
        guard let raw = value(after: "--size", in: arguments) else { return defaultWindowSize }
        let parts = raw.lowercased().split(separator: "x")
        guard parts.count == 2,
              let width = Double(parts[0]), let height = Double(parts[1]),
              width > 0, height > 0 else { return defaultWindowSize }
        return NSSize(width: width, height: height)
    }

    @MainActor
    private final class Completion {
        var finished = false
        var exitCode: Int32 = 0
    }

    private static func run(arguments: [String]) -> Int32 {
        let real = arguments.contains("--real")
        let size = windowSize(from: arguments)
        let outputRoot = URL(
            fileURLWithPath: value(after: "--output", in: arguments) ?? "screenshots")

        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)

        let completion = Completion()
        Task { @MainActor in
            do {
                let model: AppModel
                if real {
                    model = AppModel()
                    await model.start()
                } else {
                    model = try await fixtureModel()
                }
                let directory = outputRoot.appending(
                    component: real ? "real" : "fixture", directoryHint: .isDirectory)
                try await captureAll(
                    model: model, into: directory, size: size, includePrivacyShot: !real)
                print("Screenshots written to \(directory.path)")
            } catch {
                FileHandle.standardError.write(
                    Data("screenshot harness failed: \(error)\n".utf8))
                completion.exitCode = 1
            }
            completion.finished = true
        }
        // No `NSApp.run()` in this mode; pump the main run loop (which drains
        // the main queue, and with it MainActor jobs) until the capture ends.
        while !completion.finished {
            RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
        }
        return completion.exitCode
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag),
              arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    // MARK: Capture

    private static func captureAll(
        model: AppModel,
        into root: URL,
        size windowSize: NSSize,
        includePrivacyShot: Bool
    ) async throws {
        for (suffix, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let directory = root.appending(component: suffix, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)

            for (index, route) in AppRoute.allCases.enumerated() {
                model.navigate(to: route)
                try await capture(
                    RootView(model: model),
                    size: windowSize,
                    appearance: appearance,
                    to: directory.appending(
                        component: String(format: "%02d-%@.png", index + 1, route.rawValue)))
            }

            if includePrivacyShot {
                model.navigate(to: .portfolio)
                let wasPrivate = model.isPrivate
                model.setPrivacy(true)
                try await capture(
                    RootView(model: model),
                    size: windowSize,
                    appearance: appearance,
                    to: directory.appending(component: "portfolio-private.png"))
                model.setPrivacy(wasPrivate)
            }

            try await capture(
                PortfolioPopoverView(model: model, openApp: {}, openSettings: {}),
                size: nil,
                appearance: appearance,
                to: directory.appending(component: "popover.png"))
        }
        model.navigate(to: .portfolio)
    }

    private static func capture(
        _ view: some View,
        size: NSSize?,
        appearance: NSAppearance.Name,
        to url: URL
    ) async throws {
        // The real app gets its backdrop from the window; the offscreen bitmap
        // only contains the view tree, so paint that backdrop explicitly or
        // undrawn regions come out transparent (white in dark mode).
        let hosting = NSHostingView(
            rootView: view.background(Color(nsColor: .windowBackgroundColor)))
        hosting.frame = NSRect(origin: .zero, size: size ?? NSSize(width: 10, height: 10))

        // The window is never ordered in — it only gives the hierarchy an
        // appearance, a backing store, and a layout context.
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.colorSpace = .sRGB
        window.contentView = hosting

        if size == nil {
            let fitting = hosting.fittingSize
            hosting.setFrameSize(fitting)
            window.setContentSize(fitting)
        }
        hosting.layoutSubtreeIfNeeded()
        // One brief suspension so SwiftUI can settle deferred content (Table
        // columns, ContentUnavailableView) before the bitmap is taken.
        try await Task.sleep(for: .milliseconds(120))

        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            throw HarnessError.captureUnavailable(url.lastPathComponent)
        }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw HarnessError.encodingFailed(url.lastPathComponent)
        }
        try png.write(to: url)
        window.orderOut(nil)
    }

    private enum HarnessError: Error, LocalizedError {
        case captureUnavailable(String)
        case encodingFailed(String)

        var errorDescription: String? {
            switch self {
            case let .captureUnavailable(name): "Could not create a bitmap for \(name)."
            case let .encodingFailed(name): "Could not encode PNG data for \(name)."
            }
        }
    }

    // MARK: Fixture data

    private static func fixtureModel() async throws -> AppModel {
        let portfolio = fixturePortfolio()
        let settings = GUISettings(
            settingsStore: InMemorySettingsStore(),
            metadataStore: InMemoryAccountMetadataStore())
        settings.setTradeCredentialConfigured(true, for: settings.environment)

        let model = AppModel(
            settings: settings,
            credentialStore: FixtureCredentialStore(),
            snapshotCache: InMemorySnapshotCache(),
            makeProvider: { _, _ in FixtureProvider(portfolio: portfolio) })

        SnapshotLibrary.directoryOverride = try fixtureSnapshotsDirectory()
        await model.refresh(force: true)
        return model
    }

    private struct FixtureProvider: PortfolioProvider {
        let portfolio: CurrentPortfolio
        func fetchPortfolio() async throws -> CurrentPortfolio { portfolio }
    }

    private struct FixtureCredentialStore: CredentialStore {
        func credentials(
            for kind: CredentialKind,
            environment: Trading212Environment
        ) throws -> Trading212Credentials? {
            kind == .read
                ? Trading212Credentials(key: "fixture-key", secret: "fixture-secret")
                : nil
        }

        func set(_ credentials: Trading212Credentials,
                 for kind: CredentialKind,
                 environment: Trading212Environment) throws {}
        func delete(kind: CredentialKind, environment: Trading212Environment) throws {}
    }

    private static func fixturePortfolio() -> CurrentPortfolio {
        struct Holding {
            let ticker: String
            let name: String
            let quantity: Decimal
            let pieQuantity: Decimal
            let price: Decimal
        }
        func d(_ string: String) -> Decimal {
            Decimal(string: string, locale: Locale(identifier: "en_US_POSIX")) ?? 0
        }

        let holdings: [Holding] = [
            Holding(ticker: "AAPL_US_EQ", name: "Apple", quantity: d("42"), pieQuantity: d("0"), price: d("195.40")),
            Holding(ticker: "MSFT_US_EQ", name: "Microsoft", quantity: d("18"), pieQuantity: d("0"), price: d("402.10")),
            Holding(ticker: "NVDA_US_EQ", name: "NVIDIA", quantity: d("25"), pieQuantity: d("5"), price: d("118.52")),
            Holding(ticker: "VUAA_EQ", name: "Vanguard S&P 500 UCITS ETF", quantity: d("95.5"), pieQuantity: d("95.5"), price: d("92.30")),
            Holding(ticker: "IWDA_EQ", name: "iShares Core MSCI World", quantity: d("120"), pieQuantity: d("40"), price: d("88.75")),
            Holding(ticker: "ASML_NA_EQ", name: "ASML Holding", quantity: d("6"), pieQuantity: d("0"), price: d("861.20")),
            Holding(ticker: "TSLA_US_EQ", name: "Tesla", quantity: d("12.5"), pieQuantity: d("0"), price: d("219.86")),
            Holding(ticker: "SXR8_DE_EQ", name: "iShares Core S&P 500", quantity: d("3.2"), pieQuantity: d("0"), price: d("512.44")),
        ]

        let sellableTotal = holdings.reduce(Decimal.zero) {
            $0 + ($1.quantity - $1.pieQuantity) * $1.price
        }
        let positions = holdings.map { holding in
            let sellableQuantity = holding.quantity - holding.pieQuantity
            let sellableValue = sellableQuantity * holding.price
            return PortfolioPosition(
                ticker: holding.ticker,
                isin: nil,
                name: holding.name,
                instrumentCurrency: "EUR",
                quantity: holding.quantity,
                sellableQuantity: sellableQuantity,
                pieQuantity: holding.pieQuantity,
                nativePrice: holding.price,
                accountPricePerShare: holding.price,
                sellableAccountValue: sellableValue,
                sellableWeight: sellableTotal > 0 ? sellableValue / sellableTotal : 0)
        }

        let holdingsTotal = holdings.reduce(Decimal.zero) { $0 + $1.quantity * $1.price }
        let freeCash = d("1234.56")
        return CurrentPortfolio(
            environment: .demo,
            account: AccountIdentity(id: "fixture-account", currency: "EUR"),
            accountValue: holdingsTotal + freeCash,
            freeCash: freeCash,
            sellablePositionsValue: sellableTotal,
            unrealizedProfitLoss: d("2345.67"),
            positions: positions,
            capturedAt: Date().addingTimeInterval(-300))
    }

    /// Two fixture snapshot files in a temp directory so the Snapshots route
    /// renders a populated list without reading the real workspace.
    private static func fixtureSnapshotsDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(component: "andon-shots-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        func write(kind: String, stamp: String, capturedAt: String, value: String) throws {
            let json = """
            {
              "schema": "com.marinsokol.trading212andoncord.portfolio-snapshot",
              "version": 1,
              "kind": "\(kind)",
              "capturedAt": "\(capturedAt)",
              "environment": "demo",
              "account": {"id": "fixture-account", "currency": "EUR"},
              "totals": {"accountValue": "\(value)", "freeCash": "1234.56", "sellablePositionsValue": "36615.09"},
              "positions": [
                {"ticker": "AAPL_US_EQ"}, {"ticker": "MSFT_US_EQ"}, {"ticker": "NVDA_US_EQ"},
                {"ticker": "IWDA_EQ"}, {"ticker": "ASML_NA_EQ"}, {"ticker": "TSLA_US_EQ"}
              ]
            }
            """
            try Data(json.utf8).write(
                to: directory.appending(component: "\(kind)-demo-\(stamp).json"))
        }
        try write(kind: "current", stamp: "20260715T101500Z",
                  capturedAt: "2026-07-15T10:15:00Z", value: "49912.33")
        try write(kind: "preSale", stamp: "20260701T093000Z",
                  capturedAt: "2026-07-01T09:30:00Z", value: "48210.90")
        return directory
    }
}
