package com.viettelex.android.ime

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.Shader
import android.os.SystemClock
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import com.viettelex.keyboard.RainbowBorder
import com.viettelex.keyboard.RainbowDriver

/**
 * Viền phím cầu vồng — theme "Gaming RGB" (iOS RainbowBorderView song sinh). Chỉ tồn tại khi theme có
 * "borderFx":"rainbow" (ImeRootView tạo lúc dựng); theme khác ⇒ không có view, 0 chi phí.
 *
 * MỘT dải gradient ([Strip], rộng gấp đôi bàn phím, cầu vồng lặp 2 chu kỳ) bị che bởi MỘT Path là viền mọi phím:
 * display list của view này = saveLayer · viền (đục) · dải (SRC_IN) · restore — ghi MỘT lần (dựng lại chỉ khi
 * khung phím đổi). Trượt màu = translationX, độ sáng = alpha của dải: chỉ là thuộc tính RenderNode ⇒ không ghi lại
 * display list, RenderThread / GPU vẽ. Không animation từng phím. Độ lệch luôn lấy dư theo chu kỳ ⇒ dải 2W luôn phủ
 * [0, W] (mọi bề ngang / xoay).
 *
 * Chỉ chạy KHI ĐANG GÕ ([RainbowDriver], thuần — test JVM): phím đầu hẹn khung hình (postOnAnimation, tự đếm giờ —
 * tắt hiệu ứng động hệ thống không làm đứng), tăng tốc + sáng 100%; nghỉ [RainbowBorder.IDLE_AFTER] giây ⇒ giảm tốc
 * tới dừng + mờ dần xuống ánh nghỉ (~1 s) rồi THÔI hẹn khung (0 khung hình, 0 CPU khi nghỉ).
 */
@SuppressLint("ViewConstructor")
class RainbowBorderView(context: Context, private val density: Float, val aurora: Boolean = false,
                        /** Màu riêng của viền tĩnh (theme Tự hào) — null = [com.viettelex.keyboard.AuroraFx]. */
                        val auroraColors: List<Int>? = null) : ViewGroup(context) {
    /** Dải gradient — onDraw MỘT lần (SRC_IN lên viền trong lớp của cha). Theme AI ([aurora]): gradient tĩnh [AuroraFx]. */
    private class Strip(context: Context, private val aurora: Boolean, private val colors: List<Int>?) : View(context) {
        private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { xfermode = PorterDuffXfermode(PorterDuff.Mode.SRC_IN) }
        override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
            val (cols, pos) = if (aurora && colors != null) com.viettelex.keyboard.AuroraFx.stops(colors)
                else if (aurora) com.viettelex.keyboard.AuroraFx.BORDER_COLORS to com.viettelex.keyboard.AuroraFx.BORDER_STOPS
                else RainbowBorder.stops()
            paint.shader = LinearGradient(0f, 0f, w.toFloat(), 0f, IntArray(cols.size) { cols[it] or (0xFF shl 24) },
                FloatArray(pos.size) { pos[it].toFloat() }, Shader.TileMode.CLAMP)
        }
        override fun onDraw(canvas: Canvas) { canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), paint) }
        /** Một hình chữ nhật ⇒ alpha < 1 không cần lớp offscreen. */
        override fun hasOverlappingRendering() = false
    }

    private val strip = Strip(context, aurora, if (aurora) auroraColors else null)
    private val outline = Path()
    private val outlinePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE; color = 0xFF000000.toInt()
        strokeWidth = ((if (aurora) com.viettelex.keyboard.AuroraFx.LINE_WIDTH else RainbowBorder.LINE_WIDTH) * density).toFloat()
    }
    private val driver = RainbowDriver()
    /** Độ lệch đang hiện (0…1 bề ngang). */
    val phase: Double get() = driver.offset(now())
    private var framePosted = false
    private val frame = Runnable { onFrame() }

    /** Đo: tổng thời gian main thread trong [poke] (ns) — test cộng dồn. */
    internal var costNs = 0L
    /** Số khung hình đã hẹn kể từ lúc tạo (test: nghỉ ⇒ không tăng). */
    internal var frames = 0
        private set

    init {
        isClickable = false
        isFocusable = false
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
        setWillNotDraw(false)
        addView(strip)
        strip.alpha = (if (aurora) com.viettelex.keyboard.AuroraFx.BORDER_ALPHA else RainbowBorder.REST_ALPHA).toFloat()
    }

    @SuppressLint("ClickableViewAccessibility")
    override fun onTouchEvent(event: MotionEvent?) = false
    override fun dispatchTouchEvent(ev: MotionEvent?) = false

    /** Viền mọi phím (toạ độ view này, đã thụt nửa nét) — gọi khi dựng / đổi khung phím. */
    fun setOutline(p: Path) {
        outline.set(p)
        invalidate()
    }

    val lineWidthPx: Float get() = outlinePaint.strokeWidth

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val w = MeasureSpec.getSize(widthMeasureSpec); val h = MeasureSpec.getSize(heightMeasureSpec)
        strip.measure(MeasureSpec.makeMeasureSpec((if (aurora) 1 else RainbowBorder.STRIP_PERIODS) * w, MeasureSpec.EXACTLY),
            MeasureSpec.makeMeasureSpec(h, MeasureSpec.EXACTLY))
        setMeasuredDimension(w, h)
    }

    override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {
        strip.layout(0, 0, (if (aurora) 1 else RainbowBorder.STRIP_PERIODS) * (r - l), b - t)
        if (!aurora) apply(now())
    }

    override fun dispatchDraw(canvas: Canvas) {
        if (outline.isEmpty) return
        val sc = canvas.saveLayer(0f, 0f, width.toFloat(), height.toFloat(), null)
        canvas.drawPath(outline, outlinePaint)
        super.dispatchDraw(canvas)                 // dải (RenderNode con, translationX / alpha) SRC_IN ⇒ chỉ còn viền
        canvas.restoreToCount(sc)
    }

    /** Một phím vừa tới IME (chữ đã chèn). Nghỉ → chạy: hẹn khung hình. Đang chạy: chỉ ghi giờ. */
    fun poke() {
        if (aurora) return                         // theme AI: viền tĩnh — không chạy gì
        val t0 = System.nanoTime()
        if (driver.poke(now()) && !framePosted) { framePosted = true; postOnAnimation(frame) }
        costNs += System.nanoTime() - t0
    }

    /** Ẩn bàn phím: đứng yên ngay ở ánh nghỉ. */
    fun halt() {
        if (aurora) return
        val now = now()
        driver.halt(now)
        apply(now)
        removeCallbacks(frame); framePosted = false
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        halt()
    }

    val running: Boolean get() = driver.running

    private fun now() = SystemClock.uptimeMillis() / 1000.0

    private fun onFrame() {
        framePosted = false
        val now = now()
        val more = driver.frame(now)
        apply(now)
        if (!more) return                          // đã dừng + mờ xong ⇒ thôi hẹn khung
        frames++
        framePosted = true
        postOnAnimation(frame)
    }

    /** Dịch dải + độ sáng (thuộc tính RenderNode — không vẽ lại / không ghi lại display list). */
    private fun apply(now: Double) {
        val tx = (-driver.offset(now) * width).toFloat()
        if (strip.translationX != tx) strip.translationX = tx
        val a = driver.alpha(now).toFloat()
        if (strip.alpha != a) strip.alpha = a
    }

    /** Test: chỉnh thời gian nghỉ. */
    internal fun setIdleForTest(s: Double) { driver.clock.idleAfter = s }
}
