import SwiftUI
import Trading212Core

/// One-line daily change readout: `↗ +€620.47 (+1.29%) · since 9:41`.
/// Shared by the status-menu header and the Portfolio hero. Callers skip it
/// entirely in privacy mode — the tint and arrow alone would reveal the trend.
struct DailyChangeLabel: View {
    let change: DailyChange
    let model: AppModel

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
            Text(model.changeDescription(change))
                .monospacedDigit()
            Text("· since \(sinceText)")
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(tint)
    }

    private var symbol: String {
        change.isDown ? "arrow.down.right" : change.isUp ? "arrow.up.right" : "minus"
    }

    private var tint: Color {
        change.isDown ? Theme.danger : change.isUp ? Theme.success : Color.secondary
    }

    private var sinceText: String {
        Calendar.current.isDateInToday(change.since)
            ? change.since.formatted(date: .omitted, time: .shortened)
            : change.since.formatted(date: .abbreviated, time: .shortened)
    }
}
