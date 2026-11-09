import AppKit
import Foundation

public enum SingleInstance {
    private final class ClaimEntry {
        let observer: NSObjectProtocol
        let onSecondLaunch: @MainActor () -> Void

        init(observer: NSObjectProtocol, onSecondLaunch: @escaping @MainActor () -> Void) {
            self.observer = observer
            self.onSecondLaunch = onSecondLaunch
        }
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var claims: [String: ClaimEntry] = [:]

    public static func notificationName(for bundleID: String) -> Notification.Name {
        Notification.Name("\(bundleID).show")
    }

    public static func claim(
        bundleID: String,
        onSecondLaunch: @escaping @MainActor () -> Void
    ) -> Bool {
        let name = notificationName(for: bundleID)

        lock.lock()
        if let existing = claims[bundleID] {
            lock.unlock()
            let callback = existing.onSecondLaunch
            DispatchQueue.main.async {
                callback()
            }
            return false
        }

        let currentPID = ProcessInfo.processInfo.processIdentifier
        let otherRunning = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleID)
            .contains { $0.processIdentifier != currentPID && !$0.isTerminated }

        if otherRunning {
            lock.unlock()
            DistributedNotificationCenter.default().postNotificationName(
                name,
                object: nil,
                userInfo: nil,
                deliverImmediately: true
            )
            return false
        }

        let observer = DistributedNotificationCenter.default().addObserver(
            forName: name,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                onSecondLaunch()
            }
        }

        claims[bundleID] = ClaimEntry(observer: observer, onSecondLaunch: onSecondLaunch)
        lock.unlock()
        return true
    }

    public static func release(bundleID: String) {
        lock.lock()
        let entry = claims.removeValue(forKey: bundleID)
        lock.unlock()

        if let entry {
            DistributedNotificationCenter.default().removeObserver(entry.observer)
        }
    }
}
