import Foundation

/// SVG güvenlik denetimi (`behavior.md` B-8.10.x, sapma S8.10). Yalnız karar verir; XML ayrıştırmaz.
public enum SvgSanitizer {
    /// Yasak belirteçler (küçük harf, ASCII).
    private static let forbidden: [[UInt8]] = [
        "<!doctype", "<!entity", "<!attlist", "xmlns:xi=", "xinclude", "<script", "<foreignobject", "@import",
    ].map { Array($0.utf8) }

    private static let activeElements: [[UInt8]] = ["script", "foreignobject"].map { Array($0.utf8) }
    private static let href = Array("href".utf8)
    private static let urlOpen = Array("url(".utf8)
    private static let dataScheme = Array("data:".utf8)

    public static func isSafe(_ data: Data, caps: SizeCaps = .default) -> Bool {
        if data.count > caps.svgBytes { return false }
        if hasNulOrUtf16Bom(data) { return false }
        // Katı UTF-8: değiştirme karakterli çözüm girdiyle aynı baytları vermiyorsa geçersiz dizi vardır.
        var bytes = Array(String(decoding: data, as: UTF8.self).utf8)
        guard bytes.count == data.count, data.elementsEqual(bytes) else { return false }
        // Yalnız ASCII A-Z küçültülür (yerel/ICU katlaması yok).
        for i in bytes.indices where bytes[i] >= 0x41 && bytes[i] <= 0x5A { bytes[i] += 0x20 }
        guard encodingIsSafe(bytes) else { return false }
        for token in forbidden where contains(bytes, token) { return false }
        if hasPrefixedActiveElement(bytes) { return false }
        return cssUrlsAreSafe(bytes) && hrefsAreSafe(bytes)
    }

    // MARK: - B-8.10.5

    /// NUL bayt ya da bitişik `FF FE` / `FE FF` (UTF-16 BOM) var mı. Baştaki `EF BB BF` etkilemez.
    private static func hasNulOrUtf16Bom(_ data: Data) -> Bool {
        data.withUnsafeBytes { raw -> Bool in
            let p = raw.bindMemory(to: UInt8.self)
            var prev: UInt8 = 0x41
            for b in p {
                if b == 0x00 { return true }
                if (prev == 0xFF && b == 0xFE) || (prev == 0xFE && b == 0xFF) { return true }
                prev = b
            }
            return false
        }
    }

    // MARK: - B-8.10.6 kodlama

    private static let xmlDecl = Array("<?xml".utf8)
    private static let declEnd = Array("?>".utf8)
    private static let encodingName = Array("encoding".utf8)
    private static let allowedEncodings: [[UInt8]] = ["utf-8", "us-ascii", "ascii"].map { Array($0.utf8) }

    /// İsteğe bağlı baştaki UTF-8 BOM ve XML boşluğundan sonra ilk bayt `<` olmalı; XML bildirimi varsa
    /// `encoding` değeri yalnız utf-8 / us-ascii / ascii olabilir (UTF-7, EBCDIC vb. kaçışlarını önler).
    private static func encodingIsSafe(_ b: [UInt8]) -> Bool {
        let n = b.count
        var i = 0
        if n >= 3, b[0] == 0xEF, b[1] == 0xBB, b[2] == 0xBF { i = 3 }
        while i < n, isXmlSpace(b[i]) { i += 1 }
        if i >= n { return true }   // işaretleme yok
        guard b[i] == 0x3C else { return false }
        guard matches(b, xmlDecl, at: i), i + xmlDecl.count < n, isXmlSpace(b[i + xmlDecl.count]) else {
            return true   // bildirim yok (`<?xml-stylesheet` gibi işleme yönergeleri bildirim değildir)
        }
        guard let end = find(b, declEnd, from: i + xmlDecl.count) else { return false }
        var k = i + xmlDecl.count
        while let at = find(b, encodingName, from: k), at < end {
            k = at + encodingName.count
            var j = k
            while j < end, isXmlSpace(b[j]) { j += 1 }
            guard j < end, b[j] == 0x3D else { return false }
            j += 1
            while j < end, isXmlSpace(b[j]) { j += 1 }
            guard j < end, b[j] == 0x22 || b[j] == 0x27 else { return false }
            let quote = b[j]
            let start = j + 1
            var v = start
            while v < end, b[v] != quote { v += 1 }
            guard v < end, allowedEncodings.contains(where: { Array(b[start..<v]) == $0 }) else { return false }
            k = v + 1
        }
        return true
    }

    // MARK: - Ortak

    private static func isXmlSpace(_ b: UInt8) -> Bool { b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D }

    /// Ad baytı: küçük harf, rakam, `_ - . :` ve ASCII dışı. (Girdi zaten küçültülmüştür.)
    private static func isNameByte(_ b: UInt8) -> Bool {
        (b >= 0x61 && b <= 0x7A) || (b >= 0x30 && b <= 0x39) || b == 0x5F || b == 0x2D || b == 0x2E
            || b == 0x3A || b >= 0x80
    }

    /// `i` konumundan başlayan dizi `data:` önekiyle mi başlıyor.
    private static func startsWithData(_ b: [UInt8], at i: Int) -> Bool {
        guard i + dataScheme.count <= b.count else { return false }
        return b[i..<(i + dataScheme.count)].elementsEqual(dataScheme)
    }

    // MARK: - B-8.10.3 ad alanlı etkin öğeler

    /// `<önek:script` / `<önek:foreignobject`. Her `<` ad boyunca bir kez taranır (`<` ad sonlandırır).
    private static func hasPrefixedActiveElement(_ b: [UInt8]) -> Bool {
        let n = b.count
        var i = 0
        while i < n {
            guard b[i] == 0x3C else { i += 1; continue }
            var k = i + 1
            while k < n, !isXmlSpace(b[k]), b[k] != 0x2F, b[k] != 0x3E, b[k] != 0x3C {
                if b[k] == 0x3A {
                    for name in activeElements where matches(b, name, at: k + 1) { return true }
                }
                k += 1
            }
            i = k
        }
        return false
    }

    private static func matches(_ b: [UInt8], _ needle: [UInt8], at i: Int) -> Bool {
        guard i + needle.count <= b.count else { return false }
        return b[i..<(i + needle.count)].elementsEqual(needle)
    }

    // MARK: - B-8.10.3 CSS url(

    /// Her `url(` için kırpılmış, tırnaksız hedef `#` ya da `data:` ile başlamalı.
    private static func cssUrlsAreSafe(_ b: [UInt8]) -> Bool {
        let n = b.count
        var i = 0
        while let at = find(b, urlOpen, from: i) {
            var j = at + urlOpen.count
            while j < n, isXmlSpace(b[j]) { j += 1 }
            if j < n, b[j] == 0x22 || b[j] == 0x27 { j += 1 }
            while j < n, isXmlSpace(b[j]) { j += 1 }
            guard j < n, b[j] == 0x23 || startsWithData(b, at: j) else { return false }
            i = at + urlOpen.count
        }
        return true
    }

    // MARK: - B-8.10.3 href

    /// Her `href` geçişi bağımsız denetlenir; hiçbiri başka bir değerin içinden atlanmaz.
    private static func hrefsAreSafe(_ b: [UInt8]) -> Bool {
        let n = b.count
        // Kapanış tırnağı var mı sorusu O(1) olsun diye son tırnak konumları.
        let lastDouble = b.lastIndex(of: 0x22) ?? -1
        let lastSingle = b.lastIndex(of: 0x27) ?? -1
        var i = 0
        while let at = find(b, href, from: i) {
            i = at + href.count   // yalnız adın ötesine ilerle
            guard isAttributeName(b, hrefAt: at) else { continue }
            var j = i
            while j < n, isXmlSpace(b[j]) { j += 1 }
            guard j < n, b[j] == 0x3D else { continue }   // '=' yoksa öznitelik değil
            j += 1
            while j < n, isXmlSpace(b[j]) { j += 1 }
            guard j < n else { return false }              // değersiz / boş
            let first = b[j]
            if first == 0x22 || first == 0x27 {
                // Kapanış tırnağı yoksa değer tırnakla başlar: güvensiz.
                guard (first == 0x22 ? lastDouble : lastSingle) > j else { return false }
                j += 1
                while j < n, isXmlSpace(b[j]) { j += 1 }
                if j >= n || b[j] == first { return false }   // boş değer
            }
            if b[j] == 0x3E { return false }                  // tırnaksız boş değer
            guard b[j] == 0x23 || startsWithData(b, at: j) else { return false }
        }
        return true
    }

    /// `href` ya da `<önek>:href`: öncesi ad baytı değilse, ya da `:` ise eşleşir
    /// (`data-href`, `xhref` eşleşmez; `<a/href=`, `"a"href=` eşleşir).
    private static func isAttributeName(_ b: [UInt8], hrefAt at: Int) -> Bool {
        guard at > 0 else { return true }
        let prev = b[at - 1]
        return prev == 0x3A || !isNameByte(prev)
    }

    // MARK: - Bayt araması

    private static func contains(_ hay: [UInt8], _ needle: [UInt8]) -> Bool {
        find(hay, needle, from: 0) != nil
    }

    private static func find(_ hay: [UInt8], _ needle: [UInt8], from start: Int) -> Int? {
        let n = hay.count, m = needle.count
        guard m > 0, n >= m, start <= n - m else { return nil }
        let first = needle[0]
        return hay.withUnsafeBufferPointer { h -> Int? in
            needle.withUnsafeBufferPointer { nd -> Int? in
                var i = start
                let last = n - m
                while i <= last {
                    if h[i] == first {
                        var k = 1
                        while k < m, h[i + k] == nd[k] { k += 1 }
                        if k == m { return i }
                    }
                    i += 1
                }
                return nil
            }
        }
    }
}
