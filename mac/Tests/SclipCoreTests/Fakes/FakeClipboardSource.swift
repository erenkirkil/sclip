import Foundation
@testable import SclipCore

/// Betiklenebilir pano kaynağı; okuma çağrılarını sayar.
final class FakeClipboardSource: ClipboardSource {
    var state = ClipboardState(change: 1, sensitive: false, hasFiles: false)
    var clip = RawClip(items: [], files: [], flags: [])
    /// `readFiles` çağrılarında sırayla dönen sonuçlar; tükenince son sonuç tekrarlanır.
    var fileResults: [[URL]] = []
    private(set) var readClipCalls = 0
    private(set) var readFilesCalls = 0
    private(set) var fileDestinations: [EntryID?] = []

    func currentState() -> ClipboardState { state }

    func readFiles(destination: EntryID?) -> [URL] {
        readFilesCalls += 1
        fileDestinations.append(destination)
        guard !fileResults.isEmpty else { return [] }
        return fileResults.count > 1 ? fileResults.removeFirst() : fileResults[0]
    }

    func readClip() -> RawClip {
        readClipCalls += 1
        return clip
    }

    // MARK: - Betik yardımcıları

    /// Sayacı artırıp düz metin kopyasını kurar.
    func copyText(_ text: String, flags: Set<ClipFlag> = [], sensitive: Bool = false) {
        state = ClipboardState(change: state.change + 1, sensitive: sensitive, hasFiles: false)
        clip = RawClip(
            items: [RawItem(formats: [.plainText: Data(text.utf8)])], files: [], flags: flags)
    }

    /// Sayacı artırıp tek öğeli, tek biçimli bir kopya kurar.
    func copyItem(_ format: CanonicalFormat, _ data: Data) {
        state = ClipboardState(change: state.change + 1, sensitive: false, hasFiles: false)
        clip = RawClip(items: [RawItem(formats: [format: data])], files: [], flags: [])
    }

    func copyFiles(resolved: [[URL]], sensitive: Bool = false) {
        state = ClipboardState(change: state.change + 1, sensitive: sensitive, hasFiles: true)
        fileResults = resolved
    }
}
