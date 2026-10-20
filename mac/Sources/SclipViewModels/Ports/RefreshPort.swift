/// Panel gösterilmeden önce panoyu senkron yoklar (E6, B-8.8.3).
@MainActor
public protocol RefreshPort: AnyObject {
    func refreshNow()
}
