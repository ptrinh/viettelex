package com.viettelex.android.ime

import androidx.tracing.Trace

/**
 * Mốc đo hiện bàn phím / vẽ / bấm phím cho Perfetto (docs/PERF-IME-SHOW.md). Mọi tên bắt đầu "VT."
 * để lọc trong trace và cho Macrobenchmark TraceSectionMetric.
 *
 * Chi phí khi KHÔNG ghi trace: một lần đọc [Trace.isEnabled] (API 29+: một phép so cờ native) —
 * không cấp phát, không chuỗi động (tên là hằng). Section đồng bộ ([begin]/[end]) luôn đi cặp
 * trong cùng hàm; section bất đồng bộ (khung đầu, phím → vẽ) tự đóng ở lượt vẽ kế ([drew]).
 */
object ImeTrace {
    const val ON_CREATE = "VT.onCreate"
    const val ON_CREATE_INPUT_VIEW = "VT.onCreateInputView"
    const val ON_START_INPUT_VIEW = "VT.onStartInputView"
    /** onStartInputView → lượt vẽ đầu của lưới phím (bất đồng bộ, cookie 1). Cold lẫn warm. */
    const val SHOW_TO_FIRST_DRAW = "VT.showToFirstDraw"
    /** IME.onCreate → lượt vẽ đầu (chỉ lần hiện đầu sau khi service tạo — "cold"), cookie 2. */
    const val COLD_TO_FIRST_DRAW = "VT.coldToFirstDraw"
    const val KEYBOARD_DRAW = "VT.kbDraw"
    const val PLANE_SWITCH = "VT.planeSwitch"
    /** Ghi lại display list lưới phím (RenderNode, mọi phím) — nằm trong VT.kbDraw. */
    const val GRID_RECORD = "VT.gridRecord"
    /** Gợi ý lúc hiện bàn phím — hoãn ra sau khung đầu có phím (trước đây VT.startInput.refreshBar). */
    const val BAR_AFTER_FIRST_FRAME = "VT.barAfterFirstFrame"
    const val LAYOUT_BUILD = "VT.layoutBuild"
    const val ON_KEY = "VT.onKey"
    /** Lượt gợi ý hẹn giờ sau phím (phần main — gồm đường ranh giới từ khi gõ dấu cách). */
    const val SUGGEST = "VT.suggest"
    /** Phần nền của lượt gợi ý (worker). */
    const val SUGGEST_BG = "VT.suggestBg"
    /** ACTION_DOWN trên lưới phím → lượt vẽ kế của bất kỳ view bàn phím nào (cookie 3). */
    const val KEY_TO_DRAW = "VT.keyToDraw"

    private const val COOKIE_SHOW = 1
    private const val COOKIE_COLD = 2
    private const val COOKIE_KEY = 3

    private var showOpen = false
    private var coldOpen = false
    private var keyOpen = false

    @JvmStatic val enabled: Boolean get() = Trace.isEnabled()

    @JvmStatic fun begin(name: String) { if (Trace.isEnabled()) Trace.beginSection(name) }
    /** Gọi cặp với [begin] — endSection khi không ghi trace là no-op. */
    @JvmStatic fun end() { if (Trace.isEnabled()) Trace.endSection() }

    /** IME.onCreate: lần hiện đầu sau đó là cold. */
    @JvmStatic fun serviceCreated() {
        if (!Trace.isEnabled()) return
        if (coldOpen) Trace.endAsyncSection(COLD_TO_FIRST_DRAW, COOKIE_COLD)
        Trace.beginAsyncSection(COLD_TO_FIRST_DRAW, COOKIE_COLD); coldOpen = true
    }

    /** onStartInputView: bắt đầu đếm tới khung có phím. */
    @JvmStatic fun showStarted() {
        if (!Trace.isEnabled()) return
        if (showOpen) Trace.endAsyncSection(SHOW_TO_FIRST_DRAW, COOKIE_SHOW)
        Trace.beginAsyncSection(SHOW_TO_FIRST_DRAW, COOKIE_SHOW); showOpen = true
    }

    /** ACTION_DOWN một phím. */
    @JvmStatic fun keyDown() {
        if (!Trace.isEnabled()) return
        if (keyOpen) Trace.endAsyncSection(KEY_TO_DRAW, COOKIE_KEY)
        Trace.beginAsyncSection(KEY_TO_DRAW, COOKIE_KEY); keyOpen = true
    }

    /** Một view bàn phím vừa ghi xong display list (lưới phím: [keys] = true). */
    @JvmStatic fun drew(keys: Boolean) {
        if (keyOpen) { keyOpen = false; Trace.endAsyncSection(KEY_TO_DRAW, COOKIE_KEY) }
        if (!keys) return
        if (showOpen) { showOpen = false; Trace.endAsyncSection(SHOW_TO_FIRST_DRAW, COOKIE_SHOW) }
        if (coldOpen) { coldOpen = false; Trace.endAsyncSection(COLD_TO_FIRST_DRAW, COOKIE_COLD) }
    }
}
