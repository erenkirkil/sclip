import XCTest
@testable import SclipCore

final class ModuleTests: XCTestCase {
    func testModuleVersion() {
        XCTAssertEqual(SclipCoreModule.version, "2.0.0")
    }
}
