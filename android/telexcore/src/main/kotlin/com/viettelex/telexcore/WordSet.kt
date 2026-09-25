package com.viettelex.telexcore

/**
 * Immutable open-addressing string set that can be probed with a char-code buffer
 * (`IntArray` + length) WITHOUT building a String — lets the boundary/peek path
 * look words up allocation-free. Hash = String.hashCode's polynomial.
 */
internal class WordSet(words: Collection<String>) {
    private val table: Array<String?>
    private val mask: Int

    init {
        var cap = 16
        while (cap < words.size * 2) cap = cap shl 1
        table = arrayOfNulls(cap)
        mask = cap - 1
        for (w in words) {
            var i = w.hashCode() and mask
            while (true) {
                val cur = table[i]
                if (cur == null) { table[i] = w; break }
                if (cur == w) break
                i = (i + 1) and mask
            }
        }
    }

    fun contains(buf: IntArray, len: Int): Boolean {
        var h = 0
        for (k in 0 until len) h = 31 * h + buf[k]
        var i = h and mask
        while (true) {
            val cur = table[i] ?: return false
            if (cur.length == len) {
                var eq = true
                for (k in 0 until len) if (cur[k].code != buf[k]) { eq = false; break }
                if (eq) return true
            }
            i = (i + 1) and mask
        }
    }

    fun contains(s: String): Boolean {
        var i = s.hashCode() and mask
        while (true) {
            val cur = table[i] ?: return false
            if (cur == s) return true
            i = (i + 1) and mask
        }
    }
}
