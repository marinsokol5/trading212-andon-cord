import Foundation

/// A Trading 212 API environment. API keys are environment-specific.
public enum Trading212Environment: String, Codable, CaseIterable, Identifiable, Sendable {
    case live
    case demo

    public var id: String { rawValue }

    public var baseURL: URL {
        switch self {
        case .live: URL(string: "https://live.trading212.com")!
        case .demo: URL(string: "https://demo.trading212.com")!
        }
    }

    public var displayName: String {
        switch self {
        case .live: "Live"
        case .demo: "Demo"
        }
    }

    public var isRealMoney: Bool { self == .live }
}
