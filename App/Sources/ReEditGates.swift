// ReEditGates.swift
// Issue #163 (13/11/2026, macOS 1.9.9): "Sửa dấu từ đã gõ" looked dead in Codex and
// Safari while the debug log said nothing — most gates exited silently. The pure
// decisions behind re-edit (tone key on an empty engine reaches back into the word
// before the caret) and ⌫ re-open (issue #40) live here so every exit has a named
// reason for the log and a regression test. Log policy unchanged: reasons, counts
// and timings only — never typed text.

import Foundation
import Carbon.HIToolbox

// MARK: - Tap re-edit gate

/// Everything about WHETHER the tap may attempt re-edit that needs no live AX tree.
/// See `TerminalTapController.reEditGateOpen` for the history of each rule
/// (#38 boundary, #62 ⌫ cooldown + synthetic queue).
enum ReEditTapGate {
    enum Skip: Equatable {
        /// Per-field browser modes (omnibox .selection / .emptyReset): inline
        /// autocomplete rewrites text underneath us — blocked by design (RC1).
        case emitMode
        /// The previous physical key ended a word (#38): AX may still lag the keystream.
        case boundary
        /// Navigation re-arm (#163 RC5) refused: the tone key followed the navigation
        /// key too quickly for a laggy AX tree to have caught up.
        case navigationSettle(ms: UInt64)
        /// Our synthetic burst is still in flight (#62).
        case syntheticInFlight
        /// Within `deleteCooldownMs` of a physical ⌫ (#62).
        case deleteCooldown(ms: UInt64)

        var reason: String {
            switch self {
            case .emitMode: return "emitMode not backspace"
            case .boundary: return "previous key was a boundary"
            case let .navigationSettle(ms): return "navigation \(ms)ms ago < \(ReEditTapGate.navigationSettleMs)ms settle"
            case .syntheticInFlight: return "synthetic keys in flight"
            case let .deleteCooldown(ms): return "⌫ \(ms)ms ago < \(ReEditTapGate.deleteCooldownMs)ms cooldown"
            }
        }
    }

    enum Verdict: Equatable {
        /// Not a re-edit candidate at all (mid-word, feature off, plain letter): the
        /// overwhelmingly common case — no log, no AX.
        case notCandidate
        /// A candidate refused by a gate — the caller logs `reason`.
        case skip(Skip)
        /// Attempt the AX seed. `afterNavigation`: re-armed by ←/→/Home/End (log tag).
        case open(afterNavigation: Bool)
    }

    /// Issue #62 cooldown after a physical ⌫. Kept at 500ms (#163 RC3): there is no
    /// reliable "the app has applied our ⌫" signal to bypass it with —
    /// `SyntheticKeyboard.queueDrained()` only says our own events came back through
    /// the TAP, i.e. before the app processed them, and the physical ⌫ passes with
    /// no acknowledgement at all; the Zalo AX tree that produced "asa" lagged the
    /// app, not the tap. Skips are logged instead, so a field log shows them.
    static let deleteCooldownMs: UInt64 = 500

    /// #163 RC5: minimum gap between a navigation key and the tone key for the
    /// navigation re-arm. A click re-arms with no gap because moving the hand to the
    /// mouse is never that fast; arrows are, and a laggy AX tree (#38: JetBrains)
    /// could still report the caret/text from before the navigation.
    static let navigationSettleMs: UInt64 = 200

    /// ←/→/Home/End: caret moves within the line without inserting text — the keys
    /// a user presses to go back to the end of a word (#163 RC5). ↑/↓/PageUp/Down
    /// and forward-delete stay plain boundaries (line/page jumps, text edits).
    static func navigationRearms(keyCode: Int) -> Bool {
        keyCode == kVK_LeftArrow || keyCode == kVK_RightArrow
            || keyCode == kVK_Home || keyCode == kVK_End
    }

    static func verdict(engineIsEmpty: Bool, reEditEnabled: Bool, isDiacriticKey: Bool,
                        emitMode: TapEmit, lastKeyWasBoundary: Bool,
                        afterNavigationKey: Bool = false, msSinceNavigation: UInt64 = .max,
                        queueDrained: Bool = true, msSinceDelete: UInt64 = .max) -> Verdict {
        guard engineIsEmpty, reEditEnabled, isDiacriticKey else { return .notCandidate }
        guard emitMode == .backspace else { return .skip(.emitMode) }
        var viaNavigation = false
        if lastKeyWasBoundary {
            // Navigation still forgets the last commit and still counts as a
            // boundary (#38 keystream rule); it only re-arms the AX-verified seed,
            // exactly like a click, once the AX tree has had time to settle.
            guard afterNavigationKey else { return .skip(.boundary) }
            guard msSinceNavigation >= navigationSettleMs else {
                return .skip(.navigationSettle(ms: msSinceNavigation))
            }
            viaNavigation = true
        }
        guard queueDrained else { return .skip(.syntheticInFlight) }
        guard msSinceDelete >= deleteCooldownMs else { return .skip(.deleteCooldown(ms: msSinceDelete)) }
        return .open(afterNavigation: viaNavigation)
    }
}

/// Monotonic ns → whole ms elapsed, saturating at 0 when `then` is AFTER `now`
/// (a stamp taken on another thread a moment later). Never wraps the way
/// `(now &- then) / 1e6` does.
@inline(__always)
func msElapsed(now: UInt64, since then: UInt64) -> UInt64 {
    now >= then ? (now - then) / 1_000_000 : 0
}

// MARK: - ⌫ re-open on the tap without an AX caret (#163 RC2)

/// Apps whose editor never exposes `AXSelectedTextRange` (Codex's composer, field
/// log #163: `no AX caret` even after a relaunch + fresh AXManualAccessibility
/// poke) can still re-open the last word on ⌫ — by trusting the KEYSTREAM, the
/// way `ShortcutUndo` (⌫ right after a shortcut expansion) already does for apps
/// AX can't read. The engine knows the word it committed; this decides whether
/// the screen can be assumed to be "<that word><one boundary char>|".
///
/// Safety rules (mirroring ShortcutUndo / ShortcutTail anchoring):
///  • ⌫ is the VERY NEXT physical key after the boundary that committed the word —
///    any other key, click, focus change, ⌘-chord, navigation or pass-through
///    disarms (the tap clears the flag at the top of every keyDown and on click;
///    each of those paths also resets/forgets the engine snapshot);
///  • the boundary was ONE plain printable ASCII char typed through the normal
///    boundary path — not Return/Tab/Esc (they forget the snapshot), not a smart
///    quote, not a double-space period / "--" em dash replacement, not a shortcut
///    expansion or retro/auto-restore rewrite (`rewrote`);
///  • emit mode .backspace only (omnibox modes excluded as everywhere);
///  • never for axDetect browsers: their page content has AX, so "no caret" there
///    means the read is unreliable, not that the editor is blind (same exclusion
///    as `tryUndoShortcutTap`).
/// Risk (accepted, see #163): an app that rewrites the word or swallows the
/// boundary on its own with no AX to show it (autocorrect on space, fish/zsh
/// abbreviation expansion in an AX-blind terminal) gets its next tone key's
/// backspace-retype applied to the wrong characters. Re-edit after a CLICK is
/// still unsupported there — with no AX caret nothing says which word the caret
/// landed after.
enum ReopenKeystreamTrust {
    static func arms(emitMode: TapEmit, boundary: Character, smartQuoted: Bool,
                     rewrote: Bool, canReopen: Bool) -> Bool {
        guard emitMode == .backspace, canReopen, !smartQuoted, !rewrote,
              let a = boundary.asciiValue else { return false }
        return a >= 0x20 && a < 0x7F       // printable: never \t \n \r or DEL
    }

    static func allows(armed: Bool, emitMode: TapEmit, axDetectApp: Bool) -> Bool {
        armed && emitMode == .backspace && !axDetectApp
    }
}

// MARK: - IMKit re-edit acceptance (#163 RC4)

enum ReEditIMKAcceptance {
    /// Which IMKit clients may seed the engine from the text before the caret.
    /// The edit that follows a seed is the ordinary in-place replace —
    /// `insertText(_:replacementRange:)` on the tracked range, the same call every
    /// mid-word tone edit already makes there — so re-edit is safe exactly where
    /// that channel is trusted:
    ///  • learned/built-in in-place apps (the original rule);
    ///  • apps the user PINNED to In-place — a decision, like `replacesCommittedText`;
    ///  • WebKit page content (Safari, Safari web apps): routed to IMKit in-place by
    ///    the #44 carve-out precisely because WebKit honors insertText
    ///    (replacementRange:) while it drops the tap's synthetic burst. Re-edit on
    ///    this path posts NO synthetic events, so the WebKit swallow does not apply.
    ///    The omnibox is excluded per field by the caller (wantsSelection), marked
    ///    fields (Docs in Safari) by `usesMarkedNow`.
    static func appAllowed(learnedInPlace: Bool, manualInPlace: Bool, webKitPage: Bool) -> Bool {
        learnedInPlace || manualInPlace || webKitPage
    }

    /// Slate-class composers pinned In-place append instead of replacing at offset
    /// 0/1 (`edgeTapEligible`, Discord) — a seeded word starting there would hit the
    /// same bug, so it is refused.
    static func edgeZoneBlocks(offset0AppendApp: Bool, manualInPlace: Bool, wordStart: Int) -> Bool {
        offset0AppendApp && manualInPlace && wordStart <= 1
    }
}
