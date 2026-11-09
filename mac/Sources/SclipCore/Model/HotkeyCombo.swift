import Foundation

public enum Modifier: String, Sendable, CaseIterable, Codable {
    case command
    case control
    case option
    case shift
}

/// Global kisayol kombosu (B-6.6.3, B-6.6.15, B-6.8.1).
public struct HotkeyCombo: Sendable, Equatable, Hashable {
    /// Carbon `kVK_ANSI_V` (0x09).
    public static let vKeyCode: UInt16 = 9

    /// B-6.8.1: macOS varsayilan deneme sirasi (Cmd+Shift+V, Cmd+Opt+V, Ctrl+Cmd+V).
    public static let macDefaults: [HotkeyCombo] = [
        HotkeyCombo(modifiers: [.command, .shift], keyCode: vKeyCode),
        HotkeyCombo(modifiers: [.command, .option], keyCode: vKeyCode),
        HotkeyCombo(modifiers: [.control, .command], keyCode: vKeyCode),
    ]

    public let modifiers: Set<Modifier>
    public let keyCode: UInt16

    public init(modifiers: Set<Modifier>, keyCode: UInt16) {
        self.modifiers = modifiers
        self.keyCode = keyCode
    }

    /// B-6.6.15: en az 2 modifiyer zorunludur.
    public var isValid: Bool {
        modifiers.count >= 2
    }

    /// Kanonik saklama bicimi: `"command+shift:9"` (Modifier.allCases sirasinda).
    public var storageString: String {
        let modPart = Modifier.allCases
            .filter { modifiers.contains($0) }
            .map(\.rawValue)
            .joined(separator: "+")
        return "\(modPart):\(keyCode)"
    }

    public init?(storageString: String) {
        let parts = storageString.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              !parts[0].isEmpty,
              let code = UInt16(parts[1])
        else {
            return nil
        }

        let tokens = parts[0].split(separator: "+", omittingEmptySubsequences: false)
        var parsed: Set<Modifier> = []
        for token in tokens {
            guard let mod = Modifier(rawValue: String(token)),
                  parsed.insert(mod).inserted
            else {
                return nil
            }
        }

        self.init(modifiers: parsed, keyCode: code)
        guard isValid else { return nil }
    }
}
