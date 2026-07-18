import Foundation

public struct RateLimitInfo: Codable, Equatable, Sendable {
    public let limit: Int?
    public let remaining: Int?
    public let period: TimeInterval?
    public let resetAt: Date?
    public let used: Int?
    public let retryAfter: TimeInterval?

    public init(limit: Int? = nil, remaining: Int? = nil,
                period: TimeInterval? = nil, resetAt: Date? = nil,
                used: Int? = nil, retryAfter: TimeInterval? = nil) {
        self.limit = limit
        self.remaining = remaining
        self.period = period
        self.resetAt = resetAt
        self.used = used
        self.retryAfter = retryAfter
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

    public static func parse(_ response: HTTPURLResponse, now: Date = Date()) -> RateLimitInfo {
        func value(_ name: String) -> String? {
            response.value(forHTTPHeaderField: name)?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        func integer(_ name: String) -> Int? { value(name).flatMap(Int.init) }
        func seconds(_ name: String) -> TimeInterval? { value(name).flatMap(TimeInterval.init) }

        let resetAt: Date? = value("x-ratelimit-reset").flatMap { raw in
            guard let epoch = TimeInterval(raw) else { return nil }
            // Be defensive if a server emits milliseconds.
            return Date(timeIntervalSince1970: epoch > 10_000_000_000 ? epoch / 1_000 : epoch)
        }

        let retryAfter: TimeInterval? = value("Retry-After").flatMap { raw in
            if let seconds = TimeInterval(raw) { return max(0, seconds) }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
            return formatter.date(from: raw).map { max(0, $0.timeIntervalSince(now)) }
        }

        return RateLimitInfo(
            limit: integer("x-ratelimit-limit"),
            remaining: integer("x-ratelimit-remaining"),
            period: seconds("x-ratelimit-period"),
            resetAt: resetAt,
            used: integer("x-ratelimit-used"),
            retryAfter: retryAfter)
    }
}
