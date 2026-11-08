// Theme "Lạc trôi" (11/2026): Đường hầm (TunnelFx / TunnelRings), Lơ lửng (FloatFx / FloatClock / KeyFloat / FloatPolicy),
// "keyMotion", "bg2", âm "airy". Số tham chiếu GIỐNG HỆT android DriftTests.kt (+ DriftThemeTest phần view).
import XCTest
import UIKit

final class DriftTests: XCTestCase {
    private var savedPaywall = PlusGate.paywallEnabled
    #if DEBUG
    private var savedOffscreen = KeyEffectOverlay.drawsOffscreen
    #endif

    override func setUp() {
        super.setUp()
        savedPaywall = PlusGate.paywallEnabled
        PlusGate.paywallEnabled = false
        #if DEBUG
        savedOffscreen = KeyEffectOverlay.drawsOffscreen
        KeyEffectOverlay.drawsOffscreen = true
        #endif
    }
    override func tearDown() {
        PlusGate.paywallEnabled = savedPaywall
        #if DEBUG
        KeyEffectOverlay.drawsOffscreen = savedOffscreen
        #endif
        super.tearDown()
    }

    func testEffectIdsAppendedAndPlus() {
        XCTAssertEqual({ let o = KeyEffect.allCases.map(\.rawValue); let i = o.firstIndex(of: "tunnel") ?? 0; return Array(o[i..<min(i + 2, o.count)]) }(), ["tunnel", "float"])
        XCTAssertEqual(KeyEffect.allCases.firstIndex(of: .kaleido)! + 1, KeyEffect.allCases.firstIndex(of: .tunnel)!)
        XCTAssertTrue(KeyEffect.tunnel.isPlus); XCTAssertTrue(KeyEffect.float.isPlus)
        XCTAssertEqual(KeyEffect.parse("tunnel"), .tunnel); XCTAssertEqual(KeyEffect.parse("float"), .float)
        XCTAssertEqual(L10n.en["Đường hầm"], "Tunnel"); XCTAssertEqual(L10n.en["Lơ lửng"], "Floating")
        XCTAssertTrue(ThemeExtraIds.effects.contains("tunnel")); XCTAssertTrue(ThemeExtraIds.effects.contains("float"))
        XCTAssertEqual(KeyEffect.tunnel.band, .aboveKeys)
        XCTAssertTrue(KeyEffectOverlay.clipped.contains(.tunnel))
    }

    func testTunnelTimingAndCaps() {
        XCTAssertEqual(TunnelFx.pool, 16)
        XCTAssertEqual((0...3).map { TunnelFx.rings(level: $0) }, [2, 3, 4, 5])
        XCTAssertEqual(TunnelFx.rings(level: -1), 2); XCTAssertEqual(TunnelFx.rings(level: 9), 5)
        for l in 1...3 { XCTAssertLessThan(TunnelFx.duration(level: l), TunnelFx.duration(level: l - 1)) }
        for l in 0...3 {
            XCTAssertTrue((0.9...1.2).contains(TunnelFx.duration(level: l)))
            XCTAssertLessThanOrEqual(TunnelFx.delay(ring: TunnelFx.rings(level: l) - 1) + TunnelFx.duration(level: l), 1.6)
        }
        XCTAssertGreaterThanOrEqual(TunnelFx.pool, 3 * TunnelFx.rings(level: 3))
        XCTAssertEqual(TunnelFx.delay(ring: 2), 0.24, accuracy: 1e-12)
    }

    func testTunnelScaleCurveAccelerates() {
        XCTAssertEqual(TunnelFx.scale(0), 1, accuracy: 1e-12)
        XCTAssertEqual(TunnelFx.scale(0.5), 0.75, accuracy: 1e-12)
        XCTAssertEqual(TunnelFx.scale(1), 0, accuracy: 1e-12)
        XCTAssertEqual(TunnelFx.scale(-1), 1, accuracy: 1e-12); XCTAssertEqual(TunnelFx.scale(2), 0, accuracy: 1e-12)
        var prev = 0.0
        for k in 1...10 {
            let d = TunnelFx.scale(Double(k - 1) / 10) - TunnelFx.scale(Double(k) / 10)
            XCTAssertGreaterThan(d, prev, "co nhanh dần"); prev = d
        }
        XCTAssertEqual(TunnelFx.alpha(0), 0, accuracy: 1e-12)
        XCTAssertEqual(TunnelFx.alpha(0.06), 0.425, accuracy: 1e-12)
        XCTAssertEqual(TunnelFx.alpha(0.5), 0.85, accuracy: 1e-12)
        XCTAssertEqual(TunnelFx.alpha(0.85), 0.425, accuracy: 1e-12)
        XCTAssertEqual(TunnelFx.alpha(1), 0); XCTAssertEqual(TunnelFx.alpha(-0.1), 0)
        for k in 0...100 { XCTAssertLessThanOrEqual(TunnelFx.alpha(Double(k) / 100), TunnelFx.peakAlpha + 1e-12) }
        var o = TunnelFx.center((100, 50), vanish: (20, 40), 0.5)
        XCTAssertEqual(o.x, 80, accuracy: 1e-12); XCTAssertEqual(o.y, 47.5, accuracy: 1e-12)
        o = TunnelFx.center((100, 50), vanish: (20, 40), 1)
        XCTAssertEqual(o.x, 20, accuracy: 1e-12); XCTAssertEqual(o.y, 40, accuracy: 1e-12)
        o = TunnelFx.vanish(key: (10, 20, 30, 40), bounds: (0, 0, 400, 200))
        XCTAssertEqual(o.x, 25, accuracy: 1e-12); XCTAssertEqual(o.y, 40, accuracy: 1e-12)
        o = TunnelFx.vanish(key: (10, 20, 0, 0), bounds: (0, -50, 400, 200))
        XCTAssertEqual(o.x, 200, accuracy: 1e-12); XCTAssertEqual(o.y, 50, accuracy: 1e-12)
        XCTAssertEqual(TunnelFx.corner(width: 390, height: 260), 22, accuracy: 1e-12)
        XCTAssertEqual(TunnelFx.corner(width: 390, height: 100), 12, accuracy: 1e-12)
    }

    func testFloatParamsSharedAndBounded() {
        let p = FloatFx.params(0)
        XCTAssertEqual(p.ax, 1.431971, accuracy: 1e-5); XCTAssertEqual(p.ay, 2.385931, accuracy: 1e-5)
        XCTAssertEqual(p.rot, 0.018058, accuracy: 1e-5)
        XCTAssertEqual(p.px, 4.061488, accuracy: 1e-5); XCTAssertEqual(p.py, 4.426926, accuracy: 1e-5)
        XCTAssertEqual(p.pr, 3.779702, accuracy: 1e-5)
        var o = FloatFx.bob(0, 1.0)
        XCTAssertEqual(o.x, 1.431566, accuracy: 1e-5); XCTAssertEqual(o.y, 2.358608, accuracy: 1e-5)
        XCTAssertEqual(o.rot, 0.017982, accuracy: 1e-5)
        o = FloatFx.bob(1, 2.5)
        XCTAssertEqual(o.x, -1.489583, accuracy: 1e-5); XCTAssertEqual(o.y, 1.382083, accuracy: 1e-5)
        XCTAssertEqual(o.rot, -0.001236, accuracy: 1e-5)
        var positive = 0
        for i in 0..<60 {
            let q = FloatFx.params(i)
            XCTAssertLessThanOrEqual(hypot(q.ax, q.ay), FloatFx.maxOffset + 1e-9)
            XCTAssertLessThanOrEqual(abs(q.rot), FloatFx.maxRotation)
            for per in [q.px, q.py, q.pr] { XCTAssertTrue((3.0...5.0).contains(per), "chậm: chu kỳ 3–5 s") }
            if q.ax > 0 { positive += 1 }
            for k in 0...40 {
                let b = FloatFx.bob(i, Double(k) * 0.37)
                XCTAssertLessThanOrEqual(hypot(b.x, b.y), FloatFx.maxOffset + 1e-9)
                XCTAssertLessThanOrEqual(abs(b.rot), FloatFx.maxRotation)
            }
        }
        XCTAssertTrue((15...45).contains(positive), "phím kề không cùng hướng hết")
        let z = FloatFx.bob(7, 0)
        XCTAssertEqual(hypot(z.x, z.y) + abs(z.rot), 0, accuracy: 1e-12, "rời hàng từ 0 — không giật")
    }

    func testFloatClockSettlesAndStops() {
        var c = FloatClock()
        XCTAssertFalse(c.active)
        XCTAssertTrue(c.poke(at: 0)); XCTAssertFalse(c.poke(at: 0.5), "đang trôi: gõ tiếp không gắn lại")
        XCTAssertFalse(c.update(at: 2.4)); XCTAssertTrue(c.bobbing)
        XCTAssertEqual(c.offset(0, at: 1.0).x, FloatFx.bob(0, 1.0).x, accuracy: 1e-12)
        XCTAssertTrue(c.update(at: 2.5)); XCTAssertFalse(c.bobbing); XCTAssertTrue(c.active)
        XCTAssertEqual(c.frozen, 2.5, accuracy: 1e-12)
        let b = FloatFx.bob(0, 2.5)
        XCTAssertEqual(c.offset(0, at: 2.5).x, b.x, accuracy: 1e-12)
        XCTAssertEqual(c.offset(0, at: 2.9).x, b.x * 0.5, accuracy: 1e-12)
        XCTAssertEqual(c.offset(0, at: 2.9).rot, b.rot * 0.5, accuracy: 1e-12)
        XCTAssertEqual(FloatFx.settleFactor(0.4), 0.5, accuracy: 1e-12)
        XCTAssertFalse(c.update(at: 3.29)); XCTAssertTrue(c.active)
        XCTAssertFalse(c.update(at: 3.31)); XCTAssertFalse(c.active, "dừng hẳn ⇒ 0 animation")
        let z = c.offset(0, at: 3.31)
        XCTAssertEqual(abs(z.x) + abs(z.y) + abs(z.rot), 0)
    }

    func testFloatClockRepokeDuringSettleIsContinuous() {
        var c = FloatClock()
        c.poke(at: 0); c.update(at: 2.0)
        let p = c.offset(3, at: 2.3)
        XCTAssertTrue(c.poke(at: 2.3))
        let o = c.offset(3, at: 2.3)
        XCTAssertEqual(o.x, p.x, accuracy: 1e-12); XCTAssertEqual(o.y, p.y, accuracy: 1e-12); XCTAssertEqual(o.rot, p.rot, accuracy: 1e-12)
        let n = c.offset(3, at: 2.31)
        XCTAssertLessThan(abs(n.x - p.x), 0.2); XCTAssertLessThan(abs(n.y - p.y), 0.2)
        c.update(at: 3.0); XCTAssertTrue(c.bobbing)
        c.stop(); XCTAssertFalse(c.active)
    }

    func testFloatPolicy() {
        XCTAssertTrue(FloatPolicy.active(effect: .float, keyMotion: nil, plus: true, lowPower: false))
        XCTAssertTrue(FloatPolicy.active(effect: .tunnel, keyMotion: "float", plus: true, lowPower: false))
        XCTAssertTrue(FloatPolicy.active(effect: .none, keyMotion: "float", plus: true, lowPower: false))
        XCTAssertFalse(FloatPolicy.active(effect: .tunnel, keyMotion: nil, plus: true, lowPower: false))
        XCTAssertFalse(FloatPolicy.active(effect: .float, keyMotion: "float", plus: false, lowPower: false))
        XCTAssertFalse(FloatPolicy.active(effect: .float, keyMotion: "float", plus: true, lowPower: true))
        XCTAssertEqual(ThemeExtraIds.keyMotions, ["float"])
    }

    // MARK: Đường hầm — overlay

    /// Vòng gắn animation tự gỡ, trần pool, gốc ở điểm tụ TRONG bàn phím kể cả khi host dời gốc (#151); ẩn ⇒ 0 animation.
    @MainActor func testTunnelOverlayCappedInsideShiftedBounds() throws {
        #if DEBUG
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 470))
        host.bounds.origin.y = -180
        let keys = UIView(frame: host.bounds); host.addSubview(keys)
        let o = try XCTUnwrap(KeyEffectOverlay.install(.tunnel, color: .systemTeal, in: host, keys: keys, existing: nil))
        XCTAssertTrue(o.clipsToBounds)
        o.emit(key: CGRect(x: 120, y: 200, width: 34, height: 42)); o.flush()
        let t = try XCTUnwrap(o.debugTunnel)
        XCTAssertEqual(t.debugRoots.count, TunnelFx.rings(level: 0))
        XCTAssertEqual(t.debugAnimationCount, TunnelFx.rings(level: 0))
        XCTAssertEqual(t.debugRoots[0].position, CGPoint(x: 137, y: 221), "điểm tụ = tâm phím")
        let g = try XCTUnwrap(t.debugRoots[0].animation(forKey: TunnelRings.animKey) as? CAAnimationGroup)
        XCTAssertTrue(g.isRemovedOnCompletion, "xong tự gỡ ⇒ nghỉ = 0 animation")
        XCTAssertEqual(g.duration, TunnelFx.duration(level: 0), accuracy: 1e-9)
        // Vòng lớn nhất = viền bàn phím thụt `inset`, đặt ở (C − V) quanh điểm tụ ⇒ trọn trong bounds (gốc dời).
        let core = t.debugCores[0]
        let ring = try XCTUnwrap(core.path?.boundingBoxOfPath).offsetBy(dx: t.debugRoots[0].position.x + core.position.x,
                                                                         dy: t.debugRoots[0].position.y + core.position.y)
        XCTAssertTrue(o.bounds.insetBy(dx: 1, dy: 1).contains(ring), "\(ring) trong \(o.bounds)")
        // Phím ở mép trên (gốc dời) / không cỡ ⇒ vẫn trong bàn phím.
        o.emit(key: CGRect(x: 0, y: -180, width: 34, height: 42)); o.flush()
        o.emit(at: CGPoint(x: 5, y: 5)); o.flush()
        for _ in 0..<40 { o.emit(key: CGRect(x: 300, y: 250, width: 34, height: 42)); o.flush() }
        XCTAssertLessThanOrEqual(t.debugRoots.count, TunnelFx.pool, "trần vòng")
        for r in t.debugRoots { XCTAssertTrue(o.bounds.insetBy(dx: -1, dy: -1).contains(r.position), "\(r.position)") }
        XCTAssertTrue(t.debugRoots.allSatisfy { $0.opacity == 0 }, "model vô hình — chỉ animation làm hiện")
        o.halt()
        XCTAssertEqual(t.debugAnimationCount, 0)
        _ = KeyEffectOverlay.install(.none, color: .red, in: host, existing: o)
        #endif
    }

    // MARK: Lơ lửng — phím thật

    private func keyboard(theme: KeyboardTheme, effect: KeyEffect, suite: String) -> (KeyboardView, () -> Void) {
        let saved = UserDefaultsProvider.shared
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        d.set(theme.rawValue, forKey: ThemeSettings.themeKey)
        d.set(effect.rawValue, forKey: KeyEffect.key)
        UserDefaultsProvider.shared = d
        let kb = KeyboardView(needsGlobe: false, inputController: nil, onKey: { _ in })
        kb.frame = CGRect(x: 0, y: 0, width: 402, height: 300)
        kb.applyAppearance(.dark, style: .dark)
        kb.layoutIfNeeded()
        return (kb, {
            kb.tearDown()
            UserDefaultsProvider.shared = saved
            d.removePersistentDomain(forName: suite)
        })
    }

    /// Theme Lạc trôi: Lơ lửng bật theo "keyMotion" (hiệu ứng là Đường hầm); CHỈ HÌNH — khung phím + điểm chạm không đổi;
    /// nghỉ ⇒ gỡ nhịp trôi, về chỗ (tự gỡ); ẩn ⇒ 0 animation. Nền gradient bg → bg2.
    @MainActor func testKeyboardFloatIsVisualOnlyAndSettles() throws {
        #if DEBUG
        let (kb, done) = keyboard(theme: .drift, effect: .tunnel, suite: "vt-drift-tests")
        defer { done() }
        let f = try XCTUnwrap(kb.keyFloat, "theme Lạc trôi ⇒ phím Lơ lửng")
        XCTAssertEqual(kb.keyEffects?.effect, .tunnel)
        let g = try XCTUnwrap(kb.debugBackgroundGradient)
        XCTAssertFalse(g.isHidden)
        XCTAssertEqual(g.colors?.count, 2)
        let keys = kb.debugAllKeyButtons().filter { !$0.isHidden }
        XCTAssertGreaterThan(keys.count, 25)
        XCTAssertEqual(f.keyViews().count, keys.count)
        let frames = keys.map { kb.convert($0.bounds, from: $0) }
        let positions = keys.map(\.layer.position)
        let probe = frames.map { CGPoint(x: $0.midX, y: $0.midY) }
        let hitsBefore = probe.map { kb.hitTest($0, with: nil) }
        var t: CFTimeInterval = 1000
        f.now = { t }
        f.poke()
        XCTAssertEqual(f.debugAnimationCount, 3 * keys.count, "x / y / xoay mỗi phím")
        let a = try XCTUnwrap(keys[0].layer.animation(forKey: KeyFloat.bobKeys[0]) as? CAKeyframeAnimation)
        XCTAssertTrue(a.isAdditive, "cộng dồn — model không đổi")
        XCTAssertEqual(a.repeatCount, .infinity)
        XCTAssertEqual(a.duration, FloatFx.params(0).px, accuracy: 1e-9)
        for v in (a.values as? [Double]) ?? [] { XCTAssertLessThanOrEqual(abs(v), FloatFx.maxOffset) }
        t += 1
        f.poke()
        XCTAssertEqual(f.debugAnimationCount, 3 * keys.count, "gõ tiếp không gắn chồng")
        kb.layoutIfNeeded()
        XCTAssertEqual(keys.map { kb.convert($0.bounds, from: $0) }, frames, "khung phím không đổi khi trôi")
        XCTAssertEqual(keys.map(\.layer.position), positions)
        XCTAssertEqual(probe.map { kb.hitTest($0, with: nil) }, hitsBefore, "chạm vẫn trúng đúng phím")
        // Chưa đủ 2 s nghỉ ⇒ vẫn trôi.
        t += 1.5; f.idleCheck()
        XCTAssertTrue(f.clock.bobbing)
        t += 0.6; f.idleCheck()
        XCTAssertFalse(f.clock.bobbing)
        XCTAssertNil(keys[0].layer.animation(forKey: KeyFloat.bobKeys[0]))
        let s = try XCTUnwrap(keys[0].layer.animation(forKey: KeyFloat.settleKey) as? CAAnimationGroup)
        XCTAssertTrue(s.isRemovedOnCompletion, "về chỗ xong tự gỡ ⇒ 0 animation")
        XCTAssertEqual(s.duration, FloatFx.settle, accuracy: 1e-9)
        let sx = try XCTUnwrap((s.animations?.first as? CAKeyframeAnimation)?.values as? [Double])
        XCTAssertEqual(sx.first ?? 0, FloatFx.bob(0, f.clock.frozen).x, accuracy: 1e-9)
        XCTAssertEqual(sx.last ?? 1, 0, accuracy: 1e-12, "về đúng chỗ")
        f.halt()
        XCTAssertEqual(f.debugAnimationCount, 0)
        #endif
    }

    /// Theme khác / hiệu ứng khác ⇒ không có Lơ lửng; hiệu ứng "float" ở theme thường ⇒ có.
    @MainActor func testKeyFloatOnlyWhenChosen() {
        do { let (kb, done) = keyboard(theme: .nightclub, effect: .dancefloor, suite: "vt-drift-a"); XCTAssertNil(kb.keyFloat); done() }
        do { let (kb, done) = keyboard(theme: .mint, effect: .tunnel, suite: "vt-drift-b"); XCTAssertNil(kb.keyFloat); done() }
        do { let (kb, done) = keyboard(theme: .mint, effect: .float, suite: "vt-drift-c"); XCTAssertNotNil(kb.keyFloat); done() }
        #if DEBUG
        do {
            let (kb, done) = keyboard(theme: .nightclub, effect: .dancefloor, suite: "vt-drift-d")
            XCTAssertTrue(kb.debugBackgroundGradient?.isHidden ?? true, "không bg2 ⇒ nền phẳng")
            done()
        }
        #endif
    }

    /// Phil 11/2026: Giảm chuyển động KHÔNG tắt hiệu ứng / hoạt ảnh theme nào. Không có cách bật Giảm chuyển động của hệ
    /// thống trong test ⇒ chốt bằng nguồn: mã bàn phím (Keyboard/ + Shared/) không đọc cờ Giảm chuyển động ở đâu cả, và
    /// hiệu ứng vẫn chạy (Lơ lửng trôi, Đường hầm có vòng) — chạy được cả khi máy test bật Giảm chuyển động.
    @MainActor func testReduceMotionNeverGatesEffects() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        var scanned = 0
        for dir in ["Keyboard", "Shared"] {
            let urls = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent(dir), includingPropertiesForKeys: nil)
            for u in urls where u.pathExtension == "swift" {
                let src = try String(contentsOf: u, encoding: .utf8)
                scanned += 1
                XCTAssertFalse(src.contains("isReduceMotionEnabled"), "\(u.lastPathComponent) đọc Giảm chuyển động")
                XCTAssertFalse(src.contains("accessibilityReduceMotion"), "\(u.lastPathComponent) đọc Giảm chuyển động")
            }
        }
        XCTAssertGreaterThan(scanned, 50)
        XCTAssertTrue(FloatPolicy.active(effect: .float, keyMotion: nil, plus: true, lowPower: false))
        #if DEBUG
        let (kb, done) = keyboard(theme: .drift, effect: .tunnel, suite: "vt-drift-rm")
        defer { done() }
        let f = try XCTUnwrap(kb.keyFloat, "Lơ lửng chạy bất kể Giảm chuyển động")
        f.poke()
        XCTAssertGreaterThan(f.debugAnimationCount, 0, "phím trôi")
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 300))
        let keys = UIView(frame: host.bounds); host.addSubview(keys)
        let o = try XCTUnwrap(KeyEffectOverlay.install(.tunnel, color: .systemTeal, in: host, keys: keys, existing: nil))
        o.emit(key: CGRect(x: 120, y: 200, width: 34, height: 42)); o.flush()
        XCTAssertGreaterThan(o.debugTunnel?.debugAnimationCount ?? 0, 0, "vòng Đường hầm hiện")
        o.halt()
        f.halt()
        #endif
    }

    // MARK: Theme + JSON + âm

    /// (≡ Android DriftTests.driftTheme)
    func testDriftTheme() throws {
        let t = KeyboardTheme.drift
        XCTAssertEqual(KeyboardTheme.allCases.firstIndex(of: .trippy)! + 1, KeyboardTheme.allCases.firstIndex(of: .drift)!)
        XCTAssertTrue(t.isPlus); XCTAssertTrue(t.isInteractive)
        let spec = try XCTUnwrap(t.spec)
        XCTAssertEqual(spec.nameVi, "Lạc trôi"); XCTAssertEqual(spec.nameEn, "Adrift"); XCTAssertEqual(L10n.en["Lạc trôi"], "Adrift")
        XCTAssertEqual(spec.effect, "tunnel"); XCTAssertEqual(spec.sound, "airy"); XCTAssertEqual(spec.swipe, "stardust")
        XCTAssertEqual(spec.keyMotion, "float")
        XCTAssertEqual(ThemeSettings(theme: t).effectiveKeyStyle.keyMotion, "float")
        XCTAssertNil(ThemeSettings(theme: .nightclub).effectiveKeyStyle.keyMotion)
        XCTAssertEqual(ThemePicker.interactiveOrder.last, "drift")
        XCTAssertEqual(ThemePicker.groups(KeyboardTheme.allCases).interactive.last, .drift)
        XCTAssertEqual(t.systemBackdropKey, "systemBackdropDrift")
        XCTAssertNotNil(BackupSettings.byKey["systemBackdropDrift"])
        for dark in [false, true] {
            let p = t.palette(systemDark: dark)
            XCTAssertEqual(p.background, ThemeColorCode.rgba(0xFF06_2B33))
            XCTAssertEqual(p.background2, ThemeColorCode.rgba(0xFF22_104A))
            for bg in [p.background!, p.background2!] {
                XCTAssertGreaterThanOrEqual(RGBA.contrast(p.ink, p.keyFill.over(bg)), 4.5, "chữ trên phím trong mờ — cả hai đầu gradient")
                XCTAssertGreaterThanOrEqual(RGBA.contrast(p.fnInk, p.fnFill.over(bg)), 4.5)
            }
            XCTAssertGreaterThanOrEqual(RGBA.contrast(p.accentInk, p.accent), 4.5)
        }
        // Ảnh nền / Nền theo hệ thống bỏ cả gradient.
        XCTAssertNil(ThemeSettings(theme: t).palette(systemDark: true, wallpaperActive: true).background2)
        XCTAssertNil(t.palette(systemDark: true).onSystemBackdrop(systemDark: true).background2)
        // Chép JSON giữ "keyMotion" + "bg2"; bản vá KeyStyleStore giữ "keyMotion".
        let text = try XCTUnwrap(ThemeJSONActions.copyText(.builtin(t), settings: ThemeSettings(theme: t), store: [:]))
        let back = try XCTUnwrap(ThemeSpecParser.parse(text).spec)
        XCTAssertEqual(back.keyMotion, "float")
        XCTAssertEqual(back.light.bg2, 0xFF22_104A)
        var patch = KeyStyle(); patch.keyMotion = "float"
        XCTAssertEqual(KeyStyleStore.parse(KeyStyleStore.serialize(["system": patch]))["system"]?.keyMotion, "float")
    }

    func testBg2Patch() {
        let p = KeyboardTheme.drift.palette(systemDark: false)
        var st = KeyStyle(); st.light.bg = 0xFF00_0000
        XCTAssertNil(st.applyPatch(to: p, dark: false).background2, "nền vá = nền phẳng")
        var st2 = KeyStyle(); st2.light.bg2 = 0xFF11_2233
        XCTAssertEqual(st2.applyPatch(to: p, dark: false).background2, ThemeColorCode.rgba(0xFF11_2233))
        XCTAssertNil(KeyboardTheme.nightclub.palette(systemDark: false).background2)
    }

    /// "Lơ lửng" (âm): gió + pad — nhỏ hơn Gõ gỗ, ≤ 61 ms, mềm; seed cố định; checksum chung Android (airySound).
    func testAirySound() {
        for k in KeySoundKind.allCases {
            let wood = KeySoundSynth.samples(.wood, k), a = KeySoundSynth.samples(.airy, k)
            XCTAssertLessThan(a.map(abs).max() ?? 1, wood.map(abs).max() ?? 0, "\(k)")
            XCTAssertLessThan(Double(a.count) / KeySoundSynth.sampleRate, 0.061, "\(k)")
            XCTAssertLessThan(KeySoundSynth.spectralCentroid(a), 2500, "\(k)")
        }
        XCTAssertEqual(KeySoundSynth.seed(.airy, .letter), 0x6169_7279 ^ 0x85EB_CA6B)
        for (k, want) in [(KeySoundKind.letter, 153.4349), (.delete, 120.8789), (.modifier, 125.1502)] {
            XCTAssertEqual(KeySoundSynth.samples(.airy, k).reduce(0.0) { $0 + Double(abs($1)) }, want, accuracy: 0.01, "\(k)")
        }
        XCTAssertEqual(L10n.en["Lơ lửng"], "Floating")
        XCTAssertTrue(KeySoundStyle.presets.contains(.airy))
        XCTAssertEqual(KeySoundStyle.allCases.firstIndex(of: .dream)! + 1, KeySoundStyle.allCases.firstIndex(of: .airy)!)
    }

    /// Ảnh cho chủ dự án — chỉ khi có VT_THEME_SNAPSHOT_DIR. layer.render bỏ animation ⇒ vòng đường hầm + dời phím vẽ lại
    /// bằng Core Graphics theo CÙNG hàm thuần (TunnelFx, FloatFx).
    @MainActor func testWriteDriftSnapshot() throws {
        #if DEBUG
        guard let dir = ProcessInfo.processInfo.environment["VT_THEME_SNAPSHOT_DIR"] else { return }
        let suite = "vt-drift-snap"
        let saved = UserDefaultsProvider.shared
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        d.set(KeyboardTheme.drift.rawValue, forKey: ThemeSettings.themeKey)
        d.set(KeyEffect.tunnel.rawValue, forKey: KeyEffect.key)
        UserDefaultsProvider.shared = d
        defer { UserDefaultsProvider.shared = saved; d.removePersistentDomain(forName: suite) }
        let w: CGFloat = 402
        let win = UIWindow(frame: CGRect(x: 0, y: 0, width: w, height: 320))
        win.overrideUserInterfaceStyle = .dark
        win.isHidden = false
        defer { win.isHidden = true }
        let kb = KeyboardView(needsGlobe: false, inputController: nil, onKey: { _ in })
        win.addSubview(kb)
        kb.frame = win.bounds
        kb.applyAppearance(.dark, style: .dark)
        kb.setSuggestionsEnabled(true)
        kb.configureInputKind(.normal)
        kb.setNeedsLayout(); kb.layoutIfNeeded()
        kb.showSuggestions(.init(nextWords: ["lạc", "trôi", "giữa"]))
        let h = kb.systemLayoutSizeFitting(CGSize(width: w, height: 0)).height
        win.frame.size.height = max(h, 200); kb.frame = win.bounds
        win.layoutIfNeeded(); kb.layoutIfNeeded()
        let keys = kb.debugAllKeyButtons().filter { !$0.isHidden }
        let target = keys.first { $0.currentTitle == "h" } ?? keys[keys.count / 2]
        let tk = kb.convert(target.bounds, from: target)
        let shot = UIGraphicsImageRenderer(bounds: kb.bounds).image { c in
            let cg = c.cgContext
            // Nền + mọi thứ trừ phím (phím vẽ lại có dời hình).
            let hidden = keys.map(\.isHidden)
            for k in keys { k.isHidden = true }
            kb.layer.render(in: cg)
            for (k, hd) in zip(keys, hidden) { k.isHidden = hd }
            let tt = 1.3
            for (i, k) in keys.enumerated() {
                let o = FloatFx.bob(i, tt)
                let f = kb.convert(k.bounds, from: k)
                cg.saveGState()
                cg.translateBy(x: f.midX + o.x, y: f.midY + o.y)
                cg.rotate(by: o.rot)
                cg.translateBy(x: -f.width / 2, y: -f.height / 2)
                k.layer.render(in: cg)
                cg.restoreGState()
            }
            // Vòng đường hầm: 3 vòng ở u = 0.25 / 0.45 / 0.7 về phím "h".
            let b = kb.bounds
            let v = CGPoint(x: tk.midX, y: tk.midY)
            let wv = Double(b.width) - 2 * TunnelFx.inset, hv = Double(b.height) - 2 * TunnelFx.inset
            let cr = TunnelFx.corner(width: wv, height: hv)
            for (j, u) in [0.25, 0.45, 0.7].enumerated() {
                let s = CGFloat(TunnelFx.scale(u))
                let ctr = TunnelFx.center((Double(b.midX), Double(b.midY)), vanish: (Double(v.x), Double(v.y)), u)
                let r = CGRect(x: ctr.x - wv * Double(s) / 2, y: ctr.y - hv * Double(s) / 2, width: wv * Double(s), height: hv * Double(s))
                let col = TunnelFx.uiColor(TunnelFx.colors[j % 2])
                let path = UIBezierPath(roundedRect: r, cornerRadius: CGFloat(cr) * s)
                col.withAlphaComponent(CGFloat(TunnelFx.alpha(u) * TunnelFx.glowAlpha)).setStroke()
                path.lineWidth = CGFloat(TunnelFx.glowWidth) * s; path.stroke()
                col.withAlphaComponent(CGFloat(TunnelFx.alpha(u))).setStroke()
                path.lineWidth = CGFloat(TunnelFx.lineWidth) * s; path.stroke()
            }
        }
        let out = URL(fileURLWithPath: dir)
        try XCTUnwrap(shot.pngData()).write(to: out.appendingPathComponent("drift-theme-ios.png"))
        kb.tearDown()
        #endif
    }
}
