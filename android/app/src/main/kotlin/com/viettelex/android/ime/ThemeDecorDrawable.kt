package com.viettelex.android.ime

import android.graphics.Canvas
import android.graphics.ColorFilter
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PixelFormat
import android.graphics.Rect
import android.graphics.drawable.Drawable
import com.viettelex.keyboard.ThemeDecoration

/**
 * Nền theme có hoạ tiết (Tim đen / Hoa xanh): màu nền + MỘT Path chứa mọi motif. Path dựng lại
 * chỉ khi đổi cỡ (onBoundsChange); nền view nằm trong display list của view gốc nên chỉ vẽ lại
 * khi chính nền đổi — gõ phím (KeyboardView invalidate) không đụng tới. Không bitmap.
 * Hình học dùng chung [ThemeDecoration] (= iOS KeyboardDecoration).
 */
class ThemeDecorDrawable(private val bg: Int, private val decoration: ThemeDecoration?, private val density: Float,
                         private val aurora: Boolean = false, dark: Boolean = false) : Drawable() {
    /** Motif CẢNH ("pitch"… — [com.viettelex.keyboard.ThemeScene]): vẽ trọn nền, path dựng lại chỉ khi đổi cỡ. */
    private val scene: ThemeScenePainter? = decoration?.takeIf { com.viettelex.keyboard.ThemeScene.isScene(it.motif) }
        ?.let { ThemeScenePainter(it.motif, it.color, dark) }
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = decoration?.color ?: 0; style = Paint.Style.FILL }
    /** Theme AI ("borderFx":"aurora"): dải cực quang tĩnh mép trên — [AURORA_STEPS] dải ngang gradient, đậm dần lên trên
     *  ([com.viettelex.keyboard.AuroraFx.bandOpacity]); shader dựng lại chỉ khi đổi bề ngang. */
    private val auroraPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    private var auroraW = -1
    private val bgPaint = Paint().apply { color = bg; style = Paint.Style.FILL }
    private val path = Path()
    /** Khe giữa các hàng phím, dp theo toạ độ view gốc (ImeRootView đặt sau mỗi lần dựng phím). */
    private var gaps: List<ThemeDecoration.Gap> = emptyList()

    /** Đổi khe ⇒ dựng lại path (không đổi ⇒ không làm gì — không chạy mỗi lần gõ). */
    fun setRowGaps(g: List<ThemeDecoration.Gap>) {
        if (g == gaps) return
        gaps = g
        rebuild(); invalidateSelf()
    }

    override fun onBoundsChange(bounds: Rect) {
        super.onBoundsChange(bounds)
        rebuild()
    }

    private fun rebuild() {
        if (aurora && bounds.width() != auroraW) {
            auroraW = bounds.width()
            val fx = com.viettelex.keyboard.AuroraFx
            auroraPaint.shader = android.graphics.LinearGradient(bounds.left.toFloat(), 0f, bounds.right.toFloat(), 0f,
                IntArray(fx.BAND_COLORS.size) { fx.BAND_COLORS[it] or (0xFF shl 24) },
                FloatArray(fx.BAND_STOPS.size) { fx.BAND_STOPS[it].toFloat() }, android.graphics.Shader.TileMode.CLAMP)
        }
        val decoration = decoration ?: return
        if (scene != null) { path.rewind(); return }
        val w = bounds.width() / density.toDouble()
        decorPath(path, decoration.motif, ThemeDecoration.placements(w, gaps, decoration.density),
            density, bounds.left.toFloat(), 0f, decoration.alt, width = w)
    }

    override fun draw(canvas: Canvas) {
        canvas.drawRect(bounds, bgPaint)   // theo bounds: khung thả nổi vẽ tay trong một vùng
        if (aurora) {
            val band = (com.viettelex.keyboard.AuroraFx.BAND_HEIGHT * density).toFloat()
            val step = band / AURORA_STEPS
            for (i in 0 until AURORA_STEPS) {
                val y = (i + 0.5) * step / density
                auroraPaint.alpha = (255 * com.viettelex.keyboard.AuroraFx.bandOpacity(y)).toInt().coerceIn(0, 255)
                val t = bounds.top + i * step
                canvas.drawRect(bounds.left.toFloat(), t, bounds.right.toFloat(), t + step, auroraPaint)
            }
        }
        scene?.draw(canvas, bounds.left.toFloat(), bounds.top.toFloat(), bounds.width().toFloat(), bounds.height().toFloat(), density)
        if (decoration != null && scene == null) canvas.drawPath(path, paint)
    }

    override fun setAlpha(alpha: Int) {}
    override fun setColorFilter(colorFilter: ColorFilter?) {}
    @Deprecated("Deprecated in Java")
    override fun getOpacity(): Int = PixelFormat.TRANSLUCENT

    private companion object { const val AURORA_STEPS = 14 }
}

/**
 * Dựng path hoạ tiết vào [path] từ [placements] (dp), [unitPx] px mỗi dp, gốc (left, top). Nền IME + xem trước.
 * [width] (dp) = bề ngang vùng vẽ — dây đàn ("strings") kéo hết khe; null ⇒ suy từ motif (như iOS).
 */
fun decorPath(path: Path, motif: String, placements: List<ThemeDecoration.Placement>, unitPx: Float,
              left: Float = 0f, top: Float = 0f, alt: String? = null, width: Double? = null) {
    path.rewind()
    if (com.viettelex.keyboard.ThemeScene.isScene(motif)) return   // cảnh: [ThemeScenePainter] vẽ trọn nền
    val d = unitPx.toDouble()
    if (motif == ThemeDecoration.STRINGS || alt == ThemeDecoration.STRINGS) {
        // Ghi-ta: mỗi khe một dây ngang (cùng chiều quay với motif — nonzero hợp với chấm khảm đè lên).
        for (s in ThemeDecoration.strings(placements, width)) {
            val t = (top + (s.y - s.h / 2) * d).toFloat(); val b = (top + (s.y + s.h / 2) * d).toFloat()
            val x0 = (left + s.x0 * d).toFloat(); val x1 = (left + s.x1 * d).toFloat()
            path.moveTo(x1, t); path.lineTo(x1, b); path.lineTo(x0, b); path.lineTo(x0, t); path.close()
        }
    }
    // Mai / đào / bông tuyết / sao / nốt nhạc / đèn lồng…: dữ liệu hình chung iOS — tính MỘT lần mỗi lần dựng path.
    // [alt]: motif thứ hai xen kẽ (vị trí lẻ) — Trung Thu đèn lồng + trăng, Halloween bí ngô + dơi.
    val motifs = arrayOf(motif, alt ?: motif)
    val shapes = arrayOf(ThemeDecoration.shape(motifs[0]), ThemeDecoration.shape(motifs[1]))
    for ((k, p) in placements.withIndex()) {
        val m = motifs[k % 2]
        val shape = shapes[k % 2]
        val s = p.size * d
        val ox = left + p.x * d; val oy = top + p.y * d
        fun x(u: Double) = (ox + u * s).toFloat()
        fun y(u: Double) = (oy + u * s).toFloat()
        when {
            m == ThemeDecoration.HEARTS -> {
                path.moveTo(x(ThemeDecoration.HEART_START[0]), y(ThemeDecoration.HEART_START[1]))
                for (c in ThemeDecoration.HEART_CUBICS) path.cubicTo(x(c[0]), y(c[1]), x(c[2]), y(c[3]), x(c[4]), y(c[5]))
                path.close()
            }
            m == ThemeDecoration.STRINGS -> {}   // dây vẽ một lần mỗi khe ở trên
            shape.isNotEmpty() -> for (sub in shape) {
                path.moveTo(x(sub.sx), y(sub.sy))
                for (g in sub.segs) {
                    if (g.size == 2) path.lineTo(x(g[0]), y(g[1]))
                    else path.cubicTo(x(g[0]), y(g[1]), x(g[2]), y(g[3]), x(g[4]), y(g[5]))
                }
                path.close()
            }
            else -> for (c in ThemeDecoration.FLOWER_CIRCLES) {
                path.addCircle(x(c[0]), y(c[1]), (c[2] * s).toFloat(), Path.Direction.CW)
            }
        }
    }
}

/**
 * Cảnh nền (motif cảnh — [com.viettelex.keyboard.ThemeScene]): gradient (nếu có) + hình vector, toạ độ dp × [unit] px.
 * Path / shader dựng lại CHỈ khi khung đổi — vẽ trong display list của nền, không mỗi phím. iOS ThemeSceneLayer y hệt.
 */
class ThemeScenePainter(private val motif: String, private val color: Int, private val dark: Boolean) {
    private val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    private val linePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE; strokeCap = Paint.Cap.ROUND; strokeJoin = Paint.Join.ROUND; this.color = this@ThemeScenePainter.color
    }
    private val gradPaint = Paint().apply { style = Paint.Style.FILL }
    private val p1 = Path(); private val p2 = Path(); private val p3 = Path()
    private var bl = Float.NaN; private var bt = Float.NaN; private var bw = -1f; private var bh = -1f; private var bu = -1f
    private var hasGradient = false

    /** Test: số lớp vẽ (gradient + path) của cảnh hiện tại. */
    internal var layerCount = 0
        private set

    fun draw(canvas: Canvas, left: Float, top: Float, w: Float, h: Float, unit: Float) {
        if (w <= 0f || h <= 0f) return
        if (left != bl || top != bt || w != bw || h != bh || unit != bu) rebuild(left, top, w, h, unit)
        if (hasGradient) canvas.drawRect(left, top, left + w, top + h, gradPaint)
        when (motif) {
            ThemeDecoration.PITCH -> {
                fillPaint.color = 0xFFFFFFFF.toInt(); fillPaint.alpha = (255 * com.viettelex.keyboard.PitchScene.STRIPE_ALPHA).toInt()
                canvas.drawPath(p1, fillPaint)
                canvas.drawPath(p2, linePaint)
                fillPaint.color = color
                canvas.drawPath(p3, fillPaint)
            }
            ThemeDecoration.AQUARIUM -> {
                val a = com.viettelex.keyboard.AquariumScene
                fillPaint.color = color; canvas.drawPath(p1, fillPaint)                       // vệt nắng (màu deco)
                fillPaint.color = a.SAND_COLOR or (0xFF shl 24); fillPaint.alpha = (255 * a.SAND_ALPHA).toInt()
                canvas.drawPath(p2, fillPaint)                                                // cát
                linePaint.color = a.WEED_COLOR or (0xFF shl 24); linePaint.alpha = (255 * a.WEED_ALPHA).toInt()
                canvas.drawPath(p3, linePaint)                                                // rong
            }
            ThemeDecoration.CAFE -> { fillPaint.color = color; canvas.drawPath(p1, fillPaint) }   // giọt nước đọng
        }
    }

    private fun rebuild(left: Float, top: Float, w: Float, h: Float, unit: Float) {
        bl = left; bt = top; bw = w; bh = h; bu = unit
        p1.rewind(); p2.rewind(); p3.rewind()
        val stops = com.viettelex.keyboard.ThemeScene.gradient(motif, dark)
        hasGradient = stops.size >= 2
        if (hasGradient) gradPaint.shader = android.graphics.LinearGradient(0f, top, 0f, top + h,
            IntArray(stops.size) { stops[it] or (0xFF shl 24) }, null, android.graphics.Shader.TileMode.CLAMP)
        val wd = (w / unit).toDouble(); val hd = (h / unit).toDouble()
        fun x(v: Double) = left + (v * unit).toFloat()
        fun y(v: Double) = top + (v * unit).toFloat()
        var n = if (hasGradient) 1 else 0
        when (motif) {
            ThemeDecoration.PITCH -> {
                val ps = com.viettelex.keyboard.PitchScene
                for (s in ps.stripes(wd, hd)) p1.addRect(x(s[0]), top, x(s[0] + s[1]), top + h, Path.Direction.CW)
                for (pr in ps.lines(wd, hd)) when (pr) {
                    is com.viettelex.keyboard.PitchScene.Prim.Rect -> p2.addRect(x(pr.x), y(pr.y), x(pr.x + pr.w), y(pr.y + pr.h), Path.Direction.CW)
                    is com.viettelex.keyboard.PitchScene.Prim.Circle -> p2.addCircle(x(pr.cx), y(pr.cy), (pr.r * unit).toFloat(), Path.Direction.CW)
                    is com.viettelex.keyboard.PitchScene.Prim.Line -> { p2.moveTo(x(pr.x0), y(pr.y0)); p2.lineTo(x(pr.x1), y(pr.y1)) }
                }
                p3.addCircle(x(wd / 2), y(hd / 2), (ps.SPOT * unit).toFloat(), Path.Direction.CW)
                linePaint.strokeWidth = (ps.LINE_WIDTH * unit).toFloat()
                n += 3
            }
            ThemeDecoration.AQUARIUM -> {
                val a = com.viettelex.keyboard.AquariumScene
                for (q in a.rays(wd, hd)) {
                    for ((i, pt) in q.withIndex()) { if (i == 0) p1.moveTo(x(pt.first), y(pt.second)) else p1.lineTo(x(pt.first), y(pt.second)) }
                    p1.close()
                }
                p2.moveTo(x(0.0), y(hd))
                for (pt in a.sandTop(wd, hd)) p2.lineTo(x(pt.first), y(pt.second))
                p2.lineTo(x(wd), y(hd)); p2.close()
                for (wv in a.weeds(wd, hd)) { p3.moveTo(x(wv[0]), y(wv[1])); p3.quadTo(x(wv[2]), y(wv[3]), x(wv[4]), y(wv[5])) }
                linePaint.strokeWidth = (a.WEED_WIDTH * unit).toFloat()
                n += 3
            }
            ThemeDecoration.CAFE -> {
                for (dt in com.viettelex.keyboard.CafeScene.dots(wd, hd)) p1.addCircle(x(dt[0]), y(dt[1]), (dt[2] * unit).toFloat(), Path.Direction.CW)
                n += 1
            }
        }
        layerCount = n
    }
}
