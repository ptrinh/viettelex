package com.viettelex.keyboard

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs

/**
 * "Biển" (theme Biển, 11/2026): sóng vỗ bờ + bọt bắn + bong bóng + cá — song sinh iOS KeyEffectTests (extension Biển),
 * CÙNG số tham chiếu. Phần View không chạy trên JVM: test hàm thuần [SeaFx].
 */
class KeyEffectSeaTests {
    private val eps = 1e-5

    @Test fun modelAndCaps() {
        val e = KeyEffect.SEA
        assertEquals("thêm CUỐI enum", KeyEffect.SEA, KeyEffect.entries.last())
        assertEquals("sea", e.id); assertEquals(KeyEffect.SEA, KeyEffect.of("sea"))
        assertTrue(e.isPlus); assertFalse(e.isParticle); assertFalse(e.isQueued)
        assertFalse(e.needsComposeDiff); assertFalse(e.needsBoundaryWord)
        assertEquals(KeyEffectBand.ABOVE_KEYS, e.band)
        assertEquals(0, e.particlesPerTap)
        assertEquals("Sea", L10nTable.EN[e.viTitle])
        assertTrue("sea" in ThemeExtraIds.EFFECTS)
        // Trần: chùm bọt + bong bóng ≤ pool chung; sóng nối nhau không bao giờ cướp sóng đang chạy.
        assertEquals(5, SeaFx.LAYERS_PER_TAP)
        assertEquals(20, SeaFx.TAP_SLOTS * SeaFx.LAYERS_PER_TAP)
        assertTrue(SeaFx.TAP_SLOTS * SeaFx.LAYERS_PER_TAP <= KeyEffectPool.CAP)
        assertEquals(3, SeaFx.MAX_WAVES)
        assertTrue("đủ ô cho mọi sóng còn sống", SeaFx.MAX_WAVES * SeaFx.LAUNCH_GAP >= SeaFx.LIFE)
        assertEquals(1.6, SeaFx.LIFE, 1e-12)
        assertFalse("gõ dồn: chỉ bọt + bong bóng", SeaFx.shouldLaunch(0.2))
        assertTrue(SeaFx.shouldLaunch(0.55))
        assertEquals(listOf(1.0, 1.2, 1.4, 1.65, 1.65, 1.65), (0..5).map { SeaFx.size(it) })
        assertEquals(1.0, SeaFx.size(-1), 0.0)
    }

    /** Đường cong sóng: cuộn nhanh dần từ đỉnh tới bờ, vỡ (thân tan, bọt dâng) rồi rút để lại vệt ướt mờ dần. */
    @Test fun waveCurveBreakAndRecede() {
        assertEquals(0.0, SeaFx.travel(-1.0), 0.0); assertEquals(0.0, SeaFx.travel(0.0), 0.0)
        assertEquals(0.25, SeaFx.travel(0.3), 1e-12)
        assertEquals(0.5625, SeaFx.travel(0.45), 1e-12)
        assertEquals(1.0, SeaFx.travel(0.6), 0.0); assertEquals(1.0, SeaFx.travel(5.0), 0.0)
        var last = -1.0
        for (i in 0..60) { val v = SeaFx.travel(i * 0.01); assertTrue(v >= last); last = v }
        assertEquals(8.0, SeaFx.driftX(0.3), 1e-12); assertEquals(16.0, SeaFx.driftX(2.0), 0.0)
        assertEquals(0.592875, SeaFx.crestOffset(0.0, 0.0), eps)
        assertEquals(1.300941, SeaFx.crestOffset(30.0, 0.9), eps)
        assertEquals(0.140812, SeaFx.crestOffset(77.0, 1.8), eps)
        assertEquals(-26.198922, SeaFx.bodyTop(10.0, 0.9), eps)
        assertEquals(-13.236323, SeaFx.washTop(20.0, 0.0), eps)
        assertEquals(0.9, SeaFx.phase(1), 1e-12)
        var x = -110.0
        while (x <= 500.0) {
            assertTrue(abs(SeaFx.crestOffset(x, 0.9)) <= SeaFx.CREST_AMP * 1.3 + 1e-9)
            assertTrue("thân sóng nằm sau mép", SeaFx.bodyTop(x, 0.9) < SeaFx.crestOffset(x, 0.9))
            x += 3.0
        }
        assertEquals(1.0, SeaFx.waveAlpha(0.3), 0.0); assertEquals(0.5, SeaFx.waveAlpha(0.75), 1e-9)
        assertEquals(0.0, SeaFx.waveAlpha(0.9), 0.0); assertEquals(0.0, SeaFx.waveAlpha(-0.1), 0.0)
        assertEquals("chưa tới bờ: chưa có bọt tràn", 0.0, SeaFx.washHeight(0.5, 1.0), 0.0)
        assertEquals(14.7, SeaFx.washHeight(0.75, 1.4), 1e-9)
        assertEquals("đỉnh bọt tràn = WASH_MAX × cỡ", 23.1, SeaFx.washHeight(0.9, 1.65), 1e-9)
        assertEquals(7.0, SeaFx.washHeight(1.25, 1.0), 1e-9)
        assertEquals(0.0, SeaFx.washHeight(SeaFx.LIFE, 1.65), 0.0)
        assertEquals("vệt ướt chỉ hiện khi nước rút", 0.0, SeaFx.wetAlpha(0.85), 0.0)
        assertEquals(0.3, SeaFx.wetAlpha(0.9), 1e-9)
        assertEquals(0.15, SeaFx.wetAlpha(1.25), 1e-9)
        assertEquals(0.0, SeaFx.wetAlpha(SeaFx.LIFE), 0.0)
        for (t in listOf(SeaFx.LIFE, SeaFx.LIFE + 0.5)) {   // hết đời sóng: không còn gì vẽ (nghỉ gõ = 0 khung hình)
            assertEquals(0.0, SeaFx.waveAlpha(t), 0.0); assertEquals(0.0, SeaFx.washHeight(t, 1.65), 0.0)
            assertEquals(0.0, SeaFx.wetAlpha(t), 0.0)
        }
        for (i in 0..160) assertTrue(SeaFx.washHeight(i * 0.01, 1.65) <= SeaFx.WASH_MAX * 1.65 + 1e-9)
    }

    @Test fun splashBubblesAndFishRule() {
        val o = DoubleArray(4)
        SeaFx.droplet(1, 0.5, o); assertEquals(1.5, o[0], 1e-12); assertEquals(-19.0, o[1], 1e-12)
        SeaFx.droplet(0, 0.0, o); assertEquals(0.0, o[0], 0.0); assertEquals(0.0, o[1], 0.0)
        SeaFx.droplet(2, 1.0, o); assertEquals("giọt rơi xuống dưới phím", SeaFx.DROPLET_SINK, o[1], 1e-12)
        SeaFx.bubble(1, 0.5, o)
        assertEquals(9.5, o[0], 1e-9); assertEquals(-42.0, o[1], 1e-9); assertEquals(0.835294, o[2], eps); assertEquals(1.0, o[3], 0.0)
        SeaFx.bubble(0, 0.9, o)
        assertEquals(-2.168441, o[0], eps); assertEquals(-43.56, o[1], 1e-9); assertEquals(1.266667, o[2], eps); assertEquals(0.666667, o[3], eps)
        SeaFx.bubble(0, 1.0, o); assertEquals("vỡ thành vòng", SeaFx.POP_SCALE, o[2], 1e-9); assertEquals(0.0, o[3], 1e-9)
        // Cá: chỉ khi mức combo VỪA lên FISH_LEVEL, nghỉ ≥ FISH_COOLDOWN.
        assertTrue(SeaFx.fishShouldSwim(2, 1, 100.0))
        assertTrue(SeaFx.fishShouldSwim(3, 0, 4.0))
        assertFalse("chưa đủ combo", SeaFx.fishShouldSwim(1, 0, 100.0))
        assertFalse("đang combo: không bơi lại", SeaFx.fishShouldSwim(3, 2, 100.0))
        assertFalse("trong thời gian nghỉ cá", SeaFx.fishShouldSwim(2, 1, 3.9))
        assertEquals(125.752758, SeaFx.fishY(3, 260.0), eps)
        assertEquals(134.036973, SeaFx.fishY(0, 260.0), eps)
        assertTrue(SeaFx.fishRightToLeft(0)); assertFalse(SeaFx.fishRightToLeft(1))
        assertEquals(376.0, SeaFx.fishX(0.0, 390.0, true), 0.0); assertEquals(14.0, SeaFx.fishX(1.0, 390.0, true), 0.0)
        assertEquals(195.0, SeaFx.fishX(0.5, 390.0, false), 0.0)
        assertEquals(0.5, SeaFx.fishAlpha(0.05), 1e-9); assertEquals(1.0, SeaFx.fishAlpha(0.5), 0.0); assertEquals(0.0, SeaFx.fishAlpha(1.0), 0.0)
        // Cá luôn trong bàn phím (dọc) dù nhấp nhô.
        for (s in 0 until 40) {
            val y = SeaFx.fishY(s, 260.0)
            assertTrue(y - SeaFx.FISH_BOB - SeaFx.FISH_SIZE / 2 >= 0); assertTrue(y + SeaFx.FISH_BOB + SeaFx.FISH_SIZE / 2 <= 260)
        }
    }

    /** Mô phỏng nhịp gõ bằng đúng luật overlay (ComboMeter + shouldLaunch + fishShouldSwim): sóng nối nhau, ≤ MAX_WAVES
     *  sóng sống cùng lúc, gõ nhanh ⇒ sóng to, cá bơi đúng một lần mỗi đợt combo. = luật iOS fireSea / Android fireSea. */
    @Test fun typingRhythmDrivesWavesAndFish() {
        val combo = ComboMeter()
        var lastWave = Long.MIN_VALUE / 2; var lastFish = Long.MIN_VALUE / 2; var prev = 0
        val waves = mutableListOf<Pair<Long, Double>>(); var fish = 0
        var t = 0L
        repeat(60) {           // ~8 phím/giây trong 7,5 s
            val lv = combo.press(t)
            if (SeaFx.shouldLaunch((t - lastWave) / 1000.0)) { lastWave = t; waves += t to SeaFx.size(lv) }
            if (SeaFx.fishShouldSwim(lv, prev, (t - lastFish) / 1000.0)) { lastFish = t; fish++ }
            prev = lv
            val alive = waves.count { t - it.first < Math.round(SeaFx.LIFE * 1000) }
            assertTrue("≤ MAX_WAVES sóng cùng lúc", alive <= SeaFx.MAX_WAVES)
            t += 125
        }
        assertEquals(1.0, waves.first().second, 0.0)
        assertEquals("gõ nhanh ⇒ sóng to nhất", 1.65, waves.last().second, 0.0)
        assertEquals("một đợt combo liên tục ⇒ cá bơi một lần", 1, fish)
        for (i in 1 until waves.size) assertTrue(waves[i].first - waves[i - 1].first >= 550)
    }
}
