import Foundation
import SclipPlatform
import XCTest

@MainActor
final class SingleInstanceTests: XCTestCase {
    func testSecondClaimReturnsFalseAndNotifiesFirst() {
        let bundleID = "com.erenkirkil.sclip.test.\(UUID().uuidString)"
        let notified = expectation(description: "First instance notified on second claim")
        var secondCallbackInvoked = false

        let firstClaim = SingleInstance.claim(bundleID: bundleID) {
            notified.fulfill()
        }
        defer { SingleInstance.release(bundleID: bundleID) }

        XCTAssertTrue(firstClaim)

        let secondClaim = SingleInstance.claim(bundleID: bundleID) {
            secondCallbackInvoked = true
        }
        XCTAssertFalse(secondClaim)

        wait(for: [notified], timeout: 2.0)
        XCTAssertFalse(secondCallbackInvoked)
    }
}
