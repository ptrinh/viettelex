package com.viettelex.telexcore

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.BufferedReader
import java.io.InputStreamReader
import java.util.zip.GZIPInputStream

/**
 * Replays the golden corpus generated from the Swift engine
 * (TelexCore/Sources/GenGolden, `swift run gen-golden`) and requires a 100% match.
 * Format is documented in GenGolden/main.swift.
 */
class GoldenTest {

    private fun configure(e: TelexEngine, flags: String): Boolean {
        var auto = false
        for (c in flags) when (c) {
            'A' -> auto = true
            'F' -> e.freeMarking = true
            'M' -> e.modernTone = true
            'L' -> e.liveSpellCheck = true
            'S' -> e.simpleTelex = true
            't' -> e.teencode = false
            'Q' -> e.quickTelex = true
            'B' -> e.bracketVowels = true
            'V' -> e.vniMode = true
            'C' -> e.contextualEnglish = true
            'e' -> e.englishWordRestore = false
            'P' -> e.collisionPrefersVietnamese = true
        }
        return auto
    }

    private fun toggle(e: TelexEngine, c: Char, auto: Boolean): Boolean {
        when (c) {
            'A' -> return !auto
            'F' -> e.freeMarking = !e.freeMarking
            'M' -> e.modernTone = !e.modernTone
            'L' -> e.liveSpellCheck = !e.liveSpellCheck
            'S' -> e.simpleTelex = !e.simpleTelex
            't' -> e.teencode = !e.teencode
            'Q' -> e.quickTelex = !e.quickTelex
            'B' -> e.bracketVowels = !e.bracketVowels
            'V' -> e.vniMode = !e.vniMode
            'C' -> e.contextualEnglish = !e.contextualEnglish
            'e' -> e.englishWordRestore = !e.englishWordRestore
            'P' -> e.collisionPrefersVietnamese = !e.collisionPrefersVietnamese
        }
        return auto
    }

    private fun tok(a: TelexAction): String = when (a) {
        TelexAction.Passthrough -> "P"
        TelexAction.None -> "N"
        is TelexAction.Replace -> "R${a.backspaces},${a.insert}"
    }

    private fun removeLast(sb: StringBuilder, n: Int) {
        val k = minOf(n, sb.length)
        sb.setLength(sb.length - k)
    }

    /** Returns the actual line (same format) for `flags` + `ops`. */
    fun replay(flagsField: String, ops: String): String {
        val flags = if (flagsField == "-") "" else flagsField
        val e = TelexEngine()
        var auto = configure(e, flags)
        val trace = ArrayList<String>()
        val screen = StringBuilder()
        if (ops.startsWith("@")) {
            val ok = e.seed(ops.substring(1))
            trace.add(if (ok) "1" else "0")
            screen.append(e.composed)
        } else {
            var i = 0
            while (i < ops.length) {
                val c = ops[i]
                when (c) {
                    ' ', '.', ',' -> {
                        val peek = e.peekCommitText(auto)
                        val a = e.commitBoundary(auto)
                        if (a is TelexAction.Replace) { removeLast(screen, a.backspaces); screen.append(a.insert) }
                        screen.append(c)
                        trace.add(peek + "=>" + tok(a))
                    }
                    '<' -> {
                        val a = e.backspace()
                        when (a) {
                            is TelexAction.Replace -> { removeLast(screen, a.backspaces); screen.append(a.insert) }
                            else -> removeLast(screen, 1)
                        }
                        trace.add(tok(a))
                    }
                    '^' -> {
                        val w = e.reopenLastCommit()
                        if (w != null) { removeLast(screen, 1); trace.add("o:$w") } else trace.add("o~")
                    }
                    '#' -> { e.reset(); trace.add("N") }
                    '!' -> { e.resetContext(); trace.add("N") }
                    '%' -> trace.add("c:" + e.commitText(auto))
                    '`' -> {
                        if (i + 1 < ops.length) { auto = toggle(e, ops[i + 1], auto); i++ }
                        trace.add("t")
                    }
                    else -> {
                        val a = e.feed(c)
                        when (a) {
                            TelexAction.Passthrough -> screen.append(c)
                            TelexAction.None -> {}
                            is TelexAction.Replace -> { removeLast(screen, a.backspaces); screen.append(a.insert) }
                        }
                        trace.add(tok(a))
                    }
                }
                i++
            }
        }
        return listOf(
            flagsField, ops, trace.joinToString("|"), screen.toString(),
            e.composed, e.rawKeystrokes, if (e.previousWordEnglish) "1" else "0",
        ).joinToString("\t")
    }

    @Test
    fun goldenCorpusMatches100Percent() {
        val stream = javaClass.classLoader.getResourceAsStream("golden.tsv.gz")
            ?: error("golden.tsv.gz missing — run `swift run gen-golden` in TelexCore/")
        var total = 0
        var failed = 0
        val samples = ArrayList<String>()
        BufferedReader(InputStreamReader(GZIPInputStream(stream), Charsets.UTF_8)).use { r ->
            while (true) {
                val line = r.readLine() ?: break
                if (line.isEmpty()) continue
                total++
                val t1 = line.indexOf('\t')
                val t2 = line.indexOf('\t', t1 + 1)
                val actual = replay(line.substring(0, t1), line.substring(t1 + 1, t2))
                if (actual != line) {
                    failed++
                    if (samples.size < 40) samples.add("expected: $line\n  actual: $actual")
                }
            }
        }
        println("golden: ${total - failed}/$total match")
        assertTrue("golden corpus empty", total > 10_000)
        assertEquals("golden mismatches ($failed/$total):\n" + samples.joinToString("\n"), 0, failed)
    }
}
