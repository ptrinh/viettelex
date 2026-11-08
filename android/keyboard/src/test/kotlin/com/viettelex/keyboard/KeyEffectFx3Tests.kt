package com.viettelex.keyboard

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs
import kotlin.math.hypot

/**
 * Đợt 3 hiệu ứng phím (11/2026): Plasma, Rung combo, Laser, Glitch, Dấu thanh, Từ khoá, Chữ bay, Hạt cát — song sinh
 * iOS KeyEffectTests (extension đợt 3), CÙNG số tham chiếu. Phần View không chạy trên JVM: test hàm thuần.
 */
class KeyEffectFx3Tests {
    private val new = listOf(KeyEffect.PLASMA, KeyEffect.SHAKE, KeyEffect.LASER, KeyEffect.GLITCH, KeyEffect.TONE,
        KeyEffect.KEYWORD, KeyEffect.LETTERS, KeyEffect.SAND)

    @Test fun modelZeroCostHooks() {
        for (e in new) {
            assertTrue(e.id, e.isPlus)
            assertEquals(e.id, KeyEffectBand.ABOVE_KEYS, e.band)
            assertFalse(e.id, e.isParticle)
            assertEquals(e.id, 0, e.particlesPerTap)
        }
        // Chỉ ba kiểu khiến IME đọc từ đang soạn trước/sau phím (+ Token AI 11/2026); chỉ hai kiểu cần từ ở ranh giới.
        assertEquals(listOf(KeyEffect.TONE, KeyEffect.LETTERS, KeyEffect.TOKENS), KeyEffect.entries.filter { it.needsComposeDiff })
        assertEquals(listOf(KeyEffect.EMOJIWORD, KeyEffect.KEYWORD, KeyEffect.REPS, KeyEffect.RAINBOWBURST),   // + BEAST MODE (Gym), cờ (Tự hào)
            KeyEffect.entries.filter { it.needsBoundaryWord })
        assertEquals(listOf(KeyEffect.EMOJIWORD, KeyEffect.TONE, KeyEffect.KEYWORD, KeyEffect.LETTERS, KeyEffect.TOKENS),
            KeyEffect.entries.filter { it.isQueued })
        assertTrue(ThemeExtraIds.EFFECTS.containsAll(new.map { it.id }))
    }

    // MARK: Dấu thanh

    @Test fun toneDetection() {
        val cases = listOf(
            Triple("a", "á", ToneFx.SAC), Triple("ban", "bàn", ToneFx.HUYEN), Triple("ca", "cả", ToneFx.HOI),
            Triple("ma", "mã", ToneFx.NGA), Triple("ho", "họ", ToneFx.NANG), Triple("hoa", "hoá", ToneFx.SAC),
            Triple("bá", "bà", ToneFx.HUYEN), Triple("A", "Á", ToneFx.SAC), Triple("a", "á", ToneFx.SAC),
            Triple("a", "â", ToneFx.HAT), Triple("a", "ă", ToneFx.HAT), Triple("e", "ê", ToneFx.HAT),
            Triple("o", "ô", ToneFx.HAT), Triple("á", "ấ", ToneFx.HAT), Triple("o", "ơ", ToneFx.HORN),
            Triple("u", "ư", ToneFx.HORN), Triple("tuong", "tương", ToneFx.HORN), Triple("d", "đ", ToneFx.STROKE),
            Triple("D", "Đ", ToneFx.STROKE), Triple("tiê", "tiế", ToneFx.SAC), Triple("nguyen", "nguyễn", ToneFx.NGA),
        )
        for ((b, a, want) in cases) assertEquals("$b → $a", want, ToneMarks.detect(b, a))
        // Không có dấu mới: gỡ dấu, chữ thường, dời dấu, ranh giới.
        for ((b, a) in listOf("á" to "as", "hoa" to "hoan", "hóa" to "hoá", "" to "a", "a" to "", "â" to "âu",
            "đ" to "đi", "tương" to "tươn", "abc" to "abcd")) assertNull("$b → $a", ToneMarks.detect(b, a))
    }

    @Test fun toneTrajectories() {
        // Sắc: lên-phải (dx > 0, dy < 0); huyền: xuống-trái; nặng rơi xuống; hỏi/ngã/mũ bay lên.
        for (i in 0 until ToneBurst.SPARKS) {
            val s = ToneBurst.trajectory(ToneFx.SAC, i); assertTrue(s.dx > 0 && s.dy < 0)
            val h = ToneBurst.trajectory(ToneFx.HUYEN, i); assertTrue(h.dx < 0 && h.dy > 0)
        }
        assertTrue(ToneBurst.trajectory(ToneFx.NANG, 0).dy > 0)
        assertTrue(ToneBurst.easeIn(ToneFx.NANG)); assertTrue(ToneBurst.stretchesX(ToneFx.NGA))
        for (k in listOf(ToneFx.HOI, ToneFx.NGA, ToneFx.HAT, ToneFx.HORN, ToneFx.STROKE)) assertTrue(ToneBurst.trajectory(k, 0).dy < 0)
        for (k in ToneFx.entries) for (i in 0 until ToneBurst.count(k)) {
            val t = ToneBurst.trajectory(k, i)
            assertTrue(hypot(t.dx, t.dy) <= 40); assertTrue(t.duration in 0.3..0.6)
        }
        assertEquals(listOf("SAC", "HUYEN", "HOI", "NGA", "NANG", "HAT", "HORN", "STROKE"), ToneFx.entries.map { it.name })
        // Số tham chiếu chéo iOS.
        val s0 = ToneBurst.trajectory(ToneFx.SAC, 0)
        assertEquals(9.2904, s0.dx, 1e-3); assertEquals(-24.2835, s0.dy, 1e-3)
    }

    // MARK: Từ khoá

    @Test fun keywordTable() {
        assertEquals("haha:LAUGH hihi:LAUGH hehe:LAUGH kkk:LAUGH yêu:LOVE thương:LOVE love:LOVE giận:ANGRY bực:ANGRY " +
            "tết:TET năm mới:TET lì xì:TET lixi:TET", KeywordBursts.entries.joinToString(" ") { "${it.form}:${it.kind}" })
        val hit = mapOf("haha" to KeywordKind.LAUGH, "hahaha" to KeywordKind.LAUGH, "HIHI" to KeywordKind.LAUGH,
            "kkkk" to KeywordKind.LAUGH, "hehehe" to KeywordKind.LAUGH, "Yêu" to KeywordKind.LOVE,
            "thương!" to KeywordKind.LOVE, "LOVE" to KeywordKind.LOVE, "giận" to KeywordKind.ANGRY, "Bực" to KeywordKind.ANGRY,
            "Tết" to KeywordKind.TET, "tết," to KeywordKind.TET, "lixi" to KeywordKind.TET)
        for ((w, k) in hit) assertEquals(w, k, KeywordBursts.lookup(w, null))
        for (w in listOf("tet", "yeu", "thường", "thuong", "gian", "buc", "kk", "ha", "hah", "hahah", "", "!!", "khóc"))
            assertNull(w, KeywordBursts.lookup(w, null))
        assertEquals(KeywordKind.TET, KeywordBursts.lookup("mới", "năm"))     // "chúc mừng năm mới"
        assertEquals(KeywordKind.TET, KeywordBursts.lookup("xì", "lì"))
        assertNull(KeywordBursts.lookup("mới", "mừng"))
        assertNull(KeywordBursts.lookup("moi", "nam"))
    }

    @Test fun keywordParticlesCapped() {
        for (k in KeywordKind.entries) {
            val ps = KeywordBursts.particles(k)
            assertTrue("$k", ps.size in 1..KeyEffectPool.CAP)
            assertTrue("$k", KeywordBursts.lifetime(k) <= 2.0)
            assertTrue(KeywordBursts.particles(k) === ps)   // dựng một lần
            for (p in ps) {
                // Trong vùng ~90 dp quanh phím: lớp phủ cắt theo bàn phím, không vẽ ra ngoài.
                assertTrue(abs(p.x0 + p.traj.dx) + abs(p.traj.sway) <= 90 && abs(p.y0 + p.traj.dy) <= 90)
                if (p.shape == KeywordBursts.Shape.EMOJI) assertTrue(p.color < KeywordBursts.emojis(k).size)
            }
        }
        val tet = KeywordBursts.particles(KeywordKind.TET).map { it.shape }.toSet()
        assertEquals(setOf(KeywordBursts.Shape.CRACKER, KeywordBursts.Shape.SPARK, KeywordBursts.Shape.PAPER,
            KeywordBursts.Shape.ENVELOPE), tet)
        assertEquals(listOf(3, 5, 5, 20), KeywordKind.entries.map { KeywordBursts.particles(it).size })
        // Xác pháo rơi XUỐNG, lì xì bay LÊN.
        assertTrue(KeywordBursts.particles(KeywordKind.TET).filter { it.shape == KeywordBursts.Shape.PAPER }.all { it.traj.dy > 0 && it.easeIn })
        assertTrue(KeywordBursts.particles(KeywordKind.TET).filter { it.shape == KeywordBursts.Shape.ENVELOPE }.all { it.traj.dy < 0 })
    }

    // MARK: Rung combo

    /** Số tham chiếu — iOS KeyEffectTests.testShakeNumbersAndMeter giữ y hệt. Giảm chuyển động không còn tắt rung. */
    @Test fun shakeNumbersAndMeter() {
        assertEquals(7.0, ShakeFx.MAX, 0.0)
        assertEquals(listOf(0.0, 3.0, 5.0, 7.0), ShakeFx.AMPS.toList())
        assertEquals(245L, ShakeFx.DURATION_MS)
        for (lv in -1..5) assertTrue(ShakeFx.amplitude(lv) <= ShakeFx.MAX)
        assertEquals(0.0, ShakeFx.amplitude(0), 0.0)
        assertEquals(listOf(3.0, 5.0, 7.0), (1..3).map { ShakeFx.amplitude(it) })
        // 3–4 nhịp tắt dần: dấu x đổi chiều mỗi khung, |x| giảm dần.
        val mid = ShakeFx.XS.toList().drop(1).dropLast(1)
        assertTrue(mid.zipWithNext().count { (a, b) -> a * b < 0 } >= 5)
        assertTrue(mid.zipWithNext().all { (a, b) -> abs(a) > abs(b) })
        assertTrue(ShakeFx.YS.all { abs(it) < 0.5 })

        // Gõ nhanh bình thường: phím thứ 4 trong 1,2 s đã rung (≈ 3,5 phím/s).
        val m = ShakeMeter()
        assertEquals(listOf(0, 0, 0, 1), (0 until 4).map { m.press(it * 300L) })
        m.reset()
        assertEquals(listOf(0, 0, 0, 1, 1, 2, 2, 3, 3), (0 until 9).map { m.press(it * 100L) })
        assertEquals(0, m.press(800L + 2000L))
        m.reset()
        assertEquals(List(6) { 0 }, (0 until 6).map { m.press(it * 500L) })

        val amp = ShakeFx.amplitude(3)
        for (t in -10L..300L) {
            assertTrue(abs(ShakeFx.offsetX(t, amp)) <= amp + 1e-9); assertTrue(abs(ShakeFx.offsetY(t, amp)) <= amp + 1e-9)
        }
        assertEquals(0.0, ShakeFx.offsetX(0, amp), 0.0); assertEquals(0.0, ShakeFx.offsetX(ShakeFx.DURATION_MS, amp), 0.0)
        assertEquals(0.0, ShakeFx.offsetY(ShakeFx.DURATION_MS + 5, amp), 0.0)
        assertEquals(7.0, ShakeFx.offsetX(35, 7.0), 1e-9)
        assertEquals(-4.25, ShakeFx.offsetX(70, 5.0), 1e-9)
        assertEquals(-2.45, ShakeFx.offsetY(35, 7.0), 1e-9)
        assertEquals(1.2, ShakeFx.offsetX(14, 3.0), 1e-9)
    }

    // MARK: Sàn nhảy LED — flash phím cách

    /** Số tham chiếu — iOS KeyEffectTests.testBeatFlashNumbersAndGate giữ y hệt. */
    @Test fun beatFlashNumbersAndGate() {
        assertEquals(0.02, BeatFlash.RISE, 0.0); assertEquals(0.11, BeatFlash.FALL, 0.0)
        assertEquals(0.13, BeatFlash.DURATION, 1e-12)
        assertEquals(0.6, BeatFlash.PEAK, 0.0); assertEquals(3, BeatFlash.MAX_PER_SECOND)
        assertEquals(0.0, BeatFlash.alpha(-0.001), 0.0)
        assertEquals(0.0, BeatFlash.alpha(0.0), 0.0)
        assertEquals(0.3, BeatFlash.alpha(0.01), 1e-9)
        assertEquals(0.6, BeatFlash.alpha(0.02), 1e-9)
        assertEquals(0.15, BeatFlash.alpha(0.075), 1e-9)
        assertEquals(0.0, BeatFlash.alpha(0.13), 0.0)
        var t = 0.0
        while (t <= 0.2) {
            assertTrue(BeatFlash.alpha(t) <= BeatFlash.PEAK + 1e-12)
            if (t > 0.0205) assertTrue("tắt đơn điệu", BeatFlash.alpha(t) <= BeatFlash.alpha(t - 0.001) + 1e-12)
            t += 0.001
        }
        assertEquals(0xFFB6EF, BeatFlash.tint(0))
        assertEquals(0xDCC6FF, BeatFlash.tint(1))
        assertEquals(0xB6F6FF, BeatFlash.tint(2))
        assertEquals(BeatFlash.tint(0), BeatFlash.tint(3))

        // ≤ 3 lần trong MỌI khoảng 1 s: 10 nhịp trong 1 s ⇒ 3.
        val g = BeatFlash.Gate()
        assertEquals(3, (0 until 10).count { g.trigger(it * 0.1) })
        assertEquals(3, g.fired)
        assertFalse(g.trigger(0.99))
        assertTrue("đủ 1 s sau nhịp cũ nhất ⇒ lại được", g.trigger(1.0))
        val h = BeatFlash.Gate()
        assertEquals("~3 nhịp/s đều đặn: không bỏ", 12, (0 until 12).count { h.trigger(it * 0.34) })
        val w = BeatFlash.Gate()
        val times = (0 until 200).map { it * 0.047 }.filter { w.trigger(it) }
        for (i in 3 until times.size) assertTrue(times[i] - times[i - 3] >= 1.0 - 1e-9)
    }

    // MARK: Plasma

    @Test fun plasmaChainAndArc() {
        val c = PlasmaChain()
        assertFalse("phím đầu", c.press(10.0, 10.0, 1000))
        assertTrue(c.press(80.0, 20.0, 1200)); assertEquals(10.0, c.prevX, 0.0); assertEquals(10.0, c.prevY, 0.0)
        assertFalse("cùng phím", c.press(81.0, 21.0, 1300))
        assertFalse("nghỉ quá lâu", c.press(10.0, 10.0, 1300 + PlasmaArc.CHAIN_MS + 1))
        val out = DoubleArray(2 * (PlasmaArc.SEGMENTS + 1))
        for (v in 0 until PlasmaArc.VARIANTS) {
            PlasmaArc.points(0.0, 0.0, 100.0, 40.0, v, out)
            assertEquals(0.0, out[0], 0.0); assertEquals(100.0, out[2 * PlasmaArc.SEGMENTS], 0.0)
            for (i in 0..PlasmaArc.SEGMENTS) {
                val f = i.toDouble() / PlasmaArc.SEGMENTS
                assertTrue(hypot(out[2 * i] - 100 * f, out[2 * i + 1] - 40 * f) <= PlasmaArc.MAX_JITTER + 1e-9)
            }
        }
        PlasmaArc.points(0.0, 0.0, 100.0, 0.0, 3, out)
        assertArrayEquals(doubleArrayOf(PLASMA_Y1, PLASMA_Y4), doubleArrayOf(out[3], out[9]), 1e-4)
        assertEquals(1.0, PlasmaArc.alpha(0), 0.0); assertEquals(0.0, PlasmaArc.alpha(PlasmaArc.DURATION_MS), 0.0)
    }

    // MARK: Laser / Glitch

    @Test fun laserBeam() {
        assertFalse("bấm chính phím cách", LaserBeam.fires(100.0, 200.0, 300.0, 240.0, 150.0, 220.0))
        assertTrue(LaserBeam.fires(100.0, 200.0, 300.0, 240.0, 150.0, 120.0))
        assertEquals(0.0, LaserBeam.reach(0), 0.0); assertEquals(1.0, LaserBeam.reach(LaserBeam.TRAVEL_MS), 0.0)
        assertEquals(1.0, LaserBeam.alpha(10), 0.0); assertEquals(0.0, LaserBeam.alpha(LaserBeam.DURATION_MS), 0.0)
    }

    @Test fun glitchSlices() {
        assertEquals(0, GlitchFx.step(0)); assertEquals(3, GlitchFx.step(119)); assertEquals(GlitchFx.STEPS, GlitchFx.step(120))
        assertEquals(GlitchFx.STEPS, GlitchFx.step(-1))
        val out = DoubleArray(3 * GlitchFx.SLICES)
        for (v in 0 until GlitchFx.VARIANTS) for (s in 0 until GlitchFx.STEPS) {
            GlitchFx.slices(s, v, out)
            for (k in 0 until GlitchFx.SLICES) {
                assertTrue(out[3 * k] >= 0 && out[3 * k] + out[3 * k + 1] <= 1 + 1e-9)
                assertTrue(abs(out[3 * k + 2]) <= 1)
            }
        }
        GlitchFx.slices(1, 2, out)
        assertArrayEquals(GLITCH_1_2, out, 1e-4)
        assertTrue(GlitchFx.MAX_SHIFT <= 4.0)
    }

    // MARK: Chữ bay

    @Test fun flyingLetterGlyph() {
        assertEquals("á", FlyingLetters.glyph("hoa", "hoá", "s"))
        assertEquals("á", FlyingLetters.glyph("hoan", "hoán", "s"))
        assertEquals("ơ", FlyingLetters.glyph("tuong", "tương", "w"))
        assertEquals("a", FlyingLetters.glyph("", "a", "a"))
        assertEquals("A", FlyingLetters.glyph("", "A", "A"))
        assertEquals("đ", FlyingLetters.glyph("d", "đ", "d"))
        assertEquals("s", FlyingLetters.glyph("á", "as", "s"))
        assertEquals(".", FlyingLetters.glyph("abc", "", "."))
        assertEquals("😂", FlyingLetters.glyph("", "", "😂"))
        assertNull(FlyingLetters.glyph("", "", " "))
        assertNull(FlyingLetters.glyph("", "", "ab"))
        assertNull(FlyingLetters.glyph("abc", "abc", "x"))
        assertNull(FlyingLetters.glyph("", "", null))
        for (s in 0 until 50) { assertTrue(abs(FlyingLetters.drift(s)) <= 12); assertTrue(abs(FlyingLetters.spin(s)) <= 0.3) }
        assertArrayEquals(doubleArrayOf(LETTER_DRIFT_5, LETTER_SPIN_5), doubleArrayOf(FlyingLetters.drift(5), FlyingLetters.spin(5)), 1e-4)
    }

    // MARK: Hạt cát

    @Test fun sandPileCapsSlopeAndSinks() {
        val p = SandPile(390.0)
        assertEquals(130, p.columns)
        assertTrue(p.isEmpty)
        repeat(2000) { p.deposit(195.0) }
        assertTrue(p.maxHeight <= SandPile.MAX_HEIGHT + 1e-9)
        assertTrue("đống lan sang hai bên", p.heights[p.column(195.0) - 5] > 0 && p.heights[p.column(195.0) + 5] > 0)
        for (c in 1 until p.columns) assertTrue(abs(p.heights[c] - p.heights[c - 1]) <= SandPile.SLOPE + SandPile.GRAIN + 1e-9)
        repeat(5000) { p.deposit((it * 37 % 390).toDouble()) }
        assertTrue("trần chiều cao — không che phím đáy", p.maxHeight <= SandPile.MAX_HEIGHT + 1e-9)
        assertEquals(1.0, SandPile.sinkFactor(0), 0.0)
        assertEquals(1.0, SandPile.sinkFactor(SandPile.IDLE_MS), 0.0)
        assertEquals(0.5, SandPile.sinkFactor(SandPile.IDLE_MS + SandPile.SINK_MS / 2), 1e-9)
        assertEquals(0.0, SandPile.sinkFactor(SandPile.IDLE_MS + SandPile.SINK_MS), 0.0)
        p.scale(0.5); assertTrue(p.maxHeight <= SandPile.MAX_HEIGHT / 2 + 1e-9)
        p.clear(); assertTrue(p.isEmpty)
        assertEquals(0.0, SandPile.fallTime(0.0), 0.0)
        assertEquals(Math.sqrt(2 * 200 / 1800.0), SandPile.fallTime(200.0), 1e-12)
        assertEquals(0, p.column(-5.0)); assertEquals(129, p.column(1e6))
        for (s in 0 until 30) for (i in 0 until SandPile.GRAINS_PER_TAP) assertTrue(abs(SandPile.spread(i, s)) <= 8)
        assertEquals(SAND_SPREAD_1_4, SandPile.spread(1, 4), 1e-4)
    }

    companion object {
        // Số tham chiếu chéo iOS KeyEffectTests (đợt 3) — giữ y hệt.
        const val PLASMA_Y1 = 2.0967
        const val PLASMA_Y4 = 3.5963
        val GLITCH_1_2 = doubleArrayOf(0.8370, 0.1115, 0.9431, 0.2958, 0.2180, -0.2651, 0.5173, 0.1869, -0.4911)
        const val LETTER_DRIFT_5 = 5.2726
        const val LETTER_SPIN_5 = 0.2413
        const val SAND_SPREAD_1_4 = -4.2766
    }
}
