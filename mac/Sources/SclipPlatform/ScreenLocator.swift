import AppKit
import CoreGraphics
import SclipCore

public enum ScreenLocator {
    @MainActor
    public static func current() -> (cursor: CGPoint, screens: [ScreenArea]) {
        let cursor = NSEvent.mouseLocation
        let screens = NSScreen.screens.map { screen in
            ScreenArea(frame: screen.frame, visible: screen.visibleFrame)
        }
        return (cursor: cursor, screens: screens)
    }
}
