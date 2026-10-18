import XCTest
@testable import SclipPlatform

final class ModuleTests: XCTestCase {
    func testModuleVersion() {
        XCTAssertEqual(SclipPlatformModule.version, "2.0.0")
    }
}
