import Foundation

/// Satır zaman etiketi (B-6.4.8). Metinler `Strings`'ten gelir.
public enum RelativeTime {
    /// `now − from`: < 60 sn (negatif, yani saat kayması dahil) `time.now`; < 60 dk `time.minutes_ago`;
    /// < 24 sa `time.hours_ago` (`{n}` aşağı yuvarlanır); sonra `from`'un yerel saati `HH:mm`
    /// (24 saat, sıfır dolgulu). `calendar` yalnız `HH:mm` için saat dilimini belirler (testlerde sabitlenir).
    public static func label(from: Date, now: Date, strings: Strings, calendar: Calendar = .current) -> String {
        let seconds = now.timeIntervalSince(from)
        if seconds < 60 { return strings[.timeNow] }
        if seconds < 3600 {
            return strings.format(.timeMinutesAgo, ["n": String(Int(seconds / 60))])
        }
        if seconds < 86_400 {
            return strings.format(.timeHoursAgo, ["n": String(Int(seconds / 3600))])
        }
        // HH:mm, `from`'un yerel takvim bileşenlerinden okunur (DST güvenli; saniye aritmetiği yok).
        let hm = calendar.dateComponents([.hour, .minute], from: from)
        return String(format: "%02d:%02d", hm.hour ?? 0, hm.minute ?? 0)
    }
}
