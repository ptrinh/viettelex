import XCTest
@testable import VietTelex
import TelexCore

// The per-key routing used to be 6-8 separate AppState calls (each its own lock trip,
// several re-reading Accessibility.isTrusted). tapRouting() collapses that into ONE
// lock + one trusted read + at most one detector read. These tests pin the pure parts:
// the OR-merge across the two consulted ids, the gate order, and — critically — the
// LAZINESS contract: a key in a plain in-place app must not pay for a TCC read or an
// AX field scan, exactly as the legacy per-mode getters behaved.
final class RoutingDecisionTests: XCTestCase {

    private typealias W = AppState.TapWants
    private typealias R = AppState.TapRouting

    // MARK: merge

    func testMergeORsEachFamily() {
        let tap = W(tap: true, sel: .no, empty: false)
        let empty = W(tap: false, sel: .no, empty: true)
        XCTAssertEqual(AppState.mergedWants(tap, empty), W(tap: true, sel: .no, empty: true))
        XCTAssertEqual(AppState.mergedWants(W(), W()), W())
    }

    func testMergeSelYesOutranksPerField() {
        // Manual .selection pin means selection UNCONDITIONALLY — merging with a
        // per-field browser verdict must not demote it back to detector-dependent.
        let yes = W(tap: false, sel: .yes, empty: false)
        let perField = W(tap: false, sel: .perField, empty: false)
        XCTAssertEqual(AppState.mergedWants(yes, perField).sel, .yes)
        XCTAssertEqual(AppState.mergedWants(perField, yes).sel, .yes)
        XCTAssertEqual(AppState.mergedWants(perField, W()).sel, .perField)
    }

    // MARK: gate

    /// Chromium page content without Accessibility used to fall through to
    /// in-place, which Lexical ignores — tones never appeared ("banhs").
    /// Marked is the underlined fallback. The detector must not run: AX lies
    /// when untrusted, and the laziness contract forbids the scan.
    func testUntrustedChromiumPageDegradesToMarked() {
        let chrome = W(tap: false, sel: .perField, empty: false)
        let r = AppState.gateRouting(chrome, trusted: { false },
                                     wantsSelection: { XCTFail("untrusted must not scan"); return false },
                                     wantsMarkedField: { XCTFail("untrusted must not scan"); return false },
                                     pageContentInPlace: false)
        XCTAssertEqual(r, R(untrustedMarked: true))
        XCTAssertFalse(r.tapDefer)
    }

    /// Safari page content does not need the tap. Forcing marked there would
    /// underline a path that already types in-place.
    func testUntrustedWebKitStaysOffTheMarkedFallback() {
        let safari = W(tap: false, sel: .perField, empty: false)
        let r = AppState.gateRouting(safari, trusted: { false },
                                     wantsSelection: { XCTFail("untrusted must not scan"); return false },
                                     wantsMarkedField: { XCTFail("untrusted must not scan"); return false },
                                     pageContentInPlace: true)
        XCTAssertEqual(r, R())
    }

    /// Terminals and unconditional selection pins are not the Chromium page
    /// failure. Don't widen the underlined fallback onto them.
    func testUntrustedNonPerFieldDoesNotForceMarked() {
        let terminal = W(tap: true, sel: .no, empty: false)
        XCTAssertEqual(AppState.gateRouting(terminal, trusted: { false },
                                            wantsSelection: { XCTFail(); return false },
                                            wantsMarkedField: { XCTFail(); return false }),
                       R())
        let pinned = W(tap: false, sel: .yes, empty: false)
        XCTAssertEqual(AppState.gateRouting(pinned, trusted: { false },
                                            wantsSelection: { XCTFail(); return false },
                                            wantsMarkedField: { XCTFail(); return false }),
                       R())
    }

    func testGateAppliesTrustToEveryFamily() {
        let all = W(tap: true, sel: .yes, empty: true)
        XCTAssertEqual(AppState.gateRouting(all, trusted: { true },
                                            wantsSelection: { XCTFail("sel .yes must not consult the detector"); return false },
                                            wantsMarkedField: { XCTFail("sel .yes must not consult the marked verdict"); return false },
                                            wantsPassthroughField: { XCTFail("sel .yes must not consult the passthrough verdict"); return false }),
                       R(tap: true, selection: true, emptyReset: true))
        XCTAssertEqual(AppState.gateRouting(all, trusted: { false }, wantsSelection: { false },
                                            wantsMarkedField: { false }), R())
    }

    func testGatePerFieldConsultsTheDetectorExactlyOnce() {
        var reads = 0
        let w = W(tap: false, sel: .perField, empty: false)
        let r = AppState.gateRouting(w, trusted: { true }, wantsSelection: { reads += 1; return true },
                                     wantsMarkedField: { XCTFail("omnibox must not consult the marked verdict"); return false },
                                     wantsPassthroughField: { XCTFail("omnibox must not consult the passthrough verdict"); return false })
        XCTAssertEqual(r, R(tap: false, selection: true, emptyReset: false))
        XCTAssertEqual(reads, 1)
        XCTAssertFalse(AppState.gateRouting(w, trusted: { true }, wantsSelection: { false },
                                            wantsMarkedField: { false }).selection)
    }

    /// The laziness contract: no wants → NEITHER external is touched (a plain
    /// in-place app's keystroke pays zero TCC/detector cost), and untrusted →
    /// the detector is never touched.
    func testGateIsLazyOnBothExternals() {
        _ = AppState.gateRouting(W(),
                                 trusted: { XCTFail("no wants → trusted must not be read"); return true },
                                 wantsSelection: { XCTFail("no wants → detector must not be read"); return false },
                                 wantsMarkedField: { XCTFail("no wants → marked verdict must not be read"); return false },
                                 wantsPassthroughField: { XCTFail("no wants → passthrough verdict must not be read"); return false })
        _ = AppState.gateRouting(W(tap: true, sel: .perField, empty: false),
                                 trusted: { false },
                                 wantsSelection: { XCTFail("untrusted → detector must not be read"); return false },
                                 wantsMarkedField: { XCTFail("untrusted → marked verdict must not be read"); return false },
                                 wantsPassthroughField: { XCTFail("untrusted → passthrough verdict must not be read"); return false })
    }

    // MARK: equivalence with the legacy per-mode getters (shared _rawWants core)

    /// tapRouting and the legacy getters resolve the same wants from the same core;
    /// with the built-in rule table this pins tap/perField/empty membership end to end.
    /// (Gates depend on live AX state, so equivalence is asserted at tapDefer level —
    /// under the test host both sides see the same isTrusted/detector answers.)
    func testSnapshotAgreesWithLegacyGettersForBuiltInRules() {
        let s = AppState.shared
        let ids: [String?] = ["com.apple.Terminal",        // built-in tap
                              "com.apple.Safari",          // built-in axDetect (perField)
                              "com.microsoft.Excel",       // built-in emptyReset (if ruled)
                              "com.apple.Notes",           // built-in inPlace
                              "definitely.not.installed",  // unknown
                              nil]
        for id in ids {
            for front in ids {
                let r = s.tapRouting(id, front: front)
                let legacy = s.usesTapMode(id) || s.usesTapMode(front)
                    || s.usesSelectionReplace(id) || s.usesSelectionReplace(front)
                    || s.usesEmptyReset(id) || s.usesEmptyReset(front)
                XCTAssertEqual(r.tapDefer, legacy, "id=\(id ?? "nil") front=\(front ?? "nil")")
            }
        }
    }

    // POLICY 2026-08-06 (maintainer): browser PAGE CONTENT routes to the TAP
    // backspace-retype path by default — the only channel every web editor must
    // handle (the classic backspace-retype model). insertText(replacementRange:) has no
    // contract with JS editors: Docs appended + killed ⌫ (07-30), Discord appended
    // while EVERY self-report said honored (08-05, provably undetectable), Zalo
    // froze with a constant caret (08-06) — three per-host patches in one week.
    // The host allowlist is GONE; this truth table IS the policy now.
    func testPageContentRoutesToTap() {
        let w = W(tap: false, sel: .perField, empty: false)
        let r = AppState.gateRouting(w, trusted: { true },
                                     wantsSelection: { false },      // page content, not omnibox
                                     wantsMarkedField: { false })    // not the Docs class
        XCTAssertEqual(r, R(tap: true, selection: false, emptyReset: false))
    }

    func testMarkedClassFieldFallsThroughToIMKit() {
        // Google-Docs-class field: neither tap nor selection — IMKit's usesMarkedNow
        // picks it up via wantsMarkedField and composes with marked text.
        let w = W(tap: false, sel: .perField, empty: false)
        let r = AppState.gateRouting(w, trusted: { true },
                                     wantsSelection: { false },
                                     wantsMarkedField: { true })
        XCTAssertEqual(r, R(tap: false, selection: false, emptyReset: false))
    }

    func testPageContentRemoteDesktopPassthroughSkipsTap() {
        // Chrome Remote Desktop (remotedesktop.google.com): a scancode tunnel.
        // Local tap Backspace+retype fights the guest IME when both machines run
        // VietTelex. Neither tap nor selection — IMKit then passthroughs.
        let w = W(tap: false, sel: .perField, empty: false)
        let r = AppState.gateRouting(w, trusted: { true },
                                     wantsSelection: { false },
                                     wantsMarkedField: { XCTFail("passthrough settled before the marked verdict"); return false },
                                     wantsPassthroughField: { true })
        XCTAssertEqual(r, R(tap: false, selection: false, emptyReset: false),
                       "no tap-defer → IMKit passthrough, not compose")
    }

    func testWebKitRemoteDesktopPassthroughSkipsInPlace() {
        // Safari CRD would otherwise take the WebKit in-place carve-out.
        let w = W(tap: false, sel: .perField, empty: false)
        let r = AppState.gateRouting(w, trusted: { true },
                                     wantsSelection: { false },
                                     wantsMarkedField: { XCTFail("passthrough settled before the marked verdict"); return false },
                                     wantsPassthroughField: { true },
                                     pageContentInPlace: true)
        XCTAssertEqual(r, R(), "CRD wins over the WebKit in-place carve-out")
    }

    /// Khâu cuối của chuỗi Sheets: routing.emptyReset ⇒ tap emit U+202F dance.
    /// (URL→verdict: EmptyResetFieldURLTests; verdict→routing: test dưới;
    /// emit→dance: usesPlaceholderDance trong FieldVerdictCacheTests.)
    func testTapEmitModeFollowsRouting() {
        typealias C = TerminalTapController
        // Ô Sheets / Excel: emptyReset, KHÔNG phải ⌫ thuần.
        XCTAssertEqual(C.emitMode(for: R(tap: false, selection: false, emptyReset: true),
                                  selectionMode: .emptyReset), .emptyReset)
        // Omnibox: theo selectionEmitMode của app (browser → emptyReset, pin → selection).
        XCTAssertEqual(C.emitMode(for: R(tap: false, selection: true, emptyReset: false),
                                  selectionMode: .emptyReset), .emptyReset)
        XCTAssertEqual(C.emitMode(for: R(tap: false, selection: true, emptyReset: false),
                                  selectionMode: .selection), .selection)
        // Selection thắng emptyReset (omnibox chốt trước ô lưới).
        XCTAssertEqual(C.emitMode(for: R(tap: true, selection: true, emptyReset: true),
                                  selectionMode: .selection), .selection)
        // Terminal/Electron: ⌫ thuần.
        XCTAssertEqual(C.emitMode(for: R(tap: true, selection: false, emptyReset: false),
                                  selectionMode: .selection), .backspace)
        // emptyReset thắng tap: ô Sheets vẫn phải dance dù page content cũng muốn tap.
        XCTAssertEqual(C.emitMode(for: R(tap: true, selection: false, emptyReset: true),
                                  selectionMode: .selection), .emptyReset)
        // Không routing nào → tap không giữ phím (IMKit lo).
        XCTAssertNil(C.emitMode(for: R(), selectionMode: .selection))
    }

    func testPageContentSheetsRoutesToEmptyResetNotPlainTap() {
        // Google Sheets: tap vẫn giữ phím, nhưng emit phải là U+202F dance.
        let w = W(tap: false, sel: .perField, empty: false)
        let r = AppState.gateRouting(w, trusted: { true },
                                     wantsSelection: { false },
                                     wantsMarkedField: { XCTFail("emptyReset chốt trước marked"); return false },
                                     wantsPassthroughField: { false },
                                     wantsEmptyResetField: { true })
        XCTAssertEqual(r, R(tap: false, selection: false, emptyReset: true))
        XCTAssertTrue(r.tapDefer, "IMKit phải nhường cho tap")
    }

    func testWebKitSheetsKeepsInPlaceCarveOut() {
        // Safari: in-place dùng insertText(replacementRange:) nên không có ⌫ nào đụng
        // vùng chọn gợi ý — giữ carve-out, chưa có field report ngược lại.
        let w = W(tap: false, sel: .perField, empty: false)
        let r = AppState.gateRouting(w, trusted: { true },
                                     wantsSelection: { false },
                                     wantsMarkedField: { false },
                                     wantsPassthroughField: { false },
                                     wantsEmptyResetField: { true },
                                     pageContentInPlace: true)
        XCTAssertEqual(r, R(), "Sheets trong Safari vẫn in-place")
    }

    func testCRDBeatsSheetsVerdict() {
        // Ưu tiên: passthrough (CRD) > emptyReset (Sheets).
        let w = W(tap: false, sel: .perField, empty: false)
        let r = AppState.gateRouting(w, trusted: { true },
                                     wantsSelection: { false },
                                     wantsMarkedField: { false },
                                     wantsPassthroughField: { true },
                                     wantsEmptyResetField: { XCTFail("passthrough chốt trước"); return true })
        XCTAssertEqual(r, R())
    }

    func testOmniboxStillRoutesToSelection() {
        let w = W(tap: false, sel: .perField, empty: false)
        let r = AppState.gateRouting(w, trusted: { true },
                                     wantsSelection: { true },
                                     wantsMarkedField: { XCTFail("omnibox settled before the marked verdict"); return false },
                                     wantsPassthroughField: { XCTFail("omnibox settled before the passthrough verdict"); return false })
        XCTAssertEqual(r, R(tap: false, selection: true, emptyReset: false))
    }

    // WEBKIT CARVE-OUT (issue #44, 13/08/2026): Safari on macOS 26 DROPS the tap's
    // synthetic burst in web content (tap-emit fired, screen unchanged — repro
    // anotepad.com + reporter's bing.com), and every bug that motivated the 06/08
    // page-content-to-tap policy was Chromium/Electron. Safari page content routes
    // back to IMKit in-place — the field-proven pre-06/08 behavior; omnibox and the
    // Google-Docs marked class are untouched.
    func testWebKitPageContentRoutesInPlaceNotTap() {
        let w = W(tap: false, sel: .perField, empty: false)
        let r = AppState.gateRouting(w, trusted: { true },
                                     wantsSelection: { false },      // page content
                                     wantsMarkedField: { false },
                                     pageContentInPlace: true)       // Safari-family
        XCTAssertEqual(r, R(tap: false, selection: false, emptyReset: false),
                       "no tap-defer → IMKit composes in-place")
    }

    func testWebKitOmniboxAndMarkedClassUnchanged() {
        let w = W(tap: false, sel: .perField, empty: false)
        // Omnibox: still selection-replace.
        XCTAssertEqual(AppState.gateRouting(w, trusted: { true },
                                            wantsSelection: { true },
                                            wantsMarkedField: { false },
                                            pageContentInPlace: true),
                       R(tap: false, selection: true, emptyReset: false))
        // Docs-class canvas: still falls through to IMKit marked text.
        XCTAssertEqual(AppState.gateRouting(w, trusted: { true },
                                            wantsSelection: { false },
                                            wantsMarkedField: { true },
                                            pageContentInPlace: true),
                       R(tap: false, selection: false, emptyReset: false))
    }

    func testEndToEndSafariPageContentSkipsTap() {
        Accessibility.testTrustOverride = true
        defer {
            Accessibility.testTrustOverride = nil
            FocusedFieldDetector.invalidate()
        }
        // Page-content verdict: not selection, not marked (invalidate() leaves both
        // false and stamps nothing — set explicitly for determinism).
        FocusedFieldDetector._testSetCached(false)
        FocusedFieldDetector._testSetMarked(false)
        FocusedFieldDetector._testSetPassthrough(false)
        XCTAssertFalse(AppState.shared.tapRouting("com.apple.Safari").tapDefer,
                       "Safari page content must reach IMKit in-place")
        XCTAssertTrue(AppState.shared.tapRouting("com.google.Chrome").tapDefer,
                      "Chromium page content stays on the tap")
    }

    func testEndToEndChromeSheetsUsesEmptyReset() {
        Accessibility.testTrustOverride = true
        defer {
            Accessibility.testTrustOverride = nil
            FocusedFieldDetector.invalidate()
        }
        FocusedFieldDetector._testSetCached(false)        // page content, not omnibox
        FocusedFieldDetector._testSetMarked(false)
        FocusedFieldDetector._testSetPassthrough(false)
        FocusedFieldDetector._testSetEmptyReset(true)     // docs.google.com/spreadsheets
        let r = AppState.shared.tapRouting("com.google.Chrome")
        XCTAssertTrue(r.emptyReset, "ô Sheets phải đi U+202F dance")
        XCTAssertFalse(r.tap, "không còn ⌫ thuần")
        FocusedFieldDetector._testSetEmptyReset(false)
        XCTAssertTrue(AppState.shared.tapRouting("com.google.Chrome").tap,
                      "rời Sheets thì page content quay lại tap thường")
    }

    func testEndToEndChromeRemoteDesktopSkipsTap() {
        Accessibility.testTrustOverride = true
        defer {
            Accessibility.testTrustOverride = nil
            FocusedFieldDetector.invalidate()
        }
        FocusedFieldDetector._testSetCached(false)       // page content, not omnibox
        FocusedFieldDetector._testSetMarked(false)
        FocusedFieldDetector._testSetEmptyReset(false)
        FocusedFieldDetector._testSetPassthrough(true)   // remotedesktop.google.com
        XCTAssertFalse(AppState.shared.tapRouting("com.google.Chrome").tapDefer,
                       "Chrome Remote Desktop must not tap-compose (guest IME owns keys)")
        XCTAssertFalse(AppState.shared.tapRouting("com.apple.Safari").tapDefer,
                       "Safari CRD must not tap-compose either")
        FocusedFieldDetector._testSetPassthrough(false)
        XCTAssertTrue(AppState.shared.tapRouting("com.google.Chrome").tapDefer,
                      "leaving CRD restores Chromium page-content tap")
    }
}

// Spotlight overlay vs tap-family routing: FrontmostApp stays the app BEHIND the
// overlay (iTerm/Chrome), so the tap's routing verdict says "compose" while the keys
// actually land in Spotlight's field — whose inline autocomplete eats a synthetic
// Backspace as "delete the selected suggestion", reordering the word (field report
// 2026-07-31: "pas" over iTerm → garbled; log: tap-emit mode=backspace while
// client=com.apple.Spotlight). Contract: raw passthrough unless Spotlight itself is
// explicitly pinned to a tap-family mode.
final class SpotlightOverlayGateTests: XCTestCase {
    func testOverlayForcesRawForUnpinnedSpotlight() {
        for pin: AppState.AppMode? in [nil, .auto, .inPlace, .marked, .axDetect, .passthrough] {
            XCTAssertTrue(TerminalTapController.spotlightOverlayForcesRaw(visible: true, manualPin: pin),
                          "pin=\(String(describing: pin))")
        }
    }
    func testExplicitTapFamilyPinKeepsComposing() {
        for pin: AppState.AppMode in [.tap, .selection, .emptyReset] {
            XCTAssertFalse(TerminalTapController.spotlightOverlayForcesRaw(visible: true, manualPin: pin))
        }
    }
    func testNoOverlayNeverForcesRaw() {
        XCTAssertFalse(TerminalTapController.spotlightOverlayForcesRaw(visible: false, manualPin: nil))
        XCTAssertFalse(TerminalTapController.spotlightOverlayForcesRaw(visible: false, manualPin: .tap))
    }
}

// Issue #32 (field report 2026-08-11): Spotlight opened over a tap/per-field app
// (Chrome, a terminal) composed NOTHING — raw "dduowcj" stayed on screen. Live trace
// showed the client id resolved correctly (client=com.apple.Spotlight) but tapRouting
// still returned tapDefer=true, because it merges in the FRONTMOST app's wants
// (Chrome: sel=.perField) even though Spotlight's own id is never uncertain. Same word
// over TextMate (in-place, no tap wants) worked — the merge contributed nothing there.
final class SpotlightClientIDNeverMergesWithFrontTests: XCTestCase {
    override func setUp() {
        super.setUp()
        Accessibility.testTrustOverride = true   // gateRouting is a no-op untrusted
    }

    override func tearDown() {
        Accessibility.testTrustOverride = nil
        super.tearDown()
    }

    func testSpotlightOverChromeStillComposesInPlace() {
        let r = AppState.shared.tapRouting(AppState.spotlightBundleID, front: "com.google.Chrome")
        XCTAssertFalse(r.tapDefer, "Spotlight's own id must decide routing, not the app behind the overlay")
    }

    func testSpotlightOverTerminalStillComposesInPlace() {
        let r = AppState.shared.tapRouting(AppState.spotlightBundleID, front: "com.apple.Terminal")
        XCTAssertFalse(r.tapDefer)
    }

    func testNonSpotlightClientsStillMergeWithFront() {
        // The nil/uncertain-id safety net must survive for everyone else.
        let r = AppState.shared.tapRouting(nil, front: "com.apple.Terminal")
        XCTAssertTrue(r.tapDefer, "nil client id must still fall back to the frontmost app's rule")
    }
}

// Issue #110 (02/10/2026): Raycast 2.6 opened over Edge — Raycast is a non-activating
// panel, so FrontmostApp stays Edge while IMK reports client=com.raycast.macos. The
// front merge made Raycast's own keys tap-defer (Edge page content → tap) and the tap
// backspace-retyped into Raycast, which applies ⌫ after the inserts ("wngs" → "ưnứ";
// the logged tap-emit bs/ins matched the engine 1:1). Contract: overlay launchers
// route by their OWN rule (inPlace) and the tap yields while IMK serves them.
final class OverlayLauncherRoutingTests: XCTestCase {
    override func setUp() {
        super.setUp()
        Accessibility.testTrustOverride = true
    }

    override func tearDown() {
        Accessibility.testTrustOverride = nil
        ClientFocus.noteActivated(client: nil)
        super.tearDown()
    }

    func testRaycastIsOverlayLauncher() {
        XCTAssertTrue(AppState.isOverlayLauncher("com.raycast.macos"))
        XCTAssertFalse(AppState.isOverlayLauncher("com.microsoft.edgemac"))
        XCTAssertFalse(AppState.isOverlayLauncher(nil))
    }

    func testRaycastOverEdgeOrTerminalComposesViaIMKit() {
        for front in ["com.microsoft.edgemac", "com.google.Chrome", "com.apple.Terminal", "com.vng.zalo"] {
            let r = AppState.shared.tapRouting("com.raycast.macos", front: front)
            XCTAssertFalse(r.tapDefer, "Raycast over \(front): its own inPlace rule decides")
        }
    }

    func testOtherClientsStillMergeWithFront() {
        XCTAssertTrue(AppState.shared.tapRouting(nil, front: "com.apple.Terminal").tapDefer)
        // Unrelated in-place client over a terminal keeps the old safety net.
        XCTAssertTrue(AppState.shared.tapRouting("com.apple.Notes", front: "com.apple.Terminal").tapDefer)
    }

    func testTapYieldsWhileLauncherLatched() {
        XCTAssertTrue(TerminalTapController.overlayLauncherOwnsKeys(
            latchedLauncher: "com.raycast.macos", front: "com.microsoft.edgemac", manualPin: { _ in nil }))
        for pin: AppState.AppMode in [.auto, .inPlace, .marked, .axDetect, .passthrough] {
            XCTAssertTrue(TerminalTapController.overlayLauncherOwnsKeys(
                latchedLauncher: "com.raycast.macos", front: "com.apple.Terminal", manualPin: { _ in pin }),
                "pin=\(pin)")
        }
    }

    func testExplicitTapFamilyPinOnLauncherKeepsTap() {
        for pin: AppState.AppMode in [.tap, .selection, .emptyReset] {
            XCTAssertFalse(TerminalTapController.overlayLauncherOwnsKeys(
                latchedLauncher: "com.raycast.macos", front: "com.apple.Terminal", manualPin: { _ in pin }))
        }
    }

    func testNoLatchNeverYields() {
        XCTAssertFalse(TerminalTapController.overlayLauncherOwnsKeys(
            latchedLauncher: nil, front: "com.apple.Terminal",
            manualPin: { _ in XCTFail("no latch → pin must not be read"); return nil }))
        // Latched id == front (launcher genuinely frontmost, e.g. its settings window):
        // the tap's own routing already answers for it.
        XCTAssertFalse(TerminalTapController.overlayLauncherOwnsKeys(
            latchedLauncher: "com.raycast.macos", front: "com.raycast.macos", manualPin: { _ in nil }))
    }

    func testLatchFollowsIMKActivation() {
        ClientFocus.noteActivated(client: "com.raycast.macos")
        XCTAssertEqual(ClientFocus.overlayLauncher, "com.raycast.macos")
        // Esc → Edge's field re-activates: the panel no longer owns the keyboard.
        ClientFocus.noteActivated(client: "com.microsoft.edgemac")
        XCTAssertNil(ClientFocus.overlayLauncher)
        ClientFocus.noteActivated(client: "com.raycast.macos")
        ClientFocus.noteActivated(client: nil)
        XCTAssertNil(ClientFocus.overlayLauncher)
    }
}

// Field report 2026-08-11: Esc in Spotlight resets the query without closing the
// overlay, cycling activateServer(iTerm)→activateServer(Spotlight) within ~1ms. The
// freshly re-activated session's client.selectedRange() then reported a stale huge
// caret (start=6632 in a field that was actually empty), garbling the next word
// ("được" → "dđuưoựoược"). TelexInputController.spotlightReactivatedTooSoon pins the
// distrust window so the anchor at that first key falls back to the safe
// no-tracking path instead of trusting the bogus caret.
final class SpotlightRapidReactivationTests: XCTestCase {
    private let oneSecondNs: UInt64 = 1_000_000_000

    func testFirstEverActivationIsNeverDistrusted() {
        XCTAssertFalse(TelexInputController.spotlightReactivatedTooSoon(now: oneSecondNs, lastActivateNs: 0))
    }

    func testReactivationWithinWindowIsDistrusted() {
        let last: UInt64 = 10 * oneSecondNs
        let now = last + 3 * oneSecondNs   // matches the field report's ~3.27s gap
        XCTAssertTrue(TelexInputController.spotlightReactivatedTooSoon(now: now, lastActivateNs: last))
    }

    func testReactivationAfterWindowIsTrusted() {
        let last: UInt64 = 10 * oneSecondNs
        let now = last + 6 * oneSecondNs
        XCTAssertFalse(TelexInputController.spotlightReactivatedTooSoon(now: now, lastActivateNs: last))
    }

    func testExactlyAtWindowBoundaryIsTrusted() {
        let last: UInt64 = 10 * oneSecondNs
        let now = last + 5 * oneSecondNs
        XCTAssertFalse(TelexInputController.spotlightReactivatedTooSoon(now: now, lastActivateNs: last))
    }
}

// Issue #32 vòng 3 (field report 12/08, v1.5.5): activateServer(browser) reset
// verdict per-field về false (page content) nhưng scan mới chỉ được kick ở PHÍM
// ĐẦU TIÊN — verdict về sau 77–500ms, cả từ đầu sau refocus chạy trên default
// stale: omnibox bị bare-⌫ ("được" → "ddược"). prefetch() phải kick scan ngay
// từ activateServer để verdict thường về xong TRƯỚC phím đầu.
final class FieldVerdictPrefetchTests: XCTestCase {
    func testPrefetchKicksAScanAfterInvalidate() {
        FocusedFieldDetector.invalidate()
        XCTAssertFalse(FocusedFieldDetector._testIsFresh, "invalidate must zero the stamp")
        FocusedFieldDetector.prefetch()
        // The scan runs on a background queue; in the (untrusted) test host it
        // returns the safe default but must still stamp the cache as fresh.
        let deadline = Date().addingTimeInterval(2)
        while !FocusedFieldDetector._testIsFresh && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        XCTAssertTrue(FocusedFieldDetector._testIsFresh,
                      "prefetch() must kick the async scan without waiting for a keystroke")
    }

    /// Chỉ browser per-field mới đáng prefetch — gate ở call site dựa trên
    /// usesAxDetect, pin ở đây cho cả hai chiều.
    func testPrefetchGateMatchesPerFieldBrowsers() {
        Accessibility.testTrustOverride = true
        defer { Accessibility.testTrustOverride = nil }
        XCTAssertTrue(AppState.shared.usesAxDetect("com.google.Chrome"))
        XCTAssertTrue(AppState.shared.usesAxDetect("com.apple.Safari"))
        XCTAssertFalse(AppState.shared.usesAxDetect(AppState.spotlightBundleID))
        XCTAssertFalse(AppState.shared.usesAxDetect("com.apple.Notes"))
    }
}

// noteFocused: activateServer(com.apple.Spotlight) là bằng chứng chắc chắn overlay
// đang mở — cache phải TRUE ngay lập tức, không đợi CGWindowList scan (burst "pas"
// 2026-07-31: phím dấu emit vào overlay khi cache còn false).
final class SpotlightNoteFocusedTests: XCTestCase {
    func testNoteFocusedStampsVisibleImmediately() {
        SpotlightDetector._testSetVisible(false)
        XCTAssertFalse(SpotlightDetector._testVisible)
        SpotlightDetector.noteFocused()
        XCTAssertTrue(SpotlightDetector._testVisible)
        SpotlightDetector._testSetVisible(false)   // trả trạng thái cho test khác
    }

    // Field report 2026-08-11: typing "được" in Chrome's omnibox right away after
    // closing Spotlight produced "dduwợc" — the first four keys landed raw because
    // isVisible kept reporting stale-true (DetectorBackoff's TTL had grown during
    // Spotlight's long-open, stable session) for 500ms+ after activateServer had
    // already moved to Chrome. noteUnfocused() must clear the cache immediately,
    // the same way noteFocused() sets it — activateServer(anyOtherClient) is
    // equally authoritative proof in the opposite direction.
    func testNoteUnfocusedClearsVisibleImmediately() {
        SpotlightDetector._testSetVisible(true)
        XCTAssertTrue(SpotlightDetector._testVisible)
        SpotlightDetector.noteUnfocused()
        XCTAssertFalse(SpotlightDetector._testVisible)
    }

    /// End-to-end: chains noteUnfocused() into the ACTUAL gate the tap consults per
    /// keystroke (spotlightOverlayForcesRaw), pinning the fix at its point of use —
    /// not just at the cache getter. Before the fix, a long-open Spotlight session
    /// left `visible` stale-true here for 500ms+ after activateServer had already
    /// moved to Chrome, so the gate kept forcing raw passthrough into the omnibox.
    func testNoteUnfocusedStopsOverlayFromForcingRawOnTheNextKey() {
        SpotlightDetector._testSetVisible(true)   // Spotlight was just open
        XCTAssertTrue(TerminalTapController.spotlightOverlayForcesRaw(
            visible: SpotlightDetector._testVisible, manualPin: nil),
            "sanity: while still marked visible, the gate must force raw")

        SpotlightDetector.noteUnfocused()          // activateServer moved to Chrome
        XCTAssertFalse(TerminalTapController.spotlightOverlayForcesRaw(
            visible: SpotlightDetector._testVisible, manualPin: nil),
            "the very next key must be allowed to compose, not forced raw")
    }
}

// POLICY 2026-08-06, nửa còn lại: browser (axDetect) KHÔNG có quyền Trợ năng thì
// degrade sang MARKED TEXT (kênh composition — hợp đồng chuẩn web mà mọi editor
// phải hỗ trợ vì người dùng CJK), không còn rơi về in-place như cũ. In-place chính
// là kênh không-hợp-đồng đã gây toàn bộ loạt bug web-editor đầu tháng 8. Quy tắc
// này khớp với nguyên tắc đã có sẵn cho mọi mode tap-family: "thiếu AX → marked,
// không bao giờ âm thầm về in-place".
final class UntrustedBrowserFallbackTests: XCTestCase {
    override func tearDown() {
        Accessibility.testTrustOverride = nil
        super.tearDown()
    }

    func testUntrustedBuiltInBrowserDegradesToMarked() {
        Accessibility.testTrustOverride = false
        XCTAssertTrue(AppState.shared.usesMarkedText("com.google.Chrome"),
                      "browser without AX must compose with marked text")
        XCTAssertTrue(AppState.shared.usesMarkedText("com.apple.Safari"))
    }

    func testTrustedBrowserDoesNotForceMarked() {
        Accessibility.testTrustOverride = true
        XCTAssertFalse(AppState.shared.usesMarkedText("com.google.Chrome"),
                       "with AX the per-field routing decides, not blanket marked")
    }

    func testUntrustedNonBrowserRulesUnchanged() {
        Accessibility.testTrustOverride = false
        // Learned/built-in fallback apps already degraded to marked before this policy.
        XCTAssertTrue(AppState.shared.usesMarkedText("com.hnc.Discord"))
        // Built-in in-place apps stay in-place even untrusted (probed-good contract).
        XCTAssertFalse(AppState.shared.usesMarkedText("com.apple.Notes"))
    }
}

// POLICY 06/08/2026 "app lạ đi kênh an toàn": app không có rule ở đâu cả (không
// manual, không built-in, không learned fallback) → TAP khi có Accessibility,
// MARKED khi không — thay cho in-place + probe-học. Lý do: Discord (05/08) và
// Lark (06/08, bundle id trôi khỏi rule) chứng minh lỗi in-place có thể VÔ HÌNH
// với self-report — probe "học in-place OK" trong khi màn hình sai. Tap và
// marked là 2 kênh duy nhất có hợp đồng. Toggle Thử Nghiệm quay về hành vi cũ.
final class UnknownAppPolicyTests: XCTestCase {

    private let unknown = "com.example.some-random-app"
    private var savedPolicy = true

    override func setUp() {
        super.setUp()
        savedPolicy = AppState.shared.safeUnknownApps
    }

    override func tearDown() {
        AppState.shared.safeUnknownApps = savedPolicy
        AppState.shared.unmarkInPlaceGood(unknown)
        super.tearDown()
    }

    func testUnknownAppIsTapFamilyByDefault() {
        AppState.shared.safeUnknownApps = true
        XCTAssertEqual(AppState.shared.autoResolvedMode(unknown), .tap,
                       "app lạ phải hiện tap trong menu, không phải 'chưa dò'")
        XCTAssertTrue(AppState.shared.usesMarkedText(unknown),
                      "marked là degradation của tap-family khi thiếu Accessibility")
        XCTAssertFalse(AppState.shared.needsProbe(unknown),
                       "không còn gì để dò — one-shot probe nghỉ hưu dưới policy này")
    }

    func testCuratedInPlaceListIsUntouched() {
        AppState.shared.safeUnknownApps = true
        XCTAssertEqual(AppState.shared.autoResolvedMode("com.apple.Notes"), .inPlace)
        XCTAssertFalse(AppState.shared.usesMarkedText("com.apple.Notes"))
        // TextEdit vào list built-in batch 06/08 (maintainer field-verified).
        XCTAssertEqual(AppState.shared.autoResolvedMode("com.apple.TextEdit"), .inPlace)
    }

    /// probedAppsCache là chính cái cache self-report mà policy này không tin —
    /// Lark học nhầm "in-place OK" từ caret thật thà trong khi editor nuốt edit.
    /// Máy đã học nhầm phải TỰ KHỎI khi update, không cần xoá learned data.
    func testLearnedInPlaceNoLongerGrantsInPlace() {
        AppState.shared.markInPlaceGood(unknown)
        AppState.shared.safeUnknownApps = true
        XCTAssertEqual(AppState.shared.autoResolvedMode(unknown), .tap,
                       "learned in-place không được cứu app lạ khỏi kênh an toàn")
        XCTAssertTrue(AppState.shared.usesMarkedText(unknown))
    }

    func testLegacyToggleRestoresProbeAndLearn() {
        AppState.shared.safeUnknownApps = false
        XCTAssertNil(AppState.shared.autoResolvedMode(unknown), "legacy: chưa dò → nil")
        AppState.shared.markInPlaceGood(unknown)
        XCTAssertEqual(AppState.shared.autoResolvedMode(unknown), .inPlace,
                       "legacy: learned in-place lại có hiệu lực")
        XCTAssertFalse(AppState.shared.usesMarkedText(unknown))
    }
}

// Issue #110 vòng 2 (02/10/2026, v1.8.8 debug logs của tqkhiemDev): Raycast mở trên
// Edge, phím ĐẦU tới tap trước khi IMK activate panel → tap soạn như Edge và chèn "ư"
// (log: `tap-emit mode=emptyReset bs=0 ins=1` @12471.9 / @112343.4, rồi
// `activateServer client=com.raycast.macos front=com.microsoft.edgemac` @12512.7 /
// @112391.5). IMK bắt đầu engine mới với "ngs"/"ord" → "ưngs", "ưord " (applyInPlace
// start=1 anchor=1). Các test này phát lại đúng thứ tự sự kiện đó trên mô hình ô chữ
// thuần: tap gõ như Edge → activateServer Raycast → phím IMK.
final class TapHandoffTests: XCTestCase {
    private let raycast = "com.raycast.macos"
    private let edge = "com.microsoft.edgemac"
    private let t0: UInt64 = 10_000_000_000
    private let e0: UInt64 = 41

    /// Settings trong log của reporter (freeMarking, liveSpell, autoRestore, ctxEnglish,
    /// teencode, collisionVN bật; simpleTelex/modern/vni tắt).
    private func reporterEngine() -> TelexEngine {
        var f = AppState.EngineFlags()
        f.freeMarking = true; f.modernTone = false; f.liveSpellCheck = true
        f.simpleTelex = false; f.quickTelex = false; f.vniMode = false
        f.contextualEnglish = true; f.collisionPrefersVietnamese = true; f.teencode = true
        var e = TelexEngine()
        e.apply(f)
        return e
    }

    /// Tap (as Edge) types `tapKeys` into the panel's field the way SyntheticKeyboard
    /// would; returns the field text and the snapshot noteHandoff() records.
    private func tapTypes(_ tapKeys: String) -> (field: String, snap: TapHandoff.Snapshot) {
        var tap = reporterEngine()
        let field = NSMutableString()
        for ch in tapKeys {
            switch tap.feed(ch) {
            case .passthrough: field.append(String(ch))
            case .none: break
            case let .replace(bs, ins):
                field.deleteCharacters(in: NSRange(location: field.length - bs, length: bs))
                field.append(ins)
            }
        }
        return (field as String, .init(raw: tap.rawKeystrokes, composed: tap.composed, atNs: t0, epoch: e0))
    }

    /// IMK in-place composition over `field` (anchor/onLen window, as applyInPlace),
    /// optionally adopting the tap's snapshot at the first word key, then a boundary.
    private func imkTypes(_ keys: String, into start: String, adopting snap: TapHandoff.Snapshot?,
                          space: Bool) -> String {
        var engine = reporterEngine()
        let field = NSMutableString(string: start)
        var anchor = field.length, onLen = 0
        if let s = TapHandoff.adoptable(snap, nowNs: t0 + 100_000_000, epochNow: e0 + 1,
                                        latchedLauncher: raycast, clientID: raycast,
                                        textBeforeCaret: start),
           TapHandoff.replay(&engine, raw: s.raw, expect: s.composed) {
            onLen = (s.composed as NSString).length
            anchor = field.length - onLen
        }
        func apply(_ a: TelexAction, _ ch: Character?) {
            switch a {
            case .passthrough:
                if let ch { field.insert(String(ch), at: anchor + onLen); onLen += 1 }
            case .none: break
            case let .replace(bs, ins):
                field.replaceCharacters(in: NSRange(location: anchor + onLen - bs, length: bs), with: ins)
                onLen += (ins as NSString).length - bs
            }
        }
        for ch in keys { apply(engine.feed(ch), ch) }
        if space {
            apply(engine.commitBoundary(autoRestore: true), nil)
            field.append(" ")
        }
        return field as String
    }

    // MARK: Hai chuỗi trong report

    func testWngsAfterTapFirstKeyBecomesUng() {
        let (field, snap) = tapTypes("w")
        XCTAssertEqual(field, "ư", "tap đã chèn ư vào ô Raycast trước activateServer")
        XCTAssertEqual(imkTypes("ngs", into: field, adopting: nil, space: false), "ưngs",
                       "bản 1.8.8: engine IMK mới không biết chữ ư — đúng triệu chứng report")
        XCTAssertEqual(imkTypes("ngs", into: field, adopting: snap, space: false), "ứng")
    }

    func testWordAfterTapFirstKeyRestoresEnglish() {
        let (field, snap) = tapTypes("w")
        XCTAssertEqual(imkTypes("ord", into: field, adopting: nil, space: true), "ưord ",
                       "bản 1.8.8: đúng triệu chứng report")
        // Phát lại phím THÔ "w" (không phải seed("ư") = "uw") nên khôi phục ra "word".
        XCTAssertEqual(imkTypes("ord", into: field, adopting: snap, space: true), "word ")
    }

    func testTwoTapKeysBeforeActivationStillContinue() {
        // Hàng đợi synthetic chưa rút → tap tự chèn cả phím thứ 2 (noteHandoff chụp lại).
        let (field, snap) = tapTypes("wo")
        XCTAssertEqual(imkTypes("rd", into: field, adopting: snap, space: true), "word ")
        let (f2, s2) = tapTypes("wn")
        XCTAssertEqual(imkTypes("gs", into: f2, adopting: s2, space: false), "ứng")
    }

    // MARK: Không bao giờ đoán sai mà sửa chữ

    func testRejectsWhenScreenDisagrees() {
        let (_, snap) = tapTypes("w")
        for screen in ["", "u", "aư", "query ưu", "u\u{31B}"] {   // last: NFD ư
            XCTAssertNil(TapHandoff.adoptable(snap, nowNs: t0 + 1, epochNow: e0 + 1,
                                              latchedLauncher: raycast, clientID: raycast,
                                              textBeforeCaret: screen), "screen=\(screen)")
        }
        // Chữ tap chèn đứng sau ranh giới: vẫn là từ của nó → nhận.
        XCTAssertNotNil(TapHandoff.adoptable(snap, nowNs: t0 + 1, epochNow: e0 + 1,
                                             latchedLauncher: raycast, clientID: raycast,
                                             textBeforeCaret: "open ư"))
        // Engine IMK giữ nguyên khi bị từ chối: phím đi tiếp như 1.8.8, không sửa gì.
        XCTAssertEqual(imkTypes("ngs", into: "u", adopting: snap, space: false), "ungs")
    }

    func testRejectsWrongFocusHistory() {
        let (field, snap) = tapTypes("w")
        func ok(epoch: UInt64, latched: String?, client: String?, now: UInt64) -> Bool {
            TapHandoff.adoptable(snap, nowNs: now, epochNow: epoch, latchedLauncher: latched,
                                 clientID: client, textBeforeCaret: field) != nil
        }
        XCTAssertTrue(ok(epoch: e0 + 1, latched: raycast, client: raycast, now: t0 + 50_000_000))
        XCTAssertFalse(ok(epoch: e0, latched: raycast, client: raycast, now: t0 + 1), "chưa activate gì")
        XCTAssertFalse(ok(epoch: e0 + 2, latched: raycast, client: raycast, now: t0 + 1),
                       "có một lần đổi focus khác xen giữa")
        XCTAssertFalse(ok(epoch: e0 + 1, latched: nil, client: raycast, now: t0 + 1))
        XCTAssertFalse(ok(epoch: e0 + 1, latched: raycast, client: raycast,
                          now: t0 + TapHandoff.maxAgeNs + 1), "ảnh chụp thiu")
        XCTAssertFalse(ok(epoch: e0 + 1, latched: raycast, client: raycast, now: t0 - 1))
    }

    func testEdgeItselfNeverAdopts() {
        // Raycast không mở: client là Edge (hoặc bất kỳ app thường nào) → không bao giờ.
        let (field, snap) = tapTypes("w")
        for client in [edge, "com.google.Chrome", "com.apple.Terminal", nil] as [String?] {
            XCTAssertNil(TapHandoff.adoptable(snap, nowNs: t0 + 1, epochNow: e0 + 1,
                                              latchedLauncher: client, clientID: client,
                                              textBeforeCaret: field), "client=\(client ?? "nil")")
        }
    }

    func testReplayRejectsMismatch() {
        var e = reporterEngine()
        XCTAssertFalse(TapHandoff.replay(&e, raw: "w", expect: "u"))
        XCTAssertTrue(e.isEmpty, "từ chối → engine sạch")
        XCTAssertTrue(TapHandoff.replay(&e, raw: "w", expect: "ư"))
        XCTAssertEqual(e.rawKeystrokes, "w")
    }

    func testSnapshotIsOneShot() {
        TapHandoff.record(.init(raw: "w", composed: "ư", atNs: t0, epoch: e0))
        XCTAssertNotNil(TapHandoff.take())
        XCTAssertNil(TapHandoff.take())
        TapHandoff.record(.init(raw: "w", composed: "ư", atNs: t0, epoch: e0))
        TapHandoff.clear()
        XCTAssertNil(TapHandoff.take())
    }

    func testLauncherPresenceGate() {
        XCTAssertTrue(FrontmostApp.anyOverlayLauncher(["com.apple.finder", "com.raycast.macos"]))
        XCTAssertFalse(FrontmostApp.anyOverlayLauncher(["com.apple.finder", nil, "com.microsoft.edgemac"]))
    }

    /// Chi phí đo được: noteHandoff() (khi có launcher chạy) = 1 lock đọc cờ + dựng 2
    /// chuỗi ngắn + 1 lock ghi, chỉ ở lần tap TỰ chèn chữ (không phải mỗi phím).
    func testRecordCostIsNegligible() {
        var e = reporterEngine()
        for ch in "nguyeenx" { _ = e.feed(ch) }
        let n = 20_000
        let start = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<n {
            _ = FrontmostApp.shared.overlayLauncherRunning
            TapHandoff.record(.init(raw: e.rawKeystrokes, composed: e.composed,
                                    atNs: DispatchTime.now().uptimeNanoseconds, epoch: ClientFocus.epoch))
        }
        let perNs = (DispatchTime.now().uptimeNanoseconds - start) / UInt64(n)
        TapHandoff.clear()
        print("TapHandoff record cost: \(perNs) ns/emit")
        XCTAssertLessThan(perNs, 20_000, "phải là vài trăm ns, không phải ms")
    }
}
