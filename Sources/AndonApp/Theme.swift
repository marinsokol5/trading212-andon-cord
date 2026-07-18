import SwiftUI
import Trading212Core

/// Visual language for the sidebar shell. Semantic roles only — views reference
/// `Theme.accent` / `Theme.danger` rather than inline literals, so one meaning
/// maps to one value across every screen.
enum Theme {
    /// Nav selection and interactive highlights. Deliberately not red: red is
    /// reserved for LIVE and destructive signals in a trading app.
    static let accent = Color(hex: "#6c8cff")

    /// Failure / destructive / LIVE environment.
    static let danger = Color(hex: "#e0533f")
    /// Positive / configured / gains.
    static let success = Color(hex: "#26a050")
    /// Caution — stale data, pie-locked shares.
    static let warning = Color(hex: "#be7d43")

    static let sidebarWidth: CGFloat = 210

    enum Radius {
        static let sm: CGFloat = 7
        static let md: CGFloat = 10
    }
}

extension View {
    /// Flat card: subtle fill plus hairline border. Bind `hovering` for the
    /// slight raise on interactive cards.
    func card(radius: CGFloat = Theme.Radius.md, hovering: Bool = false) -> some View {
        background(
            RoundedRectangle(cornerRadius: radius)
                .fill(Color.primary.opacity(hovering ? 0.05 : 0.035)))
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(Color.primary.opacity(0.08)))
    }
}

extension Color {
    /// Parse `#RRGGBB`. Falls back to the accent blue on bad input.
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt32(s, radix: 16) else {
            self = Color(red: 0x6c / 255, green: 0x8c / 255, blue: 0xff / 255)
            return
        }
        self = Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255)
    }
}

/// Per-screen title block: H1, optional subtitle, optional trailing actions.
struct ScreenHeader<Trailing: View>: View {
    let title: String
    let subtitle: String?
    private let trailing: Trailing

    init(_ title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 18, weight: .bold))
                if let subtitle {
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil) {
        self.init(title, subtitle: subtitle) { EmptyView() }
    }
}

/// LIVE/DEMO chip. LIVE is always red — the one place red means red.
struct EnvironmentBadge: View {
    let environment: Trading212Environment

    var body: some View {
        Text(environment.displayName.uppercased())
            .font(.caption2.weight(.bold))
            .foregroundStyle(environment == .live ? Theme.danger : Color(nsColor: .secondaryLabelColor))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.secondary.opacity(0.12), in: Capsule())
    }
}
