import Foundation

// spec/vectors/*.json şema tipleri. Bağlayıcı tanım: spec/vectors/README.md.
// Task 10–15 koşucuları bu tipleri yeniden kullanır; C++ tarafı (Plan 2) aynı JSON'u okur.

/// Kahinden bilinçli sapma etiketleri (`behavior.md` → "Bilinçli sapmalar").
enum VectorDeviation: String, Codable, CaseIterable, Sendable {
    case e20 = "E20", e21 = "E21", e22 = "E22", e23 = "E23", e24 = "E24"
    case e25 = "E25", e34 = "E34", e35 = "E35", s810 = "S8.10", s83 = "S8.3", s82 = "S8.2", s86 = "S8.6"
}

/// Beklentinin kaynağı: Dart kahini ya da elle yazılmış.
enum VectorSource: String, Codable, Sendable {
    case oracle, manual
}

/// Deterministik bayt üreteci: bayt i = (seed * 31 + i) & 0xFF.
struct GenSpec: Codable, Equatable, Sendable {
    let size: Int
    let seed: Int

    /// `size` baytı üretir. Aynı (size, seed) her zaman aynı baytları verir.
    func bytes() -> Data {
        let base = seed &* 31
        // Periyot 256: tek periyot üretilip katlanarak çoğaltılır (debug derlemede 25 MiB'ı bayt bayt
        // yazmak vaka başına saniyeler sürüyordu). Çıktı bayt bayt üretimle aynıdır.
        let period = Data((0..<min(max(size, 0), 256)).map { UInt8(truncatingIfNeeded: base &+ $0) })
        return Data.tiled(period, toCount: max(size, 0))
    }
}

extension Data {
    /// `unit`'i art arda ekleyerek tam `count` bayt üretir (son kopya kesilebilir); katlamayla O(log n) ekleme.
    static func tiled(_ unit: Data, toCount count: Int) -> Data {
        guard count > 0, !unit.isEmpty else { return Data() }
        var out = Data(capacity: count)
        out.append(unit.prefix(count))
        while out.count < count {
            out.append(out.prefix(Swift.min(out.count, count - out.count)))
        }
        return out
    }
}

enum VectorSchemaError: Error, CustomStringConvertible {
    case invalid(String)
    var description: String {
        switch self {
        case .invalid(let message): return message
        }
    }
}

/// Bayt girdisi: `{"utf8"}` | `{"b64"}` | `{"fixture"}` | `{"gen"}` | `{"concat"}` | `{"repeat","count"}`.
indirect enum ByteInput: Equatable, Sendable {
    case utf8(String)
    case b64(String)
    case fixture(String)
    case gen(GenSpec)
    case concat([ByteInput])
    case repeated(String, count: Int)

    /// Somut baytlar. `fixture` yolu `spec/vectors/` altına çözülür.
    func data() throws -> Data {
        switch self {
        case .utf8(let s):
            return Data(s.utf8)
        case .b64(let s):
            guard let d = Data(base64Encoded: s) else {
                throw VectorSchemaError.invalid("geçersiz base64: \(s.prefix(32))")
            }
            return d
        case .fixture(let path):
            return try Data(contentsOf: VectorLoader.vectors(path))
        case .gen(let spec):
            return spec.bytes()
        case .concat(let parts):
            var out = Data()
            for part in parts { out.append(try part.data()) }
            return out
        case .repeated(let unit, let count):
            let one = Data(unit.utf8)
            return Data.tiled(one, toCount: one.count * max(count, 0))
        }
    }

    /// Bayt üretmeden boyut tahmini (fixture için dosya boyutu).
    func byteCount() throws -> Int {
        switch self {
        case .utf8(let s): return s.utf8.count
        case .b64: return try data().count
        case .fixture(let path):
            let attrs = try FileManager.default.attributesOfItem(atPath: VectorLoader.vectors(path).path)
            return (attrs[.size] as? NSNumber)?.intValue ?? 0
        case .gen(let spec): return spec.size
        case .concat(let parts): return try parts.reduce(0) { $0 + (try $1.byteCount()) }
        case .repeated(let unit, let count): return unit.utf8.count * count
        }
    }

    /// Ağaçtaki tüm alt girdiler (kendisi dahil).
    var flattened: [ByteInput] {
        if case .concat(let parts) = self { return [self] + parts.flatMap(\.flattened) }
        return [self]
    }
}

extension ByteInput: Decodable {
    private struct Key: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        let keys = Set(c.allKeys.map(\.stringValue))
        func key(_ s: String) -> Key { Key(stringValue: s) }
        func fail(_ why: String) -> Error {
            DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: why))
        }
        switch keys {
        case ["utf8"]: self = .utf8(try c.decode(String.self, forKey: key("utf8")))
        case ["b64"]: self = .b64(try c.decode(String.self, forKey: key("b64")))
        case ["fixture"]: self = .fixture(try c.decode(String.self, forKey: key("fixture")))
        case ["gen"]: self = .gen(try c.decode(GenSpec.self, forKey: key("gen")))
        case ["concat"]: self = .concat(try c.decode([ByteInput].self, forKey: key("concat")))
        case ["repeat", "count"]:
            self = .repeated(
                try c.decode(String.self, forKey: key("repeat")),
                count: try c.decode(Int.self, forKey: key("count"))
            )
        default:
            throw fail("bayt girdisi tek biçim içermeli, bulunan anahtarlar: \(keys.sorted())")
        }
    }
}

/// Ortak vaka zarfı.
struct VectorCase<Input: Decodable & Sendable, Expect: Decodable & Sendable>: Decodable, Sendable {
    let name: String
    let input: Input
    let expect: Expect
    let deviation: VectorDeviation?
    let source: VectorSource?
    let rule: String?
}

// MARK: - detect.json

enum DetectKind: String, Codable, Sendable { case url, color, email, phone, svg, none }

struct DetectExpect: Codable, Equatable, Sendable {
    let kind: DetectKind
    let uri: String?
    let normalized: String?
    let argb: String?   // "0xAARRGGBB"
}

typealias DetectCase = VectorCase<String, DetectExpect>

// MARK: - hash.json

enum HashPrefix: String, Codable, CaseIterable, Sendable {
    case t, u, s, c, r, f, i, p
    case imageSet = "is"
}

struct HashInput: Decodable, Sendable {
    let prefix: HashPrefix
    let text: String?
    let bytes: ByteInput?
    let items: [ByteInput]?
    let uris: [String]?
}

typealias HashCase = VectorCase<HashInput, String>

// MARK: - svg_sanitize.json

struct SvgExpect: Codable, Equatable, Sendable { let safe: Bool }

typealias SvgSanitizeCase = VectorCase<ByteInput, SvgExpect>

// MARK: - classify.json

/// `files` öğesi: `spec/vectors/` altına göre fixture yolu ya da koşucunun geçici dizine
/// `name` adıyla yazacağı üretilmiş dosya.
enum FileRef: Decodable, Equatable, Sendable {
    case fixture(String)
    case generated(name: String, bytes: ByteInput)

    private enum Keys: String, CodingKey { case name, bytes }

    init(from decoder: Decoder) throws {
        if let path = try? decoder.singleValueContainer().decode(String.self) {
            self = .fixture(path)
            return
        }
        let c = try decoder.container(keyedBy: Keys.self)
        self = .generated(
            name: try c.decode(String.self, forKey: .name),
            bytes: try c.decode(ByteInput.self, forKey: .bytes)
        )
    }
}

struct ClassifyItem: Decodable, Sendable {
    /// Kanonik biçim anahtarı (`text/plain`, `image/png`, …) → bayt.
    let formats: [String: ByteInput]
}

struct ClassifyInput: Decodable, Sendable {
    let items: [ClassifyItem]
    let files: [FileRef]?
    let flags: [String]?
}

enum ClassifyResult: String, Codable, Sendable { case entry, drop, none }

struct ClassifyExpect: Decodable, Sendable {
    let result: ClassifyResult
    let kind: String?
    let preview: String?
    let hash: String?
    let text: String?
    let uri: String?
    let display: String?
    let imageCount: Int?
    let hasRtf: Bool?
}

typealias ClassifyCase = VectorCase<ClassifyInput, ClassifyExpect>

// MARK: - search.json

struct NormalizeCase: Decodable, Sendable {
    let input: String
    let output: String
    let deviation: VectorDeviation?
    let source: VectorSource?
    let rule: String?

    private enum CodingKeys: String, CodingKey {
        case input = "in", output = "out", deviation, source, rule
    }
}

struct IndexCase: Decodable, Sendable {
    let name: String
    let entry: ClassifyInput
    let expect: String
    let deviation: VectorDeviation?
    let source: VectorSource?
    let rule: String?
}

struct SearchFile: Decodable, Sendable {
    let normalize: [NormalizeCase]
    let index: [IndexCase]
}

// MARK: - history.json

enum HistoryOpKind: String, Codable, Sendable { case add, touch, remove, clear, setMax }
enum HistoryEntryKind: String, Codable, Sendable { case text, image, pdf }
enum HistoryAddResult: String, Codable, Sendable { case added, duplicateHead, rejected }

struct HistoryOp: Decodable, Sendable {
    let op: HistoryOpKind
    let ref: String?
    let kind: HistoryEntryKind?
    let text: String?
    let `repeat`: String?
    let count: Int?
    let size: Int?
    let seed: Int?
    let n: Int?

    /// `add` için içerik: text → UTF-8 metin baytları; image / pdf → GenSpec baytları.
    var genSpec: GenSpec? {
        guard let size, let seed else { return nil }
        return GenSpec(size: size, seed: seed)
    }

    /// `kind == .text` için metin (`text` ya da `repeat` × `count`).
    var textValue: String? {
        if let text { return text }
        if let unit = self.repeat, let count { return String(repeating: unit, count: count) }
        return nil
    }
}

struct HistoryExpect: Decodable, Sendable {
    let order: [String]
    let evicted: [String]
    let results: [HistoryAddResult]?
}

struct HistoryCase: Decodable, Sendable {
    let name: String
    let maxItems: Int
    let budgetBytes: Int?
    let ops: [HistoryOp]
    let expect: HistoryExpect
    let deviation: VectorDeviation?
    let source: VectorSource?
    let rule: String?
}
