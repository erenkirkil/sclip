import AppKit
import Foundation
import SclipCore
import SclipPlatform
import XCTest

final class PasteboardWriterTests: XCTestCase {
    private var pasteboard: NSPasteboard!
    private var tempRoot: URL!
    private var tempStore: FileTempStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        pasteboard = NSPasteboard(name: .init("sclip-writer-test-\(UUID().uuidString)"))
        pasteboard.clearContents()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("sclip-writer-temp-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        tempStore = FileTempStore(root: tempRoot) { _ in false }
    }

    override func tearDownWithError() throws {
        pasteboard?.releaseGlobally()
        pasteboard = nil
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        tempRoot = nil
        tempStore = nil
        try super.tearDownWithError()
    }

    func testColorWritesOriginalText() throws {
        let writer = PasteboardWriter(pasteboard: pasteboard, temp: tempStore)
        let entry = Entry(
            id: EntryID(raw: 1),
            createdAt: Date(),
            payload: .color(original: "#FACADE", normalized: "#facade", argb: 0xFFFA_CADE),
            isSensitive: false
        )

        _ = try writer.write(entry, plainOnly: false, imageIndex: nil)
        XCTAssertEqual(pasteboard.string(forType: .string), "#FACADE")
    }

    func testUrlWritesOriginalNotNormalized() throws {
        let writer = PasteboardWriter(pasteboard: pasteboard, temp: tempStore)
        let entry = Entry(
            id: EntryID(raw: 2),
            createdAt: Date(),
            payload: .url(
                original: "user@example.com",
                uri: "mailto:user@example.com",
                display: "user@example.com"
            ),
            isSensitive: false
        )

        _ = try writer.write(entry, plainOnly: false, imageIndex: nil)
        XCTAssertEqual(pasteboard.string(forType: .string), "user@example.com")
    }

    func testPlainOnlyStripsHtmlAndRtf() throws {
        let writer = PasteboardWriter(pasteboard: pasteboard, temp: tempStore)
        let entry = Entry(
            id: EntryID(raw: 3),
            createdAt: Date(),
            payload: .richText(
                plain: "Hello world",
                html: "<b>Hello world</b>",
                rtf: Data("{\\rtf1 Hello}".utf8)
            ),
            isSensitive: false
        )

        let receipt = try writer.write(entry, plainOnly: true, imageIndex: nil)
        XCTAssertEqual(pasteboard.string(forType: .string), "Hello world")
        XCTAssertNil(pasteboard.data(forType: PasteboardTypeMap.html))
        XCTAssertNil(pasteboard.data(forType: PasteboardTypeMap.rtf))
        XCTAssertEqual(receipt.signature, ContentHash.text("t", "Hello world"))
    }

    func testRichTextWritesAllThree() throws {
        let writer = PasteboardWriter(pasteboard: pasteboard, temp: tempStore)
        let rtfBytes = Data("{\\rtf1 Bold}".utf8)
        let entry = Entry(
            id: EntryID(raw: 4),
            createdAt: Date(),
            payload: .richText(plain: "Bold", html: "<b>Bold</b>", rtf: rtfBytes),
            isSensitive: false
        )

        let receipt = try writer.write(entry, plainOnly: false, imageIndex: nil)
        XCTAssertEqual(pasteboard.string(forType: .string), "Bold")
        XCTAssertEqual(
            pasteboard.data(forType: PasteboardTypeMap.html).flatMap { String(data: $0, encoding: .utf8) },
            "<b>Bold</b>"
        )
        XCTAssertEqual(pasteboard.data(forType: PasteboardTypeMap.rtf), rtfBytes)
        XCTAssertEqual(receipt.signature, entry.contentHash)
    }

    func testSvgWritesFileUrlBytesAndText() throws {
        let writer = PasteboardWriter(pasteboard: pasteboard, temp: tempStore)
        let svgMarkup = "<svg xmlns=\"http://www.w3.org/2000/svg\"></svg>"
        let entry = Entry(
            id: EntryID(raw: 5),
            createdAt: Date(),
            payload: .svg(svgMarkup),
            isSensitive: false
        )

        _ = try writer.write(entry, plainOnly: false, imageIndex: nil)
        let item = try XCTUnwrap(pasteboard.pasteboardItems?.first)
        let fileURLString = try XCTUnwrap(item.string(forType: PasteboardTypeMap.fileURL))
        let fileURL = try XCTUnwrap(URL(string: fileURLString))
        XCTAssertEqual(fileURL.lastPathComponent, "clipboard.svg")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertEqual(item.data(forType: PasteboardTypeMap.svg), Data(svgMarkup.utf8))
        XCTAssertEqual(item.string(forType: PasteboardTypeMap.utf8PlainText), svgMarkup)
    }

    func testImageSetSingleIndex() throws {
        let writer = PasteboardWriter(pasteboard: pasteboard, temp: tempStore)
        let items = [
            ImageItem(data: Data([10, 20]), format: .png),
            ImageItem(data: Data([30, 40, 50]), format: .jpeg),
        ]
        let entry = Entry(
            id: EntryID(raw: 6),
            createdAt: Date(),
            payload: .imageSet(items),
            isSensitive: false
        )

        let receipt = try writer.write(entry, plainOnly: false, imageIndex: 1)
        XCTAssertEqual(pasteboard.pasteboardItems?.count, 1)
        XCTAssertEqual(pasteboard.data(forType: PasteboardTypeMap.jpeg), Data([30, 40, 50]))
        XCTAssertNil(pasteboard.data(forType: PasteboardTypeMap.png))
        XCTAssertEqual(receipt.signature, ContentHash.bytes("i", Data([30, 40, 50])))
    }

    func testImageSetAllUsesTempFiles() throws {
        let writer = PasteboardWriter(pasteboard: pasteboard, temp: tempStore)
        let items = [
            ImageItem(data: Data([1, 2]), format: .png),
            ImageItem(data: Data([3, 4]), format: .gif),
        ]
        let entry = Entry(
            id: EntryID(raw: 7),
            createdAt: Date(),
            payload: .imageSet(items),
            isSensitive: false
        )

        _ = try writer.write(entry, plainOnly: false, imageIndex: nil)
        let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL]
        XCTAssertEqual(urls?.map(\.lastPathComponent), ["001.png", "002.gif"])
    }

    func testSensitiveImageSetAllWritesInlineItems() throws {
        let writer = PasteboardWriter(pasteboard: pasteboard, temp: tempStore)
        let items = [
            ImageItem(data: Data([11, 22]), format: .png),
            ImageItem(data: Data([33, 44]), format: .webp),
        ]
        let entry = Entry(
            id: EntryID(raw: 8),
            createdAt: Date(),
            payload: .imageSet(items),
            isSensitive: true
        )

        _ = try writer.write(entry, plainOnly: false, imageIndex: nil)
        let pbItems = try XCTUnwrap(pasteboard.pasteboardItems)
        XCTAssertEqual(pbItems.count, 2)
        XCTAssertEqual(pbItems[0].data(forType: PasteboardTypeMap.png), Data([11, 22]))
        XCTAssertEqual(pbItems[1].data(forType: PasteboardTypeMap.webp), Data([33, 44]))
        // No temp files written for sensitive entry.
        let sclipDir = tempRoot.appendingPathComponent("sclip", isDirectory: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sclipDir.path))
    }

    func testReceiptChangeMatchesPasteboard() throws {
        let writer = PasteboardWriter(pasteboard: pasteboard, temp: tempStore)
        let before = pasteboard.changeCount
        let entry = Entry(
            id: EntryID(raw: 9),
            createdAt: Date(),
            payload: .text("receipt check"),
            isSensitive: false
        )

        let receipt = try writer.write(entry, plainOnly: false, imageIndex: nil)
        XCTAssertEqual(receipt.change, pasteboard.changeCount)
        XCTAssertGreaterThan(receipt.change, before)
        XCTAssertEqual(receipt.signature, entry.contentHash)
    }
}
