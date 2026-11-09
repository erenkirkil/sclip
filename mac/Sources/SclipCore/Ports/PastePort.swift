import Foundation

/// Yapistirmanin sonucu; hangisi olursa olsun panel gizli kalir (B-7.1.6).
public enum PasteOutcome: Sendable {
    case pasted
    case aborted
}

/// Platform yapistirici portu (B-7.2.1, B-7.2.2).
@MainActor
public protocol PastePort: AnyObject {
    func captureTarget()
    func pasteToTarget(completion: @escaping @MainActor (PasteOutcome) -> Void)
}
