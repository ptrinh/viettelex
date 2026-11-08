package com.viettelex.keyboard

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.lang.management.ManagementFactory
import kotlin.math.abs
import kotlin.math.hypot

/**
 * Đợt 2 hiệu ứng phím (Phil 19/10/2026): Nháy sáng, Matrix, Tia sét, Emoji theo chữ, Hoa đào / mai, Lửa combo,
 * Mực loang, Sóng nước, Tuyết rơi — song sinh iOS KeyEffectTests (extension đợt 2), CÙNG số tham chiếu.
 * Phần View (app/.../KeyEffectView) không chạy được trên JVM: test các hàm thuần quyết định hành vi.
 */
class KeyEffectFxTests {
    @Test fun bandsAndZOrder() {
        assertEquals(listOf(KeyEffect.MATRIX, KeyEffect.INK, KeyEffect.WAVE, KeyEffect.STRING, KeyEffect.FISHFEED),   // cá bơi sau hàng phím
            KeyEffect.entries.filter { it.band == KeyEffectBand.BELOW_KEYS })
        // Rung dây: dây ở khe hàng — trên nền + hoạ tiết dây đàn (nền view gốc), dưới phím.
        assertEquals(0, KeyEffectBand.insertIndex(KeyEffect.STRING.band, keyboardIndex = 0, balloonIndex = 4))
        // View gốc IME: [keyboard=0, strip=1, (foreground), trail, balloon=4]. Dưới phím ⇒ chèn TRƯỚC keyboard
        // (trên nền + ảnh nền — vẽ trong onDraw của view gốc trước mọi con); trên phím ⇒ ngay dưới balloon.
        assertEquals(0, KeyEffectBand.insertIndex(KeyEffect.MATRIX.band, keyboardIndex = 0, balloonIndex = 4))
        assertEquals(4, KeyEffectBand.insertIndex(KeyEffect.LIGHTNING.band, keyboardIndex = 0, balloonIndex = 4))
        assertEquals(4, KeyEffectBand.insertIndex(KeyEffect.FLASH.band, keyboardIndex = 0, balloonIndex = 4))
        for (e in KeyEffect.entries) if (e != KeyEffect.NONE) assertTrue(e.id, e.isPlus)
    }

    /** Đèn lồng / Sương ma (bộ theme đủ món) — mốc chung iOS testLanternSmokeModel. */
    @Test fun lanternSmokeModel() {
        for (e in listOf(KeyEffect.LANTERN, KeyEffect.SMOKE)) {
            assertTrue("$e", e.isParticle && e.usesGlow && e.isPlus)
            assertEquals(KeyEffectBand.ABOVE_KEYS, e.band)
            assertTrue(e.fixedColors.isNotEmpty())
            for (v in 0 until e.variantCount) { assertTrue("$e bay LÊN", e.trajectory(v).dy < 0); assertTrue(e.trajectory(v).sway > 0) }
        }
        assertFalse(KeyEffect.HEART.usesGlow)
        assertTrue(KeyEffect.LANTERN.trajectory(0).dy < -50)
        assertTrue(KeyEffect.LANTERN.trajectory(0).scaleTo < KeyEffect.LANTERN.trajectory(0).scaleFrom)
        assertTrue(KeyEffect.SMOKE.trajectory(0).scaleTo > KeyEffect.SMOKE.trajectory(0).scaleFrom)
        assertEquals(10.0, KeyEffect.LANTERN.trajectory(3).dx, 1e-9)
        assertEquals(-66.0, KeyEffect.LANTERN.trajectory(3).dy, 1e-9)
        assertEquals(1.1, KeyEffect.SMOKE.trajectory(5).duration, 1e-9)
        assertEquals(4, GlowSprite.positions(KeyEffect.LANTERN).size)
        assertEquals(GlowSprite.positions(KeyEffect.SMOKE).size, GlowSprite.alphas(KeyEffect.SMOKE).size)
        assertEquals("Lantern glow", L10nTable.EN["Đèn lồng"]); assertEquals("Spooky mist", L10nTable.EN["Sương ma"])
        // Pool: gõ 200 phím vẫn ≤ trần hạt.
        val sim = KeyEffectParticles(); sim.configure(KeyEffect.SMOKE)
        for (i in 0 until 200) sim.spawn(i.toFloat(), 0f, i * 10L)
        assertTrue(sim.aliveCount() <= KeyEffectPool.CAP)
    }

    @Test fun fixedColorsAndSnow() {
        assertArrayEquals(intArrayOf(0xFF8FB1, 0xFFC93C), KeyEffect.BLOSSOM.fixedColors)
        assertArrayEquals(intArrayOf(0xFFFFFF), KeyEffect.SNOW.fixedColors)
        assertArrayEquals(intArrayOf(0x00FF41), KeyEffect.MATRIX.fixedColors)
        assertEquals(0, KeyEffect.HEART.fixedColors.size)
        assertTrue(KeyEffect.SNOW.particlesPerTap in 3..5)
        for (v in 0 until KeyEffect.SNOW.variantCount) {
            assertTrue("tuyết rơi XUỐNG", KeyEffect.SNOW.trajectory(v).dy > 0)
            assertTrue(KeyEffect.SNOW.trajectory(v).sway > 0)
            assertTrue("hoa bay lên", KeyEffect.BLOSSOM.trajectory(v % KeyEffect.BLOSSOM.variantCount).dy < 0)
        }
        // Lắc ngang: giữa quỹ đạo x lệch khỏi đường thẳng.
        val sim = KeyEffectParticles(); sim.configure(KeyEffect.SNOW)
        sim.spawn(100f, 100f, 0L)
        assertTrue(sim.sample(0, 300L, 1f))
        assertTrue(sim.sy > 100f)
    }

    // MARK: Nháy sáng

    @Test fun flashRateCapAndGentleCurve() {
        assertTrue(FlashPulse.PEAK <= 0.25)
        assertTrue(FlashPulse.MIN_INTERVAL_MS >= 60)
        val f = FlashPulse()
        assertTrue(f.trigger(10_000))
        assertFalse("< 60 ms ⇒ bỏ qua", f.trigger(10_030))
        assertFalse(f.trigger(10_059))
        assertTrue(f.trigger(10_060))
        val g = FlashPulse()
        val n = (0 until 200).count { g.trigger(it * 10L) }
        assertTrue("200 phím / 2 s ⇒ ≤ 34 xung, có $n", n <= 34)
        assertEquals(FlashPulse.PEAK, FlashPulse.alpha(0), 1e-12)
        assertEquals(0.0, FlashPulse.alpha(FlashPulse.DURATION_MS), 0.0)
        assertEquals(0.0, FlashPulse.alpha(-1), 0.0)
        var prev = 1.0
        for (k in 0..12) { val a = FlashPulse.alpha(k * 10L); assertTrue(a <= prev); prev = a }
    }

    // MARK: Tia sét

    @Test fun lightningBoltParity() {
        val out = DoubleArray(2 * (LightningBolt.SEGMENTS + 1))
        LightningBolt.points(120.0, 2, out)
        // Cùng số với iOS KeyEffectTests.testLightningBoltDeterministicParity.
        val ref = doubleArrayOf(9.434043, -120.0, 4.295992, -102.857143, 11.736669, -85.714286, -4.608798, -68.571429,
            6.767128, -51.428571, 8.904401, -34.285714, -3.299798, -17.142857, 0.0, 0.0)
        for (i in ref.indices) assertEquals("#$i", ref[i], out[i], 1e-5)
        for (v in 0 until LightningBolt.VARIANTS) {
            LightningBolt.points(200.0, v, out)
            assertEquals(-200.0, out[1], 0.0); assertEquals(0.0, out[out.size - 2], 0.0)
            for (i in 0 until out.size step 2) assertTrue(abs(out[i]) <= 40)
        }
    }

    @Test fun shardsTileTheKeyExactly() {
        for ((w, h) in listOf(35.0 to 42.0, 180.0 to 42.0, 50.0 to 50.0)) {
            val ps = LightningShards.pieces(w, h)
            assertTrue(ps.size in 4..6)
            assertEquals("các mảnh ghép kín đúng phím", w * h, ps.sumOf { it.area }, 1e-6)
            for (p in ps) {
                assertTrue(p.area > 0)
                for (i in p.xs.indices) { assertTrue(abs(p.xs[i]) <= w / 2 + 1e-9); assertTrue(abs(p.ys[i]) <= h / 2 + 1e-9) }
            }
        }
        for (i in 0 until LightningShards.COUNT) assertEquals(1.0, hypot(LightningShards.dirX(i), LightningShards.dirY(i)), 1e-9)
        // Phím thật "hiện lại ngay": mảnh vỡ + ánh chớp xong trong < 0,4 s (overlay hết vẽ).
        assertTrue(LightningShards.DELAY_MS + LightningShards.DURATION_MS < 400)
        assertTrue(LightningBolt.DURATION_MS in 150..220)
    }

    // MARK: Matrix

    @Test fun matrixClockIdleStopAndColumnsParity() {
        val c = MatrixClock()
        assertTrue(c.poke(1000)); assertFalse(c.poke(2000))
        assertEquals(MatrixRain.IDLE_AFTER_MS - 1000, c.idleRemaining(3000))
        assertEquals(2, c.presses)
        assertEquals("đang gõ: đủ sáng", 1.0, c.fade(3000), 0.0)
        assertTrue("mờ dần", c.fade(2000 + MatrixRain.IDLE_AFTER_MS + 200) in 0.0..0.99)
        assertTrue("nghỉ ⇒ hệ số ≤ 0: dừng hẳn, không hẹn khung hình",
            c.fade(2000 + MatrixRain.IDLE_AFTER_MS + MatrixRain.FADE_OUT_MS) <= 0.0)
        c.stop(); assertFalse(c.running)
        assertTrue(c.poke(10_000))
        assertTrue(MatrixRain.maxOpacity(false) < MatrixRain.maxOpacity(true))
        assertEquals(0.55, MatrixRain.intensity(1), 1e-9)
        assertEquals(1.0, MatrixRain.intensity(50), 0.0)
        val c0 = MatrixRain.column(0); val c5 = MatrixRain.column(5)
        assertEquals(0, c0.strip); assertEquals(2.4423575, c0.duration, 1e-6)
        assertEquals(0.2594339, c0.phase, 1e-6); assertEquals(-1.7847257, c5.jitter, 1e-6)
        assertEquals(1.0, MatrixRain.rowAlpha(MatrixRain.ROWS - 1), 1e-9)
        assertTrue(MatrixRain.rowAlpha(0) < 0.1)
        assertTrue('đ' in MatrixRain.GLYPHS)
        assertTrue(MatrixRain.columnCount(1366.0) <= 28)
        // Cột rơi trong vùng [−dải, cao].
        for (t in 0L until 5000L step 37) {
            val y = MatrixRain.columnTop(c0, t, 260.0)
            assertTrue(y >= -MatrixRain.STRIP_HEIGHT - 1e-9 && y <= 260.0 + 1e-9)
        }
    }

    // MARK: Lửa combo

    @Test fun comboMeterLevelsAndCooldown() {
        val m = ComboMeter()
        for (i in 0 until 10) assertEquals(0, m.press(i * 500L))
        val levels = (0 until 20).map { m.press(10_000 + it * 125L) }
        assertEquals(3, levels.last())
        assertEquals(levels.sorted(), levels)
        assertTrue(1 in levels && 2 in levels)
        val last = 10_000 + 19 * 125L
        assertTrue(m.level(last + 900) > 0)
        assertEquals(0, m.level(last + 1100))
        assertEquals("sau nghỉ: đếm lại", 0, m.press(20_000))
        assertEquals(4, ComboMeter.SCALES.size)
        assertArrayEquals(ComboMeter.SCALES.sortedArray(), ComboMeter.SCALES, 0.0)
        // Lửa = hạt vector pool: mức 3 ⇒ 3 hạt, cỡ ×1,35.
        val sim = KeyEffectParticles(); sim.configure(KeyEffect.COMBO)
        sim.spawn(0f, 0f, 0L, count = 1, scale = 0.8f)
        assertEquals(1, sim.aliveCount())
        sim.spawn(0f, 0f, 0L, count = 3, scale = 1.35f)
        assertEquals(4, sim.aliveCount())
    }

    // MARK: Emoji theo chữ

    @Test fun emojiWordsLookup() {
        assertTrue(EmojiWords.entries.size in 30..60)
        assertEquals("😂", EmojiWords.lookup("haha", null))
        assertEquals("😂", EmojiWords.lookup("Haha!", null))
        assertEquals("❤️", EmojiWords.lookup("yeu", null))
        assertEquals("❤️", EmojiWords.lookup("yêu", "em"))
        assertEquals("🎉", EmojiWords.lookup("mừng", "chúc"))
        assertEquals("🎉", EmojiWords.lookup("nhật", "Sinh"))
        assertEquals("🙏", EmojiWords.lookup("ơn", "cảm"))
        assertEquals("🙏", EmojiWords.lookup("on", "cam"))
        assertEquals("😴", EmojiWords.lookup("ngủ", "buồn"))
        assertEquals("😴", EmojiWords.lookup("ngủ", null))
        assertNull("strict: ngu ≠ ngủ", EmojiWords.lookup("ngu", null))
        assertEquals("🧧", EmojiWords.lookup("mới", "năm"))
        assertEquals("🧧", EmojiWords.lookup("tết", null))
        assertNull(EmojiWords.lookup("nhà", null))
        assertNull(EmojiWords.lookup("", null))
        assertNull(EmojiWords.lookup("fuck", null))
        assertNull("từ trước tục ⇒ không", EmojiWords.lookup("haha", "đm"))
        val pair = SensitiveWords.pairs.entries.first()
        assertTrue(EmojiWords.blocked(pair.value.first(), pair.key))
        for (en in EmojiWords.entries) for (w in en.form.split(' ')) assertFalse(en.form, w in SensitiveWords.set)
        // Cùng bảng iOS (số mục + emoji khác nhau).
        assertEquals(56, EmojiWords.entries.size)
        assertEquals(17, EmojiWords.distinctEmojis.size)
    }

    // MARK: số đo (JVM) — phần mô hình mỗi phím / mỗi khung hình; phần canvas đo trên máy.

    @Test fun perKeyCostsAndAllocationFree() {
        val bean = ManagementFactory.getThreadMXBean() as com.sun.management.ThreadMXBean
        val tid = Thread.currentThread().id
        val out = DoubleArray(2 * (LightningBolt.SEGMENTS + 1))
        val combo = ComboMeter(); val flash = FlashPulse(); val clock = MatrixClock()
        val cols = Array(MatrixRain.columnCount(402.0)) { MatrixRain.column(it) }
        var sink = 0.0
        // làm nóng
        repeat(20_000) {
            LightningBolt.points(100.0 + it % 4 * 50, it % 6, out); combo.press(it * 30L); flash.trigger(it * 30L)
            clock.poke(it * 30L); for (c in cols) sink += MatrixRain.columnTop(c, it * 16L, 260.0)
        }
        val n = 20_000
        val a0 = bean.getThreadAllocatedBytes(tid)
        var t0 = System.nanoTime()
        for (i in 0 until n) LightningBolt.points(100.0 + i % 4 * 50, i % 6, out)
        val boltNs = (System.nanoTime() - t0).toDouble() / n
        t0 = System.nanoTime()
        for (i in 0 until n) sink += combo.press(1_000_000L + i * 30L)
        val comboNs = (System.nanoTime() - t0).toDouble() / n
        t0 = System.nanoTime()
        for (i in 0 until n) if (flash.trigger(2_000_000L + i * 30L)) sink++
        val flashNs = (System.nanoTime() - t0).toDouble() / n
        t0 = System.nanoTime()
        for (i in 0 until n) { clock.poke(3_000_000L + i * 30L); for (c in cols) sink += MatrixRain.columnTop(c, i * 16L, 260.0) }
        val matrixNs = (System.nanoTime() - t0).toDouble() / n
        val bytes = bean.getThreadAllocatedBytes(tid) - a0
        t0 = System.nanoTime()
        val words = listOf("haha", "không", "biết", "cảm", "ơn", "chúc", "mừng", "tết", "nhà", "ok")
        for (i in 0 until n) if (EmojiWords.lookup(words[i % words.size], words[(i + 9) % words.size]) != null) sink++
        val emojiNs = (System.nanoTime() - t0).toDouble() / n
        println("KEYFX-ANDROID lightning bolt/key=%.3f µs | combo press/key=%.3f µs | flash trigger/key=%.3f µs | matrix frame (%d cột)=%.3f µs | emoji lookup/ranh giới=%.3f µs | cấp phát bolt+combo+flash+matrix = %d B / %d vòng (%.0f)"
            .format(boltNs / 1000, comboNs / 1000, flashNs / 1000, cols.size, matrixNs / 1000, emojiNs / 1000, bytes, n, sink % 7))
        assertTrue("không cấp phát mỗi phím / khung hình: $bytes B", bytes < 4096)
        assertTrue(boltNs < 50_000 && comboNs < 50_000 && matrixNs < 100_000 && emojiNs < 100_000)
    }

    /**
     * "Sao băng" (theme Vũ trụ): MỘT hạt / lần bấm, bay CHÉO lên-phải đúng góc của hình (không xoay), tắt trong 0,5 s;
     * hình giọt một đa giác — số tham chiếu GIỐNG HỆT iOS KeyEffectTests.testMeteorModelAndShapeParity.
     */
    @Test fun meteorParity() {
        val m = KeyEffect.METEOR
        assertTrue(m.isParticle); assertTrue(m.isPlus); assertEquals(KeyEffectBand.ABOVE_KEYS, m.band)
        assertEquals(1, m.particlesPerTap)
        assertArrayEquals(intArrayOf(0xFFE7A0), m.fixedColors)
        val ref = arrayOf(doubleArrayOf(45.900289, -32.080578), doubleArrayOf(52.457473, -36.663517))
        for (v in 0 until m.variantCount) {
            val t = m.trajectory(v)
            assertEquals(ref[v][0], t.dx, 1e-5); assertEquals(ref[v][1], t.dy, 1e-5)
            assertEquals("vệt không xoay", 0.0, t.rotation, 0.0)
            assertEquals("bay đúng hướng vệt", MeteorStreak.ANGLE, Math.atan2(t.dy, t.dx), 1e-9)
            assertEquals(0.5, t.duration, 1e-9)
        }
        val want = doubleArrayOf(1.374882, 1.967155, 2.174260, 1.016165, 2.391047, -0.207105, 1.967155, -1.374882,
            1.016165, -2.174260, -0.207105, -2.391047, -1.374882, -1.967155, -21.310848, 14.894554)
        assertArrayEquals(want, MeteorStreak.polygon(), 1e-5)
        // Sim hạt: một lần bấm = một hạt, hết 0,5 s thì tắt.
        val sim = KeyEffectParticles(); sim.configure(m)
        sim.spawn(100f, 100f, 0L)
        assertEquals(1, sim.aliveCount())
        assertTrue(sim.sample((0 until sim.capacity).first { sim.sample(it, 250L, 1f) }, 250L, 1f))
        for (s in 0 until sim.capacity) sim.sample(s, 600L, 1f)
        assertEquals(0, sim.aliveCount())
    }
}
