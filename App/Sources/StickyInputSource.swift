// StickyInputSource.swift
// "Giữ VietTelex khi macOS tự đổi bộ gõ theo tài liệu" — EXPERIMENTAL, default OFF.
//
// Field report Facebook 15/08/2026 (Lê Xuân Hùng): Word coi MỖI Ô COMMENT là một
// "document" input context riêng, nên khi macOS bật "Automatically switch to a
// document's input source" thì mỗi ô comment khởi đầu bằng input source mặc định —
// user phải chuyển bộ gõ lại cho từng ô. Tắt setting đó thì hết, nhưng user muốn
// GIỮ nó (per-app memory cho app khác, vd Flameshot = ABC cho vụ #54).
//
// Cách giải: phân biệt "macOS TỰ đổi" với "user CHỦ ĐỘNG đổi", và chỉ giành lại
// VietTelex ở ca tự-đổi:
//   • User đổi bằng hotkey (⌃Space/custom) → ngay trước notification có một chord
//     phím-kèm-modifier — tap của mình nhìn thấy (nhánh chord chạy cho MỌI app).
//   • User đổi bằng menu bàn phím → ngay trước đó có click vào DẢI MENU BAR
//     (mouse tap của mình cũng nhìn thấy; click chọn item nằm trong dropdown,
//     nhưng click MỞ menu luôn nằm trong dải bar — dùng cửa sổ 5s là đủ trùm).
//   • macOS tự đổi theo document/app thì KHÔNG có gesture nào cả.
// Cộng thêm: app frontmost phải KHÔNG đổi quanh lúc switch (đổi app → per-app
// memory của macOS làm việc đúng, đừng giành — vd Flameshot giữ nguyên ABC).
//
// Khi giành lại bằng TISSelectInputSource trong đúng document đó, macOS ghi nhớ
// per-document y như user tự chọn — tức là mỗi ô chỉ phải giành MỘT lần, các lần
// sau macOS tự đúng. Không có vòng lặp với OS (OS chỉ đổi lúc chuyển context);
// breaker 2-lần/10s làm lưới an toàn cho app ép ASCII-capable mà mình không
// nhận diện được (bài học ping-pong #32: đừng bao giờ giành tay đôi với OS).

import AppKit
import Carbon.HIToolbox

final class StickyInputSource {
    static let shared = StickyInputSource()

    // MARK: - Tham số heuristic (đơn vị ns)

    /// Chord phím-kèm-modifier trong cửa sổ này = user vừa thao tác → không giành.
    static let gestureWindowNs: UInt64 = 1_000_000_000        // 1s
    /// Click vào dải menu bar: cửa sổ dài hơn — user còn phải tìm item trong menu.
    static let menuClickWindowNs: UInt64 = 5_000_000_000      // 5s
    /// App frontmost đổi trong cửa sổ này = per-app switch hợp lệ của macOS.
    static let appChangeWindowNs: UInt64 = 1_500_000_000      // 1.5s
    /// Breaker: tối đa 2 lần giành trong 10s, quá thì bỏ cuộc tới khi đổi app.
    static let breakerWindowNs: UInt64 = 10_000_000_000
    static let breakerMax = 2
    /// Đợi cho focus/document mới ổn định rồi mới giành (và re-verify trước khi giành).
    static let reclaimDelayMs = 150

    // MARK: - Dấu vết gesture (ghi từ TAP thread, đọc trên MAIN) — một lock chung

    private let lock = NSLock()
    private var lastChordNs: UInt64 = 0
    private var lastMenuBarClickNs: UInt64 = 0
    private var lastAppChangeNs: UInt64 = 0
    private var reclaimStamps: [UInt64] = []
    private var wasVietTelex = false

    /// Nhánh chord của tap (chạy cho mọi app): một phím kèm ⌘/⌃/⌥ vừa được nhấn.
    /// Bao trùm ⌃Space mặc định lẫn hotkey tự đặt (miễn là có modifier — hotkey đổi
    /// input source của macOS bắt buộc có modifier).
    func noteUserModifierChord() {
        let now = DispatchTime.now().uptimeNanoseconds
        lock.withLock { lastChordNs = now }
    }

    /// Mouse tap: click trong DẢI MENU BAR của màn hình chứa điểm click (44pt đầu
    /// tính từ mép trên display đó — CGEvent.location là toạ độ global, y=0 ở TRÊN).
    func noteClick(at location: CGPoint) {
        guard Self.isInMenuBarStrip(location) else { return }
        let now = DispatchTime.now().uptimeNanoseconds
        lock.withLock { lastMenuBarClickNs = now }
    }

    /// Tách thuần để test: điểm global có nằm trong dải 44pt đầu của display chứa nó
    /// không. `displayBounds` inject được trong test; production dùng CGDisplayBounds.
    static func isInMenuBarStrip(_ p: CGPoint,
                                 displayBounds: (CGPoint) -> CGRect? = StickyInputSource.boundsOfDisplay) -> Bool {
        guard let b = displayBounds(p) else { return false }
        return p.y >= b.minY && p.y <= b.minY + 44
    }

    private static func boundsOfDisplay(_ p: CGPoint) -> CGRect? {
        var display: CGDirectDisplayID = 0
        var count: UInt32 = 0
        guard CGGetDisplaysWithPoint(p, 1, &display, &count) == .success, count > 0 else { return nil }
        return CGDisplayBounds(display)
    }

    /// User vừa CHỦ ĐỘNG đổi input source (chord ≤1s / click dải menu bar ≤5s)?
    /// Dùng chung với SecureInputMonitor.PreBlockSelection (#100): mất VietTelex do
    /// user tự đổi thì hết chặn KHÔNG được chọn lại. Luôn chạy (không phụ thuộc cờ
    /// sticky), chỉ đọc hai timestamp.
    func userGestureRecently(nowNs: UInt64) -> Bool {
        let (chord, menu) = lock.withLock { (lastChordNs, lastMenuBarClickNs) }
        return Self.isUserGesture(nowNs: nowNs, lastChordNs: chord, lastMenuBarClickNs: menu)
    }

    /// App frontmost vừa đổi (≤1.5s)? Dùng cho âm báo: đổi bộ gõ theo app thì im lặng.
    func appChangedRecently(nowNs: UInt64) -> Bool {
        let t = lock.withLock { lastAppChangeNs }
        return t != 0 && nowNs &- t <= Self.appChangeWindowNs
    }

    static func isUserGesture(nowNs: UInt64, lastChordNs: UInt64, lastMenuBarClickNs: UInt64) -> Bool {
        (lastChordNs != 0 && nowNs &- lastChordNs <= gestureWindowNs)
            || (lastMenuBarClickNs != 0 && nowNs &- lastMenuBarClickNs <= menuClickWindowNs)
    }

    // MARK: - Vòng đời

    /// Gọi một lần từ main.swift. Tự theo dõi app activation (timestamp riêng —
    /// FrontmostApp không giữ thời điểm đổi).
    func start() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            let now = DispatchTime.now().uptimeNanoseconds
            self.lock.withLock {
                self.lastAppChangeNs = now
                self.reclaimStamps.removeAll()   // context mới → breaker làm lại từ đầu
            }
        }
        lock.withLock { wasVietTelex = TelexInputController.isVietTelexSelected() }
    }

    /// MAIN thread, từ observer kTISNotifySelectedKeyboardInputSourceChanged.
    func selectionChanged(isVietTelex: Bool) {
        let now = DispatchTime.now().uptimeNanoseconds
        let decision: Bool = lock.withLock {
            let was = wasVietTelex
            wasVietTelex = isVietTelex
            guard AppState.shared.stickyInputSource else { return false }
            reclaimStamps.removeAll { now &- $0 > Self.breakerWindowNs }
            return Self.shouldReclaim(
                wasVietTelex: was, isVietTelexNow: isVietTelex, nowNs: now,
                lastChordNs: lastChordNs, lastMenuBarClickNs: lastMenuBarClickNs,
                lastAppChangeNs: lastAppChangeNs, recentReclaims: reclaimStamps.count)
        }
        guard decision else { return }
        // Đợi document mới ổn định rồi RE-VERIFY toàn bộ điều kiện — trong 150ms
        // user có thể đã tự đổi, app có thể đã đổi, secure input có thể đã bật.
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(Self.reclaimDelayMs)) { [weak self] in
            self?.reclaimIfStillWanted()
        }
    }

    private func reclaimIfStillWanted() {
        guard AppState.shared.stickyInputSource,
              !TelexInputController.isVietTelexSelected(),
              SecureInputMonitor.shared.activeHolder == nil,
              !SecureFieldDetector.isSecure else { return }
        let now = DispatchTime.now().uptimeNanoseconds
        let allowed: Bool = lock.withLock {
            guard Self.reverifyAllowsReclaim(nowNs: now, lastChordNs: lastChordNs,
                                             lastMenuBarClickNs: lastMenuBarClickNs,
                                             lastAppChangeNs: lastAppChangeNs,
                                             recentReclaims: reclaimStamps.count) else { return false }
            reclaimStamps.append(now)
            return true
        }
        guard allowed else { return }
        SwitchSound.noteProgrammaticSwitch()
        let ok = SecureInputMonitor.reselectVietTelex()
        DebugLog.log("sticky-source reclaim: \(ok ? "ok" : "FAILED")")
        Signposts.log.notice("sticky-source reclaim: \(ok ? "ok" : "FAILED", privacy: .public)")
    }

    // MARK: - Heuristic thuần (test được)

    /// Lớp bảo hiểm chạy SAU reclaimDelayMs: cùng các cửa sổ gesture/app-change như
    /// shouldReclaim nhưng với timestamp ĐÃ TƯƠI. Tồn tại vì thứ tự hai notification
    /// (TIS đổi source vs NSWorkspace activate app) không đảm bảo — TIS tới trước
    /// thì shouldReclaim quyết định trên lastAppChangeNs cũ và nói "giành" nhầm ở
    /// ca chuyển app; 150ms sau notification activate chắc chắn đã xử lý xong và
    /// guard này chặn lại.
    static func reverifyAllowsReclaim(nowNs: UInt64, lastChordNs: UInt64,
                                      lastMenuBarClickNs: UInt64, lastAppChangeNs: UInt64,
                                      recentReclaims: Int) -> Bool {
        guard recentReclaims < breakerMax else { return false }
        if lastChordNs != 0, nowNs &- lastChordNs <= gestureWindowNs { return false }
        if lastMenuBarClickNs != 0, nowNs &- lastMenuBarClickNs <= menuClickWindowNs { return false }
        if lastAppChangeNs != 0, nowNs &- lastAppChangeNs <= appChangeWindowNs { return false }
        return true
    }

    /// Quyết định GIÀNH LẠI hay không, tại thời điểm nhận notification đổi input
    /// source. Chỉ giành khi: VietTelex vừa bị RỜI (was=true, now=false), KHÔNG có
    /// gesture chủ động của user trong cửa sổ, app frontmost KHÔNG vừa đổi, và
    /// breaker chưa đầy. `lastAppChangeNs == 0` = chưa từng ghi nhận (mới khởi
    /// động) — coi như không có app change gần đây.
    static func shouldReclaim(wasVietTelex: Bool, isVietTelexNow: Bool, nowNs: UInt64,
                              lastChordNs: UInt64, lastMenuBarClickNs: UInt64,
                              lastAppChangeNs: UInt64, recentReclaims: Int) -> Bool {
        guard wasVietTelex, !isVietTelexNow else { return false }
        guard recentReclaims < breakerMax else { return false }
        if lastChordNs != 0, nowNs &- lastChordNs <= gestureWindowNs { return false }
        if lastMenuBarClickNs != 0, nowNs &- lastMenuBarClickNs <= menuClickWindowNs { return false }
        if lastAppChangeNs != 0, nowNs &- lastAppChangeNs <= appChangeWindowNs { return false }
        return true
    }
}
