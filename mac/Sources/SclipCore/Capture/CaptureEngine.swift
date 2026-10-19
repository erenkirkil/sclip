import Foundation

/// Pano izleme motoru (B-8.8.4–B-8.8.9). Ana thread'de çalışır, `Sendable` değildir; depoya eklemeyi
/// çağıran yapar. Kilit kenarı `ScreenLockMonitor`'dadır, okuma zaman aşımı platform uyarlayıcısındadır.
public final class CaptureEngine {
    /// Gizli içerik filtresi (ayar anahtarı); sonraki `tick`'ten itibaren geçerlidir.
    public var sensitiveFilter: Bool

    /// Son yayınlanan ya da kendi yazılan içeriğin imzası; `nil` = dedup yok.
    public private(set) var lastSignature: String?

    private let source: ClipboardSource
    private let classifier: Classifier
    private let ids: EntryIDGenerator
    private let clock: Clock
    /// `nil` = temel çizgi henüz alınmadı (ilk `tick` yalnız temel çizgidir, B-8.8.5).
    private var baseline: Int?
    /// Boş dosya okumasında geri sarılan sayacın bekleyen denemesi; aynı sayaçta aynı kimlik/temp dizini kullanılır.
    private var pendingFiles: FilesAttempt?
    private let filesRetryWindow: TimeInterval

    private struct FilesAttempt {
        let change: Int
        let id: EntryID
        let firstAttempt: Date
    }

    public init(
        source: ClipboardSource, classifier: Classifier, ids: EntryIDGenerator, clock: Clock,
        sensitiveFilter: Bool, filesRetryWindow: TimeInterval = 10
    ) {
        self.filesRetryWindow = filesRetryWindow
        self.source = source
        self.classifier = classifier
        self.ids = ids
        self.clock = clock
        self.sensitiveFilter = sensitiveFilter
    }

    /// Tek yoklama turu. Yeni bir öğe yakalandıysa döner.
    public func tick() -> Entry? {
        let state = source.currentState()
        // Sayaç aynıysa çık; ilk tick yalnız temel çizgidir.
        guard let previous = baseline else {
            baseline = state.change
            return nil
        }
        if state.change == previous { return nil }
        baseline = state.change

        // Hassas + filtre açık: sayaç tüketilir, içerik okunmaz, imzaya dokunulmaz.
        if state.sensitive && sensitiveFilter { return nil }

        if state.hasFiles { return captureFiles(state, previous: previous) }
        let clip = source.readClip()
        // Okuma sırasında gizli bayrak belirdiyse (yarış) fail-closed: filtre açıkken atla (E31).
        if sensitiveFilter && !clip.flags.isEmpty { return nil }
        return publish(classifier.classify(clip), sensitive: state.sensitive || !clip.flags.isEmpty)
    }

    /// Ortak temizleme kuralı (B-8.8.9, E20): temel çizgi = şimdiki sayaç, imza dedup'ı sıfır.
    public func resetBaseline() {
        baseline = source.currentState().change
        lastSignature = nil
        pendingFiles = nil
    }

    /// Kendi geri yazımını bastır (B-8.8.8, E30): yeni sayaç temel çizgi, imza dedup yedeği.
    public func noteOwnWrite(_ receipt: WriteReceipt) {
        baseline = receipt.change
        lastSignature = receipt.signature
    }

    // MARK: - İç

    /// Dosya yolu (B-8.8.4). Hassas kopyada (filtre kapalı) promise çözülmez, kimlik ayrılmaz, yeniden deneme
    /// yoktur (B-8.4.4). Aksi hâlde kimlik önce ayrılır, promise'lar o kimliğin temp dizinine iner (E26); boş
    /// dönüş sayacı geri sarar ve ilk denemeden itibaren `filesRetryWindow` boyunca yeniden denenir (B-8.8.6).
    private func captureFiles(_ state: ClipboardState, previous: Int) -> Entry? {
        if state.sensitive {
            let urls = source.readFiles(destination: nil)
            return publishFiles(urls, sensitive: true, id: ids.next())
        }
        let attempt = pendingFiles.flatMap { $0.change == state.change ? $0 : nil }
            ?? FilesAttempt(change: state.change, id: ids.next(), firstAttempt: clock.now())
        pendingFiles = nil
        let urls = source.readFiles(destination: attempt.id)
        if urls.isEmpty {
            // Pencere dolduysa sayaç tüketilmiş kalır, kimlik bırakılır.
            if clock.now().timeIntervalSince(attempt.firstAttempt) <= filesRetryWindow {
                baseline = previous
                pendingFiles = attempt
            }
            return nil
        }
        return publishFiles(urls, sensitive: false, id: attempt.id)
    }

    private func publishFiles(_ urls: [URL], sensitive: Bool, id: EntryID) -> Entry? {
        guard !urls.isEmpty else { return nil }
        let clip = RawClip(items: [], files: urls, flags: [])
        return publish(classifier.classify(clip), sensitive: sensitive, id: id)
    }

    /// `drop` / `none` imzayı ayarlamaz (E25, B-8.6.4); sayaç yine de tüketilmiştir (sıcak yeniden deneme yok,
    /// Flutter ile aynı). İmza dedup'ı yalnız yayınlanacak öğeye uygulanır.
    private func publish(_ result: Classification, sensitive: Bool, id: EntryID? = nil) -> Entry? {
        guard case .payload(let payload) = result else { return nil }
        let entry = Entry(
            id: id ?? ids.next(), createdAt: clock.now(), payload: payload, isSensitive: sensitive)
        if entry.contentHash == lastSignature { return nil }
        lastSignature = entry.contentHash
        return entry
    }
}
