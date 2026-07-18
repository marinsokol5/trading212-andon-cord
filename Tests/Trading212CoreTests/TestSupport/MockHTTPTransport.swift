import Foundation
@testable import Trading212Core

final class MockHTTPTransport: HTTPTransport, @unchecked Sendable {
    enum Outcome: @unchecked Sendable {
        case response(status: Int, body: String, headers: [String: String] = [:])
        case failure(Error)
    }

    private let lock = NSLock()
    private let outcomes: [String: Outcome]
    private var recorded: [URLRequest] = []

    init(_ outcomes: [String: Outcome]) { self.outcomes = outcomes }

    var requests: [URLRequest] { lock.withLock { recorded } }
    var requestCount: Int { lock.withLock { recorded.count } }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.withLock { recorded.append(request) }
        let path = request.url?.path ?? ""
        guard let outcome = outcomes.first(where: { path.hasSuffix($0.key) })?.value else {
            return response(request: request, status: 404, body: #"{"message":"missing mock"}"#)
        }
        switch outcome {
        case let .failure(error): throw error
        case let .response(status, body, headers):
            return response(request: request, status: status, body: body, headers: headers)
        }
    }

    private func response(request: URLRequest, status: Int, body: String,
                          headers: [String: String] = [:]) -> (Data, HTTPURLResponse) {
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status,
            httpVersion: "HTTP/1.1", headerFields: headers)!
        return (Data(body.utf8), response)
    }
}

final class StubPortfolioProvider: PortfolioProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var results: [Result<CurrentPortfolio, Trading212APIError>]
    private var index = 0

    init(_ results: [Result<CurrentPortfolio, Trading212APIError>]) {
        precondition(!results.isEmpty)
        self.results = results
    }

    var callCount: Int { lock.withLock { index } }

    func fetchPortfolio() async throws -> CurrentPortfolio {
        try lock.withLock {
            let result = results[min(index, results.count - 1)]
            index += 1
            return try result.get()
        }
    }
}
