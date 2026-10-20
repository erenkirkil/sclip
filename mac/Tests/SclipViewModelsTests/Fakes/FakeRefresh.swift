@testable import SclipViewModels

/// Senkron tazeleme taklidi (E6).
@MainActor
final class FakeRefresh: RefreshPort {
    private let log: CallLog
    private(set) var count = 0

    init(log: CallLog) { self.log = log }

    func refreshNow() {
        count += 1
        log.add("refresh")
    }
}
