package com.viettelex.android.ime

/** Sự kiện của ClipDescription (KHÔNG nội dung): là chữ, timestamp hệ thống, cờ nhạy cảm. */
data class ClipFacts(val text: Boolean, val timestamp: Long, val sensitive: Boolean)

/**
 * Nhớ [ClipFacts] của clip hiện tại theo changeCount (listener primary-clip-changed tăng số) ⇒ mỗi mục
 * clipboard chỉ MỘT binder getPrimaryClipDescription, thay vì 1–2 lần mỗi lượt nút Dán (hasText + clipId)
 * và isSensitive. [invalidate] khi bàn phím hiện: quyền đọc clipboard gắn với focus / IME đang chọn,
 * lần đọc lúc thiếu quyền (null) không được giữ qua lần hiện sau. THUẦN — pinned by ClipFactsCacheTest.
 */
class ClipFactsCache(private val fetch: () -> ClipFacts?) {
    private var forCount = 0
    private var valid = false
    private var facts: ClipFacts? = null
    /** Số lần đọc thật (test). */
    var fetches = 0
        private set

    fun get(changeCount: Int): ClipFacts? {
        if (!valid || changeCount != forCount) {
            facts = fetch(); fetches++
            forCount = changeCount; valid = true
        }
        return facts
    }

    fun invalidate() { valid = false; facts = null }
}
