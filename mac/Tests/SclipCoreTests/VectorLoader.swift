import Foundation

/// Repo kökünü ve `spec/` altındaki sözleşme dosyalarını testlere açar.
/// Task 8+ vektör okuma yardımcılarıyla genişletir.
enum VectorLoader {
    /// `#filePath`'ten yukarı çıkarak `spec/` dizinini içeren ilk dizin.
    static let repoRoot: URL = {
        let fm = FileManager.default
        var dir = URL(filePath: #filePath).deletingLastPathComponent()
        while dir.path != "/" {
            var isDir: ObjCBool = false
            let spec = dir.appending(path: "spec").path
            if fm.fileExists(atPath: spec, isDirectory: &isDir), isDir.boolValue {
                return dir
            }
            dir = dir.deletingLastPathComponent()
        }
        fatalError("spec/ içeren repo kökü bulunamadı: \(#filePath)")
    }()

    /// `spec/` altındaki bir dosyanın URL'i (ör. `strings.tr.json`).
    static func spec(_ relativePath: String) -> URL {
        repoRoot.appending(path: "spec").appending(path: relativePath)
    }

    /// `spec/vectors/` altındaki bir yol (vektör dosyası ya da `fixtures/…`).
    static func vectors(_ relativePath: String) -> URL {
        spec("vectors").appending(path: relativePath)
    }

    /// `spec/vectors/<file>` dosyasını şema tipine çözer.
    static func load<T: Decodable>(_ file: String, as type: T.Type = T.self) throws -> T {
        let data = try Data(contentsOf: vectors(file))
        return try JSONDecoder().decode(T.self, from: data)
    }

    static func detectCases() throws -> [DetectCase] { try load("detect.json") }
    static func hashCases() throws -> [HashCase] { try load("hash.json") }
    static func svgSanitizeCases() throws -> [SvgSanitizeCase] { try load("svg_sanitize.json") }
    static func classifyCases() throws -> [ClassifyCase] { try load("classify.json") }
    static func searchFile() throws -> SearchFile { try load("search.json") }
    static func historyCases() throws -> [HistoryCase] { try load("history.json") }

    /// `files` öğesini somut bir dosya URL'sine çevirir. Üretilmiş dosyalar `directory` altına
    /// `name` adıyla yazılır (çağıran temizler).
    static func materialize(_ ref: FileRef, in directory: URL) throws -> URL {
        switch ref {
        case .fixture(let path):
            return vectors(path)
        case .generated(let name, let bytes):
            let url = directory.appending(path: name)
            try bytes.data().write(to: url)
            return url
        }
    }
}
