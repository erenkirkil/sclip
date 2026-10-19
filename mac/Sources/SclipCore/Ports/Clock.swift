import Foundation

/// Zaman kaynağı; testlerde sabit saat enjekte edilir.
public protocol Clock: Sendable {
    func now() -> Date
}

public struct SystemClock: Clock {
    public init() {}

    public func now() -> Date { Date() }
}
