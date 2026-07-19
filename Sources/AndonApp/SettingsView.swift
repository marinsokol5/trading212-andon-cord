import AppKit
import SwiftUI
import Trading212Core

/// The **Settings** screen: value formatting, menu-bar appearance, privacy,
/// refresh cadence, and launch-at-login.
struct SettingsView: View {
    @Bindable var model: AppModel

    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScreenHeader(
                "Settings",
                subtitle: "Formatting, menu bar, privacy, and behavior.")

            Form {
                formattingSection
                menuBarSection
                privacySection
                behaviorSection
                aboutSection
            }
            .formStyle(.grouped)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
    }

    private var formattingSection: some View {
        Section("Values") {
            Picker("Value", selection: valueStyleBinding) {
                ForEach(ValueStyle.allCases) { Text($0.displayName).tag($0) }
            }
            Picker("Numbers", selection: separatorsBinding) {
                ForEach(NumberSeparators.allCases) { Text($0.displayName).tag($0) }
            }

            // Sample data, not the real value — render it even in privacy mode
            // so formatting stays tunable while values are hidden.
            LabeledContent("Preview") {
                HStack(spacing: 5) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                    Text(GUIValueFormatter.string(
                        49_900.50,
                        currency: "EUR",
                        style: model.settings.valueStyle,
                        separators: model.settings.separators))
                        .monospacedDigit()
                }
            }
        }
    }

    private var menuBarSection: some View {
        Section("Menu bar") {
            Picker("Layout", selection: layoutBinding) {
                ForEach(MenuBarLayout.allCases) { Text($0.displayName).tag($0) }
            }
            Picker("Symbol", selection: symbolBinding) {
                ForEach(MenuBarSymbol.allCases) { Text($0.displayName).tag($0) }
            }
            Picker("Brightness", selection: tintBinding) {
                ForEach(MenuBarTint.allCases) { Text($0.displayName).tag($0) }
            }
            Toggle("Show daily change", isOn: menuBarChangeBinding)

            // Rendered with the real menu bar renderer on sample data, so the
            // picker choices can be judged by eye without leaving Settings.
            LabeledContent("Preview") {
                Image(nsImage: menuBarPreviewImage)
                    .renderingMode(.template)
                    .foregroundStyle(.primary)
            }
        }
    }

    private var menuBarPreviewImage: NSImage {
        var value = GUIValueFormatter.string(
            49_900.50, currency: "EUR",
            style: model.settings.valueStyle,
            separators: model.settings.separators)
        if model.settings.menuBarShowsDailyChange {
            value += " \(CurrencyDisplay.percentString(0.0129, separators: model.settings.separators))"
        }
        return MenuBarRenderer.image(
            value: value,
            privateMode: false,
            layout: model.settings.menuBarLayout,
            symbol: model.settings.menuBarSymbol,
            tint: .adaptive,
            trendDown: false)
    }

    private var privacySection: some View {
        Section("Privacy") {
            Toggle("Hide financial values throughout the app", isOn: privacyBinding)
            LabeledContent("Global privacy shortcut") {
                ShortcutRecorder(shortcut: shortcutBinding)
            }
        }
    }

    private var behaviorSection: some View {
        Section("Behavior") {
            Picker("Refresh", selection: cadenceBinding) {
                ForEach(RefreshCadence.allCases) { Text($0.displayName).tag($0) }
            }
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) {
                    launchAtLogin = LaunchAtLogin.setEnabled(launchAtLogin)
                    model.settings.launchAtLogin = launchAtLogin
                }
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version", value: Self.appVersion)
            Link(
                "Releases on GitHub",
                destination: URL(string: "https://github.com/marinsokol5/trading212-andon-cord/releases")!)
        }
    }

    /// Bundled builds report the Info.plist version; bare `swift build`
    /// binaries have no bundle version and show "dev".
    private static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    private var valueStyleBinding: Binding<ValueStyle> {
        Binding(get: { model.settings.valueStyle }, set: { model.settings.valueStyle = $0 })
    }
    private var separatorsBinding: Binding<NumberSeparators> {
        Binding(get: { model.settings.separators }, set: { model.settings.separators = $0 })
    }
    private var layoutBinding: Binding<MenuBarLayout> {
        Binding(get: { model.settings.menuBarLayout }, set: { model.settings.menuBarLayout = $0 })
    }
    private var symbolBinding: Binding<MenuBarSymbol> {
        Binding(get: { model.settings.menuBarSymbol }, set: { model.settings.menuBarSymbol = $0 })
    }
    private var tintBinding: Binding<MenuBarTint> {
        Binding(get: { model.settings.menuBarTint }, set: { model.settings.menuBarTint = $0 })
    }
    private var menuBarChangeBinding: Binding<Bool> {
        Binding(get: { model.settings.menuBarShowsDailyChange },
                set: { model.settings.menuBarShowsDailyChange = $0 })
    }
    private var privacyBinding: Binding<Bool> {
        Binding(get: { model.isPrivate }, set: { model.setPrivacy($0) })
    }
    private var shortcutBinding: Binding<ShortcutDefinition> {
        Binding(get: { model.settings.privacyShortcut }, set: { model.setPrivacyShortcut($0) })
    }
    private var cadenceBinding: Binding<RefreshCadence> {
        Binding(get: { model.settings.refreshCadence }, set: { model.setRefreshCadence($0) })
    }
}
