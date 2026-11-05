import XCTest
@testable import TelexCore

// Cost of the "Tự sửa từ phía trước" DECISION on the word-boundary path (engine only).
// The macOS app runs it at every boundary whenever "Quyết định theo ngữ cảnh" is on, so it
// must stay noise next to the screen I/O (IPC/AX reads are 100µs–50ms; this is µs).
// Release-only like KeystrokePerfTests: `swift test -c release --filter RetroBoundaryPerf`.
// Ceiling is generous (a regression guard, not a calibrated gate); the printed numbers
// are what matters — compare retro=on vs retro=off.
final class RetroBoundaryPerfTests: XCTestCase {
    /// Upper bound on the EXTRA engine cost per boundary with the retro decision on.
    static let ceilingExtraMicros = 5.0

    override func setUpWithError() throws {
        #if DEBUG
        throw XCTSkip("perf is release-only; run: swift test -c release --filter RetroBoundaryPerf")
        #endif
    }

    private func engine(retro: Bool, frequency: Bool = false) -> TelexEngine {
        var e = TelexEngine()
        e.freeMarking = true
        e.liveSpellCheck = true
        e.eagerEnglishRestore = true
        e.teencode = false
        e.contextualEnglish = true
        e.collisionPrefersVietnamese = true
        e.retroactiveEnglish = retro
        e.englishByFrequency = frequency
        return e
    }

    /// µs per boundary (commit + noteBoundaryCharacter + take) over mixed text that triggers
    /// corrections ("His car is very fast") and text that does not (plain Vietnamese).
    private func boundaryMicros(retro: Bool, frequency: Bool = false) -> (micros: Double, corrections: Int) {
        let text = "His car is very fast. Toi di hocj ve muon. of course we can do this "
                 + "Is this the best way? cai nay la cua toi nhes. his huwngr quas. His His. "
        var boundaries = 0, corrections = 0
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            for _ in 0..<2000 {
                var e = engine(retro: retro, frequency: frequency)
                for ch in text {
                    if ch.isASCII, ch.isLetter {
                        _ = e.feed(ch)
                    } else {
                        _ = e.commitText(autoRestore: true)
                        e.noteBoundaryCharacter(ch)
                        if e.takeRetroCorrection() != nil { corrections += 1 }
                        boundaries += 1
                    }
                }
            }
        }
        let ns = Double(elapsed.components.seconds) * 1e9 + Double(elapsed.components.attoseconds) / 1e9
        return (ns / Double(boundaries) / 1000.0, corrections)
    }

    func testRetroDecisionCostPerBoundary() {
        var off = Double.greatestFiniteMagnitude, on = Double.greatestFiniteMagnitude, fixes = 0
        for _ in 0..<5 {
            off = min(off, boundaryMicros(retro: false).micros)
            let r = boundaryMicros(retro: true)
            on = min(on, r.micros); fixes = r.corrections
        }
        print(String(format: "RetroBoundaryPerf: us/boundary off=%.3f on=%.3f extra=%.3f corrections=%d",
                     off, on, on - off, fixes))
        XCTAssertGreaterThan(fixes, 0, "workload must actually trigger corrections")
        XCTAssertLessThanOrEqual(on - off, Self.ceilingExtraMicros)
    }

    /// "Từ trùng theo tần suất" (englishByFrequency). TẮT = đường chốt chỉ thêm các phép thử
    /// `if englishByFrequency` (không tra bảng, không dựng chuỗi) — so số "off" ở đây với số của
    /// testRetroDecisionCostPerBoundary trên commit trước cờ (docs/REGRESSION.md ghi cả hai).
    /// BẬT = vài tra nhị phân trên StaticString ở ranh giới, không cấp phát.
    func testFrequencyRuleCostPerBoundary() {
        var off = Double.greatestFiniteMagnitude
        var on = Double.greatestFiniteMagnitude, fixesOff = 0, fixesOn = 0
        for _ in 0..<5 {
            let a = boundaryMicros(retro: true, frequency: false)
            off = min(off, a.micros); fixesOff = a.corrections
            let b = boundaryMicros(retro: true, frequency: true)
            on = min(on, b.micros); fixesOn = b.corrections
        }
        print(String(format: "FrequencyBoundaryPerf: us/boundary freqOff=%.3f freqOn=%.3f extra=%.3f "
                     + "corrections off=%d on=%d", off, on, on - off, fixesOff, fixesOn))
        XCTAssertNotEqual(fixesOn, fixesOff, "workload must trigger flips / frequency restores")
        XCTAssertLessThanOrEqual(on - off, Self.ceilingExtraMicros)
    }
}
