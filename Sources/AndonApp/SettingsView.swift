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

            LabeledContent("Preview") {
                HStack(spacing: 5) {
                    Image(systemName: model.isPrivate ? "eye.slash" : "chart.line.uptrend.xyaxis")
                    Text(model.isPrivate
                         ? AppModel.hiddenText
                         : model.privateAmount(49_900.50, currency: "EUR", style: model.settings.valueStyle))
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
        }
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
