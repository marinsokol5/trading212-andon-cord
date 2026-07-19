import SwiftUI
import Trading212Core

/// Fixed left sidebar: brand, route navigation, and a portfolio glance card
/// with quick refresh/privacy actions in the footer.
struct SidebarView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            brand
                .padding(.horizontal, 8)
                .padding(.top, 4)

            VStack(spacing: 4) {
                ForEach(AppRoute.allCases) { route in
                    NavButton(
                        title: route.title,
                        systemImage: route.systemImage,
                        count: route == .positions ? model.currentPortfolio?.positions.count : nil,
                        isActive: model.activeRoute == route,
                        action: { model.navigate(to: route) })
                }
            }

            Spacer()

            glanceCard
                .padding(.horizontal, 8)

            quickActions
                .padding(.horizontal, 8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 16)
        .frame(width: Theme.sidebarWidth)
        .background(.regularMaterial)
    }

    private var brand: some View {
        HStack(spacing: 9) {
            BrandMark(size: 28)
            VStack(alignment: .leading, spacing: 0) {
                Text("Andon Cord")
                    .font(.system(size: 19, weight: .heavy))
                Text(AppVariant.current == .development ? "Trading 212 · dev build" : "Trading 212")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// One ambient answer, on every route: what is the portfolio worth right
    /// now. Clicking it jumps to Portfolio — or Account while unconfigured.
    private var glanceCard: some View {
        Button {
            model.navigate(to: model.hasReadCredential || model.displaySnapshot != nil
                           ? .portfolio : .account)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text("PORTFOLIO")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.6)
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 0)
                    EnvironmentBadge(environment: model.environment)
                }
                if let snapshot = model.displaySnapshot {
                    Text(model.isPrivate
                         ? AppModel.hiddenText
                         : model.privateAmount(snapshot.totalValue, currency: snapshot.currencyCode, style: model.settings.valueStyle))
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text("Updated \(snapshot.asOf.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                } else {
                    Text(model.hasReadCredential ? "Portfolio unavailable" : "Add a viewing key")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(radius: Theme.Radius.sm, hovering: hoveringGlance)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hoveringGlance = $0 }
        .animation(.easeOut(duration: 0.12), value: hoveringGlance)
    }

    @State private var hoveringGlance = false

    private var quickActions: some View {
        HStack(spacing: 4) {
            Button {
                Task { await model.refresh() }
            } label: {
                if model.isRefreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
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
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 4)
    }
}

private struct NavButton: View {
    let title: String
    let systemImage: String
    var count: Int?
    let isActive: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 13))
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                Spacer(minLength: 4)
                if let count {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 1)
                        .background(isActive ? Color.white.opacity(0.25) : Color.primary.opacity(0.1))
                        .clipShape(Capsule())
                }
            }
            .foregroundStyle(isActive ? Color.white : Color.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(isActive ? Theme.accent : (hovering ? Color.primary.opacity(0.06) : .clear)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
