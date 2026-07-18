import Foundation

public struct AccountIdentity: Codable, Equatable, Hashable, Sendable {
    public let id: String
    public let currency: String

    public init(id: String, currency: String) {
        self.id = id
        self.currency = currency.uppercased()
    }
}

public struct AccountCashSummary: Codable, Equatable, Sendable {
    public let availableToTrade: Decimal
    public let inPies: Decimal
    public let reservedForOrders: Decimal

    public init(availableToTrade: Decimal, inPies: Decimal = 0,
                reservedForOrders: Decimal = 0) {
        self.availableToTrade = availableToTrade
        self.inPies = inPies
        self.reservedForOrders = reservedForOrders
    }

    private enum CodingKeys: String, CodingKey {
        case availableToTrade, inPies, reservedForOrders
        case free, pieCash, blocked
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        if values.contains(.availableToTrade) {
            availableToTrade = try DecimalCoding.decode(values, forKey: .availableToTrade)
        } else {
            availableToTrade = try DecimalCoding.decode(values, forKey: .free)
        }
        if let value = try DecimalCoding.decodeIfPresent(values, forKey: .inPies) {
            inPies = value
        } else {
            inPies = try DecimalCoding.decodeIfPresent(values, forKey: .pieCash) ?? 0
        }
        if let value = try DecimalCoding.decodeIfPresent(values, forKey: .reservedForOrders) {
            reservedForOrders = value
        } else {
            reservedForOrders = try DecimalCoding.decodeIfPresent(values, forKey: .blocked) ?? 0
        }
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(availableToTrade, forKey: .availableToTrade)
        try values.encode(inPies, forKey: .inPies)
        try values.encode(reservedForOrders, forKey: .reservedForOrders)
    }
}

public struct AccountInvestmentsSummary: Codable, Equatable, Sendable {
    public let currentValue: Decimal
    public let totalCost: Decimal
    public let unrealizedProfitLoss: Decimal
    public let realizedProfitLoss: Decimal

    public init(currentValue: Decimal, totalCost: Decimal = 0,
                unrealizedProfitLoss: Decimal = 0, realizedProfitLoss: Decimal = 0) {
        self.currentValue = currentValue
        self.totalCost = totalCost
        self.unrealizedProfitLoss = unrealizedProfitLoss
        self.realizedProfitLoss = realizedProfitLoss
    }

    private enum CodingKeys: String, CodingKey {
        case currentValue, totalCost, unrealizedProfitLoss, realizedProfitLoss
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        currentValue = try DecimalCoding.decode(values, forKey: .currentValue)
        totalCost = try DecimalCoding.decodeIfPresent(values, forKey: .totalCost) ?? 0
        unrealizedProfitLoss = try DecimalCoding.decodeIfPresent(values, forKey: .unrealizedProfitLoss) ?? 0
        realizedProfitLoss = try DecimalCoding.decodeIfPresent(values, forKey: .realizedProfitLoss) ?? 0
    }
}

/// `GET /api/v0/equity/account/summary`.
public struct AccountSummary: Codable, Equatable, Sendable {
    public let id: String
    public let currency: String
    public let cash: AccountCashSummary
    public let investments: AccountInvestmentsSummary
    public let totalValue: Decimal

    public init(id: String, currency: String, cash: AccountCashSummary,
                investments: AccountInvestmentsSummary, totalValue: Decimal) {
        self.id = id
        self.currency = currency.uppercased()
        self.cash = cash
        self.investments = investments
        self.totalValue = totalValue
    }

    public var identity: AccountIdentity { AccountIdentity(id: id, currency: currency) }

    private enum CodingKeys: String, CodingKey {
        case id, currency, currencyCode, cash, investments, totalValue
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(LosslessString.self, forKey: .id).value
        if let value = try values.decodeIfPresent(String.self, forKey: .currency) {
            currency = value.uppercased()
        } else {
            currency = try values.decode(String.self, forKey: .currencyCode).uppercased()
        }
        cash = try values.decode(AccountCashSummary.self, forKey: .cash)
        investments = try values.decode(AccountInvestmentsSummary.self, forKey: .investments)
        totalValue = try DecimalCoding.decode(values, forKey: .totalValue)
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(currency, forKey: .currency)
        try values.encode(cash, forKey: .cash)
        try values.encode(investments, forKey: .investments)
        try values.encode(totalValue, forKey: .totalValue)
    }

    public var currencyCode: String { currency }
}

/// Compatibility projection for callers written against the old info endpoint.
public struct AccountInfo: Codable, Equatable, Sendable {
    public let id: String
    public let currencyCode: String

    public init(id: String, currencyCode: String) {
        self.id = id
        self.currencyCode = currencyCode.uppercased()
    }
}

/// Compatibility projection for callers written against the old cash endpoint.
public struct AccountCash: Codable, Equatable, Sendable {
    public let free: Decimal
    public let total: Decimal
    public let invested: Decimal
    public let ppl: Decimal
    public let pieCash: Decimal
    public let blocked: Decimal

    public init(free: Decimal, total: Decimal, invested: Decimal,
                ppl: Decimal = 0, pieCash: Decimal = 0, blocked: Decimal = 0) {
        self.free = free
        self.total = total
        self.invested = invested
        self.ppl = ppl
        self.pieCash = pieCash
        self.blocked = blocked
    }
}
