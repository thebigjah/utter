import AppKit

/// Utter's visual identity: a speech mark built from five rounded voice bars,
/// cream on deep ink, with a coral center bar.
enum Brand {
    static let ink = NSColor(srgbRed: 0.106, green: 0.133, blue: 0.220, alpha: 1)      // #1B2238
    static let inkLight = NSColor(srgbRed: 0.180, green: 0.220, blue: 0.345, alpha: 1) // #2E3858
    static let cream = NSColor(srgbRed: 0.953, green: 0.925, blue: 0.875, alpha: 1)    // #F3ECDF
    static let coral = NSColor(srgbRed: 0.910, green: 0.451, blue: 0.353, alpha: 1)    // #E8735A

    static let barHeights: [CGFloat] = [0.38, 0.72, 1.0, 0.72, 0.38]

    /// Draws the five-bar mark centered in `rect`.
    static func drawMark(in rect: CGRect, color: NSColor, accent: NSColor? = nil) {
        let count = CGFloat(barHeights.count)
        let barWidth = rect.width / (count * 2 - 1)
        for (i, h) in barHeights.enumerated() {
            let height = rect.height * h
            let bar = CGRect(x: rect.minX + CGFloat(i) * barWidth * 2,
                             y: rect.midY - height / 2,
                             width: barWidth, height: height)
            ((i == 2 ? accent : nil) ?? color).setFill()
            NSBezierPath(roundedRect: bar, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
        }
    }

    /// Template image for the menu bar, so macOS tints it for light and dark bars.
    static func menuBarImage(active: Bool = false) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            let mark = rect.insetBy(dx: 2, dy: active ? 2 : 3.5)
            drawMark(in: mark, color: .black)
            return true
        }
        image.isTemplate = true
        return image
    }

    /// Full-color app icon at a given pixel size.
    static func renderIcon(pixels: Int) -> Data? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let s = CGFloat(pixels)
        // macOS icon grid: 824/1024 body with a soft shadow.
        let body = CGRect(x: s * 0.098, y: s * 0.098, width: s * 0.804, height: s * 0.804)
        let shape = NSBezierPath(roundedRect: body, xRadius: s * 0.18, yRadius: s * 0.18)
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
        shadow.shadowBlurRadius = s * 0.025
        shadow.shadowOffset = NSSize(width: 0, height: -s * 0.012)
        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        ink.setFill()
        shape.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGradient(starting: inkLight, ending: ink)?.draw(in: shape, angle: -90)
        drawMark(in: body.insetBy(dx: body.width * 0.24, dy: body.height * 0.27), color: cream, accent: coral)
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }
}
