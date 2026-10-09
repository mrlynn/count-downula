# Count Downcula — The Count

Approved Dracula mascot with integrated countdown progress ring, cream clock ticks and hand, burgundy/red/cream palette, and text-free icons.

## Installation

- **iOS, modern appearance support:** Copy `iOS/Adaptive/AppIcon.appiconset` into your asset catalog. This contains 1024 px default light and dark appearance images. Select AppIcon as the app icon source in Xcode.
- **iOS, explicit sizes:** Choose `iOS/Light/AppIcon.appiconset` or `iOS/Dark/AppIcon.appiconset` for a complete iPhone/iPad set. Use one catalog, not both with the same name.
- **macOS:** Choose the Light or Dark `AppIcon.appiconset` in `macOS/`. These include all 16–1024 px representations. Alternatively use the provided ICNS or iconset.
- iOS images are opaque square PNGs; the system applies the icon shape. macOS images have a rounded tile with transparent outer padding.

## Files and design

`Masters/` includes 1024 px PNGs for both platforms and appearances. `Mascot-original.png` retains the original generated transparent artwork. `Preview.png` includes actual-pixel-size checks.

This package uses the countdown-dial artwork approved in this chat. It supersedes the earlier mascot-only package as the intended app identity.

Artwork was created using the built-in image generation tool. Prompt: preserve the friendly Dracula face and integrate the cape into a bold red incomplete countdown ring, with cream ticks and a visible clock hand; compact centered composition, transparent background, no text or digits. The same artwork is used in both appearances.

PNG dimensions, catalog file references, opacity, and ICNS contents were checked during packaging. Review the supplied preview and test the selected catalog in your app before release.

## Where these are used (in this repo)

- `Resources/iOS/Assets.xcassets/AppIcon.appiconset`: the Adaptive set (light and dark), for the iPhone/iPad app and the App Clip.
- `Resources/AppIcon.icns`: the macOS Dark ICNS.
- `Resources/TV/Assets.xcassets/App Icon & Top Shelf Image.brandassets`: the Apple TV's layered icon and Top Shelf images, rendered from `Mascot-original.png` by `scripts/render-tv-assets.swift`.
- `Resources/Watch/Assets.xcassets/AppIcon.appiconset/icon-1024.png`: `Masters/Count-Downcula-Dark-1024.png` (watchOS masks it to a circle).
- `site/assets/app-icon.png`, `server/assets/app-icon.png`, `design/app-icon.png`: the macOS dark tile at 512 px. `site/assets/apple-touch-icon.png` (180) and `favicon.png` (64) come from the dark masters.

The drawn fang mark (`Sources/Shared/FangMark.swift`) stays for widgets, complications, Live Activities and progress dials, where the illustration is too detailed.
