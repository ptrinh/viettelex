// QtKeymapFix.swift — issue #131: ⌫ / ⌦ dead in DaVinci Resolve's Media Pool.
//
// ROOT CAUSE (not in VietTelex's key handling — handle() is never even called for
// those keys; the reporter's debug log has no "handle ENTER" line):
//
// Qt 5's Cocoa key mapper (qtbase 5.12–5.15, src/plugins/platforms/cocoa/
// qcocoakeymapper.mm, QCocoaKeyMapper::updateKeyboard) resolves SHORTCUTS through
//
//     source = TISCopyInputMethodKeyboardLayoutOverride();
//     if (!source) source = TISCopyCurrentKeyboardInputSource();
//     data = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData);
//
// With ANY IMKit input method selected (VietTelex, Pinyin, …) the current source is
// the input MODE, which carries no `uchr` data, so the mapper falls into NullMode and
// updateKeyMap derives the key from `QChar(event->key())` — Qt::Key_Backspace
// (0x01000003) truncated to 0x0003 == kEnterCharCode, which its symbol table maps to
// Qt::Key_Enter. A "Backspace"/"Delete" QAction shortcut (Media Pool → delete clip)
// therefore never matches. Widgets that handle the key in keyPressEvent (text fields,
// the timeline) still work, which is exactly the report. Forward Delete breaks the
// same way (0x01000007 → 0x0007 → unknown).
//
// It also explains why the per-app "Passthrough" workaround does NOT help: it only
// makes handle() return false; the selected input source is still VietTelex, so Qt
// still finds no layout. Only switching to ABC (a real layout) fixes it by hand.
//
// FIX: Qt asks for the input-method layout OVERRIDE first. Setting it from inside the
// IME process is inert (KeyboardLayoutOverride's header: TISSet… readback = none), but
// IMKTextInput.overrideKeyboard(withKeyboardNamed:) is applied in the CLIENT's process,
// where Qt reads it. We name the layout macOS is ALREADY translating with (the "live"
// layout, TISCopyCurrentKeyboardLayoutInputSource), so key translation for typing is
// unchanged — Qt merely gets the uchr data it needs to resolve ⌫/⌦ shortcuts.
//
// SCOPE / COST: only for Qt clients (Qt libs in the bundle, or a known Qt vendor),
// decided once per bundle id and cached; applied in activateServer (focus change),
// never on the keystroke path. Every non-Qt app pays one dictionary lookup per
// activation. Qt 6 maps through -[NSEvent charactersByApplyingModifiers:] and is not
// affected, but the override is harmless there (same layout), so no version sniffing.
//
// MAIN THREAD ONLY (activateServer): `cache` and `lastLogged` are unsynchronized.

import AppKit
import Carbon
import InputMethodKit

enum QtKeymapFix {

    // MARK: - Pure (AppTests)

    /// Bundle-id prefixes of vendors whose apps are Qt, for when the bundle layout
    /// can't be read (DaVinci Resolve, Fusion, ATEM Software Control…).
    static let knownQtBundlePrefixes = ["com.blackmagic-design."]

    static func isKnownQtBundle(_ id: String) -> Bool {
        knownQtBundlePrefixes.contains { id.hasPrefix($0) }
    }

    /// True for a file/dir name that is Qt's core library as apps ship it:
    /// `QtCore.framework` (macdeployqt), `libQt5Core.5.dylib`, `libQt6Core.dylib`…
    static func isQtCoreName(_ name: String) -> Bool {
        let n = name.lowercased()
        return n == "qtcore.framework" || n == "qtcore"
            || n.hasPrefix("libqt5core") || n.hasPrefix("libqt6core") || n.hasPrefix("libqtcore")
    }

    /// One directory listing (Contents/Frameworks, Contents/Libraries, Contents/MacOS).
    static func looksLikeQt(entries: [String]) -> Bool {
        entries.contains(where: isQtCoreName)
    }

    /// The layout to hand the client, or nil to leave it alone. `live` is the keyboard
    /// layout macOS is translating with right now (never an input mode).
    static func overrideLayout(isQt: Bool, live: String?) -> String? {
        guard isQt, let live, !live.isEmpty, live != "?" else { return nil }
        return live
    }

    // MARK: - Side effects (activateServer)

    private static var cache: [String: Bool] = [:]
    private static var lastLogged: String?

    /// Re-asserted on every activation of a Qt client (macOS may drop the override
    /// across an input-source cycle; Qt toggles the input context as focus moves).
    static func apply(client: IMKTextInput, bundleID: String?) {
        guard let id = bundleID, !id.isEmpty, isQt(id) else { return }
        guard let layout = overrideLayout(isQt: true, live: KeyboardLayoutOverride.liveLayoutID()) else { return }
        client.overrideKeyboard(withKeyboardNamed: layout)
        let line = "qt-keymap \(id): overrideKeyboard → \(layout) (#131 ⌫/⌦ shortcuts)"
        if line != lastLogged { lastLogged = line; DebugLog.log(line) }
    }

    /// Cached per bundle id. A client with no running app behind it (XPC helper) is
    /// answered from the vendor list and NOT cached, so a later activation of the real
    /// app can still be scanned.
    private static func isQt(_ id: String) -> Bool {
        if let hit = cache[id] { return hit }
        if isKnownQtBundle(id) { cache[id] = true; return true }
        guard let url = NSRunningApplication.runningApplications(withBundleIdentifier: id).first?.bundleURL
        else { return false }
        let fm = FileManager.default
        let verdict = ["Contents/Frameworks", "Contents/Libraries", "Contents/MacOS"].contains { sub in
            (try? fm.contentsOfDirectory(atPath: url.appendingPathComponent(sub).path))
                .map(looksLikeQt(entries:)) ?? false
        }
        cache[id] = verdict
        return verdict
    }
}
