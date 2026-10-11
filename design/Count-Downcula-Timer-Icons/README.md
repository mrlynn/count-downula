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
