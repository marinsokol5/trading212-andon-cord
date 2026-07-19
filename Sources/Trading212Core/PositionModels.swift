import Foundation

public struct Trading212Instrument: Codable, Equatable, Sendable {
    public let ticker: String
    public let isin: String?
    public let name: String
    public let currency: String

    public init(ticker: String, isin: String? = nil, name: String = "", currency: String = "") {
        self.ticker = ticker
        self.isin = isin
        self.name = name
        self.currency = currency.uppercased()
    }

    private enum CodingKeys: String, CodingKey { case ticker, isin, name, currency }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        ticker = try values.decode(String.self, forKey: .ticker)
        isin = try values.decodeIfPresent(String.self, forKey: .isin)
        name = try values.decodeIfPresent(String.self, forKey: .name) ?? ticker
        currency = try values.decode(String.self, forKey: .currency).uppercased()
    }
}

public struct Trading212WalletImpact: Codable, Equatable, Sendable {
    public let currency: String
    public let currentValue: Decimal
    public let totalCost: Decimal?
    public let unrealizedProfitLoss: Decimal?
    public let fxImpact: Decimal?

    public init(currency: String, currentValue: Decimal, totalCost: Decimal? = nil,
                unrealizedProfitLoss: Decimal? = nil, fxImpact: Decimal? = nil) {
        self.currency = currency.uppercased()
        self.currentValue = currentValue
        self.totalCost = totalCost
        self.unrealizedProfitLoss = unrealizedProfitLoss
        self.fxImpact = fxImpact
    }

    private enum CodingKeys: String, CodingKey {
        case currency, currentValue, totalCost, unrealizedProfitLoss, fxImpact
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        currency = try values.decode(String.self, forKey: .currency).uppercased()
        currentValue = try DecimalCoding.decode(values, forKey: .currentValue)
        totalCost = try DecimalCoding.decodeIfPresent(values, forKey: .totalCost)
        unrealizedProfitLoss = try DecimalCoding.decodeIfPresent(values, forKey: .unrealizedProfitLoss)
        fxImpact = try DecimalCoding.decodeIfPresent(values, forKey: .fxImpact)
    }
}

/// A position exactly as returned by the Trading 212 API, decoded with Decimal.
public struct Trading212Position: Codable, Equatable, Sendable {
    public let instrument: Trading212Instrument
    public let quantity: Decimal
    public let quantityAvailableForTrading: Decimal
    public let quantityInPies: Decimal
    public let averagePricePaid: Decimal?
    public let currentPrice: Decimal?
    public let walletImpact: Trading212WalletImpact

    public init(instrument: Trading212Instrument, quantity: Decimal,
                quantityAvailableForTrading: Decimal, quantityInPies: Decimal = 0,
                averagePricePaid: Decimal? = nil, currentPrice: Decimal? = nil,
                walletImpact: Trading212WalletImpact) {
        self.instrument = instrument
        self.quantity = quantity
        self.quantityAvailableForTrading = quantityAvailableForTrading
        self.quantityInPies = quantityInPies
        self.averagePricePaid = averagePricePaid
        self.currentPrice = currentPrice
        self.walletImpact = walletImpact
    }

    private enum CodingKeys: String, CodingKey {
        case instrument, quantity, quantityAvailableForTrading, quantityInPies
        case averagePricePaid, currentPrice, walletImpact
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        instrument = try values.decode(Trading212Instrument.self, forKey: .instrument)
        quantity = try DecimalCoding.decode(values, forKey: .quantity)
        // Sellability is a safety boundary. If the API ever omits or changes
        // this field, fail decoding instead of treating every owned share as
        // tradable (which could include pie-locked or reserved shares).
        quantityAvailableForTrading = try DecimalCoding.decode(
            values, forKey: .quantityAvailableForTrading)
        quantityInPies = try DecimalCoding.decode(values, forKey: .quantityInPies)
        averagePricePaid = try DecimalCoding.decodeIfPresent(values, forKey: .averagePricePaid)
        currentPrice = try DecimalCoding.decodeIfPresent(values, forKey: .currentPrice)
        walletImpact = try values.decode(Trading212WalletImpact.self, forKey: .walletImpact)
    }
}

/// Compatibility with clients that used the shorter name.
public typealias Position = Trading212Position

/// Position normalized into the account's currency for display and planning.
public struct PortfolioPosition: Codable, Equatable, Sendable, Identifiable {
    public var id: String { ticker }
    public let ticker: String
    public let isin: String?
    public let name: String
    public let instrumentCurrency: String
    public let quantity: Decimal
    public let sellableQuantity: Decimal
    public let pieQuantity: Decimal
    public let nativePrice: Decimal?
    public let accountPricePerShare: Decimal
    public let sellableAccountValue: Decimal
    public let sellableWeight: Decimal
    /// Unrealized P/L in the account currency, when the API reports it.
    /// Optional so cached portfolios written before this field decode cleanly.
    public let unrealizedProfitLoss: Decimal?

    public init(ticker: String, isin: String? = nil, name: String,
                instrumentCurrency: String, quantity: Decimal,
                sellableQuantity: Decimal, pieQuantity: Decimal,
                nativePrice: Decimal?, accountPricePerShare: Decimal,
                sellableAccountValue: Decimal, sellableWeight: Decimal,
                unrealizedProfitLoss: Decimal? = nil) {
        self.ticker = ticker
        self.isin = isin
        self.name = name
        self.instrumentCurrency = instrumentCurrency.uppercased()
        self.quantity = quantity
        self.sellableQuantity = sellableQuantity
        self.pieQuantity = pieQuantity
        self.nativePrice = nativePrice
        self.accountPricePerShare = accountPricePerShare
        self.sellableAccountValue = sellableAccountValue
        self.sellableWeight = sellableWeight
        self.unrealizedProfitLoss = unrealizedProfitLoss
    }
}
