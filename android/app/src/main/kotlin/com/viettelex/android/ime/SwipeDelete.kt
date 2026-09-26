package com.viettelex.android.ime

import java.text.BreakIterator

/**
 * Ranh giới "từ" cho vuốt ⌫ xoá theo từ (kiểu Gboard) — THUẦN, pinned by SwipeDeleteTest.
 *
 * Một bước lùi = cụm khoảng trắng/dấu câu liền trước + cụm chữ/số ngay trước đó
 * ("xin chào, |" → bước 1 = "chào, "). Đi theo grapheme (BreakIterator) nên chữ Việt
 * có dấu (dựng sẵn hay tổ hợp), emoji ZWJ, cờ không bao giờ bị cắt đôi. Emoji / ký hiệu
 * đứng riêng = một từ. Xuống dòng là ranh giới cứng: bước chạm "\n" dừng ở đó; "\n"
 * sát con trỏ thì tự nó là một bước.
 */
object WordBoundary {
    private const val WORD = 0
    private const val SEP = 1
    private const val NEWLINE = 2
    private const val SYM = 3

    /**
     * Số UTF-16 lùi từ cuối [text] sau 1, 2, … bước (tăng dần); tối đa [max] mốc, dừng
     * ở đầu chuỗi. Mảng rỗng ⇒ không còn gì để xoá.
     */
    fun stops(text: CharSequence, max: Int = 64): IntArray {
        val str = text.toString()
        if (str.isEmpty() || max <= 0) return IntArray(0)
        val starts = graphemeStarts(str)          // đầu mỗi grapheme, tăng dần
        val out = ArrayList<Int>()
        var g = starts.size                        // grapheme đang đứng sau (lùi dần)
        fun cls(i: Int) = classify(str, starts[i])
        while (g > 0 && out.size < max) {
            var consumed = 0
            // 1) khoảng trắng / dấu câu liền trước
            while (g > 0 && cls(g - 1) == SEP) { g--; consumed++ }
            if (g > 0 && cls(g - 1) == NEWLINE) {
                if (consumed == 0) g--             // "\n" sát con trỏ: tự nó một bước
            } else if (g > 0 && cls(g - 1) == WORD) {
                while (g > 0 && cls(g - 1) == WORD) g--
            } else if (g > 0 && cls(g - 1) == SYM) {
                g--                                // emoji / ký hiệu: một grapheme một từ
            }
            out.add(str.length - (if (g < starts.size) starts[g] else str.length))
        }
        return out.toIntArray()
    }

    /** UTF-16 của [words] bước cuối (≤ số bước có). */
    fun unitsBack(text: CharSequence, words: Int): Int {
        if (words <= 0) return 0
        val s = stops(text, words)
        return if (s.isEmpty()) 0 else s.last()
    }

    fun graphemeCount(text: CharSequence): Int = if (text.isEmpty()) 0 else graphemeStarts(text.toString()).size

    private fun graphemeStarts(str: String): IntArray {
        val bi = BreakIterator.getCharacterInstance()
        bi.setText(str)
        val r = ArrayList<Int>()
        var p = bi.first()
        while (p != BreakIterator.DONE && p < str.length) {
            // An toàn: không bao giờ đứng giữa cặp surrogate.
            if (r.isEmpty() || p > r.last()) {
                if (p > 0 && p < str.length && Character.isLowSurrogate(str[p]) && Character.isHighSurrogate(str[p - 1])) {
                    p = bi.next(); continue
                }
                r.add(p)
            }
            p = bi.next()
        }
        return r.toIntArray()
    }

    private fun classify(str: String, at: Int): Int {
        val cp = str.codePointAt(at)
        if (cp == '\n'.code || cp == '\r'.code || cp == 0x2028 || cp == 0x2029) return NEWLINE
        if (Character.isLetterOrDigit(cp)) return WORD
        return when (Character.getType(cp).toByte()) {
            Character.NON_SPACING_MARK, Character.COMBINING_SPACING_MARK, Character.ENCLOSING_MARK -> WORD
            Character.MATH_SYMBOL, Character.CURRENCY_SYMBOL, Character.MODIFIER_SYMBOL,
            Character.OTHER_SYMBOL, Character.SURROGATE, Character.PRIVATE_USE -> SYM
            else -> SEP                            // khoảng trắng, dấu câu, ký tự điều khiển
        }
    }
}

/** Hình học cử chỉ vuốt trên ⌫ — THUẦN (px). */
object SwipeDelete {
    /**
     * Có bắt đầu chế độ vuốt không: kéo sang TRÁI ≥ [activatePx] và ngang trội hơn dọc
     * (chạm/giữ ⌫ có rung tay không kích hoạt nhầm).
     */
    fun activates(dx: Float, dy: Float, activatePx: Float): Boolean =
        -dx >= activatePx && -dx > kotlin.math.abs(dy)

    /**
     * Số từ theo quãng kéo sang trái [dragLeftPx] (âm = kéo qua phải điểm chạm): chưa
     * tới [activatePx] ⇒ 0; từ đó mỗi [stepPx] (≈ bề rộng một phím chữ) thêm một từ.
     */
    fun words(dragLeftPx: Float, activatePx: Float, stepPx: Float): Int {
        if (stepPx <= 0f || dragLeftPx < activatePx) return 0
        return 1 + ((dragLeftPx - activatePx) / stepPx).toInt()
    }

    /** Ngưỡng kích hoạt theo bề rộng phím: nửa phím, không dưới [minPx]. */
    fun activatePx(stepPx: Float, minPx: Float): Float = maxOf(minPx, stepPx * 0.5f)
}

/**
 * Điều phối một lượt vuốt ⌫ trên [IcProxy]: bắt đầu → cập nhật số từ → nhấc (xoá / huỷ).
 * Biết chắc con trỏ ⇒ bôi đen bằng setSelection như Gboard; không ⇒ chỉ tính đoạn để
 * xem trước ([preview]) và xoá lúc nhấc bằng [IcProxy.deleteExact] (key DEL ở WriteMode
 * key event). THUẦN — pinned by SwipeDeleteTest (FakeEditor).
 */
class SwipeDeleteController(private val proxy: IcProxy) {
    private var before: String? = null
    private var stops = IntArray(0)
    private var anchor = -1

    /** Số từ đang chọn (đã chặn theo số từ có thật). */
    var words = 0; private set
    val active: Boolean get() = before != null
    /** Đang bôi đen trong ô (không cần xem trước ở thanh gợi ý). */
    val selecting: Boolean get() = anchor >= 0

    /** false ⇒ không dùng được (ô trống / mật khẩu / không đọc được). */
    fun start(): Boolean {
        finish(false)
        val ctx = proxy.swipeContext() ?: return false
        val st = WordBoundary.stops(ctx.before)
        if (st.isEmpty()) return false
        before = ctx.before; stops = st; anchor = ctx.anchor; words = 0
        return true
    }

    /** @return số từ thực chọn. */
    fun update(requested: Int): Int {
        if (before == null) return 0
        val w = requested.coerceIn(0, stops.size)
        if (w == words) return w
        words = w
        if (anchor >= 0 && !proxy.selectBefore(anchor, units())) anchor = -1   // IC lỗi: về xem trước
        return w
    }

    private fun units() = if (words == 0) 0 else stops[words - 1]

    /** Đoạn sẽ xoá (xem trước); null nếu chưa chọn gì. */
    val preview: String? get() {
        val b = before ?: return null
        val u = units()
        return if (u == 0) null else b.substring(b.length - u)
    }

    /**
     * Nhấc tay: [commit] và có chọn ⇒ xoá, trả đoạn đã xoá (cho "Khôi phục"); còn lại
     * huỷ — thu selection về đúng con trỏ cũ — trả null.
     */
    fun finish(commit: Boolean): String? {
        val b = before ?: return null
        val u = units()
        val sel = anchor
        before = null; stops = IntArray(0); anchor = -1; words = 0
        if (!commit || u == 0) {
            if (sel >= 0 && u > 0) proxy.selectBefore(sel, 0)
            return null
        }
        val text = b.substring(b.length - u)
        val ok = if (sel >= 0) proxy.deleteSelected(sel - u) else proxy.deleteExact(text)
        return if (ok) text else null
    }
}
