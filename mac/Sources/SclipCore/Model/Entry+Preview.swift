import Foundation

extension Entry {
    /// Satır önizlemesi (`behavior.md` B-6.4.3). Metinler katalogdan gelir.
    public func preview(_ strings: Strings) -> String {
        switch payload {
        case .text(let s): return PreviewText.cut(s)
        case .richText(let plain, _, _): return PreviewText.cut(plain)
        case .url(_, _, let display): return PreviewText.cut(display)
        case .color(_, let normalized, _): return normalized
        case .image(let item):
            return strings.format(.previewImage, [
                "format": item.format.rawValue.uppercased(),
                "size": SizeFormat.format(item.data.count, strings),
            ])
        case .imageSet(let items):
            let total = items.reduce(0) { $0 + $1.data.count }
            return strings.format(.previewImageSet, [
                "n": String(items.count),
                "size": SizeFormat.format(total, strings),
            ])
        case .svg(let xml): return strings.format(.previewSvg, ["n": String(xml.utf16.count)])
        case .pdf(let data): return strings.format(.previewPdf, ["size": SizeFormat.format(data.count, strings)])
        case .files(let urls): return PreviewText.files(urls, strings)
        }
    }
}

/// Metin önizlemesi: boşluk daralt, kırp, 120 kod noktasında kes (B-6.4.5, E24).
enum PreviewText {
    static let maxCodePoints = 120

    static func cut(_ s: String) -> String {
        let cleaned = TextWhitespace.trim(TextWhitespace.collapse(s))
        let scalars = cleaned.unicodeScalars
        var end = scalars.startIndex
        var count = 0
        while end < scalars.endIndex, count < maxCodePoints {
            end = scalars.index(after: end)
            count += 1
        }
        if end == scalars.endIndex { return cleaned }
        return String(scalars[scalars.startIndex..<end]) + "\u{2026}"
    }

    static func files(_ urls: [URL], _ strings: Strings) -> String {
        switch urls.count {
        case 0: return strings[.previewFilesNone]
        case 1: return FileName.basename(urls[0])
        default:
            let names = urls.prefix(3).map(FileName.basename).joined(separator: ", ")
            var text = strings.format(.previewFilesMulti, ["n": String(urls.count), "names": names])
            if urls.count > 3 {
                text += strings.format(.previewFilesMore, ["k": String(urls.count - 3)])
            }
            return text
        }
    }
}

/// Boyut biçimi (B-6.4.4).
enum SizeFormat {
    static let mebibyte = 1_048_576

    static func format(_ bytes: Int, _ strings: Strings) -> String {
        if bytes < mebibyte {
            return strings.format(.sizeKilobytes, ["n": String(bytes / 1024)])
        }
        // Tek ondalık, tam eşitlik sıfırdan uzağa (Dart toStringAsFixed): tamsayı aritmetiği kesindir.
        let tenths = (bytes * 10 + mebibyte / 2) / mebibyte
        return strings.format(.sizeMegabytes, ["n": "\(tenths / 10).\(tenths % 10)"])
    }
}
