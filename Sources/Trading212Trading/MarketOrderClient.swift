import Foundation
import Trading212Core

public struct OrderRateLimit: Codable, Equatable, Sendable {
    public let limit: Int?
    public let remaining: Int?
    public let resetAt: Date?
    public let retryAfter: TimeInterval?

    public init(
        limit: Int? = nil,
        remaining: Int? = nil,
        resetAt: Date? = nil,
        retryAfter: TimeInterval? = nil
    ) {
        self.limit = limit
        self.remaining = remaining
        self.resetAt = resetAt
        self.retryAfter = retryAfter
    }

    public init(response: HTTPURLResponse, now: Date = Date()) {
        let parsed = RateLimitInfo.parse(response, now: now)
        self.init(
            limit: parsed.limit,
            remaining: parsed.remaining,
            resetAt: parsed.resetAt,
            retryAfter: parsed.retryAfter
        )
    }

    public func delay(at date: Date = Date()) -> TimeInterval? {
        let resetDelay = resetAt.map { max(0, $0.timeIntervalSince(date)) }
        return switch (retryAfter, resetDelay) {
        case let (retry?, reset?): max(retry, reset)
        case let (retry?, nil): retry
        case let (nil, reset?): reset
        case (nil, nil): nil
        }
    }
}

public enum MarketOrderStatus: Equatable, Sendable, Codable, CustomStringConvertible {
    case local
    case unconfirmed
    case confirmed
    case new
    case cancelling
    case cancelled
    case partiallyFilled
    case filled
    case rejected
    case replacing
    case replaced
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue.uppercased() {
        case "LOCAL": self = .local
        case "UNCONFIRMED": self = .unconfirmed
        case "CONFIRMED": self = .confirmed
        case "NEW": self = .new
        case "CANCELLING": self = .cancelling
        case "CANCELLED", "CANCELED": self = .cancelled
        case "PARTIALLY_FILLED": self = .partiallyFilled
        case "FILLED": self = .filled
        case "REJECTED", "DECLINED", "FAILED": self = .rejected
        case "REPLACING": self = .replacing
        case "REPLACED": self = .replaced
        default: self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .local: "LOCAL"
        case .unconfirmed: "UNCONFIRMED"
        case .confirmed: "CONFIRMED"
        case .new: "NEW"
        case .cancelling: "CANCELLING"
        case .cancelled: "CANCELLED"
        case .partiallyFilled: "PARTIALLY_FILLED"
        case .filled: "FILLED"
        case .rejected: "REJECTED"
        case .replacing: "REPLACING"
        case .replaced: "REPLACED"
        case .unknown(let value): value
        }
    }

    public var description: String { rawValue }
    public var isDefiniteFailure: Bool { self == .cancelled || self == .rejected }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct MarketOrderResponse: Codable, Equatable, Sendable {
    public let id: String?
    public let ticker: String?
    public let quantity: Decimal?
    public let filledQuantity: Decimal?
    public let filledValue: Decimal?
    public let status: MarketOrderStatus
    public let side: String?
    public let currency: String?
    public let createdAt: Date?

    public init(
        id: String? = nil,
        ticker: String? = nil,
        quantity: Decimal? = nil,
        filledQuantity: Decimal? = nil,
        filledValue: Decimal? = nil,
        status: MarketOrderStatus,
        side: String? = nil,
        currency: String? = nil,
        createdAt: Date? = nil
    ) {
        self.id = id
        self.ticker = ticker
        self.quantity = quantity
        self.filledQuantity = filledQuantity
        self.filledValue = filledValue
        self.status = status
        self.side = side
        self.currency = currency
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, ticker, quantity, filledQuantity, filledValue, status, side
        case currency, createdAt
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        if let string = try? values.decode(String.self, forKey: .id), !string.isEmpty {
            id = string
        } else if let number = try? values.decode(Int64.self, forKey: .id) {
            id = String(number)
        } else {
            throw DecodingError.dataCorruptedError(
                forKey: .id,
                in: values,
                debugDescription: "market-order response is missing a valid order id"
            )
        }
        let decodedTicker = try values.decode(String.self, forKey: .ticker)
        guard !decodedTicker.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .ticker,
                in: values,
                debugDescription: "market-order response has an empty ticker"
            )
        }
        ticker = decodedTicker
        quantity = try values.decodeFlexibleDecimal(forKey: .quantity)
        filledQuantity = try values.decodeFlexibleDecimalIfPresent(forKey: .filledQuantity)
        filledValue = try values.decodeFlexibleDecimalIfPresent(forKey: .filledValue)
        status = try values.decode(MarketOrderStatus.self, forKey: .status)
        side = try values.decode(String.self, forKey: .side)
        currency = try values.decodeIfPresent(String.self, forKey: .currency)?.uppercased()
        if let rawDate = try values.decodeIfPresent(String.self, forKey: .createdAt) {
            guard let parsed = Self.parseISO8601(rawDate) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .createdAt,
                    in: values,
                    debugDescription: "market-order response has an invalid createdAt timestamp"
                )
            }
            createdAt = parsed
        } else {
            createdAt = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encodeIfPresent(id, forKey: .id)
        try values.encodeIfPresent(ticker, forKey: .ticker)
        try values.encodeIfPresent(quantity, forKey: .quantity)
        try values.encodeIfPresent(filledQuantity, forKey: .filledQuantity)
        try values.encodeIfPresent(filledValue, forKey: .filledValue)
        try values.encode(status, forKey: .status)
        try values.encodeIfPresent(side, forKey: .side)
        try values.encodeIfPresent(currency, forKey: .currency)
        try values.encodeIfPresent(createdAt.map(Self.iso8601String), forKey: .createdAt)
    }

    private static func parseISO8601(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        let regular = ISO8601DateFormatter()
        regular.formatOptions = [.withInternetDateTime]
        return regular.date(from: value)
    }

    private static func iso8601String(_ value: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: value)
    }
}

public struct MarketOrderSubmission: Equatable, Sendable {
    public let response: MarketOrderResponse
    public let rateLimit: OrderRateLimit

    public init(response: MarketOrderResponse, rateLimit: OrderRateLimit) {
        self.response = response
        self.rateLimit = rateLimit
    }
}

public protocol MarketOrderSubmitting: Sendable {
    func submit(_ order: MarketOrderRequest) async throws -> MarketOrderSubmission
}

public protocol TradingSleeper: Sendable {
    func sleep(for seconds: TimeInterval) async throws
}

public struct TaskTradingSleeper: TradingSleeper, Sendable {
    public init() {}

    public func sleep(for seconds: TimeInterval) async throws {
        guard seconds > 0 else { return }
        try await Task.sleep(for: .seconds(seconds))
    }
}

public enum OrderSubmissionError: Error, Equatable, Sendable, CustomStringConvertible {
    /// The broker definitely rejected the request before creating an order.
    case definiteRejection(status: Int, message: String, rateLimit: OrderRateLimit)
    /// No order was accepted, but execution should stop (auth, persistent rate limiting, cancellation).
    case fatalBeforeSubmission(message: String)
    /// An order might have reached the broker. It must never be retried, and no later order may be sent.
    case ambiguous(message: String)

    public var description: String {
        switch self {
        case .definiteRejection(let status, let message, _):
            "request rejected (HTTP \(status)): \(message)"
        case .fatalBeforeSubmission(let message):
            message
        case .ambiguous(let message):
            message
        }
    }
}

/// The only production component that knows the market-order endpoint.
/// The app target does not link this library.
public actor Trading212OrderClient: MarketOrderSubmitting {
    private let environment: Trading212Environment
    private let credentials: Trading212Credentials
    private let transport: any HTTPTransport
    private let sleeper: any TradingSleeper
    private let now: @Sendable () -> Date
    private let maximum429Retries: Int

    public init(
        environment: Trading212Environment,
        credentials: Trading212Credentials,
        variant: AppVariant = .current,
        transport: any HTTPTransport = URLSessionTransport(),
        sleeper: any TradingSleeper = TaskTradingSleeper(),
        now: @escaping @Sendable () -> Date = Date.init,
        maximum429Retries: Int = 5
    ) throws {
        try variant.validate(environment: environment)
        guard credentials.isComplete else {
            throw OrderSubmissionError.fatalBeforeSubmission(
                message: "trading credentials are incomplete"
            )
        }
        self.environment = environment
        self.credentials = credentials
        self.transport = transport
        self.sleeper = sleeper
        self.now = now
        self.maximum429Retries = max(0, maximum429Retries)
    }

    public func submit(_ order: MarketOrderRequest) async throws -> MarketOrderSubmission {
        guard !order.ticker.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              order.quantity != 0 else {
            throw OrderSubmissionError.fatalBeforeSubmission(
                message: "refusing to submit an empty ticker or zero quantity"
            )
        }

        let url = environment.baseURL.appending(path: "/api/v0/equity/orders/market")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(credentials.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            request.httpBody = try JSONEncoder().encode(order)
        } catch {
            throw OrderSubmissionError.fatalBeforeSubmission(
                message: "could not encode the market order"
            )
        }

        for attempt in 0...maximum429Retries {
            let data: Data
            let response: HTTPURLResponse
            do {
                (data, response) = try await transport.send(request)
            } catch {
                throw OrderSubmissionError.ambiguous(
                    message: "Network/timeout failure while submitting \(order.ticker). "
                        + "The market-order endpoint is non-idempotent: do not retry. "
                        + "Check the Trading 212 app before taking any further action."
                )
            }

            let rateLimit = OrderRateLimit(response: response, now: now())
            if response.statusCode == 429 {
                guard attempt < maximum429Retries else {
                    throw OrderSubmissionError.fatalBeforeSubmission(
                        message: "Trading 212 continued to reject the order with HTTP 429; no order was sent"
                    )
                }
                let wait = safeRateLimitWait(rateLimit: rateLimit)
                do {
                    try await sleeper.sleep(for: wait)
                } catch {
                    throw OrderSubmissionError.fatalBeforeSubmission(
                        message: "rate-limit wait was interrupted; the 429 response confirms no order was sent"
                    )
                }
                continue
            }

            if response.statusCode == 408 || response.statusCode >= 500 {
                throw OrderSubmissionError.ambiguous(
                    message: "Trading 212 returned HTTP \(response.statusCode) for \(order.ticker). "
                        + "The order may or may not have executed. Do not retry; verify broker state."
                )
            }

            if (300...399).contains(response.statusCode) {
                throw OrderSubmissionError.ambiguous(
                    message: "Trading 212 returned an HTTP redirect after the market-order POST. "
                        + "Trading 212 Andon Cord did not follow it, but cannot prove the original request had no effect. "
                        + "Do not retry; verify broker state."
                )
            }

            guard (200...299).contains(response.statusCode) else {
                let snippet = sanitizedSnippet(data)
                if response.statusCode == 401 || response.statusCode == 403 {
                    throw OrderSubmissionError.fatalBeforeSubmission(
                        message: "Trading 212 rejected the trading credential (HTTP \(response.statusCode)). "
                            + "No order was submitted."
                    )
                }
                throw OrderSubmissionError.definiteRejection(
                    status: response.statusCode,
                    message: snippet.isEmpty ? "broker rejected the request" : snippet,
                    rateLimit: rateLimit
                )
            }

            let decoded: MarketOrderResponse
            do {
                decoded = try JSONDecoder().decode(MarketOrderResponse.self, from: data)
            } catch {
                // A successful HTTP response means the broker accepted the request, but an
                // undecodable body prevents us from proving its state. Treat it as ambiguous.
                throw OrderSubmissionError.ambiguous(
                    message: "Trading 212 accepted the request (HTTP \(response.statusCode)) but returned "
                        + "an unreadable response. The order may have executed; do not retry."
                )
            }
            guard decoded.ticker == order.ticker,
                  let responseQuantity = decoded.quantity,
                  abs(responseQuantity) == abs(order.quantity),
                  decoded.side?.uppercased() == order.side.rawValue else {
                throw OrderSubmissionError.ambiguous(
                    message: "Trading 212 accepted the request but returned order details that do not "
                        + "match the submitted ticker, quantity, or side. Do not retry; verify broker state."
                )
            }
            if case .unknown(let rawStatus) = decoded.status {
                throw OrderSubmissionError.ambiguous(
                    message: "Trading 212 accepted the request but returned an unknown order status "
                        + "\(rawStatus). Do not retry; verify broker state."
                )
            }
            return MarketOrderSubmission(response: decoded, rateLimit: rateLimit)
        }

        throw OrderSubmissionError.fatalBeforeSubmission(
            message: "order submission ended before an order was sent"
        )
    }

    private func safeRateLimitWait(rateLimit: OrderRateLimit) -> TimeInterval {
        // Honor Retry-After and the full broker reset window, plus one second
        // for clock skew. A 429 proves this request was rejected before execution.
        max(1, (rateLimit.delay(at: now()) ?? 1) + 1)
    }

    private func sanitizedSnippet(_ data: Data) -> String {
        // Surface only allowlisted diagnostic fields. Never echo an arbitrary
        // gateway body, which may contain credentials or account data.
        guard let payload = try? JSONDecoder().decode(OrderErrorPayload.self, from: data),
              var text = payload.message ?? payload.error ?? payload.code else { return "" }
        text = Redactor.redact(text, credentials: [credentials])
        text = text.components(separatedBy: .controlCharacters).joined()
        return String(text.prefix(300))
    }
}

private struct OrderErrorPayload: Decodable {
    let message: String?
    let error: String?
    let code: String?

    private enum CodingKeys: String, CodingKey { case message, error, code }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        message = try? values.decode(String.self, forKey: .message)
        error = try? values.decode(String.self, forKey: .error)
        if let string = try? values.decode(String.self, forKey: .code) {
            code = string
        } else if let number = try? values.decode(Int.self, forKey: .code) {
            code = String(number)
        } else {
            code = nil
        }
    }
}

private extension KeyedDecodingContainer {
    func decodeFlexibleDecimal(forKey key: Key) throws -> Decimal {
        if let decimal = try? decode(Decimal.self, forKey: key), decimal.isFiniteNumber {
            return decimal
        }
        if let string = try? decode(String.self, forKey: key),
           let decimal = Decimal(string: string, locale: Locale(identifier: "en_US_POSIX")),
           decimal.isFiniteNumber {
            return decimal
        }
        throw DecodingError.dataCorruptedError(
            forKey: key,
            in: self,
            debugDescription: "expected a finite decimal number"
        )
    }

    func decodeFlexibleDecimalIfPresent(forKey key: Key) throws -> Decimal? {
        guard contains(key), try !decodeNil(forKey: key) else { return nil }
        return try decodeFlexibleDecimal(forKey: key)
    }
}

private extension Decimal {
    var isFiniteNumber: Bool { NSDecimalNumber(decimal: self) != .notANumber }
}
