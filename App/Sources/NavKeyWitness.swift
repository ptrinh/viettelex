import Foundation

/// Word tables (Facebook report 22/08/2026, maintainer repro 23/08) swallow the
/// Tab/arrow cell-navigation WITHOUT forwarding the key to the IME: handle() never
/// sees a boundary, the controller keeps composing the previous cell's word, and
/// the next tone edit replaces text at the OLD anchor — Word's offsets are
/// document-global, so that write lands in the previous cell and yanks the caret
/// back there.
///
/// The CGEventTap DOES see every physical key (same process). It stamps navigation
/// keycodes here (tap thread); the IMKit controller consumes at handle() entry
/// (main thread):
/// - the SAME keycode arriving = the app delivered the key normally → the Tab/arrow
///   boundary path runs exactly as before (auto-restore on Tab etc. intact).
/// - a DIFFERENT key arriving while a stamp is pending = the app swallowed the nav
///   key → the word this key would continue was in fact ended somewhere else; the
///   controller must drop its composition before processing the key.
/// Mouse clicks already have this contract via .telexResetComposition — that is why
/// clicking into the next cell worked while Tab did not.
///
/// Without Accessibility (no tap) there is no witness and the Word-table case
/// stays broken — same dependency as every other tap-assisted repair.
enum NavKeyWitness {
    /// Tab, Home, PgUp, End, PgDn, ←, →, ↓, ↑ — keys that move the caret/focus.
    /// ⌘/⌃/⌥ chords never reach stamp() (the tap's chord block returns first);
    /// Shift is allowed — Shift+Tab is the back-cell navigation in Word tables.
    static let navKeycodes: Set<Int64> = [48, 115, 116, 119, 121, 123, 124, 125, 126]

    private static let lock = NSLock()
    private static var pending: Int64 = -1

    /// Tap thread, once per physical keyDown that the tap passes through.
    /// Non-navigation keycodes are ignored (one Set lookup on the hot path).
    static func stamp(keycode: Int64) {
        guard navKeycodes.contains(keycode) else { return }
        lock.lock(); pending = keycode; lock.unlock()
    }

    /// Controller (main thread) at handle() entry, for every real keyDown.
    /// Returns true iff a stamped nav key was never delivered to the IME — the
    /// caller must drop its composition before handling `keycode`.
    static func consume(keycode: Int64) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard pending >= 0 else { return false }
        let swallowed = pending != keycode
        pending = -1
        return swallowed
    }

    /// Focus moved to another client (activateServer): a stamp left by the previous
    /// app must not leak a drop into the next app's first key.
    static func reset() {
        lock.lock(); pending = -1; lock.unlock()
    }
}
