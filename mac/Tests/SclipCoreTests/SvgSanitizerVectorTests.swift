import XCTest
@testable import SclipCore

final class SvgSanitizerVectorTests: XCTestCase {
    func testSanitizeVectors() throws {
        let cases = try VectorLoader.svgSanitizeCases()
        XCTAssertEqual(cases.count, 91)
        for c in cases {
            let data = try c.input.data()
            XCTAssertEqual(SvgSanitizer.isSafe(data), c.expect.safe, c.name)
        }
    }

    func testOversizeRejected() {
        let caps = SizeCaps.default
        var data = Data("<svg>".utf8)
        data.append(Data(repeating: 0x20, count: caps.svgBytes + 1 - data.count))
        XCTAssertEqual(data.count, caps.svgBytes + 1)
        XCTAssertFalse(SvgSanitizer.isSafe(data))
        XCTAssertTrue(SvgSanitizer.isSafe(data.prefix(caps.svgBytes)))
    }

    func testCustomCapIsHonoured() {
        var caps = SizeCaps()
        caps.svgBytes = 8
        XCTAssertTrue(SvgSanitizer.isSafe(Data("<svg/>".utf8), caps: caps))
        XCTAssertFalse(SvgSanitizer.isSafe(Data("<svg></svg>".utf8), caps: caps))
    }

    func testInvalidUtf8DoesNotCrash() {
        let bytes: [UInt8] = [0x3C, 0x73, 0x76, 0x67, 0x80, 0x81, 0xC3]
        XCTAssertFalse(SvgSanitizer.isSafe(Data(bytes)))
        XCTAssertFalse(SvgSanitizer.isSafe(Data([0xFF, 0xFE, 0x00, 0x80, 0x81])))
        // Geçerli ASCII dışı UTF-8 (U+FFFD'nin kendisi dahil) güvenli kalır.
        XCTAssertTrue(SvgSanitizer.isSafe(Data("<svg><text>çğ\u{FFFD}😀</text></svg>".utf8)))
    }

    func testBomRules() {
        let svg = Array("<svg/>".utf8)
        XCTAssertTrue(SvgSanitizer.isSafe(Data([0xEF, 0xBB, 0xBF] + svg)))
        XCTAssertFalse(SvgSanitizer.isSafe(Data([0xFF, 0xFE] + svg)))
        XCTAssertFalse(SvgSanitizer.isSafe(Data([0xFE, 0xFF] + svg)))
        XCTAssertFalse(SvgSanitizer.isSafe(Data(svg + [0x00])))
        XCTAssertFalse(SvgSanitizer.isSafe(Data([0x00, 0x00, 0xFE, 0xFF] + svg)))
    }

    func testHrefRules() {
        func safe(_ s: String) -> Bool { SvgSanitizer.isSafe(Data(s.utf8)) }
        XCTAssertTrue(safe("<use href=\"#a\"/>"))
        XCTAssertTrue(safe("<use\thref = '  #a  '/>"))
        XCTAssertTrue(safe("<use\r\nXLINK:HREF=data:image/png;base64,AAAA />"))
        XCTAssertFalse(safe("<use href=\"\"/>"))
        XCTAssertFalse(safe("<use href=''/>"))
        XCTAssertFalse(safe("<use href=/>"))
        XCTAssertFalse(safe("<use href=\"\u{00A0}#a\"/>"))
        XCTAssertFalse(safe("<use href=\"HTTP://x\"/>"))
        XCTAssertFalse(safe("<use xlink:href=\"//evil/x\"/>"))
        XCTAssertFalse(safe("<use href=\"#ok\" xlink:href=\"http://x\"/>"))
        XCTAssertFalse(safe("<use href=http://x>"))
        XCTAssertTrue(safe("<use data-href=\"http://x\" xhref=\"http://y\"/>"))
        XCTAssertTrue(safe("<text>see href in text</text>"))
    }

    /// O1: sahte `href="` bir yorumda / metinde / başka özniteliğin değerinde gerçek özniteliği yutamaz.
    func testFakeHrefCannotSwallowRealAttribute() {
        func safe(_ s: String) -> Bool { SvgSanitizer.isSafe(Data(s.utf8)) }
        XCTAssertFalse(safe("<svg><!-- <a href=\"#x --><image href=\"http://evil\"/></svg>"))
        XCTAssertFalse(safe("<svg><desc> href=\"#</desc><image href=\"http://evil\"/></svg>"))
        XCTAssertFalse(safe("<svg><g title=' href=\"#x'/><image href=\"http://evil\"/></svg>"))
        XCTAssertFalse(safe("<svg><g a=href=#x b=1/><image href=\"http://evil\"/></svg>"))
        XCTAssertTrue(safe("<svg><g title='x'/><image href=\"#a\"/><use href=\"#b\"/></svg>"))
        XCTAssertFalse(safe("<svg><use href=\"#a"))   // kapanış tırnağı yok
    }

    /// O2: ad alanı öneki ve ayırıcı çeşitleri.
    func testHrefNameForms() {
        func safe(_ s: String) -> Bool { SvgSanitizer.isSafe(Data(s.utf8)) }
        XCTAssertFalse(safe("<svg><a/href=\"http://e\">x</a></svg>"))
        XCTAssertFalse(safe("<svg><a title=\"a\"href=\"http://e\">x</a></svg>"))
        XCTAssertFalse(safe("<svg xmlns:x=\"http://www.w3.org/1999/xlink\"><image x:href=\"http://e\"/></svg>"))
        XCTAssertFalse(safe("<svg><g ns1:href=\"https://x.example/\"/></svg>"))
        XCTAssertTrue(safe("<svg><image x:href=\"#a\"/></svg>"))
        XCTAssertTrue(safe("<svg><g xhref=\"http://e\" data-href=\"http://e\"/></svg>"))
    }

    /// O3: ad alanlı etkin öğeler.
    func testPrefixedActiveElements() {
        func safe(_ s: String) -> Bool { SvgSanitizer.isSafe(Data(s.utf8)) }
        XCTAssertFalse(safe("<svg:svg xmlns:svg=\"http://www.w3.org/2000/svg\"><svg:script>x</svg:script></svg:svg>"))
        XCTAssertFalse(safe("<svg><x:ForeignObject/></svg>"))
        XCTAssertTrue(safe("<svg:svg xmlns:svg=\"http://www.w3.org/2000/svg\"><svg:rect/></svg:svg>"))
    }

    /// O4: `@import` ve CSS `url(`.
    func testCssImportAndUrl() {
        func safe(_ s: String) -> Bool { SvgSanitizer.isSafe(Data(s.utf8)) }
        XCTAssertFalse(safe("<svg><style>@import 'x.css';</style></svg>"))
        XCTAssertFalse(safe("<svg><rect fill=\"url(http://e)\"/></svg>"))
        XCTAssertFalse(safe("<svg><rect style=\"background:url('http://e')\"/></svg>"))
        XCTAssertFalse(safe("<svg><rect style='fill:URL( \"http://e\" )'/></svg>"))
        XCTAssertFalse(safe("<svg><rect fill=\"url()\"/></svg>"))
        XCTAssertFalse(safe("<svg><rect fill=\"url(#a)\" stroke=\"url(http://e)\"/></svg>"))
        XCTAssertTrue(safe("<svg><rect fill=\"url(#g)\" style=\"fill:url( '#g' )\"/></svg>"))
        XCTAssertTrue(safe("<svg><rect style=\"fill:url(data:image/png;base64,AA==)\"/></svg>"))
        // Kabul edilen risk: olay işleyicileri reddedilmez.
        XCTAssertTrue(safe("<svg onload=\"x()\"/>"))
    }

    /// O5: UTF-7 / EBCDIC / bildirilen kodlama / baştaki çöp / geçersiz UTF-8 ile kaçış.
    func testEncodingEscapes() {
        func safe(_ s: String) -> Bool { SvgSanitizer.isSafe(Data(s.utf8)) }
        XCTAssertFalse(safe("+ADw-!DOCTYPE svg+AD4-+ADw-svg/+AD4-"))
        XCTAssertFalse(safe("<?xml version=\"1.0\" encoding=\"UTF-7\"?>+ADw-svg+AD4-"))
        XCTAssertFalse(SvgSanitizer.isSafe(Data([0x4C, 0xA2, 0xA5, 0x87, 0x6E])))   // EBCDIC "<svg>"
        XCTAssertFalse(safe("<?xml version=\"1.0\" encoding=\"UTF-16\"?><svg/>"))
        XCTAssertFalse(safe("<?xml version='1.0' encoding='ISO-8859-1'?><svg/>"))
        XCTAssertFalse(safe("<?xml version=\"1.0\" encoding=utf-7?><svg/>"))
        XCTAssertFalse(safe("<?xml version=\"1.0\" encoding=\"utf-8\""))
        XCTAssertFalse(safe("<?xml version=\"encoding='utf-8'\" encoding=\"utf-7\"?><svg/>"))
        XCTAssertFalse(safe("x<svg/>"))
        XCTAssertFalse(SvgSanitizer.isSafe(Data(Array("<svg><use ".utf8) + [0xFF] + Array("href=\"http://e\"/></svg>".utf8))))
        XCTAssertTrue(safe("<?xml version=\"1.0\" encoding=\"UTF-8\"?><svg/>"))
        XCTAssertTrue(safe("<?xml version='1.0' encoding='utf-8'?><svg/>"))
        XCTAssertTrue(safe("<?xml version=\"1.0\" encoding=\"US-ASCII\"?><svg/>"))
        XCTAssertTrue(safe("<?xml version=\"1.0\"?><svg/>"))
        XCTAssertTrue(safe("<?xml-stylesheet href=\"#s\"?><svg/>"))
        XCTAssertTrue(SvgSanitizer.isSafe(Data([0xEF, 0xBB, 0xBF] + Array("\r\n\t <svg/>".utf8))))
        XCTAssertTrue(safe(""))
        XCTAssertTrue(safe(" \n"))
    }

    /// Doğrusal zaman: kötü niyetli tekrarlayan örüntüler 20 MiB üzerinde de hızlı biter.
    func testLinearTimeOnAdversarialInput() {
        let unit = Array("href=#".utf8)
        var big = Array("<svg>".utf8)
        while big.count < (20 << 20) - 16 { big.append(contentsOf: unit) }
        big.append(contentsOf: Array("</svg>".utf8))
        var lt = Array("<svg>".utf8)
        while lt.count < (20 << 20) - 16 { lt.append(0x3C) }
        var url = Array("<svg>".utf8)
        while url.count < (20 << 20) - 16 { url.append(contentsOf: Array("url(  ".utf8)) }
        var urlOk = Array("<svg>".utf8)
        while urlOk.count < (20 << 20) - 16 { urlOk.append(contentsOf: Array("url(#a)".utf8)) }
        var decl = Array("<?xml version=\"1.0\" ".utf8)
        while decl.count < (20 << 20) - 16 { decl.append(contentsOf: Array("encoding=\"utf-8\" ".utf8)) }
        decl.append(contentsOf: Array("?><svg/>".utf8))
        var pad = Array("<svg>".utf8)
        pad.append(contentsOf: [UInt8](repeating: 0x20, count: (20 << 20) - 16))
        func elapsed(_ d: [UInt8]) -> TimeInterval {
            let t = Date()
            _ = SvgSanitizer.isSafe(Data(d))
            return Date().timeIntervalSince(t)
        }
        // Tabanla kıyas: ikinci dereceden bir yol onlarca kat yavaş olurdu.
        let base = elapsed(pad)
        for d in [big, lt, url, urlOk, decl] {
            XCTAssertLessThan(elapsed(d), base * 4 + 2)
        }
    }

    func testDangerousTokens() {
        func safe(_ s: String) -> Bool { SvgSanitizer.isSafe(Data(s.utf8)) }
        XCTAssertFalse(safe("<svg><SCRIPT>x</SCRIPT></svg>"))
        XCTAssertFalse(safe("<svg><foreignObject/></svg>"))
        XCTAssertFalse(safe("<!DOCTYPE svg><svg/>"))
        XCTAssertFalse(safe("<svg xmlns:xi=\"http://www.w3.org/2001/XInclude\"/>"))
        XCTAssertTrue(safe("<svg xmlns=\"http://www.w3.org/2000/svg\"/>"))
    }

    func testSizeCapsMatchContract() {
        let c = SizeCaps.default
        XCTAssertEqual(c.textChars, 2_097_152)
        XCTAssertEqual(c.rtfBytes, 2_097_152)
        XCTAssertEqual(c.svgBytes, 20 << 20)
        XCTAssertEqual(c.pdfBytes, 25 << 20)
        XCTAssertEqual(c.imageBytes, 25 << 20)
        XCTAssertEqual(c.fileImageBytes, 25 << 20)
        XCTAssertEqual(c.totalBudgetBytes, 150 << 20)
        XCTAssertEqual(c.weightFloorChars, 65_536)
        XCTAssertEqual(c.searchIndexChars, 8_192)
        XCTAssertEqual(c.previewScalars, 120)
    }
}
