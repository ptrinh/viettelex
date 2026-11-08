// LunarCalendar.swift — âm lịch Việt Nam (gợi ý "âm lịch␣" → "30/9 năm Bính Ngọ", CaretSuggestions.swift).
// Dùng chung macOS + Linux (linux/engine-capi/Sources/TextToolCLI/LunarCalendar.swift là symlink)
// + bàn phím iOS (iOS/project.yml, iOS/Keyboard/LunarDate.swift gọi vào); Windows có bản C++ cùng
// công thức (windows/ime/core/caret_hints.cpp `lunarDate`), Android bản Kotlin (LunarDate.kt).
// Ba bản khoá chung bởi iOS/KeyboardTests/Fixtures/lunar-month-starts.txt (mọi ngày đầu tháng
// 1900–2100, sinh từ file này) — sửa công thức ⇒ sinh lại fixture và chạy test cả bốn nền tảng.
//
// Luật lịch: tháng bắt đầu từ ngày có điểm sóc (trăng mới) theo giờ địa phương; tháng 11 âm là
// tháng chứa Đông chí; năm có 13 tháng thì tháng nhuận là tháng đầu tiên (sau tháng 11) không
// chứa trung khí (kinh độ mặt trời bội số 30°). Tính theo MÚI GIỜ +7 (lịch Việt Nam từ 1968);
// lịch +8 lệch ở một số ngày, ví dụ Tết 2030 (VN 02/02, +8 là 03/02).
//
// Thiên văn: điểm sóc theo chuỗi tuần hoàn đầy đủ (Meeus, "Astronomical Algorithms" ch. 49,
// sai số cỡ giây) + ΔT (TT−UT); kinh độ biểu kiến của mặt trời (ch. 25, ~0.01°). Bản rút gọn
// (sai số điểm sóc ~30 phút) lệch ngày ở các tháng có sóc sát nửa đêm — ví dụ 1/7 năm 2026 là
// 13/08 chứ không phải 12/08. Test đối chiếu từng ngày 1986–2050 với Calendar(.vietnamese).
// Hàm thuần, chỉ dùng sin/floor (không Calendar ⇒ chạy được với FoundationEssentials trên Linux).
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

enum LunarCalendar {
    struct LunarDate: Equatable {
        var day: Int, month: Int, year: Int, leap: Bool
    }

    /// Ngày âm lịch (múi giờ `timeZone` giờ, mặc định +7) của ngày dương lịch Gregorian.
    static func lunar(day: Int, month: Int, year: Int, timeZone tz: Double = 7) -> LunarDate {
        let dayNumber = julianDay(day, month, year)
        let k = lunationIndex(Double(dayNumber))
        var monthStart = newMoonDay(k + 1, tz)
        if monthStart > dayNumber { monthStart = newMoonDay(k, tz) }
        if monthStart > dayNumber { monthStart = newMoonDay(k - 1, tz) }
        var a11 = lunarMonth11(year, tz)
        var b11 = a11
        var lunarYear: Int
        if a11 >= monthStart {
            lunarYear = year
            a11 = lunarMonth11(year - 1, tz)
        } else {
            lunarYear = year + 1
            b11 = lunarMonth11(year + 1, tz)
        }
        let lunarDay = dayNumber - monthStart + 1
        let diff = Int(floor(Double(monthStart - a11) / 29))
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
        return LunarDate(day: lunarDay, month: lunarMonth, year: lunarYear, leap: leap)
    }

    private static let can = ["Canh", "Tân", "Nhâm", "Quý", "Giáp", "Ất", "Bính", "Đinh", "Mậu", "Kỷ"]
    private static let chi = ["Thân", "Dậu", "Tuất", "Hợi", "Tý", "Sửu", "Dần", "Mão", "Thìn", "Tỵ", "Ngọ", "Mùi"]

    /// Tên năm âm lịch: 2026 → "Bính Ngọ".
    static func yearName(_ lunarYear: Int) -> String {
        can[((lunarYear % 10) + 10) % 10] + " " + chi[((lunarYear % 12) + 12) % 12]
    }

    /// "30/9 năm Bính Ngọ"; tháng nhuận: "1/6 nhuận năm Ất Tỵ". Năm là năm ÂM (trước Tết =
    /// năm trước).
    static func text(day: Int, month: Int, year: Int) -> String {
        let l = lunar(day: day, month: month, year: year)
        return String(l.day) + "/" + String(l.month) + (l.leap ? " nhuận" : "") + " năm " + yearName(l.year)
    }

    /// Số ngày Julius (lịch Gregorian) lúc trưa.
    static func julianDay(_ d: Int, _ m: Int, _ y: Int) -> Int {
        let a = (14 - m) / 12
        let yy = y + 4800 - a
        let mm = m + 12 * a - 3
        return d + (153 * mm + 2) / 5 + 365 * yy + yy / 4 - yy / 100 + yy / 400 - 32045
    }

    // MARK: Thiên văn

    private static let dr = Double.pi / 180
    private static func sind(_ x: Double) -> Double { sin(x * dr) }

    /// Kỳ trăng thứ k (k = 0: sóc 06/01/2000) có sóc ngay trước/ở ngày Julius `jd`.
    private static func lunationIndex(_ jd: Double, rounded: Bool = false) -> Int {
        let v = (jd - 2451550.09766) / 29.530588861
        return Int(floor(rounded ? v + 0.5 : v))
    }

    /// ΔT = TT − UT (ngày), đa thức Espenak–Meeus theo năm.
    private static func deltaT(_ jd: Double) -> Double {
        let y = 2000 + (jd - 2451545.0) / 365.25
        let secs: Double
        switch y {
        case ..<1961:
            let t = y - 1950; secs = 29.07 + 0.407 * t - t * t / 233 + t * t * t / 2547
        case ..<1986:
            let t = y - 1975; secs = 45.45 + 1.067 * t - t * t / 260 - t * t * t / 718
        case ..<2005:
            let t = y - 2000
            secs = 63.86 + 0.3345 * t - 0.060374 * t * t + 0.0017275 * t * t * t
                + 0.000651814 * t * t * t * t + 0.00002373599 * t * t * t * t * t
        case ..<2050:
            let t = y - 2000; secs = 62.92 + 0.32217 * t + 0.005589 * t * t
        case ..<2150:
            let u = (y - 1820) / 100; secs = -20 + 32 * u * u - 0.5628 * (2150 - y)
        default:
            let u = (y - 1820) / 100; secs = -20 + 32 * u * u
        }
        return secs / 86400
    }

    /// Thời điểm sóc thứ k, ngày Julius UT (phần thập phân). Meeus ch. 49.
    private static func newMoon(_ k: Int) -> Double {
        let kd = Double(k)
        let t = kd / 1236.85, t2 = t * t, t3 = t2 * t, t4 = t3 * t
        var jde = 2451550.09766 + 29.530588861 * kd + 0.00015437 * t2 - 0.000000150 * t3 + 0.00000000073 * t4
        let e = 1 - 0.002516 * t - 0.0000074 * t2
        let m = 2.5534 + 29.10535670 * kd - 0.0000014 * t2 - 0.00000011 * t3                       // dị thường MT
        let mp = 201.5643 + 385.81693528 * kd + 0.0107582 * t2 + 0.00001238 * t3 - 0.000000058 * t4 // dị thường trăng
        let f = 160.7108 + 390.67050284 * kd - 0.0016118 * t2 - 0.00000227 * t3 + 0.000000011 * t4  // đối số vĩ độ
        let om = 124.7746 - 1.56375588 * kd + 0.0020672 * t2 + 0.00000215 * t3
        var c = -0.40720 * sind(mp) + 0.17241 * e * sind(m) + 0.01608 * sind(2 * mp) + 0.01039 * sind(2 * f)
        c += 0.00739 * e * sind(mp - m) - 0.00514 * e * sind(mp + m) + 0.00208 * e * e * sind(2 * m)
        c += -0.00111 * sind(mp - 2 * f) - 0.00057 * sind(mp + 2 * f) + 0.00056 * e * sind(2 * mp + m)
        c += -0.00042 * sind(3 * mp) + 0.00042 * e * sind(m + 2 * f) + 0.00038 * e * sind(m - 2 * f)
        c += -0.00024 * e * sind(2 * mp - m) - 0.00017 * sind(om) - 0.00007 * sind(mp + 2 * m)
        c += 0.00004 * sind(2 * mp - 2 * f) + 0.00004 * sind(3 * m) + 0.00003 * sind(mp + m - 2 * f)
        c += 0.00003 * sind(2 * mp + 2 * f) - 0.00003 * sind(mp + m + 2 * f) + 0.00003 * sind(mp - m + 2 * f)
        c += -0.00002 * sind(mp - m - 2 * f) - 0.00002 * sind(3 * mp + m) + 0.00002 * sind(4 * mp)
        // Các số hạng hành tinh.
        let a: [Double] = [299.77 + 0.107408 * kd - 0.009173 * t2, 251.88 + 0.016321 * kd, 251.83 + 26.651886 * kd,
                           349.42 + 36.412478 * kd, 84.66 + 18.206239 * kd, 141.74 + 53.303771 * kd,
                           207.14 + 2.453732 * kd, 154.84 + 7.306860 * kd, 34.52 + 27.261239 * kd,
                           207.19 + 0.121824 * kd, 291.34 + 1.844379 * kd, 161.72 + 24.198154 * kd,
                           239.56 + 25.513099 * kd, 331.55 + 3.592518 * kd]
        let w: [Double] = [325, 165, 164, 126, 110, 62, 60, 56, 47, 42, 40, 37, 35, 23]
        for i in 0..<a.count { c += w[i] * 0.000001 * sind(a[i]) }
        jde += c
        return jde - deltaT(jde)
    }

    /// Ngày (số ngày Julius) chứa sóc thứ k theo giờ địa phương.
    private static func newMoonDay(_ k: Int, _ tz: Double) -> Int {
        Int(floor(newMoon(k) + 0.5 + tz / 24))
    }

    /// Kinh độ biểu kiến của mặt trời (radian, 0…2π) tại ngày Julius UT `jd`. Meeus ch. 25.
    private static func sunLongitude(_ jd: Double) -> Double {
        let t = (jd + deltaT(jd) - 2451545.0) / 36525, t2 = t * t
        let l0 = 280.46646 + 36000.76983 * t + 0.0003032 * t2
        let m = 357.52911 + 35999.05029 * t - 0.0001537 * t2
        let c = (1.914602 - 0.004817 * t - 0.000014 * t2) * sind(m)
            + (0.019993 - 0.000101 * t) * sind(2 * m) + 0.000289 * sind(3 * m)
        let om = 125.04 - 1934.136 * t
        let l = (l0 + c - 0.00569 - 0.00478 * sind(om)) * dr
        return l - Double.pi * 2 * floor(l / (Double.pi * 2))
    }

    /// Cung 30° (0…11) của mặt trời lúc bắt đầu ngày `dayNumber` (giờ địa phương).
    private static func sunSector(_ dayNumber: Int, _ tz: Double) -> Int {
        Int(floor(sunLongitude(Double(dayNumber) - 0.5 - tz / 24) / Double.pi * 6))
    }

    /// Ngày bắt đầu tháng 11 âm (tháng chứa Đông chí) của năm `y`.
    private static func lunarMonth11(_ y: Int, _ tz: Double) -> Int {
        let dec31 = julianDay(31, 12, y)
        var k = lunationIndex(Double(dec31))
        var nm = newMoonDay(k, tz)
        if nm > dec31 { k -= 1; nm = newMoonDay(k, tz) }
        if sunSector(nm, tz) >= 9 { nm = newMoonDay(k - 1, tz) }
        return nm
    }

    /// Vị trí tháng nhuận (tính từ tháng 11 bắt đầu ngày `a11`): tháng đầu không có trung khí.
    private static func leapMonthOffset(_ a11: Int, _ tz: Double) -> Int {
        let k = lunationIndex(Double(a11), rounded: true)
        var i = 1
        var arc = sunSector(newMoonDay(k + i, tz), tz)
        var last: Int
        repeat {
            last = arc
            i += 1
            arc = sunSector(newMoonDay(k + i, tz), tz)
        } while arc != last && i < 14
        return i - 1
    }
}
