import Foundation

/// Görsel probları (B-8.3.2, S8.3): biçim sırası png → jpeg → gif → webp; her biçimin sihirli baytları
/// doğrulanır, tutmayan (kesik başlık dahil) bir sonraki proba düşer.
enum BinaryProbe {
    private static let order: [(CanonicalFormat, ImageFormat)] = [
        (.png, .png), (.jpeg, .jpeg), (.gif, .gif), (.webp, .webp),
    ]

    private static let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
    private static let jpegSignature: [UInt8] = [0xFF, 0xD8, 0xFF]
    private static let gif87a = Array("GIF87a".utf8)
    private static let gif89a = Array("GIF89a".utf8)
    private static let riff = Array("RIFF".utf8)
    private static let webp = Array("WEBP".utf8)

    /// Öğedeki imzası tutan görseller, prob sırasıyla (sınır denetimi çağırana aittir).
    static func images(in item: RawItem) -> [ImageItem] {
        order.compactMap { canonical, format in
            guard let data = item.formats[canonical], matches(data, format) else { return nil }
            return ImageItem(data: data, format: format)
        }
    }

    static func matches(_ data: Data, _ format: ImageFormat) -> Bool {
        switch format {
        case .png: return hasPrefix(data, pngSignature)
        case .jpeg: return hasPrefix(data, jpegSignature)
        case .gif: return hasPrefix(data, gif87a) || hasPrefix(data, gif89a)
        case .webp: return data.count >= 12 && hasPrefix(data, riff) && hasPrefix(data.dropFirst(8), webp)
        }
    }

    private static func hasPrefix(_ data: Data, _ signature: [UInt8]) -> Bool {
        data.count >= signature.count && data.prefix(signature.count).elementsEqual(signature)
    }
}
