import SclipCore
import SclipViewModels
import XCTest

@MainActor
final class SettingsViewModelTests: XCTestCase {
    func testDefaults() {
        let store = FakeSettingsStore()
        let hotkeys = FakeHotkeyRegistrar()
        let vm = SettingsViewModel(store: store, hotkeys: hotkeys)

        XCTAssertEqual(vm.themeMode, .system)
        XCTAssertEqual(vm.maxItems, 30)
        XCTAssertTrue(vm.sensitiveFilter)
        XCTAssertFalse(vm.clearOnScreenLock)
        XCTAssertTrue(vm.autoHideOnBlur)
        XCTAssertFalse(vm.alwaysOnTopDefault)
        XCTAssertEqual(vm.pollingIntervalMs, 250)
        XCTAssertFalse(vm.clearOnStartup)
        XCTAssertFalse(vm.alwaysPastePlainText)
        XCTAssertNil(vm.registeredHotkey)

        vm.registerInitialHotkey()
        XCTAssertEqual(vm.registeredHotkey, HotkeyCombo.macDefaults.first)
        XCTAssertTrue(store.writes.isEmpty)
    }

    func testOutOfRangeMaxItemsFallsBackTo30() {
        let store = FakeSettingsStore(initial: [
            .maxItems: .int(42),
            .pollingIntervalMs: .int(999),
            .themeMode: .string("neon"),
            .sensitiveFilter: .int(1),
        ])
        let hotkeys = FakeHotkeyRegistrar()
        let vm = SettingsViewModel(store: store, hotkeys: hotkeys)

        XCTAssertEqual(vm.maxItems, 30)
        XCTAssertEqual(vm.pollingIntervalMs, 250)
        XCTAssertEqual(vm.themeMode, .system)
        XCTAssertTrue(vm.sensitiveFilter)
    }

    func testCorruptHotkeyStringFallsBackToDefault() {
        for corrupt in ["", "command:9", "command+shift:notanint", "unknown+shift:9", "command+shift"] {
            XCTAssertNil(HotkeyCombo(storageString: corrupt), "Should reject \(corrupt)")
        }

        let store = FakeSettingsStore(initial: [.toggleHotkey: .string("corrupt_combo")])
        let hotkeys = FakeHotkeyRegistrar()
        let vm = SettingsViewModel(store: store, hotkeys: hotkeys)
        vm.registerInitialHotkey()

        XCTAssertEqual(vm.registeredHotkey, HotkeyCombo.macDefaults[0])
    }

    func testFallbackComboIsWhatSettingsShows() {
        let preferred = HotkeyCombo(modifiers: [.command, .option, .shift], keyCode: 9)
        let store = FakeSettingsStore(initial: [.toggleHotkey: .string(preferred.storageString)])
        // Preferred and first default fail; second default (Cmd+Opt+V) succeeds.
        let secondDefault = HotkeyCombo.macDefaults[1]
        let hotkeys = FakeHotkeyRegistrar(allowed: [secondDefault])
        let vm = SettingsViewModel(store: store, hotkeys: hotkeys)

        vm.registerInitialHotkey()

        XCTAssertEqual(vm.registeredHotkey, secondDefault)
        XCTAssertEqual(
            hotkeys.registerAttempts,
            [preferred, HotkeyCombo.macDefaults[0], secondDefault]
        )
    }

    func testFailedChangeRestoresPrevious() {
        let store = FakeSettingsStore()
        let initial = HotkeyCombo.macDefaults[0]
        let validCandidate = HotkeyCombo(modifiers: [.command, .control, .shift], keyCode: 8)
        let invalidCandidate = HotkeyCombo(modifiers: [.command], keyCode: 8)
        let hotkeys = FakeHotkeyRegistrar(allowed: [initial])
        let vm = SettingsViewModel(store: store, hotkeys: hotkeys)
        vm.registerInitialHotkey()
        XCTAssertEqual(vm.registeredHotkey, initial)

        // Single modifier is invalid (< 2 modifiers): rejected without touching registrar.
        XCTAssertFalse(invalidCandidate.isValid)
        XCTAssertFalse(vm.changeHotkey(invalidCandidate))
        XCTAssertEqual(vm.registeredHotkey, initial)
        XCTAssertEqual(hotkeys.active, initial)

        // Valid combo rejected by OS: restores previous combo and does not persist failure.
        XCTAssertTrue(validCandidate.isValid)
        XCTAssertFalse(vm.changeHotkey(validCandidate))
        XCTAssertEqual(vm.registeredHotkey, initial)
        XCTAssertEqual(hotkeys.active, initial)
        XCTAssertTrue(store.writes.isEmpty)
    }

    func testRecordingSuspendsAndResumes() {
        let store = FakeSettingsStore()
        let hotkeys = FakeHotkeyRegistrar()
        let vm = SettingsViewModel(store: store, hotkeys: hotkeys)

        vm.beginRecording()
        XCTAssertEqual(hotkeys.suspendCount, 1)
        XCTAssertEqual(hotkeys.resumeCount, 0)

        vm.endRecording()
        XCTAssertEqual(hotkeys.suspendCount, 1)
        XCTAssertEqual(hotkeys.resumeCount, 1)
    }

    func testResetFailureReported() {
        let custom = HotkeyCombo(modifiers: [.command, .option, .control], keyCode: 9)
        let store = FakeSettingsStore()
        let hotkeys = FakeHotkeyRegistrar(allowed: Set(HotkeyCombo.macDefaults).union([custom]))
        let vm = SettingsViewModel(store: store, hotkeys: hotkeys)
        vm.registerInitialHotkey()

        XCTAssertTrue(vm.changeHotkey(custom))
        vm.maxItems = 100
        vm.alwaysPastePlainText = true

        hotkeys.alwaysFail = true
        let ok = vm.resetToDefaults()

        XCTAssertFalse(ok)
        XCTAssertNil(vm.registeredHotkey)
        XCTAssertEqual(vm.maxItems, 30)
        XCTAssertFalse(vm.alwaysPastePlainText)
        XCTAssertEqual(store.removeAllCount, 1)
    }

    func testWritesOnlySettingKeys() {
        let custom = HotkeyCombo(modifiers: [.command, .option], keyCode: 9)
        let store = FakeSettingsStore()
        let hotkeys = FakeHotkeyRegistrar(allowed: [custom])
        let vm = SettingsViewModel(store: store, hotkeys: hotkeys)

        XCTAssertTrue(vm.changeHotkey(custom))
        vm.themeMode = .dark
        vm.maxItems = 50
        vm.sensitiveFilter = false
        vm.clearOnScreenLock = true
        vm.autoHideOnBlur = false
        vm.alwaysOnTopDefault = true
        vm.pollingIntervalMs = 500
        vm.clearOnStartup = true
        vm.alwaysPastePlainText = true

        let allowedKeys = Set(SettingKey.allCases.map(\.rawValue))
        XCTAssertFalse(store.writtenRawKeys.isEmpty)
        for key in store.writtenRawKeys {
            XCTAssertTrue(allowedKeys.contains(key), "Unexpected key written: \(key)")
            XCTAssertTrue(key.hasPrefix("sclip.settings."))
        }
    }
}
