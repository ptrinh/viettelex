import XCTest
@testable import VietTelex

/// macOS 27.0.1 field bug (26/10/2026): a grant in "Device Control and Data Access"
/// did not reach the running IME until restart. Pins the poll's cadence (pure
/// TrustPollSchedule) and the controller's arm/boost/disarm wiring — untrusted only,
/// never reaching CGEvent.tapCreate in the test host.
final class TrustPollTests: XCTestCase {
    private let s = UInt64(1_000_000_000)

    override func tearDown() {
        Accessibility.testTrustOverride = nil
        TerminalTapController.shared._testDisarmTrustPoll()
        super.tearDown()
    }

    func testDisarmedMeansNoPolling() {
        let sched = TrustPollSchedule()
        XCTAssertNil(sched.nextInterval(nowNs: 0), "trusted / never armed: zero polling")
    }

    func testFastThenBacksOffAfterAMinute() {
        var sched = TrustPollSchedule()
        let t0: UInt64 = 1_000 * s
        XCTAssertTrue(sched.arm(nowNs: t0))
        XCTAssertEqual(sched.nextInterval(nowNs: t0), 2)
        XCTAssertEqual(sched.nextInterval(nowNs: t0 + 59 * s), 2)
        XCTAssertEqual(sched.nextInterval(nowNs: t0 + 60 * s), 10)
        XCTAssertEqual(sched.nextInterval(nowNs: t0 + 3_600 * s), 10, "stays slow, never stops while untrusted")
    }

    /// ensureRunning() re-arms on every app switch — that must not keep the fast
    /// cadence alive forever.
    func testRearmWhileArmedKeepsWindow() {
        var sched = TrustPollSchedule()
        let t0: UInt64 = 1_000 * s
        sched.arm(nowNs: t0)
        XCTAssertFalse(sched.arm(nowNs: t0 + 50 * s))
        XCTAssertEqual(sched.nextInterval(nowNs: t0 + 61 * s), 10)
    }

    func testBoostExtendsFastWindowAndArms() {
        var sched = TrustPollSchedule()
        let t0: UInt64 = 1_000 * s
        sched.boost(nowNs: t0)
        XCTAssertTrue(sched.isArmed)
        XCTAssertEqual(sched.nextInterval(nowNs: t0 + 119 * s), 2)
        XCTAssertEqual(sched.nextInterval(nowNs: t0 + 120 * s), 10)
        // Back in slow mode, a later boost brings the fast cadence back.
        sched.boost(nowNs: t0 + 300 * s)
        XCTAssertEqual(sched.nextInterval(nowNs: t0 + 301 * s), 2)
    }

    func testBoostNeverShortensWindow() {
        var sched = TrustPollSchedule()
        let t0: UInt64 = 1_000 * s
        sched.boost(nowNs: t0 + 100 * s)          // fast until t0+220
        sched.boost(nowNs: t0)                    // would end at t0+120 — ignored
        XCTAssertEqual(sched.fastUntilNs, t0 + 220 * s)
    }

    func testDisarmStopsAndRearmStartsFresh() {
        var sched = TrustPollSchedule()
        sched.arm(nowNs: 0)
        sched.disarm()
        XCTAssertNil(sched.nextInterval(nowNs: 1))
        XCTAssertTrue(sched.arm(nowNs: 500 * s))
        XCTAssertEqual(sched.nextInterval(nowNs: 501 * s), 2)
    }

    /// AX stuck false (no system notification) but the PostEvent preflight already
    /// says yes ⇒ the grant is in. Both false ⇒ still waiting.
    func testGrantDetectedFromEitherSignal() {
        XCTAssertTrue(TrustPollSchedule.grantDetected(axTrusted: false, canPostEvents: true))
        XCTAssertTrue(TrustPollSchedule.grantDetected(axTrusted: true, canPostEvents: false))
        XCTAssertTrue(TrustPollSchedule.grantDetected(axTrusted: true, canPostEvents: true))
        XCTAssertFalse(TrustPollSchedule.grantDetected(axTrusted: false, canPostEvents: false))
    }

    func testSystemSettingsDetection() {
        XCTAssertTrue(TrustPollSchedule.isSystemSettings("com.apple.systempreferences"))
        XCTAssertFalse(TrustPollSchedule.isSystemSettings("com.apple.finder"))
        XCTAssertFalse(TrustPollSchedule.isSystemSettings(nil))
    }

    // MARK: controller wiring (untrusted only)

    func testRecheckWhileUntrustedArmsPollAndObserver() {
        Accessibility.testTrustOverride = false
        let c = TerminalTapController.shared
        c.recheckTrust(reason: "test")
        XCTAssertTrue(c._testTrustPollIsRunning)
        XCTAssertTrue(c._testSettingsObserverInstalled, "watch System Settings only while untrusted")
        c._testDisarmTrustPoll()
        XCTAssertFalse(c._testTrustPollIsRunning)
        XCTAssertFalse(c._testSettingsObserverInstalled, "disarm must remove the observer (zero cost when trusted)")
        XCTAssertFalse(c._testTrustSchedule.isArmed)
    }

    func testBoostedRecheckPollsFast() {
        Accessibility.testTrustOverride = false
        let c = TerminalTapController.shared
        c.recheckTrust(reason: "test", boost: true)
        let now = DispatchTime.now().uptimeNanoseconds
        XCTAssertEqual(c._testTrustSchedule.nextInterval(nowNs: now + 100 * s), 2,
                       "after Open Settings the fast cadence lasts ~2 minutes")
        XCTAssertTrue(c._testTrustPollIsRunning)
    }
}
