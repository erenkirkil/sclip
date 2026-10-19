import Foundation

extension ItemChain {
    /// Metin yolları (B-8.3.3–B-8.3.5): boş olmayan düz metin, yoksa yalnız HTML.
    mutating func textLegs(_ plain: String?) -> Classification {
        guard let plain, !plain.isEmpty else { return htmlOnly() }
        if plain.utf16.count > caps.textChars { return .drop(.textTooLarge) }
        return .payload(plainText(plain))
    }

    /// URL → renk → e-posta → telefon → SVG işaretlemesi → richText → text (B-8.3.4). Yalnız boşluktan oluşan
    /// metin hiçbir algılamaya uymaz ve `text` olur.
    private func plainText(_ raw: String) -> Payload {
        let trimmed = TextWhitespace.trim(raw)
        switch TextDetection.detect(raw) {
        case .url(let uri), .email(let uri), .phone(let uri):
            return .url(original: trimmed, uri: uri, display: trimmed)
        case .color(let color):
            return .color(original: trimmed, normalized: color.normalized, argb: color.argb)
        case .svg:
            // Algılama kırpılmış metne bakar; saklanan, denetlenen ve hash'lenen ham metindir (Flutter ile aynı).
            if SvgSanitizer.isSafe(Data(raw.utf8), caps: caps) { return .svg(raw) }
        case .none:
            break
        }
        if let html = html(), html != raw, html.utf16.count <= caps.textChars {
            return .richText(plain: raw, html: html, rtf: rtfCompanion())
        }
        return .text(raw)
    }

    /// Yalnız HTML (B-8.3.5): etiketler soyulur, boşluk sıkıştırılır; sınır aşımında düşer (B-8.3.10 c).
    /// Kapı açıksa düşme `run()` içinde B-8.3.6 geri dönüşünden sonraya ertelenir.
    private func htmlOnly() -> Classification {
        guard let html = html() else { return .none }
        if html.utf16.count > caps.textChars { return .drop(.textTooLarge) }
        let plain = HtmlStrip.plainText(html)
        if plain.isEmpty { return .none }
        return .payload(.richText(plain: plain, html: html, rtf: rtfCompanion()))
    }

    private func html() -> String? {
        guard let data = item.formats[.html], !data.isEmpty else { return nil }
        return TextDecoding.utf8(data)
    }

    /// RTF eşlikçisi sınırı aşarsa yalnız eşlikçi düşer (B-8.6.1).
    private func rtfCompanion() -> Data? {
        guard let rtf = item.formats[.rtf], !rtf.isEmpty, rtf.count <= caps.rtfBytes else { return nil }
        return rtf
    }
}

/// Metin biçimleri UTF-8'dir; geçersiz dizi U+FFFD ile değiştirilir (spec/vectors/README.md).
enum TextDecoding {
    static func utf8(_ data: Data) -> String { String(decoding: data, as: UTF8.self) }
}

/// `<[^>]*>` soyma + B-6.4.5 boşluk daraltma ve kırpma.
enum HtmlStrip {
    static func plainText(_ html: String) -> String {
        let scalars = Array(html.unicodeScalars)
        var out = String.UnicodeScalarView()
        var i = 0
        while i < scalars.count {
            if scalars[i] == "<" {
                // Sonrasında `>` yoksa ileride de eşleşme olamaz: kalan olduğu gibi kalır (doğrusal zaman).
                guard let close = scalars[(i + 1)...].firstIndex(of: ">") else {
                    out.append(contentsOf: scalars[i...])
                    break
                }
                i = close + 1
                continue
            }
            out.append(scalars[i])
            i += 1
        }
        return TextWhitespace.trim(TextWhitespace.collapse(String(out)))
    }
}
