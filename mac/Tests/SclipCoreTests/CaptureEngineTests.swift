import XCTest
@testable import SclipCore

final class CaptureEngineTests: XCTestCase {
    private let source = FakeClipboardSource()
    private let now = Date(timeIntervalSince1970: 1_000)

    /// Testte elle ilerletilen saat (yalnız ana thread).
    private final class TestClock: Clock, @unchecked Sendable {
        var date: Date
        init(_ date: Date) { self.date = date }
        func now() -> Date { date }
    }

    private lazy var clock = TestClock(now)

    private func makeEngine(
        filter: Bool = true, caps: SizeCaps = .default, window: TimeInterval = 10
    ) -> CaptureEngine {
        CaptureEngine(
            source: source, classifier: Classifier(caps: caps), ids: EntryIDGenerator(),
            clock: clock, sensitiveFilter: filter, filesRetryWindow: window)
    }

    private let pngHeader = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

    private func text(_ entry: Entry?) -> String? {
        if case .text(let value)? = entry?.payload { return value }
        return nil
    }

    func testFirstTickIsBaseline() {
        let engine = makeEngine()
        source.copyText("old")
        XCTAssertNil(engine.tick())
        XCTAssertEqual(source.readClipCalls, 0)
        source.copyText("new")
        XCTAssertEqual(text(engine.tick()), "new")
    }

    func testUnchangedCounterSkipsRead() {
        let engine = makeEngine()
        _ = engine.tick()
        source.copyText("a")
        XCTAssertNotNil(engine.tick())
        XCTAssertEqual(source.readClipCalls, 1)
        XCTAssertNil(engine.tick())
        XCTAssertNil(engine.tick())
        XCTAssertEqual(source.readClipCalls, 1)
    }

    func testSensitiveConsumesCounter() {
        let engine = makeEngine(filter: true)
        _ = engine.tick()
        source.copyText("secret", flags: [.concealed], sensitive: true)
        XCTAssertNil(engine.tick())
        XCTAssertNil(engine.tick())
        XCTAssertEqual(source.readClipCalls, 0)
        source.copyText("public")
        XCTAssertEqual(text(engine.tick()), "public")
    }

    func testConcealedWithFilterOffIsMarkedSensitive() {
        let engine = makeEngine(filter: false)
        _ = engine.tick()
        source.copyText("secret", flags: [.concealed], sensitive: true)
        let entry = engine.tick()
        XCTAssertEqual(text(entry), "secret")
        XCTAssertEqual(entry?.isSensitive, true)
        source.copyText("tmp", flags: [.transient])
        XCTAssertEqual(engine.tick()?.isSensitive, true)
        source.copyText("plain")
        XCTAssertEqual(engine.tick()?.isSensitive, false)
    }

    func testSensitiveFilterToggleAppliesToNextTick() {
        let engine = makeEngine(filter: true)
        _ = engine.tick()
        engine.sensitiveFilter = false
        source.copyText("s", flags: [.concealed], sensitive: true)
        XCTAssertEqual(engine.tick()?.isSensitive, true)
        engine.sensitiveFilter = true
        source.copyText("s2", flags: [.concealed], sensitive: true)
        XCTAssertNil(engine.tick())
    }

    func testEmptyFilesRewindsAndRetries() {
        let engine = makeEngine()
        _ = engine.tick()
        let url = URL(filePath: "/nonexistent/sclip-test/a.txt")
        source.copyFiles(resolved: [[], [url]])
        XCTAssertNil(engine.tick())
        XCTAssertEqual(source.readFilesCalls, 1)
        let entry = engine.tick()
        XCTAssertEqual(source.readFilesCalls, 2)
        XCTAssertEqual(entry?.payload, .files([url]))
        XCTAssertEqual(source.fileDestinations.first, source.fileDestinations.last)
        XCTAssertEqual(entry?.id, source.fileDestinations.last ?? nil)
        XCTAssertNil(engine.tick(), "başarılı okuma sayacı tüketir")
        XCTAssertEqual(source.readFilesCalls, 2)
        XCTAssertEqual(source.readClipCalls, 0)
    }

    func testOwnWriteIsNotRecaptured() {
        let engine = makeEngine()
        _ = engine.tick()
        source.copyText("mine")
        engine.noteOwnWrite(WriteReceipt(change: source.state.change, signature: ContentHash.of(.text("mine"))))
        XCTAssertNil(engine.tick())
        XCTAssertEqual(source.readClipCalls, 0)
        // Yedek: sayaç yine de değişirse hash dedup devreye girer.
        source.copyText("mine")
        XCTAssertNil(engine.tick())
        XCTAssertEqual(engine.lastSignature, ContentHash.of(.text("mine")))
    }

    func testAfterResetBaselineNextCopyIsCaptured() {
        let engine = makeEngine()
        _ = engine.tick()
        source.copyText("before")
        XCTAssertNotNil(engine.tick())
        engine.resetBaseline()
        XCTAssertNil(engine.lastSignature)
        XCTAssertNil(engine.tick(), "temizlik anındaki pano yeniden yakalanmaz")
        source.copyText("after")
        XCTAssertEqual(text(engine.tick()), "after")
    }

    func testAfterResetBaselineSameContentRecopyIsCaptured() {
        let engine = makeEngine()
        _ = engine.tick()
        source.copyText("same")
        XCTAssertNotNil(engine.tick())
        engine.resetBaseline()
        source.copyText("same")
        XCTAssertEqual(text(engine.tick()), "same")
    }

    /// E20 vektörü `clear_then_readd_same_content_added`, vektörün kendi op'larıyla motor + depo üzerinden.
    func testClearThenReaddSameContentVectorThroughEngineAndStore() throws {
        let vector = try XCTUnwrap(
            VectorLoader.historyCases().first { $0.name == "clear_then_readd_same_content_added" })
        let store = HistoryStore(maxItems: vector.maxItems) { _ in }
        let engine = makeEngine()
        _ = engine.tick()
        var refByID: [EntryID: String] = [:]
        var results: [HistoryAddResult] = []
        for op in vector.ops {
            switch op.op {
            case .add:
                source.copyText(try XCTUnwrap(op.textValue))
                let entry = try XCTUnwrap(engine.tick(), "motor öğeyi yakalamalı")
                refByID[entry.id] = op.ref
                switch store.add(entry) {
                case .added: results.append(.added)
                case .duplicateHead: results.append(.duplicateHead)
                case .rejected: results.append(.rejected)
                }
            case .clear:
                store.clear()
                engine.resetBaseline()
            default:
                XCTFail("beklenmeyen op \(op.op)")
            }
        }
        XCTAssertEqual(results, vector.expect.results)
        XCTAssertEqual(store.entries.compactMap { refByID[$0.id] }, vector.expect.order)
    }

    func testOversizedPayloadDoesNotConsumeSignature() {
        var caps = SizeCaps.default
        caps.imageBytes = 16
        let engine = makeEngine(caps: caps)
        _ = engine.tick()
        source.copyText("keep")
        XCTAssertNotNil(engine.tick())
        let earlier = engine.lastSignature
        XCTAssertNotNil(earlier)

        let big = pngHeader + Data(repeating: 1, count: 32)
        source.copyItem(.png, big)
        XCTAssertNil(engine.tick())
        XCTAssertEqual(engine.lastSignature, earlier, "düşen görsel imzayı tüketmez (E25)")
        XCTAssertEqual(source.readClipCalls, 2)
        XCTAssertNil(engine.tick(), "sayaç tüketildi: sıcak yeniden deneme yok")
        XCTAssertEqual(source.readClipCalls, 2)

        let small = pngHeader + Data(repeating: 1, count: 4)
        source.copyItem(.png, small)
        guard case .image? = engine.tick()?.payload else { return XCTFail("sınır altı görsel yakalanmalı") }
        XCTAssertNotEqual(engine.lastSignature, earlier)
    }

    func testFilterOnAndFlagsAppearAfterReadIsSkipped() {
        let engine = makeEngine(filter: true)
        _ = engine.tick()
        source.copyText("race", flags: [.concealed])  // state.sensitive == false: yarış
        XCTAssertNil(engine.tick())
        XCTAssertNil(engine.lastSignature)
        XCTAssertEqual(source.readClipCalls, 1)
        XCTAssertNil(engine.tick())
        XCTAssertEqual(source.readClipCalls, 1)
    }

    func testSensitiveFilesDoNotResolvePromisesAndAreMarkedSensitive() {
        let engine = makeEngine(filter: false)
        _ = engine.tick()
        let url = URL(filePath: "/nonexistent/sclip-test/secret.txt")
        source.copyFiles(resolved: [[url]], sensitive: true)
        let entry = engine.tick()
        XCTAssertEqual(entry?.payload, .files([url]))
        XCTAssertEqual(entry?.isSensitive, true)
        XCTAssertEqual(source.fileDestinations.count, 1)
        XCTAssertNil(source.fileDestinations[0] ?? nil, "hassas kopyada hedef dizin verilmez (B-8.4.4)")
    }

    func testSensitiveFilesEmptyResultIsSkippedWithoutRetry() {
        let engine = makeEngine(filter: false)
        _ = engine.tick()
        source.copyFiles(resolved: [[]], sensitive: true)
        XCTAssertNil(engine.tick())
        XCTAssertNil(engine.tick())
        XCTAssertEqual(source.readFilesCalls, 1)
        XCTAssertNil(source.fileDestinations[0] ?? nil)
    }

    func testEmptyFilesRetriesWithinWindow() {
        let engine = makeEngine(window: 10)
        _ = engine.tick()
        let url = URL(filePath: "/nonexistent/sclip-test/a.txt")
        source.copyFiles(resolved: [[], [], [], [url]])
        for _ in 0..<3 {
            XCTAssertNil(engine.tick())
            clock.date.addTimeInterval(3)
        }
        // İlk denemeden 9 sn sonra hâlâ pencere içinde.
        XCTAssertEqual(source.readFilesCalls, 3)
        XCTAssertEqual(engine.tick()?.payload, .files([url]))
        XCTAssertEqual(source.readFilesCalls, 4)
    }

    func testEmptyFilesAbandonedAfterWindow() {
        let engine = makeEngine(window: 10)
        _ = engine.tick()
        source.copyFiles(resolved: [[]])
        XCTAssertNil(engine.tick())
        clock.date.addTimeInterval(11)
        XCTAssertNil(engine.tick(), "pencere dolu: boş sonuç terk edilir")
        XCTAssertEqual(source.readFilesCalls, 2)
        XCTAssertNil(engine.tick())
        XCTAssertNil(engine.tick())
        XCTAssertEqual(source.readFilesCalls, 2, "sayaç tüketildi: readFiles çağrılmaz")
    }

    func testPendingFilesIDIsDroppedWhenCounterChanges() {
        let engine = makeEngine()
        _ = engine.tick()
        let url = URL(filePath: "/nonexistent/sclip-test/b.txt")
        source.copyFiles(resolved: [[]])
        XCTAssertNil(engine.tick())
        XCTAssertNil(engine.tick())
        let oldID = source.fileDestinations[0]
        XCTAssertEqual(source.fileDestinations[1], oldID, "aynı sayaçta kimlik yeniden kullanılır")
        source.copyFiles(resolved: [[url]])
        let entry = engine.tick()
        XCTAssertNotNil(entry)
        XCTAssertNotEqual(entry?.id, oldID ?? nil, "yeni sayaç yeni kimlik alır")
        XCTAssertEqual(source.fileDestinations[2], entry?.id)
    }

    func testUnrecognizedClipIsNotPublishedAndKeepsSignature() {
        let engine = makeEngine()
        _ = engine.tick()
        source.copyText("keep")
        XCTAssertNotNil(engine.tick())
        source.state = ClipboardState(change: 99, sensitive: false, hasFiles: false)
        source.clip = RawClip(items: [], files: [], flags: [])
        XCTAssertNil(engine.tick())
        XCTAssertEqual(engine.lastSignature, ContentHash.of(.text("keep")))
    }

    func testEntryCarriesClockTimeAndUniqueIDs() {
        let engine = makeEngine()
        _ = engine.tick()
        source.copyText("a")
        let first = engine.tick()
        source.copyText("b")
        let second = engine.tick()
        XCTAssertEqual(first?.createdAt, now)
        XCTAssertNotEqual(first?.id, second?.id)
    }
}
