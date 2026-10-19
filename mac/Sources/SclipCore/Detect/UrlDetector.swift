import Foundation

/// URL algılama: kendi sözdizimimiz (`behavior.md` B-8.2.1, sapma S8.2). `URLComponents` kabul için kullanılmaz.
public enum UrlDetector {
    private static let prefixes = ["https://", "http://", "ftp://", "mailto:"]

    /// Kırpılmış metin url ise uri'yi (aynı metin, normalize edilmez) döndürür.
    public static func detect(_ trimmed: String) -> String? {
        let scalars = trimmed.unicodeScalars
        // Önek ASCII büyük/küçük harf duyarsız eşlenir; sonrasında en az bir karakter gerekir.
        let head = TextWhitespace.asciiLowercased(String(String.UnicodeScalarView(scalars.prefix(8))))
        guard let prefix = prefixes.first(where: { head.hasPrefix($0) }),
              scalars.count > prefix.unicodeScalars.count
        else { return nil }
        for u in scalars where TextWhitespace.isCollapseSet(u.value) { return nil }
        return trimmed
    }
}
