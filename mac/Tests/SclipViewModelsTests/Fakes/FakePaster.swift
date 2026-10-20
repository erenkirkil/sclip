@testable import SclipViewModels

/// Yapıştırma hedefi taklidi: tamamlama kapanışını tutar, testler sonucu kendisi verir.
@MainActor
final class FakePaster: PastePort {
    private let log: CallLog
    private(set) var captureCount = 0
    private(set) var pasteCount = 0
    private var completions: [@MainActor (PasteOutcome) -> Void] = []
    private var pending: Int?
    /// Doluysa `pasteToTarget` hemen bu sonuçla (eşzamanlı) tamamlanır (B-7.1.6 c).
    var immediateOutcome: PasteOutcome?

    init(log: CallLog) { self.log = log }

    var isWaiting: Bool { pending != nil }

    func captureTarget() {
        captureCount += 1
        log.add("capture")
    }

    func pasteToTarget(completion: @escaping @MainActor (PasteOutcome) -> Void) {
        pasteCount += 1
        completions.append(completion)
        pending = completions.count - 1
        log.add("pasteToTarget")
        if let immediateOutcome { complete(immediateOutcome) }
    }

    /// Bekleyen (en son) yapıştırmayı tamamlar.
    func complete(_ outcome: PasteOutcome) {
        guard let index = pending else { return }
        pending = nil
        completions[index](outcome)
    }

    /// Daha önce verilmiş bir kapanışı tekrar çağırır (bayat/yinelenen tamamlama).
    func completeAgain(at index: Int, _ outcome: PasteOutcome) {
        completions[index](outcome)
    }
}
