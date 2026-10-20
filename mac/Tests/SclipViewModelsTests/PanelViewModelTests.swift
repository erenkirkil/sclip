import Combine
import Foundation
import SclipCore
import XCTest

@testable import SclipViewModels

@MainActor
final class PanelViewModelTests: XCTestCase {
    private let ids = EntryIDGenerator()

    /// Bir testin tüm sahte bağımlılıkları ve test edilen model.
    @MainActor
    private struct Rig {
        let log = CallLog()
        let window: FakeWindow
        let paster: FakePaster
        let refresh: FakeRefresh
        let sink: FakeSink
        let clock = FakeClock()
        let vm: PanelViewModel

        init(pinned: Bool = false, autoHideOnBlur: Bool = true, trayBlurWindow: TimeInterval = 0.2) {
            window = FakeWindow(log: log)
            paster = FakePaster(log: log)
            refresh = FakeRefresh(log: log)
            sink = FakeSink(log: log)
            vm = PanelViewModel(
                window: window, paster: paster, sink: sink, refresh: refresh, clock: clock,
                pinned: pinned, autoHideOnBlur: autoHideOnBlur, trayBlurWindow: trayBlurWindow)
        }

        /// `window.hide()` içinde eşzamanlı `blur()` tetikler (macOS resign-key).
        func reentrantBlur() { window.onResignKeyDuringHide = { [vm] in vm.blur() } }

        /// Gizliden gösterime geçirir ve günlüğü kullanıcıya bırakır.
        func present() {
            vm.toggle(.hotkey)
            precondition(vm.visibility == .shown)
        }
    }

    private func entry(_ payload: Payload) -> Entry {
        Entry(id: ids.next(), createdAt: Date(timeIntervalSince1970: 0), payload: payload, isSensitive: false)
    }

    private func text() -> Entry { entry(.text("merhaba")) }

    private func rich() -> Entry { entry(.richText(plain: "a", html: "<b>a</b>", rtf: nil)) }

    private func image() -> ImageItem { ImageItem(data: Data([1, 2, 3]), format: .png) }

    // MARK: - Aç / kapat (B-7.1.2 – B-7.1.4, E1)

    func testRapidTogglesNeverDoubleShow() {
        let rig = Rig()
        for i in 1...10 {
            rig.vm.toggle(.hotkey)
            let delta = rig.window.showCount - rig.window.hideCount
            XCTAssertTrue(delta == 0 || delta == 1, "toggle \(i): delta \(delta)")
            XCTAssertEqual(rig.vm.visibility, i % 2 == 1 ? .shown : .hidden)
        }
        XCTAssertEqual(rig.window.showCount, 5)
        XCTAssertEqual(rig.window.hideCount, 5)
    }

    func testToggleDuringPastingIgnored() {
        let rig = Rig()
        rig.present()
        rig.vm.paste(text(), imageIndex: nil)
        XCTAssertEqual(rig.vm.visibility, .pasting)
        let shows = rig.window.showCount
        let hides = rig.window.hideCount
        rig.vm.toggle(.hotkey)
        rig.vm.toggle(.tray)
        rig.vm.toggle(.secondInstance)
        XCTAssertEqual(rig.vm.visibility, .pasting)
        XCTAssertEqual(rig.window.showCount, shows)
        XCTAssertEqual(rig.window.hideCount, hides)
    }

    func testToggleShownKeyOrPinnedHides() {
        let rig = Rig()
        rig.present()
        rig.vm.toggle(.hotkey)
        XCTAssertEqual(rig.vm.visibility, .hidden)

        let pinned = Rig(pinned: true)
        pinned.present()
        pinned.window.isKey = false
        pinned.vm.toggle(.hotkey)
        XCTAssertEqual(pinned.vm.visibility, .hidden)
    }

    func testToggleShownNotKeyNotPinnedBringsToFront() {
        let rig = Rig(autoHideOnBlur: false)
        rig.window.becomesKeyOnShow = false
        rig.present()
        XCTAssertFalse(rig.window.isKey)
        rig.vm.toggle(.hotkey)
        XCTAssertEqual(rig.vm.visibility, .shown)
        XCTAssertEqual(rig.window.showCount, 2)
        XCTAssertEqual(rig.window.hideCount, 0)
        XCTAssertEqual(rig.refresh.count, 2)
        XCTAssertEqual(rig.paster.captureCount, 2)  // hedef yeniden yakalanır (Flutter else-dalı)
    }

    // MARK: - Gösterim sırası ve odak (B-8.8.3, E6, E17)

    func testShowRefreshesBeforeShowing() {
        let rig = Rig()
        rig.present()
        XCTAssertEqual(
            rig.log.entries, ["refresh", "capture", "show", "focus(firstRow)"])
    }

    func testShowFocusesFirstRowByDefault() {
        let rig = Rig()
        rig.present()
        XCTAssertEqual(rig.window.focusTargets, [.firstRow])
    }

    func testShowFocusesSearchWhenOpen() {
        let rig = Rig()
        rig.vm.searchOpen = { true }
        rig.present()
        XCTAssertEqual(rig.window.focusTargets, [.searchField])
    }

    func testShowFocusesSettingsWhenOnSettingsPage() {
        let rig = Rig()
        rig.vm.searchOpen = { true }
        rig.vm.openSettings()
        rig.present()
        XCTAssertEqual(rig.window.focusTargets, [.settings])
    }

    // MARK: - Blur (B-7.1.8, B-7.1.9, E7, E9)

    func testBlurHidesWhenShownUnpinnedAutoHide() {
        let rig = Rig()
        rig.present()
        rig.vm.blur()
        XCTAssertEqual(rig.vm.visibility, .hidden)
        XCTAssertEqual(rig.window.hideCount, 1)
    }

    func testPinnedBlurDoesNotHide() {
        let rig = Rig(pinned: true)
        rig.present()
        rig.vm.blur()
        XCTAssertEqual(rig.vm.visibility, .shown)
        XCTAssertEqual(rig.window.hideCount, 0)
    }

    func testBlurIgnoredWhenAutoHideOffOrNotShown() {
        let rig = Rig(autoHideOnBlur: false)
        rig.present()
        rig.vm.blur()
        XCTAssertEqual(rig.vm.visibility, .shown)
        rig.vm.autoHideOnBlur = true
        rig.vm.requestHide()
        rig.vm.blur()
        XCTAssertEqual(rig.window.hideCount, 1)
    }

    func testBlurDuringPastingIgnored() {
        let rig = Rig()
        rig.present()
        rig.vm.paste(text(), imageIndex: nil)
        let hides = rig.window.hideCount
        rig.vm.blur()
        XCTAssertEqual(rig.vm.visibility, .pasting)
        XCTAssertEqual(rig.window.hideCount, hides)
    }

    func testTrayToggleRightAfterBlurHideDoesNotReopen() {
        let rig = Rig()
        rig.present()
        rig.vm.blur()
        rig.clock.advance(0.1)
        rig.vm.toggle(.tray)
        XCTAssertEqual(rig.vm.visibility, .hidden)
        XCTAssertEqual(rig.window.showCount, 1)
    }

    func testTrayToggleAfterWindowReopens() {
        let rig = Rig()
        rig.present()
        rig.vm.blur()
        rig.clock.advance(0.3)
        rig.vm.toggle(.tray)
        XCTAssertEqual(rig.vm.visibility, .shown)
        XCTAssertEqual(rig.window.showCount, 2)
    }

    func testTrayBlurWindowBoundaryIsInclusive() {
        // 0,25 ikilide tam gösterilir; kayan nokta payı yok.
        let rig = Rig(trayBlurWindow: 0.25)
        rig.present()
        rig.vm.blur()
        rig.clock.advance(0.25)
        rig.vm.toggle(.tray)
        XCTAssertEqual(rig.vm.visibility, .hidden, "tam sınırda yok sayılmalı (≤)")
        rig.clock.advance(0.0001)
        rig.vm.toggle(.tray)
        XCTAssertEqual(rig.vm.visibility, .shown, "sınırı aşınca açılmalı")
    }

    func testHotkeyAndSecondInstanceNotSuppressedAfterBlurHide() {
        let rig = Rig()
        rig.present()
        rig.vm.blur()
        rig.vm.toggle(.hotkey)
        XCTAssertEqual(rig.vm.visibility, .shown)
        rig.vm.blur()
        rig.vm.toggle(.secondInstance)
        XCTAssertEqual(rig.vm.visibility, .shown)
    }

    func testTrayToggleAfterNonBlurHideIsNotSuppressed() {
        let rig = Rig()
        rig.present()
        rig.vm.blur()
        rig.vm.toggle(.hotkey)  // yeniden açar, damga sıfırlanır
        rig.vm.toggle(.hotkey)  // blur dışı gizleme
        rig.vm.toggle(.tray)
        XCTAssertEqual(rig.vm.visibility, .shown)
    }

    // MARK: - Esc katmanları (B-6.2.1, E16)

    func testEscapeLayers() {
        let rig = Rig()
        var searchIsOpen = true
        var closeSearchCalls = 0
        rig.vm.searchOpen = { searchIsOpen }
        rig.vm.closeSearch = {
            closeSearchCalls += 1
            searchIsOpen = false
        }
        rig.present()
        rig.vm.openSettings()
        rig.vm.setDialogOpen(true)

        rig.vm.escape()  // 1: diyalog
        XCTAssertFalse(rig.vm.dialogOpen)
        XCTAssertEqual(rig.vm.page, .settings)
        XCTAssertEqual(rig.vm.visibility, .shown)

        rig.vm.escape()  // 2: ayarlar
        XCTAssertEqual(rig.vm.page, .history)
        XCTAssertEqual(closeSearchCalls, 0)
        XCTAssertEqual(rig.vm.visibility, .shown)

        rig.vm.escape()  // 3: arama
        XCTAssertEqual(closeSearchCalls, 1)
        XCTAssertEqual(rig.vm.visibility, .shown)

        rig.vm.escape()  // 4: gizle
        XCTAssertEqual(rig.vm.visibility, .hidden)
        XCTAssertEqual(rig.window.hideCount, 1)
    }

    func testEscapeIgnoredWhenNotShown() {
        let rig = Rig()
        rig.vm.escape()
        XCTAssertEqual(rig.window.hideCount, 0)
        rig.present()
        rig.vm.paste(text(), imageIndex: nil)
        let hides = rig.window.hideCount
        rig.vm.escape()
        XCTAssertEqual(rig.vm.visibility, .pasting)
        XCTAssertEqual(rig.window.hideCount, hides)
    }

    // MARK: - paste (B-7.1.5, B-7.1.6)

    func testPasteSequenceOrder() {
        let rig = Rig()
        var calls: [String] = []
        rig.vm.onOwnWrite = { receipt in
            calls.append("ownWrite(\(receipt.change))")
            rig.log.add("ownWrite")
        }
        rig.vm.onTouch = { _ in rig.log.add("touch") }
        rig.present()
        let item = text()
        rig.vm.paste(item, imageIndex: nil)
        XCTAssertEqual(
            Array(rig.log.entries.dropFirst(4)),
            ["write", "ownWrite", "touch", "hide", "pasteToTarget"])
        XCTAssertEqual(calls, ["ownWrite(42)"])
        XCTAssertEqual(rig.vm.visibility, .pasting)
    }

    func testPasteTouchesWrittenEntry() {
        let rig = Rig()
        var touched: [EntryID] = []
        rig.vm.onTouch = { touched.append($0) }
        rig.present()
        let item = text()
        rig.vm.paste(item, imageIndex: nil)
        XCTAssertEqual(touched, [item.id])
    }

    func testPasteAbortedReturnsToHidden() {
        let rig = Rig()
        rig.present()
        rig.vm.paste(text(), imageIndex: nil)
        rig.paster.complete(.aborted)
        XCTAssertEqual(rig.vm.visibility, .hidden)
        XCTAssertEqual(rig.window.showCount, 1)
    }

    func testPastePastedReturnsToHidden() {
        let rig = Rig()
        rig.present()
        rig.vm.paste(text(), imageIndex: nil)
        rig.paster.complete(.pasted)
        XCTAssertEqual(rig.vm.visibility, .hidden)
        XCTAssertEqual(rig.window.showCount, 1)
        rig.vm.toggle(.hotkey)
        XCTAssertEqual(rig.vm.visibility, .shown)
    }

    func testWriteFailureKeepsPanelShown() {
        let rig = Rig()
        rig.sink.failure = FakeSink.WriteError()
        var ownWrites = 0
        var touches = 0
        rig.vm.onOwnWrite = { _ in ownWrites += 1 }
        rig.vm.onTouch = { _ in touches += 1 }
        rig.present()
        rig.vm.paste(text(), imageIndex: nil)
        XCTAssertEqual(rig.vm.visibility, .shown)
        XCTAssertEqual(rig.window.hideCount, 0)
        XCTAssertEqual(rig.paster.pasteCount, 0)
        XCTAssertEqual(ownWrites, 0)
        XCTAssertEqual(touches, 0)
    }

    func testPasteIgnoredWhenHiddenOrPasting() {
        let rig = Rig()
        rig.vm.paste(text(), imageIndex: nil)
        XCTAssertTrue(rig.sink.calls.isEmpty)
        XCTAssertEqual(rig.vm.visibility, .hidden)

        rig.present()
        rig.vm.paste(text(), imageIndex: nil)
        rig.vm.paste(text(), imageIndex: nil)
        XCTAssertEqual(rig.sink.calls.count, 1)
        XCTAssertEqual(rig.paster.pasteCount, 1)
    }

    func testRichTextPlainOnlyFollowsSetting() {
        let rig = Rig()
        rig.present()
        rig.vm.paste(rich(), imageIndex: nil)
        XCTAssertEqual(rig.sink.calls.last?.plainOnly, false)
        rig.paster.complete(.pasted)

        rig.vm.alwaysPastePlainText = true
        rig.present()
        rig.vm.paste(rich(), imageIndex: nil)
        XCTAssertEqual(rig.sink.calls.last?.plainOnly, true)
    }

    func testSettingDoesNotAffectSvgImageFilesPdf() {
        let rig = Rig()
        rig.vm.alwaysPastePlainText = true
        let others: [Payload] = [
            .svg("<svg/>"), .image(image()), .imageSet([image(), image()]),
            .files([URL(fileURLWithPath: "/tmp/a")]), .pdf(Data([1])), .text("t"),
            .url(original: "https://a.b", uri: "https://a.b", display: "a.b"),
            .color(original: "#fff", normalized: "#ffffff", argb: 0xFFFF_FFFF),
        ]
        for payload in others {
            rig.present()
            rig.vm.paste(entry(payload), imageIndex: nil)
            XCTAssertEqual(rig.sink.calls.last?.plainOnly, false, "\(payload.kind)")
            rig.paster.complete(.pasted)
        }
        XCTAssertEqual(rig.sink.calls.count, others.count)
    }

    func testImageIndexForwardedOnlyForImageSet() {
        let rig = Rig()
        rig.present()
        rig.vm.paste(entry(.imageSet([image(), image()])), imageIndex: 1)
        XCTAssertEqual(rig.sink.calls.last?.imageIndex, 1)
        rig.paster.complete(.pasted)

        rig.present()
        rig.vm.paste(text(), imageIndex: 1)
        XCTAssertNil(rig.sink.calls.last?.imageIndex)
    }

    // MARK: - requestHide / onHidden / pin

    func testRequestHideFromShown() {
        let rig = Rig()
        rig.present()
        rig.vm.requestHide()
        XCTAssertEqual(rig.vm.visibility, .hidden)
        XCTAssertEqual(rig.window.hideCount, 1)
    }

    func testRequestHideDuringPastingIgnored() {
        let rig = Rig()
        rig.present()
        rig.vm.paste(text(), imageIndex: nil)
        let hides = rig.window.hideCount
        rig.vm.requestHide()
        XCTAssertEqual(rig.vm.visibility, .pasting)
        XCTAssertEqual(rig.window.hideCount, hides)
    }

    func testRequestHideWhileHiddenIgnored() {
        let rig = Rig()
        rig.vm.requestHide()
        XCTAssertEqual(rig.window.hideCount, 0)
    }

    func testHideClearsQueryViaOnHidden() {
        let rig = Rig()
        var hidden = 0
        rig.vm.onHidden = { hidden += 1 }

        rig.present()
        rig.vm.toggle(.hotkey)  // geçiş
        XCTAssertEqual(hidden, 1)

        rig.present()
        rig.vm.blur()  // blur
        XCTAssertEqual(hidden, 2)

        rig.present()
        rig.vm.escape()  // Esc
        XCTAssertEqual(hidden, 3)

        rig.present()
        rig.vm.requestHide()  // kapat düğmesi
        XCTAssertEqual(hidden, 4)

        rig.present()
        rig.vm.paste(text(), imageIndex: nil)  // yapıştırma gizlemesi (Flutter: yazımda temizler)
        XCTAssertEqual(hidden, 5)
        rig.paster.complete(.pasted)
        XCTAssertEqual(hidden, 5, "pasting sonu ikinci kez tetiklemez")
    }

    func testOnHiddenNotFiredWhenWriteFails() {
        let rig = Rig()
        rig.sink.failure = FakeSink.WriteError()
        var hidden = 0
        rig.vm.onHidden = { hidden += 1 }
        rig.present()
        rig.vm.paste(text(), imageIndex: nil)
        XCTAssertEqual(hidden, 0)
    }

    func testSetPinnedWhileShownDoesNotHide() {
        let rig = Rig()
        rig.present()
        rig.vm.setPinned(true)
        XCTAssertTrue(rig.vm.pinned)
        XCTAssertEqual(rig.vm.visibility, .shown)
        XCTAssertEqual(rig.window.hideCount, 0)
        rig.vm.setPinned(false)
        XCTAssertFalse(rig.vm.pinned)
    }

    func testSettingsPageOpenClose() {
        let rig = Rig()
        XCTAssertEqual(rig.vm.page, .history)
        rig.vm.openSettings()
        XCTAssertEqual(rig.vm.page, .settings)
        rig.vm.closeSettings()
        XCTAssertEqual(rig.vm.page, .history)
    }

    // MARK: - Yeniden giriş (eşzamanlı resign-key), bayat tamamlama

    private func assertSingleHide(_ rig: Rig, _ hidden: Int, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(rig.window.hideCount, 1, "tek window.hide()", file: file, line: line)
        XCTAssertEqual(hidden, 1, "tek onHidden", file: file, line: line)
        XCTAssertEqual(rig.vm.visibility, .hidden, file: file, line: line)
    }

    func testReentrantResignKeyOnHotkeyHideHidesOnce() {
        let rig = Rig()
        var hidden = 0
        rig.vm.onHidden = { hidden += 1 }
        rig.reentrantBlur()
        rig.present()
        rig.vm.toggle(.hotkey)
        assertSingleHide(rig, hidden)
    }

    func testReentrantResignKeyOnEscapeHideHidesOnce() {
        let rig = Rig()
        var hidden = 0
        rig.vm.onHidden = { hidden += 1 }
        rig.reentrantBlur()
        rig.present()
        rig.vm.escape()
        assertSingleHide(rig, hidden)
    }

    func testReentrantResignKeyOnRequestHideHidesOnce() {
        let rig = Rig()
        var hidden = 0
        rig.vm.onHidden = { hidden += 1 }
        rig.reentrantBlur()
        rig.present()
        rig.vm.requestHide()
        assertSingleHide(rig, hidden)
    }

    func testReentrantResignKeyOnPasteGoesStraightToPasting() {
        let rig = Rig()
        var hidden = 0
        rig.vm.onHidden = { hidden += 1 }
        rig.reentrantBlur()
        rig.present()
        var seen: [Visibility] = []
        let sub = rig.vm.$visibility.sink { seen.append($0) }
        rig.vm.paste(text(), imageIndex: nil)
        rig.paster.complete(.pasted)
        sub.cancel()
        XCTAssertEqual(seen, [.shown, .pasting, .hidden])
        assertSingleHide(rig, hidden)
    }

    func testReentrantResignKeyDoesNotStampTrayBlurWindow() {
        let rig = Rig()
        rig.reentrantBlur()
        rig.present()
        rig.vm.toggle(.hotkey)  // blur dışı gizleme; iç içe blur() yok sayılır
        rig.vm.toggle(.tray)
        XCTAssertEqual(rig.vm.visibility, .shown)
    }

    func testRapidTogglesWithReentrantWindowKeepParity() {
        let rig = Rig()
        rig.reentrantBlur()
        for i in 1...10 {
            rig.vm.toggle(.hotkey)
            let delta = rig.window.showCount - rig.window.hideCount
            XCTAssertTrue(delta == 0 || delta == 1, "toggle \(i): delta \(delta)")
            XCTAssertEqual(rig.vm.visibility, i % 2 == 1 ? .shown : .hidden)
        }
        XCTAssertEqual(rig.window.hideCount, 5)
    }

    func testStaleCompletionDoesNotEndNewerPaste() {
        let rig = Rig()
        var hidden = 0
        rig.vm.onHidden = { hidden += 1 }
        rig.present()
        rig.vm.paste(text(), imageIndex: nil)  // yapıştırma 1
        rig.paster.complete(.pasted)
        rig.present()
        rig.vm.paste(text(), imageIndex: nil)  // yapıştırma 2 sürüyor
        XCTAssertEqual(rig.vm.visibility, .pasting)
        rig.paster.completeAgain(at: 0, .pasted)  // bayat/yinelenen
        XCTAssertEqual(rig.vm.visibility, .pasting, "bayat tamamlama yok sayılmalı")
        rig.paster.complete(.pasted)
        XCTAssertEqual(rig.vm.visibility, .hidden)
        XCTAssertEqual(hidden, 2)
    }

    func testSynchronousCompletionEndsHiddenWithSingleOnHidden() {
        let rig = Rig()
        var hidden = 0
        rig.vm.onHidden = { hidden += 1 }
        rig.paster.immediateOutcome = .aborted  // B-7.1.6 (c): izin yok, hemen döner
        rig.present()
        rig.vm.paste(text(), imageIndex: nil)
        XCTAssertEqual(rig.vm.visibility, .hidden)
        XCTAssertEqual(hidden, 1)
        XCTAssertEqual(rig.window.hideCount, 1)
    }
}
