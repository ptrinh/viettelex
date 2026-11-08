package com.viettelex.keyboard

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs

/**
 * Theme "Gym" (11/2026): hiệu ứng Rep ([RepsFx]), âm "Tạ sắt", motif "treadplate". Số mốc CHUNG iOS GymThemeTests.swift.
 */
class GymThemeTests {

    @Test fun idsAppendedAndShared() {
        assertEquals(KeyboardTheme.NIGHTCLUB.ordinal + 1, KeyboardTheme.GYM.ordinal)
        assertEquals("gym", KeyboardTheme.GYM.id)
        assertEquals(KeyEffect.DANCEFLOOR.ordinal + 1, KeyEffect.REPS.ordinal)
        assertEquals("reps", KeyEffect.REPS.id)
        assertTrue(KeyEffect.REPS.isPlus)
        assertFalse("mỗi phím đều lấp thanh rep", KeyEffect.REPS.isQueued)
        assertTrue(KeyEffect.REPS.needsBoundaryWord)
        assertFalse(KeyEffect.REPS.needsComposeDiff)
        assertEquals(KeySoundStyle.CLUB.ordinal + 1, KeySoundStyle.PLATE.ordinal)
        assertTrue(KeySoundStyle.PLATE in KeySoundStyle.PRESETS)
        assertTrue("plate" in KeySoundStyle.PRESET_IDS)
        assertTrue(ThemeDecoration.TREADPLATE in ThemeDecoration.MOTIFS)
        assertEquals("Reps", L10nTable.EN["Rep"])
        assertEquals("Iron plate", L10nTable.EN["Tạ sắt"])
        assertEquals("Gym", L10nTable.EN["Gym"])
    }

    @Test fun gymTheme() {
        val t = KeyboardTheme.GYM
        val spec = t.spec!!
        assertTrue(t.isPlus)
        assertTrue(t.isInteractive)
        assertEquals("gym", ThemePicker.INTERACTIVE_ORDER.last())
        assertEquals("Gym", spec.nameVi); assertEquals("Gym", spec.nameEn)
        assertEquals("plate", spec.sound); assertEquals("reps", spec.effect); assertEquals("neon", spec.swipe)
        assertNull("dark = same", spec.dark)
        val p = t.palette(false)!!
        assertEquals(p, t.palette(true))
        assertTrue(p.isDark)
        assertEquals(ThemeDecoration.TREADPLATE, p.decoration?.motif)
        assertNotNull("viền vàng chanh neon", p.keyBorder)
        assertTrue(ThemeSpecParser.contrastIssues(spec).isEmpty())
        assertTrue(KeyboardTheme.GYM in ThemePicker.ordered())
    }

    /** Motif "treadplate": 7 gân hình thoi, cùng chiều quay, |y| ≤ 0.45, mốc chung iOS testTreadplateMotif. */
    @Test fun treadplateMotif() {
        val subs = ThemeDecoration.shape(ThemeDecoration.TREADPLATE)
        assertEquals(7, subs.size)
        var area = 0.0
        for (sub in subs) {
            val pts = ArrayList<DoubleArray>()
            pts.add(doubleArrayOf(sub.sx, sub.sy))
            for (g in sub.segs) pts.add(doubleArrayOf(g[0], g[1]))
            assertEquals(4, pts.size)
            var a = 0.0
            for (i in pts.indices) { val p = pts[i]; val q = pts[(i + 1) % pts.size]; a += p[0] * q[1] - q[0] * p[1] }
            assertTrue("chiều quay", a > 0)
            area += a / 2
            for (p in pts) { assertTrue(abs(p[1]) <= 0.45); assertTrue(abs(p[0]) <= 2.75) }
        }
        assertEquals(7 * 0.62 * 0.18 / 2, area, 1e-9)
        assertEquals(-2.180797, subs[0].sx, 1e-6)
        assertEquals(0.219203, subs[0].sy, 1e-6)
        assertEquals("gân xen kẽ ±45°", -0.219203, subs[1].sy, 1e-6)
    }

    /** "Tạ sắt": không to hơn Gõ gỗ, ≤ 60 ms, không chói; seed cố định; checksum chung iOS testPlateSoundSoftAndShared. */
    @Test fun plateSoundSoftAndShared() {
        for (k in KeySoundSynth.Kind.entries) {
            val wood = KeySoundSynth.samples(KeySoundStyle.WOOD, k); val a = KeySoundSynth.samples(KeySoundStyle.PLATE, k)
            assertTrue("$k", KeySoundSynth.rms(a) < KeySoundSynth.rms(wood))
            assertTrue("$k", a.maxOf { abs(it) } < wood.maxOf { abs(it) })
            assertTrue("$k", a.size.toDouble() / KeySoundSynth.SAMPLE_RATE < 0.061)
            assertTrue("$k không chói", KeySoundSynth.spectralCentroid(a) < 2500.0)
        }
        assertEquals(0x706C6174 xor 0x85EBCA6B.toInt(), KeySoundSynth.seed(KeySoundStyle.PLATE, KeySoundSynth.Kind.LETTER))
        val golden = listOf(113.6273, 117.8890, 141.4856)
        for ((i, k) in KeySoundSynth.Kind.entries.withIndex())
            assertEquals("$k", golden[i], KeySoundSynth.samples(KeySoundStyle.PLATE, k).sumOf { abs(it).toDouble() }, 0.01)
    }

    @Test fun counterSetsAndResets() {
        val c = RepsFx.Counter()
        val events = (0 until 10).map { c.press(it * 0.2) }
        assertEquals((1..10).toList(), events.map { it.fill })
        assertEquals("10 phím = một hiệp", listOf(1), events.mapNotNull { it.completedSet })
        for (i in 10 until 25) c.press(i * 0.2)
        assertEquals(2, c.sets); assertEquals(5, c.reps)
        assertFalse(c.isIdle(4.8 + 60))
        assertTrue(c.isIdle(4.8 + 60.01))
        assertEquals(RepsFx.Counter.Event(1, null), c.press(4.8 + 61))
        assertEquals(0, c.sets)
        for (i in 0 until 12) c.press(100.0 + i)
        c.reset()
        assertEquals(0, c.reps); assertEquals(0, c.sets)
        val d = RepsFx.Counter()
        for (i in 0 until 9) d.press(i.toDouble())
        assertEquals("hiệp đầu sau reset vẫn là SET 1", 1, d.press(9.0).completedSet)
    }

    @Test fun curvesShared() {
        assertEquals(0.05, RepsFx.barFill(0, 1, 0.06), 1e-9)
        assertEquals(0.4, RepsFx.barFill(3, 4, 1.0), 1e-9)
        assertEquals("hết hiệp: đầy", 1.0, RepsFx.barFill(9, 10, 0.3), 1e-9)
        assertEquals("rút về", 0.5, RepsFx.barFill(9, 10, 0.12 + 0.45 + 0.1), 1e-9)
        assertEquals(0.0, RepsFx.barFill(9, 10, RepsFx.SET_LIFE), 1e-9)
        assertEquals(1.25, RepsFx.badgeScale(0.12), 1e-9)
        assertEquals(0.5, RepsFx.badgeAlpha(0.06), 1e-9)
        assertEquals(0.0, RepsFx.badgeAlpha(0.9), 0.0)
        assertEquals(1.65, RepsFx.slamScale(0.05), 1e-9)
        assertEquals(1.0, RepsFx.slamAlpha(0.5), 1e-9)
        assertEquals(1.275, RepsFx.ringScale(0.35), 1e-9)
        assertEquals(0.425, RepsFx.ringAlpha(0.35), 1e-9)
        assertEquals(0.0, RepsFx.ringAlpha(0.05), 0.0)
        assertEquals(-28.5, RepsFx.labelDy(0.4), 1e-9)
        assertEquals(0.5, RepsFx.labelAlpha(0.06), 1e-9)
        assertEquals(0.0, RepsFx.labelAlpha(0.8), 0.0)
        assertEquals(listOf(-8.0, 0.0, 8.0, 8.0), listOf(0, 2, 4, -1).map(RepsFx::labelDrift))
        assertEquals(44.0, RepsFx.ringRadius(390.0, 260.0), 1e-9)
        assertEquals(24.375, RepsFx.ringRadius(110.0, 84.0), 1e-9)
        assertEquals(30.0, RepsFx.slamFont(390.0), 1e-9)
        assertEquals(110 / 8.5, RepsFx.slamFont(110.0), 1e-9)
        val o = DoubleArray(2)
        RepsFx.labelOrigin(5.0, 10.0, 2, 0.0, -40.0, 390.0, 300.0, o)
        assertEquals(40.0, o[0], 1e-9); assertEquals(10.0, o[1], 1e-9)
        RepsFx.labelOrigin(200.0, -35.0, 4, 0.0, -40.0, 390.0, 300.0, o)
        assertEquals(208.0, o[0], 1e-9); assertEquals("cả đường bay trong khung", 8.0, o[1], 1e-9)
        assertEquals("SET 3 ✓", RepsFx.badgeText(3))
    }

    @Test fun keywordTable() {
        assertEquals(listOf("gym", "tập", "fit", "no pain no gain", "beast mode", "lên tạ"), RepsFx.KEYWORDS)
        val yes = listOf(Triple("gym", null, null), Triple("Gym!", null, null), Triple("tập", null, null), Triple("FIT", null, null),
            Triple("mode", "beast", null), Triple("tạ", "lên", null), Triple("gain", "no", "pain"))
        for ((w, p, p2) in yes) assertTrue(w, RepsFx.isKeyword(w, p, p2))
        val no = listOf(Triple("tap", null, null), Triple("fitness", null, null), Triple("mode", null, null), Triple("gain", "no", null),
            Triple("tạ", null, null), Triple("gain", "no", "rain"), Triple("", null, null))
        for ((w, p, p2) in no) assertFalse(w, RepsFx.isKeyword(w, p, p2))
    }
}
