// TouchLog — log gỡ lỗi "gõ nhanh bị rớt chữ" (abcdefgh → abegh, 25/09/2026).
//
// TẮT mặc định; bật trong app VietTelex → Cài đặt → "Ghi log chạm phím". Chỉ ghi
// cấu trúc (thời điểm, độ trễ giao touch, số ngón đang đè, chạm có trúng phím, số
// lệnh xoá/chèn gửi sang app) — KHÔNG BAO GIỜ ghi ký tự người dùng gõ.
// Đọc: Console.app (Mac) → chọn iPhone → lọc "VTKB touch".
import Foundation
import os.log
import QuartzCore

enum TouchLog {
    nonisolated(unsafe) static var enabled = false
    private static let log = OSLog(subsystem: "com.viettelex.ios.keyboard", category: "touch")
    nonisolated(unsafe) private static var seq = 0

    static func loadSetting() {
        enabled = UserDefaultsProvider.shared?.bool(forKey: "debugTouchLog") ?? false
    }

    /// `touchTimestamp` = UITouch.timestamp (same clock as CACurrentMediaTime).
    static func touchBegan(active: Int, batch: Int, touchTimestamp: TimeInterval, hit: Bool, y: Double) {
        guard enabled else { return }
        seq += 1
        let lagMs = (CACurrentMediaTime() - touchTimestamp) * 1000
        os_log("VTKB touch #%d BEGAN batch=%d active=%d lag=%.1fms %{public}@",
               log: log, type: .default, seq, batch, active, lagMs,
               hit ? "hit" : String(format: "MISS y=%.0f", y))
    }

    static func touchEnded(cancelled: Bool, routed: Bool) {
        guard enabled else { return }
        os_log("VTKB touch %{public}@ routed=%d", log: log, type: .default,
               cancelled ? "CANCELLED" : "ended", routed ? 1 : 0)
    }

    static func key(kind: String, composing: Bool, lagMs: Double) {
        guard enabled else { return }
        os_log("VTKB touch key=%{public}@ composing=%d handle=%.2fms", log: log, type: .default,
               kind, composing ? 1 : 0, lagMs)
    }

    static func edit(bs: Int, insertLen: Int) {
        guard enabled else { return }
        os_log("VTKB touch edit bs=%d ins=%d", log: log, type: .default, bs, insertLen)
    }

    static func host(_ event: String, applyingEdit: Bool, composing: Bool) {
        guard enabled else { return }
        os_log("VTKB touch host %{public}@ applyingEdit=%d composing=%d", log: log, type: .default,
               event, applyingEdit ? 1 : 0, composing ? 1 : 0)
    }
}
