import Foundation

/// Kullanıcıya görünen metin kataloğu (`spec/strings.tr.json`, düz `{anahtar: metin}` nesnesi).
/// Uygulamada bundle'daki `strings.tr.json`'dan, testlerde repo kökündeki `spec/`'ten yüklenir.
public struct Strings: Sendable {
    private let table: [String: String]

    init(table: [String: String]) {
        self.table = table
    }

    /// Kataloğu okur. Dosya yoksa, JSON nesne değilse ya da bir değer metin değilse fırlatır.
    public static func load(from url: URL) throws -> Strings {
        let data = try Data(contentsOf: url)
        return Strings(table: try JSONDecoder().decode([String: String].self, from: data))
    }

    /// Anahtarın metni. Katalogda yoksa çökmez, anahtarın kendisini (rawValue) döndürür;
    /// katalog bütünlüğünü StringsTests garanti eder.
    public subscript(_ key: StringKey) -> String {
        table[key.rawValue] ?? key.rawValue
    }

    /// `{ad}` yer tutucularını `args` ile tek geçişte değiştirir. `args`'ta olmayan yer
    /// tutucular olduğu gibi kalır; yerine konan değerler yeniden taranmaz.
    public func format(_ key: StringKey, _ args: [String: String]) -> String {
        Self.substitute(self[key], args)
    }

    static func substitute(_ template: String, _ args: [String: String]) -> String {
        var result = ""
        result.reserveCapacity(template.utf8.count)
        var rest = template[...]
        while let open = rest.firstIndex(of: "{") {
            result += rest[..<open]
            let afterOpen = rest.index(after: open)
            guard let close = rest[afterOpen...].firstIndex(of: "}") else {
                rest = rest[open...]
                break
            }
            let name = rest[afterOpen..<close]
            if name.contains("{") {
                // Kapanmamış ilk süslü parantez düz metindir; taramaya hemen arkasından devam.
                result.append("{")
                rest = rest[afterOpen...]
                continue
            }
            if let value = args[String(name)] {
                result += value
            } else {
                result += rest[open...close]
            }
            rest = rest[rest.index(after: close)...]
        }
        result += rest
        return result
    }
}
