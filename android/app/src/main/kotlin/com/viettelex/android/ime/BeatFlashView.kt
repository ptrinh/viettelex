package com.viettelex.android.ime

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.os.SystemClock
import android.view.MotionEvent
import android.view.View
import com.viettelex.keyboard.BeatFlash

/**
 * Lớp flash của "Sàn nhảy LED" ([BeatFlash]): MỘT view tái dùng, [ImeRootView] chèn ngay DƯỚI [KeyboardView] (trên nền /
 * ảnh nền / đèn rọi / nhân vật), phủ trọn bàn phím (strip + phím). Phím cách ⇒ [kick]: qua cổng an toàn ≤ 3 lần / giây
 * thì loé ~130 ms. Vẽ = một lệnh drawColor, không cấp phát mỗi khung; hết flash ⇒ thôi hẹn khung hình. Không nhận chạm.
 * Kiểu khác ⇒ IME không giữ view này (0 chi phí). = iOS BeatFlashView.
 */
class BeatFlashView(context: Context) : View(context) {
    val gate = BeatFlash.Gate()
    private var start = Long.MIN_VALUE / 2
    private var color = 0
    private var beat = 0

    init {
        isClickable = false; isFocusable = false
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
        setWillNotDraw(false)
    }

    /** Nhịp phím cách: qua cổng ⇒ flash (true); quá 3 lần / giây ⇒ bỏ qua (false). */
    fun kick(now: Long = SystemClock.uptimeMillis()): Boolean {
        if (!gate.trigger(now / 1000.0)) return false
        color = BeatFlash.tint(beat++)
        start = now
        postInvalidateOnAnimation()
        return true
    }

    /** Độ đục lúc [now] (test + vẽ). */
    internal fun alphaAt(now: Long): Double = BeatFlash.alpha((now - start) / 1000.0)

    fun halt() { start = Long.MIN_VALUE / 2; gate.reset(); invalidate() }

    override fun onDraw(canvas: Canvas) {
        val now = SystemClock.uptimeMillis()
        val a = alphaAt(now)
        if (a > 0) canvas.drawColor(((a * 255).toInt().coerceIn(0, 255) shl 24) or color)
        if ((now - start) / 1000.0 < BeatFlash.DURATION) postInvalidateOnAnimation()
    }

    @SuppressLint("ClickableViewAccessibility")
    override fun onTouchEvent(event: MotionEvent?) = false
    override fun dispatchTouchEvent(event: MotionEvent?) = false
    override fun hasOverlappingRendering() = false
}
