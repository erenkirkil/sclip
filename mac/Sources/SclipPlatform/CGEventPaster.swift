import AppKit
import Carbon.HIToolbox
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
    public static let ansiVKeyCode: CGKeyCode = 0x09

    private let delayAfterOrderOut: TimeInterval
    private let enterReleaseTimeout: TimeInterval
    private let pollInterval: TimeInterval
    private let frontmostPID: () -> pid_t?
    private let isTrusted: () -> Bool
    private let keyState: KeyState
    private let poster: CGEventPoster
    private let vKeyCodeProvider: () -> CGKeyCode

    private var capturedTargetPID: pid_t?

    public init(
        delayAfterOrderOut: TimeInterval = 0.02,
        enterReleaseTimeout: TimeInterval = 0.5,
        pollInterval: TimeInterval = 0.01,
        frontmostPID: @escaping () -> pid_t? = { NSWorkspace.shared.frontmostApplication?.processIdentifier },
        isTrusted: @escaping () -> Bool = { AccessibilityPermission.isTrusted() },
        keyState: KeyState = SystemKeyState(),
        poster: CGEventPoster = SystemCGEventPoster(),
        vKeyCodeProvider: @escaping () -> CGKeyCode = { CGEventPaster.resolveVKeyCode() }
    ) {
        self.delayAfterOrderOut = delayAfterOrderOut
        self.enterReleaseTimeout = enterReleaseTimeout
        self.pollInterval = pollInterval
        self.frontmostPID = frontmostPID
        self.isTrusted = isTrusted
        self.keyState = keyState
        self.poster = poster
        self.vKeyCodeProvider = vKeyCodeProvider
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

    /// Aktif klavye duzeninde 'v' harfini ureten sanal tus kodunu bulur (Turkce-F, Dvorak vb. destegi).
    /// Latin disi bir duzen aktifse ANSI V (0x09) varsayilanina doner.
    public static func resolveVKeyCode() -> CGKeyCode {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let rawPtr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else {
            return ansiVKeyCode
        }
        let layoutData = unsafeBitCast(rawPtr, to: CFData.self)
        guard let bytePtr = CFDataGetBytePtr(layoutData) else {
            return ansiVKeyCode
        }
        let keyboardLayout = UnsafeRawPointer(bytePtr).assumingMemoryBound(to: UCKeyboardLayout.self)
        let kbdType = UInt32(LMGetKbdType())

        for code in UInt16(0)..<UInt16(128) {
            var deadKeyState: UInt32 = 0
            var chars = [UniChar](repeating: 0, count: 4)
            var actualLength: Int = 0
            let status = UCKeyTranslate(
                keyboardLayout,
                code,
                UInt16(kUCKeyActionDisplay),
                0,
                kbdType,
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                chars.count,
                &actualLength,
                &chars
            )
            if status == noErr, actualLength == 1 {
                if chars[0] == 0x0076 || chars[0] == 0x0056 { // 'v' or 'V'
                    return CGKeyCode(code)
                }
            }
        }
        return ansiVKeyCode
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
            let keyCode = self.vKeyCodeProvider()
            guard let source = CGEventSource(stateID: .hidSystemState),
                  let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
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
