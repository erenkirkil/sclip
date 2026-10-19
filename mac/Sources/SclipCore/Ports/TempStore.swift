import Foundation

/// Temp materializasyon portu (B-8.4). `isSensitive` öğe için `materialize` çağrılmaz (B-8.4.4).
public protocol TempStore: AnyObject {
    func materialize(_ entry: Entry) throws -> [URL]
    func delete(_ entry: Entry)
    func pruneAll()
}
