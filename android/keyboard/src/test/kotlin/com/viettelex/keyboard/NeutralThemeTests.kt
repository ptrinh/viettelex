package com.viettelex.keyboard

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.io.File

/**
 * Issue #137 (30/10/2026): theme miễn phí "Xám trung tính" (iOS ≡ Android) + công tắc Hệ thống
 * "Dùng màu hình nền (Material You)" (chỉ Android 12+). Quyết định palette thuần: theme × sáng/tối × materialYou × sdk.
 */
class NeutralThemeTests {
    private val c = ThemeColor
    private var savedPaywall = false

    @Before fun setUp() { savedPaywall = PlusGate.paywallEnabled }
    @After fun tearDown() {
        PlusGate.paywallEnabled = savedPaywall
        PlusGate.install({ null }, debugBuild = false)
    }

    // ---- Xám trung tính

    @Test fun neutralIsFreeAppendedAndTitled() {
        val t = KeyboardTheme.NEUTRAL
        assertEquals("neutral", t.id)
        assertEquals(KeyboardTheme.entries.last(), t)        // thêm cuối — id lưu không đổi thứ tự
        assertFalse(t.isPlus)
        assertEquals(t, KeyboardTheme.of("neutral"))
        assertEquals("Neutral Grey", t.spec?.nameEn)
        assertEquals("Xám trung tính", t.spec?.nameVi)
        PlusGate.paywallEnabled = true
        PlusGate.install({ null }, debugBuild = false)        // chưa mua Plus
        assertTrue(ThemeGate.allows(t))
        assertEquals(t, ThemeSettings(theme = t).effectiveTheme)
        assertTrue(t in ThemePicker.sections.first { it.title == "Miễn phí" }.themes)
    }

    @Test fun neutralPaletteLightDark() {
        val l = KeyboardTheme.NEUTRAL.palette(false)!!
        assertEquals(c.rgb(0xE8EAED), l.bg); assertEquals(c.rgb(0xFFFFFF), l.keyFill)
        assertEquals(c.rgb(0xD2D5DA), l.specialFill); assertEquals(c.rgb(0x1F1F1F), l.ink)
        assertEquals(c.rgb(0x5F6368), l.action); assertEquals(c.WHITE, l.actionInk)
        assertFalse(l.isDark); assertNull(l.keyBorder); assertNull(l.decoration)
        val d = KeyboardTheme.NEUTRAL.palette(true)!!
        assertEquals(c.rgb(0x202124), d.bg); assertEquals(c.rgb(0x3C4043), d.keyFill)
        assertEquals(c.rgb(0x2D2E31), d.specialFill); assertEquals(c.rgb(0xE8EAED), d.ink)
        assertEquals(c.rgb(0x9AA0A6), d.action); assertEquals(c.rgb(0x202124), d.actionInk)
        assertTrue(d.isDark)
        // Không ánh tím: R ≈ G ≈ B (xám) ở nền / phím / phím chức năng / nhấn.
        for (p in listOf(l, d)) for (x in listOf(p.bg, p.keyFill, p.specialFill, p.action))
            assertTrue(Integer.toHexString(x), maxOf(c.red(x), c.green(x), c.blue(x)) - minOf(c.red(x), c.green(x), c.blue(x)) <= 12)
    }

    @Test fun neutralWorksWithTransparencyAndWallpaperLikeOtherFreeThemes() {
        for (dark in listOf(false, true)) {
            val p = KeyboardTheme.NEUTRAL.palette(dark)!!
            val w = p.overWallpaper()
            assertTrue(w.wallpaper)
            val worst = if (dark) c.WHITE else c.BLACK
            assertTrue(c.contrast(w.ink, c.over(w.keyFill, worst)) >= 4.5)
            val t = p.withTransparency(60, 20, dark)
            assertEquals(0.8f, t.labelAlpha, 1e-4f)
            assertTrue(c.alpha(t.keyFill) < 255)
            // Theme có palette riêng ⇒ công tắc Material You không đụng tới.
            for (my in listOf(true, false)) for (sdk in listOf(30, 34))
                assertEquals(p, ThemeSettings(theme = KeyboardTheme.NEUTRAL, materialYou = my).basePalette(dark, sdk))
        }
    }

    // ---- Hệ thống: Material You hay bảng tĩnh

    @Test fun systemColorsDecisionMatrix() {
        for (theme in listOf(KeyboardTheme.SYSTEM, KeyboardTheme.NEUTRAL, KeyboardTheme.OLED)) for (dark in listOf(false, true))
            for (my in listOf(true, false)) for (sdk in listOf(26, 30, 31, 35)) {
                val tag = "$theme dark=$dark my=$my sdk=$sdk"
                val got = ThemeSettings(theme = theme, materialYou = my).basePalette(dark, sdk)
                when {
                    theme != KeyboardTheme.SYSTEM -> assertEquals(tag, theme.palette(dark), got)
                    my && sdk >= 31 -> assertNull("$tag: null = resource Material You", got)
                    else -> assertEquals(tag, SystemColors.static(dark), got)
                }
            }
        assertFalse(SystemColors.dynamicAvailable(30)); assertTrue(SystemColors.dynamicAvailable(31))
        assertTrue(SystemColors.useDynamic(true, 31)); assertFalse(SystemColors.useDynamic(false, 31))
        assertFalse(SystemColors.useDynamic(true, 30))
    }

    @Test fun staticSystemPaletteIsNeutralWithBlueAction() {
        for (dark in listOf(false, true)) {
            val p = SystemColors.static(dark)
            assertEquals(dark, p.isDark)
            assertTrue(c.contrast(p.ink, p.keyFill) >= 4.5)
            assertTrue(c.contrast(p.actionInk, p.action) >= 3)
            assertTrue("nhấn xanh", c.blue(p.action) > c.red(p.action))
        }
    }

    /** [SystemColors.static] phải trùng values/ + values-night/ ime_colors.xml (bản máy < Android 12 dùng). */
    @Test fun staticSystemPaletteMatchesResources() {
        val res = listOf("../app/src/main/res", "app/src/main/res", "android/app/src/main/res").map(::File).firstOrNull { it.exists() }
        assertNotNull("không thấy android/app/src/main/res", res)
        for ((dir, dark) in listOf("values" to false, "values-night" to true)) {
            val xml = File(res, "$dir/ime_colors.xml").readText()
            fun col(name: String): Int {
                val m = Regex("""<color name="$name">#([0-9A-Fa-f]{8})</color>""").find(xml) ?: error("$dir thiếu $name")
                return m.groupValues[1].toLong(16).toInt()
            }
            val p = SystemColors.static(dark)
            assertEquals("$dir bg", col("ime_bg"), p.bg)
            assertEquals("$dir key", col("ime_key"), p.keyFill)
            assertEquals("$dir special", col("ime_key_special"), p.specialFill)
            assertEquals("$dir ink", col("ime_ink"), p.ink)
            assertEquals("$dir balloon", col("ime_balloon"), p.balloon)
            assertEquals("$dir popup", col("ime_popup"), p.popup)
            assertEquals("$dir action", col("ime_action"), p.action)
            assertEquals("$dir trail", col("ime_action"), p.trail)
            assertEquals("$dir actionInk", col("ime_action_ink"), p.actionInk)
            assertEquals("$dir chip", col("ime_chip"), p.chip)
        }
    }

    @Test fun materialYouPersistsAndResets() {
        assertTrue(ThemeSettings().materialYou)
        assertTrue(ThemeSettings.load { null }.materialYou)        // máy cũ chưa có khoá ⇒ bật (như cũ)
        val off = ThemeSettings(materialYou = false)
        val m = off.toMap()
        assertEquals(false, m[Keys.SYSTEM_MATERIAL_YOU])
        assertEquals(off, ThemeSettings.load { m[it] })
        assertFalse(off.isDefault)
        assertTrue(off.resetToDefaults().materialYou)             // "Khôi phục giao diện gốc" ⇒ bật lại
    }

    @Test fun backupCarriesMaterialYou() {
        val spec = BackupSettings.all.first { it.key == Keys.SYSTEM_MATERIAL_YOU }
        assertEquals(SettingKind.Bool(true), spec.kind)
    }
}
