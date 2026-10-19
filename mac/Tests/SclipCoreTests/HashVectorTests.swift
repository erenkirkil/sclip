import XCTest
@testable import SclipCore

final class HashVectorTests: XCTestCase {
    func testHashVectors() throws {
        let cases = try VectorLoader.hashCases()
        XCTAssertFalse(cases.isEmpty)
        for c in cases {
            let input = c.input
            let actual: String
            switch input.prefix {
            case .t, .u, .s, .c, .r:
                let text = try XCTUnwrap(input.text, c.name)
                actual = ContentHash.text(input.prefix.rawValue, text)
            case .f:
                let uris = try XCTUnwrap(input.uris, c.name)
                actual = ContentHash.text("f", uris.joined(separator: "|"))
            case .i, .p:
                let bytes = try XCTUnwrap(input.bytes, c.name).data()
                actual = ContentHash.bytes(input.prefix.rawValue, bytes)
            case .imageSet:
                let items = try XCTUnwrap(input.items, c.name)
                    .map { ImageItem(data: try $0.data(), format: .png) }
                actual = ContentHash.imageSet(items)
            }
            XCTAssertEqual(actual, c.expect, c.name)
        }
    }

    /// `Payload` üzerinden hash (of) vektörlerle aynı sonucu vermeli.
    func testPayloadHashMatchesVectors() throws {
        for c in try VectorLoader.hashCases() {
            let input = c.input
            let payload: Payload
            switch input.prefix {
            case .t: payload = .text(try XCTUnwrap(input.text))
            case .u: payload = .url(original: try XCTUnwrap(input.text), uri: input.text ?? "", display: "")
            case .s: payload = .svg(try XCTUnwrap(input.text))
            case .c: payload = .color(original: "", normalized: try XCTUnwrap(input.text), argb: 0)
            case .r:
                let parts = try XCTUnwrap(input.text).split(separator: "\u{0}", maxSplits: 1, omittingEmptySubsequences: false)
                payload = .richText(plain: String(parts[0]), html: String(parts[1]), rtf: Data([1, 2, 3]))
            case .f: payload = .files(try XCTUnwrap(input.uris).map { URL(string: $0)! })
            case .i:
                payload = .image(ImageItem(data: try XCTUnwrap(input.bytes).data(), format: .png))
            case .p: payload = .pdf(try XCTUnwrap(input.bytes).data())
            case .imageSet:
                payload = .imageSet(try XCTUnwrap(input.items).map { ImageItem(data: try $0.data(), format: .jpeg) })
            }
            XCTAssertEqual(ContentHash.of(payload), c.expect, c.name)
        }
    }
}
