import XCTest
@testable import SclipCore

/// B-6.2.10..13 ve E10. 7 küçük resim, 3 sütun: satırlar [0 1 2] [3 4 5] [6].
final class GridNavigatorTests: XCTestCase {
    private func move(_ d: Direction, _ from: GridFocus, count: Int = 7, columns: Int = 3,
                      hasPasteAll: Bool = true, remembered: Int? = nil,
                      isFirstRow: Bool = false, searchOpen: Bool = false) -> GridMove {
        GridNavigator.move(d, from: from, count: count, columns: columns, hasPasteAll: hasPasteAll,
                           remembered: remembered, isFirstRow: isFirstRow, searchOpen: searchOpen)
    }

    // B-6.2.11
    func testRightMovesToNextThumbInsideRow() {
        XCTAssertEqual(move(.right, .thumb(0)), .focus(.thumb(1)))
    }

    // B-6.2.11: satır sonunda Hepsini yapıştır'a atlar; çağıran kaynak indeksi hatırlar.
    func testRightAtRowEndJumpsToPasteAllAndRemembers() {
        XCTAssertEqual(move(.right, .thumb(2)), .focus(.pasteAll))
        XCTAssertEqual(move(.right, .thumb(6)), .focus(.pasteAll)) // son resim
        // Çağıranın hatırladığı indeks sonraki ← ile geri döner.
        XCTAssertEqual(move(.left, .pasteAll, remembered: 2), .focus(.thumb(2)))
    }

    // B-6.2.11: Hepsini yapıştır yoksa Sil'e atlar.
    func testRightAtRowEndGoesToDeleteWithoutPasteAll() {
        XCTAssertEqual(move(.right, .thumb(2), hasPasteAll: false), .focus(.delete))
    }

    func testRightFromPasteAllGoesToDeleteAndDeleteStops() {
        XCTAssertEqual(move(.right, .pasteAll), .focus(.delete))
        XCTAssertEqual(move(.right, .delete), .none)
    }

    // B-6.2.12
    func testLeftFromPasteAllReturnsToRemembered() {
        XCTAssertEqual(move(.left, .pasteAll, remembered: 5), .focus(.thumb(5)))
        XCTAssertEqual(move(.left, .pasteAll, remembered: nil), .focus(.thumb(6)))
        XCTAssertEqual(move(.left, .pasteAll, remembered: 99), .focus(.thumb(6))) // set küçüldü
        XCTAssertEqual(move(.left, .pasteAll, remembered: -1), .focus(.thumb(6)))
    }

    // B-6.2.12: Sil → Hepsini yapıştır → hatırlanan resim.
    func testLeftFromDeleteGoesToPasteAllElseRemembered() {
        XCTAssertEqual(move(.left, .delete), .focus(.pasteAll))
        XCTAssertEqual(move(.left, .delete, hasPasteAll: false, remembered: 2), .focus(.thumb(2)))
        XCTAssertEqual(move(.left, .delete, hasPasteAll: false), .focus(.thumb(6)))
    }

    func testLeftBetweenThumbs() {
        XCTAssertEqual(move(.left, .thumb(4)), .focus(.thumb(3)))
        XCTAssertEqual(move(.left, .thumb(0)), .none)
    }

    // B-6.2.13
    func testUpDownJumpByColumns() {
        XCTAssertEqual(move(.down, .thumb(1)), .focus(.thumb(4)))
        XCTAssertEqual(move(.up, .thumb(4)), .focus(.thumb(1)))
    }

    // B-6.2.13: kenarda üst/alt satıra geçer.
    func testUpFromTopAndDownFromBottomLeaveGrid() {
        XCTAssertEqual(move(.up, .thumb(1)), .previousRow)
        XCTAssertEqual(move(.down, .thumb(6)), .nextRow)
        XCTAssertEqual(move(.down, .thumb(4), count: 6), .nextRow)
    }

    // Eksik son satır (7 resim / 3 sütun): altında hücre olmayan resimden ↓ ızgara kenarıdır (Flutter paritesi).
    func testDownFromThumbWithNoCellBelowLeavesGridInRaggedLastRow() {
        XCTAssertEqual(move(.down, .thumb(2)), .focus(.thumb(5)))
        XCTAssertEqual(move(.down, .thumb(5)), .nextRow)        // altında 8. hücre yok
        XCTAssertEqual(move(.down, .thumb(2), count: 5), .nextRow)
        XCTAssertEqual(move(.down, .thumb(3), count: 5), .nextRow)
        // ↑ simetrik: üst satırdaki karşı hücre her zaman vardır.
        XCTAssertEqual(move(.up, .thumb(6)), .focus(.thumb(3)))
        XCTAssertEqual(move(.up, .thumb(4), count: 5), .focus(.thumb(1)))
    }

    // E10 / B-6.2.4
    func testUpFromFirstRowGoesToSearchWhenOpen() {
        XCTAssertEqual(move(.up, .thumb(1), isFirstRow: true, searchOpen: true), .searchField)
        XCTAssertEqual(move(.up, .thumb(1), isFirstRow: true, searchOpen: false), .previousRow)
        // Izgaranın içindeki ↑ arama kutusuna gitmez.
        XCTAssertEqual(move(.up, .thumb(4), isFirstRow: true, searchOpen: true), .focus(.thumb(1)))
        // Liste satırı ilk değilse arama açık olsa da önceki satıra gider.
        XCTAssertEqual(move(.up, .thumb(1), isFirstRow: false, searchOpen: true), .previousRow)
    }

    // E10: butonlardan ↑ / ↓ ölü değil, satır geçişidir.
    func testUpDownFromButtonsMoveRows() {
        for button in [GridFocus.pasteAll, .delete] {
            XCTAssertEqual(move(.up, button), .previousRow)
            XCTAssertEqual(move(.down, button), .nextRow)
            XCTAssertEqual(move(.up, button, isFirstRow: true, searchOpen: true), .searchField)
            XCTAssertEqual(move(.up, button, isFirstRow: true, searchOpen: false), .previousRow)
        }
    }

    // B-6.2.13: tek sütun.
    func testSingleColumnGrid() {
        XCTAssertEqual(move(.down, .thumb(0), count: 3, columns: 1), .focus(.thumb(1)))
        XCTAssertEqual(move(.up, .thumb(0), count: 3, columns: 1), .previousRow)
        XCTAssertEqual(move(.right, .thumb(0), count: 3, columns: 1), .focus(.pasteAll))
        XCTAssertEqual(move(.down, .thumb(2), count: 3, columns: 1), .nextRow)
    }

    func testZeroOrNegativeColumnsTreatedAsOne() {
        XCTAssertEqual(move(.down, .thumb(0), count: 3, columns: 0), .focus(.thumb(1)))
        XCTAssertEqual(move(.down, .thumb(0), count: 3, columns: -4), .focus(.thumb(1)))
    }

    // B-6.2.13: boş / tek resimli kenar durumda çökmez.
    func testEmptyAndSingleItemEdgeCases() {
        XCTAssertEqual(move(.left, .pasteAll, count: 0), .none)
        XCTAssertEqual(move(.left, .delete, count: 0, hasPasteAll: false), .none)
        XCTAssertEqual(move(.right, .pasteAll, count: 0), .focus(.delete))
        XCTAssertEqual(move(.right, .thumb(0), count: 0), .none)
        XCTAssertEqual(move(.down, .thumb(0), count: 0), .none)
        XCTAssertEqual(move(.right, .thumb(0), count: 1), .focus(.pasteAll))
        XCTAssertEqual(move(.left, .pasteAll, count: 1, remembered: 0), .focus(.thumb(0)))
        XCTAssertEqual(move(.down, .thumb(0), count: 1), .nextRow)
        XCTAssertEqual(move(.up, .thumb(0), count: 1), .previousRow)
    }

    func testOutOfRangeThumbFocusIsNone() {
        XCTAssertEqual(move(.right, .thumb(7)), .none)
        XCTAssertEqual(move(.left, .thumb(-1)), .none)
        XCTAssertEqual(move(.up, .thumb(9)), .none)
    }

    // Negatif sayı hiçbir yönde çökmez, 0 gibi davranır.
    func testNegativeCountDoesNotTrap() {
        for d in [Direction.up, .down, .left, .right] {
            _ = move(d, .thumb(0), count: -3)
            _ = move(d, .pasteAll, count: -3)
            _ = move(d, .delete, count: -3, hasPasteAll: false)
        }
        XCTAssertEqual(move(.left, .pasteAll, count: -3), .none)
        XCTAssertEqual(move(.right, .thumb(0), count: -3), .none)
        XCTAssertEqual(move(.down, .delete, count: -3), .nextRow)
    }
}
