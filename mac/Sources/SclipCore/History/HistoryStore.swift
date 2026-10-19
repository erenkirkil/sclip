import Foundation

/// `HistoryStore.add` sonucu.
public enum AddResult: Sendable, Equatable {
    case added, duplicateHead, rejected
}

/// RAM-only FIFO geçmiş (B-8.7). Ana thread'de kullanılır; `Sendable` değildir.
public final class HistoryStore {
    public private(set) var entries: [Entry] = []

    /// Her `entries` değişikliğinden sonra bir kez çağrılır; no-op işlemlerde çağrılmaz.
    public var onChange: (() -> Void)?

    /// `<= 0` atamalar yok sayılır. Düşürmek fazlayı hemen kırpar (`onEvict` ile, en eski önce).
    public var maxItems: Int {
        get { limit }
        set {
            guard newValue > 0, newValue != limit else { return }
            limit = newValue
            if trimToLimit() { onChange?() }
        }
    }

    private static let defaultMaxItems = 30
    private var limit: Int
    private let caps: SizeCaps
    private let onEvict: (Entry) -> Void
    /// Girdi başına önbelleklenmiş bütçe ağırlığı; her `add`'de yük hesaplanmasın diye.
    private var weights: [EntryID: Int] = [:]

    public init(maxItems: Int = 30, caps: SizeCaps = .default, onEvict: @escaping (Entry) -> Void) {
        self.limit = maxItems > 0 ? maxItems : Self.defaultMaxItems
        self.caps = caps
        self.onEvict = onEvict
    }

    /// B-8.7.1 sırası: (1) tip sınırları → (2) baş kopya → (3) bütçeden büyük → (4) bütçe
    /// projeksiyonu ve kurbanlar → (5) aynı hash'li eskiyi çıkar → (6) başa ekle → (7) FIFO kırp.
    @discardableResult
    public func add(_ entry: Entry) -> AddResult {
        if exceedsTypeCaps(entry.payload) { return .rejected }
        if entries.first?.contentHash == entry.contentHash { return .duplicateHead }

        let weight = MemoryBudget.weight(of: entry.payload, caps: caps)
        if weight > caps.totalBudgetBytes { return .rejected }

        if weight > 0 { evictForBudget(incomingWeight: weight, hash: entry.contentHash) }

        if let index = entries.firstIndex(where: { $0.contentHash == entry.contentHash }) {
            evict(at: index)
        }
        entries.insert(entry, at: 0)
        weights[entry.id] = weight
        trimToLimit()
        onChange?()
        return .added
    }

    /// Öğeyi en üste taşır ve zamanını yeniler; id ve hash değişmez. `onEvict` çağrılmaz.
    @discardableResult
    public func touch(_ id: EntryID, at date: Date) -> Entry? {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return nil }
        let touched = entries.remove(at: index).touched(at: date)
        entries.insert(touched, at: 0)
        onChange?()
        return touched
    }

    public func remove(_ id: EntryID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        evict(at: index)
        onChange?()
    }

    /// Başlangıç sırasıyla (baştan sona) her öğe için `onEvict` çağırır.
    public func clear() {
        guard !entries.isEmpty else { return }
        let victims = entries
        entries.removeAll()
        weights.removeAll()
        victims.forEach(onEvict)
        onChange?()
    }

    // MARK: - İç

    /// Tip başına sınır (B-8.6.1–B-8.6.4); sınırda kabul, bir fazlasında red. İlk savunma hattı
    /// sınıflandırıcıdır (aşan eşlikçiyi düşürüp zengin öğeyi indirir); bu, son güvencedir.
    private func exceedsTypeCaps(_ payload: Payload) -> Bool {
        switch payload {
        case .text(let text):
            return text.utf16.count > caps.textChars
        case .svg(let markup):
            return markup.utf8.count > caps.svgBytes
        case .pdf(let data):
            return data.count > caps.pdfBytes
        case .image(let item):
            return item.data.count > caps.imageBytes
        case .imageSet(let items):
            return items.reduce(0) { $0 + $1.data.count } > caps.imageBytes
        case .richText(let plain, let html, let rtf):
            return plain.utf16.count > caps.textChars || html.utf16.count > caps.textChars
                || (rtf?.count ?? 0) > caps.rtfBytes
        case .url, .color, .files:
            return false
        }
    }

    /// Projeksiyon: toplam − aynı hash'li mevcut ağırlık + yeni ağırlık bütçeyi aşıyorsa, aynı
    /// hash'li olmayan en eski ağır öğeleri sığana kadar düşürür. Ağırlıksız öğelere dokunmaz.
    private func evictForBudget(incomingWeight: Int, hash: String) {
        var projected = incomingWeight
        for e in entries {
            projected += e.contentHash == hash ? 0 : weights[e.id, default: 0]
        }
        while projected > caps.totalBudgetBytes {
            guard let index = entries.lastIndex(where: { $0.contentHash != hash && weights[$0.id, default: 0] > 0 })
            else { return }
            projected -= weights[entries[index].id, default: 0]
            evict(at: index)
        }
    }

    @discardableResult
    private func trimToLimit() -> Bool {
        var trimmed = false
        while entries.count > limit {
            evict(at: entries.count - 1)
            trimmed = true
        }
        return trimmed
    }

    private func evict(at index: Int) {
        let victim = entries.remove(at: index)
        weights[victim.id] = nil
        onEvict(victim)
    }
}
