import Carbon.HIToolbox
import Foundation
import SclipCore

public enum HotkeyFormatter {
    public static func format(_ combo: HotkeyCombo?) -> String {
        guard let combo else { return "-" }
        var symbols = ""
        if combo.modifiers.contains(.control) { symbols += "\u{2303}" }
        if combo.modifiers.contains(.option) { symbols += "\u{2325}" }
        if combo.modifiers.contains(.shift) { symbols += "\u{21E7}" }
        if combo.modifiers.contains(.command) { symbols += "\u{2318}" }
        return symbols + keyName(for: combo.keyCode)
    }

    public static func formatReadable(_ combo: HotkeyCombo?) -> String {
        guard let combo else { return "-" }
        var parts: [String] = []
        if combo.modifiers.contains(.control) { parts.append("Ctrl") }
        if combo.modifiers.contains(.option) { parts.append("Opt") }
        if combo.modifiers.contains(.shift) { parts.append("Shift") }
        if combo.modifiers.contains(.command) { parts.append("Cmd") }
        parts.append(keyName(for: combo.keyCode))
        return parts.joined(separator: " + ")
    }

    public static func keyName(for keyCode: UInt16) -> String {
        switch Int(keyCode) {
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_Space: return "Space"
        default: return "Key\(keyCode)"
        }
    }
}
