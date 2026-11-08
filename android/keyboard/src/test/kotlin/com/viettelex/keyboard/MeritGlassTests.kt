package com.viettelex.keyboard

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs

/**
 * Theme "Gõ mõ" (Công đức, Mõ gỗ) + "Kính màu" (Nắng qua kính, Chuông nhỏ, "keyShape":"glass"). Số tham chiếu CHUNG iOS
 * (iOS/KeyboardTests/MeritGlassTests.swift).
 */
class MeritGlassTests {
    @Test fun newIdsAppendedAndShared() {
        assertEquals(listOf("merit", "sunlight"), KeyEffect.entries.map { it.id }.takeLast(2))
        assertEquals(listOf("mo", "bell"), KeySoundStyle.entries.map { it.id }.takeLast(2))
        assertTrue("mo" in KeySoundStyle.PRESET_IDS && "bell" in KeySoundStyle.PRESET_IDS)
        assertEquals(KeyboardTheme.MO, KeyboardTheme.entries.first { it.id == "mo" })
        assertEquals(KeyboardTheme.STAINED_GLASS, KeyboardTheme.entries.first { it.id == "stainedGlass" })
        assertTrue(KeyEffect.MERIT.isPlus && KeyEffect.SUNLIGHT.isPlus)
        assertFalse(KeyEffect.MERIT.isQueued || KeyEffect.SUNLIGHT.isQueued)
        assertTrue("glass" in ThemeExtraIds.KEY_SHAPES)
        for (s in listOf("Gõ mõ", "Kính màu", "Mõ gỗ", "Chuông nhỏ", "Công đức", "Nắng qua kính", "+1 công đức", "Công đức hôm nay"))
            assertTrue(s, L10nTable.EN.containsKey(s))
        assertEquals("+1 merit", L10nTable.EN["+1 công đức"])
    }

    @Test fun themesWired() {
        val mo = KeyboardTheme.MO.spec!!; val sg = KeyboardTheme.STAINED_GLASS.spec!!
        assertEquals("mo", mo.sound); assertEquals("merit", mo.effect)
        assertEquals("bell", sg.sound); assertEquals("sunlight", sg.effect); assertEquals("glass", sg.keyShape)
        assertTrue(KeyboardTheme.MO.isPlus && KeyboardTheme.STAINED_GLASS.isPlus)
        assertEquals(listOf("mo", "stainedGlass"), ThemePicker.INTERACTIVE_ORDER.takeLast(2))
    }

    @Test fun moAndBellQuietAndShared() {
        for (k in KeySoundSynth.Kind.entries) {
            val wood = KeySoundSynth.samples(KeySoundStyle.WOOD, k)
            for (st in listOf(KeySoundStyle.MO, KeySoundStyle.BELL)) {
                val a = KeySoundSynth.samples(st, k)
                assertTrue("$st $k", KeySoundSynth.rms(a) < KeySoundSynth.rms(wood))
                assertTrue("$st $k", a.maxOf { abs(it) } < wood.maxOf { abs(it) })
            }
            assertTrue(KeySoundSynth.samples(KeySoundStyle.MO, k).size.toDouble() / KeySoundSynth.SAMPLE_RATE < 0.13)
            assertTrue(KeySoundSynth.samples(KeySoundStyle.BELL, k).size.toDouble() / KeySoundSynth.SAMPLE_RATE < 0.37)
        }
        assertEquals(0x6D6F6D6F xor 0x85EBCA6B.toInt(), KeySoundSynth.seed(KeySoundStyle.MO, KeySoundSynth.Kind.LETTER))
        assertEquals(0x62656C6C xor 0x85EBCA6B.toInt(), KeySoundSynth.seed(KeySoundStyle.BELL, KeySoundSynth.Kind.LETTER))
        val mo = listOf(311.0306, 315.8752, 375.1635); val bell = listOf(728.3445, 722.3437, 830.7632)
        for ((i, k) in KeySoundSynth.Kind.entries.withIndex()) {
            assertEquals("mo $k", mo[i], KeySoundSynth.samples(KeySoundStyle.MO, k).sumOf { abs(it).toDouble() }, 0.01)
            assertEquals("bell $k", bell[i], KeySoundSynth.samples(KeySoundStyle.BELL, k).sumOf { abs(it).toDouble() }, 0.01)
        }
        assertEquals("Wooden fish", L10nTable.EN["Mõ gỗ"]); assertEquals("Small bell", L10nTable.EN["Chuông nhỏ"])
    }

    @Test fun meritCurves() {
        assertEquals(0.0, MeritFx.alpha(-0.01), 0.0)
        assertEquals(0.5, MeritFx.alpha(0.06), 1e-12)
        assertEquals(1.0, MeritFx.alpha(0.3), 0.0)
        assertEquals(0.5, MeritFx.alpha(0.7), 1e-12)
        assertEquals(0.0, MeritFx.alpha(0.9), 0.0)
        assertEquals(33.0, MeritFx.lift(0.45), 1e-12)
        assertEquals(44.0, MeritFx.lift(2.0), 0.0)
        assertEquals(listOf(-6.0, 0.0, 6.0, 6.0), listOf(0, 1, 2, -1).map { MeritFx.drift(it) })
        assertEquals(5, MeritFx.CAP)
    }

    @Test fun meritOriginInsideBounds() {
        assertArrayEquals(doubleArrayOf(63.0, 54.0), MeritFx.origin(10.0, 5.0, 0.0, 0.0, 390.0, 260.0), 1e-12)
        assertArrayEquals(doubleArrayOf(200.0, 150.0), MeritFx.origin(200.0, 150.0, 0.0, 0.0, 390.0, 260.0), 1e-12)
        assertArrayEquals(doubleArrayOf(327.0, 250.0), MeritFx.origin(389.0, 250.0, 0.0, 0.0, 390.0, 260.0), 1e-12)
        assertArrayEquals(doubleArrayOf(63.0, 94.0), MeritFx.origin(10.0, 5.0, 0.0, 40.0, 390.0, 260.0), 1e-12)
    }

    @Test fun meritGroupingAndText() {
        assertEquals("1.234", MeritFx.grouped(1234, "."))
        assertEquals("1,234,567", MeritFx.grouped(1_234_567, ","))
        assertEquals("999", MeritFx.grouped(999, "."))
        assertEquals("0", MeritFx.grouped(0, "."))
        assertEquals("0", MeritFx.grouped(-5, "."))
        assertTrue(MeritFx.counterText(1234, english = false).endsWith(": 1.234"))
        assertTrue(MeritFx.counterText(1234, english = true).endsWith(": 1,234"))
    }

    @Test fun meritDayResetsAtLocalMidnight() {
        assertEquals(19_999, MeritCounter.dayIndex(86_400.0 * 20_000 - 1, 0))
        assertEquals(20_000, MeritCounter.dayIndex(86_400.0 * 20_000 - 1, 3600))
        val vn = 7 * 3600
        val midnight = 86_400.0 * 20_000 - vn
        assertEquals(19_999, MeritCounter.dayIndex(midnight - 1, vn))
        assertEquals(20_000, MeritCounter.dayIndex(midnight, vn))
        assertEquals(-1, MeritCounter.dayIndex(-1.0, 0))
        val c = MeritCounter()
        val d0 = MeritCounter.dayIndex(midnight - 10, vn)
        for (i in 0 until 3) c.press(d0, i.toDouble())
        assertEquals(3, c.today(d0))
        val d1 = MeritCounter.dayIndex(midnight + 1, vn)
        c.press(d1, 3.0)
        assertEquals(1, c.today(d1))
        assertEquals(0, c.today(d0))
    }

    @Test fun meritPersistThrottled() {
        val c = MeritCounter(100, 7)
        assertTrue(c.press(100, 0.0)); assertEquals(8, c.count)
        assertFalse(c.press(100, 1.0)); assertFalse(c.press(100, 4.9))
        assertTrue(c.press(100, 5.0)); assertFalse(c.dirty)
        assertFalse(c.press(100, 6.0))
        assertTrue(c.takeDirty()); assertFalse(c.takeDirty())
        val d = MeritCounter()
        var writes = 0
        for (i in 0 until 100) if (d.press(1, i / 10.0)) writes++
        assertEquals(2, writes); assertEquals(100, d.count)
        assertEquals(0, MeritCounter(1, -3).count)
    }

    @Test fun sunlightGeometryAndTiming() {
        assertEquals(0.0, SunlightFx.envelope(-0.01), 0.0)
        assertEquals(0.5, SunlightFx.envelope(0.04), 1e-12)
        assertEquals(1.0, SunlightFx.envelope(0.08), 1e-12)
        assertEquals(0.25, SunlightFx.envelope(0.39), 1e-12)
        assertEquals(0.0, SunlightFx.envelope(0.7), 0.0)
        val p = SunlightFx.panes(100.0, 200.0, 30.0, 40.0)
        assertEquals(SunlightFx.Pane(100.0, 200.0, 30.0, 40.0, 0.38), p[0])
        assertEquals(66.4, p[1].x, 1e-9); assertEquals(133.6, p[2].x, 1e-9)
        assertEquals(150.0, p[3].y, 1e-9); assertEquals(250.0, p[4].y, 1e-9)
        assertTrue(p.drop(1).all { it.level == SunlightFx.NEIGHBOR })
        assertArrayEquals(doubleArrayOf(23.91487093052358, 0.0, 47.67487093052358, 0.0, 106.9, 180.0, 96.1, 180.0),
            SunlightFx.beam(1, 100.0, 180.0, 30.0, 0.0), 1e-9)
        for (i in 0 until SunlightFx.BEAMS) {
            val q = SunlightFx.beam(i, 100.0, 180.0, 30.0, 40.0)
            assertEquals(40.0, q[1], 0.0); assertEquals(40.0, q[3], 0.0); assertEquals(180.0, q[5], 0.0); assertEquals(180.0, q[7], 0.0)
            assertTrue(q[0] < q[6])
        }
    }

    @Test fun candleFlickerRateLimited() {
        val c = CandleFlicker()
        assertNull(c.press(0.0, 1))
        assertEquals(0.34, c.press(0.0, 2)!!, 0.0)
        assertNull(c.press(0.2, 3))
        assertEquals(0.24, c.press(0.34, 2)!!, 0.0)
        assertEquals(0.29, c.value(0.49), 1e-12)
        assertEquals(0.2, CandleFlicker.envelope(1.25, 0.0, 0.4), 1e-12)
        assertEquals(0.0, CandleFlicker.envelope(2.0, 0.0, 0.4), 0.0)
        val f = CandleFlicker()
        val times = ArrayList<Double>()
        for (i in 0 until 60) { val t = i * 0.05; if (f.press(t, 3) != null) times.add(t) }
        assertTrue(times.size > 3)
        for (t in times) assertTrue("≤ 3 lần / giây", times.count { it >= t && it < t + 1 } <= 3)
        assertEquals(times.size, f.changes)
    }

    @Test fun glassPaneAssignment() {
        assertEquals(listOf(0, 1, 2, 3, 0, 0, 1, 0, 1, 0, 1),
            listOf("q", "w", "a", "s", "d", "z", "x", "Q", "1", "", "đ").map { GlassKeys.paneIndex(it) })
        val rows = GlassKeys.ROWS.map { r -> r.map { it.toString() } }
        for ((r, row) in rows.withIndex()) for ((c, ch) in row.withIndex()) {
            if (c + 1 < row.size) assertNotEquals(ch, GlassKeys.paneIndex(ch), GlassKeys.paneIndex(row[c + 1]))
            if (r + 1 < rows.size && c < rows[r + 1].size) assertNotEquals(ch, GlassKeys.paneIndex(ch), GlassKeys.paneIndex(rows[r + 1][c]))
        }
        assertEquals(0x808080, GlassKeys.mix(0x000000, 0xFFFFFF, 0.5))
        assertEquals(0xA74D5C, GlassKeys.pressed(0x8E1B2E))
        assertEquals(2.52, GlassKeys.leadWidth(42.0), 1e-12)
        assertEquals(2.0, GlassKeys.leadWidth(20.0), 0.0)
        assertEquals(0x8E1B2E, GlassKeys.paneColor("q"))
    }

    @Test fun glassContrast() {
        val p = KeyboardTheme.STAINED_GLASS.palette(false)!!
        for (c in GlassKeys.PANES) {
            assertTrue(Integer.toHexString(c), ThemeColor.contrast(p.ink, GlassKeys.top(c) or (0xFF shl 24)) >= 4.5)
            assertTrue(ThemeColor.contrast(p.ink, c or (0xFF shl 24)) >= 4.5)
        }
    }
}
