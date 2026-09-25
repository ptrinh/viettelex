package com.viettelex.android.ime

import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import kotlin.math.cos
import kotlin.math.sin

/**
 * Icon kiểu SF Symbols vẽ bằng Path trong hộp 24×24 đơn vị (dựng MỘT lần, vẽ bằng
 * canvas.scale — không alloc lúc vẽ, không inflate VectorDrawable lúc khởi động).
 */
object ImeIcons {
    const val SHIFT = 0
    const val SHIFT_FILL = 1
    const val CAPS = 2
    const val DELETE = 3
    const val DELETE_FILL = 4
    const val GLOBE = 5
    const val EMOJI = 6
    const val RETURN = 7
    const val ARROW_RIGHT = 8
    const val TRASH = 9
    const val KB_DISMISS = 10
    const val MENU = 11
    const val CHEVRON_DOWN = 12
    const val CLIPBOARD = 13
    const val CLOCK = 14
    const val FACE = 15
    const val HARE = 16
    const val FORK_KNIFE = 17
    const val SOCCER = 18
    const val CAR = 19
    const val BULB = 20
    const val HEART = 21
    const val FLAG = 22
    const val DELETE_X = 23
    private const val COUNT = 24

    /** Thứ tự icon category của plane emoji (clock → flag). */
    val CATEGORY = intArrayOf(CLOCK, FACE, HARE, FORK_KNIFE, SOCCER, CAR, BULB, HEART, FLAG)

    private val paths = arrayOfNulls<Path>(COUNT)
    /** 0 = fill; > 0 = stroke width (đơn vị hộp 24). */
    private val strokes = FloatArray(COUNT)

    private fun p(i: Int, stroke: Float, build: Path.() -> Unit) {
        paths[i] = Path().apply(build); strokes[i] = stroke
    }

    init {
        val shift: Path.() -> Unit = {
            moveTo(12f, 3f); lineTo(21f, 12.5f); lineTo(16f, 12.5f); lineTo(16f, 20f)
            lineTo(8f, 20f); lineTo(8f, 12.5f); lineTo(3f, 12.5f); close()
        }
        p(SHIFT, 1.6f, shift)
        p(SHIFT_FILL, 0f, shift)
        p(CAPS, 0f) {
            moveTo(12f, 3f); lineTo(21f, 11.5f); lineTo(16f, 11.5f); lineTo(16f, 16f)
            lineTo(8f, 16f); lineTo(8f, 11.5f); lineTo(3f, 11.5f); close()
            addRect(8f, 18f, 16f, 20.5f, Path.Direction.CW)
        }
        val delBody: Path.() -> Unit = {
            moveTo(8.5f, 5f); lineTo(20f, 5f); quadTo(22f, 5f, 22f, 7f); lineTo(22f, 17f)
            quadTo(22f, 19f, 20f, 19f); lineTo(8.5f, 19f); lineTo(2f, 12f); close()
        }
        p(DELETE, 1.6f) {
            delBody()
            moveTo(11.5f, 9f); lineTo(17.5f, 15f); moveTo(17.5f, 9f); lineTo(11.5f, 15f)
        }
        p(DELETE_FILL, 0f) { delBody() }   // X vẽ riêng bằng DELETE_X màu mặt phím
        p(DELETE_X, 1.6f) { moveTo(11.5f, 9f); lineTo(17.5f, 15f); moveTo(17.5f, 9f); lineTo(11.5f, 15f) }
        p(GLOBE, 1.4f) {
            addCircle(12f, 12f, 9f, Path.Direction.CW)
            addOval(RectF(8f, 3f, 16f, 21f), Path.Direction.CW)
            moveTo(3f, 12f); lineTo(21f, 12f)
            moveTo(4.6f, 7.6f); quadTo(12f, 9.6f, 19.4f, 7.6f)
            moveTo(4.6f, 16.4f); quadTo(12f, 14.4f, 19.4f, 16.4f)
            moveTo(12f, 3f); lineTo(12f, 21f)
        }
        p(EMOJI, 0f) {
            fillType = Path.FillType.EVEN_ODD
            addCircle(12f, 12f, 9.5f, Path.Direction.CW)
            addOval(RectF(8.2f, 7.4f, 10.2f, 11f), Path.Direction.CW)
            addOval(RectF(13.8f, 7.4f, 15.8f, 11f), Path.Direction.CW)
            moveTo(7.2f, 13.2f); quadTo(12f, 20f, 16.8f, 13.2f); quadTo(12f, 15.4f, 7.2f, 13.2f); close()
        }
        p(RETURN, 1.7f) {
            moveTo(19f, 5f); lineTo(19f, 13f); quadTo(19f, 15f, 17f, 15f); lineTo(5f, 15f)
            moveTo(9f, 11f); lineTo(5f, 15f); lineTo(9f, 19f)
        }
        p(ARROW_RIGHT, 2.2f) {
            moveTo(4f, 12f); lineTo(19.5f, 12f); moveTo(13.5f, 6f); lineTo(19.5f, 12f); lineTo(13.5f, 18f)
        }
        p(TRASH, 1.5f) {
            moveTo(4f, 6.5f); lineTo(20f, 6.5f)
            moveTo(9.5f, 6.5f); lineTo(9.5f, 4.5f); quadTo(9.5f, 3.5f, 10.5f, 3.5f); lineTo(13.5f, 3.5f)
            quadTo(14.5f, 3.5f, 14.5f, 4.5f); lineTo(14.5f, 6.5f)
            moveTo(6f, 6.5f); lineTo(7f, 19.5f); quadTo(7.1f, 21f, 8.5f, 21f); lineTo(15.5f, 21f)
            quadTo(16.9f, 21f, 17f, 19.5f); lineTo(18f, 6.5f)
            moveTo(10f, 10f); lineTo(10f, 17.5f); moveTo(14f, 10f); lineTo(14f, 17.5f)
        }
        p(KB_DISMISS, 1.4f) {
            addRoundRect(RectF(2.5f, 3.5f, 21.5f, 15f), 2f, 2f, Path.Direction.CW)
            for (i in 0..4) { val x = 5.5f + i * 3.25f; moveTo(x, 7f); lineTo(x + 0.1f, 7f) }
            for (i in 0..3) { val x = 7f + i * 3.33f; moveTo(x, 9.8f); lineTo(x + 0.1f, 9.8f) }
            moveTo(8f, 12.4f); lineTo(16f, 12.4f)
            moveTo(9f, 18.5f); lineTo(12f, 21f); lineTo(15f, 18.5f)
        }
        p(MENU, 2.0f) {
            moveTo(4f, 6.5f); lineTo(20f, 6.5f); moveTo(4f, 12f); lineTo(20f, 12f)
            moveTo(4f, 17.5f); lineTo(20f, 17.5f)
        }
        p(CHEVRON_DOWN, 2.4f) { moveTo(5f, 9f); lineTo(12f, 16f); lineTo(19f, 9f) }
        p(CLIPBOARD, 1.5f) {
            moveTo(9f, 4.5f); lineTo(7f, 4.5f); quadTo(5f, 4.5f, 5f, 6.5f); lineTo(5f, 19.5f)
            quadTo(5f, 21.5f, 7f, 21.5f); lineTo(17f, 21.5f); quadTo(19f, 21.5f, 19f, 19.5f)
            lineTo(19f, 6.5f); quadTo(19f, 4.5f, 17f, 4.5f); lineTo(15f, 4.5f)
            addRoundRect(RectF(9f, 2.8f, 15f, 6.4f), 1.2f, 1.2f, Path.Direction.CW)
            moveTo(8.5f, 11f); lineTo(15.5f, 11f); moveTo(8.5f, 14.5f); lineTo(15.5f, 14.5f)
            moveTo(8.5f, 18f); lineTo(13f, 18f)
        }
        p(CLOCK, 1.6f) {
            addCircle(12f, 12f, 9f, Path.Direction.CW)
            moveTo(12f, 6.5f); lineTo(12f, 12f); lineTo(15.8f, 14.2f)
        }
        p(FACE, 1.6f) {
            addCircle(12f, 12f, 9f, Path.Direction.CW)
            addCircle(9f, 9.8f, 0.5f, Path.Direction.CW)
            addCircle(15f, 9.8f, 0.5f, Path.Direction.CW)
            moveTo(8f, 14f); quadTo(12f, 18.2f, 16f, 14f)
        }
        p(HARE, 1.5f) {
            addCircle(12f, 15.5f, 5.5f, Path.Direction.CW)
            addOval(RectF(8.2f, 2.5f, 11f, 11f), Path.Direction.CW)
            addOval(RectF(13f, 2.5f, 15.8f, 11f), Path.Direction.CW)
        }
        p(FORK_KNIFE, 1.5f) {
            moveTo(7f, 3f); lineTo(7f, 21f)
            moveTo(4.8f, 3f); lineTo(4.8f, 8f); quadTo(4.8f, 10.5f, 7f, 10.5f); quadTo(9.2f, 10.5f, 9.2f, 8f)
            lineTo(9.2f, 3f)
            moveTo(16.5f, 21f); lineTo(16.5f, 3f); quadTo(19.5f, 5.5f, 19.5f, 10.5f); lineTo(19.5f, 13f)
            lineTo(16.5f, 13f)
        }
        p(SOCCER, 1.4f) {
            addCircle(12f, 12f, 9f, Path.Direction.CW)
            val r = 3.3f
            for (i in 0..5) {
                val a = Math.toRadians(-90.0 + 72.0 * (i % 5))
                val x = 12f + r * cos(a).toFloat(); val y = 12f + r * sin(a).toFloat()
                if (i == 0) moveTo(x, y) else lineTo(x, y)
            }
            close()
            for (i in 0..4) {
                val a = Math.toRadians(-90.0 + 72.0 * i)
                moveTo(12f + r * cos(a).toFloat(), 12f + r * sin(a).toFloat())
                lineTo(12f + 9f * cos(a).toFloat(), 12f + 9f * sin(a).toFloat())
            }
        }
        p(CAR, 0f) {
            fillType = Path.FillType.EVEN_ODD
            moveTo(3f, 17f); lineTo(3f, 12.5f); quadTo(3f, 11f, 4.5f, 10.5f); lineTo(6.5f, 6.5f)
            quadTo(7.2f, 5f, 9f, 5f); lineTo(15f, 5f); quadTo(16.8f, 5f, 17.5f, 6.5f); lineTo(19.5f, 10.5f)
            quadTo(21f, 11f, 21f, 12.5f); lineTo(21f, 17f); close()
            moveTo(8.2f, 6.9f); lineTo(15.8f, 6.9f); lineTo(17.3f, 10.2f); lineTo(6.7f, 10.2f); close()
            addRect(4.5f, 17f, 8.5f, 20f, Path.Direction.CW)
            addRect(15.5f, 17f, 19.5f, 20f, Path.Direction.CW)
        }
        p(BULB, 1.5f) {
            moveTo(9f, 16f); cubicTo(9f, 13.5f, 5.5f, 12.8f, 5.5f, 9.2f)
            cubicTo(5.5f, 5.6f, 8.4f, 3f, 12f, 3f); cubicTo(15.6f, 3f, 18.5f, 5.6f, 18.5f, 9.2f)
            cubicTo(18.5f, 12.8f, 15f, 13.5f, 15f, 16f); close()
            moveTo(9.5f, 18.5f); lineTo(14.5f, 18.5f); moveTo(10.5f, 21f); lineTo(13.5f, 21f)
        }
        p(HEART, 1.5f) {
            moveTo(12f, 20.5f); cubicTo(4f, 15f, 2.5f, 11f, 2.5f, 8.5f)
            cubicTo(2.5f, 5.5f, 4.8f, 3.5f, 7.5f, 3.5f); cubicTo(9.5f, 3.5f, 11f, 4.8f, 12f, 6.5f)
            cubicTo(13f, 4.8f, 14.5f, 3.5f, 16.5f, 3.5f); cubicTo(19.2f, 3.5f, 21.5f, 5.5f, 21.5f, 8.5f)
            cubicTo(21.5f, 11f, 20f, 15f, 12f, 20.5f); close()
        }
        p(FLAG, 1.5f) {
            moveTo(5f, 3f); lineTo(5f, 21f)
            moveTo(5f, 4f); quadTo(8.5f, 2.5f, 12f, 4f); quadTo(15.5f, 5.5f, 19f, 4f); lineTo(19f, 13f)
            quadTo(15.5f, 14.5f, 12f, 13f); quadTo(8.5f, 11.5f, 5f, 13f)
        }
    }

    /**
     * Vẽ icon `id` trong hộp vuông cạnh `size` px tâm (cx, cy). `paint` chỉ cần màu
     * — style/strokeWidth được set ở đây (paint dành riêng cho icon).
     */
    fun draw(c: Canvas, id: Int, cx: Float, cy: Float, size: Float, paint: Paint, rotationDeg: Float = 0f) {
        val path = paths[id] ?: return
        val s = size / 24f
        c.save()
        c.translate(cx, cy)
        if (rotationDeg != 0f) c.rotate(rotationDeg)
        c.scale(s, s)
        c.translate(-12f, -12f)
        val sw = strokes[id]
        if (sw > 0f) {
            paint.style = Paint.Style.STROKE
            paint.strokeWidth = sw
            paint.strokeCap = Paint.Cap.ROUND
            paint.strokeJoin = Paint.Join.ROUND
        } else {
            paint.style = Paint.Style.FILL
        }
        c.drawPath(path, paint)
        c.restore()
    }
}
