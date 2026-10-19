import Foundation

/// RTF kapısı (B-8.3.1): düz metin ve RTF biçimleri birlikte sunuluyorsa (değerleri boş olsa bile; Flutter
/// `canProvide` eşdeğeri) ilk geçişte ikili problar atlanır. Kelime işlemci kopyaları metnin yanında sayfa
/// görüntüsü/PDF sunar; kullanıcının beklediği metindir.
enum RtfGate {
    static func isOpen(_ item: RawItem) -> Bool {
        item.formats[.plainText] != nil && item.formats[.rtf] != nil
    }
}
