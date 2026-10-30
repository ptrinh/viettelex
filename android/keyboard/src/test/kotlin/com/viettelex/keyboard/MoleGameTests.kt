package com.viettelex.keyboard

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import kotlin.math.abs
import kotlin.math.ceil

/**
 * Theme "Đập chuột" (game "mole") — iOS MoleGameTests y hệt: máy trạng thái (thả / cửa sổ đập / nghỉ / một con),
 * đoán phím (seed ⇒ tất định, luôn a–z), điểm + thống kê, bật CHỈ theme có "game":"mole", âm "bop" + "éc" (checksum
 * chung), theme JSON khứ hồi, chi phí mỗi phím ("MOLE-COST").
 */
class MoleGameTests {
    private var savedPaywall = false
    @Before fun setUp() { savedPaywall = PlusGate.paywallEnabled; PlusGate.paywallEnabled = false }
    @After fun tearDown() { PlusGate.paywallEnabled = savedPaywall }

    @Test fun spawnTimingFollowsTypingTime() {
        val g = MoleGame(42)
        val first = g.nextSpawn
        assertTrue(first in MoleGame.SPAWN_MIN..MoleGame.SPAWN_MAX)
        var t = 0.0
        var spawnAt: Double? = null
        for (i in 0 until 60) { t += 0.2; if (g.key(null, t) == MoleEvent.Spawn) { spawnAt = t; break } }
        assertEquals(0.2 * (ceil(first / 0.2 - 1e-9) + 1), spawnAt!!, 1e-9)
        assertTrue(g.pending)
        repeat(20) { t += 0.2; assertEquals("đang chờ đặt ⇒ không thả thêm", MoleEvent.None, g.key('a', t)) }
        g.place('a', t)
        assertEquals('a', g.mole); assertFalse(g.pending)
    }

    @Test fun hitWindowAndScoring() {
        val g = MoleGame(1)
        fun spawnNow(k: Char, t0: Double): Double {
            var x = t0
            while (g.key(null, x) != MoleEvent.Spawn) x += 0.25
            g.place(k, x); return x
        }
        var t = spawnNow('n', 100.0)
        assertEquals(MoleEvent.None, g.key('m', t + 0.5))
        assertEquals(MoleEvent.Hit('n'), g.key('n', t + 1.49))
        assertEquals(1, g.hits); assertEquals(1, g.streak); assertNull(g.mole)
        t = spawnNow('h', t + 1.6)
        assertEquals(MoleEvent.Hit('h'), g.key('h', t + 0.3))
        assertEquals(2, g.streak); assertEquals(2, g.bestStreak)
        t = spawnNow('a', t + 0.4)
        assertEquals(MoleEvent.None, g.key('x', t + 1.0))
        assertEquals("hết upTime ⇒ trượt", MoleEvent.Duck, g.key('a', t + 1.5))
        assertEquals(0, g.streak); assertEquals(2, g.bestStreak); assertEquals(1, g.misses); assertEquals(2, g.hits)
        t = spawnNow('t', t + 1.6)
        assertEquals(MoleEvent.None, g.key(null, t + 0.2))
        assertNotNull(g.mole)
    }

    @Test fun duckAndIdleStop() {
        val g = MoleGame(3)
        var t = 0.0
        while (g.key(null, t) != MoleEvent.Spawn) t += 0.25
        g.place('c', t)
        assertEquals(MoleEvent.None, g.tick(t + 1.0))
        assertEquals(MoleEvent.Duck, g.tick(t + MoleGame.UP_TIME))
        assertEquals(MoleEvent.None, g.tick(t + 2))
        assertEquals(1, g.misses)
        t += 5
        assertEquals(MoleEvent.None, g.key('a', t))
        assertEquals(0.0, g.typed, 0.0)
        val g2 = MoleGame(3)
        g2.key(null, 0.0)
        assertEquals(MoleEvent.None, g2.tick(100.0))
        assertNull(g2.mole); assertFalse(g2.pending)
        val g3 = MoleGame(3)
        t = 0.0
        while (g3.key(null, t) != MoleEvent.Spawn) t += 0.25
        g3.place('o', t)
        assertEquals(MoleEvent.Duck, g3.key('o', t + 3.2))
    }

    @Test fun oneAtATimeAndGapCap() {
        val g = MoleGame(9)
        var t = 0.0
        while (g.key(null, t) != MoleEvent.Spawn) t += 0.1
        g.place('i', t)
        repeat(14) { t += 0.1; assertNotEquals(MoleEvent.Spawn, g.key('x', t)) }
        val h = MoleGame(9)
        h.key(null, 0.0); h.key(null, 2.5)
        assertEquals(MoleGame.GAP_CAP, h.typed, 1e-12)
        g.hide()
        assertNull(g.mole); assertEquals(0, g.misses)
    }

    @Test fun nextKeyFromPrefixAndCandidates() {
        val r = FxRandom(5)
        assertEquals('u', MoleTarget.next("nh", listOf("nhưng", "nhà"), r))
        assertEquals('d', MoleTarget.next("", listOf("đi", "được"), r))
        assertEquals('o', MoleTarget.next("Đư", listOf("Đường"), r))
        assertEquals('i', MoleTarget.next("cá", listOf("cá", "cái"), r))
        assertEquals('n', MoleTarget.next("xa", listOf("nhà", "xa1", "xa ", "xanh"), r))
        assertEquals("nguyen duc", MoleTarget.fold("Nguyễn Đức"))
        for (seed in 0 until 200) {
            val c = MoleTarget.next("zzz", emptyList(), FxRandom(seed))
            assertTrue(MoleTarget.isAZ(c)); assertTrue(c in MoleTarget.COMMON)
            assertEquals('t', MoleTarget.next("", listOf("123"), FxRandom(seed)) { it == 't' })
        }
        assertFalse(MoleTarget.isAZ(' ')); assertFalse(MoleTarget.isAZ('1')); assertFalse(MoleTarget.isAZ('é'))
    }

    /** Số tham chiếu chung iOS (testSeededDeterminismParity). */
    @Test fun seededParity() {
        assertEquals(4.39127183947509, MoleGame(2026).nextSpawn, 1e-6)
        val a = MoleGame(2026)
        val picks = (0 until 12).map { a.chooseTarget("", emptyList()) }.joinToString("")
        assertEquals("ttnmmdyhmntc", picks)
    }

    @Test fun statsRecordDayRolloverAndEncoding() {
        var s = MoleStats()
        s = s.record(1, 1, 20261019).record(1, 2, 20261019)
        assertEquals(2, s.count(20261019)); assertEquals(2, s.best)
        s = s.record(1, 1, 20261020)
        assertEquals(1, s.count(20261020)); assertEquals(0, s.count(20261019))
        assertEquals(3, s.total); assertEquals(2, s.best)
        assertEquals(s, MoleStats.decode(s.encode()))
        assertEquals(MoleStats(), MoleStats.decode(null)); assertEquals(MoleStats(), MoleStats.decode("x 1"))
        val m = HashMap<String, Any?>()
        s.save { k, v -> m[k] = v }
        assertEquals(s, MoleStats.load { m[it] })
        val cal = java.util.Calendar.getInstance(java.util.TimeZone.getTimeZone("UTC")).apply { timeInMillis = 0 }
        assertEquals(19700101, MoleStats.dayNumber(cal))
        assertEquals("Whack-a-mole", L10nTable.EN["Đập chuột"])
        assertNotNull(L10nTable.EN["Hôm nay đập %s con chuột 🐭"])
        assertNotNull(L10nTable.EN["Chuỗi dài nhất: %s · Tổng: %s"])
    }

    /** 0 chi phí khi tắt: chỉ theme có game "mole" (+ Plus, không tiết kiệm pin / TalkBack) bật trò chơi. */
    @Test fun policyOnlyMoleTheme() {
        assertTrue(MolePolicy.active("mole", plus = true, powerSave = false, talkBack = false))
        assertFalse(MolePolicy.active(null, true, false, false))
        assertFalse(MolePolicy.active("mole", false, false, false))
        assertFalse(MolePolicy.active("mole", true, true, false))
        assertFalse(MolePolicy.active("mole", true, false, true))
        for (t in KeyboardTheme.entries) {
            val g = ThemeSettings(theme = t).effectiveKeyStyle.game
            assertEquals("$t", t == KeyboardTheme.MOLE, MolePolicy.active(g, true, false, false))
        }
        assertTrue(MolePolicy.shouldSqueak(true)); assertFalse(MolePolicy.shouldSqueak(false))
    }

    @Test fun moleThemeSpecAndContrast() {
        val t = KeyboardTheme.MOLE
        val spec = t.spec!!
        assertEquals("mole", spec.game); assertEquals("bop", spec.sound); assertNull(spec.effect)
        assertEquals("Whack-a-mole", spec.nameEn)
        assertTrue(t.isPlus)
        assertEquals(KeyboardTheme.MOLE, KeyboardTheme.entries[KeyboardTheme.entries.indexOf(KeyboardTheme.NEUTRAL) - 1])   // thêm cuối (sau đó: Xám trung tính)
        val c = ThemeColor
        for (dk in listOf(false, true)) {
            val p = t.palette(dk)!!
            val bg = p.bg!!
            assertTrue(c.contrast(p.ink, c.over(p.keyFill, bg)) >= 4.5)
            assertTrue(c.contrast(p.functionInk!!, c.over(p.functionFill!!, bg)) >= 4.5)
            assertEquals(ThemeDecoration.FLOWERS, p.decoration!!.motif)
        }
        assertTrue(ThemeSpecParser.contrastIssues(spec).isEmpty())
        assertEquals("Mallet bop", L10nTable.EN["Búa gỗ"])
    }

    @Test fun themeJsonGameRoundTrip() {
        val base = ThemeJsonActions.Base { t, dk -> t.palette(dk)!! }
        val text = ThemeJsonActions.copyText(ThemeEditTarget.Builtin(KeyboardTheme.MOLE), ThemeSettings(theme = KeyboardTheme.MOLE),
            emptyMap(), base)!!
        assertTrue(text, text.contains("\"game\""))
        val back = ThemeSpecParser.parse(text).spec!!
        assertEquals("mole", back.game); assertEquals("bop", back.sound)
        assertEquals(back, ThemeSpecParser.parse(back.canonical).spec)
        val b = """{"v":1,"name":{"vi":"x"},"light":{"key":"#FFFFFF","special":"#DDDDDD","ink":"#000000","accent":"#000000"}"""
        assertEquals("mole", ThemeSpecParser.parse("$b,\"game\":\"mole\"}").spec?.game)
        assertEquals(listOf(ThemeIssue.Code.badValue), ThemeSpecParser.parse("$b,\"game\":\"tetris\"}").errors.map { it.code })
        assertEquals(listOf(ThemeIssue.Code.wrongType), ThemeSpecParser.parse("$b,\"game\":1}").errors.map { it.code })
        assertNull(ThemeSpecParser.parse("$b}").spec?.game)
        val custom = ThemeSpecParser.parse("$b,\"game\":\"mole\"}").spec!!.copy(id = "my-mole")
        assertEquals("mole", ThemeSettings(custom = custom).effectiveKeyStyle.game)
        val st = KeyStyle(game = "mole")
        val raw = KeyStyleStore.serialize(mapOf("sky" to st))
        assertEquals("""{"sky":{"game":"mole"}}""", raw)
        assertEquals("mole", KeyStyleStore.parse(raw)["sky"]?.game)
        assertEquals("mole", ThemeSettings(theme = KeyboardTheme.SKY).withKeyStyle(st, KeyboardTheme.SKY).effectiveKeyStyle.game)
        assertEquals(setOf("mole"), ThemeExtraIds.GAMES)
    }

    /** "Éc" + "bop": tất định, êm (≤ Gõ gỗ), checksum chung iOS. */
    @Test fun squeakAndBopChecksums() {
        val sq = KeySoundSynth.squeakSamples()
        assertEquals(Math.round(0.130 * KeySoundSynth.SAMPLE_RATE).toInt(), sq.size)
        val wood = KeySoundSynth.samples(KeySoundStyle.WOOD, KeySoundSynth.Kind.LETTER)
        assertTrue(sq.maxOf { abs(it) } <= wood.maxOf { abs(it) })
        assertEquals(534.9296, sq.sumOf { abs(it).toDouble() }, 0.01)
        println("MOLE-GOLDEN bop=" + KeySoundSynth.Kind.entries.map { k -> "%.4f".format(KeySoundSynth.samples(KeySoundStyle.BOP, k).sumOf { abs(it).toDouble() }) })
        val golden = doubleArrayOf(171.8268, 181.9607, 215.5216)
        for (k in KeySoundSynth.Kind.entries) {
            val b = KeySoundSynth.samples(KeySoundStyle.BOP, k); val w = KeySoundSynth.samples(KeySoundStyle.WOOD, k)
            assertTrue("$k", KeySoundSynth.rms(b) < KeySoundSynth.rms(w))
            assertTrue("$k", b.maxOf { abs(it) } < w.maxOf { abs(it) })
            assertTrue("$k", KeySoundSynth.spectralCentroid(b) < 700)
            assertEquals("$k", golden[k.ordinal], b.sumOf { abs(it).toDouble() }, 0.01)
        }
    }

    /** Chi phí mỗi phím của máy trạng thái (đường nóng khi bật). In "MOLE-COST". */
    @Test fun costPerKey() {
        val g = MoleGame(1)
        var t = 0.0
        repeat(20_000) { t += 0.15; if (g.key('a', t) == MoleEvent.Spawn) g.place('b', t) }   // làm nóng JIT
        val n = 200_000
        val t0 = System.nanoTime()
        for (i in 0 until n) {
            t += 0.15
            if (g.key(if (i % 7 == 0) null else 'a', t) == MoleEvent.Spawn) g.place('b', t)
        }
        val us = (System.nanoTime() - t0) / 1000.0 / n
        println("MOLE-COST máy trạng thái %.4f µs/phím (JVM, n=%d, chuột ra %d lần)".format(us, n, g.spawns))
        assertTrue("< 0,1 ms/phím", us < 100)
        assertTrue(g.spawns > 0)
    }
}
