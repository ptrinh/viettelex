// LunarDate — ngày âm lịch Việt Nam (múi giờ UTC+7, KHÔNG phải UTC+8) + chip "âm lịch" trên
// thanh gợi ý. Logic THUẦN (không UIKit/proxy) — bản Kotlin android LunarDate.kt phải cho cùng
// kết quả (cùng bộ test LunarDateTests).
//
// Thuật toán thiên văn công khai quen thuộc: điểm sóc (new moon) theo số ngày Julius, kinh độ
// mặt trời để tìm tháng 11 âm (chứa Đông chí) và tháng nhuận (tháng không chứa trung khí).
//
// Chip: gõ "âm lịch" / "ngày âm" / "ÂL" rồi cách ⇒ chip "30/9 năm Bính Ngọ" (tháng nhuận:
// "30/9 nhuận năm Bính Ngọ"); chạm = thay cụm vừa gõ bằng chữ đó + " ". Chi phí mỗi phím: chỉ so
// chuỗi từ vừa chốt (`mayTrigger`); ngày âm chỉ tính khi khớp, cache theo ngày.
import Foundation

enum LunarDate {
    struct Lunar: Equatable {
        let day: Int, month: Int, year: Int, leap: Bool
    }

    static let timeZone = 7.0

    /// Số ngày Julius của ngày dương (lịch Gregory).
    static func jdFromDate(_ dd: Int, _ mm: Int, _ yy: Int) -> Int {
        let a = (14 - mm) / 12
        let y = yy + 4800 - a
        let m = mm + 12 * a - 3
        return dd + (153 * m + 2) / 5 + 365 * y + y / 4 - y / 100 + y / 400 - 32045
    }

    /// Thời điểm sóc thứ k (tính từ 1/1/1900), ngày Julius thực.
    static func newMoon(_ k: Int) -> Double {
        let k = Double(k)
        let t = k / 1236.85, t2 = t * t, t3 = t2 * t
        let dr = Double.pi / 180
        var jd1 = 2415020.75933 + 29.53058868 * k + 0.0001178 * t2 - 0.000000155 * t3
        jd1 += 0.00033 * sin((166.56 + 132.87 * t - 0.009173 * t2) * dr)
        let m = 359.2242 + 29.10535608 * k - 0.0000333 * t2 - 0.00000347 * t3
        let mpr = 306.0253 + 385.81691806 * k + 0.0107306 * t2 + 0.00001236 * t3
        let f = 21.2964 + 390.67050646 * k - 0.0016528 * t2 - 0.00000239 * t3
        var c1 = (0.1734 - 0.000393 * t) * sin(m * dr) + 0.0021 * sin(2 * dr * m)
        c1 = c1 - 0.4068 * sin(mpr * dr) + 0.0161 * sin(dr * 2 * mpr)
        c1 = c1 - 0.0004 * sin(dr * 3 * mpr)
        c1 = c1 + 0.0104 * sin(dr * 2 * f) - 0.0051 * sin(dr * (m + mpr))
        c1 = c1 - 0.0074 * sin(dr * (m - mpr)) + 0.0004 * sin(dr * (2 * f + m))
        c1 = c1 - 0.0004 * sin(dr * (2 * f - m)) - 0.0006 * sin(dr * (2 * f + mpr))
        c1 = c1 + 0.0010 * sin(dr * (2 * f - mpr)) + 0.0005 * sin(dr * (2 * mpr + m))
        let deltat = t < -11
            ? 0.001 + 0.000839 * t + 0.0002261 * t2 - 0.00000845 * t3 - 0.000000081 * t * t3
            : -0.000278 + 0.000265 * t + 0.000262 * t2
        return jd1 + c1 - deltat
    }

    /// Kinh độ mặt trời (radian, 0…2π) tại ngày Julius thực `jdn`.
    static func sunLongitude(_ jdn: Double) -> Double {
        let t = (jdn - 2451545.0) / 36525, t2 = t * t
        let dr = Double.pi / 180
        let m = 357.52910 + 35999.05030 * t - 0.0001559 * t2 - 0.00000048 * t * t2
        let l0 = 280.46645 + 36000.76983 * t + 0.0003032 * t2
        var dl = (1.914600 - 0.004817 * t - 0.000014 * t2) * sin(dr * m)
        dl += (0.019993 - 0.000101 * t) * sin(dr * 2 * m) + 0.000290 * sin(dr * 3 * m)
        var l = (l0 + dl) * dr
        l -= Double.pi * 2 * (l / (Double.pi * 2)).rounded(.down)
        return l
    }

    static func newMoonDay(_ k: Int, _ tz: Double = timeZone) -> Int {
        Int((newMoon(k) + 0.5 + tz / 24).rounded(.down))
    }

    /// Cung kinh độ mặt trời (0…11, mỗi cung 30°) lúc đầu ngày `dayNumber`.
    static func sunSector(_ dayNumber: Int, _ tz: Double = timeZone) -> Int {
        Int((sunLongitude(Double(dayNumber) - 0.5 - tz / 24) / Double.pi * 6).rounded(.down))
    }

    /// Ngày bắt đầu tháng 11 âm của năm dương `yy`.
    static func lunarMonth11(_ yy: Int, _ tz: Double = timeZone) -> Int {
        let off = Double(jdFromDate(31, 12, yy) - 2415021)
        let k = Int((off / 29.530588853).rounded(.down))
        let nm = newMoonDay(k, tz)
        return sunSector(nm, tz) >= 9 ? newMoonDay(k - 1, tz) : nm
    }

    /// Vị trí tháng nhuận (tính từ tháng 11 âm `a11`).
    static func leapMonthOffset(_ a11: Int, _ tz: Double = timeZone) -> Int {
        let k = Int(((Double(a11) - 2415021.076998695) / 29.530588853 + 0.5).rounded(.down))
        var i = 1
        var arc = sunSector(newMoonDay(k + i, tz), tz)
        var last = 0
        repeat {
            last = arc
            i += 1
            arc = sunSector(newMoonDay(k + i, tz), tz)
        } while arc != last && i < 14
        return i - 1
    }

    /// Dương lịch (d, m, y) → âm lịch Việt Nam.
    static func lunar(_ dd: Int, _ mm: Int, _ yy: Int, tz: Double = timeZone) -> Lunar {
        let dayNumber = jdFromDate(dd, mm, yy)
        let k = Int(((Double(dayNumber) - 2415021.076998695) / 29.530588853).rounded(.down))
        var monthStart = newMoonDay(k + 1, tz)
        if monthStart > dayNumber { monthStart = newMoonDay(k, tz) }
        var a11 = lunarMonth11(yy, tz)
        var b11 = a11
        var lunarYear: Int
        if a11 >= monthStart {
            lunarYear = yy
            a11 = lunarMonth11(yy - 1, tz)
        } else {
            lunarYear = yy + 1
            b11 = lunarMonth11(yy + 1, tz)
        }
        let lunarDay = dayNumber - monthStart + 1
        let diff = (monthStart - a11) / 29
        var leap = false
        var lunarMonth = diff + 11
        if b11 - a11 > 365 {
            let leapDiff = leapMonthOffset(a11, tz)
            if diff >= leapDiff {
                lunarMonth = diff + 10
                if diff == leapDiff { leap = true }
            }
        }
        if lunarMonth > 12 { lunarMonth -= 12 }
        if lunarMonth >= 11 && diff < 4 { lunarYear -= 1 }
        return Lunar(day: lunarDay, month: lunarMonth, year: lunarYear, leap: leap)
    }

    private static let can = ["Canh", "Tân", "Nhâm", "Quý", "Giáp", "Ất", "Bính", "Đinh", "Mậu", "Kỷ"]
    private static let chi = ["Thân", "Dậu", "Tuất", "Hợi", "Tý", "Sửu", "Dần", "Mão", "Thìn", "Tỵ", "Ngọ", "Mùi"]

    /// Tên năm âm lịch ("Bính Ngọ" cho 2026).
    static func yearName(_ lunarYear: Int) -> String {
        "\(can[((lunarYear % 10) + 10) % 10]) \(chi[((lunarYear % 12) + 12) % 12])"
    }

    /// "30/9 năm Bính Ngọ" · tháng nhuận "30/9 nhuận năm Bính Ngọ".
    static func label(_ l: Lunar) -> String {
        "\(l.day)/\(l.month)\(l.leap ? " nhuận" : "") năm \(yearName(l.year))"
    }

    // MARK: - Chip "âm lịch"

    /// Lọc rẻ theo từ vừa chốt (controller gọi mỗi lượt gợi ý lúc không gõ dở): chỉ so chuỗi.
    static func mayTrigger(_ lastWord: String?) -> Bool {
        guard let w = lastWord, w.count <= 4 else { return false }
        switch w.lowercased() {
        case "lịch", "âm", "âl": return true
        default: return false
        }
    }

    /// Cụm kích hoạt ở cuối `before` (bỏ tối đa một dấu cách cuối) ⇒ đuôi cần thay (giữ nguyên
    /// chữ hoa/thường như đã gõ, kèm dấu cách cuối nếu có); không khớp ⇒ nil.
    static func triggerTail(before: String) -> String? {
        var s = Substring(before)
        if s.last == " " { s = s.dropLast() }
        guard !s.isEmpty else { return nil }
        let i1 = s.lastIndex(where: { $0.isWhitespace })
        let t1 = i1.map { s[s.index(after: $0)...] } ?? s
        guard t1.count <= 4 else { return nil }
        let w1 = t1.lowercased()
        var start = t1.startIndex
        if w1 == "âl" {
            // một từ
        } else if w1 == "lịch" || w1 == "âm", let i1, s[i1] == " " {
            let head = s[..<i1]
            let i0 = head.lastIndex(where: { $0.isWhitespace })
            let t0 = i0.map { head[head.index(after: $0)...] } ?? head
            let w0 = t0.lowercased()
            guard (w1 == "lịch" && w0 == "âm") || (w1 == "âm" && w0 == "ngày") else { return nil }
            start = t0.startIndex
        } else {
            return nil
        }
        return String(before[start...])
    }

    /// Chip cho `before` vào ngày dương `today` (y, m, d theo lịch máy).
    static func chip(before: String, today: (y: Int, m: Int, d: Int)) -> NumberChip? {
        guard let tail = triggerTail(before: before) else { return nil }
        let text = cachedLabel(today)
        return NumberChip(display: text, replace: tail, insert: text + " ")
    }

    /// Chip theo ngày hôm nay của máy.
    static func chip(before: String, now: Date = Date()) -> NumberChip? {
        let c = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: now)
        guard let y = c.year, let m = c.month, let d = c.day else { return nil }
        return chip(before: before, today: (y, m, d))
    }

    private static var cache: (key: Int, text: String)?

    private static func cachedLabel(_ t: (y: Int, m: Int, d: Int)) -> String {
        let key = t.y * 10_000 + t.m * 100 + t.d
        if let c = cache, c.key == key { return c.text }
        let text = label(lunar(t.d, t.m, t.y))
        cache = (key, text)
        return text
    }
}
