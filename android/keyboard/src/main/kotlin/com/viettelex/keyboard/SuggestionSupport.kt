package com.viettelex.keyboard

import kotlin.math.ln

/** Đệm thanh gợi ý cho đủ 3 (port iOS SuggestionFill). */
object SuggestionFill {
    fun pad(base: List<String>, with: List<String>, need: Int, excluding: String = ""): List<String> {
        if (base.size >= need) return base.take(need)
        val out = base.toMutableList()
        val seen = base.mapTo(HashSet()) { it.lowercase() }
        if (excluding.isNotEmpty()) seen.add(excluding.lowercase())
        for (c in with) {
            if (out.size >= need) break
            if (seen.add(c.lowercase())) out.add(c)
        }
        return out
    }
}

/**
 * Xếp hạng thanh gợi ý — logic THUẦN (song sinh iOS SuggestRank trong SuggestionSupport.swift;
 * sửa ở đây thì sửa y hệt bên kia). Hợp đồng: iOS/docs/IOS-SUGGESTIONS.md (tầng 1, 2, 7).
 *
 * Inline (đang gõ dở): `ln(freq+1) + 2.5·ln(count+1) + 4·[trong nextWords] + 1.5·[chỉ thiếu dấu]
 * + LM`, LM = min(cap, weight·PMI(ngữ cảnh → ứng viên)) — nhân [Params.bigramDamp] khi
 * UserLangModel đã có ý kiến về chính lượt này (một ứng viên nằm trong nextWords): khi đó
 * cap·damp = 3.96 < 4 ⇒ ứng viên trong nextWords luôn hơn ứng viên chỉ có LM (còn lại ngang
 * nhau) — cá nhân thắng. Không ứng viên nào trong nextWords (người dùng mới, prev lạ) ⇒ LM đủ mạnh.
 * PMI: có dòng trigram (prev2, prev) và ứng viên có mục trigram ⇒ PMI trigram, không thì bigram.
 *
 * Từ kế tiếp (sau dấu cách, [nextFill]): có dòng trigram (prev2, prev) ⇒ từ người dùng đã gõ
 * ĐÚNG bộ ba này (≥ [LEARNED_TRI_MIN] lượt) trước, rồi top trigram tĩnh, rồi nextWords cá nhân/seed;
 * không có ⇒ như cũ: nextWords cá nhân/seed trước, thiếu thì lấp bằng top bigram tĩnh.
 * Điểm tĩnh = PMI + nextFreqWeight·freq/255 (PMI thuần nghiêng về cặp hiếm).
 */
object SuggestRank {
    data class Params(
        val bigramWeight: Double = BIGRAM_WEIGHT,
        val bigramCap: Double = BIGRAM_CAP,
        val bigramDamp: Double = BIGRAM_DAMP,
        val nextFreqWeight: Double = NEXT_FREQ_WEIGHT,
        /** false ⇒ chỉ bigram (như trước 28/09/2026 — đo so sánh). */
        val useTrigram: Boolean = true,
        val learnedTriMin: Int = LEARNED_TRI_MIN,
        val triOnlyRow: Int = TRI_ONLY_ROW,
    )

    // chọn trên heldout (27/09/2026, lưới trong SuggestBigramTests.tuneGrid); cap·damp < 4.
    // 28/09/2026 chuyển sang bigram của vnlm.bin: nextFreqWeight 12 → 10. Cùng ngày thêm trigram
    // (SuggestTrigramTests.tuneDev, tập DEV suggest-dev.txt): w 2.5 → 3, cap 8 → 12, damp 0.45 → 0.33.
    const val BIGRAM_WEIGHT = 3.0
    const val BIGRAM_CAP = 12.0
    const val BIGRAM_DAMP = 0.33
    const val NEXT_FREQ_WEIGHT = 10.0
    const val LEARNED_TRI_MIN = 2
    const val TRI_ONLY_ROW = 6
    val DEFAULT = Params()

    /**
     * Xếp pool VNSuggest (chưa lọc nhạy cảm). [pmi]\[i] = PMI của pool\[i] (null = không
     * có âm tiết trước / bảng). Hoà điểm giữ thứ tự pool (tần suất tĩnh) — iOS y hệt.
     */
    fun rankInline(pool: List<VNSuggest.Match>, pmi: FloatArray?, typedLen: Int,
                   count: (String) -> Int, ctx: Set<String>, p: Params = DEFAULT): List<String> {
        val damp = if (pool.any { it.word in ctx }) p.bigramDamp else 1.0
        val scores = DoubleArray(pool.size) { i ->
            val m = pool[i]
            val b = pmi?.getOrNull(i)?.takeIf { it > 0f }?.let { minOf(p.bigramCap, p.bigramWeight * it) * damp } ?: 0.0
            ln(m.freq + 1.0) + 2.5 * ln(count(m.word) + 1.0) +
                (if (m.word in ctx) 4.0 else 0.0) + (if (Cp.count(m.word) == typedLen) 1.5 else 0.0) + b
        }
        return pool.indices.sortedWith { a, b ->
            val c = scores[b].compareTo(scores[a]); if (c != 0) c else a.compareTo(b)
        }.map { pool[it].word }
    }

    /**
     * PMI (vnlm.bin, chỉ mục tường minh — thiếu = 0) của từng ứng viên sau ([prev2], [prev]):
     * mục trigram nếu có, không thì mục bigram (null nếu prev không có dòng bigram). Chạy nền.
     */
    fun inlinePmi(pool: List<VNSuggest.Match>, prev: String?,
                  lm: SyllableLM? = SyllableLM.shared, prev2: String? = null, p: Params = DEFAULT): FloatArray? {
        if (prev == null || lm == null || pool.isEmpty()) return null
        val ctx = lm.context(if (prev2 != null && p.useTrigram) VNSuggest.lexiconId(prev2) else -1,
            VNSuggest.lexiconId(prev)) ?: return null
        if (ctx.bigramSize == 0) return null
        return ctx.explicitAll(IntArray(pool.size) { pool[it].id })
    }

    /** Top [limit] âm tiết hay theo sau [prev] theo bigram tĩnh vnlm.bin (chữ thường, dạng lexicon). */
    fun bigramNext(prev: String, limit: Int, lm: SyllableLM? = SyllableLM.shared,
                   p: Params = DEFAULT): List<String> = contextNext(prev, null, limit, lm, p)

    /**
     * Top [limit] âm tiết sau ([prev2], [prev]) theo vnlm.bin: có dòng trigram (prev2, prev) ⇒
     * chấm bằng trigram (KN lùi bigram cho mục chỉ có ở bigram — [SyllableLM.Context.forEachNext]),
     * không thì bigram như [bigramNext].
     */
    fun contextNext(prev: String, prev2: String?, limit: Int, lm: SyllableLM? = SyllableLM.shared,
                    p: Params = DEFAULT): List<String> = topNext(prev, prev2, limit, lm, p)?.words() ?: emptyList()

    /**
     * Từ kế tiếp sau dấu cách (≤ [need], CHƯA đệm topWords). [personal] = nextWords cá nhân/seed
     * đã lọc nhạy cảm (≤ 6), [triCount] = số lượt người dùng gõ (prev2, prev → w), [filter] lọc
     * nhạy cảm cho phần tĩnh. [need] = số ô ("Số từ gợi ý", mặc định 3 — hành vi cũ).
     */
    fun nextFill(prev: String, prev2: String?, personal: List<String>, triCount: (String) -> Int,
                 filter: (List<String>) -> List<String> = { it }, lm: SyllableLM? = SyllableLM.shared,
                 p: Params = DEFAULT, need: Int = 3, chain: List<String> = emptyList()): List<String> {
        // chain = chuỗi seed ba từ sau (prev2, prev) ĐÃ lọc — sau bộ ba người dùng, trước trigram tĩnh / cá nhân (= iOS)
        val limit = maxOf(6, need + 3)
        val tri = if (prev2 != null && p.useTrigram && lm != null) topNext(prev, prev2, limit, lm, p) else null
        if (tri != null && tri.trigram) {
            val learned = personal.filter { triCount(it) >= p.learnedTriMin }.take(minOf(2, need))
            return SuggestionFill.pad(learned, chain + filter(tri.words()) + personal, need)
        }
        val base = if (chain.isEmpty()) personal.take(need) else SuggestionFill.pad(chain, personal, need)
        if (base.size >= need) return base
        val st = tri?.words() ?: bigramNext(prev, limit, lm, p)
        return SuggestionFill.pad(base, filter(st), need)
    }

    /**
     * #146: có đệm ô trống của "từ kế tiếp" bằng từ phổ biến nhất (topWords / SwipeEnglish.top)
     * không. Đệm chung chung chỉ hợp lý khi chưa có từ trước ([prev] null — đầu ô) hoặc từ
     * trước là âm tiết Việt. Từ trước là tiếng Anh ([english] = đang ở chế độ Tiếng Anh, hoặc
     * từ Anh không phải âm tiết Việt giữa câu Việt — "they") ⇒ KHÔNG đệm: "they" → "the of and"
     * (top unigram) là gợi ý sai; chỉ còn bằng chứng ngữ cảnh thật (cặp cá nhân / seed).
     * [isEnglish]/[isVietSyllable] nhận từ chữ thường; chỉ gọi khi cần (ít ô hơn cần). iOS y hệt.
     */
    fun padsWithTopWords(prev: String?, english: Boolean,
                         isEnglish: (String) -> Boolean = { SwipeEnglish.containsIfLoaded(it) },
                         isVietSyllable: (String) -> Boolean = { VNSuggest.lexiconId(it) >= 0 }): Boolean {
        if (prev == null) return true
        if (english) return false
        val low = prev.lowercase()
        return !isEnglish(low) || isVietSyllable(low)
    }

    /** Kết quả [topNext]: [n] id đầu (điểm giảm dần) + điểm; [trigram] = chấm bằng dòng trigram. */
    class Top(@JvmField val ids: IntArray, @JvmField val scores: DoubleArray, @JvmField var n: Int,
              @JvmField val trigram: Boolean) {
        fun words(): List<String> = List(n) { VNSuggest.display(ids[it]) }
    }

    /** Top [limit] (id, điểm) sau ([prev2], [prev]) — null nếu không có dữ liệu. Chèn vào mảng cỡ limit, không sort. */
    fun topNext(prev: String, prev2: String?, limit: Int, lm: SyllableLM? = SyllableLM.shared,
                p: Params = DEFAULT): Top? {
        if (lm == null || limit <= 0) return null
        val pid = VNSuggest.lexiconId(prev)
        val ctx = if (prev2 != null && p.useTrigram) lm.context(VNSuggest.lexiconId(prev2), pid) else null
        val tri = ctx != null && ctx.hasTrigram
        val top = Top(IntArray(limit), DoubleArray(limit), 0, tri)
        val ids = top.ids; val sc = top.scores
        val fw = p.nextFreqWeight / 255.0
        fun push(id: Int, pmi: Float) {
            val s = pmi + fw * VNSuggest.freq(id)
            val n = top.n
            if (n == limit && s <= sc[n - 1]) return
            var j = if (n < limit) top.n++ else n - 1
            while (j > 0 && sc[j - 1] < s) { sc[j] = sc[j - 1]; ids[j] = ids[j - 1]; j-- }
            sc[j] = s; ids[j] = id
        }
        // dòng trigram đủ dài ⇒ chỉ nó (bỏ duyệt cả dòng bigram prev — dòng "của"/"và" hàng nghìn
        // mục); ngắn ⇒ trộn đủ hai dòng (KN lùi γ3 + s2)
        if (tri && ctx!!.forEachTrigram { id, pmi -> push(id, pmi) } < p.triOnlyRow) {
            top.n = 0
            ctx.forEachNext { id, pmi -> push(id, pmi) }
        } else if (!tri) {
            val row = lm.bigram(pid)
            if (row.size == 0) return null
            row.forEach { id, pmi -> push(id, pmi) }
        }
        return if (top.n == 0) null else top
    }
}

object TypingHeuristics {
    /** Double-space → ". " (hành vi Apple): trước space là chữ/số, không phải dấu câu. */
    fun doubleSpaceMakesPeriod(context: String, lastWasSpace: Boolean): Boolean {
        if (!lastWasSpace || !context.endsWith(" ")) return false
        val rest = context.dropLast(1)
        val prev = Cp.lastCodePoint(rest) ?: return false
        return !Character.isWhitespace(prev) && prev != '.'.code && prev != '!'.code &&
            prev != '?'.code && prev != ','.code
    }
}

/**
 * "Tự thêm dấu cách sau dấu câu" ([KeyboardSettings.autoSpaceAfterPunct], mặc định TẮT). Phần
 * THUẦN, port 1:1 iOS SuggestionSupport.swift (AutoSpace) — test hai bên cùng số liệu. Session:
 * sau phím . , ? ! ; : chèn " " và nhớ lại; phím kế là dấu cách ⇒ nuốt, ⌫ ⇒ chỉ xoá dấu cách
 * tự thêm, dấu câu / "/" / xuống dòng ⇒ gỡ dấu cách trước nó, ngoặc/nháy đóng ⇒ gỡ rồi dời
 * dấu cách ra sau ngoặc ("hi." + ")" → "hi.) ").
 */
object AutoSpace {
    const val TRIGGERS = ".,?!;:"
    const val CLOSERS = ")]}\"'”’»›"

    enum class Reaction { KEEP, REMOVE, CARRY }

    /** Phím chèn chữ [s] ngay sau dấu cách tự thêm. */
    fun reaction(s: String): Reaction {
        val c = s.singleOrNull() ?: return Reaction.KEEP
        return when {
            c in CLOSERS -> Reaction.CARRY
            c in TRIGGERS || c == '/' -> Reaction.REMOVE
            else -> Reaction.KEEP
        }
    }

    /**
     * Vừa chèn [punct]: có thêm dấu cách không. [before] = chữ trước con trỏ SAU khi chèn (phải
     * kết thúc bằng [punct]), [after] = chữ sau con trỏ (null = không đọc được).
     */
    fun shouldAdd(punct: String, before: String, after: String?): Boolean {
        val p = punct.singleOrNull() ?: return false
        if (p !in TRIGGERS || before.lastOrNull() != p) return false
        // Đã có khoảng trắng / dấu câu / ngoặc đóng ngay sau con trỏ (sửa giữa câu).
        after?.firstOrNull()?.let { if (it.isWhitespace() || it in TRIGGERS || it in CLOSERS) return false }
        val rest = before.dropLast(1)
        val token = rest.substring(rest.indexOfLast { it.isWhitespace() } + 1)
        val prev = token.lastOrNull() ?: return false            // dấu câu đứng riêng (" :)")
        if (prev.isDigit() && (p == '.' || p == ',' || p == ':')) return false   // 3.5 · 1,000 · 10:30
        if ('@' in token || '/' in token) return false            // email, URL, đường dẫn
        return !looksLikeDomain(token)
    }

    /** "www.google", "vnexpress.net", "a.b-c.io": đoạn cuối sau dấu chấm ≥ 2 ký tự. "e.g", "hi.." thì không. */
    fun looksLikeDomain(token: String): Boolean {
        if (token.lowercase().startsWith("www")) return true
        val parts = token.split('.')
        if (parts.size < 2 || parts.last().length < 2) return false
        return parts.all { part -> part.isNotEmpty() && part.all { it.isLetterOrDigit() || it == '-' } }
    }
}

/** Nhịp thời gian iOS (giây) cho IME. */
object TypingTimings {
    const val DOUBLE_SPACE_S = 0.35
    const val SUGGESTION_DEBOUNCE_MS = 30L
    const val SHIFT_DOUBLE_TAP_S = 0.3
    const val BACKSPACE_REPEAT_DELAY_S = 0.5
    const val BACKSPACE_REPEAT_INTERVAL_S = 0.09
    const val BACKSPACE_DOUBLE_AFTER_S = 1.6
    const val BACKSPACE_WORD_AFTER_S = 3.0
    const val BACKSPACE_WORD_EVERY_NTH_TICK = 4
    const val SPACE_TRACKPAD_HOLD_S = 0.4
    const val TRACKPAD_DP_PER_CHAR = 9f
    const val USERLM_SAVE_COALESCE_MS = 5000L
}
