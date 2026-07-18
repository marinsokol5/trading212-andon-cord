import Foundation

public struct CurrentPortfolio: Codable, Equatable, Sendable {
    public let environment: Trading212Environment
    public let account: AccountIdentity
    public let accountValue: Decimal
    public let freeCash: Decimal
    public let sellablePositionsValue: Decimal
    public let unrealizedProfitLoss: Decimal?
    public let positions: [PortfolioPosition]
    public let capturedAt: Date

    public init(environment: Trading212Environment, account: AccountIdentity,
                accountValue: Decimal, freeCash: Decimal,
                sellablePositionsValue: Decimal,
                unrealizedProfitLoss: Decimal? = nil,
                positions: [PortfolioPosition],
                capturedAt: Date) {
        self.environment = environment
        self.account = account
        self.accountValue = accountValue
        self.freeCash = freeCash
        self.sellablePositionsValue = sellablePositionsValue
        self.unrealizedProfitLoss = unrealizedProfitLoss
        self.positions = positions
        self.capturedAt = capturedAt
    }

    public var accountID: String { account.id }
    public var currency: String { account.currency }
    public var currencyCode: String { account.currency }
    public var totalValue: Decimal { accountValue }
    public var asOf: Date { capturedAt }
}

public enum PortfolioBuilderError: Error, Equatable, Sendable, LocalizedError {
    case emptyAccountID
    case invalidCurrency
    case emptyTicker
    case duplicateTicker(String)
    case negativeQuantity(String)
    case sellableQuantityExceedsTotal(String)
    case missingAccountPrice(String)
    case walletCurrencyMismatch(ticker: String, expected: String, actual: String)

    public var errorDescription: String? {
        switch self {
        case .emptyAccountID: "The account summary did not contain an account identifier."
        case .invalidCurrency: "The account summary did not contain a valid currency."
        case .emptyTicker: "A position did not contain a ticker."
        case let .duplicateTicker(ticker): "The response contained duplicate ticker \(ticker)."
        case let .negativeQuantity(ticker): "Position \(ticker) contained a negative quantity."
        case let .sellableQuantityExceedsTotal(ticker):
            "Position \(ticker) reported more sellable shares than total shares."
        case let .missingAccountPrice(ticker):
            "Position \(ticker) has sellable shares but no account-currency price."
        case let .walletCurrencyMismatch(ticker, expected, actual):
            "Position \(ticker) wallet currency \(actual) does not match account currency \(expected)."
        }
    }
}

public enum CurrentPortfolioBuilder {
    public static func build(summary: AccountSummary,
                             positions apiPositions: [Trading212Position],
                             environment: Trading212Environment,
                             capturedAt: Date = Date()) throws -> CurrentPortfolio {
        guard !summary.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PortfolioBuilderError.emptyAccountID
        }
        guard summary.currency.count == 3 else { throw PortfolioBuilderError.invalidCurrency }

        var seen = Set<String>()
        var intermediate: [(Trading212Position, Decimal, Decimal)] = []
        var sellableTotal: Decimal = 0

        for position in apiPositions {
            let ticker = position.instrument.ticker.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !ticker.isEmpty else { throw PortfolioBuilderError.emptyTicker }
            guard seen.insert(ticker).inserted else {
                throw PortfolioBuilderError.duplicateTicker(ticker)
            }
            guard position.quantity >= 0, position.quantityAvailableForTrading >= 0,
                  position.quantityInPies >= 0 else {
                throw PortfolioBuilderError.negativeQuantity(ticker)
            }
            guard position.quantityAvailableForTrading <= position.quantity else {
                throw PortfolioBuilderError.sellableQuantityExceedsTotal(ticker)
            }
            if position.walletImpact.currency != summary.currency {
                throw PortfolioBuilderError.walletCurrencyMismatch(
                    ticker: ticker, expected: summary.currency,
                    actual: position.walletImpact.currency)
            }

            let accountPrice: Decimal
            if position.quantity > 0 {
                accountPrice = position.walletImpact.currentValue / position.quantity
            } else {
                accountPrice = 0
            }
            if position.quantityAvailableForTrading > 0, accountPrice <= 0 {
                throw PortfolioBuilderError.missingAccountPrice(ticker)
            }
            let sellableValue = position.quantityAvailableForTrading * accountPrice
            sellableTotal += sellableValue
            intermediate.append((position, accountPrice, sellableValue))
        }

        let positions = intermediate.map { position, accountPrice, sellableValue in
            PortfolioPosition(
                ticker: position.instrument.ticker.trimmingCharacters(in: .whitespacesAndNewlines),
                isin: position.instrument.isin,
                name: position.instrument.name,
                instrumentCurrency: position.instrument.currency,
                quantity: position.quantity,
                sellableQuantity: position.quantityAvailableForTrading,
                pieQuantity: position.quantityInPies,
                nativePrice: position.currentPrice,
                accountPricePerShare: accountPrice,
                sellableAccountValue: sellableValue,
                sellableWeight: sellableTotal > 0 ? sellableValue / sellableTotal : 0)
        }

        return CurrentPortfolio(
            environment: environment,
            account: summary.identity,
            accountValue: summary.totalValue,
            freeCash: summary.cash.availableToTrade,
            sellablePositionsValue: sellableTotal,
            unrealizedProfitLoss: summary.investments.unrealizedProfitLoss,
            positions: positions,
            capturedAt: capturedAt)
    }
}

/// Compact cached reading used by the menu bar.
public struct AccountSnapshot: Codable, Equatable, Sendable {
    public let totalValue: Decimal
    public let freeCash: Decimal
    public let sellablePositionsValue: Decimal
    public let currencyCode: String
    public let asOf: Date
    public let unrealizedProfitLoss: Decimal?

    public init(totalValue: Decimal, freeCash: Decimal = 0,
                sellablePositionsValue: Decimal = 0, currencyCode: String,
                asOf: Date, unrealizedProfitLoss: Decimal? = nil) {
        self.totalValue = totalValue
        self.freeCash = freeCash
        self.sellablePositionsValue = sellablePositionsValue
        self.currencyCode = currencyCode.uppercased()
        self.asOf = asOf
        self.unrealizedProfitLoss = unrealizedProfitLoss
    }

    public init(portfolio: CurrentPortfolio, unrealizedProfitLoss: Decimal? = nil) {
        self.init(totalValue: portfolio.accountValue, freeCash: portfolio.freeCash,
                  sellablePositionsValue: portfolio.sellablePositionsValue,
                  currencyCode: portfolio.currency, asOf: portfolio.capturedAt,
                  unrealizedProfitLoss: unrealizedProfitLoss ?? portfolio.unrealizedProfitLoss)
    }

    public var unrealizedPnL: Decimal? { unrealizedProfitLoss }

    public init(totalValue: Decimal, currencyCode: String, asOf: Date,
                unrealizedPnL: Decimal?) {
        self.init(totalValue: totalValue, currencyCode: currencyCode, asOf: asOf,
                  unrealizedProfitLoss: unrealizedPnL)
    }
}

/// Compatibility name used by the original menu-bar implementation.
public typealias PortfolioSnapshot = AccountSnapshot

public protocol PortfolioProvider: Sendable {
    func fetchPortfolio() async throws -> CurrentPortfolio
}

public extension PortfolioProvider {
    func fetchSnapshot() async throws -> AccountSnapshot {
        AccountSnapshot(portfolio: try await fetchPortfolio())
    }
}
