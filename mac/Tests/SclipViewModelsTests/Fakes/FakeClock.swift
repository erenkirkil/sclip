import Foundation
import SclipCore

/// Elle ilerletilen saat. Testler tek thread'de çalışır.
final class FakeClock: Clock, @unchecked Sendable {
    var current: Date

    init(_ start: Date = Date(timeIntervalSinceReferenceDate: 0)) { current = start }

    func now() -> Date { current }

    func advance(_ seconds: TimeInterval) { current = current.addingTimeInterval(seconds) }
}
