import CoreGraphics
import Foundation

public protocol KeyState {
    func isReturnDown() -> Bool
}

public struct SystemKeyState: KeyState {
    public init() {}

    public func isReturnDown() -> Bool {
        // kVK_Return (0x24 = 36) and kVK_ANSI_KeypadEnter (0x4C = 76)
        CGEventSource.keyState(.combinedSessionState, key: 0x24)
            || CGEventSource.keyState(.combinedSessionState, key: 0x4C)
    }
}
