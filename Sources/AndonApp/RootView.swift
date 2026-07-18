import SwiftUI
import Trading212Core

/// Top-level shell: fixed sidebar + a detail pane that switches on the route.
struct RootView: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(model: model)
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 940, minHeight: 620)
    }

    @ViewBuilder
    private var detail: some View {
        switch model.activeRoute {
        case .account:
            AccountView(model: model)
        case .portfolio:
            PortfolioView(model: model)
        case .positions:
            PositionsView(model: model)
        case .snapshots:
            SnapshotsView(model: model)
        case .display:
            DisplayView(model: model)
        case .about:
            AboutView(model: model)
        }
    }
}
