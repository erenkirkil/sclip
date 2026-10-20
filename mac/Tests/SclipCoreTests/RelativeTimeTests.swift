import XCTest
@testable import SclipCore

/// B-6.4.8: şimdi − oluşturulma < 60 sn (negatif dahil) "şimdi"; < 60 dk "{n}dk önce";
/// < 24 sa "{n}sa önce"; sonra yerel saat HH:mm.
final class RelativeTimeTests: XCTestCase {
    private static let strings: Strings = {
        do { return try Strings.load(from: VectorLoader.spec("strings.tr.json")) } catch { fatalError("\(error)") }
    }()
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func utc() -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }

    private func label(secondsAgo: TimeInterval, calendar: Calendar? = nil) -> String {
        RelativeTime.label(from: now.addingTimeInterval(-secondsAgo), now: now,
                           strings: Self.strings, calendar: calendar ?? utc())
    }

    func testJustNow() {
        XCTAssertEqual(label(secondsAgo: 0), "şimdi")
        XCTAssertEqual(label(secondsAgo: 59), "şimdi")
        XCTAssertEqual(label(secondsAgo: 59.9), "şimdi")
    }

    func testOneMinute() {
        XCTAssertEqual(label(secondsAgo: 60), "1dk önce")
        XCTAssertEqual(label(secondsAgo: 119), "1dk önce") // aşağı yuvarlanır
        XCTAssertEqual(label(secondsAgo: 3599), "59dk önce")
    }

    func testHours() {
        XCTAssertEqual(label(secondsAgo: 3600), "1sa önce")
        XCTAssertEqual(label(secondsAgo: 23 * 3600), "23sa önce")
        XCTAssertEqual(label(secondsAgo: 24 * 3600 - 1), "23sa önce")
    }

    func testBeyondDayShowsZeroPaddedClockTime() {
        // 2027-01-15 08:00:00 UTC
        let created = Date(timeIntervalSince1970: 1_800_000_000 - 5 * 3600 - 7 * 60 - 24 * 3600)
        let cal = utc()
        let hm = cal.dateComponents([.hour, .minute], from: created)
        let expected = String(format: "%02d:%02d", hm.hour!, hm.minute!)
        XCTAssertEqual(expected.count, 5)
        XCTAssertEqual(RelativeTime.label(from: created, now: now, strings: Self.strings, calendar: cal), expected)
        XCTAssertEqual(label(secondsAgo: 24 * 3600, calendar: cal),
                       String(format: "%02d:%02d", cal.component(.hour, from: now), cal.component(.minute, from: now)))
    }

    func testClockTimeUsesGivenTimeZoneAndPadsZeros() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 3 * 3600)! // UTC+3
        let created = Date(timeIntervalSince1970: 0) // 03:00 yerel
        XCTAssertEqual(RelativeTime.label(from: created, now: now, strings: Self.strings, calendar: cal), "03:00")
        let created2 = Date(timeIntervalSince1970: 5 * 60) // 03:05
        XCTAssertEqual(RelativeTime.label(from: created2, now: now, strings: Self.strings, calendar: cal), "03:05")
    }

    // Saat kayması: gelecekteki oluşturulma zamanı "şimdi" sayılır (B-6.4.8 "negatif dahil").
    func testFutureDateIsJustNow() {
        XCTAssertEqual(label(secondsAgo: -30), "şimdi")
        XCTAssertEqual(label(secondsAgo: -86_400 * 3), "şimdi")
    }

    // Brief imzası varsayılan takvimle çağrılabilir.
    func testDefaultCalendarSignatureCompiles() {
        XCTAssertEqual(RelativeTime.label(from: now, now: now, strings: Self.strings), "şimdi")
    }
}
