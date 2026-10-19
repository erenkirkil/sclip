import Foundation

/// Panodaki gizlilik bayrakları (sınıflandırmayı değiştirmez, B-8.8.4).
public enum ClipFlag: String, Sendable { case concealed, transient }

/// Tek pano öğesinin kanonik biçim → bayt eşlemesi.
public struct RawItem: Sendable {
    public var formats: [CanonicalFormat: Data]

    public init(formats: [CanonicalFormat: Data]) { self.formats = formats }
}

/// Platform katmanının sınıflandırıcıya verdiği ham pano görüntüsü.
public struct RawClip: Sendable {
    public var items: [RawItem]
    public var files: [URL]
    public var flags: Set<ClipFlag>

    public init(items: [RawItem], files: [URL], flags: Set<ClipFlag>) {
        self.items = items
        self.files = files
        self.flags = flags
    }
}
