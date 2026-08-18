// SecureInputMonitor.swift
// "VietTelex thỉnh thoảng bị mờ (disabled) không rõ nguyên nhân" — field report
// Facebook 14/08/2026 (Vũ Đình Trường An, kèm ảnh: VietTelex mờ trong picker, ABC
// được auto-chọn; user nghi "do đang SSH").
//
// Nguyên nhân thật: một process đang giữ SECURE EVENT INPUT (Terminal/iTerm2 bật
// "Secure Keyboard Entry", ô password treo quyền, loginwindow…). Khi secure input
// active, macOS vô hiệu MỌI IME bên thứ ba — dòng "ViệtTelex" mờ trong picker là
// TextInputMenuAgent vẽ từ metadata tĩnh của bundle, mình không sửa động được, và
// IMK menu của mình cũng không mở được vì không chọn được input source.
//
// Không chặn được (policy của OS), nhưng biến "không rõ nguyên nhân" thành "có tên
// thủ phạm" thì được, vì PROCESS NÀY VẪN SỐNG khi bị mờ (IMKServer không bị kill):
//  1. Icon menu bar TẠM THỜI chỉ hiện khi đang bị chặn, ghi rõ thủ phạm + PID,
//     tự biến mất khi hết chặn.
//  2. Transition ON/OFF ghi unified log (LUÔN — kể cả khi debugLogging off; sự kiện
//     hiếm, không có text người dùng) + DebugLog ring.
//  3. Dòng "Secure input:" trong debug snapshot (click Status: OK) và IMK menu.
//
// Phát hiện: notification input-source-changed là đường nhanh (secure input bật
// thường kèm macOS đá selection sang ABC), poll 5s là lưới an toàn — vi phạm có chủ
// đích ethos "no timers" của main.swift (tiền lệ: trustPoll) vì lúc bị chặn thì
// chính là lúc KHÔNG có event nào tới được mình.

import AppKit
import Carbon.HIToolbox
import IOKit
import Darwin

final class SecureInputMonitor {
    static let shared = SecureInputMonitor()

    struct Holder: Equatable {
        let pid: pid_t
        let name: String?
        /// false = PID giữ khoá ĐÃ CHẾT mà macOS chưa nhả — khoá mồ côi, chỉ
        /// logout/login mới gỡ (field case 18/08/2026: Lark quit không nhả, ps trống
        /// mà ioreg vẫn báo giữ). Equatable nên sống→chết tự thành một transition
        /// mới được log. pid 0 (không rõ ai giữ) coi như alive để khỏi khuyên láo.
        let alive: Bool
        /// "iTerm2 (PID 12345)" / "PID 12345" / "PID 12345, exited" — English on
        /// purpose: goes into logs and bug reports, where greppability beats l10n.
        var label: String {
            let base = name.map { "\($0) (PID \(pid))" } ?? "PID \(pid)"
            return alive ? base : base + ", exited"
        }
    }

    /// Process còn sống không — kill(pid, 0) không gửi signal, chỉ hỏi tồn tại;
    /// EPERM nghĩa là "sống nhưng không phải của mình" nên vẫn tính là sống.
    static func processIsAlive(_ pid: pid_t) -> Bool {
        guard pid > 0 else { return true }
        return kill(pid, 0) == 0 || errno == EPERM
    }

    /// nil = secure input off. Non-nil = active; Holder mô tả thủ phạm (pid 0 nếu
    /// IOKit không nêu tên — hiếm, nhưng "active mà không rõ ai" vẫn đáng báo).
    private(set) var activeHolder: Holder?
    private var timer: Timer?
    private var statusItem: NSStatusItem?

    /// VietTelex có đang là selection của user không — chốt lần cuối TRƯỚC khi bị
    /// chặn. Cập nhật ở mỗi lần check lúc secure input off; đóng băng suốt lúc bị
    /// chặn (vì khi đó selection đã bị macOS đá sang ABC, đọc nữa là mất sự thật).
    private var selectedBeforeBlock = false

    /// Poll chỉ để bắt transition; mọi công việc thật nằm sau guard "có đổi không".
    func start() {
        check(reason: "startup")
        let t = Timer(timeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.check(reason: "poll")
        }
        t.tolerance = 2.0   // coalesce với wakeup khác — đây là lưới an toàn, không cần đúng nhịp
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Re-check ngay khi có tín hiệu rẻ (đổi input source, mở snapshot). Idempotent,
    /// main-thread only (NSStatusItem).
    func check(reason: String) {
        let active = IsSecureEventInputEnabled()
        let holder: Holder? = active
            ? Self.secureInputPID().map { Holder(pid: $0, name: Self.processName($0),
                                                 alive: Self.processIsAlive($0)) }
                ?? Holder(pid: 0, name: nil, alive: true)
            : nil
        if !active, activeHolder == nil {
            // Trạng thái yên bình: ghi nhớ selection thật của user cho lần chặn sau.
            selectedBeforeBlock = TelexInputController.isVietTelexSelected()
            return
        }
        guard holder != activeHolder else { return }
        let was = activeHolder
        activeHolder = holder
        if let h = holder {
            // Thẳng vào unified log không qua guard debugLogging của DebugLog.log —
            // sự kiện này cần dấu vết CẢ KHI user chưa kịp bật debug (chính là ca
            // "thỉnh thoảng, không tái hiện được").
            Signposts.log.notice("secure-input ON — held by \(h.label, privacy: .public) [\(reason, privacy: .public)]")
            DebugLog.log("secure-input ON — held by \(h.label) [\(reason)]")
        } else if let w = was {
            Signposts.log.notice("secure-input OFF — was \(w.label) [\(reason, privacy: .public)]")
            DebugLog.log("secure-input OFF — was \(w.label) [\(reason)]")
            // Trả lại selection mà secure input đã cướp: macOS đá sang ABC khi chặn
            // nhưng KHÔNG tự trả về IME bên thứ ba khi hết chặn — user phải tự chọn
            // lại bằng tay (field report 14/08). Chỉ chọn lại khi TRƯỚC lúc chặn
            // VietTelex đang được chọn — không bao giờ cướp selection user tự đổi.
            if selectedBeforeBlock, !TelexInputController.isVietTelexSelected() {
                let ok = Self.reselectVietTelex()
                Signposts.log.notice("secure-input OFF — reselect VietTelex: \(ok ? "ok" : "FAILED", privacy: .public)")
                DebugLog.log("secure-input reselect: \(ok ? "ok" : "FAILED")")
            }
        }
        updateStatusItem()
    }

    /// Dòng trạng thái cho snapshot + IMK menu. English cho snapshot-side.
    var snapshotLine: String {
        activeHolder.map { "Secure input: ACTIVE — held by \($0.label)" } ?? "Secure input: off"
    }

    // MARK: - Icon menu bar tạm thời

    /// Chỉ tồn tại khi đang bị chặn: user nhìn lên là biết tại sao VietTelex mờ,
    /// không cần mở gì thêm. Biến mất là hết chuyện — không thêm icon thường trực.
    private func updateStatusItem() {
        guard let holder = activeHolder else {
            if let item = statusItem { NSStatusBar.system.removeStatusItem(item) }
            statusItem = nil
            return
        }
        let item = statusItem ?? NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        item.button?.title = "Vᵀ⃠"
        item.button?.toolTip = VTLocalized("Vietnamese typing is blocked (Secure Input)")
        let menu = NSMenu()
        let info = NSMenuItem(title: "Disabled: Secure entry — \(holder.label)",
                              action: nil, keyEquivalent: "")
        info.isEnabled = false
        menu.addItem(info)
        // Gợi ý theo ĐÚNG bệnh: khoá mồ côi (process chết không nhả — chỉ logout gỡ
        // được) khác hẳn Secure Keyboard Entry bật quên (tắt trong menu app là xong).
        // Khoá mồ côi: mẹo khoá-màn-hình FIELD-VERIFIED 18/08/2026 (ca Lark) — lock
        // làm loginwindow chiếm secure input rồi nhả khi mở, ghi đè record kẹt.
        // Rẻ hơn logout nhiều nên khuyên trước; logout là đường chắc chắn dự phòng.
        let hintText = holder.alive
            ? VTLocalized("If this is Terminal/iTerm2: turn off “Secure Keyboard Entry”")
            : VTLocalized("That process exited but the lock is stuck — lock the screen (⌃⌘Q) and unlock; if that fails, log out and back in")
        let hint = NSMenuItem(title: hintText, action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)
        item.menu = menu
    }

    // MARK: - Tự kết nối lại sau khi hết chặn

    /// Chọn lại input source của chính mình qua TIS. Chỉ gọi sau transition OFF —
    /// gọi trong lúc secure input còn active sẽ fail (IME vẫn bị vô hiệu).
    static func reselectVietTelex() -> Bool {
        guard let list = TISCreateInputSourceList(nil, false)?
            .takeRetainedValue() as? [TISInputSource] else { return false }
        for source in list {
            guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID)
            else { continue }
            let id = Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
            if TelexInputController.inputSourceIsOurs(id) {
                return TISSelectInputSource(source) == noErr
            }
        }
        return false
    }

    // MARK: - Thủ phạm từ IOKit

    /// PID đang giữ secure input, đọc từ property `IOConsoleUsers` của registry root
    /// (đúng nguồn `ioreg -l | grep kCGSSessionSecureInputPID` đọc). nil khi không có.
    static func secureInputPID() -> pid_t? {
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        guard root != 0 else { return nil }
        defer { IOObjectRelease(root) }
        guard let users = IORegistryEntryCreateCFProperty(
            root, "IOConsoleUsers" as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue() as? [[String: Any]] else { return nil }
        return extractSecureInputPID(consoleUsers: users)
    }

    /// Tách thuần để test được: session dict nào mang kCGSSessionSecureInputPID > 0.
    static func extractSecureInputPID(consoleUsers: [[String: Any]]) -> pid_t? {
        for session in consoleUsers {
            if let pid = session["kCGSSessionSecureInputPID"] as? Int, pid > 0 {
                return pid_t(pid)
            }
        }
        return nil
    }

    /// Tên process: NSRunningApplication cho app có UI, proc_name cho daemon/CLI.
    static func processName(_ pid: pid_t) -> String? {
        if let app = NSRunningApplication(processIdentifier: pid),
           let name = app.localizedName { return name }
        var buf = [CChar](repeating: 0, count: 256)
        guard proc_name(pid, &buf, UInt32(buf.count)) > 0 else { return nil }
        return String(cString: buf)
    }
}
