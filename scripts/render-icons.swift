#!/usr/bin/env swift
// Renders design/*.svg into the app's icon assets using AppKit's built-in SVG support.
//   design/app-icon.svg -> Resources/AppIcon.icns (+ design/app-icon.png preview)
//   design/mark-menubar.svg -> Resources/MenuBarIcon.png, MenuBarIcon@2x.png (template glyph)
//   design/app-icon-watch.svg -> Resources/Watch/Assets.xcassets/AppIcon.appiconset/icon-1024.png
//   design/mark.svg     -> design/mark.png preview
// Run from the repo root: swift scripts/render-icons.swift
import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let design = root.appending(path: "design")
let resources = root.appending(path: "Resources")

func render(_ svg: URL, pixels: Int, to output: URL, opaque: Bool = false) throws {
    guard let image = NSImage(contentsOf: svg) else { fatalError("Could not load \(svg.path)") }
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { fatalError("Could not allocate bitmap") }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()

    guard opaque else {
        try rep.representation(using: .png, properties: [:])!.write(to: output)
        return
    }
    // Flatten to RGB with no alpha channel (required for watchOS/iOS App Store icons).
    let flat = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                         space: CGColorSpace(name: CGColorSpace.sRGB)!,
                         bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    flat.draw(rep.cgImage!, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
    let destination = CGImageDestinationCreateWithURL(output as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, flat.makeImage()!, nil)
    CGImageDestinationFinalize(destination)
}

// App icon
let iconset = FileManager.default.temporaryDirectory.appending(path: "AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
let appIcon = design.appending(path: "app-icon.svg")
for size in [16, 32, 128, 256, 512] {
    try render(appIcon, pixels: size, to: iconset.appending(path: "icon_\(size)x\(size).png"))
    try render(appIcon, pixels: size * 2, to: iconset.appending(path: "icon_\(size)x\(size)@2x.png"))
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", resources.appending(path: "AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
try render(appIcon, pixels: 512, to: design.appending(path: "app-icon.png"))

// watchOS icon (single 1024px source; the system masks it to a circle)
try render(design.appending(path: "app-icon-watch.svg"), pixels: 1024,
           to: resources.appending(path: "Watch/Assets.xcassets/AppIcon.appiconset/icon-1024.png"), opaque: true)

// Menu bar glyph (18pt)
let mark = design.appending(path: "mark.svg")
let menuBarMark = design.appending(path: "mark-menubar.svg")
try render(menuBarMark, pixels: 18, to: resources.appending(path: "MenuBarIcon.png"))
try render(menuBarMark, pixels: 36, to: resources.appending(path: "MenuBarIcon@2x.png"))
try render(mark, pixels: 512, to: design.appending(path: "mark.png"))

print("Rendered AppIcon.icns and MenuBarIcon assets")
