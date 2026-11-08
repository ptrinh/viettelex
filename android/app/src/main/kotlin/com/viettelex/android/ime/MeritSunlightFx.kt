package com.viettelex.android.ime

import android.graphics.Canvas
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import com.viettelex.keyboard.CandleFlicker
import com.viettelex.keyboard.ComboMeter
import com.viettelex.keyboard.MeritCounter
import com.viettelex.keyboard.MeritFx
import com.viettelex.keyboard.SunlightFx

/**
 * Vẽ "Công đức" (theme Gõ mõ) trong [KeyEffectView] — song sinh iOS MeritLayers. Pool [MeritFx.CAP] nhãn (mảng cấp sẵn),
 * chữ "+1 công đức" cố định ⇒ mỗi khung chỉ drawText với vị trí / alpha tính từ hàm thuần, 0 cấp phát. Nhãn đếm trong ngày
 * vẽ ở góc trên-trái phím cách (vẽ lại mỗi khung của overlay — display list giữ nguyên khi nghỉ). Kiểu khác ⇒ view không
 * giữ đối tượng này (0 chi phí).
 */
internal class MeritDrawer(private val density: Float) {
    private val start = LongArray(MeritFx.CAP) { Long.MIN_VALUE / 2 }
    private val px = FloatArray(MeritFx.CAP)
    private val py = FloatArray(MeritFx.CAP)
    private var cursor = 0
    var seq = 0; private set
    var counter = MeritCounter(); internal set
    /** Lệch múi giờ (giây) đọc MỘT lần lúc gắn kho. */
    var utcOffset = java.util.TimeZone.getDefault().getOffset(System.currentTimeMillis()) / 1000
    var save: ((Int, Int) -> Unit)? = null
    private val text = MeritFx.floatText
    private var counterText: String? = null
    private var counterShown = -1
    private val counterRect = RectF()
    private var counterVisible = false

    private val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL; color = MeritFx.COLOR or (0xFF shl 24); typeface = Typeface.DEFAULT_BOLD
        textAlign = Paint.Align.CENTER; textSize = (MeritFx.FONT_SIZE * density).toFloat()
    }
    private val edge = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE; color = MeritFx.EDGE or (0xFF shl 24); typeface = Typeface.DEFAULT_BOLD
        textAlign = Paint.Align.CENTER; textSize = (MeritFx.FONT_SIZE * density).toFloat(); strokeWidth = 1.6f * density
        strokeJoin = Paint.Join.ROUND
    }
    private val cFill = Paint(fill).apply {
        typeface = Typeface.DEFAULT; textAlign = Paint.Align.LEFT; textSize = (MeritFx.COUNTER_FONT * density).toFloat()
        alpha = (255 * MeritFx.COUNTER_ALPHA).toInt()
    }
    private val cEdge = Paint(edge).apply {
        typeface = Typeface.DEFAULT; textAlign = Paint.Align.LEFT; textSize = (MeritFx.COUNTER_FONT * density).toFloat()
        strokeWidth = 1.2f * density; alpha = (255 * MeritFx.COUNTER_ALPHA).toInt()
    }

    /** Phím tâm ([x], [y]) cỡ [w]×[h] (px) trong view [vw]×[vh]; [epoch] giây, [nowMs] đồng hồ máy. */
    fun fire(x: Float, y: Float, w: Float, h: Float, vw: Int, vh: Int, nowMs: Long, epoch: Double, anchor: RectF?) {
        val s = cursor; cursor = (s + 1) % MeritFx.CAP
        val d = density.toDouble()
        val top = if (h > 0f) y - h / 2 else y
        val o = MeritFx.origin(x / d, top / d, 0.0, 0.0, vw / d, vh / d)
        px[s] = ((o[0] + MeritFx.drift(seq)) * d).toFloat(); py[s] = (o[1] * d).toFloat(); start[s] = nowMs
        seq++
        val day = MeritCounter.dayIndex(epoch, utcOffset)
        if (counter.press(day, nowMs / 1000.0)) save?.invoke(counter.day, counter.count)
        layoutCounter(counter.today(day), anchor)
    }

    /** Nhãn đếm theo khung phím cách [anchor] (px, toạ độ view); null ⇒ ẩn. */
    fun layoutCounter(n: Int, anchor: RectF?) {
        if (anchor == null || anchor.width() <= 40 * density || anchor.height() <= 16 * density) { counterVisible = false; return }
        counterVisible = true
        counterRect.set(anchor.left + 6 * density, anchor.top + 2 * density, anchor.right, anchor.top + (MeritFx.COUNTER_FONT + 4).toFloat() * density)
        if (n != counterShown || counterText == null) { counterShown = n; counterText = MeritFx.counterText(n) }
    }

    /** Ghi nốt (ẩn bàn phím). */
    fun persist() { if (counter.takeDirty()) save?.invoke(counter.day, counter.count) }

    /** Số nhãn còn bay lúc [now]. */
    fun alive(now: Long): Int = start.count { (now - it) / 1000.0 in 0.0..<MeritFx.DURATION }
    internal fun labelX(i: Int) = px[i]
    internal fun labelY(i: Int) = py[i]
    internal val counterLabel: String? get() = if (counterVisible) counterText else null
    internal val counterFrame: RectF get() = counterRect

    fun draw(c: Canvas, now: Long): Boolean {
        var any = false
        val d = density
        for (s in 0 until MeritFx.CAP) {
            val t = (now - start[s]) / 1000.0
            val a = MeritFx.alpha(t)
            if (a <= 0.0) continue
            any = true
            val yy = py[s] - (MeritFx.lift(t) * d).toFloat() + fill.textSize * 0.35f
            edge.alpha = (255 * a).toInt(); fill.alpha = (255 * a).toInt()
            c.drawText(text, px[s], yy, edge)
            c.drawText(text, px[s], yy, fill)
        }
        val ct = counterText
        if (counterVisible && ct != null) {
            val by = counterRect.top + cFill.textSize
            c.drawText(ct, counterRect.left, by, cEdge)
            c.drawText(ct, counterRect.left, by, cFill)
        }
        return any
    }

    fun clear() { start.fill(Long.MIN_VALUE / 2) }
}

/**
 * Vẽ "Nắng qua kính" (theme Kính màu) — song sinh iOS SunlightLayers. Pool [SunlightFx.POOL] chùm (5 ô + 3 tia, mảng
 * cấp sẵn, MỘT Path dùng lại), ánh nến mép dưới = MỘT LinearGradient dựng khi đổi cỡ. 0 cấp phát mỗi khung.
 */
internal class SunlightDrawer(private val density: Float) {
    private val start = LongArray(SunlightFx.POOL) { Long.MIN_VALUE / 2 }
    /** [slot][5 ô × (l, t, r, b, level)]. */
    private val panes = Array(SunlightFx.POOL) { FloatArray(5 * 5) }
    private val beams = Array(SunlightFx.POOL) { FloatArray(SunlightFx.BEAMS * 8) }
    private val tmp = DoubleArray(8)
    private var cursor = 0
    private val combo = ComboMeter()
    val candle = CandleFlicker()
    private val path = Path()
    private val rect = RectF()
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL; color = SunlightFx.LIGHT or (0xFF shl 24) }
    private val candlePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    private var candleFor = -1f

    fun fire(x: Float, y: Float, w: Float, h: Float, nowMs: Long) {
        val s = cursor; cursor = (s + 1) % SunlightFx.POOL
        val ps = SunlightFx.panes(x.toDouble(), y.toDouble(), w.toDouble(), h.toDouble())
        val p = panes[s]
        for ((i, q) in ps.withIndex()) {
            p[5 * i] = (q.x - q.w / 2).toFloat(); p[5 * i + 1] = (q.y - q.h / 2).toFloat()
            p[5 * i + 2] = (q.x + q.w / 2).toFloat(); p[5 * i + 3] = (q.y + q.h / 2).toFloat(); p[5 * i + 4] = q.level.toFloat()
        }
        val b = beams[s]
        for (i in 0 until SunlightFx.BEAMS) {
            SunlightFx.beam(i, x.toDouble(), (y - h / 2).toDouble(), w.toDouble(), 0.0, tmp)
            for (k in 0 until 8) b[8 * i + k] = tmp[k].toFloat()
        }
        start[s] = nowMs
        val level = combo.press(nowMs)
        candle.press(nowMs / 1000.0, level)
    }

    fun alive(now: Long): Int = start.count { (now - it) / 1000.0 in 0.0..<SunlightFx.DURATION }
    internal fun beam(slot: Int): FloatArray = beams[slot]

    fun draw(c: Canvas, now: Long, vw: Int, vh: Int): Boolean {
        var any = false
        for (s in 0 until SunlightFx.POOL) {
            val env = SunlightFx.envelope((now - start[s]) / 1000.0)
            if (env <= 0.0) continue
            any = true
            val b = beams[s]
            for (i in 0 until SunlightFx.BEAMS) {
                path.reset()
                path.moveTo(b[8 * i], b[8 * i + 1]); path.lineTo(b[8 * i + 2], b[8 * i + 3])
                path.lineTo(b[8 * i + 4], b[8 * i + 5]); path.lineTo(b[8 * i + 6], b[8 * i + 7]); path.close()
                paint.alpha = (255 * env * SunlightFx.BEAM_PEAK * SunlightFx.BEAM_WEIGHTS[i]).toInt()
                c.drawPath(path, paint)
            }
            val p = panes[s]
            for (i in 4 downTo 0) {   // ô quanh trước, ô vừa bấm sau (trên cùng)
                rect.set(p[5 * i], p[5 * i + 1], p[5 * i + 2], p[5 * i + 3])
                val r = (SunlightFx.CORNER_FACTOR * minOf(rect.width(), rect.height())).toFloat()
                paint.alpha = (255 * env * p[5 * i + 4]).toInt()
                c.drawRoundRect(rect, r, r, paint)
            }
        }
        val t = now / 1000.0
        val a = candle.value(t)
        if (a > 0.0 && vh > 0) {
            val band = (SunlightFx.CANDLE_BAND * density).toFloat()
            if (candleFor != band) {
                candleFor = band
                val col = SunlightFx.CANDLE_COLOR
                candlePaint.shader = LinearGradient(0f, 0f, 0f, band, col, (0xE6 shl 24) or col, Shader.TileMode.CLAMP)
            }
            candlePaint.alpha = (255 * a).toInt()
            c.save()
            c.translate(0f, vh - band)
            c.drawRect(0f, 0f, vw.toFloat(), band, candlePaint)
            c.restore()
        }
        if (candle.last != Double.NEGATIVE_INFINITY && t - candle.last < SunlightFx.CANDLE_HOLD + SunlightFx.CANDLE_FADE) any = true
        return any
    }

    fun clear() { start.fill(Long.MIN_VALUE / 2); candle.reset(); combo.reset() }
}
