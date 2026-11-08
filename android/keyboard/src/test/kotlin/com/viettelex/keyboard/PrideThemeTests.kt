package com.viettelex.keyboard

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import kotlin.math.abs

/**
 * Theme "Tự hào" (11/2026): lá cờ + bảng màu ([PrideFlag]), vòng cung Cầu vồng ([RainbowBurst]), cờ phấp phới + tim
 * ([PrideFlagWave]), từ khoá ([PrideKeywords]), "variant":"pride" giải lúc dựng, sao lưu `prideFlag`. Song sinh iOS
 * PrideThemeTests — CÙNG số tham chiếu.
 */
class PrideThemeTests {
    private var savedPaywall = false
    @Before fun setUp() { savedPaywall = PlusGate.paywallEnabled; PlusGate.paywallEnabled = false }
    @After fun tearDown() { PlusGate.paywallEnabled = savedPaywall; PlusGate.install({ null }, debugBuild = false) }

    @Test fun ids() {
        assertEquals(listOf("rainbow", "trans", "bi", "pan", "lesbian", "nonbinary"), PrideFlag.entries.map { it.id })
        assertEquals("prideFlag", PrideFlag.KEY)
        assertEquals(PrideFlag.BI, PrideFlag.parse("bi"))
        assertEquals(PrideFlag.RAINBOW, PrideFlag.parse("x"))
        assertEquals("pride", KeyboardTheme.PRIDE.id)
        assertEquals("rainbowburst", KeyEffect.RAINBOWBURST.id)
        assertTrue(KeyEffect.RAINBOWBURST.needsBoundaryWord)
        assertFalse("mỗi phím đều bắn vòng cung", KeyEffect.RAINBOWBURST.isQueued)
        assertTrue("rainbowburst" in ThemeExtraIds.EFFECTS)
        assertEquals("pride", ThemeVariants.PRIDE)
        assertTrue("pride" in ThemeVariants.KNOWN)
        assertEquals("Pride", L10nTable.EN["Tự hào"])
        assertEquals("Transgender", L10nTable.EN["Chuyển giới"])
        assertEquals("Non-binary", L10nTable.EN["Phi nhị nguyên"])
    }

    @Test fun flagStripesAndPalettesContrast() {
        assertEquals(listOf(6, 5, 3, 3, 5, 4), PrideFlag.entries.map { it.stripes.size })
        assertEquals(0xE40303, PrideFlag.RAINBOW.stripes.first())
        assertEquals(0xFFFFFF, PrideFlag.TRANS.stripes[2])
        for (f in PrideFlag.entries) {
            assertTrue(f.stripes.size <= 6)
            val p = ThemeSpec.palette(f.slots, true)
            assertTrue(f.id, p.isDark)
            assertTrue(f.id, p.auroraBorder)
            assertEquals(f.id, "hearts", p.decoration?.motif)
            assertTrue(f.id, ThemeColor.contrast(p.ink, p.keyFill) >= 4.5)
            assertTrue(f.id, ThemeColor.contrast(p.fnInk, p.fnFill) >= 4.5)
            assertTrue(f.id, ThemeColor.contrast(p.actionInk, p.action) >= 4.5)
            assertTrue(f.id, ThemeColor.contrast(p.ink, p.bg) >= 4.5)
        }
    }

    @Test fun rainbowBurstMath() {
        assertEquals(44.4, RainbowBurst.radius(0), 1e-9)
        assertEquals(28.4, RainbowBurst.radius(5), 1e-9)
        assertEquals(0.45, RainbowBurst.alpha(0.04), 1e-9)
        assertEquals(0.45, RainbowBurst.alpha(0.44), 1e-9)
        assertEquals(0.0, RainbowBurst.alpha(0.8), 0.0)
        assertEquals(0.15, RainbowBurst.scale(0.0), 1e-9)
        assertEquals(0.7875, RainbowBurst.scale(0.4), 1e-9)
        assertEquals(1.0, RainbowBurst.scale(0.8), 1e-9)
        var prev = 0.0; var peaked = false
        for (k in 0..80) {
            val a = RainbowBurst.alpha(k / 100.0)
            if (a < prev) peaked = true else if (peaked) assertTrue(a <= prev)
            prev = a
        }
    }

    @Test fun flagWaveMath() {
        assertEquals("cán cờ đứng yên", 0.0, PrideFlagWave.offset(0.0, 1.3), 1e-12)
        assertEquals(0.875, PrideFlagWave.offset(14.0, 0.0), 1e-9)
        val pts = DoubleArray(2 * PrideFlagWave.STRIPE_POINTS)
        val n = PrideFlagWave.stripe(0, 6, 0.0, pts)
        assertEquals(2 * (PrideFlagWave.COLUMNS + 1), n)
        assertEquals(-28.0, pts[0], 1e-9); assertEquals(-46.0, pts[1], 1e-9)
        assertEquals(-28.0, pts[2 * (n - 1)], 1e-9); assertEquals(-40.0, pts[2 * (n - 1) + 1], 1e-9)
        assertEquals(0.5, PrideFlagWave.alpha(0.075), 1e-9)
        assertEquals(1.0, PrideFlagWave.alpha(0.5), 0.0)
        assertEquals(0.5, PrideFlagWave.alpha(1.025), 1e-9)
        assertEquals(-4.0, PrideFlagWave.riseY(0.6), 1e-9)
        assertEquals(2 * Math.PI, PrideFlagWave.phase(0.6), 1e-9)
        assertEquals(-42.0, PrideFlagWave.heart(0).dx, 1e-9); assertEquals(-40.0, PrideFlagWave.heart(0).dy, 1e-9)
        assertEquals(42.0, PrideFlagWave.heart(7).dx, 1e-9); assertEquals(-50.0, PrideFlagWave.heart(7).dy, 1e-9)
        assertEquals(0.21, PrideFlagWave.heartDelay(7), 1e-9)
        for (f in 0..PrideFlagWave.FRAMES) {
            val ph = PrideFlagWave.phase(PrideFlagWave.LIFE * f / PrideFlagWave.FRAMES)
            for (i in 0 until 6) {
                val m = PrideFlagWave.stripe(i, 6, ph, pts)
                for (k in 0 until m) {
                    assertTrue(abs(pts[2 * k]) <= PrideFlagWave.WIDTH / 2 + 1e-9)
                    assertTrue(pts[2 * k + 1] >= -PrideFlagWave.GAP - PrideFlagWave.HEIGHT - PrideFlagWave.AMPLITUDE - 1e-9)
                    assertTrue(pts[2 * k + 1] <= -PrideFlagWave.GAP + PrideFlagWave.AMPLITUDE + 1e-9)
                }
            }
        }
    }

    @Test fun keywords() {
        val yes = listOf(Triple("love", "is", "love"), Triple("hào", "tự", null), Triple("Pride!", null, null),
            Triple("yêu", "là", "yêu"), Triple("HÀO", "Tự", "rất"), Triple("pride", "my", "is"))
        val no = listOf(Triple("love", "is", "this"), Triple("hao", "tu", null), Triple("yêu", "là", "em"),
            Triple("hào", null, null), Triple("love", null, null), Triple("yêu", null, null), Triple("", null, null),
            Triple("prides", null, null))
        for ((w, p, p2) in yes) assertTrue("$p2 $p $w", PrideKeywords.matches(w, p, p2))
        for ((w, p, p2) in no) assertFalse("$p2 $p $w", PrideKeywords.matches(w, p, p2))
    }

    @Test fun prideTheme() {
        val spec = KeyboardTheme.PRIDE.spec!!
        assertTrue(KeyboardTheme.PRIDE.isPlus)
        assertTrue(KeyboardTheme.PRIDE.isInteractive)
        assertEquals("Tự hào", spec.nameVi); assertEquals("Pride", spec.nameEn)
        assertEquals("pride", spec.variant)
        assertEquals("rainbowburst", spec.effect); assertEquals("pop", spec.sound); assertEquals("rainbow", spec.swipe)
        assertEquals("bảng dự phòng = Cầu vồng", PrideFlag.RAINBOW.slots, spec.light)
        assertEquals(listOf("zodiac", "pride"), ThemePicker.INTERACTIVE_ORDER.let { o -> val i = o.indexOf("zodiac"); o.subList(i, minOf(i + 2, o.size)) })
    }

    @Test fun variantResolvesFromSettings() {
        val prefs = mapOf<String, Any>(Keys.KEYBOARD_THEME to "pride", PrideFlag.KEY to "trans")
        val s = ThemeSettings.load { prefs[it] }
        assertEquals(PrideFlag.TRANS, s.variantChoice.pride)
        val p = s.basePaletteAt(true, null)!!
        assertEquals(PrideFlag.TRANS.stripes.toList(), p.auroraColors)
        assertEquals(ThemeSpec.palette(PrideFlag.TRANS.slots, true).action, p.action)
        assertNull(p.cornerGlyph)
        assertNull("bảng tĩnh = dải aurora mặc định", KeyboardTheme.PRIDE.palette(true)!!.auroraColors)
        assertEquals(listOf(0.0, 0.5, 1.0), AuroraFx.stops(listOf(1, 2, 3)).second.toList())
        val s2 = s.copy(variantChoice = s.variantChoice.copy(pride = PrideFlag.PAN))
        val m = s2.toMap()
        assertEquals("pan", m[PrideFlag.KEY])
        assertEquals(s2, ThemeSettings.load { m[it] })
        assertEquals(PrideFlag.PAN, s2.resetToDefaults().variantChoice.pride)
        assertEquals(SettingKind.Choice("rainbow", PrideFlag.IDS), BackupSettings.byKey[PrideFlag.KEY]!!.kind)
    }
}
