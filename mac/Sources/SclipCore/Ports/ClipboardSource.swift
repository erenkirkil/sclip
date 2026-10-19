import Foundation

/// Panonun ucuz yoklama görüntüsü (B-8.8.1): içerik okunmadan sayaç ve bayraklar.
public struct ClipboardState: Sendable, Equatable {
    /// Platform değişiklik sayacı (`changeCount` / `GetClipboardSequenceNumber`).
    public var change: Int
    /// Gizli işaret var mı (B-8.8.7).
    public var sensitive: Bool
    /// Pano dosya URL'si ya da dosya promise'ı taşıyor mu (B-8.8.4 dosya yolu).
    public var hasFiles: Bool

    public init(change: Int, sensitive: Bool, hasFiles: Bool) {
        self.change = change
        self.sensitive = sensitive
        self.hasFiles = hasFiles
    }
}

/// Platform pano okuma portu. Ana thread'de çağrılır; okuma zaman aşımı (B-8.8.6) uyarlayıcının işidir.
public protocol ClipboardSource: AnyObject {
    func currentState() -> ClipboardState
    /// Dosya promise'ları `destination` kimlikli öğenin temp dizinine iner (E26). Boş dönüş: yeniden dene.
    /// `destination == nil`: dosya promise'larını ÇÖZME (diske hiçbir şey yazma), yalnız zaten var olan dosya
    /// URL'lerini döndür; hassas işaretli kopyalarda kullanılır (B-8.4.4).
    func readFiles(destination: EntryID?) -> [URL]
    /// Tek seferlik ham anlık görüntü.
    func readClip() -> RawClip
}
