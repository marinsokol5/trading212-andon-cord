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
            Text("Trading212 Andon Cord needs a read-only Trading 212 API key to show your account. Trading remains unavailable until you separately add a trading key.")
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
            Text(model.errorMessage ?? "Trading212 Andon Cord has no cached portfolio to display yet.")
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
                    MetricCard(
                        title: "Updated",
                        value: snapshot.asOf.formatted(date: .abbreviated, time: .shortened),
                        symbol: "clock")
                }

                topPositions
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
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(position.ticker).font(.headline)
                Text(position.name.isEmpty ? position.instrumentCurrency : position.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
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
        }
        .padding(.vertical, 11)
    }
}
