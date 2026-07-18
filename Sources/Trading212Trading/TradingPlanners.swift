import Foundation

public enum SellPlanner {
    /// Produces signed-negative market orders only for shares explicitly reported as sellable.
    public static func plan(positions: [SellablePosition]) throws -> SellPlan {
        var seen = Set<String>()
        var orders: [PlannedSell] = []
        var pies: [SkippedPiePosition] = []
        var total: Decimal = 0

        for position in positions {
            let ticker = position.ticker.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !ticker.isEmpty else { throw TradingValidationError.emptyTicker }
            guard seen.insert(ticker).inserted else {
                throw TradingValidationError.duplicateTicker(ticker)
            }

            if position.pieQuantity > 0 {
                pies.append(SkippedPiePosition(ticker: ticker, quantity: position.pieQuantity))
            }

            guard position.quantity >= 0 else {
                throw TradingValidationError.invalidSellQuantity(
                    ticker: ticker,
                    quantity: position.quantity
                )
            }
            guard position.quantity > 0 else { continue }

            let value = max(0, position.sellableAccountValue)
            total += value
            orders.append(
                PlannedSell(
                    ticker: ticker,
                    name: position.name,
                    quantity: position.quantity,
                    estimatedAccountValue: value
                )
            )
        }

        return SellPlan(
            orders: orders,
            piesExcluded: pies,
            estimatedAccountValue: total
        )
    }
}

public enum BuyPlanner {
    /// Allocates from snapshot weights using stale account-currency prices.
    /// All quantity rounding is downward so planning can never consume the cash buffer.
    public static func plan(
        allocations: [SnapshotAllocation],
        freeCash: Decimal,
        options: BuyPlanningOptions = .default
    ) throws -> BuyPlan {
        try options.validate()
        guard freeCash > 0 else {
            throw TradingValidationError.nonPositiveFreeCash(freeCash)
        }

        var seen = Set<String>()
        for allocation in allocations {
            let ticker = allocation.ticker.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !ticker.isEmpty else { throw TradingValidationError.emptyTicker }
            guard seen.insert(ticker).inserted else {
                throw TradingValidationError.duplicateTicker(ticker)
            }
        }

        // Never mix dimensionless weights and currency values. Use weights
        // only when the complete edited set has valid weights; otherwise fall
        // back to values for the complete set and renormalize once.
        let allHavePositiveWeights = !allocations.isEmpty
            && allocations.allSatisfy { $0.savedWeight > 0 }
        let bases = allocations.map { allocation -> Decimal in
            allHavePositiveWeights ? allocation.savedWeight : max(0, allocation.savedValue)
        }
        let basisTotal = bases.reduce(Decimal.zero, +)
        guard basisTotal > 0 else {
            throw TradingValidationError.noPositiveAllocationBasis
        }

        let investable = freeCash * options.cashFraction
        var orders: [PlannedBuy] = []
        var skipped: [SkippedBuy] = []
        var allocated: Decimal = 0

        for (index, allocation) in allocations.enumerated() {
            let ticker = allocation.ticker.trimmingCharacters(in: .whitespacesAndNewlines)
            let basis = bases[index]
            guard basis > 0 else {
                skipped.append(
                    SkippedBuy(ticker: ticker, reason: .nonPositiveWeightAndValue)
                )
                continue
            }

            let normalizedWeight = basis / basisTotal
            let target = normalizedWeight * investable
            guard allocation.savedAccountPrice > 0 else {
                skipped.append(SkippedBuy(ticker: ticker, reason: .nonPositivePrice))
                continue
            }
            guard target >= options.minimumOrderValue else {
                skipped.append(
                    SkippedBuy(
                        ticker: ticker,
                        reason: .belowMinimum(
                            target: target,
                            minimum: options.minimumOrderValue
                        )
                    )
                )
                continue
            }

            let quantity = DecimalMath.floor(
                target / allocation.savedAccountPrice,
                scale: options.quantityPrecision
            )
            guard quantity > 0 else {
                skipped.append(
                    SkippedBuy(
                        ticker: ticker,
                        reason: .quantityRoundedToZero(
                            precision: options.quantityPrecision
                        )
                    )
                )
                continue
            }

            allocated += quantity * allocation.savedAccountPrice
            orders.append(
                PlannedBuy(
                    ticker: ticker,
                    name: allocation.name,
                    normalizedWeight: normalizedWeight,
                    targetAccountValue: target,
                    staleAccountPrice: allocation.savedAccountPrice,
                    quantity: quantity
                )
            )
        }

        return BuyPlan(
            orders: orders,
            skipped: skipped,
            freeCash: freeCash,
            investableCash: investable,
            allocatedAtStalePrices: allocated,
            estimatedCashRemaining: max(0, freeCash - allocated)
        )
    }
}
