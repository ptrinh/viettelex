package com.viettelex.keyboard

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import kotlin.math.abs

/**
 * Theme "Cung hoàng đạo" (11/2026): cung + nguyên tố + bảng màu ([ZodiacSign], [ZodiacElement]), ngày sinh → cung, bảng
 * chòm sao, luật thắp sao ([ConstellationTrace] / [ConstellationFx]), âm "twinkle", "variant":"zodiac" giải lúc dựng, sao
 * lưu `zodiacSign`. Song sinh iOS ZodiacThemeTests — CÙNG số tham chiếu.
 */
class ZodiacThemeTests {
    private var savedPaywall = false
    @Before fun setUp() { savedPaywall = PlusGate.paywallEnabled; PlusGate.paywallEnabled = false }
    @After fun tearDown() { PlusGate.paywallEnabled = savedPaywall; PlusGate.install({ null }, debugBuild = false) }

    @Test fun ids() {
        assertEquals(listOf("aries", "taurus", "gemini", "cancer", "leo", "virgo", "libra", "scorpio", "sagittarius", "capricorn",
            "aquarius", "pisces"), ZodiacSign.entries.map { it.id })
        assertEquals("zodiacSign", ZodiacSign.KEY)
        assertEquals(ZodiacSign.LEO, ZodiacSign.parse("leo"))
        assertEquals(ZodiacSign.ARIES, ZodiacSign.parse("ophiuchus"))
        assertEquals(ZodiacSign.ARIES, ZodiacSign.parse(null))
        assertEquals("zodiac", KeyboardTheme.ZODIAC.id)
        assertEquals("constellation", KeyEffect.CONSTELLATION.id)
        assertEquals("twinkle", KeySoundStyle.TWINKLE.id)
        assertTrue("constellation" in ThemeExtraIds.EFFECTS)
        assertTrue("twinkle" in ThemeExtraIds.SOUNDS)
        assertEquals("zodiac", ThemeVariants.ZODIAC)
        assertTrue("zodiac" in ThemeVariants.KNOWN)
        assertEquals("Zodiac", L10nTable.EN["Cung hoàng đạo"])
        assertEquals("Constellation", L10nTable.EN["Chòm sao"])
        assertEquals("Star chime", L10nTable.EN["Chuông sao"])
        assertEquals("Aries", L10nTable.EN["Bạch Dương"]); assertEquals("Pisces", L10nTable.EN["Song Ngư"])
        assertEquals("Water", L10nTable.EN["Hệ Nước"]); assertEquals("From your birthday", L10nTable.EN["Tính từ ngày sinh"])
    }

    @Test fun elementMapping() {
        val want = mapOf(
            ZodiacSign.ARIES to ZodiacElement.FIRE, ZodiacSign.LEO to ZodiacElement.FIRE, ZodiacSign.SAGITTARIUS to ZodiacElement.FIRE,
            ZodiacSign.TAURUS to ZodiacElement.EARTH, ZodiacSign.VIRGO to ZodiacElement.EARTH, ZodiacSign.CAPRICORN to ZodiacElement.EARTH,
            ZodiacSign.GEMINI to ZodiacElement.AIR, ZodiacSign.LIBRA to ZodiacElement.AIR, ZodiacSign.AQUARIUS to ZodiacElement.AIR,
            ZodiacSign.CANCER to ZodiacElement.WATER, ZodiacSign.SCORPIO to ZodiacElement.WATER, ZodiacSign.PISCES to ZodiacElement.WATER)
        for (z in ZodiacSign.entries) assertEquals(z.id, want[z], z.element)
        assertEquals("♈︎", ZodiacSign.ARIES.glyph)
        assertEquals("♓︎", ZodiacSign.PISCES.glyph)
        assertEquals(0xFFFF7A2F.toInt(), ZodiacElement.FIRE.slots.accent)
        assertEquals(0xFF8DBF5A.toInt(), ZodiacElement.EARTH.slots.accent)
        assertEquals(0xFF8EC5FF.toInt(), ZodiacElement.AIR.slots.accent)
        assertEquals(0xFF2BC4C4.toInt(), ZodiacElement.WATER.slots.accent)
    }

    @Test fun elementPalettesContrast() {
        for (e in ZodiacElement.entries) {
            val p = ThemeSpec.palette(e.slots, true)
            assertTrue(e.id, p.isDark)
            assertEquals(e.id, "starfield", p.decoration?.motif)
            assertTrue(e.id, ThemeColor.contrast(p.ink, p.keyFill) >= 4.5)
            assertTrue(e.id, ThemeColor.contrast(p.fnInk, p.fnFill) >= 4.5)
            assertTrue(e.id, ThemeColor.contrast(p.actionInk, p.action) >= 4.5)
            assertTrue(e.id, ThemeColor.contrast(p.ink, p.bg) >= 4.5)
        }
    }

    @Test fun signFromDate() {
        val cases = listOf(
            Triple(1, 1, ZodiacSign.CAPRICORN), Triple(19, 1, ZodiacSign.CAPRICORN), Triple(20, 1, ZodiacSign.AQUARIUS),
            Triple(18, 2, ZodiacSign.AQUARIUS), Triple(19, 2, ZodiacSign.PISCES), Triple(29, 2, ZodiacSign.PISCES),
            Triple(20, 3, ZodiacSign.PISCES), Triple(21, 3, ZodiacSign.ARIES), Triple(19, 4, ZodiacSign.ARIES),
            Triple(20, 4, ZodiacSign.TAURUS), Triple(20, 5, ZodiacSign.TAURUS), Triple(21, 5, ZodiacSign.GEMINI),
            Triple(20, 6, ZodiacSign.GEMINI), Triple(21, 6, ZodiacSign.CANCER), Triple(22, 7, ZodiacSign.CANCER),
            Triple(23, 7, ZodiacSign.LEO), Triple(22, 8, ZodiacSign.LEO), Triple(23, 8, ZodiacSign.VIRGO),
            Triple(22, 9, ZodiacSign.VIRGO), Triple(23, 9, ZodiacSign.LIBRA), Triple(22, 10, ZodiacSign.LIBRA),
            Triple(23, 10, ZodiacSign.SCORPIO), Triple(21, 11, ZodiacSign.SCORPIO), Triple(22, 11, ZodiacSign.SAGITTARIUS),
            Triple(21, 12, ZodiacSign.SAGITTARIUS), Triple(22, 12, ZodiacSign.CAPRICORN), Triple(31, 12, ZodiacSign.CAPRICORN),
            Triple(30, 2, null), Triple(31, 4, null), Triple(0, 5, null), Triple(1, 13, null), Triple(1, 0, null), Triple(32, 1, null))
        for ((d, m, want) in cases) assertEquals("$d/$m", want, ZodiacSign.from(d, m))
        var prev: ZodiacSign? = null; var changes = 0
        for ((m, n) in listOf(31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31).withIndex()) {
            for (d in 1..n) {
                val z = ZodiacSign.from(d, m + 1)
                assertNotNull(z)
                if (prev != null && prev != z) changes++
                prev = z
            }
        }
        assertEquals(12, changes)
    }

    @Test fun constellationTable() {
        assertEquals(listOf(4, 6, 6, 5, 8, 7, 4, 9, 8, 6, 7, 8), ZodiacSign.entries.map { it.constellation.stars.size })
        assertEquals(listOf(3, 5, 6, 4, 8, 7, 4, 8, 10, 6, 6, 8), ZodiacSign.entries.map { it.constellation.edges.size })
        assertEquals(ZodiacStar(0.30, 0.70), ZodiacSign.LEO.constellation.stars[4])
        assertEquals(ZodiacStar(0.92, 0.60), ZodiacSign.SCORPIO.constellation.stars[8])
        for (z in ZodiacSign.entries) {
            val c = z.constellation
            for (s in c.stars) assertTrue(z.id, s.x in 0.0..1.0 && s.y in 0.0..1.0)
            for (e in c.edges) assertTrue(z.id, e.a in c.stars.indices && e.b in c.stars.indices && e.a != e.b)
            for (k in 1 until c.stars.size) assertFalse("${z.id} sao $k", c.edgesOwnedBy(k).isEmpty())
            assertTrue(c.edgesOwnedBy(0).isEmpty())
            assertTrue(c.stars.size <= 9)
        }
        assertEquals(9, ZodiacSign.MAX_STARS)
    }

    @Test fun traceAndTiming() {
        val t = ConstellationTrace(4)
        val steps = listOf(0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 3.0).map { t.press(it) }
        assertEquals(listOf(
            ConstellationTrace.Step(0, true, false), ConstellationTrace.Step(1, false, false),
            ConstellationTrace.Step(2, false, false), ConstellationTrace.Step(3, false, true),
            ConstellationTrace.Step(0, true, false), ConstellationTrace.Step(1, false, false),
            ConstellationTrace.Step(0, true, false)), steps)
        assertEquals(3, t.cycle)
        assertEquals(0.5, ConstellationFx.starAlpha(0.09), 1e-9)
        assertEquals(1.0, ConstellationFx.starAlpha(1.0), 0.0)
        assertEquals(1.0, ConstellationFx.cycleAlpha(1.0, false), 0.0)
        assertEquals(0.5, ConstellationFx.cycleAlpha(2.65, false), 1e-9)
        assertEquals(0.0, ConstellationFx.cycleAlpha(2.9, false), 0.0)
        assertEquals(0.5, ConstellationFx.cycleAlpha(0.7, true), 1e-9)
        assertEquals(0.425, ConstellationFx.glowAlpha(0.075), 1e-9)
        assertEquals(0.425, ConstellationFx.glowAlpha(0.575), 1e-9)
        assertEquals(0.0, ConstellationFx.glowAlpha(1.0), 0.0)
        assertEquals(2.9, ConstellationFx.lifetime(false), 1e-9)
        assertEquals(1.0, ConstellationFx.lifetime(true), 1e-9)
    }

    @Test fun boxInsideBounds() {
        val b = ConstellationFx.box(67.0, 121.0, 0.0, -180.0, 390.0, 470.0)
        assertEquals(6.0, b.x, 1e-9); assertEquals(15.7, b.y, 1e-9)
        assertEquals(234.0, b.w, 1e-9); assertEquals(140.4, b.h, 1e-9)
        for (q in listOf(doubleArrayOf(0.0, 0.0, 390.0, 260.0), doubleArrayOf(390.0, 260.0, 390.0, 260.0),
            doubleArrayOf(55.0, 70.0, 110.0, 84.0), doubleArrayOf(500.0, -40.0, 320.0, 200.0))) {
            val r = ConstellationFx.box(q[0], q[1], 0.0, 0.0, q[2], q[3])
            assertTrue(r.x >= 0 && r.y >= 0 && r.x + r.w <= q[2] && r.y + r.h <= q[3])
            assertEquals(r.w * ConstellationFx.ASPECT, r.h, 1e-9)
        }
    }

    @Test fun zodiacTheme() {
        val spec = KeyboardTheme.ZODIAC.spec!!
        assertTrue(KeyboardTheme.ZODIAC.isPlus)
        assertTrue(KeyboardTheme.ZODIAC.isInteractive)
        assertEquals("Cung hoàng đạo", spec.nameVi); assertEquals("Zodiac", spec.nameEn)
        assertEquals("zodiac", spec.variant)
        assertEquals("constellation", spec.effect); assertEquals("twinkle", spec.sound); assertEquals("stardust", spec.swipe)
        assertEquals("bảng dự phòng = Lửa", ZodiacElement.FIRE.slots, spec.light)
        assertEquals(listOf("zodiac", "pride"), ThemePicker.INTERACTIVE_ORDER.let { o -> val i = o.indexOf("zodiac"); o.subList(i, minOf(i + 2, o.size)) })
    }

    @Test fun variantResolvesFromSettings() {
        val prefs = mapOf<String, Any>(Keys.KEYBOARD_THEME to "zodiac", ZodiacSign.KEY to "scorpio")
        val s = ThemeSettings.load { prefs[it] }
        assertEquals(ZodiacSign.SCORPIO, s.variantChoice.zodiac)
        val p = s.basePaletteAt(false, null)!!
        assertEquals(ThemeSpec.palette(ZodiacElement.WATER.slots, true).action, p.action)
        assertEquals(ZodiacSign.SCORPIO.glyph, p.cornerGlyph)
        assertEquals(ZodiacSign.SCORPIO.glyph, s.cardPalette(KeyboardTheme.ZODIAC, true)!!.cornerGlyph)
        assertNull(s.cardPalette(KeyboardTheme.SEA, false)!!.cornerGlyph)
        assertNull("bảng tĩnh không có ký hiệu", KeyboardTheme.ZODIAC.palette(false)!!.cornerGlyph)
        // Lưu: chỉ id cung; khứ hồi; khôi phục gốc giữ lựa chọn.
        val s2 = s.copy(variantChoice = s.variantChoice.copy(zodiac = ZodiacSign.GEMINI))
        val m = s2.toMap()
        assertEquals("gemini", m[ZodiacSign.KEY])
        assertEquals(s2, ThemeSettings.load { m[it] })
        assertEquals(ZodiacSign.GEMINI, s2.resetToDefaults().variantChoice.zodiac)
        assertEquals("zodiac", s.exportSpec(KeyboardTheme.ZODIAC, p, p).variant)
    }

    @Test fun backupKey() {
        val k = BackupSettings.byKey[ZodiacSign.KEY]!!.kind
        assertEquals(SettingKind.Choice("aries", ZodiacSign.IDS), k)
    }

    /** "Chuông sao": nhỏ hơn "Gõ gỗ", ≤ 60 ms, seed cố định; checksum chung iOS (ZodiacThemeTests.twinkleGolden). */
    @Test fun twinkleSound() {
        val golden = listOf(186.0985, 187.2213, 212.3972)
        for ((i, k) in KeySoundSynth.Kind.entries.withIndex()) {
            val wood = KeySoundSynth.samples(KeySoundStyle.WOOD, k); val a = KeySoundSynth.samples(KeySoundStyle.TWINKLE, k)
            assertTrue("$k", KeySoundSynth.rms(a) < KeySoundSynth.rms(wood))
            assertTrue("$k", a.maxOf { abs(it) } < wood.maxOf { abs(it) })
            assertTrue("$k", a.size.toDouble() / KeySoundSynth.SAMPLE_RATE < 0.066)
            assertEquals("$k", golden[i], a.sumOf { abs(it).toDouble() }, 0.01)
        }
        assertEquals(0x74776E6B xor 0x85EBCA6B.toInt(), KeySoundSynth.seed(KeySoundStyle.TWINKLE, KeySoundSynth.Kind.LETTER))
        assertTrue(KeySoundStyle.TWINKLE in KeySoundStyle.PRESETS)
    }
}
