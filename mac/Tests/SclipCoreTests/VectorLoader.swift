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
}
