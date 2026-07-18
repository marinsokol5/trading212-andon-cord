import AppKit
import SwiftUI
import Trading212Core

/// The **About** screen: version and build identity, the independence and
/// privacy statement, and a pointer to the bundled CLI where trading lives.
struct AboutView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScreenHeader("About", subtitle: AppVariant.current.appName)

            Form {
                versionSection
                safetySection
                cliSection
            }
            .formStyle(.grouped)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var versionSection: some View {
        Section("Version") {
            LabeledContent("Version", value: Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development")
            LabeledContent("Build variant") {
                Label(
                    AppVariant.current == .development ? "Development (Demo only)" : "Production",
                    systemImage: AppVariant.current == .development ? "hammer" : "checkmark.seal")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Environment") {
                EnvironmentBadge(environment: model.environment)
            }
        }
    }

    private var safetySection: some View {
        Section("Independence & privacy") {
            Text("Independent software, not affiliated with or endorsed by Trading 212. No backend, analytics, credential sync, or browser scraping — everything stays on this Mac.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("The app is read-only by design: it contains no order-placement code and cannot retrieve the trading credential. Viewing and trading keys live in separate Keychain slots.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var cliSection: some View {
        Section {
            Text("Snapshots, sell-all, and buy-all live in the bundled `t212` terminal command — never in this window. Run `t212 --help` in Terminal to see the command surface; Live actions require typing exact confirmation phrases.")
                .font(.callout)
                .foregroundStyle(.secondary)
        } header: {
            Text("Trading CLI")
        } footer: {
            Text("See README.md and SECURITY.md in the project repository for the full safety guide.")
        }
    }
}
