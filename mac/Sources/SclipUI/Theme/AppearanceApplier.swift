import AppKit
import SclipCore

public enum AppearanceApplier {
    @MainActor
    public static func appearance(for mode: ThemeMode) -> NSAppearance? {
        switch mode {
        case .system:
            return nil
        case .light:
            return NSAppearance(named: .aqua)
        case .dark:
            return NSAppearance(named: .darkAqua)
        }
    }

    @MainActor
    public static func apply(_ mode: ThemeMode, to window: NSWindow?) {
        let resolved = appearance(for: mode)
        NSApp?.appearance = resolved
        window?.appearance = resolved
    }
}
