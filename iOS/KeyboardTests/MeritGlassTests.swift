import XCTest

/// Theme "Gõ mõ" (Công đức, âm Mõ gỗ) + "Kính màu" (Nắng qua kính, âm Chuông nhỏ, dáng phím "glass"). Số tham chiếu CHUNG
/// Android (keyboard/src/test/.../MeritGlassTests.kt).
final class MeritGlassTests: XCTestCase {
    override func setUp() {
        super.setUp()
        KeyEffectOverlay.drawsOffscreen = true
    }
    override func tearDown() {
        KeyEffectOverlay.drawsOffscreen = false
        super.tearDown()
    }

    // MARK: id

    func testNewIdsAppendedAndShared() {
        XCTAssertEqual(Array(KeyEffect.allCases.map(\.rawValue).suffix(2)), ["merit", "sunlight"])
        XCTAssertEqual(Array(KeySoundStyle.allCases.map(\.rawValue).suffix(2)), ["mo", "bell"])
        XCTAssertTrue(KeySoundStyle.presetIDs.contains("mo") && KeySoundStyle.presetIDs.contains("bell"))
        XCTAssertTrue(KeyboardTheme.allCases.contains(.mo) && KeyboardTheme.allCases.contains(.stainedGlass))
        XCTAssertEqual(KeyboardTheme.mo.rawValue, "mo")
        XCTAssertEqual(KeyboardTheme.stainedGlass.rawValue, "stainedGlass")
        XCTAssertTrue(KeyEffect.merit.isPlus && KeyEffect.sunlight.isPlus)
        XCTAssertFalse(KeyEffect.merit.isQueued || KeyEffect.sunlight.isQueued)
        XCTAssertTrue(KeyEffectOverlay.clipped.contains(.merit) && KeyEffectOverlay.clipped.contains(.sunlight))
        XCTAssertTrue(ThemeExtraIds.keyShapes.contains("glass"))
        for s in ["Gõ mõ", "Kính màu", "Mõ gỗ", "Chuông nhỏ", "Công đức", "Nắng qua kính", "+1 công đức", "Công đức hôm nay"] {
            XCTAssertNotNil(L10n.en[s], s)
        }
        XCTAssertEqual(L10n.en["+1 công đức"], "+1 merit")
    }

    func testThemesWired() throws {
        let mo = try XCTUnwrap(KeyboardTheme.mo.spec), sg = try XCTUnwrap(KeyboardTheme.stainedGlass.spec)
        XCTAssertEqual(mo.sound, "mo"); XCTAssertEqual(mo.effect, "merit")
        XCTAssertEqual(sg.sound, "bell"); XCTAssertEqual(sg.effect, "sunlight"); XCTAssertEqual(sg.keyShape, "glass")
        XCTAssertTrue(KeyboardTheme.mo.isPlus && KeyboardTheme.stainedGlass.isPlus)
        XCTAssertTrue(KeyboardTheme.mo.isInteractive && KeyboardTheme.stainedGlass.isInteractive)
        XCTAssertEqual(Array(ThemePicker.interactiveOrder.suffix(2)), ["mo", "stainedGlass"])
        XCTAssertEqual(KeyboardTheme.mo.systemBackdropKey, "systemBackdropMo")
        XCTAssertEqual(KeyboardTheme.stainedGlass.systemBackdropKey, "systemBackdropStainedGlass")
        XCTAssertNotNil(BackupSettings.byKey["systemBackdropMo"])
        XCTAssertNotNil(BackupSettings.byKey["systemBackdropStainedGlass"])
        XCTAssertEqual(KeyboardTheme.mo.title, L("Gõ mõ"))
    }

    // MARK: âm

    func testMoAndBellQuietAndShared() {
        for k in KeySoundKind.allCases {
            let wood = KeySoundSynth.samples(.wood, k)
            for st in [KeySoundStyle.mo, .bell] {
                let a = KeySoundSynth.samples(st, k)
                XCTAssertLessThan(KeySoundSynth.rms(a), KeySoundSynth.rms(wood), "\(st) \(k)")
                XCTAssertLessThan(a.map(abs).max() ?? 1, wood.map(abs).max() ?? 0, "\(st) \(k)")
            }
            XCTAssertLessThan(Double(KeySoundSynth.samples(.mo, k).count) / KeySoundSynth.sampleRate, 0.13)
            XCTAssertLessThan(Double(KeySoundSynth.samples(.bell, k).count) / KeySoundSynth.sampleRate, 0.37)
        }
        XCTAssertEqual(KeySoundSynth.seed(.mo, .letter), 0x6D6F_6D6F ^ 0x85EB_CA6B)
        XCTAssertEqual(KeySoundSynth.seed(.bell, .letter), 0x6265_6C6C ^ 0x85EB_CA6B)
        for (k, want) in Self.moGolden {
            XCTAssertEqual(KeySoundSynth.samples(.mo, k).reduce(0.0) { $0 + Double(abs($1)) }, want, accuracy: 0.01, "mo \(k)")
        }
        for (k, want) in Self.bellGolden {
            XCTAssertEqual(KeySoundSynth.samples(.bell, k).reduce(0.0) { $0 + Double(abs($1)) }, want, accuracy: 0.01, "bell \(k)")
        }
        XCTAssertEqual(L10n.en["Mõ gỗ"], "Wooden fish")
        XCTAssertEqual(L10n.en["Chuông nhỏ"], "Small bell")
    }
    static let moGolden: [(KeySoundKind, Double)] = [(.letter, 311.0306), (.delete, 315.8752), (.modifier, 375.1635)]
    static let bellGolden: [(KeySoundKind, Double)] = [(.letter, 728.3445), (.delete, 722.3437), (.modifier, 830.7632)]

    // MARK: Công đức — hàm thuần

    func testMeritCurves() {
        XCTAssertEqual(MeritFx.alpha(-0.01), 0)
        XCTAssertEqual(MeritFx.alpha(0.06), 0.5, accuracy: 1e-12)
        XCTAssertEqual(MeritFx.alpha(0.3), 1)
        XCTAssertEqual(MeritFx.alpha(0.7), 0.5, accuracy: 1e-12)
        XCTAssertEqual(MeritFx.alpha(0.9), 0)
        XCTAssertEqual(MeritFx.lift(0.45), 33, accuracy: 1e-12)
        XCTAssertEqual(MeritFx.lift(2), 44)
        XCTAssertEqual([0, 1, 2, -1].map(MeritFx.drift), [-6, 0, 6, 6])
        XCTAssertEqual(MeritFx.cap, 5)
        XCTAssertEqual(MeritFx.duration, 0.9)
    }

    func testMeritOriginInsideBounds() {
        func o(_ x: Double, _ y: Double, _ b: (Double, Double, Double, Double)) -> [Double] {
            let r = MeritFx.origin(keyMidX: x, keyTop: y, bounds: b); return [r.x, r.y]
        }
        XCTAssertEqual(o(10, 5, (0, 0, 390, 260)), [63, 54])
        XCTAssertEqual(o(200, 150, (0, 0, 390, 260)), [200, 150])
        XCTAssertEqual(o(389, 250, (0, 0, 390, 260)), [327, 250])
        XCTAssertEqual(o(10, 5, (0, 40, 390, 260)), [63, 94], "gốc bounds dời (#151)")
    }

    func testMeritGroupingAndText() {
        XCTAssertEqual(MeritFx.grouped(1234, separator: "."), "1.234")
        XCTAssertEqual(MeritFx.grouped(1_234_567, separator: ","), "1,234,567")
        XCTAssertEqual(MeritFx.grouped(999, separator: "."), "999")
        XCTAssertEqual(MeritFx.grouped(0, separator: "."), "0")
        XCTAssertEqual(MeritFx.grouped(-5, separator: "."), "0")
        XCTAssertTrue(MeritFx.counterText(1234, english: false).hasSuffix(": 1.234"))
        XCTAssertTrue(MeritFx.counterText(1234, english: true).hasSuffix(": 1,234"))
    }

    func testMeritDayResetsAtLocalMidnight() {
        XCTAssertEqual(MeritCounter.dayIndex(epoch: 86_400 * 20_000 - 1, utcOffset: 0), 19_999)
        XCTAssertEqual(MeritCounter.dayIndex(epoch: 86_400 * 20_000 - 1, utcOffset: 3600), 20_000)
        let vn = 7 * 3600
        let midnight = Double(86_400 * 20_000 - vn)      // 00:00 giờ Việt Nam
        XCTAssertEqual(MeritCounter.dayIndex(epoch: midnight - 1, utcOffset: vn), 19_999)
        XCTAssertEqual(MeritCounter.dayIndex(epoch: midnight, utcOffset: vn), 20_000)
        XCTAssertEqual(MeritCounter.dayIndex(epoch: -1, utcOffset: 0), -1)
        var c = MeritCounter()
        let d0 = MeritCounter.dayIndex(epoch: midnight - 10, utcOffset: vn)
        for i in 0..<3 { _ = c.press(day: d0, at: Double(i)) }
        XCTAssertEqual(c.today(d0), 3)
        let d1 = MeritCounter.dayIndex(epoch: midnight + 1, utcOffset: vn)
        _ = c.press(day: d1, at: 3)
        XCTAssertEqual(c.today(d1), 1, "qua nửa đêm ⇒ về 0 rồi đếm")
        XCTAssertEqual(c.today(d0), 0)
    }

    func testMeritPersistThrottled() {
        var c = MeritCounter(day: 100, count: 7)
        XCTAssertTrue(c.press(day: 100, at: 0), "lần đầu ghi ngay")
        XCTAssertEqual(c.count, 8)
        XCTAssertFalse(c.press(day: 100, at: 1))
        XCTAssertFalse(c.press(day: 100, at: 4.9))
        XCTAssertTrue(c.press(day: 100, at: 5.0))
        XCTAssertFalse(c.dirty)
        XCTAssertFalse(c.press(day: 100, at: 6))
        XCTAssertTrue(c.takeDirty(), "ẩn bàn phím ⇒ ghi nốt")
        XCTAssertFalse(c.takeDirty())
        var d = MeritCounter()
        var writes = 0
        for i in 0..<100 where d.press(day: 1, at: Double(i) / 10) { writes += 1 }
        XCTAssertEqual(writes, 2, "100 phím / 10 s ⇒ chỉ 2 lần ghi")
        XCTAssertEqual(d.count, 100)
        XCTAssertEqual(MeritCounter(day: 1, count: -3).count, 0)
    }

    func testMeritStoreDefaultsRoundTrip() {
        let name = "merit-test-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        defer { d.removePersistentDomain(forName: name) }
        let st = MeritStore.defaults(d)
        XCTAssertEqual(st.load().day, Int.min)
        st.save(20_000, 1234)
        XCTAssertEqual(st.load().day, 20_000)
        XCTAssertEqual(st.load().count, 1234)
    }

    // MARK: Công đức — overlay

    @MainActor func testMeritOverlayCapsLabelsInsideShiftedBounds() throws {
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 260))
        host.bounds.origin = CGPoint(x: 0, y: 40)
        let o = try XCTUnwrap(KeyEffectOverlay.install(.merit, color: .systemOrange, in: host, existing: nil))
        XCTAssertEqual(o.bounds, host.bounds)
        XCTAssertNil(o.debugMerit, "chưa bấm ⇒ chưa dựng gì")
        let keys = [CGRect(x: 0, y: 40, width: 35, height: 42), CGRect(x: 355, y: 40, width: 35, height: 42),
                    CGRect(x: 170, y: 250, width: 35, height: 42)]
        for i in 0..<12 { o.emit(key: keys[i % keys.count]); o.flush() }
        let m = try XCTUnwrap(o.debugMerit)
        XCTAssertEqual(m.labels.count, MeritFx.cap, "≤ 5 nhãn cùng lúc, dùng lại")
        XCTAssertEqual(o.debugMeritCounter.count, 12)
        for l in m.labels {
            XCTAssertGreaterThanOrEqual(l.position.x - CGFloat(MeritFx.labelWidth / 2), o.bounds.minX)
            XCTAssertLessThanOrEqual(l.position.x + CGFloat(MeritFx.labelWidth / 2), o.bounds.maxX)
            XCTAssertGreaterThanOrEqual(l.position.y - CGFloat(MeritFx.rise + MeritFx.labelHeight / 2), o.bounds.minY,
                                        "cả đường bay trong bàn phím")
            XCTAssertLessThanOrEqual(l.position.y + CGFloat(MeritFx.labelHeight / 2), o.bounds.maxY)
        }
        XCTAssertTrue(o.clipsToBounds)
    }

    @MainActor func testMeritCounterPersistsAndResetsAtMidnight() throws {
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 260))
        let o = try XCTUnwrap(KeyEffectOverlay.install(.merit, color: .systemOrange, in: host, existing: nil))
        let vn = TimeZone.current.secondsFromGMT()
        var epoch = Double(86_400 * 20_000 - vn) - 5      // 5 s trước nửa đêm giờ máy
        o.debugMeritEpoch = { epoch }
        var saved: [(Int, Int)] = []
        let today = MeritCounter.dayIndex(epoch: epoch, utcOffset: vn)
        o.laserOrigin = { CGRect(x: 100, y: 210, width: 190, height: 42) }
        o.meritStore = MeritStore(load: { (today, 41) }, save: { saved.append(($0, $1)) })
        XCTAssertEqual(o.debugMeritCounter.count, 41, "nạp số đã lưu")
        let counter = try XCTUnwrap(o.debugMerit?.counterLayer)
        XCTAssertFalse(counter.isHidden)
        XCTAssertTrue(CGRect(x: 100, y: 210, width: 190, height: 42).contains(counter.frame.origin), "góc trên-trái phím cách")
        o.emit(key: CGRect(x: 10, y: 60, width: 35, height: 42)); o.flush()
        XCTAssertEqual(saved.last?.1, 42, "lần đầu ghi ngay")
        o.emit(key: CGRect(x: 10, y: 60, width: 35, height: 42)); o.flush()
        XCTAssertEqual(saved.count, 1, "ghi thưa (≤ mỗi 5 s)")
        epoch += 10                                          // qua nửa đêm
        o.emit(key: CGRect(x: 10, y: 60, width: 35, height: 42)); o.flush()
        XCTAssertEqual(o.debugMeritCounter.count, 1)
        XCTAssertEqual(o.debugMeritCounter.day, today + 1)
        o.halt()
        XCTAssertEqual(saved.last?.0, today + 1, "ẩn bàn phím ⇒ ghi nốt")
        XCTAssertEqual(saved.last?.1, 1)
        o.laserOrigin = { nil }
        o.emit(key: CGRect(x: 10, y: 60, width: 35, height: 42)); o.flush()
        XCTAssertTrue(counter.isHidden, "không có phím cách (bàn emoji) ⇒ ẩn nhãn đếm")
    }

    // MARK: Nắng qua kính

    func testSunlightGeometryAndTiming() {
        XCTAssertEqual(SunlightFx.envelope(-0.01), 0)
        XCTAssertEqual(SunlightFx.envelope(0.04), 0.5, accuracy: 1e-12)
        XCTAssertEqual(SunlightFx.envelope(0.08), 1, accuracy: 1e-12)
        XCTAssertEqual(SunlightFx.envelope(0.39), 0.25, accuracy: 1e-12)
        XCTAssertEqual(SunlightFx.envelope(0.7), 0)
        XCTAssertTrue((0.6...0.8).contains(SunlightFx.duration))
        let p = SunlightFx.panes(cx: 100, cy: 200, w: 30, h: 40)
        XCTAssertEqual(p.count, 5)
        XCTAssertEqual(p[0], SunlightFx.Pane(x: 100, y: 200, w: 30, h: 40, level: 0.38))
        XCTAssertEqual(p[1].x, 66.4, accuracy: 1e-9); XCTAssertEqual(p[2].x, 133.6, accuracy: 1e-9)
        XCTAssertEqual(p[3].y, 150, accuracy: 1e-9); XCTAssertEqual(p[4].y, 250, accuracy: 1e-9)
        XCTAssertTrue(p.dropFirst().allSatisfy { $0.level == SunlightFx.neighbor && $0.level < p[0].level })
        let b = SunlightFx.beam(1, cx: 100, keyTop: 180, w: 30, top: 0)
        let want = [23.91487093052358, 0, 47.67487093052358, 0, 106.9, 180, 96.1, 180]
        for (x, y) in zip(b, want) { XCTAssertEqual(x, y, accuracy: 1e-9) }
        for i in 0..<SunlightFx.beams {
            let q = SunlightFx.beam(i, cx: 100, keyTop: 180, w: 30, top: 40)
            XCTAssertEqual(q[1], 40); XCTAssertEqual(q[3], 40); XCTAssertEqual(q[5], 180); XCTAssertEqual(q[7], 180)
            XCTAssertLessThan(q[0], q[6], "tia chéo từ trên-trái")
        }
    }

    func testCandleFlickerRateLimited() {
        var c = CandleFlicker()
        XCTAssertNil(c.press(at: 0, level: 1), "chưa gõ dồn ⇒ không có nến")
        XCTAssertEqual(c.press(at: 0, level: 2), 0.34)
        XCTAssertNil(c.press(at: 0.2, level: 3))
        XCTAssertEqual(c.press(at: 0.34, level: 2), 0.24)
        XCTAssertEqual(c.value(at: 0.49), 0.29, accuracy: 1e-12, "chuyển mượt")
        XCTAssertEqual(CandleFlicker.envelope(1.25, from: 0, to: 0.4), 0.2, accuracy: 1e-12)
        XCTAssertEqual(CandleFlicker.envelope(2, from: 0, to: 0.4), 0)
        // Gõ cực nhanh 3 s (20 phím / giây): mọi khoảng 1 s có ≤ 3 lần đổi độ sáng.
        var f = CandleFlicker()
        var times: [Double] = []
        for i in 0..<60 { let t = Double(i) * 0.05; if f.press(at: t, level: 3) != nil { times.append(t) } }
        XCTAssertGreaterThan(times.count, 3)
        for t in times { XCTAssertLessThanOrEqual(times.filter { $0 >= t && $0 < t + 1 }.count, 3, "≤ 3 lần / giây") }
        XCTAssertEqual(f.changes, times.count)
    }

    @MainActor func testSunlightOverlayInsideShiftedBounds() throws {
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 260))
        host.bounds.origin = CGPoint(x: 0, y: 40)
        let o = try XCTUnwrap(KeyEffectOverlay.install(.sunlight, color: .systemYellow, in: host, existing: nil))
        let key = CGRect(x: 120, y: 150, width: 35, height: 42)
        for _ in 0..<12 { o.emit(key: key); o.flush() }
        let s = try XCTUnwrap(o.debugSunlight)
        XCTAssertEqual(s.bursts.count, SunlightFx.pool)
        let bu = s.bursts[0]
        XCTAssertEqual(bu.strong.path?.boundingBox ?? .null, key, "ô vừa bấm = đúng khung phím")
        XCTAssertEqual(bu.rays.count, SunlightFx.beams)
        for r in bu.rays {
            let bb = try XCTUnwrap(r.path?.boundingBox)
            XCTAssertEqual(bb.minY, o.bounds.minY, accuracy: 1e-6, "tia bắt đầu ở mép trên bàn phím (gốc dời)")
            XCTAssertEqual(bb.maxY, key.minY, accuracy: 1e-6)
        }
        let candle = try XCTUnwrap(s.candleLayer, "gõ dồn ⇒ ánh nến")
        XCTAssertEqual(candle.frame.maxY, o.bounds.maxY)
        XCTAssertGreaterThanOrEqual(candle.frame.minY, o.bounds.minY)
        XCTAssertTrue(o.clipsToBounds)
    }

    /// Xem thử (ô 120×84 như trang chọn hiệu ứng): một lần bấm ⇒ có hình hiện ra.
    @MainActor func testPreviewShowsSomething() throws {
        for e in [KeyEffect.merit, .sunlight] {
            let host = UIView(frame: CGRect(x: 0, y: 0, width: 120, height: 84))
            let o = try XCTUnwrap(KeyEffectOverlay.install(e, color: .systemOrange, in: host, existing: nil))
            o.emit(key: CGRect(x: 43, y: 34, width: 34, height: 42)); o.flush()
            if e == .merit {
                let l = try XCTUnwrap(o.debugMerit?.labels.first)
                XCTAssertFalse(l.isHidden)
                XCTAssertNotNil(l.animation(forKey: "fx"))
            } else {
                let b = try XCTUnwrap(o.debugSunlight?.bursts.first)
                XCTAssertFalse(b.root.isHidden)
                XCTAssertNotNil(b.strong.animation(forKey: "fx"))
            }
        }
    }

    // MARK: Ô kính

    func testGlassPaneAssignment() {
        XCTAssertEqual(["q", "w", "a", "s", "d", "z", "x", "Q", "1", "", "đ"].map(GlassKeys.paneIndex), [0, 1, 2, 3, 0, 0, 1, 0, 1, 0, 1])
        let rows = GlassKeys.rows.map { Array($0).map(String.init) }
        for (r, row) in rows.enumerated() {
            for (c, ch) in row.enumerated() {
                if c + 1 < row.count { XCTAssertNotEqual(GlassKeys.paneIndex(ch), GlassKeys.paneIndex(row[c + 1]), ch) }
                if r + 1 < rows.count, c < rows[r + 1].count {
                    XCTAssertNotEqual(GlassKeys.paneIndex(ch), GlassKeys.paneIndex(rows[r + 1][c]), ch)
                }
            }
        }
        XCTAssertEqual(GlassKeys.mix(0x000000, 0xFFFFFF, 0.5), 0x808080)
        XCTAssertEqual(GlassKeys.pressed(0x8E1B2E), 0xA74D5C)
        XCTAssertEqual(GlassKeys.leadWidth(keyHeight: 42), 2.52, accuracy: 1e-12)
        XCTAssertEqual(GlassKeys.leadWidth(keyHeight: 20), 2)
        XCTAssertEqual(GlassKeys.paneColor("q"), 0x8E1B2E)
    }

    func testGlassContrast() throws {
        let p = KeyboardTheme.stainedGlass.palette(systemDark: false)
        for c in GlassKeys.panes {
            XCTAssertGreaterThanOrEqual(RGBA.contrast(p.ink, RGBA(hex: GlassKeys.top(c))), 4.5, String(c, radix: 16))
            XCTAssertGreaterThanOrEqual(RGBA.contrast(p.ink, RGBA(hex: c)), 4.5)
        }
        let mo = KeyboardTheme.mo
        for d in [false, true] {
            let q = mo.palette(systemDark: d)
            XCTAssertGreaterThanOrEqual(RGBA.contrast(q.ink, q.keyFill), 4.5)
            XCTAssertGreaterThanOrEqual(RGBA.contrast(q.accentInk, q.accent), 4.5)
        }
    }

    func testGlassSkins() throws {
        let p = KeyboardTheme.stainedGlass.palette(systemDark: false)
        let s = GlassKeys.skins(p)
        let q = try XCTUnwrap(s["q"]), w = try XCTUnwrap(s["w"]), d = try XCTUnwrap(s["d"])
        XCTAssertFalse(q.normal === w.normal, "ô kề nhau khác màu")
        XCTAssertTrue(q.normal === d.normal, "cùng màu ô ⇒ dùng chung ảnh (cache)")
        XCTAssertNotNil(q.pressed)
        XCTAssertEqual(q.srcH, GlassKeys.imageH)
        XCTAssertNotNil(s[PixelKeys.actionReturnRole])
        XCTAssertNotNil(s["default"]); XCTAssertNotNil(s["shift"])
        let a = GlassKeys.assets(over: nil, palette: p)
        XCTAssertLessThan(a.skinBytes, 400_000, "ảnh tí hon, không tốn RAM")
    }
}
