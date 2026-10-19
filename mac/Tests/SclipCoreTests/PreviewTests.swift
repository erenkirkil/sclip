import XCTest
@testable import SclipCore

final class PreviewTests: XCTestCase {
    private static let strings: Strings = {
        do { return try Strings.load(from: VectorLoader.spec("strings.tr.json")) } catch { fatalError("\(error)") }
    }()
    private var s: Strings { Self.strings }

    private func preview(_ payload: Payload) -> String {
        Entry(id: EntryID(raw: 1), createdAt: Date(timeIntervalSince1970: 0), payload: payload, isSensitive: false)
            .preview(s)
    }

    private func files(_ names: [String]) -> Payload { .files(names.map { URL(filePath: "/tmp/\($0)") }) }

    func testFilesPreviewMoreThanThree() {
        let expected = s.format(.previewFilesMulti, ["n": "5", "names": "a, b, c"])
            + s.format(.previewFilesMore, ["k": "2"])
        XCTAssertEqual(preview(files(["a", "b", "c", "d", "e"])), expected)
        XCTAssertEqual(expected, "5 dosya: a, b, c + 2 daha")
    }

    func testFilesPreviewCounts() {
        XCTAssertEqual(preview(.files([])), s[.previewFilesNone])
        XCTAssertEqual(preview(files(["only.txt"])), "only.txt")
        XCTAssertEqual(preview(files(["a", "b"])), "2 dosya: a, b")
        XCTAssertEqual(preview(files(["a", "b", "c"])), "3 dosya: a, b, c")
    }

    func testBasenameRules() {
        XCTAssertEqual(FileName.basename(URL(filePath: "/tmp/dir/My%20File.txt")), "My%20File.txt")
        XCTAssertEqual(FileName.basename(URL(string: "file:///tmp/My%20File.txt")!), "My File.txt")
        XCTAssertEqual(FileName.basename(URL(filePath: "/tmp/a\\b.txt")), "b.txt")
        XCTAssertEqual(FileName.basename(URL(filePath: "/")), "/")
    }

    func testBasenameStripsTrailingSeparators() {
        XCTAssertEqual(FileName.basename(URL(string: "file:///tmp/dir/")!), "dir")
        XCTAssertEqual(FileName.basename(path: "C:\\a\\b\\"), "b")
        XCTAssertEqual(FileName.basename(path: "/"), "/")
        XCTAssertEqual(FileName.basename(path: "a//"), "a")
        XCTAssertEqual(FileName.basename(path: "\\\\"), "\\\\")
        XCTAssertEqual(FileName.basename(path: "plain"), "plain")
    }

    func testPreviewNeverSplitsSurrogatePair() {
        let text = String(repeating: "a\u{1F600}", count: 100)
        let out = preview(.text(text))
        XCTAssertEqual(out.unicodeScalars.count, 121)
        XCTAssertTrue(out.hasSuffix("\u{2026}"))
        XCTAssertEqual(out, String(repeating: "a\u{1F600}", count: 60) + "\u{2026}")
        XCTAssertNotNil(out.data(using: .utf8))
    }

    func testPreviewExactly120CodePointsHasNoEllipsis() {
        XCTAssertEqual(preview(.text(String(repeating: "x", count: 120))), String(repeating: "x", count: 120))
        XCTAssertEqual(preview(.text(String(repeating: "x", count: 121))), String(repeating: "x", count: 120) + "\u{2026}")
    }

    func testPreviewCollapsesAndTrimsWhitespace() {
        XCTAssertEqual(preview(.text("  a\n\n\tb\u{00A0}\u{2028}c\u{3000}d\u{FEFF} ")), "a b c d")
        XCTAssertEqual(preview(.text("\u{85}mid\u{85}x\u{200B}z\u{85}")), "mid\u{85}x\u{200B}z")
    }

    func testPreviewSourcesPerKind() {
        XCTAssertEqual(preview(.url(original: "A", uri: "u", display: "shown")), "shown")
        XCTAssertEqual(preview(.richText(plain: "plain  text", html: "<b>x</b>", rtf: nil)), "plain text")
        XCTAssertEqual(preview(.color(original: "#FF0000", normalized: "#ff0000", argb: 0xFFFF0000)), "#ff0000")
        XCTAssertEqual(preview(.svg("<svg>\u{1F600}</svg>")), "SVG \u{00B7} 13B")
    }

    func testImagePreviews() {
        let one = ImageItem(data: Data(count: 2048), format: .jpeg)
        XCTAssertEqual(preview(.image(one)), "JPEG \u{00B7} 2KB")
        XCTAssertEqual(preview(.imageSet([one, ImageItem(data: Data(count: 1024), format: .webp)])), "2 resim \u{00B7} 3KB")
        XCTAssertEqual(preview(.pdf(Data(count: 500))), "PDF \u{00B7} 0KB")
    }

    func testSizeFormat500BytesIs0KB() {
        XCTAssertEqual(SizeFormat.format(500, s), "0KB")
    }

    func testSizeFormatBoundaries() {
        XCTAssertEqual(SizeFormat.format(1_048_575, s), "1023KB")
        XCTAssertEqual(SizeFormat.format(1_048_576, s), "1.0MB")
        XCTAssertEqual(SizeFormat.format(1_153_434, s), "1.1MB")
        XCTAssertEqual(SizeFormat.format(1_310_720, s), "1.3MB")
        XCTAssertEqual(SizeFormat.format(3_407_872, s), "3.3MB")
        XCTAssertEqual(SizeFormat.format(26_214_400, s), "25.0MB")
        XCTAssertEqual(SizeFormat.format(1_363_149, s), "1.3MB")
        XCTAssertEqual(SizeFormat.format(1_310_719, s), "1.2MB")
    }
}
