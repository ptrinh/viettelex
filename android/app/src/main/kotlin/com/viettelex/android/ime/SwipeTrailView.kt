package com.viettelex.android.ime

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.os.SystemClock
import android.view.View

/**
 * Vệt gõ vuốt: overlay phủ đúng vùng phím (cùng toạ độ [KeyboardView]), không nhận touch.
 * Chỉ giữ điểm trong [TAIL_MS] gần nhất; nhấc tay thì mờ dần [FADE_MS]. Mảng điểm, Path,
 * Paint cấp sẵn — onDraw không cấp phát. Không vẽ/không hẹn khung hình khi không vuốt.
 */
@SuppressLint("ViewConstructor")
class SwipeTrailView(context: Context, theme: ImeTheme) : View(context) {
    private val xs = FloatArray(CAP)
    private val ys = FloatArray(CAP)
    private val ts = LongArray(CAP)
    private var head = 0          // vị trí ghi kế tiếp
    private var size = 0
    private var active = false
    private var fadeStart = 0L
    private val path = Path()
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
        strokeWidth = theme.dp(5f)
        color = theme.action
    }
    private val baseAlpha = android.graphics.Color.alpha(theme.action) * 3 / 4

    init {
        isClickable = false
        isFocusable = false
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
        setWillNotDraw(false)
    }

    override fun onTouchEvent(event: android.view.MotionEvent?) = false

    fun begin() { size = 0; head = 0; active = true; fadeStart = 0L; postInvalidateOnAnimation() }

    fun add(x: Float, y: Float, tMs: Long) {
        if (!active) return
        xs[head] = x; ys[head] = y; ts[head] = tMs
        head = (head + 1) % CAP
        if (size < CAP) size++
        postInvalidateOnAnimation()
    }

    /** Nhấc tay (mờ dần) hoặc huỷ ([fade] = false: xoá ngay). */
    fun end(fade: Boolean) {
        if (!active && size == 0) return
        active = false
        if (fade && size > 1) { fadeStart = SystemClock.uptimeMillis(); postInvalidateOnAnimation() }
        else { size = 0; invalidate() }
    }

    override fun onDraw(c: Canvas) {
        if (size < 2) return
        val now = SystemClock.uptimeMillis()
        var alpha = baseAlpha
        if (!active) {
            val f = (now - fadeStart).toFloat() / FADE_MS
            if (f >= 1f) { size = 0; return }
            alpha = (baseAlpha * (1f - f)).toInt()
        }
        // Lúc đang vuốt: chỉ vẽ điểm trong TAIL_MS gần nhất (ngón đứng yên ⇒ vệt co lại rồi hết).
        val cutoff = (if (active) now else fadeStart) - TAIL_MS
        path.reset()
        var n = 0
        for (i in 0 until size) {
            val k = (head - size + i + CAP) % CAP
            if (ts[k] < cutoff) continue
            if (n == 0) path.moveTo(xs[k], ys[k]) else path.lineTo(xs[k], ys[k])
            n++
        }
        if (n >= 2) {
            paint.alpha = alpha
            c.drawPath(path, paint)
        }
        if (!active || n >= 2) postInvalidateOnAnimation()
    }

    companion object {
        private const val CAP = 128
        const val TAIL_MS = 300L
        const val FADE_MS = 200L
    }
}
