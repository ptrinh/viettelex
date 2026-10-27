// Đếm số phím đã gõ — chỉ con số, không bao giờ ghi phím nào hay nội dung gì. Mặc định tắt
// (`AppFlavor.countsKeystrokes`); app nào cần thống kê / tiến trình thì bật. Đường phím chỉ cộng một số
// nguyên trong RAM; cộng dồn vào App Group một lần khi bàn phím ẩn (`flush`). App chủ đọc `total` / `today`.
import Foundation

enum KeystrokeCounter {
    static let totalKey = "keystrokeTotal"
    static let todayKey = "keystrokeToday"
    /// Ngày của `todayKey`, dạng yyyymmdd theo giờ máy.
    static let dayKey = "keystrokeDay"

    private static var pending = 0

    /// Một phím vừa gõ (đường phím nóng: không cấp phát, không I/O).
    @inline(__always) static func tick() {
        if AppFlavor.countsKeystrokes { pending &+= 1 }
    }

    /// Cộng phần đang giữ vào App Group (bàn phím ẩn).
    static func flush(_ d: UserDefaults? = UserDefaults(suiteName: AppFlavor.appGroup), now: Date = Date()) {
        guard pending > 0, let d else { return }
        let n = pending
        pending = 0
        d.set(d.integer(forKey: totalKey) + n, forKey: totalKey)
        let day = dayNumber(now)
        let today = d.integer(forKey: dayKey) == day ? d.integer(forKey: todayKey) : 0
        d.set(today + n, forKey: todayKey)
        d.set(day, forKey: dayKey)
    }

    static func total(_ d: UserDefaults? = UserDefaults(suiteName: AppFlavor.appGroup)) -> Int {
        d?.integer(forKey: totalKey) ?? 0
    }

    static func today(_ d: UserDefaults? = UserDefaults(suiteName: AppFlavor.appGroup), now: Date = Date()) -> Int {
        guard let d, d.integer(forKey: dayKey) == dayNumber(now) else { return 0 }
        return d.integer(forKey: todayKey)
    }

    static func dayNumber(_ date: Date) -> Int {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return (c.year ?? 0) * 10_000 + (c.month ?? 0) * 100 + (c.day ?? 0)
    }

    #if DEBUG
    static var debugPending: Int { pending }
    /// Test: giả lập n phím (bỏ qua công tắc flavor).
    static func debugAdd(_ n: Int) { pending += n }
    static func debugReset() { pending = 0 }
    #endif
}
