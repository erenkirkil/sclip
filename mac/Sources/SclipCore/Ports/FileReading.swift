import Foundation

/// Dosya listesi sınıflandırması için okuma portu (B-8.3.8). Testlerde sahte okuyucu enjekte edilir.
public protocol FileReading: Sendable {
    /// Normal dosyanın bayt boyutu; dosya yoksa, okunamıyorsa ya da normal dosya değilse `nil`.
    func size(of url: URL) -> Int?
    func read(_ url: URL) throws -> Data
    /// En fazla `maxBytes` bayt okur. Sınıflandırıcı `sınır + 1` ister: boyut okumasından sonra büyüyen dosya
    /// belleğe tamamen alınmadan sınır aşımı olarak görülür.
    func read(_ url: URL, upTo maxBytes: Int) throws -> Data
}

extension FileReading {
    /// Sınırsız okuyucular için varsayılan: okur, fazlasını keser (bellek sınırı sağlamaz).
    public func read(_ url: URL, upTo maxBytes: Int) throws -> Data {
        try read(url).prefix(max(maxBytes, 0))
    }
}

/// Diskten okuyan varsayılan uygulama. Sembolik bağlar hedeflerine çözülür.
public struct DiskFileReading: FileReading {
    public init() {}

    public func size(of url: URL) -> Int? {
        guard url.isFileURL else { return nil }
        let path = url.resolvingSymlinksInPath().path
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              attrs[.type] as? FileAttributeType == .typeRegular
        else { return nil }
        return (attrs[.size] as? NSNumber)?.intValue
    }

    public func read(_ url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    /// Sınırlı okuma: `FileHandle` ile parça parça, en fazla `maxBytes` bayt.
    public func read(_ url: URL, upTo maxBytes: Int) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var out = Data()
        while out.count < maxBytes {
            guard let chunk = try handle.read(upToCount: maxBytes - out.count), !chunk.isEmpty else { break }
            out.append(chunk)
        }
        return out
    }
}
