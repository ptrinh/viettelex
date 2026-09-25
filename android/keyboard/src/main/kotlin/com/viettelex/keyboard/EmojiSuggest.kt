package com.viettelex.keyboard

import java.text.Normalizer

/**
 * Emoji theo nghĩa từ (port iOS; blob GENERATED — assets/emojisuggest.bin, xuất bởi
 * keyboard/scripts/export-ios-data.py). 2893 khóa sort theo UTF-8, binary search tại chỗ.
 * Layout (LE): "EMS1" | count u32 | keyOff u16[count+1] | valOff u16[count+1] | keys | vals.
 */
object EmojiSuggest {
    private class Blob(val buf: java.nio.ByteBuffer) {
        val count = buf.getInt(4)
        private val keyOffBase = 8
        private val valOffBase = 8 + (count + 1) * 2
        val keyBase = valOffBase + (count + 1) * 2
        val valBase = keyBase + keyOff(count)
        fun keyOff(i: Int) = buf.getShort(keyOffBase + i * 2).toInt() and 0xFFFF
        fun valOff(i: Int) = buf.getShort(valOffBase + i * 2).toInt() and 0xFFFF
        fun keyByte(i: Int) = buf.get(keyBase + i).toInt() and 0xFF
        init {
            require(buf.get(0) == 'E'.code.toByte() && buf.get(3) == '1'.code.toByte()) { "bad emoji blob" }
        }
    }
    private val blob by lazy { Blob(KeyboardData.buffer(Keys.ASSET_EMOJI_SUGGEST)) }

    fun emojis(word: String): List<String> {
        if (word.isEmpty()) return emptyList()
        val q = Normalizer.normalize(word, Normalizer.Form.NFC).lowercase().toByteArray(Charsets.UTF_8)
        val b = blob
        var lo = 0; var hi = b.count
        while (lo < hi) { val mid = (lo + hi) ushr 1; if (cmp(b, mid, q) < 0) lo = mid + 1 else hi = mid }
        if (lo >= b.count || cmp(b, lo, q) != 0) return emptyList()
        val s = b.valOff(lo); val e = b.valOff(lo + 1)
        val bytes = ByteArray(e - s) { b.buf.get(b.valBase + s + it) }
        return String(bytes, Charsets.UTF_8).split(' ').filter { it.isNotEmpty() }
    }

    private fun cmp(b: Blob, id: Int, q: ByteArray): Int {
        var i = b.keyOff(id); val end = b.keyOff(id + 1); var j = 0
        while (i < end && j < q.size) {
            val k = b.keyByte(i); val c = q[j].toInt() and 0xFF
            if (k != c) return if (k < c) -1 else 1
            i++; j++
        }
        if (i < end) return 1
        if (j < q.size) return -1
        return 0
    }
}
