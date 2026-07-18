import Foundation

/// The complete HTTP operation used by both read and trading clients.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: HTTPTransport, Sendable {
    private let session: URLSession

    /// The production default rejects HTTP redirects. This is especially
    /// important for non-idempotent order POSTs: URLSession must never silently
    /// resubmit one to a redirected URL, and credentials must stay on the
    /// explicitly selected Trading 212 origin.
    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.waitsForConnectivity = false
        self.session = URLSession(
            configuration: configuration,
            delegate: RejectRedirectDelegate(),
            delegateQueue: nil)
    }

    /// Explicit session injection for offline URL-protocol tests or specialized
    /// embedding. Callers own that session's redirect policy.
    public init(session: URLSession) { self.session = session }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw HTTPTransportError.nonHTTPResponse
        }
        return (data, response)
    }
}

private final class RejectRedirectDelegate: NSObject, URLSessionTaskDelegate,
    @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

public enum HTTPTransportError: Error, Equatable, Sendable {
    case nonHTTPResponse
}

/// Compatibility name for early consumers of the design document.
public typealias HTTPFetching = HTTPTransport
