import Foundation

/// E-posta ve telefon algılama (`behavior.md` B-8.2.6, B-8.2.7). Rakamlar yalnız ASCII `[0-9]`.
public enum ContactDetector {
    // `\A…\z`: `$` ICU'da sondaki satır sonundan önce de eşleşir.
    private static let emailRegex = try! NSRegularExpression(
        pattern: #"\A[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}\z"#)
    private static let phoneRegex = try! NSRegularExpression(
        pattern: #"\A\+[1-9][0-9 ().\-]{6,18}\z"#)

    /// Çıplak adres ise `mailto:` + adres.
    public static func mailto(_ trimmed: String) -> String? {
        matches(emailRegex, trimmed) ? "mailto:" + trimmed : nil
    }

    /// Telefon ise `tel:+<rakamlar>` (8–15 rakam).
    public static func tel(_ trimmed: String) -> String? {
        guard matches(phoneRegex, trimmed) else { return nil }
        let digits = trimmed.unicodeScalars.filter { $0.value >= 0x30 && $0.value <= 0x39 }
        guard (8...15).contains(digits.count) else { return nil }
        return "tel:+" + String(String.UnicodeScalarView(digits))
    }

    private static func matches(_ regex: NSRegularExpression, _ s: String) -> Bool {
        regex.firstMatch(in: s, range: NSRange(location: 0, length: s.utf16.count)) != nil
    }
}
