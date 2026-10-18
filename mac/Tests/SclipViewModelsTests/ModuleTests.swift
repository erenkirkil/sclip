import XCTest
@testable import SclipViewModels

final class ModuleTests: XCTestCase {
    func testModuleVersion() {
        XCTAssertEqual(SclipViewModelsModule.version, "2.0.0")
    }
}
