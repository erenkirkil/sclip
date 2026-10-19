import Foundation

public struct ParsedColor: Sendable, Equatable {
    /// Küçük harfli metin (B-8.2.5); yalnız swatch ve hash içindir.
    public let normalized: String
    public let argb: UInt32

    public init(normalized: String, argb: UInt32) {
        self.normalized = normalized
        self.argb = argb
    }
}

/// Renk ayrıştırma (`behavior.md` B-8.2.2–B-8.2.5). Hex için `#` zorunlu (E22); rgba alfası doğru
/// ayrıştırılır (E23); yuvarlama sıfırdan uzağa. Rakamlar yalnız ASCII `[0-9]`.
public enum ColorParser {
    private static let ws = #"[\t\n\u000B\f\r    -     　﻿]*"#
    private static let alpha = #"(?:,\#(ws)(0|1|0?\.[0-9]+)\#(ws))?"#

    private static let hexRegex = try! NSRegularExpression(pattern: #"\A#(?:[0-9a-f]{3,4}|[0-9a-f]{6}|[0-9a-f]{8})\z"#)
    private static let rgbRegex = try! NSRegularExpression(
        pattern: #"\Argba?\(\#(ws)([0-9]{1,3})\#(ws),\#(ws)([0-9]{1,3})\#(ws),\#(ws)([0-9]{1,3})\#(ws)"#
            + alpha + #"\)\z"#)
    private static let hslRegex = try! NSRegularExpression(
        pattern: #"\Ahsla?\(\#(ws)([0-9]{1,3}(?:\.[0-9]+)?)(?:deg)?\#(ws),\#(ws)([0-9]{1,3}(?:\.[0-9]+)?)%\#(ws),"#
            + #"\#(ws)([0-9]{1,3}(?:\.[0-9]+)?)%\#(ws)"# + alpha + #"\)\z"#)

    public static func parse(_ trimmed: String) -> ParsedColor? {
        let text = TextWhitespace.asciiLowercased(trimmed)
        let range = NSRange(location: 0, length: text.utf16.count)
        if hexRegex.firstMatch(in: text, range: range) != nil {
            return hex(text).map { ParsedColor(normalized: text, argb: $0) }
        }
        if let m = rgbRegex.firstMatch(in: text, range: range) {
            return rgb(text, m).map { ParsedColor(normalized: text, argb: $0) }
        }
        if let m = hslRegex.firstMatch(in: text, range: range) {
            return hsl(text, m).map { ParsedColor(normalized: text, argb: $0) }
        }
        return nil
    }

    // MARK: - Hex

    private static func hex(_ text: String) -> UInt32? {
        var digits = Array(text.utf8.dropFirst())
        if digits.count <= 4 { digits = digits.flatMap { [$0, $0] } }  // #RGB(A) → #RRGGBB(AA)
        guard let value = UInt32(String(decoding: digits, as: UTF8.self), radix: 16) else { return nil }
        // #RRGGBBAA: alfa sonda → 0xAARRGGBB.
        return digits.count == 8 ? (value << 24) | (value >> 8) : 0xFF00_0000 | value
    }

    // MARK: - rgb()

    private static func rgb(_ text: String, _ m: NSTextCheckingResult) -> UInt32? {
        guard let r = group(text, m, 1).flatMap({ Int($0) }),
              let g = group(text, m, 2).flatMap({ Int($0) }),
              let b = group(text, m, 3).flatMap({ Int($0) })
        else { return nil }
        let a = group(text, m, 4).flatMap(alphaByte) ?? 255
        return pack(a, min(r, 255), min(g, 255), min(b, 255))
    }

    // MARK: - hsl()

    private static func hsl(_ text: String, _ m: NSTextCheckingResult) -> UInt32? {
        guard let hue = group(text, m, 1).flatMap({ Double($0) }),
              let sat = group(text, m, 2).flatMap({ Double($0) }),
              let lig = group(text, m, 3).flatMap({ Double($0) })
        else { return nil }
        let a = group(text, m, 4).flatMap(alphaByte) ?? 255
        let h = hue.truncatingRemainder(dividingBy: 360) / 360
        let s = min(max(sat / 100, 0), 1)
        let l = min(max(lig / 100, 0), 1)
        let r, g, b: Double
        if s == 0 {
            r = l; g = l; b = l
        } else {
            let q = l < 0.5 ? l * (1 + s) : l + s - l * s
            let p = 2 * l - q
            r = hueToRgb(p, q, h + 1.0 / 3)
            g = hueToRgb(p, q, h)
            b = hueToRgb(p, q, h - 1.0 / 3)
        }
        return pack(a, channel(r), channel(g), channel(b))
    }

    private static func hueToRgb(_ p: Double, _ q: Double, _ t: Double) -> Double {
        var t = t
        if t < 0 { t += 1 }
        if t > 1 { t -= 1 }
        if t < 1.0 / 6 { return p + (q - p) * 6 * t }
        if t < 1.0 / 2 { return q }
        if t < 2.0 / 3 { return p + (q - p) * (2.0 / 3 - t) * 6 }
        return p
    }

    // MARK: - Ortak

    private static func channel(_ v: Double) -> Int { roundedByte(v * 255) }

    private static func alphaByte(_ s: String) -> Int? {
        Double(s.hasPrefix(".") ? "0" + s : s).map { roundedByte($0 * 255) }
    }

    /// Sıfırdan uzağa yuvarla (127.5 → 128), 0–255'e sıkıştır.
    private static func roundedByte(_ v: Double) -> Int {
        Int(min(max(v.rounded(.toNearestOrAwayFromZero), 0), 255))
    }

    private static func pack(_ a: Int, _ r: Int, _ g: Int, _ b: Int) -> UInt32 {
        UInt32(a) << 24 | UInt32(r) << 16 | UInt32(g) << 8 | UInt32(b)
    }

    private static func group(_ text: String, _ m: NSTextCheckingResult, _ i: Int) -> String? {
        let r = m.range(at: i)
        guard r.location != NSNotFound, let range = Range(r, in: text) else { return nil }
        return String(text[range])
    }
}
