import XCTest

/// Theme Bóng đá: cụm cổ vũ, cú sút, túm cỏ, pháo + cờ, sân cỏ, âm "thump" + hò reo. Số tham chiếu CHUNG Android
/// (FootballFxTests.kt) — đổi một bên phải đổi cả hai.
final class FootballFxTests: XCTestCase {

    // MARK: cụm cổ vũ

    /// Gõ `text` (tách theo dấu cách; mảnh toàn "#"/số gõ từng ký hiệu) — true nếu ranh giới CUỐI bắn cụm cổ vũ.
    static func cheers(_ text: String) -> Bool {
        var m = CheerWords.Matcher()
        var hit = false
        for w in text.split(separator: " ").map(String.init) {
            if CheerWords.Matcher.isGlue(w) {
                for c in w { _ = m.feed(word: "", symbol: String(c)) }
                hit = m.feed(word: "", end: true)
            } else {
                hit = m.feed(word: w, end: true)
            }
        }
        return hit
    }

    static let yes = ["Việt Nam vô địch", "VN vô địch", "VNVĐ", "vnvd", "vnvđ", "VN number 1", "VN #1", "VN # 1", "Việt Nam số 1",
                      "VN số 1", "Việt Nam number one", "Việt Nam #1", "vô địch", "vào", "goal", "GOAL", "gooool", "vàoooo",
                      "VÀOOO", "goooal", "đi vào", "vô địch!", "Vào!!!"]
    static let no = ["vao", "vo dich", "vô", "địch", "vàobờ", "vn", "việt nam", "number one", "#1", "goals", "số 1", "vào nhà",
                     "vnvđx", "gool", "Việt Nam số 2", "VN #10", "vô đich", ""]

    func testCheerTable() {
        XCTAssertEqual(CheerWords.phrases, ["việt nam vô địch", "vô địch", "vnvđ", "vn #1", "vào", "goal", "gol"])
        XCTAssertEqual(CheerWords.table, [["vn", "vô", "địch"], ["vô", "địch"], ["vnvđ"], ["vn", "#1"], ["vào"], ["goal"], ["gol"]])
        for s in Self.yes { XCTAssertTrue(Self.cheers(s), s) }
        for s in Self.no { XCTAssertFalse(Self.cheers(s), s) }
        XCTAssertEqual(Self.yes.count, 23); XCTAssertEqual(Self.no.count, 18)
    }

    func testCheerNormalize() {
        XCTAssertEqual(CheerWords.token("Vàoooo!"), "vào")
        XCTAssertEqual(CheerWords.token("GOOOOL"), "gol")
        XCTAssertEqual(CheerWords.token("vàôoo"), "vào", "chuỗi lặp lẫn dấu ⇒ chữ gốc")
        XCTAssertEqual(CheerWords.token("…VNVĐ…"), "vnvđ")
        XCTAssertEqual(CheerWords.token("good"), "good", "lặp 2 lần giữ nguyên")
        XCTAssertEqual(CheerWords.token("#1"), "#1")
        XCTAssertEqual(CheerWords.token("!!"), "")
        XCTAssertEqual(CheerWords.token("Vie\u{0302}\u{0323}t"), "việt", "NFC")
        XCTAssertEqual(CheerWords.canonical(["việt", "nam", "number", "one"]), ["vn", "#1"])
        XCTAssertEqual(CheerWords.canonical(["vn", "số", "một"]), ["vn", "#1"])
        XCTAssertEqual(CheerWords.canonical(["vnvd"]), ["vnvđ"])
        XCTAssertEqual(CheerWords.base("ộ"), "o"); XCTAssertEqual(CheerWords.base("đ"), "đ")
    }

    func testMatcherFiresOnceAndKeepsSixTokens() {
        var m = CheerWords.Matcher()
        XCTAssertTrue(m.feed(word: "vào", end: true))
        XCTAssertFalse(m.feed(word: "", end: true), "một cụm bắn một lần")
        for w in ["a", "b", "c", "d", "e", "f", "g", "h"] { _ = m.feed(word: w, end: true) }
        XCTAssertEqual(m.tokens.count, CheerWords.maxTokens)
        // "#" rồi "1" là ký hiệu riêng: chưa so tới ranh giới; dấu câu = ranh giới.
        var n = CheerWords.Matcher()
        _ = n.feed(word: "VN", end: true)
        XCTAssertFalse(n.feed(word: "", symbol: "#"))
        XCTAssertFalse(n.feed(word: "", symbol: "1"))
        XCTAssertTrue(n.feed(word: "", symbol: "!"))
        var r = CheerWords.Matcher()
        _ = r.feed(word: "vô", end: true); r.reset()
        XCTAssertFalse(r.feed(word: "địch", end: true), "dời con trỏ ⇒ quên")
    }

    // MARK: cú sút

    func testGoalGeometry() {
        let n = GoalFx.net(minX: 0, width: 390, top: 0)
        XCTAssertEqual(n, GoalFx.Rect(x: 167, y: 4, w: 56, h: 24))
        let e = GoalFx.target(n)
        XCTAssertEqual(e.x, 195); XCTAssertEqual(e.y, 17.2, accuracy: 1e-9)
        let s = GoalFx.Pt(x: 340, y: 229)
        let c = GoalFx.control(start: s, end: e, top: 0)
        XCTAssertEqual(c, GoalFx.Pt(x: 267.5, y: 8), "điểm điều khiển kẹp ≥ top + bán kính + 1")
        let mid = GoalFx.ball(0.5, start: s, control: c, end: e)
        XCTAssertEqual(mid.x, 267.5, accuracy: 1e-9); XCTAssertEqual(mid.y, 65.55, accuracy: 1e-9)
        XCTAssertEqual(GoalFx.ball(0, start: s, control: c, end: e), s)
        XCTAssertEqual(GoalFx.ball(1, start: s, control: c, end: e), e)
        XCTAssertEqual(GoalFx.life, 1.5, accuracy: 1e-12)
        XCTAssertEqual(GoalFx.ballScale(1), 0.72, accuracy: 1e-12)
        XCTAssertEqual(GoalFx.ballSpin(0.5), 2 * Double.pi, accuracy: 1e-12)
        XCTAssertEqual(GoalFx.netRipple(0.1), 0.096853, accuracy: 1e-6)
        XCTAssertEqual(GoalFx.netRipple(0.25), -0.037086, accuracy: 1e-6)
        XCTAssertEqual(GoalFx.netRipple(0), 0); XCTAssertEqual(GoalFx.netRipple(0.6), 0)
        XCTAssertEqual(GoalFx.netAlpha(0.06), 0.5, accuracy: 1e-12)
        XCTAssertEqual(GoalFx.netAlpha(1.35), 0.5, accuracy: 1e-9)
        XCTAssertEqual(GoalFx.textScale(0.06), 0.8, accuracy: 1e-12)
        XCTAssertEqual(GoalFx.textScale(0.17), 1.1, accuracy: 1e-12)
        XCTAssertEqual(GoalFx.textScale(0.5), 1)
        XCTAssertEqual(GoalFx.textAlpha(0.75), 0.6, accuracy: 1e-9)
        let m = GoalFx.meshLines(n)
        XCTAssertEqual(m.xs, [6, 12, 18, 24, 30, 36, 42, 48, 54]); XCTAssertEqual(m.ys, [6, 12, 18])
    }

    /// Cả cung bay (± bán kính bóng), khung thành và chữ nằm trong bàn phím — mọi cỡ, kể cả gốc bounds dời (#151).
    func testGoalArcInsideBounds() {
        for (w, h) in [(320.0, 216.0), (390.0, 260.0), (744.0, 300.0), (1024.0, 340.0)] {
            for top in [0.0, 40.0] {
                let n = GoalFx.net(minX: 0, width: w, top: top)
                for kx in [w - 50, 30, w / 2] {
                    let s = GoalFx.Pt(x: kx, y: top + h - 30)
                    let e = GoalFx.target(n)
                    let c = GoalFx.control(start: s, end: e, top: top)
                    for i in 0...100 {
                        let p = GoalFx.ball(Double(i) / 100, start: s, control: c, end: e)
                        let r = GoalFx.ballRadius
                        XCTAssertGreaterThanOrEqual(p.y - r, top, "\(w)×\(h) top \(top)")
                        XCTAssertLessThanOrEqual(p.y + r, top + h)
                        XCTAssertGreaterThanOrEqual(p.x - r, 0); XCTAssertLessThanOrEqual(p.x + r, w)
                    }
                }
                XCTAssertGreaterThanOrEqual(n.y, top); XCTAssertLessThanOrEqual(n.x + n.w, w)
                let tc = GoalFx.textCenter(n)
                XCTAssertGreaterThanOrEqual(tc.x - GoalFx.textWidth / 2, 0)
                XCTAssertLessThanOrEqual(tc.y + GoalFx.textHeight / 2, top + h)
            }
        }
    }

    func testGrassTuftAndCheerBurst() {
        XCTAssertEqual(GrassTuft.scaleY(0.06), 0.5, accuracy: 1e-12)
        XCTAssertEqual(GrassTuft.alpha(0.22), 0.45, accuracy: 1e-9)
        XCTAssertEqual(GrassTuft.alpha(0.32), 0)
        XCTAssertEqual(GrassTuft.origin(keyMidX: 20, keyMaxY: 100), GoalFx.Pt(x: 20, y: 98))
        let f = CheerBurst.flags(minX: 0, top: 0, width: 390, height: 260)
        XCTAssertEqual(f.count, 14)
        XCTAssertEqual(f[0].x0, 24.0689, accuracy: 1e-3); XCTAssertEqual(f[0].y0, 8.5943, accuracy: 1e-3)
        XCTAssertEqual(f[0].dy, 167.2729, accuracy: 1e-3); XCTAssertEqual(f[0].delay, 0.2374, accuracy: 1e-3)
        XCTAssertEqual(f.reduce(0) { $0 + $1.x0 + $1.y0 + $1.dx + $1.dy + $1.rot + $1.delay }, 5075.5321, accuracy: 1e-2)
        for top in [0.0, 40.0] {
            for g in CheerBurst.flags(minX: 0, top: top, width: 390, height: 260) {
                XCTAssertGreaterThanOrEqual(g.y0, top); XCTAssertLessThanOrEqual(g.y0 + g.dy, top + 260 - CheerBurst.margin + 1e-9)
                XCTAssertGreaterThan(g.x0, 0); XCTAssertLessThan(g.x0, 390)
                XCTAssertEqual(g.delay + g.dur, CheerBurst.duration, accuracy: 1e-12)
            }
        }
        XCTAssertEqual(CheerBurst.flags(minX: 0, top: 40, width: 390, height: 260).reduce(0) { $0 + $1.x0 + $1.y0 + $1.dx + $1.dy + $1.rot + $1.delay },
                       5635.5321, accuracy: 1e-2)
        XCTAssertEqual(CheerBurst.flares(minX: 0, top: 0, width: 390, height: 260), [GoalFx.Pt(x: 39, y: 250), GoalFx.Pt(x: 351, y: 250)])
        XCTAssertEqual(CheerBurst.flareAlpha(0.05), 0.5, accuracy: 1e-12)
        // Không chớp: giữa đời pháo ở 0,75…1 và thay đổi chậm (≤ 3 Hz).
        for i in 10...89 {
            let a = CheerBurst.flareAlpha(Double(i) / 100)
            XCTAssertGreaterThanOrEqual(a, 0.75 - 1e-9); XCTAssertLessThanOrEqual(a, 1 + 1e-9)
        }
        let sp = CheerBurst.spark(4)
        XCTAssertEqual(sp.dx, 14); XCTAssertEqual(sp.dy, -32); XCTAssertEqual(sp.delay, 0.28, accuracy: 1e-12)
        XCTAssertEqual(CheerBurst.red, 0xDA251D); XCTAssertEqual(CheerBurst.yellow, 0xFFFF00)
        let star = CheerBurst.star()
        XCTAssertEqual(star.count, 10, "sao 5 cánh")
        XCTAssertEqual(star[0].x, 0, accuracy: 1e-12); XCTAssertEqual(star[0].y, -2.6, accuracy: 1e-12)
        XCTAssertEqual(star[1].x, 0.583788, accuracy: 1e-5); XCTAssertEqual(star[1].y, -0.803516, accuracy: 1e-5)
    }

    func testPitchScene() {
        let st = PitchScene.stripes(width: 390, height: 260)
        XCTAssertEqual(st.map(\.x), [39, 117, 195, 273, 351]); XCTAssertEqual(st.last?.w, 39)
        XCTAssertEqual(PitchScene.stripeWidth(200), 28)
        let ls = PitchScene.lines(width: 390, height: 260)
        XCTAssertEqual(ls.count, 7)
        XCTAssertEqual(ls[2], .circle(cx: 195, cy: 130, r: 40))
        if case let .rect(x, y, w, h) = ls[3] {
            XCTAssertEqual(x, 5); XCTAssertEqual(y, 65); XCTAssertEqual(w, 46.8, accuracy: 1e-9); XCTAssertEqual(h, 130)
        } else { XCTFail("vòng cấm trái") }
        for p in ls {
            switch p {
            case let .rect(x, y, w, h): XCTAssertTrue(x >= 0 && y >= 0 && x + w <= 390 + 1e-9 && y + h <= 260 + 1e-9)
            case let .circle(cx, cy, r): XCTAssertTrue(cx - r >= 0 && cy - r >= 0 && cx + r <= 390 && cy + r <= 260)
            case let .line(x0, y0, x1, y1): XCTAssertTrue(min(x0, x1) >= 0 && min(y0, y1) >= 0 && max(x0, x1) <= 390 && max(y0, y1) <= 260)
            }
        }
        XCTAssertTrue(PitchScene.lines(width: 10, height: 10).isEmpty)
        XCTAssertTrue(ThemeScene.isScene(.pitch)); XCTAssertFalse(ThemeScene.isScene(.waves))
        XCTAssertTrue(KeyboardDecoration.shape(.pitch).isEmpty, "cảnh không có hình motif nhỏ")
        let layer = ThemeSceneLayer()
        layer.update(motif: .pitch, color: RGBA(hex: 0xFFFFFF, alpha: 0.3), dark: false, size: CGSize(width: 390, height: 260))
        XCTAssertEqual(layer.debugLayerCount, 3, "sọc + vạch + chấm giữa")
        layer.update(motif: .pitch, color: RGBA(hex: 0xFFFFFF, alpha: 0.3), dark: false, size: CGSize(width: 390, height: 260))
        XCTAssertEqual(layer.debugLayerCount, 3, "cùng chữ ký ⇒ không dựng lại")
    }

    // MARK: âm

    func testThumpAndCheerSounds() {
        XCTAssertTrue(KeySoundStyle.presets.contains(.thump))
        XCTAssertEqual(KeySoundSynth.seed(.thump, .letter), 0x7468_756D ^ 0x85EB_CA6B)
        let golden: [(KeySoundKind, Double)] = [(.letter, 269.4209), (.delete, 250.6433), (.modifier, 308.7933)]
        for (k, want) in golden {
            XCTAssertEqual(KeySoundSynth.samples(.thump, k).reduce(0.0) { $0 + Double(abs($1)) }, want, accuracy: 0.01, "\(k)")
        }
        let wood = KeySoundSynth.samples(.wood, .letter), th = KeySoundSynth.samples(.thump, .letter)
        XCTAssertLessThan(th.map(abs).max() ?? 1, wood.map(abs).max() ?? 0, "không to hơn Gõ gỗ")
        XCTAssertLessThan(KeySoundSynth.spectralCentroid(th), 1200, "bụp trầm")
        XCTAssertEqual(L10n.en["Bóng bụp"], "Ball thump")

        let c = KeySoundSynth.cheerSamples()
        XCTAssertEqual(c.count, 20948)
        XCTAssertEqual(c.reduce(0.0) { $0 + Double(abs($1)) }, 904.6467, accuracy: 0.05)
        XCTAssertEqual(Double(c.map(abs).max() ?? 0), KeySoundSynth.cheerPeak, accuracy: 1e-4)
        XCTAssertEqual(c.first ?? 1, 0, accuracy: 1e-6); XCTAssertEqual(c.last ?? 1, 0, accuracy: 1e-6)
        XCTAssertLessThan(KeySoundSynth.spectralCentroid(Array(c[6615..<11025]), sampleRate: KeySoundSynth.surfSampleRate), 2500,
                          "mềm (đoạn 0,3…0,5 s)")
        // Dâng: 0,1 s đầu nhỏ hơn hẳn đoạn 0,35…0,55 s.
        func rms(_ a: Double, _ b: Double) -> Double {
            KeySoundSynth.rms(Array(c[Int(a * KeySoundSynth.surfSampleRate)..<Int(b * KeySoundSynth.surfSampleRate)]))
        }
        XCTAssertLessThan(rms(0, 0.1), rms(0.35, 0.55) * 0.5)
        XCTAssertEqual(FxEventSound.cheer.samples(), c)
        XCTAssertEqual(FxEventSound.surf.samples(), KeySoundSynth.surfSamples())
    }

    /// Hò reo chỉ khi Âm thanh phím bật (đường riêng).
    @MainActor func testCheerRespectsKeySoundSwitch() {
        let saved = KeyboardView.customSoundEnabled
        defer { KeyboardView.customSoundEnabled = saved }
        let n0 = KeyboardView.debugCheers
        KeyboardView.customSoundEnabled = false
        KeyboardView.goalCheer()
        XCTAssertEqual(KeyboardView.debugCheers, n0)
        KeyboardView.customSoundEnabled = true
        KeyboardView.goalCheer()
        XCTAssertEqual(KeyboardView.debugCheers, n0 + 1)
        XCTAssertTrue(KeyboardView.isReturnKey(.newline)); XCTAssertTrue(KeyboardView.isReturnKey(.lineBreak))
        XCTAssertFalse(KeyboardView.isReturnKey(.space))
    }

    // MARK: overlay

    @MainActor func testOverlayShotTuftCheerInsideShiftedBounds() throws {
        KeyEffectOverlay.drawsOffscreen = true
        defer { KeyEffectOverlay.drawsOffscreen = false }
        for originY in [0.0, 40.0] {
            let host = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 260))
            host.bounds.origin = CGPoint(x: 0, y: originY)
            let o = try XCTUnwrap(KeyEffectOverlay.install(.goal, color: .systemRed, in: host, existing: nil))
            var events = 0
            o.onThemeEvent = { events += 1 }
            XCTAssertEqual(o.bounds, host.bounds, "chung hệ toạ độ với host")
            let fx = try XCTUnwrap(o.debugThemeFx as? GoalRenderer)
            let ret = CGRect(x: 300, y: originY + 210, width: 80, height: 42)
            o.emit(key: ret, isReturn: true); o.flush()
            XCTAssertEqual(fx.debugShotRoots.count, 1)
            XCTAssertEqual(events, 1, "mỗi cú sút một tiếng hò reo")
            let path = try XCTUnwrap(fx.debugBallPaths.first)
            let box = path.boundingBoxOfPath.insetBy(dx: -CGFloat(GoalFx.ballRadius), dy: -CGFloat(GoalFx.ballRadius))
            XCTAssertTrue(host.bounds.contains(box), "cung bay trong bàn phím: \(box) ⊄ \(host.bounds)")
            o.emit(key: CGRect(x: 10, y: originY + 120, width: 35, height: 42)); o.flush()
            XCTAssertEqual(fx.debugShotRoots.count, 1, "phím thường không sút")
            XCTAssertEqual(fx.debugTufts.count, 1)
            XCTAssertEqual(events, 1)
            o.queueCheer()
            o.emit(key: CGRect(x: 10, y: originY + 170, width: 35, height: 42)); o.flush()
            let root = try XCTUnwrap(fx.debugCheerRoot)
            XCTAssertEqual(fx.debugCheerFlags.count, CheerBurst.flagCount)
            for l in fx.debugCheerFlags {
                XCTAssertTrue(root.bounds.contains(l.position), "cờ trong bàn phím")
                XCTAssertNotNil(l.animation(forKey: "fx"))
            }
            XCTAssertEqual(root.bounds, host.bounds)
            // 50 Enter liền: pool 2 cú sút, không mọc thêm.
            for _ in 0..<50 { o.emit(key: ret, isReturn: true); o.flush() }
            XCTAssertEqual(fx.debugShotRoots.count, GoalFx.pool)
            o.halt()
            o.configure(effect: .heart, color: .red)
            XCTAssertNil(o.debugThemeFx, "đổi kiểu ⇒ bỏ bộ vẽ")
            XCTAssertNil(root.superlayer, "gỡ sạch layer khi đổi kiểu")
            XCTAssertNil(KeyEffectOverlay.install(.none, color: .red, in: host, existing: o))
        }
    }

    /// Kiểu khác: không có bộ vẽ theme (0 chi phí); queueCheer bị bỏ qua.
    @MainActor func testOtherEffectsHaveNoThemeRenderer() {
        let o = KeyEffectOverlay(effect: .heart, color: .systemPink)
        XCTAssertNil(o.debugThemeFx)
        o.queueCheer()
        XCTAssertEqual(o.debugPendingCount, 0)
        XCTAssertTrue(ThemeFxFactory.effects.contains(.goal)); XCTAssertFalse(ThemeFxFactory.handles(.heart))
        XCTAssertTrue(KeyEffectOverlay.clipped.contains(.goal))
        XCTAssertEqual(L10n.en["Sút!"], "Kick!")
    }

    // MARK: theme

    func testFootballTheme() throws {
        let t = KeyboardTheme.football
        let spec = try XCTUnwrap(t.spec)
        XCTAssertTrue(t.isPlus); XCTAssertTrue(t.isInteractive)
        XCTAssertEqual(spec.nameVi, "Bóng đá"); XCTAssertEqual(spec.nameEn, "Football")
        XCTAssertEqual(L10n.en[t.title], "Football")
        XCTAssertEqual(spec.sound, "thump"); XCTAssertEqual(spec.effect, "goal")
        XCTAssertEqual(t.systemBackdropKey, "systemBackdropFootball")
        XCTAssertNotNil(BackupSettings.byKey["systemBackdropFootball"])
        XCTAssertTrue(ThemeSpecParser.contrastIssues(spec).isEmpty)
        XCTAssertEqual(ThemePicker.interactiveOrder.firstIndex(of: "football"), ThemePicker.interactiveOrder.firstIndex(of: "stainedGlass").map { $0 + 1 })
        for dark in [false, true] {
            let p = t.palette(systemDark: dark)
            let bg = try XCTUnwrap(p.background)
            XCTAssertEqual(p.decoration?.motif, .pitch)
            XCTAssertTrue(p.decoration?.isScene ?? false)
            XCTAssertGreaterThanOrEqual(RGBA.contrast(p.ink, p.keyFill.over(bg)), 4.5, "chữ / phím \(dark)")
            XCTAssertGreaterThanOrEqual(RGBA.contrast(p.fnInk, p.fnFill.over(bg)), 4.5, "phím chức năng \(dark)")
            XCTAssertGreaterThanOrEqual(RGBA.contrast(p.accentInk, p.accent.over(bg)), 4.5, "nhấn \(dark)")
        }
    }
}
