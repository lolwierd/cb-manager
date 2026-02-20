import AppKit
import ImageIO

/// Efficient thumbnail generation and caching using ImageIO.
///
/// Uses `CGImageSource` to create thumbnails without decoding the full image,
/// and `NSCache` for in-memory caching. Also provides image dimensions by
/// reading only the file header.
final class ThumbnailCache: @unchecked Sendable {
    static let shared = ThumbnailCache()

    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 300
    }

    /// Create or retrieve a cached thumbnail for the image at `path`.
    ///
    /// Uses `CGImageSourceCreateThumbnailAtIndex` which reads only enough
    /// of the file to produce a small image — orders of magnitude faster
    /// than loading the full PNG/TIFF into memory.
    func thumbnail(for path: String, maxPixelSize: CGFloat = 120) -> NSImage? {
        let key = "\(path)_\(Int(maxPixelSize))" as NSString

        if let cached = cache.object(forKey: key) {
            return cached
        }

        let url = URL(fileURLWithPath: path)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        cache.setObject(image, forKey: key)
        return image
    }

    /// Read pixel dimensions from the image file header without loading the full image.
    static func imageDimensions(at path: String) -> CGSize? {
        let url = URL(fileURLWithPath: path)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else {
            return nil
        }

        guard let width = properties[kCGImagePropertyPixelWidth as String] as? CGFloat,
              let height = properties[kCGImagePropertyPixelHeight as String] as? CGFloat else {
            return nil
        }

        return CGSize(width: width, height: height)
    }

    /// Evict a specific entry (e.g. after deletion).
    func evict(path: String, maxPixelSize: CGFloat = 120) {
        let key = "\(path)_\(Int(maxPixelSize))" as NSString
        cache.removeObject(forKey: key)
    }
}
