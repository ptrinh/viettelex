package com.viettelex.keyboard

import com.viettelex.telexcore.EnglishContextLookup

/*
 * SwipeEnglish.kt — GÕ VUỐT giai đoạn 3: vuốt ra TỪ TIẾNG ANH xen trong câu tiếng Việt.
 * Bản song sinh của iOS/Keyboard/SwipeEnglish.swift — sửa ở đây thì sửa y hệt bên kia.
 *  - [SwipeEnglish.lexicon]: ~20k từ + tần suất 1 byte cùng thang vnlexicon
 *    (assets/enlexicon.bin, Scripts/gen-enlexicon.py; nguồn: docs/DATA-SOURCES.md).
 *    Không giữ template: decoder dựng template lúc chấm cho từ lọt lọc phím đầu/cuối.
 *  - [SwipeLangContext]: P(ngôn ngữ | ≤ 3 từ trước, qua dấu câu) → độ lệch + biên độ cho tiếng Anh.
 *    MẶC ĐỊNH NGHIÊNG TIẾNG VIỆT (the/thế, can/cần trùng hẳn nét vuốt).
 */

enum class SwipeLang { VI, EN }

object SwipeEnglish {
    /**
     * Từ điển Anh đọc TẠI CHỖ trên enlexicon.bin (mmap) — RAM-AUDIT #7 (10/11/2026). Định dạng
     * KHÔNG đổi ("VTE1" | count u32 LE | [len][freq][ASCII a–z]…, từ sort tăng dần — iOS đọc cùng
     * file): chỉ giữ [off] (vị trí từng mục, 4 B/từ); tra cứu nhị phân so byte ASCII ngay trên
     * buffer, String chỉ dựng cho từ thật sự trả ra ([word]). Trước: ~20k String (~1.4 MB giữ lại +
     * ~1.9 MB rác mỗi lần nạp). Bảng riêng gõ vuốt ([swipe]: phím gộp lặp, xô cặp phím đầu/cuối,
     * tần suất IntArray) dựng LƯỜI lần đầu decoder cần — tức chỉ khi vuốt tiếng Anh bật.
     * Chỉ đọc bằng absolute get ⇒ dùng chung giữa các luồng được.
     */
    class Lexicon internal constructor(private val buf: java.nio.ByteBuffer, private val off: IntArray) {
        val count: Int get() = off.size

        /** Tần suất 0–255 (thang vnlexicon). */
        fun freq(i: Int): Int = buf.get(off[i] + 1).toInt() and 255

        /** Số chữ của từ [i]. */
        fun length(i: Int): Int = buf.get(off[i]).toInt() and 255

        /** Từ [i] (chữ thường a–z) — cấp phát một String; vòng lặp nóng dùng [compare]/[view]. */
        fun word(i: Int): String {
            val p = off[i]; val n = buf.get(p).toInt() and 255
            val b = ByteArray(n)
            for (j in 0 until n) b[j] = buf.get(p + 2 + j)
            return String(b, Charsets.US_ASCII)
        }

        /** Cùng dấu với `word(i).compareTo(key)` (so từng UTF-16 code unit rồi độ dài) — không cấp phát. */
        fun compare(i: Int, key: CharSequence): Int {
            val p = off[i]; val n = buf.get(p).toInt() and 255; val m = key.length
            val lim = if (n < m) n else m
            for (j in 0 until lim) {
                val c = (buf.get(p + 2 + j).toInt() and 255) - key[j].code
                if (c != 0) return c
            }
            return n - m
        }

        /** Chỉ số đầu tiên có từ ≥ [key]. */
        fun lowerBound(key: CharSequence): Int {
            var lo = 0; var hi = off.size
            while (lo < hi) { val mid = (lo + hi) ushr 1; if (compare(mid, key) < 0) lo = mid + 1 else hi = mid }
            return lo
        }

        fun indexOf(word: CharSequence): Int {
            val i = lowerBound(word)
            return if (i < off.size && compare(i, word) == 0) i else -1
        }

        /** Từ [i] bắt đầu bằng [prefix]. */
        fun startsWith(i: Int, prefix: CharSequence): Boolean {
            val p = off[i]; val m = prefix.length
            if ((buf.get(p).toInt() and 255) < m) return false
            for (j in 0 until m) if ((buf.get(p + 2 + j).toInt() and 255) != prefix[j].code) return false
            return true
        }

        /** CharSequence dùng lại được trỏ vào từ [View.at] — so chuỗi trong vòng lặp không cấp phát. */
        inner class View : CharSequence {
            private var p = 2; private var n = 0
            fun at(i: Int): View { p = off[i] + 2; n = buf.get(off[i]).toInt() and 255; return this }
            override val length: Int get() = n
            override fun get(index: Int): Char = (buf.get(p + index).toInt() and 255).toChar()
            override fun subSequence(startIndex: Int, endIndex: Int): CharSequence = toString().substring(startIndex, endIndex)
            override fun toString(): String { val b = ByteArray(n); for (j in 0 until n) b[j] = buf.get(p + j); return String(b, Charsets.US_ASCII) }
        }

        @Volatile private var swipeTables: Swipe? = null

        /** Bảng gõ vuốt — dựng lười một lần (thread-safe). Chỉ decoder vuốt tiếng Anh gọi. */
        val swipe: Swipe
            get() = swipeTables ?: synchronized(this) { swipeTables ?: buildSwipe().also { swipeTables = it } }

        /** Đã dựng [swipe] chưa (test: tắt vuốt tiếng Anh ⇒ không dựng). */
        val hasSwipe: Boolean get() = swipeTables != null

        private fun buildSwipe(): Swipe {
            val n = off.size
            val freq = IntArray(n)
            var total = 0
            for (i in 0 until n) total += length(i)
            val keys = ByteArray(total)
            val keyStart = IntArray(n + 1)
            val first = IntArray(n); val last = IntArray(n)
            var kc = 0
            for (i in 0 until n) {
                val p = off[i]; val len = buf.get(p).toInt() and 255
                freq[i] = buf.get(p + 1).toInt() and 255
                var prev = -1
                for (j in 0 until len) {
                    val k = (buf.get(p + 2 + j).toInt() and 255) - 97
                    if (k != prev) { keys[kc++] = k.toByte(); prev = k }
                }
                first[i] = keys[keyStart[i]].toInt(); last[i] = keys[kc - 1].toInt()
                keyStart[i + 1] = kc
            }
            val bucketStart = IntArray(677)
            for (i in 0 until n) bucketStart[first[i] * 26 + last[i] + 1]++
            for (bk in 0 until 676) bucketStart[bk + 1] += bucketStart[bk]
            val fill = bucketStart.copyOf(676)
            val order = IntArray(n)
            for (i in 0 until n) { val bk = first[i] * 26 + last[i]; order[fill[bk]++] = i }
            return Swipe(this, freq, keys.copyOf(kc), keyStart, order, bucketStart)
        }
    }

    /** Bảng riêng gõ vuốt tiếng Anh (decoder SHARK2 / FUTO) — xem [Lexicon.swipe]. */
    class Swipe internal constructor(
        val lexicon: Lexicon,
        val freq: IntArray,         // 0-255, thang vnlexicon
        val keys: ByteArray,        // phím gộp chữ lặp (0…25)
        val keyStart: IntArray,
        val order: IntArray,        // chỉ số từ xếp theo cặp (phím đầu·26 + phím cuối)
        val bucketStart: IntArray,  // 677
    ) {
        val count: Int get() = lexicon.count
        fun word(i: Int): String = lexicon.word(i)
    }

    internal val EMPTY = Lexicon(java.nio.ByteBuffer.allocate(0), IntArray(0))

    @Volatile private var loaded: Lexicon? = null

    /**
     * Từ điển Anh (mmap + IntArray vị trí ~80 KB) — nạp lười, thread-safe. Đường main thread KHÔNG
     * gọi cái này (dùng [containsOrNull]/[containsIfLoaded]); worker hâm nóng ([warm]). IME [release]
     * khi bàn phím ẩn lâu và nạp lại NỀN lúc hiện ([isLoaded] cho biết có cần hâm nóng).
     */
    val lexicon: Lexicon
        get() = loaded ?: synchronized(this) {
            loaded ?: (try { parse(KeyboardData.buffer(Keys.ASSET_EN_LEXICON)) ?: EMPTY } catch (e: Exception) { EMPTY })
                .also { loaded = it; loads++ }
        }

    val isLoaded: Boolean get() = loaded != null

    /** Test: số lần [lexicon] thực sự nạp (đường main không được làm tăng). */
    @Volatile var loads = 0
        private set

    /** Hâm nóng trên luồng nền: nạp từ điển, và bảng gõ vuốt nếu [swipe]. */
    fun warm(swipe: Boolean = false) { val l = lexicon; if (swipe) l.swipe }

    /** Bỏ bảng (GC được); lần dùng sau nạp lại. Ai đang giữ tham chiếu cũ vẫn dùng được. */
    fun release() { loaded = null }

    /** Kiểm tra + đánh chỉ mục enlexicon.bin ("VTE1" | count u32 | [len][freq][ASCII]…). null = hỏng. */
    fun parse(buf: java.nio.ByteBuffer): Lexicon? {
        val b = buf.duplicate()
        val size = b.capacity()
        if (size < 8 || b.get(0) != 0x56.toByte() || b.get(1) != 0x54.toByte() || b.get(2) != 0x45.toByte() || b.get(3) != 0x31.toByte()) return null
        val n = (b.get(4).toInt() and 255) or ((b.get(5).toInt() and 255) shl 8) or
            ((b.get(6).toInt() and 255) shl 16) or ((b.get(7).toInt() and 255) shl 24)
        if (n < 0 || n > (size - 8) / 3) return null    // mỗi mục ≥ 3 byte
        val off = IntArray(n)
        var p = 8
        for (i in 0 until n) {
            if (p + 2 > size) return null
            val len = b.get(p).toInt() and 255
            if (len == 0 || p + 2 + len > size) return null
            for (j in 0 until len) {
                val k = (b.get(p + 2 + j).toInt() and 255) - 97
                if (k !in 0 until 26) return null
            }
            off[i] = p
            p += 2 + len
        }
        return Lexicon(b, off)
    }

    fun indexOf(word: String): Int = lexicon.indexOf(word)

    fun contains(word: String): Boolean = indexOf(word) >= 0

    /**
     * Như [contains] nhưng KHÔNG nạp (main thread). Chưa nạp (đang hâm nóng nền / vừa nhả lúc ẩn
     * lâu) ⇒ coi như chưa biết = false. Cần phân biệt "không có" với "chưa biết" ⇒ [containsOrNull].
     */
    fun containsIfLoaded(word: String): Boolean = containsOrNull(word) ?: false

    /** Như [contains] nhưng KHÔNG nạp: null = từ điển chưa nạp (chưa biết). */
    fun containsOrNull(word: String): Boolean? = loaded?.let { it.indexOf(word) >= 0 }

    /**
     * Chế độ Tiếng Anh (vuốt phím cách): từ bắt đầu bằng [typed] (a–z, không phân biệt hoa
     * thường), tần suất giảm dần, tối đa [limit], bỏ chính từ đang gõ. Chữ hoa theo chữ đang
     * gõ ("Hel" → "Hello", "HEL" → "HELLO"). Chữ ngoài a–z ⇒ rỗng. Giống iOS.
     */
    fun completions(typed: String, limit: Int = 24, lex: Lexicon = lexicon): List<VNSuggest.Match> {
        val low = typed.lowercase()
        if (low.isEmpty() || limit <= 0 || low.any { it !in 'a'..'z' }) return emptyList()
        val n = lex.count
        val hits = ArrayList<Int>()
        var i = lex.lowerBound(low)
        while (i < n && lex.startsWith(i, low)) { if (lex.length(i) != low.length) hits.add(i); i++ }
        hits.sortWith { x, y -> val fx = lex.freq(x); val fy = lex.freq(y); if (fx != fy) fy - fx else x - y }
        return hits.take(limit).map { VNSuggest.Match(matchCase(lex.word(it), typed), lex.freq(it)) }
    }

    /** Từ phổ biến nhất (đệm thanh gợi ý ở chế độ Tiếng Anh). */
    fun topWords(limit: Int, lex: Lexicon = lexicon): List<String> {
        if (limit <= 0) return emptyList()
        return (0 until lex.count).sortedWith { x, y -> val fx = lex.freq(x); val fy = lex.freq(y); if (fx != fy) fy - fx else x - y }
            .take(limit).map { lex.word(it) }
    }
    @Volatile private var topCache: List<String>? = null
    /** 12 từ phổ biến nhất — nạp từ điển nếu cần (gọi trên luồng nền: [warm]). Giữ qua [release] (12 String). */
    val top: List<String> get() = topCache ?: topWords(12).also { topCache = it }
    /** [top] nếu đã có, KHÔNG nạp/sắp xếp (main thread); null = chưa hâm nóng xong. */
    val topIfReady: List<String>? get() = topCache

    fun matchCase(w: String, typed: String): String {
        val f = typed.firstOrNull() ?: return w
        if (!f.isUpperCase()) return w
        if (typed.length > 1 && typed.all { it.isUpperCase() }) return w.uppercase()
        return w.replaceFirstChar { it.uppercaseChar() }
    }
}

/** Tham số tiếng Anh cho một lần decode (xem [SwipeLangContext.prior]). */
data class SwipeEnglishPrior(
    /** Cộng vào điểm mọi ứng viên tiếng Anh (âm = nghiêng Việt). */
    val bias: Float,
    /** Tiếng Anh chỉ giữ top-1 khi hơn ứng viên Việt tốt nhất ≥ margin. */
    val margin: Float,
)

object SwipeLangContext {
    enum class Kind { VI, EN, NEUTRAL }

    // GIỮ Y HỆT bản Swift. Chọn bằng SwipeEnglishTests.sweepPriors (xem bản Swift).
    val DEFAULT = SwipeEnglishPrior(bias = -0.9f, margin = 0.3f)
    val ENGLISH = SwipeEnglishPrior(bias = 0.2f, margin = 0f)
    /** Chế độ Tiếng Anh: đẩy hẳn tiếng Anh lên (ứng viên Việt bị lọc sau decode). */
    val ONLY_ENGLISH = SwipeEnglishPrior(bias = 4f, margin = 0f)

    /** Phân loại một từ đã có trên màn hình; [swipedEnglish] = vừa vuốt ra như từ tiếng Anh. */
    fun classify(word: String?, swipedEnglish: Boolean = false): Kind {
        if (word.isNullOrEmpty()) return Kind.NEUTRAL
        if (swipedEnglish) return Kind.EN
        val w = word.lowercase()
        if (!w.all { it in 'a'..'z' }) return if (w.any { it.code > 127 }) Kind.VI else Kind.NEUTRAL
        if (EnglishContextLookup.isNeutralLoanword(w)) return Kind.NEUTRAL
        if (EnglishContextLookup.opensEnglishRun(w)) return Kind.EN
        val vnForm = SwipeLexicon.indexOf(w) >= 0
        if (SwipeEnglish.contains(w)) return if (vnForm) Kind.NEUTRAL else Kind.EN
        return if (vnForm) Kind.VI else Kind.NEUTRAL
    }

    /** Độ lệch theo 2 từ trước (prev1 = liền trước) — = [prior] trên danh sách. */
    fun prior(prev1: Kind, prev2: Kind): SwipeEnglishPrior = prior(listOf(prev1, prev2))

    /**
     * Tiền nghiệm LIÊN TỤC NGÔN NGỮ (28/09/2026): đang gõ tiếng Anh thì từ kế hay là tiếng Anh,
     * đang gõ tiếng Việt thì tiếng Việt. [Continuity] — GIỮ Y HỆT bản Swift. Chỉnh trên dev
     * (SwipeLangTuneTests): mạch Việt KHÔNG cần thêm — DEFAULT đã nghiêng Việt; viBias/viMargin > 0
     * chỉ +0,1 điểm câu Việt mà −1,5…−3 điểm từ Anh chen sau từ Việt ⇒ 0. docs/DATA-SOURCES.md.
     */
    data class Continuity(
        /** Trọng số từ lùi i vị trí = decay^i (từ trung tính vẫn tính khoảng cách). */
        val decay: Float = 0.6f,
        /** Mạch Anh s ≥ 1 (một từ Anh liền trước): bias = enBias, margin 0; 0 < s < 1: nội suy từ DEFAULT. */
        val enBias: Float = 0.2f,
        val enGain: Float = 0.5f,
        /** Trần s mạch Anh (ba từ Anh ⇒ 1 + 0,6 + 0,36 = 1,96). */
        val enCap: Float = 2f,
        /** Mạch Việt: bias −= viBias·v, margin += viMargin·v, v = min(s Việt, viCap). */
        val viBias: Float = 0f,
        val viMargin: Float = 0f,
        val viCap: Float = 2f,
    )

    val CONTINUITY = Continuity()
    /** Số từ trước con trỏ được xét. */
    const val WINDOW = 3

    /**
     * Ngôn ngữ ≤ [WINDOW] từ trước con trỏ, gần nhất trước: [composing] ⇒ từ đang soạn [pending]
     * (sẽ chốt trước từ vuốt; null = không học được ⇒ trung tính) đứng đầu; [recent] = từ đã chốt,
     * CŨ → MỚI; [english] = từ đó vừa được vuốt ra như tiếng Anh.
     */
    fun kinds(composing: Boolean, pending: String?, pendingEnglish: Boolean, recent: Collection<String>,
              english: (String?) -> Boolean): List<Kind> {
        val out = ArrayList<Kind>(WINDOW)
        if (composing) out.add(classify(pending, pendingEnglish))
        val r = recent.toList()
        var i = r.size - 1
        while (out.size < WINDOW && i >= 0) { out.add(classify(r[i], english(r[i]))); i-- }
        return out
    }

    /**
     * [kinds] = ngôn ngữ ≤ 3 từ trước con trỏ, gần nhất trước. Mạch Anh s = Σ decay^i trên các
     * từ Anh, đi từ gần ra xa, DỪNG ở từ Việt đầu tiên (một từ Việt cắt mạch Anh — "check mail
     * cho" → mạch Việt); mạch Việt đối xứng (dừng ở từ Anh). Không có từ nào rõ ngôn ngữ ⇒
     * đúng [DEFAULT] (từ rời không đổi). Mạch Anh: [ENGLISH] ở s = 1, +enGain·(s − 1) tới
     * trần; mạch Việt chỉ nới biên độ/độ lệch có trần — hình học + LM mạnh vẫn thắng, từ Anh
     * chen giữa câu Việt vẫn ra.
     */
    fun prior(kinds: List<Kind>, c: Continuity = CONTINUITY): SwipeEnglishPrior {
        val en = run(kinds, Kind.EN, Kind.VI, c.decay)
        if (en >= 1f) return SwipeEnglishPrior(c.enBias + c.enGain * (minOf(en, c.enCap) - 1f), 0f)
        if (en > 0f) return SwipeEnglishPrior(DEFAULT.bias + (c.enBias - DEFAULT.bias) * en, DEFAULT.margin * (1f - en))
        val vi = minOf(run(kinds, Kind.VI, Kind.EN, c.decay), c.viCap)
        if (vi <= 0f) return DEFAULT
        return SwipeEnglishPrior(DEFAULT.bias - c.viBias * vi, DEFAULT.margin + c.viMargin * vi)
    }

    private fun run(kinds: List<Kind>, same: Kind, stop: Kind, decay: Float): Float {
        var s = 0f; var w = 1f
        for (i in 0 until minOf(3, kinds.size)) {
            val k = kinds[i]
            if (k == stop) break
            if (k == same) s += w
            w *= decay
        }
        return s
    }
}
