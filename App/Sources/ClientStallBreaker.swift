// ClientStallBreaker.swift — một app làm VietTelex CHỜ thì app đó gõ thô, không bao giờ
// kéo cả hệ thống đứng theo.
//
// Issue #118 (08/10/2026, macOS 27.0.1, 1.8.13): chạy 9router + OpenClaw (ai.openclaw.mac,
// ghim tay In-place) → "không gõ được trên toàn máy". `sample VietTelex 3` lấy lúc đó cho
// thấy MỌI thread của VietTelex đang ngủ (main + com.viettelex.event-tap đỗ ở mach_msg,
// hai workqueue thread rỗi) — không deadlock, không AX call treo, không vòng lặp. Tức là
// tại thời điểm sample VietTelex không giữ gì cả; nếu nó là thủ phạm thì chỉ có thể theo
// kiểu TỪNG PHÍM chờ một client chậm (mỗi lần vài trăm ms → 1-2s) rồi nhả — kiểu mà
// sample 3 giây lúc đang gõ trong Terminal (bàn phím passthrough) không thấy được.
//
// Hai chỗ một client chậm có thể kéo CẢ HỆ THỐNG:
//   • IMK: handle() chạy trên MAIN và gọi ngược vào client (selectedRange/insertText/
//     setMarkedText — XPC đồng bộ). Main là MỘT hàng đợi cho phím của MỌI app: một
//     client treo 1s/phím ⇒ phím ở mọi app khác xếp hàng sau nó.
//   • Tap: callback chạy giữa đường đi của mọi phím trong session; chậm ⇒ mọi phím trễ,
//     chậm quá ⇒ macOS tắt tap (tapDisabledByTimeout).
// Mọi lời gọi AX trên đường phím đã có timeout 50ms; lời gọi IMK vào client thì KHÔNG
// đặt được timeout. Nên thay vì đoán chỗ chậm, đo chính thời lượng xử lý mỗi phím: app
// nào làm một phím vượt `stallThresholdNs` ba lần trong `strikeWindowNs` thì bị hạ xuống
// PASSTHROUGH (IMK trả false ngay, tap trả phím nguyên vẹn — không một lời gọi nào vào
// app đó) trong `cooldownNs`, rồi tự thử lại. Gõ tiếng Việt trong app đó tạm mất 30s;
// bàn phím của cả máy không bao giờ chết.
//
// Chi phí trên đường gõ: hai lần đọc đồng hồ + một phép so sánh mỗi phím; lock chỉ khi
// đã có app bị hạ (đọc một Bool dưới lock, tens of ns) hoặc khi một phím đã chậm sẵn.
// Kill switch: cờ "breaker" (AppState.tapCascadeBreaker) — tắt thì không bao giờ hạ.
//
// Chẩn đoán: giữ 8 lần chậm gần nhất (app, đường IMK/tap, ms) LUÔN LUÔN, không cần bật
// nhật ký gỡ lỗi — header nhật ký in ra, để lần báo lỗi sau có bằng chứng ngay.

import Foundation

/// Pure policy + state. Value type so tests drive it with a fake clock.
struct ClientStallState {
    /// A single key whose handling took longer than this is a stall. IMK round trips are
    /// ~2ms, a tap emit burst a few ms, the worst legit AX path (4 calls × 50ms timeout)
    /// 200ms — 250ms leaves a clear gap, yet a hung client (IMK/XPC waits of ~1s+) trips
    /// on its second key.
    static let stallThresholdNs: UInt64 = 250_000_000
    /// Three stalls inside this window ⇒ degrade. One or two slow keys can be a page-in
    /// or a one-time lazy load (lexicons on the first keys after launch); three in 10s
    /// from the same app is a pattern — and a hung client (~1s+/key) still trips within
    /// three keystrokes.
    static let strikes = 3
    static let strikeWindowNs: UInt64 = 10_000_000_000
    /// How long a degraded app stays passthrough before we try composing again.
    static let cooldownNs: UInt64 = 30_000_000_000
    static let maxRecent = 8

    enum Path: String { case imk, tap, tapTimeout = "tap-timeout" }

    struct Stall: Equatable {
        let id: String
        let path: Path
        let ms: Int
        let atNs: UInt64
    }

    private(set) var strikesByID: [String: [UInt64]] = [:]
    private(set) var degradedUntil: [String: UInt64] = [:]
    private(set) var recent: [Stall] = []

    static func isStall(durationNs: UInt64) -> Bool { durationNs > stallThresholdNs }

    /// Record one stalled key for `id`. Returns true when this stall DEGRADES the app
    /// (transition only — already-degraded apps return false).
    mutating func recordStall(id: String, path: Path, durationNs: UInt64, nowNs: UInt64,
                              enabled: Bool) -> Bool {
        recent.append(Stall(id: id, path: path, ms: Int(durationNs / 1_000_000), atNs: nowNs))
        if recent.count > Self.maxRecent { recent.removeFirst(recent.count - Self.maxRecent) }
        guard enabled else { return false }
        if isDegraded(id: id, nowNs: nowNs) { return false }
        var s = strikesByID[id, default: []].filter { nowNs &- $0 <= Self.strikeWindowNs }
        s.append(nowNs)
        // Bounded map: forget other apps' expired strikes (a handful of ids at most).
        strikesByID = strikesByID.filter { $0.key != id && $0.value.contains { nowNs &- $0 <= Self.strikeWindowNs } }
        if s.count >= Self.strikes {
            degradedUntil[id] = nowNs &+ Self.cooldownNs
            return true
        }
        strikesByID[id] = s
        return false
    }

    func isDegraded(id: String, nowNs: UInt64) -> Bool {
        guard let until = degradedUntil[id] else { return false }
        return nowNs < until
    }

    /// Drop expired cooldowns. Returns true when nothing is degraded any more.
    mutating func expire(nowNs: UInt64) -> Bool {
        degradedUntil = degradedUntil.filter { nowNs < $0.value }
        return degradedUntil.isEmpty
    }
}

/// Process-wide breaker shared by the IMK controller (MAIN) and the tap (TAP thread).
final class ClientStallBreaker {
    static let shared = ClientStallBreaker()

    private let lock = NSLock()
    private var state = ClientStallState()
    /// Fast-path latch: false ⇒ nothing is degraded, `isDegraded` skips the map.
    private var anyDegraded = false
    /// Test seam: kill switch override (production reads AppState.tapCascadeBreaker).
    var enabledOverride: Bool?

    /// Per-key gate. Hot path: one uncontended lock + Bool read when nothing is degraded.
    func isDegraded(_ id: String?, nowNs: UInt64 = DispatchTime.now().uptimeNanoseconds) -> Bool {
        guard let id else { return false }
        return lock.withLock {
            guard anyDegraded else { return false }
            if state.isDegraded(id: id, nowNs: nowNs) { return true }
            if state.expire(nowNs: nowNs) { anyDegraded = false }
            return false
        }
    }

    /// Call after handling a key: only does work when the key was slow.
    @inline(__always)
    func noteKeyHandled(_ id: @autoclosure () -> String?, path: ClientStallState.Path, startNs: UInt64,
                        endNs: UInt64 = DispatchTime.now().uptimeNanoseconds) {
        let d = endNs &- startNs
        guard ClientStallState.isStall(durationNs: d), let id = id() else { return }
        recordStall(id, path: path, durationNs: d, nowNs: endNs)
    }

    /// The tap was disabled by timeout while `id` was frontmost: macOS itself measured
    /// a callback too slow — count it as a stall at the threshold.
    func noteTapTimeout(_ id: String?) {
        guard let id else { return }
        recordStall(id, path: .tapTimeout, durationNs: ClientStallState.stallThresholdNs + 1,
                    nowNs: DispatchTime.now().uptimeNanoseconds)
    }

    private func recordStall(_ id: String, path: ClientStallState.Path, durationNs: UInt64, nowNs: UInt64) {
        let enabled = enabledOverride ?? AppState.shared.tapCascadeBreaker   // own lock — outside ours
        let degraded: Bool = lock.withLock {
            let d = state.recordStall(id: id, path: path, durationNs: durationNs, nowNs: nowNs, enabled: enabled)
            if d { anyDegraded = true }
            return d
        }
        let ms = durationNs / 1_000_000
        Signposts.log.error("client stall: \(id, privacy: .public) path=\(path.rawValue, privacy: .public) \(ms, privacy: .public)ms")
        DebugLog.log("client stall: \(id) path=\(path.rawValue) \(ms)ms")
        if degraded {
            Signposts.log.fault("client stall breaker: \(id, privacy: .public) → passthrough for \(ClientStallState.cooldownNs / 1_000_000_000, privacy: .public)s")
            DebugLog.log("client stall breaker: \(id) → passthrough \(ClientStallState.cooldownNs / 1_000_000_000)s (keys native, no calls into the app)")
        }
    }

    /// Debug-report line (always available, independent of debug logging).
    func reportLine(nowNs: UInt64 = DispatchTime.now().uptimeNanoseconds) -> String {
        let (recent, degraded) = lock.withLock {
            (state.recent, state.degradedUntil.filter { nowNs < $0.value }.keys.sorted())
        }
        let stalls = recent.isEmpty ? "(none)" : recent.map {
            "\($0.id) \($0.path.rawValue) \($0.ms)ms \((nowNs &- $0.atNs) / 1_000_000_000)s ago"
        }.joined(separator: "; ")
        return "client stalls: \(stalls) | passthrough now: \(degraded.isEmpty ? "(none)" : degraded.joined(separator: ", "))"
    }

    #if DEBUG
    func _testReset() { lock.withLock { state = ClientStallState(); anyDegraded = false }; enabledOverride = nil }
    #endif
}
