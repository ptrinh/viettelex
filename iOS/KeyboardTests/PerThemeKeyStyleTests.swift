// "Tuỳ chỉnh nâng cao" RIÊNG từng theme + "Màu nhấn" + chuyển đổi (khoá chung cũ, "Trắng hồng" đã bỏ).
// Android giữ y hệt (android/keyboard/.../KeyStyleStoreTests.kt) — chuỗi lưu trùng từng ký tự (golden).
import XCTest

final class PerThemeKeyStyleTests: XCTestCase {
    private var savedDefaults: UserDefaults!
    private var savedPaywall = false
    private var suite = ""
    private var store = ""
    private var d: UserDefaults!

    override func setUp() {
        super.setUp()
        savedDefaults = PlusGate.defaults
        savedPaywall = PlusGate.paywallEnabled
        PlusGate.paywallEnabled = false
        suite = "perthemestyle-\(UUID().uuidString)"
        PlusGate.defaults = UserDefaults(suiteName: suite)!
        store = "perthemestyle-store-\(UUID().uuidString)"
        d = UserDefaults(suiteName: store)!
    }

    override func tearDown() {
        PlusGate.defaults.removePersistentDomain(forName: suite)
        PlusGate.defaults = savedDefaults
        PlusGate.paywallEnabled = savedPaywall
        d.removePersistentDomain(forName: store)
        super.tearDown()
    }

    /// Chuỗi chuẩn — Android KeyStyleStoreTests.GOLDEN phải trùng (sao lưu đi qua lại).
    static let golden = ##"{"pink":{"accent":"#D6336C","corner":70},"system":{"fill":"#102030","font":"mono","label":"#FF2D55","weight":"heavy"}}"##
    static let goldenMap: [String: KeyStyle] = [
        "pink": KeyStyle(accentColor: 0xD6336C, corner: 70),
        "system": KeyStyle(labelColor: 0xFF2D55, fillColor: 0x102030, font: .mono, weight: .heavy),
    ]

    func testCanonicalFormatMatchesAndroid() {
        XCTAssertEqual(KeyStyleStore.serialize(Self.goldenMap), Self.golden)
        XCTAssertEqual(KeyStyleStore.parse(Self.golden), Self.goldenMap)
        // Thứ tự khoá / khoảng trắng khác ⇒ chuẩn hoá về cùng chuỗi.
        XCTAssertEqual(KeyStyleStore.normalize(##"{ "system": {"weight":"heavy","label":"#ff2d55","font":"mono","fill":"#102030"}, "pink":{"corner":70,"accent":"#D6336C"} }"##), Self.golden)
        XCTAssertNil(KeyStyleStore.normalize("[1,2]"))
        XCTAssertNil(KeyStyleStore.normalize("oops"))
        XCTAssertEqual(KeyStyleStore.serialize([:]), "{}")
    }

    // MARK: riêng từng theme

    func testPerThemeIsolation() {
        var s = ThemeSettings(theme: .mint)
        s.keyStyle = KeyStyle(fillColor: 0x102030, accentColor: 0xFF9500, corner: 0)
        s.theme = .peach
        XCTAssertEqual(s.keyStyle, KeyStyle(), "đổi theme ⇒ thấy tuỳ chỉnh của theme đó (chưa có)")
        s.keyStyle = KeyStyle(labelColor: 0x3366FF)
        s.theme = .mint
        XCTAssertEqual(s.keyStyle, KeyStyle(fillColor: 0x102030, accentColor: 0xFF9500, corner: 0))
        XCTAssertEqual(s.palette(systemDark: false, wallpaperActive: false).keyFill, RGBA(hex: 0x102030))
        s.theme = .peach
        let p = s.palette(systemDark: false, wallpaperActive: false)
        let peach = KeyboardTheme.peach.palette(systemDark: false)
        XCTAssertEqual(p.keyFill, peach.keyFill, "màu nền của mint không lan sang peach")
        XCTAssertEqual(p.keyInk, RGBA(hex: 0x3366FF))
        XCTAssertEqual(p.accent, peach.accent)
        XCTAssertFalse(p.accentShift)
        // Lưu / đọc giữ đủ mọi theme.
        s.save(d)
        XCTAssertEqual(ThemeSettings.load(d).keyStyles, s.keyStyles)
        XCTAssertEqual(Set(s.keyStyles.keys), ["mint", "peach"])
        // Thẻ "Chọn giao diện" phản ánh tuỳ chỉnh riêng; theme chưa chỉnh = palette gốc.
        XCTAssertEqual(s.cardPalette(for: .mint, systemDark: false).keyFill, RGBA(hex: 0x102030))
        XCTAssertEqual(s.cardPalette(for: .mint, systemDark: false).accent, RGBA(hex: 0xFF9500))
        XCTAssertEqual(s.cardPalette(for: .sky, systemDark: false), KeyboardTheme.sky.palette(systemDark: false))
        XCTAssertEqual(s.effectiveStyle(for: .pink).corner, 70)
    }

    func testResetOnlyCurrentTheme() {
        var s = ThemeSettings(theme: .mint)
        s.keyStyle = KeyStyle(accentColor: 0x00FF00)
        s.setStyle(KeyStyle(corner: 10), for: .oled)
        s.keyStyle = KeyStyle()                          // "Đặt lại về mặc định của giao diện"
        XCTAssertNil(s.keyStyles["mint"])
        XCTAssertEqual(s.style(for: .oled), KeyStyle(corner: 10))
        s.save(d)
        XCTAssertEqual(ThemeSettings.load(d).keyStyles, ["oled": KeyStyle(corner: 10)])
        // "Khôi phục giao diện gốc" xoá hết.
        XCTAssertEqual(s.resetToDefaults().keyStyles, [:])
        s.resetToDefaults().save(d)
        XCTAssertEqual(d.string(forKey: KeyStyleStore.key), "{}")
    }

    /// 0 chi phí khi chưa chỉnh: không tạo khoá, palette y như theme gốc.
    func testNoCustomizationIsBaseline() {
        let s = ThemeSettings(theme: .sky)
        s.save(d)
        XCTAssertNil(d.object(forKey: KeyStyleStore.key))
        XCTAssertEqual(s.effectiveKeyStyle, KeyStyle())
        let base = KeyboardTheme.sky.palette(systemDark: true)
        XCTAssertEqual(KeyStyle().applyAccent(to: base), base)
        XCTAssertEqual(s.palette(systemDark: true, wallpaperActive: false), base)
    }

    // MARK: màu nhấn

    func testAccentOverrideAndInkContrast() {
        let accents: [UInt32] = [0x000000, 0xFFFFFF, 0xFFD60A, 0xD6336C, 0x00BFB2, 0x7F7F7F, 0x2C6BB8, 0x9EE0B6]
        for t in KeyboardTheme.allCases {
            for dark in [false, true] {
                for a in accents {
                    var s = ThemeSettings(theme: t)
                    s.keyStyle = KeyStyle(accentColor: a)
                    let p = s.palette(systemDark: dark, wallpaperActive: false)
                    let tag = "\(t) \(dark) \(String(a, radix: 16))"
                    XCTAssertEqual(p.accent, RGBA(hex: a), tag)
                    XCTAssertTrue(p.accentShift, tag)
                    XCTAssertEqual(p.trail, RGBA(hex: a).alpha(0.6), tag)
                    XCTAssertGreaterThanOrEqual(RGBA.contrast(p.accentInk, p.accent), KeyboardTransparency.minLabelContrast, tag)
                    // Chữ của theme vốn đọc được ⇒ giữ nguyên.
                    let base = t.palette(systemDark: dark)
                    if RGBA.contrast(base.accentInk, RGBA(hex: a)) >= KeyboardTransparency.minLabelContrast {
                        XCTAssertEqual(p.accentInk, base.accentInk, tag)
                    }
                }
            }
        }
        // Nhấn trắng, theme chữ trắng ⇒ chữ đen.
        XCTAssertEqual(KeyStyle.accentInk(.white, on: .white), .black)
        // Glyph màu nhấn của theme (functionInk) đi theo màu nhấn, vẫn đọc được trên phím chức năng.
        var p = KeyboardTheme.peach.palette(systemDark: false)
        p.functionInk = RGBA(hex: 0xC2255C)
        XCTAssertEqual(KeyStyle(accentColor: 0x1F7A5C).applyAccent(to: p).functionInk, RGBA(hex: 0x1F7A5C))
        let pale = KeyStyle(accentColor: 0xFFF8F7).applyAccent(to: p)
        XCTAssertGreaterThanOrEqual(RGBA.contrast(pale.functionInk!, p.fnFill.over(p.background!)),
                                    KeyboardTransparency.minLabelContrast)
        // Đi cùng độ trong suốt: chữ trên nhấn vẫn đọc được.
        var tr = ThemeSettings(theme: .mint, keyboardTransparency: 60)
        tr.keyStyle = KeyStyle(accentColor: 0xFFFFFF)
        let tp = tr.palette(systemDark: true, wallpaperActive: false)
        XCTAssertEqual(tp.accent.a, 0.4, accuracy: 1e-9)
        // Hết Plus ⇒ màu nhấn không áp (giá trị giữ nguyên).
        PlusGate.paywallEnabled = true; PlusGate.setPurchased(false); PlusGate.debugOverride = false
        var locked = ThemeSettings(theme: .oled)
        locked.keyStyle = KeyStyle(accentColor: 0xFF0000)
        let lp = locked.palette(systemDark: true, wallpaperActive: false)
        XCTAssertEqual(lp.accent, KeyboardTheme.oled.palette(systemDark: true).accent)
        XCTAssertFalse(lp.accentShift)
        XCTAssertEqual(locked.keyStyle.accentColor, 0xFF0000)
    }

    /// Bàn phím thật: palette (một lần mỗi lần hiện) mang màu nhấn; ⇧ bật tô màu nhấn.
    @MainActor func testKeyboardViewUsesAccent() {
        let ud = UserDefaultsProvider.shared
        let keys = [ThemeSettings.themeKey, KeyStyleStore.key] + KeyStyleStore.legacyKeys
        let saved = keys.map { ud?.object(forKey: $0) }
        defer { for (k, v) in zip(keys, saved) { ud?.set(v, forKey: k) } }
        for k in KeyStyleStore.legacyKeys { ud?.removeObject(forKey: k) }
        ud?.set("oled", forKey: ThemeSettings.themeKey)
        ud?.set(KeyStyleStore.serialize(["oled": KeyStyle(accentColor: 0xFF9500)]), forKey: KeyStyleStore.key)
        let kb = KeyboardView(needsGlobe: false, inputController: nil) { _ in }
        kb.frame = CGRect(x: 0, y: 0, width: 390, height: 300)
        kb.applyAppearance(.dark, style: .dark)
        XCTAssertEqual(kb.debugPalette.accent, RGBA(hex: 0xFF9500))
        XCTAssertTrue(kb.debugPalette.accentShift)
        XCTAssertEqual(kb.debugShiftOnColors.fill, RGBA(hex: 0xFF9500).ui)
        // Theme khác chưa chỉnh ⇒ ⇧ bật như cũ (nền trắng).
        ud?.set("mint", forKey: ThemeSettings.themeKey)
        kb.applyAppearance(.dark, style: .dark)
        XCTAssertFalse(kb.debugPalette.accentShift)
        XCTAssertEqual(kb.debugShiftOnColors.fill, RGBA.white.ui)
    }

    // MARK: chuyển đổi

    func testMigrationFromGlobalKeysIsIdempotent() {
        // Bản cũ lưu bộ chung (kể cả giá trị canh) + theme đang chọn mint.
        d.set("mint", forKey: ThemeSettings.themeKey)
        d.set(0xFF2D55, forKey: KeyStyle.labelColorKey)
        d.set(-1, forKey: KeyStyle.fillColorKey)
        d.set(100, forKey: KeyStyle.cornerKey)
        d.set(0, forKey: KeyStyle.fontScaleKey)
        d.set("serif", forKey: KeyStyle.fontKey)
        d.set("regular", forKey: KeyStyle.weightKey)
        let want = KeyStyle(labelColor: 0xFF2D55, corner: 100, font: .serif)
        // Bàn phím (app chưa chạy): chuyển trong bộ nhớ, không ghi.
        XCTAssertEqual(ThemeSettings.load(d).keyStyles, ["mint": want])
        XCTAssertNotNil(d.object(forKey: KeyStyle.labelColorKey))
        // App: ghi một lần, khoá cũ bị xoá; theme khác không nhận.
        XCTAssertTrue(ThemeSettings.migrateStored(d))
        for k in KeyStyleStore.legacyKeys { XCTAssertNil(d.object(forKey: k), k) }
        XCTAssertEqual(d.string(forKey: KeyStyleStore.key), KeyStyleStore.serialize(["mint": want]))
        let after = ThemeSettings.load(d)
        XCTAssertEqual(after.theme, .mint)
        XCTAssertEqual(after.keyStyles, ["mint": want])
        XCTAssertEqual(after.style(for: .peach), KeyStyle())
        // Lần 2: không làm gì.
        XCTAssertFalse(ThemeSettings.migrateStored(d))
        XCTAssertEqual(ThemeSettings.load(d), after)
        // Hàm thuần: áp lên kết quả của chính nó ⇒ không đổi; không ghi đè mục đã có.
        let once = KeyStyleStore.migrate(theme: "mint", styles: [:], legacy: want)
        let twice = KeyStyleStore.migrate(theme: once.theme, styles: once.styles, legacy: want)
        XCTAssertEqual(once.styles, twice.styles); XCTAssertEqual(once.theme, twice.theme)
        let kept = KeyStyleStore.migrate(theme: "mint", styles: ["mint": KeyStyle(corner: 5)], legacy: want)
        XCTAssertEqual(kept.styles["mint"], KeyStyle(corner: 5))
        // Theme lạ / chưa chọn ⇒ bộ chung về Hệ thống.
        XCTAssertEqual(KeyStyleStore.migrate(theme: "future", styles: [:], legacy: want).styles, ["system": want])
        XCTAssertEqual(KeyStyleStore.migrate(theme: nil, styles: [:], legacy: want).styles, ["system": want])
        // Bộ chung toàn mặc định (giá trị canh) ⇒ không tạo mục nào nhưng vẫn dọn khoá cũ.
        let e = "perthemestyle-e-\(UUID().uuidString)"
        let de = UserDefaults(suiteName: e)!
        defer { de.removePersistentDomain(forName: e) }
        de.set(-1, forKey: KeyStyle.labelColorKey); de.set("default", forKey: KeyStyle.fontKey)
        XCTAssertTrue(ThemeSettings.migrateStored(de))
        XCTAssertEqual(ThemeSettings.load(de).keyStyles, [:])
        XCTAssertNil(de.object(forKey: KeyStyle.labelColorKey))
        XCTAssertFalse(ThemeSettings.migrateStored(de))
    }

    /// "Trắng hồng" (Android 1.5.12 đã phát hành) ⇒ Hệ thống + màu nhấn D6336C (chỉ khi Hệ thống chưa có).
    func testPureWhiteMigratesToSystemWithPinkAccent() {
        d.set("pureWhite", forKey: ThemeSettings.themeKey)
        d.set(true, forKey: KeyStyleStore.removedBackdropKey)
        let s = ThemeSettings.load(d)
        XCTAssertEqual(s.theme, .system)
        XCTAssertEqual(s.keyStyles, ["system": KeyStyle(accentColor: 0xD6336C)])
        XCTAssertTrue(ThemeSettings.migrateStored(d))
        XCTAssertEqual(d.string(forKey: ThemeSettings.themeKey), "system")
        XCTAssertNil(d.object(forKey: KeyStyleStore.removedBackdropKey))
        XCTAssertFalse(ThemeSettings.migrateStored(d))
        XCTAssertEqual(ThemeSettings.load(d), s)
        XCTAssertEqual(s.palette(systemDark: false, wallpaperActive: false).accent, RGBA(hex: 0xD6336C))
        // Hệ thống đã có màu nhấn ⇒ giữ; mục "pureWhite" bỏ.
        let m = KeyStyleStore.migrate(theme: "pureWhite",
                                      styles: ["system": KeyStyle(accentColor: 0x00FF00), "pureWhite": KeyStyle(corner: 3)],
                                      legacy: KeyStyle(corner: 40))
        XCTAssertEqual(m.theme, "system")
        XCTAssertEqual(m.styles, ["system": KeyStyle(accentColor: 0x00FF00)])
        // Bộ chung cũ + Trắng hồng ⇒ cả hai vào Hệ thống; lặp lại không đổi.
        let both = KeyStyleStore.migrate(theme: "pureWhite", styles: [:], legacy: KeyStyle(fillColor: 0x111111))
        XCTAssertEqual(both.styles, ["system": KeyStyle(fillColor: 0x111111, accentColor: 0xD6336C)])
        let again = KeyStyleStore.migrate(theme: both.theme, styles: both.styles, legacy: KeyStyle(fillColor: 0x111111))
        XCTAssertEqual(again.styles, both.styles)
        XCTAssertNil(KeyboardTheme(rawValue: "pureWhite"))
    }

    func testUnknownThemeFallsBackToSystem() {
        for raw in ["pureWhite", "future", "", "PINK"] {
            d.set(raw, forKey: ThemeSettings.themeKey)
            XCTAssertEqual(ThemeSettings.load(d).theme, .system, raw)
        }
        // Mục của theme lạ (bản mới hơn) giữ nguyên khi khứ hồi.
        d.set("system", forKey: ThemeSettings.themeKey)
        d.set(#"{"future":{"corner":20}}"#, forKey: KeyStyleStore.key)
        let s = ThemeSettings.load(d)
        XCTAssertEqual(s.keyStyles["future"], KeyStyle(corner: 20))
        s.save(d)
        XCTAssertEqual(d.string(forKey: KeyStyleStore.key), #"{"future":{"corner":20}}"#)
    }

    // MARK: sao lưu

    func testBackupRoundTripPerTheme() throws {
        var s = ThemeSettings(theme: .pink)
        s.keyStyles = Self.goldenMap
        s.save(d)
        let snap = BackupStore(defaults: d, containerURL: nil).settings()
        XCTAssertEqual(snap[KeyStyleStore.key], .string(Self.golden))
        let payload = BackupPayload(createdAt: nil, platform: "ios", settings: snap, shortcuts: nil, templates: nil, learnedWords: nil)
        let back = try BackupCodec.decode(BackupCodec.encode(payload))
        XCTAssertEqual(back.settings?[KeyStyleStore.key], .string(Self.golden))
        let o = "perthemestyle-o-\(UUID().uuidString)"
        let other = UserDefaults(suiteName: o)!
        defer { other.removePersistentDomain(forName: o) }
        BackupStore(defaults: other, containerURL: nil).setSettings(try XCTUnwrap(back.settings))
        XCTAssertEqual(ThemeSettings.load(other).keyStyles, Self.goldenMap)
        // Đồng bộ iCloud: chuỗi sổ đồng bộ = chuỗi chuẩn; rác bị bỏ.
        XCTAssertEqual(SettingValue.fromSyncString(Self.golden, key: KeyStyleStore.key), .string(Self.golden))
        XCTAssertNil(SettingValue.fromSyncString("oops", key: KeyStyleStore.key))
        // File có CẢ khoá chung cũ lẫn keyStyles ⇒ keyStyles thắng, khoá cũ bỏ; chuỗi lộn xộn ⇒ chuẩn hoá.
        let old = #"{"format":"viettelex-backup","version":1,"settings":{"keyLabelColor":255,"keyStyles":"{ \"oled\" : {\"corner\":0} }"}}"#
        let p = try BackupCodec.decode(Data(old.utf8))
        XCTAssertEqual(p.settings?[KeyStyleStore.key], .string(#"{"oled":{"corner":0}}"#))
        let m = BackupSettings.migrateLegacyStyle(try XCTUnwrap(p.settings), theme: "mint", styles: [:])
        XCTAssertNil(m["keyLabelColor"])
        XCTAssertEqual(m[KeyStyleStore.key], .string(#"{"oled":{"corner":0}}"#))
    }

    /// Sao lưu bản CŨ (chỉ có bộ chung keyLabelColor…, chưa có keyStyles) vẫn khôi phục được: vào theme đang
    /// chọn trên máy nhận (cùng luật chuyển đổi). Fixture chung với Android (backup-legacy-keystyle.json).
    func testRestoreOldFormatBackupMigratesIntoCurrentTheme() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "backup-legacy-keystyle", withExtension: "json"))
        let p = try BackupCodec.decode(Data(contentsOf: url))
        XCTAssertEqual(p.settings?.count, 7)                                  // systemBackdropPureWhite: key lạ
        XCTAssertEqual(p.settings?[KeyStyle.labelColorKey], .int(0xFF2D55))
        let want = KeyStyle(labelColor: 0xFF2D55, corner: 100, font: .serif)
        // Máy nhận đang dùng Bạc hà, chưa chỉnh gì.
        d.set("mint", forKey: ThemeSettings.themeKey)
        BackupStore(defaults: d, containerURL: nil).setSettings(try XCTUnwrap(p.settings))
        XCTAssertEqual(ThemeSettings.load(d).keyStyles, ["mint": want])
        for k in KeyStyleStore.legacyKeys { XCTAssertNil(d.object(forKey: k), "khoá cũ không ghi lại: \(k)") }
        XCTAssertEqual(d.string(forKey: KeyStyleStore.key), KeyStyleStore.serialize(["mint": want]))
        // Nhập lại (lặp) ⇒ không đổi; theme đã có mục riêng ⇒ không ghi đè.
        BackupStore(defaults: d, containerURL: nil).setSettings(try XCTUnwrap(p.settings))
        XCTAssertEqual(ThemeSettings.load(d).keyStyles, ["mint": want])
        var s = ThemeSettings.load(d)
        s.keyStyle = KeyStyle(corner: 5)
        s.save(d)
        BackupStore(defaults: d, containerURL: nil).setSettings(try XCTUnwrap(p.settings))
        XCTAssertEqual(ThemeSettings.load(d).keyStyles, ["mint": KeyStyle(corner: 5)])
        // Máy nhận còn ở "Trắng hồng" (Android 1.5.12) ⇒ bộ cũ + màu nhấn hồng vào Hệ thống.
        let o = "perthemestyle-pw-\(UUID().uuidString)"
        let pw = try XCTUnwrap(UserDefaults(suiteName: o))
        defer { pw.removePersistentDomain(forName: o) }
        pw.set("pureWhite", forKey: ThemeSettings.themeKey)
        BackupStore(defaults: pw, containerURL: nil).setSettings(try XCTUnwrap(p.settings))
        var withAccent = want; withAccent.accentColor = 0xD6336C
        XCTAssertEqual(ThemeSettings.load(pw).keyStyles, ["system": withAccent])
        // Bộ cũ toàn mặc định ⇒ không tạo mục.
        let blank: [String: SettingValue] = [KeyStyle.labelColorKey: .int(-1), KeyStyle.fontKey: .string("default")]
        XCTAssertEqual(BackupSettings.migrateLegacyStyle(blank, theme: "mint", styles: [:]), [:])
    }

    // MARK: ô phóng to / popup theo kiểu phím (Phil 19/10/2026 — Laban Key vẽ popup trơn; ta phải giống phím)

    func testKeyPopupStyleFollowsThemeKey() {
        for t in KeyboardTheme.allCases {
            for dark in [false, true] {
                let s = ThemeSettings(theme: t)
                let p = s.palette(systemDark: dark, wallpaperActive: false)
                let ps = KeyPopupStyle.make(p, style: s.effectiveKeyStyle, systemDark: dark, wallpaper: false)
                let sys = KeyboardTransparency.systemBackdrop(dark: dark)
                let behind = p.background?.over(sys) ?? sys
                let tag = "\(t) \(dark)"
                XCTAssertEqual(ps.fill, p.keyFill.over(behind), tag)
                XCTAssertEqual(ps.fill.a, 1, tag)
                XCTAssertGreaterThanOrEqual(RGBA.contrast(ps.ink, ps.fill), KeyboardTransparency.minLabelContrast, tag)
                XCTAssertEqual(ps.selectedFill, p.accent.over(behind), tag)
                XCTAssertGreaterThanOrEqual(RGBA.contrast(ps.selectedInk, ps.selectedFill), KeyboardTransparency.minLabelContrast, tag)
                XCTAssertEqual(ps.border == nil, p.keyBorder == nil, tag)
                XCTAssertEqual(ps.borderWidth, p.keyBorder == nil ? 0 : 1, tag)
            }
        }
        for t in [KeyboardTheme.greenFloral, .neon, .contrast] {
            XCTAssertNotNil(KeyPopupStyle.make(t.palette(systemDark: true), style: .default, systemDark: true, wallpaper: false).border)
        }
        XCTAssertEqual(ThemeSettings(theme: .pink).effectiveKeyStyle.corner, 70)
    }

    func testKeyPopupStyleFollowsCustomizationAndTransparency() {
        let st = KeyStyle(labelColor: 0xFFE066, fillColor: 0x102030, accentColor: 0xFF9500, corner: 100,
                          fontScale: 130, font: .serif, weight: .bold)
        var s = ThemeSettings(theme: .mint)
        s.keyStyle = st
        let ps = KeyPopupStyle.make(s.palette(systemDark: false, wallpaperActive: false), style: s.effectiveKeyStyle,
                                    systemDark: false, wallpaper: false)
        XCTAssertEqual(ps.fill, RGBA(hex: 0x102030))
        XCTAssertEqual(ps.ink, RGBA(hex: 0xFFE066))
        XCTAssertEqual(ps.cornerPercent, 100)
        XCTAssertEqual(ps.labelScale, 1.3, accuracy: 1e-9)
        XCTAssertEqual(ps.selectedFill, RGBA(hex: 0xFF9500))
        XCTAssertEqual(ps.radius(size: CGSize(width: 30, height: 42), fallback: 9), 15)
        // Phím trong suốt hẳn ⇒ ô đục (màu nền bàn phím), chữ vẫn đọc được; ảnh nền ⇒ ghép trên lớp phủ.
        for wallpaper in [false, true] {
            let tr = ThemeSettings(theme: .sky, keyboardTransparency: 100)
            let c = KeyPopupStyle.make(tr.palette(systemDark: true, wallpaperActive: wallpaper), style: .default,
                                       systemDark: true, wallpaper: wallpaper)
            XCTAssertEqual(c.fill.a, 1)
            XCTAssertGreaterThanOrEqual(RGBA.contrast(c.ink, c.fill), KeyboardTransparency.minLabelContrast)
        }
    }

    /// Bàn phím thật: kiểu popup giải SẴN mỗi lần hiện (không mỗi lần bấm) và đổi theo theme.
    @MainActor func testKeyboardViewCachesPopupStyle() {
        let ud = UserDefaultsProvider.shared
        let keys = [ThemeSettings.themeKey, KeyStyleStore.key] + KeyStyleStore.legacyKeys
        let saved = keys.map { ud?.object(forKey: $0) }
        defer { for (k, v) in zip(keys, saved) { ud?.set(v, forKey: k) } }
        for k in KeyStyleStore.legacyKeys { ud?.removeObject(forKey: k) }
        ud?.set("greenFloral", forKey: ThemeSettings.themeKey)
        ud?.set(KeyStyleStore.serialize(["greenFloral": KeyStyle(corner: 0)]), forKey: KeyStyleStore.key)
        let kb = KeyboardView(needsGlobe: false, inputController: nil) { _ in }
        kb.frame = CGRect(x: 0, y: 0, width: 390, height: 300)
        kb.applyAppearance(.light, style: .light)
        let want = KeyPopupStyle.make(kb.debugPalette, style: KeyStyle(corner: 0), systemDark: false, wallpaper: false)
        XCTAssertEqual(kb.debugPopupStyle, want)
        XCTAssertNotNil(kb.debugPopupStyle.border)
        XCTAssertEqual(kb.debugPopupStyle.cornerPercent, 0)
        ud?.set("oled", forKey: ThemeSettings.themeKey)
        kb.applyAppearance(.dark, style: .dark)
        XCTAssertNil(kb.debugPopupStyle.border)
        XCTAssertEqual(kb.debugPopupStyle.fill, KeyboardTheme.oled.palette(systemDark: true).keyFill)
    }

    // MARK: màu viền phím (11/2026) — lưu trong light/dark "border" có sẵn; Android KeyStyleStoreTests y hệt

    /// Chuỗi chung — Android KeyStyleStoreTests.BORDER_FIXTURE phải trùng từng ký tự.
    static let borderFixture = ##"{"nightclub":{"accent":"#FF2FD0","dark":{"border":"#33CCFF"},"light":{"border":"#33CCFF"}},"pink":{"corner":70}}"##
    /// Khoá cấp mục mà MỌI bản app đã phát hành đọc được (ThemeSpecParser.override, trước 11/2026). Khoá lạ ⇒ bản
    /// cũ bỏ CẢ mục của theme — màu viền KHÔNG được thêm khoá mới ở đây.
    static let releasedEntryKeys: Set<String> = ["label", "fill", "accent", "corner", "fontScale", "font", "weight", "light",
                                                 "dark", "sound", "effect", "swipe", "game", "keyShape", "photoFx", "keyMotion"]

    func testBorderColorRoundTripAndCompat() {
        var club = KeyStyle(accentColor: 0xFF2FD0)
        club.borderColor = 0x33CCFF
        let map: [String: KeyStyle] = ["nightclub": club, "pink": KeyStyle(corner: 70)]
        XCTAssertEqual(KeyStyleStore.serialize(map), Self.borderFixture)
        let back = KeyStyleStore.parse(Self.borderFixture)
        XCTAssertEqual(back, map)
        XCTAssertEqual(back["nightclub"]?.borderColor, 0x33CCFF)
        XCTAssertEqual(back["nightclub"]?.light.border, 0xFF33CCFF)
        XCTAssertEqual(back["nightclub"]?.dark.border, 0xFF33CCFF)
        XCTAssertEqual(KeyStyleStore.normalize(Self.borderFixture), Self.borderFixture, "sao lưu / iCloud giữ nguyên")
        // Dữ liệu cũ (không có viền) ⇒ nil, các trường khác như cũ.
        let old = KeyStyleStore.parse(##"{"nightclub":{"accent":"#FF2FD0"}}"##)
        XCTAssertNil(old["nightclub"]?.borderColor)
        XCTAssertEqual(old["nightclub"], KeyStyle(accentColor: 0xFF2FD0))
        // Bản app cũ: mục chỉ dùng khoá cấp mục đã phát hành ⇒ không bị bỏ cả mục.
        guard case .success(.object(let top)) = StrictJSON.parse(Self.borderFixture, limits: KeyStyleStore.limits) else {
            return XCTFail("fixture")
        }
        for (_, entry) in top {
            guard case .object(let fields) = entry else { return XCTFail("entry") }
            for (k, _) in fields { XCTAssertTrue(Self.releasedEntryKeys.contains(k), k) }
        }
        // Đặt rồi bỏ ⇒ đúng như chưa chỉnh (không để lại bản vá rỗng).
        var st = KeyStyle()
        st.borderColor = 0x123456
        XCTAssertFalse(st.isDefault)
        st.borderColor = nil
        XCTAssertTrue(st.isDefault)
        XCTAssertEqual(KeyStyleStore.serialize(["mint": st]), "{}")
        // Giữ màu khác của bản vá JSON (chỉ đụng "border").
        var patched = KeyStyle()
        patched.light.key = 0xFF102030
        patched.borderColor = 0xABCDEF
        patched.borderColor = nil
        XCTAssertEqual(patched.light.key, 0xFF102030)
        XCTAssertNil(patched.light.border)
    }

    func testBorderColorPalette() {
        let effectThemes: [KeyboardTheme] = [.rgb, .ai, .trippy, .pride]
        for dark in [false, true] {
            // Theme có viền (Neon Night Club: ống neon hồng) ⇒ viền theo màu chọn, đục; chỉ viền đổi.
            let clubBase = KeyboardTheme.nightclub.palette(systemDark: dark)
            XCTAssertNotNil(clubBase.keyBorder)
            var s = ThemeSettings(theme: .nightclub)
            XCTAssertEqual(s.palette(systemDark: dark, wallpaperActive: false), clubBase, "chưa chọn ⇒ y như cũ")
            s.keyStyle.borderColor = 0x33CCFF
            let club = s.palette(systemDark: dark, wallpaperActive: false)
            XCTAssertEqual(club.keyBorder, RGBA(hex: 0x33CCFF))
            var expect = clubBase
            expect.keyBorder = RGBA(hex: 0x33CCFF)
            XCTAssertEqual(club, expect, "chỉ viền đổi")
            let ps = KeyPopupStyle.make(club, style: s.effectiveKeyStyle, systemDark: dark, wallpaper: false)
            XCTAssertEqual(ps.border, RGBA(hex: 0x33CCFF), "ô phóng to / popup viền cùng màu")
            XCTAssertEqual(ps.borderWidth, 1)
            XCTAssertFalse(KeyStyle.borderLocked(club, assets: s.effectiveKeyStyle.assets))

            // Theme không viền ⇒ có viền 1pt màu chọn.
            let mintBase = KeyboardTheme.mint.palette(systemDark: dark)
            XCTAssertNil(mintBase.keyBorder)
            var m = ThemeSettings(theme: .mint)
            XCTAssertEqual(m.palette(systemDark: dark, wallpaperActive: false), mintBase)
            m.keyStyle.borderColor = 0xFF9500
            let mint = m.palette(systemDark: dark, wallpaperActive: false)
            XCTAssertEqual(mint.keyBorder, RGBA(hex: 0xFF9500))
            XCTAssertEqual(KeyPopupStyle.make(mint, style: m.effectiveKeyStyle, systemDark: dark, wallpaper: false).borderWidth, 1)
            // Đi cùng độ trong suốt phím như viền theme.
            var tr = ThemeSettings(theme: .mint, keyboardTransparency: 60)
            tr.keyStyle.borderColor = 0xFF9500
            XCTAssertEqual(tr.palette(systemDark: dark, wallpaperActive: false).keyBorder?.a ?? 0, 0.4, accuracy: 1e-9)

            // Viền hiệu ứng (cầu vồng / cực quang / Ảo giác / Tự hào) ⇒ ô khoá; còn lại (kể cả Pixel, Kính màu) ⇒ mở.
            for t in KeyboardTheme.allCases {
                let ts = ThemeSettings(theme: t)
                XCTAssertEqual(KeyStyle.borderLocked(ts.palette(systemDark: dark, wallpaperActive: false),
                                                     assets: ts.effectiveKeyStyle.assets), effectThemes.contains(t), "\(t)")
            }
            for t in [KeyboardTheme.pixel, .stainedGlass] {
                var ts = ThemeSettings(theme: t)
                ts.keyStyle.borderColor = 0x00FF00
                XCTAssertEqual(ts.palette(systemDark: dark, wallpaperActive: false).keyBorder, RGBA(hex: 0x00FF00), "\(t)")
            }
            // Skin ảnh tải về ⇒ khoá.
            var skinned = ThemeAssetSpec()
            skinned.keys["default"] = ThemeKeySkin(image: ThemeAssetRef(url: "https://example.com/k.png", sha256: nil))
            XCTAssertTrue(KeyStyle.borderLocked(mintBase, assets: skinned))
        }
        // Không chọn ⇒ palette mọi theme y như trước (không thêm gì).
        for t in KeyboardTheme.allCases {
            for dark in [false, true] {
                XCTAssertEqual(KeyStyle().applyPatch(to: t.palette(systemDark: dark), dark: dark), t.palette(systemDark: dark), "\(t)")
            }
        }
        // Hết Plus ⇒ không áp (giá trị giữ nguyên).
        PlusGate.paywallEnabled = true; PlusGate.setPurchased(false); PlusGate.debugOverride = false
        var locked = ThemeSettings(theme: .mint)
        locked.keyStyle.borderColor = 0xFF0000
        XCTAssertNil(locked.palette(systemDark: true, wallpaperActive: false).keyBorder)
        XCTAssertEqual(locked.keyStyle.borderColor, 0xFF0000)
    }

    /// Mô hình ô "Màu viền phím": ghi qua keyPath như ba ô màu kia, "Theo theme" = nil; lưu / đọc giữ đúng theme.
    func testBorderColorSettingsWriteAndReset() {
        var s = ThemeSettings(theme: .nightclub)
        let kp: WritableKeyPath<KeyStyle, UInt32?> = \.borderColor
        s.keyStyle[keyPath: kp] = 0x33CCFF
        s.keyStyle.accentColor = 0xFF2FD0
        s.setStyle(KeyStyle(corner: 70), for: .pink)
        s.save(d)
        XCTAssertEqual(d.string(forKey: KeyStyleStore.key), Self.borderFixture)
        let loaded = ThemeSettings.load(d)
        XCTAssertEqual(loaded.keyStyles, s.keyStyles)
        XCTAssertEqual(loaded.keyStyle.borderColor, 0x33CCFF)
        // Theme khác không bị ảnh hưởng.
        s.theme = .mint
        XCTAssertNil(s.keyStyle.borderColor)
        XCTAssertNil(s.palette(systemDark: true, wallpaperActive: false).keyBorder)
        // "Theo theme" ⇒ về viền hồng của theme.
        s.theme = .nightclub
        s.keyStyle[keyPath: kp] = nil
        XCTAssertEqual(s.keyStyle, KeyStyle(accentColor: 0xFF2FD0))
        XCTAssertEqual(s.palette(systemDark: true, wallpaperActive: false).keyBorder,
                       KeyboardTheme.nightclub.palette(systemDark: true).keyBorder)
    }

    /// Bàn phím thật: phím (kể cả theme không viền) vẽ viền 1pt màu chọn; khoá ảnh khung đầu đổi theo màu viền.
    @MainActor func testKeyboardViewDrawsBorderColorAndSnapshotKeyChanges() {
        let ud = UserDefaultsProvider.shared
        let keys = [ThemeSettings.themeKey, KeyStyleStore.key] + KeyStyleStore.legacyKeys
        let saved = keys.map { ud?.object(forKey: $0) }
        defer { for (k, v) in zip(keys, saved) { ud?.set(v, forKey: k) } }
        for k in KeyStyleStore.legacyKeys { ud?.removeObject(forKey: k) }
        ud?.set("mint", forKey: ThemeSettings.themeKey)
        ud?.set(KeyStyleStore.empty, forKey: KeyStyleStore.key)
        let kb = KeyboardView(needsGlobe: false, inputController: nil) { _ in }
        kb.frame = CGRect(x: 0, y: 0, width: 390, height: 300)
        kb.applyAppearance(.dark, style: .dark)
        XCTAssertNil(kb.debugPalette.keyBorder)
        XCTAssertTrue(kb.debugAllKeyButtons().allSatisfy { $0.layer.borderWidth == 0 }, "chưa chọn ⇒ không viền như cũ")
        let none = KeySnapshot.digest(kb.snapshotKeyParts())
        func apply(_ c: UInt32) -> String {
            var st = KeyStyle()
            st.borderColor = c
            ud?.set(KeyStyleStore.serialize(["mint": st]), forKey: KeyStyleStore.key)
            kb.applyAppearance(.dark, style: .dark)
            return KeySnapshot.digest(kb.snapshotKeyParts())
        }
        let blue = apply(0x0A84FF)
        XCTAssertEqual(kb.debugPalette.keyBorder, RGBA(hex: 0x0A84FF))
        let buttons = kb.debugAllKeyButtons()
        XCTAssertFalse(buttons.isEmpty)
        for b in buttons {
            XCTAssertEqual(b.layer.borderWidth, 1)
            XCTAssertEqual(b.layer.borderColor, RGBA(hex: 0x0A84FF).ui.cgColor)
        }
        XCTAssertNotNil(kb.debugPopupStyle.border)
        let red = apply(0xFF3B30)
        XCTAssertNotEqual(none, blue)
        XCTAssertNotEqual(blue, red, "đổi màu viền ⇒ khoá ảnh khung đầu khác (không hiện ảnh cũ)")
    }
}
