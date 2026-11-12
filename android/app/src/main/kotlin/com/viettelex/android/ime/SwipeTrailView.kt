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
 *
 * Phím sáng theo đường: ô bo góc màu nhấn trên khung phím (nhận MỘT lần đầu cú vuốt, [setKeys]) — trạng thái ở
 * [SwipeTrailState] (mảng cố định). Thư pháp: dải kín như Bút lông + dấu triện son lúc nhấc tay (Path dựng sẵn).
 * Sao chổi: 4 đoạn theo chiều dài (như Tan chảy, Path phụ) + chấm sáng đầu ngón. Đom đóm / Ma trận / Cánh hoa:
 * hạt (chữ Ma trận = chuỗi 1 ký tự dựng sẵn, cánh hoa = Path dựng sẵn).
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
    private val petal = Path()
    private val pOut = FloatArray(5)
    private val gOut = FloatArray(1)
    private val rect = android.graphics.RectF()
    private val glowFill = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    private val glowEdge = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE }
    private val glowHalo = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE }
    private val sealPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    private val sealMark = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE; strokeCap = Paint.Cap.ROUND; color = 0xE6FFFFFF.toInt()
    }
    private val sealShape = Path()
    private val sealLines = Path()
    private val glyphPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        typeface = android.graphics.Typeface.create(android.graphics.Typeface.MONOSPACE, android.graphics.Typeface.BOLD)
        textAlign = Paint.Align.CENTER
    }
    /** Ma trận: chuỗi 1 ký tự dựng sẵn (vẽ không cấp phát). */
    private val glyphs = Array(SwipeTrailFx.MATRIX_GLYPHS.length) { SwipeTrailFx.MATRIX_GLYPHS[it].toString() }

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
        petal.reset()
        if (s == SwipeTrailStyle.PETALS) {   // = iOS petal (dp)
            val d = theme.density
            petal.moveTo(0f, -5 * d)
            petal.quadTo(5 * d, -1 * d, 0f, 5 * d)
            petal.quadTo(-5 * d, -1 * d, 0f, -5 * d)
            petal.close()
        }
        val accent = theme.action and 0xFFFFFF
        glowFill.color = (0x52 shl 24) or accent
        glowEdge.color = (0xE6 shl 24) or accent
        glowEdge.strokeWidth = theme.dp(1.5f)
        glowHalo.color = (0x40 shl 24) or accent
        glowHalo.strokeWidth = theme.dp(5f)
        glyphPaint.textSize = theme.dp(12f)
        buildSeal()
        invalidate()
    }

    /** Thư pháp: dấu son vuông bo góc nghiêng nhẹ + nét khắc (tâm 0, dp) — dựng một lần (= iOS buildSeal). */
    private fun buildSeal() {
        sealShape.reset(); sealLines.reset()
        if (style != SwipeTrailStyle.CALLIGRAPHY) return
        val s = theme.dp(SwipeTrailFx.SEAL_SIZE.toFloat()); val c = theme.dp(SwipeTrailFx.SEAL_CORNER.toFloat())
        sealShape.addRoundRect(-s / 2, -s / 2, s / 2, s / 2, c, c, Path.Direction.CW)
        val i = (SwipeTrailFx.SEAL_INSET * s).toFloat()
        sealLines.addRect(-i, -i, i, i, Path.Direction.CW)
        val m = SwipeTrailFx.SEAL_MARKS
        for (k in m.indices step 4) {
            sealLines.moveTo((m[k] * s).toFloat(), (m[k + 1] * s).toFloat())
            sealLines.lineTo((m[k + 2] * s).toFloat(), (m[k + 3] * s).toFloat())
        }
        val tilt = Matrix().apply { setRotate(SwipeTrailFx.SEAL_TILT.toFloat()) }
        sealShape.transform(tilt); sealLines.transform(tilt)
        sealPaint.color = (0xFF shl 24) or SwipeTrailFx.SEAL_COLOR
        sealMark.strokeWidth = theme.dp(1.1f)
    }

    /**
     * Khung phím chữ (toạ độ view = toạ độ KeyboardView) cho Phím sáng theo đường / Ma trận — gọi lúc BẮT ĐẦU cú
     * vuốt. [hitDy] = độ dời điểm chọn phím (px). Kiểu khác: 0 việc.
     */
    fun setKeys(keys: List<LaidKey>, hitDy: Float) {
        val st = state
        if (!style.usesKeys) return
        var n = 0
        for (k in keys) {
            if (k.kind != KeyKind.LETTER || k.label.length != 1) continue
            st.setKey(n++, k.left, k.top, k.right, k.bottom, k.label[0])
            if (n >= SwipeTrailState.KEY_CAP) break
        }
        st.setKeyCount(n, hitDy)
    }

    /** Ô xem thử (không phím thật): lưới 3 hàng QWERTY mẫu phủ view (= iOS sampleKeys). */
    protected fun setSampleKeys() {
        if (!style.usesKeys) return
        val rows = arrayOf("qwertyuiop", "asdfghjkl", "zxcvbnm")
        val w = width / 10f; val h = height / 3f
        val ix = theme.dp(2f); val iy = theme.dp(3f)
        var n = 0
        for ((r, row) in rows.withIndex()) {
            val x0 = (width - w * row.length) / 2
            for ((k, ch) in row.withIndex())
                state.setKey(n++, x0 + w * k + ix, h * r + iy, x0 + w * (k + 1) - ix, h * (r + 1) - iy, ch)
        }
        state.setKeyCount(n, 0f)
    }

    private fun paintFor(sp: SwipeTrailStroke) = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        // Đoạn Tan chảy / Sao chổi: đầu bằng (đầu tròn chồng nhau ⇒ cục sáng ở chỗ nối đoạn) — = iOS.
        strokeCap = if (sp.kind == SwipeTrailStroke.Kind.MELT || sp.kind == SwipeTrailStroke.Kind.SEGMENT) Paint.Cap.BUTT else Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
        style = if (sp.kind == SwipeTrailStroke.Kind.FILL || sp.kind == SwipeTrailStroke.Kind.HEAD) Paint.Style.FILL else Paint.Style.STROKE
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
        if (st.glowCount > 0) drawGlows(c, st, now)   // dưới nét (= iOS glowRoot ở dưới cùng)
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
                        meltSegment(st, order[i], SwipeTrailFx.MELT_SEGMENTS)
                        c.drawPath(seg, p)
                    }
                    SwipeTrailStroke.Kind.SEGMENT -> {
                        p.alpha = (baseAlpha[i] * st.strokeAlpha).toInt()
                        meltSegment(st, order[i], SwipeTrailFx.COMET_SEGMENTS)
                        c.drawPath(seg, p)
                    }
                    SwipeTrailStroke.Kind.HEAD -> {   // Sao chổi: chấm sáng ở đầu ngón (điểm mới nhất)
                        p.alpha = (baseAlpha[i] * st.strokeAlpha).toInt()
                        c.drawCircle(st.outX[n - 1], st.outY[n - 1], widths[i] / 2, p)
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
            val shape = when (style) { SwipeTrailStyle.STARDUST -> star; SwipeTrailStyle.PETALS -> petal; else -> null }
            val r = (when (style) { SwipeTrailStyle.FIRE -> 2.6f; SwipeTrailStyle.FIREFLY -> 2.0f; else -> 2.2f }) * theme.density
            for (i in 0 until st.particleCount) {
                if (!st.particle(i, now, pOut)) continue
                dotPaint.color = colors[i % colors.size]
                val a = (255 * pOut[3]).toInt().coerceIn(0, 255)
                dotPaint.alpha = a
                when {
                    shape != null -> {
                        val save = c.save()
                        c.translate(pOut[0], pOut[1])
                        c.rotate(Math.toDegrees(pOut[4].toDouble()).toFloat())
                        c.scale(pOut[2], pOut[2])
                        c.drawPath(shape, dotPaint)
                        c.restoreToCount(save)
                    }
                    style == SwipeTrailStyle.MATRIX -> {
                        glyphPaint.color = dotPaint.color
                        // Tâm chữ ở điểm (như iOS path glyph căn tâm hộp chữ): dời nửa chiều cao chữ hoa.
                        c.drawText(glyphs[st.glyph(i)], pOut[0], pOut[1] + glyphPaint.textSize * 0.36f, glyphPaint)
                    }
                    style == SwipeTrailStyle.FIREFLY -> {   // quầng mờ + lõi (= iOS bóng cùng màu)
                        dotPaint.alpha = a * 3 / 10
                        c.drawCircle(pOut[0], pOut[1], r * pOut[2] * 2.4f, dotPaint)
                        dotPaint.alpha = a
                        c.drawCircle(pOut[0], pOut[1], r * pOut[2], dotPaint)
                    }
                    else -> c.drawCircle(pOut[0], pOut[1], r * pOut[2], dotPaint)
                }
            }
        }
        if (style == SwipeTrailStyle.CALLIGRAPHY && st.seal(now, pOut)) {
            val save = c.save()
            c.translate(pOut[0], pOut[1])
            c.scale(pOut[2], pOut[2])
            val a = (255 * pOut[3]).toInt().coerceIn(0, 255)
            sealPaint.alpha = a
            sealMark.alpha = a * 0xE6 / 255
            c.drawPath(sealShape, sealPaint)
            c.drawPath(sealLines, sealMark)
            c.restoreToCount(save)
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

    /** Phím sáng theo đường: ô bo góc màu nhấn (nền + viền + quầng) trên từng phím còn sáng. */
    private fun drawGlows(c: Canvas, st: SwipeTrailState, now: Long) {
        val rad = theme.dp(SwipeTrailFx.KEY_GLOW_CORNER.toFloat())
        for (i in 0 until st.glowCount) {
            val k = st.glow(i, now, gOut)
            if (k < 0) continue
            rect.set(st.keyLeft(k), st.keyTop(k), st.keyRight(k), st.keyBottom(k))
            val a = gOut[0]
            glowHalo.alpha = (0x40 * a).toInt(); glowFill.alpha = (0x52 * a).toInt(); glowEdge.alpha = (0xE6 * a).toInt()
            c.drawRoundRect(rect, rad, rad, glowHalo)
            c.drawRoundRect(rect, rad, rad, glowFill)
            c.drawRoundRect(rect, rad, rad, glowEdge)
        }
    }

    /** Đoạn [i] (theo chiều dài, mốc [m] — Tan chảy / Sao chổi) của nét khung hiện tại vào [seg]. */
    private fun meltSegment(st: SwipeTrailState, i: Int, m: DoubleArray) {
        seg.rewind()
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
