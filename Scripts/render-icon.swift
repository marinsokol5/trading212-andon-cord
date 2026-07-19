import AppKit
import Foundation

@main
struct RenderAndonIcon {
    private static let slots: [(Int, String)] = [
        (16, "icon_16x16"), (32, "icon_16x16@2x"),
        (32, "icon_32x32"), (64, "icon_32x32@2x"),
        (128, "icon_128x128"), (256, "icon_128x128@2x"),
        (256, "icon_256x256"), (512, "icon_256x256@2x"),
        (512, "icon_512x512"), (1024, "icon_512x512@2x"),
    ]

    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            FileHandle.standardError.write(Data("usage: render-icon <output.icns>\n".utf8))
            exit(2)
        }
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        let iconset = FileManager.default.temporaryDirectory
            .appendingPathComponent("Andon-\(ProcessInfo.processInfo.processIdentifier).iconset")
        try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: iconset) }

        for (pixels, name) in slots {
            let image = render(size: CGFloat(pixels))
            try writePNG(image, pixels: pixels, to: iconset.appendingPathComponent("\(name).png"))
        }

        let iconutil = Process()
        iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
        try iconutil.run()
        iconutil.waitUntilExit()
        guard iconutil.terminationStatus == 0 else {
            throw RenderError.iconutil(iconutil.terminationStatus)
        }
    }

    private static func render(size: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            // Geometry is authored in the 1024-unit y-down grid of
            // Resources/AndonIcon.svg; pt/box/len map it into this y-up rep so
            // both files stay coordinate-for-coordinate in sync.
            let s = size / 1024
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: x * s, y: (1024 - y) * s)
            }
            func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
                CGRect(x: x * s, y: (1024 - y - h) * s, width: w * s, height: h * s)
            }
            func len(_ v: CGFloat) -> CGFloat { v * s }
            func gradient(_ stops: [(CGFloat, CGColor)]) -> CGGradient {
                CGGradient(
                    colorsSpace: CGColorSpaceCreateDeviceRGB(),
                    colors: stops.map(\.1) as CFArray,
                    locations: stops.map(\.0))!
            }

            let tile = box(78, 78, 868, 868)
            context.saveGState()
            context.addPath(CGPath(
                roundedRect: tile,
                cornerWidth: len(212),
                cornerHeight: len(212),
                transform: nil))
            context.clip()
            context.drawLinearGradient(
                gradient([
                    (0, CGColor(srgbRed: 1.0, green: 0.824, blue: 0.247, alpha: 1)),
                    (1, CGColor(srgbRed: 0.941, green: 0.643, blue: 0.0, alpha: 1)),
                ]),
                start: pt(512, 78),
                end: pt(512, 946),
                options: [])
            context.restoreGState()

            // Three ascending candlesticks: wicks, then bodies.
            let ink = CGColor(srgbRed: 0.149, green: 0.169, blue: 0.204, alpha: 1)
            context.setStrokeColor(ink)
            context.setLineWidth(len(26))
            context.setLineCap(.round)
            for (x, top, bottom): (CGFloat, CGFloat, CGFloat) in
                [(250, 520, 740), (390, 430, 690), (530, 330, 610)] {
                context.move(to: pt(x, top))
                context.addLine(to: pt(x, bottom))
            }
            context.strokePath()
            context.setFillColor(ink)
            for (x, y, h): (CGFloat, CGFloat, CGFloat) in
                [(210, 560, 140), (350, 470, 170), (490, 370, 190)] {
                context.addPath(CGPath(
                    roundedRect: box(x, y, 80, h),
                    cornerWidth: len(18),
                    cornerHeight: len(18),
                    transform: nil))
            }
            context.fillPath()

            // Ground shadow seating the button: radial fade squashed to an ellipse.
            context.saveGState()
            context.translateBy(x: pt(710, 556).x, y: pt(710, 556).y)
            context.scaleBy(x: 1, y: 30.0 / 120.0)
            context.drawRadialGradient(
                gradient([
                    (0, CGColor(gray: 0, alpha: 0.30)),
                    (0.7, CGColor(gray: 0, alpha: 0.12)),
                    (1, CGColor(gray: 0, alpha: 0)),
                ]),
                startCenter: .zero, startRadius: 0,
                endCenter: .zero, endRadius: len(120),
                options: [])
            context.restoreGState()

            // Pressed side wall below the dome.
            context.saveGState()
            context.addEllipse(in: box(614, 356, 192, 192))
            context.clip()
            context.drawLinearGradient(
                gradient([
                    (0, CGColor(srgbRed: 0.639, green: 0.071, blue: 0.125, alpha: 1)),
                    (1, CGColor(srgbRed: 0.435, green: 0.039, blue: 0.082, alpha: 1)),
                ]),
                start: pt(710, 356),
                end: pt(710, 548),
                options: [])
            context.restoreGState()

            // Glossy dome: radial gradient lit from the upper left. The SVG's
            // objectBoundingBox (0.36, 0.30, r 0.85) resolves to these grid values.
            context.saveGState()
            context.addEllipse(in: box(614, 318, 192, 192))
            context.clip()
            context.drawRadialGradient(
                gradient([
                    (0, CGColor(srgbRed: 1.0, green: 0.604, blue: 0.522, alpha: 1)),
                    (0.35, CGColor(srgbRed: 0.941, green: 0.306, blue: 0.275, alpha: 1)),
                    (0.75, CGColor(srgbRed: 0.788, green: 0.094, blue: 0.169, alpha: 1)),
                    (1, CGColor(srgbRed: 0.588, green: 0.063, blue: 0.122, alpha: 1)),
                ]),
                startCenter: pt(683, 376), startRadius: 0,
                endCenter: pt(683, 376), endRadius: len(163),
                options: .drawsAfterEndLocation)
            context.restoreGState()

            // Specular highlight: soft white ellipse tilted with the light.
            context.saveGState()
            context.translateBy(x: pt(676, 374).x, y: pt(676, 374).y)
            context.rotate(by: 24 * .pi / 180)
            context.scaleBy(x: 1, y: 26.0 / 40.0)
            context.drawRadialGradient(
                gradient([
                    (0, CGColor(gray: 1, alpha: 0.85)),
                    (0.6, CGColor(gray: 1, alpha: 0.35)),
                    (1, CGColor(gray: 1, alpha: 0)),
                ]),
                startCenter: .zero, startRadius: 0,
                endCenter: .zero, endRadius: len(40),
                options: [])
            context.restoreGState()
            return true
        }
    }

    private static func writePNG(_ image: NSImage, pixels: Int, to url: URL) throws {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixels,
            pixelsHigh: pixels,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .calibratedRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0) else { throw RenderError.bitmap }
        rep.size = NSSize(width: pixels, height: pixels)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(
            in: NSRect(x: 0, y: 0, width: pixels, height: pixels),
            from: .zero,
            operation: .copy,
            fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        guard let png = rep.representation(using: .png, properties: [:]) else {
            throw RenderError.bitmap
        }
        try png.write(to: url, options: .atomic)
    }

    private enum RenderError: Error {
        case bitmap
        case iconutil(Int32)
    }
}
