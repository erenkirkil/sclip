import Foundation

/// Bir girdinin içeriği. Türüne göre hash kuralı `ContentHash.of` içindedir.
public enum Payload: Sendable, Equatable {
    case text(String)
    /// `original` ve `uri` kırpılmış orijinal metindir (E21, B-8.1.2); `display` görünen metindir.
    case url(original: String, uri: String, display: String)
    case color(original: String, normalized: String, argb: UInt32)
    case image(ImageItem)
    /// En az iki görsel.
    case imageSet([ImageItem])
    case svg(String)
    case files([URL])
    case pdf(Data)
    case richText(plain: String, html: String, rtf: Data?)

    public var kind: EntryKind {
        switch self {
        case .text: return .text
        case .url: return .url
        case .color: return .color
        case .image: return .image
        case .imageSet: return .imageSet
        case .svg: return .svg
        case .files: return .files
        case .pdf: return .pdf
        case .richText: return .richText
        }
    }
}
