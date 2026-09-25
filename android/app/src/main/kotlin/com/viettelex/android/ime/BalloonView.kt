package com.viettelex.android.ime

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.os.Build
import android.view.View

/**
 * Balloon phím kiểu iOS: bubble loe phía trên, cổ cong ôm liền phím (spec §6.5).
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
        if (Build.VERSION.SDK_INT >= 28) setShadowLayer(theme.dp(2f), 0f, theme.dp(1f), 0x4D000000)
    }
    private val textPaint = theme.text(34f)
    private val textOff = theme.centerOffset(textPaint)

    private var visible = false
    private var text = ""
    private var ox = 0f; private var oy = 0f          // gốc bubble trong view
    private var bubbleW = 0f; private var bubbleH = 0f
    private var shapeW = -1f; private var shapeKx0 = -1f; private var shapeH = -1f; private var shapeBh = -1f
    private var dirtyL = 0; private var dirtyT = 0; private var dirtyR = 0; private var dirtyB = 0

    init {
        isClickable = false
        isFocusable = false
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
    }

    override fun onTouchEvent(event: android.view.MotionEvent?) = false

    /** keyRect theo toạ độ view gốc. */
    fun show(kl: Float, kt: Float, kr: Float, kb: Float, text: String) {
        val kw = kr - kl
        val bw = maxOf(kw + theme.dp(24f), theme.dp(52f))
        // Không vẽ ra ngoài cửa sổ IME được: kẹp ở 0 (strip gợi ý là headroom).
        val top = maxOf(kt - theme.dp(52f), 0f)
        var x = (kl + kr) / 2 - bw / 2
        x = x.coerceIn(0f, maxOf(0f, width - bw))
        val H = kb - top
        val kx0 = kl - x
        val bh = maxOf(kt - top - theme.dp(6f), theme.dp(22f))
        if (bw != shapeW || kx0 != shapeKx0 || H != shapeH || bh != shapeBh) {
            shapeW = bw; shapeKx0 = kx0; shapeH = H; shapeBh = bh
            buildPath(bw, kx0, kx0 + kw, H, bh)
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

    private fun buildPath(bw: Float, kx0: Float, kx1: Float, H: Float, bh: Float) {
        val r = theme.dp(9f); val kr = theme.dp(5f)
        val neckY = minOf(bh + theme.dp(12f), H)
        val d7 = theme.dp(7f); val d5 = theme.dp(5f)
        path.reset()
        path.moveTo(0f, bh)
        path.lineTo(0f, r)
        path.quadTo(0f, 0f, r, 0f)
        path.lineTo(bw - r, 0f)
        path.quadTo(bw, 0f, bw, r)
        path.lineTo(bw, bh)
        path.cubicTo(bw, bh + d7, kx1, bh + d5, kx1, neckY)          // cổ phải
        path.lineTo(kx1, H - kr)
        path.quadTo(kx1, H, kx1 - kr, H)
        path.lineTo(kx0 + kr, H)
        path.quadTo(kx0, H, kx0, H - kr)
        path.lineTo(kx0, neckY)
        path.cubicTo(kx0, bh + d5, 0f, bh + d7, 0f, bh)              // cổ trái
        path.close()
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
