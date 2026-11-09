import Foundation
import SclipCore
import SclipPlatform
import XCTest

final class FileTempStoreTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("sclip-temp-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        tempRoot = nil
        try super.tearDownWithError()
    }

    func testMaterializeSvgWritesClipboardSvg() throws {
        let store = FileTempStore(root: tempRoot) { _ in false }
        let entry = Entry(
            id: EntryID(raw: 7),
            createdAt: Date(timeIntervalSince1970: 0),
            payload: .svg("<svg></svg>"),
            isSensitive: false
        )

        let urls = try store.materialize(entry)
        XCTAssertEqual(urls.count, 1)
        let url = try XCTUnwrap(urls.first)
        XCTAssertEqual(url.lastPathComponent, "clipboard.svg")
        XCTAssertTrue(url.path.contains("/sclip/e7/clipboard.svg"))
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "<svg></svg>")
    }

    func testImageSetWrites001Sequence() throws {
        let store = FileTempStore(root: tempRoot) { _ in false }
        let items = [
            ImageItem(data: Data([1, 2]), format: .png),
            ImageItem(data: Data([3, 4]), format: .jpeg),
            ImageItem(data: Data([5, 6]), format: .webp),
        ]
        let entry = Entry(
            id: EntryID(raw: 12),
            createdAt: Date(timeIntervalSince1970: 0),
            payload: .imageSet(items),
            isSensitive: false
        )

        let urls = try store.materialize(entry)
        XCTAssertEqual(urls.map(\.lastPathComponent), ["001.png", "002.jpg", "003.webp"])
        XCTAssertEqual(try Data(contentsOf: urls[0]), Data([1, 2]))
        XCTAssertEqual(try Data(contentsOf: urls[1]), Data([3, 4]))
        XCTAssertEqual(try Data(contentsOf: urls[2]), Data([5, 6]))
    }

    func testSensitiveEntryIsNeverMaterialized() {
        let store = FileTempStore(root: tempRoot) { _ in false }
        let entry = Entry(
            id: EntryID(raw: 99),
            createdAt: Date(timeIntervalSince1970: 0),
            payload: .svg("<svg/>"),
            isSensitive: true
        )

        XCTAssertThrowsError(try store.materialize(entry))
        let sclipDir = tempRoot.appendingPathComponent("sclip", isDirectory: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sclipDir.path))
    }

    func testDeleteRemovesOnlyThatEntry() throws {
        let store = FileTempStore(root: tempRoot) { _ in false }
        let e1 = Entry(id: EntryID(raw: 1), createdAt: Date(), payload: .svg("<svg/>"), isSensitive: false)
        let e2 = Entry(id: EntryID(raw: 2), createdAt: Date(), payload: .pdf(Data([0x25])), isSensitive: false)

        let u1 = try XCTUnwrap(try store.materialize(e1).first)
        let u2 = try XCTUnwrap(try store.materialize(e2).first)
        XCTAssertTrue(FileManager.default.fileExists(atPath: u1.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: u2.path))

        store.delete(e1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: u1.deletingLastPathComponent().path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: u2.path))
    }

    func testPruneAllRemovesEverything() throws {
        let store = FileTempStore(root: tempRoot) { _ in false }
        let e1 = Entry(id: EntryID(raw: 1), createdAt: Date(), payload: .svg("<svg/>"), isSensitive: false)
        let e2 = Entry(id: EntryID(raw: 2), createdAt: Date(), payload: .pdf(Data([0x25])), isSensitive: false)
        _ = try store.materialize(e1)
        _ = try store.materialize(e2)

        store.pruneAll()
        let sclipDir = tempRoot.appendingPathComponent("sclip", isDirectory: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sclipDir.path))
    }

    func testEntryStillOnPasteboardIsNotDeleted() throws {
        let activeEntry = Entry(
            id: EntryID(raw: 5),
            createdAt: Date(),
            payload: .svg("<svg/>"),
            isSensitive: false
        )
        let store = FileTempStore(root: tempRoot) { entry in
            entry.id == activeEntry.id
        }

        let url = try XCTUnwrap(try store.materialize(activeEntry).first)
        store.delete(activeEntry)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }
}
