import XCTest
@testable import SclipCore

final class SearchVectorTests: XCTestCase {
    func testNormalizeVectors() throws {
        let cases = try VectorLoader.searchFile().normalize
        XCTAssertEqual(cases.count, 30)
        for c in cases {
            XCTAssertEqual(
                Array(SearchNormalizer.normalize(c.input).unicodeScalars), Array(c.output.unicodeScalars),
                "normalize \(c.input.debugDescription)")
        }
    }

    func testIndexVectors() throws {
        let cases = try VectorLoader.searchFile().index
        XCTAssertEqual(cases.count, 24)
        let dir = try ClassifyHarness.makeTempDir("search")
        defer { try? FileManager.default.removeItem(at: dir) }
        for c in cases {
            // Girdi gerçek sınıflandırıcıdan geçer (README: "girdi sınıflandırılır").
            let payload = try ClassifyHarness.payload(c.entry, tempDir: dir)
            let entry = Entry(id: EntryID(raw: 1), createdAt: Date(timeIntervalSince1970: 0), payload: payload, isSensitive: false)
            XCTAssertEqual(SearchIndex.text(for: entry), c.expect, c.name)
        }
    }

    func testDanglingHighSurrogateCutYields8191Units() {
        let text = String(repeating: "a", count: 8191) + "\u{1F600}tail"
        let entry = Entry(id: EntryID(raw: 1), createdAt: Date(), payload: .text(text), isSensitive: false)
        let index = SearchIndex.text(for: entry)
        XCTAssertEqual(index.utf16.count, 8191)
        XCTAssertEqual(index, String(repeating: "a", count: 8191))
    }

    func testCutKeepsCompletePairAtBoundary() {
        let text = String(repeating: "a", count: 8190) + "\u{1F600}tail"
        let entry = Entry(id: EntryID(raw: 1), createdAt: Date(), payload: .text(text), isSensitive: false)
        XCTAssertEqual(SearchIndex.text(for: entry).utf16.count, 8192)
    }

    func testCutHappensBeforeNormalization() {
        // 8192 boşluk + "x": kesimden sonra yalnız boşluk kalır -> indeks boş.
        let text = String(repeating: " ", count: 8192) + "x"
        let entry = Entry(id: EntryID(raw: 1), createdAt: Date(), payload: .text(text), isSensitive: false)
        XCTAssertEqual(SearchIndex.text(for: entry), "")
    }

    func testFilterEmptyQueryReturnsSameArray() {
        let entries = [entry(1, .text("a")), entry(2, .text("b"))]
        XCTAssertEqual(EntryFilter.filter(entries, query: "").map(\.id), entries.map(\.id))
        XCTAssertEqual(EntryFilter.filter(entries, query: " \t\u{A0}").map(\.id), entries.map(\.id))
    }

    func testFilterMatchesTurkishAcrossCaseAndAccent() {
        let entries = [
            entry(1, .text("\u{0130}stanbul \u{015E}ehir")),
            entry(2, .text("ankara")),
            entry(3, .url(original: "https://x.com/Sehir", uri: "https://x.com/Sehir", display: "https://x.com/Sehir")),
        ]
        XCTAssertEqual(EntryFilter.filter(entries, query: "SEH\u{0130}R").map(\.id.raw), [1, 3])
        XCTAssertEqual(EntryFilter.filter(entries, query: "zzz").count, 0)
    }

    func testFilterMatchesTypeTokens() {
        let entries = [
            entry(1, .pdf(Data([1]))),
            entry(2, .svg("<svg/>")),
            entry(3, .files([URL(filePath: "/tmp/a.txt")])),
            entry(4, .image(ImageItem(data: Data([1]), format: .png))),
        ]
        XCTAssertEqual(EntryFilter.filter(entries, query: "PDF").map(\.id.raw), [1])
        XCTAssertEqual(EntryFilter.filter(entries, query: "svg").map(\.id.raw), [2])
        XCTAssertEqual(EntryFilter.filter(entries, query: "dosya").map(\.id.raw), [3])
        XCTAssertEqual(EntryFilter.filter(entries, query: "resim png").map(\.id.raw), [4])
    }

    func testFilterResultIsOrderedSubsetAndEmptyQueryIsIdentity() {
        let entries = (1...6).map { entry(UInt64($0), .text($0 % 2 == 0 ? "match \($0)" : "other \($0)")) }
        XCTAssertEqual(EntryFilter.filter(entries, query: "").map(\.id), entries.map(\.id))
        let hits = EntryFilter.filter(entries, query: "MATCH")
        XCTAssertEqual(hits.map(\.id.raw), [2, 4, 6])
        XCTAssertEqual(hits, entries.filter { $0.id.raw % 2 == 0 })
    }

    func testIndexUrlComparesDisplayAndUriByScalars() {
        // Canonical-esdeger ama farkli skaler dizisi: "e\u{301}" vs "\u{E9}" -> uri eklenmeli.
        let p = Payload.url(original: "x", uri: "caf\u{E9}", display: "cafe\u{301}")
        XCTAssertEqual(SearchIndex.source(for: p), "cafe\u{301} caf\u{E9}")
    }

    func testGreekFinalSigmaIsContextFree() {
        XCTAssertEqual(SearchNormalizer.normalize("\u{039F}\u{0394}\u{039F}\u{03A3}"), "\u{03BF}\u{03B4}\u{03BF}\u{03C3}")
    }

    func testNormalizeKeepsEmSpace() {
        XCTAssertEqual(SearchNormalizer.normalize("a\u{2003}b"), "a\u{2003}b")
    }

    private func entry(_ raw: UInt64, _ payload: Payload) -> Entry {
        Entry(id: EntryID(raw: raw), createdAt: Date(timeIntervalSince1970: 0), payload: payload, isSensitive: false)
    }
}
