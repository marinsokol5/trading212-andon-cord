import Foundation
import XCTest
import Trading212Core
@testable import Trading212Trading

@MainActor
final class MarketOrderClientTests: XCTestCase {
    func testMarketOrderSendsBasicAuthAndSignedDecimalQuantity() async throws {
        let transport = ScriptedHTTPTransport([
            .response(status: 200, body: responseData(quantity: "-8"), headers: [
                "x-ratelimit-remaining": "49",
            ]),
        ])
        let client = try Trading212OrderClient(
            environment: .demo,
            credentials: .init(key: "myKey", secret: "mySecret"),
            variant: .production,
            transport: transport
        )
        let result = try await client.submit(.init(ticker: "AAPL_US_EQ", quantity: -8))

        XCTAssertEqual(result.response.id, "1")
        XCTAssertEqual(result.response.status, .filled)
        XCTAssertEqual(result.rateLimit.remaining, 49)
        let captured = await transport.capturedRequests()
        let request = try XCTUnwrap(captured.first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.url.path, "/api/v0/equity/orders/market")
        let authorization = request.headers.first {
            $0.key.caseInsensitiveCompare("Authorization") == .orderedSame
        }?.value
        XCTAssertEqual(
            authorization,
            "Basic " + Data("myKey:mySecret".utf8).base64EncodedString()
        )
        let body = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try XCTUnwrap(request.body)) as? [String: Any]
        )
        XCTAssertEqual(body["ticker"] as? String, "AAPL_US_EQ")
        XCTAssertEqual((body["quantity"] as? NSNumber)?.decimalValue, -8)
        XCTAssertEqual(body["extendedHours"] as? Bool, false)
    }

    func testExplicit429WaitsForFullResetThenSafelyRetries() async throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let transport = ScriptedHTTPTransport([
            .response(status: 429, body: Data(), headers: [
                "x-ratelimit-reset": "1120",
                "x-ratelimit-remaining": "0",
            ]),
            .response(status: 200, body: responseData(ticker: "A"), headers: [:]),
        ])
        let sleeper = RecordingSleeper()
        let client = try Trading212OrderClient(
            environment: .demo,
            credentials: .init(key: "k", secret: "s"),
            variant: .production,
            transport: transport,
            sleeper: sleeper,
            now: { now }
        )

        _ = try await client.submit(.init(ticker: "A", quantity: 1))
        let captured = await transport.capturedRequests()
        let durations = await sleeper.recordedDurations()
        XCTAssertEqual(captured.count, 2)
        XCTAssertEqual(durations, [121])
    }

    func testNetworkFailureIsAmbiguousAndNeverRetried() async throws {
        let transport = ScriptedHTTPTransport([.failure])
        let client = try Trading212OrderClient(
            environment: .demo,
            credentials: .init(key: "k", secret: "s"),
            variant: .production,
            transport: transport
        )
        do {
            _ = try await client.submit(.init(ticker: "A", quantity: -1))
            XCTFail("expected ambiguity")
        } catch let error as OrderSubmissionError {
            guard case .ambiguous(let message) = error else {
                return XCTFail("expected ambiguous, got \(error)")
            }
            XCTAssertTrue(message.contains("non-idempotent"))
        }
        let captured = await transport.capturedRequests()
        XCTAssertEqual(captured.count, 1)
    }

    func test408AndEvery5xxAreAmbiguousAndNeverRetried() async throws {
        for status in [408, 500, 503, 599] {
            let transport = ScriptedHTTPTransport([
                .response(status: status, body: Data(), headers: [:]),
            ])
            let client = try Trading212OrderClient(
                environment: .demo,
                credentials: .init(key: "k", secret: "s"),
                variant: .production,
                transport: transport
            )
            do {
                _ = try await client.submit(.init(ticker: "A", quantity: 1))
                XCTFail("HTTP \(status) should be ambiguous")
            } catch let error as OrderSubmissionError {
                guard case .ambiguous = error else {
                    return XCTFail("HTTP \(status) should be ambiguous")
                }
            }
            let captured = await transport.capturedRequests()
            XCTAssertEqual(captured.count, 1)
        }
    }

    func testUnreadableSuccessfulResponseIsAmbiguous() async throws {
        let transport = ScriptedHTTPTransport([
            .response(status: 200, body: Data("not json".utf8), headers: [:]),
        ])
        let client = try Trading212OrderClient(
            environment: .demo,
            credentials: .init(key: "k", secret: "s"),
            variant: .production,
            transport: transport
        )
        do {
            _ = try await client.submit(.init(ticker: "A", quantity: 1))
            XCTFail("expected ambiguity")
        } catch let error as OrderSubmissionError {
            guard case .ambiguous = error else { return XCTFail("wrong classification") }
        }
        let captured = await transport.capturedRequests()
        XCTAssertEqual(captured.count, 1)
    }

    func testSuccessfulResponseMissingStatusOrMismatchingRequestIsAmbiguous() async throws {
        let bodies = [
            Data(#"{"id":1,"ticker":"A","quantity":1,"side":"BUY"}"#.utf8),
            responseData(ticker: "OTHER"),
        ]
        for body in bodies {
            let transport = ScriptedHTTPTransport([
                .response(status: 200, body: body, headers: [:]),
            ])
            let client = try Trading212OrderClient(
                environment: .demo,
                credentials: .init(key: "k", secret: "s"),
                variant: .production,
                transport: transport
            )
            do {
                _ = try await client.submit(.init(ticker: "A", quantity: 1))
                XCTFail("malformed or mismatched success must be ambiguous")
            } catch let error as OrderSubmissionError {
                guard case .ambiguous = error else { return XCTFail("wrong classification") }
            }
            let captured = await transport.capturedRequests()
            XCTAssertEqual(captured.count, 1)
        }
    }

    func testDefinite4xxRejectionIsNotAmbiguousAndSecretsAreRedacted() async throws {
        let credentials = Trading212Credentials(key: "KEYSECRET", secret: "TOPSECRET")
        let transport = ScriptedHTTPTransport([
            .response(
                status: 422,
                body: Data("Authorization: \(credentials.authorizationHeaderValue) TOPSECRET KEYSECRET".utf8),
                headers: [:]
            ),
        ])
        let client = try Trading212OrderClient(
            environment: .demo,
            credentials: credentials,
            variant: .production,
            transport: transport
        )
        do {
            _ = try await client.submit(.init(ticker: "A", quantity: 1))
            XCTFail("expected rejection")
        } catch let error as OrderSubmissionError {
            guard case .definiteRejection(let status, let message, _) = error else {
                return XCTFail("wrong classification")
            }
            XCTAssertEqual(status, 422)
            XCTAssertFalse(message.contains("TOPSECRET"))
            XCTAssertFalse(message.contains("KEYSECRET"))
            XCTAssertFalse(message.contains(credentials.authorizationHeaderValue))
        }
    }

    func testUnauthorizedStopsBeforeSubmissionAndNeverLeaksSecret() async throws {
        let transport = ScriptedHTTPTransport([
            .response(status: 401, body: Data("secret".utf8), headers: [:]),
        ])
        let client = try Trading212OrderClient(
            environment: .demo,
            credentials: .init(key: "k", secret: "secret"),
            variant: .production,
            transport: transport
        )
        do {
            _ = try await client.submit(.init(ticker: "A", quantity: 1))
            XCTFail("expected auth failure")
        } catch let error as OrderSubmissionError {
            guard case .fatalBeforeSubmission(let message) = error else {
                return XCTFail("wrong classification")
            }
            XCTAssertFalse(message.contains("secret"))
        }
        let captured = await transport.capturedRequests()
        XCTAssertEqual(captured.count, 1)
    }

    func testDevelopmentVariantRejectsLiveBeforeTransport() async throws {
        let transport = ScriptedHTTPTransport([])
        XCTAssertThrowsError(try Trading212OrderClient(
            environment: .live,
            credentials: .init(key: "k", secret: "s"),
            variant: .development,
            transport: transport
        ))
        let captured = await transport.capturedRequests()
        XCTAssertEqual(captured.count, 0)
    }
}
