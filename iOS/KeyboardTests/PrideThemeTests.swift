// Theme "Tự hào" (11/2026): lá cờ + bảng màu (Pride.swift), vòng cung Cầu vồng (RainbowBurst), cờ phấp phới + tim
// (PrideFlagWave), từ khoá (PrideKeywords), "variant":"pride" giải lúc hiện (viền aurora theo sọc cờ), sao lưu `prideFlag`.
// Số tham chiếu GIỐNG HỆT android PrideThemeTests.kt.
import XCTest
import UIKit

final class PrideThemeTests: XCTestCase {
    private let suite = "vt-pride-theme"

    override func setUp() {
        super.setUp()
        #if DEBUG
        KeyEffectOverlay.drawsOffscreen = true
        #endif
    }

    override func tearDown() {
        #if DEBUG
        KeyEffectOverlay.drawsOffscreen = false
        #endif
        UserDefaults(suiteName: suite)!.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testIds() {
        XCTAssertEqual(PrideFlag.allCases.map(\.rawValue), ["rainbow", "trans", "bi", "pan", "lesbian", "nonbinary"])
        XCTAssertEqual(PrideFlag.key, "prideFlag")
        XCTAssertEqual(PrideFlag.parse("bi"), .bi)
        XCTAssertEqual(PrideFlag.parse("x"), .rainbow)
        XCTAssertEqual(KeyboardTheme.pride.rawValue, "pride")
        XCTAssertEqual(KeyEffect.rainbowburst.rawValue, "rainbowburst")
        XCTAssertTrue(KeyEffect.rainbowburst.needsBoundaryWord)
        XCTAssertFalse(KeyEffect.rainbowburst.isQueued, "mỗi phím đều bắn vòng cung")
        XCTAssertTrue(ThemeExtraIds.effects.contains("rainbowburst"))
        XCTAssertEqual(ThemeVariants.pride, "pride")
        XCTAssertTrue(ThemeVariants.known.contains("pride"))
        XCTAssertEqual(L10n.en["Tự hào"], "Pride")
        XCTAssertEqual(L10n.en["Chuyển giới"], "Transgender")
        XCTAssertEqual(L10n.en["Phi nhị nguyên"], "Non-binary")
    }

    func testFlagStripesAndPalettesContrast() {
        XCTAssertEqual(PrideFlag.allCases.map { $0.stripes.count }, [6, 5, 3, 3, 5, 4])
        XCTAssertEqual(PrideFlag.rainbow.stripes.first, 0xE40303)
        XCTAssertEqual(PrideFlag.trans.stripes[2], 0xFFFFFF)
        for f in PrideFlag.allCases {
            XCTAssertLessThanOrEqual(f.stripes.count, 6)
            let p = ThemeSpec.palette(f.slots)
            XCTAssertTrue(p.isDark, f.rawValue)
            XCTAssertTrue(p.auroraBorder, f.rawValue)
            XCTAssertEqual(p.decoration?.motif, .hearts, f.rawValue)
            XCTAssertGreaterThanOrEqual(RGBA.contrast(p.ink, p.keyFill), 4.5, f.rawValue)
            XCTAssertGreaterThanOrEqual(RGBA.contrast(p.fnInk, p.fnFill), 4.5, f.rawValue)
            XCTAssertGreaterThanOrEqual(RGBA.contrast(p.accentInk, p.accent), 4.5, f.rawValue)
            XCTAssertGreaterThanOrEqual(RGBA.contrast(p.ink, p.background!), 4.5, f.rawValue)
        }
    }

    func testRainbowBurstMath() {
        XCTAssertEqual(RainbowBurst.radius(0), 44.4, accuracy: 1e-9)
        XCTAssertEqual(RainbowBurst.radius(5), 28.4, accuracy: 1e-9)
        XCTAssertEqual(RainbowBurst.alpha(0.04), 0.45, accuracy: 1e-9)
        XCTAssertEqual(RainbowBurst.alpha(0.44), 0.45, accuracy: 1e-9)
        XCTAssertEqual(RainbowBurst.alpha(0.8), 0)
        XCTAssertEqual(RainbowBurst.scale(0), 0.15, accuracy: 1e-9)
        XCTAssertEqual(RainbowBurst.scale(0.4), 0.7875, accuracy: 1e-9)
        XCTAssertEqual(RainbowBurst.scale(0.8), 1, accuracy: 1e-9)
        // Không nhấp nháy: độ đục lên một lần rồi giảm đều.
        var prev = 0.0, peaked = false
        for k in 0...80 {
            let a = RainbowBurst.alpha(Double(k) / 100)
            if a < prev { peaked = true } else if peaked { XCTAssertLessThanOrEqual(a, prev) }
            prev = a
        }
    }

    func testFlagWaveMath() {
        XCTAssertEqual(PrideFlagWave.offset(0, phase: 1.3), 0, accuracy: 1e-12, "cán cờ đứng yên")
        XCTAssertEqual(PrideFlagWave.offset(14, phase: 0), 0.875, accuracy: 1e-9)
        let s = PrideFlagWave.stripe(0, of: 6, phase: 0)
        XCTAssertEqual(s.count, 2 * (PrideFlagWave.columns + 1))
        XCTAssertEqual(s[0].x, -28, accuracy: 1e-9); XCTAssertEqual(s[0].y, -46, accuracy: 1e-9)
        XCTAssertEqual(s.last!.x, -28, accuracy: 1e-9); XCTAssertEqual(s.last!.y, -40, accuracy: 1e-9)
        XCTAssertEqual(PrideFlagWave.alpha(0.075), 0.5, accuracy: 1e-9)
        XCTAssertEqual(PrideFlagWave.alpha(0.5), 1)
        XCTAssertEqual(PrideFlagWave.alpha(1.025), 0.5, accuracy: 1e-9)
        XCTAssertEqual(PrideFlagWave.riseY(0.6), -4, accuracy: 1e-9)
        XCTAssertEqual(PrideFlagWave.phase(0.6), 2 * Double.pi, accuracy: 1e-9)
        XCTAssertEqual(PrideFlagWave.heart(0).dx, -42, accuracy: 1e-9); XCTAssertEqual(PrideFlagWave.heart(0).dy, -40, accuracy: 1e-9)
        XCTAssertEqual(PrideFlagWave.heart(7).dx, 42, accuracy: 1e-9); XCTAssertEqual(PrideFlagWave.heart(7).dy, -50, accuracy: 1e-9)
        XCTAssertEqual(PrideFlagWave.heartDelay(7), 0.21, accuracy: 1e-9)
        // Mọi điểm cờ (mọi pha) nằm trong hộp quanh gốc.
        for f in 0...PrideFlagWave.frames {
            let ph = PrideFlagWave.phase(PrideFlagWave.life * Double(f) / Double(PrideFlagWave.frames))
            for i in 0..<6 {
                for p in PrideFlagWave.stripe(i, of: 6, phase: ph) {
                    XCTAssertTrue(abs(p.x) <= PrideFlagWave.width / 2 + 1e-9)
                    XCTAssertTrue(p.y >= -PrideFlagWave.gap - PrideFlagWave.height - PrideFlagWave.amplitude - 1e-9)
                    XCTAssertTrue(p.y <= -PrideFlagWave.gap + PrideFlagWave.amplitude + 1e-9)
                }
            }
        }
    }

    func testKeywords() {
        let yes: [(String, String?, String?)] = [("love", "is", "love"), ("hào", "tự", nil), ("Pride!", nil, nil),
                                                 ("yêu", "là", "yêu"), ("HÀO", "Tự", "rất"), ("pride", "my", "is")]
        let no: [(String, String?, String?)] = [("love", "is", "this"), ("hao", "tu", nil), ("yêu", "là", "em"),
                                                ("hào", nil, nil), ("love", nil, nil), ("yêu", nil, nil), ("", nil, nil),
                                                ("prides", nil, nil)]
        for (w, p, p2) in yes { XCTAssertTrue(PrideKeywords.matches(word: w, prev: p, prev2: p2), "\(p2 ?? "") \(p ?? "") \(w)") }
        for (w, p, p2) in no { XCTAssertFalse(PrideKeywords.matches(word: w, prev: p, prev2: p2), "\(p2 ?? "") \(p ?? "") \(w)") }
    }

    /// Host dời gốc bounds (#151): vòng cung + cờ trong bàn phím, cắt theo khung, pool có trần; từ khoá ⇒ cờ.
    @MainActor func testOverlayInsideKeyboardAndCapped() throws {
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 470))
        host.bounds.origin.y = -180
        let o = try XCTUnwrap(KeyEffectOverlay.install(.rainbowburst, color: .systemOrange, in: host, existing: nil))
        XCTAssertEqual(o.bounds.origin, host.bounds.origin)
        XCTAssertTrue(o.clipsToBounds)
        o.prideFlag = .trans
        for i in 0..<10 {
            o.emit(key: CGRect(x: CGFloat(i % 10) * 39, y: CGFloat(i % 3) * 90 - 170, width: 34, height: 42)); o.flush()
        }
        XCTAssertEqual(o.debugRainbowRoots.count, RainbowBurst.pool)
        XCTAssertEqual(o.debugRainbowRoots[0].sublayers?.count, PrideFlag.trans.stripes.count)
        XCTAssertNil(o.debugPrideFlagRoot, "chưa gõ từ khoá ⇒ không có cờ")
        o.queuePride()
        o.emit(key: CGRect(x: 0, y: -175, width: 34, height: 42)); o.flush()   // phím sát mép trái + mép trên
        let flag = try XCTUnwrap(o.debugPrideFlagRoot)
        XCTAssertFalse(flag.isHidden)
        XCTAssertGreaterThanOrEqual(flag.position.x - CGFloat(PrideFlagWave.width / 2), o.bounds.minX)
        XCTAssertGreaterThanOrEqual(flag.position.y - CGFloat(PrideFlagWave.gap + PrideFlagWave.height + PrideFlagWave.rise),
                                    o.bounds.minY)
        XCTAssertLessThanOrEqual(o.debugPrideLayerCount, 40)
        // Đổi cờ ⇒ dựng lại theo số sọc mới.
        o.prideFlag = .bi
        o.emit(key: CGRect(x: 100, y: 100, width: 34, height: 42)); o.flush()
        XCTAssertEqual(o.debugRainbowRoots.first?.sublayers?.count, 3)
        o.halt()
        XCTAssertTrue(o.debugRainbowRoots.allSatisfy(\.isHidden))
        _ = KeyEffectOverlay.install(.none, color: .red, in: host, existing: o)
    }

    func testPrideTheme() throws {
        let spec = try XCTUnwrap(KeyboardTheme.pride.spec)
        XCTAssertTrue(KeyboardTheme.pride.isPlus)
        XCTAssertTrue(KeyboardTheme.pride.isInteractive)
        XCTAssertEqual(spec.nameVi, "Tự hào"); XCTAssertEqual(spec.nameEn, "Pride")
        XCTAssertEqual(spec.variant, "pride")
        XCTAssertEqual(spec.effect, "rainbowburst"); XCTAssertEqual(spec.sound, "pop"); XCTAssertEqual(spec.swipe, "rainbow")
        XCTAssertEqual(spec.light, PrideFlag.rainbow.slots, "bảng dự phòng = Cầu vồng")
        XCTAssertEqual(KeyboardTheme.pride.systemBackdropKey, "systemBackdropPride")
        XCTAssertTrue(BackupSettings.all.contains { $0.key == "systemBackdropPride" })
        XCTAssertEqual({ let o = ThemePicker.interactiveOrder; let i = o.firstIndex(of: "zodiac") ?? 0; return Array(o[i..<min(i + 2, o.count)]) }(), ["zodiac", "pride"])
    }

    func testVariantResolvesFromSettings() {
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        d.set("pride", forKey: ThemeSettings.themeKey)
        d.set("trans", forKey: PrideFlag.key)
        let s = ThemeSettings.load(d)
        XCTAssertEqual(s.variantChoice.pride, .trans)
        let p = KeyboardTheme.pride.palette(systemDark: true, at: Date(), choice: s.variantChoice)
        XCTAssertEqual(p.auroraColors, PrideFlag.trans.stripes)
        XCTAssertEqual(p.accent, ThemeSpec.palette(PrideFlag.trans.slots).accent)
        XCTAssertNil(p.cornerGlyph)
        XCTAssertNil(KeyboardTheme.pride.palette(systemDark: true).auroraColors, "bảng tĩnh = dải aurora mặc định")
        XCTAssertEqual(AuroraFx.stops([1, 2, 3]).map(\.location), [0, 0.5, 1])
        var s2 = s
        s2.variantChoice.pride = .pan
        s2.save(d)
        XCTAssertEqual(d.string(forKey: PrideFlag.key), "pan")
        XCTAssertEqual(s2.resetToDefaults().variantChoice.pride, .pan)
        XCTAssertEqual(BackupSettings.byKey[PrideFlag.key]?.kind, .string("rainbow", PrideFlag.allCases.map(\.rawValue)))
    }

    // MARK: Ảnh xem thử (chỉ khi đặt VT_THEME_SNAPSHOT_DIR)

    @MainActor func testWritePrideThemeSnapshot() throws {
        guard let dir = ProcessInfo.processInfo.environment["VT_THEME_SNAPSHOT_DIR"] else {
            throw XCTSkip("đặt VT_THEME_SNAPSHOT_DIR để xuất ảnh theme")
        }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let savedPaywall = PlusGate.paywallEnabled
        PlusGate.paywallEnabled = false
        defer { PlusGate.paywallEnabled = savedPaywall }
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        d.set(KeyboardTheme.pride.rawValue, forKey: ThemeSettings.themeKey)
        d.set("rainbowburst", forKey: KeyEffect.key)
        d.set(false, forKey: KeyboardView.keyPreviewKey)
        let saved = UserDefaultsProvider.shared
        UserDefaultsProvider.shared = d
        defer { UserDefaultsProvider.shared = saved }
        let win = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 320))
        win.overrideUserInterfaceStyle = .dark
        win.isHidden = false
        defer { win.isHidden = true }
        let kb = KeyboardView(needsGlobe: false, inputController: nil, onKey: { _ in })
        win.addSubview(kb)
        kb.frame = win.bounds
        kb.applyAppearance(.dark, style: .dark)
        kb.layoutIfNeeded()
        let img = UIGraphicsImageRenderer(bounds: kb.bounds).image { _ in kb.drawHierarchy(in: kb.bounds, afterScreenUpdates: true) }
        try img.pngData()?.write(to: URL(fileURLWithPath: dir).appendingPathComponent("pride-theme-ios.png"))
    }
}
