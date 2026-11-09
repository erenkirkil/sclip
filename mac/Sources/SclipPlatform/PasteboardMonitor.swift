import Foundation

/// Pano yoklama zamanlayicisi (B-8.8.1, B-8.8.3).
@MainActor
public final class PasteboardMonitor {
    public var interval: TimeInterval {
        didSet {
            guard interval > 0 else { return }
            if timer != nil {
                scheduleTimer()
            }
        }
    }

    private let tick: @MainActor () -> Void
    private var timer: Timer?

    public init(interval: TimeInterval, tick: @escaping @MainActor () -> Void) {
        self.interval = max(0.001, interval)
        self.tick = tick
    }

    public func start() {
        scheduleTimer()
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    public func checkNow() {
        tick()
    }

    private func scheduleTimer() {
        timer?.invalidate()
        let currentInterval = max(0.001, interval)
        let newTimer = Timer(timeInterval: currentInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
        newTimer.tolerance = currentInterval * 0.2
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }
}
