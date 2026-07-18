import AppKit
import SwiftUI
import Trading212Core

struct PortfolioPopoverView: View {
    @Bindable var model: AppModel
    let openApp: () -> Void
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Trading212 Andon Cord", systemImage: "light.beacon.max.fill")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Text(model.environment.displayName.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(model.environment == .live
                                     ? Color.red
                                     : Color(nsColor: .secondaryLabelColor))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.secondary.opacity(0.12), in: Capsule())
            }

            if let snapshot = model.displaySnapshot {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.isPrivate ? AppModel.hiddenText : model.privateAmount(
                        snapshot.totalValue,
                        currency: snapshot.currencyCode,
                        style: .fullWithCents))
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    if model.isPrivate {
                        Label("Portfolio value hidden", systemImage: "eye.slash")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        HStack {
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
                HStack { ProgressView().controlSize(.small); Text("Loading portfolio…") }
                    .foregroundStyle(.secondary)
            } else {
                Text(model.hasReadCredential ? "Portfolio unavailable" : "Viewing key not configured")
                    .foregroundStyle(.secondary)
            }

            if let error = model.errorMessage, model.displaySnapshot != nil {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }

            Divider()

            HStack(spacing: 8) {
                Button("Open Trading212 Andon Cord", action: openApp)
                    .buttonStyle(.borderedProminent)
                Button {
                    Task { await model.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(!model.hasReadCredential || model.isRefreshing)
                .help("Refresh now")
                Button {
                    model.togglePrivacy()
                } label: {
                    Image(systemName: model.isPrivate ? "eye" : "eye.slash")
                }
                .help(model.isPrivate ? "Show values" : "Hide values")
                Spacer()
                Button(action: openSettings) { Image(systemName: "gearshape") }
                    .help("Settings")
            }
        }
        .padding(16)
        .frame(width: 340)
    }
}
