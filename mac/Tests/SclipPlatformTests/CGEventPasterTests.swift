import CoreGraphics
import Foundation
import SclipCore
import SclipPlatform
import XCTest

private final class FakeKeyState: KeyState {
    var remainingDownPolls: Int
    private(set) var pollCount = 0

    init(remainingDownPolls: Int = 0) {
        self.remainingDownPolls = remainingDownPolls
    }

    func isReturnDown() -> Bool {
        pollCount += 1
        if remainingDownPolls > 0 {
            remainingDownPolls -= 1
            return true
        }
        return false
    }
}

private final class FakeCGEventPoster: CGEventPoster {
    struct PostedEvent {
        let keyCode: CGKeyCode
        let isKeyDown: Bool
        let flags: CGEventFlags
    }

    private(set) var events: [PostedEvent] = []

    func post(_ event: CGEvent) {
        let code = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let isDown = event.type == .keyDown
        events.append(PostedEvent(keyCode: code, isKeyDown: isDown, flags: event.flags))
    }
}

@MainActor
final class CGEventPasterTests: XCTestCase {
    func testAbortsWhenFrontmostChanged() {
        var currentPID: pid_t? = 100
        let poster = FakeCGEventPoster()
        let paster = CGEventPaster(
            delayAfterOrderOut: 0.005,
            enterReleaseTimeout: 0.1,
            frontmostPID: { currentPID },
            isTrusted: { true },
            keyState: FakeKeyState(),
            poster: poster
        )

        paster.captureTarget()
        currentPID = 200  // User switched app before Cmd+V landed

        let exp = expectation(description: "Paste aborts on PID mismatch")
        var outcome: PasteOutcome?
        paster.pasteToTarget { result in
            outcome = result
            exp.fulfill()
        }

        wait(for: [exp], timeout: 1.0)
        XCTAssertEqual(outcome, .aborted)
        XCTAssertTrue(poster.events.isEmpty)
    }

    func testWaitsForReturnReleaseUpToTimeout() {
        let keyState = FakeKeyState(remainingDownPolls: 3)
        let poster = FakeCGEventPoster()
        let paster = CGEventPaster(
            delayAfterOrderOut: 0.005,
            enterReleaseTimeout: 0.5,
            frontmostPID: { 42 },
            isTrusted: { true },
            keyState: keyState,
            poster: poster
        )

        paster.captureTarget()
        let start = Date()
        let exp = expectation(description: "Waits for 3 return-down polls before pasting")
        var outcome: PasteOutcome?
        paster.pasteToTarget { result in
            outcome = result
            exp.fulfill()
        }

        wait(for: [exp], timeout: 1.0)
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertEqual(outcome, .pasted)
        XCTAssertGreaterThanOrEqual(elapsed, 0.03)
        XCTAssertEqual(keyState.pollCount, 4)
        XCTAssertEqual(poster.events.count, 2)
    }

    func testTargetIsConsumedOnce() {
        let poster = FakeCGEventPoster()
        let paster = CGEventPaster(
            delayAfterOrderOut: 0.001,
            enterReleaseTimeout: 0.1,
            frontmostPID: { 77 },
            isTrusted: { true },
            keyState: FakeKeyState(),
            poster: poster
        )

        paster.captureTarget()

        let exp1 = expectation(description: "First paste succeeds")
        var firstOutcome: PasteOutcome?
        paster.pasteToTarget { result in
            firstOutcome = result
            exp1.fulfill()
        }
        wait(for: [exp1], timeout: 1.0)
        XCTAssertEqual(firstOutcome, .pasted)
        XCTAssertEqual(poster.events.count, 2)

        // Second paste without captureTarget() must abort immediately.
        let exp2 = expectation(description: "Second paste without capture aborts")
        var secondOutcome: PasteOutcome?
        paster.pasteToTarget { result in
            secondOutcome = result
            exp2.fulfill()
        }
        wait(for: [exp2], timeout: 1.0)
        XCTAssertEqual(secondOutcome, .aborted)
        XCTAssertEqual(poster.events.count, 2)
    }

    func testEventFlagsAreCommandOnly() {
        let poster = FakeCGEventPoster()
        let paster = CGEventPaster(
            delayAfterOrderOut: 0.001,
            enterReleaseTimeout: 0.1,
            frontmostPID: { 99 },
            isTrusted: { true },
            keyState: FakeKeyState(),
            poster: poster
        )

        paster.captureTarget()
        let exp = expectation(description: "Posts Cmd+V")
        paster.pasteToTarget { _ in exp.fulfill() }
        wait(for: [exp], timeout: 1.0)

        XCTAssertEqual(poster.events.count, 2)
        XCTAssertEqual(poster.events[0].keyCode, 0x09)
        XCTAssertTrue(poster.events[0].isKeyDown)
        XCTAssertEqual(poster.events[0].flags, .maskCommand)

        XCTAssertEqual(poster.events[1].keyCode, 0x09)
        XCTAssertFalse(poster.events[1].isKeyDown)
        XCTAssertEqual(poster.events[1].flags, .maskCommand)
    }
}
