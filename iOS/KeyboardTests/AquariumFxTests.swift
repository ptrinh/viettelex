import XCTest

/// Theme Bể cá: lái cá, thả / chìm / ăn thức ăn, lớn dần, thêm cá + trần, ghi bộ đếm thưa, cảnh bể, âm "bloop". Số tham
/// chiếu CHUNG Android (AquariumFxTests.kt) — đổi một bên phải đổi cả hai.
final class AquariumFxTests: XCTestCase {

    func testCountsAndGrowth() {
        XCTAssertEqual(AquariumFx.fishCount(eaten: 0), 3)
        XCTAssertEqual(AquariumFx.fishCount(eaten: 499), 3)
        XCTAssertEqual(AquariumFx.fishCount(eaten: 500), 4)
        XCTAssertEqual(AquariumFx.fishCount(eaten: 1499), 5)
        XCTAssertEqual(AquariumFx.fishCount(eaten: 1500), 6)
        XCTAssertEqual(AquariumFx.fishCount(eaten: 100_000), 6, "trần 6")
        XCTAssertEqual(AquariumFx.fishCount(eaten: -5), 3)
        XCTAssertEqual(AquariumFx.growth(eaten: 0), 1)
        XCTAssertEqual(AquariumFx.growth(eaten: 750), 1.15, accuracy: 1e-12)
        XCTAssertEqual(AquariumFx.growth(eaten: 1499), 1.2998, accuracy: 1e-12)
        XCTAssertEqual(AquariumFx.growth(eaten: 9999), 1.3, accuracy: 1e-12, "trần +30 %")
    }

    func testRegionWaypointSteerSink() {
        let r = AquariumFx.region(minX: 0, top: 0, width: 390, height: 260)
        XCTAssertEqual(r, AquariumFx.Region(minX: 12, minY: 65, maxX: 378, maxY: 244))
        XCTAssertEqual(AquariumFx.floorY(r), 244)
        let w0 = AquariumFx.waypoint(seed: 0, k: 0, region: r)
        XCTAssertEqual(w0.x, 349.847013, accuracy: 1e-5); XCTAssertEqual(w0.y, 220.040467, accuracy: 1e-5)
        let w1 = AquariumFx.waypoint(seed: 1, k: 1, region: r)
        XCTAssertEqual(w1.x, 251.297597, accuracy: 1e-5); XCTAssertEqual(w1.y, 145.744610, accuracy: 1e-5)
        for s in 0..<6 { for k in 0..<20 {
            let w = AquariumFx.waypoint(seed: s, k: k, region: r)
            XCTAssertTrue(w.x >= r.minX && w.x <= r.maxX && w.y >= r.minY && w.y <= r.maxY)
        } }
        // Một bước lái từ đứng yên: lực kẹp 90 × (1/30) = 3 pt/s.
        let f = AquariumFx.Fish(x: 100, y: 100, wx: 0, wy: 0, seed: 0)
        let o = AquariumFx.steer(f, toward: 200, 100, dt: 1.0 / 30, limit: AquariumFx.maxSpeed, arrive: true, region: r)
        XCTAssertEqual(o.vx, 3, accuracy: 1e-12); XCTAssertEqual(o.vy, 0); XCTAssertEqual(o.x, 100.1, accuracy: 1e-12)
        // Tốc độ không vượt trần, vị trí kẹp trong vùng.
        var g = AquariumFx.Fish(x: 370, y: 240, wx: 0, wy: 0, seed: 0)
        for _ in 0..<300 {
            g = AquariumFx.steer(g, toward: 1000, 1000, dt: 1.0 / 30, limit: AquariumFx.maxSpeed, arrive: false, region: r)
            XCTAssertLessThanOrEqual(hypot(g.vx, g.vy), AquariumFx.maxSpeed + 1e-9)
            XCTAssertLessThanOrEqual(g.x, r.maxX); XCTAssertLessThanOrEqual(g.y, r.maxY)
        }
        let p = AquariumFx.sink(AquariumFx.Pellet(x0: 50, x: 50, y: 100, age: 0, alive: true), dt: 0.5, floor: 250)
        XCTAssertEqual(p.y, 111, accuracy: 1e-12); XCTAssertEqual(p.x, 50.881678, accuracy: 1e-5)
        let q = AquariumFx.sink(AquariumFx.Pellet(x0: 50, x: 50, y: 249, age: 5.9, alive: true), dt: 0.2, floor: 250)
        XCTAssertEqual(q.y, 250, "dừng ở đáy"); XCTAssertFalse(q.alive, "quá 6 s ⇒ tan")
    }

    func testNearestFishPrefersFree() {
        let a = AquariumFx.Fish(x: 0, y: 0, target: 3, wx: 0, wy: 0, seed: 0)
        let b = AquariumFx.Fish(x: 50, y: 0, wx: 0, wy: 0, seed: 1)
        let c = AquariumFx.Fish(x: 100, y: 0, wx: 0, wy: 0, seed: 2)
        XCTAssertEqual(AquariumFx.nearestFish([a, b, c], count: 3, px: 1, py: 0), 1, "cá bận bị bỏ qua")
        var busy = [a, b, c]; busy[1].target = 0; busy[2].target = 1
        XCTAssertEqual(AquariumFx.nearestFish(busy, count: 3, px: 1, py: 0), 0, "không ai rảnh ⇒ gần nhất")
        XCTAssertEqual(AquariumFx.nearestFish([], count: 0, px: 0, py: 0), -1)
    }

    func testWorldFeedingDeterministic() {
        var w = AquariumFx.World(eaten: 0, minX: 0, top: 0, width: 390, height: 260)
        XCTAssertEqual(w.count, 3)
        XCTAssertEqual(w.fish[0].x, 349.847013, accuracy: 1e-5); XCTAssertEqual(w.fish[1].x, 34.026459, accuracy: 1e-5)
        XCTAssertEqual(w.fish[2].x, 84.217075, accuracy: 1e-5)
        w.drop(x: 200, y: 120)
        XCTAssertEqual(w.fish.map(\.target), [-1, -1, 0], "cá gần nhất đi ăn")
        var ate = 0
        for _ in 0..<120 { ate += w.step(dt: 1.0 / 30) }
        XCTAssertEqual(ate, 1); XCTAssertEqual(w.eaten, 1)
        XCTAssertEqual(w.fish[0].x, 301.2957, accuracy: 1e-3); XCTAssertEqual(w.fish[0].y, 193.9167, accuracy: 1e-3)
        XCTAssertFalse(w.pellets.contains { $0.alive })
        // 40 viên dồn dập: ring 8 viên, tất định.
        var v = AquariumFx.World(eaten: 0, minX: 0, top: 0, width: 390, height: 260)
        var tot = 0
        for j in 0..<40 {
            v.drop(x: Double(20 + (j * 37) % 350), y: Double(80 + (j * 53) % 150))
            for _ in 0..<6 { tot += v.step(dt: 1.0 / 30) }
        }
        for _ in 0..<300 { tot += v.step(dt: 1.0 / 30) }
        XCTAssertEqual(tot, 11); XCTAssertEqual(v.eaten, 11)
        XCTAssertEqual(v.fish.reduce(0) { $0 + $1.x + $1.y }, 1060.5885, accuracy: 1e-2)
        XCTAssertLessThanOrEqual(v.pellets.count, AquariumFx.maxPellets)
    }

    func testNewFishThresholdAndCap() {
        var w = AquariumFx.World(eaten: 1499, minX: 0, top: 0, width: 390, height: 260)
        XCTAssertEqual(w.count, 5)
        w.drop(x: 195, y: 150)
        var n = 0
        while n < 200, w.step(dt: 1.0 / 30) == 0 { n += 1 }
        XCTAssertEqual(w.eaten, 1500); XCTAssertEqual(w.count, 6, "mỗi 500 viên thêm một chú")
        XCTAssertEqual(w.scale(of: 0), 1.3, accuracy: 1e-12)
        XCTAssertEqual(w.scale(of: 1), 1.3 * 0.85, accuracy: 1e-12)
        let full = AquariumFx.World(eaten: 50_000, minX: 0, top: 0, width: 390, height: 260)
        XCTAssertEqual(full.count, AquariumFx.maxFish)
    }

    func testPersistThrottle() {
        var g = AquariumFx.PersistGate()
        XCTAssertFalse(g.shouldSave(now: 0), "chưa bẩn")
        g.note()
        XCTAssertTrue(g.shouldSave(now: 0))
        g.note()
        XCTAssertFalse(g.shouldSave(now: 4.9), "≤ một lần mỗi 5 s")
        XCTAssertTrue(g.shouldSave(now: 5.0))
        XCTAssertFalse(g.shouldSave(now: 20), "không đổi ⇒ không ghi")
        g.note()
        XCTAssertTrue(g.flush(now: 21), "ẩn bàn phím ⇒ ghi ngay")
        XCTAssertFalse(g.flush(now: 21.5))
        // 60 s gõ liên tục, ăn mỗi khung ⇒ ≤ 13 lần ghi.
        var h = AquariumFx.PersistGate(); var writes = 0
        for i in 0..<1800 { h.note(); if h.shouldSave(now: Double(i) / 30) { writes += 1 } }
        XCTAssertEqual(writes, 12)
    }

    func testAquariumScene() {
        XCTAssertTrue(ThemeScene.isScene(.aquarium))
        XCTAssertEqual(ThemeScene.gradient(.aquarium, dark: false), [0x0F4C7A, 0x0B3D66, 0x062847])
        XCTAssertEqual(ThemeScene.gradient(.aquarium, dark: true), [0x0F4C7A, 0x0B3D66, 0x062847])
        let rays = AquariumScene.rays(width: 390, height: 260)
        XCTAssertEqual(rays.count, 4)
        XCTAssertEqual(rays[0][0].0, 46.8, accuracy: 1e-9); XCTAssertEqual(rays[0][2].1, 195)
        for q in rays { for p in q { XCTAssertTrue(p.0 >= 0 && p.0 <= 390 && p.1 >= 0 && p.1 <= 260) } }
        let sand = AquariumScene.sandTop(width: 390, height: 260)
        XCTAssertEqual(sand.count, 50); XCTAssertEqual(sand.last?.0, 390)
        for p in sand { XCTAssertTrue(p.1 >= 260 - AquariumScene.sandHeight - 2 && p.1 <= 260) }
        let weeds = AquariumScene.weeds(width: 390, height: 260)
        XCTAssertEqual(weeds.count, 6)
        for w in weeds { XCTAssertTrue(w.y1 >= 0 && w.y1 < w.y0 && w.x1 >= 0 && w.x1 <= 390) }
        let layer = ThemeSceneLayer()
        layer.update(motif: .aquarium, color: RGBA(hex: 0xFFFFFF, alpha: 0.07), dark: true, size: CGSize(width: 390, height: 260))
        XCTAssertEqual(layer.debugLayerCount, 4, "gradient + vệt nắng + cát + rong")
    }

    func testBloopSound() {
        XCTAssertTrue(KeySoundStyle.presets.contains(.bloop))
        XCTAssertEqual(KeySoundSynth.seed(.bloop, .letter), 0x626C_6F6F ^ 0x85EB_CA6B)
        let golden: [(KeySoundKind, Double)] = [(.letter, 178.8050), (.delete, 180.1272), (.modifier, 213.0168)]
        for (k, want) in golden {
            XCTAssertEqual(KeySoundSynth.samples(.bloop, k).reduce(0.0) { $0 + Double(abs($1)) }, want, accuracy: 0.01, "\(k)")
        }
        let wood = KeySoundSynth.samples(.wood, .letter), b = KeySoundSynth.samples(.bloop, .letter)
        XCTAssertLessThan(b.map(abs).max() ?? 1, wood.map(abs).max() ?? 0, "không to hơn Gõ gỗ")
        XCTAssertEqual(L10n.en["Bọt cá"], "Fish bloop")
    }

    // MARK: bộ vẽ

    @MainActor func testRendererDropsPelletsAndPersistsOnHide() throws {
        KeyEffectOverlay.drawsOffscreen = true
        defer { KeyEffectOverlay.drawsOffscreen = false }
        let name = "vt-aquarium-test"
        let d = try XCTUnwrap(UserDefaults(suiteName: name))
        d.removePersistentDomain(forName: name)
        defer { d.removePersistentDomain(forName: name) }
        d.set(500, forKey: AquariumFx.storageKey)
        for originY in [0.0, 40.0] {
            let host = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 260))
            host.bounds.origin = CGPoint(x: 0, y: originY)
            let o = try XCTUnwrap(KeyEffectOverlay.install(.fishfeed, color: .systemBlue, in: host, existing: nil))
            o.themeDefaults = d
            XCTAssertEqual(o.layer.zPosition, 0, "cá bơi SAU hàng phím")
            let fx = try XCTUnwrap(o.debugThemeFx as? FishFeedRenderer)
            o.layoutSubviews()
            let w = try XCTUnwrap(fx.debugWorld)
            XCTAssertEqual(w.count, 4, "500 viên đã ăn (bộ nhớ) ⇒ 4 chú")
            XCTAssertEqual(fx.debugFishLayers.count, 4)
            for l in fx.debugFishLayers { XCTAssertTrue(host.bounds.contains(l.position), "cá trong bàn phím (gốc dời)") }
            o.emit(key: CGRect(x: 180, y: originY + 100, width: 35, height: 42)); o.flush()
            XCTAssertTrue(fx.debugLinkRunning, "đang gõ ⇒ mô phỏng chạy")
            XCTAssertEqual(fx.debugWorld?.pellets.filter(\.alive).count, 1)
            for _ in 0..<150 { fx.debugStep(1.0 / 30) }
            for l in fx.debugFishLayers { XCTAssertTrue(host.bounds.contains(l.position)) }
            o.halt()
            XCTAssertFalse(fx.debugLinkRunning, "ẩn ⇒ dừng hẳn")
            XCTAssertGreaterThanOrEqual(d.integer(forKey: AquariumFx.storageKey), 500)
            o.configure(effect: .heart, color: .red)
            XCTAssertNil(o.debugThemeFx)
            XCTAssertTrue(fx.debugFishLayers.isEmpty, "đổi kiểu ⇒ gỡ sạch")
        }
        // Ô xem thử (không App Group): không ghi gì.
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 120, height: 84))
        let o = try XCTUnwrap(KeyEffectOverlay.install(.fishfeed, color: .systemBlue, in: host, existing: nil))
        o.layoutSubviews()
        let fx = try XCTUnwrap(o.debugThemeFx as? FishFeedRenderer)
        XCTAssertEqual(fx.debugWorld?.eaten, 0)
    }

    func testAquariumTheme() throws {
        let t = KeyboardTheme.aquarium
        let spec = try XCTUnwrap(t.spec)
        XCTAssertTrue(t.isPlus); XCTAssertTrue(t.isInteractive)
        XCTAssertEqual(spec.nameVi, "Bể cá"); XCTAssertEqual(spec.nameEn, "Aquarium")
        XCTAssertEqual(L10n.en[t.title], "Aquarium")
        XCTAssertEqual(spec.sound, "bloop"); XCTAssertEqual(spec.effect, "fishfeed")
        XCTAssertNil(spec.dark, "dark = same")
        XCTAssertEqual(t.systemBackdropKey, "systemBackdropAquarium")
        XCTAssertNotNil(BackupSettings.byKey["systemBackdropAquarium"])
        XCTAssertTrue(ThemeSpecParser.contrastIssues(spec).isEmpty)
        XCTAssertEqual(L10n.en["Cho cá ăn"], "Feed the fish")
        let p = t.palette(systemDark: false)
        XCTAssertEqual(p.decoration?.motif, .aquarium)
        // Phím trong mờ: chữ ≥ 4.5 trên mọi điểm gradient của cảnh (kể cả dưới vệt nắng ở đỉnh).
        let ray = try XCTUnwrap(p.decoration?.color)
        for s in ThemeScene.gradient(.aquarium, dark: false) {
            for base in [RGBA(hex: s), ray.over(RGBA(hex: s))] {
                XCTAssertGreaterThanOrEqual(RGBA.contrast(p.ink, p.keyFill.over(base)), 4.5, String(s, radix: 16))
                XCTAssertGreaterThanOrEqual(RGBA.contrast(p.fnInk, p.fnFill.over(base)), 4.5)
            }
        }
    }
}
