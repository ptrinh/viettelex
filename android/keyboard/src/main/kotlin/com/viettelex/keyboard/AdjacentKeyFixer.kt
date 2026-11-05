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
        // số chỉ có ở VNI (phím dấu 1–9/0): giữ nguyên chỗ, không có phím kề
        if (keys.size !in 2..10 || !keys.all { isAsciiLetter(it) || it in '0'..'9' }) return null
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

    /**
     * Chạm trượt MÀ VẪN RA TỪ HỢP LỆ — [correction] chỉ chạy khi không khớp gì nên bỏ sót:
     * "casn" (ý là "caan" → cân, a trượt sang s) ra "cán". Phím thanh Telex s/f/r/x/j nằm
     * giữa hàng chữ, cạnh nguyên âm. Thử thay MỘT phím thanh giữa từ (không phải phím đầu/
     * cuối) bằng phím kề; nhận ứng viên phổ biến ít nhất bằng từ đang ra; ưu tiên nhân đôi
     * nguyên âm ("as" ⇐ "aa"), rồi tần suất. Chỉ gợi ý (slot 3), không tự thay. Port iOS.
     */
    fun toneSlipCorrection(raw: String, compose: (String) -> String, frequency: (String) -> Int?): String? {
        if (raw.length !in 3..10 || !raw.all { isAsciiLetter(it) }) return null
        val lower = raw.lowercase().toCharArray()
        val current = compose(String(lower))
        val curFreq = frequency(current) ?: return null
        var best: String? = null
        var bestKey = -1
        for (i in 1 until lower.size - 1) {
            // phím thanh phải đứng sau nguyên âm (hoặc w): "tr" trong "tre" là phụ âm, không phải dấu hỏi
            if (lower[i] !in TONE_KEYS || lower[i - 1] !in "aeiouyw") continue
            for (n in neighbors[lower[i]].orEmpty()) {
                val c = lower.copyOf(); c[i] = n
                val w = compose(String(c))
                if (w == current) continue
                val f = frequency(w) ?: continue
                val doubled = n == lower[i - 1] && n in "aeo"
                if (f < curFreq - (if (doubled) DOUBLED_SLACK else 0)) continue
                val key = (if (doubled) 1 shl 16 else 0) + f
                if (key > bestKey) { best = w; bestKey = key }
            }
        }
        var w = best ?: return null
        if (raw[0].isUpperCase()) w = Cp.capitalizeFirst(w)
        return w
    }

    /**
     * Ứng viên MỘT sửa: thay phím thứ [pos] bằng phím kề [key] ra từ [word]. [deletion]: bỏ phím
     * thứ [pos] (chạm đúp — [AutoCorrect.repeatCandidates]); khi đó [key] = chính phím bị bỏ.
     */
    data class Candidate(val word: String, val freq: Int, val pos: Int, val key: Char, val deletion: Boolean = false)

    /**
     * MỌI cách thay đúng MỘT phím của [lower] (chữ thường) bằng phím kề ra từ hợp lệ (một từ có thể
     * xuất hiện nhiều lần, khác vị trí). Không xét đảo phím: mô phỏng không có bằng chứng chạm cho
     * nó và sửa oan tiếng lóng (nma → nam). Cắt tỉa tiền tố chết như [correction]. Dùng cho
     * [AutoCorrect] (cần cả ứng viên thứ hai để đo độ chắc).
     */
    fun oneEditCandidates(
        lower: String,
        compose: (String) -> String,
        frequency: (String) -> Int?,
        hasCompletion: (String) -> Boolean,
    ): List<Candidate> {
        val c0 = lower.toCharArray()
        val current = compose(lower)
        val out = ArrayList<Candidate>()
        fun consider(c: CharArray, pos: Int, key: Char) {
            val w = compose(String(c))
            if (w == current) return
            val f = frequency(w) ?: return
            out.add(Candidate(w, f, pos, key))
        }
        var k = 0
        while (k < c0.size && hasCompletion(stripTones(compose(String(c0, 0, k + 1))))) k++
        for (i in c0.indices) {
            if (i > k) break
            for (n in neighbors[c0[i]].orEmpty()) { val c = c0.copyOf(); c[i] = n; consider(c, i, n) }
        }
        return out
    }

    /** Toạ độ tâm phím trên lưới QWERTY (cột theo bước phím, hàng) — cho [AutoCorrect.evidence]. */
    fun keyPosition(c: Char): Pair<Int, Double>? {
        rows.forEachIndexed { r, (keys, off) -> val i = keys.indexOf(c); if (i >= 0) return r to off + i }
        return null
    }

    private const val TONE_KEYS = "sfrxj"
    // nhân đôi nguyên âm là bằng chứng mạnh: nhận cả ứng viên kém phổ biến hơn chút (đo heldout: 75→76/85, không thêm gợi ý thừa)
    private const val DOUBLED_SLACK = 10

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

    /** [toneSlipCorrection] theo setting của [bridge] (Telex; VNI không có phím thanh chữ), cache chung (khoá tách). */
    fun lexiconToneSlip(raw: String, bridge: EngineBridge): String? =
        if (bridge.vniMode) null else bridge.adjacentFixCache.value("\u0001" + raw) {
            toneSlipCorrection(raw, compose = { bridge.composeTrial(it) }, frequency = { VNSuggest.frequency(it) })
        }
}
