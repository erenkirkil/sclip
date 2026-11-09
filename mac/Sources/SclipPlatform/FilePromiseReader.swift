import AppKit
import Foundation
import SclipCore

/// NSFilePromiseReceiver cozumleyicisi (B-8.4.2, B-8.8.6, E26, E27).
/// Ana thread'i asla bloklamaz: ilk cagrimda arka plan OperationQueue uzerinde
/// promise cozumlemesini baslatir, sonraki yoklama (tick) turlarinda tamamlandiysa
/// URL'leri dondurur; zaman asimi (10 sn) veya iptal durumunda temp dizinini siler.
public final class FilePromiseReader {
    public typealias PromiseOperationStarter = (
        _ pasteboard: NSPasteboard,
        _ entryDir: URL,
        _ queue: OperationQueue,
        _ onFile: @escaping @Sendable (URL?, Error?) -> Void
    ) -> Int

    private final class AttemptState: @unchecked Sendable {
        private let lock = NSLock()
        private let entryDir: URL
        private var urls: [URL] = []
        private var completedCount = 0
        private var expectedTotal: Int?
        private var isCancelled = false

        init(entryDir: URL) {
            self.entryDir = entryDir
        }

        func setExpectedTotal(_ total: Int) {
            lock.lock()
            expectedTotal = total
            lock.unlock()
        }

        func markCancelled() {
            lock.lock()
            isCancelled = true
            lock.unlock()
        }

        func record(url: URL?, error: Error?) {
            lock.lock()
            let cancelled = isCancelled
            if !cancelled {
                if error == nil, let url {
                    urls.append(url)
                }
                completedCount += 1
            }
            lock.unlock()

            if cancelled {
                try? FileManager.default.removeItem(at: entryDir)
            }
        }

        func status() -> (done: Bool, urls: [URL]) {
            lock.lock()
            defer { lock.unlock() }
            guard !isCancelled, let total = expectedTotal else {
                return (false, [])
            }
            return (completedCount >= total, urls)
        }
    }

    private struct InFlightAttempt {
        let id: EntryID
        let entryDir: URL
        let startedAt: Date
        let opQueue: OperationQueue
        let state: AttemptState
        let timeoutWorkItem: DispatchWorkItem
    }

    private let root: URL
    private let timeout: TimeInterval
    private let now: () -> Date
    private let startOperations: PromiseOperationStarter
    private var inFlight: InFlightAttempt?

    public init(
        root: URL = FileManager.default.temporaryDirectory,
        timeout: TimeInterval = 10,
        now: @escaping () -> Date = Date.init,
        startOperations: PromiseOperationStarter? = nil
    ) {
        self.root = root
        self.timeout = timeout
        self.now = now
        self.startOperations = startOperations ?? Self.defaultStartOperations
    }

    deinit {
        cancelCurrentAttempt()
    }

    public func cancelCurrentAttempt() {
        guard let current = inFlight else { return }
        inFlight = nil
        current.timeoutWorkItem.cancel()
        current.state.markCancelled()
        current.opQueue.cancelAllOperations()
        try? FileManager.default.removeItem(at: current.entryDir)
    }

    public func receive(from pb: NSPasteboard, into id: EntryID) -> [URL] {
        if let current = inFlight, current.id != id {
            cancelCurrentAttempt()
        }

        if inFlight == nil {
            let entryDir = root
                .appendingPathComponent("sclip", isDirectory: true)
                .appendingPathComponent(id.description, isDirectory: true)
            do {
                try FileManager.default.createDirectory(
                    at: entryDir,
                    withIntermediateDirectories: true
                )
            } catch {
                return []
            }

            let opQueue = OperationQueue()
            opQueue.maxConcurrentOperationCount = 1
            opQueue.isSuspended = true
            let state = AttemptState(entryDir: entryDir)
            let count = startOperations(pb, entryDir, opQueue) { url, error in
                state.record(url: url, error: error)
            }
            guard count > 0 else {
                try? FileManager.default.removeItem(at: entryDir)
                return []
            }
            state.setExpectedTotal(count)
            let timeoutWorkItem = DispatchWorkItem { [weak self] in
                guard let self, let active = self.inFlight, active.id == id else { return }
                self.cancelCurrentAttempt()
            }
            inFlight = InFlightAttempt(
                id: id,
                entryDir: entryDir,
                startedAt: now(),
                opQueue: opQueue,
                state: state,
                timeoutWorkItem: timeoutWorkItem
            )
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: timeoutWorkItem)
            opQueue.isSuspended = false
        }

        guard let active = inFlight else { return [] }
        let (done, resolved) = active.state.status()
        if done {
            active.timeoutWorkItem.cancel()
            inFlight = nil
            if resolved.isEmpty {
                try? FileManager.default.removeItem(at: active.entryDir)
                return []
            }
            Self.publishFileURLs(resolved, to: pb)
            return resolved
        }

        if now().timeIntervalSince(active.startedAt) >= timeout {
            cancelCurrentAttempt()
        }
        return []
    }

    public static func expectedFileCount(forFileNameCounts counts: [Int]) -> Int {
        counts.reduce(0) { $0 + max(1, $1) }
    }

    private static func defaultStartOperations(
        pasteboard: NSPasteboard,
        entryDir: URL,
        queue: OperationQueue,
        onFile: @escaping @Sendable (URL?, Error?) -> Void
    ) -> Int {
        guard let promises = pasteboard.readObjects(
            forClasses: [NSFilePromiseReceiver.self],
            options: nil
        ) as? [NSFilePromiseReceiver], !promises.isEmpty else {
            return 0
        }
        for promise in promises {
            promise.receivePromisedFiles(
                atDestination: entryDir,
                options: [:],
                operationQueue: queue
            ) { fileURL, error in
                onFile(fileURL, error)
            }
        }
        return expectedFileCount(forFileNameCounts: promises.map { $0.fileNames.count })
    }

    /// Cozulen veya geri yazilan dosya URL'lerini minimal `public.file-url` olarak yazar.
    public static func publishFileURLs(_ urls: [URL], to pb: NSPasteboard) {
        guard !urls.isEmpty else { return }
        pb.clearContents()
        var items: [NSPasteboardItem] = []
        items.reserveCapacity(urls.count)
        for url in urls {
            let item = NSPasteboardItem()
            item.setString(url.absoluteString, forType: PasteboardTypeMap.fileURL)
            items.append(item)
        }
        pb.writeObjects(items)
    }
}
