// SecureInputMonitor.swift
// "VietTelex thỉnh thoảng bị mờ (disabled) không rõ nguyên nhân" — field report
// Facebook 14/08/2026 (Vũ Đình Trường An, kèm ảnh: VietTelex mờ trong picker, ABC
// được auto-chọn; user nghi "do đang SSH").
//
// Nguyên nhân thật: một process đang giữ SECURE EVENT INPUT (Terminal/iTerm2 bật
// "Secure Keyboard Entry", ô password treo quyền, loginwindow, 1Password sau
// sleep…). Khi secure input active, macOS vô hiệu MỌI IME bên thứ ba — dòng
// "ViệtTelex" mờ trong picker là TextInputMenuAgent vẽ từ metadata tĩnh của
// bundle, mình không sửa động được, và IMK menu của mình cũng không mở được vì
// không chọn được input source.
//
// Không chặn được (policy của OS — không có API nhả hộ, kẻo malware cũng làm
// được), nhưng biến "không rõ nguyên nhân" thành "có tên thủ phạm" thì được, vì
// PROCESS NÀY VẪN SỐNG khi bị mờ (IMKServer không bị kill):
//  1. Icon menu bar TẠM THỜI chỉ hiện khi đang bị chặn, ghi rõ thủ phạm + PID,
//     tự biến mất khi hết chặn. Gợi ý theo ĐÚNG bệnh (1Password sau sleep ≠
//     Terminal Secure Keyboard Entry ≠ khoá mồ côi).
//  2. Transition ON/OFF ghi unified log (LUÔN — kể cả khi debugLogging off; sự kiện
//     hiếm, không có text người dùng) + DebugLog ring.
//  3. Dòng "Secure input:" trong debug snapshot (click Status: OK) và IMK menu.
//
// Phát hiện: notification input-source-changed là đường nhanh (secure input bật
// thường kèm macOS đá selection sang ABC); didWake / screenIsUnlocked bắt ca
// 1Password-sau-sleep ngay khi mở máy (ioreg hay báo NHẦM loginwindow); poll 5s
// là lưới an toàn — vi phạm có chủ đích ethos "no timers" của main.swift (tiền
// lệ: trustPoll) vì lúc bị chặn thì chính là lúc KHÔNG có event nào tới được mình.

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

    /// Gợi ý theo bệnh, tách thuần để test được. ioreg SAU SLEEP hay ghi
    /// loginwindow trong khi 1Password mới là process EnableSecureEventInput
    /// (1Password Community #25015, 07/2026: password field vẫn highlighted dù
    /// app khác đang focus; quit 1Password hoặc click vào rồi click ra mới nhả).
    enum HintKind: Equatable {
        case orphan
        case passwordManager(String)
        case loginwindowWithPasswordManager(String)
        case loginwindowStuck
        case terminal
        case generic
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
    private var settleWork: DispatchWorkItem?
    private var statusItem: NSStatusItem?
    private var workspaceObservers: [NSObjectProtocol] = []

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

        // 1Password (và loginwindow) bật SI lúc lock/sleep; IME bị mờ TRƯỚC khi
        // input-source-changed hay poll 5s kịp chạy. Check ngay + một nhịp settle
        // vì UI khoá của 1Password hiện SAU khi loginwindow nhả.
        // NSWorkspace không có screensDidUnlockNotification (SDK 13); unlock đi
        // qua DistributedNotificationCenter `com.apple.screenIsUnlocked`.
        let nc = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(nc.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.checkSoon(reason: "wake")
        })
        workspaceObservers.append(nc.addObserver(
            forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.checkSoon(reason: "screens-wake")
        })
        workspaceObservers.append(DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.checkSoon(reason: "unlock")
        })
    }

    /// Check ngay, rồi một lần nữa sau 1.2s. Coalesce wake+unlock thành một settle.
    func checkSoon(reason: String) {
        check(reason: reason)
        settleWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.check(reason: reason + "-settle")
        }
        settleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
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
        guard holder != activeHolder else {
            // PID không đổi, nhưng HINT có thể đổi: sau sleep ioreg vẫn ghi
            // loginwindow trong khi 1Password đã kịp hiện ô mật khẩu.
            if holder != nil { updateStatusItem() }
            return
        }
        let was = activeHolder
        activeHolder = holder
        if let h = holder {
            // Thẳng vào unified log không qua guard debugLogging của DebugLog.log —
            // sự kiện này cần dấu vết CẢ KHI user chưa kịp bật debug (chính là ca
            // "thỉnh thoảng, không tái hiện được").
            let kind = currentHintKind(holder: h)
            Signposts.log.notice("secure-input ON — held by \(h.label, privacy: .public) [\(reason, privacy: .public)]")
            DebugLog.log("secure-input ON — held by \(h.label) [\(reason)]")
            if case .loginwindowWithPasswordManager(let pm) = kind {
                Signposts.log.notice("secure-input ON — ioreg names loginwindow, \(pm, privacy: .public) is running (common false attribution after sleep)")
                DebugLog.log("secure-input ON — ioreg names loginwindow, \(pm) is running (common false attribution after sleep)")
            }
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
        guard let holder = activeHolder else { return "Secure input: off" }
        switch currentHintKind(holder: holder) {
        case .loginwindowWithPasswordManager(let pm):
            return "Secure input: ACTIVE — held by \(holder.label) (likely \(pm) after sleep)"
        case .passwordManager:
            return "Secure input: ACTIVE — held by \(holder.label) (password manager)"
        default:
            return "Secure input: ACTIVE — held by \(holder.label)"
        }
    }

    // MARK: - Phân loại gợi ý

    static func looksLikePasswordManager(_ name: String?) -> Bool {
        guard let raw = name?.lowercased(), !raw.isEmpty else { return false }
        let needles = ["1password", "agilebits", "bitwarden", "lastpass", "keepass"]
        return needles.contains { raw.contains($0) }
    }

    static func looksLikeLoginwindow(_ name: String?) -> Bool {
        guard let raw = name?.lowercased() else { return false }
        return raw.contains("loginwindow") || raw == "login window"
    }

    static func looksLikeTerminal(_ name: String?) -> Bool {
        guard let raw = name?.lowercased() else { return false }
        return raw.contains("terminal") || raw.contains("iterm")
            || raw.contains("alacritty") || raw.contains("wezterm")
            || raw.contains("ghostty") || raw == "kitty"
    }

    static func canonicalPasswordManagerName(_ name: String) -> String {
        let n = name.lowercased()
        if n.contains("1password") || n.contains("agilebits") { return "1Password" }
        if n.contains("bitwarden") { return "Bitwarden" }
        if n.contains("lastpass") { return "LastPass" }
        if n.contains("keepass") { return "KeePassXC" }
        return name
    }

    static func classifyHint(holderName: String?, holderAlive: Bool,
                             runningPasswordManagers: [String]) -> HintKind {
        if !holderAlive { return .orphan }
        if looksLikePasswordManager(holderName) {
            return .passwordManager(canonicalPasswordManagerName(holderName ?? "1Password"))
        }
        if looksLikeLoginwindow(holderName), let pm = runningPasswordManagers.first {
            return .loginwindowWithPasswordManager(pm)
        }
        if looksLikeLoginwindow(holderName) { return .loginwindowStuck }
        if looksLikeTerminal(holderName) { return .terminal }
        return .generic
    }

    static func runningPasswordManagerNames() -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for app in NSWorkspace.shared.runningApplications {
            let blob = ((app.bundleIdentifier ?? "") + " " + (app.localizedName ?? "")).lowercased()
            guard looksLikePasswordManager(blob) else { continue }
            let display = canonicalPasswordManagerName(app.localizedName ?? app.bundleIdentifier ?? "1Password")
            if seen.insert(display).inserted { out.append(display) }
        }
        return out
    }

    private func currentHintKind(holder: Holder) -> HintKind {
        Self.classifyHint(holderName: holder.name, holderAlive: holder.alive,
                          runningPasswordManagers: Self.runningPasswordManagerNames())
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

        let kind = currentHintKind(holder: holder)
        let hint = NSMenuItem(title: Self.hintText(kind), action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)

        if let pm = Self.revealTarget(kind) {
            menu.addItem(.separator())
            let reveal = NSMenuItem(
                title: String(format: VTLocalized("Switch to %@ (then click away)"), pm),
                action: #selector(MenuActions.revealPasswordManager(_:)),
                keyEquivalent: "")
            reveal.target = MenuActions.shared
            menu.addItem(reveal)
        }
        item.menu = menu
    }

    static func hintText(_ kind: HintKind) -> String {
        switch kind {
        case .orphan:
            return VTLocalized("That process exited but the lock is stuck — lock the screen (⌃⌘Q) and unlock; if that fails, log out and back in")
        case .passwordManager(let pm):
            return String(format: VTLocalized("%@ left Secure Input on — click its window then click away, or quit it"), pm)
        case .loginwindowWithPasswordManager(let pm):
            return String(format: VTLocalized("loginwindow is listed, but %@ often holds Secure Input after sleep — click it then click away, or quit it"), pm)
        case .loginwindowStuck:
            return VTLocalized("loginwindow is holding Secure Input after sleep — lock the screen (⌃⌘Q) and unlock")
        case .terminal:
            return VTLocalized("If this is Terminal/iTerm2: turn off “Secure Keyboard Entry”")
        case .generic:
            return VTLocalized("An app is holding Secure Input (a password field) — click away from that field, or quit the app named above")
        }
    }

    static func revealTarget(_ kind: HintKind) -> String? {
        switch kind {
        case .passwordManager(let pm), .loginwindowWithPasswordManager(let pm):
            return pm
        default:
            return nil
        }
    }

    /// Đưa password manager lên trước — workaround field-verified: focus rồi unfocus
    /// làm nó gọi DisableSecureEventInput. Không nhả hộ được (không có API).
    static func activatePasswordManager() {
        let apps = NSWorkspace.shared.runningApplications.filter { app in
            let blob = ((app.bundleIdentifier ?? "") + " " + (app.localizedName ?? "")).lowercased()
            return looksLikePasswordManager(blob)
        }
        let preferred = apps.first {
            ($0.bundleIdentifier ?? "").lowercased().contains("1password.1password")
        } ?? apps.first {
            let id = ($0.bundleIdentifier ?? "").lowercased()
            return !id.contains("helper") && !id.contains("safari")
        } ?? apps.first
        if #available(macOS 14.0, *) {
            preferred?.activate()
        } else {
            preferred?.activate(options: [.activateIgnoringOtherApps])
        }
    }

    private final class MenuActions: NSObject {
        static let shared = MenuActions()
        @objc func revealPasswordManager(_ sender: Any) {
            SecureInputMonitor.activatePasswordManager()
        }
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
