import Foundation
import SclipCore

public enum TempStoreError: Error, Equatable {
    case sensitiveEntry
    case unsupportedPayload
}

/// `<root>/sclip/<entryId>/` gecici dosya deposu (B-8.4.1 – B-8.4.4, E29).
public final class FileTempStore: TempStore {
    private let root: URL
    private let isOnPasteboard: (Entry) -> Bool

    public init(
        root: URL = FileManager.default.temporaryDirectory,
        isOnPasteboard: @escaping (Entry) -> Bool
    ) {
        self.root = root
        self.isOnPasteboard = isOnPasteboard
    }

    public func materialize(_ entry: Entry) throws -> [URL] {
        guard !entry.isSensitive else {
            throw TempStoreError.sensitiveEntry
        }

        let dir = try freshEntryDirectory(for: entry.id)
        switch entry.payload {
        case .svg(let xml):
            let fileURL = dir.appendingPathComponent("clipboard.svg", isDirectory: false)
            try Data(xml.utf8).write(to: fileURL, options: .atomic)
            return [fileURL]

        case .pdf(let data):
            let fileURL = dir.appendingPathComponent("clipboard.pdf", isDirectory: false)
            try data.write(to: fileURL, options: .atomic)
            return [fileURL]

        case .image(let item):
            let ext = Self.fileExtension(for: item.format)
            let fileURL = dir.appendingPathComponent("clipboard.\(ext)", isDirectory: false)
            try item.data.write(to: fileURL, options: .atomic)
            return [fileURL]

        case .imageSet(let items):
            var urls: [URL] = []
            urls.reserveCapacity(items.count)
            for (index, item) in items.enumerated() {
                let ext = Self.fileExtension(for: item.format)
                let filename = String(format: "%03d.%@", index + 1, ext)
                let fileURL = dir.appendingPathComponent(filename, isDirectory: false)
                try item.data.write(to: fileURL, options: .atomic)
                urls.append(fileURL)
            }
            return urls

        case .text, .url, .color, .files, .richText:
            throw TempStoreError.unsupportedPayload
        }
    }

    public func delete(_ entry: Entry) {
        guard !isOnPasteboard(entry) else { return }
        let dir = sclipRootDirectory.appendingPathComponent(entry.id.description, isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
    }

    public func pruneAll() {
        try? FileManager.default.removeItem(at: sclipRootDirectory)
    }

    private var sclipRootDirectory: URL {
        root.appendingPathComponent("sclip", isDirectory: true)
    }

    private func freshEntryDirectory(for id: EntryID) throws -> URL {
        let dir = sclipRootDirectory.appendingPathComponent(id.description, isDirectory: true)
        if FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.removeItem(at: dir)
        }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public static func fileExtension(for format: ImageFormat) -> String {
        switch format {
        case .png: return "png"
        case .jpeg: return "jpg"
        case .gif: return "gif"
        case .webp: return "webp"
        }
    }
}
