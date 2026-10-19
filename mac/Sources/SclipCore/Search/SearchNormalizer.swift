import Foundation

/// Arama normalizasyonu (`behavior.md` B-6.5.3). Tüm adımlar Unicode skaleri üzerindedir.
public enum SearchNormalizer {
    public static func normalize(_ s: String) -> String {
        var out = String.UnicodeScalarView()
        var pendingSpace = false
        for scalar in s.unicodeScalars {
            for lowered in lowercased(scalar) {
                if isSearchSpace(lowered.value) {
                    pendingSpace = true
                    continue
                }
                if pendingSpace {
                    if !out.isEmpty { out.append(" ") }
                    pendingSpace = false
                }
                out.append(fold(lowered))
            }
        }
        return String(out)
    }

    /// (1) `I`, `U+0130`, `U+0131` → `i`; (2) skaler başına küçük harf eşlemesi. `String.lowercased()`
    /// bağlama duyarlı kurallar (Yunanca son sigma) uyguladığı için kullanılmaz (Dart paritesi).
    private static func lowercased(_ scalar: Unicode.Scalar) -> String.UnicodeScalarView {
        switch scalar.value {
        case 0x49, 0x130, 0x131: return "i".unicodeScalars
        default: return scalar.properties.lowercaseMapping.unicodeScalars
        }
    }

    private static func isSearchSpace(_ v: UInt32) -> Bool {
        v == 0x20 || (v >= 0x09 && v <= 0x0D) || v == 0xA0
    }

    /// (4) `ş→s ğ→g ü→u ö→o ç→c â→a î→i û→u`.
    private static func fold(_ u: Unicode.Scalar) -> Unicode.Scalar {
        switch u.value {
        case 0x15F: return "s"
        case 0x11F: return "g"
        case 0xFC, 0xFB: return "u"
        case 0xF6: return "o"
        case 0xE7: return "c"
        case 0xE2: return "a"
        case 0xEE: return "i"
        default: return u
        }
    }
}
