import XCTest
@testable import VietTelex

/// Issue #118 (08/10/2026): "không gõ được trên toàn máy" khi chạy OpenClaw. A client
/// that makes key handling wait must be demoted to passthrough so it can never hold
/// every other app's keys hostage (IMK handle() runs on MAIN, shared by all apps).
final class ClientStallBreakerTests: XCTestCase {
    private let ms: UInt64 = 1_000_000
    private let s: UInt64 = 1_000_000_000

    // MARK: pure policy

    func testFastKeysNeverDegrade() {
        var st = ClientStallState()
        XCTAssertFalse(ClientStallState.isStall(durationNs: 3 * ms))
        XCTAssertFalse(ClientStallState.isStall(durationNs: 200 * ms))   // worst legit AX path
        XCTAssertTrue(ClientStallState.isStall(durationNs: 251 * ms))
        XCTAssertFalse(st.isDegraded(id: "ai.openclaw.mac", nowNs: 1 * s))
    }

    func testThreeStallsInWindowDegradeThenCooldownRestores() {
        var st = ClientStallState()
        let id = "ai.openclaw.mac"
        XCTAssertFalse(st.recordStall(id: id, path: .imk, durationNs: 1200 * ms, nowNs: 10 * s, enabled: true))
        XCTAssertFalse(st.recordStall(id: id, path: .imk, durationNs: 1200 * ms, nowNs: 12 * s, enabled: true))
        XCTAssertFalse(st.isDegraded(id: id, nowNs: 12 * s))
        XCTAssertTrue(st.recordStall(id: id, path: .imk, durationNs: 1200 * ms, nowNs: 13 * s, enabled: true))
        XCTAssertTrue(st.isDegraded(id: id, nowNs: 13 * s))
        // Already degraded: further stalls are not a new transition.
        XCTAssertFalse(st.recordStall(id: id, path: .tap, durationNs: 900 * ms, nowNs: 14 * s, enabled: true))
        // Other apps unaffected.
        XCTAssertFalse(st.isDegraded(id: "com.apple.TextEdit", nowNs: 14 * s))
        // Cooldown elapses → composing again.
        XCTAssertTrue(st.isDegraded(id: id, nowNs: 13 * s + ClientStallState.cooldownNs - 1))
        XCTAssertFalse(st.isDegraded(id: id, nowNs: 13 * s + ClientStallState.cooldownNs))
        XCTAssertTrue(st.expire(nowNs: 13 * s + ClientStallState.cooldownNs))
    }

    func testSpreadOutStallsDoNotDegrade() {
        var st = ClientStallState()
        let id = "com.example.slow"
        for i in 0..<6 {   // one slow key every 6s — a GC pause, not a hung client
            XCTAssertFalse(st.recordStall(id: id, path: .imk, durationNs: 300 * ms,
                                          nowNs: UInt64(i) * 6 * s, enabled: true))
        }
        XCTAssertFalse(st.isDegraded(id: id, nowNs: 40 * s))
    }

    func testKillSwitchRecordsButNeverDegrades() {
        var st = ClientStallState()
        for i in 0..<5 {
            XCTAssertFalse(st.recordStall(id: "x", path: .imk, durationNs: 2 * s,
                                          nowNs: UInt64(i) * s, enabled: false))
        }
        XCTAssertFalse(st.isDegraded(id: "x", nowNs: 5 * s))
        XCTAssertEqual(st.recent.count, 5)   // evidence still kept for the debug report
    }

    func testRecentRingIsBounded() {
        var st = ClientStallState()
        for i in 0..<20 {
            _ = st.recordStall(id: "a\(i)", path: .tap, durationNs: 300 * ms, nowNs: UInt64(i) * s, enabled: true)
        }
        XCTAssertEqual(st.recent.count, ClientStallState.maxRecent)
        XCTAssertEqual(st.recent.last?.id, "a19")
        XCTAssertLessThanOrEqual(st.strikesByID.count, 11)   // expired strikes pruned
    }

    // MARK: key path with a fake client that blocks (hung AX / IMK XPC target)

    /// Mirrors both production key paths: gate first (degraded → passthrough without
    /// touching the client), otherwise call the client and charge the time.
    private func handleKey(_ b: ClientStallBreaker, id: String, client: () -> Void) -> Bool {
        if b.isDegraded(id) { return false }   // passthrough
        let t0 = DispatchTime.now().uptimeNanoseconds
        client()
        b.noteKeyHandled(id, path: .imk, startNs: t0)
        return true
    }

    func testHungClientIsDemotedAndLaterKeysReturnPromptly() {
        let b = ClientStallBreaker()
        b.enabledOverride = true
        var calls = 0
        let hungClient = { calls += 1; Thread.sleep(forTimeInterval: 0.27) }   // > 250ms per call
        for _ in 0..<ClientStallState.strikes {
            XCTAssertTrue(handleKey(b, id: "ai.openclaw.mac", client: hungClient))
        }
        XCTAssertTrue(b.isDegraded("ai.openclaw.mac"))
        // Next 50 keys: never reach the client, each returns in well under a millisecond.
        let t0 = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<50 { XCTAssertFalse(handleKey(b, id: "ai.openclaw.mac", client: hungClient)) }
        let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6
        XCTAssertEqual(calls, ClientStallState.strikes)
        XCTAssertLessThan(elapsedMs, 50)
        // A healthy app keeps composing.
        XCTAssertTrue(handleKey(b, id: "com.apple.TextEdit", client: {}))
        XCTAssertTrue(b.reportLine().contains("passthrough now: ai.openclaw.mac"))
    }

    func testTapTimeoutsCountAsStrikes() {
        let b = ClientStallBreaker()
        b.enabledOverride = true
        for _ in 0..<ClientStallState.strikes { b.noteTapTimeout("com.example.term") }
        XCTAssertTrue(b.isDegraded("com.example.term"))
        XCTAssertFalse(b.isDegraded(nil))
        XCTAssertTrue(b.reportLine().contains("tap-timeout"))
    }

    func testFastKeysAreFreeAndNeverCharged() {
        let b = ClientStallBreaker()
        b.enabledOverride = true
        var looked = false
        for _ in 0..<1000 {
            let t0 = DispatchTime.now().uptimeNanoseconds
            b.noteKeyHandled({ looked = true; return "x" }(), path: .tap, startNs: t0)
        }
        XCTAssertFalse(looked, "id must only be resolved for a slow key")
        XCTAssertTrue(b.reportLine().hasPrefix("client stalls: (none)"))
    }
}
