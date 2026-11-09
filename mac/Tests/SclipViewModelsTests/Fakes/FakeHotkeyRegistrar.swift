import SclipCore

final class FakeHotkeyRegistrar: HotkeyRegistrar {
    var allowed: Set<HotkeyCombo>
    var alwaysFail = false
    private(set) var active: HotkeyCombo?
    private(set) var registerAttempts: [HotkeyCombo] = []
    private(set) var unregisterCount = 0
    private(set) var suspendCount = 0
    private(set) var resumeCount = 0

    init(allowed: Set<HotkeyCombo> = Set(HotkeyCombo.macDefaults)) {
        self.allowed = allowed
    }

    func register(_ combo: HotkeyCombo) -> Bool {
        registerAttempts.append(combo)
        guard !alwaysFail, allowed.contains(combo) else { return false }
        active = combo
        return true
    }

    func unregister() {
        unregisterCount += 1
        active = nil
    }

    func suspend() {
        suspendCount += 1
    }

    func resume() {
        resumeCount += 1
    }
}
