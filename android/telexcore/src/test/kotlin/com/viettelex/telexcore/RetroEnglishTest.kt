package com.viettelex.telexcore

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * Port of TelexCore RetroEnglishTests.swift (retroactive English correction). The eval
 * corpus is the shared fixture iOS/KeyboardTests/Fixtures/retro-english-eval.txt
 * (Scripts/gen-retro-english-eval.py); thresholds identical to the Swift test.
 */
class RetroEnglishTest {

    private fun appEngine(retro: Boolean, contextual: Boolean = true) = TelexEngine().apply {
        freeMarking = true; liveSpellCheck = true; eagerEnglishRestore = true; teencode = false
        contextualEnglish = contextual; collisionPrefersVietnamese = true; retroactiveEnglish = retro
    }

    private class Typed(val text: String, val edits: Int)

    private fun typeKeys(keys: String, e: TelexEngine): Typed {
        val screen = StringBuilder()
        var edits = 0
        fun apply(c: RetroCorrection?) {
            if (c == null) return
            val tail = screen.substring(screen.length - c.backspaces)
            assertEquals("retro expected-text mismatch in $keys", c.expected, tail)
            screen.setLength(screen.length - c.backspaces)
            screen.append(c.insert)
            edits++
        }
        for (ch in keys) {
            if (ch.code < 128 && ch.isLetter()) {
                e.feed(ch)
            } else {
                screen.append(e.commitText(true))
                screen.append(ch)
                e.noteBoundaryCharacter(ch)
                apply(e.takeRetroCorrection())
            }
        }
        screen.append(e.commitText(true))
        apply(e.takeRetroCorrection())
        return Typed(screen.toString(), edits)
    }

    private fun typed(keys: String, retro: Boolean = true, contextual: Boolean = true) =
        typeKeys(keys, appEngine(retro, contextual)).text

    private fun words(s: String): List<String> = s.split(Regex("[^\\p{L}]+")).filter { it.isNotEmpty() }

    @Test fun rewritesCollisionWordsBeforeEnglishRun() {
        assertEquals("His car is very fast", typed("His car is very fast"))
        assertEquals("Hí cả í very fast", typed("His car is very fast", retro = false))
        assertEquals("my car is here now", typed("my car is here now"))
        assertEquals("of course not", typed("of course not"))
        assertEquals("its time to go home", typed("its time to go home"))
        assertEquals("This list is very long", typed("This list is very long"))
    }

    @Test fun vietnameseWithLoanwordsUntouched() {
        for (keys in listOf("Mai car team hopj", "Guwir file cho car nhaf", "car team meeting",
            "cais nayf as the best", "check car deploy build", "lamf car review code",
            "hoom nay hopj car buoori with the team", "em sex check the logs")) {
            assertEquals(keys, typed(keys, retro = false), typed(keys))
        }
        assertEquals("Mai cả team họp", typed("Mai car team hopj"))
        assertEquals("Gửi file cho cả nhà", typed("Guwir file cho car nhaf"))
        assertEquals("cả team meeting", typed("car team meeting"))
    }

    @Test fun inertWithoutContextualEnglish() {
        for (keys in listOf("His car is very fast", "my car is here now", "of course not")) {
            assertEquals(keys, typed(keys, retro = false, contextual = false), typed(keys, retro = true, contextual = false))
        }
        val e = appEngine(retro = true, contextual = false)
        assertFalse(e.retroactiveEnglishActive)
        assertEquals(0, typeKeys("His car is very fast", e).edits)
        assertTrue(e.debugRetroHistory.isEmpty())
    }

    @Test fun inertInVNI() {
        val e = appEngine(retro = true).apply { vniMode = true }
        assertFalse(e.retroactiveEnglishActive)
    }

    @Test fun caseKeptExactly() {
        assertEquals("HIS CAR is very fast", typed("HIS CAR is very fast"))
        assertEquals("His Car is very fast", typed("His Car is very fast"))
    }

    @Test fun correctionShape() {
        val e = appEngine(retro = true)
        for (k in listOf("His", "car", "is", "very")) {
            for (ch in k) e.feed(ch)
            e.commitText(true)
            e.noteBoundaryCharacter(' ')
            assertNull(e.takeRetroCorrection())
        }
        for (ch in "fast") e.feed(ch)
        assertEquals("fast", e.commitText(true))
        assertEquals(RetroCorrection(16, "í cả í very fast", "is car is very fast", 3), e.pendingRetroCorrection)
        e.noteBoundaryCharacter('.')
        assertEquals(RetroCorrection(17, "í cả í very fast.", "is car is very fast.", 3), e.takeRetroCorrection())
        assertNull(e.takeRetroCorrection())
    }

    @Test fun historyClearedByUnknownEdits() {
        fun prime(e: TelexEngine) {
            for (k in listOf("His", "car", "is", "very")) {
                for (ch in k) e.feed(ch)
                e.commitText(true)
                e.noteBoundaryCharacter(' ')
            }
        }
        val clears: List<(TelexEngine) -> Unit> = listOf(
            { it.reset() }, { it.resetContext() }, { it.forgetLastCommit() },
            { it.backspace() },
            { it.noteBoundaryCharacter(',') },
            { it.retroactiveEnglish = false; it.feed('x'); it.commitText(true); it.noteBoundaryCharacter(' '); it.retroactiveEnglish = true },
        )
        clears.forEachIndexed { i, clear ->
            val e = appEngine(retro = true)
            prime(e)
            clear(e)
            for (ch in "fast") e.feed(ch)
            e.commitText(true)
            assertNull("clear #$i", e.takeRetroCorrection())
        }
        val e = appEngine(retro = true)
        for (k in listOf("His", "car", "is", "very", "fast")) {
            for (ch in k) e.feed(ch)
            e.commitText(true)
        }
        assertNull(e.takeRetroCorrection())
    }

    @Test fun commitBoundaryPath() {
        val e = appEngine(retro = true)
        for (k in listOf("His", "car", "is", "very", "fast")) {
            for (ch in k) e.feed(ch)
            e.commitBoundary(true)
            if (k != "fast") e.noteBoundaryCharacter(' ')
        }
        assertEquals("is car is very fast", e.takeRetroCorrection()?.insert)
    }

    @Test fun planIsPure() {
        fun w(raw: String, shown: String, eng: Boolean, cand: Boolean, gap: Int = 1) =
            RetroWord(raw, shown, eng, cand, RetroEnglish.classBits(raw.lowercase()), gap, false)
        val h = listOf(w("His", "Hí", false, true, 0), w("car", "cả", false, true),
            w("is", "í", false, true), w("very", "very", true, false), w("fast", "fast", true, false))
        assertEquals(listOf(0, 1, 2), RetroEnglish.plan(h)?.toList())
        assertNull(RetroEnglish.plan(h.dropLast(1)))
        assertNull(RetroEnglish.plan(h.map { it.copy() }.also { it[3].gap = 0 }))
        assertNull(RetroEnglish.plan(h.map { it.copy() }.also { it[0].cls = 0 }))
    }

    private fun fixture(): File = listOf("../../iOS", "../iOS", "iOS")
        .map { File(it, "KeyboardTests/Fixtures/retro-english-eval.txt") }
        .firstOrNull { it.exists() } ?: error("không thấy retro-english-eval.txt")

    /** Same metrics + thresholds as RetroEnglishTests.testEvalPrecisionRecall. */
    @Test fun evalPrecisionRecall() {
        var tp = 0; var fp = 0; var offWrong = 0; var vChanged = 0; var sentences = 0
        for (line in fixture().readLines()) {
            if (line.isEmpty() || line.startsWith("#")) continue
            val p = line.split('\t')
            if (p.size != 3) continue
            val keys = p[1]; val mask = p[2]
            val o = words(typed(keys, retro = false)); val n = words(typed(keys, retro = true)); val k = words(keys)
            assertTrue(keys, o.size == n.size && n.size == k.size && k.size == mask.length)
            sentences++
            for (i in k.indices) {
                val english = mask[i] == 'e'
                val gold = if (english) k[i] else o[i]
                if (o[i] != n[i]) {
                    if (n[i] == gold) tp++ else fp++
                    if (!english) vChanged++
                }
                if (english && o[i] != gold) offWrong++
            }
        }
        val precision = tp.toDouble() / maxOf(tp + fp, 1)
        val recall = tp.toDouble() / maxOf(offWrong, 1)
        println("RETRO-EVAL kotlin $sentences sentences | TP=$tp FP=$fp precision=$precision recall=$tp/$offWrong=$recall vChanged=$vChanged")
        assertTrue(sentences > 5000)
        assertEquals(0, vChanged)
        assertEquals(0, fp)
        assertTrue(precision >= 0.99)
        assertTrue(recall >= 0.30)
    }
}
