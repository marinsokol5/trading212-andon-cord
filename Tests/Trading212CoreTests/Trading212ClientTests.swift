import Foundation
import XCTest
@testable import Trading212Core

@MainActor
final class Trading212ClientTests: XCTestCase {
    private let summaryJSON = #"""
    {
      "id": 12345,
      "currency": "EUR",
      "cash": {"availableToTrade":"100.25","inPies":2,"reservedForOrders":3},
      "investments": {
        "currentValue":"180.50","totalCost":150,
        "unrealizedProfitLoss":"30.50","realizedProfitLoss":1
      },
      "totalValue":"285.75"
    }
    """#

    private let positionsJSON = #"""
    [{
      "instrument":{"ticker":"AAPL_US_EQ","isin":"US0378331005","name":"Apple","currency":"USD"},
      "quantity":"2","quantityAvailableForTrading":"1.5","quantityInPies":"0.5",
      "averagePricePaid":"75.25","currentPrice":"100.125",
      "walletImpact":{"currency":"EUR","currentValue":"180.50","totalCost":"150","unrealizedProfitLoss":"30.50"}
    }]
    """#

    private func makeClient(_ outcomes: [String: MockHTTPTransport.Outcome],
                            environment: Trading212Environment = .demo,
                            variant: AppVariant = .production) -> (Trading212Client, MockHTTPTransport) {
        let transport = MockHTTPTransport(outcomes)
        return (Trading212Client(
            environment: environment,
            credentials: Trading212Credentials(key: "test-key", secret: "test-secret"),
            transport: transport,
            variant: variant,
            dateProvider: FixedDateProvider(Date(timeIntervalSince1970: 1_700_000_000))), transport)
    }

    func testSummaryUsesConsolidatedEndpointAndExactDecimals() async throws {
        let (client, transport) = makeClient([
            "account/summary": .response(status: 200, body: summaryJSON),
        ])
        let summary = try await client.accountSummary()
        XCTAssertEqual(summary.id, "12345")
        XCTAssertEqual(summary.currency, "EUR")
        XCTAssertEqual(summary.cash.availableToTrade, Decimal(string: "100.25"))
        XCTAssertEqual(summary.totalValue, Decimal(string: "285.75"))
        XCTAssertEqual(transport.requests.single?.url?.path, "/api/v0/equity/account/summary")
        XCTAssertFalse(transport.requests.contains { $0.url?.path.contains("/cash") == true })
        XCTAssertFalse(transport.requests.contains { $0.url?.path.contains("/info") == true })
    }

    func testCompatibilityInfoAndCashDeriveFromSummary() async throws {
        let (client, transport) = makeClient([
            "account/summary": .response(status: 200, body: summaryJSON),
        ])
        let info = try await client.accountInfo()
        let cash = try await client.accountCash()
        XCTAssertEqual(info, AccountInfo(id: "12345", currencyCode: "EUR"))
        XCTAssertEqual(cash.free, Decimal(string: "100.25"))
        XCTAssertEqual(cash.invested, Decimal(string: "180.50"))
        XCTAssertEqual(transport.requestCount, 2)
        XCTAssertTrue(transport.requests.allSatisfy { $0.url?.path.hasSuffix("account/summary") == true })
    }

    func testFetchPortfolioUsesSummaryAndPositionsAndExcludesPieQuantityFromValue() async throws {
        let (client, transport) = makeClient([
            "account/summary": .response(status: 200, body: summaryJSON),
            "equity/positions": .response(status: 200, body: positionsJSON),
        ])
        let portfolio = try await client.fetchPortfolio()
        XCTAssertEqual(portfolio.account, AccountIdentity(id: "12345", currency: "EUR"))
        XCTAssertEqual(portfolio.accountValue, Decimal(string: "285.75"))
        XCTAssertEqual(portfolio.freeCash, Decimal(string: "100.25"))
        XCTAssertEqual(portfolio.positions.count, 1)
        XCTAssertEqual(portfolio.positions[0].accountPricePerShare, Decimal(string: "90.25"))
        XCTAssertEqual(portfolio.positions[0].sellableAccountValue, Decimal(string: "135.375"))
        XCTAssertEqual(portfolio.sellablePositionsValue, Decimal(string: "135.375"))
        XCTAssertEqual(portfolio.positions[0].sellableWeight, 1)
        XCTAssertEqual(Set(transport.requests.compactMap(\.url?.path)), [
            "/api/v0/equity/account/summary", "/api/v0/equity/positions",
        ])
    }

    func testRequestUsesBasicAuthAndNeverPutsSecretsInURL() async throws {
        let (client, transport) = makeClient([
            "account/summary": .response(status: 200, body: summaryJSON),
        ])
        _ = try await client.accountSummary()
        let request = try XCTUnwrap(transport.requests.single)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"),
                       Trading212Credentials(key: "test-key", secret: "test-secret").authorizationHeaderValue)
        XCTAssertFalse(request.url!.absoluteString.contains("test-key"))
        XCTAssertFalse(request.url!.absoluteString.contains("test-secret"))
    }

    func testDevelopmentBuildRefusesLiveWithoutSendingRequest() async {
        let (client, transport) = makeClient([:], environment: .live, variant: .development)
        await XCTAssertThrowsErrorAsync(try await client.accountSummary()) {
            XCTAssertEqual($0 as? Trading212APIError, .liveEnvironmentDisabledInDevelopment)
        }
        XCTAssertEqual(transport.requestCount, 0)
    }

    func testStatusMappingAndRateLimitHeaders() async {
        let (unauthorized, _) = makeClient([
            "account/summary": .response(status: 401, body: #"{"message":"bad key"}"#),
        ])
        await XCTAssertThrowsErrorAsync(try await unauthorized.accountSummary()) {
            XCTAssertEqual($0 as? Trading212APIError, .unauthorized)
        }

        let (limited, _) = makeClient([
            "account/summary": .response(
                status: 429, body: "{}",
                headers: [
                    "x-ratelimit-limit": "1", "x-ratelimit-remaining": "0",
                    "x-ratelimit-reset": "1700000010", "Retry-After": "7",
                ]),
        ])
        await XCTAssertThrowsErrorAsync(try await limited.accountSummary()) { error in
            guard case let .rateLimited(info) = error as? Trading212APIError else {
                return XCTFail("Expected rateLimited, got \(error)")
            }
            XCTAssertEqual(info.limit, 1)
            XCTAssertEqual(info.remaining, 0)
            XCTAssertEqual(info.delay(at: Date(timeIntervalSince1970: 1_700_000_000)), 10)
        }
    }

    func testServerErrorDescriptionRedactsEchoedCredentials() async {
        let (client, _) = makeClient([
            "account/summary": .response(
                status: 500,
                body: #"{"message":"gateway rejected test-key:test-secret"}"#),
        ])
        await XCTAssertThrowsErrorAsync(try await client.accountSummary()) { error in
            let description = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            XCTAssertFalse(description.contains("test-key"))
            XCTAssertFalse(description.contains("test-secret"))
            XCTAssertTrue(description.contains(Redactor.marker))
        }
    }

    func testURLFailuresAreMappedWithoutUnderlyingSecretBearingDescription() async {
        let (client, _) = makeClient([
            "account/summary": .failure(URLError(.timedOut)),
        ])
        await XCTAssertThrowsErrorAsync(try await client.accountSummary()) {
            XCTAssertEqual($0 as? Trading212APIError, .network(.timedOut))
        }
    }

    func testPositionMissingExplicitSellableQuantityFailsClosed() async {
        let unsafe = positionsJSON.replacingOccurrences(
            of: ",\"quantityAvailableForTrading\":\"1.5\"",
            with: ""
        )
        let (client, _) = makeClient([
            "equity/positions": .response(status: 200, body: unsafe),
        ])
        await XCTAssertThrowsErrorAsync(try await client.positions()) {
            XCTAssertEqual($0 as? Trading212APIError, .decoding(endpoint: "positions"))
        }
    }
}

private extension Array {
    var single: Element? { count == 1 ? self[0] : nil }
}

@MainActor
private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ verify: (Error) -> Void = { _ in },
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected expression to throw", file: file, line: line)
    } catch {
        verify(error)
    }
}
