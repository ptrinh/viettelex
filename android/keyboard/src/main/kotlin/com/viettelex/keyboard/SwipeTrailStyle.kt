package com.viettelex.keyboard

import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * "Hiệu ứng nét vuốt" (Gõ vuốt → Hiệu ứng nét vuốt) — THUẦN, song sinh iOS/Keyboard/SwipeTrailStyles.swift:
 * cùng khoá [Keys.SWIPE_TRAIL] (`swipeTrail`), cùng id, cùng hàm thuần (nhiễu tia điện, độ dày bút lông,
 * quỹ đạo hạt). "Tắt" + "Đơn giản" (mặc định = vệt cũ) miễn phí; còn lại Plus — chưa có Plus ⇒ Đơn giản
 * (giá trị lưu giữ nguyên). Tắt ⇒ IME không gắn vệt (0 chi phí). Vệt = MỘT đường dựng lại mỗi khung; kiểu
 * chỉ đổi Paint / shader dựng sẵn lúc cấu hình. Hạt: mảng cấp sẵn ≤ [SwipeTrailFx.PARTICLE_CAP].
 */
enum class SwipeTrailStyle(val id: String, val viTitle: String) {
    NONE("none", "Tắt"), // l10n-key
    SIMPLE("simple", "Đơn giản"), // l10n-key
    FIRE("fire", "Lửa"), // l10n-key
    ELECTRIC("electric", "Điện"), // l10n-key
    BRUSH("brush", "Bút lông"), // l10n-key
    RAINBOW("rainbow", "Cầu vồng"), // l10n-key
    NEON("neon", "Neon"), // l10n-key
    STARDUST("stardust", "Bụi sao"), // l10n-key
    FIREWORK("firework", "Pháo hoa cuối nét"), // l10n-key
    PLASMA("plasma", "Plasma"), // l10n-key
    THEME("theme", "Theo giao diện"); // l10n-key

    val title: String get() = tr(viTitle)

    /** Tắt + Đơn giản miễn phí; còn lại (cả "Theo giao diện") thuộc Plus. */
    val isPlus: Boolean get() = this != NONE && this != SIMPLE

    /** Sinh hạt mỗi N điểm của đường vuốt (0 = không hạt dọc đường). */
    val spawnEvery: Int get() = when (this) {
        FIRE -> 3
        STARDUST -> 4
        PLASMA -> 5
        else -> 0
    }
    /** Có pool hạt (dọc đường hoặc chùm pháo hoa lúc nhấc tay). */
    val usesParticles: Boolean get() = spawnEvery > 0 || this == FIREWORK

    /**
     * Các lớp nét (dưới → trên) — = iOS strokes. [base] = bề rộng vệt Đơn giản (Android 5dp, iOS 6pt);
     * [trail] = màu vệt theme (ARGB); [accent] = màu nhấn (RGB).
     */
    fun strokes(base: Double, trail: Int, accent: Int, dark: Boolean): List<SwipeTrailStroke> {
        val a = accent and 0xFFFFFF
        fun alpha(rgb: Int, x: Double): Int = ((x * 255).roundToInt() shl 24) or (rgb and 0xFFFFFF)
        return when (this) {
            NONE, THEME -> emptyList()
            SIMPLE, FIREWORK -> listOf(SwipeTrailStroke(base, trail))
            FIRE -> listOf(SwipeTrailStroke(base * 2.2, 0x73FF3B1F), SwipeTrailStroke(base * 1.1, 0xE6FF8A1A.toInt()),
                SwipeTrailStroke(base * 0.45, 0xFFFFE08A.toInt()))
            ELECTRIC -> listOf(SwipeTrailStroke(base * 1.9, 0x5939D8FF), SwipeTrailStroke(base * 0.9, 0xB37FE8FF.toInt()),
                SwipeTrailStroke(base * 0.35, 0xFFFFFFFF.toInt()))
            NEON -> listOf(SwipeTrailStroke(base * 2.8, alpha(a, 0.18)), SwipeTrailStroke(base * 1.6, alpha(a, 0.40)),
                SwipeTrailStroke(base * 0.6, 0xFF000000.toInt() or SwipeTrailFx.mix(a, 0xFFFFFF, 0.65)))
            RAINBOW -> listOf(SwipeTrailStroke(base, 0xFFFFFFFF.toInt(), SwipeTrailStroke.Kind.GRADIENT))
            BRUSH -> listOf(SwipeTrailStroke(0.0, if (dark) 0xE6F2F2F2.toInt() else 0xE61A1A1A.toInt(), SwipeTrailStroke.Kind.FILL))
            STARDUST -> listOf(SwipeTrailStroke(base * 0.45, alpha(a, 0.55)))
            // = hiệu ứng phím Plasma: quầng tím, thân tím nhạt, lõi gần trắng (= iOS)
            PLASMA -> listOf(SwipeTrailStroke(base * 2.4, 0x59B44CFF), SwipeTrailStroke(base * 1.1, 0xBFC77DFF.toInt()),
                SwipeTrailStroke(base * 0.4, 0xFFF3E0FF.toInt()))
        }
    }

    /** Màu hạt (RGB) — hạt i dùng màu i % size. */
    fun particleColors(accent: Int): IntArray = when (this) {
        FIRE -> intArrayOf(0xFFC21A, 0xFF7A1A, 0xFF3B30)
        STARDUST -> intArrayOf(0xFFC93C, accent and 0xFFFFFF, 0xFFE7A0)
        FIREWORK -> intArrayOf(accent and 0xFFFFFF, 0xFFC93C, 0xFF5E7E, 0x4FC3F7)
        PLASMA -> intArrayOf(0xB44CFF, 0xE0B0FF, 0xF3E0FF)
        else -> IntArray(0)
    }

    companion object {
        val DEFAULT = SIMPLE
        val IDS: Set<String> = entries.map { it.id }.toSet()
        /** Id hợp lệ cho "swipe" của theme JSON: mọi kiểu cụ thể (không có "theme"). */
        val THEME_IDS: List<String> = entries.filter { it != THEME }.map { it.id }
        /** Giá trị lạ / thiếu ⇒ [DEFAULT]. */
        fun of(raw: Any?): SwipeTrailStyle = entries.firstOrNull { it.id == raw } ?: DEFAULT
        /** Kiểu hiện ở dòng cài đặt: kiểu Plus khi chưa có Plus ⇒ Đơn giản (giá trị lưu giữ nguyên). */
        fun displayed(raw: Any?, plus: Boolean = SwipeTrailGate.allows): SwipeTrailStyle =
            of(raw).let { if (it.isPlus && !plus) SIMPLE else it }
    }
}

data class SwipeTrailStroke(
    /** dp (Android) / pt (iOS). Bút lông (FILL) = 0: bề rộng theo tốc độ ([SwipeTrailFx.brushWidth]). */
    val width: Double,
    val argb: Int,
    val kind: Kind = Kind.STROKE,
) {
    enum class Kind { STROKE, FILL, GRADIENT }
}

/** Cổng Plus: đi cùng quyền theme cao cấp (như Hiệu ứng khi bấm phím). */
object SwipeTrailGate {
    val allows: Boolean get() = PlusGate.isUnlocked(PlusFeature.PREMIUM_THEMES)
    fun allows(s: SwipeTrailStyle): Boolean = !s.isPlus || allows
}

/** Kiểu thực vẽ — hàm thuần (test). Không bao giờ trả [SwipeTrailStyle.THEME]. = iOS SwipeTrailPolicy. */
object SwipeTrailPolicy {
    /** Tắt ⇒ Tắt. Chưa có Plus / tiết kiệm pin ⇒ kiểu Plus về Đơn giản. "Theo giao diện" ⇒ "swipe" của theme. */
    fun active(setting: SwipeTrailStyle, plus: Boolean, themeSwipe: String?, powerSave: Boolean): SwipeTrailStyle {
        if (!setting.isPlus) return setting
        if (!plus || powerSave) return SwipeTrailStyle.SIMPLE
        if (setting != SwipeTrailStyle.THEME) return setting
        val t = SwipeTrailStyle.entries.firstOrNull { it.id == themeSwipe }
        return if (t == null || t == SwipeTrailStyle.THEME) SwipeTrailStyle.SIMPLE else t
    }
}

/** Hàm thuần dùng chung hai nền tảng (iOS SwipeTrailFx cùng số). */
object SwipeTrailFx {
    const val PARTICLE_CAP = 24
    const val FIREWORK_COUNT = 12
    /** Biên độ nhiễu tia điện (dp). */
    const val ELECTRIC_AMPLITUDE = 4.5
    /** Tia plasma lượn rộng hơn tia điện (dp) — = iOS plasmaAmplitude. */
    const val PLASMA_AMPLITUDE = 6.0
    const val BRUSH_MAX = 10.0
    const val BRUSH_MIN = 2.5
    /** Tốc độ coi là "nhanh" (dp/ms). */
    const val BRUSH_FAST = 1.6
    const val BRUSH_SMOOTHING = 0.35
    const val BRUSH_TAPER = 6
    /** Sống lâu nhất của hạt (giây). */
    const val MAX_PARTICLE_LIFE = 1.1
    /** Cầu vồng: mốc màu (RGB), lặp 2 vòng. */
    val RAINBOW = intArrayOf(0xFF3B30, 0xFF9500, 0xFFCC00, 0x34C759, 0x00C7BE, 0x007AFF, 0xAF52DE,
        0xFF3B30, 0xFF9500, 0xFFCC00, 0x34C759, 0x00C7BE, 0x007AFF, 0xAF52DE)

    /** Nhiễu tia điện cho điểm [index] với [seed] — −1…1, tất định (LCG 32-bit như iOS, Int tràn số y hệt). */
    fun jitter(seed: Int, index: Int): Double {
        var s = (seed * 31 + index) * -1640531535 + 1      // 2654435761 dạng Int32
        s = s * 1103515245 + 12345
        return ((s ushr 8) and 0xFFFF) / 65535.0 * 2 - 1
    }

    /** Bề rộng bút lông theo tốc độ (dp/ms): chậm = dày, nhanh = mảnh. */
    fun brushWidth(speed: Double): Double {
        val f = min(1.0, max(0.0, speed) / BRUSH_FAST)
        return BRUSH_MAX - (BRUSH_MAX - BRUSH_MIN) * f
    }
    fun brushSmooth(prev: Double, target: Double): Double = prev + (target - prev) * BRUSH_SMOOTHING
    /** Hệ số vuốt nhọn hai đầu (0…1) cho điểm i trong n điểm. */
    fun brushTaperFactor(i: Int, n: Int): Double {
        val k = BRUSH_TAPER.toDouble()
        return max(0.12, minOf(1.0, (i + 1) / k, (n - i) / k))
    }

    /** Trộn hai màu RGB (t = 0 ⇒ a, 1 ⇒ b). */
    fun mix(a: Int, b: Int, t: Double): Int {
        fun ch(s: Int): Int {
            val x = ((a shr s) and 0xFF).toDouble(); val y = ((b shr s) and 0xFF).toDouble()
            return (x + (y - x) * t).roundToInt() shl s
        }
        return ch(16) or ch(8) or ch(0)
    }

    fun variants(s: SwipeTrailStyle): Int = when (s) {
        SwipeTrailStyle.FIRE -> 8
        SwipeTrailStyle.STARDUST -> 6
        SwipeTrailStyle.FIREWORK -> FIREWORK_COUNT
        SwipeTrailStyle.PLASMA -> 6
        else -> 0
    }

    /** Quỹ đạo hạt [v] (dp, giây, radian) — = iOS. */
    fun trajectory(s: SwipeTrailStyle, v: Int): KeyEffectTrajectory {
        val n = maxOf(variants(s), 1)
        val t = if (n > 1) (v - (n - 1) / 2.0) / ((n - 1) / 2.0) else 0.0
        return when (s) {
            SwipeTrailStyle.FIRE -> KeyEffectTrajectory(t * 8, -(22 + (v % 3) * 6.0), 1.0, 0.25, 0.0,
                0.55 + (v % 3) * 0.06, sway = 2.0)
            SwipeTrailStyle.STARDUST -> KeyEffectTrajectory(t * 3, -3.0, 0.4, 1.0, t * 0.8, 0.9 + (v % 3) * 0.1)
            SwipeTrailStyle.FIREWORK -> {
                val ang = v * 2 * PI / FIREWORK_COUNT
                val d = 30 + (v % 2) * 6.0
                KeyEffectTrajectory(cos(ang) * d, sin(ang) * d, 1.0, 0.35, 0.0, 0.6)
            }
            SwipeTrailStyle.PLASMA -> {   // tia lửa tím bắn ngắn ra hai bên nét, tắt nhanh (= iOS)
                val up = if (v % 2 == 0) -1.0 else 1.0
                KeyEffectTrajectory(t * 10, up * (6 + (v % 3) * 3.0), 1.0, 0.2, 0.0, 0.32 + (v % 3) * 0.05)
            }
            else -> KeyEffectTrajectory(0.0, 0.0, 1.0, 1.0, 0.0, 0.0)
        }
    }

    /** Độ đậm hạt ở tỉ lệ đời f (0…1): Bụi sao lấp lánh (= keyframes iOS), còn lại giữ rồi tắt dần. */
    fun particleAlpha(s: SwipeTrailStyle, f: Double): Double {
        if (f <= 0 || f >= 1) return 0.0
        if (s == SwipeTrailStyle.STARDUST) {
            for (k in 1 until TWINKLE_T.size) if (f <= TWINKLE_T[k]) {
                val u = (f - TWINKLE_T[k - 1]) / (TWINKLE_T[k] - TWINKLE_T[k - 1])
                return TWINKLE_V[k - 1] + (TWINKLE_V[k] - TWINKLE_V[k - 1]) * u
            }
            return 0.0
        }
        return if (f < 0.4) 1.0 else 1 - (f - 0.4) / 0.6
    }
    private val TWINKLE_T = doubleArrayOf(0.0, 0.12, 0.3, 0.45, 0.62, 0.78, 1.0)
    private val TWINKLE_V = doubleArrayOf(0.0, 1.0, 0.3, 1.0, 0.2, 0.8, 0.0)

    /** Đếm điểm để sinh hạt: true mỗi [every] điểm. */
    class Spawner(val every: Int) {
        var count = 0
            private set
        fun tick(): Boolean {
            if (every <= 0) return false
            count++
            if (count >= every) { count = 0; return true }
            return false
        }
        fun reset() { count = 0 }
    }
}

/**
 * Trạng thái vệt vuốt (THUẦN, test JVM): vòng điểm ~300 ms, hình học mỗi khung (đường gấp khúc — có nhiễu tia
 * điện — hoặc dải kín bút lông) vào mảng cấp sẵn, pool hạt cố định. View (app/.../SwipeTrailView) chỉ đổ
 * ra Path / Canvas. Không cấp phát sau khi dựng. Toạ độ px; [density] = px/dp.
 */
class SwipeTrailState(val style: SwipeTrailStyle, private val density: Float) {
    private val xs = FloatArray(CAP)
    private val ys = FloatArray(CAP)
    private val ts = LongArray(CAP)
    private var head = 0          // vị trí ghi kế tiếp
    var size = 0
        private set
    var active = false
        private set
    private var fadeStart = 0L
    var seed = 0
        private set

    /** Hình học khung hiện tại: [outN] điểm (đường) hoặc 2·n điểm (dải bút lông, kín). */
    val outX = FloatArray(CAP * 2)
    val outY = FloatArray(CAP * 2)
    var outN = 0
        private set
    /** Hệ số mờ của nét (1 khi đang vuốt, giảm khi mờ dần). */
    var strokeAlpha = 1f
        private set
    private val hw = FloatArray(CAP)
    private val tt = LongArray(CAP)

    // Hạt
    val particleCount: Int = if (style.usesParticles) SwipeTrailFx.PARTICLE_CAP else 0
    private val px = FloatArray(particleCount)
    private val py = FloatArray(particleCount)
    private val pt0 = LongArray(particleCount)
    private val alive = BooleanArray(particleCount)
    private val vCount = maxOf(1, SwipeTrailFx.variants(style))
    private val trDx = FloatArray(vCount); private val trDy = FloatArray(vCount)
    private val trS0 = FloatArray(vCount); private val trS1 = FloatArray(vCount)
    private val trRot = FloatArray(vCount); private val trDur = LongArray(vCount); private val trSway = FloatArray(vCount)
    private var cursor = 0
    private val spawner = SwipeTrailFx.Spawner(style.spawnEvery)
    private var lastX = Float.NaN
    private var lastY = Float.NaN

    init {
        for (v in 0 until vCount) {
            val t = SwipeTrailFx.trajectory(style, v)
            trDx[v] = (t.dx * density).toFloat(); trDy[v] = (t.dy * density).toFloat()
            trS0[v] = t.scaleFrom.toFloat(); trS1[v] = t.scaleTo.toFloat()
            trRot[v] = t.rotation.toFloat(); trDur[v] = (t.duration * 1000).toLong(); trSway[v] = (t.sway * density).toFloat()
        }
    }

    fun begin() { size = 0; head = 0; active = true; fadeStart = 0L; strokeAlpha = 1f; spawner.reset(); lastX = Float.NaN }

    fun add(x: Float, y: Float, tMs: Long) {
        if (!active) return
        xs[head] = x; ys[head] = y; ts[head] = tMs
        head = (head + 1) % CAP
        if (size < CAP) size++
        lastX = x; lastY = y
        if (spawner.tick()) spawn(x, y, tMs)
    }

    /** Nhấc tay (mờ dần) hoặc huỷ ([fade] = false: xoá nét ngay). Hạt bay nốt. */
    fun end(fade: Boolean, nowMs: Long) {
        if (!active && size == 0) return
        active = false
        if (fade && size > 1) fadeStart = nowMs else size = 0
    }

    /** Đã chốt từ vuốt: "Pháo hoa cuối nét" bắn một chùm ở chỗ nhấc tay. Kiểu khác: 0 việc. */
    fun commitBurst(nowMs: Long): Boolean {
        if (style != SwipeTrailStyle.FIREWORK || lastX.isNaN() || particleCount == 0) return false
        repeat(SwipeTrailFx.FIREWORK_COUNT) { spawn(lastX, lastY, nowMs) }
        return true
    }

    private fun spawn(x: Float, y: Float, t: Long) {
        if (particleCount == 0) return
        val i = cursor
        cursor = (cursor + 1) % particleCount
        px[i] = x; py[i] = y; pt0[i] = t; alive[i] = true
    }

    /**
     * Dựng hình học khung lúc [nowMs]; false = không còn nét để vẽ. Đang vuốt: chỉ điểm trong [TAIL_MS] gần
     * nhất (ngón đứng yên ⇒ vệt co lại rồi hết). Tia điện: mỗi lần dựng một seed (nhấp nháy, tất định theo seed).
     */
    fun build(nowMs: Long): Boolean {
        outN = 0
        if (size < 2) return false
        if (!active) {
            val f = (nowMs - fadeStart).toFloat() / FADE_MS
            if (f >= 1f) { size = 0; return false }
            strokeAlpha = 1f - f
        } else strokeAlpha = 1f
        val cutoff = (if (active) nowMs else fadeStart) - TAIL_MS
        var n = 0
        val first = (head - size + CAP) % CAP
        for (k in 0 until size) {
            val i = (first + k) % CAP
            if (ts[i] < cutoff) continue
            outX[n] = xs[i]; outY[n] = ys[i]; tt[n] = ts[i]
            n++
        }
        if (n < 2) return false
        when (style) {
            SwipeTrailStyle.ELECTRIC, SwipeTrailStyle.PLASMA -> jag(n)
            SwipeTrailStyle.BRUSH -> { brush(n); return true }
            else -> {}
        }
        outN = n
        return true
    }

    private fun jag(n: Int) {
        seed++
        val amp = ((if (style == SwipeTrailStyle.PLASMA) SwipeTrailFx.PLASMA_AMPLITUDE else SwipeTrailFx.ELECTRIC_AMPLITUDE) * density).toFloat()
        // Pháp tuyến tính trên điểm gốc: lưu bản gốc điểm trước khi dời.
        var prevX = outX[0]; var prevY = outY[0]
        for (k in 1 until n - 1) {
            val cx = outX[k]; val cy = outY[k]
            val dx = outX[k + 1] - prevX; val dy = outY[k + 1] - prevY
            val len = max(0.001f, sqrt(dx * dx + dy * dy))
            val o = (SwipeTrailFx.jitter(seed, k) * amp).toFloat()
            outX[k] = cx - dy / len * o; outY[k] = cy + dx / len * o
            prevX = cx; prevY = cy
        }
    }

    /** Dải kín: n điểm cạnh trái rồi n điểm cạnh phải (ngược) vào outX/outY (2n). */
    private fun brush(n: Int) {
        // Nửa bề rộng (px) mỗi điểm: tốc độ dp/ms → bề rộng → làm mượt → vuốt nhọn hai đầu.
        var w = SwipeTrailFx.BRUSH_MAX
        for (k in 0 until n) {
            if (k > 0) {
                val dx = (outX[k] - outX[k - 1]) / density; val dy = (outY[k] - outY[k - 1]) / density
                val dt = max(0.001, (tt[k] - tt[k - 1]).toDouble())
                w = SwipeTrailFx.brushSmooth(w, SwipeTrailFx.brushWidth(sqrt((dx * dx + dy * dy).toDouble()) / dt))
            }
            hw[k] = (w * SwipeTrailFx.brushTaperFactor(k, n) / 2 * density).toFloat()
        }
        for (k in 0 until n) {
            val a = max(0, k - 1); val b = min(n - 1, k + 1)
            val dx = outX[b] - outX[a]; val dy = outY[b] - outY[a]
            val len = max(0.001f, sqrt(dx * dx + dy * dy))
            val nx = -dy / len * hw[k]; val ny = dx / len * hw[k]
            outX[2 * n - 1 - k] = outX[k] - nx; outY[2 * n - 1 - k] = outY[k] - ny
            outX[k] += nx; outY[k] += ny
        }
        outN = 2 * n
    }

    /** Hạt [i] lúc [nowMs] vào [out] = (x, y, scale, alpha, rotation); false = không hiện (và được thu hồi). */
    fun particle(i: Int, nowMs: Long, out: FloatArray): Boolean {
        if (!alive[i]) return false
        val v = i % vCount
        val f = (nowMs - pt0[i]).toFloat() / trDur[v]
        if (f >= 1f || trDur[v] <= 0) { alive[i] = false; return false }
        if (f < 0f) return false
        val e = 1 - (1 - f) * (1 - f)           // easeOut
        out[0] = px[i] + trDx[v] * e + trSway[v] * sin(f * 2 * PI).toFloat()
        out[1] = py[i] + trDy[v] * e
        out[2] = trS0[v] + (trS1[v] - trS0[v]) * f
        out[3] = SwipeTrailFx.particleAlpha(style, f.toDouble()).toFloat()
        out[4] = trRot[v] * f
        return true
    }

    fun liveParticles(): Int { var n = 0; for (a in alive) if (a) n++; return n }

    /** Còn gì phải vẽ khung sau (đang vuốt / đang mờ / còn hạt)? false ⇒ View ngừng hẹn khung (0 animation). */
    fun isAnimating(nowMs: Long): Boolean {
        if (active && size > 0) return true
        if (!active && size > 1 && nowMs - fadeStart < FADE_MS) return true
        for (i in 0 until particleCount) if (alive[i]) {
            if (nowMs - pt0[i] < trDur[i % vCount]) return true
            alive[i] = false
        }
        return false
    }

    /** Dọn hết (ẩn bàn phím / đổi kiểu). */
    fun clear() { size = 0; active = false; java.util.Arrays.fill(alive, false); outN = 0 }

    companion object {
        const val CAP = 128
        const val TAIL_MS = 300L
        const val FADE_MS = 200L
    }
}
