import Foundation

/// Dosya adı çıkarma (`behavior.md` B-6.4.6).
enum FileName {
    static func basename(_ url: URL) -> String {
        basename(path: url.isFileURL ? url.path : url.absoluteString)
    }

    /// Sondaki `/` ve `\` atılır, kalanın son bileşeni döner; hiçbir şey kalmazsa yolun tamamı.
    static func basename(path: String) -> String {
        let units = Array(path.utf16)
        func isSeparator(_ u: UInt16) -> Bool { u == 0x2F || u == 0x5C }
        guard let last = units.lastIndex(where: { !isSeparator($0) }) else { return path }
        let start = units[...last].lastIndex(where: isSeparator).map { $0 + 1 } ?? 0
        return String(decoding: units[start...last], as: UTF16.self)
    }
}
