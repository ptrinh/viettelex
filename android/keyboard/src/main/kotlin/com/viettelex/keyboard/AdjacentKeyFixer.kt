package com.viettelex.keyboard

import java.text.Normalizer
import kotlin.math.abs

/**
 * Gợi ý sửa lỗi CHẠM TRƯỢT sang phím kề (port iOS). Không tự thay — chỉ đưa lên bar.
 * Pure: engine + lexicon tiêm qua lambda.
 */
object AdjacentKeyFixer {
    private val rows: List<Pair<String, Double>> =
        listOf("qwertyuiop" to 0.0, "asdfghjkl" to 0.5, "zxcvbnm" to 1.5)

    /** Phím kề: cùng hàng ±1, hàng trên/dưới tâm lệch ≤ 0.6 phím (lưới QWERTY iOS). */
    val neighbors: Map<Char, List<Char>> = run {
        val pos = HashMap<Char, Pair<Int, Double>>()
        rows.forEachIndexed { r, (keys, off) -> keys.forEachIndexed { i, k -> pos[k] = r to off + i } }
        val out = HashMap<Char, List<Char>>()
        for ((k, p) in pos) {
            out[k] = pos.filter { (o, q) ->
                o != k && ((q.first == p.first && abs(q.second - p.second) <= 1.01) ||
                    (abs(q.first - p.first) == 1 && abs(q.second - p.second) <= 0.6))
            }.keys.sorted()
        }
        out
    }

    private fun isAsciiLetter(c: Char) = c in 'a'..'z' || c in 'A'..'Z'

    fun correction(
        raw: String,
        compose: (String) -> String,
        frequency: (String) -> Int?,
        hasCompletion: (String) -> Boolean,
    ): String? {
        val keys = raw.toCharArray()
        if (keys.size !in 2..10 || !keys.all(::isAsciiLetter)) return null
        val lower = CharArray(keys.size) { keys[it].lowercaseChar() }
        val current = compose(String(lower))
        if (frequency(current) != null || hasCompletion(current)) return null

        var bestWord: String? = null
        var bestFreq = 0
        fun consider(c: CharArray) {
            val w = compose(String(c))
            if (w == current) return
            val f = frequency(w) ?: return
            if (bestWord == null || f > bestFreq) { bestWord = w; bestFreq = f }
        }
        // Cắt tỉa theo TIỀN TỐ CHẾT (bỏ dấu thanh) — xem iOS.
        val alive = HashMap<String, Boolean>()
        fun isAlive(c: CharArray, k: Int): Boolean {
            val key = String(c, 0, k + 1)
            alive[key]?.let { return it }
            val v = hasCompletion(stripTones(compose(key)))
            alive[key] = v
            return v
        }
        fun firstDead(c: CharArray, from: Int): Int {
            var k = from
            while (k < c.size && isAlive(c, k)) k++
            return k
        }
        val dead0 = firstDead(lower, 0)
        val editable = lower.indices.filter { it <= dead0 }
        // 1 sửa: đảo 2 phím liền nhau xét trước và thắng nếu có.
        for (i in editable) {
            if (i + 1 < lower.size && lower[i] != lower[i + 1]) {
                val c = lower.copyOf(); val t = c[i]; c[i] = c[i + 1]; c[i + 1] = t; consider(c)
            }
        }
        if (bestWord == null) {
            for (i in editable) for (n in neighbors[lower[i]].orEmpty()) {
                val c = lower.copyOf(); c[i] = n; consider(c)
            }
        }
        if (bestWord == null && lower.size <= 8) {
            for (i in editable) for (a in neighbors[lower[i]].orEmpty()) {
                val ci = lower.copyOf(); ci[i] = a
                val deadI = firstDead(ci, i)
                if (deadI <= i) continue
                for (j in lower.indices) {
                    if (j <= i || j > deadI) continue
                    for (b in neighbors[lower[j]].orEmpty()) {
                        val c = ci.copyOf(); c[j] = b; consider(c)
                    }
                }
            }
        }
        var w = bestWord ?: return null
        if (keys[0].isUpperCase() && w.isNotEmpty()) w = Cp.capitalizeFirst(w)
        return w
    }

    private val toneMarks = intArrayOf(0x300, 0x301, 0x303, 0x309, 0x323)

    /** Bỏ 5 dấu thanh, giữ dấu chữ: "cũm" → "cum". */
    fun stripTones(s: String): String {
        val d = Normalizer.normalize(s, Normalizer.Form.NFD)
        val sb = StringBuilder(d.length)
        for (ch in d) if (ch.code !in toneMarks) sb.append(ch)
        return Normalizer.normalize(sb, Normalizer.Form.NFC)
    }

    /** Cache theo raw, thread-safe (gọi từ thread gợi ý nền). Đầy thì xoá sạch. */
    class Cache(private val capacity: Int = 256) {
        private val map = HashMap<String, String?>()
        fun value(raw: String, compute: () -> String?): String? {
            synchronized(map) { if (map.containsKey(raw)) return map[raw] }
            val v = compute()
            synchronized(map) {
                if (map.size >= capacity) map.clear()
                map[raw] = v
            }
            return v
        }
        val count: Int get() = synchronized(map) { map.size }
    }

    /** Bản sửa cho từ đang gõ theo setting của [bridge], qua cache. An toàn ngoài main. */
    fun lexiconCorrection(raw: String, bridge: EngineBridge): String? =
        bridge.adjacentFixCache.value(raw) {
            correction(raw,
                compose = { bridge.composeTrial(it) },
                frequency = { VNSuggest.frequency(it) },
                hasCompletion = { VNSuggest.matches(it, poolLimit = 1).isNotEmpty() })
        }
}
