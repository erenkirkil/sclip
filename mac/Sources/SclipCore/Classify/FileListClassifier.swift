import Foundation

/// Dosya listesi (B-8.3.8, B-8.6.5): uzantıların hepsi png / jpg / jpeg / gif / webp, her dosya 1 bayt – sınır
/// arası ve toplam sınır içindeyse sırayla okunup `image` (1) / `imageSet` (≥ 2); aksi her durumda `files`.
struct FileListClassifier {
    let caps: SizeCaps
    let files: any FileReading

    func classify(_ urls: [URL]) -> Payload {
        guard let images = readImages(urls) else { return .files(urls) }
        return images.count == 1 ? .image(images[0]) : .imageSet(images)
    }

    private func readImages(_ urls: [URL]) -> [ImageItem]? {
        let limit = caps.fileImageBytes
        var formats: [ImageFormat] = []
        var total = 0
        for url in urls {
            guard let format = Self.imageFormat(url),
                  let size = files.size(of: url), size >= 1, size <= limit
            else { return nil }
            total += size
            guard total <= limit else { return nil }
            formats.append(format)
        }
        // Boyut okuma ile okuma arasında dosya büyüyebilir: okuma `sınır + 1` baytla sınırlıdır ve okunan
        // baytlar yeniden denetlenir.
        var items: [ImageItem] = []
        var readTotal = 0
        let readCap = limit == Int.max ? limit : limit + 1
        for (url, format) in zip(urls, formats) {
            guard let data = try? files.read(url, upTo: readCap), !data.isEmpty, data.count <= limit
            else { return nil }
            readTotal += data.count
            guard readTotal <= limit else { return nil }
            items.append(ImageItem(data: data, format: format))
        }
        return items.isEmpty ? nil : items
    }

    /// Uzantı dosya adının son `.`'sından sonrasıdır, büyük/küçük harf duyarsız; baştaki nokta uzantı değildir.
    static func imageFormat(_ url: URL) -> ImageFormat? {
        let name = FileName.basename(url)
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return nil }
        switch name[name.index(after: dot)...].lowercased() {
        case "png": return .png
        case "jpg", "jpeg": return .jpeg
        case "gif": return .gif
        case "webp": return .webp
        default: return nil
        }
    }
}
