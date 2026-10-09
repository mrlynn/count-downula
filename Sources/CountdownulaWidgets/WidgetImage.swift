import ImageIO
import SwiftUI

/// Photos for widgets on every platform: decoded at no more than the size they're drawn, which keeps
/// the extension inside its memory limit, and handed to SwiftUI without UIKit or AppKit.
enum WidgetImage {
    static func image(from data: Data, maxPixelDimension: CGFloat) -> Image? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelDimension,
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        return Image(decorative: cgImage, scale: 1)
    }
}
