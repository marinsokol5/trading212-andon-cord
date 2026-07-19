import AppKit
import SwiftUI
import Trading212Core

/// The **Portfolio** screen: account value, key metrics, and a short preview
/// of the largest positions. The full table lives on the Positions route.
struct PortfolioView: View {
    @Bindable var model: AppModel

    private static let previewCount = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScreenHeader("Portfolio", subtitle: "Trading 212 · \(model.environment.displayName)") {
                if let asOf = model.displaySnapshot?.asOf {
                    Text("Updated \(asOf.formatted(.relative(presentation: .named)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if model.isRefreshing {
                    ProgressView().controlSize(.small)
                }
                Button {
                    Task { await model.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(!model.hasReadCredential || model.isRefreshing)

                Button {
                    model.togglePrivacy()
                } label: {
                    Label(
                        model.isPrivate ? "Show values" : "Hide values",
                        systemImage: model.isPrivate ? "eye" : "eye.slash")
                }
            }
            .buttonStyle(.borderless)

            if !model.hasReadCredential, model.displaySnapshot == nil {
                setupState
            } else if let snapshot = model.displaySnapshot {
                content(snapshot)
            } else if model.isRefreshing {
                ProgressView("Loading portfolio…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                failureState
            }
        }
    }

    private var setupState: some View {
        ContentUnavailableView {
            Label("Connect a viewing key", systemImage: "key.horizontal")
        } description: {
            Text("Trading 212 Andon Cord needs a read-only Trading 212 API key to show your account. Trading remains unavailable until you separately add a trading key.")
                .frame(maxWidth: 470)
        } actions: {
            Button("Open Account") { model.navigate(to: .account) }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var failureState: some View {
        ContentUnavailableView {
            Label("Portfolio unavailable", systemImage: "exclamationmark.triangle")
        } description: {
            Text(model.errorMessage ?? "Trading 212 Andon Cord has no cached portfolio to display yet.")
                .frame(maxWidth: 470)
        } actions: {
            Button("Try Again") { Task { await model.refresh() } }
            Button("Account") { model.navigate(to: .account) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func content(_ snapshot: AccountSnapshot) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let error = model.errorMessage {
                    Label(error, systemImage: "wifi.exclamationmark")
                        .font(.callout)
                        .foregroundStyle(Theme.warning)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.warning.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("ACCOUNT VALUE")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(model.privateAmount(snapshot.totalValue, currency: snapshot.currencyCode, style: .fullWithCents))
                        .font(.system(size: 38, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .accessibilityLabel(model.isPrivate
                            ? "Value hidden"
                            : model.privateAmount(snapshot.totalValue, currency: snapshot.currencyCode, style: .fullWithCents))
                    if let change = model.dailyChange {
                        DailyChangeLabel(change: change, model: model)
                            .font(.callout)
                    }
                }

                HStack(spacing: 12) {
                    MetricCard(
                        title: "Free cash",
                        value: model.privateAmount(snapshot.freeCash, currency: snapshot.currencyCode, style: .fullWithCents),
                        symbol: "banknote")
                    MetricCard(
                        title: "Sellable positions",
                        value: model.privateAmount(snapshot.sellablePositionsValue, currency: snapshot.currencyCode, style: .fullWithCents),
                        symbol: "chart.line.uptrend.xyaxis")
                    if let pnl = snapshot.unrealizedProfitLoss {
                        MetricCard(
                            title: "Unrealized P/L",
                            value: model.privateAmount(pnl, currency: snapshot.currencyCode, style: .fullWithCents),
                            symbol: pnl < 0 ? "arrow.down.right" : "arrow.up.right",
                            tint: pnl < 0 ? Theme.danger : Theme.success)
                    }
                }

                topPositions
                allocation
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 18)
            .padding(.top, 4)
        }
    }

    @ViewBuilder
    private var topPositions: some View {
        if let portfolio = model.currentPortfolio {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Largest positions").font(.title3.weight(.semibold))
                    Spacer()
                    Button {
                        model.navigate(to: .positions)
                    } label: {
                        Text("View all \(portfolio.positions.count)")
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                    }
                    .buttonStyle(.borderless)
                    .disabled(portfolio.positions.isEmpty)
                }

                if portfolio.positions.isEmpty {
                    Text("No positions")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 18)
                } else {
                    let preview = portfolio.positions
                        .sorted { $0.sellableAccountValue > $1.sellableAccountValue }
                        .prefix(Self.previewCount)
                    VStack(spacing: 0) {
                        ForEach(Array(preview.enumerated()), id: \.element.id) { index, position in
                            PositionRow(position: position, currency: portfolio.currency, model: model)
                            if index != preview.count - 1 { Divider() }
                        }
                    }
                    .padding(.horizontal, 14)
                    .card()
                }
            }
        } else {
            Text("Position details will appear after the next successful refresh.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    /// One horizontal 100% bar of sellable value, top holdings plus a neutral
    /// remainder. Everything here is a proportion, so it stays visible in
    /// privacy mode by design.
    @ViewBuilder
    private var allocation: some View {
        if let portfolio = model.currentPortfolio {
            let entries = Self.allocationEntries(portfolio)
            if !entries.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Allocation").font(.title3.weight(.semibold))
                    VStack(alignment: .leading, spacing: 12) {
                        GeometryReader { geo in
                            let gaps = CGFloat(entries.count - 1) * 2
                            HStack(spacing: 2) {
                                ForEach(entries) { entry in
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(entry.color)
                                        .frame(width: max(3, (geo.size.width - gaps) * entry.layoutFraction))
                                        .help("\(entry.name): \(entry.percentText) of sellable value")
                                }
                            }
                        }
                        .frame(height: 14)
                        .accessibilityLabel("Allocation of sellable value")

                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 170), alignment: .leading)],
                            alignment: .leading, spacing: 8) {
                                ForEach(entries) { entry in
                                    HStack(spacing: 6) {
                                        Circle().fill(entry.color).frame(width: 8, height: 8)
                                        Text(entry.name)
                                            .font(.caption)
                                            .lineLimit(1)
                                        Text(entry.percentText)
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
                }
            }
        }
    }

    private struct AllocationEntry: Identifiable {
        let id: String
        let name: String
        let fraction: Decimal
        let color: Color

        var layoutFraction: CGFloat { CGFloat(NSDecimalNumber(decimal: fraction).doubleValue) }
        var percentText: String {
            String(format: "%.1f%%", NSDecimalNumber(decimal: fraction * 100).doubleValue)
        }
    }

    private static let allocationSlots = 5

    private static func allocationEntries(_ portfolio: CurrentPortfolio) -> [AllocationEntry] {
        let weighted = portfolio.positions
            .filter { $0.sellableWeight > 0 }
            .sorted { $0.sellableWeight > $1.sellableWeight }
        guard !weighted.isEmpty else { return [] }

        var entries = weighted.prefix(allocationSlots).enumerated().map { index, position in
            AllocationEntry(
                id: position.ticker,
                name: position.name.isEmpty ? position.ticker : position.name,
                fraction: position.sellableWeight,
                color: Theme.Chart.categorical[index])
        }
        let rest = weighted.dropFirst(allocationSlots).reduce(Decimal(0)) { $0 + $1.sellableWeight }
        if rest > 0 {
            entries.append(AllocationEntry(
                id: "•other", name: "Other", fraction: rest, color: Theme.Chart.other))
        }
        return entries
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let symbol: String
    var tint: Color?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.monospacedDigit())
                .foregroundStyle(tint ?? .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

private struct PositionRow: View {
    let position: PortfolioPosition
    let currency: String
    @Bindable var model: AppModel

    var body: some View {
        Button {
            model.showInPositions(position)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(position.name.isEmpty ? position.ticker : position.name)
                        .font(.headline)
                        .lineLimit(1)
                    Text(position.ticker)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 18)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(model.privateAmount(position.sellableAccountValue, currency: currency, style: .fullWithCents))
                        .font(.body.monospacedDigit())
                    Text(model.isPrivate
                         ? AppModel.hiddenText
                         : "\(position.sellableQuantity) sellable" + (position.pieQuantity > 0 ? " · \(position.pieQuantity) in pies" : ""))
                        .font(.caption)
                        .foregroundStyle(position.pieQuantity > 0
                                         ? Theme.warning
                                         : Color(nsColor: .secondaryLabelColor))
                }
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show \(position.name.isEmpty ? position.ticker : position.name) in Positions")
    }
}
