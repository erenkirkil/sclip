import Combine
import Foundation
import SclipCore

/// Geçmiş listesinin görünümü (B-6.4.x, B-6.5.x). Satırlar her zaman türetilmiştir:
/// `rows = EntryFilter.filter(store.entries, query:)`; filtre depoyu asla değiştirmez (B-8.7.8).
@MainActor
public final class HistoryViewModel: ObservableObject {
    @Published public private(set) var rows: [Entry] = []
    @Published public private(set) var totalCount = 0

    private let store: HistoryStore
    private let search: SearchViewModel
    private let strings: Strings
    private let clock: Clock
    private let resetBaseline: () -> Void
    private var query = ""
    private var queryObservation: AnyCancellable?

    /// `store.onChange`'in tek sahibi bu model olur (init'te atanır); başkası atamamalı.
    /// `resetBaseline`: `CaptureEngine.resetBaseline` (E20); tüm temizleme yolları `clearAll` üzerinden geçer.
    public init(
        store: HistoryStore, search: SearchViewModel, strings: Strings, clock: Clock,
        resetBaseline: @escaping () -> Void
    ) {
        self.store = store
        self.search = search
        self.strings = strings
        self.clock = clock
        self.resetBaseline = resetBaseline
        store.onChange = { [weak self] in self?.recompute() }
        // `$query` willSet'te yayar; `search.query` henüz eskidir, bu yüzden gelen değer kullanılır.
        queryObservation = search.$query.sink { [weak self] newQuery in
            self?.query = newQuery
            self?.recompute()
        }
    }

    // MARK: - Eylemler

    public func ingest(_ e: Entry) { store.add(e) }

    /// Öğeyi siler ve ekran okuyucu duyurusunu döndürür (B-6.10.3). Bilinmeyen id: depo değişmez, "" döner.
    public func delete(_ id: EntryID) -> String {
        guard let entry = store.entries.first(where: { $0.id == id }) else { return "" }
        let announcement = strings.format(.a11yAnnounceDeleted, ["preview": entry.preview(strings)])
        store.remove(id)
        return announcement
    }

    /// B-6.4.9: en üste taşır, zamanı yeniler; id ve hash değişmez.
    public func touch(_ id: EntryID) { store.touch(id, at: clock.now()) }

    /// Ortak temizleme kuralı (B-8.8.9): depo temizlenir, sorgu silinir (çubuk açıksa açık kalır),
    /// temel çizgi bir kez sıfırlanır. Filtre aktifken de **tümü** silinir (B-6.5.8).
    public func clearAll() {
        store.clear()
        search.clearQuery()
        resetBaseline()
    }

    // MARK: - Metinler

    public func clearConfirmation() -> (title: String, body: String, confirm: String, cancel: String) {
        // Filtre "aktif" = görünen sayı toplamdan farklı (Flutter `clearAllMessage` paritesi); her
        // öğeyi eşleyen sorguda görünen sayı ile toplamın aynı olduğu anlamsız bir cümle çıkmaz.
        let body =
            rows.count == totalCount
            ? strings[.clearAllBodyAll]
            : strings.format(
                .clearAllBodyFiltered, ["visible": String(rows.count), "total": String(totalCount)])
        return (strings[.clearAllTitle], body, strings[.clearAllConfirm], strings[.commonCancel])
    }

    /// B-6.5.7: kırpılmış sorgu boşsa `search.empty.no_history`, doluysa (geçmiş boş olsa bile) `search.empty.no_results`.
    public var emptyStateText: String {
        let trimmed = SearchNormalizer.trimmedForDisplay(query)
        if trimmed.isEmpty { return strings[.searchEmptyNoHistory] }
        return strings.format(.searchEmptyNoResults, ["query": trimmed])
    }

    /// Arama kutusunda Enter'ın yapıştıracağı öğe (B-6.2.15); sonuç yoksa `nil`.
    public var firstFilteredEntry: Entry? { rows.first }

    // MARK: - Özel

    private func recompute() {
        rows = EntryFilter.filter(store.entries, query: query)
        totalCount = store.entries.count
    }
}
