import SwiftUI
import Trading212Core

/// The **Positions** screen: every holding in a sortable table, with the
/// sellable/pie split that decides what `t212 sell-all` may touch.
struct PositionsView: View {
    @Bindable var model: AppModel

    @State private var sortOrder = [
        KeyPathComparator(\PortfolioPosition.sellableAccountValue, order: .reverse)
    ]
    @State private var filter = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScreenHeader("Positions", subtitle: subtitle) {
                TextField("Filter", text: $filter)
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
            TableColumn("Ticker", value: \.ticker) { position in
                Text(position.ticker).fontWeight(.semibold)
            }
            .width(min: 90, ideal: 90)

            TableColumn("Name", value: \.name) { position in
                Text(position.name.isEmpty ? position.instrumentCurrency : position.name)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .width(min: 120, ideal: 120)

            TableColumn("Quantity", value: \.quantity) { position in
                amount("\(position.quantity)")
            }
            .width(min: 60, ideal: 60)

            TableColumn("Sellable", value: \.sellableQuantity) { position in
                amount("\(position.sellableQuantity)")
            }
            .width(min: 60, ideal: 60)

            TableColumn("In pies", value: \.pieQuantity) { position in
                amount(
                    position.pieQuantity > 0 ? "\(position.pieQuantity)" : "—",
                    tint: position.pieQuantity > 0 ? Theme.warning : .secondary)
            }
            .width(min: 50, ideal: 50)

            TableColumn("Price", value: \.accountPricePerShare) { position in
                amount(model.privateAmount(
                    position.accountPricePerShare,
                    currency: portfolio.currency,
                    style: .fullWithCents))
            }
            .width(min: 75, ideal: 75)

            TableColumn("Sellable value", value: \.sellableAccountValue) { position in
                amount(model.privateAmount(
                    position.sellableAccountValue,
                    currency: portfolio.currency,
                    style: .fullWithCents))
            }
            .width(min: 95, ideal: 95)

            TableColumn("Weight", value: \.sellableWeight) { position in
                amount(weightText(position.sellableWeight), tint: .secondary)
            }
            .width(min: 55, ideal: 55)
        }
    }

    /// Quantities are masked in privacy mode along with money: share counts
    /// plus public prices reconstruct the account value.
    private func amount(_ text: String, tint: Color = .primary) -> some View {
        Text(model.isPrivate ? AppModel.hiddenText : text)
            .monospacedDigit()
            .foregroundStyle(model.isPrivate ? .secondary : tint)
    }

    private func rows(_ portfolio: CurrentPortfolio) -> [PortfolioPosition] {
        let trimmed = filter.trimmingCharacters(in: .whitespaces)
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
