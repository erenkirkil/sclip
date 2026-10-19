import Foundation

/// Metin algılama sonucu. Bağlayıcı kural: `spec/behavior.md` §8.2.
public enum TextDetection: Sendable, Equatable {
    case url(uri: String)
    case color(ParsedColor)
    case email(uri: String)
    case phone(uri: String)
    case svg
    case none

    /// Ham metni Dart `trim()` kümesiyle kırpar; sıra url → color → email → phone → svg.
    public static func detect(_ raw: String) -> TextDetection {
        let trimmed = TextWhitespace.trim(raw)
        if trimmed.isEmpty { return .none }
        if let uri = UrlDetector.detect(trimmed) { return .url(uri: uri) }
        if let color = ColorParser.parse(trimmed) { return .color(color) }
        if let uri = ContactDetector.mailto(trimmed) { return .email(uri: uri) }
        if let uri = ContactDetector.tel(trimmed) { return .phone(uri: uri) }
        if SvgMarkupHeuristic.looksLikeSvg(trimmed) { return .svg }
        return .none
    }
}
