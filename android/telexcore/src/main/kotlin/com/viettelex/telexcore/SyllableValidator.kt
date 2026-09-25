// Port of TelexCore/SyllableValidator.swift — rule tables compiled into flat class
// tries; the hot paths walk IntArrays (no String, no hashing, no allocation).
package com.viettelex.telexcore

object SyllableValidator {

    internal val onsets: Set<String> = setOf(
        "", "b", "c", "ch", "d", "đ", "g", "gh", "gi", "h", "k", "kh", "l",
        "m", "n", "ng", "ngh", "nh", "p", "ph", "qu", "r", "s", "t", "th",
        "tr", "v", "x", "z", "dz",
        "kr",
    )

    internal val rimes: Set<String> = """
        a ac ach ai am an ang anh ao ap at au ay ak
        ă ăc ăm ăn ăng ăp ăt ăk
        â âc âm ân âng âp ât âu ây
        e ec em en eng eo ep et
        ê êch êm ên êng ênh êp êt êu
        i ich im in inh ip it iu ia
        ik
        iê iêc iêm iên iêng iêp iêt iêu
        ie
        o oc oi om on ong op ot
        oa oac oach oai oam oan oang oanh oao oap oat oay
        oă oăc oăm oăn oăng oăt
        oe oem oen oeo oet
        oo oong ooc
        ô ôc ôi ôm ôn ông ôp ôt
        ơ ơi ơm ơn ơp ơt
        u uc ui um un ung up ut ua
        uâ uân uâng uât uây
        uê uêch uên uênh
        uô uôc uôi uôm uôn uông uôt uơ
        uy uya uych uyn uynh uyt uyu uyên uyêt
        ư ưa ưc ưi ưm ưn ưng ưt ưu
        ưk
        ươ ươi ươm ươn ương ươp ươt ươu ươc
        y yê yêm yên yêng yêt yêu
    """.split(' ', '\n').filter { it.isNotEmpty() }.toSet()

    private fun toneMask(r: String): Int {
        if (r == "ưk") return (1 shl T.GRAVE) or (1 shl T.ACUTE) or (1 shl T.DOT)
        val stop = r.endsWith("p") || r.endsWith("t") || r.endsWith("c") || r.endsWith("ch") || r.endsWith("k")
        return if (stop) (1 shl T.ACUTE) or (1 shl T.DOT) else 0b0011_1111
    }

    internal val teencodeOnsets = setOf("z", "dz")
    internal val teencodeRimes = setOf("ie", "ik", "ưk")

    private fun foldBase(c: Char): Char = when (c) {
        'ă', 'â' -> 'a'
        'ê' -> 'e'
        'ô', 'ơ' -> 'o'
        'ư' -> 'u'
        'đ' -> 'd'
        else -> c
    }
    private fun fold(s: String) = buildString { for (c in s) append(foldBase(c)) }

    internal val onsetExact = ClassTrie(onsets.map { it to 1 })
    internal val rimeExact = ClassTrie(rimes.map { it to toneMask(it) })
    internal val onsetExactStd = ClassTrie((onsets - teencodeOnsets).map { it to 1 })
    internal val rimeExactStd = ClassTrie((rimes - teencodeRimes).map { it to toneMask(it) })
    internal val onsetFolded = ClassTrie(onsets.map { fold(it) to 1 })
    internal val rimeFolded = ClassTrie(rimes.map { fold(it) to 1 })
    internal val onsetFoldedStd = ClassTrie((onsets - teencodeOnsets).map { fold(it) to 1 })
    internal val rimeFoldedStd = ClassTrie((rimes - teencodeRimes).map { fold(it) to 1 })

    private fun kOnsetAllows(c: Int): Boolean =
        c == 'i' - 'a' || c == 'e' - 'a' || c == 28 || c == 'y' - 'a'

    private const val C_O = 'o' - 'a'
    private const val C_Y = 'y' - 'a'
    private const val C_G = 'g' - 'a'
    private const val C_R = 'r' - 'a'
    private const val C_Z = 'z' - 'a'
    private const val C_D = 'd' - 'a'
    private const val C_C = 'c' - 'a'
    private const val C_H = 'h' - 'a'
    private const val C_K = 'k' - 'a'
    private const val C_Q = 'q' - 'a'
    private const val C_U = 'u' - 'a'
    private const val C_I = 'i' - 'a'

    /**
     * Zero-allocation core: `classes[0 until n]` are letter classes, `tone` the tone raw
     * value (0-5). Mirrors both Swift twins (Array + buffer) — they are identical.
     */
    fun isValidSyllable(classes: IntArray, n: Int, tone: Int, teencode: Boolean = true): Boolean {
        if (n == 0) return false
        if (teencode && n == 2 && classes[0] == C_O && classes[1] == C_Y) return true
        if (teencode && n >= 3 && tone == T.GRAVE && classes[n - 2] == C_O && classes[n - 1] == C_Y) {
            val c0 = classes[0]
            if (n == 3 && (c0 == C_G || c0 == C_R || c0 == C_Z || c0 == C_H)) return true
            if (n == 4 && ((c0 == C_D && classes[1] == C_Z) || (c0 == C_C && classes[1] == C_H))) return true
        }
        if (teencode && n == 3 && tone == T.NONE && classes[0] == 32 && classes[1] == C_O && classes[2] == C_U) return true
        val onsetT = if (teencode) onsetExact else onsetExactStd
        val rimeT = if (teencode) rimeExact else rimeExactStd

        var pos = 0
        while (pos < n && !Tables.isVowelClass(classes[pos])) pos++
        var onsetEnd = pos
        var quGlide = false
        if (pos >= 1 && classes[0] == C_Q && pos < n && classes[pos] == C_U &&
            pos + 1 < n && Tables.isVowelClass(classes[pos + 1])
        ) {
            onsetEnd = pos + 1
            quGlide = true
        } else if (n >= 3 && classes[0] == C_G && classes[1] == C_I && Tables.isVowelClass(classes[2])) {
            onsetEnd = 2
        }
        if (accepts(classes, n, tone, teencode, onsetT, rimeT, onsetEnd, onsetEnd)) return true
        if (quGlide && accepts(classes, n, tone, teencode, onsetT, rimeT, onsetEnd, pos)) return true
        return onsetEnd != pos && accepts(classes, n, tone, teencode, onsetT, rimeT, pos, pos)
    }

    private fun accepts(
        classes: IntArray, n: Int, tone: Int, teencode: Boolean,
        onsetT: ClassTrie, rimeT: ClassTrie, onsetEnd: Int, rimeStart: Int,
    ): Boolean {
        var node = 0
        for (k in 0 until onsetEnd) {
            node = onsetT.step(node, classes[k])
            if (node < 0) return false
        }
        if (onsetT.mask(node) == 0) return false
        if (!teencode && onsetEnd == 1 && classes[0] == C_K && rimeStart < n && !kOnsetAllows(classes[rimeStart])) return false
        var rnode = 0
        for (k in rimeStart until n) {
            rnode = rimeT.step(rnode, classes[k])
            if (rnode < 0) return false
        }
        return ((rimeT.mask(rnode) shr tone) and 1) == 1
    }

    /** String façade (boundary / tests; not the hot path). */
    @JvmStatic
    @JvmOverloads
    fun isValidSyllable(word: String, teencode: Boolean = true): Boolean {
        if (word.isEmpty()) return false
        val lower = word.lowercase()
        val classes = IntArray(lower.length)
        var tone = T.NONE
        var n = 0
        for (ch in lower) {
            if (ch.isSurrogate()) return false
            var toneless = ch
            val d = Tables.detone(ch.code)
            if (d >= 0) {
                toneless = (d shr 3).toChar()
                val t = d and 7
                if (t != T.NONE) {
                    if (tone != T.NONE) return false
                    tone = t
                }
            }
            val cls = Tables.charClass(toneless)
            if (cls < 0) return false
            classes[n++] = cls
        }
        return isValidSyllable(classes, n, tone, teencode)
    }

    /**
     * Allocation-free twin of `isValidSyllable(String(scalars).lowercase())` over a
     * scalar buffer (the engine's `out`); `buf` is caller scratch (≥ n).
     */
    internal fun isValidSyllableScalars(scalars: IntArray, n: Int, teencode: Boolean, buf: IntArray): Boolean {
        if (n == 0) return false
        var tone = T.NONE
        for (i in 0 until n) {
            val cp = scalars[i]
            if (cp > 0xFFFF) return false
            var toneless = Character.toLowerCase(cp)
            val d = Tables.detone(toneless)
            if (d >= 0) {
                toneless = d shr 3
                val t = d and 7
                if (t != T.NONE) {
                    if (tone != T.NONE) return false
                    tone = t
                }
            }
            val cls = Tables.charClass(toneless.toChar())
            if (cls < 0) return false
            buf[i] = cls
        }
        return isValidSyllable(buf, n, tone, teencode)
    }

    private fun cls(bases: IntArray, i: Int): Int = ((bases[i] and 0x7F) - 'a'.code) and 0xFF

    /** Prefix plausibility over folded bases (bit 7 = carries a mark). Permissive. */
    fun isValidPrefix(bases: IntArray, n: Int, teencode: Boolean = true): Boolean {
        if (n == 0) return true
        val onsetF = if (teencode) onsetFolded else onsetFoldedStd
        val rimeF = if (teencode) rimeFolded else rimeFoldedStd
        for (i in 0 until n) if (!isLetter(bases[i] and 0x7F)) return false

        var pos = 0
        while (pos < n && !isVowelAscii(bases[pos] and 0x7F)) pos++
        if (pos == n) {
            var node = 0
            for (i in 0 until n) {
                node = onsetF.step(node, cls(bases, i))
                if (node < 0) return false
            }
            return true
        }
        if (teencode && n == 2 && bases[0] == 'o'.code && bases[1] == 'y'.code) return true
        if (teencode && n >= 3 && bases[n - 2] == 'o'.code && bases[n - 1] == 'y'.code) {
            val b0 = bases[0] and 0x7F
            val b1 = bases[1] and 0x7F
            if (n == 3 && (b0 == 'g'.code || b0 == 'r'.code || b0 == 'z'.code || b0 == 'd'.code || b0 == 'h'.code)) return true
            if (n == 4 && ((b0 == 'd'.code && b1 == 'z'.code) || (b0 == 'c'.code && b1 == 'h'.code))) return true
        }
        if (teencode && n == 3 && (bases[0] and 0x7F) == 'd'.code && bases[1] == 'o'.code && bases[2] == 'u'.code) return true

        val quAlt = if ((bases[0] and 0x7F) == 'q'.code && bases[pos] == 'u'.code) pos + 1 else -1
        val giAlt = if ((bases[0] and 0x7F) == 'g'.code && n >= 2 && bases[1] == 'i'.code) 2 else -1
        return prefixReading(bases, n, onsetF, rimeF, pos, pos) ||
            prefixReading(bases, n, onsetF, rimeF, quAlt, quAlt) ||
            prefixReading(bases, n, onsetF, rimeF, giAlt, giAlt) ||
            prefixReading(bases, n, onsetF, rimeF, quAlt, pos)
    }

    private fun prefixReading(bases: IntArray, n: Int, onsetF: ClassTrie, rimeF: ClassTrie, onsetEnd: Int, rimeStart: Int): Boolean {
        if (onsetEnd < 0 || onsetEnd > n) return false
        var node = 0
        for (i in 0 until onsetEnd) {
            node = onsetF.step(node, cls(bases, i))
            if (node < 0) return false
        }
        if (onsetF.mask(node) == 0) return false
        var rnode = 0
        for (i in rimeStart until n) {
            rnode = rimeF.step(rnode, cls(bases, i))
            if (rnode < 0) return false
        }
        return true
    }

    /** String façade over the prefix check (tests / non-hot callers). */
    @JvmStatic
    @JvmOverloads
    fun isValidPrefix(word: String, teencode: Boolean = true): Boolean {
        if (word.isEmpty()) return true
        val lower = word.lowercase()
        val bases = IntArray(lower.length)
        var n = 0
        for (ch in lower) {
            if (ch.isSurrogate()) return false
            var toneless = ch
            val d = Tables.detone(ch.code)
            if (d >= 0) toneless = (d shr 3).toChar()
            if (Tables.charClass(toneless) < 0) return false
            val folded = foldBase(toneless)
            if (folded.code >= 128) return false
            bases[n++] = folded.code or (if (folded == toneless) 0 else 0x80)
        }
        return isValidPrefix(bases, n, teencode)
    }
}

/** Flat trie over the 33-letter class alphabet. -1 = absent; mask 0 = not a word. */
internal class ClassTrie(words: List<Pair<String, Int>>) {
    private val next: IntArray
    private val masks: IntArray

    init {
        val stride = Tables.CLASS_COUNT
        var nx = IntArray(stride * 64) { -1 }
        var ms = IntArray(64)
        var nodes = 1
        outer@ for ((w, accept) in words) {
            val path = IntArray(w.length)
            for ((i, ch) in w.withIndex()) {
                val c = Tables.charClass(ch)
                if (c < 0) continue@outer
                path[i] = c
            }
            var node = 0
            for (c in path) {
                val slot = node * stride + c
                if (nx[slot] < 0) {
                    if (nodes == ms.size) {
                        ms = ms.copyOf(ms.size * 2)
                        val grown = IntArray(nx.size * 2) { -1 }
                        System.arraycopy(nx, 0, grown, 0, nx.size)
                        nx = grown
                    }
                    nx[slot] = nodes
                    nodes++
                }
                node = nx[slot]
            }
            ms[node] = ms[node] or maxOf(accept, 1)
        }
        next = nx.copyOf(nodes * stride)
        masks = ms.copyOf(nodes)
    }

    fun step(node: Int, cls: Int): Int {
        if (cls < 0 || cls >= Tables.CLASS_COUNT) return -1
        return next[node * Tables.CLASS_COUNT + cls]
    }

    fun mask(node: Int): Int = masks[node]
}
