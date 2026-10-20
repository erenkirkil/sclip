import XCTest

@testable import SclipCore

final class SearchTrimTests: XCTestCase {
    func testTrimUsesDartTrimSet() {
        XCTAssertEqual(SearchNormalizer.trimmedForDisplay(" \t\u{85}\u{3000}Elma  Armut\u{FEFF}\n"), "Elma  Armut")
    }

    func testTrimOfWhitespaceOnlyIsEmpty() {
        XCTAssertEqual(SearchNormalizer.trimmedForDisplay(" \u{A0}\u{2028} "), "")
    }

    func testTrimKeepsInnerWhitespaceAndCase() {
        XCTAssertEqual(SearchNormalizer.trimmedForDisplay("İ  a"), "İ  a")
    }
}
