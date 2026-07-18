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
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let margin = size * 0.076
            let tile = rect.insetBy(dx: margin, dy: margin)
            let path = CGPath(
                roundedRect: tile,
                cornerWidth: tile.width * 0.245,
                cornerHeight: tile.height * 0.245,
                transform: nil)
            context.saveGState()
            context.addPath(path)
            context.clip()
            let colors = [
                CGColor(srgbRed: 1.0, green: 0.42, blue: 0.29, alpha: 1),
                CGColor(srgbRed: 0.79, green: 0.09, blue: 0.20, alpha: 1),
            ] as CFArray
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: [0, 1])!
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: rect.midX, y: rect.maxY),
                end: CGPoint(x: rect.midX, y: rect.minY),
                options: [])
            context.restoreGState()

            context.setStrokeColor(CGColor(gray: 1, alpha: 1))
            context.setLineWidth(size * 0.072)
            context.setLineCap(.round)
            context.addArc(
                center: CGPoint(x: rect.midX, y: size * 0.55),
                radius: size * 0.19,
                startAngle: 0,
                endAngle: .pi,
                clockwise: false)
            context.move(to: CGPoint(x: size * 0.31, y: size * 0.55))
            context.addLine(to: CGPoint(x: size * 0.31, y: size * 0.33))
            context.move(to: CGPoint(x: size * 0.69, y: size * 0.55))
            context.addLine(to: CGPoint(x: size * 0.69, y: size * 0.33))
            context.move(to: CGPoint(x: size * 0.25, y: size * 0.31))
            context.addLine(to: CGPoint(x: size * 0.75, y: size * 0.31))
            context.strokePath()

            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fillEllipse(in: CGRect(
                x: size * 0.45, y: size * 0.50,
                width: size * 0.10, height: size * 0.10))
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
