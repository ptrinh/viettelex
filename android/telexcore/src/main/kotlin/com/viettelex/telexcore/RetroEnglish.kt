// Port of TelexCore/Sources/TelexCore/RetroEnglish.swift (1:1) — RETROACTIVE English
// correction (TelexEngine.retroactiveEnglish, EXPERIMENTAL, default OFF, inert unless
// contextualEnglish is on). See the Swift file and docs/DESIGN.md for the design.
// ONE STRONG English word also makes the run certain: a frequent English word no Vietnamese
// syllable reads as (EnglishFrequency, en ≥ strongMin, vn = 0: "very", "fast") right after an
// anchored span of ≥ 2 rewrite candidates — "His car is fast." is fixed at "fast".
// Flip-back (TelexEngine.englishByFrequency, experimental): the same edit path rewrites a word
// the FREQUENCY rule turned English back to Vietnamese ("His hửng" → "hí hửng").
package com.viettelex.telexcore

/**
 * One screen edit that rewrites the words before the caret. Apply like
 * [TelexAction.Replace]: delete [backspaces] chars (UTF-16 units — every character involved
 * is precomposed BMP or ASCII) right before the caret, insert [insert]. [expected] is what
 * those chars are now: compare with the editor text and skip on mismatch.
 *
 * [flipBack]: the edit puts a word the frequency rule (`TelexEngine.englishByFrequency`) had
 * turned English BACK to Vietnamese ("His hửng" → "hí hửng"). It undoes the engine's own
 * guess, so integrators apply it AUTOMATICALLY even when retroactive English is in offer-only
 * (chip) mode — still only after the same text-before-caret check.
 */
data class RetroCorrection(
    val backspaces: Int,
    val expected: String,
    val insert: String,
    val words: Int,
    val flipBack: Boolean = false,
)

/** A committed word as the retroactive check sees it (Swift `RetroWord`). */
internal data class RetroWord(
    var raw: String,
    var shown: String,
    var english: Boolean,
    var candidate: Boolean,
    var cls: Int,
    var gap: Int,
    var leftNonEnglish: Boolean,
    var gateBit: Int = 0,
    var predBits: Int = 0,
    /** Committed as English that is STRONG on its own (EnglishFrequency: en ≥ strongMin, vn = 0). */
    var strong: Boolean = false,
    /** Restored to English by the frequency rule; [alt] = the Vietnamese composition it replaced. */
    var byFrequency: Boolean = false,
    var alt: String = "",
)

internal object RetroEnglish {
    const val CLS_P = 1 shl 0
    const val CLS_O = 1 shl 1
    const val CLS_D = 1 shl 2
    const val CLS_B = 1 shl 3
    const val CLS_R = 1 shl 4
    const val CLS_C = 1 shl 5
    const val CLS_X = 1 shl 6
    const val ANCHOR_MASK = CLS_P or CLS_D or CLS_R or CLS_C

    const val HISTORY_CAPACITY = 6
    const val WINDOW = 3
    const val MAX_GAP = 2

    /** Swift `isCandidateRaw` (lowercase ascii). */
    fun isCandidateRaw(w: String): Boolean =
        EnglishCollisions.words.contains(w) || EnglishContextWords.words.contains(w) ||
            EnglishContextWords.runKeepers.contains(w) || w == "was" || w == "wow" || w == "yes" || w == "queue" || w == "away"

    fun classBits(w: String): Int = EnglishContextWords.retroClasses[w] ?: 0

    fun pairAllowed(l: Int, r: Int): Boolean {
        if (l == 0) return true
        if ((l and (CLS_O or CLS_B or CLS_C)) != 0) return true
        if ((l and CLS_P) != 0 && (r == 0 || (r and CLS_B) != 0)) return true
        if ((l and CLS_D) != 0 && r == 0) return true
        if ((l and CLS_R) != 0 && (r == 0 || (r and (CLS_D or CLS_P or CLS_O)) != 0)) return true
        return false
    }

    /** Is lowercased raw [w] a STRONG English word (frequent, no Vietnamese reading)? */
    fun isStrongRaw(w: String): Boolean {
        val sc = EnglishFrequency.scores(w)
        if (sc < 0) return false
        return EnglishFrequency.vn(sc) == 0 && EnglishFrequency.en(sc) >= EnglishFrequency.strongMin
    }

    /** Swift `RetroEnglish.plan`: history indices to rewrite (ascending), or null. */
    fun plan(h: List<RetroWord>): IntArray? {
        val n = h.size
        if (n < 2 || !h[n - 1].english || h[n - 1].gap <= 0) return null
        // A run of ONE strong word ("fast", "very") — needs ≥ 2 rewritten words below.
        val strongEnd = !h[n - 2].english
        if (strongEnd && !h[n - 1].strong) return null
        var s = if (strongEnd) n - 1 else n - 2
        while (s > 0 && h[s].gap > 0 && h[s - 1].english) s--
        var lo = s
        var k = 0
        while (k < WINDOW && lo > 0 && h[lo].gap > 0 && (h[lo - 1].candidate || h[lo - 1].english)) { lo--; k++ }
        if (lo >= s) return null
        for (a in lo until s) {
            val picks = (a until s).filter { h[it].candidate }
            if (picks.isEmpty() || (strongEnd && picks.size < 2) || !anchors(h, a, picks)) continue
            var ok = true
            for (i in a until s) if (!pairAllowed(h[i].cls, h[i + 1].cls)) { ok = false; break }
            for (i in picks) {
                if (h[i].gateBit == 0) continue
                if (i == a || (h[i - 1].predBits and h[i].gateBit) == 0) { ok = false; break }
            }
            if (!ok) continue
            if (h[a].candidate && leftIsNonEnglish(h, a) && picks.size < 2) continue
            return picks.toIntArray()
        }
        return null
    }

    private fun anchors(h: List<RetroWord>, a: Int, picks: List<Int>): Boolean {
        val w = h[a]
        if ((w.cls and ANCHOR_MASK) != 0) return true
        if (w.candidate && (w.cls and CLS_B) != 0 && a + 1 < h.size && (h[a + 1].cls and CLS_P) != 0 &&
            h[a].gap <= 0
        ) return true
        if (w.english && !w.candidate &&
            picks.all { (h[it].cls and CLS_B) != 0 && (h[it].cls and CLS_X) == 0 }
        ) return true
        return false
    }

    private fun leftIsNonEnglish(h: List<RetroWord>, a: Int): Boolean {
        if (h[a].gap <= 0) return false
        if (a > 0) return !h[a - 1].english
        return h[a].leftNonEnglish
    }

    /** Swift `RetroEnglish.correction`. */
    fun correction(h: List<RetroWord>, picks: IntArray, flipBack: Boolean = false): RetroCorrection? {
        if (picks.isEmpty()) return null
        val first = picks[0]
        val e = StringBuilder()
        val r = StringBuilder()
        for (i in first until h.size) {
            if (i > first) repeat(h[i].gap) { e.append(' '); r.append(' ') }
            e.append(h[i].shown)
            r.append(if (i in picks) (if (flipBack) h[i].alt else h[i].raw) else h[i].shown)
        }
        var lcp = 0
        while (lcp < e.length && lcp < r.length && e[lcp] == r[lcp]) lcp++
        return RetroCorrection(e.length - lcp, e.substring(lcp), r.substring(lcp), picks.size, flipBack)
    }
}
