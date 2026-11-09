import Foundation

@MainActor
public final class ScreenLockMonitor {
    private static let lockedNotification = Notification.Name("com.apple.screenIsLocked")
    private static let unlockedNotification = Notification.Name("com.apple.screenIsUnlocked")

    private let onLock: () -> Void
    private var isLocked = false
    nonisolated(unsafe) private var lockObserver: NSObjectProtocol?
    nonisolated(unsafe) private var unlockObserver: NSObjectProtocol?

    public init(onLock: @escaping () -> Void) {
        self.onLock = onLock

        let center = DistributedNotificationCenter.default()
        lockObserver = center.addObserver(
            forName: Self.lockedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.isLocked else { return }
                self.isLocked = true
                self.onLock()
            }
        }

        unlockObserver = center.addObserver(
            forName: Self.unlockedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isLocked = false
            }
        }
    }

    deinit {
        let center = DistributedNotificationCenter.default()
        if let lockObserver {
            center.removeObserver(lockObserver)
        }
        if let unlockObserver {
            center.removeObserver(unlockObserver)
        }
    }
}
