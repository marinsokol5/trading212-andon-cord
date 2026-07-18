import Darwin
import Foundation
import Trading212Core
import Trading212Trading

protocol AndonConsole: Sendable {
    func output(_ text: String)
    func error(_ text: String)
    func prompt(_ text: String) -> String?
    func terminalConfirmation(_ text: String) -> String?
    func standardInput(limit: Int) throws -> Data
}

extension AndonConsole {
    /// Test/injected consoles can model an interactive terminal through their
    /// ordinary prompt implementation. The production console overrides this
    /// and requires a real controlling TTY.
    func terminalConfirmation(_ text: String) -> String? { prompt(text) }
}

struct StandardAndonConsole: AndonConsole, Sendable {
    func output(_ text: String) {
        FileHandle.standardOutput.write(Data(text.utf8))
    }

    func error(_ text: String) {
        FileHandle.standardError.write(Data(text.utf8))
    }

    func prompt(_ text: String) -> String? {
        error(text)
        return readLine(strippingNewline: true)
    }

    func terminalConfirmation(_ text: String) -> String? {
        guard let terminal = FileHandle(forUpdatingAtPath: "/dev/tty"),
              Darwin.isatty(terminal.fileDescriptor) == 1 else {
            return nil
        }
        terminal.write(Data(text.utf8))
        var input = Data()
        while input.count < 256 {
            let byte = terminal.readData(ofLength: 1)
            guard !byte.isEmpty else { return nil }
            if byte == Data([0x0A]) || byte == Data([0x0D]) { break }
            input.append(byte)
        }
        return String(data: input, encoding: .utf8)
    }

    func standardInput(limit: Int) throws -> Data {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        guard data.count <= limit else { throw CLIError.inputTooLarge }
        return data
    }
}

enum AndonRender {
    static func environmentBanner(_ environment: Trading212Environment) -> String {
        if environment == .live {
            return """

              ============================================================
              ==                LIVE — REAL MONEY                       ==
              ==      Market orders use actual Trading 212 funds.       ==
              ============================================================

            """
        }
        return """

              ------------------------------------------------------------
              --             DEMO — PRACTICE MONEY                     --
              ------------------------------------------------------------

            """
    }

    static func portfolio(_ portfolio: CurrentPortfolio) -> String {
        let currency = portfolio.currency
        var lines = [
            "Environment: \(portfolio.environment.rawValue.uppercased())",
            "Account:     \(portfolio.accountID)",
            "Currency:    \(currency)",
            "Account value:               \(money(portfolio.accountValue)) \(currency)",
            "Free cash:                   \(money(portfolio.freeCash)) \(currency)",
            "Sellable positions value:    \(money(portfolio.sellablePositionsValue)) \(currency)",
            "",
            row(["TICKER", "QTY", "SELLABLE", "PIE", "VALUE", "WEIGHT"], [18, 13, 13, 11, 15, 10]),
            String(repeating: "-", count: 80),
        ]
        for position in portfolio.positions.sorted(by: { $0.ticker < $1.ticker }) {
            lines.append(row([
                position.ticker,
                quantity(position.quantity),
                quantity(position.sellableQuantity),
                quantity(position.pieQuantity),
                money(position.sellableAccountValue),
                percent(position.sellableWeight),
            ], [18, 13, 13, 11, 15, 10]))
        }
        if portfolio.positions.isEmpty { lines.append("No open positions.") }

        let pies = portfolio.positions.filter { $0.pieQuantity > 0 }
        if !pies.isEmpty {
            lines.append(contentsOf: ["", "Pie-locked shares (excluded from all orders):"])
            lines.append(contentsOf: pies.sorted(by: { $0.ticker < $1.ticker }).map {
                "  \(pad($0.ticker, width: 18)) \(quantity($0.pieQuantity))"
            })
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func snapshot(_ decoded: DecodedTradingSnapshot, path: String) -> String {
        let snapshot = decoded.document
        var lines = [
            "Snapshot:    \(path)",
            "Format:      \(decoded.source.rawValue)",
            "Captured:    \(iso8601(snapshot.capturedAt))",
            "Environment: \(snapshot.environment.rawValue.uppercased())",
            "Account:     \(snapshot.account.id.isEmpty ? "unavailable (legacy file)" : snapshot.account.id)",
            "Currency:    \(snapshot.account.currency)",
            "Account value:            \(money(snapshot.totals.accountValue))",
            "Free cash at capture:      \(money(snapshot.totals.freeCash))",
            "Sellable positions value: \(money(snapshot.totals.sellablePositionsValue))",
            "",
            row(["TICKER", "SELLABLE", "PIE", "SAVED PRICE", "VALUE", "WEIGHT"], [18, 13, 11, 15, 15, 10]),
            String(repeating: "-", count: 82),
        ]
        for position in snapshot.positions.sorted(by: { $0.ticker < $1.ticker }) {
            lines.append(row([
                position.ticker,
                quantity(position.sellableQuantity),
                quantity(position.pieQuantity),
                money(position.accountPricePerShare),
                money(position.sellableAccountValue),
                percent(position.sellableWeight),
            ], [18, 13, 11, 15, 15, 10]))
        }
        if decoded.source == .legacyAndonV1 {
            lines += [
                "",
                "WARNING: legacy andon v1 has no account id; account identity cannot be verified.",
                "The source file was decoded in memory and was not rewritten.",
            ]
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func sellPlan(_ plan: SellPlan, currency: String) -> String {
        var lines = [
            "SELL ALL — every sellable position will be submitted as a market order.",
            "",
            row(["TICKER", "QUANTITY", "EST. VALUE"], [22, 18, 18]),
            String(repeating: "-", count: 58),
        ]
        lines += plan.orders.map {
            row([$0.ticker, quantity($0.quantity), money($0.estimatedAccountValue)], [22, 18, 18])
        }
        lines.append("")
        lines.append("Estimated sellable value: \(money(plan.estimatedAccountValue)) \(currency)")
        if !plan.piesExcluded.isEmpty {
            lines += ["", "Pie-locked shares excluded and left untouched:"]
            lines += plan.piesExcluded.map { "  \(pad($0.ticker, width: 22)) \(quantity($0.quantity))" }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func buyPlan(_ plan: BuyPlan, currency: String) -> String {
        var lines = [
            "BUY ALL — allocate by saved sellable weights.",
            "",
            "  WARNING: SAVED PRICES ARE STALE, NOT LIVE QUOTES.",
            "  Quantities are rounded down and include the configured cash buffer.",
            "",
            "Free cash: \(money(plan.freeCash)) \(currency)",
            "Investable: \(money(plan.investableCash)) \(currency)",
            "",
            row(["TICKER", "WEIGHT", "TARGET", "STALE PRICE", "QUANTITY"], [20, 10, 15, 15, 16]),
            String(repeating: "-", count: 76),
        ]
        lines += plan.orders.map {
            row([
                $0.ticker,
                percent($0.normalizedWeight),
                money($0.targetAccountValue),
                money($0.staleAccountPrice),
                quantity($0.quantity),
            ], [20, 10, 15, 15, 16])
        }
        if !plan.skipped.isEmpty {
            lines += ["", "Skipped:"]
            lines += plan.skipped.map { "  \(pad($0.ticker, width: 20)) \(skipReason($0.reason))" }
        }
        lines += [
            "",
            "Allocated at stale prices: \(money(plan.allocatedAtStalePrices)) \(currency)",
            "Estimated cash remaining:  \(money(plan.estimatedCashRemaining)) \(currency)",
        ]
        return lines.joined(separator: "\n") + "\n"
    }

    static func execution(_ outcome: TradeExecutionOutcome) -> String {
        var lines = ["", "Order results:"]
        for order in outcome.receipt.orders {
            let state: String
            switch order.state {
            case .notSent: state = "NOT SENT"
            case .submitting: state = "SUBMITTING — VERIFY IF INTERRUPTED"
            case .accepted(_, let status, _):
                if let filled = order.brokerResult?.filledQuantity,
                   let requested = order.brokerResult?.quantity {
                    state = "\(status.rawValue) — broker filled \(quantity(filled)) / \(quantity(requested))"
                } else {
                    state = status.rawValue
                }
            case .rejected(let message, _, _): state = "REJECTED — \(message)"
            case .notSubmitted(let message, _): state = "NOT SUBMITTED — \(message)"
            case .ambiguous: state = "AMBIGUOUS — CHECK THE TRADING 212 APP"
            }
            lines.append("  \(pad(order.ticker, width: 22)) qty \(pad(quantity(order.quantity), width: 15)) \(state)")
        }
        lines += [
            "",
            "Receipt: \(outcome.receipt.id.uuidString.lowercased())",
            "Accepted/sent: \(outcome.receipt.acceptedCount); rejected: \(outcome.receipt.rejectedCount); not sent: \(outcome.receipt.notSent.count)",
        ]
        if outcome.isAmbiguous {
            lines += [
                "",
                "STOPPED: AN ORDER HAS AN AMBIGUOUS OUTCOME.",
                "The market-order endpoint is non-idempotent. Never blindly retry.",
                "CHECK THE TRADING 212 APP and reconcile broker state first.",
            ]
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func money(_ value: Decimal) -> String {
        CurrencyDisplay.decimalString(
            value,
            minimumFractionDigits: 2,
            maximumFractionDigits: 2,
            separators: .commaDot,
            locale: Locale(identifier: "en_US_POSIX")
        )
    }

    static func quantity(_ value: Decimal) -> String {
        CurrencyDisplay.decimalString(
            value,
            minimumFractionDigits: 0,
            maximumFractionDigits: 6,
            separators: .commaDot,
            locale: Locale(identifier: "en_US_POSIX"),
            usesGroupingSeparator: false
        )
    }

    static func percent(_ value: Decimal) -> String {
        CurrencyDisplay.percentString(
            value,
            fractionDigits: 2,
            separators: .commaDot,
            locale: Locale(identifier: "en_US_POSIX")
        )
    }

    private static func skipReason(_ reason: SkippedBuy.Reason) -> String {
        switch reason {
        case .nonPositivePrice: "saved price is missing or zero"
        case .belowMinimum(let target, let minimum):
            "target \(money(target)) is below min-order \(money(minimum))"
        case .quantityRoundedToZero(let precision):
            "quantity rounds down to zero at precision \(precision)"
        case .nonPositiveWeightAndValue:
            "no positive saved weight/value"
        }
    }

    private static func row(_ values: [String], _ widths: [Int]) -> String {
        zip(values, widths).enumerated().map {
            pad($0.element.0, width: $0.element.1, right: $0.offset > 0)
        }
            .joined()
    }

    private static func pad(_ value: String, width: Int, right: Bool = false) -> String {
        let shortened = value.count > width ? String(value.prefix(width)) : value
        let padding = String(repeating: " ", count: max(0, width - shortened.count))
        return right ? padding + shortened : shortened + padding
    }

    private static func iso8601(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
