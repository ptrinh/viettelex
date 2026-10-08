import XCTest
@testable import VietTelex

/// Issue #118: OpenClaw types one key per ~1 ms (keycode 0 + unicode string). Those
/// bursts must pass through verbatim — composing them mangled the agent's text and
/// kept MAIN busy with an endless retype loop — while no human rhythm ever trips.
final class MachineTypingDetectorTests: XCTestCase {
    private let ms: UInt64 = 1_000_000
    private let t0: UInt64 = 5_000_000_000

    /// Feed keys whose event timestamp and arrival time advance by the same gaps.
    private func feed(_ d: inout MachineTypingDetector, gaps: [UInt64], start: UInt64,
                      isRepeat: Bool = false) -> [(machine: Bool, began: Bool)] {
        var t = start
        var out: [(machine: Bool, began: Bool)] = []
        for g in gaps {
            t += g
            out.append(d.observe(eventNs: t, arrivalNs: t, isRepeat: isRepeat))
        }
        return out
    }

    func testHumanTypingNeverTrips() {
        var d = MachineTypingDetector()
        // Fast typist with rollover: mostly 40–90 ms, a few near-simultaneous pairs.
        let gaps: [UInt64] = [0, 60, 45, 8, 70, 50, 6, 90, 40, 9, 55, 48, 65, 7, 80].map { $0 * ms }
        let r = feed(&d, gaps: gaps, start: t0)
        XCTAssertFalse(r.contains { $0.machine })
    }

    func testAgentBurstTripsOnceAndStaysActive() {
        var d = MachineTypingDetector()
        let r = feed(&d, gaps: Array(repeating: 1 * ms, count: 40), start: t0)
        // First key has no predecessor; the next 6 fast gaps trip on key index 6.
        XCTAssertEqual(r.firstIndex { $0.machine }, MachineTypingDetector.tripRun)
        XCTAssertEqual(r.filter { $0.began }.count, 1)
        XCTAssertTrue(r.suffix(from: MachineTypingDetector.tripRun).allSatisfy { $0.machine })
    }

    func testShortRolloverBurstDoesNotTrip() {
        var d = MachineTypingDetector()
        let gaps: [UInt64] = [0, 3, 3, 3, 3, 60, 3, 3, 3, 3, 3].map { $0 * ms }   // 5 fast max
        XCTAssertFalse(feed(&d, gaps: gaps, start: t0).contains { $0.machine })
    }

    func testPauseReleasesSoHumanTypingComposesAgain() {
        var d = MachineTypingDetector()
        _ = feed(&d, gaps: Array(repeating: 1 * ms, count: 20), start: t0)
        XCTAssertTrue(d.isActive)
        // A hiccup shorter than the release gap keeps the burst (agent yields to its UI).
        var t = t0 + 20 * ms + 100 * ms
        XCTAssertTrue(d.observe(eventNs: t, arrivalNs: t, isRepeat: false).machine)
        // Human resumes after a real pause.
        t += MachineTypingDetector.releaseGapNs
        XCTAssertFalse(d.observe(eventNs: t, arrivalNs: t, isRepeat: false).machine)
        XCTAssertFalse(d.isActive)
    }

    /// MAIN was busy, then the queue flushed: human keys ARRIVE 0.1 ms apart, but their
    /// own timestamps keep the human rhythm — must not read as machine typing.
    func testQueuedHumanKeysFlushedTogetherDoNotTrip() {
        var d = MachineTypingDetector()
        var arrive = t0
        var stamp = t0
        for _ in 0..<15 {
            arrive += 100_000
            stamp += 70 * ms
            XCTAssertFalse(d.observe(eventNs: stamp, arrivalNs: arrive, isRepeat: false).machine)
        }
    }

    /// A source that leaves timestamps at 0 (or a clock that runs backwards): the event
    /// clock is ignored and arrival alone decides — still trips on a real burst, still
    /// quiet for human spacing.
    func testUnknownEventTimestampFallsBackToArrival() {
        var d = MachineTypingDetector()
        var t = t0
        var hits = 0
        for _ in 0..<12 { t += 1 * ms; if d.observe(eventNs: 0, arrivalNs: t, isRepeat: false).machine { hits += 1 } }
        XCTAssertGreaterThan(hits, 0)

        var h = MachineTypingDetector()
        t = t0
        for i in 0..<12 {
            t += 60 * ms
            let backwards: UInt64 = i % 2 == 0 ? 10 : 5   // non-monotonic stamps
            XCTAssertFalse(h.observe(eventNs: backwards, arrivalNs: t, isRepeat: false).machine)
        }
    }

    /// Holding a key with a very fast KeyRepeat setting is a human: never trips, and a
    /// repeat breaks any run in progress.
    func testAutorepeatNeverTripsAndBreaksRun() {
        var d = MachineTypingDetector()
        XCTAssertFalse(feed(&d, gaps: Array(repeating: 10 * ms, count: 30), start: t0, isRepeat: true)
            .contains { $0.machine })
        var e = MachineTypingDetector()
        var t = t0
        for _ in 0..<5 { t += 1 * ms; _ = e.observe(eventNs: t, arrivalNs: t, isRepeat: false) }
        t += 1 * ms; _ = e.observe(eventNs: t, arrivalNs: t, isRepeat: true)
        XCTAssertEqual(e.run, 0)
        t += 1 * ms
        XCTAssertFalse(e.observe(eventNs: t, arrivalNs: t, isRepeat: false).machine)
    }

    func testReportLineRecordsBurstsAlways() {
        MachineTypingLog._testReset()
        defer { MachineTypingLog._testReset() }
        XCTAssertEqual(MachineTypingLog.reportLine(), "machine typing: (none)")
        MachineTypingLog.noteBurst("com.google.Chrome", path: "tap", nowNs: 10_000_000_000)
        MachineTypingLog.noteBurst("ai.openclaw.mac", path: "imk", nowNs: 20_000_000_000)
        XCTAssertEqual(MachineTypingLog.reportLine(nowNs: 25_000_000_000),
                       "machine typing: 2 burst(s), last ai.openclaw.mac imk 5s ago")
    }

    func testCUAPacedTypingAt16msIsNotFlagged() {
        // CUA posts down/up 8 ms apart (16 ms per key): fast, but slow enough that we
        // leave it alone rather than risk a false positive on a human burst.
        var d = MachineTypingDetector()
        XCTAssertFalse(feed(&d, gaps: Array(repeating: 16 * ms, count: 30), start: t0).contains { $0.machine })
    }
}
