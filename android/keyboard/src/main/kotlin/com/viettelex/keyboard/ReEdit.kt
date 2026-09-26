package com.viettelex.keyboard

/**
 * Hàm thuần cho SỬA LẠI từ đã gõ xong (port ý tưởng macOS `tryReopenLastCommit` /
 * `tryReEditWord`). Mọi nghi ngờ ⇒ không làm: sửa sai chữ user không yêu cầu tệ hơn
 * nhiều so với gõ literal.
 */
object ReEdit {
    /** Từ dài hơn một âm tiết thì engine cũng từ chối seed — đọc thêm vô ích. */
    const val MAX_WORD = 12

    /**
     * Phím được phép NẠP LẠI từ trước con trỏ: chỉ dấu thanh s f r x j z và móc w. KHÔNG
     * a/e/o/d (mũ/đ bằng phím lặp): con trỏ sau "to" gõ o thường là muốn "too", không phải
     * "tô" (user quyết 26/09/2026).
     */
    fun isTransformKey(ch: Char): Boolean = when (ch.lowercaseChar()) {
        's', 'f', 'r', 'x', 'j', 'z', 'w' -> true
        else -> false
    }

    /**
     * Từ (toàn chữ cái) ngay trước con trỏ trong [before]; null nếu không có, dài quá
     * [MAX_WORD], hoặc dính vào thứ không phải từ tiếng Việt đứng riêng (chữ số, `@ . _ - /`…:
     * "mp3", "gmail.com", "a_b").
     */
    fun trailingWord(before: String): String? {
        var start = before.length
        var n = 0
        while (start > 0) {
            val cp = before.codePointBefore(start)
            if (!Character.isLetter(cp)) break
            start -= Character.charCount(cp)
            if (++n > MAX_WORD) return null
        }
        if (n == 0) return null
        if (start > 0) {
            val prev = before.codePointBefore(start)
            if (Character.isLetterOrDigit(prev) || prev in GLUE) return null
        }
        return before.substring(start)
    }

    /** Ký tự ngay sau con trỏ không phải chữ/số (hoặc cuối ô) — tức con trỏ ở CUỐI từ. */
    fun atWordEnd(after: String): Boolean =
        after.isEmpty() || !Character.isLetterOrDigit(after.codePointAt(0))

    /**
     * [before] (chữ trước con trỏ, TRƯỚC khi ⌫ xoá) kết thúc bằng đúng [word] + MỘT ký tự
     * ranh giới (không phải chữ/số) — thứ ⌫ sắp xoá.
     */
    fun endsWithWordThenBoundary(before: String, word: String): Boolean {
        if (word.isEmpty() || before.isEmpty()) return false
        val last = before.codePointBefore(before.length)
        if (Character.isLetterOrDigit(last)) return false
        val head = before.substring(0, before.length - Character.charCount(last))
        return head.endsWith(word)
    }

    private val GLUE = "@._-/\\#&=+%~:".map { it.code }.toSet()
}
