import SwiftUI
import Trading212Core

/// Info block at the top of the status-item menu: identity, portfolio value,
/// cash/sellable split, freshness. Rendered through a view-backed `NSMenuItem`;
/// every action lives in the regular menu items below it.
struct MenuBarHeaderView: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label {
                    Text("Trading 212 Andon Cord")
                } icon: {
                    BrandMark(size: 15)
                }
                .font(.subheadline.weight(.semibold))
                Spacer()
                EnvironmentBadge(environment: model.environment)
            }

            if let snapshot = model.displaySnapshot {
                VStack(alignment: .leading, spacing: 4) {
                    // In privacy mode the eye-slash rides on the value line —
                    // one line says "hidden", no separate caption needed.
                    HStack(spacing: 7) {
                        Text(model.isPrivate ? AppModel.hiddenText : model.privateAmount(
                            snapshot.totalValue,
                            currency: snapshot.currencyCode,
                            style: .fullWithCents))
                            .font(.system(size: 26, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        if model.isPrivate {
                            Image(systemName: "eye.slash")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityLabel(model.isPrivate ? "Portfolio value hidden" : "Portfolio value")
                    if let change = model.dailyChange {
                        DailyChangeLabel(change: change, model: model)
                            .font(.caption)
                    }
                    if !model.isPrivate {
                        HStack(spacing: 4) {
                            Text("Cash \(model.privateAmount(snapshot.freeCash, currency: snapshot.currencyCode, style: .fullWithCents))")
                            Text("·")
                            Text("Sellable \(model.privateAmount(snapshot.sellablePositionsValue, currency: snapshot.currencyCode, style: .fullWithCents))")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Text("Updated \(snapshot.asOf.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            } else if model.isRefreshing {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Loading portfolio…")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            } else {
                Text(model.hasReadCredential ? "Portfolio unavailable" : "Viewing key not configured")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if let error = model.errorMessage, model.displaySnapshot != nil {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(Theme.warning)
                    .lineLimit(2)
            }
        }
        .padding(.top, 4)
        .padding(.bottom, 8)
        .padding(.horizontal, 14)
        .frame(width: 300, alignment: .leading)
    }
}
