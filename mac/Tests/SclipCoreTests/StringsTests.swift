import XCTest
@testable import SclipCore

final class StringsTests: XCTestCase {
    private var catalogURL: URL { VectorLoader.spec("strings.tr.json") }

    private func rawCatalog() throws -> [String: String] {
        let data = try Data(contentsOf: catalogURL)
        return try JSONDecoder().decode([String: String].self, from: data)
    }

    private func writeTemp(_ json: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "sclip-strings-\(UUID().uuidString).json")
        try Data(json.utf8).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    // MARK: - Katalog bütünlüğü

    func testEveryKeyExistsInJSON() throws {
        let s = try Strings.load(from: catalogURL)
        for key in StringKey.allCases {
            XCTAssertFalse(s[key].isEmpty, key.rawValue)
            XCTAssertNotEqual(s[key], key.rawValue, "fallback döndü: \(key.rawValue)")
        }
    }

    func testNoUnusedKeysInJSON() throws {
        let jsonKeys = Set(try rawCatalog().keys)
        let enumKeys = Set(StringKey.allCases.map(\.rawValue))
        XCTAssertEqual(jsonKeys.subtracting(enumKeys), [], "JSON'da olup StringKey'de olmayan")
        XCTAssertEqual(enumKeys.subtracting(jsonKeys), [], "StringKey'de olup JSON'da olmayan")
    }

    func testRawValuesAreLowercaseDotSnake() {
        let pattern = /^[a-z0-9]+(_[a-z0-9]+)*(\.[a-z0-9]+(_[a-z0-9]+)*)+$/
        for key in StringKey.allCases {
            XCTAssertNotNil(key.rawValue.wholeMatch(of: pattern), key.rawValue)
        }
    }

    func testCaseNamesAreLowerCamelCaseOfRawValue() {
        for key in StringKey.allCases {
            let parts = key.rawValue.split(whereSeparator: { $0 == "." || $0 == "_" })
            let expected = parts.enumerated().map { index, part in
                index == 0 ? String(part) : part.prefix(1).uppercased() + part.dropFirst()
            }.joined()
            XCTAssertEqual(String(describing: key), expected, key.rawValue)
        }
    }

    func testPlaceholdersAreFromAllowedSet() throws {
        let allowed: Set<String> = [
            "visible", "total", "query", "preview", "n", "k", "size", "format", "time", "names",
        ]
        for (key, value) in try rawCatalog() {
            for match in value.matches(of: /\{([a-z]+)\}/) {
                XCTAssertTrue(allowed.contains(String(match.1)), "\(key): {\(match.1)}")
            }
        }
    }

    func testRemovedTrueDarkSettingHasNoStrings() throws {
        for (key, value) in try rawCatalog() {
            XCTAssertFalse(value.contains("OLED"), key)
            XCTAssertFalse(key.contains("true_dark"), key)
        }
    }

    // MARK: - Biçimlendirme

    func testFormatSubstitutesPlaceholders() throws {
        let s = try Strings.load(from: catalogURL)
        XCTAssertEqual(
            s.format(.clearAllBodyFiltered, ["visible": "3", "total": "27"]),
            "Filtre aktif: görünen 3 değil, tümü (27) silinecek. Emin misin?"
        )
    }

    func testFormatLeavesUnknownPlaceholdersAsIs() throws {
        let s = try Strings.load(from: catalogURL)
        XCTAssertEqual(
            s.format(.clearAllBodyFiltered, ["visible": "3"]),
            "Filtre aktif: görünen 3 değil, tümü ({total}) silinecek. Emin misin?"
        )
    }

    func testFormatReplacesEveryOccurrenceAndIgnoresExtraArgs() throws {
        let url = try writeTemp(#"{"search.empty.no_results": "{query} / {query}"}"#)
        let s = try Strings.load(from: url)
        XCTAssertEqual(s.format(.searchEmptyNoResults, ["query": "a", "x": "y"]), "a / a")
    }

    func testFormatDoesNotRecurseIntoSubstitutedValues() throws {
        let url = try writeTemp(#"{"search.empty.no_results": "'{query}' {n}"}"#)
        let s = try Strings.load(from: url)
        XCTAssertEqual(
            s.format(.searchEmptyNoResults, ["query": "{n}", "n": "5"]),
            "'{n}' 5"
        )
    }

    // MARK: - Yükleme ve hata yolları

    func testMissingKeyFallsBackToRawValue() throws {
        let s = try Strings.load(from: try writeTemp("{}"))
        XCTAssertEqual(s[.clearAllTitle], StringKey.clearAllTitle.rawValue)
        XCTAssertEqual(s.format(.clearAllTitle, [:]), StringKey.clearAllTitle.rawValue)
    }

    func testLoadThrowsOnNonStringValues() throws {
        let url = try writeTemp(#"{"clear_all.title": 1}"#)
        XCTAssertThrowsError(try Strings.load(from: url))
    }

    func testLoadThrowsOnMissingFile() {
        let url = FileManager.default.temporaryDirectory.appending(path: "sclip-yok-\(UUID()).json")
        XCTAssertThrowsError(try Strings.load(from: url))
    }
}
