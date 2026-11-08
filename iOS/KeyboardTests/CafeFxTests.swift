import XCTest

/// Theme Cà phê sữa đá: viên đá lắc, giọt nước đọng, phin nhỏ giọt, sữa xoáy, cảnh ly, âm "clink". Số tham chiếu CHUNG
/// Android (CafeFxTests.kt) — đổi một bên phải đổi cả hai.
final class CafeFxTests: XCTestCase {

    func testIceJiggleAndDroplet() {
        XCTAssertEqual(CafeFx.jiggle(0), 0)
        XCTAssertEqual(CafeFx.jiggle(0.05), 0.048000, accuracy: 1e-6)
        XCTAssertEqual(CafeFx.jiggle(0.2), 0.009992, accuracy: 1e-6)
        XCTAssertEqual(CafeFx.jiggle(0.4), 0, "đứng yên sau 0,4 s")
        for i in 0...40 { XCTAssertLessThanOrEqual(abs(CafeFx.jiggle(Double(i) / 100)), CafeFx.jiggleAmp) }
        XCTAssertEqual(CafeFx.cubeAlpha(0.2), 0.45, accuracy: 1e-12)
        let d = CafeFx.droplet(0.3)
        XCTAssertEqual(d.dy, 3, accuracy: 1e-12); XCTAssertEqual(d.alpha, 0.45, accuracy: 1e-12)
        XCTAssertEqual(CafeFx.droplet(0.6).alpha, 0)
        let o = CafeFx.dropletOrigin(keyMaxX: 100, keyMaxY: 50)
        XCTAssertEqual(o.x, 94); XCTAssertEqual(o.y, 47)
    }

    func testDripTiming() {
        var c = CafeFx.DripCounter()
        XCTAssertEqual((0..<12).map { _ in c.press() }, [false, false, false, true, false, false, false, true, false, false, false, true])
        c.reset(); XCTAssertEqual(c.n, 0)
        XCTAssertEqual(CafeFx.dropY(0.15), 2, accuracy: 1e-12)
        XCTAssertEqual(CafeFx.dropY(1), CafeFx.dropFall)
        let b = CafeFx.phinBox(minX: 0, top: 0)
        XCTAssertEqual(b.x, 8); XCTAssertEqual(b.y, 3); XCTAssertEqual(b.w, 16); XCTAssertEqual(b.h, 29)
        // Phin nằm gọn trong thanh gợi ý (cao ≥ 36) kể cả khi gốc bounds dời.
        let s = CafeFx.phinBox(minX: 0, top: 40)
        XCTAssertGreaterThanOrEqual(s.y, 40); XCTAssertLessThanOrEqual(s.y + s.h, 40 + 36)
    }

    func testSwirlGateAndSpiral() {
        var g = CafeFx.SwirlGate()
        XCTAssertFalse(g.shouldSwirl(level: 1, previous: 0, now: 0))
        XCTAssertTrue(g.shouldSwirl(level: 2, previous: 1, now: 1))
        XCTAssertFalse(g.shouldSwirl(level: 3, previous: 2, now: 1.5), "chỉ lúc VỪA lên mức 2")
        XCTAssertFalse(g.shouldSwirl(level: 2, previous: 1, now: 3.4), "hồi 2,5 s")
        XCTAssertTrue(g.shouldSwirl(level: 2, previous: 0, now: 3.5))
        let sp = CafeFx.spiral()
        XCTAssertEqual(sp.count, 41)
        XCTAssertEqual(sp[0].0, 0); XCTAssertEqual(sp[0].1, 0)
        XCTAssertEqual(sp[40].0, 0, accuracy: 1e-9); XCTAssertEqual(sp[40].1, -22, accuracy: 1e-9)
        for p in sp { XCTAssertLessThanOrEqual(hypot(p.0, p.1), CafeFx.swirlRadius + 1e-9) }
        let c = CafeFx.swirlCenter(midX: 195, bottom: 260)
        XCTAssertEqual(c.x, 195); XCTAssertEqual(c.y, 232)
        XCTAssertLessThanOrEqual(c.y + CafeFx.swirlRadius + CafeFx.swirlWidth, 260, "xoáy trong bàn phím")
        XCTAssertEqual(CafeFx.swirlAlpha(1.0), 0.425, accuracy: 1e-9)
        XCTAssertEqual(CafeFx.swirlAlpha(0.5), 0.85)
    }

    func testCafeScene() {
        XCTAssertTrue(ThemeScene.isScene(.cafe))
        XCTAssertEqual(ThemeScene.gradient(.cafe, dark: false), [0xEAD7B8, 0xC9A27E, 0x6B4430])
        XCTAssertEqual(ThemeScene.gradient(.cafe, dark: true), [0x1A0F09, 0x3A271C, 0x4A3426])
        let dots = CafeScene.dots(width: 390, height: 260)
        XCTAssertEqual(dots.count, 24)
        XCTAssertEqual(dots[0].x, 219.95663, accuracy: 1e-4); XCTAssertEqual(dots[0].y, 103.28112, accuracy: 1e-4)
        XCTAssertEqual(dots.reduce(0) { $0 + $1.x + $1.y + $1.r }, 7238.7733, accuracy: 1e-2)
        for d in dots { XCTAssertTrue(d.x - d.r >= 0 && d.x + d.r <= 390 && d.y - d.r >= 0 && d.y + d.r <= 260) }
        let layer = ThemeSceneLayer()
        layer.update(motif: .cafe, color: RGBA(hex: 0xFFFFFF, alpha: 0.25), dark: false, size: CGSize(width: 390, height: 260))
        XCTAssertEqual(layer.debugLayerCount, 2, "gradient + giọt đọng")
    }

    func testClinkSound() {
        XCTAssertTrue(KeySoundStyle.presets.contains(.clink))
        XCTAssertEqual(KeySoundSynth.seed(.clink, .letter), 0x636C_696E ^ 0x85EB_CA6B)
        let golden: [(KeySoundKind, Double)] = [(.letter, 102.6325), (.delete, 114.7269), (.modifier, 124.6305)]
        for (k, want) in golden {
            XCTAssertEqual(KeySoundSynth.samples(.clink, k).reduce(0.0) { $0 + Double(abs($1)) }, want, accuracy: 0.01, "\(k)")
        }
        let c = KeySoundSynth.samples(.clink, .letter)
        XCTAssertGreaterThan(KeySoundSynth.spectralCentroid(c), 1200, "sáng như thuỷ tinh")
        XCTAssertLessThan(KeySoundSynth.spectralCentroid(c), 2500, "nhưng không chói")
        XCTAssertLessThan(c.map(abs).max() ?? 1, KeySoundSynth.samples(.wood, .letter).map(abs).max() ?? 0)
        XCTAssertEqual(L10n.en["Đá lanh canh"], "Ice clink")
    }

    @MainActor func testRendererInsideShiftedBounds() throws {
        KeyEffectOverlay.drawsOffscreen = true
        defer { KeyEffectOverlay.drawsOffscreen = false }
        for originY in [0.0, 40.0] {
            let host = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 260))
            host.bounds.origin = CGPoint(x: 0, y: originY)
            let o = try XCTUnwrap(KeyEffectOverlay.install(.ice, color: .brown, in: host, existing: nil))
            let fx = try XCTUnwrap(o.debugThemeFx as? IceRenderer)
            o.layoutSubviews()
            let phin = try XCTUnwrap(fx.debugPhin)
            XCTAssertTrue(host.bounds.contains(phin.frame), "phin trong bàn phím (gốc dời)")
            let key = CGRect(x: 100, y: originY + 120, width: 35, height: 42)
            for i in 0..<4 {
                o.emit(key: key); o.flush()
                XCTAssertEqual(fx.debugCoffeeDropAnimating, i == 3, "mỗi 4 phím một giọt")
            }
            XCTAssertEqual(fx.debugCubes.count, 4)
            for c in fx.debugCubes { XCTAssertEqual(c.position, CGPoint(x: key.midX, y: key.midY)) }
            for _ in 0..<CafeFx.pool * 3 { o.emit(key: key); o.flush() }
            XCTAssertEqual(fx.debugCubes.count, CafeFx.pool, "pool dùng lại")
            // Gõ dồn ⇒ một vòng sữa xoáy, trong bàn phím.
            let swirl = try XCTUnwrap(fx.debugSwirl)
            let box = try XCTUnwrap(swirl.path?.boundingBoxOfPath).offsetBy(dx: swirl.position.x, dy: swirl.position.y)
            XCTAssertTrue(host.bounds.contains(box), "vòng sữa trong bàn phím: \(box)")
            o.configure(effect: .heart, color: .red)
            XCTAssertNil(o.debugThemeFx)
            XCTAssertNil(phin.superlayer, "đổi kiểu ⇒ gỡ phin")
        }
    }

    func testCafeTheme() throws {
        let t = KeyboardTheme.cafe
        let spec = try XCTUnwrap(t.spec)
        XCTAssertTrue(t.isPlus); XCTAssertTrue(t.isInteractive)
        XCTAssertEqual(spec.nameVi, "Cà phê sữa đá"); XCTAssertEqual(spec.nameEn, "Iced Coffee")
        XCTAssertEqual(L10n.en[t.title], "Iced Coffee")
        XCTAssertEqual(spec.sound, "clink"); XCTAssertEqual(spec.effect, "ice")
        XCTAssertEqual(t.systemBackdropKey, "systemBackdropCafe")
        XCTAssertNotNil(BackupSettings.byKey["systemBackdropCafe"])
        XCTAssertTrue(ThemeSpecParser.contrastIssues(spec).isEmpty)
        XCTAssertEqual(L10n.en["Đá lanh canh"], "Ice clink")
        XCTAssertEqual({ let o = ThemePicker.interactiveOrder; let i = o.firstIndex(of: "football") ?? 0; return Array(o[i..<min(i + 3, o.count)]) }(), ["football", "aquarium", "cafe"])
        for dark in [false, true] {
            let p = t.palette(systemDark: dark)
            XCTAssertEqual(p.decoration?.motif, .cafe)
            // Phím đá trong mờ: chữ ≥ 4.5 trên mọi điểm gradient cà phê → sữa.
            for s in ThemeScene.gradient(.cafe, dark: dark) {
                XCTAssertGreaterThanOrEqual(RGBA.contrast(p.ink, p.keyFill.over(RGBA(hex: s))), 4.5, "\(dark) \(String(s, radix: 16))")
                XCTAssertGreaterThanOrEqual(RGBA.contrast(p.fnInk, p.fnFill.over(RGBA(hex: s))), 4.5)
            }
            XCTAssertGreaterThanOrEqual(RGBA.contrast(p.accentInk, p.accent.over(try XCTUnwrap(p.background))), 4.5)
        }
    }
}
