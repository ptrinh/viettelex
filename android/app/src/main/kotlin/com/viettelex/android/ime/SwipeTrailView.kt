package com.viettelex.android.ime

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.LinearGradient
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Shader
import android.graphics.SweepGradient
import android.os.SystemClock
import android.view.View
import com.viettelex.keyboard.SwipeTrailFx
import com.viettelex.keyboard.SwipeTrailState
import com.viettelex.keyboard.SwipeTrailStroke
import com.viettelex.keyboard.SwipeTrailStyle
import kotlin.math.ceil
import kotlin.math.floor

/**
 * Vệt gõ vuốt: overlay phủ đúng vùng phím (cùng toạ độ [KeyboardView]), không nhận touch. Kiểu ("Hiệu ứng nét
 * vuốt", [SwipeTrailStyle]) chỉ đổi các Paint / shader dựng MỘT lần ở [configure]; hình học + hạt ở
 * [SwipeTrailState] (mảng cấp sẵn). Mỗi khung: MỘT Path từ mảng điểm, vẽ qua các Paint. onDraw không cấp
 * phát; không hẹn khung khi không còn gì để vẽ (0 animation khi nghỉ). Kiểu Tắt ⇒ IME gỡ view khỏi
 * KeyboardView (không gọi gì).
 *
 * Ảo ảnh: CÙNG Path vẽ thêm 5 lần với canvas xoay quanh tâm vùng phím (không dựng path mới); màu = MỘT
 * SweepGradient, xoay theo thời gian bằng local matrix (Matrix cấp sẵn). Tan chảy: màu + bề rộng tính theo thời
 * gian mỗi khung (chỉ khi còn nét — hết nét thì ngừng hẹn khung như mọi kiểu); 3 đoạn cũ → mới dựng vào MỘT
 * Path phụ cấp sẵn. Vệt lặp: 3 bóng = cùng Path vẽ với canvas dời.
 */
@SuppressLint("ViewConstructor")
open class SwipeTrailView(context: Context, private val theme: ImeTheme) : View(context) {
    var style: SwipeTrailStyle = SwipeTrailStyle.NONE
        private set
    protected var state = SwipeTrailState(SwipeTrailStyle.NONE, theme.density)
        private set
    private val path = Path()
    private val seg = Path()
    private val spin = Matrix()
    private var sweep: Shader? = null
    private var paints: Array<Paint> = emptyArray()
    private var baseAlpha = IntArray(0)
    private var widths = FloatArray(0)
    private var kinds: Array<SwipeTrailStroke.Kind> = emptyArray()
    /** Thứ tự trong cùng loại (đoạn Tan chảy / bóng Vệt lặp). */
    private var order = IntArray(0)
    private var fillLast = false
    private val dotPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    private var colors = IntArray(0)
    private val star = Path()
    private val pOut = FloatArray(5)

    init {
        isClickable = false
        isFocusable = false
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
        setWillNotDraw(false)
        configure(SwipeTrailStyle.SIMPLE)
    }

    override fun onTouchEvent(event: android.view.MotionEvent?) = false

    /** Dựng Paint / shader / pool cho kiểu (gọi lúc hiện bàn phím). Cùng kiểu ⇒ 0 việc. */
    fun configure(s: SwipeTrailStyle) {
        if (s == style) return
        style = s
        state = SwipeTrailState(s, theme.density)
        // Đơn giản = vệt cũ: 5dp, màu vệt theme × 3/4 độ đậm.
        val tr = theme.trail
        val simple = ((android.graphics.Color.alpha(tr) * 3 / 4) shl 24) or (tr and 0xFFFFFF)
        val specs = s.strokes(5.0, simple, theme.action, theme.dark)
        paints = Array(specs.size) { i -> paintFor(specs[i]) }
        baseAlpha = IntArray(specs.size) { android.graphics.Color.alpha(specs[it].argb) }
        widths = FloatArray(specs.size) { theme.dp(specs[it].width.toFloat()) }
        kinds = Array(specs.size) { specs[it].kind }
        order = IntArray(specs.size) { i -> (0 until i).count { specs[it].kind == specs[i].kind } }
        fillLast = specs.lastOrNull()?.kind == SwipeTrailStroke.Kind.FILL
        updateShader()
        colors = s.particleColors(theme.action).map { (0xFF shl 24) or it }.toIntArray()
        star.reset()
        if (s == SwipeTrailStyle.STARDUST) {
            for (k in 0 until 8) {
                val r = (if (k % 2 == 0) 4.5f else 1.5f) * theme.density
                val a = k * Math.PI / 4 - Math.PI / 2
                val x = (Math.cos(a) * r).toFloat(); val y = (Math.sin(a) * r).toFloat()
                if (k == 0) star.moveTo(x, y) else star.lineTo(x, y)
            }
            star.close()
        }
        invalidate()
    }

    private fun paintFor(sp: SwipeTrailStroke) = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        // Đoạn Tan chảy: đầu bằng (đầu tròn chồng nhau ⇒ cục sáng ở chỗ nối đoạn) — = iOS.
        strokeCap = if (sp.kind == SwipeTrailStroke.Kind.MELT) Paint.Cap.BUTT else Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
        style = if (sp.kind == SwipeTrailStroke.Kind.FILL) Paint.Style.FILL else Paint.Style.STROKE
        strokeWidth = theme.dp(sp.width.toFloat())
        color = sp.argb
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        updateShader()
    }

    /**
     * Cầu vồng: MỘT LinearGradient chéo theo cỡ view. Ảo ảnh: MỘT SweepGradient (bánh xe màu) quanh tâm vùng
     * phím, dùng chung cho nét thật + nhánh. Đặt lúc cấu hình / đổi cỡ, không mỗi khung.
     */
    private fun updateShader() {
        val w = width.coerceAtLeast(1).toFloat(); val h = height.coerceAtLeast(1).toFloat()
        when (style) {
            SwipeTrailStyle.RAINBOW -> {
                val p = paints.firstOrNull() ?: return
                val c = IntArray(SwipeTrailFx.RAINBOW.size) { (0xFF shl 24) or SwipeTrailFx.RAINBOW[it] }
                p.shader = LinearGradient(0f, h * 0.2f, w, h * 0.8f, c, null, Shader.TileMode.CLAMP)
            }
            SwipeTrailStyle.KALEIDOSCOPE -> {
                val c = IntArray(SwipeTrailFx.HUE_WHEEL.size) { (0xFF shl 24) or SwipeTrailFx.HUE_WHEEL[it] }
                val g = SweepGradient(w / 2, h / 2, c, null)
                sweep = g
                for (i in paints.indices) if (kinds[i] == SwipeTrailStroke.Kind.CONIC || kinds[i] == SwipeTrailStroke.Kind.MIRROR)
                    paints[i].shader = g
            }
            else -> sweep = null
        }
    }

    fun begin() { state.begin(); postInvalidateOnAnimation() }

    fun add(x: Float, y: Float, tMs: Long) {
        if (!state.active) return
        state.add(x, y, tMs)
        postInvalidateOnAnimation()
    }

    /** Nhấc tay (mờ dần) hoặc huỷ ([fade] = false: xoá nét ngay). */
    fun end(fade: Boolean) {
        state.end(fade, SystemClock.uptimeMillis())
        postInvalidateOnAnimation()
    }

    /** Đã chốt từ vuốt ⇒ "Pháo hoa cuối nét" (kiểu khác: 0 việc). */
    fun commitBurst() { if (state.commitBurst(SystemClock.uptimeMillis())) postInvalidateOnAnimation() }

    /** Ẩn bàn phím / gỡ: dọn hết, không hẹn khung nào. */
    fun clear() { state.clear(); invalidate() }

    override fun onDraw(c: Canvas) { drawTrail(c, SystemClock.uptimeMillis()) }

    /** Vẽ khung lúc [now]; true nếu còn phải vẽ khung sau (đã hẹn). */
    protected fun drawTrail(c: Canvas, now: Long): Boolean {
        val st = state
        if (paints.isNotEmpty() && st.build(now)) {
            path.rewind()
            val n = st.outN
            path.moveTo(st.outX[0], st.outY[0])
            for (i in 1 until n) path.lineTo(st.outX[i], st.outY[i])
            if (fillLast) path.close()
            val t = st.elapsed(now)
            for (i in paints.indices) {
                val p = paints[i]
                when (kinds[i]) {
                    SwipeTrailStroke.Kind.MIRROR -> drawMirror(c, p, baseAlpha[i], st.strokeAlpha, t)
                    SwipeTrailStroke.Kind.CONIC -> {
                        spinHue(t, 0f)
                        p.alpha = (baseAlpha[i] * st.strokeAlpha).toInt()
                        c.drawPath(path, p)
                    }
                    SwipeTrailStroke.Kind.MELT -> {
                        val rgb = SwipeTrailFx.cycleColor(t / SwipeTrailFx.MELT_HUE_PERIOD)
                        p.color = ((baseAlpha[i] * st.strokeAlpha).toInt() shl 24) or rgb
                        p.strokeWidth = (widths[i] * SwipeTrailFx.meltBreath(t / SwipeTrailFx.MELT_BREATH_PERIOD)).toFloat()
                        meltSegment(st, order[i])
                        c.drawPath(seg, p)
                    }
                    SwipeTrailStroke.Kind.GHOST -> {
                        // Bóng trôi xa dần (easeOut) + mờ theo tiến độ mờ riêng (chậm hơn nét chính).
                        val f = st.fadeFrac.toDouble()
                        val e = 1 - (1 - f) * (1 - f)
                        p.alpha = (baseAlpha[i] * (1 - f)).toInt().coerceIn(0, 255)
                        val save = c.save()
                        c.translate(theme.dp(SwipeTrailFx.chromaShiftX(order[i], e).toFloat()),
                            theme.dp(SwipeTrailFx.chromaShiftY(order[i], e).toFloat()))
                        c.drawPath(path, p)
                        c.restoreToCount(save)
                    }
                    else -> {
                        p.alpha = (baseAlpha[i] * st.strokeAlpha).toInt()
                        c.drawPath(path, p)
                    }
                }
            }
        }
        if (st.particleCount > 0 && colors.isNotEmpty()) {
            val starShape = style == SwipeTrailStyle.STARDUST
            val r = (if (style == SwipeTrailStyle.FIRE) 2.6f else 2.2f) * theme.density
            for (i in 0 until st.particleCount) {
                if (!st.particle(i, now, pOut)) continue
                dotPaint.color = colors[i % colors.size]
                dotPaint.alpha = (255 * pOut[3]).toInt().coerceIn(0, 255)
                if (starShape) {
                    val save = c.save()
                    c.translate(pOut[0], pOut[1])
                    c.rotate(Math.toDegrees(pOut[4].toDouble()).toFloat())
                    c.scale(pOut[2], pOut[2])
                    c.drawPath(star, dotPaint)
                    c.restoreToCount(save)
                } else c.drawCircle(pOut[0], pOut[1], r * pOut[2], dotPaint)
            }
        }
        val more = st.isAnimating(now)
        if (more) postInvalidateOnAnimation()
        return more
    }

    /**
     * Bánh xe màu xoay theo thời gian; [turn] = góc (độ) canvas đang xoay — trừ đi để nhánh lấy màu ở VỊ TRÍ THẬT
     * trên màn hình (= iOS: replicator nằm trong mask, gradient không xoay theo nhánh).
     */
    private fun spinHue(t: Double, turn: Float) {
        val g = sweep ?: return
        val deg = (360.0 * (t / SwipeTrailFx.KALEIDO_HUE_PERIOD % 1.0)).toFloat()
        spin.setRotate(deg - turn, width / 2f, height / 2f)
        g.setLocalMatrix(spin)
    }

    /** Ảo ảnh: CÙNG path vẽ thêm (nhánh − 1) lần, mỗi lần canvas xoay 360/nhánh độ quanh tâm vùng phím. */
    private fun drawMirror(c: Canvas, p: Paint, base: Int, fade: Float, t: Double) {
        p.alpha = (base * fade).toInt()
        val cx = width / 2f; val cy = height / 2f
        val step = 360f / SwipeTrailFx.KALEIDO_BRANCHES
        for (k in 1 until SwipeTrailFx.KALEIDO_BRANCHES) {
            spinHue(t, step * k)
            val save = c.save()
            c.rotate(step * k, cx, cy)
            c.drawPath(path, p)
            c.restoreToCount(save)
        }
    }

    /** Tan chảy: đoạn [i] (theo chiều dài, [SwipeTrailFx.MELT_SEGMENTS]) của nét khung hiện tại vào [seg]. */
    private fun meltSegment(st: SwipeTrailState, i: Int) {
        seg.rewind()
        val m = SwipeTrailFx.MELT_SEGMENTS
        val a = st.cut(m[minOf(i, m.size - 2)]); val b = st.cut(m[minOf(i + 1, m.size - 1)])
        segPoint(st, a, true)
        var k = ceil(a).toInt()
        if (k.toFloat() == a) k++
        while (k < b) { seg.lineTo(st.outX[k], st.outY[k]); k++ }
        segPoint(st, b, false)
    }

    /** Điểm ở chỉ số thực [f] (nội suy giữa hai điểm khung) — moveTo ([first]) hoặc lineTo vào [seg]. */
    private fun segPoint(st: SwipeTrailState, f: Float, first: Boolean) {
        val k = floor(f).toInt().coerceIn(0, st.outN - 1)
        val k1 = minOf(k + 1, st.outN - 1)
        val u = f - k
        val x = st.outX[k] + (st.outX[k1] - st.outX[k]) * u
        val y = st.outY[k] + (st.outY[k1] - st.outY[k]) * u
        if (first) seg.moveTo(x, y) else seg.lineTo(x, y)
    }
}
