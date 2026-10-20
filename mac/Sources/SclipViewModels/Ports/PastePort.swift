/// Yapıştırmanın sonucu; hangisi olursa olsun panel gizli kalır (B-7.1.6).
public enum PasteOutcome: Sendable { case pasted, aborted }

/// Platform yapıştırıcı (Task 24).
@MainActor
public protocol PastePort: AnyObject {
    /// Gösterimden önce ön plan hedefini kaydeder (B-7.2.1).
    func captureTarget()
    /// Sentetik yapıştırmayı yürütür; bitince tam bir kez `completion` çağırır.
    func pasteToTarget(completion: @escaping @MainActor (PasteOutcome) -> Void)
}
