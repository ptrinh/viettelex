package com.viettelex.keyboard

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Theme "Ảo giác" (trippy) + hiệu ứng "Kính vạn hoa" (kaleido) + nền đổi sắc "hueflow" + âm "Mơ màng" (dream).
 * CÙNG SỐ tham chiếu với iOS PsychedelicThemeTests.swift.
 */
class PsychedelicThemeTests {
    private fun pts(a: DoubleArray) = (a.indices step 2).map { a[it] to a[it + 1] }

    // MARK: Kính vạn hoa

    @Test fun kaleidoIdAppendedAndCapped() {
        assertEquals(KeyEffect.DANCEFLOOR.ordinal + 1, KeyEffect.KALEIDO.ordinal)
        assertEquals(KeyEffect.DANCEFLOOR.ordinal + 1, KeyEffect.KALEIDO.ordinal)
        assertEquals("kaleido", KeyEffect.KALEIDO.id)
        assertTrue(KeyEffect.KALEIDO.isPlus)
        assertFalse(KeyEffect.KALEIDO.isQueued); assertFalse(KeyEffect.KALEIDO.isParticle)
        assertEquals(KeyEffectBand.ABOVE_KEYS, KeyEffect.KALEIDO.band)
        assertEquals(4, KaleidoBloom.POOL)
        assertEquals(8, KaleidoBloom.FOLDS)
        assertEquals("Kaleidoscope", L10nTable.EN["Kính vạn hoa"])
    }

    /** 8 nhánh: mỗi mảnh / đá đối xứng qua trục của nó; nhánh k+2 = nhánh k xoay 90°; mốc chung iOS. */
    @Test fun kaleidoGeometrySymmetric() {
        for (k in 0 until KaleidoBloom.FOLDS) {
            for (poly in listOf(KaleidoBloom.shard(k) to KaleidoBloom.axis(k),
                    KaleidoBloom.gem(k) to KaleidoBloom.axis(k) + Math.PI / KaleidoBloom.FOLDS)) {
                val (p, a) = poly
                // Phản chiếu qua trục (đường qua tâm theo hướng (sin a, −cos a)): tập điểm không đổi.
                val ux = Math.sin(a); val uy = -Math.cos(a)
                val orig = pts(p)
                for ((x, y) in orig) {
                    val d = x * ux + y * uy
                    val mx = 2 * d * ux - x; val my = 2 * d * uy - y
                    assertTrue("nhánh $k đối xứng", orig.any { Math.abs(it.first - mx) < 1e-9 && Math.abs(it.second - my) < 1e-9 })
                    assertTrue(Math.hypot(x, y) <= KaleidoBloom.EXTENT + 1e-9)
                }
            }
            val a = pts(KaleidoBloom.shard(k)); val b = pts(KaleidoBloom.shard((k + 2) % KaleidoBloom.FOLDS))
            val r = Math.PI / 2
            for (i in a.indices) {
                val x = a[i].first * Math.cos(r) - a[i].second * Math.sin(r); val y = a[i].first * Math.sin(r) + a[i].second * Math.cos(r)
                assertEquals(b[i].first, x, 1e-9); assertEquals(b[i].second, y, 1e-9)
            }
            assertEquals(k, KaleidoBloom.shardColor(k)); assertEquals((k + 4) % 8, KaleidoBloom.gemColor(k))
        }
        assertEquals(19.883842686965714, KaleidoBloom.shard(1)[0], 1e-9)
        assertEquals(-19.883842686965718, KaleidoBloom.shard(1)[1], 1e-9)
        assertEquals(7.270985214936708, KaleidoBloom.gem(3)[0], 1e-9)
        assertEquals(17.55371111771445, KaleidoBloom.gem(3)[1], 1e-9)
        var sum = 0.0
        for (k in 0 until KaleidoBloom.FOLDS) {
            val all = pts(KaleidoBloom.shard(k)) + pts(KaleidoBloom.gem(k))
            for ((i, p) in all.withIndex()) sum += (k + 1) * (p.first * 3 + p.second * 7) + i * 0.01 * p.first
        }
        assertEquals(-1636.6092194925936, sum, 1e-6)
    }

    /** Nở + xoay chậm + tan trong ~0,9 s; số chung iOS. */
    @Test fun kaleidoTimeline() {
        assertTrue(KaleidoBloom.DURATION in 0.8..1.0)
        assertTrue(KaleidoBloom.SPIN >= Math.toRadians(30.0) && KaleidoBloom.SPIN <= Math.toRadians(60.0))
        assertEquals(0.3681841563786009, KaleidoBloom.scale(0.05), 1e-12)
        assertEquals(0.90625, KaleidoBloom.scale(0.45), 1e-12)
        assertEquals(0.39269908169872414, KaleidoBloom.angle(0.45), 1e-12)
        assertEquals(0.3716563786008231, KaleidoBloom.alpha(0.05), 1e-12)
        assertEquals(0.225, KaleidoBloom.alpha(0.45), 1e-12)
        assertEquals(0.011111111111111098, KaleidoBloom.alpha(0.8), 1e-12)
        assertEquals(0.0, KaleidoBloom.alpha(0.9), 0.0); assertEquals(0.0, KaleidoBloom.alpha(-0.01), 0.0)
        assertEquals(1.0, KaleidoBloom.scale(5.0), 1e-12)
        // Không nháy: độ mờ đổi chiều đúng MỘT lần (lên rồi xuống).
        var turns = 0; var prev = 0.0; var rising = true
        for (i in 1..90) {
            val a = KaleidoBloom.alpha(i / 100.0)
            if (rising && a < prev - 1e-12) { rising = false; turns++ } else if (!rising && a > prev + 1e-12) turns++
            prev = a
        }
        assertEquals(1, turns)
    }

    /** Tâm kẹp để cả bông nằm trong khung — kể cả khung dời gốc (#151) hoặc hẹp hơn bông. */
    @Test fun kaleidoCenterInsideShiftedBounds() {
        val r = KaleidoBloom.EXTENT
        val cases = listOf(doubleArrayOf(0.0, -180.0, 390.0, 470.0), doubleArrayOf(0.0, 0.0, 390.0, 290.0), doubleArrayOf(10.0, 5.0, 60.0, 50.0))
        for (b in cases) {
            for ((x, y) in listOf(0.0 to -180.0, 390.0 to 290.0, 195.0 to 100.0, -50.0 to 1000.0, 17.0 to 21.0)) {
                val c = KaleidoBloom.center(x, y, b[0], b[1], b[2], b[3])
                if (b[2] > 2 * r) { assertTrue(c[0] - r >= b[0] - 1e-9); assertTrue(c[0] + r <= b[0] + b[2] + 1e-9) }
                else assertEquals(b[0] + b[2] / 2, c[0], 1e-9)
                if (b[3] > 2 * r) { assertTrue(c[1] - r >= b[1] - 1e-9); assertTrue(c[1] + r <= b[1] + b[3] + 1e-9) }
                else assertEquals(b[1] + b[3] / 2, c[1], 1e-9)
            }
        }
        val c = KaleidoBloom.center(17.0, -170.0, 0.0, -180.0, 390.0, 470.0)
        assertEquals(38.0, c[0], 1e-9); assertEquals(-142.0, c[1], 1e-9)
        val mid = KaleidoBloom.center(195.0, 100.0, 0.0, -180.0, 390.0, 470.0)
        assertEquals(195.0, mid[0], 1e-9); assertEquals(100.0, mid[1], 1e-9)
    }

    // MARK: Hue flow

    @Test fun hueFlowRateLimits() {
        assertTrue("một vòng ≥ 8 s", HueFlow.PERIOD >= HueFlow.MIN_CYCLE)
        assertEquals(8.0, HueFlow.MIN_CYCLE, 0.0)
        assertEquals(12.0, RainbowTuning.HUEFLOW_BORDER.period, 0.0)
        assertEquals(12.0, RainbowTuning.HUEFLOW_FILL.period, 0.0)
        assertTrue(1 / RainbowTuning.HUEFLOW_FILL.fullSpeed >= 8.0)
        assertTrue("≤ 3 lần chuyển sắc / giây", HueFlow.transitionsPerSecond <= 3.0)
        assertEquals(5.0 / 12.0, HueFlow.transitionsPerSecond, 1e-12)
        assertEquals(0.018897007742348607, HueFlow.maxLuminanceStep, 1e-9)
        assertTrue("sắc kề nhau cùng độ sáng — không nháy", HueFlow.maxLuminanceStep <= 0.025)
        assertEquals(HueFlow.FILL_HUES.first(), HueFlow.FILL_HUES.last())
        // Nền: độ đậm không đổi khi gõ / nghỉ (không có bước sáng nào).
        assertEquals(RainbowTuning.HUEFLOW_FILL.restAlpha, RainbowTuning.HUEFLOW_FILL.activeAlpha, 0.0)
        // Viền: một lần sáng lên (0,6 s) — không phải nhấp nháy.
        assertTrue(RainbowTuning.HUEFLOW_BORDER.fadeInTime >= 0.5)
        assertEquals(1.5, HueFlow.IDLE_AFTER, 0.0)
        val (cols, pos) = HueFlow.fillStops()
        assertEquals(11, cols.size); assertEquals(1.0, pos.last(), 0.0); assertEquals(0.5, pos[5], 1e-12)
    }

    /** Gõ ⇒ chạy (tốc độ 1/12 vòng/giây sau 0,8 s); nghỉ 1,5 s ⇒ giảm tốc tới dừng trong ≤ 1,5 s rồi KHÔNG còn khung. */
    @Test fun hueFlowStopsAfterIdle() {
        val d = RainbowDriver(RainbowTuning.HUEFLOW_FILL)
        assertEquals(1.5, d.clock.idleAfter, 0.0)
        assertTrue(d.poke(10.0))
        assertEquals(0.8, d.motion.ramp, 1e-12); assertEquals(1.0 / 12, d.motion.v1, 1e-12)
        assertEquals(HueFlow.FILL_ALPHA, d.alpha(10.3), 0.0)
        assertTrue(d.frame(11.0)); assertTrue(d.running)
        assertTrue(d.frame(11.6))   // 1,6 s sau phím ⇒ nghỉ, đang giảm tốc
        assertFalse(d.running)
        assertEquals(1.5, d.motion.ramp, 1e-9)
        val stopAt = d.motion.rampEnd
        assertTrue(stopAt - 10.0 <= 1.5 + 1.5 + 0.2)
        assertFalse("dừng hẳn ⇒ thôi hẹn khung", d.frame(stopAt + 0.01))
        val off = d.offset(stopAt + 5); assertEquals(off, d.offset(stopAt + 50), 1e-12)
        assertEquals(HueFlow.FILL_ALPHA, d.alpha(stopAt + 1), 0.0)
        // Tốc độ không bao giờ vượt một vòng / 8 s.
        var t = 10.0
        while (t < stopAt) { assertTrue(d.motion.velocity(t) <= 1 / HueFlow.MIN_CYCLE + 1e-12); t += 0.05 }
        // Mốc chung iOS: từ lệch 0,3 lúc 10 s, chạy đầy tới 20 s ⇒ 0,1.
        val m = RainbowMotion.rest(0.3).resumed(10.0, RainbowTuning.HUEFLOW_BORDER)
        assertEquals(0.09999999999999987, m.offset(20.0), 1e-9)
        val b = RainbowDriver(RainbowTuning.HUEFLOW_BORDER)
        b.poke(0.0)
        assertEquals(HueFlow.BORDER_ACTIVE, b.alpha(0.6), 1e-12)
        b.settle(1.0)
        assertEquals(HueFlow.BORDER_REST, b.alpha(2.6), 1e-12)
    }

    @Test fun hueFlowRipple() {
        assertEquals(74.25537109375, HueFlow.rippleRadius(0.8, 1), 1e-9)
        assertEquals(0.16542968749999998, HueFlow.rippleAlpha(0.8, 1), 1e-12)
        assertEquals(0.205078125, HueFlow.rippleAlpha(0.1, 0), 1e-12)
        assertEquals(109.78515625, HueFlow.rippleRadius(2.0, 2), 1e-9)
        assertEquals(0.0, HueFlow.rippleAlpha(0.2, 1), 0.0)
        assertEquals(0.0, HueFlow.rippleAlpha(HueFlow.rippleLifetime, 2), 0.0)
        assertEquals(2.2, HueFlow.rippleLifetime, 1e-12)
        assertEquals(0xFFCC00, HueFlow.rippleColor(1, 0)); assertEquals(0xFF3B30, HueFlow.rippleColor(0, 0))
        assertEquals(0x00C7BE, HueFlow.rippleColor(1, 1))
        // Gợn chậm: bán kính tăng đơn điệu, độ đậm ≤ đỉnh 0,35.
        var prev = -1.0
        for (i in 0..44) {
            val r = HueFlow.rippleRadius(i * 0.05, 0); assertTrue(r >= prev); prev = r
            assertTrue(HueFlow.rippleAlpha(i * 0.05, 0) <= HueFlow.RIPPLE_PEAK + 1e-12)
        }
        val g = HueFlow.RippleGate()
        assertFalse(g.trigger(1, 0.0))
        assertTrue(g.trigger(2, 0.0)); assertFalse(g.trigger(3, 0.5)); assertTrue(g.trigger(2, 0.9))
        assertEquals(2, g.fired)
    }

    // MARK: Theme

    @Test fun trippyTheme() {
        val t = KeyboardTheme.TRIPPY
        assertEquals(KeyboardTheme.NIGHTCLUB.ordinal + 1, KeyboardTheme.TRIPPY.ordinal)
        assertEquals("trippy", t.id); assertTrue(t.isPlus); assertTrue(t.isInteractive)
        assertEquals("Psychedelic", L10nTable.EN["Ảo giác"])
        val spec = t.spec!!
        assertEquals("Ảo giác", spec.nameVi); assertEquals("Psychedelic", spec.nameEn)
        assertEquals("kaleido", spec.effect); assertEquals("dream", spec.sound); assertEquals("rainbow", spec.swipe)
        for (dark in listOf(false, true)) {
            val p = t.palette(dark)!!
            assertTrue(p.hueFlow); assertFalse(p.rainbowBorder); assertFalse(p.auroraBorder)
            assertEquals(ThemeDecoration.SWIRL, p.decoration?.motif)
            assertTrue(p.isDark)
            assertTrue("phím trong mờ", (p.keyFill ushr 24) < 0xFF)
            val behind = ThemeColor.over(p.keyFill, p.bg)
            assertTrue("chữ trắng ≥ 4,5", ThemeColor.contrast(p.ink, behind) >= 4.5)
        }
        assertEquals(listOf("nightclub", "ai", "trippy"), ThemePicker.INTERACTIVE_ORDER.take(3))
    }

    @Test fun hueflowParseAndPatch() {
        val base = """{"v":1,"name":{"vi":"x"},"light":{"key":"#000000","special":"#111111","ink":"#FFFFFF","accent":"#7C4DFF","borderFx":"hueflow"}}"""
        val s = ThemeSpecParser.parse(base).spec!!
        assertEquals("hueflow", s.light.borderFx)
        assertTrue(s.palette(false).hueFlow); assertFalse(s.palette(false).rainbowBorder)
        assertTrue(s.canonical.contains(""""borderFx":"hueflow""""))
        assertEquals(s.canonical, ThemeSpecParser.parse(s.canonical).spec?.canonical)
        assertEquals("hueflow", ThemeSpec.slots(s.palette(false)).borderFx)
        assertTrue(ThemeSlots.BORDER_FX.contains("hueflow"))
    }

    /** Motif "swirl": một dải xoắn (đa giác đơn, chiều quay dương) + 4 chấm; |y| ≤ 0,45; mốc chung iOS. */
    @Test fun swirlMotif() {
        assertEquals(ThemeDecoration.MOTIFS.indexOf(ThemeDecoration.NEURAL) + 1, ThemeDecoration.MOTIFS.indexOf(ThemeDecoration.SWIRL))
        val subs = ThemeDecoration.shape(ThemeDecoration.SWIRL)
        assertEquals(5, subs.size)
        assertEquals(2 * (ThemeDecoration.SWIRL_STEPS + 1), 1 + subs[0].segs.size)
        var sum = 0.0
        for ((k, sub) in subs.withIndex()) {
            val p = mutableListOf(sub.sx to sub.sy)
            for (g in sub.segs) { var i = 0; while (i < g.size) { p.add(g[i] to g[i + 1]); i += 2 } }
            var a = 0.0
            for (i in p.indices) { val u = p[i]; val v = p[(i + 1) % p.size]; a += u.first * v.second - v.first * u.second }
            assertTrue("#$k chiều quay", a > 0)
            for (q in p) {
                assertTrue("#$k", Math.abs(q.second) <= 0.45)
                if (k == 0) assertTrue(Math.abs(q.first) <= 0.5)
                sum += q.first * 3 + q.second * 7
            }
        }
        assertEquals(-10.817954210730875, sum, 1e-6)
    }

    // MARK: Âm

    @Test fun dreamSound() {
        assertEquals(KeySoundStyle.CLUB.ordinal + 1, KeySoundStyle.DREAM.ordinal)
        assertTrue(KeySoundStyle.PRESETS.contains(KeySoundStyle.DREAM))
        assertEquals("Dreamy", L10nTable.EN["Mơ màng"])
        for ((k, want) in DREAM_GOLDEN) {
            val wood = KeySoundSynth.samples(KeySoundStyle.WOOD, k); val a = KeySoundSynth.samples(KeySoundStyle.DREAM, k)
            assertTrue(KeySoundSynth.rms(a) < KeySoundSynth.rms(wood))
            assertTrue((a.maxOf { Math.abs(it) }) < wood.maxOf { Math.abs(it) })
            assertTrue(a.size.toDouble() / KeySoundSynth.SAMPLE_RATE < 0.061)
            assertEquals("$k", want, a.sumOf { Math.abs(it).toDouble() }, 0.01)
        }
    }

    companion object {
        val DREAM_GOLDEN = listOf(KeySoundSynth.Kind.LETTER to 127.8460, KeySoundSynth.Kind.DELETE to 134.0004,
            KeySoundSynth.Kind.MODIFIER to 155.4833)
    }
}
