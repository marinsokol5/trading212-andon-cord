import SwiftUI
import Trading212Core

/// The **Account** screen. A fresh install gets a single focused connect card;
/// once viewing access works, it becomes two cards — viewing and optional
/// trading credentials. The environment is fixed by the build and shown as a
/// badge in the header, not as a form row.
struct AccountView: View {
    @Bindable var model: AppModel

    @State private var readKey = ""
    @State private var readSecret = ""
    @State private var tradeKey = ""
    @State private var tradeSecret = ""
    @State private var readPhase: SavePhase = .idle
    @State private var tradePhase: SavePhase = .idle
    @State private var confirmRemoveRead = false
    @State private var confirmRemoveTrade = false
    @State private var isReplacingRead = false
    @State private var isReplacingTrade = false
    @State private var showEnvironmentInfo = false
    @State private var showViewingHelp = false
    @State private var showTradingHelp = false

    private enum SavePhase: Equatable {
        case idle
        case working
        case saved(String)
        case failed(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScreenHeader(
                "Account",
                subtitle: "Your credentials and portfolio data stay on this Mac.") {
                    environmentInfo
                }

            ScrollView {
                VStack(spacing: 16) {
                    if model.hasReadCredential {
                        viewingCard
                        tradingCard
                    } else {
                        connectCard
                    }
                }
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 22)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
        }
        .confirmationDialog(
            "Remove the viewing key for \(model.environment.displayName)?",
            isPresented: $confirmRemoveRead) {
                Button("Remove Viewing Key", role: .destructive) {
                    Task { await removeRead() }
                }
            }
        .confirmationDialog(
            "Remove the trading key for \(model.environment.displayName)?",
            isPresented: $confirmRemoveTrade) {
                Button("Remove Trading Key", role: .destructive) {
                    Task { await removeTrade() }
                }
            }
    }

    // MARK: Header

    private var environmentInfo: some View {
        HStack(spacing: 6) {
            EnvironmentBadge(environment: model.environment)
            helpButton(
                $showEnvironmentInfo,
                "This build always uses the Trading 212 \(model.environment.displayName) API. "
                    + "There is no runtime switch — paste keys created for that environment.")
        }
        .help("This build always uses the Trading 212 \(model.environment.displayName) API.")
    }

    // MARK: First run

    private var connectCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                cardIcon("key.horizontal.fill", size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connect your Trading 212 account")
                        .font(.headline)
                    Text("A read-only key is enough to see your portfolio.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                step(1, "In Trading 212, open Settings → API (Beta) → Generate API key.")
                step(2, "Enable the Account data and Portfolio permissions on your \(model.environment.displayName) account, then generate the key.")
                step(3, "Paste the API key ID and secret key here.")
            }

            credentialFields(
                keyTitle: "API key ID", key: $readKey,
                secretTitle: "Secret key", secret: $readSecret)

            phaseRow(readPhase)

            HStack {
                Spacer()
                validateReadButton
            }
        }
        .padding(18)
        .card()
    }

    // MARK: Configured state

    private var viewingCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            cardHeader(
                icon: "key.horizontal.fill",
                title: "Viewing access",
                subtitle: "Read-only key for the portfolio and menu bar.",
                configured: model.hasReadCredential,
                help: $showViewingHelp,
                helpText: "Generate a key in Trading 212 Settings → API (Beta) with the "
                    + "Account data and Portfolio permissions enabled. The key is validated "
                    + "against the API before it replaces a working Keychain value.")

            if isReplacingRead {
                credentialFields(
                    keyTitle: "API key ID", key: $readKey,
                    secretTitle: "Secret key", secret: $readSecret)

                phaseRow(readPhase)

                HStack {
                    Button("Cancel") { cancelReplaceRead() }
                    Spacer()
                    validateReadButton
                }
            } else {
                savedSummary(
                    title: readSummaryTitle,
                    detail: model.settings.validatedAt(for: model.environment).map {
                        "Validated \($0.formatted(date: .abbreviated, time: .shortened))."
                    })

                phaseRow(readPhase)

                HStack {
                    Button("Remove…", role: .destructive) { confirmRemoveRead = true }
                    Spacer()
                    Button("Replace Key…") { beginReplaceRead() }
                }
            }
        }
        .padding(18)
        .card()
    }

    private var tradingCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            cardHeader(
                icon: "lock.shield.fill",
                title: "Trading access",
                subtitle: "Optional — used only by the bundled t212 command.",
                configured: model.hasTradeCredential,
                help: $showTradingHelp,
                helpText: "The app cannot retrieve this key and contains no order-placement "
                    + "code. Setup runs the signed bundled t212 command and sends one JSON "
                    + "object over an anonymous stdin pipe. Trading 212 exposes no scope "
                    + "introspection: account and environment identity are verified, but the "
                    + "orders scope cannot be proven without placing an order — setup never "
                    + "places one.")

            if model.environment == .live {
                liveWarning
            }

            if model.hasTradeCredential, !isReplacingTrade {
                savedSummary(
                    title: Text("Key saved for the bundled t212 command"),
                    detail: "The app cannot read it back — it can only replace or remove it.")

                phaseRow(tradePhase)

                HStack {
                    Button("Remove…", role: .destructive) { confirmRemoveTrade = true }
                    Spacer()
                    Button("Replace Key…") { beginReplaceTrade() }
                }
            } else {
                credentialFields(
                    keyTitle: "API key ID", key: $tradeKey,
                    secretTitle: "Secret key", secret: $tradeSecret)

                Text("Validation hands this key straight to the signed t212 command over a private pipe. The app never stores it and cannot read it back.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                phaseRow(tradePhase)

                HStack {
                    if isReplacingTrade {
                        Button("Cancel") { cancelReplaceTrade() }
                    }
                    Spacer()
                    Button("Validate & Save via CLI") { Task { await saveTrade() } }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accent)
                        .disabled(
                            tradePhase == .working
                            || !model.hasReadCredential
                            || tradeKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || tradeSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .padding(18)
        .card()
    }

    // MARK: Building blocks

    private func cardHeader(
        icon: String,
        title: String,
        subtitle: String,
        configured: Bool,
        help: Binding<Bool>,
        helpText: String
    ) -> some View {
        HStack(spacing: 10) {
            cardIcon(icon, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            helpButton(help, helpText)
            statusBadge(configured: configured)
        }
    }

    private func cardIcon(_ systemImage: String, size: CGFloat) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(Theme.accent)
            .frame(width: size, height: size)
            .background(Theme.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: Theme.Radius.sm))
    }

    private func statusBadge(configured: Bool) -> some View {
        Label(
            configured ? "Configured" : "Not configured",
            systemImage: configured ? "checkmark.circle.fill" : "circle.dashed")
            .font(.caption.weight(.semibold))
            .foregroundStyle(configured ? Theme.success : Theme.warning)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                (configured ? Theme.success : Theme.warning).opacity(0.12),
                in: Capsule())
    }

    private func helpButton(_ isPresented: Binding<Bool>, _ text: String) -> some View {
        Button {
            isPresented.wrappedValue.toggle()
        } label: {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .popover(isPresented: isPresented, arrowEdge: .bottom) {
            Text(text)
                .font(.callout)
                .frame(width: 300, alignment: .leading)
                .padding(12)
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.accent)
                .frame(width: 18, height: 18)
                .background(Theme.accent.opacity(0.14), in: Circle())
            Text(text)
                .font(.callout)
        }
    }

    private func credentialFields(
        keyTitle: String, key: Binding<String>,
        secretTitle: String, secret: Binding<String>
    ) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            GridRow {
                Text(keyTitle)
                    .foregroundStyle(.secondary)
                    .gridColumnAlignment(.trailing)
                // Plain fields on purpose: Trading 212 shows both values in
                // clear text, and they are pasted once and never redisplayed.
                TextField("Paste the API key ID", text: key)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
            }
            GridRow {
                Text(secretTitle)
                    .foregroundStyle(.secondary)
                    .gridColumnAlignment(.trailing)
                TextField("Paste the secret key", text: secret)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
            }
        }
    }

    /// Compact "it's saved" row shown instead of write-only input fields.
    private func savedSummary(title: Text, detail: String?) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(Theme.success)
            VStack(alignment: .leading, spacing: 1) {
                title.font(.callout)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: Theme.Radius.sm))
    }

    private var readSummaryTitle: Text {
        if let hint = model.readKeyHint {
            Text("Key ID ending ")
                + Text("…\(hint)").fontDesign(.monospaced)
                + Text(" saved in the Keychain")
        } else {
            Text("Key saved in the Keychain")
        }
    }

    private var liveWarning: some View {
        Label(
            "LIVE means real money. Use a separately scoped key and read the CLI safety guide first.",
            systemImage: "exclamationmark.octagon.fill")
            .font(.callout.weight(.semibold))
            .foregroundStyle(Theme.danger)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.danger.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.Radius.sm))
    }

    private var validateReadButton: some View {
        Button(model.hasReadCredential ? "Validate & Replace" : "Validate & Save") {
            Task { await saveRead() }
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.accent)
        .disabled(
            readPhase == .working
            || readKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || readSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @ViewBuilder
    private func phaseRow(_ phase: SavePhase) -> some View {
        switch phase {
        case .idle:
            EmptyView()
        case .working:
            HStack { ProgressView().controlSize(.small); Text("Validating…") }
                .font(.caption)
                .foregroundStyle(.secondary)
        case let .saved(message):
            Label(message, systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(Theme.success)
        case let .failed(message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(Theme.danger)
                .textSelection(.enabled)
        }
    }

    // MARK: Actions

    private func beginReplaceRead() {
        readKey = ""; readSecret = ""
        readPhase = .idle
        isReplacingRead = true
    }

    private func cancelReplaceRead() {
        readKey = ""; readSecret = ""
        readPhase = .idle
        isReplacingRead = false
    }

    private func beginReplaceTrade() {
        tradeKey = ""; tradeSecret = ""
        tradePhase = .idle
        isReplacingTrade = true
    }

    private func cancelReplaceTrade() {
        tradeKey = ""; tradeSecret = ""
        tradePhase = .idle
        isReplacingTrade = false
    }

    private func saveRead() async {
        readPhase = .working
        do {
            try await model.validateAndSaveRead(key: readKey, secret: readSecret)
            readKey = ""; readSecret = ""
            readPhase = .saved("Validated and saved.")
            isReplacingRead = false
        } catch {
            readPhase = .failed(error.localizedDescription)
        }
    }

    private func saveTrade() async {
        tradePhase = .working
        let result = await model.validateAndSaveTrade(key: tradeKey, secret: tradeSecret)
        tradeKey = ""; tradeSecret = ""
        tradePhase = result.succeeded ? .saved(result.output) : .failed(result.output)
        if result.succeeded { isReplacingTrade = false }
    }

    private func removeRead() async {
        do {
            try model.removeReadCredential()
            readPhase = .idle
        } catch {
            readPhase = .failed(error.localizedDescription)
        }
    }

    private func removeTrade() async {
        let result = await model.removeTradeCredential()
        tradePhase = result.succeeded ? .saved("Trading key removed.") : .failed(result.output)
    }
}
