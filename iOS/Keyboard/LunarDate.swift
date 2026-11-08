// LunarDate — ngày âm lịch Việt Nam (múi giờ UTC+7, KHÔNG phải UTC+8) + chip "âm lịch" trên
// thanh gợi ý. Logic THUẦN (không UIKit/proxy) — bản Kotlin android LunarDate.kt phải cho cùng
// kết quả (cùng bộ test LunarDateTests).
//
// Phần tính ngày âm dùng chung LunarCalendar.swift của bản desktop (điểm sóc Meeus đầy đủ + ΔT);
// file này chỉ giữ kiểu Lunar, nhãn và phần chip.
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

    /// Dương lịch (d, m, y) → âm lịch Việt Nam. Tính bằng LunarCalendar (App/Sources/LunarCalendar.swift,
    /// dùng chung macOS/Linux, đưa vào target bàn phím qua project.yml) — mọi nền tảng cùng một
    /// công thức (Meeus đầy đủ + ΔT); fixture Fixtures/lunar-month-starts.txt khoá kết quả 1900–2100.
    static func lunar(_ dd: Int, _ mm: Int, _ yy: Int, tz: Double = timeZone) -> Lunar {
        let l = LunarCalendar.lunar(day: dd, month: mm, year: yy, timeZone: tz)
        return Lunar(day: l.day, month: l.month, year: l.year, leap: l.leap)
    }

    /// Tên năm âm lịch ("Bính Ngọ" cho 2026).
    static func yearName(_ lunarYear: Int) -> String { LunarCalendar.yearName(lunarYear) }

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
