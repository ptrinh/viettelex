// "Hiệu ứng nét vuốt" (Phil 19/10/2026): model cài đặt + id chung Android, sao lưu, cổng Plus (hết Plus ⇒ Đơn
// giản, giá trị giữ), "swipe" trong theme JSON, cấu hình lớp từng kiểu (Tắt = không dựng gì), trần hạt / không
// rò qua 200 cú vuốt, nhiễu tia điện tất định, độ dày bút lông là hàm thuần, 0 animation khi nghỉ, và chi phí
// main thread mỗi lần chạm di chuyển so với Đơn giản (mục tiêu ≤ +0,1 ms). Số tham chiếu GIỐNG HỆT Android
// SwipeTrailStyleTests.kt.
import XCTest
import UIKit

// MARK: - Vệt vuốt cùng hệ toạ độ với bàn phím khi host dời gốc bounds (#151, khung host cao tạm)
// Trước: layer.frame = bounds nhưng gốc bounds 0 ⇒ điểm chạm (toạ độ KeyboardView) vẽ lệch lên đúng phần dư.
final class SwipeTrailCoordinateTests: XCTestCase {
    @MainActor func testTrailSharesShiftedHostOrigin() throws {
        let host = CALayer()
        host.frame = CGRect(x: 0, y: 0, width: 390, height: 470)
        host.bounds.origin.y = -180
        let t = SwipeTrailRenderer()
        t.configure(style: .rainbow, trail: RGBA(hex: 0xFFFFFF, alpha: 0.6), accent: RGBA(hex: 0x0A84FF), dark: false)
        t.begin(bounds: host.bounds)
        host.addSublayer(t.layer)
        let p = CGPoint(x: 60, y: 150)
        XCTAssertEqual(t.layer.frame, host.bounds, "phủ trọn phần đang hiện")
        XCTAssertEqual(host.convert(p, from: t.layer), p, "điểm chạm vẽ đúng chỗ")
        for l in t.layer.sublayers ?? [] { XCTAssertEqual(host.convert(p, from: l), p) }
        let g = try XCTUnwrap(t.debugGradient)
        XCTAssertEqual(host.convert(p, from: g), p, "gradient (mặt nạ nét cầu vồng) cùng toạ độ")
        // Host đo lại: hết dư ⇒ cú vuốt sau theo gốc mới.
        host.frame = CGRect(x: 0, y: 0, width: 390, height: 290)
        host.bounds.origin.y = 0
        t.begin(bounds: host.bounds)
        XCTAssertEqual(t.layer.frame, host.bounds)
        for l in [t.layer, g] + (t.layer.sublayers ?? []) { XCTAssertEqual(host.convert(p, from: l), p) }
        // Đổi kiểu (gradient dựng lại) rồi vuốt: gradient mới cũng cùng toạ độ.
        t.configure(style: .rainbow, trail: RGBA(hex: 0xFF0000, alpha: 0.6), accent: RGBA(hex: 0x0A84FF), dark: true)
        t.begin(bounds: host.bounds)
        XCTAssertEqual(host.convert(p, from: try XCTUnwrap(t.debugGradient)), p)
    }
}

final class SwipeTrailStyleTests: XCTestCase {
    private var savedDefaults: UserDefaults!
    private var savedPaywall = true
    private let plusSuite = "vt-swipetrail-plus"
    private let suite = "vt-swipetrail"

    override func setUp() {
        super.setUp()
        savedDefaults = PlusGate.defaults
        savedPaywall = PlusGate.paywallEnabled
        UserDefaults(suiteName: plusSuite)!.removePersistentDomain(forName: plusSuite)
        PlusGate.defaults = UserDefaults(suiteName: plusSuite)!
    }

    override func tearDown() {
        PlusGate.defaults = savedDefaults
        PlusGate.paywallEnabled = savedPaywall
        super.tearDown()
    }

    private func setPlus(_ on: Bool) {
        PlusGate.paywallEnabled = true
        PlusGate.defaults.set(false, forKey: PlusConfig.debugOverrideKey)
        PlusGate.defaults.set(on, forKey: PlusConfig.unlockedKey)
    }

    // MARK: model / id / sao lưu

    func testIdsMatchAndroidAndDefaultIsSimple() {
        XCTAssertEqual(SwipeTrailStyle.allCases.map(\.rawValue),
                       ["none", "simple", "fire", "electric", "brush", "rainbow", "neon", "stardust", "firework", "theme"])
        XCTAssertEqual(SwipeTrailStyle.key, "swipeTrail")
        XCTAssertEqual(SwipeTrailStyle.defaultValue, .simple)
        XCTAssertEqual(SwipeTrailStyle.parse(nil), .simple)
        XCTAssertEqual(SwipeTrailStyle.parse("glitter"), .simple, "id lạ ⇒ Đơn giản")
        XCTAssertEqual(SwipeTrailStyle.parse(7), .simple)
        XCTAssertEqual(SwipeTrailStyle.parse("none"), .none)
        XCTAssertEqual(SwipeTrailStyle.themeIds, ["none", "simple", "fire", "electric", "brush", "rainbow", "neon", "stardust", "firework"])
        XCTAssertEqual(ThemeExtraIds.swipes, Set(SwipeTrailStyle.themeIds))
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        XCTAssertEqual(SwipeTrailStyle.load(d), .simple)
        d.set("neon", forKey: SwipeTrailStyle.key)
        XCTAssertEqual(SwipeTrailStyle.load(d), .neon)
        d.removePersistentDomain(forName: suite)
    }

    func testBackupSpecWhitelistsIds() {
        let spec = BackupSettings.all.first { $0.key == SwipeTrailStyle.key }
        XCTAssertEqual(spec?.kind, .string("simple", ["none", "simple", "fire", "electric", "brush", "rainbow", "neon", "stardust", "firework", "theme"]))
    }

    func testTitlesBilingual() {
        for s in SwipeTrailStyle.allCases { XCTAssertNotNil(L10n.en[s.title], "thiếu bản dịch: \(s.title)") }
        XCTAssertNotNil(L10n.en["Hiệu ứng nét vuốt"])
    }

    // MARK: cổng Plus

    func testOnlyOffAndSimpleAreFree() {
        XCTAssertFalse(SwipeTrailStyle.none.isPlus)
        XCTAssertFalse(SwipeTrailStyle.simple.isPlus)
        for s in SwipeTrailStyle.allCases where s != .none && s != .simple { XCTAssertTrue(s.isPlus, s.rawValue) }
        setPlus(false)
        XCTAssertTrue(SwipeTrailGate.allows(.none))
        XCTAssertTrue(SwipeTrailGate.allows(.simple))
        XCTAssertFalse(SwipeTrailGate.allows(.theme), "Theo giao diện cũng là Plus")
        XCTAssertFalse(SwipeTrailGate.allows(.fire))
        setPlus(true)
        XCTAssertTrue(SwipeTrailGate.allows(.fire))
    }

    /// Đã chọn Neon rồi hết Plus ⇒ bàn phím vẽ Đơn giản, dòng cài đặt hiện Đơn giản; giá trị lưu giữ nguyên.
    func testLapsedPlusFallsBackToSimpleButKeepsSetting() {
        setPlus(false)
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        d.set("neon", forKey: SwipeTrailStyle.key)
        XCTAssertEqual(SwipeTrailPolicy.current(d, themeSwipe: nil), .simple)
        XCTAssertEqual(SwipeTrailStyle.displayed("neon"), .simple)
        XCTAssertEqual(SwipeTrailStyle.load(d), .neon, "dữ liệu giữ nguyên")
        d.set("none", forKey: SwipeTrailStyle.key)
        XCTAssertEqual(SwipeTrailPolicy.current(d, themeSwipe: "neon"), .none, "Tắt luôn miễn phí")
        setPlus(true)
        d.set("neon", forKey: SwipeTrailStyle.key)
        XCTAssertEqual(SwipeTrailPolicy.current(d, themeSwipe: nil), .neon)
        XCTAssertEqual(SwipeTrailStyle.displayed("neon"), .neon)
        d.removePersistentDomain(forName: suite)
    }

    func testPolicyResolvesThemeAtDrawTime() {
        let A = SwipeTrailPolicy.active
        XCTAssertEqual(A(.theme, true, "rainbow", false), .rainbow)
        XCTAssertEqual(A(.theme, true, nil, false), .simple, "theme không khai báo ⇒ Đơn giản")
        XCTAssertEqual(A(.theme, true, "theme", false), .simple, "không tự trỏ")
        XCTAssertEqual(A(.theme, true, "junk", false), .simple)
        XCTAssertEqual(A(.theme, true, "none", false), .none)
        XCTAssertEqual(A(.theme, false, "rainbow", false), .simple, "chưa Plus")
        XCTAssertEqual(A(.fire, true, "rainbow", false), .fire, "kiểu cụ thể bỏ qua theme")
        XCTAssertEqual(A(.fire, true, nil, true), .simple, "nguồn điện thấp ⇒ Đơn giản")
        XCTAssertEqual(A(.none, false, nil, true), .none)
        XCTAssertEqual(A(.simple, false, nil, true), .simple)
        for s in SwipeTrailStyle.allCases { XCTAssertNotEqual(A(s, true, "theme", false), .theme) }
    }

    // MARK: theme JSON "swipe"

    func testBuiltinThemesSwipeMapping() {
        let want: [String: String] = ["tet": "stardust", "tetMai": "stardust", "xmas": "stardust", "xmasSnow": "stardust",
                                      "rgb": "rainbow", "neon": "neon", "space": "stardust", "typewriter": "brush",
                                      "halloween": "electric", "pixel": "neon", "ai": "neon", "nightclub": "neon", "trippy": "rainbow"]
        XCTAssertFalse(BuiltinThemes.specs.isEmpty)
        for (id, spec) in BuiltinThemes.specs {
            XCTAssertEqual(spec.swipe, want[id], id)
            XCTAssertEqual(spec.typography.swipe, want[id], id)
        }
        for id in want.keys { XCTAssertNotNil(BuiltinThemes.specs[id], id) }
    }

    func testSwipeRoundTripsThroughThemeAndKeyStyleStore() throws {
        let text = ##"{"v":1,"name":{"vi":"x"},"light":{"key":"#FFFFFF","special":"#DDDDDD","ink":"#000000","accent":"#000000"},"swipe":"brush"}"##
        let spec = try XCTUnwrap(ThemeSpecParser.parse(text).spec)
        XCTAssertEqual(spec.swipe, "brush")
        let again = try XCTUnwrap(ThemeSpecParser.parse(spec.json.canonical).spec)
        XCTAssertEqual(again, spec)
        // Bản vá theo theme (sửa JSON theme có sẵn) giữ "swipe".
        var st = KeyStyle()
        st.swipe = "neon"
        let raw = KeyStyleStore.serialize(["pink": st])
        XCTAssertTrue(raw.contains(#""swipe":"neon""#), raw)
        XCTAssertEqual(KeyStyleStore.parse(raw)["pink"]?.swipe, "neon")
        XCTAssertNil(ThemeSpecParser.override(from: .object([("swipe", .string("theme"))])), "id lạ ⇒ bỏ mục")
        // Export ("Chép JSON") mang "swipe" của kiểu chữ hiện tại.
        let p = try XCTUnwrap(BuiltinThemes.specs["neon"]).palette(dark: false)
        let ex = ThemeSpec.export(id: nil, nameVi: "y", nameEn: nil, light: p, dark: p, style: st)
        XCTAssertEqual(ex.swipe, "neon")
    }

    /// Chọn theme KHÔNG đổi cài đặt nét vuốt — "Theo giao diện" giải lúc vẽ.
    func testSelectingThemeDoesNotTouchSwipeSetting() {
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        d.set("simple", forKey: SwipeTrailStyle.key)
        guard let t = KeyboardTheme(rawValue: "rgb") else { return XCTFail("thiếu theme rgb") }
        ThemeExtras.applyOnSelect(t.spec?.typography ?? KeyStyle(), to: d)
        XCTAssertEqual(d.string(forKey: SwipeTrailStyle.key), "simple")
        d.removePersistentDomain(forName: suite)
    }

    // MARK: cấu hình lớp

    func testStrokeConfigPerStyle() {
        let n: [SwipeTrailStyle: Int] = [.none: 0, .theme: 0, .simple: 1, .firework: 1, .fire: 3, .electric: 3, .neon: 3,
                                         .rainbow: 1, .brush: 1, .stardust: 1]
        for s in SwipeTrailStyle.allCases {
            let k = s.strokes(base: 6, trail: 0x99FF_FFFF, accent: 0x0A84FF, dark: false)
            XCTAssertEqual(k.count, n[s], s.rawValue)
            XCTAssertTrue(k.allSatisfy { $0.width >= 0 && $0.argb >> 24 > 0 }, s.rawValue)
        }
        XCTAssertEqual(SwipeTrailStyle.simple.strokes(base: 6, trail: 0x99FF_FFFF, accent: 0, dark: false),
                       [SwipeTrailStroke(width: 6, argb: 0x99FF_FFFF)], "Đơn giản = vệt cũ")
        XCTAssertEqual(SwipeTrailStyle.rainbow.strokes(base: 6, trail: 0, accent: 0, dark: false).first?.kind, .gradient)
        XCTAssertEqual(SwipeTrailStyle.brush.strokes(base: 6, trail: 0, accent: 0, dark: false).first?.argb, 0xE61A_1A1A, "mực đậm nền sáng")
        XCTAssertEqual(SwipeTrailStyle.brush.strokes(base: 6, trail: 0, accent: 0, dark: true).first?.argb, 0xE6F2_F2F2, "mực sáng nền tối")
        // Neon: lõi sáng (pha trắng) + hai quầng theo màu nhấn.
        let neon = SwipeTrailStyle.neon.strokes(base: 6, trail: 0, accent: 0x0A84FF, dark: true)
        XCTAssertEqual(neon.map(\.argb), [0x2E0A_84FF, 0x660A_84FF, 0xFFA9_D4FF])
        XCTAssertEqual(SwipeTrailFx.mix(0x000000, 0xFFFFFF, 0.5), 0x808080)
        XCTAssertEqual(SwipeTrailStyle.fire.spawnEvery, 3)
        XCTAssertEqual(SwipeTrailStyle.stardust.spawnEvery, 4)
        for s in SwipeTrailStyle.allCases where ![.fire, .stardust, .firework].contains(s) {
            XCTAssertFalse(s.usesParticles, s.rawValue)
        }
    }

    @MainActor func testRendererLayersPerStyleAndOffBuildsNothing() {
        for s in SwipeTrailStyle.allCases {
            let r = SwipeTrailRenderer()
            r.configure(style: s, trail: RGBA(hex: 0xFFFFFF, alpha: 0.6), accent: RGBA(hex: 0x0A84FF), dark: false)
            let strokes = s.strokes(base: 6, trail: 0, accent: 0, dark: false).count
            XCTAssertEqual(r.debugStrokeLayers.count, strokes, s.rawValue)
            XCTAssertEqual(r.debugParticles.count, s.usesParticles ? SwipeTrailFx.particleCap : 0, s.rawValue)
            XCTAssertEqual(r.debugGradient != nil, s == .rainbow, s.rawValue)
            if s == .none || s == .theme {
                // 2 nhóm rỗng (nét, hạt) — Tắt thật sự thì KeyboardView không dựng renderer (test bàn phím dưới).
                XCTAssertEqual(r.debugSublayerCount, 2, s.rawValue)
            }
            // Cấu hình lại cùng tham số ⇒ không dựng lại (cùng đối tượng layer).
            let before = r.debugStrokeLayers.map(ObjectIdentifier.init)
            r.configure(style: s, trail: RGBA(hex: 0xFFFFFF, alpha: 0.6), accent: RGBA(hex: 0x0A84FF), dark: false)
            XCTAssertEqual(r.debugStrokeLayers.map(ObjectIdentifier.init), before)
        }
    }

    // MARK: hàm thuần (số tham chiếu chung Android)

    func testElectricJitterDeterministicParity() {
        let ref: [(Int, Int, Double)] = [(0, 0, 0.550744), (1, 1, 0.736660), (7, 3, -0.921202), (42, 10, 0.172717),
                                         (-5, 2, -0.025589), (123456, 127, -0.434409)]
        for (s, i, v) in ref {
            XCTAssertEqual(SwipeTrailFx.jitter(seed: s, index: i), v, accuracy: 1e-6, "seed \(s) i \(i)")
            XCTAssertEqual(SwipeTrailFx.jitter(seed: s, index: i), SwipeTrailFx.jitter(seed: s, index: i))
        }
        var differs = 0
        for i in 0..<64 {
            let a = SwipeTrailFx.jitter(seed: 9, index: i), b = SwipeTrailFx.jitter(seed: 10, index: i)
            XCTAssertTrue((-1...1).contains(a))
            if a != b { differs += 1 }
        }
        XCTAssertGreaterThan(differs, 60, "seed khác ⇒ tia khác (nhấp nháy)")
    }

    @MainActor func testElectricPathDeterministicPerSeedAndKeepsEnds() throws {
        func draw() -> CGPath? {
            let r = SwipeTrailRenderer()
            r.configure(style: .electric, trail: .white, accent: RGBA(hex: 0x0A84FF), dark: false)
            r.begin(bounds: CGRect(x: 0, y: 0, width: 400, height: 300))
            for i in 0..<20 { r.add(CGPoint(x: 20 + Double(i) * 15, y: 150), Double(i) * 0.01) }
            r.redraw()
            XCTAssertEqual(r.debugSeed, 1)
            return r.debugStrokeLayers.first?.path
        }
        let a = try XCTUnwrap(draw()), b = try XCTUnwrap(draw())
        XCTAssertEqual(a, b, "cùng seed ⇒ cùng tia")
        let box = a.boundingBoxOfPath
        XCTAssertEqual(box.minX, 20, accuracy: 0.01, "đầu nét không nhiễu")
        XCTAssertEqual(box.maxX, 305, accuracy: 0.01, "cuối nét không nhiễu")
        XCTAssertLessThanOrEqual(box.height, 2 * SwipeTrailFx.electricAmplitude + 0.01)
        XCTAssertGreaterThan(box.height, 1, "có răng cưa")
    }

    func testBrushWidthIsPureFunctionOfSpeed() {
        XCTAssertEqual(SwipeTrailFx.brushWidth(speed: 0), 10)
        XCTAssertEqual(SwipeTrailFx.brushWidth(speed: 0.8), 6.25, accuracy: 1e-9)
        XCTAssertEqual(SwipeTrailFx.brushWidth(speed: 1.6), 2.5)
        XCTAssertEqual(SwipeTrailFx.brushWidth(speed: 50), 2.5, "nhanh ⇒ mảnh, có sàn")
        XCTAssertEqual(SwipeTrailFx.brushWidth(speed: -1), 10)
        var last = Double.infinity
        for i in 0...40 {
            let w = SwipeTrailFx.brushWidth(speed: Double(i) * 0.05)
            XCTAssertLessThanOrEqual(w, last)
            last = w
        }
        XCTAssertEqual(SwipeTrailFx.brushSmooth(10, 2.5), 7.375, accuracy: 1e-9)
        XCTAssertEqual(SwipeTrailFx.brushTaperFactor(0, 30), 1.0 / 6, accuracy: 1e-9)
        XCTAssertEqual(SwipeTrailFx.brushTaperFactor(15, 30), 1)
        XCTAssertEqual(SwipeTrailFx.brushTaperFactor(29, 30), 1.0 / 6, accuracy: 1e-9)
        XCTAssertEqual(SwipeTrailFx.brushTaperFactor(0, 1), 1.0 / 6, accuracy: 1e-9)
    }

    func testParticleTrajectoriesParity() {
        let f3 = SwipeTrailFx.trajectory(.firework, 3)
        XCTAssertEqual(f3.dx, 0, accuracy: 1e-9)
        XCTAssertEqual(f3.dy, 36, accuracy: 1e-9)
        XCTAssertEqual(f3.duration, 0.6)
        let e0 = SwipeTrailFx.trajectory(.fire, 0)
        XCTAssertEqual(e0.dx, -8, accuracy: 1e-9)
        XCTAssertEqual(e0.dy, -22)
        XCTAssertEqual(e0.duration, 0.55, accuracy: 1e-9)
        let e5 = SwipeTrailFx.trajectory(.fire, 5)
        XCTAssertEqual(e5.dx, 8.0 * 3 / 7, accuracy: 1e-9)
        XCTAssertEqual(e5.dy, -34)
        let s2 = SwipeTrailFx.trajectory(.stardust, 2)
        XCTAssertEqual(s2.rotation, -0.16, accuracy: 1e-9)
        XCTAssertEqual(s2.duration, 1.1, accuracy: 1e-9)
        for s in [SwipeTrailStyle.fire, .stardust, .firework] {
            for v in 0..<SwipeTrailFx.variants(s) {
                XCTAssertLessThanOrEqual(SwipeTrailFx.trajectory(s, v).duration, SwipeTrailFx.maxParticleLife, s.rawValue)
            }
        }
        var sp = SwipeTrailFx.Spawner(every: 3)
        XCTAssertEqual((0..<9).map { _ in sp.tick() }, [false, false, true, false, false, true, false, false, true])
        var off = SwipeTrailFx.Spawner(every: 0)
        XCTAssertFalse(off.tick())
    }

    // MARK: trần hạt / không rò / nghỉ = 0 animation

    @MainActor func testParticlesCappedNoLeakOver200SwipesAndIdleHasNoAnimations() {
        for s in [SwipeTrailStyle.fire, .stardust, .firework, .electric] {
            let r = SwipeTrailRenderer()
            r.configure(style: s, trail: .white, accent: RGBA(hex: 0x0A84FF), dark: true)
            let layers0 = r.debugSublayerCount
            var t = 0.0
            for k in 0..<200 {
                r.begin(bounds: CGRect(x: 0, y: 0, width: 400, height: 300))
                for i in 0..<40 {
                    t += 0.008
                    r.add(CGPoint(x: 10 + Double(i * 9 % 380), y: 40 + Double((i * 7 + k) % 200)), t)
                    r.redraw()
                }
                r.fadeOut(reduceMotion: k % 2 == 0)
                r.commitBurst()
                XCTAssertLessThanOrEqual(r.debugVisibleParticles, SwipeTrailFx.particleCap, s.rawValue)
                XCTAssertLessThanOrEqual(r.debugPointCount, 128)
            }
            XCTAssertEqual(r.debugSublayerCount, layers0, "\(s.rawValue): không thêm layer qua 200 cú vuốt")
            XCTAssertEqual(r.debugParticles.count, s.usesParticles ? SwipeTrailFx.particleCap : 0)
            if s.usesParticles { XCTAssertGreaterThan(r.debugVisibleParticles, 0, s.rawValue) }
            if s == .electric { XCTAssertGreaterThan(r.debugAnimationCount, 0, "nhấp nháy khi đang/ vừa vuốt") }
            r.settleNow()
            XCTAssertEqual(r.debugAnimationCount, 0, "\(s.rawValue): nghỉ ⇒ 0 animation")
            XCTAssertEqual(r.debugVisibleParticles, 0)
        }
    }

    /// Nhấc tay ⇒ settle tự hẹn sau mờ dần + đời hạt: hết animation mà không cần gọi gì.
    @MainActor func testSettlesItselfAfterFade() {
        let r = SwipeTrailRenderer()
        r.configure(style: .fire, trail: .white, accent: RGBA(hex: 0xFF0000), dark: false)
        r.begin(bounds: CGRect(x: 0, y: 0, width: 300, height: 200))
        for i in 0..<12 { r.add(CGPoint(x: 10 + Double(i) * 10, y: 100), Double(i) * 0.01); r.redraw() }
        r.fadeOut(reduceMotion: false)
        XCTAssertGreaterThan(r.debugAnimationCount, 0)
        RunLoop.main.run(until: Date().addingTimeInterval(SwipeTrailFx.fade + SwipeTrailFx.maxParticleLife + 0.15))
        XCTAssertEqual(r.debugAnimationCount, 0)
        XCTAssertEqual(r.debugVisibleParticles, 0)
    }

    @MainActor func testFireworkBurstsOnlyOnCommit() {
        let r = SwipeTrailRenderer()
        r.configure(style: .firework, trail: .white, accent: RGBA(hex: 0x0A84FF), dark: false)
        r.begin(bounds: CGRect(x: 0, y: 0, width: 300, height: 200))
        for i in 0..<30 { r.add(CGPoint(x: 10 + Double(i) * 8, y: 100), Double(i) * 0.01); r.redraw() }
        XCTAssertEqual(r.debugVisibleParticles, 0, "không hạt dọc đường")
        r.fadeOut(reduceMotion: false)
        XCTAssertEqual(r.debugVisibleParticles, 0, "nhấc tay chưa chốt từ ⇒ chưa bắn")
        r.commitBurst()
        XCTAssertEqual(r.debugVisibleParticles, SwipeTrailFx.fireworkCount)
        XCTAssertTrue(r.debugParticles.filter { !$0.isHidden }.allSatisfy { abs($0.position.x - 242) < 0.01 && $0.position.y == 100 })
        let other = SwipeTrailRenderer()
        other.configure(style: .simple, trail: .white, accent: .white, dark: false)
        other.commitBurst()
        XCTAssertEqual(other.debugParticles.count, 0)
    }

    // MARK: bàn phím thật

    @MainActor private func withKeyboard(_ style: String?, plus: Bool, theme: String? = nil,
                                         _ body: (KeyboardView) throws -> Void) rethrows {
        setPlus(plus)
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        if let style { d.set(style, forKey: SwipeTrailStyle.key) }
        if let theme { d.set(theme, forKey: ThemeSettings.themeKey) }
        let saved = UserDefaultsProvider.shared
        UserDefaultsProvider.shared = d
        defer { UserDefaultsProvider.shared = saved; d.removePersistentDomain(forName: suite) }
        let win = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 300))
        win.isHidden = false
        let kb = KeyboardView(needsGlobe: false, inputController: nil) { _ in }
        kb.frame = win.bounds
        win.addSubview(kb)
        kb.applyAppearance(.light, style: .light)
        kb.layoutIfNeeded()
        kb.swipeEnabled = true
        try body(kb)
        win.isHidden = true
    }

    @MainActor private func swipe(_ kb: KeyboardView, _ word: String) -> Bool {
        let keys = word.compactMap { c -> CGPoint? in
            kb.debugLetterFrame(String(c)).map { CGPoint(x: $0.midX, y: $0.midY + TouchGeometry.yOffset) }
        }
        var pts: [CGPoint] = []
        for i in 1..<keys.count {
            for j in 1...8 {
                let u = CGFloat(j) / 8
                pts.append(CGPoint(x: keys[i - 1].x + (keys[i].x - keys[i - 1].x) * u,
                                   y: keys[i - 1].y + (keys[i].y - keys[i - 1].y) * u))
            }
        }
        return kb.debugTouch(from: keys[0], through: pts, start: CACurrentMediaTime())
    }

    @MainActor func testKeyboardOffBuildsNoTrail() {
        withKeyboard("none", plus: true) { kb in
            XCTAssertEqual(kb.trailStyle, .none)
            XCTAssertTrue(swipe(kb, "viet"))
            XCTAssertNil(kb.debugTrail, "Tắt ⇒ không dựng renderer / layer nào")
        }
        withKeyboard(nil, plus: false) { kb in
            XCTAssertEqual(kb.trailStyle, .simple)
            XCTAssertTrue(swipe(kb, "viet"))
            let t = kb.debugTrail
            XCTAssertNotNil(t)
            XCTAssertEqual(t?.style, .simple)
            XCTAssertEqual(t?.debugStrokeLayers.count, 1)
        }
        withKeyboard("fire", plus: false) { kb in
            XCTAssertEqual(kb.trailStyle, .simple, "chưa Plus ⇒ Đơn giản")
        }
    }

    @MainActor func testKeyboardMatchThemeAndFireworkCommit() {
        withKeyboard("theme", plus: true, theme: "rgb") { kb in
            XCTAssertEqual(kb.trailStyle, .rainbow, "Theo giao diện + Gaming RGB ⇒ Cầu vồng")
        }
        withKeyboard("theme", plus: true, theme: "peach") { kb in
            XCTAssertEqual(kb.trailStyle, .simple, "theme không khai báo ⇒ Đơn giản")
        }
        withKeyboard("firework", plus: true) { kb in
            XCTAssertTrue(swipe(kb, "viet"))
            let t = kb.debugTrail
            XCTAssertEqual(t?.debugVisibleParticles, 0)
            kb.swipeCommitted()
            XCTAssertEqual(t?.debugVisibleParticles, SwipeTrailFx.fireworkCount)
        }
        // Đổi sang Tắt ở lần hiện kế ⇒ gỡ renderer.
        withKeyboard("simple", plus: true) { kb in
            XCTAssertTrue(swipe(kb, "viet"))
            XCTAssertNotNil(kb.debugTrail)
            UserDefaultsProvider.shared?.set("none", forKey: SwipeTrailStyle.key)
            kb.applyAppearance(.light, style: .light)
            XCTAssertNil(kb.debugTrail)
        }
    }

    // MARK: chi phí main thread mỗi lần chạm di chuyển (so với Đơn giản)

    /// Đo trực tiếp add + redraw (+ commit CA, layer trong window thật) — phần DUY NHẤT khác nhau giữa các kiểu
    /// (thu điểm cho bộ giải mã như nhau). Khối Đơn giản / kiểu xen kẽ để nhiễu chia đều. In "TRAILBENCH …".
    @MainActor func testPerMoveMainThreadCostVsSimple() {
        let win = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 290))
        win.isHidden = false
        defer { win.isHidden = true }
        let bounds = win.bounds
        // Đường giả như vuốt thật: ~60 lần di chuyển / cú, bước ~7 pt.
        let path: [CGPoint] = (0..<60).map { i in
            let f = Double(i) / 59
            return CGPoint(x: 20 + 360 * f, y: 145 + 90 * sin(f * 3 * .pi))
        }
        func run(_ s: SwipeTrailStyle, swipes: Int) -> [Double] {
            let r = SwipeTrailRenderer()
            r.configure(style: s, trail: RGBA(hex: 0xFFFFFF, alpha: 0.6), accent: RGBA(hex: 0x0A84FF), dark: false)
            win.layer.addSublayer(r.layer)
            defer { r.settleNow(); r.layer.removeFromSuperlayer() }
            var out: [Double] = []
            out.reserveCapacity(swipes * path.count)
            var t = CACurrentMediaTime()
            for _ in 0..<swipes {
                r.begin(bounds: bounds)
                for p in path {
                    t += 0.008
                    let t0 = CACurrentMediaTime()
                    r.add(p, t)
                    r.redraw()
                    out.append((CACurrentMediaTime() - t0) * 1000)
                }
                r.fadeOut(reduceMotion: false)
                r.commitBurst()
            }
            return out
        }
        func pct(_ a: [Double], _ q: Double) -> Double {
            let s = a.sorted(); return s.isEmpty ? 0 : s[min(s.count - 1, Int(Double(s.count) * q))]
        }
        _ = run(.simple, swipes: 20)    // làm nóng
        let styles: [SwipeTrailStyle] = [.fire, .electric, .brush, .rainbow, .neon, .stardust, .firework]
        var report: [String] = []
        for s in styles {
            var deltas: [Double] = [], base: [Double] = [], on: [Double] = []
            for _ in 0..<5 {
                let a = run(.simple, swipes: 20), b = run(s, swipes: 20)
                base += a; on += b
                deltas.append(pct(b, 0.5) - pct(a, 0.5))
            }
            let d = pct(deltas, 0.5)
            let line = String(format: "TRAILBENCH %@ per_move_p50 simple=%.4f style=%.4f Δ=%.4f ms | p95 simple=%.4f style=%.4f",
                              s.rawValue, pct(base, 0.5), pct(on, 0.5), d, pct(base, 0.95), pct(on, 0.95))
            print(line)
            report.append(line)
            XCTAssertLessThanOrEqual(d, 0.1, "\(s.rawValue): +ms mỗi lần di chuyển so với Đơn giản")
        }
        XCTContext.runActivity(named: report.joined(separator: "\n")) { _ in }
    }
}
