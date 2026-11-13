import XCTest
import Carbon.HIToolbox
import TelexCore
@testable import VietTelex

// Issue #163 (13/11/2026): "Sửa dấu từ đã gõ" looked dead in Codex / Safari with
// nothing in the debug log. Each gate decision is pinned here as a pure function.

// MARK: - Tap re-edit gate: named reasons, cooldown logging, navigation re-arm (RC1/3/5)

final class ReEditTapGateTests: XCTestCase {

    private func v(empty: Bool = true, enabled: Bool = true, diacritic: Bool = true,
                   mode: TapEmit = .backspace, boundary: Bool = false,
                   nav: Bool = false, msNav: UInt64 = .max,
                   drained: Bool = true, msDel: UInt64 = .max) -> ReEditTapGate.Verdict {
        ReEditTapGate.verdict(engineIsEmpty: empty, reEditEnabled: enabled, isDiacriticKey: diacritic,
                              emitMode: mode, lastKeyWasBoundary: boundary,
                              afterNavigationKey: nav, msSinceNavigation: msNav,
                              queueDrained: drained, msSinceDelete: msDel)
    }

    /// Non-candidates stay silent (no log line per ordinary key).
    func testNonCandidatesAreSilent() {
        XCTAssertEqual(v(empty: false), .notCandidate)
        XCTAssertEqual(v(enabled: false), .notCandidate)
        XCTAssertEqual(v(diacritic: false), .notCandidate)
        // …even when another gate would also refuse.
        XCTAssertEqual(v(empty: false, mode: .emptyReset, boundary: true, msDel: 0), .notCandidate)
    }

    func testPlainCaseOpens() {
        XCTAssertEqual(v(), .open(afterNavigation: false))
    }

    /// RC1: the Safari address bar runs .emptyReset — blocked by design, now with a reason.
    func testOmniboxModesSkipWithReason() {
        XCTAssertEqual(v(mode: .emptyReset), .skip(.emitMode))
        XCTAssertEqual(v(mode: .selection), .skip(.emitMode))
        XCTAssertEqual(ReEditTapGate.Skip.emitMode.reason, "emitMode not backspace")
    }

    /// #38 stays: a tone key right after a typed boundary never re-edits.
    func testBoundaryStillBlocks() {
        XCTAssertEqual(v(boundary: true), .skip(.boundary))
    }

    /// RC3: the 500ms cooldown is kept, but a skip now carries the elapsed ms for the log
    /// (field log: tone keys 229–364ms after ⌫ were silently dropped).
    func testDeleteCooldownSkipIsReportedWithTiming() {
        XCTAssertEqual(v(msDel: 300), .skip(.deleteCooldown(ms: 300)))
        XCTAssertEqual(v(msDel: ReEditTapGate.deleteCooldownMs - 1),
                       .skip(.deleteCooldown(ms: ReEditTapGate.deleteCooldownMs - 1)))
        XCTAssertEqual(v(msDel: ReEditTapGate.deleteCooldownMs), .open(afterNavigation: false))
        XCTAssertEqual(ReEditTapGate.deleteCooldownMs, 500)
        XCTAssertEqual(TerminalTapController.reEditDeleteCooldownMs, 500)
        XCTAssertTrue(ReEditTapGate.Skip.deleteCooldown(ms: 300).reason.contains("300ms"))
    }

    func testSyntheticInFlightSkips() {
        XCTAssertEqual(v(drained: false), .skip(.syntheticInFlight))
    }

    /// RC5: ←/→/Home/End re-arm the AX-verified seed once the AX tree has settled.
    func testNavigationReArmsAfterSettle() {
        XCTAssertEqual(v(boundary: true, nav: true, msNav: ReEditTapGate.navigationSettleMs),
                       .open(afterNavigation: true))
        XCTAssertEqual(v(boundary: true, nav: true, msNav: 5_000), .open(afterNavigation: true))
    }

    /// RC5 + #38: a tone key hot on the heels of the arrow could read a lagging AX tree
    /// (JetBrains terminal: `git` shown without the just-typed space) — refused.
    func testNavigationTooFastIsRefused() {
        XCTAssertEqual(v(boundary: true, nav: true, msNav: 40), .skip(.navigationSettle(ms: 40)))
    }

    /// The navigation re-arm only lifts the boundary rule — never the #62 gates.
    func testNavigationDoesNotBypassOtherGates() {
        XCTAssertEqual(v(boundary: true, nav: true, msNav: 1_000, drained: false), .skip(.syntheticInFlight))
        XCTAssertEqual(v(boundary: true, nav: true, msNav: 1_000, msDel: 100), .skip(.deleteCooldown(ms: 100)))
        XCTAssertEqual(v(mode: .emptyReset, boundary: true, nav: true, msNav: 1_000), .skip(.emitMode))
    }

    func testNavigationKeysThatReArm() {
        for k in [kVK_LeftArrow, kVK_RightArrow, kVK_Home, kVK_End] {
            XCTAssertTrue(ReEditTapGate.navigationRearms(keyCode: k), "\(k)")
        }
        for k in [kVK_UpArrow, kVK_DownArrow, kVK_PageUp, kVK_PageDown, kVK_ForwardDelete,
                  kVK_Space, kVK_Return, kVK_Tab, kVK_ANSI_S] {
            XCTAssertFalse(ReEditTapGate.navigationRearms(keyCode: k), "\(k)")
        }
    }

    /// The Bool wrapper the older tests use is unchanged: navigation is never implied.
    func testLegacyBoolGateMatchesVerdict() {
        XCTAssertTrue(TerminalTapController.reEditGateOpen(
            engineIsEmpty: true, reEditEnabled: true, isDiacriticKey: true, emitMode: .backspace,
            lastKeyWasBoundary: false))
        XCTAssertFalse(TerminalTapController.reEditGateOpen(
            engineIsEmpty: true, reEditEnabled: true, isDiacriticKey: true, emitMode: .backspace,
            lastKeyWasBoundary: true))
    }
}

// MARK: - Click check split (logging)

final class ReEditClickVerdictTests: XCTestCase {
    func testUnreadableFrameAndOutsideClickAreDistinct() {
        let composer = CGRect(x: 300, y: 800, width: 600, height: 40)
        XCTAssertEqual(ReEditClickCheck.verdict(click: CGPoint(x: 420, y: 815), fieldFrame: composer), .allowed)
        XCTAssertEqual(ReEditClickCheck.verdict(click: CGPoint(x: 700, y: 420), fieldFrame: composer), .outsideFrame)
        // Codex: the composer returns no AX frame at all.
        XCTAssertEqual(ReEditClickCheck.verdict(click: CGPoint(x: 10, y: 10), fieldFrame: nil), .frameUnreadable)
        XCTAssertEqual(ReEditClickCheck.verdict(click: CGPoint(x: 10, y: 10), fieldFrame: .zero), .frameUnreadable)
        XCTAssertEqual(ReEditClickCheck.verdict(click: nil, fieldFrame: nil), .allowed)
    }
}

// MARK: - ⌫ re-open by keystream trust when AX has no caret (RC2)

final class ReopenKeystreamTrustTests: XCTestCase {

    func testArmsOnlyOnPlainPrintableAsciiBoundary() {
        for b: Character in [" ", ".", ",", "1", "!", ")"] {
            XCTAssertTrue(ReopenKeystreamTrust.arms(emitMode: .backspace, boundary: b, smartQuoted: false,
                                                    rewrote: false, canReopen: true), "\(b)")
        }
        for b: Character in ["\t", "\n", "\r", "\u{7F}", "—", "“", "\u{00A0}"] {
            XCTAssertFalse(ReopenKeystreamTrust.arms(emitMode: .backspace, boundary: b, smartQuoted: false,
                                                     rewrote: false, canReopen: true), "\(b.unicodeScalars.first!.value)")
        }
    }

    func testArmRefusals() {
        // Smart quote replaced the typed char; a rewrite (expansion / retro / restore) ran.
        XCTAssertFalse(ReopenKeystreamTrust.arms(emitMode: .backspace, boundary: "\"", smartQuoted: true,
                                                 rewrote: false, canReopen: true))
        XCTAssertFalse(ReopenKeystreamTrust.arms(emitMode: .backspace, boundary: " ", smartQuoted: false,
                                                 rewrote: true, canReopen: true))
        // Nothing to re-open (auto-restored word, overflow…).
        XCTAssertFalse(ReopenKeystreamTrust.arms(emitMode: .backspace, boundary: " ", smartQuoted: false,
                                                 rewrote: false, canReopen: false))
        // Omnibox modes.
        XCTAssertFalse(ReopenKeystreamTrust.arms(emitMode: .emptyReset, boundary: " ", smartQuoted: false,
                                                 rewrote: false, canReopen: true))
        XCTAssertFalse(ReopenKeystreamTrust.arms(emitMode: .selection, boundary: " ", smartQuoted: false,
                                                 rewrote: false, canReopen: true))
    }

    func testAllowsOnlyArmedNonBrowserBackspaceMode() {
        XCTAssertTrue(ReopenKeystreamTrust.allows(armed: true, emitMode: .backspace, axDetectApp: false))
        // Any key/click/focus change between boundary and ⌫ disarmed it.
        XCTAssertFalse(ReopenKeystreamTrust.allows(armed: false, emitMode: .backspace, axDetectApp: false))
        // Browsers: "no caret" there means an unreliable read, not a blind editor.
        XCTAssertFalse(ReopenKeystreamTrust.allows(armed: true, emitMode: .backspace, axDetectApp: true))
        XCTAssertFalse(ReopenKeystreamTrust.allows(armed: true, emitMode: .emptyReset, axDetectApp: false))
    }

    /// The Codex repro end to end on the engine: "toan" ␣ ⌫ s → "toán".
    func testCodexReproComposesThroughKeystreamReopen() {
        var e = TelexEngine()
        e.freeMarking = true; e.simpleTelex = true; e.liveSpellCheck = true
        for ch in "toan" { _ = e.feed(ch) }
        _ = e.commitBoundary(autoRestore: true, boundary: " ")
        XCTAssertTrue(ReopenKeystreamTrust.arms(emitMode: .backspace, boundary: " ", smartQuoted: false,
                                                rewrote: false, canReopen: e.canReopenLastCommit))
        XCTAssertTrue(ReopenKeystreamTrust.allows(armed: true, emitMode: .backspace, axDetectApp: false))
        XCTAssertEqual(e.reopenLastCommit(), "toan")
        XCTAssertEqual(e.feed("s"), .replace(backspaces: 2, insert: "án"))
        XCTAssertEqual(e.composed, "toán")
    }

    /// A second boundary (two spaces) consumes the snapshot — the ⌫ would delete the
    /// second space, not the one after the word.
    func testSecondBoundaryLeavesNothingToTrust() {
        var e = TelexEngine()
        for ch in "toan" { _ = e.feed(ch) }
        _ = e.commitBoundary(autoRestore: true, boundary: " ")
        _ = e.commitBoundary(autoRestore: true, boundary: " ")
        XCTAssertFalse(ReopenKeystreamTrust.arms(emitMode: .backspace, boundary: " ", smartQuoted: false,
                                                 rewrote: false, canReopen: e.canReopenLastCommit))
    }
}

// MARK: - IMKit re-edit acceptance (RC4)

final class ReEditIMKAcceptanceTests: XCTestCase {
    func testAcceptsLearnedPinnedAndWebKitPage() {
        XCTAssertTrue(ReEditIMKAcceptance.appAllowed(learnedInPlace: true, manualInPlace: false, webKitPage: false))
        XCTAssertTrue(ReEditIMKAcceptance.appAllowed(learnedInPlace: false, manualInPlace: true, webKitPage: false))
        XCTAssertTrue(ReEditIMKAcceptance.appAllowed(learnedInPlace: false, manualInPlace: false, webKitPage: true))
        XCTAssertFalse(ReEditIMKAcceptance.appAllowed(learnedInPlace: false, manualInPlace: false, webKitPage: false))
    }

    func testWebKitPageClients() {
        XCTAssertTrue(AppState.isWebKitPageClient("com.apple.Safari"))
        XCTAssertTrue(AppState.isWebKitPageClient("com.apple.SafariTechnologyPreview"))
        XCTAssertTrue(AppState.isWebKitPageClient("com.apple.Safari.WebApp.0F3A9C1E-0000-4000-8000-000000000001"))
        XCTAssertFalse(AppState.isWebKitPageClient("com.google.Chrome"))
        XCTAssertFalse(AppState.isWebKitPageClient("com.openai.codex"))
        XCTAssertFalse(AppState.isWebKitPageClient(nil))
    }

    /// Discord pinned In-place appends at offset 0/1 (edgeTapEligible) — a seeded word
    /// starting there would hit the same bug.
    func testEdgeZoneOfOffset0AppendApp() {
        XCTAssertTrue(ReEditIMKAcceptance.edgeZoneBlocks(offset0AppendApp: true, manualInPlace: true, wordStart: 0))
        XCTAssertTrue(ReEditIMKAcceptance.edgeZoneBlocks(offset0AppendApp: true, manualInPlace: true, wordStart: 1))
        XCTAssertFalse(ReEditIMKAcceptance.edgeZoneBlocks(offset0AppendApp: true, manualInPlace: true, wordStart: 2))
        XCTAssertFalse(ReEditIMKAcceptance.edgeZoneBlocks(offset0AppendApp: false, manualInPlace: true, wordStart: 0))
        XCTAssertFalse(ReEditIMKAcceptance.edgeZoneBlocks(offset0AppendApp: true, manualInPlace: false, wordStart: 0))
    }
}

// MARK: - Debug-log timestamp (first line 18446744073709.6)

final class DebugLogElapsedTests: XCTestCase {
    func testElapsedNeverWraps() {
        XCTAssertEqual(DebugLog.elapsedMs(now: 1_000, start: 2_000_000), 0)
        XCTAssertEqual(DebugLog.elapsedMs(now: 3_500_000, start: 1_000_000), 2.5, accuracy: 1e-9)
        XCTAssertEqual(DebugLog.elapsedMs(now: 5, start: 5), 0)
    }

    func testMsElapsedSaturates() {
        XCTAssertEqual(msElapsed(now: 10, since: 20_000_000), 0)
        XCTAssertEqual(msElapsed(now: 250_000_000, since: 0), 250)
        XCTAssertEqual(msElapsed(now: 1_250_000_000, since: 1_000_000_000), 250)
    }
}
