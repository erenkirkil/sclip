import Foundation

extension SearchNormalizer {
    /// Kullanıcıya gösterilen sorgu için Dart `String.trim()` kümesiyle kırpma (B-6.5.7).
    /// Normalizasyondan farklı olarak büyük/küçük harf ve iç boşluklara dokunmaz.
    public static func trimmedForDisplay(_ s: String) -> String { TextWhitespace.trim(s) }
}
