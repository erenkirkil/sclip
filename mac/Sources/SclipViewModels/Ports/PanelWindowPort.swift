/// Gösterimden sonra odaklanacak yer (E17).
public enum FocusTarget: Sendable { case firstRow, searchField, settings }

/// Platform panel penceresi (Task 26). Tüm çağrılar ana thread'de, senkrondur.
@MainActor
public protocol PanelWindowPort: AnyObject {
    func show()
    func hide()
    func focus(_ target: FocusTarget)
    /// Pencere anahtar (key) mi; `NSApp.isActive` değil (B-7.1.8).
    var isKey: Bool { get }
}
