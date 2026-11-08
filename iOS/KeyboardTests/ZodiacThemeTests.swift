// Theme "Cung hoàng đạo" (11/2026): cung + nguyên tố + bảng màu (Zodiac.swift), ngày sinh → cung, bảng chòm sao, luật
// thắp sao (ConstellationTrace / ConstellationFx), hiệu ứng "Chòm sao" (overlay trong bàn phím, trần layer), âm "twinkle",
// "variant":"zodiac" giải lúc hiện, sao lưu `zodiacSign`. Số tham chiếu GIỐNG HỆT android ZodiacThemeTests.kt.
import XCTest
import UIKit

final class ZodiacThemeTests: XCTestCase {
    private let suite = "vt-zodiac-theme"

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

    // MARK: id + dữ liệu chung

    func testIds() {
        XCTAssertEqual(ZodiacSign.allCases.map(\.rawValue),
                       ["aries", "taurus", "gemini", "cancer", "leo", "virgo", "libra", "scorpio", "sagittarius", "capricorn",
                        "aquarius", "pisces"])
        XCTAssertEqual(ZodiacSign.key, "zodiacSign")
        XCTAssertEqual(ZodiacSign.parse("leo"), .leo)
        XCTAssertEqual(ZodiacSign.parse("ophiuchus"), .aries)
        XCTAssertEqual(ZodiacSign.parse(nil), .aries)
        XCTAssertEqual(KeyboardTheme.zodiac.rawValue, "zodiac")
        XCTAssertEqual(KeyEffect.constellation.rawValue, "constellation")
        XCTAssertEqual(KeySoundStyle.twinkle.rawValue, "twinkle")
        XCTAssertTrue(ThemeExtraIds.effects.contains("constellation"))
        XCTAssertTrue(ThemeExtraIds.sounds.contains("twinkle"))
        XCTAssertEqual(ThemeVariants.zodiac, "zodiac")
        XCTAssertTrue(ThemeVariants.known.contains("zodiac"))
        XCTAssertEqual(L10n.en["Cung hoàng đạo"], "Zodiac")
        XCTAssertEqual(L10n.en["Chòm sao"], "Constellation")
        XCTAssertEqual(L10n.en["Chuông sao"], "Star chime")
        XCTAssertEqual(L10n.en["Bạch Dương"], "Aries"); XCTAssertEqual(L10n.en["Song Ngư"], "Pisces")
        XCTAssertEqual(L10n.en["Hệ Nước"], "Water"); XCTAssertEqual(L10n.en["Tính từ ngày sinh"], "From your birthday")
    }

    func testElementMapping() {
        let want: [ZodiacSign: ZodiacElement] = [
            .aries: .fire, .leo: .fire, .sagittarius: .fire,
            .taurus: .earth, .virgo: .earth, .capricorn: .earth,
            .gemini: .air, .libra: .air, .aquarius: .air,
            .cancer: .water, .scorpio: .water, .pisces: .water,
        ]
        for z in ZodiacSign.allCases { XCTAssertEqual(z.element, want[z], z.rawValue) }
        XCTAssertEqual(ZodiacSign.aries.glyph, "\u{2648}\u{FE0E}")
        XCTAssertEqual(ZodiacSign.pisces.glyph, "\u{2653}\u{FE0E}")
        XCTAssertEqual(ZodiacElement.fire.slots.accent, 0xFFFF_7A2F)
        XCTAssertEqual(ZodiacElement.earth.slots.accent, 0xFF8D_BF5A)
        XCTAssertEqual(ZodiacElement.air.slots.accent, 0xFF8E_C5FF)
        XCTAssertEqual(ZodiacElement.water.slots.accent, 0xFF2B_C4C4)
    }

    /// Mọi bảng nguyên tố: chữ/phím, chữ chức năng/phím chức năng, chữ nhấn/nhấn, chữ/nền ≥ 4,5.
    func testElementPalettesContrast() {
        for e in ZodiacElement.allCases {
            let p = ThemeSpec.palette(e.slots)
            XCTAssertTrue(p.isDark, e.rawValue)
            XCTAssertEqual(p.decoration?.motif, .starfield, e.rawValue)
            XCTAssertGreaterThanOrEqual(RGBA.contrast(p.ink, p.keyFill), 4.5, e.rawValue)
            XCTAssertGreaterThanOrEqual(RGBA.contrast(p.fnInk, p.fnFill), 4.5, e.rawValue)
            XCTAssertGreaterThanOrEqual(RGBA.contrast(p.accentInk, p.accent), 4.5, e.rawValue)
            XCTAssertGreaterThanOrEqual(RGBA.contrast(p.ink, p.background!), 4.5, e.rawValue)
        }
    }

    /// Mốc ngày nhiệt đới (Zodiac.swift đầu file) — Android y hệt.
    func testSignFromDate() {
        let cases: [(Int, Int, ZodiacSign?)] = [
            (1, 1, .capricorn), (19, 1, .capricorn), (20, 1, .aquarius), (18, 2, .aquarius), (19, 2, .pisces),
            (29, 2, .pisces), (20, 3, .pisces), (21, 3, .aries), (19, 4, .aries), (20, 4, .taurus), (20, 5, .taurus),
            (21, 5, .gemini), (20, 6, .gemini), (21, 6, .cancer), (22, 7, .cancer), (23, 7, .leo), (22, 8, .leo),
            (23, 8, .virgo), (22, 9, .virgo), (23, 9, .libra), (22, 10, .libra), (23, 10, .scorpio), (21, 11, .scorpio),
            (22, 11, .sagittarius), (21, 12, .sagittarius), (22, 12, .capricorn), (31, 12, .capricorn),
            (30, 2, nil), (31, 4, nil), (0, 5, nil), (1, 13, nil), (1, 0, nil), (32, 1, nil),
        ]
        for (d, m, want) in cases { XCTAssertEqual(ZodiacSign.from(day: d, month: m), want, "\(d)/\(m)") }
        // Mỗi ngày trong năm ra đúng một cung, đổi cung đúng 12 lần.
        var prev: ZodiacSign?, changes = 0
        for (m, n) in [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31].enumerated() {
            for d in 1...n {
                let z = ZodiacSign.from(day: d, month: m + 1)
                XCTAssertNotNil(z)
                if let p = prev, p != z { changes += 1 }
                prev = z
            }
        }
        XCTAssertEqual(changes, 12)
    }

    /// Bảng chòm sao: số sao / cạnh mỗi cung, toạ độ trong hộp đơn vị, cạnh hợp lệ, mỗi sao k > 0 nối về sao trước nó.
    func testConstellationTable() {
        XCTAssertEqual(ZodiacSign.allCases.map { $0.constellation.stars.count }, [4, 6, 6, 5, 8, 7, 4, 9, 8, 6, 7, 8])
        XCTAssertEqual(ZodiacSign.allCases.map { $0.constellation.edges.count }, [3, 5, 6, 4, 8, 7, 4, 8, 10, 6, 6, 8])
        XCTAssertEqual(ZodiacSign.leo.constellation.stars[4], ZodiacStar(x: 0.30, y: 0.70))
        XCTAssertEqual(ZodiacSign.scorpio.constellation.stars[8], ZodiacStar(x: 0.92, y: 0.60))
        for z in ZodiacSign.allCases {
            let c = z.constellation
            for s in c.stars {
                XCTAssertTrue((0...1).contains(s.x) && (0...1).contains(s.y), z.rawValue)
            }
            for e in c.edges {
                XCTAssertTrue(c.stars.indices.contains(e.a) && c.stars.indices.contains(e.b) && e.a != e.b, z.rawValue)
            }
            for k in 1..<c.stars.count { XCTAssertFalse(c.edges(ownedBy: k).isEmpty, "\(z.rawValue) sao \(k)") }
            XCTAssertTrue(c.edges(ownedBy: 0).isEmpty)
            XCTAssertLessThanOrEqual(c.stars.count, 9)
        }
    }

    func testTraceAndTiming() {
        var t = ConstellationTrace(count: 4)
        let steps = [0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 3.0].map { t.press(at: $0) }
        XCTAssertEqual(steps, [
            .init(star: 0, newCycle: true, completes: false), .init(star: 1, newCycle: false, completes: false),
            .init(star: 2, newCycle: false, completes: false), .init(star: 3, newCycle: false, completes: true),
            .init(star: 0, newCycle: true, completes: false), .init(star: 1, newCycle: false, completes: false),
            .init(star: 0, newCycle: true, completes: false),
        ])
        XCTAssertEqual(t.cycle, 3)
        XCTAssertEqual(ConstellationFx.starAlpha(0.09), 0.5, accuracy: 1e-9)
        XCTAssertEqual(ConstellationFx.starAlpha(1), 1)
        XCTAssertEqual(ConstellationFx.cycleAlpha(1.0, completed: false), 1)
        XCTAssertEqual(ConstellationFx.cycleAlpha(2.65, completed: false), 0.5, accuracy: 1e-9)
        XCTAssertEqual(ConstellationFx.cycleAlpha(2.9, completed: false), 0)
        XCTAssertEqual(ConstellationFx.cycleAlpha(0.7, completed: true), 0.5, accuracy: 1e-9)
        XCTAssertEqual(ConstellationFx.glowAlpha(0.075), 0.425, accuracy: 1e-9)
        XCTAssertEqual(ConstellationFx.glowAlpha(0.575), 0.425, accuracy: 1e-9)
        XCTAssertEqual(ConstellationFx.glowAlpha(1.0), 0)
        XCTAssertEqual(ConstellationFx.lifetime(completed: false), 2.9, accuracy: 1e-9)
        XCTAssertEqual(ConstellationFx.lifetime(completed: true), 1.0, accuracy: 1e-9)
    }

    func testBoxInsideBounds() {
        let b = ConstellationFx.box(cx: 67, cy: 121, bounds: (0, -180, 390, 470))
        XCTAssertEqual(b.x, 6, accuracy: 1e-9); XCTAssertEqual(b.y, 15.7, accuracy: 1e-9)
        XCTAssertEqual(b.w, 234, accuracy: 1e-9); XCTAssertEqual(b.h, 140.4, accuracy: 1e-9)
        // Phím sát mép / ô xem thử nhỏ: hộp kẹp trong khung.
        for (cx, cy, bw, bh) in [(0.0, 0.0, 390.0, 260.0), (390, 260, 390, 260), (55, 70, 110, 84), (500, -40, 320, 200)] {
            let r = ConstellationFx.box(cx: cx, cy: cy, bounds: (0, 0, bw, bh))
            XCTAssertGreaterThanOrEqual(r.x, 0); XCTAssertGreaterThanOrEqual(r.y, 0)
            XCTAssertLessThanOrEqual(r.x + r.w, bw); XCTAssertLessThanOrEqual(r.y + r.h, bh)
            XCTAssertEqual(r.h, r.w * ConstellationFx.aspect, accuracy: 1e-9)
        }
    }

    // MARK: overlay

    /// Host dời gốc bounds (#151): sao nằm trong bàn phím, cắt theo khung, trần layer (pool 2 chòm × 20).
    @MainActor func testConstellationOverlayInsideKeyboardAndCapped() throws {
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 470))
        host.bounds.origin.y = -180
        let o = try XCTUnwrap(KeyEffectOverlay.install(.constellation, color: .systemOrange, in: host, existing: nil))
        XCTAssertEqual(o.bounds.origin, host.bounds.origin)
        XCTAssertTrue(o.clipsToBounds)
        o.zodiacSign = .scorpio
        for i in 0..<25 {
            o.emit(key: CGRect(x: CGFloat(i % 10) * 39, y: CGFloat(i % 4) * 60 - 170, width: 34, height: 42)); o.flush()
        }
        XCTAssertEqual(o.debugStarRoots.count, ConstellationFx.pool)
        XCTAssertLessThanOrEqual(o.debugStarLayerCount, ConstellationFx.pool * 20)
        // 25 phím, chòm 9 sao: 9 + 9 + 7 ⇒ chòm đang dở (ô 0) có 7 sao hiện.
        XCTAssertEqual(o.debugStarsShown[0], 7)
        for (i, pts) in o.debugStarPositions.enumerated() {
            for p in pts.prefix(o.debugStarsShown[i]) {
                XCTAssertTrue(o.bounds.contains(p), "\(p) ngoài \(o.bounds)")
            }
        }
        o.halt()
        XCTAssertEqual(o.debugStarsShown, [0, 0])
        _ = KeyEffectOverlay.install(.none, color: .red, in: host, existing: o)
    }

    // MARK: theme + biến thể

    func testZodiacTheme() throws {
        let spec = try XCTUnwrap(KeyboardTheme.zodiac.spec)
        XCTAssertTrue(KeyboardTheme.zodiac.isPlus)
        XCTAssertTrue(KeyboardTheme.zodiac.isInteractive)
        XCTAssertEqual(spec.nameVi, "Cung hoàng đạo"); XCTAssertEqual(spec.nameEn, "Zodiac")
        XCTAssertEqual(spec.variant, "zodiac")
        XCTAssertEqual(spec.effect, "constellation"); XCTAssertEqual(spec.sound, "twinkle"); XCTAssertEqual(spec.swipe, "stardust")
        XCTAssertEqual(spec.light, ZodiacElement.fire.slots, "bảng dự phòng = Lửa")
        XCTAssertEqual(KeyboardTheme.zodiac.systemBackdropKey, "systemBackdropZodiac")
        XCTAssertTrue(BackupSettings.all.contains { $0.key == "systemBackdropZodiac" })
        XCTAssertEqual(ThemePicker.interactiveOrder.firstIndex(of: "zodiac").map { $0 + 1 }, ThemePicker.interactiveOrder.firstIndex(of: "pride"))
    }

    /// Lựa chọn cung giải lúc hiện: bảng màu theo nguyên tố + ký hiệu góc; theme khác không đổi.
    func testVariantResolvesFromSettings() {
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        d.set("zodiac", forKey: ThemeSettings.themeKey)
        d.set("scorpio", forKey: ZodiacSign.key)
        let s = ThemeSettings.load(d)
        XCTAssertEqual(s.variantChoice.zodiac, .scorpio)
        let p = KeyboardTheme.zodiac.palette(systemDark: false, at: Date(), choice: s.variantChoice)
        XCTAssertEqual(p.accent, ThemeSpec.palette(ZodiacElement.water.slots).accent)
        XCTAssertEqual(p.cornerGlyph, ZodiacSign.scorpio.glyph)
        let card = s.cardPalette(for: .zodiac, systemDark: true)
        XCTAssertEqual(card.cornerGlyph, ZodiacSign.scorpio.glyph)
        XCTAssertNil(KeyboardTheme.sea.palette(systemDark: false, at: Date(), choice: s.variantChoice).cornerGlyph)
        XCTAssertNil(KeyboardTheme.zodiac.palette(systemDark: false).cornerGlyph, "bảng tĩnh không có ký hiệu")
        // Lưu: chỉ id cung; khôi phục gốc giữ lựa chọn.
        var s2 = s
        s2.variantChoice.zodiac = .gemini
        s2.save(d)
        XCTAssertEqual(d.string(forKey: ZodiacSign.key), "gemini")
        XCTAssertEqual(s2.resetToDefaults().variantChoice.zodiac, .gemini)
        // Chép JSON giữ "variant".
        XCTAssertEqual(s.exportSpec(for: .zodiac).variant, "zodiac")
    }

    func testBackupKey() {
        let spec = BackupSettings.byKey[ZodiacSign.key]
        XCTAssertEqual(spec?.kind, .string("aries", ZodiacSign.allCases.map(\.rawValue)))
    }

    // MARK: âm

    /// "Chuông sao": nhỏ hơn "Gõ gỗ", ≤ 60 ms, seed cố định; checksum chung Android (KeySoundTests.kt twinkle).
    func testTwinkleSound() {
        for k in KeySoundKind.allCases {
            let wood = KeySoundSynth.samples(.wood, k), a = KeySoundSynth.samples(.twinkle, k)
            XCTAssertLessThan(KeySoundSynth.rms(a), KeySoundSynth.rms(wood), "\(k)")
            XCTAssertLessThan(a.map(abs).max() ?? 1, wood.map(abs).max() ?? 0, "\(k)")
            XCTAssertLessThan(Double(a.count) / KeySoundSynth.sampleRate, 0.066, "\(k)")
        }
        XCTAssertEqual(KeySoundSynth.seed(.twinkle, .letter), 0x7477_6E6B ^ 0x85EB_CA6B)
        for (k, want) in Self.twinkleGolden {
            XCTAssertEqual(KeySoundSynth.samples(.twinkle, k).reduce(0.0) { $0 + Double(abs($1)) }, want, accuracy: 0.01, "\(k)")
        }
        XCTAssertTrue(KeySoundStyle.presets.contains(.twinkle))
    }
    static let twinkleGolden: [(KeySoundKind, Double)] = [(.letter, 186.0985), (.delete, 187.2213), (.modifier, 212.3972)]

    // MARK: Ảnh xem thử (chỉ khi đặt VT_THEME_SNAPSHOT_DIR)

    @MainActor func testWriteZodiacThemeSnapshot() throws {
        guard let dir = ProcessInfo.processInfo.environment["VT_THEME_SNAPSHOT_DIR"] else {
            throw XCTSkip("đặt VT_THEME_SNAPSHOT_DIR để xuất ảnh theme")
        }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let savedPaywall = PlusGate.paywallEnabled
        PlusGate.paywallEnabled = false
        defer { PlusGate.paywallEnabled = savedPaywall }
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        d.set(KeyboardTheme.zodiac.rawValue, forKey: ThemeSettings.themeKey)
        d.set("leo", forKey: ZodiacSign.key)
        d.set("constellation", forKey: KeyEffect.key)
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
        XCTAssertEqual(kb.debugCornerGlyph?.string as? String, ZodiacSign.leo.glyph)
        let img = UIGraphicsImageRenderer(bounds: kb.bounds).image { _ in kb.drawHierarchy(in: kb.bounds, afterScreenUpdates: true) }
        try img.pngData()?.write(to: URL(fileURLWithPath: dir).appendingPathComponent("zodiac-theme-ios.png"))
    }
}
