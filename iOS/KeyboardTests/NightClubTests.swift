import XCTest

/// Theme Neon Night Club: Đèn rọi (SpotlightFx / SpotlightLights), quả cầu disco, Sàn nhảy LED (DanceFloor), bóng cô gái
/// nhảy (DancerFigure). Số tham chiếu CHUNG Android (keyboard/src/test/.../SpotlightTests.kt).
final class NightClubTests: XCTestCase {
    override func setUp() {
        super.setUp()
        SpotlightView.drawsOffscreen = true
        KeyEffectOverlay.drawsOffscreen = true
    }
    override func tearDown() {
        SpotlightView.drawsOffscreen = false
        KeyEffectOverlay.drawsOffscreen = false
        super.tearDown()
    }

    // MARK: Đèn rọi — hàm thuần

    func testSpotlightRadiusAlphaScale() {
        XCTAssertEqual(SpotlightFx.radius(keyWidth: 34, level: 0), 54.4, accuracy: 1e-9)
        XCTAssertEqual(SpotlightFx.radius(keyWidth: 34, level: 3), 69.7, accuracy: 1e-9, "gõ nhanh ⇒ to hơn")
        XCTAssertEqual(SpotlightFx.radius(keyWidth: 10, level: 0), 36, "kẹp dưới")
        XCTAssertEqual(SpotlightFx.radius(keyWidth: 100, level: 3), 150, "kẹp trên")
        XCTAssertEqual(SpotlightFx.duration(level: 0), 0.72, accuracy: 1e-12)
        XCTAssertEqual(SpotlightFx.duration(level: 3), 0.87, accuracy: 1e-12)
        XCTAssertEqual(SpotlightFx.duration(level: 9), 0.87, accuracy: 1e-12, "mức kẹp 0…3")
        XCTAssertEqual(SpotlightFx.peak(level: 0), 0.78, accuracy: 1e-12)
        XCTAssertEqual(SpotlightFx.peak(level: 3), 0.99, accuracy: 1e-12, "gõ nhanh ⇒ sáng hơn")
        XCTAssertEqual(SpotlightFx.alpha(-0.01, level: 0), 0)
        XCTAssertEqual(SpotlightFx.alpha(0.03, level: 0), 0.39, accuracy: 1e-12)
        XCTAssertEqual(SpotlightFx.alpha(0.06, level: 0), 0.78, accuracy: 1e-12)
        XCTAssertEqual(SpotlightFx.alpha(0.39, level: 0), 0.195, accuracy: 1e-12)
        XCTAssertEqual(SpotlightFx.alpha(0.72, level: 0), 0)
        XCTAssertEqual(SpotlightFx.alpha(0.8, level: 3), 0.007393689986282588, accuracy: 1e-12)
        XCTAssertEqual(SpotlightFx.scale(0, level: 0), 0.8, accuracy: 1e-12)
        XCTAssertEqual(SpotlightFx.scale(0.36, level: 0), 1.025, accuracy: 1e-12)
        XCTAssertEqual(SpotlightFx.scale(5, level: 0), 1.1, accuracy: 1e-12)
        XCTAssertEqual((0..<4).map { SpotlightFx.color($0) }, [0xFF2FD0, 0x9B5CFF, 0x2FE6FF, 0xFF2FD0])
        // Tắt trong khoảng 0,6–0,9 s.
        for lv in 0...3 { XCTAssertTrue((0.6...0.9).contains(SpotlightFx.duration(level: lv))) }
    }

    func testSpotlightLightsCap() {
        var l = SpotlightLights()
        XCTAssertEqual(l.live(at: 0), 0)
        XCTAssertEqual(l.lastEnd, -.greatestFiniteMagnitude)
        for k in 0..<7 { _ = l.press(at: Double(k) * 0.1, level: 0) }
        XCTAssertEqual(l.presses, 7)
        XCTAssertEqual(l.cursor, 1, "đủ 6 ⇒ quầng cũ nhất bị thay")
        XCTAssertEqual(l.starts[0], 0.6, accuracy: 1e-12)
        XCTAssertEqual(l.live(at: 0.65), SpotlightFx.cap)
        XCTAssertEqual(l.lastEnd, 1.32, accuracy: 1e-12)
        XCTAssertEqual(l.live(at: 1.0), 4)
        XCTAssertEqual(l.live(at: 1.4), 0)
        l.reset()
        XCTAssertEqual(l.live(at: 0.65), 0)
    }

    func testDiscoBall() {
        let c = DiscoBall.center(minX: 0, minY: 0, width: 400)
        XCTAssertEqual(c.x, 386, accuracy: 1e-12); XCTAssertEqual(c.y, 13, accuracy: 1e-12)
        let d = DiscoBall.direction(press: 0, dot: 0)
        XCTAssertEqual(d.x, -0.15643446504023104, accuracy: 1e-12); XCTAssertEqual(d.y, 0.9876883405951377, accuracy: 1e-12)
        for p in 0..<6 { for i in 0..<DiscoBall.dotsPerPress {
            let v = DiscoBall.direction(press: p, dot: i)
            XCTAssertLessThan(v.x, 0.01, "toả sang trái (quả cầu ở góc phải)"); XCTAssertGreaterThanOrEqual(v.y, -0.1)
        } }
        XCTAssertEqual(DiscoBall.dotAlpha(0.225), 0.25, accuracy: 1e-12)
        XCTAssertEqual(DiscoBall.dotAlpha(0.45), 0)
        XCTAssertEqual(DiscoBall.dotTravel(0.225), 22.5, accuracy: 1e-12)
        XCTAssertEqual(DiscoBall.dotTravel(9), 30, accuracy: 1e-12)
    }

    // MARK: Sàn nhảy LED

    func testDanceFloorTiming() {
        XCTAssertEqual(DanceFloor.alpha(0, ring: 0), 0.55, accuracy: 1e-12)
        XCTAssertEqual(DanceFloor.alpha(0.05, ring: 1), 0, "vòng 1 chưa tới lượt")
        XCTAssertEqual(DanceFloor.alpha(0.06, ring: 1), 0.55, accuracy: 1e-12)
        XCTAssertEqual(DanceFloor.alpha(0.13, ring: 0), 0.1375, accuracy: 1e-12)
        XCTAssertEqual(DanceFloor.alpha(0.26, ring: 0), 0)
        XCTAssertEqual(DanceFloor.lifetime, 0.38, accuracy: 1e-12)
        XCTAssertEqual(DanceFloor.flickerAlpha(0.03), 0.22, accuracy: 1e-12)
        XCTAssertEqual(DanceFloor.flickerAlpha(0.08), 0)
        XCTAssertEqual(DanceFloor.flickerAlpha(0.15), 0.11, accuracy: 1e-12)
        XCTAssertEqual(DanceFloor.flickerAlpha(0.2), 0)
        var g = DanceFloor.FlickerGate()
        XCTAssertFalse(g.trigger(level: 2, at: 0), "chưa đủ combo")
        XCTAssertTrue(g.trigger(level: 3, at: 1))
        XCTAssertFalse(g.trigger(level: 3, at: 2.1), "trần nhịp 1,2 s")
        XCTAssertTrue(g.trigger(level: 3, at: 2.2))
        XCTAssertEqual(g.fired, 2)
    }

    func testDanceFloorTiles() {
        let t = DanceFloor.tiles(cx: 100, cy: 50, w: 30, h: 40, seed: 0)
        XCTAssertEqual(t.count, 25)
        XCTAssertEqual((0..<3).map { r in t.filter { $0.ring == r }.count }, [1, 8, 16], "vòng vuông")
        let center = t[12]
        XCTAssertEqual([center.x, center.y, center.w, center.h], [100, 50, 30, 40])
        XCTAssertEqual(t[13].x, 135.4, accuracy: 1e-9)
        XCTAssertEqual(t[7].y, 50 - 51.2, accuracy: 1e-9)
        XCTAssertEqual(DanceFloor.colorIndex(1, -1, seed: 2), 1)
        // Phím cách: ô hàng xóm rộng ≤ 0,85 × cao, dời ra ngoài mép phím.
        let sp = DanceFloor.tiles(cx: 100, cy: 50, w: 200, h: 40, seed: 2)
        XCTAssertEqual(sp[13].x, 223.12, accuracy: 1e-9)
        XCTAssertEqual(sp[13].w, 34, accuracy: 1e-9)
        XCTAssertEqual(sp.reduce(0.0) { $0 + $1.x * Double($1.color + 1) + $1.w }, 6075.88, accuracy: 1e-6)
        let grid = DanceFloor.grid(bounds: (0, 0, 400, 300), cx: 100, cy: 50, w: 30, h: 40, seed: 0)
        XCTAssertEqual(grid.count, 55)
        XCTAssertTrue(grid.allSatisfy { $0.x >= 0 && $0.x <= 400 && $0.y >= 0 && $0.y <= 300 })
        XCTAssertLessThanOrEqual(DanceFloor.grid(bounds: (0, 0, 4000, 3000), cx: 0, cy: 0, w: 30, h: 40, seed: 0).count,
                                 DanceFloor.maxGrid, "trần ô nháy")
    }

    /// Lớp phủ Sàn nhảy LED: pool 3 chùm, cắt theo bàn phím; gõ dồn ⇒ nháy cả bàn phím (một lớp).
    func testDanceFloorOverlay() {
        let o = KeyEffectOverlay(effect: .dancefloor, color: .systemPink)
        o.frame = CGRect(x: 0, y: 0, width: 400, height: 300)
        XCTAssertTrue(o.clipsToBounds)
        for _ in 0..<(ComboMeter.thresholds[2] + 1) {
            o.emit(key: CGRect(x: 100, y: 200, width: 30, height: 40)); o.flush()
        }
        XCTAssertEqual(o.debugDanceRoots.count, DanceFloor.pool)
        XCTAssertNotNil(o.debugFloorFlicker, "gõ dồn ⇒ nháy cả bàn phím")
        let layers = o.debugDanceRoots.flatMap { $0.sublayers ?? [] }
        XCTAssertEqual(layers.count, DanceFloor.pool * DanceFloor.rings * DanceFloor.colors.count)
        XCTAssertTrue(layers.allSatisfy { $0.animation(forKey: "fx") != nil })
    }

    // MARK: Bóng cô gái nhảy

    func testDancerPosesParseAndRotate() {
        let poses = DancerFigure.poses
        XCTAssertEqual(poses.map(\.id), ["vArms", "point", "jump", "spin", "disco", "clap", "groove", "hips"])
        XCTAssertEqual(DancerFigure.parse(BuiltinThemesData.dancerJson), poses)
        // Xoay vòng: đủ 8 tư thế mỗi 8 lần nháy, không lặp liền.
        let seq = (1...16).map { DancerFigure.poseIndex(press: $0, count: poses.count) }
        XCTAssertEqual(Array(seq.prefix(8)), [3, 6, 1, 4, 7, 2, 5, 0])
        XCTAssertEqual(Set(seq.prefix(8)).count, 8)
        for i in 1..<seq.count { XCTAssertNotEqual(seq[i], seq[i - 1]) }
        // Đọc chặt: mục hỏng bị bỏ, JSON hỏng ⇒ rỗng.
        XCTAssertEqual(DancerFigure.parse("{"), [])
        XCTAssertEqual(DancerFigure.parse(#"{"poses":[{"id":"a","torso":180}]}"#), [])
        XCTAssertEqual(DancerFigure.parse(#"{"poses":[{"id":"a","torso":999,"lua":0,"lfa":0,"rua":0,"rfa":0,"lth":0,"lsh":0,"rth":0,"rsh":0,"hair":0,"flare":0}]}"#), [])
        XCTAssertEqual(DancerFigure.parse(#"{"poses":[{"id":"a","torso":180,"lua":0,"lfa":0,"rua":0,"rfa":0,"lth":0,"lsh":0,"rth":0,"rsh":0,"hair":0,"flare":50}]}"#).count, 1)
        XCTAssertLessThan(BuiltinThemesData.dancerJson.utf8.count, 30 * 1024, "dữ liệu nhỏ")
    }

    /// Hình học: 17 đa giác / 216 điểm, cùng chiều quay, vừa khung (86 % cao, giữa ngang), checksum chung Android.
    func testDancerGeometry() {
        let golden: [Double] = [71623.601231, 67304.161350, 70302.961617, 73226.334031, 75023.606427, 72363.604897,
                                71621.713071, 74609.106699]
        for (i, p) in DancerFigure.poses.enumerated() {
            let polys = DancerFigure.fitted(p, width: 400, height: 300)
            XCTAssertEqual(polys.count, 17, p.id)
            XCTAssertEqual(polys.reduce(0) { $0 + $1.count / 2 }, 216, p.id)
            var minY = Double.infinity, maxY = -Double.infinity
            for q in polys {
                var a = 0.0
                for k in stride(from: 0, to: q.count, by: 2) {
                    let n = (k + 2) % q.count
                    a += q[k] * q[n + 1] - q[n] * q[k + 1]
                    XCTAssertTrue(q[k] > 0 && q[k] < 400, p.id)
                    minY = min(minY, q[k + 1]); maxY = max(maxY, q[k + 1])
                }
                XCTAssertGreaterThan(a, 0, "\(p.id) cùng chiều quay")
            }
            XCTAssertEqual(minY, 21, accuracy: 1e-9); XCTAssertEqual(maxY, 279, accuracy: 1e-9)
            XCTAssertEqual(DancerFigure.checksum(polys), golden[i], accuracy: 1e-5, p.id)
        }
    }

    // MARK: Lớp đèn rọi

    func testSpotlightViewNoPhotoShowsDancer() {
        let v = SpotlightView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        v.layoutIfNeeded()
        v.setPhoto(nil)
        XCTAssertTrue(v.debugDarkHidden, "không ảnh: không phủ đen thêm (nền theme đã tối)")
        XCTAssertTrue(v.debugTextureVisible)
        XCTAssertNotNil(v.debugDancer?.path)
        XCTAssertFalse(v.debugDancer?.isHidden ?? true)
        XCTAssertTrue(v.debugLitHidden, "nghỉ: không lượt vẽ mặt nạ")
        v.light(key: CGRect(x: 100, y: 200, width: 30, height: 40)); v.flush()
        XCTAssertFalse(v.debugLitHidden)
        XCTAssertEqual(v.poseIndex, 3, "nháy ⇒ tư thế kế")
        XCTAssertNotNil(v.debugHoleLayers[0].animation(forKey: "fx"))
        XCTAssertEqual(v.debugHoleLayers[0].bounds.width, CGFloat(2 * SpotlightFx.radius(keyWidth: 30, level: 0)), accuracy: 0.01)
        XCTAssertEqual(v.debugHoleLayers[0].position, CGPoint(x: 115, y: 220))
        let first = v.debugDancer?.path
        v.light(key: CGRect(x: 10, y: 20, width: 30, height: 40)); v.flush()
        XCTAssertEqual(v.poseIndex, 6)
        XCTAssertNotEqual(v.debugDancer?.path, first, "đổi path")
        XCTAssertEqual(v.debugRim?.path, v.debugDancer?.path, "viền cùng hình bóng")
        XCTAssertEqual(v.debugRim?.strokeColor, UIColor(red: 0x9B / 255.0, green: 0x5C / 255.0, blue: 1, alpha: 1).cgColor,
                       "viền theo màu đèn vừa bật (lần 2: tím)")
        for _ in 0..<10 { v.light(key: CGRect(x: 10, y: 20, width: 30, height: 40)); v.flush() }
        XCTAssertEqual(v.debugLights.presses, 12)
        XCTAssertLessThanOrEqual(v.debugLights.live(at: CACurrentMediaTime()), SpotlightFx.cap)
        XCTAssertLessThanOrEqual(v.debugDots.count, DiscoBall.dotPool, "chấm sáng pool cố định")
        v.debugIdle()
        XCTAssertTrue(v.debugLitHidden)
        XCTAssertTrue(v.debugTintLayers.allSatisfy(\.isHidden))
    }

    func testSpotlightViewWithPhotoSharesImageAndHidesDancer() throws {
        let v = SpotlightView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        v.layoutIfNeeded()
        v.setPhoto(nil)
        let img = try XCTUnwrap(UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { c in
            UIColor.red.setFill(); c.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }.cgImage)
        v.setPhoto(img)
        XCTAssertTrue(v.hasPhoto)
        XCTAssertTrue((v.debugLitContents as AnyObject?) === img, "CHÍNH CGImage của ảnh nền — không sao chép")
        XCTAssertFalse(v.debugDarkHidden, "ảnh: phủ đen 90 %")
        XCTAssertTrue(v.debugDancer?.isHidden ?? true, "có ảnh nền ⇒ không hiện bóng")
        XCTAssertFalse(v.debugTextureVisible)
        v.light(key: CGRect(x: 100, y: 200, width: 30, height: 40)); v.flush()
        XCTAssertEqual(v.poseIndex, 0, "có ảnh: không đổi tư thế")
        v.halt()
        XCTAssertTrue(v.debugLitHidden)
    }

    /// Bàn phím thật: theme Neon Night Club ⇒ có lớp đèn rọi (dưới phím, trên ảnh nền), chung hệ toạ độ (#151, đi qua
    /// debugCoordinateOverlays — test HostOversizeControllerTests phủ mọi lớp trong danh sách); theme khác ⇒ nil.
    @MainActor func testKeyboardViewInstallsSpotlightOnlyForTheme() {
        let saved = UserDefaultsProvider.shared, savedPaywall = PlusGate.paywallEnabled
        let suite = "vt-nightclub-tests"
        defer {
            UserDefaultsProvider.shared = saved
            PlusGate.paywallEnabled = savedPaywall
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        }
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        PlusGate.paywallEnabled = false
        d.set(KeyboardTheme.nightclub.rawValue, forKey: ThemeSettings.themeKey)
        d.set(KeyEffect.dancefloor.rawValue, forKey: KeyEffect.key)
        UserDefaultsProvider.shared = d
        let kb = KeyboardView(needsGlobe: false, inputController: nil, onKey: { _ in })
        kb.frame = CGRect(x: 0, y: 0, width: 402, height: 300)
        kb.applyAppearance(.dark, style: .dark)
        kb.bounds.origin = CGPoint(x: 0, y: -60)          // host cấp dư (#151): gốc bounds dời
        kb.layoutIfNeeded()
        let s = try! XCTUnwrap(kb.spotlight)
        XCTAssertTrue(kb.debugCoordinateOverlays.contains(s))
        XCTAssertEqual(s.frame, kb.bounds)
        XCTAssertEqual(s.bounds.origin, kb.bounds.origin, "chung hệ toạ độ với bàn phím")
        XCTAssertNotNil(kb.keyEffects, "Sàn nhảy LED")
        XCTAssertLessThan(kb.subviews.firstIndex(of: s)!, kb.subviews.firstIndex(of: kb.keyEffects!)!, "đèn rọi dưới hiệu ứng / phím")
        d.set(KeyboardTheme.pixel.rawValue, forKey: ThemeSettings.themeKey)
        kb.applyAppearance(.dark, style: .dark)
        XCTAssertNil(kb.spotlight, "theme khác: 0 lớp")
        kb.tearDown()
    }
}
