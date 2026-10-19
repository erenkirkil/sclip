import Foundation

/// Arama indeksi (`behavior.md` B-6.5.5). `dosya`, `resim`, `pdf`, `svg` sözleşme sabitleridir.
public enum SearchIndex {
    /// Kaynağın normalizasyondan önce kesildiği UTF-16 birim sayısı (B-8.6.8).
    static let maxUnits = 8192

    /// Öğenin normalize edilmiş arama metni.
    public static func text(for entry: Entry) -> String {
        SearchNormalizer.normalize(cut(source(for: entry.payload)))
    }

    static func source(for payload: Payload) -> String {
        switch payload {
        case .text(let s): return s
        case .richText(let plain, _, _): return plain
        case .color(let original, _, _): return original
        case .url(_, let uri, let display):
            return display.unicodeScalars.elementsEqual(uri.unicodeScalars) ? display : display + " " + uri
        case .files(let urls):
            return (["dosya"] + urls.map(FileName.basename)).joined(separator: " ")
        case .image(let item):
            return "resim " + item.format.rawValue
        case .imageSet(let items):
            var seen = Set<ImageFormat>()
            let names = items.compactMap { seen.insert($0.format).inserted ? $0.format.rawValue : nil }
            return (["resim"] + names).joined(separator: " ")
        case .pdf: return "pdf"
        case .svg: return "svg"
        }
    }

    /// İlk 8192 UTF-16 birimi; kesim bir vekil çiftini bölerse sarkan yüksek vekil atılır (L7).
    static func cut(_ s: String) -> String {
        let units = s.utf16
        guard units.count > maxUnits else { return s }
        var end = units.index(units.startIndex, offsetBy: maxUnits)
        let last = units.index(before: end)
        if UTF16.isLeadSurrogate(units[last]) { end = last }
        return String(units[units.startIndex..<end]) ?? s
    }
}
