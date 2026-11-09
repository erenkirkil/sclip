import AppKit
import ApplicationServices
import Foundation

public enum AccessibilityPermission {
    public static func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    public static func openSettings() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)

        let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}
