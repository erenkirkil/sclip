import XCTest
@testable import SclipCore

final class HistoryStoreTests: XCTestCase {
    private let ids = EntryIDGenerator()

    private func entry(_ payload: Payload) -> Entry {
        Entry(id: ids.next(), createdAt: Date(timeIntervalSince1970: 0), payload: payload, isSensitive: false)
    }

    private func text(_ value: String) -> Entry { entry(.text(value)) }

    func testNonPositiveMaxItemsIsIgnored() {
        let store = HistoryStore(maxItems: 5) { _ in }
        store.maxItems = 0
        XCTAssertEqual(store.maxItems, 5)
        store.maxItems = -3
        XCTAssertEqual(store.maxItems, 5)
        XCTAssertEqual(HistoryStore(maxItems: 0) { _ in }.maxItems, 30)
    }

    func testLoweringMaxItemsTrimsAndEvictsOldestFirst() {
        var evicted: [String] = []
        let store = HistoryStore(maxItems: 30) { if case .text(let t) = $0.payload { evicted.append(t) } }
        for t in ["a", "b", "c", "d"] { store.add(text(t)) }
        var changes = 0
        store.onChange = { changes += 1 }
        store.maxItems = 2
        XCTAssertEqual(evicted, ["a", "b"])
        XCTAssertEqual(store.entries.count, 2)
        XCTAssertEqual(changes, 1)
        store.maxItems = 50
        XCTAssertEqual(changes, 1, "yükseltme değişiklik değildir")
    }

    func testOnChangeFiresOncePerMutationNotOnNoOps() {
        let store = HistoryStore(maxItems: 2) { _ in }
        var changes = 0
        store.onChange = { changes += 1 }
        let first = text("a")
        store.add(first)
        XCTAssertEqual(changes, 1)
        store.add(text("a"))  // duplicateHead
        XCTAssertEqual(changes, 1)
        store.add(text("b"))
        store.add(text("c"))  // taşma: tek onChange
        XCTAssertEqual(changes, 3)
        store.remove(first.id)  // zaten düşmüş
        XCTAssertEqual(changes, 3)
        XCTAssertNil(store.touch(first.id, at: Date()))
        XCTAssertEqual(changes, 3)
        store.clear()
        XCTAssertEqual(changes, 4)
        store.clear()
        XCTAssertEqual(changes, 4)
    }

    func testTouchReturnsRefreshedEntryAndKeepsIdentity() throws {
        var evictions = 0
        let store = HistoryStore(maxItems: 30) { _ in evictions += 1 }
        let a = text("a")
        store.add(a)
        store.add(text("b"))
        let when = Date(timeIntervalSince1970: 99)
        let touched = try XCTUnwrap(store.touch(a.id, at: when))
        XCTAssertEqual(touched.id, a.id)
        XCTAssertEqual(touched.contentHash, a.contentHash)
        XCTAssertEqual(touched.createdAt, when)
        XCTAssertEqual(store.entries.first, touched)
        XCTAssertEqual(evictions, 0)
    }

    func testPerTypeCapsRejectAboveLimitAndAcceptAtLimit() {
        var caps = SizeCaps.default
        caps.textChars = 10
        caps.svgBytes = 10
        caps.pdfBytes = 10
        caps.imageBytes = 10
        caps.rtfBytes = 10
        let store = HistoryStore(maxItems: 30, caps: caps) { _ in }
        func add(_ p: Payload) -> AddResult { store.add(entry(p)) }
        let img = { (n: Int) in ImageItem(data: Data(repeating: UInt8(n), count: n), format: .png) }

        XCTAssertEqual(add(.text(String(repeating: "a", count: 10))), .added)
        XCTAssertEqual(add(.text(String(repeating: "b", count: 11))), .rejected)
        XCTAssertEqual(add(.svg(String(repeating: "c", count: 10))), .added)
        XCTAssertEqual(add(.svg(String(repeating: "d", count: 11))), .rejected)
        XCTAssertEqual(add(.pdf(Data(repeating: 1, count: 10))), .added)
        XCTAssertEqual(add(.pdf(Data(repeating: 2, count: 11))), .rejected)
        XCTAssertEqual(add(.image(img(10))), .added)
        XCTAssertEqual(add(.image(img(11))), .rejected)
        XCTAssertEqual(add(.imageSet([img(5), img(5)])), .added)
        XCTAssertEqual(add(.imageSet([img(5), img(6)])), .rejected)
        XCTAssertEqual(add(.richText(plain: "p", html: "h", rtf: Data(repeating: 3, count: 10))), .added)
        XCTAssertEqual(add(.richText(plain: "p", html: "h", rtf: Data(repeating: 4, count: 11))), .rejected)
        XCTAssertEqual(add(.richText(plain: String(repeating: "p", count: 11), html: "h", rtf: nil)), .rejected)
        XCTAssertEqual(add(.richText(plain: "p", html: String(repeating: "h", count: 11), rtf: nil)), .rejected)
    }

    func testRejectedAddDoesNotTouchStore() {
        var caps = SizeCaps.default
        caps.imageBytes = 4
        var evictions = 0
        let store = HistoryStore(maxItems: 30, caps: caps) { _ in evictions += 1 }
        var changes = 0
        store.add(text("keep"))
        store.onChange = { changes += 1 }
        let big = entry(.image(ImageItem(data: Data(count: 5), format: .png)))
        XCTAssertEqual(store.add(big), .rejected)
        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(evictions, 0)
        XCTAssertEqual(changes, 0)
    }
}
