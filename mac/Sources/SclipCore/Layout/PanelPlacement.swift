import Foundation

/// Bir ekranın tam çerçevesi ve görünür alanı (menü çubuğu / Dock hariç).
/// AppKit global koordinatı: sol-alt köken, y yukarı doğru artar.
public struct ScreenArea: Sendable, Equatable {
    public let frame: CGRect
    public let visible: CGRect

    public init(frame: CGRect, visible: CGRect) {
        self.frame = frame
        self.visible = visible
    }

    // Foundation CGRect'in Equatable uyumunu (CoreGraphics'te) görünür kılmıyor; yalnız Foundation
    // içe aktarma kuralı yüzünden bileşenlerle elle karşılaştırılır.
    public static func == (lhs: ScreenArea, rhs: ScreenArea) -> Bool {
        sameRect(lhs.frame, rhs.frame) && sameRect(lhs.visible, rhs.visible)
    }

    private static func sameRect(_ a: CGRect, _ b: CGRect) -> Bool {
        a.origin.x == b.origin.x && a.origin.y == b.origin.y
            && a.size.width == b.size.width && a.size.height == b.size.height
    }
}

/// Panelin imleç yakınındaki konumu (B-6.1.5). Saf fonksiyon; ekran listesini ve imleci
/// çağıran (panel denetleyicisi) `NSScreen`/`NSEvent`'ten toplar.
public enum PanelPlacement {
    /// Panelin sol-alt köşesi.
    ///
    /// - Üst kenar imlecin `offset` altındadır, yatayda imlece ortalanır; imlecin üstüne çevrilmez.
    /// - Hedef ekran: `frame`'i imleci içeren ekran. `frame` kullanılır ki menü çubuğundaki
    ///   (tepsi tıklaması) imleç de doğru ekranı seçsin. Hiçbiri içermiyorsa (monitör çıkarıldı,
    ///   çözünürlük değişti) ilk ekran.
    /// - Sonuç, hedef ekranın `visible` alanına `margin` payıyla sıkıştırılır. Panel görünür alandan
    ///   büyükse sol-üst köşe görünür kalır (alt/sağ taşar).
    /// - `screens` boşsa sıkıştırma yapılamaz; imleç tabanlı konum olduğu gibi döner.
    public static func origin(cursor: CGPoint, screens: [ScreenArea], size: CGSize,
                              offset: CGFloat = 12, margin: CGFloat = 8) -> CGPoint {
        let x = cursor.x - size.width / 2
        let y = cursor.y - offset - size.height
        guard let screen = screens.first(where: { $0.frame.holds(cursor) }) ?? screens.first else {
            return CGPoint(x: x, y: y)
        }
        let area = screen.visible
        // x için alt sınır, y için üst sınır en son uygulanır: sığmayan panelde sol-üst köşe görünür kalır.
        let maxX = area.origin.x + area.size.width - margin - size.width
        let maxY = area.origin.y + area.size.height - margin - size.height
        return CGPoint(x: max(min(x, maxX), area.origin.x + margin),
                       y: min(max(y, area.origin.y + margin), maxY))
    }
}

private extension CGRect {
    /// `CGRect.contains` CoreGraphics'te; SclipCore yalnız Foundation/CryptoKit içe aktarır.
    /// Yatay yarı açık (`minX <= x < maxX`): yan yana ekranların ortak kenarı sağdaki ekrana düşer.
    /// Dikey üstte kapalı (`minY <= y <= maxY`): AppKit'te ekranın en üst piksel satırı (menü çubuğu,
    /// tepsi tıklaması) tam `maxY` raporlanır, ekranın içi sayılır (NSMouseInRect gibi). Ekranlar
    /// dizi sırasıyla denenir, ilk eşleşen kazanır: dikey üst üste ekranların ortak kenarı dizide
    /// önce gelene düşer.
    func holds(_ p: CGPoint) -> Bool {
        p.x >= origin.x && p.x < origin.x + size.width && p.y >= origin.y && p.y <= origin.y + size.height
    }
}
