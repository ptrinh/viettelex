// InputSourceCacheRefresher.swift
// Issue #158: app cài từ App Store (sandbox) "không thấy" VietTelex và crash khi bấm
// phím tắt đổi bộ gõ.
//
// macOS giữ cho mỗi app một file đệm danh sách bộ gõ:
//   $(getconf DARWIN_USER_CACHE_DIR)<bundle id>/com.apple.IntlDataCache.le(.kbdx)
// File tạo TRƯỚC khi cài VietTelex không được macOS làm mới, kể cả khi mở lại app. Với
// app đó VietTelex coi như không tồn tại: chọn VietTelex không có tác dụng, và bảng chọn
// bộ gõ của hệ thống (chạy trong process của app) tra ID của mình ra NULL rồi CFRelease
// ⇒ app crash. Người báo xoá file đệm, mở lại app là hết (Slack, WhatsApp).
//
// Ở đây làm đúng việc đó, tự động và dè dặt:
//   • chỉ khi VietTelex đang được bật trong danh sách bộ gõ;
//   • chỉ với thư mục đệm của một APP đã cài (không đụng dịch vụ nền của macOS);
//   • chỉ xoá đúng các file com.apple.IntlDataCache.le* (macOS tự tạo lại);
//   • app đang chạy thì chờ nó thoát rồi mới xoá;
//   • mỗi app tối đa một lần / 7 ngày (file tạo lại mà vẫn thiếu thì không xoá mãi).

import AppKit
import Carbon.HIToolbox

enum InputSourceCacheRefresher {

    enum Action: Equatable { case none, deleteNow, waitForQuit }

    static let cachePrefix = "com.apple.IntlDataCache.le"
    static let indexFile = "com.apple.IntlDataCache.le.kbdx"
    static let retryInterval: TimeInterval = 7 * 24 * 3600
    static let defaultsKey = "inputSourceCacheRefreshed"

    // MARK: - Phần thuần (có test)

    /// File đệm không nhắc tới bộ gõ của mình ⇒ cũ. File rỗng/không đọc được ⇒ không kết luận.
    static func cacheIsStale(_ data: Data, marker: String) -> Bool {
        guard !data.isEmpty, let needle = marker.data(using: .utf8), !needle.isEmpty else { return false }
        return data.range(of: needle) == nil
    }

    /// Các file sẽ xoá trong một thư mục đệm: chỉ họ com.apple.IntlDataCache.le*.
    static func cacheFiles(in names: [String]) -> [String] {
        names.filter { $0.hasPrefix(cachePrefix) }.sorted()
    }

    static func decide(stale: Bool, isInstalledApp: Bool, isOwnBundle: Bool, running: Bool,
                       lastRefresh: TimeInterval?, now: TimeInterval) -> Action {
        guard stale, isInstalledApp, !isOwnBundle else { return .none }
        if let last = lastRefresh, now - last < retryInterval, now >= last { return .none }
        return running ? .waitForQuit : .deleteNow
    }

    // MARK: - Chạy thật

    private static let queue = DispatchQueue(label: "com.viettelex.inputsource-cache", qos: .utility)
    private static var started = false

    static func start() {
        guard !started else { return }
        started = true
        // App vừa thoát: nếu file đệm của nó cũ thì đây là lúc xoá an toàn.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let id = app.bundleIdentifier else { return }
            queue.asyncAfter(deadline: .now() + 1) { refresh(bundleIDs: [id], running: []) }
        }
        // Quét một lần sau khi khởi động (sau cài/cập nhật cũng đi qua đây), không chen lúc mở app.
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
            let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
            queue.async { refresh(bundleIDs: nil, running: running) }
        }
    }

    static func cacheRoot() -> URL? {
        var buf = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard confstr(_CS_DARWIN_USER_CACHE_DIR, &buf, buf.count) > 0 else { return nil }
        return URL(fileURLWithPath: String(cString: buf), isDirectory: true)
    }

    private static func vietTelexEnabled() -> Bool {
        let filter = [kTISPropertyBundleID as String: AppState.stableBundleIdentifier] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource]
        else { return false }
        return !list.isEmpty
    }

    /// `bundleIDs` nil = quét mọi thư mục đệm. `running` = app đang chạy (chờ nó thoát).
    private static func refresh(bundleIDs: [String]?, running: Set<String>) {
        guard vietTelexEnabled(), let root = cacheRoot() else { return }
        let fm = FileManager.default
        let ids = bundleIDs ?? ((try? fm.contentsOfDirectory(atPath: root.path)) ?? [])
        let defaults = UserDefaults.standard
        var stamps = defaults.dictionary(forKey: defaultsKey) as? [String: Double] ?? [:]
        let own = Bundle.main.bundleIdentifier ?? AppState.stableBundleIdentifier
        let now = Date().timeIntervalSince1970
        var changed = false
        for id in ids {
            let dir = root.appendingPathComponent(id, isDirectory: true)
            guard let data = try? Data(contentsOf: dir.appendingPathComponent(indexFile), options: .mappedIfSafe),
                  cacheIsStale(data, marker: AppState.stableBundleIdentifier) else { continue }
            let action = decide(
                stale: true,
                isInstalledApp: NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) != nil,
                isOwnBundle: id == own || id.hasPrefix(AppState.stableBundleIdentifier),
                running: running.contains(id), lastRefresh: stamps[id], now: now)
            switch action {
            case .none: continue
            case .waitForQuit:
                DebugLog.log("input-source cache stale for \(id): waiting for it to quit")
            case .deleteNow:
                let names = cacheFiles(in: (try? fm.contentsOfDirectory(atPath: dir.path)) ?? [])
                var removed = 0
                for n in names where (try? fm.removeItem(at: dir.appendingPathComponent(n))) != nil { removed += 1 }
                DebugLog.log("input-source cache stale for \(id): removed \(removed)/\(names.count) file(s)")
                stamps[id] = now
                changed = true
            }
        }
        if changed { defaults.set(stamps, forKey: defaultsKey) }
    }
}
