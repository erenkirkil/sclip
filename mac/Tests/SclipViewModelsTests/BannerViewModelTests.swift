import SclipViewModels
import XCTest

@MainActor
final class BannerViewModelTests: XCTestCase {
    func testHotkeyBannerClearsOnSuccessfulRegister() {
        let vm = BannerViewModel()
        XCTAssertTrue(vm.banners.isEmpty)

        vm.setHotkeyRegistered(false)
        XCTAssertEqual(vm.banners, [.hotkey])

        vm.setHotkeyRegistered(true)
        XCTAssertTrue(vm.banners.isEmpty)
    }

    func testLockClearedOnlyWhenHadEntries() {
        let vm = BannerViewModel()

        vm.lockCleared(hadEntries: false)
        XCTAssertTrue(vm.banners.isEmpty)

        vm.lockCleared(hadEntries: true)
        XCTAssertEqual(vm.banners, [.lockCleared])

        vm.dismissLockCleared()
        XCTAssertTrue(vm.banners.isEmpty)
    }

    func testAccessibilityBannerOrder() {
        let vm = BannerViewModel()

        // Trigger in reverse order; published array must preserve canonical order:
        // [.accessibility, .hotkey, .lockCleared]
        vm.lockCleared(hadEntries: true)
        vm.setHotkeyRegistered(false)
        vm.setAccessibilityTrusted(false)

        XCTAssertEqual(vm.banners, [.accessibility, .hotkey, .lockCleared])

        vm.setAccessibilityTrusted(true)
        XCTAssertEqual(vm.banners, [.hotkey, .lockCleared])
    }
}
