package com.viettelex.android.ime

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RadialGradient
import android.graphics.Shader
import android.os.SystemClock
import android.view.MotionEvent
import android.view.View
import com.viettelex.keyboard.AIEye
import com.viettelex.keyboard.AIEyeClock
import com.viettelex.keyboard.ComboMeter

/**
 * "Mắt AI" (nhân vật [com.viettelex.keyboard.BuddyCharacter.AI], Plus) — song sinh iOS AIEyeView. Quả cầu (gradient tròn)
 * + vành + mống mắt + đồng tử + mí, vẽ vector bằng Canvas; Shader dựng lại chỉ khi đổi cỡ. Không nhận chạm (ô nhân vật
 * của StripView bắt "cù" như Bạn đồng hành).
 *
 * Hiệu năng: chỉ tồn tại khi chọn Mắt AI. Mỗi phím: ghi đích nhìn + mức combo rồi hẹn khung hình; chuyển động (đồng tử
 * ~120 ms, chớp 160 ms, mí 350 ms, thở đúng [AIEye.BREATH_CYCLES] nhịp) tính theo giờ trong onDraw — hết chuyển động thì
 * THÔI hẹn khung hình. Mốc nghỉ / thở / lim dim = MỘT postDelayed (không lặp); lim dim ⇒ 0 khung hình, 0 hẹn giờ.
 */
@SuppressLint("ViewConstructor")
class AIEyeView(context: Context, private val density: Float, lowPower: Boolean) : View(context) {
    var lowPower: Boolean = lowPower
        set(v) { val was = field; field = v; if (v && !was) halt() }
    /** Ô nhân vật đang hiện (strip mở) — ẩn ⇒ dừng như halt. */
    var shownInSlot: Boolean = true
        set(v) { if (field != v) { field = v; visibility = if (v) VISIBLE else INVISIBLE; if (!v) halt() } }

    private val clock = AIEyeClock()
    private val combo = ComboMeter()
    private val haloPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val orbPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val irisPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val pupilPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = AIEye.PUPIL_COLOR or OPAQUE }
    private val shinePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0xE6FFFFFF.toInt() }
    private val lidPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = (0xF7 shl 24) or AIEye.LID_COLOR }
    private val lidLinePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE; color = (0xBF shl 24) or AIEye.RING_COLOR
    }
    private val ringPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE; color = (0xD9 shl 24) or AIEye.RING_COLOR
    }
    private val orbClip = Path()
    private val off = DoubleArray(2)
    private var side = 0f
    private var radius = 0f
    private var cx = 0f
    private var cy = 0f

    // Chuyển động (giây, SystemClock): đồng tử from → to, quầng from → to, mí from → to, chớp.
    private var pupilFromX = 0f; private var pupilFromY = 0f; private var pupilToX = 0f; private var pupilToY = 0f
    private var pupilT0 = NEVER; private var pupilDur = AIEye.LOOK_TIME
    private var scaleFrom = 1f; private var scaleTo = 1f
    private var glowFrom = AIEye.REST_GLOW.toFloat(); private var glowTo = AIEye.REST_GLOW.toFloat(); private var glowT0 = NEVER
    private var lidFrom = AIEye.REST_LID.toFloat(); private var lidTo = AIEye.REST_LID.toFloat(); private var lidT0 = NEVER
    private var lidDur = AIEye.LID_TIME
    private var blinkT0 = NEVER
    /** Bắt đầu thở (giây) — NEVER = không thở. */
    private var breathT0 = NEVER
    private var tickPosted = false
    private val tick = Runnable { tickPosted = false; onTick(now()) }

    /** Đo / test: số khung hình đã vẽ khi còn chuyển động. */
    internal var animFrames = 0; private set

    init {
        isClickable = false
        isFocusable = false
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
    }

    @SuppressLint("ClickableViewAccessibility")
    override fun onTouchEvent(event: MotionEvent?) = false

    private fun now() = SystemClock.uptimeMillis() / 1000.0

    /** Tâm quả cầu (toạ độ view cha). */
    val eyeCenterX: Float get() = left + width / 2f
    val eyeCenterY: Float get() = top + height / 2f

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        if (w <= 0 || h <= 0) return
        side = minOf(w, h).toFloat()
        radius = (side * AIEye.ORB).toFloat()
        cx = w / 2f; cy = h / 2f
        fun c(rgb: Int, a: Float) = (Math.round(a * 255) shl 24) or rgb
        haloPaint.shader = RadialGradient(cx, cy, side / 2f, intArrayOf(c(AIEye.HALO_INNER, 0.85f), c(AIEye.HALO_OUTER, 0.35f),
            c(AIEye.HALO_OUTER, 0f)), floatArrayOf(0f, 0.55f, 1f), Shader.TileMode.CLAMP)
        orbPaint.shader = RadialGradient(cx - radius * 0.16f, cy - radius * 0.24f, radius * 1.15f,
            IntArray(3) { AIEye.ORB_COLORS[it] or OPAQUE }, floatArrayOf(0f, 0.6f, 1f), Shader.TileMode.CLAMP)
        val ri = (side * AIEye.IRIS).toFloat()
        irisPaint.shader = RadialGradient(cx, cy, ri, IntArray(3) { AIEye.IRIS_COLORS[it] or OPAQUE },
            floatArrayOf(0f, 0.45f, 1f), Shader.TileMode.CLAMP)
        ringPaint.strokeWidth = 1.2f * density
        lidLinePaint.strokeWidth = density
        orbClip.rewind(); orbClip.addCircle(cx, cy, radius, Path.Direction.CW)
    }

    /** Phím vừa bấm, tâm phím ([x], [y]) theo toạ độ view CHA. */
    fun keyPressed(x: Float, y: Float) {
        val t = now()
        val wasResting = clock.phase(t) == AIEye.Phase.RESTING
        val n = clock.press(t)
        val lv = combo.press(SystemClock.uptimeMillis())
        breathT0 = NEVER
        if (side > 0f) {
            AIEye.pupilOffset(cx.toDouble(), cy.toDouble(), (x - left).toDouble(), (y - top).toDouble(),
                AIEye.maxOffset(side.toDouble()), off, AIEye.GAZE * density)
            val ps = pupilAt(t)
            pupilFromX = ps[0]; pupilFromY = ps[1]; scaleFrom = ps[2]
            pupilToX = off[0].toFloat(); pupilToY = off[1].toFloat(); scaleTo = AIEye.pupilScale(lv).toFloat()
            pupilT0 = t; pupilDur = AIEye.LOOK_TIME
            glowFrom = glowAt(t); glowTo = AIEye.glow(lv).toFloat(); glowT0 = t
            if (wasResting) { lidFrom = lidAt(t); lidTo = AIEye.OPEN_LID.toFloat(); lidT0 = t; lidDur = AIEye.LOOK_TIME }
            if (!lowPower && AIEye.blinks(n)) blinkT0 = t
            if (lowPower) { pupilT0 = NEVER; glowT0 = NEVER; lidT0 = NEVER; lidFrom = lidTo }
        }
        schedule(if (lowPower) AIEye.BREATH_END else AIEye.IDLE_AFTER)
        invalidate()
    }

    /** Chạm ô nhân vật: chớp một cái (mở mắt nếu đang lim dim). */
    fun tickle() {
        if (lowPower) return
        keyPressed(left + width / 2f, top + height / 2f)
        blinkT0 = now()
        invalidate()
    }

    private fun schedule(s: Double) {
        removeCallbacks(tick)
        tickPosted = true
        postDelayed(tick, maxOf(50L, Math.round(s * 1000)))
    }

    private fun onTick(t: Double) {
        when (clock.phase(t)) {
            AIEye.Phase.ACTIVE -> clock.nextDeadline(t)?.let { schedule(it - t) }
            AIEye.Phase.BREATHING -> {
                if (breathT0 == NEVER && !lowPower) {
                    // Đồng tử về giữa (0,6 s), quầng về nền rồi phập phồng ĐÚNG số nhịp còn lại.
                    val ps = pupilAt(t)
                    pupilFromX = ps[0]; pupilFromY = ps[1]; scaleFrom = ps[2]; pupilToX = 0f; pupilToY = 0f; scaleTo = 1f
                    pupilT0 = t; pupilDur = 0.6
                    glowT0 = NEVER; glowTo = AIEye.REST_GLOW.toFloat()
                    breathT0 = clock.lastPress + AIEye.IDLE_AFTER
                    invalidate()
                }
                clock.nextDeadline(t)?.let { schedule(it - t) }
            }
            AIEye.Phase.RESTING -> settle(t, animated = !lowPower)
        }
    }

    private fun settle(t: Double, animated: Boolean) {
        breathT0 = NEVER
        glowT0 = NEVER; glowTo = AIEye.REST_GLOW.toFloat()
        val ps = pupilAt(t)
        pupilFromX = ps[0]; pupilFromY = ps[1]; scaleFrom = ps[2]; pupilToX = 0f; pupilToY = 0f; scaleTo = 1f
        pupilT0 = if (animated) t else NEVER; pupilDur = AIEye.LID_TIME
        lidFrom = lidAt(t); lidTo = AIEye.REST_LID.toFloat(); lidT0 = if (animated) t else NEVER; lidDur = AIEye.LID_TIME
        if (!animated) lidFrom = lidTo
        invalidate()
    }

    /** Ẩn bàn phím / đổi nhân vật: đứng yên ở dáng lim dim, huỷ hẹn giờ. */
    fun halt() {
        removeCallbacks(tick); tickPosted = false
        clock.reset(); combo.reset()
        blinkT0 = NEVER
        settle(now(), animated = false)
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        halt()
    }

    private val pupilTmp = FloatArray(3)
    /** (dx, dy, scale) đồng tử lúc [t]. */
    private fun pupilAt(t: Double): FloatArray {
        val f = if (pupilT0 == NEVER) 1f else ((t - pupilT0) / pupilDur).coerceIn(0.0, 1.0).toFloat()
        val e = 1f - (1f - f) * (1f - f)
        pupilTmp[0] = pupilFromX + (pupilToX - pupilFromX) * e
        pupilTmp[1] = pupilFromY + (pupilToY - pupilFromY) * e
        pupilTmp[2] = scaleFrom + (scaleTo - scaleFrom) * e
        return pupilTmp
    }
    private fun glowAt(t: Double): Float {
        if (breathT0 != NEVER) return AIEye.breathGlow(t - breathT0).toFloat()
        if (glowT0 == NEVER) return glowTo
        val f = ((t - glowT0) / AIEye.LOOK_TIME).coerceIn(0.0, 1.0).toFloat()
        return glowFrom + (glowTo - glowFrom) * f
    }
    private fun lidAt(t: Double): Float {
        var o = if (lidT0 == NEVER) lidTo else lidFrom + (lidTo - lidFrom) * ((t - lidT0) / lidDur).coerceIn(0.0, 1.0).toFloat()
        if (blinkT0 != NEVER) {
            val f = (t - blinkT0) / AIEye.BLINK_TIME
            if (f in 0.0..1.0) {
                val k = if (f < 0.45) f / 0.45 else (1 - f) / 0.55
                o += ((AIEye.BLINK_LID.toFloat() - o) * k).toFloat()
            }
        }
        return o
    }
    private fun moving(t: Double): Boolean =
        (pupilT0 != NEVER && t - pupilT0 < pupilDur) || (glowT0 != NEVER && t - glowT0 < AIEye.LOOK_TIME) ||
            (lidT0 != NEVER && t - lidT0 < lidDur) || (blinkT0 != NEVER && t - blinkT0 < AIEye.BLINK_TIME) ||
            (breathT0 != NEVER && t - breathT0 < AIEye.BREATH_PERIOD * AIEye.BREATH_CYCLES)

    override fun onDraw(canvas: Canvas) {
        if (side <= 0f) return
        val t = now()
        haloPaint.alpha = (255 * glowAt(t)).toInt().coerceIn(0, 255)
        canvas.drawCircle(cx, cy, side / 2f, haloPaint)
        canvas.drawCircle(cx, cy, radius, orbPaint)
        val save = canvas.save()
        canvas.clipPath(orbClip)
        canvas.drawCircle(cx, cy, (side * AIEye.IRIS).toFloat(), irisPaint)
        val p = pupilAt(t)
        val rp = (side * AIEye.PUPIL).toFloat() * p[2]
        val px = cx + p[0]; val py = cy + p[1]
        canvas.drawCircle(px, py, rp, pupilPaint)
        canvas.drawCircle(px - rp * 0.42f, py - rp * 0.42f, rp * 0.32f, shinePaint)
        val edge = (cy - radius) + AIEye.lidEdge(lidAt(t).toDouble(), radius.toDouble()).toFloat()
        if (edge > cy - radius + 0.5f) {
            canvas.drawRect(cx - radius, cy - radius, cx + radius, edge, lidPaint)
            canvas.drawLine(cx - radius, edge, cx + radius, edge, lidLinePaint)
        }
        canvas.restoreToCount(save)
        canvas.drawCircle(cx, cy, radius - ringPaint.strokeWidth / 2, ringPaint)
        if (moving(t)) { animFrames++; postInvalidateOnAnimation() }
    }

    // Test
    internal val phase: AIEye.Phase get() = clock.phase(now())
    internal val tickScheduled: Boolean get() = tickPosted
    internal fun pupilNow(): FloatArray = pupilAt(Double.MAX_VALUE).copyOf()
    internal fun isMoving(): Boolean = moving(now())
    internal fun glowNow(): Float = glowAt(now())
    internal fun lidNow(): Float = lidAt(now())
    internal fun maxOffsetPx(): Double = AIEye.maxOffset(side.toDouble())
    internal fun tickAt(t: Double) = onTick(t)
    internal fun backdate(ago: Double) { clock.reset(); clock.press(now() - ago) }

    companion object {
        private const val OPAQUE = 0xFF shl 24
        private const val NEVER = -1e18
    }
}
