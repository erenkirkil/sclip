import Foundation

/// Ağır bütçe ağırlıkları (B-8.6.6, B-8.6.7). Her `Payload` türü açıkça ele alınır; yeni bir
/// bayt taşıyan tür eklendiğinde ağırlığı seçilene kadar derleme başarısız olur.
public enum MemoryBudget {
    /// `payload`'ın bütçedeki ağırlığı. Metin ağırlığı UTF-16 kod birimidir (Ruling I); RTF bayttır.
    public static func weight(of payload: Payload, caps: SizeCaps) -> Int {
        switch payload {
        case .image(let item):
            return item.data.count
        case .imageSet(let items):
            return items.reduce(0) { $0 + $1.data.count }
        case .pdf(let data):
            return data.count
        case .svg(let markup):
            return stringWeight(markup.utf16.count, caps: caps)
        case .text(let text):
            return stringWeight(text.utf16.count, caps: caps)
        case .richText(let plain, let html, let rtf):
            return stringWeight(plain.utf16.count + html.utf16.count + (rtf?.count ?? 0), caps: caps)
        case .url, .color, .files:
            return 0
        }
    }

    /// Eşik altındaki metin 0 sayılır: bütçeyi zorlamaz, ağır kurban olarak da düşürülmez.
    private static func stringWeight(_ length: Int, caps: SizeCaps) -> Int {
        length < caps.weightFloorChars ? 0 : length
    }
}
