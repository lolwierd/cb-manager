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
    private let dimensionsCache = NSCache<NSString, NSValue>()
    private let lock = NSLock()
    private var inFlightThumbnailLoads: [NSString: DispatchGroup] = [:]
    private var cacheKeysByPath: [NSString: Set<NSString>] = [:]

    private init() {
        cache.countLimit = 180
        cache.totalCostLimit = 64 * 1024 * 1024
        dimensionsCache.countLimit = 1024
    }

    /// Create or retrieve a cached thumbnail for the image at `path`.
    ///
    /// Uses `CGImageSourceCreateThumbnailAtIndex` which reads only enough
    /// of the file to produce a small image — orders of magnitude faster
    /// than loading the full PNG/TIFF into memory.
    func thumbnail(for path: String, maxPixelSize: CGFloat = 120) -> NSImage? {
        let key = cacheKey(for: path, maxPixelSize: maxPixelSize)

        if let cached = cache.object(forKey: key) {
            return cached
        }

        let (loadGroup, createdLoadGroup) = lock.withLock { () -> (DispatchGroup, Bool) in
            if let existing = inFlightThumbnailLoads[key] {
                return (existing, false)
            }

            let group = DispatchGroup()
            group.enter()
            inFlightThumbnailLoads[key] = group
            return (group, true)
        }

        if !createdLoadGroup {
            loadGroup.wait()
            return cache.object(forKey: key)
        }

        defer {
            lock.withLock {
                loadGroup.leave()
                inFlightThumbnailLoads.removeValue(forKey: key)
            }
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
        let cost = cgImage.bytesPerRow * cgImage.height
        cache.setObject(image, forKey: key, cost: cost)
        lock.withLock {
            var keys = cacheKeysByPath[url.path as NSString] ?? []
            keys.insert(key)
            cacheKeysByPath[url.path as NSString] = keys
        }
        return image
    }

    func cachedThumbnail(for path: String, maxPixelSize: CGFloat = 120) -> NSImage? {
        cache.object(forKey: cacheKey(for: path, maxPixelSize: maxPixelSize))
    }

    /// Read pixel dimensions from the image file header without loading the full image.
    static func imageDimensions(at path: String) -> CGSize? {
        shared.cachedImageDimensions(at: path)
    }

    private func cachedImageDimensions(at path: String) -> CGSize? {
        let key = path as NSString
        if let cached = dimensionsCache.object(forKey: key) {
            return cached.sizeValue
        }

        let url = URL(fileURLWithPath: path)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else {
            return nil
        }

        guard let width = properties[kCGImagePropertyPixelWidth as String] as? CGFloat,
              let height = properties[kCGImagePropertyPixelHeight as String] as? CGFloat else {
            return nil
        }

        let size = CGSize(width: width, height: height)
        dimensionsCache.setObject(NSValue(size: size), forKey: key)
        return size
    }

    /// Evict a specific entry (e.g. after deletion).
    func evict(path: String) {
        let pathKey = path as NSString
        let keys = lock.withLock { cacheKeysByPath.removeValue(forKey: pathKey) ?? [] }
        for key in keys {
            cache.removeObject(forKey: key)
        }
        dimensionsCache.removeObject(forKey: pathKey)
    }

    private func cacheKey(for path: String, maxPixelSize: CGFloat) -> NSString {
        "\(path)_\(Int(maxPixelSize.rounded()))" as NSString
    }
}
