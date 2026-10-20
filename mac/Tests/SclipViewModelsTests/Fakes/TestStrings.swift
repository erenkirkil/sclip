import Foundation
import SclipCore

/// Repo kökündeki `spec/strings.tr.json` kataloğu (testlerde uygulama bundle'ı yok).
enum TestStrings {
    static let catalog: Strings = {
        var dir = URL(filePath: #filePath).deletingLastPathComponent()
        while dir.path != "/" {
            let url = dir.appending(path: "spec").appending(path: "strings.tr.json")
            if FileManager.default.fileExists(atPath: url.path) {
                do { return try Strings.load(from: url) } catch { fatalError("\(error)") }
            }
            dir = dir.deletingLastPathComponent()
        }
        fatalError("spec/strings.tr.json bulunamadı: \(#filePath)")
    }()
}
