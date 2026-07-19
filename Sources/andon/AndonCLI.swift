import Foundation
import Trading212Core
import Trading212Trading

enum CLIError: Error, Sendable, CustomStringConvertible {
    case inputTooLarge
    case invalidCredentialInput
    case missingReadCredential(Trading212Environment)
    case missingTradingCredential(Trading212Environment)
    case accountMismatch(read: String, trading: String)
    case snapshotCurrencyMismatch(expected: String, actual: String)
    case aborted
    case operation(String)

    var description: String {
        switch self {
        case .inputTooLarge:
            "credential input exceeds the 16 KiB limit"
        case .invalidCredentialInput:
            "expected one JSON object on stdin: {\"key\":\"…\",\"secret\":\"…\"}"
        case .missingReadCredential(let environment):
            "read credentials are not configured for \(environment.rawValue.uppercased())"
        case .missingTradingCredential(let environment):
            "trading credentials are not configured for \(environment.rawValue.uppercased())"
        case .accountMismatch(let read, let trading):
            "trading credential account \(trading) does not match read credential account \(read)"
        case .snapshotCurrencyMismatch(let expected, let actual):
            "snapshot currency is \(actual), but the current account currency is \(expected)"
        case .aborted:
            "aborted; no orders were submitted"
        case .operation(let message):
            message
        }
    }
}

struct AndonCLI: Sendable {
    static let version = "0.2.0"
    static let help = """
    t212 — a local Trading 212 portfolio companion and emergency cord

    USAGE
      t212 account [--json]
      t212 portfolio [--json|--output FILE]
      t212 snapshot view --input FILE [--json]
      t212 whoami | status [--json] | save [--out FILE] | view [--in FILE]
      t212 credentials set-trading [--stdin-json]
      t212 credentials status [--json]
      t212 credentials delete [--trading]
      t212 sell-all [--output FILE] [--dry-run]
      t212 buy-all --input FILE [--cash-fraction 0.99] [--min-order 1]
                    [--precision 6] [--dry-run]

    ENVIRONMENT
      The Trading 212 environment is fixed by the build: production builds always
      use Live (real money), development builds always use Demo. There is no
      runtime switch; use the key for the matching environment.

    SAFETY
      Real execution always requires typing the exact phrase SELL ALL or BUY ALL,
      in Demo as well as Live. The confirmation is read from a controlling
      terminal; piped stdin is refused and there is no noninteractive bypass.
      Legacy snapshots require a separate USE UNVERIFIED LEGACY SNAPSHOT acknowledgement.
      --dry-run performs reads and planning but writes no files and submits no orders.
      A market order is never auto-retried after timeout, connection loss, HTTP 408,
      HTTP 5xx, or an unreadable success response. Explicit HTTP 429 is the sole safe retry.
      Pie-locked shares are reported and excluded from every order.

    `credentials set-trading` reads exactly one JSON object from stdin. Secrets are
    never accepted in arguments or environment variables and are never printed.
    """

    private let variant: AppVariant
    private let workspace: Workspace
    private let console: any AndonConsole
    private let readCredentialStore: any CredentialStore
    private let tradingCredentialStore: any CredentialStore & TradeCredentialStatusProviding
    private let metadataStore: any AccountMetadataStoring
    private let transport: any HTTPTransport
    private let snapshotStore: TradingSnapshotStore
    private let sleeper: any TradingSleeper
    private let now: @Sendable () -> Date
    private let makeJournal: @Sendable (URL, URL) -> any TradeJournaling
    private let makeSubmitter: @Sendable (
        Trading212Environment,
        Trading212Credentials
    ) throws -> any MarketOrderSubmitting
    private let prepareWorkspace: @Sendable () throws -> Void

    init(
        variant: AppVariant = .current,
        workspace: Workspace? = nil,
        console: any AndonConsole = StandardAndonConsole(),
        transport: any HTTPTransport = URLSessionTransport(),
        sleeper: any TradingSleeper = TaskTradingSleeper(),
        now: @escaping @Sendable () -> Date = Date.init
    ) throws {
        let resolvedWorkspace: Workspace
        if let supplied = workspace {
            resolvedWorkspace = supplied
        } else {
            resolvedWorkspace = try Workspace(variant: variant)
        }
        self.variant = variant
        self.workspace = resolvedWorkspace
        self.console = console
        readCredentialStore = KeychainCredentialStore(variant: variant)
        tradingCredentialStore = CLITradingCredentialStore(
            configuration: TradingCredentialStoreConfiguration(variant: variant)
        )
        metadataStore = JSONAccountMetadataStore(workspace: resolvedWorkspace)
        self.transport = transport
        snapshotStore = TradingSnapshotStore()
        self.sleeper = sleeper
        self.now = now
        makeJournal = { receiptURL, auditURL in
            FileTradeJournal(receiptURL: receiptURL, auditURL: auditURL)
        }
        makeSubmitter = { environment, credentials in
            try Trading212OrderClient(
                environment: environment,
                credentials: credentials,
                variant: variant,
                transport: transport,
                sleeper: sleeper,
                now: now
            )
        }
        prepareWorkspace = { try resolvedWorkspace.prepare() }
    }

    /// Full dependency seam used by the offline CLI tests. No production
    /// command needs to expose or select these objects.
    init(
        variant: AppVariant,
        workspace: Workspace,
        console: any AndonConsole,
        readCredentialStore: any CredentialStore,
        tradingCredentialStore: any CredentialStore & TradeCredentialStatusProviding,
        metadataStore: any AccountMetadataStoring,
        transport: any HTTPTransport,
        snapshotStore: TradingSnapshotStore,
        sleeper: any TradingSleeper,
        now: @escaping @Sendable () -> Date,
        makeJournal: @escaping @Sendable (URL, URL) -> any TradeJournaling,
        makeSubmitter: @escaping @Sendable (
            Trading212Environment,
            Trading212Credentials
        ) throws -> any MarketOrderSubmitting,
        prepareWorkspace: @escaping @Sendable () throws -> Void = {}
    ) {
        self.variant = variant
        self.workspace = workspace
        self.console = console
        self.readCredentialStore = readCredentialStore
        self.tradingCredentialStore = tradingCredentialStore
        self.metadataStore = metadataStore
        self.transport = transport
        self.snapshotStore = snapshotStore
        self.sleeper = sleeper
        self.now = now
        self.makeJournal = makeJournal
        self.makeSubmitter = makeSubmitter
        self.prepareWorkspace = prepareWorkspace
    }

    func run(arguments: [String]) async -> AndonExitCode {
        do {
            let invocation = try AndonArgumentParser.parse(arguments)
            switch invocation.command {
            case .help:
                console.output(Self.help + "\n")
                return .success
            case .version:
                console.output(Self.version + "\n")
                return .success
            default:
                break
            }

            // The build variant is the only environment source. `validate` is
            // the same compile-unit guard the network clients apply and can
            // only trip if a dev-compiled binary somehow carried `.production`.
            let environment = variant.environment
            try variant.validate(environment: environment)
            return try await execute(invocation.command, environment: environment)
        } catch let error as AndonArgumentError {
            console.error("t212: \(error)\nRun `t212 --help` for usage.\n")
            return .usage
        } catch is AppVariantError {
            console.error("t212: development builds cannot use the LIVE environment\n")
            return .usage
        } catch let error as CLIError {
            console.error("t212: \(error)\n")
            return exitCode(for: error)
        } catch let error as TradingSnapshotError {
            console.error("t212: \(error)\n")
            switch error {
            case .environmentMismatch, .accountMismatch:
                return .authenticationOrAccountMismatch
            default:
                return .failure
            }
        } catch let error as TradingValidationError {
            console.error("t212: \(error)\n")
            return .usage
        } catch let error as Trading212APIError {
            console.error("t212: \(error.localizedDescription)\n")
            switch error {
            case .missingCredentials:
                return .missingCredentials
            case .unauthorized, .forbidden:
                return .authenticationOrAccountMismatch
            default:
                return .networkOrAPI
            }
        } catch let error as TradingCredentialStoreError {
            console.error("t212: \(error)\n")
            switch error {
            case .authenticationCancelled:
                return .aborted
            default:
                return .missingCredentials
            }
        } catch let error as TradeExecutionError {
            console.error("t212: \(error)\n")
            return .failure
        } catch {
            // Avoid interpolating unknown third-party errors: they can contain
            // response details. Every expected error path above is redacted.
            console.error("t212: operation failed\n")
            return .failure
        }
    }

    private func execute(
        _ command: AndonInvocation.Command,
        environment: Trading212Environment
    ) async throws -> AndonExitCode {
        switch command {
        case .help, .version:
            return .success
        case .account(let json):
            return try await account(environment: environment, json: json)
        case .portfolio(let json, let output):
            return try await portfolio(environment: environment, json: json, output: output)
        case .snapshotView(let input, let json):
            return try snapshotView(input: input, json: json)
        case .credentialsSetTrading(let stdinJSON):
            return try await setTradingCredential(environment: environment, stdinJSON: stdinJSON)
        case .credentialsStatus(let json):
            return try credentialStatus(environment: environment, json: json)
        case .credentialsDeleteTrading:
            return try deleteTradingCredential(environment: environment)
        case .sellAll(let output, let dryRun):
            return try await sellAll(environment: environment, output: output, dryRun: dryRun)
        case .buyAll(let input, let options, let dryRun):
            return try await buyAll(
                environment: environment,
                input: input,
                options: options,
                dryRun: dryRun
            )
        }
    }

    private func account(
        environment: Trading212Environment,
        json: Bool
    ) async throws -> AndonExitCode {
        let summary = try await readSummary(
            client: readClient(environment: environment)
        )
        if json {
            let object: [String: String] = [
                "environment": environment.rawValue,
                "baseURL": environment.baseURL.absoluteString,
                "accountID": summary.id,
                "currency": summary.currency,
            ]
            console.output(try encodedJSON(object))
        } else {
            console.output("""
            Environment: \(environment.rawValue.uppercased()) (\(environment.baseURL.absoluteString))
            Account id:  \(summary.id)
            Currency:    \(summary.currency)
            Read credentials validated.

            """)
        }
        return .success
    }

    private func portfolio(
        environment: Trading212Environment,
        json: Bool,
        output: URL?
    ) async throws -> AndonExitCode {
        let value = try await readPortfolio(
            client: readClient(environment: environment)
        )
        let snapshot = TradingSnapshotDocument(portfolio: value, kind: .current)
        if json {
            console.output(String(decoding: try TradingSnapshotCodec.encode(snapshot), as: UTF8.self))
        } else if let output {
            let backup = try snapshotStore.write(snapshot, to: output, backupExisting: true)
            if let backup { console.output("Backed up existing snapshot: \(backup.path)\n") }
            console.output("Snapshot written atomically (mode 0600): \(output.path)\n")
        } else {
            console.output(AndonRender.portfolio(value))
        }
        return .success
    }

    private func snapshotView(input: URL, json: Bool) throws -> AndonExitCode {
        let decoded = try snapshotStore.read(from: input)
        if json {
            guard decoded.source == .canonical else {
                throw CLIError.operation(
                    "refusing to convert a legacy snapshot to canonical JSON without a verified account id; "
                        + "use text view or create a fresh canonical snapshot"
                )
            }
            console.output(String(
                decoding: try TradingSnapshotCodec.encode(decoded.document),
                as: UTF8.self
            ))
        } else {
            console.output(AndonRender.snapshot(decoded, path: input.path))
        }
        return .success
    }

    private func setTradingCredential(
        environment: Trading212Environment,
        stdinJSON _: Bool
    ) async throws -> AndonExitCode {
        let data = try console.standardInput(limit: 16 * 1_024)
        let credentials: Trading212Credentials
        do {
            credentials = try JSONDecoder().decode(Trading212Credentials.self, from: data)
        } catch {
            throw CLIError.invalidCredentialInput
        }
        guard credentials.isComplete else { throw CLIError.invalidCredentialInput }

        // Validate both pairs against the same environment/account before the
        // privileged credential is saved. This makes account mismatch fail closed.
        let readAccountSummary = try await readSummary(
            client: readClient(environment: environment)
        )
        let tradingSummary = try await readSummary(client: Trading212Client(
            environment: environment,
            credentials: credentials,
            transport: transport,
            variant: variant
        ))
        guard readAccountSummary.id == tradingSummary.id,
              readAccountSummary.currency == tradingSummary.currency else {
            throw CLIError.accountMismatch(
                read: readAccountSummary.id,
                trading: tradingSummary.id
            )
        }

        try prepareWorkspace()
        try tradingCredentialStore.set(credentials, for: .trading, environment: environment)
        var metadata = try metadataStore.metadata(for: environment)
            ?? AccountMetadata(environment: environment)
        metadata.accountID = readAccountSummary.id
        metadata.currency = readAccountSummary.currency
        metadata.readCredentialConfigured = true
        metadata.tradeCredentialConfigured = true
        metadata.validatedAt = now()
        try metadataStore.save(metadata)
        console.output("Trading credential validated and saved for \(environment.rawValue.uppercased()).\n")
        return .success
    }

    private func credentialStatus(
        environment: Trading212Environment,
        json: Bool
    ) throws -> AndonExitCode {
        let readConfigured = readCredentialStore.contains(kind: .read, environment: environment)
        let tradingConfigured = try tradingCredentialStore
            .isTradeCredentialConfigured(for: environment)
        if json {
            struct Status: Encodable {
                let readConfigured: Bool
                let tradingConfigured: Bool
            }
            console.output(try encodedJSON(Status(
                readConfigured: readConfigured,
                tradingConfigured: tradingConfigured
            )))
        } else {
            console.output("""
            Environment: \(environment.rawValue.uppercased())
            Read credential:    \(readConfigured ? "configured" : "missing")
            Trading credential: \(tradingConfigured ? "configured" : "missing")

            """)
        }
        return .success
    }

    private func deleteTradingCredential(
        environment: Trading212Environment
    ) throws -> AndonExitCode {
        try prepareWorkspace()
        try tradingCredentialStore.delete(kind: .trading, environment: environment)
        var metadata = try metadataStore.metadata(for: environment)
            ?? AccountMetadata(environment: environment)
        metadata.tradeCredentialConfigured = false
        try metadataStore.save(metadata)
        console.output("Trading credential deleted for \(environment.rawValue.uppercased()).\n")
        return .success
    }

    private func sellAll(
        environment: Trading212Environment,
        output: URL?,
        dryRun: Bool
    ) async throws -> AndonExitCode {
        let portfolio = try await readPortfolio(
            client: readClient(environment: environment)
        )
        let plan = try SellPlanner.plan(positions: portfolio.tradingSellablePositions)

        console.output(AndonRender.environmentBanner(environment))
        console.output(AndonRender.sellPlan(plan, currency: portfolio.currency))
        guard !plan.orders.isEmpty else {
            console.output("Nothing sellable; no snapshot or order is needed.\n")
            return .success
        }

        if dryRun {
            console.output("\n--dry-run: snapshot/receipt/audit NOT written; intended orders (NONE submitted):\n")
            for request in plan.requests {
                console.output("  SELL \(request.ticker) qty \(AndonRender.quantity(request.quantity))\n")
            }
            return .success
        }

        try prepareWorkspace()
        // This write is intentionally before confirmation, trading-Keychain
        // retrieval, and the first market order. An existing plan is backed up.
        let snapshot = TradingSnapshotDocument(portfolio: portfolio, kind: .preSale)
        let snapshotURL = output ?? workspace.snapshotsDirectoryURL.appending(
            path: TradingFileNames.snapshot(
                kind: .preSale,
                environment: environment,
                at: now()
            )
        )
        let backup = try snapshotStore.write(snapshot, to: snapshotURL, backupExisting: true)
        if let backup { console.output("Backed up existing snapshot: \(backup.path)\n") }
        console.output("Pre-sale snapshot written (mode 0600): \(snapshotURL.path)\n")

        guard confirm(action: .sellAll) else {
            console.error("Aborted. No orders submitted; the pre-sale snapshot remains at \(snapshotURL.path).\n")
            return .aborted
        }

        let tradingCredentials = try loadTradingCredentials(environment: environment)
        try await validateTradingAccount(
            credentials: tradingCredentials,
            environment: environment,
            expectedID: portfolio.accountID,
            expectedCurrency: portfolio.currency
        )
        return try await executeOrders(
            action: .sellAll,
            environment: environment,
            accountID: portfolio.accountID,
            snapshotPath: snapshotURL.path,
            requests: plan.requests,
            credentials: tradingCredentials
        )
    }

    private func buyAll(
        environment: Trading212Environment,
        input: URL,
        options: BuyPlanningOptions,
        dryRun: Bool
    ) async throws -> AndonExitCode {
        let summary = try await readSummary(
            client: readClient(environment: environment)
        )
        let decoded = try snapshotStore.read(
            from: input,
            expectedEnvironment: environment,
            expectedAccountID: summary.id
        )
        guard decoded.document.account.currency.uppercased() == summary.currency.uppercased() else {
            throw CLIError.snapshotCurrencyMismatch(
                expected: summary.currency,
                actual: decoded.document.account.currency
            )
        }
        let plan = try BuyPlanner.plan(
            allocations: decoded.allocationsForBuy(),
            freeCash: summary.cash.availableToTrade,
            options: options
        )

        console.output(AndonRender.environmentBanner(environment))
        if decoded.source == .legacyAndonV1 {
            console.output("WARNING: legacy snapshot has no account id; identity could not be verified.\n\n")
        }
        console.output(AndonRender.buyPlan(plan, currency: summary.currency))
        guard !plan.orders.isEmpty else {
            console.output("No buy orders meet the plan constraints.\n")
            return .success
        }

        if dryRun {
            console.output("\n--dry-run: receipt/audit NOT written; intended orders (NONE submitted):\n")
            for request in plan.requests {
                console.output("  BUY  \(request.ticker) qty \(AndonRender.quantity(request.quantity))\n")
            }
            return .success
        }

        if decoded.source == .legacyAndonV1, !confirmUnverifiedLegacySnapshot() {
            console.error("Aborted. No orders submitted from the unverified legacy snapshot.\n")
            return .aborted
        }

        guard confirm(action: .buyAll) else {
            console.error("Aborted. No orders submitted.\n")
            return .aborted
        }

        let tradingCredentials = try loadTradingCredentials(environment: environment)
        try await validateTradingAccount(
            credentials: tradingCredentials,
            environment: environment,
            expectedID: summary.id,
            expectedCurrency: summary.currency
        )
        return try await executeOrders(
            action: .buyAll,
            environment: environment,
            accountID: summary.id,
            snapshotPath: input.path,
            requests: plan.requests,
            credentials: tradingCredentials
        )
    }

    private func executeOrders(
        action: TradingAction,
        environment: Trading212Environment,
        accountID: String,
        snapshotPath: String,
        requests: [MarketOrderRequest],
        credentials: Trading212Credentials
    ) async throws -> AndonExitCode {
        try prepareWorkspace()
        let receiptID = UUID()
        let receiptURL = workspace.receiptsDirectoryURL.appending(
            path: TradingFileNames.receipt(action: action, id: receiptID)
        )
        let journal = makeJournal(receiptURL, workspace.auditLogURL)
        let client = try makeSubmitter(environment, credentials)
        let executor = SequentialOrderExecutor(
            submitter: client,
            journal: journal,
            sleeper: sleeper,
            now: now
        )
        let outcome = try await executor.execute(
            action: action,
            environment: environment,
            accountID: accountID,
            snapshotPath: snapshotPath,
            requests: requests,
            receiptID: receiptID
        )
        console.output(AndonRender.execution(outcome))
        console.output("Receipt file: \(receiptURL.path)\n")
        switch outcome.receipt.status {
        case .completed:
            return .success
        case .stoppedAmbiguous:
            return .ambiguousOrder
        case .completedWithRejections, .stoppedBeforeSubmission, .running:
            return .failure
        }
    }

    private func readClient(environment: Trading212Environment) throws -> Trading212Client {
        guard let credentials = try readCredentialStore.credentials(
            for: .read,
            environment: environment
        ) else {
            throw CLIError.missingReadCredential(environment)
        }
        return Trading212Client(
            environment: environment,
            credentials: credentials,
            transport: transport,
            variant: variant
        )
    }

    private func loadTradingCredentials(
        environment: Trading212Environment
    ) throws -> Trading212Credentials {
        guard let credentials = try tradingCredentialStore.credentials(
            for: .trading,
            environment: environment
        ) else {
            throw CLIError.missingTradingCredential(environment)
        }
        return credentials
    }

    private func validateTradingAccount(
        credentials: Trading212Credentials,
        environment: Trading212Environment,
        expectedID: String,
        expectedCurrency: String
    ) async throws {
        let summary = try await readSummary(client: Trading212Client(
            environment: environment,
            credentials: credentials,
            transport: transport,
            variant: variant
        ))
        guard summary.id == expectedID, summary.currency == expectedCurrency else {
            throw CLIError.accountMismatch(read: expectedID, trading: summary.id)
        }
    }

    /// Identical in Demo and Live: the exact phrase, typed on a controlling
    /// terminal. Demo rehearses the Live workflow with nothing skipped.
    private func confirm(action: TradingAction) -> Bool {
        let phrase = action.confirmationPhrase
        guard let response = console.terminalConfirmation(
            "Type \"\(phrase)\" to proceed (anything else aborts): "
        ) else {
            console.error(
                "Confirmation requires an interactive controlling terminal; piped input is refused.\n"
            )
            return false
        }
        return response == phrase
    }

    private func confirmUnverifiedLegacySnapshot() -> Bool {
        let phrase = "USE UNVERIFIED LEGACY SNAPSHOT"
        let prompt = "Legacy files contain no account id. Type \"\(phrase)\" to accept this risk: "
        guard let response = console.terminalConfirmation(prompt) else {
            console.error(
                "Legacy acknowledgement requires an interactive controlling terminal.\n"
            )
            return false
        }
        return response == phrase
    }

    private func encodedJSON<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(value), as: UTF8.self) + "\n"
    }

    /// GET retries are safe and separate from the non-idempotent order path.
    private func readSummary(client: Trading212Client) async throws -> AccountSummary {
        try await retryIdempotentRead { try await client.accountSummary() }
    }

    private func readPortfolio(client: Trading212Client) async throws -> CurrentPortfolio {
        try await retryIdempotentRead { try await client.fetchPortfolio() }
    }

    private func retryIdempotentRead<Value: Sendable>(
        maximumRetries: Int = 5,
        operation: @Sendable () async throws -> Value
    ) async throws -> Value {
        for attempt in 0...maximumRetries {
            do {
                return try await operation()
            } catch Trading212APIError.rateLimited(let info) where attempt < maximumRetries {
                let delay = max(1, (info.delay(at: now()) ?? 1) + 1)
                try await sleeper.sleep(for: delay)
            }
        }
        throw CLIError.operation("read retry limit exhausted")
    }

    private func exitCode(for error: CLIError) -> AndonExitCode {
        switch error {
        case .missingReadCredential, .missingTradingCredential:
            .missingCredentials
        case .accountMismatch, .snapshotCurrencyMismatch:
            .authenticationOrAccountMismatch
        case .aborted:
            .aborted
        default:
            .failure
        }
    }
}
