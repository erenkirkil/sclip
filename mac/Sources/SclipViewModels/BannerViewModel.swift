import Combine
import Foundation
import SclipCore

public enum Banner: Sendable, Equatable {
    case accessibility
    case hotkey
    case lockCleared
}

/// Serit gorunum modeli (B-6.9.1 – B-6.9.5, E11).
/// Kanonik sira her zaman `[.accessibility, .hotkey, .lockCleared]`.
@MainActor
public final class BannerViewModel: ObservableObject {
    @Published public private(set) var banners: [Banner] = []

    private var accessibilityTrusted = true
    private var hotkeyRegistered = true
    private var lockClearedVisible = false

    public init() {}

    public func setAccessibilityTrusted(_ v: Bool) {
        accessibilityTrusted = v
        rebuild()
    }

    public func setHotkeyRegistered(_ v: Bool) {
        hotkeyRegistered = v
        rebuild()
    }

    /// B-6.9.4: Yalniz bos olmayan bir gecmis gercekten temizlendiyse gosterilir.
    public func lockCleared(hadEntries: Bool) {
        guard hadEntries else { return }
        lockClearedVisible = true
        rebuild()
    }

    public func dismissLockCleared() {
        lockClearedVisible = false
        rebuild()
    }

    private func rebuild() {
        var next: [Banner] = []
        if !accessibilityTrusted { next.append(.accessibility) }
        if !hotkeyRegistered { next.append(.hotkey) }
        if lockClearedVisible { next.append(.lockCleared) }
        if banners != next {
            banners = next
        }
    }
}
