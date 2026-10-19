import Foundation

/// Düz metnin bağımsız SVG işaretlemesi olup olmadığı (`behavior.md` B-8.2.8).
public enum SvgMarkupHeuristic {
    private static let headLimit = 512

    public static func looksLikeSvg(_ text: String) -> Bool {
        let trimmed = TextWhitespace.trimLeading(text)
        if trimmed.isEmpty { return false }
        let head = String(decoding: Array(trimmed.utf16.prefix(headLimit)), as: UTF16.self).lowercased()
        let startsWithSvg = head.hasPrefix("<svg") || (head.hasPrefix("<?xml") && head.contains("<svg"))
        return startsWithSvg && trimmed.lowercased().contains("</svg>")
    }
}
