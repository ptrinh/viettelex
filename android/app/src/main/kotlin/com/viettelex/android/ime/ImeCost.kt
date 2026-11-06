package com.viettelex.android.ime

/**
 * Bộ đếm việc (không phải thời gian) trên đường hiện bàn phím — cho test ngân sách
 * ImeRenderBudgetTest (đếm được, tất định, không phụ thuộc tốc độ máy). Chỉ main thread ghi;
 * mỗi lần ghi là một phép cộng int (không cấp phát) ⇒ để luôn bật.
 */
internal object ImeCost {
    /** onCreateInputView (dựng cả cây view bàn phím). */
    @JvmField var inputViews = 0
    /** ImeTheme dựng mới (đọc prefs.all + màu). */
    @JvmField var themes = 0
    /** KeyLayout.build (lỡ cache plane). */
    @JvmField var layoutBuilds = 0
    /** KeyboardView.onDraw (ghi display list của view — rẻ nếu lưới tĩnh còn sạch). */
    @JvmField var keyboardDraws = 0
    /** Ghi lại lưới phím tĩnh (mọi phím) — đắt; chỉ khi bố cục / shift / phím chức năng / theme đổi. */
    @JvmField var gridRecords = 0

    fun reset() { inputViews = 0; themes = 0; layoutBuilds = 0; keyboardDraws = 0; gridRecords = 0 }
}
