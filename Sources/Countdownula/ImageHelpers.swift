import AppKit

extension NSImage {
    /// The fanged-timer logo as an 18pt template glyph; falls back to an SF Symbol
    /// when running outside the .app bundle (e.g. `swift run`).
    static var countdownulaMark: NSImage? {
        let image = NSImage(named: "MenuBarIcon")
            ?? NSImage(systemSymbolName: "hourglass", accessibilityDescription: nil)
        image?.size = NSSize(width: 18, height: 18)
        image?.isTemplate = true
        return image
    }

    var pixelSize: CGSize {
        if let cg = cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return CGSize(width: cg.width, height: cg.height)
        }
        return size
    }

    /// Re-encodes as JPEG, shrinking so the longest edge is at most `maxPixelDimension`.
    func jpegData(maxPixelDimension: CGFloat, quality: Double = 0.85) -> Data? {
        let source = pixelSize
        guard source.width > 0, source.height > 0 else { return nil }
        let scale = min(1, maxPixelDimension / max(source.width, source.height))
        let width = Int(source.width * scale), height = Int(source.height * scale)

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        draw(in: NSRect(x: 0, y: 0, width: width, height: height), from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()

        return rep.representation(using: .jpeg, properties: [.compressionFactor: quality])
    }

    /// A rounded, aspect-filled square thumbnail suitable for a menu bar button.
    func roundedThumbnail(side: CGFloat, cornerRadius: CGFloat = 4) -> NSImage {
        let original = self
        return NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius).addClip()
            let s = original.size
            let scale = max(rect.width / s.width, rect.height / s.height)
            let w = s.width * scale, h = s.height * scale
            original.draw(in: NSRect(x: (rect.width - w) / 2, y: (rect.height - h) / 2, width: w, height: h))
            return true
        }
    }
}
