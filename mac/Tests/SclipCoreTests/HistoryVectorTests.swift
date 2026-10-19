import XCTest
@testable import SclipCore

final class HistoryVectorTests: XCTestCase {
    func testHistoryVectors() throws {
        let cases = try VectorLoader.historyCases()
        XCTAssertFalse(cases.isEmpty)
        for c in cases {
            try run(c)
        }
    }

    /// Arama filtresi depoyu değiştirmez, `onEvict` çağırmaz (B-8.7.8).
    func testFilterNeverMutatesStore() {
        var evicted: [Entry] = []
        let store = HistoryStore(maxItems: 30) { evicted.append($0) }
        var changes = 0
        let ids = EntryIDGenerator()
        for text in ["alpha", "beta", "gamma"] {
            store.add(Entry(id: ids.next(), createdAt: Date(timeIntervalSince1970: 0), payload: .text(text), isSensitive: false))
        }
        store.onChange = { changes += 1 }
        let before = store.entries

        XCTAssertEqual(EntryFilter.filter(store.entries, query: "ta").count, 1)
        XCTAssertTrue(EntryFilter.filter(store.entries, query: "zzz").isEmpty)
        XCTAssertEqual(EntryFilter.filter(store.entries, query: "").count, 3)

        XCTAssertEqual(store.entries, before)
        XCTAssertTrue(evicted.isEmpty)
        XCTAssertEqual(changes, 0)
    }

    // MARK: - Vektör yürütücü

    private func run(_ c: HistoryCase) throws {
        var caps = SizeCaps.default
        if let budget = c.budgetBytes { caps.totalBudgetBytes = budget }

        var evictedIDs: [EntryID] = []
        let store = HistoryStore(maxItems: c.maxItems, caps: caps) { evictedIDs.append($0.id) }
        let ids = EntryIDGenerator()
        var refByID: [EntryID: String] = [:]
        var idByRef: [String: EntryID] = [:]
        var results: [HistoryAddResult] = []
        var tick = 0.0

        for op in c.ops {
            tick += 1
            let now = Date(timeIntervalSince1970: tick)
            switch op.op {
            case .add:
                let ref = try XCTUnwrap(op.ref, c.name)
                let entry = Entry(id: ids.next(), createdAt: now, payload: try payload(for: op, c.name), isSensitive: false)
                refByID[entry.id] = ref
                switch store.add(entry) {
                case .added:
                    idByRef[ref] = entry.id
                    results.append(.added)
                case .duplicateHead: results.append(.duplicateHead)
                case .rejected: results.append(.rejected)
                }
            case .touch:
                if let id = op.ref.flatMap({ idByRef[$0] }) { store.touch(id, at: now) }
            case .remove:
                if let id = op.ref.flatMap({ idByRef[$0] }) { store.remove(id) }
            case .clear:
                store.clear()
            case .setMax:
                store.maxItems = try XCTUnwrap(op.n, c.name)
            }
        }

        XCTAssertEqual(store.entries.compactMap { refByID[$0.id] }, c.expect.order, "\(c.name): order")
        XCTAssertEqual(evictedIDs.compactMap { refByID[$0] }, c.expect.evicted, "\(c.name): evicted")
        if let expected = c.expect.results {
            XCTAssertEqual(results, expected, "\(c.name): results")
        }
    }

    private func payload(for op: HistoryOp, _ name: String) throws -> Payload {
        switch try XCTUnwrap(op.kind, name) {
        case .text: return .text(try XCTUnwrap(op.textValue, name))
        case .image: return .image(ImageItem(data: try XCTUnwrap(op.genSpec, name).bytes(), format: .png))
        case .pdf: return .pdf(try XCTUnwrap(op.genSpec, name).bytes())
        }
    }
}
