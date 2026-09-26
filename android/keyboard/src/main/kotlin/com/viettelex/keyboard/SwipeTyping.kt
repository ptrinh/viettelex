package com.viettelex.keyboard

import java.text.Normalizer
import kotlin.math.ln
import kotlin.math.sqrt

/*
 * SwipeTyping.kt — phần THUẦN của tích hợp gõ vuốt (không View/MotionEvent):
 *  - [GestureClassifier]: chạm hay vuốt (chữ đầu vẫn chèn NGAY lúc chạm xuống; thành vuốt
 *    thì caller huỷ chữ đó bằng EngineBridge.undoLastLetter).
 *  - [SwipeSuggest]: ứng viên decoder → từ có dấu top-1 + biến thể cho thanh gợi ý,
 *    điểm ngữ cảnh từ UserLangModel, luật dấu cách treo.
 * Cùng hằng số/hành vi với bản iOS.
 */

/**
 * Bộ phân loại cử chỉ trên một phím chữ. Mọi toạ độ dp, thời gian ms.
 *
 * Thành VUỐT khi (cùng lúc): chỉ một ngón, đã ra khỏi phím xuất phát, xa điểm chạm
 * ≥ [Params.minDistanceKeys] bề rộng phím và tốc độ trung bình ≥ [Params.minSpeed].
 * Vừa gõ chữ trong [Params.fastTypingWindowMs] ⇒ hai ngưỡng nhân hệ số giảm tuyến tính
 * từ [Params.fastTypingFactor] về 1 (kiểu AOSP LatinIME: gõ nhanh kéo lệch ngón không
 * thành vuốt). Ngón thứ hai, hoặc quá [Params.lockAfterMs] chưa đạt ⇒ khoá là CHẠM.
 */
class GestureClassifier(val params: Params = Params()) {
    data class Params(
        val minDistanceKeys: Float = 1.0f,
        /** dp/ms. */
        val minSpeed: Float = 0.1f,
        val lockAfterMs: Long = 500,
        val fastTypingWindowMs: Long = 350,
        val fastTypingFactor: Float = 3.0f,
    )

    enum class State { IDLE, PENDING, SWIPE, TAP }

    var state = State.IDLE; private set
    private var x0 = 0f; private var y0 = 0f; private var t0 = 0L
    private var kl = 0f; private var kt = 0f; private var kr = 0f; private var kb = 0f
    private var distThreshold = 0f
    private var speedThreshold = 0f
    private var left = false

    /**
     * Ngón chạm xuống phím chữ (rect [keyL]…[keyB]). [sinceLastLetterMs] = thời gian từ
     * phím chữ trước (Long.MAX_VALUE nếu không có).
     */
    fun begin(x: Float, y: Float, tMs: Long, keyL: Float, keyT: Float, keyR: Float, keyB: Float,
              keyWidth: Float, sinceLastLetterMs: Long) {
        state = State.PENDING
        x0 = x; y0 = y; t0 = tMs
        kl = keyL; kt = keyT; kr = keyR; kb = keyB
        left = false
        val f = factorAfterTyping(sinceLastLetterMs)
        distThreshold = params.minDistanceKeys * keyWidth * f
        speedThreshold = params.minSpeed * f
    }

    /** Hệ số ngưỡng sau khi vừa gõ: fastTypingFactor ở 0 ms → 1 ở hết cửa sổ. */
    fun factorAfterTyping(sinceMs: Long): Float {
        val w = params.fastTypingWindowMs
        if (sinceMs < 0 || sinceMs >= w) return 1f
        return 1f + (params.fastTypingFactor - 1f) * (1f - sinceMs.toFloat() / w.toFloat())
    }

    /** Ngón khác chạm xuống: đang chờ ⇒ khoá chạm (gõ chồng ngón). */
    fun pointerAdded() { if (state == State.PENDING) state = State.TAP }

    /** Điểm mới của ngón đang theo dõi (kể cả điểm lịch sử). */
    fun move(x: Float, y: Float, tMs: Long): State {
        if (state != State.PENDING) return state
        val dt = tMs - t0
        if (!left && (x < kl || x >= kr || y < kt || y >= kb)) left = true
        val dx = x - x0; val dy = y - y0
        val dist = sqrt(dx * dx + dy * dy)
        if (left && dist >= distThreshold && dt > 0 && dist / dt.toFloat() >= speedThreshold) {
            state = State.SWIPE
        } else if (dt > params.lockAfterMs) {
            state = State.TAP
        }
        return state
    }

    fun end() { state = State.IDLE }
}

/** Kết quả vuốt: từ chèn + biến thể cho thanh gợi ý (đã theo chữ hoa). */
data class SwipeChoice(val word: String, val alternatives: List<String>)

object SwipeSuggest {
    const val TOP_K = 5
    const val MAX_ALTERNATIVES = 3

    /** Chữ hoa theo shift lúc bắt đầu vuốt. */
    enum class Case { LOWER, FIRST, ALL }

    /** Bỏ dấu tiếng Việt + đ→d, chữ thường (khớp dạng folded của lexicon). */
    fun fold(w: String): String {
        val n = Normalizer.normalize(w.lowercase(), Normalizer.Form.NFD)
        val sb = StringBuilder(n.length)
        for (c in n) {
            if (Character.getType(c) == Character.NON_SPACING_MARK.toInt()) continue
            sb.append(if (c == 'đ') 'd' else c)
        }
        return sb.toString()
    }

    /**
     * Điểm ngữ cảnh: từ kế tiếp hay gặp sau (prev2, prev1) được cộng [NEXT_BONUS]; từ
     * người dùng hay gõ cộng ln(1+count)·[PERSONAL_WEIGHT] (trần [PERSONAL_CAP]).
     */
    class Context(private val next: Set<String>, private val nextFolded: Set<String>,
                  private val count: (String) -> Int) {
        val folded: ((String) -> Float)? = if (nextFolded.isEmpty()) null else { f -> if (f in nextFolded) NEXT_BONUS else 0f }
        val word: (String) -> Float = { w ->
            val c = count(w)
            val p = if (c > 0) minOf(PERSONAL_CAP, PERSONAL_WEIGHT * ln(1.0 + c).toFloat()) else 0f
            p + if (w in next) NEXT_BONUS else 0f
        }
    }

    const val NEXT_BONUS = 1.5f
    const val PERSONAL_WEIGHT = 0.4f
    const val PERSONAL_CAP = 1.5f

    fun context(model: UserLangModel?, prev1: String?, prev2: String?): Context {
        if (model == null) return Context(emptySet(), emptySet()) { 0 }
        val next = if (prev1 != null) model.nextWords(prev1, prev2, 24).map { it.lowercase() }.toSet() else emptySet()
        return Context(next, next.mapTo(HashSet()) { fold(it) }) { model.count(it) }
    }

    /**
     * Ứng viên không dấu (đã xếp) → top-1 có dấu + biến thể: dấu khác của dạng top-1 và
     * dạng top-2/3 (cho/co), xen kẽ, tối đa [MAX_ALTERNATIVES]. null nếu không có gì.
     */
    fun choose(cands: List<SwipeCandidate>, wordCtx: ((String) -> Float)?, case: Case = Case.LOWER): SwipeChoice? {
        var best: List<SwipeWord> = emptyList()
        var bestIdx = -1
        for ((i, c) in cands.withIndex()) {
            best = SwipeDecoder.expand(c.folded, 8, context = wordCtx)
            if (best.isNotEmpty()) { bestIdx = i; break }
        }
        if (bestIdx < 0) return null
        val word = best[0].word
        val variants = best.drop(1).map { it.word }
        val others = ArrayList<String>()
        for (c in cands.drop(bestIdx + 1)) {
            if (others.size >= 2) break
            SwipeDecoder.expand(c.folded, 1, context = wordCtx).firstOrNull()?.let { others.add(it.word) }
        }
        val alts = LinkedHashSet<String>()
        var vi = 0; var oi = 0
        // Thứ tự: biến thể dấu tốt nhất (slot giữa), dạng top-2, biến thể kế, dạng top-3…
        while (alts.size < MAX_ALTERNATIVES && (vi < variants.size || oi < others.size)) {
            if (vi < variants.size) alts.add(variants[vi++])
            if (alts.size < MAX_ALTERNATIVES && oi < others.size) alts.add(others[oi++])
        }
        alts.remove(word)
        return SwipeChoice(applyCase(word, case), alts.map { applyCase(it, case) })
    }

    fun applyCase(w: String, case: Case): String = when (case) {
        Case.LOWER -> w
        Case.FIRST -> Cp.capitalizeFirst(w)
        Case.ALL -> w.uppercase()
    }

    /**
     * Dấu cách treo: cần chèn " " trước từ vuốt khi ký tự liền trước là chữ/số/dấu câu
     * đóng. Không ở đầu ô, sau khoảng trắng/xuống dòng, sau ngoặc/nháy mở. Không đọc
     * được (null) ⇒ không thêm.
     */
    fun needsLeadingSpace(before: String?): Boolean {
        if (before.isNullOrEmpty()) return false
        val cp = before.codePointBefore(before.length)
        if (Character.isWhitespace(cp) || Character.isSpaceChar(cp)) return false
        return cp.toChar() !in OPENERS
    }

    private const val OPENERS = "([{\"'“‘«/-@#_–—"
}
