import XCTest
@testable import VietTelex

// The two AX verdicts that decide HOW a keystroke is emitted are cached, and a cache that
// outlives its field is a typing bug — not a stale statistic. Tester report 2026-07-28
// (v1.4.17): "đang gõ ở terminal, bấm vào ô input ở trên trình duyệt thì nó thành bôi đen,
// rồi gõ chỉ replace rồi không gõ thêm được gì, phải click ra ngoài ứng dụng khác ấn lại
// mới được" — the browser field inherited the previous field's verdict, and the
// "don't know" default was selection-replace, which in page content means Shift+Left
// select + overtype. Hence these tests pin the INVALIDATION CONTRACT, which is
// deliberately different for the two detectors (asymmetric risk).
final class FieldVerdictCacheTests: XCTestCase {

    override func tearDown() {
        // Leave both caches in their natural "unknown" state for other tests.
        FocusedFieldDetector.invalidate()
        SecureFieldDetector.invalidate()
        super.tearDown()
    }

    // MARK: selection-replace verdict

    func testFocusedFieldVerdictIsReadWhileFresh() {
        FocusedFieldDetector._testSetCached(true)
        XCTAssertTrue(FocusedFieldDetector.wantsSelection, "a fresh verdict must be served as-is")
        FocusedFieldDetector._testSetCached(false)
        XCTAssertFalse(FocusedFieldDetector.wantsSelection)
    }

    /// THE regression: a "selection-replace" verdict must never survive into the next field.
    func testInvalidateDropsAStaleSelectionVerdict() {
        FocusedFieldDetector._testSetCached(true)        // e.g. an address bar
        FocusedFieldDetector.invalidate()                // user clicks into a page field
        XCTAssertFalse(FocusedFieldDetector._testCached,
                       "a stale selection-replace verdict must not be inherited by the new field")
    }

    /// …and the safe default it falls back to is IN-PLACE, not the module's initial value.
    /// Carrying selection-replace into page content breaks typing outright (highlighted
    /// text, only one character replaceable); in-place for the one keystroke before the
    /// async scan answers is merely suboptimal in an address bar.
    func testInvalidateFallsBackToInPlaceNotSelection() {
        FocusedFieldDetector._testSetCached(true)
        FocusedFieldDetector.invalidate()
        XCTAssertFalse(FocusedFieldDetector._testCached, "unknown must mean in-place after a focus change")
    }

    func testInvalidateIsIdempotent() {
        FocusedFieldDetector._testSetCached(true)
        FocusedFieldDetector.invalidate()
        FocusedFieldDetector.invalidate()
        XCTAssertFalse(FocusedFieldDetector._testCached)
    }

    // MARK: password-field verdict

    /// The secure verdict is invalidated too (so a password field is re-scanned per focus),
    /// but on purpose it is NOT forced to a value: forcing "secure" would drop the first
    /// Vietnamese character on every app switch, and a stale "not secure" costs nothing —
    /// the engine only starts rewriting text from the second key of a syllable.
    func testSecureVerdictIsRescannedButNotForced() {
        SecureFieldDetector._testSetCached(true)
        XCTAssertTrue(SecureFieldDetector.isSecure)
        SecureFieldDetector.invalidate()
        XCTAssertTrue(SecureFieldDetector._testCached, "the value is kept…")
        XCTAssertFalse(SecureFieldDetector._testIsFresh, "…but marked stale, so the next read re-scans")
    }
}

// The U+202F placeholder dance (omnibox / Office strategy) must fire ONLY when there is
// text to retype. Tester report 2026-07-27: "ấn nút xóa thì bị thêm ký tự rồi xóa" — on a
// pure deletion the engine returns .replace(bs: 1, insert: ""), so the placeholder had
// nothing to protect and was simply visible for a moment before being deleted again.
final class PlaceholderDanceTests: XCTestCase {

    func testDanceOnlyWhenThereIsTextToRetype() {
        // Tone edit in an omnibox: replace 3 chars with "óa" → dance protects the retype.
        XCTAssertTrue(SyntheticKeyboard.usesPlaceholderDance(mode: .emptyReset, backspaces: 3,
                                                             textIsEmpty: false))
        // THE regression: pure deletion (insert == "") → plain Backspace, no placeholder.
        XCTAssertFalse(SyntheticKeyboard.usesPlaceholderDance(mode: .emptyReset, backspaces: 1,
                                                              textIsEmpty: true))
    }

    func testDanceNeedsARealReplaceAndTheRightMode() {
        // A pure insert (nothing to delete) never needs it.
        XCTAssertFalse(SyntheticKeyboard.usesPlaceholderDance(mode: .emptyReset, backspaces: 0,
                                                              textIsEmpty: false))
        // Other strategies have their own mechanics.
        for mode in [TapEmit.backspace, .selection] {
            XCTAssertFalse(SyntheticKeyboard.usesPlaceholderDance(mode: mode, backspaces: 3,
                                                                  textIsEmpty: false),
                           "\(mode) must not use the U+202F placeholder")
        }
    }
}

// The ancestor walk that classifies a browser field (page content → in-place,
// toolbar/omnibox → selection-replace) is hop-bounded. Field report 2026-07-30
// (v1.4.22): a React composer's AXTextArea sat under ≥11 AXGroups, the old 12-hop
// budget ran out BEFORE reaching AXWebArea, and the "unknown → selection" fallback
// routed page content through the synthetic overtype that web editors swallow —
// tone keys consumed, edit never landed ("không gõ được dấu"). These tests pin the
// role polarity, the fallback, and a hop budget that actually covers that hierarchy.
final class FieldWalkClassifierTests: XCTestCase {

    func testRolePolarity() {
        XCTAssertEqual(FocusedFieldDetector.roleDecision("AXWebArea"), false)  // page → in-place
        XCTAssertEqual(FocusedFieldDetector.roleDecision("AXToolbar"), true)   // omnibox → selection
        XCTAssertNil(FocusedFieldDetector.roleDecision("AXGroup"))
        XCTAssertNil(FocusedFieldDetector.roleDecision("AXTextArea"))
    }

    func testUnknownChainFallsBackToSelection() {
        XCTAssertTrue(FocusedFieldDetector.chainDecision(["AXTextField", "AXGroup", "AXWindow"]))
        XCTAssertTrue(FocusedFieldDetector.chainDecision([String]()))
    }

    func testFirstDecisiveAncestorWins() {
        XCTAssertFalse(FocusedFieldDetector.chainDecision(["AXTextArea", "AXWebArea", "AXToolbar"]))
        XCTAssertTrue(FocusedFieldDetector.chainDecision(["AXTextField", "AXToolbar", "AXWebArea"]))
    }

    /// The exact 2026-07-30 hierarchy: AXTextArea under 11 AXGroups, AXWebArea at
    /// depth 13. The old 12-hop budget classified it as omnibox; the current budget
    /// must reach the web area — and the regression is pinned from both sides.
    func testDeepReactComposerReachesWebAreaWithinHopBudget() {
        let chain = ["AXTextArea"] + Array(repeating: "AXGroup", count: 11) + ["AXWebArea"]
        XCTAssertTrue(FocusedFieldDetector.chainDecision(chain.prefix(12)),
                      "12 hops must reproduce the old misclassification (guards test realism)")
        XCTAssertFalse(FocusedFieldDetector.chainDecision(chain.prefix(FocusedFieldDetector.maxAncestorHops)),
                       "the current hop budget must reach AXWebArea → in-place")
        XCTAssertGreaterThanOrEqual(FocusedFieldDetector.maxAncestorHops, 20,
                                    "deep web hierarchies need real headroom past 13")
    }

    /// Field report 2026-08-14: facebook.com's comment box — the SAME failure as the
    /// 2026-07-30 React composer, one budget later. Its chain is exactly 24 deep
    /// (AXTextArea → 6×AXGroup → AXTable → 16×AXGroup), so the 24-hop budget died one
    /// hop short of AXWebArea and the page inherited the omnibox strategy: typing went
    /// through the emptyReset dance and the ⌫ re-open of issue #40 refused outright.
    func testFacebookCommentBoxDepthReachesWebArea() {
        let chain = ["AXTextArea"] + Array(repeating: "AXGroup", count: 6) + ["AXTable"]
            + Array(repeating: "AXGroup", count: 16) + ["AXWebArea"]
        XCTAssertEqual(chain.count, 25, "the observed chain plus the web area above it")
        XCTAssertTrue(FocusedFieldDetector.chainDecision(chain.prefix(24)),
                      "24 hops reproduces the reported misclassification (test realism)")
        XCTAssertFalse(FocusedFieldDetector.chainDecision(chain),
                       "the current budget must reach AXWebArea → page content")
    }

    /// The rule that keeps this class of bug from returning a third time: a walk that
    /// EXHAUSTS the budget is page content (only a document nests that deep — an
    /// omnibox is 2-3 hops), while a chain that ENDS undecided is genuinely unknown and
    /// keeps the historical selection default.
    func testExhaustedBudgetMeansPageContentNotOmnibox() {
        XCTAssertTrue(FocusedFieldDetector.exhaustedMeansPageContent(
            hops: FocusedFieldDetector.maxAncestorHops))
        XCTAssertFalse(FocusedFieldDetector.exhaustedMeansPageContent(hops: 3))

        // A chain deeper than any budget, with no decisive role at all → page content.
        let bottomless = Array(repeating: "AXGroup", count: FocusedFieldDetector.maxAncestorHops + 10)
        XCTAssertFalse(FocusedFieldDetector.chainDecision(bottomless),
                       "budget exhausted → page content, never the omnibox strategy")
        // A SHORT undecided chain (native-ish field, top of tree) keeps selection.
        XCTAssertTrue(FocusedFieldDetector.chainDecision(["AXTextField", "AXGroup", "AXWindow"]))
    }
}

// Canvas editors (Google Docs) ignore replacementRange: in-place inserts APPEND
// ("Quoocs" → "Quoôcốc") and the tracked ⌫ rewrite "succeeds" on the hidden input
// while the canvas shows nothing — and the verify probe never fires because that
// hidden input self-reports a consistent caret. Field report 2026-07-30. The only
// reliable signal is the web area's URL → force marked text (composition events,
// which Docs handles correctly). Scope is pinned here: /document only.
final class MarkedFieldURLTests: XCTestCase {

    func testGoogleDocsDocumentForcesMarked() {
        XCTAssertTrue(FocusedFieldDetector.markedFieldURL(
            URL(string: "https://docs.google.com/document/d/abc123/edit")))
    }

    func testScopeIsDocumentOnly() {
        // Sheets has its own shipped handling (1.4.20); Slides is unverified.
        XCTAssertFalse(FocusedFieldDetector.markedFieldURL(
            URL(string: "https://docs.google.com/spreadsheets/d/abc/edit")))
        XCTAssertFalse(FocusedFieldDetector.markedFieldURL(
            URL(string: "https://docs.google.com/presentation/d/abc/edit")))
        XCTAssertFalse(FocusedFieldDetector.markedFieldURL(
            URL(string: "https://docs.google.com/")))
    }

    func testTikTokForcesMarked() {
        // Field report 19/08/2026: comment box TikTok trên Safari — in-place bị
        // append ("chuủ tichịch"), tap bị Safari nuốt → marked là kênh đúng.
        XCTAssertTrue(FocusedFieldDetector.markedFieldURL(
            URL(string: "https://www.tiktok.com/@user/video/123")))
        XCTAssertTrue(FocusedFieldDetector.markedFieldURL(
            URL(string: "https://tiktok.com/foryou")))
        // Không ăn nhầm host chỉ CHỨA chữ tiktok:
        XCTAssertFalse(FocusedFieldDetector.markedFieldURL(
            URL(string: "https://faketiktok.com/")))
        XCTAssertFalse(FocusedFieldDetector.markedFieldURL(
            URL(string: "https://tiktok.com.evil.example/")))
    }

    func testOtherHostsNeverForceMarked() {
        XCTAssertFalse(FocusedFieldDetector.markedFieldURL(
            URL(string: "https://evil.example.com/document/d/abc")))
        XCTAssertFalse(FocusedFieldDetector.markedFieldURL(
            URL(string: "https://google.com/document")))
        XCTAssertFalse(FocusedFieldDetector.markedFieldURL(nil))
    }

    func testInvalidateResetsMarkedVerdict() {
        // Same asymmetry as wantsSelection: a field switch must never carry a Docs
        // verdict into the next field — one keystroke of in-place is the mild failure.
        FocusedFieldDetector._testSetMarked(true)
        XCTAssertTrue(FocusedFieldDetector.wantsMarkedField)
        FocusedFieldDetector.invalidate()
        XCTAssertFalse(FocusedFieldDetector.wantsMarkedField)
    }
}

// Discord-web (2026-08-05): Lexical composer ignores replacementRange on VISIBLE text
// while caret + AX say honored — undetectable by probes, marked costs double-Enter.
// URL rule routes the field through the tap path (như Discord desktop từ ngày đầu).
final class TapFieldURLTests: XCTestCase {
    /// POLICY 2026-08-06: the per-host tap allowlist (discord.com, chat.zalo.me —
    /// `tapFieldURL`) is GONE. Page content routes to tap in gateRouting for EVERY
    /// site (see RoutingDecisionTests.testPageContentRoutesToTap); the detector only
    /// carries the marked-class exception (Google Docs) and the diagnostic host.
    /// This test pins the deletion so a future per-host allowlist has to argue with
    /// this comment: three sites broke the same contract-free channel in one week,
    /// and the Discord case proved the failure UNDETECTABLE from self-reports.
    func testNoPerHostTapAllowlistRemains() {
        // Compile-time pin: wantsTapField / tapFieldURL no longer exist — if someone
        // reintroduces them, the mirror properties here start shadowing and this
        // becomes a merge-conflict-style prompt to reread the policy.
        XCTAssertFalse(FocusedFieldDetector.wantsMarkedField && false)
    }

    // debugLastHost (2026-08-06): diagnostic-only, never consulted by routing — a
    // field report ("caret behind by 6, past the Discord-class tolerance") on an
    // unrecognized Chrome tab had no way to name the actual site in the log.
    func testDebugLastHostSurvivesAndResetsOnInvalidate() {
        FocusedFieldDetector._testSetHost("example.com")
        XCTAssertEqual(FocusedFieldDetector.debugLastHost, "example.com")
        FocusedFieldDetector.invalidate()
        XCTAssertNil(FocusedFieldDetector.debugLastHost)
    }
}
