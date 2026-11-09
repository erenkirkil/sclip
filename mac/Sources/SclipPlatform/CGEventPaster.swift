import AppKit
import CoreGraphics
import Foundation
import SclipCore

public protocol CGEventPoster {
    func post(_ event: CGEvent)
}

public struct SystemCGEventPoster: CGEventPoster {
    public init() {}

    public func post(_ event: CGEvent) {
        event.post(tap: .cghidEventTap)
    }
}

@MainActor
public final class CGEventPaster: PastePort {
    private static let vKeyCode: CGKeyCode = 0x09

    private let delayAfterOrderOut: TimeInterval
    private let enterReleaseTimeout: TimeInterval
    private let pollInterval: TimeInterval
    private let frontmostPID: () -> pid_t?
    private let isTrusted: () -> Bool
    private let keyState: KeyState
    private let poster: CGEventPoster

    private var capturedTargetPID: pid_t?

    public init(
        delayAfterOrderOut: TimeInterval = 0.02,
        enterReleaseTimeout: TimeInterval = 0.5,
        pollInterval: TimeInterval = 0.01,
        frontmostPID: @escaping () -> pid_t? = { NSWorkspace.shared.frontmostApplication?.processIdentifier },
        isTrusted: @escaping () -> Bool = { AccessibilityPermission.isTrusted() },
        keyState: KeyState = SystemKeyState(),
        poster: CGEventPoster = SystemCGEventPoster()
    ) {
        self.delayAfterOrderOut = delayAfterOrderOut
        self.enterReleaseTimeout = enterReleaseTimeout
        self.pollInterval = pollInterval
        self.frontmostPID = frontmostPID
        self.isTrusted = isTrusted
        self.keyState = keyState
        self.poster = poster
    }

    public func captureTarget() {
        capturedTargetPID = frontmostPID()
    }

    public func pasteToTarget(completion: @escaping @MainActor @Sendable (PasteOutcome) -> Void) {
        let targetPID = capturedTargetPID
        capturedTargetPID = nil

        guard let targetPID else {
            completion(.aborted)
            return
        }

        let start = Date()
        waitUntilReturnReleased(start: start) { [weak self] in
            guard let self else {
                completion(.aborted)
                return
            }
            self.schedulePasteAfterDelay(targetPID: targetPID, completion: completion)
        }
    }

    private func waitUntilReturnReleased(start: Date, onDone: @escaping @MainActor @Sendable () -> Void) {
        if !keyState.isReturnDown() {
            onDone()
            return
        }
        if Date().timeIntervalSince(start) >= enterReleaseTimeout {
            onDone()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + pollInterval) { [weak self] in
            self?.waitUntilReturnReleased(start: start, onDone: onDone)
        }
    }

    private func schedulePasteAfterDelay(
        targetPID: pid_t,
        completion: @escaping @MainActor @Sendable (PasteOutcome) -> Void
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delayAfterOrderOut) { [weak self] in
            guard let self else {
                completion(.aborted)
                return
            }
            guard self.frontmostPID() == targetPID else {
                completion(.aborted)
                return
            }
            guard self.isTrusted() else {
                completion(.aborted)
                return
            }
            guard let source = CGEventSource(stateID: .hidSystemState),
                  let keyDown = CGEvent(keyboardEventSource: source, virtualKey: Self.vKeyCode, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: Self.vKeyCode, keyDown: false)
            else {
                completion(.aborted)
                return
            }

            // E33: Force solely Command modifier so held Shift/Option do not leak into Cmd+Shift+V.
            keyDown.flags = .maskCommand
            keyUp.flags = .maskCommand

            self.poster.post(keyDown)
            self.poster.post(keyUp)
            completion(.pasted)
        }
    }
}
