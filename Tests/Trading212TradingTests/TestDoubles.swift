import Foundation
import Trading212Core
import Trading212Trading

struct CapturedRequest: Equatable, Sendable {
    let url: URL
    let method: String
    let headers: [String: String]
    let body: Data?
}

actor ScriptedHTTPTransport: HTTPTransport {
    enum Step: Sendable {
        case response(status: Int, body: Data, headers: [String: String])
        case failure
    }

    private var steps: [Step]
    private(set) var requests: [CapturedRequest] = []

    init(_ steps: [Step]) {
        self.steps = steps
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(CapturedRequest(
            url: request.url!,
            method: request.httpMethod ?? "GET",
            headers: request.allHTTPHeaderFields ?? [:],
            body: request.httpBody
        ))
        guard !steps.isEmpty else { throw MockFailure.unexpectedCall }
        switch steps.removeFirst() {
        case .failure:
            throw MockFailure.network
        case .response(let status, let body, let headers):
            return (
                body,
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: status,
                    httpVersion: "HTTP/1.1",
                    headerFields: headers
                )!
            )
        }
    }

    func capturedRequests() -> [CapturedRequest] { requests }
}

enum MockFailure: Error, Sendable {
    case network
    case unexpectedCall
    case journal
}

actor RecordingSleeper: TradingSleeper {
    private(set) var durations: [TimeInterval] = []
    var shouldThrow = false

    func sleep(for seconds: TimeInterval) async throws {
        durations.append(seconds)
        if shouldThrow { throw CancellationError() }
    }

    func recordedDurations() -> [TimeInterval] { durations }
    func setShouldThrow(_ value: Bool) { shouldThrow = value }
}

actor ScriptedSubmitter: MarketOrderSubmitting {
    enum Step: Sendable {
        case response(MarketOrderSubmission)
        case error(OrderSubmissionError)
        case unknownError
    }

    private var steps: [Step]
    private(set) var requests: [MarketOrderRequest] = []

    init(_ steps: [Step]) { self.steps = steps }

    func submit(_ order: MarketOrderRequest) async throws -> MarketOrderSubmission {
        requests.append(order)
        guard !steps.isEmpty else { throw MockFailure.unexpectedCall }
        switch steps.removeFirst() {
        case .response(let response): return response
        case .error(let error): throw error
        case .unknownError: throw MockFailure.network
        }
    }

    func submittedRequests() -> [MarketOrderRequest] { requests }
}

actor RecordingJournal: TradeJournaling {
    private(set) var records: [(TradeReceipt, TradeAuditEvent)] = []
    private let failAtCall: Int?

    init(failAtCall: Int? = nil) { self.failAtCall = failAtCall }

    func record(receipt: TradeReceipt, event: TradeAuditEvent) async throws {
        if records.count == failAtCall { throw MockFailure.journal }
        records.append((receipt, event))
    }

    func allRecords() -> [(TradeReceipt, TradeAuditEvent)] { records }
}

func responseData(
    id: Int64 = 1,
    ticker: String = "AAPL_US_EQ",
    quantity: String = "1",
    status: String = "FILLED"
) -> Data {
    let side = (Decimal(string: quantity) ?? 0) < 0 ? "SELL" : "BUY"
    return Data("""
    {"id":\(id),"ticker":"\(ticker)","quantity":"\(quantity)","filledQuantity":"\(quantity)","status":"\(status)","side":"\(side)"}
    """.utf8)
}

func submission(
    id: String = "1",
    status: MarketOrderStatus = .filled,
    remaining: Int? = 49,
    resetAt: Date? = nil
) -> MarketOrderSubmission {
    MarketOrderSubmission(
        response: MarketOrderResponse(id: id, status: status),
        rateLimit: OrderRateLimit(remaining: remaining, resetAt: resetAt)
    )
}
