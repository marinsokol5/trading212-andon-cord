import AppKit

@MainActor
enum MenuBarRenderer {
    static func image(
        value: String,
        privateMode: Bool,
        layout: MenuBarLayout,
        symbol: MenuBarSymbol,
        tint: MenuBarTint
    ) -> NSImage {
        let height = NSStatusBar.system.thickness
        let foreground: NSColor = tint == .adaptive ? .black : .white
        let image: NSImage = switch layout {
        case .stacked:
            stackedImage(
                value: value,
                privateMode: privateMode,
                symbol: symbol,
                height: height,
                foreground: foreground)
        case .inline:
            inlineImage(
                value: value,
                privateMode: privateMode,
                symbol: symbol,
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
        let topWidth: CGFloat = symbol == .icon
            ? 10
            : ("ANDON" as NSString).size(withAttributes: labelAttributes).width
        let width = ceil(max(valueSize.width, topWidth)) + 6

        return NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            let topRect = NSRect(x: (rect.width - topWidth) / 2, y: rect.height - 10.5,
                                 width: topWidth, height: 8.5)
            drawSymbol(symbol, in: topRect, attributes: labelAttributes, color: foreground)
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
        height: CGFloat,
        foreground: NSColor
    ) -> NSImage {
        let valueFont = NSFont.menuBarFont(ofSize: 0)
        let labelFont = NSFont.systemFont(ofSize: 10, weight: .medium)
        let valueAttributes = attributes(font: valueFont, color: foreground)
        let labelAttributes = attributes(font: labelFont, color: foreground)
        let glyphWidth: CGFloat = symbol == .icon
            ? 15
            : ceil(("ANDON" as NSString).size(withAttributes: labelAttributes).width)
        let valueWidth: CGFloat = privateMode
            ? 16
            : ceil((value as NSString).size(withAttributes: valueAttributes).width)
        let gap: CGFloat = 4
        let width = glyphWidth + gap + valueWidth + 6

        return NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            let startX: CGFloat = 3
            drawSymbol(
                symbol,
                in: NSRect(x: startX, y: (rect.height - 14) / 2, width: glyphWidth, height: 14),
                attributes: labelAttributes,
                color: foreground)
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
        color: NSColor
    ) {
        switch symbol {
        case .icon:
            drawMark(in: rect, color: color)
        case .label:
            let text = "ANDON" as NSString
            let size = text.size(withAttributes: attributes)
            text.draw(
                in: NSRect(x: rect.midX - size.width / 2,
                           y: rect.midY - size.height / 2,
                           width: size.width, height: size.height),
                withAttributes: attributes)
        }
    }

    /// Small monochrome andon lamp: a dome, center light, and base. Geometry is
    /// intentionally simple so it remains readable at 8–15 points.
    private static func drawMark(in rect: NSRect, color: NSColor) {
        color.setStroke()
        color.setFill()
        let lineWidth = max(1, rect.height * 0.13)
        let path = NSBezierPath()
        path.lineWidth = lineWidth
        path.lineCapStyle = .round
        path.appendArc(
            withCenter: NSPoint(x: rect.midX, y: rect.midY + rect.height * 0.05),
            radius: rect.height * 0.29,
            startAngle: 0,
            endAngle: 180)
        path.move(to: NSPoint(x: rect.midX - rect.height * 0.29, y: rect.midY))
        path.line(to: NSPoint(x: rect.midX - rect.height * 0.29, y: rect.minY + rect.height * 0.20))
        path.move(to: NSPoint(x: rect.midX + rect.height * 0.29, y: rect.midY))
        path.line(to: NSPoint(x: rect.midX + rect.height * 0.29, y: rect.minY + rect.height * 0.20))
        path.move(to: NSPoint(x: rect.midX - rect.height * 0.38, y: rect.minY + rect.height * 0.16))
        path.line(to: NSPoint(x: rect.midX + rect.height * 0.38, y: rect.minY + rect.height * 0.16))
        path.stroke()
        NSBezierPath(ovalIn: NSRect(
            x: rect.midX - lineWidth,
            y: rect.midY - lineWidth * 0.45,
            width: lineWidth * 2,
            height: lineWidth * 2)).fill()
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
