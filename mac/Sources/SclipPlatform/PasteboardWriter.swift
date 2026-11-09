import AppKit
import Foundation
import SclipCore

public enum PasteboardWriteError: Error, Equatable {
    case invalidImageIndex
    case writeFailed
}

/// Tip basina macOS NSPasteboard geri yazicisi (`ClipboardSink`, B-8.9.1 – B-8.9.7, E21, E30).
public final class PasteboardWriter: ClipboardSink {
    private let pasteboard: NSPasteboard
    private let temp: TempStore

    public init(pasteboard: NSPasteboard = .general, temp: TempStore) {
        self.pasteboard = pasteboard
        self.temp = temp
    }

    public func write(_ entry: Entry, plainOnly: Bool, imageIndex: Int?) throws -> WriteReceipt {
        let signature: String

        switch entry.payload {
        case .text(let s):
            try writeSingleString(s)
            signature = entry.contentHash

        case .url(let original, _, _):
            try writeSingleString(original)
            signature = entry.contentHash

        case .color(let original, _, _):
            try writeSingleString(original)
            signature = entry.contentHash

        case .richText(let plain, let html, let rtf):
            if plainOnly {
                try writeSingleString(plain)
                signature = ContentHash.text("t", plain)
            } else {
                let item = NSPasteboardItem()
                item.setString(plain, forType: PasteboardTypeMap.utf8PlainText)
                item.setData(Data(html.utf8), forType: PasteboardTypeMap.html)
                if let rtf, !rtf.isEmpty {
                    item.setData(rtf, forType: PasteboardTypeMap.rtf)
                }
                try writeItems([item])
                signature = entry.contentHash
            }

        case .svg(let xml):
            let item = NSPasteboardItem()
            if !entry.isSensitive, let urls = try? temp.materialize(entry), let first = urls.first {
                item.setString(first.absoluteString, forType: PasteboardTypeMap.fileURL)
            }
            item.setData(Data(xml.utf8), forType: PasteboardTypeMap.svg)
            item.setString(xml, forType: PasteboardTypeMap.utf8PlainText)
            try writeItems([item])
            signature = entry.contentHash

        case .pdf(let data):
            let item = NSPasteboardItem()
            if !entry.isSensitive, let urls = try? temp.materialize(entry), let first = urls.first {
                item.setString(first.absoluteString, forType: PasteboardTypeMap.fileURL)
            }
            item.setData(data, forType: PasteboardTypeMap.pdf)
            try writeItems([item])
            signature = entry.contentHash

        case .image(let img):
            let item = NSPasteboardItem()
            item.setData(img.data, forType: Self.pasteboardType(for: img.format))
            try writeItems([item])
            signature = entry.contentHash

        case .imageSet(let items):
            if let index = imageIndex {
                guard items.indices.contains(index) else {
                    throw PasteboardWriteError.invalidImageIndex
                }
                let chosen = items[index]
                let item = NSPasteboardItem()
                item.setData(chosen.data, forType: Self.pasteboardType(for: chosen.format))
                try writeItems([item])
                signature = ContentHash.bytes("i", chosen.data)
            } else if entry.isSensitive {
                // B-8.4.4: Hassas imageSet diske yazilmaz; satir ici coklu oge olarak yazilir.
                let pbItems = items.map { img -> NSPasteboardItem in
                    let item = NSPasteboardItem()
                    item.setData(img.data, forType: Self.pasteboardType(for: img.format))
                    return item
                }
                try writeItems(pbItems)
                signature = entry.contentHash
            } else {
                let urls = try temp.materialize(entry)
                FilePromiseReader.publishFileURLs(urls, to: pasteboard)
                signature = entry.contentHash
            }

        case .files(let urls):
            FilePromiseReader.publishFileURLs(urls, to: pasteboard)
            signature = entry.contentHash
        }

        return WriteReceipt(change: pasteboard.changeCount, signature: signature)
    }

    private func writeSingleString(_ value: String) throws {
        let item = NSPasteboardItem()
        item.setString(value, forType: PasteboardTypeMap.utf8PlainText)
        try writeItems([item])
    }

    private func writeItems(_ items: [NSPasteboardItem]) throws {
        pasteboard.clearContents()
        guard pasteboard.writeObjects(items) else {
            throw PasteboardWriteError.writeFailed
        }
    }

    public static func pasteboardType(for format: ImageFormat) -> NSPasteboard.PasteboardType {
        switch format {
        case .png: return PasteboardTypeMap.png
        case .jpeg: return PasteboardTypeMap.jpeg
        case .gif: return PasteboardTypeMap.gif
        case .webp: return PasteboardTypeMap.webp
        }
    }
}
