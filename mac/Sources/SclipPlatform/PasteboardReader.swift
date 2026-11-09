import AppKit
import Foundation
import SclipCore

/// macOS NSPasteboard okuyucusu (`ClipboardSource`, B-8.8.1, B-8.8.4, B-8.8.7, B-8.4.4).
public final class PasteboardReader: ClipboardSource {
    private let pasteboard: NSPasteboard
    private let receivePromises: (NSPasteboard, EntryID) -> [URL]
    private let cancelPromises: () -> Void

    public init(
        pasteboard: NSPasteboard = .general,
        receivePromises: @escaping (NSPasteboard, EntryID) -> [URL] = { _, _ in [] },
        cancelPromises: @escaping () -> Void = {}
    ) {
        self.pasteboard = pasteboard
        self.receivePromises = receivePromises
        self.cancelPromises = cancelPromises
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
            cancelPromises()
            return directURLs
        }
        // B-8.4.4: destination == nil ise (hassas kopya) promise cozulmez, diske yazilmaz.
        guard let destination else {
            cancelPromises()
            return []
        }
        return receivePromises(pasteboard, destination)
    }

    public func readClip() -> RawClip {
        cancelPromises()
        let items = pasteboard.pasteboardItems ?? []
        var rawItems: [RawItem] = []
        rawItems.reserveCapacity(items.count)

        for item in items {
            let itemTypes = Set(item.types)
            var formats: [CanonicalFormat: Data] = [:]
            for (pbType, canonical) in PasteboardTypeMap.directMappings where itemTypes.contains(pbType) {
                if let data = item.data(forType: pbType) {
                    formats[canonical] = data
                }
            }
            let hasDirectRaster = formats[.png] != nil
                || formats[.jpeg] != nil
                || formats[.gif] != nil
                || formats[.webp] != nil
            if !hasDirectRaster,
               itemTypes.contains(PasteboardTypeMap.tiff),
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
