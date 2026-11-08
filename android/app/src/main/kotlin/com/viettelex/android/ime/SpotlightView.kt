package com.viettelex.android.ime

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.LightingColorFilter
import android.graphics.LinearGradient
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PorterDuff
import android.graphics.PorterDuffColorFilter
import android.graphics.PorterDuffXfermode
import android.graphics.RadialGradient
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.Shader
import android.os.SystemClock
import android.view.MotionEvent
import android.view.View
import com.viettelex.keyboard.BuddyCharacter
import com.viettelex.keyboard.ComboMeter
import com.viettelex.keyboard.DiscoBall
import com.viettelex.keyboard.NightDancer
import com.viettelex.keyboard.SpotlightFx
import com.viettelex.keyboard.SpotlightLights
import com.viettelex.keyboard.SpotlightTexture

/**
 * "Đèn rọi" (theme Neon Night Club — "photoFx":"spotlight", [com.viettelex.keyboard.SpotlightPolicy]) + quả cầu disco
 * nhỏ. Song sinh iOS SpotlightView (NightClub.swift) — số liệu chung ở keyboard/Spotlight.kt.
 *
 * Thứ tự lớp: ImeRootView vẽ nền theme + ảnh nền + lớp phủ trong onDraw · VIEW NÀY (con đầu tiên) · hiệu ứng dải dưới ·
 * phím. Không nhận chạm. Chỉ tồn tại khi theme đang dùng có "photoFx":"spotlight" (IME gắn/gỡ mỗi lần hiện — theme khác
 * không có view, 0 chi phí).
 *
 *  • Có ảnh nền: phủ đen 90 % (vẽ một lần vào display list — nghỉ = không vẽ lại). Mỗi phím bấm: chớp đèn sân khấu
 *    (~3,8–4,9 bề rộng phím, lõi lộ ảnh 100 % / quầng ~60 %, giữ 0,15 s rồi tắt ~1 s) rọi ảnh — CHÍNH bitmap ảnh nền
 *    của ImeRootView (không giải mã / sao chép thêm) vẽ qua mặt nạ RadialGradient trong MỘT saveLayer (SRC_IN), cộng
 *    quầng tô neon (SCREEN: lõi nóng gần trắng → màu → vành sáng mờ). Không ảnh nền: NGƯỜI NHẢY HOẠT HÌNH
 *    ([NightDancer] — atlas 4 × 2 của Bạn đồng hành, cô gái / chàng trai) cao 85 % bàn phím phía sau phím, chìm trong tối (~12 % sáng — LightingColorFilter);
 *    trong saveLayer của đèn: phông tím đêm + viền neon theo màu đèn (bóng tô màu dời ±viền) + nhân vật màu thật (SRC_ATOP
 *    ⇒ chỉ lộ dưới đèn). Mỗi lần đèn nháy ⇒ biến thể kế (7 khung × lật ngang, không lặp liền). Atlas giải MỘT lần trên
 *    luồng nền theo cỡ hiển thị ([NightDancer.decodeLongEdge]); có ảnh nền ⇒ không giải / thả ra.
 *  • Paint / Shader / mảng cấp sẵn ⇒ không cấp phát mỗi khung hình; chỉ hẹn khung hình khi còn quầng / chấm / quả cầu
 *    đang xoay (nghỉ = 0 CPU).
 */
@SuppressLint("ViewConstructor")
class SpotlightView(context: Context, private val density: Float) : View(context) {
    private val lights = SpotlightLights()
    private val combo = ComboMeter()
    private val lx = FloatArray(SpotlightFx.CAP)
    private val ly = FloatArray(SpotlightFx.CAP)
    private val lr = FloatArray(SpotlightFx.CAP)
    private val lc = IntArray(SpotlightFx.CAP)

    private var photo: Bitmap? = null
    private var photoMatrix: Matrix? = null
    private val darkPaint = Paint().apply { color = (Math.round(SpotlightFx.DARKNESS * 255).toInt() shl 24) }
    private val maskPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        // Lõi lộ ảnh 100 %, quầng ~60 %, rìa tắt (SpotlightFx.MASK_*).
        shader = RadialGradient(0f, 0f, 1f,
            IntArray(SpotlightFx.MASK_LEVELS.size) { (Math.round(SpotlightFx.MASK_LEVELS[it] * 255).toInt() shl 24) or 0xFFFFFF },
            FloatArray(SpotlightFx.MASK_STOPS.size) { SpotlightFx.MASK_STOPS[it].toFloat() }, Shader.TileMode.CLAMP)
    }
    private val tintPaints = Array(SpotlightFx.COLORS.size) { i ->
        val c = SpotlightFx.COLORS[i]
        Paint(Paint.ANTI_ALIAS_FLAG).apply {
            // Lõi nóng gần trắng → màu neon → vành sáng mờ ở rìa (SpotlightFx.GLOW_*), cộng sáng (SCREEN).
            shader = RadialGradient(0f, 0f, 1f, IntArray(SpotlightFx.GLOW_STOPS.size) { SpotlightFx.glowColor(c, it) },
                FloatArray(SpotlightFx.GLOW_STOPS.size) { SpotlightFx.GLOW_STOPS[it].toFloat() }, Shader.TileMode.CLAMP)
            xfermode = PorterDuffXfermode(PorterDuff.Mode.SCREEN)
        }
    }
    private val photoPaint = Paint(Paint.FILTER_BITMAP_FLAG).apply { xfermode = PorterDuffXfermode(PorterDuff.Mode.SRC_IN) }
    private val gradPaint = Paint().apply { xfermode = PorterDuffXfermode(PorterDuff.Mode.SRC_IN) }
    // Người nhảy (không ảnh nền): atlas giải lười trên luồng nền, src / dst dùng lại.
    /** Nhân vật nhảy ([NightDancer.character]) — đổi ⇒ thả atlas cũ, giải lại lần cần vẽ. */
    var dancer: BuddyCharacter = BuddyCharacter.GIRL
        set(v) {
            if (field == v) return
            field = v; atlas = null; atlasGen++; loading = false
            maybeLoadAtlas()
        }
    @Volatile private var atlas: Bitmap? = null
    private var atlasGen = 0
    private var loading = false
    private var flashes = 0
    /** Biến thể đang hiện (khung × lật — [NightDancer.next]); 0 = đứng thẳng trước lần nháy đầu. */
    internal var variant = 0; private set
    private var rimColor = SpotlightFx.COLORS[0]
    private val dSrc = Rect()
    private val dDst = RectF()
    private val shadePaint = Paint(Paint.FILTER_BITMAP_FLAG).apply {
        val k = Math.round(NightDancer.SHADE * 255).toInt()
        colorFilter = LightingColorFilter((k shl 16) or (k shl 8) or k, 0)
    }
    private var rimFilterColor = -1
    private val colorPaint = Paint(Paint.FILTER_BITMAP_FLAG).apply { xfermode = PorterDuffXfermode(PorterDuff.Mode.SRC_ATOP) }
    private val rimPaint = Paint(Paint.FILTER_BITMAP_FLAG).apply { xfermode = PorterDuffXfermode(PorterDuff.Mode.SRC_ATOP) }

    // Quả cầu disco
    private val ballPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val facetPath = Path()
    private val ballClip = Path()
    private var spinFrom = 0f
    private var spinTo = 0f
    private var spinStart = Double.NEGATIVE_INFINITY
    private var lastDots = Double.NEGATIVE_INFINITY
    private val dotStart = DoubleArray(DiscoBall.DOT_POOL) { Double.NEGATIVE_INFINITY }
    private val dotDx = FloatArray(DiscoBall.DOT_POOL)
    private val dotDy = FloatArray(DiscoBall.DOT_POOL)
    private val dotColor = IntArray(DiscoBall.DOT_POOL)
    private var dotCursor = 0

    // Chờ vẽ (gõ chồng trong cùng lượt) — tối đa MAX_PENDING khung mới nhất.
    private val pendX = FloatArray(MAX_PENDING)
    private val pendY = FloatArray(MAX_PENDING)
    private val pendW = FloatArray(MAX_PENDING)
    private var pendN = 0
    private var posted = false
    private val flushRun = Runnable { flush() }

    init {
        isClickable = false
        isFocusable = false
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
        setWillNotDraw(false)
        val d = (DiscoBall.DIAMETER * density).toFloat()
        val step = d / 4
        for (k in 1..3) {
            facetPath.moveTo(-d / 2 + k * step, -d / 2); facetPath.lineTo(-d / 2 + k * step, d / 2)
            facetPath.moveTo(-d / 2, -d / 2 + k * step); facetPath.lineTo(d / 2, -d / 2 + k * step)
        }
        ballClip.addCircle(0f, 0f, d / 2, Path.Direction.CW)
    }

    @SuppressLint("ClickableViewAccessibility")
    override fun onTouchEvent(event: MotionEvent?) = false

    /** Ảnh nền đang hiện của ImeRootView (CHÍNH bitmap + ma trận center-crop theo toạ độ view gốc) hoặc null = hoạ tiết. */
    fun setPhoto(b: Bitmap?, m: Matrix?) {
        if (photo === b && photoMatrix === m) return
        photo = b; photoMatrix = m
        if (b != null) { atlas = null; atlasGen++; loading = false }   // có ảnh nền ⇒ không người nhảy, thả atlas
        else maybeLoadAtlas()
        invalidate()
    }

    /** Test: atlas người nhảy đang giữ (null = chưa giải / có ảnh nền). */
    internal val dancerAtlas: Bitmap? get() = atlas

    /** Giải atlas người nhảy MỘT lần trên luồng nền (chỉ khi không có ảnh nền và đã biết cỡ). */
    private fun maybeLoadAtlas() {
        if (photo != null || atlas != null || loading || height <= 0) return
        loading = true
        val gen = atlasGen
        val c = dancer
        val displayDp = height * NightDancer.HEIGHT_FRACTION / density
        val app = context.applicationContext
        ATLAS_EXECUTOR.execute {
            val b = decodeAtlas(app, c, displayDp, density.toDouble())
            post {
                if (gen != atlasGen) return@post
                loading = false
                if (photo == null) { atlas = b; invalidate() }
            }
        }
    }

    /** Test: giải đồng bộ (Robolectric). */
    internal fun loadAtlasNow() {
        if (photo != null) return
        atlas = decodeAtlas(context, dancer, height * NightDancer.HEIGHT_FRACTION / density, density.toDouble())
    }
    internal val hasPhoto: Boolean get() = photo != null

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        if (w <= 0 || h <= 0) return
        val g = SpotlightTexture.GRADIENT
        gradPaint.shader = LinearGradient(0f, 0f, w.toFloat(), h.toFloat(), intArrayOf(g[0] or (0xFF shl 24), g[1] or (0xFF shl 24),
            g[2] or (0xFF shl 24)), null, Shader.TileMode.CLAMP)
        maybeLoadAtlas()
    }

    /** Khung phím vừa bấm: tâm ([x], [y]) + bề rộng [w] (px, toạ độ view này) — vẽ ở lượt sau, SAU khi phím đã chèn chữ. */
    fun light(x: Float, y: Float, w: Float) {
        if (pendN == MAX_PENDING) {
            for (i in 1 until MAX_PENDING) { pendX[i - 1] = pendX[i]; pendY[i - 1] = pendY[i]; pendW[i - 1] = pendW[i] }
            pendN--
        }
        pendX[pendN] = x; pendY[pendN] = y; pendW[pendN] = w; pendN++
        if (!posted) { posted = true; post(flushRun) }
    }

    /** Bật các quầng đang chờ (test gọi thẳng). */
    fun flush() {
        posted = false
        if (pendN == 0) return
        val nowMs = SystemClock.uptimeMillis()
        val now = nowMs / 1000.0
        for (i in 0 until pendN) {
            val level = combo.press(nowMs)
            val press = lights.presses
            val s = lights.press(now, level)
            val wDp = if (pendW[i] > 0f) pendW[i] / density else 34f
            lx[s] = pendX[i]; ly[s] = pendY[i]
            lr[s] = (SpotlightFx.radius(wDp.toDouble(), level) * density).toFloat()
            lc[s] = ((press % SpotlightFx.COLORS.size) + SpotlightFx.COLORS.size) % SpotlightFx.COLORS.size
        }
        pendN = 0
        if (photo == null) {
            // Mỗi lần đèn nháy: người nhảy sang biến thể kế (không lặp liền) + viền theo màu đèn vừa bật.
            flashes++
            variant = NightDancer.next(variant, flashes)
            rimColor = SpotlightFx.color(lights.presses - 1)
        }
        spin(now)
        postInvalidateOnAnimation()
    }

    private fun spin(now: Double) {
        spinFrom = currentAngle(now)
        spinTo = spinFrom + DiscoBall.SPIN.toFloat()
        spinStart = now
        if (now - lastDots < DiscoBall.MIN_INTERVAL) return
        lastDots = now
        val press = lights.presses
        for (i in 0 until DiscoBall.DOTS_PER_PRESS) {
            val s = dotCursor; dotCursor = (s + 1) % DiscoBall.DOT_POOL
            val d = DiscoBall.direction(press, i)
            dotStart[s] = now; dotDx[s] = d[0].toFloat(); dotDy[s] = d[1].toFloat()
            dotColor[s] = SpotlightFx.COLORS[(press + i) % SpotlightFx.COLORS.size]
        }
    }

    private fun currentAngle(now: Double): Float {
        val u = ((now - spinStart) / DiscoBall.SPIN_DURATION).coerceIn(0.0, 1.0)
        val e = 1 - (1 - u) * (1 - u)
        return (spinFrom + (spinTo - spinFrom) * e).toFloat()
    }

    /** Ẩn bàn phím / gỡ: tắt mọi quầng + chấm (không còn khung hình nào). */
    fun halt() {
        pendN = 0
        lights.reset(); combo.reset()
        dotStart.fill(Double.NEGATIVE_INFINITY)
        spinFrom = spinTo; spinStart = Double.NEGATIVE_INFINITY
        invalidate()
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        halt()
    }

    internal fun liveLights(): Int = lights.live(SystemClock.uptimeMillis() / 1000.0)
    internal val presses: Int get() = lights.presses
    internal fun lightRadius(i: Int): Float = lr[i]

    override fun onDraw(canvas: Canvas) {
        val w = width.toFloat(); val h = height.toFloat()
        val ph = photo
        if (ph != null) canvas.drawRect(0f, 0f, w, h, darkPaint)
        // Người nhảy chìm trong tối (ngoài đèn) — trước lớp đèn.
        val dance = if (ph == null) atlas?.takeIf { dancerRects(it, w, h) } else null
        if (dance != null) drawDancer(canvas, dance, shadePaint, 0f, 0f)
        val now = SystemClock.uptimeMillis() / 1000.0
        var alive = false
        if (lights.live(now) > 0) {
            alive = true
            val save = canvas.saveLayer(0f, 0f, w, h, null)
            for (i in 0 until SpotlightFx.CAP) {
                val dt = now - lights.starts[i]
                val a = SpotlightFx.alpha(dt, lights.levels[i])
                if (a <= 0) continue
                val r = (lr[i] * SpotlightFx.scale(dt, lights.levels[i])).toFloat()
                maskPaint.alpha = (a * 255).toInt().coerceIn(0, 255)
                canvas.save(); canvas.translate(lx[i], ly[i]); canvas.scale(r, r)
                canvas.drawCircle(0f, 0f, 1f, maskPaint)
                canvas.restore()
            }
            val m = photoMatrix
            if (ph != null && m != null && !(ph.config == Bitmap.Config.HARDWARE && !canvas.isHardwareAccelerated)) {
                canvas.save(); canvas.translate(-left.toFloat(), -top.toFloat())
                canvas.drawBitmap(ph, m, photoPaint)
                canvas.restore()
            } else {
                canvas.drawRect(0f, 0f, w, h, gradPaint)
                if (dance != null) {
                    // Viền neon: bóng tô màu đèn dời ±viền (8 hướng), rồi nhân vật màu thật đè lên — chỉ dưới đèn (SRC_ATOP).
                    if (rimFilterColor != rimColor) {
                        rimFilterColor = rimColor
                        rimPaint.colorFilter = PorterDuffColorFilter(rimColor or (0xFF shl 24), PorterDuff.Mode.SRC_IN)
                    }
                    val r = (NightDancer.RIM * density).toFloat()
                    for (k in 0 until 8) drawDancer(canvas, dance, rimPaint, r * RIM_DX[k], r * RIM_DY[k])
                    drawDancer(canvas, dance, colorPaint, 0f, 0f)
                }
            }
            canvas.restoreToCount(save)
            for (i in 0 until SpotlightFx.CAP) {
                val dt = now - lights.starts[i]
                val a = SpotlightFx.alpha(dt, lights.levels[i])
                if (a <= 0) continue
                val r = (lr[i] * SpotlightFx.scale(dt, lights.levels[i])).toFloat()
                val p = tintPaints[lc[i]]
                p.alpha = (a * 255).toInt().coerceIn(0, 255)
                canvas.save(); canvas.translate(lx[i], ly[i]); canvas.scale(r, r)
                canvas.drawCircle(0f, 0f, 1f, p)
                canvas.restore()
            }
        }
        if (drawBall(canvas, now, w)) alive = true
        if (alive) postInvalidateOnAnimation()
    }

    /** Đặt src (ô khung của biến thể) / dst (85 % cao, đứng đáy, giữa ngang) — false nếu atlas hỏng. */
    private fun dancerRects(b: Bitmap, w: Float, h: Float): Boolean {
        if (b.width <= 0 || b.height <= 0) return false
        val c = NightDancer.cell(NightDancer.frame(variant))
        dSrc.set(Math.round(c[0] * b.width).toInt(), Math.round(c[1] * b.height).toInt(),
            Math.round((c[0] + c[2]) * b.width).toInt(), Math.round((c[1] + c[3]) * b.height).toInt())
        val aspect = dSrc.width().toDouble() / maxOf(dSrc.height(), 1)
        val r = NightDancer.rect(w.toDouble(), h.toDouble(), aspect)
        dDst.set(r[0].toFloat(), r[1].toFloat(), (r[0] + r[2]).toFloat(), (r[1] + r[3]).toFloat())
        return true
    }

    /** Test: khung vẽ người nhảy hiện tại (px). */
    internal val dancerRect: RectF get() = dDst

    /** Vẽ ô hiện tại (lật ngang nếu biến thể lật) dời ([dx], [dy]) px. */
    private fun drawDancer(canvas: Canvas, b: Bitmap, p: Paint, dx: Float, dy: Float) {
        canvas.save()
        canvas.translate(dx, dy)
        if (NightDancer.mirrored(variant)) canvas.scale(-1f, 1f, dDst.centerX(), 0f)
        canvas.drawBitmap(b, dSrc, dDst, p)
        canvas.restore()
    }

    /** Quả cầu disco + chấm sáng; true = còn chuyển động. */
    private fun drawBall(canvas: Canvas, now: Double, w: Float): Boolean {
        val c = DiscoBall.center(0.0, 0.0, (w / density).toDouble())
        val cx = (c[0] * density).toFloat(); val cy = (c[1] * density).toFloat()
        val d = (DiscoBall.DIAMETER * density).toFloat()
        var moving = false
        // Chấm sáng toả ra
        for (s in 0 until DiscoBall.DOT_POOL) {
            val dt = now - dotStart[s]
            val a = DiscoBall.dotAlpha(dt)
            if (a <= 0) continue
            moving = true
            val dist = (DiscoBall.dotTravel(dt) * density).toFloat()
            ballPaint.style = Paint.Style.FILL
            ballPaint.color = dotColor[s] or (0xFF shl 24); ballPaint.alpha = (a * 255).toInt().coerceIn(0, 255)
            canvas.drawCircle(cx + dotDx[s] * dist, cy + dotDy[s] * dist, (DiscoBall.DOT_RADIUS * density).toFloat(), ballPaint)
        }
        // Dây treo
        ballPaint.style = Paint.Style.STROKE; ballPaint.strokeWidth = 0.8f * density
        ballPaint.color = 0xB3BFBFBF.toInt()
        canvas.drawLine(cx, cy - d / 2 - (DiscoBall.CORD * density).toFloat(), cx, cy - d / 2, ballPaint)
        // Thân + mặt gương xoay
        canvas.save(); canvas.translate(cx, cy)
        ballPaint.style = Paint.Style.FILL; ballPaint.color = 0xFFB9BCC8.toInt()
        canvas.drawCircle(0f, 0f, d / 2, ballPaint)
        canvas.save(); canvas.clipPath(ballClip)
        val ang = currentAngle(now)
        if (now - spinStart < DiscoBall.SPIN_DURATION) moving = true
        canvas.rotate(Math.toDegrees(ang.toDouble()).toFloat())
        ballPaint.style = Paint.Style.STROKE; ballPaint.strokeWidth = 0.7f * density; ballPaint.color = 0xFF5A5E6E.toInt()
        canvas.drawPath(facetPath, ballPaint)
        canvas.restore()
        ballPaint.strokeWidth = 0.6f * density; ballPaint.color = 0xFFE6E8F0.toInt()
        canvas.drawCircle(0f, 0f, d / 2, ballPaint)
        ballPaint.style = Paint.Style.FILL; ballPaint.color = 0xE6FFFFFF.toInt()
        canvas.drawCircle(-d * 0.17f, -d * 0.21f, d * 0.11f, ballPaint)
        canvas.restore()
        return moving
    }

    companion object {
        const val MAX_PENDING = 4
        private val RIM_DX = FloatArray(8) { Math.cos(Math.PI / 4 * it).toFloat() }
        private val RIM_DY = FloatArray(8) { Math.sin(Math.PI / 4 * it).toFloat() }
        private val ATLAS_EXECUTOR = java.util.concurrent.Executors.newSingleThreadExecutor { r ->
            Thread(r, "vt-dancer").apply { isDaemon = true }
        }

        /** Giải atlas buddy-<id>-v2.png theo cỡ hiển thị (inSampleSize — [NightDancer.sampleSize]). Lỗi / OOM ⇒ null. */
        internal fun decodeAtlas(context: Context, c: BuddyCharacter, displayDp: Double, density: Double): Bitmap? = try {
            val name = "buddy-${c.id}-v2.png"
            val o = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            context.assets.open(name).use { BitmapFactory.decodeStream(it, null, o) }
            val target = NightDancer.decodeLongEdge(displayDp, density, o.outWidth, o.outHeight)
            if (target <= 0) null else {
                o.inJustDecodeBounds = false
                o.inScaled = false
                o.inSampleSize = NightDancer.sampleSize(maxOf(o.outWidth, o.outHeight), target)
                context.assets.open(name).use { BitmapFactory.decodeStream(it, null, o) }
            }
        } catch (_: java.io.IOException) { null } catch (_: RuntimeException) { null } catch (_: OutOfMemoryError) { null }
    }
}
