import XCTest
import UIKit
import ImageIO
import UniformTypeIdentifiers
import CoreText

/// Nền bàn phím trong suốt (lộ vật liệu bàn phím hệ thống, cùng màu dải 🌐/🎤) hay tự vẽ.
final class KeyboardBackdropTests: XCTestCase {
    private var savedPaywall = false
    override func setUp() { super.setUp(); savedPaywall = PlusGate.paywallEnabled; PlusGate.paywallEnabled = false }
    override func tearDown() { PlusGate.paywallEnabled = savedPaywall; super.tearDown() }

    func testDefaultSystemThemeIsClearInLightAndDark() {
        for dark in [false, true] {
            XCTAssertTrue(ThemeSettings().clearBackground(systemDark: dark, wallpaperActive: false))
            XCTAssertNil(ThemeSettings().palette(systemDark: dark, wallpaperActive: false).background)
        }
    }

    func testTransparentThemesStayClearWithKeyTransparency() {
        var s = ThemeSettings()
        s.keyboardTransparency = 60
        XCTAssertTrue(s.clearBackground(systemDark: true, wallpaperActive: false))
        s.theme = .glass
        XCTAssertTrue(s.clearBackground(systemDark: true, wallpaperActive: false))
    }

    func testOwnBackgroundThemesAndWallpaperDrawTheirOwn() {
        var s = ThemeSettings()
        // "Tối OLED" / "Tương phản cao" là nguồn nền ĐEN TUYỀN; pastel tự vẽ nền.
        for t in [KeyboardTheme.oled, .contrast, .peach, .mint, .sky, .lavender] {
            s.theme = t
            XCTAssertFalse(s.clearBackground(systemDark: true, wallpaperActive: false), t.rawValue)
        }
        s.theme = .system
        XCTAssertFalse(s.clearBackground(systemDark: true, wallpaperActive: true))
    }

    // MARK: "Nền theo hệ thống" (tuỳ chọn từng theme có nền, mặc định tắt)

    func testSystemBackdropOptionPerThemeDefaultOff() {
        var s = ThemeSettings()
        XCTAssertTrue(s.systemBackdropThemes.isEmpty)
        XCTAssertNil(KeyboardTheme.system.systemBackdropKey)
        XCTAssertNil(KeyboardTheme.glass.systemBackdropKey)
        XCTAssertEqual(KeyboardTheme.oled.systemBackdropKey, "systemBackdropOled")
        s.theme = .oled
        XCTAssertFalse(s.usesSystemBackdrop)
        let own = s.palette(systemDark: true, wallpaperActive: false)
        s.systemBackdropThemes = [.oled]
        XCTAssertTrue(s.usesSystemBackdrop)
        let sys = s.palette(systemDark: true, wallpaperActive: false)
        XCTAssertNil(sys.background)
        XCTAssertTrue(s.clearBackground(systemDark: true, wallpaperActive: false))
        XCTAssertEqual(sys.keyFill, own.keyFill)          // giữ màu phím theme
        XCTAssertEqual(sys.ink, own.ink)
        // Bật cho OLED không ảnh hưởng theme khác.
        s.theme = .contrast
        XCTAssertFalse(s.usesSystemBackdrop)
        XCTAssertNotNil(s.palette(systemDark: true, wallpaperActive: false).background)
        // Ảnh nền thắng (ảnh nền tự vẽ nền).
        s.theme = .oled
        XCTAssertFalse(s.clearBackground(systemDark: true, wallpaperActive: true))
        // Khôi phục giao diện gốc tắt hết.
        XCTAssertTrue(s.resetToDefaults().systemBackdropThemes.isEmpty)
    }

    func testSystemBackdropKeepsBarReadableAndSurfaceFollowsSystem() {
        var s = ThemeSettings()
        s.theme = .oled                                   // chữ trắng, theme tối cố định
        s.systemBackdropThemes = [.oled]
        let light = s.palette(systemDark: false, wallpaperActive: false)   // kính sáng phía sau
        let behind = KeyboardTransparency.systemBackdrop(dark: false)
        XCTAssertGreaterThanOrEqual(RGBA.contrast(light.barInk, behind), KeyboardTransparency.minLabelContrast)
        XCTAssertEqual(light.surfaceDark, false)          // bảng emoji theo nền sáng
        XCTAssertTrue(light.isDark)                       // phím vẫn tối
        XCTAssertEqual(s.palette(systemDark: true, wallpaperActive: false).surfaceDark, true)
    }

    func testSystemBackdropSettingRoundTripsAndIsBackedUp() throws {
        let d = try XCTUnwrap(UserDefaults(suiteName: "sysbd-\(UUID().uuidString)"))
        var s = ThemeSettings()
        s.systemBackdropThemes = [.oled, .peach]
        s.save(d)
        XCTAssertEqual(ThemeSettings.load(d).systemBackdropThemes, [.oled, .peach])
        for t in KeyboardTheme.allCases {
            guard let k = t.systemBackdropKey else { continue }
            XCTAssertEqual(BackupSettings.byKey[k]?.kind, .bool(false), k)   // có trong sao lưu, mặc định tắt
        }
    }

    // MARK: nền phủ trọn input view + bo góc

    /// Nền theme phủ TRỌN view (headroom balloon, strip, host cấp dư/thiếu, bar bật/tắt/thu
    /// gọn) — không để lộ khung kính xám của hệ thống ở mép trên (Phil 05/10, theme đen).
    @MainActor func testBackdropCoversWholeInputView() throws {
        let d = UserDefaultsProvider.shared
        let saved = d?.object(forKey: ThemeSettings.themeKey)
        defer { d?.set(saved, forKey: ThemeSettings.themeKey) }
        d?.set(KeyboardTheme.oled.rawValue, forKey: ThemeSettings.themeKey)
        let w: CGFloat = UIDevice.current.userInterfaceIdiom == .pad ? 834 : 390
        for (suggestions, reserve) in [(true, true), (false, true), (false, false)] {
            let kb = KeyboardView(needsGlobe: false, inputController: nil) { _ in }
            let host = UIView(frame: CGRect(x: 0, y: 0, width: w, height: 500))
            host.addSubview(kb)
            kb.frame = CGRect(x: 0, y: 0, width: w, height: 300)
            kb.applyAppearance(.dark, style: .dark)
            kb.configureInputKind(.normal)
            kb.setSuggestionsEnabled(suggestions, reserveStrip: reserve)
            kb.layoutIfNeeded()
            let want = kb.debugRequestedHeight
            for h in [want, want - 14, want - 40, want + 30, want + 120] {   // đúng / thiếu / dư
                kb.frame.size.height = h
                kb.setNeedsLayout(); kb.layoutIfNeeded()
                for f in kb.debugBackdrop.frames {
                    XCTAssertEqual(f, kb.bounds, "bar \(suggestions)/\(reserve) h \(h)")
                }
            }
        }
    }

    func testBackdropCornerRadiusOnlyPhoneIOS26() {
        XCTAssertGreaterThan(KeyLayout.backdropCornerRadius(phone: true, systemMajor: 26), 0)
        XCTAssertGreaterThan(KeyLayout.backdropCornerRadius(phone: true, systemMajor: 27), 0)
        XCTAssertEqual(KeyLayout.backdropCornerRadius(phone: true, systemMajor: 18), 0)
        XCTAssertEqual(KeyLayout.backdropCornerRadius(phone: false, systemMajor: 27), 0)
    }

    func testSystemKeysKeepContrastOnSystemBackdrop() {
        // Nền trong ⇒ phím nằm trên vật liệu hệ thống: chữ vẫn ≥ 4.5:1, phím tách khỏi nền.
        for dark in [false, true] {
            let p = KeyboardTheme.system.palette(systemDark: dark)
            let sys = KeyboardTransparency.systemBackdrop(dark: dark)
            XCTAssertGreaterThanOrEqual(RGBA.contrast(p.ink, p.keyFill.over(sys)), 4.5)
            XCTAssertGreaterThan(RGBA.contrast(p.keyFill.over(sys), sys), 1.1)
        }
    }
}

/// Theme bàn phím: token, cổng Plus, lưu/đọc cài đặt, tương phản WCAG, pipeline ảnh nền.
final class KeyboardThemeTests: XCTestCase {

    private var savedDefaults: UserDefaults!
    private var savedPaywall = false
    private var suite = ""

    override func setUp() {
        super.setUp()
        savedDefaults = PlusGate.defaults
        savedPaywall = PlusGate.paywallEnabled
        PlusGate.paywallEnabled = false   // mặc định test = mở (test gating tự bật)
        suite = "themeplus-\(UUID().uuidString)"
        PlusGate.defaults = UserDefaults(suiteName: suite)!
    }

    override func tearDown() {
        PlusGate.defaults.removePersistentDomain(forName: suite)
        PlusGate.defaults = savedDefaults
        PlusGate.paywallEnabled = savedPaywall
        super.tearDown()
    }

    /// Bật paywall + chưa mua (tắt cả công tắc giả lập Debug).
    private func lockPlus() {
        PlusGate.paywallEnabled = true
        PlusGate.setPurchased(false)
        PlusGate.debugOverride = false
    }

    // MARK: token

    func testThemeSetIsCompactAndSystemIsDefault() {
        XCTAssertTrue((6...40).contains(KeyboardTheme.allCases.count))
        XCTAssertEqual(ThemeSettings().theme, .system)
        XCTAssertEqual(ThemeSettings.load(nil).theme, .system)
    }

    /// Theme Hệ thống giữ NGUYÊN màu cũ của KeyboardView (không đổi hình người dùng cũ).
    func testSystemPaletteMatchesLegacyColors() {
        let light = KeyboardTheme.system.palette(systemDark: false)
        XCTAssertEqual(light.keyFill, .white)
        XCTAssertEqual(light.specialFill, RGBA(r: 0.68, g: 0.70, b: 0.74))
        XCTAssertEqual(light.ink, .black)
        XCTAssertNil(light.background)
        XCTAssertFalse(light.isDark)
        let dark = KeyboardTheme.system.palette(systemDark: true)
        // Tối: theo stock iOS 27 đo pixel (phím #444444 trên nền #202020) — xem UXFeedbackTests.
        XCTAssertEqual(dark.keyFill, RGBA(hex: 0x444444))
        XCTAssertEqual(dark.ink, .white)
        XCTAssertTrue(dark.isDark)
    }

    /// Theme tối cố định (OLED, Tương phản cao, Tim đen, Neon) không đổi theo hệ thống; mọi theme
    /// nền đục khác có bản tối riêng (bug 10/2026: "giao diện plus ở chế độ tối không chuyển tối").
    func testFixedThemesIgnoreSystemAppearance() {
        let fixed: Set<KeyboardTheme> = [.oled, .contrast, .blackHeart, .neon, .tet, .xmas, .piano, .rgb, .space, .trungthu, .halloween, .mole]
        for t in KeyboardTheme.allCases where t != .system && t != .glass {
            XCTAssertNotNil(t.palette(systemDark: false).background, "\(t) cần nền đục")
            if fixed.contains(t) {
                XCTAssertEqual(t.palette(systemDark: false), t.palette(systemDark: true), t.rawValue)
                // Piano: phím ngà chữ đen nhưng NỀN tối ⇒ thanh gợi ý / emoji theo nhánh tối (surfaceDark).
                let p = t.palette(systemDark: false)
                XCTAssertTrue(p.surfaceDark ?? p.isDark, t.rawValue)
            } else {
                XCTAssertNotEqual(t.palette(systemDark: false), t.palette(systemDark: true), t.rawValue)
            }
        }
        XCTAssertNil(KeyboardTheme.glass.palette(systemDark: false).background,
                     "Kính để lộ backdrop hệ thống, không tự blur")
    }

    func testIsDarkMatchesInkLuminance() {
        for t in KeyboardTheme.allCases {
            for d in [false, true] {
                let p = t.palette(systemDark: d)
                XCTAssertEqual(p.isDark, p.ink.luminance > 0.5, "\(t) dark=\(d)")
            }
        }
    }

    // MARK: tương phản WCAG

    /// Tương phản cao: chữ/nền phím ≥ 7:1 (AAA, vượt AA 4.5), cả khi đè phím, nhấn
    /// (return hành động) và thanh gợi ý trên nền bàn phím.
    func testHighContrastMeetsWCAG() {
        let p = KeyboardTheme.contrast.palette(systemDark: false)
        let bg = p.background!
        XCTAssertGreaterThanOrEqual(RGBA.contrast(p.ink, p.keyFill.over(bg)), 7)
        XCTAssertGreaterThanOrEqual(RGBA.contrast(p.ink, p.specialFill.over(bg)), 7)
        XCTAssertGreaterThanOrEqual(RGBA.contrast(p.accentInk, p.accent), 7)
        XCTAssertGreaterThanOrEqual(RGBA.contrast(p.barInk, bg), 7)
        XCTAssertGreaterThanOrEqual(RGBA.contrast(p.ink, p.balloon), 7)
        // Ranh giới phím phải thấy được (viền ≥ 3:1 so với nền — WCAG 1.4.11).
        XCTAssertGreaterThanOrEqual(RGBA.contrast(p.keyBorder!.over(bg), bg), 3)
    }

    /// Mọi theme đục: chữ trên phím đạt AA (4.5:1).
    func testAllOpaqueThemesMeetAA() {
        for t in KeyboardTheme.allCases {
            for d in [false, true] {
                let p = t.palette(systemDark: d)
                // Nền trong suốt: kiểm trên backdrop hệ thống xấp xỉ (xám sáng / xám tối).
                let bg = p.background ?? (p.isDark ? RGBA(hex: 0x2A2A2A) : RGBA(hex: 0xD1D4DA))
                let key = p.keyFill.over(bg)
                XCTAssertGreaterThanOrEqual(RGBA.contrast(p.ink, key), 4.5, "\(t) dark=\(d) phím")
                XCTAssertGreaterThanOrEqual(RGBA.contrast(p.barInk, bg), 4.5, "\(t) dark=\(d) bar")
                XCTAssertGreaterThanOrEqual(RGBA.contrast(p.accentInk, p.accent), 3, "\(t) dark=\(d) nhấn")
            }
        }
    }

    /// Có ảnh nền: phím bán trong 80%. Kể cả ảnh tệ nhất (đen tuyền dưới theme sáng,
    /// trắng tuyền dưới theme tối) và lớp phủ 0%, chữ vẫn ≥ 4.5:1.
    func testWallpaperKeysStayLegibleOnWorstImage() {
        for t in KeyboardTheme.allCases {
            for d in [false, true] {
                let p = ThemeSettings(theme: t).palette(systemDark: d, wallpaperActive: true)
                XCTAssertNil(p.background)
                let worst: RGBA = p.isDark ? .white : .black
                XCTAssertGreaterThanOrEqual(RGBA.contrast(p.ink, p.keyFill.over(worst)), 4.5,
                                            "\(t) dark=\(d) phím")
                XCTAssertGreaterThanOrEqual(RGBA.contrast(p.ink, p.specialFill.over(worst)), 4.5,
                                            "\(t) dark=\(d) phím đè")
                XCTAssertLessThan(p.keyFill.a, 1.0001)
                // Ảnh vẫn lộ ra ở theme sáng (phím không đục hoàn toàn).
                if !p.isDark { XCTAssertLessThan(p.keyFill.a, 1, "\(t) phím nên hơi trong") }
            }
        }
    }

    func testContrastMath() {
        XCTAssertEqual(RGBA.contrast(.white, .black), 21, accuracy: 0.01)
        XCTAssertEqual(RGBA.contrast(.white, .white), 1, accuracy: 0.001)
        // #767676 trên trắng ≈ 4.54 (mốc AA quen thuộc).
        XCTAssertEqual(RGBA.contrast(RGBA(hex: 0x767676), .white), 4.54, accuracy: 0.02)
    }

    // MARK: cổng Plus

    func testGateOpenWhilePaywallOff() {
        PlusGate.paywallEnabled = false
        for t in KeyboardTheme.allCases { XCTAssertTrue(ThemeGate.allows(t)) }
        XCTAssertTrue(ThemeGate.allowsWallpaper)
    }

    func testFreeThemesStayFreeBehindPaywall() {
        lockPlus()
        XCTAssertTrue(ThemeGate.allows(.system))
        XCTAssertTrue(ThemeGate.allows(.oled))
        XCTAssertTrue(ThemeGate.allows(.contrast))
        XCTAssertFalse(ThemeGate.allows(.glass))
        XCTAssertFalse(ThemeGate.allowsWallpaper)
        PlusGate.setPurchased(true)
        XCTAssertTrue(ThemeGate.allows(.glass))
        XCTAssertTrue(ThemeGate.allowsWallpaper)
    }

    func testFreeThemesIncludeAccessibility() {
        XCTAssertFalse(KeyboardTheme.system.isPlus)
        XCTAssertFalse(KeyboardTheme.contrast.isPlus, "trợ năng không được khoá sau Plus")
        XCTAssertTrue(KeyboardTheme.glass.isPlus)
        XCTAssertTrue(KeyboardTheme.allCases.contains { $0.isPlus })
    }

    func testLockedPlusFallsBackToSystem() {
        lockPlus()
        let s = ThemeSettings(theme: .mint, wallpaper: true)
        XCTAssertEqual(s.effectiveTheme, .system)
        XCTAssertFalse(s.wallpaperActive(fileExists: true))
        XCTAssertEqual(ThemeSettings(theme: .contrast).effectiveTheme, .contrast)
    }

    // MARK: lưu/đọc

    func testSettingsRoundTrip() {
        let suite = "themetest-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        defer { d.removePersistentDomain(forName: suite) }
        XCTAssertEqual(ThemeSettings.load(d), ThemeSettings())   // mặc định khi trống
        let s = ThemeSettings(theme: .lavender, wallpaper: true, dim: 55, blur: 7, version: 123.5,
                              keyboardTransparency: 35, labelTransparency: 60)
        s.save(d)
        XCTAssertEqual(ThemeSettings.load(d), s)
    }

    func testLoadClampsAndIgnoresGarbage() {
        let suite = "themetest-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        defer { d.removePersistentDomain(forName: suite) }
        d.set("neon-pink-unknown", forKey: ThemeSettings.themeKey)
        d.set(500, forKey: ThemeSettings.dimKey)
        d.set(-3, forKey: ThemeSettings.blurKey)
        d.set(180, forKey: KeyboardTransparency.keyboardKey)
        d.set(-9, forKey: KeyboardTransparency.labelKey)
        let s = ThemeSettings.load(d)
        XCTAssertEqual(s.keyboardTransparency, 100)
        XCTAssertEqual(s.labelTransparency, 0)
        XCTAssertEqual(s.theme, .system)
        XCTAssertEqual(s.dim, 80)
        XCTAssertEqual(s.blur, 0)
    }

    // MARK: độ trong suốt

    private func allPalettes() -> [(KeyboardPalette, Bool, Bool)] {
        var out: [(KeyboardPalette, Bool, Bool)] = []
        for t in KeyboardTheme.allCases {
            for dark in [false, true] {
                let p = t.palette(systemDark: dark)
                out.append((p, dark, false)); out.append((p.overWallpaper(), dark, true))
            }
        }
        return out
    }

    func testTransparencyZeroIsIdentity() {
        for (p, dark, wp) in allPalettes() {
            XCTAssertEqual(p.withTransparency(keyboard: 0, labels: 0, systemDark: dark, wallpaper: wp), p)
            XCTAssertEqual(p.withTransparency(keyboard: -30, labels: -1, systemDark: dark, wallpaper: wp), p)
        }
    }

    func testTransparencyMapping() {
        XCTAssertEqual(KeyboardTransparency.alpha(0), 1)
        XCTAssertEqual(KeyboardTransparency.alpha(40), 0.6, accuracy: 1e-9)
        XCTAssertEqual(KeyboardTransparency.alpha(100), 0)
        XCTAssertEqual(KeyboardTransparency.alpha(250), 0)      // kẹp
        XCTAssertEqual(KeyboardTransparency.alpha(-5), 1)

        let peach = KeyboardTheme.peach.palette(systemDark: false)
        let half = peach.withTransparency(keyboard: 50, labels: 0, systemDark: false, wallpaper: false)
        XCTAssertEqual(half.background?.a ?? -1, 0.5, accuracy: 1e-9)
        XCTAssertEqual(half.keyFill.a, 0.5, accuracy: 1e-9)
        XCTAssertEqual(half.specialFill.a, 0.5, accuracy: 1e-9)
        XCTAssertEqual(half.accent.a, 0.5, accuracy: 1e-9)
        XCTAssertEqual(half.surfaceAlpha, 0.5, accuracy: 1e-9)
        XCTAssertEqual(half.keyInk.a, 1)                        // chữ không mờ theo phím

        let glass = KeyboardTheme.glass.palette(systemDark: false)
        let g = glass.withTransparency(keyboard: 50, labels: 0, systemDark: false, wallpaper: false)
        XCTAssertEqual(g.keyBorder?.a ?? -1, (glass.keyBorder?.a ?? 0) * 0.5, accuracy: 1e-9)
        XCTAssertNil(g.background)                              // nền trong suốt vẫn nil

        // 100% phím: nền/phím/viền/bóng biến mất hẳn, chữ còn nguyên.
        for (p, dark, wp) in allPalettes() {
            let z = p.withTransparency(keyboard: 100, labels: 0, systemDark: dark, wallpaper: wp)
            XCTAssertEqual(z.keyFill.a, 0); XCTAssertEqual(z.specialFill.a, 0); XCTAssertEqual(z.accent.a, 0)
            XCTAssertEqual(z.background?.a ?? 0, 0); XCTAssertEqual(z.keyBorder?.a ?? 0, 0)
            XCTAssertEqual(z.surfaceAlpha, 0)
            XCTAssertEqual(z.keyInk.a, 1)
        }
    }

    func testLabelTransparencyIndependentAndSparesBalloon() {
        for (p, dark, wp) in allPalettes() {
            let z = p.withTransparency(keyboard: 0, labels: 100, systemDark: dark, wallpaper: wp)
            XCTAssertEqual(z.keyInk.a, 0); XCTAssertEqual(z.accentInk.a, 0)
            XCTAssertEqual(z.keyFill, p.keyFill); XCTAssertEqual(z.background, p.background)
            XCTAssertEqual(z.ink, p.ink); XCTAssertEqual(z.balloon, p.balloon)   // balloon rõ nguyên
            let h = p.withTransparency(keyboard: 0, labels: 30, systemDark: dark, wallpaper: wp)
            XCTAssertEqual(h.keyInk, p.ink.alpha(0.7))
        }
    }

    /// Nền trong suốt lộ backdrop khác tông → chữ tự đổi đen/trắng cho đọc được;
    /// mức nhỏ không được lật màu (không đổi hình người đang dùng).
    func testLabelsStayReadableWhenBackgroundGoesClear() {
        // Chữ tối của theme sáng trên backdrop tối (cơ chế đổi đen/trắng).
        let lightOnDark = KeyboardTheme.peach.palette(systemDark: false)
            .withTransparency(keyboard: 100, labels: 0, systemDark: true, wallpaper: false)
        XCTAssertEqual(lightOnDark.keyInk, .white)
        XCTAssertTrue(lightOnDark.isDark)
        XCTAssertGreaterThanOrEqual(RGBA.contrast(lightOnDark.barInk,
                                                  KeyboardTransparency.systemBackdrop(dark: true)), 4.5)
        // Hồng đào TỐI (chữ sáng) trên backdrop tối: chữ theme vẫn đọc được ⇒ giữ nguyên màu theme.
        let peachDark = KeyboardTheme.peach.palette(systemDark: true)
        XCTAssertEqual(peachDark.withTransparency(keyboard: 100, labels: 0, systemDark: true,
                                                  wallpaper: false).keyInk, peachDark.ink)
        let peachLight = KeyboardTheme.peach.palette(systemDark: false)
        XCTAssertEqual(peachLight.withTransparency(keyboard: 100, labels: 0, systemDark: false,
                                                   wallpaper: false).keyInk, peachLight.ink)
        for (p, dark, wp) in allPalettes() {
            let small = p.withTransparency(keyboard: 10, labels: 0, systemDark: dark, wallpaper: wp)
            XCTAssertEqual(small.keyInk, p.ink); XCTAssertEqual(small.barInk, p.barInk)
            XCTAssertEqual(small.accentInk, p.accentInk); XCTAssertEqual(small.isDark, p.isDark)
        }
    }

    func testSettingsApplyTransparency() {
        let s = ThemeSettings(theme: .mint, keyboardTransparency: 100, labelTransparency: 100)
        let p = s.palette(systemDark: false, wallpaperActive: false)
        XCTAssertEqual(p.keyFill.a, 0); XCTAssertEqual(p.keyInk.a, 0)
    }

    func testResetToDefaults() {
        XCTAssertTrue(ThemeSettings().isDefault)
        let s = ThemeSettings(theme: .sky, wallpaper: true, dim: 60, blur: 9, version: 77,
                              keyboardTransparency: 40, labelTransparency: 25)
        XCTAssertFalse(s.isDefault)
        let r = s.resetToDefaults()
        XCTAssertTrue(r.isDefault)
        XCTAssertEqual(r.theme, .system); XCTAssertFalse(r.wallpaper)
        XCTAssertEqual(r.dim, 30); XCTAssertEqual(r.blur, 0)
        XCTAssertEqual(r.keyboardTransparency, 0); XCTAssertEqual(r.labelTransparency, 0)
        XCTAssertEqual(r.version, 77)                          // ảnh nền giữ nguyên, không vứt cache
        XCTAssertFalse(ThemeSettings(labelTransparency: 5).isDefault)
    }

    func testWallpaperNeedsFile() {
        let s = ThemeSettings(theme: .sky, wallpaper: true)
        XCTAssertFalse(s.wallpaperActive(fileExists: false))
        XCTAssertTrue(s.wallpaperActive(fileExists: true))
        XCTAssertFalse(ThemeSettings(wallpaper: false).wallpaperActive(fileExists: true))
    }

    // MARK: ảnh nền

    nonisolated(unsafe) private static var jpegCache: [String: Data] = [:]
    private func makeJPEG(width: Int, height: Int) -> Data {
        let k = "\(width)x\(height)"
        if let d = Self.jpegCache[k] { return d }
        let d = renderJPEG(width: width, height: height)
        Self.jpegCache[k] = d
        return d
    }

    private func renderJPEG(width: Int, height: Int) -> Data {
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        let img = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: fmt).image { ctx in
            // Nhiễu màu → JPEG khó nén (trường hợp xấu cho giới hạn dung lượng).
            var seed: UInt32 = 12345
            let step = 16
            for y in stride(from: 0, to: height, by: step) {
                for x in stride(from: 0, to: width, by: step) {
                    seed = seed &* 1664525 &+ 1013904223
                    UIColor(red: CGFloat(seed & 0xFF) / 255, green: CGFloat((seed >> 8) & 0xFF) / 255,
                            blue: CGFloat((seed >> 16) & 0xFF) / 255, alpha: 1).setFill()
                    ctx.fill(CGRect(x: x, y: y, width: step, height: step))
                }
            }
        }
        return img.jpegData(compressionQuality: 0.95)!
    }

    private func pixelSize(_ data: Data) -> (Int, Int) {
        let src = CGImageSourceCreateWithData(data as CFData, nil)!
        let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as! [CFString: Any]
        return (p[kCGImagePropertyPixelWidth] as! Int, p[kCGImagePropertyPixelHeight] as! Int)
    }

    func testPrepareDownsamplesAndCompresses() {
        let original = makeJPEG(width: 4032, height: 3024)     // ảnh camera 12MP
        let out = Wallpaper.prepare(original: original, blur: 0)!
        let (w, h) = pixelSize(out)
        XCTAssertLessThanOrEqual(max(w, h), Wallpaper.maxEdge)
        XCTAssertEqual(max(w, h), Wallpaper.maxEdge)
        XCTAssertEqual(Double(w) / Double(h), 4032.0 / 3024.0, accuracy: 0.01)
        XCTAssertLessThanOrEqual(out.count, Wallpaper.maxBytes)
    }

    func testPreparePortraitAndBlur() {
        let original = makeJPEG(width: 1500, height: 3000)
        let out = Wallpaper.prepare(original: original, blur: 10)!
        let (w, h) = pixelSize(out)
        XCTAssertEqual(h, Wallpaper.maxEdge)
        XCTAssertEqual(w, 540)
        XCTAssertLessThanOrEqual(out.count, Wallpaper.maxBytes)
    }

    func testSmallImageNotUpscaled() {
        let out = Wallpaper.prepare(original: makeJPEG(width: 600, height: 400), blur: 0)!
        let (w, h) = pixelSize(out)
        XCTAssertLessThanOrEqual(w, 600)
        XCTAssertLessThanOrEqual(h, 400)
    }

    /// Cỡ giải trong extension: đủ phủ view (aspect-fill) nhưng không vượt bản lưu.
    func testDisplayMaxPixel() {
        // iPhone dọc 393×300pt @3x = 1179×900px; ảnh 4:3 ngang → cần rộng 1200 → kẹp 1080.
        XCTAssertEqual(Wallpaper.displayMaxPixel(viewSize: CGSize(width: 393, height: 300),
                                                 scale: 3, imageAspect: 4.0 / 3), 1080)
        // @2x view 320×216 = 640×432, ảnh vuông → cần 640×640.
        XCTAssertEqual(Wallpaper.displayMaxPixel(viewSize: CGSize(width: 320, height: 216),
                                                 scale: 2, imageAspect: 1), 640)
        // Ảnh dọc 1:2 phủ view ngang 640×432: rộng 640 → cao 1280 → kẹp 1080.
        XCTAssertEqual(Wallpaper.displayMaxPixel(viewSize: CGSize(width: 320, height: 216),
                                                 scale: 2, imageAspect: 0.5), 1080)
        XCTAssertEqual(Wallpaper.displayMaxPixel(viewSize: .zero, scale: 3, imageAspect: 1), 1080)
    }

    func testKeyboardDecodeRespectsLimit() {
        let data = Wallpaper.prepare(original: makeJPEG(width: 4032, height: 3024), blur: 0)!
        let cg = Wallpaper.downsample(data: data, maxPixel: 640)!
        XCTAssertLessThanOrEqual(max(cg.width, cg.height), 640)
    }

    /// RAM: giải ảnh nền cỡ bàn phím iPhone 3x — đo phys_footprint tăng thêm.
    func testKeyboardDecodeMemoryFootprint() throws {
        try SlowTests.require()
        let data = Wallpaper.prepare(original: makeJPEG(width: 4032, height: 3024), blur: 0)!
        let px = Wallpaper.displayMaxPixel(viewSize: CGSize(width: 430, height: 300), scale: 3,
                                           imageAspect: 4.0 / 3)
        let before = Self.footprint()
        var images: [CGImage] = []
        autoreleasepool {
            images.append(Wallpaper.downsample(data: data, maxPixel: px)!)
        }
        let delta = Double(Self.footprint() - before) / 1_048_576
        let bitmapMB = Double(images[0].bytesPerRow * images[0].height) / 1_048_576
        print("THEME-RAM wallpaper decode \(images[0].width)x\(images[0].height): bitmap \(String(format: "%.1f", bitmapMB))MB, footprint +\(String(format: "%.1f", delta))MB")
        XCTAssertLessThanOrEqual(bitmapMB, 5, "bitmap ảnh nền phải ≤5MB (ngân sách extension ~48MB)")
        XCTAssertLessThan(delta, 12)
    }

    private static func footprint() -> Int64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? Int64(info.phys_footprint) : 0
    }
}

/// Ảnh nền + "Tuỳ chỉnh nâng cao" (Plus): độ trong suốt phím không làm mất ảnh nền, bo góc,
/// kẹp cỡ chữ, phông/độ đậm không cắt dấu chồng, lưu/đọc, cổng Plus, sao lưu.
final class KeyStyleTests: XCTestCase {
    private var savedDefaults: UserDefaults!
    private var savedPaywall = false
    private var suite = ""

    override func setUp() {
        super.setUp()
        savedDefaults = PlusGate.defaults
        savedPaywall = PlusGate.paywallEnabled
        PlusGate.paywallEnabled = false
        suite = "keystyle-\(UUID().uuidString)"
        PlusGate.defaults = UserDefaults(suiteName: suite)!
    }

    override func tearDown() {
        PlusGate.defaults.removePersistentDomain(forName: suite)
        PlusGate.defaults = savedDefaults
        PlusGate.paywallEnabled = savedPaywall
        KeyboardView.labelFonts = KeyLabelFonts(style: .default, compact: nil)
        KeyboardView.cornerPercent = nil
        super.tearDown()
    }

    private func lockPlus() {
        PlusGate.paywallEnabled = true
        PlusGate.setPurchased(false)
        PlusGate.debugOverride = false
    }

    private static let custom = KeyStyle(labelColor: 0xFF2D55, fillColor: 0x102030, corner: 100,
                                         fontScale: 150, font: .mono, weight: .heavy)

    // MARK: bug — độ trong suốt phím 100% làm mất ảnh nền

    func testKeyTransparency100KeepsWallpaper() {
        for t in KeyboardTheme.allCases {
            for dark in [false, true] {
                for dim in [0, 30, 80] {
                    let s = ThemeSettings(theme: t, wallpaper: true, dim: dim, keyboardTransparency: 100)
                    let p = s.palette(systemDark: dark, wallpaperActive: true)
                    let wl = p.wallpaperLayer(dim: dim)
                    XCTAssertEqual(wl.imageAlpha, 1, "\(t) \(dark): ảnh nền phải còn nguyên")
                    XCTAssertEqual(wl.overlay.a, Double(dim) / 100, accuracy: 1e-9, "lớp phủ theo độ tối, không theo độ trong suốt")
                    XCTAssertEqual(p.keyFill.a, 0)          // phím thì trong suốt hẳn
                    XCTAssertEqual(p.keyInk.a, 1)
                }
            }
        }
    }

    /// Bàn phím thật: alpha UIImageView ảnh nền + lớp phủ không theo độ trong suốt phím.
    @MainActor func testKeyboardViewWallpaperIgnoresKeyTransparency() {
        let d = UserDefaultsProvider.shared
        let keys = [KeyboardTransparency.keyboardKey, ThemeSettings.dimKey]
        let saved = keys.map { d?.object(forKey: $0) }
        defer { for (k, v) in zip(keys, saved) { d?.set(v, forKey: k) } }
        d?.set(100, forKey: KeyboardTransparency.keyboardKey)
        d?.set(40, forKey: ThemeSettings.dimKey)
        let kb = KeyboardView(needsGlobe: false, inputController: nil) { _ in }
        kb.frame = CGRect(x: 0, y: 0, width: 390, height: 300)
        kb.applyAppearance(.light, style: .light)
        XCTAssertEqual(kb.debugWallpaperLayer.alpha, 1)
        var a: CGFloat = 0
        kb.debugWallpaperLayer.overlay?.getRed(nil, green: nil, blue: nil, alpha: &a)
        XCTAssertEqual(a, 0.4, accuracy: 0.01)
    }

    // MARK: bo góc

    func testCornerRadiusMapping() {
        let sq = CGSize(width: 30, height: 42), wide = CGSize(width: 200, height: 42)
        XCTAssertEqual(KeyStyle.cornerRadius(percent: nil, size: sq, fallback: 8), 8)     // mặc định
        XCTAssertEqual(KeyStyle.cornerRadius(percent: 0, size: sq, fallback: 8), 0)       // chữ nhật
        XCTAssertEqual(KeyStyle.cornerRadius(percent: 100, size: sq, fallback: 8), 15)    // tròn trọn cạnh ngắn
        XCTAssertEqual(KeyStyle.cornerRadius(percent: 100, size: wide, fallback: 8), 21)  // viên thuốc
        XCTAssertEqual(KeyStyle.cornerRadius(percent: 50, size: wide, fallback: 8), 10.5)
        XCTAssertEqual(KeyStyle.cornerRadius(percent: 400, size: sq, fallback: 8), 15)    // kẹp
    }

    // MARK: phông / cỡ chữ

    private static func styles() -> [KeyStyle] {
        KeyLabelFont.allCases.flatMap { f in
            KeyLabelWeight.allCases.map { KeyStyle(fontScale: 150, font: f, weight: $0) }
        }
    }

    func testFontSizeCapOnNarrowKeys() {
        let keyW: CGFloat = 26, keyH: CGFloat = 40   // phím chữ hẹp (một tay / máy nhỏ)
        for st in Self.styles() {
            let lf = KeyLabelFonts(style: st, compact: nil)
            let want = KeyGeometry.Typography.lowercaseSize * lf.scale
            let em = lf.em(KeyLabelEm.keySample)
            let size = KeyLabelFit.size(want: want, em: em, keyWidth: keyW, keyHeight: keyH)
            XCTAssertLessThan(size, want, "\(st.font) \(st.weight): 150% phải bị kẹp trên phím hẹp")
            let f = lf.font(size: size)
            for g in ["W", "M", "Ư", "Đ"] {
                let w = (g as NSString).size(withAttributes: [.font: f]).width
                XCTAssertLessThanOrEqual(w, keyW - 2 * KeyLabelFit.sidePad + 0.5, "\(st.font) \(st.weight) \(g)")
            }
            let m = KeyLabelEm.measure(f, sample: KeyLabelEm.keySample)
            XCTAssertLessThanOrEqual(m.inkHeight * size, keyH, "\(st.font) \(st.weight)")
            let base = KeyLabelFit.baseline(preferred: 28 * keyH / 43, size: size, em: em, keyHeight: keyH)
            XCTAssertGreaterThanOrEqual(base - em.ascent * size, 0)            // mực không vượt đỉnh phím
            XCTAssertLessThanOrEqual(base + em.descent * size, keyH)           // không vượt đáy
        }
        // Phím rộng, cỡ vừa ⇒ không đụng tới.
        let lf = KeyLabelFonts(style: KeyStyle(font: .serif), compact: nil)
        XCTAssertEqual(KeyLabelFit.size(want: 24.5, em: lf.em(KeyLabelEm.keySample), keyWidth: 60, keyHeight: 60), 24.5)
    }

    /// Dấu chồng (Ễ, Ỗ…) và phần dưới dòng (ỵ) trong ô phóng to / popup không bị UILabel cắt,
    /// ở MỌI phông + độ đậm.
    func testStackedDiacriticsFitCenteredLabels() {
        for st in Self.styles() {
            let lf = KeyLabelFonts(style: st, compact: nil)
            for h in [CGFloat(30), 38, 46] {
                let size = KeyLabelFit.centeredSize(want: 34, em: lf.em(KeyLabelEm.stackedSample), height: h)
                let f = lf.font(size: size.rounded(.down))
                let s = f.pointSize
                let lineH = f.ascender - f.descender
                for g in ["Ễ", "Ỗ", "Ẫ", "Ữ", "ỵ", "Ỹ"] {
                    let ink = CTLineGetBoundsWithOptions(
                        CTLineCreateWithAttributedString(NSAttributedString(string: g, attributes: [.font: f])),
                        .useGlyphPathBounds)
                    let baseline = h / 2 - lineH / 2 + f.ascender      // UILabel căn giữa hộp dòng
                    XCTAssertGreaterThanOrEqual(baseline - ink.maxY, -0.5, "\(st.font) \(st.weight) \(g) h\(h) s\(s)")
                    XCTAssertLessThanOrEqual(baseline - ink.minY, h + 0.5, "\(st.font) \(st.weight) \(g) h\(h) s\(s)")
                }
            }
        }
    }

    /// Bàn phím thật: chữ 150% phông đơn cách rất đậm trên máy hẹp — phím chữ vừa phím, bo tròn.
    @MainActor func testKeyboardViewAppliesStyleAtLayout() {
        let d = UserDefaultsProvider.shared
        let keys = [ThemeSettings.themeKey, KeyStyleStore.key] + KeyStyleStore.legacyKeys
        let saved = keys.map { d?.object(forKey: $0) }
        defer { for (k, v) in zip(keys, saved) { d?.set(v, forKey: k) } }
        for k in KeyStyleStore.legacyKeys { d?.removeObject(forKey: k) }
        d?.set(KeyboardTheme.system.rawValue, forKey: ThemeSettings.themeKey)
        d?.set(KeyStyleStore.serialize(["system": Self.custom]), forKey: KeyStyleStore.key)
        let kb = KeyboardView(needsGlobe: false, inputController: nil) { _ in }
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 500))
        host.addSubview(kb)
        kb.frame = CGRect(x: 0, y: 0, width: 320, height: 300)
        kb.applyAppearance(.light, style: .light)
        kb.configureInputKind(.normal)
        kb.setNeedsLayout(); kb.layoutIfNeeded()
        let st = try? XCTUnwrap(kb.debugLetterStyle("w"))
        guard let st, let f = st.font, st.size.width > 0 else { return XCTFail("không thấy phím w") }
        XCTAssertEqual(st.radius, min(st.size.width, st.size.height) / 2, accuracy: 0.01)   // 100% = tròn
        let w = ("W" as NSString).size(withAttributes: [.font: f]).width
        XCTAssertLessThanOrEqual(w, st.size.width - 2 * KeyLabelFit.sidePad + 0.5)
        XCTAssertTrue(f.fontDescriptor.symbolicTraits.contains(.traitMonoSpace) || f.fontName.lowercased().contains("mono"),
                      f.fontName)
        // Ô phóng to: dấu chồng nằm trọn trong khung chữ.
        if let b = kb.debugBalloon(letter: "e", text: "Ễ") {
            let lf = KeyboardView.labelFonts
            let em = lf.em(KeyLabelEm.stackedSample)
            XCTAssertLessThanOrEqual(b.fontSize, KeyLabelFit.centeredSize(want: 34, em: em, height: b.label.height) + 0.5)
        }
    }

    // MARK: lưu / đọc / mặc định

    func testSettingsParsingAndDefaults() {
        let suite = "keystyle-rt-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        defer { d.removePersistentDomain(forName: suite) }
        XCTAssertEqual(ThemeSettings.load(d).keyStyle, KeyStyle())  // trống ⇒ mặc định
        XCTAssertTrue(KeyStyle().isDefault)
        XCTAssertFalse(KeyStyle().customizesLabels)
        XCTAssertEqual(KeyStyleStore.parse(KeyStyleStore.serialize(["mint": Self.custom]))["mint"], Self.custom)
        XCTAssertEqual(KeyStyleStore.serialize(["mint": KeyStyle()]), "{}")   // mặc định ⇒ không có mục
        // Rác / ngoài phạm vi (cùng luật khoá cũ).
        // Đọc CHẶT: mục có màu sai / khoá lạ / giá trị lạ bị bỏ CẢ MỤC (theme vẽ như chưa chỉnh).
        XCTAssertNil(KeyStyleStore.parse(##"{"mint":{"label":"#1000000"}}"##)["mint"])
        XCTAssertNil(KeyStyleStore.parse(##"{"mint":{"label":"#FF2D55","what":1}}"##)["mint"])
        XCTAssertNil(KeyStyleStore.parse(#"{"mint":{"font":"comic-sans"}}"#)["mint"])
        XCTAssertNil(KeyStyleStore.parse(#"{"mint":{"accent":true}}"#)["mint"])
        // Số ngoài khoảng ⇒ kẹp.
        let g = KeyStyleStore.parse(#"{"mint":{"corner":300,"fontScale":30}}"#)["mint"]
        XCTAssertEqual(g?.corner, 100); XCTAssertEqual(g?.fontScale, 80)
        XCTAssertEqual(KeyStyleStore.parse(#"{"mint":{"fontScale":999}}"#)["mint"]?.fontScale, 150)
        XCTAssertEqual(KeyStyleStore.parse("not json"), [:])
        XCTAssertEqual(KeyStyleStore.parse(#"{"bad id!":{"corner":5},"ok":[1]}"#), [:])
        // Thuộc ThemeSettings: lưu cùng, "Khôi phục giao diện gốc" xoá.
        var s = ThemeSettings(theme: .mint)
        s.keyStyle = Self.custom
        s.save(d)
        XCTAssertEqual(ThemeSettings.load(d).keyStyle, Self.custom)
        XCTAssertFalse(s.isDefault)
        XCTAssertEqual(s.resetToDefaults().keyStyle, KeyStyle())
    }

    // MARK: cổng Plus

    func testPlusGatingStoredButInactiveRendersDefaults() {
        var s = ThemeSettings(theme: .oled)
        s.keyStyle = Self.custom
        var plain = s; plain.keyStyle = KeyStyle()
        lockPlus()
        XCTAssertFalse(ThemeGate.allowsAdvanced)
        XCTAssertEqual(s.effectiveKeyStyle, KeyStyle())
        XCTAssertEqual(s.palette(systemDark: true, wallpaperActive: false),
                       plain.palette(systemDark: true, wallpaperActive: false))
        XCTAssertEqual(s.keyStyle, Self.custom)                        // giá trị lưu giữ nguyên
        PlusGate.setPurchased(true)
        XCTAssertTrue(ThemeGate.allowsAdvanced)
        XCTAssertEqual(s.effectiveKeyStyle, Self.custom)
        let p = s.palette(systemDark: true, wallpaperActive: false)
        XCTAssertEqual(p.keyFill, RGBA(hex: 0x102030))
        XCTAssertEqual(p.keyInk, RGBA(hex: 0xFF2D55))
    }

    // MARK: màu

    func testCustomColors() {
        // Chỉ đổi nền: chữ theme tự đổi đen/trắng cho đọc được.
        for t in KeyboardTheme.allCases {
            for dark in [false, true] {
                for fill: UInt32 in [0x000000, 0xFFFFFF, 0xFFD60A, 0x203040] {
                    var s = ThemeSettings(theme: t)
                    s.keyStyle = KeyStyle(fillColor: fill)
                    let p = s.palette(systemDark: dark, wallpaperActive: false)
                    XCTAssertGreaterThanOrEqual(RGBA.contrast(p.keyInk, p.keyFill), KeyboardTransparency.minLabelContrast,
                                                "\(t) \(dark) \(String(fill, radix: 16))")
                    XCTAssertGreaterThanOrEqual(RGBA.contrast(p.ink, p.balloon), KeyboardTransparency.minLabelContrast)
                }
            }
        }
        // Chữ người dùng chọn: độ trong suốt phím 100% không lật sang đen/trắng.
        var s = ThemeSettings(theme: .peach, keyboardTransparency: 100)
        s.keyStyle = KeyStyle(labelColor: 0x3366FF)
        XCTAssertEqual(s.palette(systemDark: true, wallpaperActive: false).keyInk, RGBA(hex: 0x3366FF))
        // Không tuỳ chỉnh ⇒ palette y như cũ.
        let base = KeyboardTheme.mint.palette(systemDark: false)
        XCTAssertEqual(KeyStyle().applyColors(to: base), base)
    }

    // MARK: sao lưu

    func testBackupIncludesKeyStyle() {
        let specs = BackupSettings.byKey
        XCTAssertEqual(specs[KeyStyleStore.key]?.kind, .styleMap)
        // Khoá chung cũ: chỉ NHẬN (file cũ), không xuất.
        for k in KeyStyleStore.legacyKeys {
            XCTAssertFalse(BackupSettings.all.contains { $0.key == k }, k)
            XCTAssertNotNil(specs[k], k)
        }

        let a = "keystyle-bk-a-\(UUID().uuidString)", b = "keystyle-bk-b-\(UUID().uuidString)"
        let da = UserDefaults(suiteName: a)!, db = UserDefaults(suiteName: b)!
        defer { da.removePersistentDomain(forName: a); db.removePersistentDomain(forName: b) }
        var s = ThemeSettings(theme: .mint)
        s.keyStyle = Self.custom
        s.setStyle(KeyStyle(accentColor: 0xD6336C), for: .system)
        s.save(da)
        let exported = BackupStore(defaults: da, containerURL: nil).settings()
        XCTAssertEqual(exported[KeyStyleStore.key], .string(KeyStyleStore.serialize(s.keyStyles)))
        BackupStore(defaults: db, containerURL: nil).setSettings(exported)
        XCTAssertEqual(ThemeSettings.load(db).keyStyles, s.keyStyles)
        // Máy chưa từng chỉnh: xuất "{}".
        let fresh = BackupStore(defaults: UserDefaults(suiteName: "keystyle-empty-\(UUID().uuidString)")!,
                                containerURL: nil).settings()
        XCTAssertEqual(fresh[KeyStyleStore.key], .string("{}"))
    }
}


/// Bản tối của theme pastel + bộ theme 10/2026 (Tim đen, Hoa xanh, Xanh lá, Neon, Hồng):
/// bảng màu chung với Android (Fixtures/theme-palettes.tsv), độ đọc được, cổng Plus, hoạ tiết nền rẻ,
/// và đi cùng độ trong suốt / ảnh nền / Nền theo hệ thống / Tuỳ chỉnh nâng cao ở chế độ tối.
final class ThemeSetTests: XCTestCase {
    private var savedDefaults: UserDefaults!
    private var savedPaywall = false
    private var suite = ""

    override func setUp() {
        super.setUp()
        savedDefaults = PlusGate.defaults
        savedPaywall = PlusGate.paywallEnabled
        PlusGate.paywallEnabled = false
        suite = "themeset-\(UUID().uuidString)"
        PlusGate.defaults = UserDefaults(suiteName: suite)!
    }

    override func tearDown() {
        PlusGate.defaults.removePersistentDomain(forName: suite)
        PlusGate.defaults = savedDefaults
        PlusGate.paywallEnabled = savedPaywall
        super.tearDown()
    }

    static let newThemes: [KeyboardTheme] = [.blackHeart, .greenFloral, .sage, .neon, .pink,
                                             .tet, .tetMai, .xmas, .xmasSnow, .piano,
                                             .sen,
                                             .typewriter, .rgb, .space,
                                             .trungthu, .valentine, .halloween,
                                             .guitar,
                                             .mole]
    static let pastels: [KeyboardTheme] = [.peach, .mint, .sky, .lavender]

    // MARK: bảng màu chung iOS ↔ Android

    private struct Fixture {
        var order: [String] = []
        var plus: [String] = []
        var rows: [(theme: String, dark: Bool, cols: [String])] = []
    }

    private func fixture() throws -> Fixture {
        let url = try XCTUnwrap(Bundle(for: ThemeSetTests.self).url(forResource: "theme-palettes", withExtension: "tsv"))
        var f = Fixture()
        for line in try String(contentsOf: url, encoding: .utf8).split(separator: "\n") where !line.hasPrefix("#") {
            let c = line.split(separator: "\t").map(String.init)
            switch c[0] {
            case "order": f.order = c[1].split(separator: ",").map(String.init)
            case "plus": f.plus = c[1].split(separator: ",").map(String.init)
            default: f.rows.append((c[0], c[1] == "1", Array(c.dropFirst(2))))
            }
        }
        return f
    }

    /// AARRGGBB, alpha cắt cụt (Android withAlpha cũng cắt cụt).
    private static func hex(_ c: RGBA?) -> String {
        guard let c else { return "-" }
        return String(format: "%08X", ThemeColorCode.argb(c))
    }

    func testPalettesMatchSharedFixtureWithAndroid() throws {
        let f = try fixture()
        XCTAssertEqual(KeyboardTheme.allCases.map(\.rawValue), f.order, "id + thứ tự phải trùng Android")
        XCTAssertEqual(KeyboardTheme.allCases.filter(\.isPlus).map(\.rawValue), f.plus)
        XCTAssertEqual(f.rows.count, 52)
        for r in f.rows {
            let t = try XCTUnwrap(KeyboardTheme(rawValue: r.theme), r.theme)
            let p = t.palette(systemDark: r.dark)
            let deco = p.decoration.map { "\($0.motif.rawValue)\($0.alt.map { "+" + $0.rawValue } ?? ""):\(Self.hex($0.color))" } ?? "-"
            let got = [Self.hex(p.background), Self.hex(p.keyFill), Self.hex(p.specialFill), Self.hex(p.ink),
                       Self.hex(p.accent), Self.hex(p.accentInk), Self.hex(p.keyBorder), Self.hex(p.functionFill),
                       Self.hex(p.functionInk), deco]
            XCTAssertEqual(got, r.cols, "\(r.theme) dark=\(r.dark)")
        }
    }

    // MARK: bản tối

    func testDarkVariantsKeepHueFamilyAndAccent() {
        for t in Self.pastels + [.greenFloral, .sage, .pink] {
            let light = t.palette(systemDark: false), dark = t.palette(systemDark: true)
            XCTAssertNotEqual(light, dark, t.rawValue)
            XCTAssertFalse(light.isDark, t.rawValue)
            XCTAssertTrue(dark.isDark, "\(t) bản tối phải là tối (icon/emoji theo nhánh tối)")
            XCTAssertLessThan(dark.background!.luminance, 0.05, "\(t) nền tối sẫm")
            XCTAssertLessThan(dark.keyFill.luminance, 0.08, "\(t) phím tối sẫm")
            XCTAssertEqual(light.accent, dark.accent, "\(t) giữ màu nhấn")
            // Cùng họ màu: kênh trội của nền tối = kênh trội của nền sáng (hồng / xanh / tím…).
            func dominant(_ c: RGBA) -> Int { [c.r, c.g, c.b].enumerated().max { $0.element < $1.element }!.offset }
            XCTAssertEqual(dominant(light.background!), dominant(dark.background!), t.rawValue)
        }
    }

    /// Đi theo sáng/tối hệ thống TỰ ĐỘNG qua ThemeSettings (không công tắc riêng).
    func testSettingsFollowSystemAppearance() {
        for t in Self.pastels + Self.newThemes {
            let s = ThemeSettings(theme: t)
            XCTAssertEqual(s.palette(systemDark: true, wallpaperActive: false).background,
                           t.palette(systemDark: true).background, t.rawValue)
            XCTAssertEqual(s.palette(systemDark: false, wallpaperActive: false).background,
                           t.palette(systemDark: false).background, t.rawValue)
        }
    }

    // MARK: đọc được

    /// Chữ phím, chữ phím chức năng, thanh gợi ý: ≥ 4.5:1 và `readable` không phải lật màu.
    func testLabelsReadableInEveryMode() {
        for t in KeyboardTheme.allCases where t != .system && t != .glass {
            for dark in [false, true] {
                let p = t.palette(systemDark: dark)
                let bg = p.background!
                let key = p.keyFill.over(bg), fn = p.fnFill.over(bg)
                XCTAssertGreaterThanOrEqual(RGBA.contrast(p.ink, key), 4.5, "\(t) \(dark) phím")
                XCTAssertGreaterThanOrEqual(RGBA.contrast(p.fnInk, fn), 4.5, "\(t) \(dark) phím chức năng")
                XCTAssertGreaterThanOrEqual(RGBA.contrast(p.ink, p.specialFill.over(bg)), 4.5, "\(t) \(dark) phím đè")
                XCTAssertEqual(KeyboardTransparency.readable(p.ink, on: key), p.ink)
                XCTAssertEqual(KeyboardTransparency.readable(p.fnInk, on: fn), p.fnInk)
                XCTAssertEqual(KeyboardTransparency.readable(p.barInk, on: bg), p.barInk)
                XCTAssertGreaterThanOrEqual(RGBA.contrast(p.ink, p.balloon), 4.5, "\(t) \(dark) ô phóng to")
                XCTAssertGreaterThanOrEqual(RGBA.contrast(p.accentInk, p.accent), 3, "\(t) \(dark) Nhập")
                if let d = p.decoration {
                    // Hoạ tiết mờ: chữ thanh gợi ý vẫn đọc được ngay trên hoạ tiết.
                    XCTAssertGreaterThanOrEqual(RGBA.contrast(p.barInk, d.color.over(bg)), 4.5, "\(t) \(dark) hoạ tiết")
                }
            }
        }
    }

    // MARK: Plus

    func testNewThemesArePlusAndGated() {
        for t in Self.newThemes { XCTAssertTrue(t.isPlus, t.rawValue) }
        PlusGate.paywallEnabled = true
        PlusGate.setPurchased(false)
        PlusGate.debugOverride = false
        for t in Self.newThemes {
            XCTAssertFalse(ThemeGate.allows(t), t.rawValue)
            let s = ThemeSettings(theme: t)
            XCTAssertEqual(s.effectiveTheme, .system)
            XCTAssertNil(s.effectiveKeyStyle.corner, "hết Plus ⇒ không mang bo góc của Hồng")
        }
        PlusGate.setPurchased(true)
        for t in Self.newThemes { XCTAssertTrue(ThemeGate.allows(t), t.rawValue) }
    }

    func testNewThemesRoundTripAndBackupKeys() throws {
        let name = "themeset-rt-\(UUID().uuidString)"
        let d = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { d.removePersistentDomain(forName: name) }
        for t in Self.newThemes {
            ThemeSettings(theme: t).save(d)
            XCTAssertEqual(ThemeSettings.load(d).theme, t)
            let k = try XCTUnwrap(t.systemBackdropKey)
            XCTAssertEqual(BackupSettings.byKey[k]?.kind, .bool(false), k)
        }
    }

    // MARK: trang "Chọn giao diện"

    // MARK: âm / hiệu ứng đi kèm theme ("sound" / "effect")

    func testFestiveThemesCarrySoundAndEffect() {
        XCTAssertEqual(KeyboardTheme.tet.spec?.sound, "phao"); XCTAssertEqual(KeyboardTheme.tet.spec?.effect, "blossom")
        XCTAssertEqual(KeyboardTheme.tetMai.spec?.sound, "phao")
        XCTAssertEqual(KeyboardTheme.xmas.spec?.sound, "jingle"); XCTAssertEqual(KeyboardTheme.xmas.spec?.effect, "snow")
        XCTAssertEqual(KeyboardTheme.piano.spec?.sound, "piano"); XCTAssertNil(KeyboardTheme.piano.spec?.effect)
        XCTAssertNil(KeyboardTheme.peach.spec?.sound); XCTAssertNil(KeyboardTheme.peach.spec?.effect)
        XCTAssertEqual(ThemeSettings(theme: .tet).effectiveKeyStyle.sound, "phao")
        for t in [KeyboardTheme.tet, .tetMai, .xmas, .xmasSnow, .piano, .typewriter, .rgb, .space] {
            XCTAssertEqual(L10n.en[t.title] != nil || L10n.en[t.spec!.nameVi] != nil, true, t.rawValue)
        }
    }

    /// Sen Việt: Plus, âm đàn tranh + hiệu ứng cánh hoa (màu nhấn hồng sen), motif hoa sen cả hai chế độ; bản sáng
    /// nền kem hồng / phím trắng / phím chức năng xanh lá, bản tối nền xanh đen; tên vi + en. Android y hệt.
    func testSenThemeCarriesDanTranhAndPetal() throws {
        let t = KeyboardTheme.sen
        XCTAssertTrue(t.isPlus)
        XCTAssertEqual(t.spec?.sound, "dantranh"); XCTAssertEqual(t.spec?.effect, "petal")
        XCTAssertEqual(t.spec?.nameVi, "Sen Việt"); XCTAssertEqual(t.spec?.nameEn, "Vietnamese Lotus")
        XCTAssertEqual(L10n.en[t.spec!.nameVi], "Vietnamese Lotus")
        XCTAssertTrue(ThemeExtras.soundAllowed("dantranh"))
        XCTAssertEqual(ThemeSettings(theme: .sen).effectiveKeyStyle.sound, "dantranh")
        let light = t.palette(systemDark: false), dark = t.palette(systemDark: true)
        XCTAssertFalse(light.isDark); XCTAssertTrue(dark.isDark)
        XCTAssertEqual(light.keyFill, RGBA(hex: 0xFFFFFF))
        XCTAssertEqual(light.functionFill, RGBA(hex: 0x2E7D32))
        XCTAssertEqual(light.accent, dark.accent)
        XCTAssertEqual(light.decoration?.motif, .lotus); XCTAssertEqual(dark.decoration?.motif, .lotus)
        // Chọn theme: lưu kiểu âm đàn tranh + hiệu ứng cánh hoa, KHÔNG bật âm thanh phím.
        let plan = ThemeExtras.plan(ThemeSettings(theme: .sen).effectiveKeyStyle, soundOn: false,
                                    effectAllowed: { _ in true }, soundAllowed: ThemeExtras.soundAllowed)
        XCTAssertEqual(plan, ThemeExtras.Outcome(effect: "petal", sound: "dantranh", soundHint: true))
        // JSON chép → dán trọn vòng.
        let text = try XCTUnwrap(ThemeJSONActions.copyText(.builtin(.sen), settings: ThemeSettings(theme: .sen), store: [:]))
        let back = try XCTUnwrap(ThemeSpecParser.parse(text).spec)
        XCTAssertEqual(back.sound, "dantranh"); XCTAssertEqual(back.effect, "petal")
        XCTAssertEqual(back.light.deco?.motif, .lotus)
        XCTAssertEqual(ThemeSpecParser.parse(back.canonical).spec, back)
    }

    /// Hoa sen: mọi đường con cùng chiều quay (tô nonzero = hợp, không thủng) + nằm trọn trong ô ±0.5.
    func testLotusMotifShape() {
        let subs = KeyboardDecoration.shape(.lotus)
        XCTAssertEqual(subs.count, 6)
        let box = KeyboardDecoration(motif: .lotus, color: .white).path([KeyboardDecoration.Placement(x: 0, y: 0, size: 1)]).boundingBoxOfPath
        XCTAssertGreaterThanOrEqual(box.minX, -0.5); XCTAssertLessThanOrEqual(box.maxX, 0.5)
        XCTAssertGreaterThanOrEqual(box.minY, -0.5); XCTAssertLessThanOrEqual(box.maxY, 0.5)
        XCTAssertEqual(Double(box.minY), -0.40, accuracy: 0.01); XCTAssertEqual(Double(box.maxY), 0.40, accuracy: 0.01)
        // Diện tích có dấu (đa giác từ điểm đầu + điểm cuối từng đoạn, cubic lấy mẫu) cùng dấu.
        for sub in subs {
            var pts: [(Double, Double)] = [sub.start]
            var cur = sub.start
            for g in sub.segs {
                if g.count == 2 { cur = (g[0], g[1]); pts.append(cur); continue }
                for i in 1...20 {
                    let t = Double(i) / 20, u = 1 - t
                    pts.append((u * u * u * cur.0 + 3 * u * u * t * g[0] + 3 * u * t * t * g[2] + t * t * t * g[4],
                                u * u * u * cur.1 + 3 * u * u * t * g[1] + 3 * u * t * t * g[3] + t * t * t * g[5]))
                }
                cur = (g[4], g[5])
            }
            var area = 0.0
            for i in 0..<pts.count { let a = pts[i], b = pts[(i + 1) % pts.count]; area += a.0 * b.1 - b.0 * a.1 }
            XCTAssertGreaterThan(area, 0, "đường con ngược chiều ⇒ thủng")
        }
        // Mốc chung Android (ThemeSetTests.lotusShape).
        XCTAssertEqual(subs[0].segs[0][0], -0.2807, accuracy: 1e-4)
        XCTAssertEqual(subs[0].segs[0][1], -0.6276, accuracy: 1e-4)
        XCTAssertEqual(subs[4].segs[0][2], 0.5932, accuracy: 1e-4)
    }

    // MARK: bộ đủ món — Máy chữ cổ / Gaming RGB / Vũ trụ

    /// Màu + phông + âm + hiệu ứng đúng thiết kế; âm / hiệu ứng có trên máy (id trong danh sách trắng).
    func testFullPackThemes() throws {
        let tw = try XCTUnwrap(KeyboardTheme.typewriter.spec)
        XCTAssertEqual(tw.nameEn, "Vintage Typewriter")
        XCTAssertEqual(tw.sound, "typewriter"); XCTAssertEqual(tw.effect, "ink")
        let font = try XCTUnwrap(tw.assets.font, "phông máy chữ tải về")
        let entry = try XCTUnwrap(BuiltinFonts.list.first { $0.id == "xanh-mono" })
        XCTAssertEqual(font.ref, entry.ref, "theme trỏ đúng phông có sẵn (url + sha256)")
        XCTAssertEqual(tw.palette(dark: false).background, RGBA(hex: 0xEFE6D2))
        XCTAssertEqual(tw.corner, 80, "phím tròn tròn")
        let rgb = try XCTUnwrap(KeyboardTheme.rgb.spec)
        XCTAssertEqual(rgb.nameEn, "Gaming RGB")
        XCTAssertEqual(rgb.sound, "mechanical"); XCTAssertEqual(rgb.effect, "combo")
        for dark in [false, true] {
            XCTAssertTrue(KeyboardTheme.rgb.palette(systemDark: dark).rainbowBorder)
            XCTAssertNil(KeyboardTheme.rgb.palette(systemDark: dark).keyBorder, "viền thường nhường chỗ cầu vồng")
        }
        let sp = try XCTUnwrap(KeyboardTheme.space.spec)
        XCTAssertEqual(sp.nameEn, "Outer Space")
        XCTAssertEqual(sp.sound, "scifi"); XCTAssertEqual(sp.effect, "meteor")
        for t in [KeyboardTheme.typewriter, .rgb, .space] {
            let st = try XCTUnwrap(t.spec)
            XCTAssertTrue(ThemeExtras.soundAllowed(st.sound ?? ""), t.rawValue)
            XCTAssertNotNil(KeyEffect(rawValue: st.effect ?? ""), t.rawValue)
            XCTAssertTrue(t.isPlus)
        }
        for t in KeyboardTheme.allCases where t != .rgb {
            XCTAssertFalse(t.palette(systemDark: false).rainbowBorder, t.rawValue)
        }
    }

    /// Phông tải về chưa có (máy offline / chưa tải) ⇒ vẫn vẽ được bằng phông mặc định: theme vẫn chọn được, bảng
    /// màu đủ, kế hoạch tệp chỉ là phông (thiếu file ⇒ bàn phím dùng phông hệ thống).
    func testTypewriterRendersWithoutDownloadedFont() {
        let s = ThemeSettings(theme: .typewriter)
        XCTAssertNotNil(s.effectiveKeyStyle.assets.font)
        XCTAssertEqual(s.palette(systemDark: false, wallpaperActive: false).keyFill, RGBA(hex: 0xFBF6E9))
        let plan = ThemeAssetPlan.make(s.effectiveKeyStyle.assets)
        XCTAssertNotNil(plan.font); XCTAssertTrue(plan.skins.isEmpty)
        XCTAssertNil(plan.background); XCTAssertNil(plan.foreground)
        let empty = FileManager.default.temporaryDirectory.appendingPathComponent("vt-tw-\(UUID().uuidString)")
        XCTAssertNil(ThemeAssetLoader.load(plan, dir: empty)?.font, "chưa tải ⇒ không có phông riêng ⇒ phông mặc định")
        ThemeAssetLoader.dropCache()
    }

    /// "borderFx": đọc / chuẩn hoá / lỗi; bản vá bỏ cầu vồng ("none") và thêm cầu vồng cho theme khác.
    func testBorderFxParseAndPatch() throws {
        let base = ##"{"v":1,"name":{"vi":"x"},"light":{"key":"#000000","special":"#111111","ink":"#FFFFFF","accent":"#7C4DFF","borderFx":"rainbow"}}"##
        let s = try XCTUnwrap(ThemeSpecParser.parse(base).spec)
        XCTAssertEqual(s.light.borderFx, "rainbow")
        XCTAssertTrue(s.palette(dark: false).rainbowBorder)
        XCTAssertTrue(s.canonical.contains(#""borderFx":"rainbow""#))
        XCTAssertEqual(ThemeSpecParser.parse(s.canonical).spec?.canonical, s.canonical)
        for bad in [#""borderFx":"disco""#, #""borderFx":1"#, #""borderFx":true"#] {
            let j = base.replacingOccurrences(of: #""borderFx":"rainbow""#, with: bad)
            XCTAssertNil(ThemeSpecParser.parse(j).spec, bad)
        }
        // Bản vá: bỏ cầu vồng của Gaming RGB / thêm cho Neon.
        let rgbSlots = try XCTUnwrap(KeyboardTheme.rgb.spec).light
        var off = rgbSlots; off.borderFx = nil
        XCTAssertEqual(off.patch(from: rgbSlots).patch.borderFx, "none")
        var st = KeyStyle(); st.light = off.patch(from: rgbSlots).patch; st.dark = st.light
        var settings = ThemeSettings(theme: .rgb); settings.setStyle(st, for: .rgb)
        XCTAssertFalse(settings.palette(systemDark: false, wallpaperActive: false).rainbowBorder)
        var on = ThemeSlots(); on.borderFx = "rainbow"
        var neon = ThemeSettings(theme: .neon); var ns = KeyStyle(); ns.light = on; ns.dark = on
        neon.setStyle(ns, for: .neon)
        XCTAssertTrue(neon.palette(systemDark: true, wallpaperActive: false).rainbowBorder)
    }

    /// Bộ đủ món 10/2026: Trung Thu / Valentine / Halloween mang đủ màu + hoạ tiết + hiệu ứng + âm (Android y hệt).
    func testFestivalFullPackThemes() throws {
        let want: [(KeyboardTheme, String, String, KeyboardDecoration.Motif, KeyboardDecoration.Motif?)] = [
            (.trungthu, "trong", "lantern", .lantern, .moon), (.valentine, "pop", "heart", .hearts, nil),
            (.halloween, "boo", "smoke", .pumpkin, .bat)]
        for (t, snd, fx, m, alt) in want {
            let spec = try XCTUnwrap(t.spec, t.rawValue)
            XCTAssertEqual(spec.sound, snd); XCTAssertEqual(spec.effect, fx)
            XCTAssertTrue(KeySoundStyle.presetIDs.contains(snd)); XCTAssertNotNil(KeyEffect(rawValue: fx))
            XCTAssertTrue(t.isPlus, t.rawValue)
            XCTAssertNotNil(L10n.en[t.title], t.rawValue)
            XCTAssertEqual(spec.nameEn, ["trungthu": "Mid-Autumn", "valentine": "Valentine", "halloween": "Halloween"][t.rawValue])
            for dark in [false, true] {
                let d = try XCTUnwrap(t.palette(systemDark: dark).decoration, t.rawValue)
                XCTAssertEqual(d.motif, m); XCTAssertEqual(d.alt, alt)
            }
            // Chọn theme ⇒ đặt hiệu ứng + kiểu âm, KHÔNG bật âm thanh phím.
            let yes: (String) -> Bool = { _ in true }
            XCTAssertEqual(ThemeExtras.plan(ThemeSettings(theme: t).effectiveKeyStyle, soundOn: false, effectAllowed: yes, soundAllowed: yes),
                           ThemeExtras.Outcome(effect: fx, sound: snd, soundHint: true))
        }
        // Trung Thu / Halloween nền tối cố định; Valentine có bản sáng hồng + bản tối đỏ rượu.
        XCTAssertTrue(KeyboardTheme.trungthu.palette(systemDark: false).isDark)
        XCTAssertTrue(KeyboardTheme.halloween.palette(systemDark: false).isDark)
        XCTAssertFalse(KeyboardTheme.valentine.palette(systemDark: false).isDark)
        XCTAssertTrue(KeyboardTheme.valentine.palette(systemDark: true).isDark)
    }

    /// Motif thứ hai xen kẽ ("alt"): vị trí chẵn = motif, lẻ = alt; chép JSON giữ nguyên; không alt ⇒ như cũ.
    func testDecorationAltAlternates() throws {
        typealias D = KeyboardDecoration
        let d = D(motif: .pumpkin, color: .white, alt: .bat)
        XCTAssertEqual((0..<4).map(d.motif(at:)), [.pumpkin, .bat, .pumpkin, .bat])
        XCTAssertEqual(D(motif: .hearts, color: .white).motif(at: 1), .hearts)
        // Path xen kẽ ≠ path một motif (cùng vị trí).
        let pts = [D.Placement(x: 20, y: 20, size: 8), D.Placement(x: 60, y: 20, size: 8)]
        XCTAssertNotEqual(d.path(pts), D(motif: .pumpkin, color: .white).path(pts))
        XCTAssertEqual(D(motif: .pumpkin, color: .white, alt: .pumpkin).path(pts), D(motif: .pumpkin, color: .white).path(pts))
        // Khứ hồi JSON theme có sẵn.
        let text = try XCTUnwrap(ThemeJSONActions.copyText(.builtin(.halloween), settings: ThemeSettings(theme: .halloween), store: [:]))
        XCTAssertTrue(text.contains("\"alt\""), text)
        let back = try XCTUnwrap(ThemeSpecParser.parse(text).spec)
        XCTAssertEqual(back.light.deco?.alt, .bat)
        XCTAssertEqual(ThemeSpec.palette(back.light).decoration, KeyboardTheme.halloween.palette(systemDark: false).decoration)
    }

    // MARK: Ghi-ta (bộ đủ món 10/2026): mặt đàn gỗ mật ong, phím gỗ hồng sắc, dây đàn + khảm, lỗ thoát âm, âm + rung dây

    /// Theme mang đủ màu + hoạ tiết (dây + khảm) + lỗ thoát âm + hiệu ứng + âm; Plus; tên vi + en; nhãn ≥ 4.5:1.
    func testGuitarFullPackTheme() throws {
        let t = KeyboardTheme.guitar
        let spec = try XCTUnwrap(t.spec)
        XCTAssertEqual(spec.sound, "guitar"); XCTAssertEqual(spec.effect, "string")
        XCTAssertTrue(KeySoundStyle.presetIDs.contains("guitar")); XCTAssertEqual(KeyEffect(rawValue: "string"), .string)
        XCTAssertTrue(t.isPlus)
        XCTAssertEqual(spec.nameVi, "Ghi-ta"); XCTAssertEqual(spec.nameEn, "Guitar")
        XCTAssertEqual(L10n.en[t.title], "Guitar")
        XCTAssertEqual(KeyboardTheme.allCases[KeyboardTheme.allCases.firstIndex(of: .halloween)! + 1], .guitar, "thêm cuối danh sách (sau Halloween)")
        for dark in [false, true] {
            let p = t.palette(systemDark: dark)
            let d = try XCTUnwrap(p.decoration)
            XCTAssertEqual(d.motif, .strings); XCTAssertEqual(d.alt, .inlay)
            XCTAssertTrue(p.spaceSoundhole, "lỗ thoát âm cả hai chế độ")
            XCTAssertFalse(p.rainbowBorder)
            let bg = try XCTUnwrap(p.background)
            for (ink, fill, what) in [(p.keyInk, p.keyFill, "phím"), (p.fnInk, p.fnFill, "phím chức năng"),
                                      (p.accentInk, p.accent, "Enter"), (p.ink, p.specialFill, "phím đè"),
                                      (p.barInk, bg, "thanh gợi ý")] {
                XCTAssertGreaterThanOrEqual(RGBA.contrast(ink, fill), 4.5, "\(what) dark=\(dark)")
            }
            // Phím gỗ hồng sắc TỐI hơn mặt đàn (sáng); phím chức năng sẫm hơn phím chữ.
            XCTAssertLessThan(p.fnFill.luminance, p.keyFill.luminance)
            if !dark { XCTAssertGreaterThan(bg.luminance, 3 * p.keyFill.luminance) }
        }
        XCTAssertNotEqual(t.palette(systemDark: false), t.palette(systemDark: true))
        let yes: (String) -> Bool = { _ in true }
        XCTAssertEqual(ThemeExtras.plan(ThemeSettings(theme: t).effectiveKeyStyle, soundOn: false, effectAllowed: yes, soundAllowed: yes),
                       ThemeExtras.Outcome(effect: "string", sound: "guitar", soundHint: true), "âm không tự bật")
        XCTAssertEqual(t.systemBackdropKey, "systemBackdropGuitar")
    }

    /// "spaceDeco": đọc / chép / dán / chuẩn hoá khứ hồi; giá trị lạ ⇒ lỗi; bản vá bỏ được ("none").
    func testSpaceDecoJSONRoundTrip() throws {
        let text = try XCTUnwrap(ThemeJSONActions.copyText(.builtin(.guitar), settings: ThemeSettings(theme: .guitar), store: [:]))
        XCTAssertTrue(text.contains("\"spaceDeco\""), text)
        let back = try XCTUnwrap(ThemeSpecParser.parse(text).spec)
        XCTAssertEqual(back.light.spaceDeco, "soundhole")
        XCTAssertTrue(ThemeSpec.palette(back.light).spaceSoundhole)
        XCTAssertEqual(ThemeSpec.palette(back.light), KeyboardTheme.guitar.palette(systemDark: false))
        XCTAssertEqual(ThemeSpecParser.parse(back.canonical).spec, back)
        XCTAssertEqual(ThemeSpec.slots(from: ThemeSpec.palette(back.light)).spaceDeco, "soundhole")
        let base = ##"{"v":1,"name":{"vi":"x"},"light":{"key":"#FFFFFF","special":"#DDDDDD","ink":"#000000","accent":"#000000","spaceDeco":%@}}"##
        func issues(_ v: String) -> [ThemeIssue] { ThemeSpecParser.parse(String(format: base, v)).errors }
        XCTAssertTrue(issues("\"soundhole\"").isEmpty)
        XCTAssertTrue(issues("\"none\"").isEmpty)
        XCTAssertEqual(issues("\"rosette\"").first?.code, .badValue)
        XCTAssertEqual(issues("1").first?.code, .wrongType)
        // Bản vá: bỏ lỗ thoát âm ⇒ "none" ⇒ palette không còn; vá lại ⇒ có.
        let gl = try XCTUnwrap(KeyboardTheme.guitar.spec).light
        var edited = gl; edited.spaceDeco = nil
        let patch = edited.patch(from: gl).patch
        XCTAssertEqual(patch.spaceDeco, "none")
        var st = KeyStyle(); st.light = patch
        XCTAssertFalse(st.applyPatch(to: KeyboardTheme.guitar.palette(systemDark: false), dark: false).spaceSoundhole)
        XCTAssertTrue(gl.merged(with: ThemeSlots()).spaceDeco == "soundhole")
        let raw = KeyStyleStore.serialize(["guitar": st])
        XCTAssertEqual(KeyStyleStore.parse(raw)["guitar"], st)
        // Theme khác không có lỗ thoát âm.
        for t in KeyboardTheme.allCases where t != .guitar { XCTAssertFalse(t.palette(systemDark: false).spaceSoundhole, t.rawValue) }
    }

    /// Motif "inlay": một chấm tròn, cùng chiều quay, trong ô ±0.5, mốc chung Android. "strings": mỗi khe một dây ngang
    /// kéo hết bề ngang (trừ lề), dày dần ở khe dưới; không có motif tại điểm (chỉ alt).
    func testGuitarStringsAndInlayMotifs() {
        typealias D = KeyboardDecoration
        let subs = D.shape(.inlay)
        XCTAssertEqual(subs.count, 1)
        var sum = 0.0, area = 0.0
        var pts = [[subs[0].start.0, subs[0].start.1]]
        for g in subs[0].segs { var i = 0; while i < g.count { pts.append([g[i], g[i + 1]]); i += 2 } }
        for i in 0..<pts.count {
            let p = pts[i], q = pts[(i + 1) % pts.count]
            area += p[0] * q[1] - q[0] * p[1]
            XCTAssertLessThanOrEqual(abs(p[0]), 0.5); XCTAssertLessThanOrEqual(abs(p[1]), 0.5)
            sum += p[0] * 3 + p[1] * 7
        }
        XCTAssertGreaterThan(area, 0)
        XCTAssertEqual(sum, 0.66, accuracy: 1e-9)
        XCTAssertTrue(D.shape(.strings).isEmpty)
        // Ba khe bàn phím iPhone 402pt.
        let gaps = [D.Gap(center: 93.5, height: 11), D.Gap(center: 146.5, height: 11), D.Gap(center: 199.5, height: 11)]
        let placements = D.placements(width: 402, gaps: gaps)
        let s = D.strings(placements, width: 402)
        XCTAssertEqual(s.map(\.y), [93.5, 146.5, 199.5])
        for (x, h) in zip(s, [0.6, 0.9, 1.2]) { XCTAssertEqual(x.h, h, accuracy: 1e-9, "dây dưới dày hơn") }
        for x in s { XCTAssertEqual(x.x0, D.stringInset); XCTAssertEqual(x.x1, 402 - D.stringInset) }
        XCTAssertEqual(D.stringThickness(9), 1.5, "trần độ dày")
        let only = D(motif: .strings, color: .white), both = D(motif: .strings, color: .white, alt: .inlay)
        XCTAssertTrue(only.hasStrings); XCTAssertTrue(both.hasStrings); XCTAssertFalse(D(motif: .inlay, color: .white).hasStrings)
        let box = only.path(placements, width: 402).boundingBoxOfPath
        XCTAssertEqual(box.minX, CGFloat(D.stringInset), accuracy: 1e-6)
        XCTAssertEqual(box.maxX, CGFloat(402 - D.stringInset), accuracy: 1e-6)
        XCTAssertEqual(box.minY, 93.5 - 0.3, accuracy: 1e-6); XCTAssertEqual(box.maxY, 199.5 + 0.6, accuracy: 1e-6)
        // Có khảm (alt) ⇒ thêm chấm ở vị trí lẻ, không đổi dây.
        XCTAssertNotEqual(both.path(placements, width: 402), only.path(placements, width: 402))
        XCTAssertTrue(D.strings([], width: 402).isEmpty)
        // Không truyền bề ngang ⇒ dây tới motif xa nhất + lề.
        XCTAssertEqual(D.strings(placements, width: nil).first?.x1 ?? 0,
                       (placements.map { $0.x + $0.size / 2 }.max() ?? 0) + D.inset - D.stringInset, accuracy: 1e-9)
    }

    /// Lỗ thoát âm: tâm phím, vành ngoài không chạm mép; bàn phím thật chỉ theme Ghi-ta có 3 lớp trên phím cách.
    @MainActor func testSoundholeOnSpaceKey() {
        for (w, h) in [(180.0, 42.0), (120.0, 38.0), (60.0, 42.0), (400.0, 50.0)] {
            let r = Soundhole.radius(width: w, height: h)
            XCTAssertLessThanOrEqual(Soundhole.outerExtent(width: w, height: h), 0.47 * h, "\(w)×\(h)")
            XCTAssertLessThanOrEqual(2 * Soundhole.outerExtent(width: w, height: h), w)
            XCTAssertGreaterThan(r, 0)
        }
        XCTAssertEqual(Soundhole.radius(width: 180, height: 42), 0.34 * 42, accuracy: 1e-9)
        XCTAssertEqual(Soundhole.radius(width: 60, height: 42), 0.18 * 60, accuracy: 1e-9)
        let d = UserDefaultsProvider.shared
        let saved = d?.object(forKey: ThemeSettings.themeKey)
        defer { d?.set(saved, forKey: ThemeSettings.themeKey) }
        for t in [KeyboardTheme.guitar, .piano] {
            d?.set(t.rawValue, forKey: ThemeSettings.themeKey)
            let kb = KeyboardView(needsGlobe: false, inputController: nil) { _ in }
            kb.frame = CGRect(x: 0, y: 0, width: 402, height: 300)
            kb.applyAppearance(.light, style: .light)
            kb.setNeedsLayout(); kb.layoutIfNeeded()
            let sh = kb.debugSoundhole
            if t == .guitar {
                XCTAssertEqual(sh.count, 3)
                let box = try? XCTUnwrap(sh.hole).boundingBoxOfPath
                XCTAssertNotNil(box)
                XCTAssertGreaterThan(box?.width ?? 0, 4)
            } else {
                XCTAssertEqual(sh.count, 0, "theme khác: không lớp nào (0 chi phí)")
            }
        }
    }

    /// Hình motif mới (đèn lồng, trăng, bí ngô, dơi): mọi đường con cùng chiều (diện tích có dấu > 0 — tô nonzero
    /// không thủng), nằm trong ô ±0.5; tổng toạ độ = mốc chung Android (ThemeSetTests.newMotifShapesParity).
    func testNewMotifShapesWindingBoundsAndParity() {
        for m in [KeyboardDecoration.Motif.lantern, .moon, .pumpkin, .bat] {
            let subs = KeyboardDecoration.shape(m)
            XCTAssertFalse(subs.isEmpty, m.rawValue)
            var sum = 0.0
            for sub in subs {
                var pts = [[sub.start.0, sub.start.1]]
                for g in sub.segs { var i = 0; while i < g.count { pts.append([g[i], g[i + 1]]); i += 2 } }
                var a = 0.0
                for i in 0..<pts.count { let p = pts[i], q = pts[(i + 1) % pts.count]; a += p[0] * q[1] - q[0] * p[1] }
                XCTAssertGreaterThan(a, 0, "\(m) chiều quay")
                for p in pts {
                    XCTAssertLessThanOrEqual(abs(p[0]), 0.5 + 1e-9, m.rawValue); XCTAssertLessThanOrEqual(abs(p[1]), 0.5 + 1e-9, m.rawValue)
                    sum += p[0] * 3 + p[1] * 7
                }
            }
            XCTAssertEqual(sum, Self.motifChecksums[m.rawValue] ?? .nan, accuracy: 1e-6, m.rawValue)
        }
    }
    static let motifChecksums: [String: Double] = ["lantern": 0.55, "moon": 6.8533471195, "pumpkin": -4.65, "bat": -26.67]

    /// Chép JSON → sửa → dán: "sound" / "effect" đi trọn vòng (theme có sẵn, bản vá, theme tự tạo).
    func testSoundEffectRoundTrip() throws {
        let s = ThemeSettings(theme: .tet)
        let text = try XCTUnwrap(ThemeJSONActions.copyText(.builtin(.tet), settings: s, store: [:]))
        XCTAssertTrue(text.contains("\"sound\""), text)
        let back = try XCTUnwrap(ThemeSpecParser.parse(text).spec)
        XCTAssertEqual(back.sound, "phao"); XCTAssertEqual(back.effect, "blossom")
        XCTAssertEqual(ThemeSpecParser.parse(back.canonical).spec, back)
        // Sửa theme có sẵn: đổi âm ⇒ lưu vào bản vá; trùng mặc định theme ⇒ không lưu.
        var settings = s, store: [String: ThemeSpec] = [:]
        let edited = text.replacingOccurrences(of: "\"phao\"", with: "\"wood\"")
        XCTAssertTrue(ThemeJSONActions.save(edited, to: .builtin(.tet), settings: &settings, store: &store).ok)
        XCTAssertEqual(settings.keyStyles["tet"]?.sound, "wood")
        XCTAssertEqual(settings.effectiveKeyStyle.sound, "wood")
        XCTAssertNil(settings.keyStyles["tet"]?.effect)
        let raw = KeyStyleStore.serialize(settings.keyStyles)
        XCTAssertEqual(KeyStyleStore.parse(raw), settings.keyStyles)
        settings = s
        XCTAssertTrue(ThemeJSONActions.save(text, to: .builtin(.tet), settings: &settings, store: &store).ok)
        XCTAssertNil(settings.keyStyles["tet"]?.sound)
        // Theme tự tạo: dán + lưu kho giữ nguyên.
        var custom = back; custom.id = "mytet"
        let restored = CustomThemeStore.parse(CustomThemeStore.serialize(["mytet": custom]))
        XCTAssertEqual(restored["mytet"]?.sound, "phao"); XCTAssertEqual(restored["mytet"]?.effect, "blossom")
    }

    func testThemeExtrasPlanNeverEnablesSound() {
        let yes: (String) -> Bool = { _ in true }, no: (String) -> Bool = { _ in false }
        let st = KeyStyle(sound: "phao", effect: "blossom")
        XCTAssertEqual(ThemeExtras.plan(st, soundOn: false, effectAllowed: yes, soundAllowed: yes),
                       ThemeExtras.Outcome(effect: "blossom", sound: "phao", soundHint: true))
        XCTAssertEqual(ThemeExtras.plan(st, soundOn: true, effectAllowed: yes, soundAllowed: yes).soundHint, false)
        // Không khai báo ⇒ không đổi gì, không gợi ý.
        XCTAssertEqual(ThemeExtras.plan(KeyStyle(), soundOn: false, effectAllowed: yes, soundAllowed: yes),
                       ThemeExtras.Outcome(effect: nil, sound: nil, soundHint: false))
        // Chưa có trên máy / khoá Plus ⇒ bỏ qua (không lưu giá trị khoá).
        XCTAssertEqual(ThemeExtras.plan(st, soundOn: false, effectAllowed: no, soundAllowed: no),
                       ThemeExtras.Outcome(effect: nil, sound: nil, soundHint: false))
    }

    func testThemeExtrasApplyOnSelect() throws {
        let name = "theme-extras-\(UUID().uuidString)"
        let d = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { d.removePersistentDomain(forName: name) }
        d.set(false, forKey: ThemeExtras.soundOnKey)
        d.set("subtle", forKey: ThemeExtras.soundStyleKey)
        // Chọn theme có âm + hiệu ứng: lưu kiểu âm + hiệu ứng, âm thanh phím VẪN TẮT, có gợi ý.
        let r = ThemeExtras.applyOnSelect(KeyStyle(sound: "wood", effect: "heart"), to: d)
        XCTAssertTrue(r.soundHint)
        XCTAssertEqual(d.string(forKey: ThemeExtras.soundStyleKey), "wood")
        XCTAssertEqual(KeyEffect.load(d), .heart)
        XCTAssertFalse(d.bool(forKey: ThemeExtras.soundOnKey))
        // Người dùng đổi tay sau đó: giữ nguyên (chỉ áp lúc chọn) — chọn theme KHÔNG khai báo cũng không đổi.
        d.set("bubble", forKey: ThemeExtras.soundStyleKey); d.set(KeyEffect.ripple.rawValue, forKey: KeyEffect.key)
        let none = ThemeExtras.applyOnSelect(ThemeSettings(theme: .peach).effectiveKeyStyle, to: d)
        XCTAssertFalse(none.soundHint)
        XCTAssertEqual(d.string(forKey: ThemeExtras.soundStyleKey), "bubble")
        XCTAssertEqual(KeyEffect.load(d), .ripple)
        // Âm thanh phím đang bật ⇒ không gợi ý.
        d.set(true, forKey: ThemeExtras.soundOnKey)
        XCTAssertFalse(ThemeExtras.applyOnSelect(KeyStyle(sound: "wood"), to: d).soundHint)
        // Id chưa có trên máy (hiệu ứng / âm mới chưa vào bản này) ⇒ bỏ qua, không ghi id lạ.
        ThemeExtras.applyOnSelect(KeyStyle(sound: "notASound", effect: "notAnEffect"), to: d)
        XCTAssertEqual(d.string(forKey: ThemeExtras.soundStyleKey), "wood")
        XCTAssertEqual(KeyEffect.load(d), .ripple)
        // Khoá Plus: hiệu ứng Plus không được đặt.
        PlusGate.paywallEnabled = true
        PlusGate.setPurchased(false)
        PlusGate.debugOverride = false
        d.set(KeyEffect.none.rawValue, forKey: KeyEffect.key)
        XCTAssertNil(ThemeExtras.applyOnSelect(KeyStyle(effect: "firework"), to: d).effect)
        XCTAssertEqual(KeyEffect.load(d), .none)
    }

    func testPickerSectionsFreeThenPlus() {
        let secs = ThemePicker.sections
        XCTAssertEqual(secs.map(\.title), ["Miễn phí", "Plus"])
        XCTAssertEqual(secs[0].themes, [.system, .oled, .contrast, .neutral])
        XCTAssertEqual(Set(secs[0].themes + secs[1].themes), Set(KeyboardTheme.allCases))
        XCTAssertTrue(secs[1].themes.allSatisfy(\.isPlus))
        XCTAssertEqual(L10n.en["Miễn phí"], "Free")
        XCTAssertEqual(L10n.en["Chọn giao diện"], "Choose theme")
        XCTAssertEqual(L10n.en["Giao diện bàn phím"], "Keyboard theme")
    }

    /// Issue #137 (30/10/2026): "Xám trung tính" miễn phí, thêm cuối, kiểu Gboard, theo sáng/tối hệ thống — ≡ Android
    /// NeutralThemeTests (palette chung qua theme-palettes.tsv).
    func testNeutralThemeFreeGreyFollowsSystem() throws {
        let t = KeyboardTheme.neutral
        XCTAssertEqual(t.rawValue, "neutral")
        XCTAssertEqual(KeyboardTheme.allCases.last, t, "thêm CUỐI — rawValue lưu không đổi thứ tự")
        XCTAssertFalse(t.isPlus)
        XCTAssertEqual(L10n.en["Xám trung tính"], "Neutral Grey")
        XCTAssertEqual(t.spec?.nameEn, "Neutral Grey")
        let l = t.palette(systemDark: false), d = t.palette(systemDark: true)
        XCTAssertEqual([l.background, l.keyFill, l.specialFill, l.ink, l.accent, l.accentInk].map(Self.hex),
                       ["FFE8EAED", "FFFFFFFF", "FFD2D5DA", "FF1F1F1F", "FF5F6368", "FFFFFFFF"])
        XCTAssertEqual([d.background, d.keyFill, d.specialFill, d.ink, d.accent, d.accentInk].map(Self.hex),
                       ["FF202124", "FF3C4043", "FF2D2E31", "FFE8EAED", "FF9AA0A6", "FF202124"])
        XCTAssertFalse(l.isDark); XCTAssertTrue(d.isDark)
        XCTAssertNil(l.keyBorder); XCTAssertNil(l.decoration)
        // Có nền riêng ⇒ có "Nền theo hệ thống" như theme miễn phí khác, và khoá đó được sao lưu.
        XCTAssertEqual(t.systemBackdropKey, "systemBackdropNeutral")
        XCTAssertNotNil(BackupSettings.byKey["systemBackdropNeutral"])
        // Không bị khoá Plus kể cả khi chưa mua.
        let saved = PlusGate.paywallEnabled
        defer { PlusGate.paywallEnabled = saved }
        PlusGate.paywallEnabled = true
        XCTAssertTrue(ThemeGate.allows(t))
        XCTAssertEqual(ThemeSettings(theme: t).effectiveTheme, t)
    }

    func testPickerSelectRespectsPlusGate() {
        let s = ThemeSettings(theme: .oled, keyboardTransparency: 30)
        XCTAssertEqual(ThemePicker.select(.neon, in: s)?.theme, .neon)        // paywall tắt ⇒ mở
        XCTAssertEqual(ThemePicker.select(.neon, in: s)?.keyboardTransparency, 30)   // chỉ đổi theme
        PlusGate.paywallEnabled = true
        PlusGate.setPurchased(false)
        PlusGate.debugOverride = false
        XCTAssertNil(ThemePicker.select(.blackHeart, in: s))                   // khoá ⇒ không đổi
        XCTAssertEqual(ThemePicker.tap(.blackHeart, in: s), .openPlus)         // khoá ⇒ mở màn Plus
        XCTAssertEqual(ThemePicker.tap(.oled, in: s), .select(s))
        XCTAssertEqual(ThemePicker.select(.contrast, in: s)?.theme, .contrast) // miễn phí luôn chọn được
        PlusGate.setPurchased(true)
        XCTAssertEqual(ThemePicker.select(.blackHeart, in: s)?.theme, .blackHeart)
    }

    // MARK: bo góc Hồng

    func testPinkRoundedByDefaultButUserCornerWins() {
        XCTAssertEqual(ThemeSettings(theme: .pink).effectiveKeyStyle.corner, 70)
        XCTAssertNil(ThemeSettings(theme: .peach).effectiveKeyStyle.corner)
        var s = ThemeSettings(theme: .pink)
        s.keyStyle = KeyStyle(corner: 10)
        XCTAssertEqual(s.effectiveKeyStyle.corner, 10)
        XCTAssertNil(s.resetToDefaults().effectiveKeyStyle.corner)
    }

    // MARK: hoạ tiết nền

    func testDecorationOnlyOnHeartAndFloral() {
        for t in KeyboardTheme.allCases {
            for dark in [false, true] {
                let m = t.palette(systemDark: dark).decoration?.motif
                switch t {
                case .blackHeart: XCTAssertEqual(m, .hearts)
                case .greenFloral: XCTAssertEqual(m, .flowers)
                case .tet, .tetMai: XCTAssertEqual(m, .mai)
                case .xmas: XCTAssertEqual(m, .snowflake)
                case .xmasSnow: XCTAssertEqual(m, dark ? .star : .snowflake)
                case .piano: XCTAssertEqual(m, .notes)
                case .sen: XCTAssertEqual(m, .lotus)
                case .space: XCTAssertEqual(m, .starfield)
                case .trungthu: XCTAssertEqual(m, .lantern)
                case .valentine: XCTAssertEqual(m, .hearts)
                case .halloween: XCTAssertEqual(m, .pumpkin)
                case .guitar: XCTAssertEqual(m, .strings)
                case .mole: XCTAssertEqual(m, .flowers)
                default: XCTAssertNil(m, t.rawValue)
                }
            }
        }
    }

    /// Hoạ tiết CHỈ ở khe giữa các hàng phím (bug ảnh 18/10: tim đè chữ "Anh" + ☰ ở thanh gợi ý):
    /// gộp phím cùng hàng, bỏ phía trên hàng đầu, cỡ vừa khe, số motif có trần, tất định.
    func testDecorationOnlyInRowGaps() {
        typealias D = KeyboardDecoration
        // 4 hàng phím iPhone (đỉnh 46, cao 42, khe 11) + phím lệch nhẹ trong hàng (vẫn cùng hàng).
        var spans: [(top: Double, bottom: Double)] = []
        for r in 0..<4 { let t = 46 + Double(r) * 53; spans += [(t, t + 42), (t + 0.5, t + 41.5)] }
        let gaps = D.rowGaps(spans)
        XCTAssertEqual(gaps, [D.Gap(center: 93.5, height: 11), D.Gap(center: 146.5, height: 11), D.Gap(center: 199.5, height: 11)])
        XCTAssertEqual(D.rowGaps([(0, 40)]), [])                       // một hàng: không khe
        XCTAssertEqual(D.rowGaps([(0, 40), (38, 80)]), [])             // chồng nhau: cùng hàng
        let pts = D.placements(width: 402, gaps: gaps)
        XCTAssertEqual(pts.count, 18)                                   // mốc chung Android
        for p in pts {
            XCTAssertGreaterThan(p.y - p.size / 2, 46 + 42 - 1e-9, "không lên thanh gợi ý / hàng đầu")
            let g = gaps.first { abs($0.center - p.y) < 1e-9 }!
            XCTAssertLessThanOrEqual(p.size, g.height - 2 * D.clearance + 1e-9, "motif nằm trọn trong khe")
            XCTAssertGreaterThanOrEqual(p.x - p.size / 2, D.inset - 1e-9)
            XCTAssertLessThanOrEqual(p.x + p.size / 2, 402 - D.inset + 1e-9)
        }
        // Khe hẹp (ngang máy / iPad ~5pt) ⇒ không vẽ thay vì đè phím.
        XCTAssertTrue(D.placements(width: 800, gaps: [D.Gap(center: 50, height: 6)]).isEmpty)
        // Rộng: trần số motif.
        XCTAssertLessThanOrEqual(D.placements(width: 5000, gaps: Array(repeating: D.Gap(center: 50, height: 11), count: 8)).count, D.maxMotifs)
        for motif in D.Motif.allCases {
            let box = D(motif: motif, color: .white).path(pts).boundingBoxOfPath
            XCTAssertGreaterThanOrEqual(box.minY, 88 - 1e-6); XCTAssertLessThanOrEqual(box.maxY, 205 + 1e-6)
        }
        // Hoa: 5 cánh không chồng nhau, không chạm nhuỵ (tô nonzero không thủng lỗ).
        XCTAssertGreaterThan(2 * 0.32 * sin(Double.pi / 5), 2 * 0.18)
        XCTAssertGreaterThan(0.32 - 0.18, 0.12)
    }

    /// Bàn phím thật (Tim đen, Hoa xanh; sáng/tối): mọi motif dưới thanh gợi ý và không chạm phím nào.
    @MainActor func testKeyboardViewMotifsStayBetweenKeys() {
        let d = UserDefaultsProvider.shared
        let saved = d?.object(forKey: ThemeSettings.themeKey)
        defer { d?.set(saved, forKey: ThemeSettings.themeKey) }
        for t in [KeyboardTheme.blackHeart, .greenFloral, .tet, .xmasSnow, .piano, .sen, .space, .trungthu, .halloween, .guitar] {
            for dark in [false, true] {
                d?.set(t.rawValue, forKey: ThemeSettings.themeKey)
                let kb = KeyboardView(needsGlobe: false, inputController: nil) { _ in }
                let host = UIView(frame: CGRect(x: 0, y: 0, width: 402, height: 400))
                host.addSubview(kb)
                kb.frame = CGRect(x: 0, y: 0, width: 402, height: 300)
                kb.applyAppearance(dark ? .dark : .light, style: dark ? .dark : .light)
                kb.setSuggestionsEnabled(true)
                kb.setNeedsLayout(); kb.layoutIfNeeded()
                // Dựng lại hàng phím SAU lượt layout (bug ảnh: hoạ tiết mất vì khe đo lúc hàng chưa có phím)
                // — không gọi setNeedsLayout tay: rebuild phải tự xin đo lại.
                kb.configureInputKind(.normal)
                kb.layoutIfNeeded()
                let (motifs, keys) = kb.debugDecorationBoxes
                XCTAssertGreaterThan(motifs.count, 6, "\(t) \(dark)")
                for m in motifs {
                    XCTAssertGreaterThanOrEqual(m.minY, kb.debugRowsMinY, "\(t): motif lên thanh gợi ý")
                    for k in keys { XCTAssertFalse(m.intersects(k), "\(t): motif chạm phím \(k)") }
                }
            }
        }
    }

    // MARK: đi cùng độ trong suốt / ảnh nền / Nền theo hệ thống / Tuỳ chỉnh nâng cao (tối)

    func testDarkComposesWithTransparencyWallpaperBackdropAndAdvanced() {
        for t in Self.pastels + Self.newThemes {
            let base = t.palette(systemDark: true)
            // Ảnh nền: bỏ nền + hoạ tiết; chữ ≥ 4.5 trên ảnh tệ nhất cả ở phím chức năng.
            let wp = ThemeSettings(theme: t).palette(systemDark: true, wallpaperActive: true)
            XCTAssertNil(wp.background); XCTAssertNil(wp.decoration)
            if t != .piano { XCTAssertTrue(wp.isDark, t.rawValue) }   // Piano: phím ngà chữ đen ở cả hai chế độ
            XCTAssertGreaterThanOrEqual(RGBA.contrast(wp.fnInk, wp.fnFill.over(.white)), 4.5, "\(t) phím chức năng trên ảnh")
            // Nền theo hệ thống: không hoạ tiết, bảng emoji theo nền tối.
            var sb = ThemeSettings(theme: t)
            sb.systemBackdropThemes = [t]
            let sp = sb.palette(systemDark: true, wallpaperActive: false)
            XCTAssertNil(sp.background); XCTAssertNil(sp.decoration); XCTAssertEqual(sp.surfaceDark, true)
            // Độ trong suốt: hoạ tiết + nền chức năng mờ theo phím; chữ vẫn đọc được trên backdrop.
            let half = base.withTransparency(keyboard: 50, labels: 0, systemDark: true, wallpaper: false)
            XCTAssertEqual(half.decoration?.color.a ?? 0, (base.decoration?.color.a ?? 0) * 0.5, accuracy: 1e-9)
            XCTAssertEqual(half.functionFill?.a ?? 0.5, 0.5, accuracy: 1e-9)
            let full = base.withTransparency(keyboard: 100, labels: 0, systemDark: true, wallpaper: false)
            let sys = KeyboardTransparency.systemBackdrop(dark: true)
            XCTAssertGreaterThanOrEqual(RGBA.contrast(full.fnInk, full.fnFill.over(sys)), KeyboardTransparency.minLabelContrast)
            XCTAssertGreaterThanOrEqual(RGBA.contrast(full.keyInk, full.keyFill.over(sys)), KeyboardTransparency.minLabelContrast)
            let faded = base.withTransparency(keyboard: 0, labels: 40, systemDark: true, wallpaper: false)
            XCTAssertEqual(faded.fnInk.a, 0.6, accuracy: 1e-9)
            // Tuỳ chỉnh nâng cao: màu người dùng phủ mọi phím.
            var adv = ThemeSettings(theme: t)
            adv.keyStyle = KeyStyle(labelColor: 0xFF2D55, fillColor: 0x102030)
            let ap = adv.palette(systemDark: true, wallpaperActive: false)
            XCTAssertEqual(ap.fnFill, RGBA(hex: 0x102030)); XCTAssertEqual(ap.fnInk, RGBA(hex: 0xFF2D55))
            adv.keyStyle = KeyStyle(fillColor: 0xFFFFFF)
            let wf = adv.palette(systemDark: true, wallpaperActive: false)
            XCTAssertGreaterThanOrEqual(RGBA.contrast(wf.fnInk, wf.fnFill), KeyboardTransparency.minLabelContrast, t.rawValue)
        }
    }

    // MARK: bàn phím thật

    /// Tim đen / Hoa xanh vẽ hoạ tiết ở lớp nền; OLED / Hồng đào không.
    @MainActor func testKeyboardViewDecorationLayer() throws {
        let d = UserDefaultsProvider.shared
        let saved = d?.object(forKey: ThemeSettings.themeKey)
        defer { d?.set(saved, forKey: ThemeSettings.themeKey) }
        func make(_ t: KeyboardTheme, dark: Bool = true) -> KeyboardView {
            d?.set(t.rawValue, forKey: ThemeSettings.themeKey)
            let kb = KeyboardView(needsGlobe: false, inputController: nil) { _ in }
            let host = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 400))
            host.addSubview(kb)
            kb.frame = CGRect(x: 0, y: 0, width: 390, height: 300)
            kb.applyAppearance(dark ? .dark : .light, style: dark ? .dark : .light)
            kb.configureInputKind(.normal)
            kb.setNeedsLayout(); kb.layoutIfNeeded()
            return kb
        }
        XCTAssertTrue(make(.blackHeart).debugDecorationVisible)
        XCTAssertTrue(make(.greenFloral, dark: false).debugDecorationVisible)
        XCTAssertFalse(make(.oled).debugDecorationVisible)
        XCTAssertFalse(make(.peach).debugDecorationVisible)
    }
}
