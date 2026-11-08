package com.viettelex.keyboard

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs

/**
 * Hiệu ứng / âm / theme "Mưa" (theme Mưa đêm, 11/2026) — số tham chiếu GIỐNG HỆT iOS RainFxTests (KeyEffectTests.swift),
 * KeySoundTests.testRainPatter…, KeyboardThemeTests.testRainyNightTheme.
 */
class RainFxTests {
    @Test fun idAppendedLast() {
        assertTrue(KeyEffect.RAIN.ordinal > KeyEffect.SUNLIGHT.ordinal)
        assertEquals("rain", KeyEffect.RAIN.id)
        assertTrue(KeyEffect.RAIN.isPlus)
        assertEquals(KeyEffectBand.ABOVE_KEYS, KeyEffect.RAIN.band)
        assertEquals("Rain", L10nTable.EN[KeyEffect.RAIN.viTitle])
    }

    /** Mưa thưa dần: 1.0 suốt 40 phím đầu, −0.1 mỗi 40 phím, sàn 0.2 từ phím 320; ẩn bàn phím ⇒ đếm lại từ 0. */
    @Test fun intensityCurve() {
        val want = mapOf(0 to 1.0, 1 to 1.0, 39 to 1.0, 40 to 0.9, 79 to 0.9, 80 to 0.8, 200 to 0.5, 319 to 0.3, 320 to 0.2,
            1000 to 0.2, -5 to 1.0)
        for ((k, v) in want) assertEquals("$k", v, RainFx.intensity(k), 1e-12)
        var prev = 2.0
        for (k in 0..600) { val i = RainFx.intensity(k); assertTrue(i <= prev); assertTrue(i >= RainFx.FLOOR_INTENSITY); prev = i }
    }

    /** Đèn ấm: 0 → 0.6 theo độ thưa; chuyển nấc êm (smoothstep 1,5 s), không vượt đích. */
    @Test fun warmGlowCurve() {
        assertEquals(0.0, RainFx.glow(0), 1e-12)
        assertEquals(0.075, RainFx.glow(40), 1e-12)
        assertEquals(0.375, RainFx.glow(200), 1e-12)
        assertEquals(0.6, RainFx.glow(320), 1e-12)
        assertEquals(0.6, RainFx.glow(5000), 1e-12)
        assertEquals(0.0, RainFx.glowAt(0.0, 0.3, 0.0), 1e-12)
        assertEquals(0.15, RainFx.glowAt(0.0, 0.3, 0.75), 1e-12)
        assertEquals(0.3, RainFx.glowAt(0.0, 0.3, 1.5), 1e-12)
        assertEquals(0.3, RainFx.glowAt(0.0, 0.3, 9.0), 1e-12)
        assertEquals(0.0, RainFx.glowAt(0.0, 0.3, -1.0), 1e-12)
        var last = -1.0
        for (i in 0..30) { val g = RainFx.glowAt(0.1, 0.4, i * 0.05); assertTrue(g >= last - 1e-12); assertTrue(g <= 0.4 + 1e-12); last = g }
        assertEquals(214.5, RainFx.glowRadius(390.0, 260.0), 1e-9)
        assertEquals(234.0, RainFx.glowRadius(1000.0, 260.0), 1e-9)
    }

    /** Trần hạt mưa nền: ≤ 12 cùng lúc; mưa thưa ⇒ ít hạt (khoảng cách sinh hạt dài ra). */
    @Test fun dropCaps() {
        assertEquals(12, RainFx.maxInFlight(1.0))
        assertEquals(6, RainFx.maxInFlight(0.5))
        assertEquals(3, RainFx.maxInFlight(0.2))
        assertEquals(0.25, RainFx.spawnGap(1.0), 1e-12)
        assertEquals(1.25, RainFx.spawnGap(0.2), 1e-12)
        assertEquals(1.25, RainFx.spawnGap(0.0), 1e-12)
        for (k in 0..400 step 40) assertTrue(RainFx.maxInFlight(RainFx.intensity(k)) <= RainFx.MAX_DROPS)
        // Mô phỏng gõ 10 phím / giây trong 60 s: số hạt đang trượt không bao giờ quá trần của độ đậm hiện tại.
        val starts = ArrayList<Double>(); var last = -1e9
        for (n in 0 until 600) {
            val t = n * 0.1; val i = RainFx.intensity(n + 1)
            if (RainFx.shouldSpawn(t - last, i)) { last = t; starts += t }
            val alive = starts.count { t - it in 0.0..<RainFx.DROP_LIFE }
            assertTrue("t=$t alive=$alive", alive <= RainFx.MAX_DROPS)
        }
        assertEquals(3 * RainFx.TAP_SLOTS, RainFx.TAP_SLOTS * RainFx.LAYERS_PER_TAP)
        assertTrue(RainFx.TAP_SLOTS * RainFx.LAYERS_PER_TAP <= KeyEffectPool.CAP)
    }

    /** Nghỉ: hạt mưa nền sống đúng [RainFx.DROP_LIFE] = ngưỡng nghỉ 3 s; giọt ở phím ≤ 2,1 s ⇒ sau 3 s không còn gì. */
    @Test fun idleStop() {
        assertEquals(RainFx.IDLE_AFTER, RainFx.DROP_LIFE, 0.0)
        assertFalse(RainFx.isIdle(2.99)); assertTrue(RainFx.isIdle(3.0))
        assertEquals(2.1, RainFx.TAP_LIFE, 1e-12)
        assertTrue(RainFx.TAP_LIFE <= RainFx.IDLE_AFTER)
        assertEquals(0.0, RainFx.dropAlpha(1.0), 0.0); assertEquals(0.0, RainFx.dropAlpha(-0.01), 0.0)
        val o = DoubleArray(3)
        RainFx.drop(RainFx.TAP_LIFE, o); assertEquals(0.0, o[2], 0.0)
        RainFx.ring(RainFx.TAP_LIFE, o); assertEquals(0.0, o[1], 0.0)
        RainFx.trail(RainFx.TAP_LIFE, o); assertEquals(0.0, o[1], 0.0)
    }

    /** Quỹ đạo hạt mưa nền: trượt — đọng — trượt (mốc chung iOS), đơn điệu, x trong lề. */
    @Test fun ambientPathShared() {
        assertEquals(0.0, RainFx.travel(0.0, 0), 0.0); assertEquals(1.0, RainFx.travel(1.0, 2), 0.0)
        assertEquals(0.22, RainFx.travel(0.18, 0), 1e-12)
        assertEquals(0.235, RainFx.travel(0.29, 0), 1e-12)
        assertEquals(0.67, RainFx.travel(0.73, 1), 1e-12)
        assertEquals(0.75, RainFx.travel(0.86, 2), 1e-12)
        for (p in 0..2) { var prev = 0.0; for (i in 0..100) { val y = RainFx.travel(i / 100.0, p); assertTrue(y >= prev); prev = y } }
        // Đoạn "đọng": 22 % thời gian mà chỉ trượt 3 % quãng.
        assertTrue(RainFx.travel(0.40, 0) - RainFx.travel(0.18, 0) < 0.04)
        assertEquals(282.0, RainFx.travelDistance(260.0), 1e-12)
        assertEquals(RainFx.DROP_PEAK_ALPHA, RainFx.dropAlpha(0.5), 1e-12)
        var sum = 0.0
        for (s in 0 until 50) { val x = RainFx.dropX(s, 390.0); assertTrue(x in 10.0..380.0); sum += x }
        assertEquals(RAIN_DROPX_SUM, sum, 1e-6)
        assertEquals(1, RainFx.profile(4)); assertEquals(2, RainFx.profile(-1))
    }

    /** Giọt ở phím: rơi → đọng → lăn; vòng loang; vệt ướt — số mốc chung iOS. */
    @Test fun tapDropShared() {
        val o = DoubleArray(3)
        RainFx.drop(0.0, o); assertEquals(-16.0, o[1], 1e-12); assertEquals(0.9, o[2], 1e-12)
        RainFx.drop(0.06, o); assertEquals(-12.0, o[1], 1e-12)
        RainFx.drop(0.15, o); assertEquals(0.0, o[1], 1e-12)
        RainFx.drop(0.75, o); assertEquals(7.5, o[1], 1e-12); assertEquals(2.5, o[0], 1e-12); assertEquals(0.9, o[2], 1e-12)
        RainFx.drop(1.19, o); assertEquals(0.3, o[2], 1e-9)
        RainFx.ring(0.12, o); assertEquals(1.5, o[0], 1e-12); assertEquals(0.7, o[1], 1e-12)
        RainFx.ring(0.32, o); assertEquals(8.625, o[0], 1e-12); assertEquals(0.35, o[1], 1e-12)
        RainFx.ring(0.6, o); assertEquals(0.0, o[1], 0.0)
        RainFx.trail(0.1, o); assertEquals(0.0, o[1], 0.0)
        RainFx.trail(0.75, o); assertEquals(0.25, o[0], 1e-12); assertEquals(0.35, o[1], 1e-12)
        RainFx.trail(1.7, o); assertEquals(1.0, o[0], 0.0); assertEquals(0.175, o[1], 1e-12)
    }

    // ---- âm Mưa

    /** Âm "Mưa": nhỏ nhất (đỉnh < mọi kiểu khác, RMS < Gõ gỗ), không chói, 4 biến thể phím chữ khác nhau, checksum chung iOS. */
    @Test fun rainPatterSound() {
        for (k in KeySoundSynth.Kind.entries) {
            val a = KeySoundSynth.samples(KeySoundStyle.RAIN, k); val wood = KeySoundSynth.samples(KeySoundStyle.WOOD, k)
            assertTrue("$k", KeySoundSynth.rms(a) < KeySoundSynth.rms(wood))
            assertTrue("$k", KeySoundSynth.spectralCentroid(a) < 2500)
            for (st in KeySoundStyle.PRESETS) if (st != KeySoundStyle.RAIN)
                // ≤: Chuông sao (Cung hoàng đạo) cũng đỉnh 0.34 — hai nhánh cùng chọn mức êm nhất.
                assertTrue("$st", a.maxOf { abs(it) } <= KeySoundSynth.samples(st, k).maxOf { abs(it) } + 1e-6f)
        }
        val golden = listOf(54.9785, 57.6999, 63.9406)
        for ((i, k) in KeySoundSynth.Kind.entries.withIndex())
            assertEquals("$k", golden[i], KeySoundSynth.samples(KeySoundStyle.RAIN, k).sumOf { abs(it).toDouble() }, 0.01)
        val varGolden = listOf(54.9785, 39.5428, 45.6720, 40.3041)
        val vs = (0 until KeySoundSynth.RAIN_VARIANTS).map { KeySoundSynth.rainLetterSamples(it) }
        for (v in vs.indices) {
            assertEquals("var $v", varGolden[v], vs[v].sumOf { abs(it).toDouble() }, 0.01)
            assertEquals(vs[v].toList(), KeySoundSynth.rainLetterSamples(v).toList())
            assertTrue(KeySoundSynth.spectralCentroid(vs[v]) < 2500)
            for (u in 0 until v) assertNotEquals(vs[u].toList(), vs[v].toList())
        }
        assertEquals(KeySoundSynth.samples(KeySoundStyle.RAIN, KeySoundSynth.Kind.LETTER).toList(), vs[0].toList())
        assertEquals(0x7261696E xor 0x85EBCA6B.toInt(), KeySoundSynth.seed(KeySoundStyle.RAIN, KeySoundSynth.Kind.LETTER))
        // Thứ tự biến thể: đủ 4, không lặp liền (kể cả nối vòng).
        val seq = (0 until 32).map { KeySoundSynth.rainVariant(it) }
        assertEquals(setOf(0, 1, 2, 3), seq.toSet())
        for (i in 1 until seq.size) assertNotEquals(seq[i - 1], seq[i])
        assertEquals(listOf(0, 2, 1, 3, 2, 0, 3, 1), seq.take(8))
        assertEquals("Rain", L10nTable.EN["Mưa"])
        assertTrue(KeySoundStyle.RAIN in KeySoundStyle.PRESETS)
    }

    // ---- theme Mưa đêm

    @Test fun rainyNightTheme() {
        val t = KeyboardTheme.RAINY_NIGHT
        assertEquals("rainyNight", t.id)
        assertTrue(t.isPlus); assertFalse("không gắn nhãn Tương tác", t.isInteractive)
        val spec = t.spec!!
        assertEquals("Mưa đêm", spec.nameVi); assertEquals("Rainy Night", spec.nameEn)
        assertEquals("Rainy Night", L10nTable.EN[t.viTitle])
        assertEquals("rain", spec.sound); assertEquals("rain", spec.effect); assertEquals("simple", spec.swipe)
        assertEquals(null, spec.dark)
        assertTrue(ThemeSpecParser.contrastIssues(spec).isEmpty())
        val p = t.palette(false)!!
        assertTrue(ThemeColor.contrast(p.ink, ThemeColor.over(p.keyFill, p.bg)) >= 4.5)
        assertTrue(ThemeColor.alpha(p.keyFill) < 255)   // phím kính trong mờ
        assertEquals(ThemeDecoration.BOKEH, p.decoration?.motif)
        assertTrue(ThemeDecoration.hasShade(p.decoration?.motif, p.decoration?.alt))
        // Nhóm Plus, thứ tự khai báo (sau Neon Night Club), không vào nhóm Tương tác.
        val secs = ThemePicker.sections
        assertTrue(t in secs[2].themes); assertFalse(t in secs[1].themes)
        assertEquals(t, ThemePicker.ordered().last())
    }

    /** Motif "bokeh": đốm tròn rời nhau trong ô (|y| + r ≤ 0.5), dải phủ nền trên sáng → dưới tối — mốc chung iOS. */
    @Test fun bokehMotif() {
        assertTrue(ThemeDecoration.BOKEH in ThemeDecoration.MOTIFS)
        val subs = ThemeDecoration.shape(ThemeDecoration.BOKEH)
        assertEquals(5, subs.size)
        for (d in ThemeDecoration.BOKEH_DOTS) assertTrue(abs(d[1]) + d[2] <= 0.5 + 1e-12)
        for (i in ThemeDecoration.BOKEH_DOTS.indices) for (j in 0 until i) {
            val a = ThemeDecoration.BOKEH_DOTS[i]; val b = ThemeDecoration.BOKEH_DOTS[j]
            assertTrue(Math.hypot(a[0] - b[0], a[1] - b[1]) > a[2] + b[2])
        }
        assertEquals(0x14, ThemeDecoration.BOKEH_SHADE[0] ushr 24)
        assertEquals(0x2E, ThemeDecoration.BOKEH_SHADE[2] ushr 24)
        assertEquals(0x000000, ThemeDecoration.BOKEH_SHADE[2] and 0xFFFFFF)
        assertFalse(ThemeDecoration.hasShade(ThemeDecoration.NEURAL, null))
    }

    companion object {
        /** Tổng hoành độ 50 hạt đầu ở bề ngang 390 (dp) — chung iOS. Tính bằng bản Python của fxSeed/fxStep/fxValue. */
        const val RAIN_DROPX_SUM = 9862.284428168154
    }
}
