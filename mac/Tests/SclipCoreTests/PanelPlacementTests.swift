import XCTest
@testable import SclipCore

/// B-6.1.5: imlecin `offset` altı, yatayda ortalı, imlecin bulunduğu ekranın görünür alanına
/// `margin` ile sıkıştırılır, imlecin üstüne çevrilmez. AppKit koordinatı: sol-alt köken, y yukarı.
final class PanelPlacementTests: XCTestCase {
    private let size = CGSize(width: 400, height: 300)
    // Menü çubuğu üstten 25 pt yer kaplar: visible, frame'den kısa.
    private let main = ScreenArea(frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                                  visible: CGRect(x: 0, y: 0, width: 1440, height: 875))

    // B-6.1.5
    func testCentersBelowCursor() {
        let o = PanelPlacement.origin(cursor: CGPoint(x: 700, y: 600), screens: [main], size: size)
        XCTAssertEqual(o.x, 500)            // 700 - 400/2
        XCTAssertEqual(o.y, 600 - 12 - 300) // üst kenar imlecin 12 pt altında
    }

    // B-6.1.5
    func testClampsAtRightAndBottomEdges() {
        let right = PanelPlacement.origin(cursor: CGPoint(x: 1430, y: 600), screens: [main], size: size)
        XCTAssertEqual(right.x, 1440 - 400 - 8)
        let left = PanelPlacement.origin(cursor: CGPoint(x: 10, y: 600), screens: [main], size: size)
        XCTAssertEqual(left.x, 8)
        // İmleç ekranın dibinde: panel aşağı taşar, alttan 8 pt payla sıkışır; imlecin üstüne çevrilmez.
        let bottom = PanelPlacement.origin(cursor: CGPoint(x: 700, y: 100), screens: [main], size: size)
        XCTAssertEqual(bottom.y, 8)
    }

    // B-6.1.5: üstten de görünür alanın (menü çubuğu altı) içinde kalır.
    func testClampsBelowMenuBar() {
        let o = PanelPlacement.origin(cursor: CGPoint(x: 700, y: 899), screens: [main], size: size)
        XCTAssertEqual(o.y, 875 - 300 - 8)
    }

    // B-6.1.5
    func testSecondaryScreenWithNegativeOrigin() {
        let secondary = ScreenArea(frame: CGRect(x: -1920, y: -180, width: 1920, height: 1080),
                                   visible: CGRect(x: -1920, y: -180, width: 1920, height: 1055))
        let screens = [main, secondary]
        let o = PanelPlacement.origin(cursor: CGPoint(x: -1000, y: 400), screens: screens, size: size)
        XCTAssertEqual(o.x, -1200)
        XCTAssertEqual(o.y, 400 - 12 - 300)
        // Sol kenara yakın: ikincil ekranın kendi kenarına sıkışır, ana ekrana taşmaz.
        let edge = PanelPlacement.origin(cursor: CGPoint(x: -1915, y: 400), screens: screens, size: size)
        XCTAssertEqual(edge.x, -1920 + 8)
    }

    // Plan Review Focus 2: ekran düzeni değişti, imleç hiçbir ekranda değil.
    func testCursorOutsideAllScreensFallsBackToFirstScreen() {
        let o = PanelPlacement.origin(cursor: CGPoint(x: 5000, y: 5000), screens: [main], size: size)
        XCTAssertEqual(o.x, 1440 - 400 - 8)
        XCTAssertEqual(o.y, 875 - 300 - 8)
        XCTAssertTrue(main.visible.contains(CGRect(origin: o, size: size)))
    }

    func testEmptyScreensReturnsCursorBasedOriginWithoutCrash() {
        let o = PanelPlacement.origin(cursor: CGPoint(x: 700, y: 600), screens: [], size: size)
        XCTAssertEqual(o, CGPoint(x: 500, y: 288))
    }

    // Panel görünür alandan büyükse sol-üst köşe görünür kalır.
    func testOversizedPanelKeepsTopLeftVisible() {
        let small = ScreenArea(frame: CGRect(x: 0, y: 0, width: 300, height: 200),
                               visible: CGRect(x: 0, y: 0, width: 300, height: 180))
        let o = PanelPlacement.origin(cursor: CGPoint(x: 150, y: 100), screens: [small], size: size)
        XCTAssertEqual(o.x, 8)
        XCTAssertEqual(o.y + size.height, 180 - 8)
    }

    // Menü çubuğu bölgesindeki imleç (tepsi tıklaması) frame içinde sayılır, ekran doğru seçilir.
    func testCursorInMenuBarStripPicksThatScreen() {
        let secondary = ScreenArea(frame: CGRect(x: 1440, y: 0, width: 1920, height: 1080),
                                   visible: CGRect(x: 1440, y: 0, width: 1920, height: 1055))
        let o = PanelPlacement.origin(cursor: CGPoint(x: 2400, y: 1070), screens: [main, secondary], size: size)
        XCTAssertEqual(o.x, 2200)
        XCTAssertEqual(o.y, 1055 - 300 - 8)
    }

    // B-6.1.5: ekranın en üst piksel satırı tam frame.maxY raporlanır, o ekrana aittir.
    func testCursorAtFrameMaxYOnNonFirstScreenPicksThatScreen() {
        let secondary = ScreenArea(frame: CGRect(x: 1440, y: 0, width: 1920, height: 1080),
                                   visible: CGRect(x: 1440, y: 0, width: 1920, height: 1055))
        let o = PanelPlacement.origin(cursor: CGPoint(x: 2400, y: 1080), screens: [main, secondary], size: size)
        XCTAssertEqual(o.x, 2200)
        XCTAssertEqual(o.y, 1055 - 300 - 8)
    }

    // Dikey üst üste iki ekranın ortak kenarı (alttaki.maxY == üsttekinin minY): dizide ilk gelen kazanır.
    func testSharedHorizontalEdgeOfStackedScreensPicksFirstInArray() {
        let lower = ScreenArea(frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                               visible: CGRect(x: 0, y: 0, width: 1440, height: 900))
        let upper = ScreenArea(frame: CGRect(x: 0, y: 900, width: 1440, height: 900),
                               visible: CGRect(x: 0, y: 900, width: 1440, height: 875))
        let edge = CGPoint(x: 700, y: 900)
        let a = PanelPlacement.origin(cursor: edge, screens: [lower, upper], size: size)
        XCTAssertEqual(a.y, 900 - 12 - 300)           // lower seçildi: sıkıştırma gerekmedi
        let b = PanelPlacement.origin(cursor: edge, screens: [upper, lower], size: size)
        XCTAssertEqual(b.y, 900 + 8)                  // upper seçildi: alt kenardan 8 pt payla sıkıştı
    }

    // Yan yana iki ekranın ortak dikey kenarı: yarı açık x, sağdaki ekran kazanır.
    func testSharedVerticalEdgeOfSideBySideScreensPicksRightScreen() {
        let right = ScreenArea(frame: CGRect(x: 1440, y: 0, width: 1920, height: 1080),
                               visible: CGRect(x: 1440, y: 0, width: 1920, height: 1055))
        let o = PanelPlacement.origin(cursor: CGPoint(x: 1440, y: 600), screens: [main, right], size: size)
        XCTAssertEqual(o.x, 1440 + 8) // sağ ekranın sol kenarına sıkıştı; sol ekran seçilseydi 1032
    }
}
