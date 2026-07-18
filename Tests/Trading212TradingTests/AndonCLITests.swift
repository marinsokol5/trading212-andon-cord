import Foundation
import XCTest
import Trading212Core
import Trading212Trading
@testable import andon

@MainActor
final class AndonCLITests: XCTestCase {
    func testSellAllDryRunSubmitsZeroOrdersAndWritesNothing() async throws {
        let outputURL = URL(fileURLWithPath: "/virtual/pre-sale.json")
        let console = TestConsole()
        let readStore = CountingCredentialStore(read: .init(key: "read", secret: "read-secret"))
        let tradeStore = CountingCredentialStore(trading: .init(key: "trade", secret: "trade-secret"))
        let files = RecordingFileSystem()
        let transport = RoutingHTTPTransport(routes: [
            "/api/v0/equity/account/summary": [.init(body: accountSummaryData())],
            "/api/v0/equity/positions": [.init(body: positionsData())],
        ])
        let submitterFactoryCalls = ThreadSafeCounter()
        let journalFactoryCalls = ThreadSafeCounter()
        let workspacePrepareCalls = ThreadSafeCounter()
        let cli = makeCLI(
            console: console,
            readStore: readStore,
            tradeStore: tradeStore,
            files: files,
            transport: transport,
            journalFactoryCalls: journalFactoryCalls,
            submitterFactoryCalls: submitterFactoryCalls,
            workspacePrepareCalls: workspacePrepareCalls
        )

        let code = await cli.run(arguments: [
            "sell-all", "--dry-run", "--output", outputURL.path,
        ])

        XCTAssertEqual(code, .success)
        XCTAssertEqual(submitterFactoryCalls.count(), 0)
        XCTAssertEqual(journalFactoryCalls.count(), 0)
        XCTAssertEqual(workspacePrepareCalls.count(), 0)
        XCTAssertEqual(files.writes(), 0, "dry-run must not write snapshot, receipt, or audit")
        XCTAssertEqual(tradeStore.retrievalCount(.trading, .demo), 0)
        let requests = await transport.capturedRequests()
        XCTAssertEqual(requests.count, 2)
        XCTAssertTrue(requests.allSatisfy { $0.method == "GET" })
        XCTAssertTrue(console.outputText().contains("NONE submitted"))
        XCTAssertTrue(console.outputText().contains("qty -8"))
    }

    func testBuyAllDryRunSubmitsZeroOrdersAndWritesNothing() async throws {
        let inputURL = URL(fileURLWithPath: "/virtual/pre-sale.json")
        let snapshot = buySnapshot()
        let files = RecordingFileSystem(files: [
            inputURL: try TradingSnapshotCodec.encode(snapshot),
        ])
        let console = TestConsole()
        let readStore = CountingCredentialStore(read: .init(key: "read", secret: "read-secret"))
        let tradeStore = CountingCredentialStore(trading: .init(key: "trade", secret: "trade-secret"))
        let transport = RoutingHTTPTransport(routes: [
            "/api/v0/equity/account/summary": [.init(body: accountSummaryData())],
        ])
        let submitterFactoryCalls = ThreadSafeCounter()
        let journalFactoryCalls = ThreadSafeCounter()
        let workspacePrepareCalls = ThreadSafeCounter()
        let cli = makeCLI(
            console: console,
            readStore: readStore,
            tradeStore: tradeStore,
            files: files,
            transport: transport,
            journalFactoryCalls: journalFactoryCalls,
            submitterFactoryCalls: submitterFactoryCalls,
            workspacePrepareCalls: workspacePrepareCalls
        )

        let code = await cli.run(arguments: [
            "buy-all", "--dry-run", "--input", inputURL.path,
        ])

        XCTAssertEqual(code, .success)
        XCTAssertEqual(submitterFactoryCalls.count(), 0)
        XCTAssertEqual(journalFactoryCalls.count(), 0)
        XCTAssertEqual(workspacePrepareCalls.count(), 0)
        XCTAssertEqual(files.writes(), 0)
        XCTAssertEqual(tradeStore.retrievalCount(.trading, .demo), 0)
        let requests = await transport.capturedRequests()
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.method, "GET")
        XCTAssertTrue(console.outputText().contains("SAVED PRICES ARE STALE"))
        XCTAssertTrue(console.outputText().contains("NONE submitted"))
    }

    func testWrongConfirmationPhraseAbortsEvenInDemo() async throws {
        let console = TestConsole(prompts: ["yes"])
        let readStore = CountingCredentialStore(read: .init(key: "read", secret: "read-secret"))
        let tradeStore = CountingCredentialStore(trading: .init(key: "trade", secret: "trade-secret"))
        let files = RecordingFileSystem()
        let transport = RoutingHTTPTransport(routes: [
            "/api/v0/equity/account/summary": [.init(body: accountSummaryData())],
            "/api/v0/equity/positions": [.init(body: positionsData())],
        ])
        let submitterFactoryCalls = ThreadSafeCounter()
        let journalFactoryCalls = ThreadSafeCounter()
        let cli = makeCLI(
            console: console,
            readStore: readStore,
            tradeStore: tradeStore,
            files: files,
            transport: transport,
            journalFactoryCalls: journalFactoryCalls,
            submitterFactoryCalls: submitterFactoryCalls
        )

        let code = await cli.run(arguments: [
            "sell-all", "--output", "/virtual/demo.json",
        ])

        XCTAssertEqual(code, .aborted)
        XCTAssertEqual(files.writes(), 1, "pre-sale snapshot still precedes confirmation")
        XCTAssertEqual(tradeStore.retrievalCount(.trading, .demo), 0)
        XCTAssertEqual(submitterFactoryCalls.count(), 0)
        XCTAssertEqual(journalFactoryCalls.count(), 0)
        XCTAssertTrue(console.errorText().contains("SELL ALL"))
    }

    func testDemoRefusesConfirmationWithoutControllingTerminal() async throws {
        let console = TestConsole(
            prompts: ["SELL ALL"],
            hasControllingTTY: false
        )
        let readStore = CountingCredentialStore(read: .init(key: "read", secret: "read-secret"))
        let tradeStore = CountingCredentialStore(trading: .init(key: "trade", secret: "trade-secret"))
        let files = RecordingFileSystem()
        let cli = makeCLI(
            console: console,
            readStore: readStore,
            tradeStore: tradeStore,
            files: files,
            transport: RoutingHTTPTransport(routes: [
                "/api/v0/equity/account/summary": [.init(body: accountSummaryData())],
                "/api/v0/equity/positions": [.init(body: positionsData())],
            ]),
            journalFactoryCalls: ThreadSafeCounter(),
            submitterFactoryCalls: ThreadSafeCounter()
        )

        let code = await cli.run(arguments: [
            "sell-all", "--output", "/virtual/demo-no-tty.json",
        ])
        XCTAssertEqual(code, .aborted)
        XCTAssertEqual(files.writes(), 1, "snapshot still precedes confirmation")
        XCTAssertEqual(tradeStore.retrievalCount(.trading, .demo), 0)
        XCTAssertTrue(console.errorText().contains("controlling terminal"))
    }

    func testDevelopmentBuildAlwaysTargetsDemoHost() async throws {
        let console = TestConsole()
        let readStore = CountingCredentialStore(read: .init(key: "read", secret: "secret"))
        let transport = RoutingHTTPTransport(routes: [
            "/api/v0/equity/account/summary": [.init(body: accountSummaryData())],
        ])
        let cli = makeCLI(
            variant: .development,
            console: console,
            readStore: readStore,
            tradeStore: CountingCredentialStore(),
            files: RecordingFileSystem(),
            transport: transport,
            journalFactoryCalls: ThreadSafeCounter(),
            submitterFactoryCalls: ThreadSafeCounter()
        )

        let code = await cli.run(arguments: ["account"])
        XCTAssertEqual(code, .success)
        XCTAssertEqual(readStore.retrievalCount(.read, .live), 0)
        let requests = await transport.capturedRequests()
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.url.host(), "demo.trading212.com")
        XCTAssertTrue(console.outputText().contains("DEMO"))
    }

    #if ANDON_PROD
    func testProductionBuildAlwaysTargetsLiveHost() async throws {
        let console = TestConsole()
        let readStore = CountingCredentialStore(
            read: .init(key: "read", secret: "secret"),
            environment: .live
        )
        let transport = RoutingHTTPTransport(routes: [
            "/api/v0/equity/account/summary": [.init(body: accountSummaryData())],
        ])
        let cli = makeCLI(
            variant: .production,
            console: console,
            readStore: readStore,
            tradeStore: CountingCredentialStore(environment: .live),
            files: RecordingFileSystem(),
            transport: transport,
            journalFactoryCalls: ThreadSafeCounter(),
            submitterFactoryCalls: ThreadSafeCounter()
        )

        let code = await cli.run(arguments: ["account"])
        XCTAssertEqual(code, .success)
        XCTAssertEqual(readStore.retrievalCount(.read, .demo), 0)
        let requests = await transport.capturedRequests()
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.url.host(), "live.trading212.com")
        XCTAssertTrue(console.outputText().contains("LIVE"))
    }
    #endif

    func testCredentialStatusJSONIsStableAndDoesNotRetrieveTradeSecret() async throws {
        let console = TestConsole()
        let readStore = CountingCredentialStore(read: .init(key: "r", secret: "s"))
        let tradeStore = CountingCredentialStore(trading: .init(key: "t", secret: "u"))
        let cli = makeCLI(
            console: console,
            readStore: readStore,
            tradeStore: tradeStore,
            files: RecordingFileSystem(),
            transport: RoutingHTTPTransport(routes: [:]),
            journalFactoryCalls: ThreadSafeCounter(),
            submitterFactoryCalls: ThreadSafeCounter()
        )

        let code = await cli.run(arguments: [
            "credentials", "status", "--json",
        ])
        XCTAssertEqual(code, .success)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(console.outputText().utf8)) as? [String: Bool]
        )
        XCTAssertEqual(object, ["readConfigured": true, "tradingConfigured": true])
        XCTAssertEqual(tradeStore.retrievalCount(.trading, .demo), 0)
    }

    func testSetTradingRefusesAccountMismatchWithoutSavingOrLeakingSecret() async throws {
        let secret = "NEVER-PRINT-THIS"
        let console = TestConsole(inputData: try JSONEncoder().encode(
            Trading212Credentials(key: "trade", secret: secret)
        ))
        let readStore = CountingCredentialStore(read: .init(key: "read", secret: "read-secret"))
        let tradeStore = CountingCredentialStore()
        let transport = RoutingHTTPTransport(routes: [
            "/api/v0/equity/account/summary": [
                .init(body: accountSummaryData(id: "account-1")),
                .init(body: accountSummaryData(id: "account-2")),
            ],
        ])
        let cli = makeCLI(
            console: console,
            readStore: readStore,
            tradeStore: tradeStore,
            files: RecordingFileSystem(),
            transport: transport,
            journalFactoryCalls: ThreadSafeCounter(),
            submitterFactoryCalls: ThreadSafeCounter()
        )

        let code = await cli.run(arguments: [
            "credentials", "set-trading", "--stdin-json",
        ])
        XCTAssertEqual(code, .authenticationOrAccountMismatch)
        XCTAssertEqual(tradeStore.setCount, 0)
        XCTAssertFalse(console.outputText().contains(secret))
        XCTAssertFalse(console.errorText().contains(secret))
    }

    func testIdempotentSummaryReadRetries429AndHonorsReset() async throws {
        let console = TestConsole()
        let sleeper = RecordingSleeper()
        let transport = RoutingHTTPTransport(routes: [
            "/api/v0/equity/account/summary": [
                .init(status: 429, body: Data(), headers: ["x-ratelimit-reset": "10"]),
                .init(body: accountSummaryData()),
            ],
        ])
        let cli = makeCLI(
            console: console,
            readStore: CountingCredentialStore(read: .init(key: "r", secret: "s")),
            tradeStore: CountingCredentialStore(),
            files: RecordingFileSystem(),
            transport: transport,
            sleeper: sleeper,
            now: { Date(timeIntervalSince1970: 0) },
            journalFactoryCalls: ThreadSafeCounter(),
            submitterFactoryCalls: ThreadSafeCounter()
        )

        let code = await cli.run(arguments: ["account"])
        XCTAssertEqual(code, .success)
        let requests = await transport.capturedRequests()
        let durations = await sleeper.recordedDurations()
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(durations, [11])
    }

    // The default is the development variant: its fixed environment is Demo,
    // which stays valid in both plain and ANDON_PROD test compilations. A
    // `.production` CLI always targets Live and is exercised only under
    // ANDON_PROD, where the compile-unit guard permits it.
    private func makeCLI(
        variant: AppVariant = .development,
        console: TestConsole,
        readStore: CountingCredentialStore,
        tradeStore: CountingCredentialStore,
        files: RecordingFileSystem,
        transport: RoutingHTTPTransport,
        sleeper: any TradingSleeper = RecordingSleeper(),
        now: @escaping @Sendable () -> Date = { Date(timeIntervalSince1970: 100) },
        journalFactoryCalls: ThreadSafeCounter,
        submitterFactoryCalls: ThreadSafeCounter,
        workspacePrepareCalls: ThreadSafeCounter = ThreadSafeCounter()
    ) -> AndonCLI {
        AndonCLI(
            variant: variant,
            workspace: Workspace(rootURL: URL(fileURLWithPath: "/virtual/workspace")),
            console: console,
            readCredentialStore: readStore,
            tradingCredentialStore: tradeStore,
            metadataStore: TestMetadataStore(),
            transport: transport,
            snapshotStore: TradingSnapshotStore(fileSystem: files),
            sleeper: sleeper,
            now: now,
            makeJournal: { _, _ in
                journalFactoryCalls.increment()
                return RecordingJournal()
            },
            makeSubmitter: { _, _ in
                submitterFactoryCalls.increment()
                return ScriptedSubmitter([])
            },
            prepareWorkspace: { workspacePrepareCalls.increment() }
        )
    }

    private func buySnapshot() -> TradingSnapshotDocument {
        TradingSnapshotDocument(
            kind: .preSale,
            capturedAt: Date(timeIntervalSince1970: 0),
            environment: .demo,
            account: .init(id: "account-1", currency: "GBP"),
            totals: .init(accountValue: 4_200, freeCash: 1_000, sellablePositionsValue: 3_200),
            positions: [
                .init(
                    ticker: "AAPL_US_EQ",
                    name: "Apple",
                    instrumentCurrency: "USD",
                    quantity: 8,
                    sellableQuantity: 8,
                    pieQuantity: 0,
                    nativePrice: 180,
                    accountPricePerShare: 150,
                    sellableAccountValue: 1_200,
                    sellableWeight: cliDecimal("0.375")
                ),
                .init(
                    ticker: "MSFT_US_EQ",
                    name: "Microsoft",
                    instrumentCurrency: "USD",
                    quantity: 5,
                    sellableQuantity: 5,
                    pieQuantity: 0,
                    nativePrice: 400,
                    accountPricePerShare: 400,
                    sellableAccountValue: 2_000,
                    sellableWeight: cliDecimal("0.625")
                ),
            ]
        )
    }
}

private func cliDecimal(_ string: String) -> Decimal {
    Decimal(string: string, locale: Locale(identifier: "en_US_POSIX"))!
}
