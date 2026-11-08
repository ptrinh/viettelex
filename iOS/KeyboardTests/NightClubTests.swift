import XCTest

/// Theme Neon Night Club: Đèn rọi (SpotlightFx / SpotlightLights), quả cầu disco, Sàn nhảy LED (DanceFloor), người nhảy
/// hoạt hình (NightDancer). Số tham chiếu CHUNG Android (keyboard/src/test/.../SpotlightTests.kt).
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

    // MARK: Người nhảy hoạt hình (NightDancer) — số CHUNG Android SpotlightTests

    /// Biến thể (khung × lật) tất định, không lặp liền, đủ 14 biến thể. = Android dancerVariants.
    func testDancerVariants() {
        XCTAssertEqual(NightDancer.sequence, [0, 1, 0, 1, 2, 3, 4, 5, 6])
        XCTAssertEqual(NightDancer.variants, 14)
        XCTAssertEqual(NightDancer.frame(3), 3); XCTAssertFalse(NightDancer.mirrored(3))
        XCTAssertEqual(NightDancer.frame(10), 3); XCTAssertTrue(NightDancer.mirrored(10))
        let golden = [1, 7, 1, 9, 3, 4, 5, 4, 7, 8, 0, 8, 2, 3, 4, 12, 13, 0, 12, 0, 1, 2, 3, 11, 12, 6, 11, 1, 0, 1, 9,
                      10, 3, 12, 6, 0, 1, 6, 8, 9]
        var p = -1
        let seq: [Int] = (1...400).map { n in p = NightDancer.next(prev: p, flash: n); return p }
        XCTAssertEqual(Array(seq.prefix(40)), golden)
        XCTAssertTrue(seq.allSatisfy { (0..<NightDancer.variants).contains($0) })
        for i in 1..<seq.count { XCTAssertNotEqual(seq[i - 1], seq[i], "lần \(i)") }
        XCTAssertEqual(Set(seq.prefix(40)).count, 14, "đủ 14 biến thể trong 40 lần nháy")
        let mirrors = seq.filter(NightDancer.mirrored).count
        let twice = (1..<seq.count).filter { NightDancer.mirrored(seq[$0]) && NightDancer.mirrored(seq[$0 - 1]) }.count
        XCTAssertTrue((100...200).contains(mirrors), "lật ~1/3 số lần")
        XCTAssertLessThan(twice * 2, mirrors, "lật hai lần liền ít hơn hẳn")
        XCTAssertGreaterThan(seq.enumerated().filter { NightDancer.frame($0.element) == NightDancer.sequence[($0.offset + 1) % 9] }.count,
                             240, "theo chuỗi nhảy là chính")
        for n in 1...200 { for prev in 0..<NightDancer.variants { XCTAssertNotEqual(NightDancer.next(prev: prev, flash: n), prev) } }
    }

    func testDancerCharacterCellsAndDecodeSize() {
        XCTAssertEqual(NightDancer.character(.off), .girl)
        XCTAssertEqual(NightDancer.character(.girl), .girl)
        XCTAssertEqual(NightDancer.character(.boy), .boy)
        for c in [BuddyCharacter.cat, .chick, .ai] { XCTAssertEqual(NightDancer.character(c), .girl) }
        XCTAssertEqual(NightDancer.cell(0), CGRect(x: 0, y: 0, width: 0.25, height: 0.5))
        XCTAssertEqual(NightDancer.cell(3), CGRect(x: 0.75, y: 0, width: 0.25, height: 0.5))
        XCTAssertEqual(NightDancer.cell(6), CGRect(x: 0.5, y: 0.5, width: 0.25, height: 0.5))
        let r = NightDancer.rect(width: 400, height: 260, cellAspect: 0.75)
        XCTAssertEqual(r.height, 221, accuracy: 1e-9); XCTAssertEqual(r.width, 165.75, accuracy: 1e-9)
        XCTAssertEqual(r.minX, 117.125, accuracy: 1e-9); XCTAssertEqual(r.minY, 39, accuracy: 1e-9)
        XCTAssertTrue(CGRect(x: 0, y: 0, width: 400, height: 260).contains(r))
        XCTAssertEqual(NightDancer.decodeLongEdge(displayHeight: 221, scale: 3, atlasW: 1536, atlasH: 1024), 1536)
        XCTAssertEqual(NightDancer.decodeLongEdge(displayHeight: 221, scale: 2, atlasW: 1536, atlasH: 1024), 1326)
        XCTAssertEqual(NightDancer.decodeLongEdge(displayHeight: 85, scale: 2, atlasW: 1536, atlasH: 1024), 510)
        XCTAssertEqual(NightDancer.decodeLongEdge(displayHeight: 400, scale: 3, atlasW: 4096, atlasH: 2731), 2048)
        XCTAssertEqual(NightDancer.decodeLongEdge(displayHeight: 221, scale: 3, atlasW: 0, atlasH: 0), 0)
        XCTAssertEqual(NightDancer.decodedBytes(longEdge: 1536, atlasW: 1536, atlasH: 1024), 6_291_456)
        XCTAssertEqual(NightDancer.decodedBytes(longEdge: 1326, atlasW: 1536, atlasH: 1024), 4_688_736)
        XCTAssertLessThan(NightDancer.decodedBytes(longEdge: 2048, atlasW: 2048, atlasH: 1365), 11_200_000, "≤ ~11 MB ở trần")
    }

    /// Giải atlas thật theo cỡ hiển thị + đo RAM (phys_footprint) — báo con số trong log test.
    func testDancerAtlasDecodeSizeAndMemory() throws {
        func footprint() -> Int {
            var info = task_vm_info_data_t()
            var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
            let kr = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
            }
            return kr == KERN_SUCCESS ? Int(info.phys_footprint) : 0
        }
        let before = footprint()
        let img = try XCTUnwrap(NightDancer.decodeAtlas(.girl, displayHeight: 221, scale: 3))
        let after = footprint()
        XCTAssertEqual(max(img.width, img.height), 1536, "@3x, bàn phím 260 pt ⇒ ảnh gốc 1536 px (không mờ)")
        XCTAssertEqual(img.bytesPerRow * img.height, 6_291_456, accuracy: 64 * 1024)
        print("NightDancer RAM: ảnh \(img.width)×\(img.height) = \(img.bytesPerRow * img.height) B; phys_footprint +\(after - before) B")
        let small = try XCTUnwrap(NightDancer.decodeAtlas(.boy, displayHeight: 85, scale: 2))
        XCTAssertEqual(max(small.width, small.height), 510, "cỡ nhỏ ⇒ giải nhỏ")
    }

    // MARK: Lớp đèn rọi

    func testSpotlightViewNoPhotoShowsDancer() {
        let v = SpotlightView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        v.layoutIfNeeded()
        v.setPhoto(nil)
        XCTAssertTrue(v.debugDarkHidden, "không ảnh: không phủ đen thêm (nền theme đã tối)")
        XCTAssertTrue(v.debugTextureVisible)
        v.debugLoadAtlasNow(scale: 2)
        XCTAssertNotNil(v.debugAtlas)
        XCTAssertTrue(v.debugDancerVisible)
        XCTAssertEqual(v.debugDancerFrame, NightDancer.rect(width: 400, height: 300, cellAspect: 0.75), "85 % cao, đứng đáy, giữa")
        XCTAssertEqual(v.debugDancerCell, NightDancer.cell(0), "đứng thẳng trước lần nháy đầu")
        XCTAssertTrue(v.debugLitHidden, "nghỉ: không lượt vẽ mặt nạ")
        v.light(key: CGRect(x: 100, y: 200, width: 30, height: 40)); v.flush()
        XCTAssertFalse(v.debugLitHidden)
        XCTAssertEqual(v.variant, NightDancer.next(prev: 0, flash: 1), "nháy ⇒ biến thể kế")
        XCTAssertEqual(v.debugDancerCell, NightDancer.cell(NightDancer.frame(v.variant)))
        XCTAssertEqual(v.debugDancerMirrored, NightDancer.mirrored(v.variant))
        XCTAssertNotNil(v.debugHoleLayers[0].animation(forKey: "fx"))
        XCTAssertEqual(v.debugHoleLayers[0].bounds.width, CGFloat(2 * SpotlightFx.radius(keyWidth: 30, level: 0)), accuracy: 0.01)
        XCTAssertEqual(v.debugHoleLayers[0].position, CGPoint(x: 115, y: 220))
        var prev = v.variant
        for i in 0..<20 {
            v.light(key: CGRect(x: 10, y: 20, width: 30, height: 40)); v.flush()
            XCTAssertNotEqual(v.variant, prev, "không lặp liền (\(i))")
            prev = v.variant
            if i == 0 {
                XCTAssertEqual(v.debugRimColor, UIColor(red: 0x9B / 255.0, green: 0x5C / 255.0, blue: 1, alpha: 1).cgColor,
                               "viền theo màu đèn vừa bật (lần 2: tím)")
            }
        }
        XCTAssertEqual(v.debugLights.presses, 21)
        XCTAssertLessThanOrEqual(v.debugLights.live(at: CACurrentMediaTime()), SpotlightFx.cap)
        XCTAssertLessThanOrEqual(v.debugDots.count, DiscoBall.dotPool, "chấm sáng pool cố định")
        XCTAssertTrue(CGRect(x: 0, y: 0, width: 400, height: 300).contains(v.debugDancerFrame), "luôn trong bàn phím")
        v.debugIdle()
        XCTAssertTrue(v.debugLitHidden)
        XCTAssertTrue(v.debugTintLayers.allSatisfy(\.isHidden))
        v.dancer = .boy
        XCTAssertNil(v.debugAtlas, "đổi nhân vật ⇒ thả atlas cũ")
    }

    func testSpotlightViewWithPhotoSharesImageAndHidesDancer() throws {
        let v = SpotlightView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        v.layoutIfNeeded()
        v.setPhoto(nil)
        v.debugLoadAtlasNow(scale: 2)
        XCTAssertNotNil(v.debugAtlas)
        let img = try XCTUnwrap(UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { c in
            UIColor.red.setFill(); c.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }.cgImage)
        v.setPhoto(img)
        XCTAssertTrue(v.hasPhoto)
        XCTAssertTrue((v.debugLitContents as AnyObject?) === img, "CHÍNH CGImage của ảnh nền — không sao chép")
        XCTAssertFalse(v.debugDarkHidden, "ảnh: phủ đen 90 %")
        XCTAssertNil(v.debugAtlas, "có ảnh nền ⇒ thả atlas (0 byte)")
        XCTAssertFalse(v.debugDancerVisible, "có ảnh nền ⇒ không người nhảy")
        v.debugLoadAtlasNow(scale: 2)
        XCTAssertNil(v.debugAtlas, "có ảnh nền ⇒ không giải")
        XCTAssertFalse(v.debugTextureVisible)
        v.light(key: CGRect(x: 100, y: 200, width: 30, height: 40)); v.flush()
        XCTAssertEqual(v.variant, 0, "có ảnh: không đổi biến thể")
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
