#!/usr/bin/env swift
// Renders the Apple TV brand assets from the approved Count artwork (design/count-icon):
//   Resources/TV/Assets.xcassets/App Icon & Top Shelf Image.brandassets
// tvOS icons are layered for the focus parallax: an opaque back layer (a burgundy night with
// stars), a middle glow, and the Count with his countdown dial in front. The Top Shelf images
// (shown when the app has nothing of its own to show there) use the same night, the Count and
// the wordmark. Run from the repo root: swift scripts/render-tv-assets.swift
import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let mascotURL = root.appending(path: "design/count-icon/Mascot-original.png")
guard let mascot = NSImage(contentsOf: mascotURL)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fatalError("Could not load \(mascotURL.path)")
}
let catalog = root.appending(path: "Resources/TV/Assets.xcassets")
let brand = catalog.appending(path: "App Icon & Top Shelf Image.brandassets")

// The icon's own background (#200B16) and the brand's blood red.
let night = CGColor(red: 0.125, green: 0.043, blue: 0.086, alpha: 1)
let deep = CGColor(red: 0.06, green: 0.02, blue: 0.045, alpha: 1)
let blood = CGColor(red: 0.85, green: 0.09, blue: 0.2, alpha: 1)
let cream = CGColor(red: 0.98, green: 0.94, blue: 0.86, alpha: 1)

enum Layer { case back, middle, front }

func context(_ width: Int, _ height: Int, opaque: Bool) -> CGContext {
    CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
              space: CGColorSpace(name: CGColorSpace.sRGB)!,
              bitmapInfo: opaque ? CGImageAlphaInfo.noneSkipLast.rawValue : CGImageAlphaInfo.premultipliedLast.rawValue)!
}

func write(_ ctx: CGContext, to url: URL) {
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(destination)
}

/// The night: a soft radial lift in the middle and a scatter of stars from a fixed seed.
func drawNight(_ ctx: CGContext, _ w: CGFloat, _ h: CGFloat, center: CGPoint) {
    ctx.setFillColor(deep)
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [night, deep] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: max(w, h) * 0.75, options: [.drawsAfterEndLocation])
    var seed: UInt64 = 0xC0FFEE
    func next() -> CGFloat {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat(seed >> 33) / CGFloat(UInt64(1) << 31)
    }
    let count = Int(w * h / 9_000)
    for _ in 0..<count {
        let x = next() * w, y = next() * h, r = (0.4 + next() * 1.2) * h / 480
        ctx.setFillColor(CGColor(red: 1, green: 0.95, blue: 0.9, alpha: 0.15 + next() * 0.45))
        ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
    }
}

/// A red glow behind the Count, so the dial seems lit from within when the icon tilts.
func drawGlow(_ ctx: CGContext, center: CGPoint, radius: CGFloat) {
    let colors = [blood.copy(alpha: 0.55)!, blood.copy(alpha: 0)!] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 1])!
    ctx.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
}

func drawMascot(_ ctx: CGContext, center: CGPoint, side: CGFloat) {
    ctx.interpolationQuality = .high
    ctx.draw(mascot, in: CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side))
}

/// One icon layer at a pixel size. The Count fills most of the height, inside tvOS's safe zone.
func iconLayer(_ layer: Layer, width: Int, height: Int) -> CGContext {
    let w = CGFloat(width), h = CGFloat(height), center = CGPoint(x: w / 2, y: h / 2)
    let ctx = context(width, height, opaque: layer == .back)
    switch layer {
    case .back: drawNight(ctx, w, h, center: center)
    case .middle: drawGlow(ctx, center: center, radius: h * 0.62)
    case .front: drawMascot(ctx, center: center, side: h * 0.86)
    }
    return ctx
}

/// The Top Shelf: the night, and the Count beside the wordmark, centered as a pair.
func topShelf(width: Int, height: Int) -> CGContext {
    let w = CGFloat(width), h = CGFloat(height)
    let serif = NSFontDescriptor.preferredFontDescriptor(forTextStyle: .largeTitle).withDesign(.serif)
        ?? NSFont.systemFont(ofSize: 10).fontDescriptor
    let font = NSFont(descriptor: serif.addingAttributes([.traits: [NSFontDescriptor.TraitKey.weight: NSFont.Weight.bold]]), size: h * 0.15)
        ?? NSFont.boldSystemFont(ofSize: h * 0.15)
    let text = NSAttributedString(string: "Count Downcula", attributes: [.font: font, .foregroundColor: NSColor(cgColor: cream)!])
    let line = CTLineCreateWithAttributedString(text)
    let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)

    let side = h * 0.9, gap = h * 0.08
    let start = (w - (side + gap + bounds.width)) / 2
    let countCenter = CGPoint(x: start + side / 2, y: h / 2)
    let ctx = context(width, height, opaque: true)
    drawNight(ctx, w, h, center: CGPoint(x: w / 2, y: h / 2))
    drawGlow(ctx, center: countCenter, radius: h * 0.7)
    drawMascot(ctx, center: countCenter, side: side)
    ctx.textPosition = CGPoint(x: start + side + gap - bounds.minX, y: h / 2 - bounds.midY)
    CTLineDraw(line, ctx)
    return ctx
}

// MARK: - Catalog JSON

let info = #"  "info" : { "author" : "xcode", "version" : 1 }"#

func json(_ url: URL, _ body: String) {
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! "{\n\(body)\(body.isEmpty ? "" : ",\n")\(info)\n}\n".write(to: url, atomically: true, encoding: .utf8)
}

func imageset(_ dir: URL, idiom: String, files: [(name: String, scale: String)]) {
    let images = files.map { #"    { "filename" : "\#($0.name)", "idiom" : "\#(idiom)", "scale" : "\#($0.scale)" }"# }.joined(separator: ",\n")
    json(dir.appending(path: "Contents.json"), "  \"images\" : [\n\(images)\n  ]")
}

func imagestack(_ name: String, idiom: String, sizes: [(scale: String, width: Int, height: Int)]) {
    let stack = brand.appending(path: "\(name).imagestack")
    let layers: [(String, Layer)] = [("Front", .front), ("Middle", .middle), ("Back", .back)]
    json(stack.appending(path: "Contents.json"),
         "  \"layers\" : [\n" + layers.map { #"    { "filename" : "\#($0.0).imagestacklayer" }"# }.joined(separator: ",\n") + "\n  ]")
    for (layerName, layer) in layers {
        let dir = stack.appending(path: "\(layerName).imagestacklayer")
        json(dir.appending(path: "Contents.json"), "")
        let content = dir.appending(path: "Content.imageset")
        var files: [(String, String)] = []
        for size in sizes {
            let file = "\(layerName.lowercased())\(size.scale == "1x" ? "" : "@\(size.scale)").png"
            write(iconLayer(layer, width: size.width, height: size.height), to: content.appending(path: file))
            files.append((file, size.scale))
        }
        imageset(content, idiom: idiom, files: files)
    }
}

try? FileManager.default.removeItem(at: brand)
json(catalog.appending(path: "Contents.json"), "")
imagestack("App Icon", idiom: "tv", sizes: [("1x", 400, 240), ("2x", 800, 480)])
imagestack("App Icon - App Store", idiom: "tv-marketing", sizes: [("1x", 1280, 768)])
for (name, width) in [("Top Shelf Image", 1920), ("Top Shelf Image Wide", 2320)] {
    let dir = brand.appending(path: "\(name).imageset")
    write(topShelf(width: width, height: 720), to: dir.appending(path: "shelf.png"))
    write(topShelf(width: width * 2, height: 1440), to: dir.appending(path: "shelf@2x.png"))
    imageset(dir, idiom: "tv", files: [("shelf.png", "1x"), ("shelf@2x.png", "2x")])
}
json(brand.appending(path: "Contents.json"), """
  "assets" : [
    { "filename" : "App Icon - App Store.imagestack", "idiom" : "tv", "role" : "primary-app-icon", "size" : "1280x768" },
    { "filename" : "App Icon.imagestack", "idiom" : "tv", "role" : "primary-app-icon", "size" : "400x240" },
    { "filename" : "Top Shelf Image Wide.imageset", "idiom" : "tv", "role" : "top-shelf-image-wide", "size" : "2320x720" },
    { "filename" : "Top Shelf Image.imageset", "idiom" : "tv", "role" : "top-shelf-image", "size" : "1920x720" }
  ]
""")
print("Rendered \(brand.path)")
