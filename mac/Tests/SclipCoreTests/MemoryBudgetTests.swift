import XCTest
@testable import SclipCore

final class MemoryBudgetTests: XCTestCase {
    private let caps = SizeCaps.default

    private func png(_ count: Int) -> ImageItem { ImageItem(data: Data(count: count), format: .png) }

    func testBinaryPayloadsWeighTheirBytes() {
        XCTAssertEqual(MemoryBudget.weight(of: .image(png(1_000)), caps: caps), 1_000)
        XCTAssertEqual(MemoryBudget.weight(of: .imageSet([png(300), png(700)]), caps: caps), 1_000)
        XCTAssertEqual(MemoryBudget.weight(of: .pdf(Data(count: 2_048)), caps: caps), 2_048)
    }

    func testTextAndSvgWeighCharactersAboveFloor() {
        let floor = caps.weightFloorChars
        XCTAssertEqual(MemoryBudget.weight(of: .text(String(repeating: "a", count: floor - 1)), caps: caps), 0)
        XCTAssertEqual(MemoryBudget.weight(of: .text(String(repeating: "a", count: floor)), caps: caps), floor)
        XCTAssertEqual(MemoryBudget.weight(of: .svg(String(repeating: "a", count: floor)), caps: caps), floor)
        XCTAssertEqual(MemoryBudget.weight(of: .svg("<svg/>"), caps: caps), 0)
    }

    /// Karakter = UTF-16 kod birimi: BMP dışı bir skaler 2 birim sayılır (Ruling I).
    func testTextCountsUTF16CodeUnits() {
        let floor = caps.weightFloorChars
        let text = String(repeating: "\u{1F600}", count: floor / 2)
        XCTAssertEqual(text.count, floor / 2)
        XCTAssertEqual(MemoryBudget.weight(of: .text(text), caps: caps), floor)
    }

    func testRichTextSumsPlainHtmlAndRtfBytes() {
        let plain = String(repeating: "p", count: 50_000)
        let html = String(repeating: "h", count: 20_000)
        let rtf = Data(count: 10_000)
        XCTAssertEqual(MemoryBudget.weight(of: .richText(plain: plain, html: html, rtf: rtf), caps: caps), 80_000)
        XCTAssertEqual(MemoryBudget.weight(of: .richText(plain: plain, html: html, rtf: nil), caps: caps), 70_000)
        // Eşik toplam üzerinden uygulanır (Flutter paritesi): 60 000 < 65 536 → 0.
        XCTAssertEqual(MemoryBudget.weight(of: .richText(plain: plain, html: String(repeating: "h", count: 10_000), rtf: nil), caps: caps), 0)
        XCTAssertEqual(MemoryBudget.weight(of: .richText(plain: "a", html: "<b>a</b>", rtf: Data(count: 100)), caps: caps), 0)
    }

    func testUrlColorFilesWeighNothing() {
        XCTAssertEqual(MemoryBudget.weight(of: .url(original: "https://a.b", uri: "https://a.b", display: "a.b"), caps: caps), 0)
        XCTAssertEqual(MemoryBudget.weight(of: .color(original: "#fff", normalized: "#ffffff", argb: 0xFFFF_FFFF), caps: caps), 0)
        XCTAssertEqual(MemoryBudget.weight(of: .files([URL(filePath: "/tmp/a")]), caps: caps), 0)
    }
}
