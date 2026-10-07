import ImageIO
import UIKit

enum ImageDownsampling {
    /// Decodes at most `maxPixelDimension` on the longest edge, without loading the full-size bitmap.
    /// Keeps 48 MP camera photos cheap in the app and inside the widget extension's memory limit.
    static func image(from data: Data, maxPixelDimension: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelDimension,
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    /// JPEG at no more than `maxPixelDimension`, flattened onto white so transparent images don't turn black.
    static func jpegData(from data: Data, maxPixelDimension: CGFloat, quality: CGFloat = 0.85) -> Data? {
        guard let image = image(from: data, maxPixelDimension: maxPixelDimension) else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let rect = CGRect(origin: .zero, size: image.size)
        return UIGraphicsImageRenderer(size: image.size, format: format).jpegData(withCompressionQuality: quality) { context in
            UIColor.white.setFill()
            context.fill(rect)
            image.draw(in: rect)
        }
    }
}
