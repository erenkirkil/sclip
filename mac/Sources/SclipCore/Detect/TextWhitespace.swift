import Foundation

/// Boşluk kümeleri (`behavior.md` B-6.4.5).
enum TextWhitespace {
    /// ECMAScript `\s` kümesi (B-6.4.5 daraltma kümesi): U+0009–U+000D, U+0020, U+00A0, U+1680,
    /// U+2000–U+200A, U+2028, U+2029, U+202F, U+205F, U+3000, U+FEFF.
    static func isCollapseSet(_ v: UInt32) -> Bool {
        switch v {
        case 0x09...0x0D, 0x20, 0xA0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF:
            return true
        default:
            return false
        }
    }

    /// Dart `String.trim()` kümesi: daraltma kümesi + U+0085.
    static func isTrimSet(_ v: UInt32) -> Bool { v == 0x85 || isCollapseSet(v) }

    static func trim(_ s: String) -> String { trimmed(s, leading: true, trailing: true) }

    /// ECMAScript `\s` kümesindeki karakter dizilerini tek U+0020'ye indirir (B-6.4.5 adım 1).
    static func collapse(_ s: String) -> String {
        var out = String.UnicodeScalarView()
        var inRun = false
        for u in s.unicodeScalars {
            if isCollapseSet(u.value) {
                if !inRun { out.append(" ") }
                inRun = true
            } else {
                out.append(u)
                inRun = false
            }
        }
        return String(out)
    }

    static func trimLeading(_ s: String) -> String { trimmed(s, leading: true, trailing: false) }

    private static func trimmed(_ s: String, leading: Bool, trailing: Bool) -> String {
        let scalars = s.unicodeScalars
        var start = scalars.startIndex
        var end = scalars.endIndex
        if leading {
            while start < end, isTrimSet(scalars[start].value) { start = scalars.index(after: start) }
        }
        if trailing {
            while end > start {
                let prev = scalars.index(before: end)
                guard isTrimSet(scalars[prev].value) else { break }
                end = prev
            }
        }
        return String(scalars[start..<end])
    }

    /// Yalnız ASCII A–Z küçültülür (Unicode katlama istenmez: `ſ` → `s` gibi).
    static func asciiLowercased(_ s: String) -> String {
        var out = String.UnicodeScalarView()
        for u in s.unicodeScalars {
            if u.value >= 0x41 && u.value <= 0x5A, let l = Unicode.Scalar(u.value + 0x20) {
                out.append(l)
            } else {
                out.append(u)
            }
        }
        return String(out)
    }
}
