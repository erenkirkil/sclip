import Foundation

/// imageSet ızgarasındaki odak hedefi: küçük resim (indeks), Hepsini yapıştır ya da Sil düğmesi.
public enum GridFocus: Sendable, Equatable { case thumb(Int), pasteAll, delete }

/// Bir ok tuşunun sonucu. `.previousRow` / `.nextRow` odağın ızgaradan çıkıp liste satırı
/// düzeyinde bir önceki / sonraki satıra (ilk satırın üstünde: üst çubuğa) geçtiğini söyler.
public enum GridMove: Sendable, Equatable {
    case focus(GridFocus), previousRow, nextRow, searchField, none
}

public enum Direction: Sendable { case up, down, left, right }

/// imageSet ızgarası klavye navigasyonu (B-6.2.11–13, E10). Saf fonksiyon; odak nesnelerine
/// dokunmaz. Küçük resimden Hepsini yapıştır / Sil düğmesine geçişte çağıran kaynak indeksi saklar
/// ve sonraki çağrıda `remembered` olarak geri verir (B-6.2.11, B-6.2.12).
public enum GridNavigator {
    /// - Parameters:
    ///   - count: küçük resim sayısı (0 olabilir).
    ///   - columns: görünen sütun sayısı; 1'den küçükse 1 sayılır.
    ///   - hasPasteAll: Hepsini yapıştır düğmesi var mı (yoksa → ve ← doğrudan Sil'e/Sil'den).
    ///   - remembered: son satır-sonu çıkışının küçük resim indeksi; aralık dışıysa yok sayılır.
    ///   - isFirstRow: bu imageSet listenin ilk satırı mı.
    ///   - searchOpen: arama çubuğu açık mı.
    public static func move(_ d: Direction, from: GridFocus, count: Int, columns: Int, hasPasteAll: Bool,
                            remembered: Int?, isFirstRow: Bool, searchOpen: Bool) -> GridMove {
        let columns = max(1, columns)
        let count = max(0, count) // negatif sayı hiçbir aralık ifadesini çökertmesin
        switch d {
        case .right: return right(from: from, count: count, columns: columns, hasPasteAll: hasPasteAll)
        case .left: return left(from: from, count: count, hasPasteAll: hasPasteAll, remembered: remembered)
        case .up: return up(from: from, count: count, columns: columns, isFirstRow: isFirstRow, searchOpen: searchOpen)
        case .down: return down(from: from, count: count, columns: columns)
        }
    }

    private static func right(from: GridFocus, count: Int, columns: Int, hasPasteAll: Bool) -> GridMove {
        switch from {
        case .thumb(let i):
            guard (0..<count).contains(i) else { return .none }
            // Satır sonu ya da son resim: sondaki düğme sütununa atla (B-6.2.11).
            if (i + 1) % columns == 0 || i == count - 1 {
                return .focus(hasPasteAll ? .pasteAll : .delete)
            }
            return .focus(.thumb(i + 1))
        case .pasteAll: return .focus(.delete)
        case .delete: return .none
        }
    }

    private static func left(from: GridFocus, count: Int, hasPasteAll: Bool, remembered: Int?) -> GridMove {
        switch from {
        case .thumb(let i):
            return (1..<max(count, 1)).contains(i) ? .focus(.thumb(i - 1)) : .none
        case .pasteAll:
            return thumbOrNone(remembered: remembered, count: count)
        case .delete:
            return hasPasteAll ? .focus(.pasteAll) : thumbOrNone(remembered: remembered, count: count)
        }
    }

    /// Hatırlanan resim; yoksa ya da set küçüldüyse son resim; resim yoksa `.none`.
    private static func thumbOrNone(remembered: Int?, count: Int) -> GridMove {
        guard count > 0 else { return .none }
        if let r = remembered, (0..<count).contains(r) { return .focus(.thumb(r)) }
        return .focus(.thumb(count - 1))
    }

    private static func up(from: GridFocus, count: Int, columns: Int, isFirstRow: Bool, searchOpen: Bool) -> GridMove {
        if case .thumb(let i) = from {
            guard (0..<count).contains(i) else { return .none }
            if i >= columns { return .focus(.thumb(i - columns)) }
        }
        // Izgaranın üst kenarı ya da düğmeler: liste satırı geçişi (E10); ilk satırda B-6.2.4.
        return isFirstRow && searchOpen ? .searchField : .previousRow
    }

    private static func down(from: GridFocus, count: Int, columns: Int) -> GridMove {
        guard case .thumb(let i) = from else { return .nextRow }
        guard (0..<count).contains(i) else { return .none }
        if i + columns < count { return .focus(.thumb(i + columns)) }
        // Altta karşı hücre yok (eksik son satır dahil): ızgara kenarı, alt satıra geç (Flutter paritesi).
        return .nextRow
    }
}
