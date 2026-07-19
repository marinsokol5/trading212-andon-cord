import SwiftUI
import Trading212Core

/// The **Positions** screen: every holding in a sortable table, with the
/// sellable/pie split that decides what `t212 sell-all` may touch.
struct PositionsView: View {
    @Bindable var model: AppModel

    @State private var sortOrder = [
        KeyPathComparator(\PortfolioPosition.sellableAccountValue, order: .reverse)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScreenHeader("Positions", subtitle: subtitle) {
                TextField("Filter", text: $model.positionsFilter)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                    .disabled(model.currentPortfolio == nil)
                Button {
                    Task { await model.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(!model.hasReadCredential || model.isRefreshing)
            }

            if let portfolio = model.currentPortfolio {
                if portfolio.positions.isEmpty {
                    ContentUnavailableView(
                        "No positions",
                        systemImage: "list.bullet.rectangle",
                        description: Text("This account holds no instruments right now."))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    table(portfolio)
                    totalsBar(portfolio)
                }
            } else if !model.hasReadCredential {
                ContentUnavailableView {
                    Label("Connect a viewing key", systemImage: "key.horizontal")
                } description: {
                    Text("Positions appear once a read-only API key is configured.")
                } actions: {
                    Button("Open Account") { model.navigate(to: .account) }
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    "No position data yet",
                    systemImage: "list.bullet.rectangle",
                    description: Text("Position details will appear after the next successful refresh."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var subtitle: String {
        guard let portfolio = model.currentPortfolio else {
            return "Sellable and pie-held shares per instrument"
        }
        let pieBound = portfolio.positions.filter { $0.pieQuantity > 0 }.count
        return pieBound > 0
            ? "\(portfolio.positions.count) instruments · \(pieBound) with pie-held shares (never sold by the CLI)"
            : "\(portfolio.positions.count) instruments"
    }

    private func table(_ portfolio: CurrentPortfolio) -> some View {
        // Ideal widths deliberately equal the minimums: Table lays columns out
        // at ideal and clips overflow instead of compressing, so any slack
        // here pushes the trailing columns off narrow windows.
        Table(rows(portfolio), sortOrder: $sortOrder) {
            TableColumn("Name", value: \.name) { position in
                Text(position.name.isEmpty ? position.ticker : position.name)
                    .fontWeight(.semibold)
                    .lineLimit(1)
            }
            .width(min: 100, ideal: 100)

            TableColumn("Ticker", value: \.ticker) { position in
                Text(position.ticker)
                    .foregroundStyle(.secondary)
            }
            .width(min: 62, ideal: 62)

            TableColumn("Quantity", value: \.quantity) { position in
                amount("\(position.quantity)")
            }
            .width(min: 46, ideal: 46)

            TableColumn("Sellable", value: \.sellableQuantity) { position in
                amount("\(position.sellableQuantity)")
            }
            .width(min: 46, ideal: 46)

            TableColumn("In pies", value: \.pieQuantity) { position in
                amount(
                    position.pieQuantity > 0 ? "\(position.pieQuantity)" : "—",
                    tint: position.pieQuantity > 0 ? Theme.warning : .secondary)
            }
            .width(min: 42, ideal: 42)

            TableColumn("Price", value: \.accountPricePerShare) { position in
                amount(model.privateAmount(
                    position.accountPricePerShare,
                    currency: portfolio.currency,
                    style: .fullWithCents))
            }
            .width(min: 66, ideal: 66)

            TableColumn("Sellable value", value: \.sellableAccountValue) { position in
                amount(model.privateAmount(
                    position.sellableAccountValue,
                    currency: portfolio.currency,
                    style: .fullWithCents))
            }
            .width(min: 82, ideal: 82)

            TableColumn("P/L", value: \.pnlSortValue) { position in
                pnlCell(position, currency: portfolio.currency)
            }
            .width(min: 76, ideal: 76)

            TableColumn("Weight", value: \.sellableWeight) { position in
                weightCell(position.sellableWeight)
            }
            .width(min: 60, ideal: 60)
        }
    }

    @ViewBuilder
    private func pnlCell(_ position: PortfolioPosition, currency: String) -> some View {
        if let pnl = position.unrealizedProfitLoss {
            amount(
                CurrencyDisplay.signedString(
                    pnl, currencyCode: currency, separators: model.settings.separators),
                tint: pnl < 0 ? Theme.danger : pnl > 0 ? Theme.success : .secondary)
        } else {
            amount("—", tint: .secondary)
        }
    }

    /// Weight stays visible in privacy mode: it is a proportion, not an amount.
    /// Compact enough (20pt bar + caption text) to fit the 940pt-wide window.
    private func weightCell(_ weight: Decimal) -> some View {
        HStack(spacing: 4) {
            Capsule()
                .fill(Color.primary.opacity(0.10))
                .frame(width: 20, height: 4)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(Theme.accent)
                        .frame(width: 20 * min(1, CGFloat(NSDecimalNumber(decimal: weight).doubleValue)))
                }
            Text(weightText(weight))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    /// Count · sellable total · summed P/L for every holding (not the filter).
    private func totalsBar(_ portfolio: CurrentPortfolio) -> some View {
        let pnls = portfolio.positions.compactMap(\.unrealizedProfitLoss)
        let totalPnL = pnls.reduce(Decimal(0), +)
        return HStack(spacing: 14) {
            Text("\(portfolio.positions.count) instruments")
                .foregroundStyle(.secondary)
            Spacer()
            HStack(spacing: 5) {
                Text("Sellable total").foregroundStyle(.secondary)
                amount(model.privateAmount(
                    portfolio.sellablePositionsValue,
                    currency: portfolio.currency,
                    style: .fullWithCents))
            }
            if !pnls.isEmpty {
                HStack(spacing: 5) {
                    Text("P/L").foregroundStyle(.secondary)
                    amount(
                        CurrencyDisplay.signedString(
                            totalPnL, currencyCode: portfolio.currency,
                            separators: model.settings.separators),
                        tint: totalPnL < 0 ? Theme.danger : totalPnL > 0 ? Theme.success : .secondary)
                }
            }
        }
        .font(.caption)
        .padding(.horizontal, 22)
        .padding(.vertical, 8)
        .overlay(alignment: .top) { Divider() }
    }

    /// Quantities are masked in privacy mode along with money: share counts
    /// plus public prices reconstruct the account value.
    private func amount(_ text: String, tint: Color = .primary) -> some View {
        Text(model.isPrivate ? AppModel.hiddenText : text)
            .monospacedDigit()
            .foregroundStyle(model.isPrivate ? .secondary : tint)
    }

    private func rows(_ portfolio: CurrentPortfolio) -> [PortfolioPosition] {
        let trimmed = model.positionsFilter.trimmingCharacters(in: .whitespaces)
        let filtered = trimmed.isEmpty
            ? portfolio.positions
            : portfolio.positions.filter {
                $0.ticker.localizedCaseInsensitiveContains(trimmed)
                    || $0.name.localizedCaseInsensitiveContains(trimmed)
            }
        return filtered.sorted(using: sortOrder)
    }

    private func weightText(_ weight: Decimal) -> String {
        let percent = NSDecimalNumber(decimal: weight * 100).doubleValue
        return String(format: "%.1f%%", percent)
    }
}

private extension PortfolioPosition {
    /// Sort key for the P/L column: missing P/L orders as zero.
    var pnlSortValue: Decimal { unrealizedProfitLoss ?? 0 }
}
