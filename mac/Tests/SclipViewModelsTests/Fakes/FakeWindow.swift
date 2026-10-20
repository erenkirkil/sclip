@testable import SclipViewModels

/// Panel penceresi taklidi: `show` anahtar durumu verir, `hide` alır.
@MainActor
final class FakeWindow: PanelWindowPort {
    private let log: CallLog
    private(set) var showCount = 0
    private(set) var hideCount = 0
    private(set) var focusTargets: [FocusTarget] = []
    var isKey = false
    /// `false` ise `show` pencereyi görünür ama anahtar olmayan bırakır.
    var becomesKeyOnShow = true
    /// Anahtar pencere gizlenirken eşzamanlı çağrılır (macOS `orderOut` → `windowDidResignKey`).
    var onResignKeyDuringHide: (@MainActor () -> Void)?

    init(log: CallLog) { self.log = log }

    func show() {
        showCount += 1
        isKey = becomesKeyOnShow
        log.add("show")
    }

    func hide() {
        hideCount += 1
        let wasKey = isKey
        isKey = false
        log.add("hide")
        if wasKey { onResignKeyDuringHide?() }
    }

    func focus(_ target: FocusTarget) {
        focusTargets.append(target)
        log.add("focus(\(target))")
    }
}
