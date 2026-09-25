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
}
