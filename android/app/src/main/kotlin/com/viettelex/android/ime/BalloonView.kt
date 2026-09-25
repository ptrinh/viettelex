package com.viettelex.android.ime

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.os.Build
import android.view.View

/**
 * Preview phím kiểu Gboard (spec §6.5 — hình dạng Android từ 26/09/2026).
 * Overlay phủ toàn bàn phím, không nhận touch. Path dựng lại CHỈ khi hình dạng đổi
 * (cùng hàng phím ⇒ cùng path) bằng path.reset() — không alloc trên hot path.
 * Toạ độ theo view gốc (strip + phím).
 */
@SuppressLint("ViewConstructor")
class BalloonView(context: Context, private val theme: ImeTheme) : View(context) {
    private val path = Path()
    private val fill = theme.fill(theme.balloonFill).apply {
        // Bóng mềm 2dp lệch xuống 1dp, opacity 0.3. Shadow layer trên path chỉ được
        // tăng tốc phần cứng từ API 28; máy cũ bỏ bóng.
        if (Build.VERSION.SDK_INT >= 28) setShadowLayer(theme.dp(3f), 0f, theme.dp(1.5f), 0x33000000)
    }
    private val textPaint = theme.text(28f)
    private val textOff = theme.centerOffset(textPaint)

    private var visible = false
    private var text = ""
    private var ox = 0f; private var oy = 0f          // gốc bubble trong view
    private var bubbleW = 0f; private var bubbleH = 0f
    private var shapeW = -1f; private var shapeH = -1f

    init {
        isClickable = false
        isFocusable = false
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
    }

    override fun onTouchEvent(event: android.view.MotionEvent?) = false

    /**
     * keyRect theo toạ độ view gốc. Preview kiểu Gboard/Material: thẻ bo góc nổi NGAY
     * TRÊN phím (không cổ nối như iOS), rộng hơn phím chút, chữ lớn.
     */
    fun show(kl: Float, kt: Float, kr: Float, kb: Float, text: String) {
        val kw = kr - kl; val kh = kb - kt
        val bw = maxOf(kw * 1.2f, theme.dp(44f))
        val bh = maxOf(kh * 1.15f, theme.dp(52f))
        // Không vẽ ra ngoài cửa sổ IME được: kẹp ở 0 (strip gợi ý là headroom).
        val top = maxOf(kt - theme.dp(4f) - bh, 0f)
        val x = ((kl + kr) / 2 - bw / 2).coerceIn(0f, maxOf(0f, width - bw))
        if (bw != shapeW || bh != shapeH) {
            shapeW = bw; shapeH = bh
            path.reset()
            val r = theme.dp(10f)
            path.addRoundRect(0f, 0f, bw, bh, r, r, Path.Direction.CW)
        }
        invalidateBalloon()          // vùng cũ
        ox = x; oy = top; bubbleW = bw; bubbleH = bh
        this.text = text
        visible = true
        invalidateBalloon()          // vùng mới
    }

    fun hide() {
        if (!visible) return
        visible = false
        invalidateBalloon()
    }

    @Suppress("DEPRECATION")
    private fun invalidateBalloon() {
        val pad = theme.dp(4f)
        invalidate((ox - pad).toInt(), (oy - pad).toInt(), (ox + bubbleW + pad).toInt(), (oy + shapeH + pad).toInt())
    }

    override fun onDraw(c: Canvas) {
        if (!visible) return
        c.save()
        c.translate(ox, oy)
        c.drawPath(path, fill)
        c.drawText(text, bubbleW / 2, bubbleH / 2 + textOff, textPaint)
        c.restore()
    }
}
