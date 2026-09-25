// SyntheticInputGuard.swift — ngừng MỌI phím giả lập khi một app chống-giả-lập đang
// có cửa sổ trên màn hình.
//
// Little Snitch (field 22 + 25/09/2026): "Simulated Input Ignored — From: VietTelex".
// Nó từ chối phím synthetic khi cảnh báo kết nối / cửa sổ của nó đang mở (chống app
// khác bấm "Allow" hộ). Rule inPlace cho LS Agent chỉ phủ việc GÕ TRONG LS; hai
// nguồn còn lại vẫn chạm tới nó: phím F20 kiểm tra sức khoẻ của watchdog (3s/lần khi
// đang gõ, bất kể app nào ở trước) và backspace-retype của tap khi cảnh báo LS
// (panel không kích hoạt app) nổi lên đúng lúc gõ ở Chrome.
//
// Chi phí (đo 25/09/2026): ~0,5 ms CPU mỗi refresh, CHỈ khi đang gõ (tick watchdog
// 3s, nhánh không-idle) — máy không ai gõ thì 0. Hot path của tap chỉ đọc một Bool.

import Cocoa

enum SyntheticInputGuard {
    /// Bundle-id prefixes of apps that reject synthetic input.
    static let guardBundlePrefixes = ["at.obdev.littlesnitch"]

    /// Menu-bar layer (status items sit here forever) — never counts as "a window up".
    static let statusLayer = 25

    private static let lock = NSLock()
    nonisolated(unsafe) private static var _active = false
    static var isActive: Bool { lock.withLock { _active } }

    static func isGuardApp(_ bundleID: String?) -> Bool {
        guard let id = bundleID else { return false }
        return guardBundlePrefixes.contains { id.hasPrefix($0) }
    }

    /// Pure: is any on-screen, non-status-bar window owned by a guard process?
    static func guardWindowUp(windows: [(ownerPID: pid_t, layer: Int)], guardPIDs: Set<pid_t>) -> Bool {
        guard !guardPIDs.isEmpty else { return false }
        return windows.contains { guardPIDs.contains($0.ownerPID) && $0.layer != statusLayer }
    }

    /// Idle: forget the last verdict (no scan while nobody types).
    static func clear() { lock.withLock { _active = false } }

    /// Recompute. Call off the tap thread (watchdog tick, typing-active only).
    static func refresh() {
        let pids = Set(NSWorkspace.shared.runningApplications
            .filter { isGuardApp($0.bundleIdentifier) }
            .map(\.processIdentifier))
        var up = false
        if !pids.isEmpty {
            let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                  kCGNullWindowID) as? [[String: Any]] ?? []
            let windows = info.compactMap { w -> (ownerPID: pid_t, layer: Int)? in
                guard let pid = w[kCGWindowOwnerPID as String] as? Int32,
                      let layer = w[kCGWindowLayer as String] as? Int else { return nil }
                return (pid, layer)
            }
            up = guardWindowUp(windows: windows, guardPIDs: pids)
        }
        let changed: Bool = lock.withLock { defer { _active = up }; return _active != up }
        if changed { DebugLog.log("synthetic-input guard \(up ? "ON (Little Snitch window up)" : "OFF")") }
    }
}
