package com.viettelex.keyboard

import java.text.Normalizer

/**
 * Inline suggestion từ tiếng Việt đang gõ dở (port iOS): binary search range trên
 * foldedKey rồi post-filter TƯƠNG THÍCH DẤU từng ký tự. Thread-safe (chỉ đọc blob).
 */
object VNSuggest {
    /** Một ứng viên + tần suất tĩnh 0-255. */
    data class Match(val word: String, val freq: Int)

    // char → (base << 8) | attr  (attr = quality<<3 | tone); -1 = ngoài bảng.
    private val decomposeTable: IntArray = run {
        val m = IntArray(0x1F00) { -1 }
        val bases = listOf(
            'a' to listOf("a", "â", "ă"), 'e' to listOf("e", "ê", null), 'o' to listOf("o", "ô", "ơ"),
            'u' to listOf("u", null, "ư"), 'i' to listOf("i", null, null), 'y' to listOf("y", null, null),
        )
        val tones = listOf("́", "̀", "̉", "̃", "̣")
        for ((base, variants) in bases) {
            variants.forEachIndexed { q, v ->
                if (v == null) return@forEachIndexed
                m[v[0].code] = (base.code shl 8) or (q shl 3)
                tones.forEachIndexed { t, mark ->
                    val nfc = Normalizer.normalize(v + mark, Normalizer.Form.NFC)
                    if (nfc.length == 1) m[nfc[0].code] = (base.code shl 8) or (q shl 3) or (t + 1)
                }
            }
        }
        m['đ'.code] = ('d'.code shl 8) or (3 shl 3)
        for (c in 'a'..'z') if (m[c.code] == -1) m[c.code] = c.code shl 8
        m
    }

    /** Decompose; null nếu chứa ký tự ngoài chữ Việt/Latin. */
    private fun decompose(s: String): IntArray? {
        val n = Normalizer.normalize(s, Normalizer.Form.NFC).lowercase()
        if (n.isEmpty()) return null
        val out = IntArray(n.length)
        for ((i, ch) in n.withIndex()) {
            val c = ch.code
            val d = if (c < decomposeTable.size) decomposeTable[c] else -1
            if (d < 0) return null
            out[i] = d
        }
        return out
    }

    private fun lex() = VNLexicon2Data.blob

    fun display(id: Int): String {
        val b = lex()
        val lo = if (id == 0) 0 else b.dispOffsets[id]
        val hi = b.dispOffsets[id + 1]
        val bytes = ByteArray(hi - lo) { b.displayByte(lo + it).toByte() }
        return String(bytes, Charsets.UTF_8)
    }

    /** display(id) == utf8 (so byte tại chỗ, không alloc String). */
    private fun displayEquals(id: Int, utf8: ByteArray): Boolean {
        val b = lex()
        val lo = if (id == 0) 0 else b.dispOffsets[id]
        val hi = b.dispOffsets[id + 1]
        if (hi - lo != utf8.size) return false
        for (i in utf8.indices) if (b.displayByte(lo + i) != (utf8[i].toInt() and 0xFF)) return false
        return true
    }

    /**
     * Ứng viên tương thích với chuỗi đang gõ, theo tần suất giảm dần (hoà: id tăng),
     * tối đa [poolLimit]; bỏ đúng [excluding] (lowercase).
     */
    fun matches(typed: String, poolLimit: Int = 24, excluding: String = ""): List<Match> {
        val dec = decompose(typed) ?: return emptyList()
        val b = lex()
        val excl = excluding.lowercase()
        val ids: IntArray = if (dec.size == 1) {
            VNLexicon2Data.firstCharTop[(dec[0] shr 8).toChar()] ?: return emptyList()
        } else {
            val r = range(dec); IntArray(r.last - r.first + 1) { r.first + it }
        }
        // pool: (freq, id) packed → sort giảm freq, tăng id
        val pool = LongArray(ids.size)
        var n = 0
        for (id in ids) {
            val start = b.offsets[id]
            val len = b.offsets[id + 1] - start
            if (len < dec.size) continue
            var ok = true
            for (i in dec.indices) {
                val base = dec[i] shr 8
                val a = dec[i] and 0xFF
                if (b.foldedByte(start + i) != base) { ok = false; break }
                val cand = b.attr(start + i)
                val q = a shr 3; val t = a and 7
                if (q != 0 && q != cand shr 3) { ok = false; break }
                if (t != 0 && t != cand and 7) { ok = false; break }
            }
            if (!ok) continue
            pool[n++] = ((255 - b.freq(id)).toLong() shl 32) or id.toLong()
        }
        java.util.Arrays.sort(pool, 0, n)
        val out = ArrayList<Match>(minOf(n, poolLimit))
        for (k in 0 until n) {
            val id = (pool[k] and 0xFFFFFFFFL).toInt()
            val w = display(id)
            if (w == excl) continue
            out.add(Match(w, 255 - (pool[k] ushr 32).toInt()))
            if (out.size >= poolLimit) break
        }
        return out
    }

    /** Âm tiết có trong lexicon (binary search). */
    fun contains(word: String): Boolean = frequency(word) != null

    /** Tần suất đúng âm tiết [word], null nếu không có. */
    fun frequency(word: String): Int? {
        val dec = decompose(word) ?: return null
        val b = lex()
        val w = word.lowercase().toByteArray(Charsets.UTF_8)
        for (id in range(dec)) {
            if (b.offsets[id + 1] - b.offsets[id] != dec.size) continue
            if (displayEquals(id, w)) return b.freq(id)
        }
        return null
    }

    /** Range [lo, hi] các entry có foldedKey bắt đầu bằng prefix (IntRange, có thể rỗng). */
    private fun range(dec: IntArray): IntRange {
        val b = lex()
        fun cmp(id: Int): Int {
            val start = b.offsets[id]
            val end = b.offsets[id + 1]
            var i = start
            for (d in dec) {
                val p = d shr 8
                if (i == end) return -1
                val f = b.foldedByte(i)
                if (f != p) return if (f < p) -1 else 1
                i++
            }
            return 0
        }
        var lo = 0; var hi = VNLexicon2Data.count
        while (lo < hi) { val mid = (lo + hi) ushr 1; if (cmp(mid) < 0) lo = mid + 1 else hi = mid }
        val start = lo
        hi = VNLexicon2Data.count
        while (lo < hi) { val mid = (lo + hi) ushr 1; if (cmp(mid) <= 0) lo = mid + 1 else hi = mid }
        return start until lo
    }
}
