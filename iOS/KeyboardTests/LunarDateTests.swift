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

    /// Bản rút gọn cũ (sóc sai ~30 phút, thiếu lùi thêm một kỳ trăng) trả ngày 0 hoặc lệch một ngày ở
    /// các ngày này; công thức chung LunarCalendar (desktop) ra đúng.
    func testRegressionShortAlgorithmDates() {
        XCTAssertEqual(lunar(7, 5, 2054), .init(day: 30, month: 3, year: 2054, leap: false))    // cũ: ngày 0
        XCTAssertEqual(lunar(9, 4, 2062), .init(day: 30, month: 2, year: 2062, leap: false))    // cũ: ngày 0
        XCTAssertEqual(lunar(9, 12, 2072), .init(day: 1, month: 11, year: 2072, leap: false))   // cũ: lệch 1 ngày
        XCTAssertEqual(lunar(15, 11, 2077), .init(day: 1, month: 10, year: 2077, leap: false))  // cũ: lệch 1 ngày
        XCTAssertEqual(LunarDate.label(lunar(7, 5, 2054)), "30/3 năm Giáp Tuất")
    }

    /// Fixture chung 4 nền tảng: mọi ngày đầu tháng âm 1900–2100 (sinh từ App/Sources/LunarCalendar.swift).
    /// Đi từng ngày, so ngày/tháng/nhuận/năm với tháng trong fixture chứa ngày đó.
    func testMatchesCrossPortFixture() throws {
        let url = Bundle(for: Self.self).url(forResource: "lunar-month-starts", withExtension: "txt")
            ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/lunar-month-starts.txt")
        let starts = try LunarFixture.parse(String(contentsOf: url, encoding: .utf8))
        XCTAssertEqual(starts.count, 2487)
        var bad: [String] = [], days = 0
        for (i, s) in starts.enumerated() {
            let next = i + 1 < starts.count ? starts[i + 1].jd : LunarFixture.jd(31, 12, 2100) + 1
            for jd in s.jd..<next {
                let (y, m, d) = LunarFixture.gregorian(jd)
                let l = lunar(d, m, y)
                if l != .init(day: jd - s.jd + 1, month: s.month, year: s.year, leap: s.leap) { bad.append("\(d)/\(m)/\(y)") }
                days += 1
            }
        }
        XCTAssertGreaterThan(days, 73_000)
        XCTAssertEqual(bad, [], "lệch: \(bad.prefix(10))")
    }

    /// Đối chiếu lịch Việt của Foundation (iOS 26+) — 1990–2050, từng ngày (cùng khoảng AppTests;
    /// sau 2050 Foundation có tháng trả ngày 0) và 1985 (Foundation ra Tết 20/2 như lịch Trung Quốc;
    /// lịch Việt 1985 Tết 21/1 — xem testVietnamTimezoneDivergence).
    func testMatchesFoundationVietnameseCalendar() throws {
        guard #available(iOS 26, *) else { throw XCTSkip("Calendar.Identifier.vietnamese cần iOS 26") }
        let tz = TimeZone(secondsFromGMT: 7 * 3600)!
        var vn = Calendar(identifier: .vietnamese); vn.timeZone = tz
        var g = Calendar(identifier: .gregorian); g.timeZone = tz
        var date = g.date(from: DateComponents(year: 1990, month: 1, day: 1, hour: 12))!
        let end = g.date(from: DateComponents(year: 2050, month: 12, day: 31, hour: 12))!
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
        XCTAssertGreaterThan(n, 22_000)
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

    // MARK: - Chip "Tết"

    func testTetTriggers() {
        XCTAssertEqual(LunarDate.triggerTail(before: "Sắp Tết "), "Tết ")
        XCTAssertEqual(LunarDate.triggerTail(before: "tết "), "tết ")
        XCTAssertEqual(LunarDate.triggerTail(before: "ăn TẾT "), "TẾT ")
        let nfd = "te\u{0302}\u{0301}t "
        XCTAssertEqual(LunarDate.triggerTail(before: "ăn " + nfd), nfd)
        for s in ["tếtt ", "tet ", "tét ", "xTết ", "Tết.", "Tết  "] {
            XCTAssertNil(LunarDate.triggerTail(before: s), "«\(s)» không được khớp")
        }
        for w in ["Tết", "tết", "TẾT", "te\u{0302}\u{0301}t"] { XCTAssertTrue(LunarDate.mayTrigger(w), w) }
        for w in ["tếtt", "tet", "Têt"] { XCTAssertFalse(LunarDate.mayTrigger(w), w) }
    }

    /// Chip = ngày dương mùng 1 Tết kế tiếp (≥ hôm nay); chạm giữ chữ Tết như đã gõ, nối ngày.
    func testTetChipBoundaries() {
        XCTAssertEqual(LunarDate.chip(before: "Sắp Tết ", today: (2026, 11, 8)),
                       NumberChip(display: "06/02/2027", replace: "Tết ", insert: "Tết 06/02/2027 "))
        XCTAssertEqual(LunarDate.chip(before: "TẾT ", today: (2026, 11, 8))?.insert, "TẾT 06/02/2027 ")
        XCTAssertEqual(LunarDate.chip(before: "tết ", today: (2027, 2, 5))?.display, "06/02/2027")   // hôm trước
        XCTAssertEqual(LunarDate.chip(before: "tết ", today: (2027, 2, 6))?.display, "06/02/2027")   // đúng mùng 1
        XCTAssertEqual(LunarDate.chip(before: "tết ", today: (2027, 2, 7))?.display, "26/01/2028")   // hôm sau
        XCTAssertEqual(LunarDate.chip(before: "Tết", today: (2026, 11, 8))?.insert, "Tết 06/02/2027 ")
        // chữ vừa chèn không sinh chip số / chip Tết kế tiếp
        XCTAssertNil(NumberChips.chip(before: "Tết 06/02/2027 "))
        XCTAssertNil(LunarDate.triggerTail(before: "Tết 06/02/2027 "))
    }

    /// Tết theo thuật toán = bảng Tết của KeyboardBuddy; mọi Tết 1901–2100 là 1/1 âm của năm đó.
    func testTetDayNumber() {
        for (y, md) in BuddySeason.lunarNewYear {
            let g = LunarCalendar.gregorian(LunarCalendar.tetDayNumber(lunarYear: y))
            XCTAssertEqual([g.year, g.month, g.day], [y, md.0, md.1], "Tết \(y)")
        }
        for y in 1901...2100 {
            let g = LunarCalendar.gregorian(LunarCalendar.tetDayNumber(lunarYear: y))
            XCTAssertEqual(lunar(g.day, g.month, g.year), .init(day: 1, month: 1, year: y, leap: false), "Tết \(y)")
        }
    }
}

/// Đọc iOS/KeyboardTests/Fixtures/lunar-month-starts.txt: "yyyymmdd<TAB>tháng[+]<TAB>năm âm".
enum LunarFixture {
    struct Start { let jd: Int, month: Int, year: Int, leap: Bool }

    static func jd(_ d: Int, _ m: Int, _ y: Int) -> Int {
        let a = (14 - m) / 12, yy = y + 4800 - a, mm = m + 12 * a - 3
        return d + (153 * mm + 2) / 5 + 365 * yy + yy / 4 - yy / 100 + yy / 400 - 32045
    }

    static func gregorian(_ jd: Int) -> (y: Int, m: Int, d: Int) {
        let a = jd + 32044, b = (4 * a + 3) / 146097, c = a - 146097 * b / 4
        let d = (4 * c + 3) / 1461, e = c - 1461 * d / 4, m = (5 * e + 2) / 153
        return (100 * b + d - 4800 + m / 10, m + 3 - 12 * (m / 10), e - (153 * m + 2) / 5 + 1)
    }

    static func parse(_ text: String) throws -> [Start] {
        try text.split(separator: "\n").filter { !$0.hasPrefix("#") && !$0.isEmpty }.map { line in
            let f = line.split(separator: "\t")
            guard f.count == 3, let ymd = Int(f[0]), let year = Int(f[2]) else { throw CocoaError(.fileReadCorruptFile) }
            let leap = f[1].hasSuffix("+")
            guard let month = Int(leap ? f[1].dropLast() : f[1]) else { throw CocoaError(.fileReadCorruptFile) }
            return Start(jd: jd(ymd % 100, ymd / 100 % 100, ymd / 10_000), month: month, year: year, leap: leap)
        }
    }
}
