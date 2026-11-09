import AppKit
import SclipCore
import SclipUI
import XCTest

@MainActor
final class ThumbnailCacheTests: XCTestCase {
    private let sampleSvg = """
    <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16">
      <rect width="16" height="16" fill="#ff0000"/>
    </svg>
    """

    private func makeSamplePngData() throws -> Data {
        let image = NSImage(size: NSSize(width: 8, height: 8))
        image.lockFocus()
        NSColor.systemRed.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 8, height: 8)).fill()
        image.unlockFocus()
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let rep = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    }

    func testRemoveEvictsAllCachedThumbnailsForEntry() {
        let cache = ThumbnailCache(countLimit: 16)
        let id1 = EntryID(raw: 1)
        let id2 = EntryID(raw: 2)

        cache.loadSvgThumbnail(entryID: id1, xml: sampleSvg, scale: 1.0) { _ in }
        cache.loadSvgThumbnail(entryID: id1, xml: sampleSvg, scale: 2.0) { _ in }
        cache.loadSvgThumbnail(entryID: id2, xml: sampleSvg, scale: 2.0) { _ in }

        XCTAssertNotNil(cache.cachedImage(entryID: id1, scale: 1.0))
        XCTAssertNotNil(cache.cachedImage(entryID: id1, scale: 2.0))
        XCTAssertNotNil(cache.cachedImage(entryID: id2, scale: 2.0))

        cache.remove(entryID: id1)

        XCTAssertNil(cache.cachedImage(entryID: id1, scale: 1.0))
        XCTAssertNil(cache.cachedImage(entryID: id1, scale: 2.0))
        XCTAssertNotNil(cache.cachedImage(entryID: id2, scale: 2.0))
    }

    func testClearEvictsAllCachedThumbnails() {
        let cache = ThumbnailCache(countLimit: 16)
        let id1 = EntryID(raw: 10)
        let id2 = EntryID(raw: 20)

        cache.loadSvgThumbnail(entryID: id1, xml: sampleSvg, scale: 2.0) { _ in }
        cache.loadSvgThumbnail(entryID: id2, xml: sampleSvg, scale: 2.0) { _ in }
        XCTAssertNotNil(cache.cachedImage(entryID: id1, scale: 2.0))
        XCTAssertNotNil(cache.cachedImage(entryID: id2, scale: 2.0))

        cache.clear()

        XCTAssertNil(cache.cachedImage(entryID: id1, scale: 2.0))
        XCTAssertNil(cache.cachedImage(entryID: id2, scale: 2.0))
    }

    func testClearDuringInFlightAsyncDecodeDoesNotRepopulateCache() throws {
        let cache = ThumbnailCache(countLimit: 16)
        let id = EntryID(raw: 30)
        let pngData = try makeSamplePngData()

        let exp = expectation(description: "in-flight decode completion after clear")
        var receivedImage: NSImage?
        cache.loadThumbnail(entryID: id, index: 0, data: pngData, scale: 2.0) { img in
            receivedImage = img
            exp.fulfill()
        }
        // Clear immediately while background decode is in-flight.
        cache.clear()

        wait(for: [exp], timeout: 2.0)
        XCTAssertNil(receivedImage)
        XCTAssertNil(cache.cachedImage(entryID: id, index: 0, scale: 2.0))
    }

    func testRemoveDuringInFlightAsyncDecodeDoesNotRepopulateCache() throws {
        let cache = ThumbnailCache(countLimit: 16)
        let id = EntryID(raw: 40)
        let pngData = try makeSamplePngData()

        let exp = expectation(description: "in-flight decode completion after remove")
        var receivedImage: NSImage?
        cache.loadThumbnail(entryID: id, index: 0, data: pngData, scale: 2.0) { img in
            receivedImage = img
            exp.fulfill()
        }
        // Remove entry immediately while background decode is in-flight.
        cache.remove(entryID: id)

        wait(for: [exp], timeout: 2.0)
        XCTAssertNil(receivedImage)
        XCTAssertNil(cache.cachedImage(entryID: id, index: 0, scale: 2.0))
    }
}
