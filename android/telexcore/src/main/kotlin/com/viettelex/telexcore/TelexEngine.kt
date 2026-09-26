// Port of TelexCore/Sources/TelexCore/TelexEngine.swift (1:1, behaviour identical —
// verified by the golden corpus generated from the Swift engine, see GenGolden).
//
// Hot path works over fixed-capacity (32) primitive arrays allocated once per
// instance: raw keys, the incremental parse state (letters as parallel arrays),
// render scratch and diff buffers. Per keystroke the only allocation is the
// `TelexAction.Replace` + its insert String when the screen actually changes —
// exactly what the Swift engine allocates.
//
// Swift `TelexEngine` is a value type; this is a class. Use `copy()` for an
// independent snapshot.
package com.viettelex.telexcore

sealed class TelexAction {
    /** Not handled by the engine; let the system insert the character. */
    object Passthrough : TelexAction() { override fun toString() = "Passthrough" }
    /** Replace `backspaces` trailing characters already on screen with `insert`. */
    data class Replace(val backspaces: Int, val insert: String) : TelexAction()
    /** Nothing to do. */
    object None : TelexAction() { override fun toString() = "None" }
}

/** Vietnamese tone (Swift `Tone`; ordinal == Swift rawValue). */
enum class Tone { NONE, ACUTE, GRAVE, HOOK, TILDE, DOT }

class TelexEngine {

    /** "Bỏ dấu tự do" (free mark placement). */
    var freeMarking = false
    /** Modern tone placement for open oa/oe/uy (hoà, khoẻ, thuý). */
    var modernTone = false
    /** Live spell-check: stop transforming once the word can't be Vietnamese. */
    var liveSpellCheck = false
    /** Simple Telex: a standalone `w` stays literal. */
    var simpleTelex = false
    /** Teencode spelling (w→qu, z/dz→d, k before a/o/u, informal rimes). Engine default ON. */
    var teencode = true
    /** Quick Telex: cc→ch, gg→gi, kk→kh, nn→ng, qq→qu, pp→ph, tt→th (word-initial). */
    var quickTelex = false
    /** Bracket vowels: `[`→ơ, `]`→ư, `{`/`}` uppercase. */
    var bracketVowels = false
    /** VNI input method (digits carry the diacritics). */
    var vniMode = false
    /** Context-based English decision (experimental). */
    var contextualEnglish = false
    /** Whether the PREVIOUS committed word was classified English. */
    var previousWordEnglish = false
        private set
    /** Force-restore English words that collide with valid syllables. Default ON. */
    var englishWordRestore = true
    /** Prefer a valid Vietnamese syllable over a standalone collision-table hit. */
    var collisionPrefersVietnamese = false

    // Raw keystrokes (ascii, case preserved).
    private val raw = IntArray(CAPACITY)
    private var rawCount = 0
    private var overflowed = false

    // Current on-screen composition (scalar values).
    private val out = IntArray(CAPACITY)
    private var outCount = 0

    // Scratch buffers.
    private val scratch = IntArray(CAPACITY)
    private val rBase = IntArray(CAPACITY)       // renderLetters
    private val rMark = IntArray(CAPACITY)
    private val rUpper = BooleanArray(CAPACITY)
    private val basesScratch = IntArray(CAPACITY)
    private val rawLetter = IntArray(CAPACITY) { -1 }
    private val toneKeys = IntArray(CAPACITY)
    private val vowelIdx = IntArray(CAPACITY)
    private val valBuf = IntArray(CAPACITY + 1)  // composedIsValidSyllable stack twin
    private val headBuf = IntArray(CAPACITY + 1) // isValidHead stack twin
    private val wordBuf = IntArray(CAPACITY)     // lowercase word for dictionary probes

    // Incremental parse state.
    private val lBase = IntArray(CAPACITY)       // letters
    private val lMark = IntArray(CAPACITY)
    private val lUpper = BooleanArray(CAPACITY)
    private var pCount = 0
    private var pTone = T.NONE
    private var pToneKeyCount = 0
    private var pCancelled = false
    private var pToneCancelSpan = 0
    private var pToneCancelAt = -1
    private var pProcessed = 0
    private var pFreeMarking = false
    private var pSimpleTelex = false
    private var pQuickTelex = false
    private var pVniMode = false
    private var pBracketVowels = false
    private var pLiveSpellCheck = false

    private var disabledAtCount = Int.MAX_VALUE
    private var markCancelled = false
    private var toneCancelAt = -1
    private var toneCancelSpan = 0
    private var pFoldTones = false
    // Current parse was built with pFoldTones (freeze folded a pending tone) — see Swift.
    private var tonesFolded = false
    private var lastEffTone = T.NONE
    private var upperToneKey = false

    // Re-open snapshot.
    private val reopenRaw = IntArray(CAPACITY)
    private val reopenOut = IntArray(CAPACITY)
    private var reopenRawCount = 0
    private var reopenOutCount = 0
    private var reopenPrevEnglish = false

    val isEmpty: Boolean get() = rawCount == 0

    /** Deep copy (Swift value semantics). */
    fun copy(): TelexEngine = TelexEngine().also { copyInto(it) }

    /** Ghi đè toàn bộ trạng thái của [e] bằng bản này — checkpoint không cấp phát (EngineBridge.undoLastLetter). */
    fun copyInto(e: TelexEngine) {
        e.freeMarking = freeMarking; e.modernTone = modernTone; e.liveSpellCheck = liveSpellCheck
        e.simpleTelex = simpleTelex; e.teencode = teencode; e.quickTelex = quickTelex
        e.bracketVowels = bracketVowels; e.vniMode = vniMode; e.contextualEnglish = contextualEnglish
        e.previousWordEnglish = previousWordEnglish; e.englishWordRestore = englishWordRestore
        e.collisionPrefersVietnamese = collisionPrefersVietnamese
        raw.copyInto(e.raw); e.rawCount = rawCount; e.overflowed = overflowed
        out.copyInto(e.out); e.outCount = outCount
        scratch.copyInto(e.scratch)
        rBase.copyInto(e.rBase); rMark.copyInto(e.rMark); rUpper.copyInto(e.rUpper)
        basesScratch.copyInto(e.basesScratch); rawLetter.copyInto(e.rawLetter)
        toneKeys.copyInto(e.toneKeys); vowelIdx.copyInto(e.vowelIdx)
        lBase.copyInto(e.lBase); lMark.copyInto(e.lMark); lUpper.copyInto(e.lUpper)
        e.pCount = pCount; e.pTone = pTone; e.pToneKeyCount = pToneKeyCount
        e.pCancelled = pCancelled; e.pToneCancelSpan = pToneCancelSpan; e.pToneCancelAt = pToneCancelAt
        e.pProcessed = pProcessed; e.pFreeMarking = pFreeMarking; e.pSimpleTelex = pSimpleTelex
        e.pQuickTelex = pQuickTelex; e.pVniMode = pVniMode; e.pBracketVowels = pBracketVowels
        e.pLiveSpellCheck = pLiveSpellCheck; e.disabledAtCount = disabledAtCount
        e.markCancelled = markCancelled; e.toneCancelAt = toneCancelAt; e.toneCancelSpan = toneCancelSpan
        e.pFoldTones = pFoldTones; e.tonesFolded = tonesFolded; e.lastEffTone = lastEffTone; e.upperToneKey = upperToneKey
        reopenRaw.copyInto(e.reopenRaw); reopenOut.copyInto(e.reopenOut)
        e.reopenRawCount = reopenRawCount; e.reopenOutCount = reopenOutCount
        e.reopenPrevEnglish = reopenPrevEnglish
    }

    // MARK: - Public entry points

    /** RE-EDIT an already committed word; true only when the word round-trips exactly. */
    fun seed(word: String): Boolean {
        reset()
        if (word.isEmpty() || word.codePointCount(0, word.length) > CAPACITY / 2) return false
        val keys = seedKeystrokes(word, vniMode) ?: return false
        if (keys.length > CAPACITY) { reset(); return false }
        for (ch in keys) feed(ch)
        if (composed != word) { reset(); return false }
        return true
    }

    /** Feed one typed character. Only ascii letters compose. */
    fun feed(ch: Char): TelexAction {
        val ascii = ch.code
        if (ascii >= 128 ||
            !(isLetter(ascii) || (vniMode && isDigit(ascii)) || (bracketVowels && bracketBase(ascii) >= 0))
        ) return TelexAction.Passthrough
        if (rawCount >= CAPACITY) { overflowed = true; return TelexAction.Passthrough }

        if (rawCount == 0) { reopenRawCount = 0; reopenOutCount = 0 }

        raw[rawCount] = ascii
        rawCount++

        if (pLiveSpellCheck != liveSpellCheck) {
            recomputeFreeze()
            rebuildFrozenAware()
        } else if (pProcessed != rawCount - 1 ||
            pFreeMarking != freeMarking || pSimpleTelex != simpleTelex ||
            pQuickTelex != quickTelex || pVniMode != vniMode ||
            pBracketVowels != bracketVowels
        ) {
            rebuildFrozenAware()
        } else {
            parseStep(rawCount - 1)
            pProcessed = rawCount
        }

        var newCount = render()
        snapshotCancel()

        if (disabledAtCount == Int.MAX_VALUE && upperToneKey) {
            disabledAtCount = 0
            rebuildParseState()
            tonesFolded = false
            newCount = render()
            snapshotCancel()
        }

        if (liveSpellCheck && disabledAtCount == Int.MAX_VALUE && !prefixIsValid(newCount) &&
            elongationHeadCount(newCount, pTone) <= 0
        ) {
            disabledAtCount = rawCount
            if (pTone != T.NONE) {
                pFoldTones = true
                rebuildParseState()
                pFoldTones = false
                tonesFolded = true
                newCount = render()
                snapshotCancel()
            }
        }

        if (liveSpellCheck && disabledAtCount != Int.MAX_VALUE && !upperToneKey &&
            rawCount >= 2 && raw[rawCount - 1] == raw[rawCount - 2]
        ) {
            recomputeFreeze()
            rebuildFrozenAware()
            newCount = render()
            snapshotCancel()
        }

        if (newCount == outCount + 1 && scratch[newCount - 1] == ascii &&
            commonPrefixLength(outCount) == outCount
        ) {
            copyOut(newCount)
            return TelexAction.Passthrough
        }

        val action = diff(newCount)
        copyOut(newCount)
        return action
    }

    private fun snapshotCancel() {
        markCancelled = pCancelled
        toneCancelAt = pToneCancelAt
        toneCancelSpan = pToneCancelSpan
    }

    /** Backspace: delete the whole last DISPLAYED character, then reconcile. */
    fun backspace(): TelexAction {
        if (rawCount <= 0) return TelexAction.Passthrough
        if (overflowed) return TelexAction.Passthrough

        rebuildFrozenAware()
        render()

        if (pCount == 0) {
            rawCount -= 1
        } else {
            val last = pCount - 1
            var w = 0
            for (r in 0 until rawCount) {
                if (rawLetter[r] != last) { raw[w] = raw[r]; w++ }
            }
            rawCount = w
        }

        recomputeFreeze()
        rebuildFrozenAware()
        val newCount = render()
        snapshotCancel()
        val action = diff(newCount)
        copyOut(newCount)
        return action
    }

    /** Word boundary reached. Optionally auto-restore raw keystrokes. Resets the word. */
    fun commitBoundary(autoRestore: Boolean): TelexAction {
        try {
            if (rawCount <= 0) { reopenRawCount = 0; reopenOutCount = 0; return TelexAction.None }
            if (overflowed) {
                if (contextualEnglish) previousWordEnglish = false
                reopenRawCount = 0; reopenOutCount = 0
                return TelexAction.None
            }
            val wantsRestore = autoRestore && outCount > 0 && shouldRestoreRaw()
            var action: TelexAction = TelexAction.None
            if (wantsRestore && compositionDiffersFromRaw()) {
                val limit = minOf(rawCount, outCount)
                var lcp = 0
                while (lcp < limit && raw[lcp] == out[lcp]) lcp++
                val backspaces = outCount - lcp
                val sb = StringBuilder(rawCount - lcp)
                for (i in lcp until rawCount) sb.append(raw[i].toChar())
                action = TelexAction.Replace(backspaces, sb.toString())
            }
            captureReopen(wantsRestore)
            updateContext(wantsRestore)
            return action
        } finally {
            resetWord()
        }
    }

    private fun captureReopen(restored: Boolean) {
        if (restored || rawCount <= 0) { reopenRawCount = 0; reopenOutCount = 0; return }
        for (i in 0 until rawCount) reopenRaw[i] = raw[i]
        for (i in 0 until outCount) reopenOut[i] = out[i]
        reopenRawCount = rawCount
        reopenOutCount = outCount
        reopenPrevEnglish = previousWordEnglish
    }

    /** Discard the re-open snapshot. */
    fun forgetLastCommit() {
        reopenRawCount = 0
        reopenOutCount = 0
    }

    /** True while `reopenLastCommit()` has something to put back. */
    val canReopenLastCommit: Boolean get() = rawCount == 0 && reopenRawCount > 0

    /** RE-OPEN the word the last boundary committed (⌫ on the boundary char). */
    fun reopenLastCommit(): String? {
        if (!canReopenLastCommit) return null
        val n = reopenRawCount
        val expected = reopenOutCount
        val prevEnglish = reopenPrevEnglish
        // reset() clears the snapshot counts but not the buffers — replay from them.
        reset()
        previousWordEnglish = prevEnglish
        for (i in 0 until n) feed(reopenRaw[i].toChar())
        if (rawCount != n || outCount != expected) { reset(); return null }
        for (i in 0 until outCount) if (out[i] != reopenOut[i]) { reset(); return null }
        return composed
    }

    // MARK: - Boundary restore decision (non-mutating apart from scratch buffers)

    private fun shouldRestoreRaw(): Boolean {
        if (rawCount >= 3) {
            var allW = true
            for (i in 0 until rawCount) if ((raw[i] or 0x20) != 'w'.code) { allW = false; break }
            if (allW) return true
        }
        if (markCancelled) {
            if (composedIsValidSyllable()) return false
            if (toneCancelSpan > 1) {
                return !composedIsRecognizedEnglish() || rawIsEnglishContextWord(false)
            }
            if (toneCancelAt >= 0 && toneCancelAt < rawCount - 1 && rawIsEnglishCollision()) return true
            if (isTeencodeKeep()) return false
            // Mark doubler + tone folded at the freeze ("cheese" → "chese"): restore raw.
            if (toneCancelAt < 0 && tonesFolded) return true
            return composedHasDiacritic()
        }
        if (rawIsEnglishCollision() && !(collisionPrefersVietnamese && composedIsValidSyllable())) return true
        if (upperToneKey || rawIsEnglishException() ||
            (!composedIsValidSyllable() && !isTeencodeKeep())
        ) return true
        if (contextualEnglish && previousWordEnglish &&
            (rawIsEnglishContextWord(true) || (collisionPrefersVietnamese && rawIsEnglishCollision()))
        ) return true
        return false
    }

    private fun composedHasDiacritic(): Boolean {
        if (pTone != T.NONE) return true
        for (k in 0 until pCount) if (lMark[k] != Mark.NONE) return true
        return false
    }

    private fun composedIsRecognizedEnglish(): Boolean {
        if (outCount < 2 || outCount > 12) return false
        val n = lowerAsciiInto(out, outCount, 12)
        if (n < 0) return false
        return EnglishCollisions.words.contains(wordBuf, n) || EnglishContextWords.words.contains(wordBuf, n)
    }

    /**
     * Lowercase ascii-letter copy of `src[0 until count]` into `wordBuf` (the String
     * the Swift engine builds for its Set lookups, minus the allocation). Returns the
     * length, or -1 when empty / longer than `maxLen` / not all ascii letters.
     */
    private fun lowerAsciiInto(src: IntArray, count: Int, maxLen: Int): Int {
        if (count <= 0 || count > maxLen) return -1
        for (i in 0 until count) {
            var b = src[i]
            if (b in 'A'.code..'Z'.code) b = b or 0x20
            if (b < 'a'.code || b > 'z'.code) return -1
            wordBuf[i] = b
        }
        return count
    }

    private fun isRecognizedEnglish(): Boolean =
        rawIsEnglishContextWord(false) || rawIsEnglishCollision() || rawIsEnglishException()

    private fun classifyWordContext(restored: Boolean): Int {
        if (!restored && compositionHasDiacritic()) return CTX_VIETNAMESE
        if (isRecognizedEnglish()) return CTX_ENGLISH
        val wn = lowerAsciiInto(out, outCount, EnglishContextWords.maxLength)   // composedAsciiWord
        if (wn > 0) {
            val neutral = EnglishContextWords.neutralLoanwords.contains(wordBuf, wn)
            if (EnglishContextWords.words.contains(wordBuf, wn) || EnglishCollisions.words.contains(wordBuf, wn) || neutral) {
                return if (neutral) CTX_NEUTRAL else CTX_ENGLISH
            }
        }
        if (rawIsNeutralLoanword() || rawIsEnglishContextWord(true)) return CTX_NEUTRAL
        if (!restored && SyllableValidator.isValidSyllableScalars(out, outCount, teencode, valBuf)) return CTX_VIETNAMESE
        if (rawCount <= 2) return CTX_NEUTRAL
        return CTX_ENGLISH
    }

    private fun rawIsNeutralLoanword(): Boolean {
        val n = lowerAsciiInto(raw, rawCount, EnglishContextWords.maxLength)
        return n > 0 && EnglishContextWords.neutralLoanwords.contains(wordBuf, n)
    }

    private fun updateContext(restored: Boolean) {
        if (!contextualEnglish || rawCount <= 0) return
        when (classifyWordContext(restored)) {
            CTX_ENGLISH -> previousWordEnglish = true
            CTX_VIETNAMESE -> previousWordEnglish = false
            else -> {}
        }
    }

    private fun rawIsEnglishContextWord(includingRestoreOnly: Boolean): Boolean {
        val n = lowerAsciiInto(raw, rawCount, EnglishContextWords.maxLength)
        if (n <= 0) return false
        if (EnglishContextWords.words.contains(wordBuf, n)) return true
        return includingRestoreOnly && EnglishContextWords.restoreOnly.contains(wordBuf, n)
    }

    /** Clear the cross-word English context (focus / app switch). */
    fun resetContext() { previousWordEnglish = false }

    /** Final text to commit at a word boundary, with auto-restore applied. Resets the word. */
    fun commitText(autoRestore: Boolean): String {
        try {
            if (overflowed) {
                if (contextualEnglish) previousWordEnglish = false
                reopenRawCount = 0; reopenOutCount = 0
                return composed
            }
            val wantsRestore = autoRestore && outCount > 0 && shouldRestoreRaw()
            captureReopen(wantsRestore)
            updateContext(wantsRestore)
            return if (wantsRestore) rawKeystrokes else composed
        } finally {
            resetWord()
        }
    }

    /** Non-mutating twin of `commitText`: what the boundary WILL commit. */
    fun peekCommitText(autoRestore: Boolean): String {
        if (overflowed) return composed
        if (autoRestore && outCount > 0 && shouldRestoreRaw()) return rawKeystrokes
        return composed
    }

    private fun rawIsEnglishCollision(): Boolean {
        if (!englishWordRestore) return false
        if (rawCount < 2 || rawCount > 12) return false
        if (!compositionDiffersFromRaw()) return false
        if ((raw[0] or 0x20) == 'w'.code) {
            val wTransformed = pCount > 0 && rBase[0] == 'u'.code && rMark[0] == Mark.HORN
            if (!wTransformed) return false
        }
        val n = lowerAsciiInto(raw, rawCount, 12)
        return n > 0 && EnglishCollisions.words.contains(wordBuf, n)
    }

    private fun rawIsEnglishException(): Boolean {
        if (pCount <= 0) return false
        val wTransformed = rBase[0] == 'u'.code && rMark[0] == Mark.HORN
        outer@ for (word in ENGLISH_EXCEPTIONS) {
            if (word.size != rawCount) continue
            if (word[0] == 'w'.code && !wTransformed) continue
            for (i in 0 until rawCount) if (lowercased(raw[i]) != word[i]) continue@outer
            return true
        }
        return false
    }

    /** Teencode onset code: 0 none, 1 w→qu (skip 1), 2 z→d (skip 1), 3 dz→d (skip 2). */
    private fun teencodeOnset(): Int {
        if (!teencode || pCount < 2 || rMark[0] != Mark.NONE) return 0
        return when (rBase[0]) {
            'w'.code -> 1
            'z'.code -> 2
            'd'.code -> if (pCount >= 3 && rBase[1] == 'z'.code && rMark[1] == Mark.NONE) 3 else 0
            else -> 0
        }
    }

    private fun onsetSkip(code: Int) = if (code == 3) 2 else 1

    /** Writes the canonical onset classes into buf, returns the count written. */
    private fun writeCanon(code: Int, buf: IntArray): Int {
        return if (code == 1) {
            buf[0] = 'q' - 'a'; buf[1] = 'u' - 'a'; 2
        } else {
            buf[0] = 'd' - 'a'; 1
        }
    }

    private fun isAbbreviationPrefix(upper: Boolean): Boolean {
        if (pCount <= 0) return false
        for (k in 0 until pCount) {
            if (isVowelAscii(lBase[k]) || lUpper[k] != upper) return false
        }
        return true
    }

    private fun abbreviationDoublerException(lower: Int, upper: Boolean): Boolean =
        !pVniMode && lower == 'd'.code && isAbbreviationPrefix(upper)

    private fun composedIsValidSyllable(): Boolean {
        if (pCount >= 1 && lastEffTone == T.NONE && rBase[0] == 'd'.code && rMark[0] == Mark.BAR) {
            var bareConsonantsOnly = true
            for (k in 1 until pCount) {
                if (rMark[k] != Mark.NONE || isVowelAscii(rBase[k])) { bareConsonantsOnly = false; break }
            }
            if (bareConsonantsOnly) return true
        }
        if (lastEffTone == T.NONE && rawCount >= 2) {
            var sameCase = true
            val firstIsUpper = isUpperAscii(raw[0])
            for (i in 0 until rawCount) if (isUpperAscii(raw[i]) != firstIsUpper) { sameCase = false; break }
            if (sameCase) {
                var hasBar = false
                var onlyBar = true
                for (k in 0 until pCount) {
                    if (isVowelAscii(rBase[k])) { onlyBar = false; break }
                    if (rBase[k] == 'd'.code && rMark[k] == Mark.BAR) hasBar = true
                    else if (rMark[k] != Mark.NONE) { onlyBar = false; break }
                }
                if (hasBar && onlyBar) return true
            }
        }
        val buf = valBuf
        val onset = teencodeOnset()
        val stacksTeencodeRime = pCount >= 3 &&
            rBase[pCount - 2] == 'i'.code && rMark[pCount - 2] == Mark.NONE &&
            rBase[pCount - 1] == 'e'.code && rMark[pCount - 1] == Mark.NONE &&
            onset != 0 && onsetSkip(onset) == pCount - 2
        if (!stacksTeencodeRime && pCount < CAPACITY - 1 && onset != 0) {
            var n = writeCanon(onset, buf)
            for (k in onsetSkip(onset) until pCount) {
                buf[n] = Tables.letterClass(rBase[k], rMark[k]); n++
            }
            if (SyllableValidator.isValidSyllable(buf, n, lastEffTone, teencode)) return true
        }
        for (k in 0 until pCount) buf[k] = Tables.letterClass(rBase[k], rMark[k])
        return SyllableValidator.isValidSyllable(buf, pCount, lastEffTone, teencode)
    }

    // MARK: - Teencode elongation

    private fun elongationHeadCount(count: Int, tone: Int): Int {
        val minRun = 3
        if (count < minRun + 1) return -1
        val lastB = rBase[count - 1]
        val lastM = rMark[count - 1]
        for (j in (count - minRun) until (count - 1)) {
            if (rBase[j] != lastB || rMark[j] != lastM) return -1
        }
        var runStart = count - minRun
        while (runStart > 0 && rBase[runStart - 1] == lastB && rMark[runStart - 1] == lastM) runStart--
        if (runStart < 1) runStart = 1
        var k = runStart
        while (k <= count - minRun) {
            if (isValidHead(k, tone)) return k
            k++
        }
        return -1
    }

    private fun isValidHead(k: Int, tone: Int): Boolean {
        if (k < 1 || k > CAPACITY) return false
        var t = tone
        if ((t == T.GRAVE || t == T.HOOK || t == T.TILDE) && hasStopCoda(k) &&
            !(t == T.GRAVE && isUkRime(k))
        ) t = T.NONE
        val buf = headBuf
        val onset = teencodeOnset()
        if (onset != 0 && onsetSkip(onset) < k) {
            var n = writeCanon(onset, buf)
            for (j in onsetSkip(onset) until k) {
                buf[n] = Tables.letterClass(rBase[j], rMark[j]); n++
            }
            if (SyllableValidator.isValidSyllable(buf, n, t, teencode)) return true
        }
        for (j in 0 until k) buf[j] = Tables.letterClass(rBase[j], rMark[j])
        return SyllableValidator.isValidSyllable(buf, k, t, teencode)
    }

    private fun isTeencodeKeep(): Boolean = elongationHeadCount(pCount, lastEffTone) > 0

    private fun compositionDiffersFromRaw(): Boolean {
        if (outCount != rawCount) return true
        for (i in 0 until outCount) if (out[i] != raw[i]) return true
        return false
    }

    private fun compositionHasDiacritic(): Boolean {
        for (i in 0 until outCount) if (out[i] > 127) return true
        return false
    }

    private fun letterCreatedByW(idx: Int): Boolean {
        for (i in 0 until rawCount) {
            if (rawLetter[i] == idx) return raw[i] == 'w'.code || raw[i] == 'W'.code
        }
        return false
    }

    private fun uaUuPredecessorAllowsRetarget(pred: Int): Boolean {
        val m = lMark[pred]
        return m == Mark.NONE || (m == Mark.HORN && !letterCreatedByW(pred))
    }

    private fun hasLowercaseBefore(at: Int): Boolean {
        for (i in 0 until at) if (raw[i] >= 'a'.code && raw[i] <= 'z'.code) return true
        return false
    }

    /** Drop the current word AND the re-open snapshot. */
    fun reset() {
        if (rawCount > 0) previousWordEnglish = false
        resetWord()
        reopenRawCount = 0
        reopenOutCount = 0
    }

    private fun resetWord() {
        rawCount = 0
        outCount = 0
        markCancelled = false
        toneCancelAt = -1
        toneCancelSpan = 0
        upperToneKey = false
        overflowed = false
        disabledAtCount = Int.MAX_VALUE
        tonesFolded = false
        pCount = 0
        pTone = T.NONE
        pToneKeyCount = 0
        pCancelled = false
        pToneCancelAt = -1
        pToneCancelSpan = 0
        pProcessed = 0
    }

    private fun prefixIsValid(n: Int): Boolean {
        var o = 0
        var start = 0
        if (teencode && n >= 1 && lMark[0] == Mark.NONE && n < CAPACITY - 1) {
            when (lBase[0]) {
                'w'.code -> { basesScratch[0] = 'q'.code; basesScratch[1] = 'u'.code; o = 2; start = 1 }
                'z'.code -> { basesScratch[0] = 'd'.code; o = 1; start = 1 }
                'd'.code -> if (n >= 2 && lBase[1] == 'z'.code && lMark[1] == Mark.NONE) {
                    basesScratch[0] = 'd'.code; o = 1; start = 2
                }
            }
        }
        for (k in start until n) {
            basesScratch[o] = lBase[k] or (if (lMark[k] != Mark.NONE) 0x80 else 0)
            o++
        }
        return SyllableValidator.isValidPrefix(basesScratch, o, teencode)
    }

    // MARK: - Caller helpers

    /** TRUE while the current word has exceeded the 32-key capacity. */
    val isOverflowed: Boolean get() = overflowed

    /** Current composed word. */
    val composed: String
        get() {
            val sb = StringBuilder(outCount)
            for (i in 0 until outCount) sb.appendCodePoint(out[i])
            return sb.toString()
        }

    /** The raw keystrokes typed for the current word. */
    val rawKeystrokes: String
        get() {
            val sb = StringBuilder(rawCount)
            for (i in 0 until rawCount) sb.append(raw[i].toChar())
            return sb.toString()
        }

    /** Test-only: live-spell-check freeze index (Int.MAX_VALUE = not frozen). */
    internal val debugFreezeAt: Int get() = disabledAtCount
    internal val debugCancelSnapshot: Triple<Boolean, Int, Int> get() = Triple(markCancelled, toneCancelAt, toneCancelSpan)
    internal val debugParseCancelState: Triple<Boolean, Int, Int> get() = Triple(pCancelled, pToneCancelAt, pToneCancelSpan)

    // MARK: - Rendering

    private fun copyOut(n: Int) {
        System.arraycopy(scratch, 0, out, 0, n)
        outCount = n
    }

    private fun render(): Int {
        val count = pCount
        System.arraycopy(lBase, 0, rBase, 0, count)
        System.arraycopy(lMark, 0, rMark, 0, count)
        System.arraycopy(lUpper, 0, rUpper, 0, count)

        for (k in 1 until maxOf(1, count)) {
            if (rBase[k - 1] != 'u'.code || rBase[k] != 'o'.code) continue
            val prevHorn = rMark[k - 1] == Mark.HORN
            val curHorn = rMark[k] == Mark.HORN
            if (prevHorn == curHorn) continue
            val oIsLast = k == count - 1
            val isQuGlide = k >= 2 && rBase[k - 2] == 'q'.code
            if (!oIsLast && !isQuGlide) {
                rMark[k - 1] = Mark.HORN
                rMark[k] = Mark.HORN
            }
        }

        var effTone = pTone
        var toneScope = count
        if (pTone != T.NONE) {
            val head = elongationHeadCount(count, pTone)
            if (head > 0) toneScope = head
        }
        var toneIdx = if (pTone == T.NONE) -1 else toneVowelIndex(toneScope)
        if (toneIdx >= 0 && (effTone == T.GRAVE || effTone == T.HOOK || effTone == T.TILDE) &&
            hasStopCoda(toneScope) && !(effTone == T.GRAVE && isUkRime(toneScope))
        ) {
            effTone = T.NONE
            toneIdx = -1
        }
        val target = if (toneIdx >= 0) toneIdx else maxOf(0, count - 1)
        for (j in 0 until pToneKeyCount) rawLetter[toneKeys[j]] = target
        lastEffTone = effTone

        for (k in 0 until count) {
            var scalar = Tables.markedScalar(rBase[k], rMark[k], rUpper[k])
            if (k == toneIdx) scalar = Tables.applyTone(scalar, effTone)
            scratch[k] = scalar
        }
        return count
    }

    // MARK: - Incremental parse

    /** Circumflex the doubler target; an o inside ươ also un-horns the u (ươ → uô). */
    private fun setCircumflex(k: Int) {
        lMark[k] = Mark.CIRCUMFLEX
        if (lBase[k] == 'o'.code && k >= 1 && lBase[k - 1] == 'u'.code && lMark[k - 1] == Mark.HORN) {
            lMark[k - 1] = Mark.NONE
        }
    }

    private fun rebuildFrozenAware() {
        rebuildParseState()
        tonesFolded = false
        if (disabledAtCount != Int.MAX_VALUE && pTone != T.NONE) {
            pFoldTones = true
            rebuildParseState()
            pFoldTones = false
            tonesFolded = true
        }
    }

    private fun recomputeFreeze() {
        if (disabledAtCount == 0 && upperToneKey && !liveSpellCheck) return
        val full = rawCount
        disabledAtCount = Int.MAX_VALUE
        if (!liveSpellCheck) return
        var r = 1
        while (r <= full) {
            rawCount = r
            rebuildParseState()
            if (disabledAtCount == Int.MAX_VALUE && pCount > 0 && !prefixIsValid(pCount)) {
                render()
                if (elongationHeadCount(pCount, pTone) <= 0) disabledAtCount = r
            }
            r++
        }
        rawCount = full
        if (disabledAtCount != Int.MAX_VALUE) {
            val frozenAt = disabledAtCount
            disabledAtCount = Int.MAX_VALUE
            rebuildParseState()
            render()
            if (elongationHeadCount(pCount, pTone) <= 0) disabledAtCount = frozenAt
        }
    }

    private fun rebuildParseState() {
        pCount = 0
        pTone = T.NONE
        pToneKeyCount = 0
        pCancelled = false
        pToneCancelAt = -1
        pToneCancelSpan = 0
        upperToneKey = false
        pFreeMarking = freeMarking
        pSimpleTelex = simpleTelex
        pQuickTelex = quickTelex
        pVniMode = vniMode
        pBracketVowels = bracketVowels
        pLiveSpellCheck = liveSpellCheck
        for (i in 0 until rawCount) rawLetter[i] = -1
        for (i in 0 until rawCount) parseStep(i)
        pProcessed = rawCount
    }

    private fun literal(at: Int, base: Int, upper: Boolean) {
        appendLetter(base, Mark.NONE, upper)
        rawLetter[at] = pCount - 1
    }

    private fun parseStep(at: Int) {
        val key = raw[at]
        val lower = lowercased(key)
        val upper = isUpperAscii(key)

        if (pCancelled || (at >= disabledAtCount && !abbreviationDoublerException(lower, upper))) {
            literal(at, lower, upper); return
        }

        if (pBracketVowels) {
            val bb = bracketBase(key)
            if (bb >= 0) {
                appendLetter(bb, Mark.HORN, key == '{'.code || key == '}'.code)
                rawLetter[at] = pCount - 1
                return
            }
        }

        if (pVniMode) {
            parseStepVNI(at, key, lower, upper)
            return
        }

        val t = toneForKey(lower)
        if (t >= 0) {
            if (pFoldTones) { literal(at, lower, upper); return }
            if (hasVowel(pCount)) {
                if (pTone == t) {
                    pTone = T.NONE
                    pCancelled = true; pToneCancelAt = at
                    pToneCancelSpan = if (pToneKeyCount > 0) at - toneKeys[pToneKeyCount - 1] else 1
                    literal(at, lower, upper)
                    for (j in 0 until pToneKeyCount) {
                        if (rawLetter[toneKeys[j]] == -1) rawLetter[toneKeys[j]] = pCount - 1
                    }
                    pToneKeyCount = 0
                } else if (stopCodaRejectsTone(t)) {
                    literal(at, lower, upper)
                } else {
                    pTone = t
                    if (upper && hasLowercaseBefore(at)) upperToneKey = true
                    rawLetter[at] = -1
                    toneKeys[pToneKeyCount] = at; pToneKeyCount++
                }
            } else {
                literal(at, lower, upper)
            }
            return
        }

        if (lower == 'z'.code) {
            if (pTone != T.NONE) {
                pToneCancelAt = at
                pToneCancelSpan = if (pToneKeyCount > 0) at - toneKeys[pToneKeyCount - 1] else 1
                pTone = T.NONE
                if (upper && hasLowercaseBefore(at)) upperToneKey = true
                rawLetter[at] = -1
                toneKeys[pToneKeyCount] = at; pToneKeyCount++
            } else {
                literal(at, lower, upper)
            }
            return
        }

        if (lower == 'w'.code) {
            var tIdx = -1
            var k = pCount - 1
            while (k >= 0) {
                val b = lBase[k]
                if (b == 'a'.code || b == 'o'.code || b == 'u'.code) { tIdx = k; break }
                if (!freeMarking && !isVowelAscii(b)) break
                k--
            }
            if (tIdx >= 1 && lBase[tIdx] == 'a'.code && lMark[tIdx] == Mark.NONE &&
                lBase[tIdx - 1] == 'u'.code && uaUuPredecessorAllowsRetarget(tIdx - 1) &&
                !(tIdx >= 2 && lBase[tIdx - 2] == 'q'.code)
            ) tIdx--
            if (tIdx >= 1 && lBase[tIdx] == 'u'.code && lMark[tIdx] == Mark.NONE &&
                lBase[tIdx - 1] == 'u'.code && uaUuPredecessorAllowsRetarget(tIdx - 1) &&
                !(tIdx >= 2 && lBase[tIdx - 2] == 'q'.code)
            ) tIdx--
            if (tIdx >= 0) {
                val pb = lBase[tIdx]
                val pm = lMark[tIdx]
                if (pm == Mark.NONE && pb == 'a'.code) {
                    lMark[tIdx] = Mark.BREVE; rawLetter[at] = tIdx; return
                }
                if (pm == Mark.NONE && (pb == 'o'.code || pb == 'u'.code)) {
                    lMark[tIdx] = Mark.HORN; rawLetter[at] = tIdx; return
                }
                if (pm == Mark.BREVE && pb == 'a'.code) {
                    lMark[tIdx] = Mark.NONE
                    pCancelled = true
                    literal(at, 'w'.code, upper); return
                }
                if (pm == Mark.HORN && (pb == 'o'.code || pb == 'u'.code)) {
                    lMark[tIdx] = Mark.NONE
                    pCancelled = true
                    if (pb == 'u'.code && letterCreatedByW(tIdx)) {
                        lBase[tIdx] = 'w'.code
                        rawLetter[at] = tIdx
                        return
                    }
                    literal(at, 'w'.code, upper); return
                }
            }
            if (!simpleTelex && standaloneHornUAllowed(pCount)) {
                appendLetter('u'.code, Mark.HORN, upper)
            } else {
                appendLetter('w'.code, Mark.NONE, upper)
            }
            rawLetter[at] = pCount - 1
            return
        }

        if (lower == 'a'.code || lower == 'e'.code || lower == 'o'.code) {
            if (pCount > 0) {
                val pIdx = pCount - 1
                if (lBase[pIdx] == lower && lMark[pIdx] == Mark.NONE) {
                    setCircumflex(pIdx); rawLetter[at] = pIdx; return
                }
                // `o` on ơ (ươ cluster): hook → hat, UniKey-style ("mơ"+o → mô).
                if (lower == 'o'.code && lBase[pIdx] == lower && lMark[pIdx] == Mark.HORN) {
                    setCircumflex(pIdx); rawLetter[at] = pIdx; return
                }
                if (lBase[pIdx] == lower && lMark[pIdx] == Mark.CIRCUMFLEX) {
                    lMark[pIdx] = Mark.NONE
                    pCancelled = true
                    literal(at, lower, upper); return
                }
            }
            if (freeMarking) {
                var k = pCount - 1
                while (k >= 0 && !isVowelAscii(lBase[k])) k--
                val nucleusEnd = k
                while (k >= 0 && isVowelAscii(lBase[k])) {
                    // "lươn" + o → "luôn": reach-back also retargets a horned o.
                    if (lBase[k] == lower &&
                        (lMark[k] == Mark.NONE || (lower == 'o'.code && lMark[k] == Mark.HORN))
                    ) {
                        if (lower == 'o'.code && nucleusEnd == pCount - 1 && k == pCount - 2 &&
                            lMark[k + 1] == Mark.NONE &&
                            (lBase[k + 1] == 'e'.code || lBase[k + 1] == 'a'.code)
                        ) break
                        setCircumflex(k); rawLetter[at] = k; return
                    }
                    if (lBase[k] == lower && lMark[k] == Mark.CIRCUMFLEX) {
                        lMark[k] = Mark.NONE
                        pCancelled = true
                        literal(at, lower, upper); return
                    }
                    k--
                }
            }
            literal(at, lower, upper)
            return
        }

        if (lower == 'd'.code) {
            if (pCount > 0) {
                val pIdx = pCount - 1
                if (lBase[pIdx] == 'd'.code && lMark[pIdx] == Mark.NONE) {
                    lMark[pIdx] = Mark.BAR; rawLetter[at] = pIdx; return
                }
                if (lBase[pIdx] == 'd'.code && lMark[pIdx] == Mark.BAR) {
                    lMark[pIdx] = Mark.NONE
                    pCancelled = true
                    literal(at, 'd'.code, upper); return
                }
            }
            if (freeMarking && pCount > 1 && lBase[0] == 'd'.code && lMark[0] == Mark.NONE) {
                lMark[0] = Mark.BAR; rawLetter[at] = 0; return
            }
            if (freeMarking && pCount > 1 && lBase[0] == 'd'.code && lMark[0] == Mark.BAR &&
                lBase[pCount - 1] != 'd'.code
            ) {
                lMark[0] = Mark.NONE
                pCancelled = true
                literal(at, 'd'.code, upper); return
            }
            literal(at, 'd'.code, upper)
            return
        }

        if (quickTelex && pCount == 1 && lBase[0] == lower && lMark[0] == Mark.NONE) {
            val second = quickTelexSecond(lower)
            if (second >= 0) {
                literal(at, second, upper)
                return
            }
        }

        literal(at, lower, upper)
    }

    private fun parseStepVNI(at: Int, key: Int, lower: Int, upper: Boolean) {
        if (!isDigit(key)) { literal(at, lower, upper); return }

        val t = vniTone(key)
        if (pFoldTones && t >= 0) { literal(at, key, false); return }

        if (t >= 0) {
            if (hasVowel(pCount)) {
                if (pTone == t) {
                    pTone = T.NONE
                    pCancelled = true; pToneCancelAt = at
                    pToneCancelSpan = if (pToneKeyCount > 0) at - toneKeys[pToneKeyCount - 1] else 1
                    literal(at, key, false)
                    for (j in 0 until pToneKeyCount) {
                        if (rawLetter[toneKeys[j]] == -1) rawLetter[toneKeys[j]] = pCount - 1
                    }
                    pToneKeyCount = 0
                } else if (stopCodaRejectsTone(t)) {
                    literal(at, key, false)
                } else {
                    pTone = t
                    rawLetter[at] = -1
                    toneKeys[pToneKeyCount] = at; pToneKeyCount++
                }
            } else {
                literal(at, key, false)
            }
            return
        }

        if (key == '0'.code) {
            if (pTone != T.NONE) {
                pToneCancelAt = at
                pToneCancelSpan = if (pToneKeyCount > 0) at - toneKeys[pToneKeyCount - 1] else 1
                pTone = T.NONE
                rawLetter[at] = -1
                toneKeys[pToneKeyCount] = at; pToneKeyCount++
            } else {
                literal(at, key, false)
            }
            return
        }

        val mark = vniMark(key)
        if (mark >= 0) {
            var k = pCount - 1
            while (k >= 0) {
                if (vniMarkAccepts(lBase[k], mark)) {
                    var target = k
                    if (mark == Mark.HORN && target >= 1 &&
                        lBase[target] == 'u'.code && lMark[target] == Mark.NONE &&
                        lBase[target - 1] == 'u'.code &&
                        !(target >= 2 && lBase[target - 2] == 'q'.code)
                    ) target--
                    if (lMark[target] == Mark.NONE) {
                        lMark[target] = mark
                        rawLetter[at] = target
                        return
                    }
                    if (lMark[target] == mark) {
                        lMark[target] = Mark.NONE
                        pCancelled = true
                        literal(at, key, false)
                        return
                    }
                    break
                }
                k--
            }
            literal(at, key, false)
            return
        }

        literal(at, key, false)
    }

    // MARK: - Tone placement

    private fun toneVowelIndex(count: Int): Int {
        var vcount = 0
        var start = 0
        if (count >= 2 && rBase[0] == 'q'.code && rBase[1] == 'u'.code && rMark[1] == Mark.NONE) {
            start = 2
        } else if (count >= 3 && rBase[0] == 'g'.code && rBase[1] == 'i'.code && rMark[1] == Mark.NONE &&
            isVowelAscii(rBase[2])
        ) {
            start = 2
        }
        for (k in start until count) if (isVowelAscii(rBase[k])) { vowelIdx[vcount] = k; vcount++ }
        if (vcount == 0) {
            for (k in 0 until count) if (isVowelAscii(rBase[k])) return k
            return count - 1
        }
        var lastMarked = -1
        for (j in 0 until vcount) if (rMark[vowelIdx[j]] != Mark.NONE) lastMarked = vowelIdx[j]
        if (lastMarked >= 0) return lastMarked
        if (vcount == 1) return vowelIdx[0]
        val hasCoda = vowelIdx[vcount - 1] < (count - 1)
        if (vcount == 2) {
            if (hasCoda) return vowelIdx[1]
            if (modernTone) {
                val a = rBase[vowelIdx[0]]
                val b = rBase[vowelIdx[1]]
                val glideInitial = (a == 'o'.code && (b == 'a'.code || b == 'e'.code)) ||
                    (a == 'u'.code && b == 'y'.code)
                if (glideInitial) return vowelIdx[1]
            }
            return vowelIdx[0]
        }
        return vowelIdx[1]
    }

    // MARK: - Diffing

    private fun commonPrefixLength(limit: Int): Int {
        var i = 0
        while (i < limit && scratch[i] == out[i]) i++
        return i
    }

    private fun diff(newCount: Int): TelexAction {
        val lcp = commonPrefixLength(minOf(newCount, outCount))
        val backspaces = outCount - lcp
        if (backspaces == 0 && lcp == newCount) return EMPTY_REPLACE
        val sb = StringBuilder(newCount - lcp)
        for (i in lcp until newCount) sb.appendCodePoint(scratch[i])
        return TelexAction.Replace(backspaces, sb.toString())
    }

    // MARK: - Small helpers

    private fun standaloneHornUAllowed(count: Int): Boolean {
        var node = 0
        for (k in 0 until count) {
            node = ONSETS_ALLOWING_STANDALONE_U.step(node, (lBase[k] - 'a'.code) and 0xFF)
            if (node < 0) return false
        }
        return ONSETS_ALLOWING_STANDALONE_U.mask(node) != 0
    }

    private fun hasVowel(count: Int): Boolean {
        for (k in 0 until count) if (isVowelAscii(lBase[k])) return true
        return false
    }

    private fun isUkRime(count: Int): Boolean =
        count >= 2 && rBase[count - 1] == 'k'.code && rBase[count - 2] == 'u'.code && rMark[count - 2] == Mark.HORN

    private fun hasStopCoda(count: Int): Boolean {
        if (count <= 0) return false
        val last = rBase[count - 1]
        if (last == 'p'.code || last == 't'.code || last == 'c'.code || last == 'k'.code) return true
        return last == 'h'.code && count >= 2 && rBase[count - 2] == 'c'.code
    }

    private fun lettersHaveStopCoda(count: Int): Boolean {
        if (count <= 0) return false
        val last = lBase[count - 1]
        if (last == 'p'.code || last == 't'.code || last == 'c'.code || last == 'k'.code) return true
        return last == 'h'.code && count >= 2 && lBase[count - 2] == 'c'.code
    }

    private fun lettersAreUkRime(count: Int): Boolean =
        count >= 2 && lBase[count - 1] == 'k'.code && lBase[count - 2] == 'u'.code && lMark[count - 2] == Mark.HORN

    private fun stopCodaRejectsTone(tone: Int): Boolean {
        if (tone != T.GRAVE && tone != T.HOOK && tone != T.TILDE) return false
        if (!lettersHaveStopCoda(pCount)) return false
        if (tone == T.GRAVE && lettersAreUkRime(pCount)) return false
        return true
    }

    private fun appendLetter(base: Int, mark: Int, upper: Boolean) {
        if (pCount >= CAPACITY) return
        lBase[pCount] = base
        lMark[pCount] = mark
        lUpper[pCount] = upper
        pCount++
    }

    companion object {
        const val CAPACITY = 32

        private const val CTX_ENGLISH = 0
        private const val CTX_VIETNAMESE = 1
        private const val CTX_NEUTRAL = 2

        private val EMPTY_REPLACE = TelexAction.Replace(0, "")

        private val ENGLISH_EXCEPTIONS: Array<IntArray> = arrayOf(
            "was".map { it.code }.toIntArray(),
            "wow".map { it.code }.toIntArray(),
            "yes".map { it.code }.toIntArray(),
        )

        private val ONSETS_ALLOWING_STANDALONE_U = ClassTrie(
            listOf(
                "", "b", "c", "ch", "d", "g", "h", "kh", "l", "m", "n", "ng", "nh",
                "ph", "r", "s", "t", "th", "tr", "v", "x", "gi",
            ).map { it to 1 }
        )

        /** Bracket key → horned vowel base ('o'/'u'), or -1. */
        internal fun bracketBase(key: Int): Int = when (key) {
            '['.code, '{'.code -> 'o'.code
            ']'.code, '}'.code -> 'u'.code
            else -> -1
        }

        private fun vniTone(d: Int): Int = when (d) {
            '1'.code -> T.ACUTE
            '2'.code -> T.GRAVE
            '3'.code -> T.HOOK
            '4'.code -> T.TILDE
            '5'.code -> T.DOT
            else -> -1
        }

        private fun vniMark(d: Int): Int = when (d) {
            '6'.code -> Mark.CIRCUMFLEX
            '7'.code -> Mark.HORN
            '8'.code -> Mark.BREVE
            '9'.code -> Mark.BAR
            else -> -1
        }

        private fun vniMarkAccepts(base: Int, mark: Int): Boolean = when (mark) {
            Mark.CIRCUMFLEX -> base == 'a'.code || base == 'e'.code || base == 'o'.code
            Mark.HORN -> base == 'o'.code || base == 'u'.code
            Mark.BREVE -> base == 'a'.code
            Mark.BAR -> base == 'd'.code
            else -> false
        }

        private fun quickTelexSecond(c: Int): Int = when (c) {
            'c'.code, 'k'.code, 'p'.code, 't'.code -> 'h'.code
            'g'.code -> 'i'.code
            'n'.code -> 'g'.code
            'q'.code -> 'u'.code
            else -> -1
        }

        private fun telexToneKey(t: Int): Char? = when (t) {
            T.ACUTE -> 's'; T.GRAVE -> 'f'; T.HOOK -> 'r'; T.TILDE -> 'x'; T.DOT -> 'j'; else -> null
        }

        private fun vniToneKey(t: Int): Char? = when (t) {
            T.ACUTE -> '1'; T.GRAVE -> '2'; T.HOOK -> '3'; T.TILDE -> '4'; T.DOT -> '5'; else -> null
        }

        private fun telexMarkExpansion(c: Int): String? = when (c) {
            'â'.code -> "aa"; 'ă'.code -> "aw"; 'ê'.code -> "ee"; 'ô'.code -> "oo"
            'ơ'.code -> "ow"; 'ư'.code -> "uw"; 'đ'.code -> "dd"; else -> null
        }

        private fun vniMarkExpansion(c: Int): String? = when (c) {
            'â'.code -> "a6"; 'ê'.code -> "e6"; 'ô'.code -> "o6"; 'ơ'.code -> "o7"
            'ư'.code -> "u7"; 'ă'.code -> "a8"; 'đ'.code -> "d9"; else -> null
        }

        /** Keystrokes that would compose `word`, or null if some character can't be typed. */
        private fun seedKeystrokes(word: String, vni: Boolean): String? {
            val sb = StringBuilder()
            var toneKey: Char? = null
            var i = 0
            while (i < word.length) {
                val cp = word.codePointAt(i)
                i += Character.charCount(cp)
                val isUpper = Character.isUpperCase(cp)
                val lower = Character.toLowerCase(cp)
                var toneless = lower
                val d = Tables.detone(lower)
                if (d >= 0) {
                    val t = d and 7
                    if (t != T.NONE) {
                        if (toneKey != null) return null
                        toneKey = if (vni) vniToneKey(t) else telexToneKey(t)
                    }
                    toneless = d shr 3
                }
                val expanded: String = (if (vni) vniMarkExpansion(toneless) else telexMarkExpansion(toneless))
                    ?: run {
                        if (toneless !in 'a'.code..'z'.code) return null
                        toneless.toChar().toString()
                    }
                if (isUpper) {
                    if (vni) {
                        sb.append(expanded[0].uppercaseChar()); sb.append(expanded, 1, expanded.length)
                    } else sb.append(expanded.uppercase())
                } else sb.append(expanded)
            }
            if (toneKey != null) sb.append(toneKey)
            return sb.toString()
        }
    }
}
