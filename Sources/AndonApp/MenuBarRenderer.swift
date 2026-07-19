import AppKit

@MainActor
enum MenuBarRenderer {
    /// Text drawn for `MenuBarSymbol.label` — the "T212 label" picker option.
    private static let labelText = "T212" as NSString

    /// `trendDown` mirrors the trend mark vertically so the bar never shows a
    /// rising arrow on a down day; `.t212` (brand chevron) and `.label` are
    /// direction-agnostic and ignore it.
    static func image(
        value: String,
        privateMode: Bool,
        layout: MenuBarLayout,
        symbol: MenuBarSymbol,
        tint: MenuBarTint,
        trendDown: Bool
    ) -> NSImage {
        let height = NSStatusBar.system.thickness
        let foreground: NSColor = tint == .adaptive ? .black : .white
        let image: NSImage = switch layout {
        case .stacked:
            stackedImage(
                value: value,
                privateMode: privateMode,
                symbol: symbol,
                trendDown: trendDown,
                height: height,
                foreground: foreground)
        case .inline:
            inlineImage(
                value: value,
                privateMode: privateMode,
                symbol: symbol,
                trendDown: trendDown,
                height: height,
                foreground: foreground)
        }
        image.isTemplate = tint == .adaptive
        return image
    }

    private static func stackedImage(
        value: String,
        privateMode: Bool,
        symbol: MenuBarSymbol,
        trendDown: Bool,
        height: CGFloat,
        foreground: NSColor
    ) -> NSImage {
        let valueFont = NSFont.systemFont(ofSize: 12, weight: .medium)
        let labelFont = NSFont.systemFont(ofSize: 8.5, weight: .medium)
        let valueAttributes = attributes(font: valueFont, color: foreground)
        let labelAttributes = attributes(font: labelFont, color: foreground)
        let valueSize: NSSize
        if privateMode {
            valueSize = NSSize(width: 14, height: 9)
        } else {
            valueSize = (value as NSString).size(withAttributes: valueAttributes)
        }
        let topWidth: CGFloat = switch symbol {
        case .icon, .t212: 10
        case .label: labelText.size(withAttributes: labelAttributes).width
        }
        let width = ceil(max(valueSize.width, topWidth)) + 4

        return NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            let topRect = NSRect(x: (rect.width - topWidth) / 2, y: rect.height - 11,
                                 width: topWidth, height: 10)
            drawSymbol(symbol, in: topRect, attributes: labelAttributes,
                       color: foreground, trendDown: trendDown)
            if privateMode {
                drawEyeSlash(
                    in: NSRect(x: (rect.width - 13) / 2, y: 1.5, width: 13, height: 9),
                    color: foreground)
            } else {
                (value as NSString).draw(
                    in: NSRect(x: 0, y: 0.3, width: rect.width, height: valueSize.height),
                    withAttributes: valueAttributes)
            }
            return true
        }
    }

    private static func inlineImage(
        value: String,
        privateMode: Bool,
        symbol: MenuBarSymbol,
        trendDown: Bool,
        height: CGFloat,
        foreground: NSColor
    ) -> NSImage {
        let valueFont = NSFont.menuBarFont(ofSize: 0)
        let labelFont = NSFont.systemFont(ofSize: 10, weight: .medium)
        let valueAttributes = attributes(font: valueFont, color: foreground)
        let labelAttributes = attributes(font: labelFont, color: foreground)
        let glyphWidth: CGFloat = switch symbol {
        case .icon, .t212: 15
        case .label: ceil(labelText.size(withAttributes: labelAttributes).width)
        }
        let valueWidth: CGFloat = privateMode
            ? 16
            : ceil((value as NSString).size(withAttributes: valueAttributes).width)
        let gap: CGFloat = 4
        let width = glyphWidth + gap + valueWidth + 4

        return NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            let startX: CGFloat = 2
            drawSymbol(
                symbol,
                in: NSRect(x: startX, y: (rect.height - 14) / 2, width: glyphWidth, height: 14),
                attributes: labelAttributes,
                color: foreground,
                trendDown: trendDown)
            if privateMode {
                drawEyeSlash(
                    in: NSRect(x: startX + glyphWidth + gap,
                               y: (rect.height - 12) / 2,
                               width: 16, height: 12),
                    color: foreground)
            } else {
                let size = (value as NSString).size(withAttributes: valueAttributes)
                (value as NSString).draw(
                    in: NSRect(x: startX + glyphWidth + gap,
                               y: (rect.height - size.height) / 2,
                               width: valueWidth, height: size.height),
                    withAttributes: valueAttributes)
            }
            return true
        }
    }

    private static func drawSymbol(
        _ symbol: MenuBarSymbol,
        in rect: NSRect,
        attributes: [NSAttributedString.Key: Any],
        color: NSColor,
        trendDown: Bool
    ) {
        switch symbol {
        case .icon:
            drawMark(in: rect, color: color, down: trendDown)
        case .t212:
            drawT212Mark(in: rect, color: color)
        case .label:
            let text = labelText
            let size = text.size(withAttributes: attributes)
            text.draw(
                in: NSRect(x: rect.midX - size.width / 2,
                           y: rect.midY - size.height / 2,
                           width: size.width, height: size.height),
                withAttributes: attributes)
        }
    }

    /// Trading 212's mark: a symmetric upward chevron — an arrowhead with a
    /// broad rounded peak and a shallow V-notch cut from its base, legs
    /// splaying to the bottom corners. Same geometry as InvestingBar's
    /// menu-bar mark, drawn into the largest centered square of `rect` so
    /// both layouts render it undistorted.
    private static func drawT212Mark(in rect: NSRect, color: NSColor) {
        let side = min(rect.width, rect.height)
        let box = NSRect(x: rect.midX - side / 2, y: rect.midY - side / 2,
                         width: side, height: side)
        func p(_ fx: CGFloat, _ fy: CGFloat) -> NSPoint {
            NSPoint(x: box.minX + box.width * fx, y: box.minY + box.height * fy)
        }

        let apex = p(0.50, 0.84)             // top peak (rounded by the arc)
        let outerBottomRight = p(0.89, 0.20)
        let innerBottomRight = p(0.63, 0.20)
        let notch = p(0.50, 0.50)            // floor of the V-notch
        let innerBottomLeft = p(0.37, 0.20)
        let outerBottomLeft = p(0.11, 0.20)
        let peakRadius = box.width * 0.11

        let chevron = NSBezierPath()
        chevron.move(to: notch)
        chevron.line(to: innerBottomLeft)
        chevron.line(to: outerBottomLeft)
        // Up the left flank, around the rounded peak, down the right flank.
        chevron.appendArc(from: apex, to: outerBottomRight, radius: peakRadius)
        chevron.line(to: outerBottomRight)
        chevron.line(to: innerBottomRight)
        chevron.close()
        chevron.lineWidth = box.width * 0.04
        chevron.lineJoinStyle = .round

        color.setFill()
        color.setStroke()
        chevron.fill()
        chevron.stroke()
    }

    /// Small monochrome stock line capped with an arrowhead at its end — the
    /// same trend mark InvestingBar draws for its menu bar, with its exact
    /// proportions (10% inset, 0.11 stroke, 0.30 barbs). Drawn into the largest
    /// centered square of `rect` so neither layout squashes the slope; `down`
    /// mirrors it vertically so the arrow falls on a down day.
    private static func drawMark(in rect: NSRect, color: NSColor, down: Bool) {
        let side = min(rect.width, rect.height)
        let box = NSRect(x: rect.midX - side / 2, y: rect.midY - side / 2,
                         width: side, height: side)
        let area = box.insetBy(dx: side * 0.10, dy: side * 0.10)
        let normalized: [NSPoint] = [
            NSPoint(x: 0.00, y: 0.10), NSPoint(x: 0.25, y: 0.42),
            NSPoint(x: 0.50, y: 0.28), NSPoint(x: 0.75, y: 0.74),
            NSPoint(x: 1.00, y: 0.98),
        ]
        let points = normalized.map {
            NSPoint(x: area.minX + $0.x * area.width,
                    y: area.minY + (down ? 1 - $0.y : $0.y) * area.height)
        }

        let path = NSBezierPath()
        path.lineWidth = max(1, side * 0.11)
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.move(to: points[0])
        for point in points.dropFirst() { path.line(to: point) }

        // Arrowhead at the peak: two barbs angled back along the final segment.
        let tip = points[points.count - 1]
        let prev = points[points.count - 2]
        let angle = atan2(tip.y - prev.y, tip.x - prev.x)
        let barbLength = side * 0.30
        let spread = CGFloat.pi / 7
        for offset in [-spread, spread] {
            path.move(to: tip)
            path.line(to: NSPoint(x: tip.x - barbLength * cos(angle + offset),
                                  y: tip.y - barbLength * sin(angle + offset)))
        }

        color.setStroke()
        path.stroke()
    }

    private static func drawEyeSlash(in rect: NSRect, color: NSColor) {
        let image = NSImage(
            systemSymbolName: "eye.slash",
            accessibilityDescription: "Portfolio value hidden")?
            .withSymbolConfiguration(.init(pointSize: rect.height, weight: .regular))
        color.set()
        image?.draw(in: rect)
    }

    private static func attributes(
        font: NSFont,
        color: NSColor
    ) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        return [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph,
        ]
    }
}
