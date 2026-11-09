import AppKit
import Foundation
import SclipCore

/// macOS NSPasteboard okuyucusu (`ClipboardSource`, B-8.8.1, B-8.8.4, B-8.8.7, B-8.4.4).
public final class PasteboardReader: ClipboardSource {
    private let pasteboard: NSPasteboard
    private let receivePromises: (NSPasteboard, EntryID) -> [URL]

    public init(
        pasteboard: NSPasteboard = .general,
        receivePromises: @escaping (NSPasteboard, EntryID) -> [URL] = { _, _ in [] }
    ) {
        self.pasteboard = pasteboard
        self.receivePromises = receivePromises
    }

    public func currentState() -> ClipboardState {
        let change = pasteboard.changeCount
        let types = allTypes()
        return ClipboardState(
            change: change,
            sensitive: PasteboardTypeMap.isSensitive(types),
            hasFiles: PasteboardTypeMap.hasFiles(types)
        )
    }

    public func readFiles(destination: EntryID?) -> [URL] {
        let directURLs = readDirectFileURLs()
        if !directURLs.isEmpty {
            return directURLs
        }
        // B-8.4.4: destination == nil ise (hassas kopya) promise cozulmez, diske yazilmaz.
        guard let destination else { return [] }
        return receivePromises(pasteboard, destination)
    }

    public func readClip() -> RawClip {
        let items = pasteboard.pasteboardItems ?? []
        var rawItems: [RawItem] = []
        rawItems.reserveCapacity(items.count)

        for item in items {
            var formats: [CanonicalFormat: Data] = [:]
            for (pbType, canonical) in PasteboardTypeMap.directMappings {
                if let data = item.data(forType: pbType) {
                    formats[canonical] = data
                }
            }
            if formats[.png] == nil,
               let tiffData = item.data(forType: PasteboardTypeMap.tiff),
               let pngData = ImageTranscoder.tiffToPNG(tiffData)
            {
                formats[.png] = pngData
            }
            if !formats.isEmpty {
                rawItems.append(RawItem(formats: formats))
            }
        }

        let files = readDirectFileURLs()
        let flags = PasteboardTypeMap.flags(for: allTypes())
        return RawClip(items: rawItems, files: files, flags: flags)
    }

    private func readDirectFileURLs() -> [URL] {
        let types = pasteboard.types ?? []
        guard types.contains(PasteboardTypeMap.fileURL),
              let urls = pasteboard.readObjects(
                  forClasses: [NSURL.self],
                  options: [.urlReadingFileURLsOnly: true]
              ) as? [URL]
        else {
            return []
        }
        return urls
    }

    private func allTypes() -> [NSPasteboard.PasteboardType] {
        var collected = pasteboard.types ?? []
        if let items = pasteboard.pasteboardItems {
            for item in items {
                for t in item.types where !collected.contains(t) {
                    collected.append(t)
                }
            }
        }
        return collected
    }
}
