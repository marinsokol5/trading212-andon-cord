import Foundation
import Trading212Core

public extension TradingSnapshotDocument {
    init(portfolio: CurrentPortfolio, kind: Kind = .current) {
        self.init(
            kind: kind,
            capturedAt: portfolio.capturedAt,
            environment: portfolio.environment,
            account: .init(id: portfolio.account.id, currency: portfolio.account.currency),
            totals: .init(
                accountValue: portfolio.accountValue,
                freeCash: portfolio.freeCash,
                sellablePositionsValue: portfolio.sellablePositionsValue
            ),
            positions: portfolio.positions.sorted { $0.ticker < $1.ticker }.map { position in
                .init(
                    ticker: position.ticker,
                    isin: position.isin,
                    name: position.name,
                    instrumentCurrency: position.instrumentCurrency,
                    quantity: position.quantity,
                    sellableQuantity: position.sellableQuantity,
                    pieQuantity: position.pieQuantity,
                    nativePrice: position.nativePrice,
                    accountPricePerShare: position.accountPricePerShare,
                    sellableAccountValue: position.sellableAccountValue,
                    sellableWeight: position.sellableWeight
                )
            }
        )
    }
}

public extension CurrentPortfolio {
    var tradingSellablePositions: [SellablePosition] {
        positions.map { position in
            SellablePosition(
                ticker: position.ticker,
                name: position.name,
                quantity: position.sellableQuantity,
                pieQuantity: position.pieQuantity,
                accountPricePerShare: position.accountPricePerShare,
                sellableAccountValue: position.sellableAccountValue
            )
        }
    }
}
