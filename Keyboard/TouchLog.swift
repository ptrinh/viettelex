// TouchLog — log gỡ lỗi "gõ nhanh bị rớt chữ" (abcdefgh → abegh, 25/09/2026).
//
// TẮT mặc định; bật trong app VietTelex → Giới thiệu → Debug mode. Ghi thời điểm,
// độ trễ giao touch, số ngón đang đè, chạm trúng phím nào, lệnh xoá/chèn gửi sang
// app. KÝ TỰ (maintainer 25/09/2026: "record từng ký tự cho dễ debug") CHỈ vào file
// App Group mà user tự xem/xoá — os_log hệ thống KHÔNG nhận ký tự (sysdiagnose có
// thể rời máy).
// Hai đích: os_log "VTKB touch" (Console.app qua cáp) VÀ file touchlog.txt trong App
// Group — app đọc + nút Copy (cần "Cho phép Toàn quyền": không có Full Access thì
// extension không ghi được container chung, chỉ còn os_log).
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

    static let fileName = "touchlog.txt"
    static var fileURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.viettelex")?
            .appendingPathComponent(fileName)
    }
    private static let queue = DispatchQueue(label: "com.viettelex.touchlog", qos: .utility)
    private static let stampFormat: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"; f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()
    /// Append off-main; cap ~300 KB (keeps the newer half). No-op khi Debug mode
    /// TẮT — mọi caller (kể cả log nút Dán mỗi lần refresh bar) đi qua cổng này.
    static func write(_ line: String) {
        guard enabled, let url = fileURL else { return }
        let stamped = stampFormat.string(from: Date()) + " " + line + "\n"
        queue.async {
            let fm = FileManager.default
            if !fm.fileExists(atPath: url.path) { fm.createFile(atPath: url.path, contents: nil) }
            guard let h = try? FileHandle(forWritingTo: url) else { return }
            defer { try? h.close() }
            let size = (try? h.seekToEnd()) ?? 0
            if size > 300_000, let data = try? Data(contentsOf: url) {
                try? h.truncate(atOffset: 0)
                try? h.write(contentsOf: data.suffix(150_000))
            }
            try? h.write(contentsOf: Data(stamped.utf8))
        }
    }

    /// `touchTimestamp` = UITouch.timestamp (same clock as CACurrentMediaTime).
    static func touchBegan(active: Int, batch: Int, touchTimestamp: TimeInterval, hit: Bool, y: Double,
                           key: String? = nil) {
        guard enabled else { return }
        seq += 1
        let lagMs = (CACurrentMediaTime() - touchTimestamp) * 1000
        let where_ = hit ? "hit" : String(format: "MISS y=%.0f", y)
        os_log("VTKB touch #%d BEGAN batch=%d active=%d lag=%.1fms %{public}@",
               log: log, type: .default, seq, batch, active, lagMs, where_)
        write(String(format: "#%d BEGAN batch=%d active=%d lag=%.1fms ", seq, batch, active, lagMs) + where_
              + (key.map { " [\($0)]" } ?? ""))
    }

    /// Button keys (space, return, dấu câu…) don't go through the letter router —
    /// log their touch-down lag too: the bottom row sits on the system-gesture edge.
    static func buttonDown(_ name: String, touchTimestamp: TimeInterval?) {
        guard enabled else { return }
        let lag = touchTimestamp.map { String(format: "%.1fms", (CACurrentMediaTime() - $0) * 1000) } ?? "?"
        os_log("VTKB touch %{public}@ DOWN lag=%{public}@", log: log, type: .default, name, lag)
        write("\(name) DOWN lag=\(lag)")
    }

    /// Every touch-began hit-test verdict (deduped per touch timestamp), so a touch
    /// that never reaches the letter router shows WHERE it went (slot/control/nil).
    nonisolated(unsafe) private static var lastHitStamp: TimeInterval = -1
    static func hitTest(target: String, y: Double, stamp: TimeInterval) {
        guard enabled, stamp != lastHitStamp else { return }
        lastHitStamp = stamp
        let s = String(format: "HIT %@ y=%.0f", target, y)
        os_log("VTKB touch %{public}@", log: log, type: .default, s)
        write(s)
    }

    static func touchEnded(cancelled: Bool, routed: Bool) {
        guard enabled else { return }
        os_log("VTKB touch %{public}@ routed=%d", log: log, type: .default,
               cancelled ? "CANCELLED" : "ended", routed ? 1 : 0)
        write("\(cancelled ? "CANCELLED" : "ended") routed=\(routed ? 1 : 0)")
    }

    static func key(kind: String, composing: Bool, lagMs: Double, char: String? = nil) {
        guard enabled else { return }
        os_log("VTKB touch key=%{public}@ composing=%d handle=%.2fms", log: log, type: .default,
               kind, composing ? 1 : 0, lagMs)
        write(String(format: "key=%@ composing=%d handle=%.2fms", kind, composing ? 1 : 0, lagMs)
              + (char.map { " [\($0)]" } ?? ""))
    }

    static func edit(bs: Int, insertLen: Int, insert: String? = nil) {
        guard enabled else { return }
        os_log("VTKB touch edit bs=%d ins=%d", log: log, type: .default, bs, insertLen)
        write("edit bs=\(bs) ins=\(insertLen)" + (insert.map { " [\($0)]" } ?? ""))
    }

    static func host(_ event: String, applyingEdit: Bool, composing: Bool) {
        guard enabled else { return }
        os_log("VTKB touch host %{public}@ applyingEdit=%d composing=%d", log: log, type: .default,
               event, applyingEdit ? 1 : 0, composing ? 1 : 0)
        write("host \(event) applyingEdit=\(applyingEdit ? 1 : 0) composing=\(composing ? 1 : 0)")
    }

    /// Session header: settings that change touch behaviour, so a pasted log is
    /// self-describing (A/B of the bottom-edge deferral).
    static func session(fullAccess: Bool) {
        guard enabled else { return }
        write("=== keyboard appear — fullAccess=\(fullAccess ? 1 : 0)")
    }
}
