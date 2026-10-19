import CryptoKit
import Foundation

/// İçerik hash'i (B-8.1.5–B-8.1.7). Hex her zaman küçük harfli ilk 16 karakterdir.
public enum ContentHash {
    /// `"p:" + hex16(sha256(utf8("p:" + value)))`.
    public static func text(_ prefix: String, _ value: String) -> String {
        "\(prefix):" + hex16(Data("\(prefix):\(value)".utf8))
    }

    /// `"p:" + uzunluk + ":" + hex16(sha256(data))`; bayt boyutundan bağımsız tam SHA-256 (E35).
    public static func bytes(_ prefix: String, _ data: Data) -> String {
        "\(prefix):\(data.count):" + hex16(data)
    }

    /// `"is:" + n + ":" + hex16(sha256(utf8(join("|", uzunluk + ":" + hex16(sha256(öğe))))))`.
    /// Sıraya duyarlı, biçimleri yok sayar; hash'lenen dizede önek yoktur (B-8.1.7).
    public static func imageSet(_ items: [ImageItem]) -> String {
        let joined = items.map { "\($0.data.count):" + hex16($0.data) }.joined(separator: "|")
        return "is:\(items.count):" + hex16(Data(joined.utf8))
    }

    public static func of(_ payload: Payload) -> String {
        switch payload {
        case .text(let s): return text("t", s)
        case .url(let original, _, _): return text("u", original)
        case .color(_, let normalized, _): return text("c", normalized)
        case .svg(let xml): return text("s", xml)
        case .richText(let plain, let html, _): return text("r", plain + "\u{0}" + html)
        case .files(let urls): return text("f", urls.map(\.absoluteString).joined(separator: "|"))
        case .image(let item): return bytes("i", item.data)
        case .pdf(let data): return bytes("p", data)
        case .imageSet(let items): return imageSet(items)
        }
    }

    private static func hex16(_ data: Data) -> String {
        SHA256.hash(data: data).prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}
