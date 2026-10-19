import XCTest
@testable import SclipCore

final class DetectVectorTests: XCTestCase {
    private func describe(_ d: TextDetection) -> DetectExpect {
        switch d {
        case .url(let uri): return DetectExpect(kind: .url, uri: uri, normalized: nil, argb: nil)
        case .email(let uri): return DetectExpect(kind: .email, uri: uri, normalized: nil, argb: nil)
        case .phone(let uri): return DetectExpect(kind: .phone, uri: uri, normalized: nil, argb: nil)
        case .color(let c):
            let hex = String(c.argb, radix: 16, uppercase: true)
            let padded = String(repeating: "0", count: 8 - hex.count) + hex
            return DetectExpect(kind: .color, uri: nil, normalized: c.normalized, argb: "0x" + padded)
        case .svg: return DetectExpect(kind: .svg, uri: nil, normalized: nil, argb: nil)
        case .none: return DetectExpect(kind: .none, uri: nil, normalized: nil, argb: nil)
        }
    }

    func testDetectVectors() throws {
        let cases = try VectorLoader.detectCases()
        XCTAssertGreaterThanOrEqual(cases.count, 60)
        for c in cases {
            XCTAssertEqual(describe(TextDetection.detect(c.input)), c.expect, c.name)
        }
    }

    func testUnicodeDigitsAreNotPhoneOrColor() {
        XCTAssertEqual(TextDetection.detect("#\u{0661}\u{0662}\u{0663}"), .none)
        XCTAssertEqual(TextDetection.detect("+\u{0669}\u{0660}\u{0665}\u{0663}\u{0662}\u{0661}\u{0662}\u{0663}"), .none)
        XCTAssertEqual(TextDetection.detect("rgb(\u{0661}, 2, 3)"), .none)
    }

    func testRgbaAlphaHalfIsNotZero() {
        XCTAssertEqual(ColorParser.parse("rgba(255,0,0,0.5)")?.argb, 0x80FF_0000)
    }

    func testRgbaAlphaRoundsHalfAwayFromZero() {
        // 0.5 * 255 = 127.5 -> 128 (0x80)
        XCTAssertEqual(ColorParser.parse("rgba(0,0,0,.5)")?.argb, 0x8000_0000)
    }

    func testHslaAlphaHalfAwayFromZero() {
        XCTAssertEqual(ColorParser.parse("hsla(0, 0%, 0%, 0.5)")?.argb, 0x8000_0000)
    }

    func testColorNormalizedLowercasedAndTrimmedInput() {
        XCTAssertEqual(TextDetection.detect("\u{0085} #ABCDEF \u{3000}"),
                       .color(ParsedColor(normalized: "#abcdef", argb: 0xFFAB_CDEF)))
    }

    func testUrlRejectsAnyCollapseSetWhitespace() {
        for scalar in ["\u{0009}", "\u{000B}", "\u{000C}", "\u{00A0}", "\u{1680}", "\u{2003}", "\u{2028}",
                       "\u{2029}", "\u{202F}", "\u{205F}", "\u{3000}", "\u{FEFF}"] {
            XCTAssertNil(UrlDetector.detect("https://x.com/a\(scalar)b"), "U+\(scalar.unicodeScalars.first!.value)")
        }
    }

    func testUrlAcceptsNonAsciiAndKeepsOriginalCase() {
        XCTAssertEqual(UrlDetector.detect("FTP://Sunucu/dosya-\u{015F}"), "FTP://Sunucu/dosya-\u{015F}")
    }

    func testUrlRequiresCharacterAfterScheme() {
        XCTAssertNil(UrlDetector.detect("ftp://"))
        XCTAssertNil(UrlDetector.detect("mailto:"))
        XCTAssertEqual(UrlDetector.detect("mailto:x"), "mailto:x")
    }

    func testPhoneDigitCountBounds() {
        XCTAssertNil(ContactDetector.tel("+1 2 3 4 5 6 7"))
        XCTAssertEqual(ContactDetector.tel("+1 2 3 4 5 6 7 8"), "tel:+12345678")
    }

    func testEmailRejectsTrailingNewlineInsideText() {
        XCTAssertNil(ContactDetector.mailto("a@b.com\nx"))
    }

    func testSvgSelfClosingAndHtmlWrappedAreNotSvg() {
        XCTAssertFalse(SvgMarkupHeuristic.looksLikeSvg("<svg/>"))
        XCTAssertFalse(SvgMarkupHeuristic.looksLikeSvg("<div><svg></svg></div>"))
        XCTAssertTrue(SvgMarkupHeuristic.looksLikeSvg("\u{3000}<SVG></SVG>"))
    }

    func testEmptyAndWhitespaceOnlyIsNone() {
        XCTAssertEqual(TextDetection.detect(""), .none)
        XCTAssertEqual(TextDetection.detect(" \u{0085}\u{FEFF}"), .none)
    }
}
