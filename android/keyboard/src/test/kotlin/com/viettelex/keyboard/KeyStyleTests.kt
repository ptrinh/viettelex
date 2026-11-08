package com.viettelex.keyboard

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * Ảnh nền + "Tuỳ chỉnh nâng cao" (Plus) — y hệt iOS KeyStyleTests (KeyboardThemeTests.swift):
 * độ trong suốt phím 100% không làm mất ảnh nền, bo góc, kẹp cỡ chữ, lưu/đọc, cổng Plus, sao lưu.
 */
class KeyStyleTests {
    private val c = ThemeColor
    private var savedPaywall = false

    @Before fun setUp() { savedPaywall = PlusGate.paywallEnabled; PlusGate.paywallEnabled = false }
    @After fun tearDown() {
        PlusGate.paywallEnabled = savedPaywall
        PlusGate.install({ null }, debugBuild = false)
    }

    private fun lockPlus() {
        PlusGate.paywallEnabled = true
        PlusGate.install({ null }, debugBuild = false)
    }

    private val custom = KeyStyle(labelColor = 0xFF2D55, fillColor = 0x102030, corner = 100, fontScale = 150,
        font = KeyLabelFont.MONO, weight = KeyLabelWeight.HEAVY)

    /** Palette như ImeTheme dựng (theme có bảng màu riêng; SYSTEM dùng màu resource ⇒ giả lập). */
    private fun imePalette(s: ThemeSettings, dark: Boolean, wallpaper: Boolean): ThemePalette {
        val base = s.effectiveTheme.palette(dark) ?: ThemePalette(bg = c.rgb(0xEEF0F4), keyFill = c.WHITE,
            specialFill = c.rgb(0xD6DBE3), ink = c.rgb(0x1F1F1F), trail = c.rgb(0x0B57D0), balloon = c.WHITE,
            popup = c.WHITE, action = c.rgb(0x0B57D0), actionInk = c.WHITE, chip = c.rgb(0xD3E3FD), isDark = dark)
        val styled = s.styledCurrent(base, dark)
        return (if (wallpaper) styled.overWallpaper() else styled)
            .withTransparency(s.keyboardTransparency, s.labelTransparency, dark)
    }

    // ---- bug: độ trong suốt phím 100% làm mất ảnh nền

    @Test fun keyTransparency100KeepsWallpaper() {
        for (t in KeyboardTheme.entries) for (dark in listOf(false, true)) for (dim in listOf(0, 30, 80)) {
            val s = ThemeSettings(theme = t, wallpaper = true, dim = dim, keyboardTransparency = 100)
            val p = imePalette(s, dark, wallpaper = true)
            val wl = p.wallpaperLayer(dim)
            assertEquals("$t $dark: ảnh nền phải còn nguyên", 1f, wl.imageAlpha)
            assertEquals("lớp phủ theo độ tối, không theo độ trong suốt", (255 * dim / 100f).toInt(), c.alpha(wl.overlay))
            assertEquals(0, c.alpha(p.keyFill))          // phím thì trong suốt hẳn
            assertEquals(1f, p.labelAlpha)
        }
    }

    // ---- bo góc

    @Test fun cornerRadiusMapping() {
        assertEquals(7f, KeyStyle.cornerRadius(null, 30f, 42f, 7f))      // mặc định
        assertEquals(0f, KeyStyle.cornerRadius(0, 30f, 42f, 7f))         // chữ nhật
        assertEquals(15f, KeyStyle.cornerRadius(100, 30f, 42f, 7f))      // tròn trọn cạnh ngắn
        assertEquals(21f, KeyStyle.cornerRadius(100, 200f, 42f, 7f))     // viên thuốc
        assertEquals(10.5f, KeyStyle.cornerRadius(50, 200f, 42f, 7f))
        assertEquals(15f, KeyStyle.cornerRadius(400, 30f, 42f, 7f))      // kẹp
    }

    // ---- cỡ chữ

    @Test fun fontSizeCapOnNarrowKeys() {
        val f = KeyLabelFitter
        // Phông rộng (W ≈ 0.95 em), mực Ư/Ê + g ≈ 1.25 em; phím 26×40 px, lề 3/1.
        val want = 22f * 1.5f
        val s = f.size(want, 0.95f, 0.98f, 0.27f, 26f, 40f, 3f, 1f)
        assertTrue("150% phải bị kẹp: $s", s < want)
        assertTrue("chữ rộng nhất vừa phím", s * 0.95f <= 26f - 2 * 3f + 1e-3f)
        assertTrue("mực vừa chiều cao", s * (0.98f + 0.27f) <= 40f - 2 * 1f + 1e-3f)
        // Phím rộng, cỡ vừa ⇒ giữ nguyên.
        assertEquals(22f, f.size(22f, 0.95f, 0.98f, 0.27f, 80f, 80f, 3f, 1f))
        // Ô căn giữa hộp dòng (ô phóng to / popup): dấu chồng Ễ cao hơn ascent ⇒ thu nhỏ đủ để không tràn.
        val h = 40f
        val cs = f.centeredSize(34f, lineAbove = 0.93f, lineBelow = 0.24f, emAbove = 1.12f, emBelow = 0.27f, height = h)
        val baseline = h / 2 + (0.93f - 0.24f) * cs / 2           // căn giữa (ascent+descent)/2 như KeyboardView/BalloonView
        assertTrue("đỉnh dấu chồng trong khung", baseline - 1.12f * cs >= -1e-3f)
        assertTrue("đáy trong khung", baseline + 0.27f * cs <= h + 1e-3f)
        assertEquals(20f, f.centeredSize(20f, 0.93f, 0.24f, 0.9f, 0.2f, 80f))   // dư chỗ ⇒ giữ
    }

    @Test fun sliderScalesSupersedeMediumLarge() {
        assertEquals(1f, KeyStyle().letterScale)
        val big = KeyStyle(fontScale = 150)
        assertEquals(1.5f, big.letterScale)
        assertTrue(big.controlScale in 1.2f..1.3f && big.hintScale in 1.2f..1.25f)
        assertEquals(0.8f, KeyStyle(fontScale = 80).letterScale)
        assertTrue(big.customizesLabels)
        assertFalse(KeyStyle().customizesLabels)
    }

    // ---- lưu / đọc / mặc định

    @Test fun settingsParsingAndDefaults() {
        assertEquals(KeyStyle(), ThemeSettings.load { null }.keyStyle)
        assertTrue(KeyStyle().isDefault)
        assertEquals(custom, KeyStyleStore.parse(KeyStyleStore.serialize(mapOf("mint" to custom)))["mint"])
        assertEquals("{}", KeyStyleStore.serialize(mapOf("mint" to KeyStyle())))   // mặc định ⇒ không có mục
        // Rác / ngoài phạm vi (cùng luật khoá cũ).
        // Đọc CHẶT: mục có màu sai / khoá lạ / giá trị lạ bị bỏ CẢ MỤC (theme vẽ như chưa chỉnh).
        assertNull(KeyStyleStore.parse("""{"mint":{"label":"#1000000"}}""")["mint"])
        assertNull(KeyStyleStore.parse("""{"mint":{"label":"#FF2D55","what":1}}""")["mint"])
        assertNull(KeyStyleStore.parse("""{"mint":{"font":"comic-sans"}}""")["mint"])
        assertNull(KeyStyleStore.parse("""{"mint":{"accent":true}}""")["mint"])
        // Số ngoài khoảng ⇒ kẹp.
        val g = KeyStyleStore.parse("""{"mint":{"corner":300,"fontScale":30}}""")["mint"]!!
        assertEquals(100, g.corner); assertEquals(80, g.fontScale)
        assertEquals(150, KeyStyleStore.parse("""{"mint":{"fontScale":999}}""")["mint"]!!.fontScale)
        assertEquals(emptyMap<String, KeyStyle>(), KeyStyleStore.parse("not json"))
        assertEquals(emptyMap<String, KeyStyle>(), KeyStyleStore.parse("""{"bad id!":{"corner":5},"ok":[1]}"""))
        // "rounded" từ iOS: giữ giá trị (khứ hồi), Android vẽ như mặc định.
        assertEquals(KeyLabelFont.ROUNDED, KeyStyleStore.parse("""{"sky":{"font":"rounded"}}""")["sky"]!!.font)
        assertFalse(KeyLabelFont.ROUNDED.onAndroid)
        // Thuộc ThemeSettings: lưu cùng, "Khôi phục giao diện gốc" xoá.
        val s = ThemeSettings(theme = KeyboardTheme.MINT).withKeyStyle(custom)
        val all = s.toMap()
        assertEquals(custom, ThemeSettings.load { all[it] }.keyStyle)
        assertFalse(s.isDefault)
        assertEquals(KeyStyle(), s.resetToDefaults().keyStyle)
    }

    @Test fun sameKeysAndIdsAsIOS() {
        assertEquals(listOf("keyLabelColor", "keyFillColor", "keyCornerRadius", "keyFontScale", "keyLabelFont", "keyLabelWeight"),
            listOf(Keys.KEY_LABEL_COLOR, Keys.KEY_FILL_COLOR, Keys.KEY_CORNER_RADIUS, Keys.KEY_FONT_SCALE, Keys.KEY_LABEL_FONT, Keys.KEY_LABEL_WEIGHT))
        assertEquals(listOf("default", "rounded", "serif", "mono", "condensed", "pixel"), KeyLabelFont.entries.map { it.id })
        assertEquals(listOf("light", "regular", "medium", "bold", "heavy"), KeyLabelWeight.entries.map { it.id })
    }

    // ---- cổng Plus

    @Test fun plusGatingStoredButInactiveRendersDefaults() {
        val s = ThemeSettings(theme = KeyboardTheme.OLED).withKeyStyle(custom)
        val plain = s.withKeyStyle(KeyStyle())
        lockPlus()
        assertFalse(ThemeGate.allowsAdvanced)
        assertEquals(KeyStyle(), s.effectiveKeyStyle)
        assertEquals(imePalette(plain, true, false), imePalette(s, true, false))
        assertEquals(custom, s.keyStyle)                              // giá trị lưu giữ nguyên
        PlusGate.paywallEnabled = false
        assertTrue(ThemeGate.allowsAdvanced)
        assertEquals(custom, s.effectiveKeyStyle)
        val p = imePalette(s, true, false)
        assertEquals(c.rgb(0x102030), p.keyFill)
        assertEquals(c.rgb(0xFF2D55), p.keyInk)
    }

    // ---- màu

    @Test fun customColors() {
        for (t in KeyboardTheme.entries) for (dark in listOf(false, true)) for (fill in listOf(0x000000, 0xFFFFFF, 0xFFD60A, 0x203040)) {
            val p = imePalette(ThemeSettings(theme = t).withKeyStyle(KeyStyle(fillColor = fill)), dark, false)
            assertTrue("$t $dark ${Integer.toHexString(fill)}", c.contrast(p.keyInk, p.keyFill) >= KeyboardTransparency.MIN_LABEL_CONTRAST)
            assertTrue(c.contrast(p.ink, p.balloon) >= KeyboardTransparency.MIN_LABEL_CONTRAST)
            assertTrue(c.contrast(p.ink, p.popup) >= KeyboardTransparency.MIN_LABEL_CONTRAST)
        }
        // Chữ người dùng chọn: độ trong suốt phím 100% không lật sang đen/trắng.
        val pinned = imePalette(ThemeSettings(theme = KeyboardTheme.PEACH, keyboardTransparency = 100)
            .withKeyStyle(KeyStyle(labelColor = 0x3366FF)), true, false)
        assertEquals(c.rgb(0x3366FF), pinned.keyInk)
        val base = KeyboardTheme.MINT.palette(false)!!
        assertEquals(base, KeyStyle().applyColors(base))               // không tuỳ chỉnh ⇒ y như cũ
    }

    // ---- sao lưu

    @Test fun backupIncludesKeyStyle() {
        val k = BackupSettings.byKey
        assertEquals(SettingKind.StyleMap, k[Keys.KEY_STYLES]?.kind)
        // Khoá chung cũ: chỉ NHẬN (file cũ), không xuất.
        for (key in KeyStyleStore.LEGACY_KEYS) { assertTrue(key, BackupSettings.all.none { it.key == key }); assertTrue(key, k.containsKey(key)) }

        val s = ThemeSettings(theme = KeyboardTheme.MINT).withKeyStyle(custom)
            .withKeyStyle(KeyStyle(accentColor = 0xD6336C), KeyboardTheme.SYSTEM)
        val prefs = s.toMap()
        val p = BackupPrefs.snapshot({ prefs[it] }, emptyList(), null)
        assertEquals(KeyStyleStore.serialize(s.keyStyles), p.settings!![Keys.KEY_STYLES])
        val back = BackupCodec.decode(BackupCodec.encode(p)).settings!!
        assertEquals(s.keyStyles, ThemeSettings.load { back[it] }.keyStyles)
        // Máy chưa từng chỉnh: xuất "{}".
        val fresh = BackupPrefs.snapshot({ null }, emptyList(), null).settings!!
        assertEquals("{}", fresh[Keys.KEY_STYLES])
    }
}
