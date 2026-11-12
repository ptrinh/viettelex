// Theme "Ảo giác" (trippy, 11/2026): hiệu ứng "Kính vạn hoa" (KaleidoBloom / KaleidoFx), nền đổi sắc "borderFx":"hueflow"
// (HueFlow + RainbowBorderView .hueflowBorder / .hueflowFill), motif "swirl", âm "dream" (Mơ màng). Số tham chiếu GIỐNG
// HỆT android PsychedelicThemeTests.kt / PsychedelicViewTest.kt. Ảnh xem thử: đặt VT_THEME_SNAPSHOT_DIR.
import XCTest
import UIKit

final class PsychedelicThemeTests: XCTestCase {
    private let suite = "vt-trippy-theme"
    private let plusSuite = "vt-trippy-theme-plus"
    private var savedPaywall = false
    private var savedDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        savedPaywall = PlusGate.paywallEnabled
        savedDefaults = PlusGate.defaults
        UserDefaults(suiteName: plusSuite)!.removePersistentDomain(forName: plusSuite)
        PlusGate.defaults = UserDefaults(suiteName: plusSuite)!
        #if DEBUG
        KeyEffectOverlay.drawsOffscreen = true
        RainbowBorderView.drawsOffscreen = true
        #endif
    }

    override func tearDown() {
        PlusGate.paywallEnabled = savedPaywall
        PlusGate.defaults = savedDefaults
        UserDefaults(suiteName: plusSuite)!.removePersistentDomain(forName: plusSuite)
        #if DEBUG
        KeyEffectOverlay.drawsOffscreen = false
        RainbowBorderView.drawsOffscreen = false
        #endif
        super.tearDown()
    }

    // MARK: Kính vạn hoa

    func testKaleidoIdAppendedAndCapped() {
        XCTAssertEqual(KeyEffect.allCases.firstIndex(of: .dancefloor)! + 1, KeyEffect.allCases.firstIndex(of: .kaleido)!)
        XCTAssertEqual(KeyEffect.allCases.firstIndex(of: .dancefloor)! + 1, KeyEffect.allCases.firstIndex(of: .kaleido)!)
        XCTAssertEqual(KeyEffect.kaleido.rawValue, "kaleido")
        XCTAssertTrue(KeyEffect.kaleido.isPlus)
        XCTAssertFalse(KeyEffect.kaleido.isQueued); XCTAssertFalse(KeyEffect.kaleido.isParticle)
        XCTAssertEqual(KeyEffect.kaleido.band, .aboveKeys)
        XCTAssertTrue(KeyEffectOverlay.clipped.contains(.kaleido), "cắt theo bàn phím (#151)")
        XCTAssertEqual(KaleidoBloom.pool, 4)
        XCTAssertEqual(KaleidoBloom.folds, 8)
        XCTAssertEqual(L10n.en["Kính vạn hoa"], "Kaleidoscope")
    }

    /// 8 nhánh: mỗi mảnh / đá đối xứng qua trục của nó; nhánh k+2 = nhánh k xoay 90°; mốc chung Android.
    func testKaleidoGeometrySymmetric() {
        for k in 0..<KaleidoBloom.folds {
            for (poly, a) in [(KaleidoBloom.shard(k), KaleidoBloom.axis(k)),
                              (KaleidoBloom.gem(k), KaleidoBloom.axis(k) + .pi / Double(KaleidoBloom.folds))] {
                let ux = sin(a), uy = -cos(a)
                for p in poly {
                    let d = p.x * ux + p.y * uy
                    let mx = 2 * d * ux - p.x, my = 2 * d * uy - p.y
                    XCTAssertTrue(poly.contains { abs($0.x - mx) < 1e-9 && abs($0.y - my) < 1e-9 }, "nhánh \(k) đối xứng")
                    XCTAssertLessThanOrEqual(hypot(p.x, p.y), KaleidoBloom.extent + 1e-9)
                }
            }
            let a = KaleidoBloom.shard(k), b = KaleidoBloom.shard((k + 2) % KaleidoBloom.folds)
            for i in a.indices {
                let r = KaleidoBloom.rotate(a[i], .pi / 2)
                XCTAssertEqual(b[i].x, r.x, accuracy: 1e-9); XCTAssertEqual(b[i].y, r.y, accuracy: 1e-9)
            }
            XCTAssertEqual(KaleidoBloom.shardColor(k), k); XCTAssertEqual(KaleidoBloom.gemColor(k), (k + 4) % 8)
        }
        XCTAssertEqual(KaleidoBloom.shard(1)[0].x, 19.883842686965714, accuracy: 1e-9)
        XCTAssertEqual(KaleidoBloom.shard(1)[0].y, -19.883842686965718, accuracy: 1e-9)
        XCTAssertEqual(KaleidoBloom.gem(3)[0].x, 7.270985214936708, accuracy: 1e-9)
        XCTAssertEqual(KaleidoBloom.gem(3)[0].y, 17.55371111771445, accuracy: 1e-9)
        var sum = 0.0
        for k in 0..<KaleidoBloom.folds {
            for (i, p) in (KaleidoBloom.shard(k) + KaleidoBloom.gem(k)).enumerated() {
                sum += Double(k + 1) * (p.x * 3 + p.y * 7) + Double(i) * 0.01 * p.x
            }
        }
        XCTAssertEqual(sum, -1636.6092194925936, accuracy: 1e-6)
    }

    /// Nở + xoay chậm + tan trong ~0,9 s; số chung Android.
    func testKaleidoTimeline() {
        XCTAssertTrue((0.8...1.0).contains(KaleidoBloom.duration))
        XCTAssertGreaterThanOrEqual(KaleidoBloom.spin, 30 * .pi / 180); XCTAssertLessThanOrEqual(KaleidoBloom.spin, 60 * .pi / 180)
        XCTAssertEqual(KaleidoBloom.scale(0.05), 0.3681841563786009, accuracy: 1e-12)
        XCTAssertEqual(KaleidoBloom.scale(0.45), 0.90625, accuracy: 1e-12)
        XCTAssertEqual(KaleidoBloom.angle(0.45), 0.39269908169872414, accuracy: 1e-12)
        XCTAssertEqual(KaleidoBloom.alpha(0.05), 0.3716563786008231, accuracy: 1e-12)
        XCTAssertEqual(KaleidoBloom.alpha(0.45), 0.225, accuracy: 1e-12)
        XCTAssertEqual(KaleidoBloom.alpha(0.8), 0.011111111111111098, accuracy: 1e-12)
        XCTAssertEqual(KaleidoBloom.alpha(0.9), 0); XCTAssertEqual(KaleidoBloom.alpha(-0.01), 0)
        XCTAssertEqual(KaleidoBloom.scale(5), 1, accuracy: 1e-12)
        // Không nháy: độ mờ đổi chiều đúng MỘT lần (lên rồi xuống).
        var turns = 0, prev = 0.0, rising = true
        for i in 1...90 {
            let a = KaleidoBloom.alpha(Double(i) / 100)
            if rising && a < prev - 1e-12 { rising = false; turns += 1 } else if !rising && a > prev + 1e-12 { turns += 1 }
            prev = a
        }
        XCTAssertEqual(turns, 1)
    }

    /// Tâm kẹp để cả bông nằm trong khung — kể cả khung dời gốc (#151) hoặc hẹp hơn bông.
    func testKaleidoCenterInsideShiftedBounds() {
        let r = KaleidoBloom.extent
        for b in [(0.0, -180.0, 390.0, 470.0), (0, 0, 390, 290), (10, 5, 60, 50)] {
            for (x, y) in [(0.0, -180.0), (390, 290), (195, 100), (-50, 1000), (17, 21)] {
                let c = KaleidoBloom.center(x: x, y: y, bounds: b)
                if b.2 > 2 * r { XCTAssertGreaterThanOrEqual(c.x - r, b.0 - 1e-9); XCTAssertLessThanOrEqual(c.x + r, b.0 + b.2 + 1e-9) }
                else { XCTAssertEqual(c.x, b.0 + b.2 / 2, accuracy: 1e-9) }
                if b.3 > 2 * r { XCTAssertGreaterThanOrEqual(c.y - r, b.1 - 1e-9); XCTAssertLessThanOrEqual(c.y + r, b.1 + b.3 + 1e-9) }
                else { XCTAssertEqual(c.y, b.1 + b.3 / 2, accuracy: 1e-9) }
            }
        }
        let c = KaleidoBloom.center(x: 17, y: -170, bounds: (0, -180, 390, 470))
        XCTAssertEqual(c.x, 38, accuracy: 1e-9); XCTAssertEqual(c.y, -142, accuracy: 1e-9)
        let mid = KaleidoBloom.center(x: 195, y: 100, bounds: (0, -180, 390, 470))
        XCTAssertEqual(mid.x, 195, accuracy: 1e-9); XCTAssertEqual(mid.y, 100, accuracy: 1e-9)
    }

    /// Overlay thật trên host dời gốc bounds: ≤ 4 bông dùng lại, mọi bông (cả bán kính) trong bàn phím, ẩn ⇒ ẩn hết, đổi kiểu ⇒ gỡ.
    @MainActor func testKaleidoOverlayInsideShiftedKeyboardAndCapped() throws {
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 470))
        host.bounds.origin.y = -180
        let keysView = UIView(frame: host.bounds)
        host.addSubview(keysView)
        let o = try XCTUnwrap(KeyEffectOverlay.install(.kaleido, color: .systemPurple, keyFill: .white, in: host, keys: keysView, existing: nil))
        XCTAssertEqual(o.bounds.origin, host.bounds.origin)
        XCTAssertTrue(o.clipsToBounds)
        XCTAssertTrue(o.debugKaleidoRoots.isEmpty, "chưa gõ: không dựng gì")
        let keys = [CGRect(x: 0, y: -180, width: 34, height: 42), CGRect(x: 356, y: 248, width: 34, height: 42),
                    CGRect(x: 180, y: 120, width: 34, height: 42)]
        for i in 0..<30 { o.emit(key: keys[i % keys.count]); o.flush() }
        XCTAssertEqual(o.debugKaleidoRoots.count, KaleidoBloom.pool)
        XCTAssertEqual(o.layer.sublayers?.count, KaleidoBloom.pool)
        let r = CGFloat(KaleidoBloom.extent)
        for root in o.debugKaleidoRoots {
            XCTAssertTrue(o.bounds.insetBy(dx: r - 0.5, dy: r - 0.5).contains(root.position), "\(root.position) — cả bông trong \(o.bounds)")
            XCTAssertFalse(root.isHidden)
            let spinner = try XCTUnwrap(root.sublayers?.first)
            XCTAssertNotNil(spinner.animation(forKey: "fx"), "animation gắn một lần")
            XCTAssertEqual(spinner.sublayers?.count, KaleidoBloom.colors.count, "mỗi sắc một layer")
        }
        o.halt()
        for root in o.debugKaleidoRoots { XCTAssertTrue(root.isHidden) }
        _ = KeyEffectOverlay.install(.heart, color: .red, in: host, keys: keysView, existing: o)
        XCTAssertTrue(o.debugKaleidoRoots.isEmpty, "đổi kiểu ⇒ gỡ sạch")
        _ = KeyEffectOverlay.install(.none, color: .red, in: host, existing: o)
    }

    // MARK: Hue flow

    func testHueFlowRateLimits() {
        XCTAssertGreaterThanOrEqual(HueFlow.period, HueFlow.minCycle, "một vòng ≥ 8 s")
        XCTAssertEqual(HueFlow.minCycle, 8)
        XCTAssertEqual(RainbowTuning.hueflowBorder.period, 12)
        XCTAssertEqual(RainbowTuning.hueflowFill.period, 12)
        XCTAssertGreaterThanOrEqual(1 / RainbowTuning.hueflowFill.fullSpeed, 8)
        XCTAssertLessThanOrEqual(HueFlow.transitionsPerSecond, 3, "≤ 3 lần chuyển sắc / giây")
        XCTAssertEqual(HueFlow.transitionsPerSecond, 5.0 / 12, accuracy: 1e-12)
        XCTAssertEqual(HueFlow.maxLuminanceStep, 0.018897007742348607, accuracy: 1e-9)
        XCTAssertLessThanOrEqual(HueFlow.maxLuminanceStep, 0.025, "sắc kề nhau cùng độ sáng — không nháy")
        XCTAssertEqual(HueFlow.fillHues.first, HueFlow.fillHues.last)
        XCTAssertEqual(RainbowTuning.hueflowFill.restAlpha, RainbowTuning.hueflowFill.activeAlpha, "nền: độ đậm không đổi")
        XCTAssertGreaterThanOrEqual(RainbowTuning.hueflowBorder.fadeInTime, 0.5)
        XCTAssertEqual(HueFlow.idleAfter, 1.5)
        let st = HueFlow.fillStops()
        XCTAssertEqual(st.count, 11); XCTAssertEqual(st.last?.location, 1); XCTAssertEqual(st[5].location, 0.5, accuracy: 1e-12)
    }

    /// Chuyển động thuần: gõ ⇒ tốc độ 1/12 vòng/giây sau 0,8 s; nghỉ ⇒ giảm tốc 1,5 s rồi đứng yên. Mốc chung Android.
    func testHueFlowMotionStopsAfterIdle() {
        let k = RainbowTuning.hueflowFill
        let run = RainbowMotion.rest(at: 0.3).resumed(at: 10, k)
        XCTAssertEqual(run.ramp, 0.8, accuracy: 1e-12); XCTAssertEqual(run.v1, 1.0 / 12, accuracy: 1e-12)
        XCTAssertEqual(RainbowMotion.rest(at: 0.3).resumed(at: 10, .hueflowBorder).offset(at: 20), 0.09999999999999987, accuracy: 1e-9)
        let stop = run.settled(at: 21.5, k)
        XCTAssertEqual(stop.ramp, 1.5, accuracy: 1e-9)
        XCTAssertEqual(stop.v1, 0)
        XCTAssertEqual(stop.offset(at: stop.rampEnd + 5), stop.offset(at: stop.rampEnd + 50), accuracy: 1e-12, "đứng yên")
        var t = 10.0
        while t < stop.rampEnd {
            let v = t < 21.5 ? run.velocity(at: t) : stop.velocity(at: t)
            XCTAssertLessThanOrEqual(v, 1 / HueFlow.minCycle + 1e-12); t += 0.05
        }
    }

    /// View thật: gõ ⇒ chạy; nghỉ 1,5 s ⇒ dừng dần rồi 0 animation (0 chi phí khi nghỉ). Nền: độ đậm KHÔNG đổi.
    @MainActor func testHueFillViewStopsAndRipplesOnlyOnFastTyping() throws {
        let win = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 300))
        win.isHidden = false
        defer { win.isHidden = true }
        let fill = RainbowBorderView(kind: .hueflowFill)
        fill.frame = win.bounds
        win.addSubview(fill)
        fill.layoutIfNeeded()
        XCTAssertTrue(fill.isFill)
        XCTAssertNil(fill.layer.mask, "nền: cả mặt, không mặt nạ")
        XCTAssertEqual(fill.debugStrip.opacity, Float(HueFlow.fillAlpha), accuracy: 1e-6)
        fill.debugSetIdle(0.15)
        fill.poke(at: CGPoint(x: 100, y: 150))
        XCTAssertTrue(fill.debugRunning)
        XCTAssertEqual(fill.debugRippleFired, 0, "gõ chậm ⇒ không gợn")
        XCTAssertFalse(fill.debugAnimationKeys.contains("rgb.fade"), "nền: không có bước sáng")
        for _ in 0..<20 { fill.poke(at: CGPoint(x: 100, y: 150)) }
        XCTAssertEqual(fill.debugRippleFired, 1, "gõ dồn ⇒ MỘT gợn (trần nhịp)")
        XCTAssertEqual(fill.debugRipples.count, 1)
        XCTAssertEqual(fill.debugRipples.first?.position, CGPoint(x: 100, y: 150))
        XCTAssertEqual(fill.debugRipples.first?.sublayers?.count, HueFlow.rippleRings)
        fill.poke(at: nil)
        XCTAssertEqual(fill.debugRippleFired, 1, "phím không khung: không gợn")
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        fill.debugSettleNow()
        XCTAssertFalse(fill.debugRunning)
        RunLoop.main.run(until: Date().addingTimeInterval(HueFlow.decelTime + 0.4))
        XCTAssertEqual(fill.debugAnimationCount, 0, "nghỉ ⇒ 0 animation")
        fill.halt()
        XCTAssertTrue(fill.debugRipples.allSatisfy(\.isHidden))
        // Viền: bộ số "hueflow", có mặt nạ, không gợn.
        let border = RainbowBorderView(kind: .hueflowBorder)
        XCTAssertEqual(border.tuning, .hueflowBorder)
        XCTAssertNotNil(border.layer.mask)
        for _ in 0..<20 { border.poke(at: CGPoint(x: 1, y: 1)) }
        XCTAssertEqual(border.debugRippleFired, 0)
        border.halt()
    }

    func testHueFlowRipple() {
        XCTAssertEqual(HueFlow.rippleRadius(0.8, ring: 1), 74.25537109375, accuracy: 1e-9)
        XCTAssertEqual(HueFlow.rippleAlpha(0.8, ring: 1), 0.16542968749999998, accuracy: 1e-12)
        XCTAssertEqual(HueFlow.rippleAlpha(0.1, ring: 0), 0.205078125, accuracy: 1e-12)
        XCTAssertEqual(HueFlow.rippleRadius(2.0, ring: 2), 109.78515625, accuracy: 1e-9)
        XCTAssertEqual(HueFlow.rippleAlpha(0.2, ring: 1), 0)
        XCTAssertEqual(HueFlow.rippleAlpha(HueFlow.rippleLifetime, ring: 2), 0)
        XCTAssertEqual(HueFlow.rippleLifetime, 2.2, accuracy: 1e-12)
        XCTAssertEqual(HueFlow.rippleColor(ring: 1, seed: 0), 0xFFCC00)
        XCTAssertEqual(HueFlow.rippleColor(ring: 0, seed: 0), 0xFF3B30)
        XCTAssertEqual(HueFlow.rippleColor(ring: 1, seed: 1), 0x00C7BE)
        var prev = -1.0
        for i in 0...44 {
            let r = HueFlow.rippleRadius(Double(i) * 0.05, ring: 0); XCTAssertGreaterThanOrEqual(r, prev); prev = r
            XCTAssertLessThanOrEqual(HueFlow.rippleAlpha(Double(i) * 0.05, ring: 0), HueFlow.ripplePeak + 1e-12)
        }
        var g = HueFlow.RippleGate()
        XCTAssertFalse(g.trigger(level: 1, at: 0))
        XCTAssertTrue(g.trigger(level: 2, at: 0)); XCTAssertFalse(g.trigger(level: 3, at: 0.5)); XCTAssertTrue(g.trigger(level: 2, at: 0.9))
        XCTAssertEqual(g.fired, 2)
    }

    // MARK: Theme

    func testTrippyTheme() throws {
        let t = KeyboardTheme.trippy
        XCTAssertEqual(KeyboardTheme.allCases.firstIndex(of: .nightclub)! + 1, KeyboardTheme.allCases.firstIndex(of: .trippy)!)
        XCTAssertTrue(t.isPlus); XCTAssertTrue(t.isInteractive)
        XCTAssertEqual(t.title, L("Ảo giác")); XCTAssertEqual(L10n.en["Ảo giác"], "Psychedelic")
        let spec = try XCTUnwrap(t.spec)
        XCTAssertEqual(spec.nameVi, "Ảo giác"); XCTAssertEqual(spec.nameEn, "Psychedelic")
        XCTAssertEqual(spec.effect, "kaleido"); XCTAssertEqual(spec.sound, "dream"); XCTAssertEqual(spec.swipe, "kaleidoscope")
        for dark in [false, true] {
            let p = t.palette(systemDark: dark)
            XCTAssertTrue(p.hueFlow); XCTAssertFalse(p.rainbowBorder); XCTAssertFalse(p.auroraBorder)
            XCTAssertEqual(p.decoration?.motif, .swirl)
            XCTAssertTrue(p.isDark)
            XCTAssertLessThan(p.keyFill.a, 1, "phím trong mờ")
            let bg = try XCTUnwrap(p.background)
            XCTAssertGreaterThanOrEqual(RGBA.contrast(p.ink, p.keyFill.over(bg)), 4.5, "chữ trắng ≥ 4,5")
        }
        XCTAssertEqual(t.systemBackdropKey, "systemBackdropTrippy")
        XCTAssertNotNil(BackupSettings.byKey["systemBackdropTrippy"])
        XCTAssertEqual(Array(ThemePicker.interactiveOrder.prefix(3)), ["nightclub", "ai", "trippy"])
    }

    func testHueflowParseAndPatch() throws {
        let base = ##"{"v":1,"name":{"vi":"x"},"light":{"key":"#000000","special":"#111111","ink":"#FFFFFF","accent":"#7C4DFF","borderFx":"hueflow"}}"##
        let s = try XCTUnwrap(ThemeSpecParser.parse(base).spec)
        XCTAssertEqual(s.light.borderFx, "hueflow")
        XCTAssertTrue(s.palette(dark: false).hueFlow); XCTAssertFalse(s.palette(dark: false).rainbowBorder)
        XCTAssertTrue(s.canonical.contains(#""borderFx":"hueflow""#))
        XCTAssertEqual(ThemeSpecParser.parse(s.canonical).spec?.canonical, s.canonical)
        XCTAssertEqual(ThemeSpec.slots(from: s.palette(dark: false)).borderFx, "hueflow")
        XCTAssertTrue(ThemeSlots.borderFxValues.contains("hueflow"))
    }

    /// Motif "swirl": một dải xoắn (đa giác đơn, chiều quay dương) + 4 chấm; |y| ≤ 0,45; mốc chung Android.
    func testSwirlMotif() {
        XCTAssertEqual(KeyboardDecoration.Motif.allCases.firstIndex(of: .neural)! + 1, KeyboardDecoration.Motif.allCases.firstIndex(of: .swirl)!)
        let subs = KeyboardDecoration.shape(.swirl)
        XCTAssertEqual(subs.count, 5)
        XCTAssertEqual(1 + subs[0].segs.count, 2 * (KeyboardDecoration.swirlSteps + 1))
        var sum = 0.0
        for (k, sub) in subs.enumerated() {
            var pts: [(Double, Double)] = [sub.start]
            for g in sub.segs { var i = 0; while i < g.count { pts.append((g[i], g[i + 1])); i += 2 } }
            var a = 0.0
            for i in pts.indices { let p = pts[i], q = pts[(i + 1) % pts.count]; a += p.0 * q.1 - q.0 * p.1 }
            XCTAssertGreaterThan(a, 0, "#\(k) chiều quay")
            for p in pts {
                XCTAssertLessThanOrEqual(abs(p.1), 0.45, "#\(k)")
                if k == 0 { XCTAssertLessThanOrEqual(abs(p.0), 0.5) }
                sum += p.0 * 3 + p.1 * 7
            }
        }
        XCTAssertEqual(sum, -10.817954210730875, accuracy: 1e-6)
    }

    // MARK: Âm

    func testDreamSound() {
        let golden: [(KeySoundKind, Double)] = [(.letter, 127.8460), (.delete, 134.0004), (.modifier, 155.4833)]
        for (k, want) in golden {
            let wood = KeySoundSynth.samples(.wood, k), a = KeySoundSynth.samples(.dream, k)
            XCTAssertLessThan(KeySoundSynth.rms(a), KeySoundSynth.rms(wood), "\(k)")
            XCTAssertLessThan(a.map(abs).max() ?? 1, wood.map(abs).max() ?? 0, "\(k)")
            XCTAssertLessThan(Double(a.count) / KeySoundSynth.sampleRate, 0.061, "\(k)")
            XCTAssertEqual(a.reduce(0.0) { $0 + Double(abs($1)) }, want, accuracy: 0.01, "\(k)")
        }
        XCTAssertEqual(KeySoundStyle.allCases.firstIndex(of: .club)! + 1, KeySoundStyle.allCases.firstIndex(of: .dream)!)
        XCTAssertTrue(KeySoundStyle.presets.contains(.dream))
        XCTAssertTrue(KeySoundStyle.presetIDs.contains("dream"))
        XCTAssertEqual(L10n.en["Mơ màng"], "Dreamy")
    }

    // MARK: Bàn phím thật

    @MainActor private func withKeyboard(_ body: (KeyboardView, UIWindow) throws -> Void) rethrows {
        PlusGate.paywallEnabled = false
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        d.set(KeyboardTheme.trippy.rawValue, forKey: ThemeSettings.themeKey)
        d.set(KeyEffect.kaleido.rawValue, forKey: KeyEffect.key)
        d.set(false, forKey: KeyboardView.keyPreviewKey)
        let saved = UserDefaultsProvider.shared
        UserDefaultsProvider.shared = d
        defer { UserDefaultsProvider.shared = saved; d.removePersistentDomain(forName: suite) }
        let win = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 320))
        win.overrideUserInterfaceStyle = .dark
        win.backgroundColor = UIColor(white: 0.11, alpha: 1)
        win.isHidden = false
        defer { win.isHidden = true }
        let kb = KeyboardView(needsGlobe: false, inputController: nil, onKey: { _ in })
        win.addSubview(kb)
        kb.frame = win.bounds
        kb.applyAppearance(.dark, style: .dark)
        kb.layoutIfNeeded()
        try body(kb, win)
        kb.tearDown()
    }

    /// Theme thật: viền "hueflow" trên hàng phím + nền đổi sắc sau hàng phím (cùng khung bàn phím); đổi theme ⇒ gỡ (0 chi phí).
    @MainActor func testKeyboardInstallsHueFlowLayersOnlyForTrippy() throws {
        try withKeyboard { kb, _ in
            let border = try XCTUnwrap(kb.rainbow)
            XCTAssertEqual(border.kind, .hueflowBorder)
            let fill = try XCTUnwrap(kb.hueFill)
            XCTAssertEqual(fill.kind, .hueflowFill)
            XCTAssertEqual(fill.frame, kb.bounds)
            let iFill = try XCTUnwrap(kb.subviews.firstIndex(of: fill)), iBorder = try XCTUnwrap(kb.subviews.firstIndex(of: border))
            XCTAssertLessThan(iFill, iBorder, "nền sau phím, viền trên phím")
            XCTAssertEqual(kb.keyEffects?.effect, .kaleido)
            let f = try XCTUnwrap(kb.debugLetterFrame("g"))
            for i in 0..<20 { kb.benchTap(at: CGPoint(x: f.midX, y: f.midY), time: 1 + Double(i) * 0.01) }
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            XCTAssertTrue(fill.debugRunning)
            XCTAssertEqual(fill.debugRippleFired, 1, "gõ dồn ⇒ một gợn sóng màu")
            let p = try XCTUnwrap(fill.debugRipples.first?.position)
            XCTAssertEqual(p.x, f.midX, accuracy: 1); XCTAssertEqual(p.y, f.midY, accuracy: 1)
            XCTAssertFalse(kb.keyEffects?.debugKaleidoRoots.isEmpty ?? true, "Kính vạn hoa đã nở")
            // Đổi sang theme khác ⇒ không còn lớp nào.
            UserDefaultsProvider.shared?.set(KeyboardTheme.oled.rawValue, forKey: ThemeSettings.themeKey)
            kb.applyAppearance(.dark, style: .dark)
            kb.layoutIfNeeded()
            XCTAssertNil(kb.hueFill)
            XCTAssertNil(kb.rainbow)
        }
    }

    // MARK: Ảnh xem thử (chỉ khi đặt VT_THEME_SNAPSHOT_DIR)

    @MainActor func testWriteTrippyThemeSnapshot() throws {
        guard let dir = ProcessInfo.processInfo.environment["VT_THEME_SNAPSHOT_DIR"] else {
            throw XCTSkip("đặt VT_THEME_SNAPSHOT_DIR để xuất ảnh theme")
        }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try withKeyboard { kb, win in
            kb.setSuggestionsEnabled(true)
            kb.configureInputKind(.normal)
            kb.setNeedsLayout(); kb.layoutIfNeeded()
            kb.showSuggestions(.init(nextWords: ["Xin", "chào", "bạn"]))
            let h = kb.systemLayoutSizeFitting(CGSize(width: 402, height: 0)).height
            win.frame.size.height = max(h, 200); kb.frame = win.bounds
            win.layoutIfNeeded(); kb.layoutIfNeeded()
            // Nền đang trôi giữa chừng (lệch 0,35 chu kỳ) như lúc gõ.
            kb.hueFill?.debugSetPhase(0.35)
            kb.rainbow?.debugSetPhase(0.2)
            let rb = kb.rainbow
            rb?.isHidden = true
            let g = kb.debugLetterFrame("g") ?? CGRect(x: 180, y: 200, width: 34, height: 42)
            let img = UIGraphicsImageRenderer(bounds: win.bounds).image { ctx in
                let c = ctx.cgContext
                win.backgroundColor?.setFill(); ctx.fill(win.bounds)
                kb.layer.render(in: c)
                if let rb {
                    c.saveGState(); c.translateBy(x: rb.frame.minX, y: rb.frame.minY); rb.debugDraw(in: c); c.restoreGState()
                }
                // Một bông Kính vạn hoa giữa đời (t = 0,3 s) ở phím "g" — vẽ tay theo đúng hình học KaleidoBloom.
                let t = 0.3
                let ctr = KaleidoBloom.center(x: Double(g.midX), y: Double(g.midY),
                                              bounds: (Double(kb.bounds.minX), Double(kb.bounds.minY), Double(kb.bounds.width), Double(kb.bounds.height)))
                c.saveGState()
                c.translateBy(x: ctr.x, y: ctr.y)
                c.rotate(by: CGFloat(KaleidoBloom.angle(t)))
                c.scaleBy(x: CGFloat(KaleidoBloom.scale(t)), y: CGFloat(KaleidoBloom.scale(t)))
                c.setAlpha(CGFloat(KaleidoBloom.alpha(t)))
                func poly(_ pts: [(x: Double, y: Double)], _ rgb: UInt32) {
                    c.beginPath(); c.move(to: CGPoint(x: pts[0].x, y: pts[0].y))
                    for q in pts.dropFirst() { c.addLine(to: CGPoint(x: q.x, y: q.y)) }
                    c.closePath()
                    c.setFillColor(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                                   blue: CGFloat(rgb & 0xFF) / 255, alpha: 0.85)
                    c.fillPath()
                }
                for k in 0..<KaleidoBloom.folds {
                    poly(KaleidoBloom.shard(k), KaleidoBloom.colors[KaleidoBloom.shardColor(k)])
                    poly(KaleidoBloom.gem(k), KaleidoBloom.colors[KaleidoBloom.gemColor(k)])
                }
                c.restoreGState()
            }
            rb?.isHidden = false
            try XCTUnwrap(img.pngData()).write(to: URL(fileURLWithPath: dir).appendingPathComponent("trippy-theme-ios.png"))
        }
    }
}
