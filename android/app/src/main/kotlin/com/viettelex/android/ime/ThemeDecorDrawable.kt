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
                         private val aurora: Boolean = false,
                         /** Màu đáy ("bg2" — gradient dọc bg → bgBottom, Lạc trôi); null = nền phẳng. */
                         private val bgBottom: Int? = null,
                         /** Ký hiệu mờ góc trên phải (Cung hoàng đạo — palette.cornerGlyph); null = không. iOS cornerGlyphLayer. */
                         private val glyph: String? = null, glyphColor: Int = 0,
                         /** Dải mép trên theo sọc cờ (theme Tự hào) — null = [com.viettelex.keyboard.AuroraFx.BAND_COLORS]. */
                         private val auroraColors: List<Int>? = null) : Drawable() {
    private val glyphPaint: Paint? = glyph?.let {
        Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = glyphColor or (0xFF shl 24)
            alpha = (255 * CORNER_GLYPH_ALPHA).toInt()
            textSize = (CORNER_GLYPH_SIZE * density).toFloat()
            textAlign = Paint.Align.RIGHT
        }
    }
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = decoration?.color ?: 0; style = Paint.Style.FILL }
    /** Theme AI ("borderFx":"aurora"): dải cực quang tĩnh mép trên — [AURORA_STEPS] dải ngang gradient, đậm dần lên trên
     *  ([com.viettelex.keyboard.AuroraFx.bandOpacity]); shader dựng lại chỉ khi đổi bề ngang. */
    private val auroraPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    private var auroraW = -1
    private val bgPaint = Paint().apply { color = bg; style = Paint.Style.FILL }
    /** Motif "bokeh" (Mưa đêm): dải phủ nền trên → dưới ([ThemeDecoration.BOKEH_SHADE]); shader dựng lại khi đổi chiều cao. */
    private val shade = decoration != null && ThemeDecoration.hasShade(decoration.motif, decoration.alt)
    private val shadePaint = Paint().apply { style = Paint.Style.FILL }
    private var shadeH = -1
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
        if (bgBottom != null) bgPaint.shader = android.graphics.LinearGradient(0f, bounds.top.toFloat(), 0f, bounds.bottom.toFloat(),
            bg, bgBottom, android.graphics.Shader.TileMode.CLAMP)
        if (aurora && bounds.width() != auroraW) {
            auroraW = bounds.width()
            val fx = com.viettelex.keyboard.AuroraFx
            val (cols, stops) = auroraColors?.let { fx.stops(it) } ?: (fx.BAND_COLORS to fx.BAND_STOPS)
            auroraPaint.shader = android.graphics.LinearGradient(bounds.left.toFloat(), 0f, bounds.right.toFloat(), 0f,
                IntArray(cols.size) { cols[it] or (0xFF shl 24) },
                FloatArray(stops.size) { stops[it].toFloat() }, android.graphics.Shader.TileMode.CLAMP)
        }
        if (shade && bounds.height() != shadeH) {
            shadeH = bounds.height()
            shadePaint.shader = android.graphics.LinearGradient(0f, bounds.top.toFloat(), 0f, bounds.bottom.toFloat(),
                ThemeDecoration.BOKEH_SHADE, FloatArray(ThemeDecoration.BOKEH_SHADE_STOPS.size) { ThemeDecoration.BOKEH_SHADE_STOPS[it].toFloat() },
                android.graphics.Shader.TileMode.CLAMP)
        }
        val decoration = decoration ?: return
        val w = bounds.width() / density.toDouble()
        decorPath(path, decoration.motif, ThemeDecoration.placements(w, gaps, decoration.density),
            density, bounds.left.toFloat(), 0f, decoration.alt, width = w)
    }

    override fun draw(canvas: Canvas) {
        canvas.drawRect(bounds, bgPaint)   // theo bounds: khung thả nổi vẽ tay trong một vùng
        if (shade) canvas.drawRect(bounds, shadePaint)
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
        if (decoration != null) canvas.drawPath(path, paint)
        if (glyph != null && glyphPaint != null) {
            // Góc trên phải (dải gợi ý) — một lần mỗi lần vẽ nền, không mỗi phím.
            canvas.drawText(glyph, bounds.right - 8 * density, bounds.top + ((CORNER_GLYPH_SIZE + 4) * density).toFloat(), glyphPaint)
        }
    }

    override fun setAlpha(alpha: Int) {}
    override fun setColorFilter(colorFilter: ColorFilter?) {}
    @Deprecated("Deprecated in Java")
    override fun getOpacity(): Int = PixelFormat.TRANSLUCENT

    companion object {
        private const val AURORA_STEPS = 14
        /** Ký hiệu góc: cỡ (dp) + độ đậm so với chữ theme — iOS KeyboardView.cornerGlyphSize / cornerGlyphAlpha. */
        const val CORNER_GLYPH_SIZE = 26.0
        const val CORNER_GLYPH_ALPHA = 0.22
    }
}

/**
 * Dựng path hoạ tiết vào [path] từ [placements] (dp), [unitPx] px mỗi dp, gốc (left, top). Nền IME + xem trước.
 * [width] (dp) = bề ngang vùng vẽ — dây đàn ("strings") kéo hết khe; null ⇒ suy từ motif (như iOS).
 */
fun decorPath(path: Path, motif: String, placements: List<ThemeDecoration.Placement>, unitPx: Float,
              left: Float = 0f, top: Float = 0f, alt: String? = null, width: Double? = null) {
    path.rewind()
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
