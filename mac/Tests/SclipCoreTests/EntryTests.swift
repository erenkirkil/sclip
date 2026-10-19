import XCTest
@testable import SclipCore

final class EntryTests: XCTestCase {
    func testTouchedKeepsIdAndHash() {
        let t0 = Date(timeIntervalSince1970: 1_000)
        let t1 = Date(timeIntervalSince1970: 2_000)
        let entry = Entry(id: EntryID(raw: 7), createdAt: t0, payload: .text("hello"), isSensitive: true)
        let touched = entry.touched(at: t1)
        XCTAssertEqual(touched.id, entry.id)
        XCTAssertEqual(touched.contentHash, entry.contentHash)
        XCTAssertEqual(touched.contentHash, "t:1bec6ebade142b8e")
        XCTAssertEqual(touched.createdAt, t1)
        XCTAssertEqual(touched.payload, entry.payload)
        XCTAssertTrue(touched.isSensitive)
    }

    func testImageSetHashIsOrderSensitive() {
        let a = ImageItem(data: Data([1, 2, 3, 4]), format: .png)
        let b = ImageItem(data: Data([5, 6, 7, 8]), format: .png)
        XCTAssertNotEqual(ContentHash.imageSet([a, b]), ContentHash.imageSet([b, a]))
        XCTAssertEqual(ContentHash.imageSet([a, b]), "is:2:8843b624558880ab")
    }

    func testImageSetHashIgnoresFormats() {
        let png = [ImageItem(data: Data([1]), format: .png), ImageItem(data: Data([2]), format: .png)]
        let jpg = [ImageItem(data: Data([1]), format: .jpeg), ImageItem(data: Data([2]), format: .webp)]
        XCTAssertEqual(ContentHash.imageSet(png), ContentHash.imageSet(jpg))
    }

    func testRichTextHashExcludesRtf() {
        let withRtf = Payload.richText(plain: "hi", html: "<b>hi</b>", rtf: Data([9, 9]))
        let noRtf = Payload.richText(plain: "hi", html: "<b>hi</b>", rtf: nil)
        XCTAssertEqual(ContentHash.of(withRtf), ContentHash.of(noRtf))
        XCTAssertEqual(ContentHash.of(withRtf), "r:e036281eeac82765")
    }

    func testUrlHashUsesOriginalNotUri() {
        let p = Payload.url(original: "HTTPS://Example.COM/Path", uri: "HTTPS://Example.COM/Path", display: "x")
        XCTAssertEqual(ContentHash.of(p), "u:0ba68acf60782646")
    }

    func testColorHashUsesNormalized() {
        let p = Payload.color(original: "rgb(255, 0, 0)", normalized: "#ff0000", argb: 0xFFFF0000)
        XCTAssertEqual(ContentHash.of(p), "c:327530fd52591d0c")
    }

    func testPayloadKinds() {
        let img = ImageItem(data: Data([1]), format: .png)
        let pairs: [(Payload, EntryKind)] = [
            (.text("a"), .text),
            (.url(original: "a", uri: "a", display: "a"), .url),
            (.color(original: "a", normalized: "a", argb: 0), .color),
            (.image(img), .image),
            (.imageSet([img, img]), .imageSet),
            (.svg("<svg/>"), .svg),
            (.files([]), .files),
            (.pdf(Data()), .pdf),
            (.richText(plain: "", html: "", rtf: nil), .richText),
        ]
        for (payload, kind) in pairs { XCTAssertEqual(payload.kind, kind) }
        XCTAssertEqual(pairs.count, EntryKind.allCases.count)
    }

    func testEntryIDDescriptionAndGeneratorMonotonic() {
        XCTAssertEqual(EntryID(raw: 42).description, "e42")
        let gen = EntryIDGenerator()
        let ids = (0..<100).map { _ in gen.next().raw }
        XCTAssertEqual(ids, ids.sorted())
        XCTAssertEqual(Set(ids).count, 100)
    }

    func testEntryIDGeneratorIsUniqueUnderConcurrency() async {
        let gen = EntryIDGenerator()
        let all = await withTaskGroup(of: [UInt64].self) { group in
            for _ in 0..<8 { group.addTask { (0..<500).map { _ in gen.next().raw } } }
            var out: [UInt64] = []
            for await part in group { out += part }
            return out
        }
        XCTAssertEqual(Set(all).count, 4000)
    }

    func testClockProtocolAndSystemClock() {
        struct Fixed: Clock { func now() -> Date { Date(timeIntervalSince1970: 5) } }
        XCTAssertEqual(Fixed().now().timeIntervalSince1970, 5)
        XCTAssertLessThan(abs(SystemClock().now().timeIntervalSinceNow), 5)
    }

    func testCanonicalFormatRawValues() {
        XCTAssertEqual(CanonicalFormat.plainText.rawValue, "text/plain")
        XCTAssertEqual(CanonicalFormat.svg.rawValue, "image/svg+xml")
        XCTAssertEqual(CanonicalFormat.allCases.count, 9)
        let clip = RawClip(items: [RawItem(formats: [.plainText: Data("a".utf8)])], files: [], flags: [.concealed])
        XCTAssertTrue(clip.flags.contains(.concealed))
    }
}
