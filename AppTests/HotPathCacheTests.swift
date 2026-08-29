import XCTest
@testable import VietTelex

// Everything the keystroke path reads must come from MEMORY. Three regressions this
// file locks down, all found by an audit of what a single keypress actually costs:
//
//  1. `Accessibility.isTrusted` used to call AXIsProcessTrusted() INLINE whenever its
//     5s TTL had lapsed — a ~10-15ms out-of-process TCC check landing on whichever
//     keystroke happened to be unlucky, on both the tap thread and the IMKit main
//     thread. It now serves the cached answer always and refreshes in the background
//     (the SpotlightDetector/SecureFieldDetector shape), with ONE synchronous read
//     ever: the first, at launch, before any keystroke exists.
//  2. The three AX/window-list detectors re-scanned every 200-300ms for the whole
//     duration of a typing run — the same verdict, ~8 cross-process round trips a
//     second. They now back their TTL off while the verdict keeps repeating.
//  3. The engine toggles were `UserDefaults.object(forKey:)` reads — 7 per keystroke,
//     plus autoRestore per word boundary. Now cached in memory, with the setter
//     writing BOTH the cache and the defaults so Settings still applies live.
final class HotPathCacheTests: XCTestCase {

    // MARK: - 1. trust cache: stale read + async refresh

    /// The read plan is a pure function precisely so this can be pinned without a live
    /// Accessibility grant.
    func testFirstEverReadIsTheOnlySynchronousOne() {
        XCTAssertEqual(Accessibility.trustReadPlan(hasValue: false, lastCheckNs: 0,
                                                   nowNs: 1_000, refreshing: false),
                       .syncFirstRead,
                       "with no cached answer there is nothing to serve — read TCC once")
        // …and never again, however stale the cache gets.
        XCTAssertNotEqual(Accessibility.trustReadPlan(hasValue: true, lastCheckNs: 1,
                                                      nowNs: .max, refreshing: false),
                          .syncFirstRead,
                          "a keystroke must never pay the TCC IPC")
    }

    func testFreshCachedAnswerIsServedWithoutAnyRefresh() {
        let ttl = Accessibility.trustTTLNs
        XCTAssertEqual(Accessibility.trustReadPlan(hasValue: true, lastCheckNs: 1_000,
                                                   nowNs: 1_000 + ttl - 1, refreshing: false),
                       .serveCached)
    }

    func testExpiredTTLServesTheStaleAnswerAndRefreshesInTheBackground() {
        let ttl = Accessibility.trustTTLNs
        XCTAssertEqual(Accessibility.trustReadPlan(hasValue: true, lastCheckNs: 1_000,
                                                   nowNs: 1_000 + ttl, refreshing: false),
                       .serveCachedAndRefresh,
                       "TTL expiry must NOT block the keystroke on a TCC call")
    }

    /// invalidateCache() stamps lastCheckNs = 0, and that must read as "stale now" —
    /// the trust-change observer relies on the very next read kicking a refresh instead
    /// of waiting out a TTL from a bogus timestamp.
    func testInvalidatedCacheRefreshesOnTheNextRead() {
        XCTAssertEqual(Accessibility.trustReadPlan(hasValue: true, lastCheckNs: 0,
                                                   nowNs: 5, refreshing: false),
                       .serveCachedAndRefresh)
    }

    /// The refresh is deduped: while one background check is in flight, further reads
    /// just take the cached value (no thundering herd of TCC calls per keystroke).
    func testRefreshIsDedupedWhileOneIsInFlight() {
        XCTAssertEqual(Accessibility.trustReadPlan(hasValue: true, lastCheckNs: 0,
                                                   nowNs: .max, refreshing: true),
                       .serveCached)
    }

    /// End-to-end on the real cache state (no live TCC needed): a stale entry still
    /// answers immediately, and with the value it had.
    func testStaleTrustCacheStillAnswersImmediately() {
        let savedOverride = Accessibility.testTrustOverride
        Accessibility.testTrustOverride = nil          // exercise the cache itself
        defer {
            Accessibility.testTrustOverride = savedOverride
            Accessibility._testForgetTrustCache()
        }
        Accessibility._testSetTrustCache(true)
        XCTAssertTrue(Accessibility._testTrustIsFresh)
        XCTAssertTrue(Accessibility.isTrusted, "a fresh cached answer is served as-is")

        Accessibility.invalidateCache()
        XCTAssertFalse(Accessibility._testTrustIsFresh, "invalidate marks it stale…")
        // …but the READ still returns the last known value synchronously; the refresh
        // happens on a background queue and lands later. (Revoke-critical paths — the
        // watchdog and the tapDisabledBy* branch — call AXIsProcessTrusted directly and
        // never read this cache, which is what makes the stale answer safe.)
        XCTAssertTrue(Accessibility.isTrusted)
    }

    // MARK: - 2. detector TTL backoff

    func testTTLStaysAtBaseUntilTheVerdictHasRepeated() {
        let base: UInt64 = 200_000_000
        for runs in 0..<DetectorBackoff.threshold {
            XCTAssertEqual(DetectorBackoff.ttl(base: base, stableRuns: runs), base,
                           "a fresh focus must be re-scanned at the base TTL")
        }
    }

    func testTTLDoublesPerExtraIdenticalVerdictAndIsCapped() {
        let base: UInt64 = 200_000_000
        XCTAssertEqual(DetectorBackoff.ttl(base: base, stableRuns: 3), 400_000_000)
        XCTAssertEqual(DetectorBackoff.ttl(base: base, stableRuns: 4), 800_000_000)
        // 1.6s would exceed the cap — a verdict may never go staler than 1s.
        XCTAssertEqual(DetectorBackoff.ttl(base: base, stableRuns: 5), DetectorBackoff.capNs)
        // Absurd run counts must not overflow the shift.
        XCTAssertEqual(DetectorBackoff.ttl(base: base, stableRuns: 10_000), DetectorBackoff.capNs)
        XCTAssertLessThanOrEqual(DetectorBackoff.ttl(base: 300_000_000, stableRuns: 99),
                                 DetectorBackoff.capNs)
    }

    /// A focus change resets the backoff — pinned here through the public contract the
    /// detectors expose (invalidate makes the next read re-scan; FieldVerdictCacheTests
    /// pins the verdict/value half of that contract, which the backoff must not alter).
    func testInvalidateLeavesTheDetectorsReadyForAFreshScan() {
        FocusedFieldDetector._testSetCached(true)
        FocusedFieldDetector.invalidate()
        XCTAssertFalse(FocusedFieldDetector._testCached)

        SecureFieldDetector._testSetCached(true)
        SecureFieldDetector.invalidate()
        XCTAssertTrue(SecureFieldDetector._testCached, "value kept…")
        XCTAssertFalse(SecureFieldDetector._testIsFresh, "…but stale, so it re-scans")
    }

    // MARK: - 3. engine toggles: cache AND disk stay in sync

    /// The getters now answer from memory, so a setter that forgot to persist would
    /// "work" all session and silently lose the setting on the next launch.
    func testEngineToggleSettersWriteBothTheCacheAndUserDefaults() {
        let s = AppState.shared
        // AppState.settingsSuiteName, NOT the literal: under XCTest AppState writes to
        // the isolated .tests suite (so test runs stop reconfiguring the dev machine's
        // real IME settings) — this test asserts round-trip into whatever suite
        // AppState actually uses.
        let store = UserDefaults(suiteName: AppState.settingsSuiteName) ?? .standard
        let toggles: [(name: String, key: String, get: () -> Bool, set: (Bool) -> Void)] = [
            ("autoRestore", "autoRestore", { s.autoRestore }, { s.autoRestore = $0 }),
            ("freeMarking", "freeMarking", { s.freeMarking }, { s.freeMarking = $0 }),
            ("modernOrthography", "modernOrthography",
             { s.modernOrthography }, { s.modernOrthography = $0 }),
            ("liveSpellCheck", "liveSpellCheck", { s.liveSpellCheck }, { s.liveSpellCheck = $0 }),
            ("simpleTelex", "simpleTelex", { s.simpleTelex }, { s.simpleTelex = $0 }),
            ("quickTelex", "quickTelex", { s.quickTelex }, { s.quickTelex = $0 }),
            ("vniMode", "vniMode", { s.vniMode }, { s.vniMode = $0 }),
            ("contextualEnglish", "contextualEnglish",
             { s.contextualEnglish }, { s.contextualEnglish = $0 }),
        ]
        for t in toggles {
            let saved = t.get()
            defer { t.set(saved) }
            for value in [!saved, saved] {
                t.set(value)
                XCTAssertEqual(t.get(), value, "\(t.name): in-memory cache must follow the setter")
                XCTAssertEqual(store.object(forKey: t.key) as? Bool, value,
                               "\(t.name): the setter must ALSO persist, or the choice dies on relaunch")
            }
        }
    }

    /// Settings live-toggling must reach the very next keystroke: the tap pushes these
    /// into the engine per key, so a write on main has to be visible to a subsequent
    /// read with no reload step in between.
    func testLiveToggleIsVisibleImmediately() {
        let s = AppState.shared
        let saved = s.vniMode
        defer { s.vniMode = saved }
        s.vniMode = !saved
        XCTAssertEqual(s.vniMode, !saved)
        s.vniMode = saved
        XCTAssertEqual(s.vniMode, saved)
    }
}

// The health probe is created from our PRIVATE event source, so it carries EMPTY
// modifier flags. Posting it into the session while the user holds ⌘ made the ⌘-Tab
// switcher read "⌘ released" and COMMIT the pointed-at app within one watchdog tick
// (field report 2026-07-30: holding ⌘ and tabbing "chỉ được 1 lúc là tự mở app").
// The gate is shared by postProbe() and the watchdog's miss-accounting; this pins
// both its polarity and the pairing rule (skipped ⇒ never counted as a miss).
final class ProbeChordGateTests: XCTestCase {

    func testChordHeldBlocksTheProbe() {
        XCTAssertFalse(SyntheticKeyboard.probeMayPost(secureInput: false, secureField: false, chordHeld: true))
    }

    func testSecureInputStillBlocksTheProbe() {
        XCTAssertFalse(SyntheticKeyboard.probeMayPost(secureInput: true, secureField: false, chordHeld: false))
        XCTAssertFalse(SyntheticKeyboard.probeMayPost(secureInput: false, secureField: true, chordHeld: false))
        // Issue #65 (After Effects): giữ Space = hand tool tạm thời; F20 probe rơi
        // vào giữa lúc giữ làm AE mất track keyUp của Space → kẹt hand tool.
        XCTAssertFalse(SyntheticKeyboard.probeMayPost(secureInput: false, secureField: false,
                                                      chordHeld: false, spaceHeld: true))
        XCTAssertTrue(SyntheticKeyboard.probeMayPost(secureInput: false, secureField: false,
                                                     chordHeld: false, spaceHeld: false))
    }

    func testQuietHandsAllowTheProbe() {
        XCTAssertTrue(SyntheticKeyboard.probeMayPost(secureInput: false, secureField: false, chordHeld: false))
    }

    /// ⇧ must NOT starve the probe: it is held for whole words in normal typing, and a
    /// probe blackout under it would blind the watchdog during the exact activity it
    /// exists to protect. Only ⌘/⌃/⌥ count as a chord.
    func testShiftAloneDoesNotCountAsChord() {
        // chordModifierHeld reads live session state, which a unit test cannot press
        // keys into — pin the FLAG SET instead, so a future edit adding .maskShift
        // (or dropping .maskCommand) fails here.
        XCTAssertEqual(SyntheticKeyboard.chordFlags,
                       CGEventFlags.maskCommand.union(.maskControl).union(.maskAlternate))
    }
}

// The test host runs the REAL AppState. Without suite isolation, every test that
// flips a toggle wrote into the dev machine's live com.viettelex.settings —
// `xcodebuild test` silently reconfigured the installed IME (2026-07-30:
// debugLogging kept turning itself off mid-debugging session).
final class SettingsSuiteIsolationTests: XCTestCase {
    func testXCTestHostUsesTheIsolatedSuite() {
        XCTAssertNotNil(ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"],
                        "this suite only proves isolation when actually run under XCTest")
        XCTAssertEqual(AppState.settingsSuiteName, "com.viettelex.settings.tests")
    }
}
