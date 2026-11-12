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
                       ["none", "simple", "fire", "electric", "brush", "rainbow", "neon", "stardust", "firework", "plasma", "kaleidoscope", "melt", "chroma", "keys", "calligraphy", "comet", "firefly", "matrix", "petals", "theme"])
        XCTAssertEqual(SwipeTrailStyle.key, "swipeTrail")
        XCTAssertEqual(SwipeTrailStyle.defaultValue, .simple)
        XCTAssertEqual(SwipeTrailStyle.parse(nil), .simple)
        XCTAssertEqual(SwipeTrailStyle.parse("glitter"), .simple, "id lạ ⇒ Đơn giản")
        XCTAssertEqual(SwipeTrailStyle.parse(7), .simple)
        XCTAssertEqual(SwipeTrailStyle.parse("none"), .none)
        XCTAssertEqual(SwipeTrailStyle.themeIds, ["none", "simple", "fire", "electric", "brush", "rainbow", "neon", "stardust", "firework", "plasma", "kaleidoscope", "melt", "chroma", "keys", "calligraphy", "comet", "firefly", "matrix", "petals"])
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
        XCTAssertEqual(spec?.kind, .string("simple", ["none", "simple", "fire", "electric", "brush", "rainbow", "neon", "stardust", "firework", "plasma", "kaleidoscope", "melt", "chroma", "keys", "calligraphy", "comet", "firefly", "matrix", "petals", "theme"]))
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
        let want: [String: String] = ["tet": "calligraphy", "tetMai": "petals", "xmas": "stardust", "xmasSnow": "stardust",
                                      "rgb": "rainbow", "neon": "neon", "space": "stardust", "typewriter": "brush", "sen": "petals",
                                      "halloween": "electric", "pixel": "neon", "ai": "matrix", "nightclub": "neon", "trippy": "kaleidoscope", "drift": "stardust", "rainyNight": "firefly", "gym": "neon",
                                      "zodiac": "stardust", "pride": "rainbow", "piano": "keys", "guitar": "keys", "valentine": "petals", "greenFloral": "petals", "trungthu": "firefly"]
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

    /// Gõ vuốt TẮT (mặc định): chọn theme KHÔNG đổi cài đặt nét vuốt (Gõ vuốt bật ⇒ ThemeSwipeExtrasTests).
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
                                         .rainbow: 1, .brush: 1, .stardust: 1, .plasma: 3,
                                         .kaleidoscope: 3, .melt: 3, .chroma: 4,
                                         .keys: 1, .calligraphy: 1, .comet: 6, .firefly: 1, .matrix: 2, .petals: 1]
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
        XCTAssertEqual(SwipeTrailStyle.plasma.spawnEvery, 5)
        for s in SwipeTrailStyle.allCases where ![.fire, .stardust, .firework, .plasma, .melt, .firefly, .matrix, .petals].contains(s) {
            XCTAssertFalse(s.usesParticles, s.rawValue)
        }
        for s in [SwipeTrailStyle.firefly, .matrix, .petals] { XCTAssertTrue(s.usesParticles, s.rawValue) }
        XCTAssertEqual(SwipeTrailStyle.allCases.filter(\.usesKeys), [.keys, .matrix], "chỉ hai kiểu cần khung phím")
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
        for s in [SwipeTrailStyle.fire, .stardust, .firework, .plasma, .melt, .firefly, .matrix, .petals] {
            XCTAssertGreaterThan(SwipeTrailFx.variants(s), 0, s.rawValue)
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
        let keys = SwipeTrailRenderer.sampleKeys(in: CGRect(x: 0, y: 40, width: 400, height: 200))
        for s in [SwipeTrailStyle.fire, .stardust, .firework, .electric, .plasma, .kaleidoscope, .melt, .chroma,
                  .keys, .calligraphy, .comet, .firefly, .matrix, .petals] {
            let r = SwipeTrailRenderer()
            r.configure(style: s, trail: .white, accent: RGBA(hex: 0x0A84FF), dark: true)
            let layers0 = r.debugSublayerCount
            var t = 0.0
            for k in 0..<200 {
                r.setKeys(keys.rects, keys.chars, hitDy: 4)
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
            if [SwipeTrailStyle.electric, .plasma, .kaleidoscope, .melt, .chroma, .keys, .calligraphy].contains(s) { XCTAssertGreaterThan(r.debugAnimationCount, 0, "nhấp nháy khi đang/ vừa vuốt") }
            XCTAssertLessThanOrEqual(r.debugGlows.count, SwipeTrailFx.keyGlowCap)
            r.settleNow()
            XCTAssertEqual(r.debugAnimationCount, 0, "\(s.rawValue): nghỉ ⇒ 0 animation")
            XCTAssertEqual(r.debugVisibleParticles, 0)
            XCTAssertEqual(r.debugLitKeys, [], "\(s.rawValue): nghỉ ⇒ không ô sáng")
            XCTAssertEqual(r.debugSeal?.isHidden ?? true, true)
            XCTAssertTrue(r.debugHeads.allSatisfy(\.isHidden))
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

    // MARK: Ảo ảnh / Tan chảy / Vệt lặp (số tham chiếu chung Android)

    func testNewStylesPureParity() {
        XCTAssertEqual(SwipeTrailStyle.melt.spawnEvery, 4)
        XCTAssertEqual(SwipeTrailFx.kaleidoBranches, 6)
        XCTAssertEqual(SwipeTrailFx.hueWheel.first, SwipeTrailFx.hueWheel.last, "bánh xe màu khép vòng")
        XCTAssertEqual(SwipeTrailFx.cycleColor(0), 0xFF4D6D)
        XCTAssertEqual(SwipeTrailFx.cycleColor(1), 0xFF4D6D)
        XCTAssertEqual(SwipeTrailFx.cycleColor(0.5), SwipeTrailFx.mix(0x4DFF88, 0x4DD8FF, 0.5))
        XCTAssertEqual(SwipeTrailFx.cycleColor(1.25), SwipeTrailFx.cycleColor(0.25))
        XCTAssertEqual(SwipeTrailFx.cycleColor(-0.75), SwipeTrailFx.cycleColor(0.25))
        XCTAssertEqual(SwipeTrailFx.cycleColor(0.25), 0xEEED4D, "1,75 mốc: giữa cam và vàng chanh")
        XCTAssertEqual(SwipeTrailFx.meltBreath(0), 1, accuracy: 1e-9)
        XCTAssertEqual(SwipeTrailFx.meltBreath(0.25), 1.3, accuracy: 1e-9)
        XCTAssertEqual(SwipeTrailFx.meltBreath(0.75), 0.7, accuracy: 1e-9)
        XCTAssertEqual(SwipeTrailFx.meltSag(0), 0)
        XCTAssertEqual(SwipeTrailFx.meltSag(0.5), 1.75, accuracy: 1e-9)
        XCTAssertEqual(SwipeTrailFx.meltSag(1), 7)
        XCTAssertEqual(SwipeTrailFx.meltSag(3), 7, "không chảy quá meltDrip")
        XCTAssertEqual(SwipeTrailFx.meltSag(-1), 0)
        let g0 = SwipeTrailFx.chromaShift(0, 0)
        XCTAssertEqual(g0.dx, 0, accuracy: 1e-9); XCTAssertEqual(g0.dy, -2.5, accuracy: 1e-9)
        let g1 = SwipeTrailFx.chromaShift(1, 1)
        XCTAssertEqual(g1.dx, 8 * 3.0.squareRoot() / 2, accuracy: 1e-9); XCTAssertEqual(g1.dy, 4, accuracy: 1e-9)
        let g2 = SwipeTrailFx.chromaShift(2, 0.5)
        XCTAssertEqual(g2.dx, -5.25 * 3.0.squareRoot() / 2, accuracy: 1e-9); XCTAssertEqual(g2.dy, 2.625, accuracy: 1e-9)
        let m4 = SwipeTrailFx.trajectory(.melt, 4)
        XCTAssertEqual(m4.dx, 2 * 0.6, accuracy: 1e-9); XCTAssertEqual(m4.dy, 14); XCTAssertEqual(m4.duration, 0.68, accuracy: 1e-9)
        for v in 0..<SwipeTrailFx.variants(.melt) { XCTAssertGreaterThan(SwipeTrailFx.trajectory(.melt, v).dy, 0, "giọt rơi xuống") }
        XCTAssertEqual(SwipeTrailStyle.kaleidoscope.strokes(base: 6, trail: 0, accent: 0, dark: false).map(\.argb),
                       [0x73FF_FFFF, 0xFFFF_FFFF, 0xD9FF_FFFF])
        XCTAssertEqual(SwipeTrailStyle.kaleidoscope.strokes(base: 6, trail: 0, accent: 0, dark: false).map(\.kind),
                       [.mirror, .conic, .stroke])
        let k = SwipeTrailStyle.kaleidoscope.strokes(base: 6, trail: 0, accent: 0, dark: false)
        XCTAssertLessThan(k[0].width, k[1].width, "nhánh mảnh hơn nét thật")
        XCTAssertLessThan(k[0].argb >> 24, k[1].argb >> 24, "nhánh mờ hơn nét thật")
        XCTAssertEqual(SwipeTrailStyle.melt.strokes(base: 6, trail: 0, accent: 0, dark: false).map(\.argb),
                       [0x73FF_4D6D, 0xBFFF_4D6D, 0xFFFF_4D6D])
        XCTAssertEqual(SwipeTrailStyle.chroma.strokes(base: 6, trail: 0x99AB_CDEF, accent: 0, dark: false).map(\.argb),
                       [0x99FF_2D55, 0x9930_D158, 0x990A_84FF, 0x99AB_CDEF])
        XCTAssertEqual(SwipeTrailStyle.melt.particleColors(accent: 0), [0xFF4D6D, 0xE8FF4D, 0x4DD8FF])
    }

    private func line(_ r: SwipeTrailRenderer, _ n: Int = 20) {
        r.begin(bounds: CGRect(x: 0, y: 0, width: 400, height: 300))
        for i in 0..<n { r.add(CGPoint(x: 20 + Double(i) * 15, y: 150), Double(i) * 0.01); r.redraw() }
    }

    /// Ảo ảnh: 5 nhánh = CAReplicatorLayer nhân CÙNG path (không dựng 6 path), xoay 60° quanh tâm vùng phím;
    /// màu = MỘT gradient nón xoay trên render server; settle ⇒ 0 animation.
    @MainActor func testKaleidoscopeReplicatesOnePathAroundKeyboardCentre() throws {
        let r = SwipeTrailRenderer()
        r.configure(style: .kaleidoscope, trail: .white, accent: RGBA(hex: 0x0A84FF), dark: true)
        XCTAssertEqual(r.debugLoopCount, 1, "chỉ animation xoay bánh xe màu")
        line(r)
        let paths = r.debugStrokeLayers.compactMap(\.path)
        XCTAssertEqual(paths.count, 3)
        XCTAssertTrue(paths.allSatisfy { $0 == paths[0] }, "mọi lớp (nét thật, nhánh, lõi) vẽ CÙNG một path (CA giữ bản sao bất biến)")
        let rep = try XCTUnwrap(r.debugMirror)
        XCTAssertEqual(rep.instanceCount, SwipeTrailFx.kaleidoBranches - 1)
        XCTAssertEqual(rep.sublayers?.count, 1)
        XCTAssertEqual(Double(rep.instanceTransform.m11), 0.5, accuracy: 1e-9)
        XCTAssertEqual(Double(rep.instanceTransform.m12), 3.0.squareRoot() / 2, accuracy: 1e-9, "xoay 60°")
        XCTAssertEqual(rep.bounds, CGRect(x: 0, y: 0, width: 400, height: 300))
        XCTAssertEqual(rep.position, CGPoint(x: 200, y: 150), "xoay quanh tâm vùng phím")
        let hue = try XCTUnwrap(r.debugHue)
        XCTAssertEqual(hue.type, .conic)
        XCTAssertEqual(hue.colors?.count, SwipeTrailFx.hueWheel.count)
        XCTAssertEqual(hue.position, CGPoint(x: 200, y: 150))
        XCTAssertEqual(Double(hue.bounds.width), 500, accuracy: 0.01, "cạnh = đường chéo: xoay không lộ góc")
        XCTAssertNotNil(hue.animation(forKey: "spin"))
        XCTAssertEqual(r.debugAnimationCount, 1)
        XCTAssertNil(r.debugGradient)
        r.fadeOut(reduceMotion: true)
        XCTAssertEqual(r.debugAnimationCount, 0, "huỷ ⇒ gỡ ngay animation lặp")
        line(r)
        r.fadeOut(reduceMotion: false)
        r.settleNow()
        XCTAssertEqual(r.debugAnimationCount, 0)
    }

    /// Tan chảy: 3 đoạn theo chiều dài (cũ mờ hơn), đổi màu + thở bằng animation CA, đuôi chảy xuống ≤ meltDrip.
    @MainActor func testMeltSegmentsSagAndRenderServerLoops() throws {
        let r = SwipeTrailRenderer()
        r.configure(style: .melt, trail: .white, accent: RGBA(hex: 0x0A84FF), dark: false)
        let ls = r.debugStrokeLayers
        XCTAssertEqual(ls.map { Double($0.strokeStart) }, [0, 0.35, 0.7])
        XCTAssertEqual(ls.map { Double($0.strokeEnd) }, [0.35, 0.7, 1])
        XCTAssertTrue(ls.allSatisfy { $0.lineCap == .butt }, "đầu bằng: không cục sáng ở chỗ nối đoạn")
        XCTAssertEqual(ls.map { $0.opacity }, [1, 1, 1])
        XCTAssertEqual(r.debugLoopCount, 6, "mỗi đoạn: đổi màu + thở")
        line(r, 25)   // 0,24 s < đuôi 0,3 s: đủ 25 điểm
        for l in ls {
            XCTAssertNotNil(l.animation(forKey: "breath"))
            XCTAssertNotNil(l.animation(forKey: "tint"))
        }
        let box = try XCTUnwrap(ls.first?.path).boundingBoxOfPath
        XCTAssertEqual(Double(box.minY), 150, accuracy: 0.01, "điểm mới nhất không chảy")
        XCTAssertEqual(Double(box.maxY), 150 + SwipeTrailFx.meltSag(0.24 / SwipeTrailRenderer.tail), accuracy: 0.01, "điểm cũ nhất chảy xuống nhiều nhất")
        XCTAssertLessThanOrEqual(Double(box.maxY) - 150, SwipeTrailFx.meltDrip + 0.01)
        let breath = try XCTUnwrap(ls[2].animation(forKey: "breath") as? CAKeyframeAnimation)
        let w = Double(ls[2].lineWidth)
        XCTAssertEqual((breath.values as? [Double])?.max() ?? 0, w * 1.3, accuracy: 1e-6)
        XCTAssertEqual((breath.values as? [Double])?.min() ?? 0, w * 0.7, accuracy: 1e-6)
        XCTAssertEqual(breath.duration, SwipeTrailFx.meltBreathPeriod)
        let tint = try XCTUnwrap(ls[0].animation(forKey: "tint") as? CAKeyframeAnimation)
        XCTAssertEqual(tint.values?.count, SwipeTrailFx.hueWheel.count)
        XCTAssertEqual(tint.duration, SwipeTrailFx.meltHuePeriod)
        r.fadeOut(reduceMotion: false)
        r.settleNow()
        XCTAssertEqual(r.debugAnimationCount, 0)
    }

    /// Vệt lặp: 3 bóng R/G/B dưới nét chính, lệch chromaOffset lúc vuốt; nhấc tay ⇒ trôi tới chromaDrift + mờ
    /// (chậm hơn nét chính); cú vuốt sau bóng về chỗ cũ; settle ⇒ 0 animation.
    @MainActor func testChromaGhostsDriftApartAfterLift() throws {
        let r = SwipeTrailRenderer()
        let before = SwipeTrailRenderer()
        before.configure(style: .simple, trail: .white, accent: .white, dark: false)
        r.configure(style: .chroma, trail: .white, accent: RGBA(hex: 0x0A84FF), dark: true)
        XCTAssertEqual(r.debugGhosts.count, 3)
        XCTAssertEqual(r.debugSublayerCount, before.debugSublayerCount + 1 + 3, "nhóm bóng + 3 bóng (lõi thay nét Đơn giản)")
        let ghostRoot = try XCTUnwrap(r.debugGhosts.first?.superlayer)
        XCTAssertTrue(r.layer.sublayers?.first === ghostRoot, "bóng nằm dưới nét chính")
        line(r)
        let gp = r.debugStrokeLayers.compactMap(\.path)
        XCTAssertEqual(gp.count, 4)
        XCTAssertTrue(gp.allSatisfy { $0 == gp[0] }, "bóng + nét chính vẽ CÙNG một path")
        for (i, g) in r.debugGhosts.enumerated() {
            let d = SwipeTrailFx.chromaShift(i, 0)
            XCTAssertEqual(Double(g.transform.m41), d.dx, accuracy: 1e-9); XCTAssertEqual(Double(g.transform.m42), d.dy, accuracy: 1e-9)
        }
        XCTAssertEqual(r.debugAnimationCount, 0, "đang vuốt: bóng đứng yên, không animation")
        r.fadeOut(reduceMotion: false)
        XCTAssertNotNil(ghostRoot.animation(forKey: "fade"))
        XCTAssertEqual(ghostRoot.animation(forKey: "fade")?.duration, SwipeTrailFx.chromaFade)
        for (i, g) in r.debugGhosts.enumerated() {
            XCTAssertNotNil(g.animation(forKey: "drift"))
            XCTAssertEqual(Double(g.transform.m41), SwipeTrailFx.chromaShift(i, 1).dx, accuracy: 1e-9)
        }
        r.settleNow()
        XCTAssertEqual(r.debugAnimationCount, 0)
        line(r)
        XCTAssertEqual(ghostRoot.opacity, 1)
        XCTAssertEqual(Double(r.debugGhosts[1].transform.m42), SwipeTrailFx.chromaShift(1, 0).dy, accuracy: 1e-9)
        // Đổi sang kiểu khác ⇒ gỡ nhóm bóng.
        r.configure(style: .simple, trail: .white, accent: .white, dark: false)
        XCTAssertEqual(r.debugSublayerCount, before.debugSublayerCount)
    }

    // MARK: Phím sáng theo đường / Thư pháp / Sao chổi / Đom đóm / Ma trận / Cánh hoa (số tham chiếu chung Android)

    func testSixNewStylesPureParity() {
        // Thư pháp: ngòi 35°, mực đọng ở chỗ chậm.
        XCTAssertEqual(SwipeTrailFx.nibFactor(dx: 1, dy: 0), 0.701504, accuracy: 1e-6)
        XCTAssertEqual(SwipeTrailFx.nibFactor(dx: 0, dy: 1), 0.873406, accuracy: 1e-6)
        XCTAssertEqual(SwipeTrailFx.nibFactor(dx: cos(35 * .pi / 180), dy: sin(35 * .pi / 180)), SwipeTrailFx.nibMin, accuracy: 1e-9,
                       "dọc theo ngòi ⇒ mảnh nhất")
        XCTAssertEqual(SwipeTrailFx.nibFactor(dx: -cos(55 * .pi / 180), dy: sin(55 * .pi / 180)), 1, accuracy: 1e-9,
                       "vuông góc ngòi ⇒ dày nhất")
        XCTAssertEqual(SwipeTrailFx.nibFactor(dx: 0, dy: 0), 1)
        XCTAssertEqual(SwipeTrailFx.calliPool(speed: 0), 4)
        XCTAssertEqual(SwipeTrailFx.calliPool(speed: 0.125), 2, accuracy: 1e-9)
        XCTAssertEqual(SwipeTrailFx.calliPool(speed: 0.3), 0)
        XCTAssertEqual(SwipeTrailFx.calliWidth(speed: 0.8, dx: 1, dy: 0), 5.480496, accuracy: 1e-6)
        XCTAssertEqual(SwipeTrailFx.calliWidth(speed: 0.1, dx: 0, dy: 1), 12.805819, accuracy: 1e-6)
        XCTAssertEqual(SwipeTrailFx.calliWidth(speed: 0, dx: 0, dy: 0), 16.5, accuracy: 1e-9)
        // Dấu triện + nhịp đom đóm (keyframes tuyến tính = CA).
        XCTAssertEqual(SwipeTrailFx.keyframe(0.075, SwipeTrailFx.sealScaleT, SwipeTrailFx.sealScaleV), 1.175, accuracy: 1e-9)
        XCTAssertEqual(SwipeTrailFx.keyframe(0.5, SwipeTrailFx.sealScaleT, SwipeTrailFx.sealScaleV), 1)
        XCTAssertEqual(SwipeTrailFx.keyframe(0.04, SwipeTrailFx.sealAlphaT, SwipeTrailFx.sealAlphaV), 0.5, accuracy: 1e-9)
        XCTAssertEqual(SwipeTrailFx.keyframe(0.3, SwipeTrailFx.sealAlphaT, SwipeTrailFx.sealAlphaV), 1)
        XCTAssertEqual(SwipeTrailFx.keyframe(0.8, SwipeTrailFx.sealAlphaT, SwipeTrailFx.sealAlphaV), 0.5, accuracy: 1e-9)
        XCTAssertEqual(SwipeTrailFx.keyframe(2, SwipeTrailFx.sealAlphaT, SwipeTrailFx.sealAlphaV), 0)
        XCTAssertEqual(SwipeTrailFx.keyframe(0.25, SwipeTrailFx.fireflyPulseT, SwipeTrailFx.fireflyPulseV), 0.675, accuracy: 1e-9)
        XCTAssertEqual(SwipeTrailFx.sealMarks.count, 5)
        XCTAssertEqual(SwipeTrailFx.sealLife + SwipeTrailFx.fade, 1.1, accuracy: 1e-9)
        XCTAssertLessThanOrEqual(SwipeTrailFx.sealLife, SwipeTrailFx.maxParticleLife, "settle sau khi dấu tắt")
        // Phím sáng: tắt tuyến tính 0,35 s sau khi rời phím.
        XCTAssertEqual(SwipeTrailFx.keyGlowAlpha(sinceLeave: -1), 1)
        XCTAssertEqual(SwipeTrailFx.keyGlowAlpha(sinceLeave: 0), 1)
        XCTAssertEqual(SwipeTrailFx.keyGlowAlpha(sinceLeave: 0.175), 0.5, accuracy: 1e-9)
        XCTAssertEqual(SwipeTrailFx.keyGlowAlpha(sinceLeave: 0.35), 0)
        XCTAssertEqual(SwipeTrailFx.keyGlowAlpha(sinceLeave: 1), 0)
        // Dò phím: khung nới 2, nhiều khung ⇒ tâm gần nhất (hoà ⇒ phím trước).
        let L: [Double] = [0, 32, 0], T: [Double] = [0, 0, 44], R: [Double] = [30, 62, 30], B: [Double] = [40, 40, 84]
        func hit(_ x: Double, _ y: Double) -> Int { SwipeTrailFx.keyHit(x: x, y: y, minX: L, minY: T, maxX: R, maxY: B) }
        XCTAssertEqual(hit(15, 20), 0)
        XCTAssertEqual(hit(31, 20), 0)
        XCTAssertEqual(hit(31.5, 20), 1)
        XCTAssertEqual(hit(15, 42), 0)
        XCTAssertEqual(hit(15, 43), 2)
        XCTAssertEqual(hit(-2, 0), 0)
        XCTAssertEqual(hit(-2.5, 0), -1)
        XCTAssertEqual(hit(100, 100), -1)
        XCTAssertEqual(SwipeTrailFx.keyHit(x: 1, y: 1, minX: [], minY: [], maxX: [], maxY: []), -1)
        // Ma trận: chữ của phím đang qua, cứ 3 chữ có 1 chữ số.
        XCTAssertEqual(SwipeTrailFx.matrixGlyphs.count, 36)
        XCTAssertEqual(SwipeTrailFx.matrixGlyph(spawn: 0, key: "v"), 21)
        XCTAssertEqual(SwipeTrailFx.matrixGlyph(spawn: 1, key: "a"), 0)
        XCTAssertEqual(SwipeTrailFx.matrixGlyph(spawn: 2, key: "a"), 30)
        XCTAssertEqual(SwipeTrailFx.matrixGlyph(spawn: 3, key: nil), 27)
        XCTAssertEqual(SwipeTrailFx.matrixGlyph(spawn: 4, key: "Q"), 16)
        XCTAssertEqual(SwipeTrailFx.matrixGlyph(spawn: 4, key: "é"), 34)
        // Sao chổi: đuôi 0,6 s; đoạn trắng dần về đầu.
        XCTAssertEqual(SwipeTrailFx.tail(.comet), 0.6)
        XCTAssertEqual(SwipeTrailFx.tail(.simple), 0.3)
        XCTAssertEqual(SwipeTrailFx.tail(.melt), SwipeTrailRenderer.tail)
        let comet = SwipeTrailStyle.comet.strokes(base: 6, trail: 0, accent: 0x0A84FF, dark: false)
        XCTAssertEqual(comet.map(\.argb), [0x4D0A_84FF, 0x8C47_A3FF, 0xCC9D_CEFF, 0xFFFF_FFFF, 0x470A_84FF, 0xFFFF_FFFF])
        XCTAssertEqual(comet.map(\.kind), [.segment, .segment, .segment, .segment, .head, .head])
        for (s, w) in zip(comet, [2.7, 4.8, 6.9, 9, 26.4, 9]) { XCTAssertEqual(s.width, w, accuracy: 1e-9, "đuôi mảnh → đầu dày") }
        XCTAssertEqual(SwipeTrailStyle.calligraphy.strokes(base: 6, trail: 0, accent: 0, dark: false).map(\.argb), [0xF014_1210])
        XCTAssertEqual(SwipeTrailStyle.calligraphy.strokes(base: 6, trail: 0, accent: 0, dark: true).map(\.argb), [0xF0EE_E8DC])
        XCTAssertEqual(SwipeTrailStyle.calligraphy.strokes(base: 6, trail: 0, accent: 0, dark: true).first?.kind, .fill)
        XCTAssertEqual(SwipeTrailStyle.keys.strokes(base: 6, trail: 0, accent: 0x0A84FF, dark: true).map(\.argb), [0x4D0A_84FF], "nét rất mờ")
        // Hạt: quỹ đạo + màu.
        XCTAssertEqual([SwipeTrailStyle.firefly, .matrix, .petals].map(\.spawnEvery), [3, 3, 4])
        XCTAssertEqual([SwipeTrailStyle.firefly, .matrix, .petals].map { SwipeTrailFx.variants($0) }, [6, 6, 8])
        let f4 = SwipeTrailFx.trajectory(.firefly, 4)
        XCTAssertEqual(f4.dx, 3.6, accuracy: 1e-9); XCTAssertEqual(f4.dy, -7); XCTAssertEqual(f4.duration, 1.1, accuracy: 1e-9)
        XCTAssertEqual(f4.sway, 2.5)
        let p7 = SwipeTrailFx.trajectory(.petals, 7)
        XCTAssertEqual(p7.dx, 10, accuracy: 1e-9); XCTAssertEqual(p7.dy, 24); XCTAssertEqual(p7.rotation, 2.4, accuracy: 1e-9)
        XCTAssertEqual(p7.duration, 1.03, accuracy: 1e-9)
        let m5 = SwipeTrailFx.trajectory(.matrix, 5)
        XCTAssertEqual(m5.dx, 0); XCTAssertEqual(m5.dy, 24); XCTAssertEqual(m5.duration, 0.86, accuracy: 1e-9)
        for v in 0..<8 { XCTAssertGreaterThan(SwipeTrailFx.trajectory(.petals, v).dy, 0, "cánh hoa rơi xuống") }
        for v in 0..<6 { XCTAssertLessThan(SwipeTrailFx.trajectory(.firefly, v).dy, 0, "đom đóm bay lên") }
        XCTAssertEqual(SwipeTrailStyle.petals.particleColors(accent: 0), [0xF58FB1, 0xFFC8DA, 0xF7A8C4])
        XCTAssertEqual(SwipeTrailStyle.firefly.particleColors(accent: 0), [0xD8FF5A, 0xF2FF8A, 0xB6F23A])
        XCTAssertEqual(SwipeTrailStyle.matrix.particleColors(accent: 0), [0x3DFF6E, 0x00E05A, 0xB6FFC8])
    }

    private static let keysBounds = CGRect(x: 0, y: 0, width: 400, height: 300)

    /// Phím sáng theo đường: đi qua q → w → e ⇒ 3 ô sáng đúng thứ tự, ô đang có ngón "chưa mờ", ô đã rời bắt
    /// đầu mờ (beginTime = lúc rời); không thêm layer / animation mới mỗi lần di chuyển; settle ⇒ 0 animation.
    @MainActor func testKeyGlowLightsKeysInOrderAndFades() throws {
        let r = SwipeTrailRenderer()
        r.configure(style: .keys, trail: .white, accent: RGBA(hex: 0x0A84FF), dark: false)
        XCTAssertEqual(r.debugGlows.count, SwipeTrailFx.keyGlowCap)
        XCTAssertTrue(r.layer.sublayers?.first === r.debugGlows.first?.superlayer, "ô sáng nằm DƯỚI nét")
        let rects = [CGRect(x: 0, y: 100, width: 40, height: 50), CGRect(x: 40, y: 100, width: 40, height: 50),
                     CGRect(x: 80, y: 100, width: 40, height: 50)]
        r.setKeys(rects, ["q", "w", "e"], hitDy: 4)
        r.begin(bounds: Self.keysBounds)
        let layers0 = r.debugSublayerCount
        // y 129 − hitDy 4 = 125: giữa hàng. 13 điểm, bước 9 pt.
        for i in 0..<13 { r.add(CGPoint(x: 5 + Double(i) * 9, y: 129), Double(i) * 0.01); r.redraw() }
        XCTAssertEqual(r.debugLitKeys, [0, 1, 2], "sáng theo thứ tự phím đi qua")
        XCTAssertEqual(r.debugLitNow, 2, "phím cuối: ngón còn trong phím")
        XCTAssertEqual(r.debugSublayerCount, layers0, "không thêm layer khi vuốt")
        let g = r.debugGlows
        XCTAssertEqual(g[0].frame, rects[0])
        XCTAssertEqual(g[2].frame, rects[2])
        XCTAssertNotNil(g[0].animation(forKey: "fade"))
        XCTAssertGreaterThan(g[2].beginTime, g[0].beginTime + 1e6, "ô đang sáng: animation mờ chưa tới lượt")
        XCTAssertEqual(r.debugAnimationCount, 3, "mỗi ô MỘT animation (gắn một lần)")
        // Ra ngoài phím ⇒ ô cuối bắt đầu mờ.
        r.add(CGPoint(x: 200, y: 129), 0.2)
        XCTAssertNil(r.debugLitNow)
        XCTAssertLessThan(g[2].beginTime, g[0].beginTime + 1, "rời phím ⇒ bắt đầu mờ ngay")
        r.fadeOut(reduceMotion: false)
        r.settleNow()
        XCTAssertEqual(r.debugAnimationCount, 0)
        XCTAssertEqual(r.debugLitKeys, [])
        // Huỷ ⇒ ô tắt ngay; dời điểm chọn phím (hitDy): y 104 − 4 = 100 vẫn trong phím, y 101 − 4 = 97 thì nới 2 chưa tới.
        r.begin(bounds: Self.keysBounds)
        r.add(CGPoint(x: 20, y: 104), 1)
        XCTAssertEqual(r.debugCurrentKey, 0)
        r.add(CGPoint(x: 20, y: 101), 1.01)
        XCTAssertEqual(r.debugCurrentKey, -1)
        r.fadeOut(reduceMotion: true)
        XCTAssertEqual(r.debugLitKeys, [])
        // Kiểu không cần phím: setKeys = 0 việc.
        let other = SwipeTrailRenderer()
        other.configure(style: .simple, trail: .white, accent: .white, dark: false)
        other.setKeys(rects, ["q", "w", "e"], hitDy: 4)
        other.begin(bounds: Self.keysBounds)
        other.add(CGPoint(x: 20, y: 129), 0)
        XCTAssertEqual(other.debugCurrentKey, -1)
        XCTAssertEqual(other.debugGlows.count, 0)
    }

    /// Thư pháp: dải kín (MỘT path), chỗ chậm dày hơn chỗ nhanh, hướng nét đổi bề rộng (ngòi xiên); nhấc tay ⇒
    /// dấu triện son ở điểm cuối (animation gắn một lần), settle ⇒ ẩn + 0 animation.
    @MainActor func testCalligraphyNibAndSealStamp() throws {
        func height(_ step: Double, dx: Double, dy: Double) throws -> CGFloat {
            let r = SwipeTrailRenderer()
            r.configure(style: .calligraphy, trail: .white, accent: .white, dark: false)
            r.begin(bounds: Self.keysBounds)
            for i in 0..<30 { r.add(CGPoint(x: 50 + Double(i) * dx, y: 50 + Double(i) * dy), Double(i) * step) }
            r.redraw()
            let box = try XCTUnwrap(r.debugStrokeLayers.first?.path).boundingBoxOfPath
            return dx == 0 ? box.width : box.height   // bề dày vuông góc hướng vuốt
        }
        XCTAssertGreaterThan(try height(0.008, dx: 1, dy: 0), try height(0.001, dx: 4, dy: 0), "chậm ⇒ dày (mực đọng)")
        XCTAssertGreaterThan(try height(0.002, dx: 0, dy: 4), try height(0.002, dx: 4, dy: 0), "dọc dày hơn ngang (ngòi 35°)")
        let r = SwipeTrailRenderer()
        r.configure(style: .calligraphy, trail: .white, accent: .white, dark: true)
        XCTAssertEqual(Double(r.debugStrokeLayers.first?.fillColor?.alpha ?? 0), 240.0 / 255, accuracy: 1e-6)
        let seal = try XCTUnwrap(r.debugSeal)
        XCTAssertTrue(seal.isHidden)
        XCTAssertEqual(seal.sublayers?.count, 1, "nét khắc trắng")
        r.begin(bounds: Self.keysBounds)
        for i in 0..<10 { r.add(CGPoint(x: 20 + Double(i) * 10, y: 80), Double(i) * 0.01); r.redraw() }
        XCTAssertTrue(seal.isHidden, "chưa nhấc tay")
        r.fadeOut(reduceMotion: false)
        XCTAssertFalse(seal.isHidden)
        XCTAssertEqual(seal.position, CGPoint(x: 110, y: 80))
        let stamp = try XCTUnwrap(seal.animation(forKey: "stamp"))
        XCTAssertEqual(stamp.duration, SwipeTrailFx.sealLife)
        r.settleNow()
        XCTAssertTrue(seal.isHidden)
        XCTAssertEqual(r.debugAnimationCount, 0)
        // Huỷ ⇒ không đóng dấu.
        r.begin(bounds: Self.keysBounds)
        r.add(CGPoint(x: 1, y: 1), 0); r.add(CGPoint(x: 9, y: 1), 0.01)
        r.fadeOut(reduceMotion: true)
        XCTAssertTrue(seal.isHidden)
    }

    /// Sao chổi: đuôi 0,6 s (giữ điểm Đơn giản đã bỏ), 4 đoạn chung MỘT path, đầu sáng = 2 chấm dời theo ngón.
    @MainActor func testCometLongTailSegmentsAndHead() throws {
        let r = SwipeTrailRenderer()
        r.configure(style: .comet, trail: .white, accent: RGBA(hex: 0x0A84FF), dark: true)
        XCTAssertEqual(r.debugTail, 0.6)
        XCTAssertEqual(r.debugHeads.count, 2)
        let segs = r.debugStrokeLayers.filter { !r.debugHeads.contains($0) }
        XCTAssertEqual(segs.map { Double($0.strokeStart) }, [0, 0.4, 0.7, 0.88])
        XCTAssertEqual(segs.map { Double($0.strokeEnd) }, [0.4, 0.7, 0.88, 1])
        r.begin(bounds: Self.keysBounds)
        XCTAssertTrue(r.debugHeads.allSatisfy(\.isHidden))
        for i in 0..<60 { r.add(CGPoint(x: 10 + Double(i) * 5, y: 150), Double(i) * 0.01) }   // 0,59 s
        r.redraw()
        XCTAssertEqual(r.debugPointCount, 60, "đuôi 0,6 s giữ cả 60 điểm (Đơn giản chỉ ~31)")
        let paths = segs.compactMap(\.path)
        XCTAssertEqual(paths.count, 4)
        XCTAssertTrue(paths.allSatisfy { $0 == paths[0] }, "4 đoạn chung một path")
        for h in r.debugHeads {
            XCTAssertFalse(h.isHidden)
            XCTAssertEqual(h.position, CGPoint(x: 305, y: 150), "đầu sáng ở ngón")
            XCTAssertNotNil(h.path)
        }
        let simple = SwipeTrailRenderer()
        simple.configure(style: .simple, trail: .white, accent: .white, dark: false)
        simple.begin(bounds: Self.keysBounds)
        for i in 0..<60 { simple.add(CGPoint(x: 10 + Double(i) * 5, y: 150), Double(i) * 0.01) }
        XCTAssertLessThan(simple.debugPointCount, 35)
        r.fadeOut(reduceMotion: false)
        r.settleNow()
        XCTAssertTrue(r.debugHeads.allSatisfy(\.isHidden))
        XCTAssertEqual(r.debugAnimationCount, 0)
    }

    /// Ma trận: chữ rơi = path glyph dựng sẵn (static) theo phím đang đi qua; Đom đóm có quầng (shadowPath sẵn);
    /// Cánh hoa xoay. Pool cố định.
    @MainActor func testMatrixGlyphsFollowKeysAndParticleShapes() throws {
        XCTAssertEqual(SwipeTrailRenderer.glyphPaths.count, 36)
        XCTAssertTrue(SwipeTrailRenderer.glyphPaths.allSatisfy { !$0.boundingBoxOfPath.isEmpty }, "mọi chữ có nét")
        let v = SwipeTrailRenderer.glyphPaths[21].boundingBoxOfPath
        XCTAssertEqual(Double(v.midX), 0, accuracy: 0.6); XCTAssertEqual(Double(v.midY), 0, accuracy: 0.6)
        let r = SwipeTrailRenderer()
        r.configure(style: .matrix, trail: .white, accent: .white, dark: true)
        XCTAssertEqual(r.debugGlows.count, 0, "Ma trận không có ô sáng")
        r.setKeys([CGRect(x: 0, y: 0, width: 400, height: 300)], ["v"], hitDy: 0)
        r.begin(bounds: Self.keysBounds)
        for i in 0..<9 { r.add(CGPoint(x: 20 + Double(i) * 8, y: 150), Double(i) * 0.01) }   // bắn 3 chữ: v, v, số
        let shown = r.debugParticles.prefix(3).map { $0.path }
        XCTAssertEqual(shown[0], SwipeTrailRenderer.glyphPaths[21])
        XCTAssertEqual(shown[1], SwipeTrailRenderer.glyphPaths[21])
        XCTAssertEqual(shown[2], SwipeTrailRenderer.glyphPaths[30])
        XCTAssertNotEqual(shown[2], SwipeTrailRenderer.glyphPaths[21])
        XCTAssertEqual(r.debugVisibleParticles, 3)
        let f = SwipeTrailRenderer()
        f.configure(style: .firefly, trail: .white, accent: .white, dark: true)
        XCTAssertTrue(f.debugParticles.allSatisfy { $0.shadowPath != nil && $0.shadowOpacity > 0 }, "quầng đom đóm")
        let p = SwipeTrailRenderer()
        p.configure(style: .petals, trail: .white, accent: .white, dark: false)
        XCTAssertEqual(p.debugParticles.count, SwipeTrailFx.particleCap)
        XCTAssertTrue(p.debugParticles.allSatisfy { $0.path == p.debugParticles[0].path }, "một path cánh hoa dùng chung")
        XCTAssertNotEqual(p.debugParticles[0].path?.boundingBoxOfPath.height, p.debugParticles[0].path?.boundingBoxOfPath.width,
                          "cánh hoa thuôn (không tròn)")
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
        // Phím sáng theo đường: bàn phím giao khung phím chữ lúc bắt đầu vuốt ⇒ v, i, e, t (và phím giữa) sáng.
        withKeyboard("keys", plus: true) { kb in
            XCTAssertEqual(kb.trailStyle, .keys)
            XCTAssertTrue(swipe(kb, "viet"))
            let lit = kb.debugTrail?.debugLitKeys ?? []
            XCTAssertGreaterThanOrEqual(lit.count, 4, "\(lit)")
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
        let keys = SwipeTrailRenderer.sampleKeys(in: bounds)   // ~ bàn phím thật: 26 phím phủ vùng vuốt
        func run(_ s: SwipeTrailStyle, swipes: Int) -> [Double] {
            let r = SwipeTrailRenderer()
            r.configure(style: s, trail: RGBA(hex: 0xFFFFFF, alpha: 0.6), accent: RGBA(hex: 0x0A84FF), dark: false)
            win.layer.addSublayer(r.layer)
            defer { r.settleNow(); r.layer.removeFromSuperlayer() }
            var out: [Double] = []
            out.reserveCapacity(swipes * path.count)
            var t = CACurrentMediaTime()
            for _ in 0..<swipes {
                r.setKeys(keys.rects, keys.chars, hitDy: 4)   // kiểu không cần phím: 0 việc (như KeyboardView)
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
        let styles: [SwipeTrailStyle] = [.fire, .electric, .brush, .rainbow, .neon, .stardust, .firework, .plasma,
                                          .kaleidoscope, .melt, .chroma, .keys, .calligraphy, .comet, .firefly,
                                          .matrix, .petals]
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
