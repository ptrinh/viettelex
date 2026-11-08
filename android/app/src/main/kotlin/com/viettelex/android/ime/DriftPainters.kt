package com.viettelex.android.ime

import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import com.viettelex.keyboard.FloatClock
import com.viettelex.keyboard.TunnelFx

/**
 * "Đường hầm" (theme Lạc trôi) — pool vòng vẽ trên [KeyEffectView] (song sinh iOS TunnelRings). Mảng cấp sẵn, MỘT RectF
 * + hai Paint dùng lại ⇒ không cấp phát mỗi khung hình; hết vòng thì thôi hẹn khung hình (nghỉ = 0). Vòng = viền bàn phím
 * (thụt [TunnelFx.INSET]) thu nhỏ quanh điểm tụ V bằng canvas.scale — tâm tự về V + (C − V)·s như phối cảnh; nét mảnh
 * thu theo (xa thì mảnh). Hình học + nhịp: [TunnelFx] (keyboard/Drift.kt, số chung iOS).
 */
class TunnelPainter(private val density: Float) {
    private val start = LongArray(TunnelFx.POOL) { Long.MIN_VALUE / 2 }
    private val durMs = LongArray(TunnelFx.POOL)
    private val vx = FloatArray(TunnelFx.POOL)
    private val vy = FloatArray(TunnelFx.POOL)
    private val col = IntArray(TunnelFx.POOL)
    private var cursor = 0
    private var seq = 0
    private val v = DoubleArray(2)
    private val rect = RectF()
    private val core = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE }
    private val glow = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE }

    /** Bắn: tâm phím ([x], [y]) cỡ [w]×[h] px (0 ⇒ tâm bàn phím), khung vẽ [vw]×[vh] px, mức combo [level]. */
    fun fire(x: Float, y: Float, w: Float, h: Float, vw: Int, vh: Int, level: Int, now: Long) {
        if (vw <= 1 || vh <= 1) return
        TunnelFx.vanish((x - w / 2).toDouble(), (y - h / 2).toDouble(), w.toDouble(), h.toDouble(), 0.0, 0.0,
            vw.toDouble(), vh.toDouble(), v)
        val lv = TunnelFx.level(level)
        val d = (TunnelFx.duration(lv) * 1000).toLong()
        for (i in 0 until TunnelFx.rings(lv)) {
            val s = cursor; cursor = (cursor + 1) % TunnelFx.POOL
            seq++
            start[s] = now + (TunnelFx.delay(i) * 1000).toLong()
            durMs[s] = d
            vx[s] = v[0].toFloat(); vy[s] = v[1].toFloat()
            col[s] = TunnelFx.COLORS[seq % TunnelFx.COLORS.size]
        }
    }

    /** Số vòng đang hiện lúc [now] (test). */
    fun alive(now: Long): Int = (0 until TunnelFx.POOL).count { now - start[it] in 0 until durMs[it] }
    /** Vòng còn trong pool (đã từng bắn) — trần [TunnelFx.POOL]. */
    val capacity: Int get() = TunnelFx.POOL

    /** Vẽ lúc [now] trong khung [vw]×[vh]; true = còn vòng (đang chạy hoặc chờ trễ). */
    fun draw(canvas: Canvas, now: Long, vw: Int, vh: Int): Boolean {
        var any = false
        val inset = (TunnelFx.INSET * density).toFloat()
        val cx = vw / 2f; val cy = vh / 2f
        val hw = vw / 2f - inset; val hh = vh / 2f - inset
        val r = (TunnelFx.corner((2 * hw / density).toDouble(), (2 * hh / density).toDouble()) * density).toFloat()
        for (s in 0 until TunnelFx.POOL) {
            val dt = now - start[s]
            if (dt >= durMs[s]) continue
            any = true
            if (dt < 0) continue                       // vòng sau còn chờ trễ
            val u = dt.toDouble() / durMs[s]
            val a = TunnelFx.alpha(u)
            if (a <= 0.0) continue
            val k = TunnelFx.scale(u).toFloat()
            if (k <= 0.001f) continue
            canvas.save()
            canvas.translate(vx[s], vy[s])
            canvas.scale(k, k)
            rect.set(cx - vx[s] - hw, cy - vy[s] - hh, cx - vx[s] + hw, cy - vy[s] + hh)
            val c = col[s] or (0xFF shl 24)
            glow.color = c; glow.alpha = (255 * a * TunnelFx.GLOW_ALPHA).toInt().coerceIn(0, 255)
            glow.strokeWidth = (TunnelFx.GLOW_WIDTH * density).toFloat()
            canvas.drawRoundRect(rect, r, r, glow)
            core.color = c; core.alpha = (255 * a).toInt().coerceIn(0, 255)
            core.strokeWidth = (TunnelFx.LINE_WIDTH * density).toFloat()
            canvas.drawRoundRect(rect, r, r, core)
            canvas.restore()
        }
        return any
    }

    fun halt() { start.fill(Long.MIN_VALUE / 2) }
}

/**
 * "Lơ lửng" trên Android: KeyboardView vẽ mỗi phím trong một canvas.save/translate/rotate theo [FloatClock] — CHỈ HÌNH,
 * vùng nhận chạm (khung phím gốc trong `keys`) không đổi. Đồng hồ theo giây ([now]); hết trôi + về chỗ ⇒ thôi hẹn khung
 * hình (nghỉ = 0). Giữ mảng tạm cấp sẵn.
 */
class KeyFloatDriver {
    val clock = FloatClock()
    private val o = DoubleArray(3)
    /** Đồng hồ (giây) — test thay. */
    var now: () -> Double = { android.os.SystemClock.uptimeMillis() / 1000.0 }

    /** Một phím vừa bấm. */
    fun poke() { clock.poke(now()) }

    /** Đầu một lượt vẽ: cập nhật trạng thái; true = đang trôi / về chỗ (vẽ có dời hình + hẹn khung kế). */
    fun frame(t: Double): Boolean { clock.update(t); return clock.active }

    /** Dời canvas cho phím [i] tâm ([cx], [cy]) px, [d] px mỗi dp. Gọi giữa save/restore. */
    fun apply(c: Canvas, i: Int, t: Double, cx: Float, cy: Float, d: Float) {
        clock.offset(i, t, o)
        c.translate((o[0] * d).toFloat(), (o[1] * d).toFloat())
        if (o[2] != 0.0) c.rotate(Math.toDegrees(o[2]).toFloat(), cx, cy)
    }

    fun halt() = clock.stop()
}
