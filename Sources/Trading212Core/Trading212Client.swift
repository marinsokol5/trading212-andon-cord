import Foundation

public enum NetworkFailure: String, Codable, Equatable, Sendable {
    case offline
    case timedOut
    case connectionLost
    case cannotReachHost
    case cancelled
    case other
}

public enum Trading212APIError: Error, Equatable, Sendable, LocalizedError {
    case missingCredentials
    case liveEnvironmentDisabledInDevelopment
    case unauthorized
    case forbidden
    case rateLimited(RateLimitInfo)
    case invalidRequest(status: Int, message: String?)
    case server(status: Int, message: String?)
    case network(NetworkFailure)
    case invalidResponse
    case decoding(endpoint: String)
    case invalidPortfolio(PortfolioBuilderError)

    public var errorDescription: String? {
        switch self {
        case .missingCredentials: "Read credentials have not been configured."
        case .liveEnvironmentDisabledInDevelopment:
            "Development builds cannot connect to the Trading 212 Live environment."
        case .unauthorized: "Trading 212 rejected the credentials (HTTP 401)."
        case .forbidden: "The API key does not have permission for this operation (HTTP 403)."
        case let .rateLimited(info):
            if let delay = info.delay() { "Trading 212 rate limit reached; retry in \(Int(delay.rounded(.up))) seconds." }
            else { "Trading 212 rate limit reached (HTTP 429)." }
        case let .invalidRequest(status, message):
            message.map { "Trading 212 request failed (HTTP \(status)): \($0)" }
                ?? "Trading 212 request failed (HTTP \(status))."
        case let .server(status, message):
            message.map { "Trading 212 server error (HTTP \(status)): \($0)" }
                ?? "Trading 212 server error (HTTP \(status))."
        case let .network(failure):
            switch failure {
            case .offline: "No internet connection."
            case .timedOut: "Trading 212 took too long to respond. Try again."
            case .connectionLost: "The connection to Trading 212 was interrupted."
            case .cannotReachHost: "Couldn't reach Trading 212. Check your connection."
            case .cancelled: "The request was cancelled."
            case .other: "The network request failed."
            }
        case .invalidResponse: "Trading 212 returned a non-HTTP response."
        case let .decoding(endpoint): "Trading 212 returned an invalid response for \(endpoint)."
        case let .invalidPortfolio(error): error.localizedDescription
        }
    }
}

/// Read-only Trading 212 v0 client. It deliberately has no order endpoint.
public struct Trading212Client: PortfolioProvider, Sendable {
    public let environment: Trading212Environment
    private let credentials: Trading212Credentials
    private let transport: any HTTPTransport
    private let variant: AppVariant
    private let dateProvider: any DateProviding

    public init(environment: Trading212Environment,
                credentials: Trading212Credentials,
                transport: any HTTPTransport = URLSessionTransport(),
                variant: AppVariant = .current,
                dateProvider: any DateProviding = SystemDateProvider()) {
        self.environment = environment
        self.credentials = credentials
        self.transport = transport
        self.variant = variant
        self.dateProvider = dateProvider
    }

    public func accountSummary() async throws -> AccountSummary {
        try await get(AccountSummary.self, path: "api/v0/equity/account/summary")
    }

    /// Compatibility wrapper; does not call the retired `/account/info` path.
    public func accountInfo() async throws -> AccountInfo {
        let summary = try await accountSummary()
        return AccountInfo(id: summary.id, currencyCode: summary.currency)
    }

    /// Compatibility wrapper; does not call the retired `/account/cash` path.
    public func accountCash() async throws -> AccountCash {
        let summary = try await accountSummary()
        return AccountCash(
            free: summary.cash.availableToTrade,
            total: summary.totalValue,
            invested: summary.investments.currentValue,
            ppl: summary.investments.unrealizedProfitLoss,
            pieCash: summary.cash.inPies,
            blocked: summary.cash.reservedForOrders)
    }

    public func positions() async throws -> [Trading212Position] {
        let data = try await getData(path: "api/v0/equity/positions")
        do { return try JSONDecoder().decode(PositionResponse.self, from: data).positions }
        catch { throw Trading212APIError.decoding(endpoint: "positions") }
    }

    /// Fetches the two independent read endpoints concurrently and builds the
    /// one normalized account-currency portfolio used by all surfaces.
    public func fetchPortfolio() async throws -> CurrentPortfolio {
        async let summary = accountSummary()
        async let positions = positions()
        do {
            return try CurrentPortfolioBuilder.build(
                summary: try await summary,
                positions: try await positions,
                environment: environment,
                capturedAt: dateProvider.now())
        } catch let error as Trading212APIError {
            throw error
        } catch let error as PortfolioBuilderError {
            throw Trading212APIError.invalidPortfolio(error)
        }
    }

    public func fetchSnapshot() async throws -> AccountSnapshot {
        AccountSnapshot(portfolio: try await fetchPortfolio())
    }

    private func get<T: Decodable>(_ type: T.Type, path: String) async throws -> T {
        let data = try await getData(path: path)
        do { return try JSONDecoder().decode(type, from: data) }
        catch { throw Trading212APIError.decoding(endpoint: path.split(separator: "/").last.map(String.init) ?? path) }
    }

    private func getData(path: String) async throws -> Data {
        do { try variant.validate(environment: environment) }
        catch { throw Trading212APIError.liveEnvironmentDisabledInDevelopment }
        guard credentials.isComplete else { throw Trading212APIError.missingCredentials }

        var request = URLRequest(url: environment.baseURL.appending(path: path))
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(credentials.authorizationHeaderValue, forHTTPHeaderField: "Authorization")

        let data: Data
        let response: HTTPURLResponse
        do { (data, response) = try await transport.send(request) }
        catch let error as URLError { throw Trading212APIError.network(Self.map(error)) }
        catch is CancellationError { throw Trading212APIError.network(.cancelled) }
        catch is HTTPTransportError { throw Trading212APIError.invalidResponse }
        catch { throw Trading212APIError.network(.other) }

        switch response.statusCode {
        case 200..<300:
            return data
        case 401:
            throw Trading212APIError.unauthorized
        case 403:
            throw Trading212APIError.forbidden
        case 429:
            throw Trading212APIError.rateLimited(
                RateLimitInfo.parse(response, now: dateProvider.now()))
        case 408:
            throw Trading212APIError.network(.timedOut)
        case 500...599:
            throw Trading212APIError.server(
                status: response.statusCode,
                message: Self.safeErrorMessage(data, credentials: credentials))
        default:
            throw Trading212APIError.invalidRequest(
                status: response.statusCode,
                message: Self.safeErrorMessage(data, credentials: credentials))
        }
    }

    private static func safeErrorMessage(_ data: Data,
                                         credentials: Trading212Credentials) -> String? {
        guard !data.isEmpty else { return nil }
        if let payload = try? JSONDecoder().decode(APIErrorPayload.self, from: data),
           let raw = payload.message ?? payload.error ?? payload.code {
            return String(Redactor.redact(raw, credentials: [credentials]).prefix(300))
        }
        // Never surface arbitrary response bodies: successful payloads may
        // contain financial/account information and some gateways echo headers.
        return nil
    }

    private static func map(_ error: URLError) -> NetworkFailure {
        switch error.code {
        case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff: .offline
        case .timedOut: .timedOut
        case .networkConnectionLost: .connectionLost
        case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed: .cannotReachHost
        case .cancelled: .cancelled
        default: .other
        }
    }
}

private struct APIErrorPayload: Decodable {
    let message: String?
    let error: String?
    let code: String?

    private enum CodingKeys: String, CodingKey { case message, error, code }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        message = try? values.decode(String.self, forKey: .message)
        error = try? values.decode(String.self, forKey: .error)
        if let string = try? values.decode(String.self, forKey: .code) { code = string }
        else if let number = try? values.decode(Int.self, forKey: .code) { code = String(number) }
        else { code = nil }
    }
}

private struct PositionResponse: Decodable {
    let positions: [Trading212Position]

    private enum CodingKeys: String, CodingKey { case items, positions }

    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(),
           let array = try? single.decode([Trading212Position].self) {
            positions = array
            return
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        if let items = try values.decodeIfPresent([Trading212Position].self, forKey: .items) {
            positions = items
        } else {
            positions = try values.decode([Trading212Position].self, forKey: .positions)
        }
    }
}

/// Compatibility name used by the original app.
public typealias ProviderError = Trading212APIError
