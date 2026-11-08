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
import kotlin.math.hypot

/**
 * Theme "AI" (11/2026): hiệu ứng Token AI ([TokenStream] + [ShimmerGate]), Mắt AI ([AIEye], nhân vật
 * [BuddyCharacter.AI]), motif "neural", "borderFx":"aurora" ([AuroraFx]), âm "ai". Song sinh iOS AIThemeTests — CÙNG
 * số tham chiếu (phần View không chạy trên JVM: test hàm thuần).
 */
class AIThemeTests {
    private var savedPaywall = false
    @Before fun setUp() { savedPaywall = PlusGate.paywallEnabled; PlusGate.paywallEnabled = false }
    @After fun tearDown() { PlusGate.paywallEnabled = savedPaywall; PlusGate.install({ null }, debugBuild = false) }

    // ---- Token AI

    @Test fun tokensEffectIdAndHooks() {
        assertEquals(KeyEffect.SEA.ordinal + 1, KeyEffect.TOKENS.ordinal)   // thêm sau Biển (Night Club theo sau)
        assertEquals("tokens", KeyEffect.TOKENS.id)
        assertEquals(KeyEffect.TOKENS, KeyEffect.of("tokens"))
        assertTrue(KeyEffect.TOKENS.isPlus)
        assertTrue(KeyEffect.TOKENS.isQueued)
        assertTrue(KeyEffect.TOKENS.needsComposeDiff)
        assertFalse(KeyEffect.TOKENS.needsBoundaryWord)
        assertFalse(KeyEffect.TOKENS.isParticle)
        assertEquals(KeyEffectBand.ABOVE_KEYS, KeyEffect.TOKENS.band)
        assertEquals("AI tokens", L10nTable.EN["Token AI"])
        assertTrue("tokens" in ThemeExtraIds.EFFECTS)
    }

    @Test fun tokenChipCountAndCaps() {
        val want = mapOf("b" to 3, "a" to 4, "đ" to 4, "á" to 5, "ế" to 6, "ợ" to 6, "ơ" to 5, "" to 3, "7" to 4, "," to 3)
        for ((g, n) in want) assertEquals(g, n, TokenStream.chipCount(g))
        for (c in "aăâbcdđeêghiklmnoôơpqrstuưvxyáàảãạấầẩẫậếềểễệốồổỗộớờởỡợứừửữựíìỉĩị") {
            val n = TokenStream.chipCount(c.toString())
            assertTrue("$c", n in TokenStream.MIN_CHIPS..TokenStream.MAX_CHIPS)
        }
        assertEquals(24, TokenStream.CAP)
        assertEquals(TokenStream.POOL * TokenStream.MAX_CHIPS, TokenStream.CAP)
        assertEquals(0.08 + 5 * 0.035 + 0.55, TokenStream.lifetime, 1e-9)
        assertEquals(3, TokenStream.COLORS.size)
    }

    /** Đường bay mốc chung iOS testTokenPathParity: phím (100,150) → đích (195,22), 5 chip, khung 390×260. */
    @Test fun tokenPathParity() {
        val want = arrayOf(doubleArrayOf(88.0, 150.0, 138.2776, 83.3063), doubleArrayOf(94.0, 150.0, 133.7842, 77.5446),
            doubleArrayOf(100.0, 150.0, 128.9507, 72.2329), doubleArrayOf(106.0, 150.0, 123.7753, 67.4180),
            doubleArrayOf(112.0, 150.0, 118.2602, 63.1492))
        val s = DoubleArray(2); val c = DoubleArray(2)
        for (i in 0 until 5) {
            TokenStream.start(100.0, 150.0, i, 5, 390.0, 260.0, s)
            TokenStream.control(s[0], s[1], 195.0, 22.0, i, 5, 390.0, 260.0, c)
            assertEquals(want[i][0], s[0], 1e-4); assertEquals(want[i][1], s[1], 1e-4)
            assertEquals(want[i][2], c[0], 1e-4); assertEquals(want[i][3], c[1], 1e-4)
        }
        TokenStream.control(300.0, 200.0, 300.0, 20.0, 0, 3, 390.0, 260.0, c)
        assertEquals(304.2, c[0], 1e-4); assertEquals(110.0, c[1], 1e-4)
        TokenStream.control(380.0, 5.0, 10.0, 5.0, 2, 3, 390.0, 260.0, c)
        assertEquals(195.0, c[0], 1e-4); assertEquals(2.0, c[1], 1e-4)
        // Hai đầu đường cong đúng điểm đầu / đích.
        val p = DoubleArray(2)
        TokenStream.point(1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 0.0, p); assertEquals(1.0, p[0], 0.0); assertEquals(2.0, p[1], 0.0)
        TokenStream.point(1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 1.0, p); assertEquals(5.0, p[0], 0.0); assertEquals(6.0, p[1], 0.0)
        assertEquals(0.25, TokenStream.ease(0.5), 1e-12)
        assertEquals(0.0, TokenStream.alpha(-0.1), 0.0); assertEquals(1.0, TokenStream.alpha(0.5), 0.0)
        assertEquals(0.0, TokenStream.alpha(1.0), 1e-12); assertEquals(TokenStream.END_SCALE, TokenStream.scale(1.0), 1e-12)
    }

    /** Mọi điểm trên mọi đường bay (phím sát mép / góc, đích ngoài khung) nằm TRONG bàn phím — bao lồi Bézier. */
    @Test fun tokenPathsStayInsideKeyboard() {
        val w = 390.0; val h = 260.0
        val s = DoubleArray(2); val c = DoubleArray(2); val t = DoubleArray(2); val p = DoubleArray(2)
        val keys = listOf(0.0 to 0.0, 390.0 to 0.0, 0.0 to 260.0, 390.0 to 260.0, 195.0 to 130.0, 20.0 to 240.0, 370.0 to 10.0)
        val targets = listOf(195.0 to 22.0, -50.0 to -50.0, 500.0 to 10.0, 370.0 to 20.0, 10.0 to 250.0)
        for ((kx, ky) in keys) for ((tx, ty) in targets) for (n in 3..6) for (i in 0 until n) {
            TokenStream.clamp(tx, ty, w, h, t)
            TokenStream.start(kx, ky, i, n, w, h, s)
            TokenStream.control(s[0], s[1], t[0], t[1], i, n, w, h, c)
            for (k in 0..20) {
                TokenStream.point(s[0], s[1], c[0], c[1], t[0], t[1], k / 20.0, p)
                assertTrue("($kx,$ky)→($tx,$ty) #$i", p[0] >= TokenStream.INSET - 1e-9 && p[0] <= w - TokenStream.INSET + 1e-9)
                assertTrue("($kx,$ky)→($tx,$ty) #$i", p[1] >= TokenStream.INSET - 1e-9 && p[1] <= h - TokenStream.INSET + 1e-9)
            }
        }
    }

    /** Vệt sáng chỉ khi gợi ý đổi thật — mốc chung iOS testShimmerTriggersOnlyOnChange. */
    @Test fun shimmerTriggersOnlyOnChange() {
        val g = ShimmerGate()
        assertFalse("rỗng ⇒ không", g.update(emptyList(), 10.0))
        assertTrue(g.update(listOf("xin", "chào"), 10.0))
        assertFalse("y nguyên ⇒ không", g.update(listOf("xin", "chào"), 10.1))
        assertFalse("đổi quá dồn ⇒ bỏ", g.update(listOf("xin", "chào", "bạn"), 10.2))
        assertFalse("y nguyên (đã ghi lần bỏ) ⇒ không", g.update(listOf("xin", "chào", "bạn"), 20.0))
        assertTrue(g.update(listOf("cảm", "ơn"), 20.0))
        assertFalse(g.update(listOf("cảm", "ơn"), 30.0))
        assertFalse("về rỗng ⇒ không quét", g.update(emptyList(), 31.0))
        assertTrue("rỗng → có lại ⇒ quét", g.update(listOf("cảm", "ơn"), 32.0))
        g.reset(); assertTrue(g.update(listOf("cảm", "ơn"), 32.1))
        assertEquals(-0.35 * 300, ShimmerGate.left(0.0, 300.0), 1e-9)
        assertEquals(300.0, ShimmerGate.left(1.0, 300.0), 1e-9)
        assertEquals(0.3, ShimmerGate.DURATION, 0.0)
    }

    // ---- Mắt AI

    @Test fun aiBuddyCharacter() {
        assertEquals(BuddyCharacter.AI, BuddyCharacter.entries.last())
        assertEquals("ai", BuddyCharacter.AI.id)
        assertEquals(BuddyCharacter.AI, BuddyCharacter.of("ai"))
        assertTrue(BuddyCharacter.AI.isPlus)
        assertFalse(BuddyCharacter.AI.isRigged)
        assertNull(BuddyRig.rig(BuddyCharacter.AI))
        assertEquals(0.0, BuddyRig.checksum(BuddyCharacter.AI), 0.0)
        assertFalse(BuddyCharacter.AI in BuddyCharacter.RIGGED)
        assertEquals(BuddyCharacter.entries.filter { it != BuddyCharacter.OFF && it != BuddyCharacter.AI }, BuddyCharacter.RIGGED)
        assertEquals(BuddyStyle.VECTOR, BuddyStyle.SPRITE.resolved(BuddyCharacter.AI))
        assertEquals("AI Eye", L10nTable.EN["Mắt AI"])
        assertEquals(BuddyCharacter.AI, BuddyPolicy.active(BuddyCharacter.AI, plus = true))
        assertEquals(BuddyCharacter.OFF, BuddyPolicy.active(BuddyCharacter.AI, plus = false))
    }

    /** Đồng tử: đúng hướng, không bao giờ quá bán kính cho phép — mốc chung iOS testEyePupilClamp. */
    /** Khung cỡ gốc Mắt AI: cạnh round(strip × 0,86), tâm dọc = tâm dòng chữ gợi ý, kẹp trong strip. = iOS testEyeSlotCentersOnSuggestionRow. */
    @Test fun eyeSlotCentersOnSuggestionRow() {
        assertEquals(0.86, AIEye.SLOT_SIZE, 0.0)
        // strip, rowMid → top, side
        val cases = listOf(
            doubleArrayOf(44.0, 24.0, 5.0, 38.0), doubleArrayOf(44.0, 21.0, 2.0, 38.0), doubleArrayOf(44.0, 22.0, 3.0, 38.0),
            doubleArrayOf(52.0, 26.0, 3.5, 45.0), doubleArrayOf(40.0, 19.0, 2.0, 34.0),
            doubleArrayOf(35.0, 22.0, 9.0, 26.0),   // strip bị bóp: mắt nhỏ lại, vẫn đúng tâm
            doubleArrayOf(44.0, 10.0, 0.0, 22.0),   // chữ sát mép trên ⇒ cạnh tối thiểu nửa strip
            doubleArrayOf(44.0, 40.0, 22.0, 22.0))   // chữ sát đáy ⇒ kẹp đáy strip
        val out = DoubleArray(2)
        for (c in cases) {
            AIEye.slot(c[0], c[1], out)
            assertEquals("${c.toList()}", c[2], out[0], 1e-9)
            assertEquals("${c.toList()}", c[3], out[1], 1e-9)
            assertTrue(out[0] >= 0 && out[0] + out[1] <= c[0])
            if (c[1] - c[3] / 2 >= 0 && c[1] + c[3] / 2 <= c[0]) assertEquals(c[1], out[0] + out[1] / 2, 1.0)
        }
    }

    @Test fun eyePupilClamp() {
        val o = DoubleArray(2)
        AIEye.pupilOffset(0.0, 0.0, 60.0, 80.0, 10.0, o)
        assertEquals(5.0, o[0], 1e-9); assertEquals(20.0 / 3, o[1], 1e-9)
        AIEye.pupilOffset(0.0, 0.0, 600.0, 800.0, 10.0, o)
        assertEquals(6.0, o[0], 1e-9); assertEquals(8.0, o[1], 1e-9)
        AIEye.pupilOffset(5.0, 5.0, 5.0, 5.0, 10.0, o)
        assertEquals(0.0, o[0], 0.0); assertEquals(0.0, o[1], 0.0)
        assertEquals(5.72, AIEye.maxOffset(44.0), 1e-9)
        assertEquals(0.0, AIEye.maxOffset(-1.0), 0.0)
        val r = AIEye.maxOffset(44.0)
        for (a in 0 until 72) for (d in listOf(0.5, 10.0, 119.0, 120.0, 400.0, 5000.0)) {
            val tx = Math.cos(a * Math.PI / 36) * d; val ty = Math.sin(a * Math.PI / 36) * d
            AIEye.pupilOffset(0.0, 0.0, tx, ty, r, o)
            assertTrue(hypot(o[0], o[1]) <= r + 1e-9)
            assertTrue("cùng hướng", o[0] * tx + o[1] * ty >= 0)
            // mép đồng tử (bán kính PUPIL·side, co ≤ 1) luôn trong mống mắt
            assertTrue(hypot(o[0], o[1]) + AIEye.PUPIL * 44 <= AIEye.IRIS * 44 + 1e-9)
        }
        assertEquals(1.0, AIEye.pupilScale(0), 0.0); assertEquals(0.62, AIEye.pupilScale(9), 0.0)
        assertEquals(0.6, AIEye.glow(-3), 0.0); assertEquals(1.0, AIEye.glow(3), 0.0)
        for (lv in 1..3) {
            assertTrue(AIEye.pupilScale(lv) < AIEye.pupilScale(lv - 1))
            assertTrue(AIEye.glow(lv) > AIEye.glow(lv - 1))
        }
    }

    /** Nghỉ ⇒ thở đúng 3 nhịp rồi lim dim; lim dim = không hẹn gì nữa — mốc chung iOS testEyeIdleBreathingBounded. */
    @Test fun eyeIdleBreathingBounded() {
        assertEquals(AIEye.Phase.ACTIVE, AIEye.phase(0.0))
        assertEquals(AIEye.Phase.ACTIVE, AIEye.phase(1.999))
        assertEquals(AIEye.Phase.BREATHING, AIEye.phase(2.0))
        assertEquals(AIEye.Phase.BREATHING, AIEye.phase(6.79))
        assertEquals("2 + 1,6 × 3 (dấu phẩy động) ⇒ mốc sát trên 6,8", AIEye.Phase.RESTING, AIEye.phase(6.81))
        assertEquals(AIEye.Phase.RESTING, AIEye.phase(Double.MAX_VALUE))
        assertEquals(6.8, AIEye.BREATH_END, 1e-12)
        assertEquals(1.5, AIEye.nextDeadline(0.5)!!, 1e-12)
        assertEquals(1.8, AIEye.nextDeadline(5.0)!!, 1e-12)
        assertNull(AIEye.nextDeadline(6.81)); assertNull(AIEye.nextDeadline(1e9))
        // Thở: rest → đỉnh giữa nhịp → rest; ngoài 3 nhịp ⇒ rest (không phập phồng mãi).
        assertEquals(AIEye.REST_GLOW, AIEye.breathGlow(0.0), 1e-12)
        assertEquals(AIEye.REST_GLOW + AIEye.BREATH_AMP, AIEye.breathGlow(0.8), 1e-12)
        assertEquals(AIEye.REST_GLOW, AIEye.breathGlow(1.6), 1e-9)
        assertEquals(AIEye.REST_GLOW, AIEye.breathGlow(4.8), 0.0)
        assertEquals(AIEye.REST_GLOW, AIEye.breathGlow(100.0), 0.0)
        var s = 0.0
        while (s < 6.0) { val g = AIEye.breathGlow(s); assertTrue(g >= AIEye.REST_GLOW - 1e-12 && g <= 0.85 + 1e-12); s += 0.01 }
        // Đồng hồ: chuỗi gõ (chớp mỗi 9 phím), lim dim ⇒ chuỗi mới; mốc kế hữu hạn.
        val ck = AIEyeClock()
        assertEquals(AIEye.Phase.RESTING, ck.phase(0.0))
        assertNull(ck.nextDeadline(0.0))
        val blinks = (1..27).filter { AIEye.blinks(ck.press(100.0 + it * 0.1)) }
        assertEquals(listOf(9, 18, 27), blinks)
        assertEquals(102.7 + 2.0, ck.nextDeadline(102.7)!!, 1e-9)
        assertEquals(102.7 + 6.8, ck.nextDeadline(105.0)!!, 1e-9)
        assertNull(ck.nextDeadline(102.7 + 6.81))
        assertEquals(28, ck.press(104.0))
        assertEquals("lim dim ⇒ chuỗi mới", 1, ck.press(200.0))
        assertEquals(0.5, AIEye.openness(AIEye.Phase.RESTING), 0.0); assertEquals(1.0, AIEye.openness(AIEye.Phase.BREATHING), 0.0)
        assertEquals(0.0, AIEye.lidEdge(1.0, 10.0), 0.0); assertEquals(10.0, AIEye.lidEdge(0.5, 10.0), 0.0)
        assertEquals(20.0, AIEye.lidEdge(-1.0, 10.0), 0.0)
    }

    // ---- Theme AI, motif neural, aurora, âm

    @Test fun aiTheme() {
        assertEquals(KeyboardTheme.TIME_OF_DAY.ordinal + 1, KeyboardTheme.AI.ordinal)
        val spec = KeyboardTheme.AI.spec!!
        assertTrue(KeyboardTheme.AI.isPlus)
        assertEquals("AI", spec.nameVi); assertEquals("AI", spec.nameEn); assertEquals("AI", L10nTable.EN["AI"])
        assertEquals("tokens", spec.effect); assertEquals("ai", spec.sound); assertEquals("neon", spec.swipe)
        assertNull(spec.corner)
        for (dk in listOf(false, true)) {
            val p = KeyboardTheme.AI.palette(dk)!!
            assertTrue(p.auroraBorder); assertFalse(p.rainbowBorder)
            assertEquals(ThemeDecoration.NEURAL, p.decoration!!.motif)
            assertTrue(p.isDark)
            assertTrue("chữ trắng trên phím kính", ThemeColor.contrast(p.ink, p.keyFill) >= 4.5)
        }
        assertTrue(KeyboardTheme.AI.palette(false) == KeyboardTheme.AI.palette(true))
    }

    @Test fun auroraBorderParseAndPatch() {
        val base = """{"v":1,"name":{"vi":"x"},"light":{"key":"#000000","special":"#111111","ink":"#FFFFFF","accent":"#7C4DFF","borderFx":"aurora"}}"""
        val s = ThemeSpecParser.parse(base).spec!!
        assertEquals("aurora", s.light.borderFx)
        assertTrue(s.palette(false).auroraBorder); assertFalse(s.palette(false).rainbowBorder)
        assertTrue(s.canonical.contains(""""borderFx":"aurora""""))
        assertEquals(s.canonical, ThemeSpecParser.parse(s.canonical).spec!!.canonical)
        assertEquals("aurora", ThemeSpec.slots(s.palette(false)).borderFx)
        val on = ThemeSlots(borderFx = "aurora")
        val pal = KeyStyle(light = on, dark = on).applyPatch(KeyboardTheme.RGB.palette(true)!!, true)
        assertTrue(pal.auroraBorder); assertFalse("aurora thay cầu vồng", pal.rainbowBorder)
        // AuroraFx — mốc chung iOS testAuroraFxParity.
        assertEquals(0.32, AuroraFx.bandOpacity(0.0), 1e-12)
        assertEquals(0.08, AuroraFx.bandOpacity(28.0), 1e-12)
        assertEquals(0.0, AuroraFx.bandOpacity(56.0), 0.0); assertEquals(0.0, AuroraFx.bandOpacity(-1.0), 0.0)
        assertEquals(3, AuroraFx.BORDER_COLORS.size); assertEquals(4, AuroraFx.BAND_COLORS.size)
        assertEquals(1.0, AuroraFx.BORDER_STOPS.last(), 0.0); assertEquals(1.0, AuroraFx.BAND_STOPS.last(), 0.0)
    }

    /** Motif "neural": nút + dây trong ô ±0.5, chấm lưới trải ngang (|y| ≤ 0.45), cùng chiều quay, mốc chung iOS. */
    @Test fun neuralMotif() {
        assertTrue(ThemeDecoration.NEURAL in ThemeDecoration.MOTIFS)
        assertEquals(ThemeDecoration.MOTIFS.indexOf(ThemeDecoration.NEURAL) + 1, ThemeDecoration.MOTIFS.indexOf(ThemeDecoration.SWIRL))
        val subs = ThemeDecoration.shape(ThemeDecoration.NEURAL)
        assertEquals(12, subs.size)
        var sum = 0.0
        for ((k, sub) in subs.withIndex()) {
            val pts = ArrayList<DoubleArray>()
            pts.add(doubleArrayOf(sub.sx, sub.sy))
            for (g in sub.segs) { var i = 0; while (i < g.size) { pts.add(doubleArrayOf(g[i], g[i + 1])); i += 2 } }
            var a = 0.0
            for (i in pts.indices) { val p = pts[i]; val q = pts[(i + 1) % pts.size]; a += p[0] * q[1] - q[0] * p[1] }
            assertTrue("#$k chiều quay", a > 0)
            for (p in pts) {
                assertTrue("#$k", abs(p[1]) <= 0.45)
                if (k < 6) assertTrue("#$k nút/dây trong ô", abs(p[0]) <= 0.5)
                sum += p[0] * 3 + p[1] * 7
            }
        }
        assertEquals(20.15, sum, 1e-6)
    }

    @Test fun aiSynthBlip() {
        val golden = listOf(165.6180, 166.9984, 195.0660)
        for ((i, k) in KeySoundSynth.Kind.entries.withIndex()) {
            val wood = KeySoundSynth.samples(KeySoundStyle.WOOD, k); val a = KeySoundSynth.samples(KeySoundStyle.AI, k)
            assertTrue("$k", KeySoundSynth.rms(a) < KeySoundSynth.rms(wood))
            assertTrue("$k", a.maxOf { abs(it) } < wood.maxOf { abs(it) })
            assertTrue("$k", a.size.toDouble() / KeySoundSynth.SAMPLE_RATE < 0.061)
            assertEquals("$k", golden[i], a.sumOf { abs(it).toDouble() }, 0.01)
        }
        assertEquals(KeySoundStyle.CHIP.ordinal + 1, KeySoundStyle.AI.ordinal)
        assertTrue(KeySoundStyle.AI in KeySoundStyle.PRESETS)
        assertTrue("ai" in KeySoundStyle.PRESET_IDS)
        assertEquals("AI synth", L10nTable.EN["Synth AI"])
    }
}
