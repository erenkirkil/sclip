import SclipCore

/// Pano yazma taklidi: çağrıları kaydeder, istenirse hata atar.
final class FakeSink: ClipboardSink {
    struct WriteError: Error {}
    struct Call: Equatable {
        let id: EntryID
        let plainOnly: Bool
        let imageIndex: Int?
    }

    private let log: CallLog
    private(set) var calls: [Call] = []
    var failure: Error?
    var receipt = WriteReceipt(change: 42, signature: "sig")

    init(log: CallLog) { self.log = log }

    func write(_ entry: Entry, plainOnly: Bool, imageIndex: Int?) throws -> WriteReceipt {
        calls.append(Call(id: entry.id, plainOnly: plainOnly, imageIndex: imageIndex))
        log.add("write")
        if let failure { throw failure }
        return receipt
    }
}
