// MachineTypingDetector.swift — phím đến nhanh hơn tay người ⇒ máy đang gõ, để nguyên.
//
// Issue #118 (08/10/2026): OpenClaw (agent điều khiển máy) + 9router làm VietTelex
// "treo toàn máy", tắt 9router (agent ngừng làm việc) là hết, ABC thì gõ bình thường.
// Đọc mã OpenClaw (apps/macos/Sources/OpenClaw/ComputerScreenActionExecutor.swift,
// postTextGrapheme) và Peekaboo/CUA mà nó dùng: agent GÕ CHỮ bằng CGEvent, mỗi ký tự
// một cặp keyDown/keyUp (keycode 0 + chuỗi unicode), cách nhau ~1 ms — 500–1000 phím
// mỗi giây, hoặc gửi thẳng tới pid (SLEventPostToPid: không qua tap, nhưng vẫn qua
// IMK tới input method đang chọn). `peekaboo type` thì gõ keycode THẬT, 5 ms/ký tự.
//
// Với VietTelex đang chọn, mọi phím đó bị soạn Telex: chữ agent gõ bị biến dạng
// ("address" → "adđress"), agent đọc lại thấy sai, ⌘A-xoá-gõ lại — một vòng lặp liên
// tục, mỗi phím một lượt IMK đồng bộ trên MAIN (selectedRange/insertText vào app đang
// bị điều khiển, vốn đang bận) hoặc một loạt phím giả lập từ tap. MAIN là hàng đợi
// phím chung của mọi app và cũng là nơi phục vụ menu input method ⇒ gõ ở đâu cũng kẹt,
// menu không mở. ClientStallBreaker không bắt được ca này: không phím nào chậm >250ms,
// chỉ là QUÁ NHIỀU phím.
//
// Cách giải: chuỗi phím đến với khoảng cách < `fastGapNs` liên tiếp `tripRun` lần là
// máy gõ (người gõ nhanh nhất ~20 ký tự/s ≈ 50 ms/phím; rollover hai phím có thể sát
// nhau, nhưng 7 phím liền nhau mỗi phím < 12 ms thì không). Khi đó: bỏ cụm đang soạn,
// cho phím đi nguyên vẹn (IMK trả false ngay, tap trả phím — không một lời gọi nào vào
// app), tới khi có một khoảng lặng ≥ `releaseGapNs`. Được luôn cả máy quét mã vạch,
// text expander gõ phím: văn bản do máy gửi phải tới đúng nguyên văn.
//
// HAI đồng hồ, phải CÙNG nhanh mới tính: thời điểm tạo event (dấu thời gian của chính
// event) và thời điểm phím tới tay mình. Chỉ dùng thời điểm tới thì phím NGƯỜI bị dồn
// lại sau một lần main bận (hàng đợi xả một lèo) trông như máy gõ; chỉ dùng dấu thời
// gian event thì một nguồn đặt timestamp = 0/sai đơn vị sẽ trông như máy gõ. Dấu thời
// gian không dùng được (0, chạy lùi) ⇒ bỏ qua nó, chỉ còn đồng hồ tới quyết định.
//
// Phím autorepeat (giữ phím) không tính và cắt chuỗi: KeyRepeat đặt nhanh có thể dưới
// 15 ms/phím nhưng đó là tay người.
//
// Kill switch: cờ "breaker" (AppState.tapCascadeBreaker) — tắt thì không bao giờ hạ.
// Chi phí đường gõ: vài phép trừ/so sánh trên struct thuộc một thread (IMK: MAIN,
// tap: TAP thread) — không lock, không cấp phát; cờ chỉ đọc khi detector đã nói "máy".

import Foundation

struct MachineTypingDetector {
    /// Gap between two key-downs (by BOTH clocks) below which the pair is "too fast".
    static let fastGapNs: UInt64 = 12_000_000
    /// Consecutive too-fast gaps that make a burst machine typing (7 keys ≈ <84 ms).
    static let tripRun = 6
    /// A pause this long ends machine typing — the next key is a fresh start.
    static let releaseGapNs: UInt64 = 150_000_000

    private(set) var isActive = false
    private(set) var run = 0
    private var lastEventNs: UInt64 = 0
    private var lastArrivalNs: UInt64 = 0

    /// Feed one key-down. `eventNs` = the event's own timestamp in ns (0 = unknown),
    /// `arrivalNs` = monotonic now. Returns `(machine, began)`: whether this key should
    /// pass through untouched, and whether THIS key started the burst (log/drop once).
    mutating func observe(eventNs: UInt64, arrivalNs: UInt64, isRepeat: Bool) -> (machine: Bool, began: Bool) {
        let hadPrev = lastArrivalNs != 0
        let gapA = arrivalNs &- lastArrivalNs
        let eventKnown = eventNs != 0 && lastEventNs != 0 && eventNs >= lastEventNs
        let gapE = eventKnown ? eventNs - lastEventNs : 0
        lastArrivalNs = arrivalNs
        lastEventNs = eventNs

        if hadPrev, gapA >= Self.releaseGapNs {   // a pause: whatever it was is over
            isActive = false
            run = 0
        }
        if isRepeat {                             // held key: human, never counts
            run = 0
            return (isActive, false)
        }
        let fast = hadPrev && gapA < Self.fastGapNs && (!eventKnown || gapE < Self.fastGapNs)
        run = fast ? run + 1 : 0
        if !isActive, run >= Self.tripRun {
            isActive = true
            return (true, true)
        }
        return (isActive, false)
    }

    mutating func reset() { self = MachineTypingDetector() }
}

/// Always-on record of machine-typing bursts for the debug report (like the stall
/// ring): written only when a burst BEGINS (rare), from MAIN (IMK) or TAP.
enum MachineTypingLog {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var count = 0
    nonisolated(unsafe) private static var last: (id: String, path: String, atNs: UInt64)?

    static func noteBurst(_ id: String?, path: String, nowNs: UInt64 = DispatchTime.now().uptimeNanoseconds) {
        lock.withLock { count += 1; last = (id ?? "?", path, nowNs) }
    }

    static func reportLine(nowNs: UInt64 = DispatchTime.now().uptimeNanoseconds) -> String {
        let (n, l) = lock.withLock { (count, last) }
        guard let l else { return "machine typing: (none)" }
        return "machine typing: \(n) burst(s), last \(l.id) \(l.path) \((nowNs &- l.atNs) / 1_000_000_000)s ago"
    }

    #if DEBUG
    static func _testReset() { lock.withLock { count = 0; last = nil } }
    #endif
}
