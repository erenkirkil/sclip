import AppKit
import ImageIO
import SclipCore

@MainActor
public final class ThumbnailCache {
    public static let shared = ThumbnailCache()

    private let cache = NSCache<NSString, NSImage>()

    public init(countLimit: Int = 256) {
        cache.countLimit = countLimit
    }

    public func cachedImage(entryID: EntryID, index: Int = 0, scale: CGFloat) -> NSImage? {
        let key = cacheKey(entryID: entryID, index: index, scale: scale) as NSString
        return cache.object(forKey: key)
    }

    public func loadThumbnail(
        entryID: EntryID,
        index: Int = 0,
        data: Data,
        scale: CGFloat,
        completion: @escaping @MainActor (NSImage?) -> Void
    ) {
        let keyString = cacheKey(entryID: entryID, index: index, scale: scale)
        if let hit = cache.object(forKey: keyString as NSString) {
            completion(hit)
            return
        }

        let maxPixelSize = max(24, Int(ceil(Metrics.thumb * max(scale, 1.0) * 2.0)))
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let cgImage = Self.decodeCGThumbnail(from: data, maxPixelSize: maxPixelSize)
            DispatchQueue.main.async {
                guard let cgImage else {
                    completion(nil)
                    return
                }
                let nsImage = NSImage(
                    cgImage: cgImage,
                    size: NSSize(width: Metrics.thumb, height: Metrics.thumb)
                )
                self?.cache.setObject(nsImage, forKey: keyString as NSString)
                completion(nsImage)
            }
        }
    }

    public func loadSvgThumbnail(
        entryID: EntryID,
        xml: String,
        scale: CGFloat,
        completion: @escaping @MainActor (NSImage?) -> Void
    ) {
        let key = cacheKey(entryID: entryID, index: 0, scale: scale) as NSString
        if let hit = cache.object(forKey: key) {
            completion(hit)
            return
        }

        let data = Data(xml.utf8)
        guard SvgSanitizer.isSafe(data),
              let image = NSImage(data: data),
              image.isValid,
              image.size.width > 0,
              image.size.height > 0
        else {
            completion(nil)
            return
        }

        cache.setObject(image, forKey: key)
        completion(image)
    }

    public func clear() {
        cache.removeAllObjects()
    }

    private func cacheKey(entryID: EntryID, index: Int, scale: CGFloat) -> String {
        "\(entryID.raw):\(index):\(Int(round(max(scale, 1.0) * 100)))"
    }

    nonisolated private static func decodeCGThumbnail(from data: Data, maxPixelSize: Int) -> CGImage? {
        guard !data.isEmpty else { return nil }
        let sourceOptions: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions as CFDictionary) else {
            return nil
        }
        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary)
    }
}
