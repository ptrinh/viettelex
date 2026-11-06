package com.viettelex.android.ime

/**
 * Chạm mới khi còn phím nhấc-mới-chốt đang đè (space / dấu ở ?123): chốt phím cũ có thể
 * đổi plane (PlanePolicy.returnToLettersOnSpace / returnToLettersAfterSymbol) ⇒ phím đã
 * tra ở bố cục CŨ không còn hiện. THUẦN — pinned by RollingTouchTest.
 *
 * [hit] tra phím ở bố cục hiện tại; [flush] chốt phím đang chờ (trừ chính phím vừa tra —
 * cùng phím đè lần nữa); [layout] = định danh bố cục hiện tại (so bằng identity). Bố cục
 * đổi trong lúc chốt ⇒ tra lại ở bố cục mới.
 */
object FlushRoute {
    inline fun <K : Any> resolve(hit: () -> K?, flush: (K) -> Unit, layout: () -> Any?): K? {
        val first = hit() ?: return null
        val before = layout()
        flush(first)
        return if (layout() !== before) hit() else first
    }
}
