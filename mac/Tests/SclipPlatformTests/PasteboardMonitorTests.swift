import Foundation
import SclipPlatform
import XCTest

@MainActor
final class PasteboardMonitorTests: XCTestCase {
    func testMonitorKeepsTickingAfterSlowRead() {
        var tickCount = 0
        var didSlowSleep = false
        let finished = expectation(description: "Monitor ticks at least 3 times after slow read")

        let monitor = PasteboardMonitor(interval: 0.03) {
            tickCount += 1
            if !didSlowSleep {
                didSlowSleep = true
                Thread.sleep(forTimeInterval: 0.3)
            }
            if tickCount >= 3 {
                finished.fulfill()
            }
        }

        monitor.start()
        wait(for: [finished], timeout: 2.0)
        monitor.stop()
        XCTAssertGreaterThanOrEqual(tickCount, 3)
    }

    func testIntervalChangeRestartsTimer() {
        var tickCount = 0
        let exp = expectation(description: "Monitor ticks swiftly after interval lowered")

        let monitor = PasteboardMonitor(interval: 10.0) {
            tickCount += 1
            if tickCount >= 2 {
                exp.fulfill()
            }
        }

        monitor.start()
        monitor.interval = 0.02
        wait(for: [exp], timeout: 1.0)
        monitor.stop()
        XCTAssertGreaterThanOrEqual(tickCount, 2)
    }
}
