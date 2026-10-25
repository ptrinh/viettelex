// KeyboardLayoutOverride.swift
// Ported from the VTX fork (github.com/xkhanhs/vtx, MIT) — credit: xkhanhs, who
// measured both documented OS routes inert on macOS 26 (see below).
// Pins the physical-key → character mapping VietTelex composes on, so Telex types the
// same way no matter which input source the user switched FROM.
//
// THE PROBLEM: an IMKit input method owns no keyboard layout. macOS keeps whichever
// ASCII layout was selected before the switch and translates key events with it, so
// the SAME input method composes on a different keyboard depending on switch history.
// Measured 2026-08-13 with TISCopyCurrentKeyboardLayoutInputSource:
//
//     ABC     → VietTelex   ⇒ current layout = com.apple.keylayout.ABC
//     Colemak → VietTelex   ⇒ current layout = com.apple.keylayout.Colemak
//
// For someone learning Colemak that is not a preference — it is a coin flip decided
// by where they happened to be a moment earlier.
//
// WHAT DOES NOT WORK: TISSetInputMethodKeyboardLayoutOverride, which reads like
// Apple's mechanism for exactly this. On macOS 26 it is INERT. It returns noErr, and
// then macOS discards the value — measured from inside the input-method process, at
// activateServer, with the app selected (2026-08-13):
//
//     layout-override com.apple.keylayout.ABC: ok stored=(none) live=…Colemak
//
// `stored` is TISCopyInputMethodKeyboardLayoutOverride read back immediately after
// the successful set. Nothing was kept, and `live` went on mirroring whichever
// source the user switched in from. Do not "restore" this call: noErr from it means
// nothing, so any future change here needs the same stored/live readback as proof.
//
// ALSO DOES NOT WORK: a selection BOUNCE — select the wanted layout, then re-select
// ourselves, automating the workaround users find by hand ("switch to ABC, type a
// bit, switch back"). Both selections return noErr and the layout does not move
// (2026-08-13):
//
//     layout-override …ABC: bounce …Colemak→…Colemak (0,0)
//
// Presumably macOS restores the layout an input method was last entered with, so
// leaving and re-entering reinstates the very binding we were trying to replace.
//
// WHAT WORKS: doing the mapping ourselves. KeyboardLayoutTranslator turns keyCode
// into the character the PINNED layout would produce, and the controller feeds the
// engine that instead of event.characters.
//
// The cost is that macOS's own translation is now wrong wherever we let a key pass
// through untouched, so the controller must insert those characters itself. That
// risk is fenced: `translator` is nil — and every path behaves exactly as it did in
// 1.5.7 — unless the user pinned a layout AND macOS is currently on a different one.
// The remapping path can therefore only run in the situation that is already broken.
//
// MAIN THREAD ONLY: `resolved` is an unsynchronized cache. Both call sites
// (activateServer, Settings) are main-thread; keep it that way.

import Carbon
import Foundation

/// One ASCII-capable keyboard layout the user can pin VietTelex to.
struct KeyboardLayoutOption: Identifiable, Equatable {
    /// kTISPropertyInputSourceID, e.g. "com.apple.keylayout.Colemak".
    let id: String
    /// Localized display name for the Settings picker, e.g. "Colemak".
    let name: String
}

enum KeyboardLayoutOverride {
    /// Sentinel for "don't override" — inherit whatever layout macOS hands us, which
    /// is the behaviour every build up to 1.5.7 had. Kept as the default so an
    /// upgrade changes nothing for the QWERTY majority.
    static let systemDefault = ""

    /// id → input source, so a focus change doesn't re-scan the ~112 installed
    /// layouts. Never invalidated: layouts are added by installing a system update
    /// or a third-party bundle, neither of which happens without a restart.
    private static var resolved: [String: TISInputSource] = [:]

    /// Last id handed to Carbon, for log dedupe only — never to skip the call. macOS
    /// may reset the override across an input-source cycle, so activateServer must be
    /// free to re-assert the same value.
    private static var lastLogged: String?

    /// Every ASCII-capable keyboard layout INSTALLED on this Mac, not merely the ones
    /// enabled in System Settings: once VietTelex composes on Colemak the user has no
    /// reason to keep Colemak in the input menu, so demanding it be enabled there
    /// would be a step that buys nothing. Sorted by localized name.
    static func installed() -> [KeyboardLayoutOption] {
        let filter = [kTISPropertyInputSourceType as String: kTISTypeKeyboardLayout as String,
                      kTISPropertyInputSourceIsASCIICapable as String: true] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, true)?.takeRetainedValue()
                as? [TISInputSource] else { return [] }
        return list.compactMap { src -> KeyboardLayoutOption? in
            guard let id = property(src, kTISPropertyInputSourceID) else { return nil }
            resolved[id] = src
            return KeyboardLayoutOption(id: id, name: property(src, kTISPropertyLocalizedName) ?? id)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Rewrites the KEYCODE of a ⌘/⌃/⌥ chord, which no amount of character
    /// translation can fix: a chord never reaches our engine — the app resolves it
    /// itself, through the LIVE layout. With QWERTY pinned while macOS sat on Colemak,
    /// ⌘ on the physical R key opened Chrome's print dialog, because Colemak calls
    /// that key P. Typing was already correct; only the chord was wrong.
    ///
    /// So the fix is a change of ADDRESS, not of character: hand the app the keycode
    /// that the LIVE layout resolves to the character the PINNED layout has there.
    struct ChordRemap {
        let pinned: KeyboardLayoutTranslator
        let live: KeyboardLayoutTranslator

        /// The keycode to substitute, or nil to leave the event alone (the key is not
        /// an ASCII key on the pinned layout, or the live layout can't produce that
        /// character at all — a substitution guess there would be worse than none).
        func substitute(for keyCode: UInt16, shift: Bool) -> UInt16? {
            guard let want = pinned.ascii(keyCode: keyCode, shift: shift),
                  live.ascii(keyCode: keyCode, shift: shift) != want,
                  let code = live.keyCode(forASCII: want, shift: shift),
                  code != keyCode
            else { return nil }
            return code
        }
    }

    /// Guards `_translator` and `_chordRemap`. They are written on main (activateServer, Settings)
    /// and read from the event-tap thread on every keystroke — the same cross-thread
    /// shape AppState locks its hot-path caches for. A struct wrapping an array is
    /// not safe to read while it is being reassigned, so this cannot be a bare var.
    private static let translatorLock = NSLock()
    private static var _translator: KeyboardLayoutTranslator?
    private static var _chordRemap: ChordRemap?

    /// The active remapper, or nil when macOS's own layout is already correct —
    /// either the user pinned nothing, or the pinned layout is the live one. nil is
    /// the fast, unchanged, 1.5.7 path.
    static var translator: KeyboardLayoutTranslator? {
        translatorLock.withLock { _translator }
    }

    /// The keycode rewriter for ⌘/⌃/⌥ chords, nil in exactly the cases `translator`
    /// is — plus when the live layout carries no `uchr` data to invert, in which case
    /// typing is still remapped and chords keep today's (wrong) behaviour.
    static var chordRemap: ChordRemap? {
        translatorLock.withLock { _chordRemap }
    }

    /// State the last `apply` resolved from, so repeat calls (one per focus change)
    /// are a two-Carbon-read no-op instead of a table rebuild.
    private static var resolvedFor: (pinned: String, live: String)?

    /// Point Telex at `id`. `systemDefault` (empty) means "whatever macOS gives us",
    /// which is what every build up to 1.5.7 did.
    ///
    /// This does NOT ask macOS to change anything — both documented routes were
    /// measured inert (see the header). It decides whether OUR translation has to
    /// stand in, and prepares it.
    ///
    /// Called from activateServer, i.e. once per focus change.
    @discardableResult
    static func apply(_ id: String) -> Bool {
        let live = liveLayoutID()
        // Nothing pinned, or macOS already happens to be on the pinned layout: leave
        // the event untouched. This is the common case and it must stay free — it is
        // also what keeps a QWERTY user on exactly the 1.5.7 code path.
        guard id != systemDefault, id != live else {
            if translator != nil { log(id, "off (live=\(live))") }
            setTranslator(nil)
            resolvedFor = nil
            return false
        }
        guard resolvedFor.map({ $0 != (id, live) }) ?? true else { return translator != nil }
        resolvedFor = (id, live)

        guard let src = source(for: id) else {
            setTranslator(nil)
            log(id, "not installed")
            return false
        }
        guard let built = KeyboardLayoutTranslator(layoutID: id, source: src) else {
            setTranslator(nil)
            log(id, "no uchr data — cannot remap")
            return false
        }
        setTranslator(built, chord: chordRemap(pinned: built, liveID: live))
        log(id, "remapping (live=\(live))")
        return true
    }

    /// Inverting the live layout is what lets a chord be re-addressed; a layout with no
    /// `uchr` data (old 'KCHR' resources) simply doesn't get chord repair.
    private static func chordRemap(pinned: KeyboardLayoutTranslator, liveID: String) -> ChordRemap? {
        guard let src = source(for: liveID),
              let live = KeyboardLayoutTranslator(layoutID: liveID, source: src)
        else {
            DebugLog.log("layout-override: live layout \(liveID) not invertible — ⌘ chords unrepaired")
            return nil
        }
        return ChordRemap(pinned: pinned, live: live)
    }

    private static func setTranslator(_ new: KeyboardLayoutTranslator?, chord: ChordRemap? = nil) {
        translatorLock.withLock {
            _translator = new
            _chordRemap = chord
        }
    }

    /// Also read by QtKeymapFix (#131) — the layout to name in a Qt client's override.
    static func liveLayoutID() -> String {
        property(TISCopyCurrentKeyboardLayoutInputSource().takeRetainedValue(),
                 kTISPropertyInputSourceID) ?? "?"
    }

    /// True when `id` names a layout that is still installed. Guards the Settings
    /// picker against a stale preference (layout removed by a system update) showing
    /// an empty selection.
    static func isInstalled(_ id: String) -> Bool {
        id == systemDefault || source(for: id) != nil
    }

    // MARK: - Private

    private static func source(for id: String) -> TISInputSource? {
        if let hit = resolved[id] { return hit }
        let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, true)?.takeRetainedValue()
                as? [TISInputSource], let src = list.first else { return nil }
        resolved[id] = src
        return src
    }

    private static func property(_ src: TISInputSource, _ key: CFString) -> String? {
        guard let raw = TISGetInputSourceProperty(src, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
    }

    /// One line per DISTINCT outcome: activateServer fires on every focus change and
    /// would otherwise flood the 2000-line ring the user pastes into bug reports.
    private static func log(_ id: String, _ outcome: String) {
        let line = "layout-override \(id): \(outcome)"
        guard lastLogged != line else { return }
        lastLogged = line
        DebugLog.log(line)
    }
}
