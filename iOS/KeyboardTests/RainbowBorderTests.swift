// Viền cầu vồng (theme Gaming RGB): dải màu + đồng hồ chung Android (số tham chiếu), MỘT lớp gradient che bằng
// viền phím (không animation từng phím), chỉ chạy khi đang gõ — nghỉ thì giảm tốc + mờ dần rồi 0 animation; theme
// khác ⇒ không có view. Phủ kín mọi độ lệch / bề ngang (bug "tắt đèn từ phía phải qua").
// Bộ chậm (VT_SLOW_TESTS=1): đo chi phí main thread mỗi phím + khi nghỉ, in "RGB-COST".
import XCTest
import UIKit

final class RainbowBorderTests: XCTestCase {
    private var savedPaywall = false
    private var savedProvider: UserDefaults?
    private let suite = "vt-rgb-tests"

    override func setUp() {
        super.setUp()
        savedPaywall = PlusGate.paywallEnabled
        PlusGate.paywallEnabled = false
        savedProvider = UserDefaultsProvider.shared
    }

    override func tearDown() {
        PlusGate.paywallEnabled = savedPaywall
        UserDefaultsProvider.shared = savedProvider
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    // MARK: thuần — chung Android (RainbowBorderTests.kt)

    func testStopsAndOffsetParity() {
        XCTAssertEqual(RainbowBorder.hues, [0xFF3B30, 0xFF9500, 0xFFCC00, 0x34C759, 0x00C7BE, 0x007AFF, 0xAF52DE, 0xFF3B30])
        let st = RainbowBorder.stops()
        XCTAssertEqual(st.count, 15)
        XCTAssertEqual(st.first?.location, 0); XCTAssertEqual(st.last?.location, 1)
        XCTAssertEqual(st[7].color, 0xFF3B30); XCTAssertEqual(st[7].location, 0.5, accuracy: 1e-12, "chu kỳ hai bắt đầu giữa dải")
        XCTAssertEqual(st[3].location, 3.0 / 14, accuracy: 1e-12)
        for i in 1..<st.count { XCTAssertGreaterThan(st[i].location, st[i - 1].location) }
        // Nửa sau = nửa đầu dời 0.5 ⇒ dịch đúng một bề ngang (nửa dải) là liền mạch.
        for i in 0..<7 { XCTAssertEqual(st[i].color, st[i + 7].color); XCTAssertEqual(st[i].location + 0.5, st[i + 7].location, accuracy: 1e-12) }
        XCTAssertEqual(RainbowBorder.offset(from: 0.25, elapsed: 1), 0.5, accuracy: 1e-12)
        XCTAssertEqual(RainbowBorder.offset(from: 0.9, elapsed: 0.8), 0.1, accuracy: 1e-12)
        XCTAssertEqual(RainbowBorder.offset(from: 0, elapsed: RainbowBorder.period * 3), 0, accuracy: 1e-12)
        XCTAssertEqual(RainbowBorder.period, 4); XCTAssertEqual(RainbowBorder.idleAfter, 1.2); XCTAssertEqual(RainbowBorder.lineWidth, 1.5)
    }

    func testClockRunsOnlyWhileTyping() {
        var c = RainbowClock()
        XCTAssertFalse(c.running)
        XCTAssertTrue(c.poke(at: 10), "phím đầu ⇒ chạy")
        XCTAssertFalse(c.poke(at: 10.3), "đang chạy ⇒ chỉ ghi giờ")
        XCTAssertEqual(c.idleRemaining(at: 11), 0.5, accuracy: 1e-9)
        XCTAssertLessThanOrEqual(c.idleRemaining(at: 11.6), 0)
        c.stop()
        XCTAssertFalse(c.running)
        XCTAssertTrue(c.poke(at: 20))
    }

    // MARK: phủ kín — bug "tắt đèn từ phía phải qua" (Phil 19/10/2026, iPhone thật)
    //
    // Dải rộng 2W (W = bề ngang, một chu kỳ màu = W) đặt ở x = −offset·W. Bản cũ chạy vòng lặp −phase·W → −(phase+1)·W
    // sau lần nghỉ đầu (phase > 0) ⇒ offset tới phase+1 > 1 ⇒ mép phải dải (1−phase)·W < W: viền bên phải tối dần.

    private func assertCovers(_ x: Double, _ msg: @autoclosure () -> String, line: UInt = #line) {
        let c = RainbowBorder.coverage(offset: x)
        XCTAssertLessThanOrEqual(c.lowerBound, 1e-9, msg(), line: line)
        XCTAssertGreaterThanOrEqual(c.upperBound, 1 - 1e-9, msg(), line: line)
    }

    func testCoverageAtAnyOffsetOverManyCycles() {
        XCTAssertGreaterThanOrEqual(RainbowBorder.stripPeriods, 2, "dải ≥ W + một chu kỳ")
        // Bản cũ: offset = phase + elapsed/period KHÔNG lấy dư — phase 0,5 sau 3 s ⇒ 1,25 ⇒ phải tối 1/4.
        XCTAssertLessThan(RainbowBorder.coverage(offset: 0.5 + 3 / RainbowBorder.period).upperBound, 1, "công thức cũ hở mép phải")
        for i in 0...2000 { assertCovers(RainbowBorder.wrap(Double(i) * 0.0173 - 7), "wrap \(i)") }
        XCTAssertEqual(RainbowBorder.wrap(-0.25), 0.75, accuracy: 1e-12)
        XCTAssertEqual(RainbowBorder.wrap(3), 0)
        // Phiên gõ dài: gõ / nghỉ / gõ dở lúc đang giảm tốc… qua hàng chục chu kỳ — mọi thời điểm đều phủ kín.
        var m = RainbowMotion()
        var t = 0.0
        let pattern: [(typing: Double, idle: Double)] = [(3.1, 1.7), (0.3, 0.4), (7.9, 2.5), (1.0, 0.05), (13.3, 0.9), (0.2, 3)]
        for round in 0..<20 {
            for p in pattern {
                m = m.resumed(at: t)
                for k in 0..<Int(p.typing * 50) { assertCovers(m.offset(at: t + Double(k) / 50), "gõ r\(round)") }
                t += p.typing
                m = m.settled(at: t)
                for k in 0..<Int(p.idle * 50) { assertCovers(m.offset(at: t + Double(k) / 50), "nghỉ r\(round)") }
                t += p.idle
            }
        }
        XCTAssertGreaterThan(t / RainbowBorder.period, 50, "qua nhiều chu kỳ")
    }

    func testMotionDeceleratesAndAcceleratesSmoothly() {
        let v = RainbowMotion.fullSpeed
        let run = RainbowMotion.rest(at: 0.3).resumed(at: 10)
        XCTAssertEqual(run.ramp, RainbowBorder.accelTime, accuracy: 1e-12)
        XCTAssertEqual(run.velocity(at: 10), 0); XCTAssertEqual(run.velocity(at: 10.2), v / 2, accuracy: 1e-12)
        XCTAssertEqual(run.velocity(at: 20), v)
        let stop = run.settled(at: 20)
        XCTAssertEqual(stop.ramp, RainbowBorder.decelTime, accuracy: 1e-12, "dừng dần ~1 s")
        XCTAssertEqual(stop.velocity(at: 20), v, accuracy: 1e-12, "không giật: tốc độ liền")
        XCTAssertEqual(stop.velocity(at: 20.5), v / 2, accuracy: 1e-12)
        XCTAssertEqual(stop.velocity(at: 21), 0)
        XCTAssertEqual(stop.offset(at: 21), stop.offset(at: 99), accuracy: 1e-12, "đứng yên sau khi dừng")
        XCTAssertEqual(stop.offset(at: 20), run.offset(at: 20), accuracy: 1e-12, "vị trí liền")
        // Gõ lại giữa lúc giảm tốc: tăng tốc từ tốc độ đang có (ramp ngắn hơn), vị trí + tốc độ liền.
        let again = stop.resumed(at: 20.5)
        XCTAssertEqual(again.ramp, RainbowBorder.accelTime / 2, accuracy: 1e-12)
        XCTAssertEqual(again.velocity(at: 20.5), v / 2, accuracy: 1e-12)
        XCTAssertEqual(again.offset(at: 20.5), stop.offset(at: 20.5), accuracy: 1e-12)
        // Đơn điệu (không bao giờ chạy lùi).
        var prev = stop.travelled(at: 20)
        for k in 1...200 { let u = stop.travelled(at: 20 + Double(k) * 0.01); XCTAssertGreaterThanOrEqual(u, prev); prev = u }
    }

    func testFadeEasesToRestGlowAndBack() {
        XCTAssertEqual(RainbowBorder.restAlpha, 0.58); XCTAssertEqual(RainbowBorder.fadeOutTime, 1); XCTAssertEqual(RainbowBorder.fadeInTime, 0.2)
        let rest = RainbowFade()
        XCTAssertEqual(rest.alpha(at: 0), RainbowBorder.restAlpha, "mới hiện: ánh nghỉ")
        let on = rest.toward(1, at: 5, duration: RainbowBorder.fadeInTime)
        XCTAssertEqual(on.alpha(at: 5), RainbowBorder.restAlpha, accuracy: 1e-12)
        XCTAssertEqual(on.alpha(at: 5.2), 1)
        let off = on.toward(RainbowBorder.restAlpha, at: 9, duration: RainbowBorder.fadeOutTime)
        XCTAssertEqual(off.alpha(at: 9), 1)
        XCTAssertEqual(off.alpha(at: 9.5), (1 + RainbowBorder.restAlpha) / 2, accuracy: 1e-12, "mờ dần, không cắt")
        XCTAssertEqual(off.alpha(at: 10), RainbowBorder.restAlpha)
        var prev = 1.0
        for k in 0...100 { let a = off.alpha(at: 9 + Double(k) * 0.01); XCTAssertLessThanOrEqual(a, prev + 1e-12); prev = a }
        // Gõ lại giữa lúc mờ: sáng lên TỪ độ sáng đang hiện.
        let back = off.toward(1, at: 9.5, duration: RainbowBorder.fadeInTime)
        XCTAssertEqual(back.from, off.alpha(at: 9.5), accuracy: 1e-12)
    }

    /// Keyframe tăng/giảm tốc: mọi giá trị đã lấy dư ∈ [0, 1] (phủ kín), keyTimes không giảm, bước qua biên chu kỳ là
    /// cặp 1 → 0 cùng keyTime; khớp đường chuyển động.
    func testKeyframesStayWrappedAndFollowMotion() {
        for x in stride(from: 0.0, to: 1, by: 0.037) {
            for m in [RainbowMotion.rest(at: x).resumed(at: 3), RainbowMotion.rest(at: x).resumed(at: 3).settled(at: 50)] {
                let t = m.t0, end = m.rampEnd
                let (vals, times) = RainbowBorder.keyframes(m, from: t, to: end)
                XCTAssertEqual(vals.count, times.count)
                XCTAssertEqual(times.first, 0); XCTAssertEqual(times.last ?? 0, 1, accuracy: 1e-12)
                for v in vals { XCTAssertTrue((0...1).contains(v), "x=\(x) v=\(v)"); assertCovers(v, "keyframe x=\(x)") }
                for i in 1..<times.count { XCTAssertGreaterThanOrEqual(times[i], times[i - 1]) }
                for i in 1..<vals.count where times[i] == times[i - 1] { XCTAssertEqual(vals[i - 1], 1); XCTAssertEqual(vals[i], 0) }
                XCTAssertEqual(vals.last ?? -1, m.offset(at: end), accuracy: 1e-9)
                let wraps = zip(vals, vals.dropFirst()).filter { $0 == 1 && $1 == 0 }.count
                XCTAssertEqual(wraps, Int(m.travelled(at: end).rounded(.down) - m.travelled(at: t).rounded(.down)), "x=\(x)")
            }
        }
    }

    // MARK: bàn phím thật

    @MainActor private func keyboard(_ theme: KeyboardTheme, in win: UIWindow? = nil) -> KeyboardView {
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        d.set(theme.rawValue, forKey: ThemeSettings.themeKey)
        UserDefaultsProvider.shared = d
        let kb = KeyboardView(needsGlobe: false, inputController: nil) { _ in }
        let host: UIView = win ?? UIView(frame: CGRect(x: 0, y: 0, width: 402, height: 400))
        host.addSubview(kb)
        kb.frame = CGRect(x: 0, y: 0, width: 402, height: 290)
        kb.applyAppearance(.dark, style: .dark)
        kb.setNeedsLayout(); kb.layoutIfNeeded()
        return kb
    }

    @MainActor func testOnlyRgbThemeHasOverlayAndItIsOneMaskedLayer() throws {
        for t in KeyboardTheme.allCases where t != .rgb && t != .ai {
            XCTAssertNil(keyboard(t).rainbow, "\(t): theme khác ⇒ không có lớp (0 chi phí)")
        }
        // AI ("borderFx":"aurora"): cùng lớp mặt nạ viền nhưng gradient TĨNH (AIThemeTests).
        XCTAssertEqual(keyboard(.ai).rainbow?.isAurora, true)
        XCTAssertNotNil(keyboard(.ai).debugAuroraBand, "dải cực quang mép trên")
        XCTAssertNil(keyboard(.rgb).debugAuroraBand)
        let kb = keyboard(.rgb)
        let v = try XCTUnwrap(kb.rainbow)
        XCTAssertFalse(v.isUserInteractionEnabled)
        XCTAssertNil(v.hitTest(CGPoint(x: 50, y: 150), with: nil), "không nhận chạm")
        XCTAssertEqual(v.layer.sublayers?.count, 1, "MỘT lớp gradient")
        XCTAssertEqual(v.debugStrip.colors?.count, 15)
        // Mặt nạ = viền mọi phím đang hiện: bao trùm khung phím chữ q…p.
        let path = try XCTUnwrap(v.debugMaskPath)
        let q = try XCTUnwrap(kb.debugLetterFrame("q")), p = try XCTUnwrap(kb.debugLetterFrame("p"))
        let box = path.boundingBoxOfPath
        XCTAssertLessThanOrEqual(box.minX, kb.convert(q, to: v).minX + 1)
        XCTAssertGreaterThanOrEqual(box.maxX, kb.convert(p, to: v).maxX - 1)
        XCTAssertEqual(v.debugAnimationCount, 0, "mới hiện: cầu vồng tĩnh, không animation")
        XCTAssertFalse(v.debugRunning)
    }

    /// Phiên thật trên CÙNG một view: gõ ⇒ tăng tốc + sáng lên (GPU), gõ tiếp không thêm gì; nghỉ ⇒ giảm tốc + mờ dần
    /// CÙNG LÚC (không cắt), xong ⇒ 0 animation ở ánh nghỉ; gõ lại ⇒ sáng 100% + chạy tiếp từ chỗ đứng.
    @MainActor func testIdleDeceleratesAndFadesThenZeroAnimations() throws {
        let win = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 400))
        win.isHidden = false
        defer { win.isHidden = true }
        let kb = keyboard(.rgb, in: win)
        let v = try XCTUnwrap(kb.rainbow)
        v.debugSetIdle(0.6)                                 // > accelTime: nghỉ khi đã chạy đầy tốc
        XCTAssertEqual(v.debugStrip.opacity, Float(RainbowBorder.restAlpha), "mới hiện: ánh nghỉ")
        let f = try XCTUnwrap(kb.debugLetterFrame("a"))
        func tap() { kb.benchTap(at: CGPoint(x: f.midX, y: f.midY), time: CACurrentMediaTime()) }
        tap()
        XCTAssertTrue(v.debugRunning)
        XCTAssertEqual(v.debugAnimationKeys, ["rgb.move", "rgb.loop", "rgb.fade"], "tăng tốc → vòng lặp, sáng lên")
        XCTAssertEqual(v.debugStrip.opacity, 1)
        for _ in 0..<5 { tap() }
        XCTAssertEqual(v.debugAnimationKeys.count, 3, "gõ tiếp không thêm animation")
        KeyboardBenchTests.spin(0.3)
        XCTAssertTrue(v.debugRunning, "chưa đủ thời gian nghỉ")
        KeyboardBenchTests.spin(0.45)
        // Đang dừng dần: giảm tốc (keyframe) + mờ, không còn vòng lặp.
        XCTAssertFalse(v.debugRunning)
        XCTAssertEqual(v.debugAnimationKeys, ["rgb.move", "rgb.fade"], "giảm tốc + mờ dần cùng lúc")
        XCTAssertEqual(v.debugStrip.opacity, Float(RainbowBorder.restAlpha), "model = ánh nghỉ")
        XCTAssertEqual(v.debugMotion.v1, 0)
        XCTAssertEqual(v.debugMotion.ramp, RainbowBorder.decelTime, accuracy: 0.05)
        XCTAssertEqual(v.debugFade.from, 1, accuracy: 1e-9, "mờ từ 100%")
        XCTAssertEqual(v.debugFade.duration, RainbowBorder.fadeOutTime)
        KeyboardBenchTests.spin(1.2)
        XCTAssertEqual(v.debugAnimationCount, 0, "dừng xong ⇒ 0 animation")
        XCTAssertEqual(v.debugStrip.opacity, Float(RainbowBorder.restAlpha))
        let rest = v.phase
        XCTAssertGreaterThan(rest, 0, "đứng yên ở vị trí đã trượt tới (không giật về đầu)")
        KeyboardBenchTests.spin(0.2)
        XCTAssertEqual(v.phase, rest, accuracy: 1e-12, "nghỉ = đứng yên")
        // Gõ lại: sáng 100% (~0,2 s) + tăng tốc từ đúng chỗ đứng.
        tap()
        XCTAssertEqual(v.debugMotion.x0, rest, accuracy: 1e-9)
        XCTAssertEqual(v.debugFade.to, 1); XCTAssertEqual(v.debugFade.duration, RainbowBorder.fadeInTime)
        XCTAssertEqual(v.debugStrip.opacity, 1)
        XCTAssertTrue(v.debugAnimationKeys.contains("rgb.loop"))
        // Gõ lại GIỮA lúc đang dừng dần: tốc độ + độ sáng nối tiếp (không giật).
        KeyboardBenchTests.spin(0.45)
        v.debugSettleNow()
        KeyboardBenchTests.spin(0.3)
        let mid = v.debugMotion, now = CACurrentMediaTime()
        let alphaMid = v.debugFade.alpha(at: now)
        tap()
        XCTAssertEqual(v.debugMotion.v0, mid.velocity(at: now), accuracy: RainbowMotion.fullSpeed * 0.1)
        XCTAssertLessThan(v.debugFade.from, 1); XCTAssertEqual(v.debugFade.from, alphaMid, accuracy: 0.05)
        // Ẩn bàn phím giữa lúc gõ ⇒ dừng ngay, 0 animation.
        kb.removeFromSuperview()
        XCTAssertEqual(v.debugAnimationCount, 0)
        XCTAssertFalse(v.debugRunning)
    }

    /// Phủ kín trên view thật: mọi bề ngang (iPhone dọc / xoay ngang / iPad) × mọi chỗ đứng, cả khi đang chạy, đang
    /// dừng dần và khi xoay giữa chừng: mọi giá trị translation.x mà animation có thể nhận ∈ [−W, 0] (dải 2W phủ [0, W]).
    @MainActor func testStripCoversKeyboardAtEveryPhaseAndWidth() throws {
        let win = UIWindow(frame: CGRect(x: 0, y: 0, width: 1366, height: 1024))
        win.isHidden = false
        defer { win.isHidden = true }
        let kb = keyboard(.rgb, in: win)
        let v = try XCTUnwrap(kb.rainbow)
        func check(_ what: String, line: UInt = #line) {
            let w = Double(v.bounds.width)
            XCTAssertGreaterThan(w, 0)
            XCTAssertEqual(Double(v.debugStrip.bounds.width), w * RainbowBorder.stripPeriods, accuracy: 0.5, line: line)
            for x in v.debugTranslationValues {
                XCTAssertTrue(x <= 0.5 && x >= -w - 0.5, "\(what) W=\(w): tx=\(x) ⇒ hở viền", line: line)
            }
            if let o = v.debugLoopTimeOffset {
                XCTAssertTrue(o >= 0 && o < RainbowBorder.period, "\(what): timeOffset=\(o)", line: line)
            }
        }
        for w in [CGFloat(375), 402, 440, 874, 956, 768, 1032, 1366] {
            kb.frame = CGRect(x: 0, y: 0, width: w, height: 290)
            kb.setNeedsLayout(); kb.layoutIfNeeded()
            for x in stride(from: 0.0, to: 1, by: 0.0625) + [0.999] {
                v.debugSetPhase(x)
                check("đứng x=\(x)")
                v.poke()
                check("gõ x=\(x)")                  // bản cũ: x=0,5 ⇒ vòng lặp tới −1,5W
                v.debugSettleNow()
                check("dừng dần x=\(x)")
                v.poke()
                check("gõ lại x=\(x)")
            }
            // Xoay giữa lúc chạy: dựng lại theo W mới, vẫn phủ kín.
            let other: CGFloat = w > 700 ? 402 : 874
            kb.frame = CGRect(x: 0, y: 0, width: other, height: 290)
            kb.setNeedsLayout(); kb.layoutIfNeeded()
            check("xoay \(w)→\(other)")
            v.halt()
        }
    }

    /// Bộ chậm: chi phí main thread mỗi phím (poke) + CPU khi nghỉ / khi đang chạy (render server lo animation).
    @MainActor func testCostPerKeyAndIdle() throws {
        try SlowTests.require()
        let win = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 400))
        win.isHidden = false
        defer { win.isHidden = true }
        func cpu(_ sec: Double) -> Double {
            let c0 = KeyboardBenchTests.mainThreadCPU()
            KeyboardBenchTests.spin(sec)
            return (KeyboardBenchTests.mainThreadCPU() - c0) * 1000
        }
        let kb = keyboard(.rgb, in: win)
        let v = try XCTUnwrap(kb.rainbow)
        let keys = Array("xinchaomoinguoihomnaytoiddilamvieccongty")
        var pokes: [Double] = []
        for _ in 0..<5 {
            for c in keys {
                guard let f = kb.debugLetterFrame(String(c)) else { continue }
                RainbowBorderView.debugCost = 0
                kb.benchTap(at: CGPoint(x: f.midX, y: f.midY), time: CACurrentMediaTime())
                pokes.append(RainbowBorderView.debugCost * 1000)
                KeyboardBenchTests.spin(0.01)
            }
        }
        let running = cpu(1.0) / 1.0                           // animation đang chạy (chưa nghỉ)
        KeyboardBenchTests.spin(RainbowBorder.idleAfter + RainbowBorder.decelTime + 0.3)
        XCTAssertEqual(v.debugAnimationCount, 0, "đã dừng + mờ xong ⇒ 0 animation")
        let idle = cpu(1.0)
        kb.removeFromSuperview()
        let base = cpu(1.0)
        let p = KeyboardBenchTests.pct
        let line = String(format: "RGB-COST poke p50=%.4f p95=%.4f p99=%.4f ms/phím | main CPU khi đang chạy=%.3f ms/s | nghỉ=%.3f ms/s | không bàn phím=%.3f ms/s",
                          p(pokes, 0.5), p(pokes, 0.95), p(pokes, 0.99), running, idle, base)
        print(line)
        XCTContext.runActivity(named: line) { _ in }
        XCTAssertLessThan(p(pokes, 0.95), 0.3, "≤ 0,3 ms/phím")
        XCTAssertLessThan(idle - base, 0.5, "nghỉ = 0 việc")
    }
}
