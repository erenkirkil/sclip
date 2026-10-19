import Foundation

/// Süreç içinde benzersiz, monoton, kalıcı olmayan kimlik (B-8.1.3).
public struct EntryID: Hashable, Sendable, CustomStringConvertible {
    public let raw: UInt64

    public init(raw: UInt64) { self.raw = raw }

    public var description: String { "e\(raw)" }
}

/// Kilitli, monoton `EntryID` üreteci. İlk kimlik 1'dir.
public final class EntryIDGenerator: @unchecked Sendable {
    private let lock = NSLock()
    private var last: UInt64 = 0

    public init() {}

    public func next() -> EntryID {
        lock.lock()
        defer { lock.unlock() }
        last += 1
        return EntryID(raw: last)
    }
}
