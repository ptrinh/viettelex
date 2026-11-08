package com.viettelex.keyboard

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs

/**
 * Theme Bóng đá: cụm cổ vũ, cú sút, túm cỏ, pháo + cờ, sân cỏ, âm "thump" + hò reo. Số tham chiếu CHUNG iOS
 * (iOS/KeyboardTests/FootballFxTests.swift) — đổi một bên phải đổi cả hai.
 */
class FootballFxTests {

    // MARK: cụm cổ vũ

    /** Gõ [text] (tách theo dấu cách; mảnh toàn "#"/số gõ từng ký hiệu) — true nếu ranh giới CUỐI bắn cụm cổ vũ. */
    private fun cheers(text: String): Boolean {
        val m = CheerWords.Matcher()
        var hit = false
        for (w in text.split(' ').filter { it.isNotEmpty() }) {
            hit = if (CheerWords.Matcher.isGlue(w)) {
                for (c in w) m.feed("", c.toString())
                m.feed("", end = true)
            } else m.feed(w, end = true)
        }
        return hit
    }

    private val yes = listOf("Việt Nam vô địch", "VN vô địch", "VNVĐ", "vnvd", "vnvđ", "VN number 1", "VN #1", "VN # 1", "Việt Nam số 1",
        "VN số 1", "Việt Nam number one", "Việt Nam #1", "vô địch", "vào", "goal", "GOAL", "gooool", "vàoooo",
        "VÀOOO", "goooal", "đi vào", "vô địch!", "Vào!!!")
    private val no = listOf("vao", "vo dich", "vô", "địch", "vàobờ", "vn", "việt nam", "number one", "#1", "goals", "số 1", "vào nhà",
        "vnvđx", "gool", "Việt Nam số 2", "VN #10", "vô đich", "")

    @Test fun cheerTable() {
        assertEquals(listOf("việt nam vô địch", "vô địch", "vnvđ", "vn #1", "vào", "goal", "gol"), CheerWords.PHRASES)
        assertEquals(listOf(listOf("vn", "vô", "địch"), listOf("vô", "địch"), listOf("vnvđ"), listOf("vn", "#1"), listOf("vào"),
            listOf("goal"), listOf("gol")), CheerWords.TABLE)
        for (s in yes) assertTrue(s, cheers(s))
        for (s in no) assertFalse(s, cheers(s))
        assertEquals(23, yes.size); assertEquals(18, no.size)
    }

    @Test fun cheerNormalize() {
        assertEquals("vào", CheerWords.token("Vàoooo!"))
        assertEquals("gol", CheerWords.token("GOOOOL"))
        assertEquals("chuỗi lặp lẫn dấu ⇒ chữ gốc", "vào", CheerWords.token("vàôoo"))
        assertEquals("vnvđ", CheerWords.token("…VNVĐ…"))
        assertEquals("lặp 2 lần giữ nguyên", "good", CheerWords.token("good"))
        assertEquals("#1", CheerWords.token("#1"))
        assertEquals("", CheerWords.token("!!"))
        assertEquals("NFC", "việt", CheerWords.token("Việt"))
        assertEquals(listOf("vn", "#1"), CheerWords.canonical(listOf("việt", "nam", "number", "one")))
        assertEquals(listOf("vn", "#1"), CheerWords.canonical(listOf("vn", "số", "một")))
        assertEquals(listOf("vnvđ"), CheerWords.canonical(listOf("vnvd")))
        assertEquals('o', CheerWords.base('ộ')); assertEquals('đ', CheerWords.base('đ'))
    }

    @Test fun matcherFiresOnceAndKeepsSixTokens() {
        val m = CheerWords.Matcher()
        assertTrue(m.feed("vào", end = true))
        assertFalse("một cụm bắn một lần", m.feed("", end = true))
        for (w in listOf("a", "b", "c", "d", "e", "f", "g", "h")) m.feed(w, end = true)
        assertEquals(CheerWords.MAX_TOKENS, m.tokens.size)
        val n = CheerWords.Matcher()
        n.feed("VN", end = true)
        assertFalse(n.feed("", "#"))
        assertFalse(n.feed("", "1"))
        assertTrue(n.feed("", "!"))
        val r = CheerWords.Matcher()
        r.feed("vô", end = true); r.reset()
        assertFalse("dời con trỏ ⇒ quên", r.feed("địch", end = true))
    }

    /** Phía phiên gõ: Matcher chỉ nạp khi IME đặt (Sút!); null ⇒ không bao giờ có cụm. */
    @Test fun sessionCheerOnlyWhenSet() {
        val s = KeyboardSession(UserLangModel()).also { it.startInput(KeyboardSettings(), FieldTraits()) }
        val p = MockProxy()
        fun type(word: String) { for (c in word) s.handle(Key.Letter(c), p) }
        assertEquals(null, s.cheer)
        type("vaof"); s.handle(Key.Space, p)
        assertFalse("không chọn Sút! ⇒ không so", s.cheerHit)
        s.cheer = CheerWords.Matcher()
        type("vaof"); s.handle(Key.Space, p)
        assertTrue("\"vào\" + cách", s.cheerHit)
        type("an"); s.handle(Key.Space, p)
        assertFalse(s.cheerHit)
        // "VN #1": "#" và "1" là ký hiệu riêng, dồn thành "#1"; Enter = ranh giới.
        type("VN"); s.handle(Key.Space, p)
        s.handle(Key.Text("#"), p); assertFalse(s.cheerHit)
        s.handle(Key.Text("1"), p); assertFalse(s.cheerHit)
        s.handle(Key.Newline, p)
        assertTrue("VN #1 + Enter", s.cheerHit)
        // Dời con trỏ ⇒ quên.
        type("vooo"); s.handle(Key.Space, p)
        s.handle(Key.MoveCursor(-1), p)
        type("ddichj"); s.handle(Key.Space, p)
        assertFalse(s.cheerHit)
    }

    // MARK: cú sút

    @Test fun goalGeometry() {
        val n = GoalFx.net(0.0, 390.0, 0.0)
        assertEquals(GoalFx.Rect(167.0, 4.0, 56.0, 24.0), n)
        val e = GoalFx.target(n)
        assertEquals(195.0, e.x, 0.0); assertEquals(17.2, e.y, 1e-9)
        val s = GoalFx.Pt(340.0, 229.0)
        val c = GoalFx.control(s, e, 0.0)
        assertEquals("điểm điều khiển kẹp ≥ top + bán kính + 1", GoalFx.Pt(267.5, 8.0), c)
        val mid = GoalFx.ball(0.5, s, c, e)
        assertEquals(267.5, mid.x, 1e-9); assertEquals(65.55, mid.y, 1e-9)
        assertEquals(s, GoalFx.ball(0.0, s, c, e))
        assertEquals(e, GoalFx.ball(1.0, s, c, e))
        assertEquals(1.5, GoalFx.LIFE, 1e-12)
        assertEquals(0.72, GoalFx.ballScale(1.0), 1e-12)
        assertEquals(2 * Math.PI, GoalFx.ballSpin(0.5), 1e-12)
        assertEquals(0.096853, GoalFx.netRipple(0.1), 1e-6)
        assertEquals(-0.037086, GoalFx.netRipple(0.25), 1e-6)
        assertEquals(0.0, GoalFx.netRipple(0.0), 0.0); assertEquals(0.0, GoalFx.netRipple(0.6), 0.0)
        assertEquals(0.5, GoalFx.netAlpha(0.06), 1e-12)
        assertEquals(0.5, GoalFx.netAlpha(1.35), 1e-9)
        assertEquals(0.8, GoalFx.textScale(0.06), 1e-12)
        assertEquals(1.1, GoalFx.textScale(0.17), 1e-12)
        assertEquals(1.0, GoalFx.textScale(0.5), 0.0)
        assertEquals(0.6, GoalFx.textAlpha(0.75), 1e-9)
        val (xs, ys) = GoalFx.meshLines(n)
        assertEquals(listOf(6.0, 12.0, 18.0, 24.0, 30.0, 36.0, 42.0, 48.0, 54.0), xs); assertEquals(listOf(6.0, 12.0, 18.0), ys)
    }

    /** Cả cung bay (± bán kính bóng), khung thành và chữ nằm trong bàn phím — mọi cỡ, kể cả gốc dời (#151). */
    @Test fun goalArcInsideBounds() {
        for ((w, h) in listOf(320.0 to 216.0, 390.0 to 260.0, 744.0 to 300.0, 1024.0 to 340.0)) {
            for (top in listOf(0.0, 40.0)) {
                val n = GoalFx.net(0.0, w, top)
                for (kx in listOf(w - 50, 30.0, w / 2)) {
                    val s = GoalFx.Pt(kx, top + h - 30)
                    val e = GoalFx.target(n)
                    val c = GoalFx.control(s, e, top)
                    for (i in 0..100) {
                        val p = GoalFx.ball(i / 100.0, s, c, e)
                        val r = GoalFx.BALL_RADIUS
                        assertTrue("$w×$h top $top", p.y - r >= top)
                        assertTrue(p.y + r <= top + h)
                        assertTrue(p.x - r >= 0); assertTrue(p.x + r <= w)
                    }
                }
                assertTrue(n.y >= top); assertTrue(n.x + n.w <= w)
                val tc = GoalFx.textCenter(n)
                assertTrue(tc.x - GoalFx.TEXT_WIDTH / 2 >= 0)
                assertTrue(tc.y + GoalFx.TEXT_HEIGHT / 2 <= top + h)
            }
        }
    }

    @Test fun grassTuftAndCheerBurst() {
        assertEquals(0.5, GrassTuft.scaleY(0.06), 1e-12)
        assertEquals(0.45, GrassTuft.alpha(0.22), 1e-9)
        assertEquals(0.0, GrassTuft.alpha(0.32), 0.0)
        assertEquals(GoalFx.Pt(20.0, 98.0), GrassTuft.origin(20.0, 100.0))
        val f = CheerBurst.flags(0.0, 0.0, 390.0, 260.0)
        assertEquals(14, f.size)
        assertEquals(24.0689, f[0].x0, 1e-3); assertEquals(8.5943, f[0].y0, 1e-3)
        assertEquals(167.2729, f[0].dy, 1e-3); assertEquals(0.2374, f[0].delay, 1e-3)
        assertEquals(5075.5321, f.sumOf { it.x0 + it.y0 + it.dx + it.dy + it.rot + it.delay }, 1e-2)
        for (top in listOf(0.0, 40.0)) {
            for (g in CheerBurst.flags(0.0, top, 390.0, 260.0)) {
                assertTrue(g.y0 >= top); assertTrue(g.y0 + g.dy <= top + 260 - CheerBurst.MARGIN + 1e-9)
                assertTrue(g.x0 > 0); assertTrue(g.x0 < 390)
                assertEquals(CheerBurst.DURATION, g.delay + g.dur, 1e-12)
            }
        }
        assertEquals(5635.5321, CheerBurst.flags(0.0, 40.0, 390.0, 260.0).sumOf { it.x0 + it.y0 + it.dx + it.dy + it.rot + it.delay }, 1e-2)
        assertEquals(listOf(GoalFx.Pt(39.0, 250.0), GoalFx.Pt(351.0, 250.0)), CheerBurst.flares(0.0, 0.0, 390.0, 260.0))
        assertEquals(0.5, CheerBurst.flareAlpha(0.05), 1e-12)
        val star = CheerBurst.star()
        assertEquals("sao 5 cánh", 10, star.size)
        assertEquals(0.0, star[0].first, 1e-12); assertEquals(-2.6, star[0].second, 1e-12)
        assertEquals(0.583788, star[1].first, 1e-5); assertEquals(-0.803516, star[1].second, 1e-5)
        for (i in 10..89) {
            val a = CheerBurst.flareAlpha(i / 100.0)
            assertTrue("không chớp", a >= 0.75 - 1e-9 && a <= 1 + 1e-9)
        }
        val sp = CheerBurst.spark(4)
        assertEquals(14.0, sp[0], 0.0); assertEquals(-32.0, sp[1], 0.0); assertEquals(0.28, sp[2], 1e-12)
        assertEquals(0xDA251D, CheerBurst.RED); assertEquals(0xFFFF00, CheerBurst.YELLOW)
    }

    @Test fun pitchScene() {
        val st = PitchScene.stripes(390.0, 260.0)
        assertEquals(listOf(39.0, 117.0, 195.0, 273.0, 351.0), st.map { it[0] }); assertEquals(39.0, st.last()[1], 0.0)
        assertEquals(28.0, PitchScene.stripeWidth(200.0), 0.0)
        val ls = PitchScene.lines(390.0, 260.0)
        assertEquals(7, ls.size)
        assertEquals(PitchScene.Prim.Circle(195.0, 130.0, 40.0), ls[2])
        val box = ls[3] as PitchScene.Prim.Rect
        assertEquals(5.0, box.x, 0.0); assertEquals(65.0, box.y, 0.0); assertEquals(46.8, box.w, 1e-9); assertEquals(130.0, box.h, 0.0)
        for (p in ls) when (p) {
            is PitchScene.Prim.Rect -> assertTrue(p.x >= 0 && p.y >= 0 && p.x + p.w <= 390 + 1e-9 && p.y + p.h <= 260 + 1e-9)
            is PitchScene.Prim.Circle -> assertTrue(p.cx - p.r >= 0 && p.cy - p.r >= 0 && p.cx + p.r <= 390 && p.cy + p.r <= 260)
            is PitchScene.Prim.Line -> assertTrue(minOf(p.x0, p.x1) >= 0 && minOf(p.y0, p.y1) >= 0 && maxOf(p.x0, p.x1) <= 390 && maxOf(p.y0, p.y1) <= 260)
        }
        assertTrue(PitchScene.lines(10.0, 10.0).isEmpty())
        assertTrue(ThemeScene.isScene(ThemeDecoration.PITCH)); assertFalse(ThemeScene.isScene(ThemeDecoration.WAVES))
        assertTrue("cảnh không có hình motif nhỏ", ThemeDecoration.shape(ThemeDecoration.PITCH).isEmpty())
        assertTrue(ThemeDecoration.PITCH in ThemeDeco.MOTIFS)
    }

    // MARK: âm

    @Test fun thumpAndCheerSounds() {
        assertTrue(KeySoundStyle.THUMP in KeySoundStyle.PRESETS)
        assertEquals(0x7468756D xor 0x85EBCA6B.toInt(), KeySoundSynth.seed(KeySoundStyle.THUMP, KeySoundSynth.Kind.LETTER))
        val golden = listOf(KeySoundSynth.Kind.LETTER to 269.4209, KeySoundSynth.Kind.DELETE to 250.6433, KeySoundSynth.Kind.MODIFIER to 308.7933)
        for ((k, want) in golden) {
            assertEquals("$k", want, KeySoundSynth.samples(KeySoundStyle.THUMP, k).sumOf { abs(it.toDouble()) }, 0.01)
        }
        val wood = KeySoundSynth.samples(KeySoundStyle.WOOD, KeySoundSynth.Kind.LETTER)
        val th = KeySoundSynth.samples(KeySoundStyle.THUMP, KeySoundSynth.Kind.LETTER)
        assertTrue("không to hơn Gõ gỗ", th.maxOf { abs(it) } < wood.maxOf { abs(it) })
        assertTrue("bụp trầm", KeySoundSynth.spectralCentroid(th) < 1200)
        assertEquals("Ball thump", L10nTable.EN["Bóng bụp"])

        val c = KeySoundSynth.cheerSamples()
        assertEquals(20948, c.size)
        assertEquals(904.6467, c.sumOf { abs(it.toDouble()) }, 0.05)
        assertEquals(KeySoundSynth.CHEER_PEAK, c.maxOf { abs(it) }.toDouble(), 1e-4)
        assertEquals(0.0, c.first().toDouble(), 1e-6); assertEquals(0.0, c.last().toDouble(), 1e-6)
        assertTrue("mềm", KeySoundSynth.spectralCentroid(c, KeySoundSynth.SURF_SAMPLE_RATE.toDouble()) < 2500)
        val sr = KeySoundSynth.SURF_SAMPLE_RATE
        fun rms(a: Double, b: Double) = KeySoundSynth.rms(c.copyOfRange((a * sr).toInt(), (b * sr).toInt()))
        assertTrue("dâng", rms(0.0, 0.1) < rms(0.35, 0.55) * 0.5)
    }

    // MARK: theme

    @Test fun footballTheme() {
        val t = KeyboardTheme.FOOTBALL
        val spec = t.spec
        assertNotNull(spec)
        assertTrue(t.isPlus); assertTrue(t.isInteractive)
        assertEquals("Bóng đá", spec!!.nameVi); assertEquals("Football", spec.nameEn)
        assertEquals("Football", L10nTable.EN[t.viTitle])
        assertEquals("thump", spec.sound); assertEquals("goal", spec.effect)
        assertTrue(ThemeSpecParser.contrastIssues(spec).isEmpty())
        assertEquals("football", ThemePicker.INTERACTIVE_ORDER.last())
        assertTrue(KeyEffect.GOAL.isPlus); assertEquals("Kick!", L10nTable.EN[KeyEffect.GOAL.viTitle])
        assertEquals(setOf(KeyEffect.GOAL), ThemeFxFactory.EFFECTS)
        for (dark in listOf(false, true)) {
            val p = t.palette(dark)!!
            assertEquals(ThemeDecoration.PITCH, p.decoration?.motif)
            assertTrue(p.decoration!!.isScene)
        }
    }
}
