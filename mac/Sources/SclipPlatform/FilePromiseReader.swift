import AppKit
import Foundation
import SclipCore

/// NSFilePromiseReceiver cozumleyicisi (B-8.4.2, B-8.8.6, E26, E27).
public final class FilePromiseReader {
    private final class UrlCollector: @unchecked Sendable {
        private let lock = NSLock()
        private var urls: [URL] = []

        func append(_ url: URL) {
            lock.lock()
            urls.append(url)
            lock.unlock()
        }

        func snapshot() -> [URL] {
            lock.lock()
            defer { lock.unlock() }
            return urls
        }
    }

    private let root: URL
    private let timeout: TimeInterval

    public init(root: URL = FileManager.default.temporaryDirectory, timeout: TimeInterval = 10) {
        self.root = root
        self.timeout = timeout
    }

    public func receive(from pb: NSPasteboard, into id: EntryID) -> [URL] {
        guard let promises = pb.readObjects(
            forClasses: [NSFilePromiseReceiver.self],
            options: nil
        ) as? [NSFilePromiseReceiver], !promises.isEmpty else {
            return []
        }

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
        let group = DispatchGroup()
        let collector = UrlCollector()

        for promise in promises {
            group.enter()
            promise.receivePromisedFiles(
                atDestination: entryDir,
                options: [:],
                operationQueue: opQueue
            ) { fileURL, error in
                if error == nil {
                    collector.append(fileURL)
                }
                group.leave()
            }
        }

        let waitResult = group.wait(timeout: .now() + timeout)
        guard waitResult == .success else {
            opQueue.cancelAllOperations()
            return []
        }

        let resolved = collector.snapshot()
        if !resolved.isEmpty {
            Self.publishFileURLs(resolved, to: pb)
        }
        return resolved
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
