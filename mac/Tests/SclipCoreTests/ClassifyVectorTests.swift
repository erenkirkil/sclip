import XCTest
@testable import SclipCore

/// spec/vectors/classify.json koşucusu (B-8.3.x, B-8.6.x).
final class ClassifyVectorTests: XCTestCase {
    private static let strings: Strings = {
        do { return try Strings.load(from: VectorLoader.spec("strings.tr.json")) } catch { fatalError("\(error)") }
    }()

    func testClassifyVectors() throws {
        let cases = try VectorLoader.classifyCases()
        XCTAssertEqual(cases.count, 112)
        let dir = try ClassifyHarness.makeTempDir("classify")
        defer { try? FileManager.default.removeItem(at: dir) }
        let classifier = Classifier()
        for c in cases {
            let clip = try ClassifyHarness.rawClip(c.input, tempDir: dir)
            check(classifier.classify(clip), c.expect, c.name)
        }
    }

    func testPngTruncatedHeaderFallsToNextProbe() throws {
        let jpeg = try Data(contentsOf: VectorLoader.vectors("fixtures/tiny.jpg"))
        let clip = RawClip(
            items: [RawItem(formats: [.png: Data([0x89, 0x50, 0x4E, 0x47]), .jpeg: jpeg])], files: [], flags: [])
        XCTAssertEqual(Classifier().classify(clip), .payload(.image(ImageItem(data: jpeg, format: .jpeg))))
    }

    // MARK: - Düşme nedenleri (her neden ayrı test)

    private static let tinyCaps: SizeCaps = {
        var caps = SizeCaps()
        caps.textChars = 3
        caps.imageBytes = 8
        caps.pdfBytes = 2
        caps.svgBytes = 4
        return caps
    }()

    private func classifyOne(_ formats: [CanonicalFormat: Data]) -> Classification {
        Classifier(caps: Self.tinyCaps).classify(RawClip(items: [RawItem(formats: formats)], files: [], flags: []))
    }

    func testDropPlainTextOverCap() {
        XCTAssertEqual(classifyOne([.plainText: Data("abcd".utf8)]), .drop(.textTooLarge))
    }

    func testDropPlainTextOverCapSkipsRichDocFallback() {
        // Sınırı aşan düz metin, kapı açık olsa bile geri dönüşe gitmeden düşer (Flutter ile aynı).
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        XCTAssertEqual(classifyOne([.plainText: Data("abcd".utf8), .rtf: Data("r".utf8), .png: png]), .drop(.textTooLarge))
    }

    func testDropHtmlOnlyOverCap() {
        XCTAssertEqual(classifyOne([.html: Data("abcd".utf8)]), .drop(.textTooLarge))
    }

    func testDropHtmlOnlyOverCapWithGateOpenAfterEmptyFallback() {
        XCTAssertEqual(classifyOne([.plainText: Data(), .rtf: Data("r".utf8), .html: Data("abcd".utf8)]), .drop(.textTooLarge))
    }

    func testDropSingleImageOverCap() {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00])
        XCTAssertEqual(classifyOne([.png: png]), .drop(.overCap(.image)))
    }

    func testDropPdfOverCap() {
        XCTAssertEqual(classifyOne([.pdf: Data("%PDF".utf8)]), .drop(.overCap(.pdf)))
    }

    func testDropSvgBytesOverCap() {
        XCTAssertEqual(classifyOne([.svg: Data("<svg></svg>".utf8)]), .drop(.overCap(.svg)))
    }

    func testEmptyClipIsNone() {
        XCTAssertEqual(Classifier().classify(RawClip(items: [], files: [], flags: [])), .none)
    }

    func testFileReadFailureStaysFiles() {
        let urls = [URL(filePath: "/nonexistent/a.png")]
        let result = Classifier(files: StubFiles(size: 10, fails: true)).classify(RawClip(items: [], files: urls, flags: []))
        XCTAssertEqual(result, .payload(.files(urls)))
    }

    func testFileSizeUnknownStaysFiles() {
        let urls = [URL(filePath: "/nonexistent/a.png")]
        let result = Classifier(files: StubFiles(size: nil, fails: false)).classify(RawClip(items: [], files: urls, flags: []))
        XCTAssertEqual(result, .payload(.files(urls)))
    }

    func testFileGrownAfterSizeCheckStaysFiles() {
        // Boyut 1 bayt görünür, okuma sınırdan büyük döner: files'a iner.
        var caps = SizeCaps()
        caps.fileImageBytes = 4
        let urls = [URL(filePath: "/nonexistent/a.png")]
        let result = Classifier(caps: caps, files: GrowingFile()).classify(RawClip(items: [], files: urls, flags: []))
        XCTAssertEqual(result, .payload(.files(urls)))
    }

    func testDiskFileReadingIsBounded() throws {
        let dir = try ClassifyHarness.makeTempDir("bounded")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "f.png")
        try Data((0..<100).map { UInt8($0) }).write(to: url)
        let reader = DiskFileReading()
        XCTAssertEqual(try reader.read(url, upTo: 10), Data((0..<10).map { UInt8($0) }))
        XCTAssertEqual(try reader.read(url, upTo: 1000).count, 100)
        XCTAssertEqual(reader.size(of: url), 100)
        XCTAssertNil(reader.size(of: dir))
    }

    // MARK: - Karşılaştırma

    private func check(_ actual: Classification, _ expect: ClassifyExpect, _ name: String) {
        switch (expect.result, actual) {
        case (.none, .none), (.drop, .drop):
            return
        case (.entry, .payload(let payload)):
            checkEntry(payload, expect, name)
        default:
            XCTFail("\(name): beklenen \(expect.result), bulunan \(Self.describe(actual))")
        }
    }

    private func checkEntry(_ payload: Payload, _ expect: ClassifyExpect, _ name: String) {
        let entry = Entry(id: EntryID(raw: 1), createdAt: Date(timeIntervalSince1970: 0), payload: payload, isSensitive: false)
        if let kind = expect.kind { XCTAssertEqual(payload.kind.rawValue, kind, "\(name) kind") }
        if let preview = expect.preview {
            XCTAssertEqual(Array(entry.preview(Self.strings).unicodeScalars), Array(preview.unicodeScalars), "\(name) preview")
        }
        if let hash = expect.hash { XCTAssertEqual(entry.contentHash, hash, "\(name) hash") }
        if let text = expect.text { XCTAssertEqual(Self.pasteText(payload).map { Array($0.unicodeScalars) }, Array(text.unicodeScalars), "\(name) text") }
        if case .url(_, let uri, let display) = payload {
            if let e = expect.uri { XCTAssertEqual(uri, e, "\(name) uri") }
            if let e = expect.display { XCTAssertEqual(display, e, "\(name) display") }
        } else if expect.uri != nil || expect.display != nil {
            XCTFail("\(name): uri/display yalnız url'de")
        }
        if let n = expect.imageCount { XCTAssertEqual(Self.imageCount(payload), n, "\(name) imageCount") }
        if let hasRtf = expect.hasRtf {
            guard case .richText(_, _, let rtf) = payload else { return XCTFail("\(name): hasRtf richText değil") }
            XCTAssertEqual(rtf != nil, hasRtf, "\(name) hasRtf")
        }
    }

    private static func pasteText(_ p: Payload) -> String? {
        switch p {
        case .text(let s): return s
        case .url(let original, _, _): return original
        case .color(let original, _, _): return original
        case .svg(let xml): return xml
        case .richText(let plain, _, _): return plain
        default: return nil
        }
    }

    private static func imageCount(_ p: Payload) -> Int? {
        switch p {
        case .image: return 1
        case .imageSet(let items): return items.count
        default: return nil
        }
    }

    private static func describe(_ c: Classification) -> String {
        switch c {
        case .none: return "none"
        case .drop(let reason): return "drop(\(reason))"
        case .payload(let p): return "entry(\(p.kind))"
        }
    }
}

private struct StubFiles: FileReading {
    let size: Int?
    let fails: Bool
    struct Failure: Error {}
    func size(of url: URL) -> Int? { size }
    func read(_ url: URL) throws -> Data {
        if fails { throw Failure() }
        return Data(count: size ?? 0)
    }
}

/// Boyutu küçük bildirip okunduğunda büyümüş gibi davranan sahte dosya.
private struct GrowingFile: FileReading {
    func size(of url: URL) -> Int? { 1 }
    func read(_ url: URL) throws -> Data { Data(repeating: 0x89, count: 64) }
}

/// Vektör girdisini `RawClip`'e çevirir; search.json `index` koşucusu da kullanır.
enum ClassifyHarness {
    static func makeTempDir(_ tag: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: "sclip-\(tag)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func rawClip(_ input: ClassifyInput, tempDir: URL) throws -> RawClip {
        let items = try input.items.map { item -> RawItem in
            var formats: [CanonicalFormat: Data] = [:]
            for (key, bytes) in item.formats {
                guard let format = CanonicalFormat(rawValue: key) else {
                    throw VectorSchemaError.invalid("bilinmeyen kanonik anahtar: \(key)")
                }
                formats[format] = try bytes.data()
            }
            return RawItem(formats: formats)
        }
        // Her vaka kendi alt dizinini alır: aynı adlı üretilmiş dosyalar (big.png) çakışmaz.
        let caseDir = tempDir.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: caseDir, withIntermediateDirectories: true)
        let files = try (input.files ?? []).map { try VectorLoader.materialize($0, in: caseDir) }
        let flags = try (input.flags ?? []).map { raw -> ClipFlag in
            guard let flag = ClipFlag(rawValue: raw) else { throw VectorSchemaError.invalid("bilinmeyen bayrak: \(raw)") }
            return flag
        }
        return RawClip(items: items, files: files, flags: Set(flags))
    }

    static func payload(_ input: ClassifyInput, tempDir: URL, classifier: Classifier = Classifier()) throws -> Payload {
        let result = classifier.classify(try rawClip(input, tempDir: tempDir))
        guard case .payload(let payload) = result else {
            throw VectorSchemaError.invalid("girdi bir öğe üretmedi: \(result)")
        }
        return payload
    }
}
