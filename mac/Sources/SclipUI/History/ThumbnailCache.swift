import AppKit
import ImageIO
import SclipCore

@MainActor
public final class ThumbnailCache {
    public static let shared = ThumbnailCache()

    private let cache = NSCache<NSString, NSImage>()
    private var keysByEntryID: [EntryID: Set<String>] = [:]
    private var clearGeneration: UInt64 = 0
    private var entryGenerations: [EntryID: UInt64] = [:]

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

        let capturedClearGen = clearGeneration
        let capturedEntryGen = entryGenerations[entryID, default: 0]
        let maxPixelSize = max(24, Int(ceil(Metrics.thumb * max(scale, 1.0) * 2.0)))
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let cgImage = Self.decodeCGThumbnail(from: data, maxPixelSize: maxPixelSize)
            DispatchQueue.main.async {
                guard let self,
                      self.clearGeneration == capturedClearGen,
                      self.entryGenerations[entryID, default: 0] == capturedEntryGen,
                      let cgImage
                else {
                    completion(nil)
                    return
                }
                let nsImage = NSImage(
                    cgImage: cgImage,
                    size: NSSize(width: Metrics.thumb, height: Metrics.thumb)
                )
                self.storeImage(nsImage, entryID: entryID, keyString: keyString)
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
        let keyString = cacheKey(entryID: entryID, index: 0, scale: scale)
        if let hit = cache.object(forKey: keyString as NSString) {
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

        storeImage(image, entryID: entryID, keyString: keyString)
        completion(image)
    }

    public func remove(entryID: EntryID) {
        entryGenerations[entryID, default: 0] &+= 1
        guard let keys = keysByEntryID.removeValue(forKey: entryID) else { return }
        for key in keys {
            cache.removeObject(forKey: key as NSString)
        }
    }

    public func clear() {
        clearGeneration &+= 1
        entryGenerations.removeAll()
        keysByEntryID.removeAll()
        cache.removeAllObjects()
    }

    private func storeImage(_ image: NSImage, entryID: EntryID, keyString: String) {
        keysByEntryID[entryID, default: []].insert(keyString)
        cache.setObject(image, forKey: keyString as NSString)
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
