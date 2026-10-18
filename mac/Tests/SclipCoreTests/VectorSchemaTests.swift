import XCTest

/// `spec/vectors/` şema kapısı: dosyalar çözülür, adlar benzersiz, fixture'lar var, asgari sayılar
/// tutar, sapma etiketleri izinli kümede, `gen` tanımları geçerli. Davranışı değil şekli denetler;
/// davranış Task 10–15 koşucularındadır.
final class VectorSchemaTests: XCTestCase {
    private static let caseKeys: Set<String> = ["name", "input", "expect", "deviation", "source", "rule"]
    private static let canonicalFormats: Set<String> = [
        "text/plain", "text/html", "text/rtf", "image/png", "image/jpeg", "image/gif",
        "image/webp", "image/svg+xml", "application/pdf",
    ]
    private static let entryKinds: Set<String> = [
        "text", "url", "color", "image", "imageSet", "svg", "files", "pdf", "richText",
    ]
    /// Bayt girdisi üst sınırı: koşucuların belleğini korur (en büyük geçerli vaka 150 MiB bütçe).
    private static let maxGenBytes = 256 << 20

    // MARK: - Çözme ve sayılar

    func testEveryFileDecodes() throws {
        XCTAssertNoThrow(try VectorLoader.detectCases())
        XCTAssertNoThrow(try VectorLoader.classifyCases())
        XCTAssertNoThrow(try VectorLoader.svgSanitizeCases())
        XCTAssertNoThrow(try VectorLoader.hashCases())
        XCTAssertNoThrow(try VectorLoader.searchFile())
        XCTAssertNoThrow(try VectorLoader.historyCases())
    }

    func testMinimumCaseCounts() throws {
        XCTAssertGreaterThanOrEqual(try VectorLoader.detectCases().count, 60, "detect")
        XCTAssertGreaterThanOrEqual(try VectorLoader.classifyCases().count, 40, "classify")
        XCTAssertGreaterThanOrEqual(try VectorLoader.svgSanitizeCases().count, 20, "svg_sanitize")
        XCTAssertGreaterThanOrEqual(try VectorLoader.hashCases().count, 20, "hash")
        let search = try VectorLoader.searchFile()
        XCTAssertGreaterThanOrEqual(search.normalize.count + search.index.count, 30, "search")
        XCTAssertFalse(search.normalize.isEmpty, "search.normalize")
        XCTAssertFalse(search.index.isEmpty, "search.index")
        XCTAssertGreaterThanOrEqual(try VectorLoader.historyCases().count, 15, "history")
    }

    func testCaseNamesAreUniquePerFile() throws {
        let files: [(String, [String])] = [
            ("detect", try VectorLoader.detectCases().map(\.name)),
            ("classify", try VectorLoader.classifyCases().map(\.name)),
            ("svg_sanitize", try VectorLoader.svgSanitizeCases().map(\.name)),
            ("hash", try VectorLoader.hashCases().map(\.name)),
            ("search.index", try VectorLoader.searchFile().index.map(\.name)),
            ("search.normalize", try VectorLoader.searchFile().normalize.map(\.input)),
            ("history", try VectorLoader.historyCases().map(\.name)),
        ]
        for (file, names) in files {
            var seen = Set<String>()
            for name in names {
                // normalize vakaları adsızdır; anahtar `in` değeridir ve boş dize geçerli bir girdidir.
                if file != "search.normalize" { XCTAssertFalse(name.isEmpty, "\(file): boş ad") }
                XCTAssertTrue(seen.insert(name).inserted, "\(file): yinelenen ad \(name.debugDescription)")
            }
        }
    }

    // MARK: - Sapmalar ve kaynak

    private func allTags() throws -> [(file: String, name: String, dev: VectorDeviation?, src: VectorSource?)] {
        var out: [(String, String, VectorDeviation?, VectorSource?)] = []
        out += try VectorLoader.detectCases().map { ("detect", $0.name, $0.deviation, $0.source) }
        out += try VectorLoader.classifyCases().map { ("classify", $0.name, $0.deviation, $0.source) }
        out += try VectorLoader.svgSanitizeCases().map { ("svg_sanitize", $0.name, $0.deviation, $0.source) }
        out += try VectorLoader.hashCases().map { ("hash", $0.name, $0.deviation, $0.source) }
        let search = try VectorLoader.searchFile()
        out += search.normalize.map { ("search.normalize", $0.input, $0.deviation, $0.source) }
        out += search.index.map { ("search.index", $0.name, $0.deviation, $0.source) }
        out += try VectorLoader.historyCases().map { ("history", $0.name, $0.deviation, $0.source) }
        return out
    }

    /// İzinli küme çözmede zorlanır (enum); burada her zorunlu sapmanın beklenen dosyada en az bir
    /// vakası olduğu denetlenir.
    func testEveryRequiredDeviationIsCovered() throws {
        let required: [VectorDeviation: String] = [
            .e20: "history", .e21: "hash", .e22: "detect", .e23: "detect", .e24: "classify",
            .e25: "history", .e34: "classify", .e35: "hash", .s810: "svg_sanitize", .s83: "classify", .s82: "detect", .s86: "classify",
        ]
        let tags = try allTags()
        for (dev, file) in required {
            XCTAssertTrue(tags.contains { $0.file == file && $0.dev == dev }, "\(dev.rawValue) → \(file) vakası yok")
        }
    }

    func testDeviationRawValuesAreFromAllowedSet() throws {
        let allowed = Set(VectorDeviation.allCases.map(\.rawValue))
        XCTAssertEqual(allowed, ["E20", "E21", "E22", "E23", "E24", "E25", "E34", "E35", "S8.10", "S8.3", "S8.2", "S8.6"])
        for file in ["detect", "classify", "svg_sanitize", "hash", "history"] {
            for item in try rawArray("\(file).json") {
                if let dev = item["deviation"] {
                    XCTAssertTrue(allowed.contains(dev as? String ?? ""), "\(file): \(dev)")
                }
            }
        }
    }

    func testDeviationCasesAreManualAndClassifyIsManual() throws {
        for tag in try allTags() {
            if tag.dev != nil {
                XCTAssertEqual(tag.src, .manual, "\(tag.file)/\(tag.name): sapmalı vaka manual olmalı")
            }
            if tag.file == "classify" {
                XCTAssertEqual(tag.src, .manual, "classify/\(tag.name): source manual olmalı")
            } else if tag.dev == nil {
                XCTAssertNotNil(tag.src, "\(tag.file)/\(tag.name): source eksik")
            }
        }
    }

    func testRuleIdsExistInBehavior() throws {
        let behavior = try String(contentsOf: VectorLoader.spec("behavior.md"), encoding: .utf8)
        var rules: [(String, String)] = []
        rules += try VectorLoader.detectCases().compactMap { c in c.rule.map { (c.name, $0) } }
        rules += try VectorLoader.classifyCases().compactMap { c in c.rule.map { (c.name, $0) } }
        rules += try VectorLoader.svgSanitizeCases().compactMap { c in c.rule.map { (c.name, $0) } }
        rules += try VectorLoader.hashCases().compactMap { c in c.rule.map { (c.name, $0) } }
        rules += try VectorLoader.searchFile().index.compactMap { c in c.rule.map { (c.name, $0) } }
        rules += try VectorLoader.historyCases().compactMap { c in c.rule.map { (c.name, $0) } }
        for (name, rule) in rules {
            XCTAssertNotNil(rule.wholeMatch(of: /B-\d+\.\d+\.\d+/), "\(name): \(rule)")
            XCTAssertTrue(behavior.contains("**\(rule)**"), "\(name): \(rule) behavior.md'de yok")
        }
    }

    // MARK: - Bayt girdileri ve fixture'lar

    private func allByteInputs() throws -> [(String, ByteInput)] {
        var out: [(String, ByteInput)] = []
        out += try VectorLoader.svgSanitizeCases().map { ("svg/\($0.name)", $0.input) }
        for c in try VectorLoader.hashCases() {
            if let b = c.input.bytes { out.append(("hash/\(c.name)", b)) }
            for b in c.input.items ?? [] { out.append(("hash/\(c.name)", b)) }
        }
        func classifyInputs(_ ctx: String, _ input: ClassifyInput) -> [(String, ByteInput)] {
            var r = input.items.flatMap { $0.formats.values.map { (ctx, $0) } }
            for f in input.files ?? [] {
                if case .generated(_, let b) = f { r.append((ctx, b)) }
            }
            return r
        }
        for c in try VectorLoader.classifyCases() { out += classifyInputs("classify/\(c.name)", c.input) }
        for c in try VectorLoader.searchFile().index { out += classifyInputs("search/\(c.name)", c.entry) }
        return out.flatMap { ctx, input in input.flattened.map { (ctx, $0) } }
    }

    private func allFileRefs() throws -> [(String, FileRef)] {
        var out: [(String, FileRef)] = []
        for c in try VectorLoader.classifyCases() { out += (c.input.files ?? []).map { ("classify/\(c.name)", $0) } }
        for c in try VectorLoader.searchFile().index { out += (c.entry.files ?? []).map { ("search/\(c.name)", $0) } }
        return out
    }

    func testFixturePathsExist() throws {
        let fm = FileManager.default
        var paths: [(String, String)] = []
        for (ctx, input) in try allByteInputs() {
            if case .fixture(let p) = input { paths.append((ctx, p)) }
        }
        for (ctx, ref) in try allFileRefs() {
            if case .fixture(let p) = ref { paths.append((ctx, p)) }
        }
        XCTAssertFalse(paths.isEmpty, "hiç fixture referansı yok")
        for (ctx, path) in paths {
            XCTAssertTrue(path.hasPrefix("fixtures/"), "\(ctx): \(path) fixtures/ altında değil")
            XCTAssertFalse(path.contains(".."), "\(ctx): \(path)")
            var isDir: ObjCBool = false
            let exists = fm.fileExists(atPath: VectorLoader.vectors(path).path, isDirectory: &isDir)
            XCTAssertTrue(exists && !isDir.boolValue, "\(ctx): fixture yok: \(path)")
        }
    }

    func testRequiredFixturesExist() throws {
        let fm = FileManager.default
        let required = [
            "fake.txt", "empty.png", "tiny.png", "tiny.jpg", "tiny.gif", "tiny.webp",
            "malicious_svg/billion_laughs.svg", "malicious_svg/external_entity.svg",
            "malicious_svg/figma_like.svg", "malicious_svg/simple_icon.svg", "malicious_svg/xinclude.svg",
        ]
        for name in required {
            XCTAssertTrue(fm.fileExists(atPath: VectorLoader.vectors("fixtures/\(name)").path), name)
        }
        XCTAssertEqual(try ByteInput.fixture("fixtures/empty.png").byteCount(), 0, "empty.png 0 bayt olmalı")
    }

    func testGenAndRepeatSpecsAreValid() throws {
        for (ctx, input) in try allByteInputs() {
            switch input {
            case .gen(let spec):
                XCTAssertGreaterThanOrEqual(spec.size, 0, ctx)
                XCTAssertLessThanOrEqual(spec.size, Self.maxGenBytes, ctx)
                XCTAssertGreaterThanOrEqual(spec.seed, 0, ctx)
            case .repeated(let unit, let count):
                XCTAssertFalse(unit.isEmpty, ctx)
                XCTAssertGreaterThanOrEqual(count, 0, ctx)
                XCTAssertLessThanOrEqual(unit.utf8.count * count, Self.maxGenBytes, ctx)
            case .concat(let parts):
                XCTAssertFalse(parts.isEmpty, "\(ctx): boş concat")
            default:
                break
            }
        }
        for c in try VectorLoader.historyCases() {
            for op in c.ops where op.kind == .image || op.kind == .pdf {
                let spec = try XCTUnwrap(op.genSpec, "\(c.name): size/seed eksik")
                XCTAssertGreaterThan(spec.size, 0, c.name)
                XCTAssertLessThanOrEqual(spec.size, Self.maxGenBytes, c.name)
                XCTAssertGreaterThanOrEqual(spec.seed, 0, c.name)
            }
        }
    }

    func testGenFormulaIsPinned() {
        XCTAssertEqual([UInt8](GenSpec(size: 4, seed: 0).bytes()), [0, 1, 2, 3])
        XCTAssertEqual([UInt8](GenSpec(size: 3, seed: 1).bytes()), [31, 32, 33])
        XCTAssertEqual([UInt8](GenSpec(size: 2, seed: 9).bytes()), [23, 24])        // 279 & 0xFF
        XCTAssertEqual(GenSpec(size: 300, seed: 2).bytes()[256], 62)                 // periyot 256
    }

    func testSmallByteInputsResolve() throws {
        for (ctx, input) in try allByteInputs() where try input.byteCount() <= 1 << 20 {
            XCTAssertNoThrow(try input.data(), ctx)
        }
    }

    // MARK: - Dosya başına biçim

    func testNoUnknownKeys() throws {
        for file in ["detect", "svg_sanitize", "hash", "classify"] {
            for item in try rawArray("\(file).json") {
                assertKeys(item, Self.caseKeys, file)
            }
        }
        for item in try rawArray("detect.json") {
            assertKeys(item["expect"], ["kind", "uri", "normalized", "argb"], "detect.expect")
        }
        for item in try rawArray("hash.json") {
            assertKeys(item["input"], ["prefix", "text", "bytes", "items", "uris"], "hash.input")
        }
        for item in try rawArray("svg_sanitize.json") { assertKeys(item["expect"], ["safe"], "svg.expect") }
        let classifyExpectKeys: Set<String> = [
            "result", "kind", "preview", "hash", "text", "uri", "display", "imageCount", "hasRtf",
        ]
        for item in try rawArray("classify.json") {
            assertClassifyInputKeys(item["input"], "classify.input")
            assertKeys(item["expect"], classifyExpectKeys, "classify.expect")
        }
        let search = try XCTUnwrap(rawObject("search.json"))
        assertKeys(search, ["normalize", "index"], "search")
        for item in search["normalize"] as? [[String: Any]] ?? [] {
            assertKeys(item, ["in", "out", "deviation", "source", "rule"], "search.normalize")
        }
        for item in search["index"] as? [[String: Any]] ?? [] {
            assertKeys(item, ["name", "entry", "expect", "deviation", "source", "rule"], "search.index")
            assertClassifyInputKeys(item["entry"], "search.index.entry")
        }
        for item in try rawArray("history.json") {
            let ctx = "history/\(item["name"] ?? "?")"
            assertKeys(item, ["name", "maxItems", "budgetBytes", "ops", "expect", "deviation", "source", "rule"], ctx)
            assertKeys(item["expect"], ["order", "evicted", "results"], ctx)
            for op in item["ops"] as? [[String: Any]] ?? [] {
                assertKeys(op, ["op", "ref", "kind", "text", "repeat", "count", "size", "seed", "n"], ctx)
            }
        }
    }

    func testDetectExpectationsAreConsistent() throws {
        for c in try VectorLoader.detectCases() {
            let e = c.expect
            switch e.kind {
            case .url, .email, .phone:
                XCTAssertNotNil(e.uri, "\(c.name): uri eksik")
                XCTAssertNil(e.normalized, c.name)
                XCTAssertNil(e.argb, c.name)
                if e.kind == .email { XCTAssertTrue(e.uri?.hasPrefix("mailto:") == true, c.name) }
                if e.kind == .phone { XCTAssertNotNil(e.uri?.wholeMatch(of: /tel:\+[0-9]{8,15}/), c.name) }
            case .color:
                XCTAssertNil(e.uri, c.name)
                let normalized = try XCTUnwrap(e.normalized, "\(c.name): normalized eksik")
                XCTAssertEqual(normalized, normalized.lowercased(), "\(c.name): normalized küçük harf olmalı")
                XCTAssertNotNil(e.argb?.wholeMatch(of: /0x[0-9A-F]{8}/), "\(c.name): argb biçimi")
            case .svg, .none:
                XCTAssertNil(e.uri, c.name)
                XCTAssertNil(e.normalized, c.name)
                XCTAssertNil(e.argb, c.name)
            }
        }
    }

    func testHashInputsMatchPrefixAndExpectShape() throws {
        for c in try VectorLoader.hashCases() {
            let i = c.input
            let fields = [i.text != nil, i.bytes != nil, i.items != nil, i.uris != nil].filter { $0 }.count
            XCTAssertEqual(fields, 1, "\(c.name): tam bir yük alanı olmalı")
            switch i.prefix {
            case .t, .u, .s, .c, .r:
                XCTAssertNotNil(i.text, c.name)
                XCTAssertNotNil(c.expect.wholeMatch(of: /[tuscr]:[0-9a-f]{16}/), "\(c.name): \(c.expect)")
                XCTAssertTrue(c.expect.hasPrefix(i.prefix.rawValue + ":"), c.name)
            case .f:
                XCTAssertNotNil(i.uris, c.name)
                XCTAssertNotNil(c.expect.wholeMatch(of: /f:[0-9a-f]{16}/), "\(c.name): \(c.expect)")
            case .i, .p:
                let bytes = try XCTUnwrap(i.bytes, c.name)
                let match = try XCTUnwrap(c.expect.wholeMatch(of: /([ip]):([0-9]+):([0-9a-f]{16})/), "\(c.name): \(c.expect)")
                XCTAssertEqual(String(match.1), i.prefix.rawValue, c.name)
                XCTAssertEqual(Int(match.2), try bytes.byteCount(), "\(c.name): uzunluk alanı")
            case .imageSet:
                let items = try XCTUnwrap(i.items, c.name)
                XCTAssertGreaterThanOrEqual(items.count, 2, c.name)
                let match = try XCTUnwrap(c.expect.wholeMatch(of: /is:([0-9]+):[0-9a-f]{16}/), "\(c.name): \(c.expect)")
                XCTAssertEqual(Int(match.1), items.count, "\(c.name): adet alanı")
            }
        }
    }

    func testClassifyCasesAreWellFormed() throws {
        let inputs: [(String, ClassifyInput)] =
            try VectorLoader.classifyCases().map { ("classify/\($0.name)", $0.input) }
            + VectorLoader.searchFile().index.map { ("search/\($0.name)", $0.entry) }
        for (ctx, input) in inputs {
            XCTAssertFalse(input.items.isEmpty && (input.files ?? []).isEmpty, "\(ctx): boş girdi")
            for item in input.items {
                for key in item.formats.keys {
                    XCTAssertTrue(Self.canonicalFormats.contains(key), "\(ctx): bilinmeyen biçim \(key)")
                }
            }
            for flag in input.flags ?? [] {
                XCTAssertTrue(["concealed", "transient"].contains(flag), "\(ctx): bayrak \(flag)")
            }
            for ref in input.files ?? [] {
                if case .generated(let name, _) = ref {
                    XCTAssertFalse(name.contains("/") || name.contains("\\") || name.isEmpty, "\(ctx): \(name)")
                }
            }
        }
        for c in try VectorLoader.classifyCases() {
            let e = c.expect
            if e.result == .entry {
                let kind = try XCTUnwrap(e.kind, "\(c.name): kind eksik")
                XCTAssertTrue(Self.entryKinds.contains(kind), "\(c.name): kind \(kind)")
                XCTAssertNotNil(e.preview, "\(c.name): preview eksik")
                if kind == "imageSet" { XCTAssertGreaterThanOrEqual(e.imageCount ?? 0, 2, c.name) }
            } else {
                XCTAssertNil(e.kind, c.name)
                XCTAssertNil(e.preview, c.name)
                XCTAssertNil(e.hash, c.name)
            }
        }
    }

    func testHistoryCasesAreWellFormed() throws {
        for c in try VectorLoader.historyCases() {
            // Başlangıç boyutu yalnız ayarın izinli değerlerinden (B-6.6.4); kenar durumlar setMax ile kurulur.
            XCTAssertTrue([10, 30, 50, 100].contains(c.maxItems), "\(c.name): maxItems \(c.maxItems) izinli değil")
            if let budget = c.budgetBytes { XCTAssertGreaterThan(budget, 0, c.name) }
            var refs = Set<String>()
            var adds = 0
            for op in c.ops {
                switch op.op {
                case .add:
                    adds += 1
                    let ref = try XCTUnwrap(op.ref, "\(c.name): add ref'siz")
                    refs.insert(ref)
                    switch try XCTUnwrap(op.kind, "\(c.name): add kind'sız") {
                    case .text:
                        XCTAssertNotNil(op.textValue, "\(c.name): text ya da repeat+count gerekli")
                        XCTAssertNil(op.size, c.name)
                    case .image, .pdf:
                        XCTAssertNotNil(op.genSpec, "\(c.name): size+seed gerekli")
                        XCTAssertNil(op.text, c.name)
                    }
                case .touch, .remove:
                    XCTAssertNotNil(op.ref, "\(c.name): \(op.op) ref'siz")
                case .setMax:
                    let n = try XCTUnwrap(op.n, "\(c.name): setMax n'siz")
                    XCTAssertGreaterThan(n, 0, "\(c.name): setMax n > 0 olmalı")
                case .clear:
                    XCTAssertNil(op.ref, c.name)
                }
            }
            if let results = c.expect.results {
                XCTAssertEqual(results.count, adds, "\(c.name): results sayısı add sayısına eşit olmalı")
            }
            for ref in c.expect.order + c.expect.evicted {
                XCTAssertTrue(refs.contains(ref), "\(c.name): bilinmeyen ref \(ref)")
            }
            XCTAssertEqual(Set(c.expect.order).count, c.expect.order.count, "\(c.name): order'da tekrar")
        }
    }

    // MARK: - Yardımcılar

    private func rawJSON(_ file: String) throws -> Any {
        try JSONSerialization.jsonObject(with: Data(contentsOf: VectorLoader.vectors(file)), options: [.fragmentsAllowed])
    }

    private func rawArray(_ file: String) throws -> [[String: Any]] {
        try XCTUnwrap(try rawJSON(file) as? [[String: Any]], "\(file): üst düzey dizi değil")
    }

    private func rawObject(_ file: String) throws -> [String: Any]? {
        try rawJSON(file) as? [String: Any]
    }

    private func assertKeys(_ object: Any?, _ allowed: Set<String>, _ ctx: String,
                            file: StaticString = #filePath, line: UInt = #line) {
        guard let dict = object as? [String: Any] else {
            XCTFail("\(ctx): nesne değil", file: file, line: line)
            return
        }
        let unknown = Set(dict.keys).subtracting(allowed)
        XCTAssertTrue(unknown.isEmpty, "\(ctx): bilinmeyen anahtar \(unknown.sorted())", file: file, line: line)
    }

    private func assertClassifyInputKeys(_ object: Any?, _ ctx: String) {
        assertKeys(object, ["items", "files", "flags"], ctx)
        let items = (object as? [String: Any])?["items"] as? [[String: Any]] ?? []
        for item in items { assertKeys(item, ["formats"], ctx) }
    }
}
