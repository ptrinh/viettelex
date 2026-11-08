// LunarDateTests — ngày âm lịch Việt Nam (UTC+7) + chip "âm lịch" trên thanh gợi ý.
// Cùng bộ ca với android LunarDateTests.kt.
import XCTest

final class LunarDateTests: XCTestCase {
    private func lunar(_ d: Int, _ m: Int, _ y: Int) -> LunarDate.Lunar { LunarDate.lunar(d, m, y) }

    func testTetMatchesBuddyTable() {
        XCTAssertEqual(BuddySeason.lunarNewYear.count, 10)
        for (y, md) in BuddySeason.lunarNewYear {
            XCTAssertEqual(lunar(md.1, md.0, y), .init(day: 1, month: 1, year: y, leap: false), "Tết \(y)")
            // hôm trước Tết = ngày cuối năm âm trước
            let eve = LunarDate.lunar(md.1 - 1 == 0 ? 31 : md.1 - 1, md.1 - 1 == 0 ? md.0 - 1 : md.0, y)
            XCTAssertEqual(eve.year, y - 1, "giao thừa \(y)")
            XCTAssertEqual(eve.month, 12, "giao thừa \(y)")
        }
    }

    func testMidAutumnMatchesBuddyTable() {
        XCTAssertEqual(BuddySeason.midAutumnDay.count, 10)
        for (y, md) in BuddySeason.midAutumnDay {
            XCTAssertEqual(lunar(md.1, md.0, y), .init(day: 15, month: 8, year: y, leap: false), "Trung Thu \(y)")
        }
    }

    /// UTC+7 khác UTC+8: sóc rơi 23h–24h giờ Việt Nam.
    func testVietnamTimezoneDivergence() {
        XCTAssertEqual(lunar(2, 2, 2030), .init(day: 1, month: 1, year: 2030, leap: false))
        XCTAssertEqual(lunar(26, 9, 2034), .init(day: 15, month: 8, year: 2034, leap: false))
        XCTAssertEqual(lunar(21, 1, 1985), .init(day: 1, month: 1, year: 1985, leap: false))   // Tết 1985 VN
    }

    func testLeapMonths() {
        XCTAssertEqual(lunar(25, 7, 2025), .init(day: 1, month: 6, year: 2025, leap: true))
        XCTAssertEqual(lunar(24, 7, 2025), .init(day: 30, month: 6, year: 2025, leap: false))
        XCTAssertEqual(lunar(22, 3, 2023), .init(day: 1, month: 2, year: 2023, leap: true))
        XCTAssertEqual(LunarDate.label(lunar(25, 7, 2025)), "1/6 nhuận năm Ất Tỵ")
    }

    func testLabelAndYearName() {
        XCTAssertEqual(LunarDate.yearName(2026), "Bính Ngọ")
        XCTAssertEqual(LunarDate.yearName(2025), "Ất Tỵ")
        XCTAssertEqual(LunarDate.yearName(2027), "Đinh Mùi")
        XCTAssertEqual(LunarDate.yearName(1984), "Giáp Tý")
        XCTAssertEqual(LunarDate.label(lunar(8, 11, 2026)), "30/9 năm Bính Ngọ")
        // trước Tết 2026 (17/2) ⇒ vẫn năm Ất Tỵ
        XCTAssertEqual(LunarDate.label(lunar(16, 2, 2026)), "29/12 năm Ất Tỵ")
        XCTAssertEqual(LunarDate.label(lunar(17, 2, 2026)), "1/1 năm Bính Ngọ")
        XCTAssertEqual(LunarDate.label(lunar(1, 1, 2026)), "13/11 năm Ất Tỵ")
    }

    /// Đối chiếu lịch Việt của Foundation (iOS 26+) — 1990–2060, từng ngày. Ngoài khoảng này lệch vài
    /// tháng sát ranh giới trung khí (2062, 2072: công thức gần đúng khác nhau) và 1985 (Foundation
    /// ra Tết 20/2 như lịch Trung Quốc; lịch Việt 1985 Tết 21/1 — xem testVietnamTimezoneDivergence).
    func testMatchesFoundationVietnameseCalendar() throws {
        guard #available(iOS 26, *) else { throw XCTSkip("Calendar.Identifier.vietnamese cần iOS 26") }
        let tz = TimeZone(secondsFromGMT: 7 * 3600)!
        var vn = Calendar(identifier: .vietnamese); vn.timeZone = tz
        var g = Calendar(identifier: .gregorian); g.timeZone = tz
        var date = g.date(from: DateComponents(year: 1990, month: 1, day: 1, hour: 12))!
        let end = g.date(from: DateComponents(year: 2060, month: 12, day: 31, hour: 12))!
        var n = 0, bad: [String] = []
        while date <= end {
            let gc = g.dateComponents([.year, .month, .day], from: date)
            let vc = vn.dateComponents([.day, .month, .isLeapMonth], from: date)
            let l = lunar(gc.day!, gc.month!, gc.year!)
            if l.day != vc.day || l.month != vc.month || l.leap != (vc.isLeapMonth ?? false) {
                bad.append("\(gc.day!)/\(gc.month!)/\(gc.year!)")
            }
            n += 1
            date = g.date(byAdding: .day, value: 1, to: date)!
        }
        XCTAssertGreaterThan(n, 25_000)
        XCTAssertEqual(bad.count, 0, "lệch: \(bad.prefix(10))")
    }

    // MARK: - Chip

    func testTriggers() {
        XCTAssertEqual(LunarDate.triggerTail(before: "Hôm nay âm lịch "), "âm lịch ")
        XCTAssertEqual(LunarDate.triggerTail(before: "Âm Lịch "), "Âm Lịch ")
        XCTAssertEqual(LunarDate.triggerTail(before: "hôm nay ngày âm "), "ngày âm ")
        XCTAssertEqual(LunarDate.triggerTail(before: "ÂL "), "ÂL ")
        XCTAssertEqual(LunarDate.triggerTail(before: "x âl"), "âl")
        // NFD (a + dấu mũ rời) vẫn khớp, đuôi giữ nguyên chữ đã gõ
        let nfd = "a\u{0302}m li\u{0323}ch "
        XCTAssertEqual(LunarDate.triggerTail(before: "hôm nay " + nfd), nfd)
        for s in ["", " ", "lịch ", "âm ", "ngày ", "đâm lịch ", "âm\nlịch ", "âm  lịch ", "ÂLL ", "ngày âm lịch  ",
                  "âm lịch.", "ngàyâm ", "AL "] {
            XCTAssertNil(LunarDate.triggerTail(before: s), "«\(s)» không được khớp")
        }
    }

    func testMayTrigger() {
        for w in ["lịch", "Lịch", "âm", "ÂM", "ÂL", "âl"] { XCTAssertTrue(LunarDate.mayTrigger(w), w) }
        for w in [nil, "ngày", "lich", "am", "AAL", "lịchs"] { XCTAssertFalse(LunarDate.mayTrigger(w), "\(w ?? "nil")") }
    }

    func testChipReplacesTriggerPhrase() {
        let today = (y: 2026, m: 11, d: 8)
        XCTAssertEqual(LunarDate.chip(before: "Hôm nay âm lịch ", today: today),
                       NumberChip(display: "30/9 năm Bính Ngọ", replace: "âm lịch ", insert: "30/9 năm Bính Ngọ "))
        XCTAssertEqual(LunarDate.chip(before: "ngày âm ", today: today)?.replace, "ngày âm ")
        XCTAssertEqual(LunarDate.chip(before: "ÂL ", today: today)?.replace, "ÂL ")
        XCTAssertEqual(LunarDate.chip(before: "ÂL ", today: (2025, 7, 25))?.insert, "1/6 nhuận năm Ất Tỵ ")
        XCTAssertNil(LunarDate.chip(before: "ngày ", today: today))
        // đuôi thay là hậu tố của context (controller xoá đúng từng ấy ký tự)
        for b in ["a âm lịch ", "x ngày âm ", "ÂL"] {
            let c = LunarDate.chip(before: b, today: today)
            XCTAssertTrue(b.hasSuffix(c?.replace ?? "#"), b)
        }
        // chữ vừa chèn không sinh chip số kế tiếp
        XCTAssertNil(NumberChips.chip(before: "hôm nay 30/9 năm Bính Ngọ "))
        XCTAssertNotNil(LunarDate.chip(before: "ÂL "))   // theo ngày máy
    }
}
