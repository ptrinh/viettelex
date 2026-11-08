package com.viettelex.keyboard

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import kotlin.math.abs
import kotlin.math.hypot

/**
 * Theme "Lạc trôi": Đường hầm ([TunnelFx]), Lơ lửng ([FloatFx] / [FloatClock] / [FloatPolicy]), "keyMotion", "bg2", âm "airy".
 * Số tham chiếu GIỐNG HỆT iOS DriftTests.swift.
 */
class DriftTests {
    private val savedPaywall = PlusGate.paywallEnabled
    @Before fun setUp() { PlusGate.paywallEnabled = false }
    @After fun tearDown() { PlusGate.paywallEnabled = savedPaywall }

    @Test fun effectIdsAppendedAndPlus() {
        val ids = KeyEffect.entries.map { it.id }
        assertEquals(listOf("tunnel", "float"), ids.subList(ids.indexOf("tunnel"), ids.indexOf("tunnel") + 2))
        assertEquals(KeyEffect.KALEIDO.ordinal + 1, KeyEffect.TUNNEL.ordinal)
        assertTrue(KeyEffect.TUNNEL.isPlus); assertTrue(KeyEffect.FLOAT.isPlus)
        assertEquals(KeyEffect.TUNNEL, KeyEffect.of("tunnel")); assertEquals(KeyEffect.FLOAT, KeyEffect.of("float"))
        assertEquals("Tunnel", L10nTable.EN["Đường hầm"]); assertEquals("Floating", L10nTable.EN["Lơ lửng"])
        assertTrue("tunnel" in ThemeExtraIds.EFFECTS); assertTrue("float" in ThemeExtraIds.EFFECTS)
    }

    @Test fun tunnelTimingAndCaps() {
        assertEquals(16, TunnelFx.POOL)
        assertEquals(listOf(2, 3, 4, 5), (0..3).map { TunnelFx.rings(it) })
        assertEquals(2, TunnelFx.rings(-1)); assertEquals(5, TunnelFx.rings(9))
        // Gõ dồn ⇒ rơi nhanh hơn; mọi vòng (kể cả trễ) xong trong ~0,9–1,2 s (+ trễ vòng cuối).
        for (l in 1..3) assertTrue(TunnelFx.duration(l) < TunnelFx.duration(l - 1))
        for (l in 0..3) {
            assertTrue(TunnelFx.duration(l) in 0.9..1.2)
            assertTrue(TunnelFx.delay(TunnelFx.rings(l) - 1) + TunnelFx.duration(l) <= 1.6)
        }
        // Trần pool đủ cho ≥ 3 lần gõ dồn mức cao nhất.
        assertTrue(TunnelFx.POOL >= 3 * TunnelFx.rings(3))
        assertEquals(0.24, TunnelFx.delay(2), 1e-12)
    }

    @Test fun tunnelScaleCurveAccelerates() {
        assertEquals(1.0, TunnelFx.scale(0.0), 1e-12)
        assertEquals(0.75, TunnelFx.scale(0.5), 1e-12)
        assertEquals(0.0, TunnelFx.scale(1.0), 1e-12)
        assertEquals(1.0, TunnelFx.scale(-1.0), 1e-12); assertEquals(0.0, TunnelFx.scale(2.0), 1e-12)
        var prev = 0.0
        for (k in 1..10) {   // co nhanh dần: mỗi đoạn bằng nhau co nhiều hơn đoạn trước
            val d = TunnelFx.scale((k - 1) / 10.0) - TunnelFx.scale(k / 10.0)
            assertTrue(d > prev); prev = d
        }
        assertEquals(0.0, TunnelFx.alpha(0.0), 1e-12)
        assertEquals(0.425, TunnelFx.alpha(0.06), 1e-12)
        assertEquals(0.85, TunnelFx.alpha(0.5), 1e-12)
        assertEquals(0.425, TunnelFx.alpha(0.85), 1e-12)
        assertEquals(0.0, TunnelFx.alpha(1.0), 1e-12); assertEquals(0.0, TunnelFx.alpha(-0.1), 1e-12)
        for (k in 0..100) assertTrue(TunnelFx.alpha(k / 100.0) <= TunnelFx.PEAK_ALPHA + 1e-12)
        // Phối cảnh: tâm vòng = V + (C − V)·s — u = 0 ở tâm bàn phím, u = 1 ở điểm tụ.
        val o = DoubleArray(2)
        TunnelFx.center(100.0, 50.0, 20.0, 40.0, 0.5, o); assertEquals(80.0, o[0], 1e-12); assertEquals(47.5, o[1], 1e-12)
        TunnelFx.center(100.0, 50.0, 20.0, 40.0, 1.0, o); assertEquals(20.0, o[0], 1e-12); assertEquals(40.0, o[1], 1e-12)
        TunnelFx.vanish(10.0, 20.0, 30.0, 40.0, 0.0, 0.0, 400.0, 200.0, o); assertEquals(25.0, o[0], 1e-12); assertEquals(40.0, o[1], 1e-12)
        TunnelFx.vanish(10.0, 20.0, 0.0, 0.0, 0.0, -50.0, 400.0, 200.0, o); assertEquals(200.0, o[0], 1e-12); assertEquals(50.0, o[1], 1e-12)
        assertEquals(22.0, TunnelFx.corner(390.0, 260.0), 1e-12)
        assertEquals(12.0, TunnelFx.corner(390.0, 100.0), 1e-12)
    }

    @Test fun floatParamsSharedAndBounded() {
        val p = FloatFx.params(0)
        assertEquals(1.431971, p.ax, 1e-5); assertEquals(2.385931, p.ay, 1e-5); assertEquals(0.018058, p.rot, 1e-5)
        assertEquals(4.061488, p.px, 1e-5); assertEquals(4.426926, p.py, 1e-5); assertEquals(3.779702, p.pr, 1e-5)
        val o = DoubleArray(3)
        FloatFx.bob(0, 1.0, o)
        assertEquals(1.431566, o[0], 1e-5); assertEquals(2.358608, o[1], 1e-5); assertEquals(0.017982, o[2], 1e-5)
        FloatFx.bob(1, 2.5, o)
        assertEquals(-1.489583, o[0], 1e-5); assertEquals(1.382083, o[1], 1e-5); assertEquals(-0.001236, o[2], 1e-5)
        // Mọi phím, mọi lúc: lệch ≤ 4 pt, xoay ≤ 2°, chu kỳ 3–5 s (chậm), phím kề không cùng hướng hết.
        var signs = 0
        for (i in 0 until 60) {
            val q = FloatFx.params(i)
            assertTrue(hypot(q.ax, q.ay) <= FloatFx.MAX_OFFSET + 1e-9)
            assertTrue(abs(q.rot) <= FloatFx.MAX_ROTATION)
            for (per in listOf(q.px, q.py, q.pr)) assertTrue(per in 3.0..5.0)
            if (q.ax > 0) signs++
            for (k in 0..40) {
                FloatFx.bob(i, k * 0.37, o)
                assertTrue(hypot(o[0], o[1]) <= FloatFx.MAX_OFFSET + 1e-9)
                assertTrue(abs(o[2]) <= FloatFx.MAX_ROTATION)
            }
        }
        assertTrue(signs in 15..45)
        FloatFx.bob(7, 0.0, o); assertEquals(0.0, hypot(o[0], o[1]) + abs(o[2]), 1e-12)   // rời hàng từ 0 — không giật
    }

    @Test fun floatClockSettlesAndStops() {
        val c = FloatClock()
        val o = DoubleArray(3); val b = DoubleArray(3)
        assertFalse(c.active)
        assertTrue(c.poke(0.0)); assertFalse("đang trôi: gõ tiếp không gắn lại", c.poke(0.5))
        assertFalse(c.update(2.4)); assertTrue(c.bobbing)
        c.offset(0, 1.0, o); FloatFx.bob(0, 1.0, b); assertEquals(b[0], o[0], 1e-12); assertEquals(b[1], o[1], 1e-12)
        // Nghỉ đủ 2 s sau phím cuối (0,5) ⇒ về chỗ từ 2,5.
        assertTrue(c.update(2.5)); assertFalse(c.bobbing); assertTrue(c.active)
        assertEquals(2.5, c.frozen, 1e-12)
        c.offset(0, 2.5, o); FloatFx.bob(0, 2.5, b); assertEquals(b[0], o[0], 1e-12)
        c.offset(0, 2.9, o); assertEquals(b[0] * 0.5, o[0], 1e-12); assertEquals(b[2] * 0.5, o[2], 1e-12)
        assertEquals(0.5, FloatFx.settleFactor(0.4), 1e-12)
        assertFalse(c.update(3.29)); assertTrue(c.active)
        assertFalse(c.update(3.31)); assertFalse("dừng hẳn ⇒ 0 khung hình", c.active)
        c.offset(0, 3.31, o); assertEquals(0.0, abs(o[0]) + abs(o[1]) + abs(o[2]), 0.0)
        c.offset(5, 9.0, o); assertEquals(0.0, abs(o[0]) + abs(o[1]) + abs(o[2]), 0.0)
    }

    /** Gõ lại lúc đang về chỗ: nhịp mới từ 0 CỘNG phần về chỗ còn lại ⇒ liền mạch (không giật). */
    @Test fun floatClockRepokeDuringSettleIsContinuous() {
        val c = FloatClock()
        val o = DoubleArray(3); val p = DoubleArray(3)
        c.poke(0.0); c.update(2.0)
        c.offset(3, 2.3, p)
        assertTrue(c.poke(2.3))
        c.offset(3, 2.3, o)
        assertEquals(p[0], o[0], 1e-12); assertEquals(p[1], o[1], 1e-12); assertEquals(p[2], o[2], 1e-12)
        c.offset(3, 2.31, o)
        assertTrue(abs(o[0] - p[0]) < 0.2 && abs(o[1] - p[1]) < 0.2)
        c.update(3.0); assertTrue(c.bobbing)
        c.stop(); assertFalse(c.active)
    }

    @Test fun floatPolicy() {
        assertTrue(FloatPolicy.active(KeyEffect.FLOAT, null, plus = true, lowPower = false))
        assertTrue(FloatPolicy.active(KeyEffect.TUNNEL, "float", plus = true, lowPower = false))
        assertTrue(FloatPolicy.active(KeyEffect.NONE, "float", plus = true, lowPower = false))
        assertFalse(FloatPolicy.active(KeyEffect.TUNNEL, null, plus = true, lowPower = false))
        assertFalse(FloatPolicy.active(KeyEffect.FLOAT, "float", plus = false, lowPower = false))
        assertFalse(FloatPolicy.active(KeyEffect.FLOAT, "float", plus = true, lowPower = true))
        assertEquals(setOf("float"), ThemeExtraIds.KEY_MOTIONS)
    }

    /** Theme Lạc trôi — iOS testDriftTheme y hệt. */
    @Test fun driftTheme() {
        val t = KeyboardTheme.DRIFT
        assertEquals(KeyboardTheme.TRIPPY.ordinal + 1, t.ordinal)
        assertTrue(t.isPlus); assertTrue(t.isInteractive)
        val spec = t.spec!!
        assertEquals("Lạc trôi", spec.nameVi); assertEquals("Adrift", spec.nameEn); assertEquals("Adrift", L10nTable.EN["Lạc trôi"])
        assertEquals("tunnel", spec.effect); assertEquals("airy", spec.sound); assertEquals("stardust", spec.swipe)
        assertEquals("float", spec.keyMotion)
        assertEquals("float", ThemeSettings(theme = t).effectiveKeyStyle.keyMotion)
        assertNull(ThemeSettings(theme = KeyboardTheme.NIGHTCLUB).effectiveKeyStyle.keyMotion)
        assertEquals(ThemePicker.INTERACTIVE_ORDER.indexOf("guitar") + 1, ThemePicker.INTERACTIVE_ORDER.indexOf("drift"))
        assertTrue(t in ThemePicker.groups().interactive)
        for (dark in listOf(false, true)) {
            val p = t.palette(dark)!!
            assertEquals(0xFF062B33.toInt(), p.bg); assertEquals(0xFF22104A.toInt(), p.bgBottom)
            // Chữ trắng ≥ 4.5 trên phím trong mờ ở CẢ hai đầu gradient (đỉnh lục lam, đáy tím).
            for (bg in listOf(p.bg, p.bgBottom!!)) {
                val key = ThemeColor.over(p.keyFill, bg)
                assertTrue(ThemeColor.contrast(p.ink, key) >= 4.5)
                assertTrue(ThemeColor.contrast(p.functionInk!!, ThemeColor.over(p.functionFill!!, bg)) >= 4.5)
            }
            assertTrue(ThemeColor.contrast(p.actionInk, p.action) >= 4.5)
        }
        // Chép JSON giữ "keyMotion" + "bg2" (khứ hồi), bản vá KeyStyleStore giữ "keyMotion".
        val back = ThemeSpecParser.parse(ThemeSpec.export("drift", "Lạc trôi", "Adrift", t.palette(false)!!, t.palette(true)!!,
            ThemeSettings(theme = t).effectiveKeyStyle).json.canonical).spec!!
        assertEquals("float", back.keyMotion); assertEquals(0xFF22104A.toInt(), back.light.bg2)
        assertEquals("float", KeyStyleStore.parse(KeyStyleStore.serialize(mapOf("system" to KeyStyle(keyMotion = "float"))))["system"]?.keyMotion)
        // Kính (gradient giả lập Android) không xuất "bg2".
        val glass = ThemeSettings(theme = KeyboardTheme.GLASS)
        val gp = KeyboardTheme.GLASS.palette(false)
        if (gp != null) assertNull(glass.exportSpec(KeyboardTheme.GLASS, gp, KeyboardTheme.GLASS.palette(true)!!).light.bg2)
    }

    /** Bản vá "bg" ⇒ nền phẳng; bản vá "bg2" ⇒ đổi màu đáy. */
    @Test fun bg2Patch() {
        val p = KeyboardTheme.DRIFT.palette(false)!!
        assertEquals(0xFF22104A.toInt(), p.bgBottom)
        assertNull(KeyStyle(light = ThemeSlots(bg = 0xFF000000.toInt())).applyPatch(p, false).bgBottom)
        assertEquals(0xFF112233.toInt(), KeyStyle(light = ThemeSlots(bg2 = 0xFF112233.toInt())).applyPatch(p, false).bgBottom)
        assertNull(KeyboardTheme.NIGHTCLUB.palette(false)!!.bgBottom)
    }

    /** "Lơ lửng" (âm): làn gió + pad — nhỏ hơn Gõ gỗ, mềm (trọng tâm phổ thấp), seed cố định; checksum chung iOS. */
    @Test fun airySound() {
        for (k in KeySoundSynth.Kind.entries) {
            val wood = KeySoundSynth.samples(KeySoundStyle.WOOD, k); val a = KeySoundSynth.samples(KeySoundStyle.AIRY, k)
            assertTrue("$k", a.maxOf { abs(it) } < wood.maxOf { abs(it) })
            assertTrue("$k", a.size.toDouble() / KeySoundSynth.SAMPLE_RATE < 0.061)
            assertTrue("$k", KeySoundSynth.spectralCentroid(a) < 2500)
        }
        assertEquals(0x61697279 xor 0x85EBCA6B.toInt(), KeySoundSynth.seed(KeySoundStyle.AIRY, KeySoundSynth.Kind.LETTER))
        for ((i, k) in KeySoundSynth.Kind.entries.withIndex())
            assertEquals("$k", AIRY_GOLDEN[i], KeySoundSynth.samples(KeySoundStyle.AIRY, k).sumOf { abs(it).toDouble() }, 0.01)
        assertEquals("Floating", L10nTable.EN["Lơ lửng"])
        assertTrue(KeySoundStyle.AIRY in KeySoundStyle.PRESETS)
        assertEquals(KeySoundStyle.DREAM.ordinal + 1, KeySoundStyle.AIRY.ordinal)
    }

    private companion object {
        val AIRY_GOLDEN = listOf(153.4349, 120.8789, 125.1502)
    }
}
