package com.viettelex.android.ime

import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import com.viettelex.keyboard.KaleidoBloom

/**
 * Vẽ "Kính vạn hoa" trong [KeyEffectView] (iOS KaleidoFx song sinh — hình học / thời gian [KaleidoBloom] chung). Dựng lười
 * ở phím đầu (kiểu khác ⇒ không có đối tượng). Path mỗi sắc (mảnh + đá cùng sắc, dp) dựng MỘT lần; mỗi khung chỉ
 * translate / rotate / scale canvas + đổi alpha paint — không cấp phát. Pool [KaleidoBloom.POOL] bông; tâm kẹp trong khung.
 */
internal class KaleidoDrawer(private val density: Float) {
    private val start = LongArray(KaleidoBloom.POOL) { Long.MIN_VALUE / 2 }
    private val cx = FloatArray(KaleidoBloom.POOL)
    private val cy = FloatArray(KaleidoBloom.POOL)
    private var cursor = 0
    private val paths = Array(KaleidoBloom.COLORS.size) { Path() }
    private val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    private val edge = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE; color = 0xFFFFFFFF.toInt() }

    init {
        fun add(pts: DoubleArray, p: Path) {
            p.moveTo(pts[0].toFloat(), pts[1].toFloat())
            for (i in 2 until pts.size step 2) p.lineTo(pts[i].toFloat(), pts[i + 1].toFloat())
            p.close()
        }
        for (k in 0 until KaleidoBloom.FOLDS) {
            add(KaleidoBloom.shard(k), paths[KaleidoBloom.shardColor(k)])
            add(KaleidoBloom.gem(k), paths[KaleidoBloom.gemColor(k)])
        }
    }

    /** Một bông tại ([x], [y]) px trong khung [w] × [h] px (toạ độ view). */
    fun fire(x: Float, y: Float, w: Int, h: Int, now: Long) {
        val s = cursor % KaleidoBloom.POOL
        cursor++
        val c = KaleidoBloom.center(x / density.toDouble(), y / density.toDouble(), 0.0, 0.0, w / density.toDouble(), h / density.toDouble())
        cx[s] = (c[0] * density).toFloat(); cy[s] = (c[1] * density).toFloat()
        start[s] = now
    }

    /** Vẽ các bông còn sống lúc [now] (ms); true = còn chạy. */
    fun draw(canvas: Canvas, now: Long): Boolean {
        var any = false
        for (s in 0 until KaleidoBloom.POOL) {
            val t = (now - start[s]) / 1000.0
            if (t < 0 || t >= KaleidoBloom.DURATION) continue
            any = true
            val a = KaleidoBloom.alpha(t)
            if (a <= 0) continue
            val k = (KaleidoBloom.scale(t) * density).toFloat()
            val save = canvas.save()
            canvas.translate(cx[s], cy[s])
            canvas.rotate(Math.toDegrees(KaleidoBloom.angle(t)).toFloat())
            canvas.scale(k, k)
            edge.strokeWidth = 0.6f
            edge.alpha = (a * 0.55 * 255).toInt().coerceIn(0, 255)
            for ((i, p) in paths.withIndex()) {
                fill.color = KaleidoBloom.COLORS[i] or (0xFF shl 24)
                fill.alpha = (a * 0.85 * 255).toInt().coerceIn(0, 255)
                canvas.drawPath(p, fill)
                canvas.drawPath(p, edge)
            }
            canvas.restoreToCount(save)
        }
        return any
    }

    fun halt() { start.fill(Long.MIN_VALUE / 2) }

    /** Test: số bông còn sống lúc [now] + tâm bông [i]. */
    fun alive(now: Long): Int = start.count { (now - it) / 1000.0 in 0.0..<KaleidoBloom.DURATION }
    fun center(i: Int) = cx[i] to cy[i]
}
