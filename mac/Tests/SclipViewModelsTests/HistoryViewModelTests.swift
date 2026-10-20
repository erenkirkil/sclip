import Combine
import Foundation
import SclipCore
import XCTest

@testable import SclipViewModels

@MainActor
final class HistoryViewModelTests: XCTestCase {
    private let ids = EntryIDGenerator()

    @MainActor
    private struct Rig {
        let store: HistoryStore
        let search = SearchViewModel()
        let clock = FakeClock(Date(timeIntervalSinceReferenceDate: 1000))
        let evicted = EvictLog()
        let baseline = ResetCounter()
        let vm: HistoryViewModel

        init() {
            let log = evicted
            store = HistoryStore(onEvict: { log.ids.append($0.id) })
            let counter = baseline
            vm = HistoryViewModel(
                store: store, search: search, strings: TestStrings.catalog, clock: clock,
                resetBaseline: { counter.count += 1 })
        }
    }

    @MainActor final class EvictLog { var ids: [EntryID] = [] }
    @MainActor final class ResetCounter { var count = 0 }

    private func text(_ s: String) -> Entry {
        Entry(id: ids.next(), createdAt: Date(timeIntervalSinceReferenceDate: 0), payload: .text(s), isSensitive: false)
    }

    private func texts(_ rig: Rig) -> [String] {
        rig.vm.rows.map { entry in
            if case .text(let s) = entry.payload { return s }
            return ""
        }
    }

    // MARK: - Satırlar (B-6.5.4, B-6.5.6, B-8.7.8)

    func testFilterUpdatesRowsNotStore() {
        let rig = Rig()
        ["elma", "armut", "elmas"].forEach { rig.vm.ingest(text($0)) }
        let before = rig.store.entries
        rig.search.query = "elma"
        XCTAssertEqual(texts(rig), ["elmas", "elma"])
        XCTAssertEqual(rig.vm.totalCount, 3)
        XCTAssertEqual(rig.store.entries, before)
        XCTAssertTrue(rig.evicted.ids.isEmpty)
        rig.search.query = ""
        XCTAssertEqual(rig.vm.rows, before)
    }

    func testRowsRecomputedWhenIngestingWhileFiltered() {
        let rig = Rig()
        rig.vm.ingest(text("elma"))
        rig.search.query = "elma"
        rig.vm.ingest(text("armut"))
        XCTAssertEqual(texts(rig), ["elma"])
        rig.vm.ingest(text("elma kabuğu"))
        XCTAssertEqual(texts(rig), ["elma kabuğu", "elma"])
        XCTAssertEqual(rig.vm.totalCount, 3)
    }

    func testInitialRowsReflectExistingStore() {
        let evicted = EvictLog()
        let store = HistoryStore(onEvict: { evicted.ids.append($0.id) })
        store.add(text("a"))
        let vm = HistoryViewModel(
            store: store, search: SearchViewModel(), strings: TestStrings.catalog,
            clock: FakeClock(), resetBaseline: {})
        XCTAssertEqual(vm.rows.count, 1)
        XCTAssertEqual(vm.totalCount, 1)
    }

    func testFirstFilteredEntryIsFirstRow() {
        let rig = Rig()
        XCTAssertNil(rig.vm.firstFilteredEntry)
        ["elma", "armut", "elmas"].forEach { rig.vm.ingest(text($0)) }
        XCTAssertEqual(rig.vm.firstFilteredEntry, rig.vm.rows.first)
        rig.search.query = "armut"
        XCTAssertEqual(rig.vm.firstFilteredEntry?.payload, .text("armut"))
        rig.search.query = "yok"
        XCTAssertNil(rig.vm.firstFilteredEntry)
    }

    // MARK: - Sil / dokun (B-6.10.3, B-6.4.9)

    func testDeleteAnnouncement() {
        let rig = Rig()
        let e = text("merhaba dünya")
        rig.vm.ingest(e)
        let announcement = rig.vm.delete(e.id)
        XCTAssertEqual(announcement, "Silindi: merhaba dünya")
        XCTAssertTrue(rig.vm.rows.isEmpty)
        XCTAssertEqual(rig.vm.totalCount, 0)
        XCTAssertEqual(rig.evicted.ids, [e.id])
    }

    func testDeleteUnknownIdReturnsEmptyAndChangesNothing() {
        let rig = Rig()
        rig.vm.ingest(text("a"))
        let announcement = rig.vm.delete(EntryID(raw: 9999))
        XCTAssertEqual(announcement, "")
        XCTAssertEqual(rig.vm.totalCount, 1)
        XCTAssertTrue(rig.evicted.ids.isEmpty)
    }

    func testTouchMovesToTopKeepsId() {
        let rig = Rig()
        let a = text("a"), b = text("b"), c = text("c")
        [a, b, c].forEach { rig.vm.ingest($0) }
        rig.vm.touch(a.id)
        XCTAssertEqual(rig.vm.rows.map(\.id), [a.id, c.id, b.id])
        XCTAssertEqual(rig.vm.rows.first?.contentHash, a.contentHash)
        XCTAssertEqual(rig.vm.rows.first?.createdAt, rig.clock.now())
        XCTAssertTrue(rig.evicted.ids.isEmpty)
    }

    func testTouchUnknownIdIsNoOp() {
        let rig = Rig()
        let a = text("a")
        rig.vm.ingest(a)
        rig.vm.touch(EntryID(raw: 9999))
        XCTAssertEqual(rig.vm.rows.map(\.id), [a.id])
    }

    // MARK: - Hepsini sil (B-6.5.8, B-8.8.9, E20)

    func testClearAllCallsResetBaselineOnce() {
        let rig = Rig()
        ["a", "b"].forEach { rig.vm.ingest(text($0)) }
        rig.vm.clearAll()
        XCTAssertEqual(rig.baseline.count, 1)
        XCTAssertTrue(rig.store.entries.isEmpty)
        XCTAssertTrue(rig.vm.rows.isEmpty)
        XCTAssertEqual(rig.vm.totalCount, 0)
        XCTAssertEqual(rig.evicted.ids.count, 2)
    }

    func testClearAllOnEmptyStoreStillResetsBaselineOnce() {
        let rig = Rig()
        rig.vm.clearAll()
        XCTAssertEqual(rig.baseline.count, 1)
    }

    /// U1 / B-8.8.9: sorgu temizlenir, çubuk açıksa açık kalır; temizleme filtreye bakmaz.
    func testClearAllClearsQueryKeepsBarOpenAndDeletesEverything() {
        let rig = Rig()
        ["elma", "armut", "elmas"].forEach { rig.vm.ingest(text($0)) }
        rig.search.open()
        rig.search.query = "elma"
        XCTAssertEqual(rig.vm.rows.count, 2)
        rig.vm.clearAll()
        XCTAssertEqual(rig.search.query, "")
        XCTAssertTrue(rig.search.isOpen)
        XCTAssertTrue(rig.store.entries.isEmpty)
        XCTAssertEqual(rig.evicted.ids.count, 3)
        XCTAssertEqual(rig.baseline.count, 1)
    }

    func testClearConfirmationFilteredText() {
        let rig = Rig()
        for i in 0..<24 { rig.vm.ingest(text("x\(i)")) }
        for i in 0..<3 { rig.vm.ingest(text("kedi\(i)")) }
        rig.search.query = "kedi"
        XCTAssertEqual(rig.vm.rows.count, 3)
        let c = rig.vm.clearConfirmation()
        XCTAssertEqual(c.body, "Filtre aktif: görünen 3 değil, tümü (27) silinecek. Emin misin?")
        XCTAssertEqual(c.title, "Geçmişi sil")
        XCTAssertEqual(c.confirm, "Hepsini sil")
        XCTAssertEqual(c.cancel, "Vazgeç")
    }

    func testClearConfirmationUnfilteredText() {
        let rig = Rig()
        rig.vm.ingest(text("a"))
        XCTAssertEqual(rig.vm.clearConfirmation().body, "Tüm pano geçmişi silinecek. Emin misin?")
        rig.search.query = "   "  // yalnız boşluk: filtre yok
        XCTAssertEqual(rig.vm.clearConfirmation().body, "Tüm pano geçmişi silinecek. Emin misin?")
    }

    /// Flutter paritesi (home_page.dart:41-47): görünen == toplam ise filtre "yok" sayılır;
    /// "görünen 2 değil, tümü (2)" gibi anlamsız bir cümle çıkmaz.
    func testClearConfirmationWhenQueryMatchesEverythingUsesAllText() {
        let rig = Rig()
        ["elma", "elmas"].forEach { rig.vm.ingest(text($0)) }
        rig.search.query = "elma"
        XCTAssertEqual(rig.vm.clearConfirmation().body, "Tüm pano geçmişi silinecek. Emin misin?")
    }

    // MARK: - Boş durum (B-6.5.7)

    func testEmptyStateTexts() {
        let rig = Rig()
        XCTAssertEqual(rig.vm.emptyStateText, "Henüz içerik yok — bir şey kopyala")
        rig.vm.ingest(text("elma"))
        rig.search.query = "  armut "
        XCTAssertEqual(rig.vm.emptyStateText, "'armut' için sonuç yok")
    }

    /// Karar J: geçmiş boşken bile kırpılmış sorgu doluysa "sonuç yok" metni.
    func testEmptyStateWithNonEmptyQueryAndEmptyHistoryShowsNoResults() {
        let rig = Rig()
        rig.search.query = "armut"
        XCTAssertEqual(rig.vm.emptyStateText, "'armut' için sonuç yok")
    }

    func testWhitespaceOnlyQueryShowsNoHistoryText() {
        let rig = Rig()
        rig.search.query = " \t\u{3000}\u{85} "
        XCTAssertEqual(rig.vm.emptyStateText, "Henüz içerik yok — bir şey kopyala")
    }
}
