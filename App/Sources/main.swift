// main.swift
// Process entry point. macOS launches this bundle when the user selects the
// Vietnamese input source; we start an IMKServer and run the event loop.
// No timers, no polling — everything is event driven. The one persistent thread
// besides main is the event tap's run loop (TerminalTapController.start), which
// parks in mach_msg at zero CPU and exists so tap callbacks never queue behind
// main-thread IMKit/UI work.

import Cocoa
import InputMethodKit
import Carbon.HIToolbox

// Held for the process lifetime.
var telexServer: IMKServer?
var inputSourceObserver: NSObjectProtocol?

// MUST be "<bundle id>_Connection" (modern macOS NSConnection convention for input
// methods). The old arbitrary name "VietTelex_Connection" silently broke SANDBOXED
// clients: WhatsApp (MAS) could never connect — no activateServer, no menu section,
// every keystroke swallowed — while non-sandboxed apps (Terminal, Chrome) worked.
let connectionName = (Bundle.main.infoDictionary?["InputMethodConnectionName"] as? String)
    ?? "com.viettelex.inputmethod.telex_Connection"

// XCTest host guard. AppTests use this app as their test host: the process
// launches, XCTest injects the bundle, tests run, the process dies. If that
// throwaway process registers an IMKServer and calls into TCC, it fights the
// REAL installed IME — field day 2026-07-22: the debug-signed host's
// AXIsProcessTrusted checks corrupted the Accessibility row (8 duplicate
// entries, silent denial for the real app) and its IMK registration stole
// client connections. Under XCTest: plain NSApplication run loop, nothing else.
let isTestHost = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

if !isTestHost {
telexServer = IMKServer(name: connectionName, bundleIdentifier: Bundle.main.bundleIdentifier)

// No internal VI/EN toggle: Vietnamese is ON whenever VietTelex is the active macOS
// input source. Switch to another input source (or use macOS's per-app input-source
// memory) to type English — the OS drives everything.

// Prime the frontmost-app cache (registers its NSWorkspace observer) so the per-key
// hot paths never call NSWorkspace.frontmostApplication themselves.
_ = FrontmostApp.shared

// Terminal tap-mode: CGEventTap for apps that ignore replacementRange
// (iTerm, Terminal…). No-op unless Accessibility is granted (Developer ID build);
// re-attempted from activateServer once permission is granted.
TerminalTapController.shared.ensureRunning()

// Authoritative gate for the tap: whenever macOS switches the selected keyboard input
// source, recompute whether VietTelex is active. This catches per-document switching
// (which can restore VietTelex on focus-return without an activateServer call) and
// makes the tap's state independent of the flaky activate/deactivate call ordering.
inputSourceObserver = DistributedNotificationCenter.default().addObserver(
    forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
    object: nil, queue: .main) { _ in
    let isVietTelex = TelexInputController.isVietTelexSelected()
    TerminalTapController.shared.selectionChanged(isVietTelex: isVietTelex)
    // Secure input bật thường kèm macOS đá selection sang ABC — đây là đường
    // phát hiện NHANH; poll 5s của monitor chỉ là lưới an toàn.
    SecureInputMonitor.shared.check(reason: "input-source-changed")
    // Sticky-source (experimental): macOS tự đổi source theo document → giành lại.
    StickyInputSource.shared.selectionChanged(isVietTelex: isVietTelex)
    // Hotkey chuyển bộ gõ: nhớ source non-VietTelex gần nhất làm đích cho chiều
    // VietTelex → khác (xem SwitchHotkey.toggle).
    SwitchHotkey.noteSelection(isVietTelex: isVietTelex,
                               currentID: SwitchHotkey.currentInputSourceID())
}

// "VietTelex bị mờ không rõ nguyên nhân" (field report 14/08/2026): khi có process
// giữ secure input, macOS vô hiệu mọi IME bên thứ ba. Monitor nêu tên thủ phạm
// (menu bar tạm thời + unified log + snapshot) — xem SecureInputMonitor.swift.
SecureInputMonitor.shared.start()

// Sticky-source (experimental, default OFF): giữ VietTelex khi macOS tự đổi input
// source theo document (Word coi mỗi ô comment là một document — field report
// 15/08/2026). Xem StickyInputSource.swift.
StickyInputSource.shared.start()

// Icon menu bar user chọn: SelfUpdater tráo nguyên bundle mỗi lần cập nhật nên
// MenuIcon.pdf quay về mặc định — áp lại lựa chọn đã lưu ở mỗi lần khởi động
// (no-op khi nội dung đã đúng, tức bundle chỉ bị chạm khi user thật sự đổi icon).
MenuIconSwitcher.applyIfNeeded(choice: AppState.shared.menuIcon)

// Accessibility permission toggled (System Settings): react IMMEDIATELY, not on the
// next keystroke. Revoke while the tap is live used to leave a tap macOS keeps
// disabling while we kept re-enabling — a ping-pong that wedged ALL input (keyboard
// AND mouse are in the tap mask). Now: revoked → full teardown (events flow native);
// granted → start the tap without needing an input-source cycle.
var axChangeObserver: NSObjectProtocol?
axChangeObserver = DistributedNotificationCenter.default().addObserver(
    forName: NSNotification.Name("com.apple.accessibility.api"),
    object: nil, queue: .main) { _ in
    // No trust check here — right after the toggle tccd can still report the OLD
    // value (that race skipped the teardown in build 7 and the wedged tap
    // survived). trustMayHaveChanged tears down unconditionally and re-creates
    // ~1.5s later iff genuinely trusted.
    TerminalTapController.shared.trustChangedExternally()
}

}  // end !isTestHost

// Standard editing key equivalents (⌘A/⌘C/⌘V/⌘X/⌘Z, ⌘W) inside our OWN Settings
// window. macOS dispatches key equivalents through the app's main menu — an
// LSUIElement agent has no visible menu bar, but without a mainMenu object the
// events go nowhere and ⌘A in the filter/shortcut fields does nothing. The menu
// is never shown; it exists purely as the responder-chain routing table.
let mainMenu = NSMenu()

let editItem = NSMenuItem()
let editMenu = NSMenu(title: "Edit")
editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
editMenu.addItem(.separator())
editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
editItem.submenu = editMenu
mainMenu.addItem(editItem)

let windowItem = NSMenuItem()
let windowMenu = NSMenu(title: "Window")
windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
windowItem.submenu = windowMenu
mainMenu.addItem(windowItem)

NSApplication.shared.mainMenu = mainMenu

// Mở lại app bundle (double-click VietTelex.app trong /Library/Input Methods,
// hoặc `open -b com.viettelex.inputmethod.telex`) → hiện Cài đặt. Lối thoát khi
// menu input source không dùng được — issue #61 (25/08/2026): BetterMouse chen
// event tap làm TextInputMenuAgent chỉ vẽ được "…" thay cho menu của mình; user
// không còn đường nào tới Cài đặt. macOS gửi reopen cho instance đang chạy
// (LaunchServices không spawn process IME thứ hai), nên delegate này là đủ.
final class ReopenDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldHandleReopen(_ sender: NSApplication,
                                       hasVisibleWindows flag: Bool) -> Bool {
        if !isTestHost { SettingsWindowController.shared.show(tab: .general) }
        return false
    }
}
let reopenDelegate = ReopenDelegate()          // held for the process lifetime
NSApplication.shared.delegate = reopenDelegate

NSApplication.shared.run()
