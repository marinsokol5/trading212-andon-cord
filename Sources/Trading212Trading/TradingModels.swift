import Foundation

public enum TradingAction: String, Codable, Sendable, CaseIterable {
    case sellAll
    case buyAll

    /// The exact phrase a real (non-dry-run) execution requires in every
    /// environment, Demo included, so the rehearsal UX matches Live exactly.
    public var confirmationPhrase: String {
        switch self {
        case .sellAll: "SELL ALL"
        case .buyAll: "BUY ALL"
        }
    }
}

public struct SellablePosition: Codable, Equatable, Sendable {
    public let ticker: String
    public let name: String
    public let quantity: Decimal
    public let pieQuantity: Decimal
    public let accountPricePerShare: Decimal
    public let sellableAccountValue: Decimal

    public init(
        ticker: String,
        name: String = "",
        quantity: Decimal,
        pieQuantity: Decimal = 0,
        accountPricePerShare: Decimal,
        sellableAccountValue: Decimal
    ) {
        self.ticker = ticker
        self.name = name
        self.quantity = quantity
        self.pieQuantity = pieQuantity
        self.accountPricePerShare = accountPricePerShare
        self.sellableAccountValue = sellableAccountValue
    }
}

public struct SnapshotAllocation: Codable, Equatable, Sendable {
    public let ticker: String
    public let name: String
    public let savedAccountPrice: Decimal
    public let savedValue: Decimal
    public let savedWeight: Decimal

    public init(
        ticker: String,
        name: String = "",
        savedAccountPrice: Decimal,
        savedValue: Decimal,
        savedWeight: Decimal
    ) {
        self.ticker = ticker
        self.name = name
        self.savedAccountPrice = savedAccountPrice
        self.savedValue = savedValue
        self.savedWeight = savedWeight
    }
}

public struct MarketOrderRequest: Codable, Equatable, Sendable {
    public let ticker: String
    public let quantity: Decimal
    public let extendedHours: Bool

    public init(ticker: String, quantity: Decimal, extendedHours: Bool = false) {
        self.ticker = ticker
        self.quantity = quantity
        self.extendedHours = extendedHours
    }

    public var side: OrderSide { quantity < 0 ? .sell : .buy }
}

public enum OrderSide: String, Codable, Sendable {
    case buy = "BUY"
    case sell = "SELL"
}

public struct PlannedSell: Codable, Equatable, Sendable {
    public let ticker: String
    public let name: String
    public let quantity: Decimal
    public let estimatedAccountValue: Decimal

    public init(ticker: String, name: String, quantity: Decimal, estimatedAccountValue: Decimal) {
        self.ticker = ticker
        self.name = name
        self.quantity = quantity
        self.estimatedAccountValue = estimatedAccountValue
    }

    public var request: MarketOrderRequest {
        MarketOrderRequest(ticker: ticker, quantity: -quantity)
    }
}

public struct SkippedPiePosition: Codable, Equatable, Sendable {
    public let ticker: String
    public let quantity: Decimal

    public init(ticker: String, quantity: Decimal) {
        self.ticker = ticker
        self.quantity = quantity
    }
}

public struct SellPlan: Codable, Equatable, Sendable {
    public let orders: [PlannedSell]
    public let piesExcluded: [SkippedPiePosition]
    public let estimatedAccountValue: Decimal

    public init(
        orders: [PlannedSell],
        piesExcluded: [SkippedPiePosition],
        estimatedAccountValue: Decimal
    ) {
        self.orders = orders
        self.piesExcluded = piesExcluded
        self.estimatedAccountValue = estimatedAccountValue
    }

    public var requests: [MarketOrderRequest] { orders.map(\.request) }
}

public struct BuyPlanningOptions: Codable, Equatable, Sendable {
    public static let `default` = BuyPlanningOptions()

    public let cashFraction: Decimal
    public let minimumOrderValue: Decimal
    public let quantityPrecision: Int

    public init(
        cashFraction: Decimal = Decimal(string: "0.99")!,
        minimumOrderValue: Decimal = 1,
        quantityPrecision: Int = 6
    ) {
        self.cashFraction = cashFraction
        self.minimumOrderValue = minimumOrderValue
        self.quantityPrecision = quantityPrecision
    }

    public func validate() throws {
        guard cashFraction > 0, cashFraction <= 1 else {
            throw TradingValidationError.invalidCashFraction(cashFraction)
        }
        guard minimumOrderValue >= 0 else {
            throw TradingValidationError.invalidMinimumOrder(minimumOrderValue)
        }
        guard (0...12).contains(quantityPrecision) else {
            throw TradingValidationError.invalidQuantityPrecision(quantityPrecision)
        }
    }
}

public struct PlannedBuy: Codable, Equatable, Sendable {
    public let ticker: String
    public let name: String
    public let normalizedWeight: Decimal
    public let targetAccountValue: Decimal
    public let staleAccountPrice: Decimal
    public let quantity: Decimal

    public init(
        ticker: String,
        name: String,
        normalizedWeight: Decimal,
        targetAccountValue: Decimal,
        staleAccountPrice: Decimal,
        quantity: Decimal
    ) {
        self.ticker = ticker
        self.name = name
        self.normalizedWeight = normalizedWeight
        self.targetAccountValue = targetAccountValue
        self.staleAccountPrice = staleAccountPrice
        self.quantity = quantity
    }

    public var request: MarketOrderRequest {
        MarketOrderRequest(ticker: ticker, quantity: quantity)
    }
}

public struct SkippedBuy: Codable, Equatable, Sendable {
    public enum Reason: Codable, Equatable, Sendable {
        case nonPositivePrice
        case belowMinimum(target: Decimal, minimum: Decimal)
        case quantityRoundedToZero(precision: Int)
        case nonPositiveWeightAndValue
    }

    public let ticker: String
    public let reason: Reason

    public init(ticker: String, reason: Reason) {
        self.ticker = ticker
        self.reason = reason
    }
}

public struct BuyPlan: Codable, Equatable, Sendable {
    public let orders: [PlannedBuy]
    public let skipped: [SkippedBuy]
    public let freeCash: Decimal
    public let investableCash: Decimal
    public let allocatedAtStalePrices: Decimal
    public let estimatedCashRemaining: Decimal

    public init(
        orders: [PlannedBuy],
        skipped: [SkippedBuy],
        freeCash: Decimal,
        investableCash: Decimal,
        allocatedAtStalePrices: Decimal,
        estimatedCashRemaining: Decimal
    ) {
        self.orders = orders
        self.skipped = skipped
        self.freeCash = freeCash
        self.investableCash = investableCash
        self.allocatedAtStalePrices = allocatedAtStalePrices
        self.estimatedCashRemaining = estimatedCashRemaining
    }

    public var requests: [MarketOrderRequest] { orders.map(\.request) }
}

public enum TradingValidationError: Error, Equatable, Sendable, CustomStringConvertible {
    case invalidCashFraction(Decimal)
    case invalidMinimumOrder(Decimal)
    case invalidQuantityPrecision(Int)
    case nonPositiveFreeCash(Decimal)
    case emptyTicker
    case duplicateTicker(String)
    case noPositiveAllocationBasis
    case invalidSellQuantity(ticker: String, quantity: Decimal)

    public var description: String {
        switch self {
        case .invalidCashFraction(let value):
            "cash-fraction must be greater than 0 and at most 1 (got \(value))"
        case .invalidMinimumOrder(let value):
            "min-order must be at least 0 (got \(value))"
        case .invalidQuantityPrecision(let value):
            "precision must be an integer from 0 through 12 (got \(value))"
        case .nonPositiveFreeCash(let value):
            "no free cash to invest (free cash is \(value))"
        case .emptyTicker:
            "snapshot contains an empty ticker"
        case .duplicateTicker(let ticker):
            "snapshot contains duplicate ticker \(ticker)"
        case .noPositiveAllocationBasis:
            "snapshot has no positive weights or values to allocate"
        case .invalidSellQuantity(let ticker, let quantity):
            "sellable quantity for \(ticker) must be positive (got \(quantity))"
        }
    }
}

public enum DecimalMath {
    /// Rounds a positive value toward zero at `scale`. Buy quantities always use this.
    public static func floor(_ value: Decimal, scale: Int) -> Decimal {
        guard value > 0, scale >= 0 else { return 0 }
        var input = value
        var output = Decimal()
        NSDecimalRound(&output, &input, scale, .down)
        return output > 0 ? output : 0
    }

    public static func string(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }
}
