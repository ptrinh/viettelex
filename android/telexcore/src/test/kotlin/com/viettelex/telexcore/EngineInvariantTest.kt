package com.viettelex.telexcore

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.random.Random

/** Hand-ported structural tests (ScreenSimulation, PeekCommit, Reopen, Seed, Overflow). */
class EngineInvariantTest {

    private fun applyScreen(sb: StringBuilder, a: TelexAction, ch: Char?) {
        when (a) {
            TelexAction.Passthrough -> if (ch != null) sb.append(ch) else if (sb.isNotEmpty()) sb.setLength(sb.length - 1)
            TelexAction.None -> {}
            is TelexAction.Replace -> {
                assertTrue("bs ${a.backspaces} > screen ${sb.length}", a.backspaces <= sb.length)
                sb.setLength(sb.length - a.backspaces); sb.append(a.insert)
            }
        }
    }

    /** ScreenSimulationTests: a dumb client applying the actions always shows `composed`. */
    @Test fun screenAlwaysEqualsComposedUnderRandomTyping() {
        val rnd = Random(40)
        val keys = "aaeeoouuwwddsfrxjzbcghiklmnpqtvyAEOUWDSF<<<"
        repeat(20_000) {
            val e = TelexEngine().apply {
                freeMarking = rnd.nextBoolean(); simpleTelex = rnd.nextBoolean()
                liveSpellCheck = rnd.nextBoolean(); modernTone = rnd.nextBoolean()
                quickTelex = rnd.nextInt(4) == 0; teencode = rnd.nextBoolean()
            }
            val sb = StringBuilder()
            val n = 1 + rnd.nextInt(24)
            val typed = StringBuilder()
            for (i in 0 until n) {
                val c = keys[rnd.nextInt(keys.length)]
                typed.append(c)
                if (c == '<') applyScreen(sb, e.backspace(), null) else applyScreen(sb, e.feed(c), c)
                assertEquals("keys=$typed", e.composed, sb.toString())
            }
        }
    }

    /** PeekCommitTests: peek == commitText on an independent copy, and peek does not mutate. */
    @Test fun peekMatchesCommitOnCopy() {
        val rnd = Random(7)
        val keys = "aeouwdsfrxjzbchnglmtiyAS"
        repeat(10_000) {
            val e = TelexEngine().apply {
                freeMarking = rnd.nextBoolean(); simpleTelex = rnd.nextBoolean()
                liveSpellCheck = rnd.nextBoolean(); contextualEnglish = rnd.nextBoolean()
                collisionPrefersVietnamese = rnd.nextBoolean(); teencode = rnd.nextBoolean()
            }
            repeat(1 + rnd.nextInt(3)) {
                repeat(1 + rnd.nextInt(10)) { e.feed(keys[rnd.nextInt(keys.length)]) }
                val auto = rnd.nextBoolean()
                val before = e.composed
                val peek = e.peekCommitText(auto)
                assertEquals(before, e.composed)
                assertEquals(peek, e.copy().commitText(auto))
                e.commitText(auto)
            }
        }
    }

    @Test fun reopenIssue40() {
        val e = TelexEngine().apply { freeMarking = true; simpleTelex = true; liveSpellCheck = true }
        for (c in "thasy") e.feed(c)
        assertEquals("tháy", e.composed)
        assertEquals(TelexAction.None, e.commitBoundary(true))
        assertTrue(e.canReopenLastCommit)
        assertEquals("tháy", e.reopenLastCommit())
        assertEquals("thasy", e.rawKeystrokes)
        assertEquals(TelexAction.Replace(2, "ấy"), e.feed('a'))
        assertEquals("thấy", e.composed)
    }

    @Test fun reopenBackspaceThroughWord() {
        val e = TelexEngine().apply { freeMarking = true; simpleTelex = true; liveSpellCheck = true }
        for (c in "dduwowngf") e.feed(c)
        e.commitBoundary(true)
        assertEquals("đường", e.reopenLastCommit())
        for (expected in listOf("đườn", "đườ", "đư", "đ", "")) {
            e.backspace()
            assertEquals(expected, e.composed)
        }
        assertFalse(e.canReopenLastCommit)
        assertNull(e.reopenLastCommit())
    }

    @Test fun seedRoundTrips() {
        val e = TelexEngine()
        assertTrue(e.seed("toan")); assertEquals(TelexAction.Replace(2, "án"), e.feed('s'))
        assertTrue(e.seed("Việt")); assertEquals("Việt", e.composed)
        assertFalse(e.seed("google"))
        assertFalse(e.seed("hoà"))   // old-style engine spells hòa
        e.modernTone = true
        assertTrue(e.seed("hoà"))
        e.vniMode = true
        assertTrue(e.seed("đường")); assertEquals("d9u7o7ng2", e.rawKeystrokes)
    }

    @Test fun overflowPassesThrough() {
        val e = TelexEngine()
        repeat(32) { assertEquals(TelexAction.Passthrough, e.feed('b')) }
        assertFalse(e.isOverflowed)
        assertEquals(TelexAction.Passthrough, e.feed('b'))
        assertTrue(e.isOverflowed)
        assertEquals(TelexAction.Passthrough, e.backspace())
        assertEquals(TelexAction.None, e.commitBoundary(true))
        assertTrue(e.isEmpty)
    }

    @Test fun nonLetterPassesThrough() {
        val e = TelexEngine()
        for (c in "1.,!ễ[") assertEquals(TelexAction.Passthrough, e.feed(c))
        assertTrue(e.isEmpty)
    }

    /**
     * UpperToneBackspaceTests.testBackspaceEqualsRetypeWithoutLastKey (same LCG, same
     * sequences): when the last key was inserted literally, ⌫ == retyping without it.
     */
    @Test fun backspaceEqualsRetypeWithoutLastKey() {
        var seed = 0x9E3779B97F4A7C15UL
        fun next(): ULong {
            seed = seed * 6364136223846793005UL + 1442695040888963407UL
            return seed shr 33
        }
        fun engine(cfg: Int) = TelexEngine().apply {
            liveSpellCheck = cfg and 1 != 0; freeMarking = cfg and 2 != 0
            simpleTelex = cfg and 4 != 0; teencode = cfg and 8 != 0; vniMode = cfg and 16 != 0
        }
        fun typed(cfg: Int, keys: String) = engine(cfg).also { e -> for (c in keys) e.feed(c) }
        val telexKeys = "aeiouydwsfrxjzntcghl"
        val vniKeys = "aeiouydntcgh1234567890"
        var checked = 0
        for (cfg in 0 until 32) {
            val keys = if (cfg and 16 != 0) vniKeys else telexKeys
            repeat(600) {
                val sb = StringBuilder()
                repeat(3 + (next() % 6UL).toInt()) {
                    var c = keys[(next() % keys.length.toULong()).toInt()]
                    if (next() % 3UL == 0UL) c = c.uppercaseChar()
                    sb.append(c)
                }
                val word = if (checked == 0) "uxuJxwl" else sb.toString()
                for (n in 2..word.length) {
                    val prefix = word.substring(0, n - 1)
                    val e = typed(cfg, word.substring(0, n))
                    val f = typed(cfg, prefix)
                    if (e.composed != f.composed + word[n - 1]) continue
                    checked++
                    e.backspace()
                    assertEquals("cfg=$cfg keys=${word.substring(0, n)} ⌫", f.composed, e.composed)
                }
            }
        }
        for (keys in listOf("VieeJt", "uxuJxwl")) {
            for (cfg in 0 until 16) {
                val e = typed(cfg, keys); e.backspace()
                assertEquals("cfg=$cfg keys=$keys ⌫", typed(cfg, keys.dropLast(1)).composed, e.composed)
            }
        }
        assertTrue("checked=$checked", checked > 20_000)
    }
}
