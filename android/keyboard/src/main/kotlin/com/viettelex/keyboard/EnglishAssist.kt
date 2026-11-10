package com.viettelex.keyboard

/*
 * EnglishAssist.kt — GỢI Ý TIẾNG ANH GIỮA CÂU VIỆT trên thanh gợi ý (góp ý người dùng 19/10/2026:
 * "nhiều khi có từ tiếng Anh dài mà không nhớ cách viết"). Bản song sinh của
 * iOS/Keyboard/EnglishAssist.swift — sửa ở đây thì sửa y hệt bên kia (test hai bên cùng ví dụ).
 *
 * Chế độ tiếng Việt, phím thô (a–z, ≥ 4 phím) của từ đang gõ:
 *  1. HOÀN THÀNH: tiền tố từ tiếng Anh và cách đọc tiếng Việt yếu ⇒ trộn từ tiếng Anh (tần suất
 *     enlexicon). Cùng ngưỡng macOS PredictionLogic.prefersEnglish: không âm tiết Việt nào khớp ⇒
 *     tiếng Anh luôn; có ⇒ từ Anh đầu ≥ [MIN_FREQ] và hơn âm tiết Việt mạnh nhất ≥ [MARGIN], chữ
 *     đang hiện không là âm tiết Việt tần suất ≥ [MAX_EXACT].
 *  2. SỬA CHÍNH TẢ: không từ Anh nào bắt đầu bằng phím thô, không âm tiết Việt nào khớp, ≥
 *     [TYPO_MIN_LEN] phím ⇒ từ Anh cách ≤ 1 sửa (≤ 2 khi ≥ [TYPO_LONG_LEN]), tính cả tiền tố (đang gõ
 *     dở: "acomm" → accommodation). Damerau OSA, giữ chữ đầu, dải chéo ⇒ ≤ ~70 ô mỗi từ.
 *
 * HIỆU NĂNG: chạy trong [SuggestJob.compute] (thread nền). Từ rõ là tiếng Việt hoặc phím thô < 4 /
 * ngoài a–z ⇒ null TRƯỚC khi chạm lexicon tiếng Anh. Nhận gợi ý = đường chạm gợi ý có sẵn (chèn
 * nguyên văn + dấu cách, reset engine) ⇒ Telex không bỏ dấu lại.
 */
object EnglishAssist {
    const val MIN_RAW = 4
    const val MIN_FREQ = 150
    const val MARGIN = 80
    const val MAX_EXACT = 60
    const val MAX_RAW = 24
    const val COMPLETION_LIMIT = 6
    const val TYPO_MIN_LEN = 5
    const val TYPO_LONG_LEN = 8
    const val TYPO_MIN_FREQ = 80
    const val TYPO_LIMIT = 2

    enum class Kind { COMPLETION, CORRECTION }

    /** [words]: từ tiếng Anh chữ thường (dạng lexicon), xếp hạng — bên gọi lo hoa/thường. */
    data class Result(val words: List<String>, val kind: Kind)

    /** Cổng rẻ (không tra gì): phím thô 4…24 chữ a–z (hoa/thường). */
    fun eligible(raw: String): Boolean {
        if (raw.length < MIN_RAW || raw.length > MAX_RAW) return false
        return raw.all { it in 'a'..'z' || it in 'A'..'Z' }
    }

    /**
     * Gợi ý tiếng Anh cho từ đang gõ (null = không gì). [pool] = VNSuggest.matches(composed) (đã bỏ
     * chính composed), [typedFreq] = VNSuggest.frequency(composed). [lex] chỉ được gọi khi qua hết
     * cổng tiếng Việt.
     */
    fun suggest(raw: String, composed: String, pool: List<VNSuggest.Match>, typedFreq: Int?,
                lex: () -> SwipeEnglish.Lexicon = { SwipeEnglish.lexicon }): Result? {
        if (!eligible(raw)) return null
        // Telex đã bỏ dấu/thanh (chữ hiện có ký tự ngoài ASCII) mà vẫn có âm tiết Việt khớp ⇒ đang gõ
        // tiếng Việt: không tính gì thêm. (Từ Anh dài làm hỏng âm tiết ⇒ engine trả lại phím thô, ASCII.)
        if (pool.isNotEmpty() && composed.any { it.code >= 0x80 }) return null
        val n = Cp.count(composed)
        var exact = typedFreq ?: -1
        var best = typedFreq ?: -1
        for (m in pool) {
            best = maxOf(best, m.freq)
            if (Cp.count(m.word) == n) exact = maxOf(exact, m.freq)
        }
        // Rõ là tiếng Việt ("thin" ~ thìn, "nguowif" → người): không tra tiếng Anh.
        if (exact >= MAX_EXACT) return null
        // Âm tiết Việt khớp đã mạnh tới mức không từ Anh nào (tần suất ≤ 255) hơn nổi MARGIN.
        if (pool.isNotEmpty() && best > 255 - MARGIN) return null
        val lexicon = lex()
        if (lexicon.count == 0) return null
        val low = raw.lowercase()
        val comps = SwipeEnglish.completions(low, COMPLETION_LIMIT, lexicon)
        if (comps.isNotEmpty()) {
            val top = comps[0].freq
            if (!(pool.isEmpty() || (top >= MIN_FREQ && top - best >= MARGIN))) return null
            return Result(comps.map { it.word }, Kind.COMPLETION)
        }
        if (pool.isNotEmpty() || low.length < TYPO_MIN_LEN || indexOf(low, lexicon) >= 0) return null
        val fixes = corrections(low, lexicon)
        return if (fixes.isEmpty()) null else Result(fixes, Kind.CORRECTION)
    }

    fun indexOf(word: String, lex: SwipeEnglish.Lexicon): Int = lex.indexOf(word)

    private class Hit(val d: Int, val whole: Boolean, val f: Int, val i: Int)

    /**
     * Từ tiếng Anh cách [low] (a–z chữ thường) ≤ 1 sửa (≤ 2 khi ≥ TYPO_LONG_LEN), cùng chữ đầu, tần
     * suất ≥ TYPO_MIN_FREQ. Khớp cả từ trước khớp tiền tố; rồi khoảng cách tăng, tần suất giảm.
     */
    fun corrections(low: String, lex: SwipeEnglish.Lexicon, limit: Int = TYPO_LIMIT): List<String> {
        val n = low.length
        if (n < TYPO_MIN_LEN) return emptyList()
        val maxD = if (n >= TYPO_LONG_LEN) 2 else 1
        val first = low[0]
        val start = lex.lowerBound(first.toString())
        val end = if (first >= 'z') lex.count else lex.lowerBound((first + 1).toString())
        val hits = ArrayList<Hit>()
        val rows = IntArray(3 * (n + 1))
        val out = IntArray(2)
        val w = lex.View()     // đọc tại chỗ trên buffer — không String mỗi từ
        for (i in start until end) {
            val f = lex.freq(i)
            if (f < TYPO_MIN_FREQ) continue
            val m = lex.length(i)
            if (m < n - maxD) continue
            distance(w.at(i), low, maxD, rows, out)
            val full = out[0]; val prefix = out[1]
            if (full in 1..maxD) hits.add(Hit(full, true, f, i))
            else if (m > n && prefix in 1..maxD) hits.add(Hit(prefix, false, f, i))
        }
        hits.sortWith { x, y ->
            when {
                x.whole != y.whole -> if (x.whole) -1 else 1
                x.d != y.d -> x.d - y.d
                x.f != y.f -> y.f - x.f
                else -> x.i - y.i
            }
        }
        return hits.take(limit).map { lex.word(it.i) }
    }

    /**
     * Khoảng cách Damerau (OSA) ≤ [maxD] giữa từ [w] và phím thô [r]: out[0] = cả từ, out[1] = nhỏ
     * nhất trên các tiền tố của [w] dài |r|±maxD; > maxD ⇒ maxD + 1. Chỉ tính dải chéo 2·maxD+1, tới
     * hàng |r|+maxD.
     */
    fun distance(w: CharSequence, r: String, maxD: Int, rows: IntArray, out: IntArray) {
        val n = r.length; val m = w.length; val inf = maxD + 1; val stride = n + 1
        out[0] = inf; out[1] = inf
        if (m < n - maxD) return
        val last = minOf(m, n + maxD)
        for (j in 0..n) rows[j] = if (j <= maxD) j else inf
        var base0 = 0; var base1 = stride; var base2 = 2 * stride
        var prevChar = '\u0000'
        var row = 1
        while (row <= last) {
            val c = w[row - 1]
            val lo = maxOf(1, row - maxD); val hi = minOf(n, row + maxD)
            rows[base1] = if (row <= maxD) row else inf
            if (lo > 1) rows[base1 + lo - 1] = inf
            var rowMin = rows[base1]
            for (j in lo..hi) {
                val cost = if (c == r[j - 1]) 0 else 1
                var v = minOf(rows[base0 + j] + 1, rows[base1 + j - 1] + 1, rows[base0 + j - 1] + cost)
                if (row > 1 && j > 1 && c == r[j - 2] && prevChar == r[j - 1]) v = minOf(v, rows[base2 + j - 2] + 1)
                if (v > inf) v = inf
                rows[base1 + j] = v
                if (v < rowMin) rowMin = v
            }
            if (hi < n) rows[base1 + hi + 1] = inf
            if (row >= n - maxD && hi == n && rows[base1 + n] < out[1]) out[1] = rows[base1 + n]
            if (row == m && hi == n) out[0] = rows[base1 + n]
            if (rowMin > maxD) break
            val t = base2; base2 = base0; base0 = base1; base1 = t
            prevChar = c
            row++
        }
    }

    /** "Lọc từ nhạy cảm" — cùng bộ lọc gợi ý tiếng Việt (từ, cặp sau [prev], bộ ba). */
    fun filtered(r: Result?, prev: String?, prev2: String?, enabled: Boolean): Result? {
        r ?: return null
        val w = SensitiveWords.filter(r.words, enabled, after = prev, prev2 = prev2)
        return if (w.isEmpty()) null else Result(w, r.kind)
    }

    /**
     * Trộn vào danh sách tiếng Việt đã xếp hạng: hoàn thành ⇒ 2 từ Anh đầu dẫn, rồi tiếng Việt, rồi
     * phần còn lại; sửa chính tả ⇒ bản sửa tiếng Việt (nếu có) trước, rồi từ Anh. Bỏ trùng.
     */
    fun merge(vietnamese: List<String>, english: Result?): List<String> {
        if (english == null || english.words.isEmpty()) return vietnamese
        val ordered = when (english.kind) {
            Kind.COMPLETION -> english.words.take(2) + vietnamese + english.words.drop(2)
            Kind.CORRECTION -> vietnamese + english.words
        }
        val seen = HashSet<String>()
        return ordered.filter { seen.add(it.lowercase()) }
    }
}
