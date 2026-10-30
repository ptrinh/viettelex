package com.viettelex.keyboard

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class KeyboardThemeTests {
    private val c = ThemeColor
    private var savedPaywall = false

    @Before fun setUp() { savedPaywall = PlusGate.paywallEnabled; PlusGate.paywallEnabled = false }   // test gating tự bật
    @After fun tearDown() {
        PlusGate.paywallEnabled = savedPaywall
        PlusGate.install({ null }, debugBuild = false)
    }

    private fun lockPlus() {
        PlusGate.paywallEnabled = true
        PlusGate.install({ null }, debugBuild = false)   // chưa mua
    }

    // ---- token

    @Test fun compactSetSystemDefault() {
        assertTrue(KeyboardTheme.entries.size in 6..40)
        assertEquals(KeyboardTheme.SYSTEM, ThemeSettings().theme)
        assertNull("Hệ thống dùng màu Material You trong resources", KeyboardTheme.SYSTEM.palette(false))
    }

    @Test fun sameIdsAsIOS() {
        assertEquals(listOf("system", "oled", "contrast", "peach", "mint", "sky", "lavender", "glass",
            "blackHeart", "greenFloral", "sage", "neon", "pink", "tet", "tetMai", "xmas", "xmasSnow", "piano", "sen",
            "typewriter", "rgb", "space", "trungthu", "valentine", "halloween", "guitar", "mole", "neutral"),
            KeyboardTheme.entries.map { it.id })
    }

    @Test fun isDarkMatchesInk() {
        for (t in KeyboardTheme.entries) for (d in listOf(false, true)) {
            val p = t.palette(d) ?: continue
            assertEquals("$t", c.luminance(p.ink) > 0.5, p.isDark)
        }
    }

    @Test fun glassIsGradient() {
        assertNotNull(KeyboardTheme.GLASS.palette(false)!!.bgBottom)
        assertTrue(c.alpha(KeyboardTheme.GLASS.palette(true)!!.keyFill) < 255)
    }

    // ---- WCAG

    @Test fun contrastMath() {
        assertEquals(21.0, c.contrast(c.WHITE, c.BLACK), 0.01)
        assertEquals(4.54, c.contrast(c.rgb(0x767676), c.WHITE), 0.02)
    }

    @Test fun highContrastMeetsAAA() {
        val p = KeyboardTheme.CONTRAST.palette(false)!!
        assertTrue(c.contrast(p.ink, c.over(p.keyFill, p.bg)) >= 7)
        assertTrue(c.contrast(p.ink, c.over(p.specialFill, p.bg)) >= 7)
        assertTrue(c.contrast(p.actionInk, p.action) >= 7)
        assertTrue(c.contrast(p.ink, p.bg) >= 7)
        assertTrue(c.contrast(c.over(p.keyBorder!!, p.bg), p.bg) >= 3)
    }

    @Test fun allThemesMeetAA() {
        for (t in KeyboardTheme.entries) for (d in listOf(false, true)) {
            val p = t.palette(d) ?: continue
            val bottom = p.bgBottom ?: p.bg
            for (bg in listOf(p.bg, bottom)) {
                assertTrue("$t/$d phím", c.contrast(p.ink, c.over(p.keyFill, bg)) >= 4.5)
                assertTrue("$t/$d phím chức năng", c.contrast(p.ink, c.over(p.specialFill, bg)) >= 4.5)
                assertTrue("$t/$d thanh gợi ý", c.contrast(p.barInk ?: p.ink, bg) >= 4.5)
            }
            assertTrue("$t/$d nhấn", c.contrast(p.actionInk, p.action) >= 3)
        }
    }

    @Test fun wallpaperKeysLegibleOnWorstImage() {
        for (t in KeyboardTheme.entries) for (d in listOf(false, true)) {
            val p = t.palette(d)?.overWallpaper() ?: continue
            assertTrue(p.wallpaper)
            val worst = if (p.isDark) c.WHITE else c.BLACK
            assertTrue("$t/$d", c.contrast(p.ink, c.over(p.keyFill, worst)) >= 4.5)
            assertTrue("$t/$d đè", c.contrast(p.ink, c.over(p.specialFill, worst)) >= 4.5)
            if (!p.isDark) assertTrue("$t phím nên hơi trong", c.alpha(p.keyFill) < 255)
        }
    }

    // ---- Plus

    @Test fun openWhilePaywallOff() {
        PlusGate.paywallEnabled = false
        KeyboardTheme.entries.forEach { assertTrue(ThemeGate.allows(it)) }
        assertTrue(ThemeGate.allowsWallpaper)
    }

    @Test fun freeThemesStayFreeBehindPaywall() {
        lockPlus()
        assertTrue(ThemeGate.allows(KeyboardTheme.SYSTEM))
        assertTrue(ThemeGate.allows(KeyboardTheme.OLED))
        assertTrue(ThemeGate.allows(KeyboardTheme.CONTRAST))
        assertTrue(ThemeGate.allows(KeyboardTheme.NEUTRAL))
        assertFalse(ThemeGate.allows(KeyboardTheme.MINT))
        assertFalse(ThemeGate.allowsWallpaper)
        val s = ThemeSettings(theme = KeyboardTheme.GLASS, wallpaper = true)
        assertEquals(KeyboardTheme.SYSTEM, s.effectiveTheme)
        assertFalse(s.wallpaperActive(fileExists = true))
        PlusGate.install({ if (it == Keys.PLUS_UNLOCKED) true else null }, debugBuild = false)
        assertEquals(KeyboardTheme.GLASS, s.effectiveTheme)
        assertTrue(s.wallpaperActive(fileExists = true))
    }

    // ---- lưu/đọc

    @Test fun settingsRoundTrip() {
        assertEquals(ThemeSettings(), ThemeSettings.load { null })
        val s = ThemeSettings(KeyboardTheme.LAVENDER, wallpaper = true, dim = 55, blur = 7, version = 123L,
            keyboardTransparency = 35, labelTransparency = 60)
        val m = s.toMap()
        assertEquals(s, ThemeSettings.load { m[it] })
    }

    @Test fun loadClampsGarbage() {
        val m = mapOf<String, Any>(Keys.KEYBOARD_THEME to "neon-pink-unknown", Keys.WALLPAPER_DIM to 500, Keys.WALLPAPER_BLUR to -2,
            Keys.KEYBOARD_TRANSPARENCY to 180, Keys.KEY_LABEL_TRANSPARENCY to -9)
        val s = ThemeSettings.load { m[it] }
        assertEquals(100, s.keyboardTransparency)
        assertEquals(0, s.labelTransparency)
        assertEquals(KeyboardTheme.SYSTEM, s.theme)
        assertEquals(80, s.dim)
        assertEquals(0, s.blur)
    }

    // ---- độ trong suốt (cùng hợp đồng với iOS KeyboardThemeTests)

    private fun allPalettes(): List<Pair<ThemePalette, Boolean>> = KeyboardTheme.entries.flatMap { t ->
        listOf(false, true).flatMap { dark -> t.palette(dark)?.let { listOf(it to dark, it.overWallpaper() to dark) } ?: emptyList() }
    }
    private fun a(c: Int) = ThemeColor.alpha(c)

    @Test fun transparencyZeroIsIdentity() {
        for ((p, dark) in allPalettes()) {
            assertEquals(p, p.withTransparency(0, 0, dark))
            assertEquals(p, p.withTransparency(-30, -1, dark))
        }
    }

    @Test fun transparencyMapping() {
        assertEquals(1f, KeyboardTransparency.alpha(0))
        assertEquals(0.6f, KeyboardTransparency.alpha(40), 1e-6f)
        assertEquals(0f, KeyboardTransparency.alpha(100))
        assertEquals(0f, KeyboardTransparency.alpha(250))
        assertEquals(1f, KeyboardTransparency.alpha(-5))
        val peach = KeyboardTheme.PEACH.palette(false)!!
        val half = peach.withTransparency(50, 0, false)
        for (c in listOf(half.bg, half.keyFill, half.specialFill, half.action, half.chip)) assertEquals(127, a(c))
        assertEquals(0.5f, half.surfaceAlpha)
        assertEquals(1f, half.labelAlpha)
        val glass = KeyboardTheme.GLASS.palette(false)!!.withTransparency(50, 0, false)
        assertEquals(a(KeyboardTheme.GLASS.palette(false)!!.keyBorder!!) / 2, a(glass.keyBorder!!))
        assertEquals(127, a(glass.bgBottom!!))
        for ((p, dark) in allPalettes()) {
            val z = p.withTransparency(100, 0, dark)
            for (c in listOfNotNull(z.bg, z.bgBottom, z.keyFill, z.specialFill, z.action, z.chip, z.keyBorder)) assertEquals(0, a(c))
            assertEquals(0f, z.surfaceAlpha)
            assertEquals(1f, z.labelAlpha)
            assertEquals(255, a(z.keyInk))
        }
    }

    @Test fun labelTransparencyIndependentAndSparesBalloon() {
        for ((p, dark) in allPalettes()) {
            val z = p.withTransparency(0, 100, dark)
            assertEquals(0f, z.labelAlpha)
            assertEquals(p.keyFill, z.keyFill); assertEquals(p.bg, z.bg)
            assertEquals(p.ink, z.ink); assertEquals(p.balloon, z.balloon)   // balloon rõ nguyên
            assertEquals(0.7f, p.withTransparency(0, 30, dark).labelAlpha, 1e-6f)
        }
    }

    /** Nền trong suốt lộ app khác tông → chữ tự đổi đen/trắng; mức nhỏ không được lật màu. */
    @Test fun labelsStayReadableWhenBackgroundGoesClear() {
        // Chữ tối của theme sáng trên nền tối (cơ chế đổi đen/trắng).
        val lightOnDark = KeyboardTheme.PEACH.palette(false)!!.withTransparency(100, 0, true)
        assertEquals(ThemeColor.WHITE, lightOnDark.keyInk)
        assertTrue(lightOnDark.isDark)
        // Hồng đào TỐI (chữ sáng) trên nền tối: vẫn đọc được ⇒ giữ màu theme.
        val peachDark = KeyboardTheme.PEACH.palette(true)!!
        assertEquals(peachDark.ink, peachDark.withTransparency(100, 0, true).keyInk)
        val peachLight = KeyboardTheme.PEACH.palette(false)!!
        assertEquals(peachLight.ink, peachLight.withTransparency(100, 0, false).keyInk)
        for ((p, dark) in allPalettes()) {
            val small = p.withTransparency(10, 0, dark)
            assertEquals(p.ink, small.keyInk); assertEquals(p.actionInk, small.actionInk); assertEquals(p.isDark, small.isDark)
        }
    }

    @Test fun resetToDefaults() {
        assertTrue(ThemeSettings().isDefault)
        val s = ThemeSettings(KeyboardTheme.SKY, wallpaper = true, dim = 60, blur = 9, version = 77L,
            keyboardTransparency = 40, labelTransparency = 25)
        assertFalse(s.isDefault)
        val r = s.resetToDefaults()
        assertTrue(r.isDefault)
        assertEquals(KeyboardTheme.SYSTEM, r.theme); assertFalse(r.wallpaper)
        assertEquals(30, r.dim); assertEquals(0, r.blur)
        assertEquals(0, r.keyboardTransparency); assertEquals(0, r.labelTransparency)
        assertEquals(77L, r.version)                          // ảnh nền giữ nguyên
        assertFalse(ThemeSettings(labelTransparency = 5).isDefault)
    }

    @Test fun wallpaperNeedsFile() {
        val s = ThemeSettings(KeyboardTheme.SKY, wallpaper = true)
        assertFalse(s.wallpaperActive(false))
        assertTrue(s.wallpaperActive(true))
    }

    // ---- ảnh nền

    @Test fun targetSizeCapsLongEdge() {
        assertEquals(1080 to 810, WallpaperMath.targetSize(4032, 3024))
        assertEquals(540 to 1080, WallpaperMath.targetSize(1500, 3000))
        assertEquals(600 to 400, WallpaperMath.targetSize(600, 400))   // không phóng to
        for ((w, h) in listOf(12000 to 9000, 1081 to 1, 3000 to 4000)) {
            val (tw, th) = WallpaperMath.targetSize(w, h)
            assertTrue(maxOf(tw, th) <= WallpaperMath.MAX_EDGE)
        }
    }

    @Test fun sampleSizeNeverUndershoots() {
        assertEquals(2, WallpaperMath.sampleSize(4032, 3024, 1080, 810))
        assertEquals(1, WallpaperMath.sampleSize(1080, 810, 1080, 810))
        for ((sw, sh) in listOf(4032 to 3024, 8000 to 6000, 1200 to 5000)) {
            val (tw, th) = WallpaperMath.targetSize(sw, sh)
            val s = WallpaperMath.sampleSize(sw, sh, tw, th)
            assertTrue(sw / s >= tw && sh / s >= th)
            // Bitmap giải ra ≤ 2× cạnh cần ⇒ ≤ 4× điểm ảnh, không bao giờ full-size 12MP.
            assertTrue(sw / s < tw * 2 || s == 1)
        }
    }

    @Test fun fillSizeCoversViewWithinStored() {
        // Ảnh lưu 1080×810, view IME 1080×700px → cần đúng bản lưu.
        assertEquals(1080 to 810, WallpaperMath.fillSize(1080, 810, 1080, 700))
        // View nhỏ 540×300 → 540×405 (phủ kín, aspect-fill).
        assertEquals(540 to 405, WallpaperMath.fillSize(1080, 810, 540, 300))
        // Bitmap IME tối đa 1080×1080×4 ≈ 4.4MB.
        val (w, h) = WallpaperMath.fillSize(1080, 1080, 1440, 900)
        assertTrue(w.toLong() * h * 4 <= 5_000_000)
    }

    @Test fun blurSmoothsAndKeepsSize() {
        val w = 20; val h = 10
        val px = IntArray(w * h) { if ((it % w) < w / 2) c.BLACK else c.WHITE }
        val orig = px.copyOf()
        WallpaperMath.blur(px, w, h, 6)
        assertEquals(orig.size, px.size)
        val mid = px[5 * w + w / 2]
        assertTrue(c.red(mid) in 60..200)          // biên đen/trắng đã nhoè
        assertEquals(255, c.alpha(mid))
        val flat = IntArray(16) { c.rgb(0x336699) }
        WallpaperMath.blur(flat, 4, 4, 5)
        assertTrue(flat.all { it == c.rgb(0x336699) })  // ảnh phẳng không đổi
        WallpaperMath.blur(orig, w, h, 0)            // radius 0: không làm gì
    }
}
