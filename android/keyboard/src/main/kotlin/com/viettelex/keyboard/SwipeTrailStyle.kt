package com.viettelex.keyboard

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.atan2
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
    KALEIDOSCOPE("kaleidoscope", "Ảo ảnh"), // l10n-key
    MELT("melt", "Tan chảy"), // l10n-key
    CHROMA("chroma", "Vệt lặp"), // l10n-key
    KEYS("keys", "Phím sáng theo đường"), // l10n-key
    CALLIGRAPHY("calligraphy", "Thư pháp"), // l10n-key
    COMET("comet", "Sao chổi"), // l10n-key
    FIREFLY("firefly", "Đom đóm"), // l10n-key
    MATRIX("matrix", "Ma trận"), // l10n-key
    PETALS("petals", "Cánh hoa"), // l10n-key
    THEME("theme", "Theo giao diện"); // l10n-key

    val title: String get() = tr(viTitle)

    /** Tắt + Đơn giản miễn phí; còn lại (cả "Theo giao diện") thuộc Plus. */
    val isPlus: Boolean get() = this != NONE && this != SIMPLE

    /** Sinh hạt mỗi N điểm của đường vuốt (0 = không hạt dọc đường). */
    val spawnEvery: Int get() = when (this) {
        FIRE -> 3
        STARDUST -> 4
        PLASMA -> 5
        MELT -> 4
        FIREFLY -> 3
        MATRIX -> 3
        PETALS -> 4
        else -> 0
    }
    /** Có pool hạt (dọc đường hoặc chùm pháo hoa lúc nhấc tay). */
    val usesParticles: Boolean get() = spawnEvery > 0 || this == FIREWORK
    /** Cần khung phím chữ (setKeys lúc bắt đầu vuốt): Phím sáng theo đường (sáng phím), Ma trận (chữ của phím). */
    val usesKeys: Boolean get() = this == KEYS || this == MATRIX

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
            // Nhánh xoay (mảnh, mờ — nét thật vẫn dễ đọc) dưới nét thật tô bánh xe màu, lõi trắng trên cùng (= iOS).
            KALEIDOSCOPE -> listOf(SwipeTrailStroke(base * 0.6, 0x73FFFFFF, SwipeTrailStroke.Kind.MIRROR),
                SwipeTrailStroke(base * 1.3, 0xFFFFFFFF.toInt(), SwipeTrailStroke.Kind.CONIC),
                SwipeTrailStroke(base * 0.35, 0xD9FFFFFF.toInt()))
            // 3 đoạn cũ → mới ([SwipeTrailFx.MELT_SEGMENTS]): đoạn cũ mờ hơn. Màu + bề rộng đổi theo thời gian.
            MELT -> listOf(0.45, 0.75, 1.0).map {
                SwipeTrailStroke(base * 1.5, alpha(SwipeTrailFx.HUE_WHEEL[0], it), SwipeTrailStroke.Kind.MELT)
            }
            // 3 bóng đỏ / lục / lam lệch nhau ([SwipeTrailFx.chromaShift]) dưới nét chính màu vệt theme.
            CHROMA -> listOf(SwipeTrailStroke(base * 1.1, 0x99FF2D55.toInt(), SwipeTrailStroke.Kind.GHOST),
                SwipeTrailStroke(base * 1.1, 0x9930D158.toInt(), SwipeTrailStroke.Kind.GHOST),
                SwipeTrailStroke(base * 1.1, 0x990A84FF.toInt(), SwipeTrailStroke.Kind.GHOST),
                SwipeTrailStroke(base * 0.6, trail))
            // Nét rất mờ — phím sáng ([SwipeTrailFx.keyGlowAlpha]) mới là chính (= iOS).
            KEYS -> listOf(SwipeTrailStroke(base * 0.35, alpha(a, 0.3)))
            // Mực đậm nền sáng / mực sáng nền tối; bề rộng theo tốc độ × ngòi xiên ([SwipeTrailFx.calliWidth]).
            CALLIGRAPHY -> listOf(SwipeTrailStroke(0.0, if (dark) 0xF0EEE8DC.toInt() else 0xF0141210.toInt(), SwipeTrailStroke.Kind.FILL))
            // 4 đoạn cũ → mới: mảnh + màu nhấn mờ ở đuôi → dày + trắng ở đầu; rồi quầng + lõi đầu (= iOS).
            COMET -> List(4) { i ->
                SwipeTrailStroke(base * SwipeTrailFx.COMET_WIDTHS[i],
                    alpha(SwipeTrailFx.mix(a, 0xFFFFFF, SwipeTrailFx.COMET_WHITE[i]), SwipeTrailFx.COMET_ALPHA[i]),
                    SwipeTrailStroke.Kind.SEGMENT)
            } + listOf(SwipeTrailStroke(base * 4.4, alpha(a, 0.28), SwipeTrailStroke.Kind.HEAD),
                SwipeTrailStroke(base * 1.5, 0xFFFFFFFF.toInt(), SwipeTrailStroke.Kind.HEAD))
            FIREFLY -> listOf(SwipeTrailStroke(base * 0.3, 0x40D8FF5A))
            MATRIX -> listOf(SwipeTrailStroke(base * 1.2, 0x2600FF66), SwipeTrailStroke(base * 0.35, 0xD900E05A.toInt()))
            PETALS -> listOf(SwipeTrailStroke(base * 0.5, 0x59F58FB1))
        }
    }

    /** Màu hạt (RGB) — hạt i dùng màu i % size. */
    fun particleColors(accent: Int): IntArray = when (this) {
        FIRE -> intArrayOf(0xFFC21A, 0xFF7A1A, 0xFF3B30)
        STARDUST -> intArrayOf(0xFFC93C, accent and 0xFFFFFF, 0xFFE7A0)
        FIREWORK -> intArrayOf(accent and 0xFFFFFF, 0xFFC93C, 0xFF5E7E, 0x4FC3F7)
        PLASMA -> intArrayOf(0xB44CFF, 0xE0B0FF, 0xF3E0FF)
        MELT -> intArrayOf(SwipeTrailFx.HUE_WHEEL[0], SwipeTrailFx.HUE_WHEEL[2], SwipeTrailFx.HUE_WHEEL[4])
        FIREFLY -> intArrayOf(0xD8FF5A, 0xF2FF8A, 0xB6F23A)
        MATRIX -> intArrayOf(0x3DFF6E, 0x00E05A, 0xB6FFC8)
        PETALS -> intArrayOf(0xF58FB1, 0xFFC8DA, 0xF7A8C4)   // hồng sen + hồng nhạt
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
    /**
     * CONIC = nét tô bánh xe màu (Ảo ảnh), MIRROR = nhánh xoay quanh tâm vùng phím (Ảo ảnh), MELT = một đoạn nét
     * Tan chảy (thứ tự = đoạn trong MELT_SEGMENTS), GHOST = bóng lệch màu (Vệt lặp, thứ tự = CHROMA_ANGLES),
     * SEGMENT = một đoạn Sao chổi (thứ tự = đoạn trong COMET_SEGMENTS), HEAD = chấm tròn ở đầu ngón (Sao chổi,
     * width = đường kính; không dùng Path chung). = iOS.
     */
    enum class Kind { STROKE, FILL, GRADIENT, CONIC, MIRROR, MELT, GHOST, SEGMENT, HEAD }
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
    /** Sống lâu nhất của hạt (giây) — Đom đóm sống tới 1,2 s. */
    const val MAX_PARTICLE_LIFE = 1.25
    /** Cầu vồng: mốc màu (RGB), lặp 2 vòng. */
    val RAINBOW = intArrayOf(0xFF3B30, 0xFF9500, 0xFFCC00, 0x34C759, 0x00C7BE, 0x007AFF, 0xAF52DE,
        0xFF3B30, 0xFF9500, 0xFFCC00, 0x34C759, 0x00C7BE, 0x007AFF, 0xAF52DE)

    /** Bánh xe màu (RGB) — Ảo ảnh (gradient quét quanh tâm) + Tan chảy (đổi màu theo thời gian). Mốc cuối = đầu. */
    val HUE_WHEEL = intArrayOf(0xFF4D6D, 0xFFB84D, 0xE8FF4D, 0x4DFF88, 0x4DD8FF, 0x6B5BFF, 0xE04DFF, 0xFF4D6D)
    /** Ảo ảnh: số nhánh đối xứng xoay (gồm nét thật) quanh TÂM VÙNG PHÍM; một vòng xoay bánh xe màu (giây). */
    const val KALEIDO_BRANCHES = 6
    const val KALEIDO_HUE_PERIOD = 4.0
    /** Tan chảy: vòng màu (giây), chu kỳ + biên độ "thở", đuôi chảy xuống tối đa (dp), mốc 3 đoạn theo chiều dài. */
    const val MELT_HUE_PERIOD = 6.0
    const val MELT_BREATH_PERIOD = 1.2
    const val MELT_BREATH_AMP = 0.3
    const val MELT_DRIP = 7.0
    val MELT_SEGMENTS = doubleArrayOf(0.0, 0.35, 0.7, 1.0)
    /** Vệt lặp: lệch lúc vuốt / lúc tan hẳn (dp), thời gian trôi + mờ sau nhấc tay (giây), hướng từng bóng (độ). */
    const val CHROMA_OFFSET = 2.5
    const val CHROMA_DRIFT = 8.0
    const val CHROMA_FADE = 0.45
    val CHROMA_ANGLES = doubleArrayOf(-90.0, 30.0, 150.0)

    /** Đuôi nét (giây): Sao chổi dài gấp đôi, kiểu khác 0,3 s như vệt cũ (= iOS tail). */
    const val COMET_TAIL = 0.6
    fun tail(s: SwipeTrailStyle): Double = if (s == SwipeTrailStyle.COMET) COMET_TAIL else 0.3
    /** Sao chổi: mốc 4 đoạn theo chiều dài (cũ → mới), bề rộng (× base), độ pha trắng, độ đậm từng đoạn. */
    val COMET_SEGMENTS = doubleArrayOf(0.0, 0.4, 0.7, 0.88, 1.0)
    val COMET_WIDTHS = doubleArrayOf(0.45, 0.8, 1.15, 1.5)
    val COMET_WHITE = doubleArrayOf(0.0, 0.25, 0.6, 1.0)
    val COMET_ALPHA = doubleArrayOf(0.3, 0.55, 0.8, 1.0)

    /** Phím sáng theo đường: tắt dần sau khi rời phím (giây), số ô sáng tối đa, nới khung khi dò (dp), bo góc (dp). */
    const val KEY_GLOW_FADE = 0.35
    const val KEY_GLOW_CAP = 12
    const val KEY_GLOW_SLOP = 2.0
    const val KEY_GLOW_CORNER = 6.0
    /** Độ sáng của phím đã rời được [s] giây (≤ 0 = ngón còn trong phím): tắt tuyến tính trong KEY_GLOW_FADE. */
    fun keyGlowAlpha(s: Double): Double = if (s <= 0) 1.0 else max(0.0, 1 - s / KEY_GLOW_FADE)
    /**
     * Phím dưới điểm (x, y) (đã trừ độ dời điểm chọn phím): khung nới [slop] chứa điểm; nhiều khung ⇒ tâm gần
     * nhất. −1 = không phím nào. Không cấp phát. = iOS keyHit (slop = KEY_GLOW_SLOP · density).
     */
    fun keyHit(x: Float, y: Float, left: FloatArray, top: FloatArray, right: FloatArray, bottom: FloatArray, n: Int,
               slop: Float = KEY_GLOW_SLOP.toFloat()): Int {
        var best = -1; var bestD = Float.MAX_VALUE
        for (i in 0 until n) {
            if (x < left[i] - slop || x > right[i] + slop || y < top[i] - slop || y > bottom[i] + slop) continue
            val cx = (left[i] + right[i]) / 2 - x; val cy = (top[i] + bottom[i]) / 2 - y
            val d = cx * cx + cy * cy
            if (d < bestD) { bestD = d; best = i }
        }
        return best
    }

    /** Thư pháp: góc ngòi (độ), bề rộng tối thiểu dọc ngòi, hệ số dày so với Bút lông, mực đọng tối đa (dp) + tốc độ hết đọng (dp/ms). */
    const val NIB_ANGLE = 35.0
    const val NIB_MIN = 0.3
    const val CALLI_SCALE = 1.25
    const val CALLI_POOL_MAX = 4.0
    const val CALLI_POOL_SPEED = 0.25
    /** Ngòi xiên: nét vuông góc với ngòi dày nhất, dọc theo ngòi mảnh nhất (NIB_MIN). Hướng (0, 0) ⇒ 1. */
    fun nibFactor(dx: Double, dy: Double): Double {
        if (dx == 0.0 && dy == 0.0) return 1.0
        return NIB_MIN + (1 - NIB_MIN) * abs(sin(atan2(dy, dx) - NIB_ANGLE * PI / 180))
    }
    /** Mực đọng (dp cộng thêm) theo tốc độ (dp/ms). */
    fun calliPool(speed: Double): Double = CALLI_POOL_MAX * max(0.0, 1 - max(0.0, speed) / CALLI_POOL_SPEED)
    /** Bề rộng nét thư pháp: Bút lông × CALLI_SCALE × ngòi + mực đọng. = iOS calliWidth. */
    fun calliWidth(speed: Double, dx: Double, dy: Double): Double =
        brushWidth(speed) * CALLI_SCALE * nibFactor(dx, dy) + calliPool(speed)
    /** Dấu triện đỏ lúc nhấc tay: cạnh (dp), bo góc, đời (giây), màu son (RGB), nghiêng (độ). */
    const val SEAL_SIZE = 15.0
    const val SEAL_CORNER = 3.5
    const val SEAL_LIFE = 0.9
    const val SEAL_COLOR = 0xD1352B
    const val SEAL_TILT = -8.0
    /** Đóng dấu: phóng → 1 rồi giữ; hiện nhanh, giữ, mờ dần (= keyframes CA iOS). */
    val SEAL_SCALE_T = doubleArrayOf(0.0, 0.15, 1.0); val SEAL_SCALE_V = doubleArrayOf(1.35, 1.0, 1.0)
    val SEAL_ALPHA_T = doubleArrayOf(0.0, 0.08, 0.6, 1.0); val SEAL_ALPHA_V = doubleArrayOf(0.0, 1.0, 1.0, 0.0)
    /** Nét khắc trắng (đơn vị = cạnh dấu, tâm 0): khung trong (nửa cạnh SEAL_INSET) + mỗi 4 số = (x0, y0, x1, y1). */
    const val SEAL_INSET = 0.36
    val SEAL_MARKS = doubleArrayOf(-0.24, -0.2, -0.02, -0.2, -0.24, 0.0, -0.02, 0.0, -0.24, 0.2, -0.02, 0.2,
        0.13, -0.24, 0.13, 0.24, 0.13, -0.02, 0.26, 0.12)
    /** Nội suy tuyến tính theo mốc (= CAKeyframeAnimation linear). f ngoài 0…1 ⇒ mốc biên. */
    fun keyframe(f: Double, t: DoubleArray, v: DoubleArray): Double {
        if (v.isEmpty()) return 0.0
        if (f <= t[0]) return v[0]
        for (k in 1 until t.size) if (f <= t[k]) {
            val u = (f - t[k - 1]) / max(1e-9, t[k] - t[k - 1])
            return v[k - 1] + (v[k] - v[k - 1]) * u
        }
        return v[v.size - 1]
    }

    /** Đom đóm: nhịp sáng (= opacity keyframes iOS). */
    val FIREFLY_PULSE_T = doubleArrayOf(0.0, 0.15, 0.35, 0.5, 0.7, 0.85, 1.0)
    val FIREFLY_PULSE_V = doubleArrayOf(0.0, 1.0, 0.35, 0.95, 0.3, 0.7, 0.0)

    /** Ma trận: bảng chữ rơi (a–z rồi 0–9) — chuỗi 1 ký tự dựng sẵn để vẽ không cấp phát. */
    const val MATRIX_GLYPHS = "abcdefghijklmnopqrstuvwxyz0123456789"
    /**
     * Chữ thứ [n] (đếm hạt đã bắn trong cú vuốt): cứ 3 chữ có 1 chữ số; còn lại = chữ của phím đang đi qua
     * ([key] = 0 ⇒ không có; không phải a–z ⇒ chữ số). Trả chỉ số trong MATRIX_GLYPHS. = iOS matrixGlyph.
     */
    fun matrixGlyph(n: Int, key: Char): Int {
        val digit = 26 + ((n * 7) % 10 + 10) % 10
        if (n % 3 == 2) return digit
        val c = if (key in 'A'..'Z') key + 32 else key
        return if (c in 'a'..'z') c - 'a' else digit
    }

    /** Màu bánh xe ở tỉ lệ f (vòng tròn: lấy phần lẻ) — nội suy tuyến tính giữa các mốc (= keyframes CA iOS). */
    fun cycleColor(f: Double): Int {
        val n = HUE_WHEEL.size - 1
        var u = f - kotlin.math.floor(f)
        if (u < 0) u += 1
        val x = u * n
        val k = min(n - 1, x.toInt())
        return mix(HUE_WHEEL[k], HUE_WHEEL[k + 1], x - k)
    }
    /** Hệ số bề rộng Tan chảy ở pha (số chu kỳ thở đã qua): 1 ± MELT_BREATH_AMP, hình sin. */
    fun meltBreath(phase: Double): Double = 1 + MELT_BREATH_AMP * sin(2 * PI * phase)
    /** Độ chảy xuống (dp) của điểm có tuổi u = tuổi / đuôi (0 = mới nhất, 1 = sắp hết): bậc hai. */
    fun meltSag(u: Double): Double { val x = min(1.0, max(0.0, u)); return MELT_DRIP * x * x }
    /**
     * Độ lệch bóng [i] (dp) ở tiến độ trôi [e] (0 = đang vuốt, 1 = tan hẳn; đã qua easeOut) — = iOS chromaShift,
     * tách x / y để vẽ mỗi khung không cấp phát.
     */
    fun chromaShiftX(i: Int, e: Double): Double = cos(chromaAngle(i)) * chromaDist(e)
    fun chromaShiftY(i: Int, e: Double): Double = sin(chromaAngle(i)) * chromaDist(e)
    private fun chromaDist(e: Double) = CHROMA_OFFSET + (CHROMA_DRIFT - CHROMA_OFFSET) * min(1.0, max(0.0, e))
    private fun chromaAngle(i: Int) = CHROMA_ANGLES[i % CHROMA_ANGLES.size] * PI / 180

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
        SwipeTrailStyle.MELT -> 6
        SwipeTrailStyle.FIREFLY -> 6
        SwipeTrailStyle.MATRIX -> 6
        SwipeTrailStyle.PETALS -> 8
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
            // giọt nhỏ khỏi nét, rơi xuống rồi tan (= iOS)
            SwipeTrailStyle.MELT -> KeyEffectTrajectory(t * 2, 10 + (v % 3) * 4.0, 1.0, 0.3, 0.0, 0.6 + (v % 3) * 0.08)
            // trôi chậm lên, lượn nhẹ, nhịp sáng rồi tắt (= iOS)
            SwipeTrailStyle.FIREFLY -> KeyEffectTrajectory(t * 6, -(4 + (v % 3) * 3.0), 0.7, 1.0, 0.0,
                1.0 + (v % 3) * 0.1, sway = 2.5)
            // chữ rơi thẳng xuống một đoạn ngắn rồi tắt (= iOS)
            SwipeTrailStyle.MATRIX -> KeyEffectTrajectory(0.0, 14 + (v % 3) * 5.0, 1.0, 1.0, 0.0, 0.7 + (v % 3) * 0.08)
            // cánh hoa rơi chậm, đung đưa, xoay (= iOS)
            SwipeTrailStyle.PETALS -> KeyEffectTrajectory(t * 10, 18 + (v % 3) * 6.0, 1.0, 0.75, t * 2.4,
                0.95 + (v % 3) * 0.08, sway = 5.0)
            else ->KeyEffectTrajectory(0.0, 0.0, 1.0, 1.0, 0.0, 0.0)
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
        if (s == SwipeTrailStyle.FIREFLY) return keyframe(f, FIREFLY_PULSE_T, FIREFLY_PULSE_V)
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
    /** Tiến độ mờ sau nhấc tay theo [fadeMs] (0 khi đang vuốt) — bóng Vệt lặp trôi + mờ theo số này. */
    var fadeFrac = 0f
        private set
    /** Mờ hẳn sau nhấc tay (ms): Vệt lặp để bóng tan chậm hơn nét chính; kiểu khác = [FADE_MS]. */
    val fadeMs: Long = if (style == SwipeTrailStyle.CHROMA) (SwipeTrailFx.CHROMA_FADE * 1000).toLong() else FADE_MS
    /** Đuôi nét (ms): Sao chổi 600, kiểu khác [TAIL_MS] (= iOS SwipeTrailFx.tail). */
    val tailMs: Long = (SwipeTrailFx.tail(style) * 1000).toLong()
    /** Mốc thời gian của cú vuốt (điểm đầu) — màu / thở theo thời gian tính từ đây (iOS: animation gắn lúc begin). */
    private var startMs = -1L
    private val hw = FloatArray(CAP)
    private val tt = LongArray(CAP)
    /** Tan chảy: chiều dài cộng dồn (px) tới điểm k của hình học khung — để chia đoạn theo chiều dài như iOS strokeStart. */
    private val cum = FloatArray(CAP)

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
    /** Ma trận: chữ (chỉ số MATRIX_GLYPHS) của từng hạt + số chữ đã bắn trong cú vuốt. */
    private val pglyph = IntArray(if (style == SwipeTrailStyle.MATRIX) particleCount else 0)
    private var spawned = 0

    // Phím sáng theo đường / Ma trận: khung phím chữ (px, toạ độ view) nhận lúc bắt đầu vuốt — mảng cố định.
    private val usesKeys = style.usesKeys
    private val kl = FloatArray(if (usesKeys) KEY_CAP else 0)
    private val kt = FloatArray(kl.size)
    private val kr = FloatArray(kl.size)
    private val kb = FloatArray(kl.size)
    private val kc = CharArray(kl.size)
    var keyCount = 0
        private set
    private var hitDy = 0f
    /** Phím ngón đang ở (−1 = không). */
    var currentKey = -1
        private set
    // Ô sáng: phím + lúc rời (Long.MAX_VALUE = ngón còn trong phím).
    val glowCount: Int = if (style == SwipeTrailStyle.KEYS) SwipeTrailFx.KEY_GLOW_CAP else 0
    private val gKey = IntArray(glowCount) { -1 }
    private val gLeave = LongArray(glowCount)
    private var gCursor = 0
    private var curGlow = -1
    private val glowFadeMs = (SwipeTrailFx.KEY_GLOW_FADE * 1000).toLong()

    // Thư pháp: dấu triện ở chỗ nhấc tay (lúc đóng; −1 = không có).
    private var sealX = 0f
    private var sealY = 0f
    private var sealT0 = -1L
    private val sealMs = (SwipeTrailFx.SEAL_LIFE * 1000).toLong()

    init {
        for (v in 0 until vCount) {
            val t = SwipeTrailFx.trajectory(style, v)
            trDx[v] = (t.dx * density).toFloat(); trDy[v] = (t.dy * density).toFloat()
            trS0[v] = t.scaleFrom.toFloat(); trS1[v] = t.scaleTo.toFloat()
            trRot[v] = t.rotation.toFloat(); trDur[v] = (t.duration * 1000).toLong(); trSway[v] = (t.sway * density).toFloat()
        }
    }

    fun begin() {
        size = 0; head = 0; active = true; fadeStart = 0L; strokeAlpha = 1f; fadeFrac = 0f; spawner.reset(); lastX = Float.NaN
        startMs = -1L
        currentKey = -1; curGlow = -1; spawned = 0
    }

    /**
     * Khung phím chữ thứ [i] (px, toạ độ view) — gọi lúc BẮT ĐẦU cú vuốt cho kiểu [SwipeTrailStyle.usesKeys]
     * (kiểu khác: 0 việc). [count] = số phím, [hitDy] = độ dời điểm chọn phím (dò ở y − hitDy như bộ giải mã).
     */
    fun setKey(i: Int, left: Float, top: Float, right: Float, bottom: Float, ch: Char) {
        if (i !in kl.indices) return
        kl[i] = left; kt[i] = top; kr[i] = right; kb[i] = bottom; kc[i] = ch
    }
    fun setKeyCount(count: Int, hitDy: Float) {
        keyCount = count.coerceIn(0, kl.size); this.hitDy = hitDy; currentKey = -1
    }
    fun keyLeft(k: Int) = kl[k]
    fun keyTop(k: Int) = kt[k]
    fun keyRight(k: Int) = kr[k]
    fun keyBottom(k: Int) = kb[k]

    /** Phím dưới ngón (dò ≤ KEY_CAP khung, không cấp phát). Đổi phím: ô cũ bắt đầu mờ, ô mới sáng. */
    private fun trackKey(x: Float, y: Float, t: Long) {
        val k = SwipeTrailFx.keyHit(x, y - hitDy, kl, kt, kr, kb, keyCount, (SwipeTrailFx.KEY_GLOW_SLOP * density).toFloat())
        if (k == currentKey) return
        currentKey = k
        if (glowCount == 0) return
        releaseGlow(t)
        if (k >= 0) {
            val i = gCursor
            gCursor = (gCursor + 1) % glowCount
            gKey[i] = k; gLeave[i] = Long.MAX_VALUE
            curGlow = i
        }
    }

    private fun releaseGlow(t: Long) {
        if (curGlow >= 0) { gLeave[curGlow] = t; curGlow = -1 }
    }

    /** Ô sáng [i] lúc [nowMs]: phím (chỉ số setKey), −1 = không hiện. Độ sáng vào [alphaOut][0]. */
    fun glow(i: Int, nowMs: Long, alphaOut: FloatArray): Int {
        val k = gKey[i]
        if (k < 0 || k >= keyCount) return -1
        val leave = gLeave[i]
        val a = if (leave == Long.MAX_VALUE) 1.0 else SwipeTrailFx.keyGlowAlpha((nowMs - leave) / 1000.0)
        if (a <= 0.0) { gKey[i] = -1; return -1 }
        alphaOut[0] = a.toFloat()
        return k
    }

    /** Dấu triện lúc [nowMs] vào [out] = (x, y, scale, alpha); false = không hiện. */
    fun seal(nowMs: Long, out: FloatArray): Boolean {
        if (sealT0 < 0) return false
        val f = (nowMs - sealT0).toDouble() / sealMs
        if (f >= 1.0) { sealT0 = -1L; return false }
        if (f < 0.0) return false
        out[0] = sealX; out[1] = sealY
        out[2] = SwipeTrailFx.keyframe(f, SwipeTrailFx.SEAL_SCALE_T, SwipeTrailFx.SEAL_SCALE_V).toFloat()
        out[3] = SwipeTrailFx.keyframe(f, SwipeTrailFx.SEAL_ALPHA_T, SwipeTrailFx.SEAL_ALPHA_V).toFloat()
        return true
    }

    /** Ma trận: chữ (chỉ số MATRIX_GLYPHS) của hạt [i]. */
    fun glyph(i: Int): Int = if (i in pglyph.indices) pglyph[i] else 26

    /** Giây đã qua từ đầu cú vuốt (0 nếu chưa có điểm). */
    fun elapsed(nowMs: Long): Double = if (startMs < 0) 0.0 else max(0L, nowMs - startMs) / 1000.0

    fun add(x: Float, y: Float, tMs: Long) {
        if (!active) return
        if (startMs < 0) startMs = tMs
        xs[head] = x; ys[head] = y; ts[head] = tMs
        head = (head + 1) % CAP
        if (size < CAP) size++
        lastX = x; lastY = y
        if (usesKeys && keyCount > 0) trackKey(x, y, tMs)
        if (spawner.tick()) {
            if (pglyph.isNotEmpty()) {
                pglyph[cursor] = SwipeTrailFx.matrixGlyph(spawned, if (currentKey >= 0) kc[currentKey] else 0.toChar())
                spawned++
            }
            spawn(x, y, tMs)
        }
    }

    /** Nhấc tay (mờ dần) hoặc huỷ ([fade] = false: xoá nét ngay). Hạt bay nốt. */
    fun end(fade: Boolean, nowMs: Long) {
        if (!active && size == 0) return
        active = false
        if (fade && size > 1) fadeStart = nowMs else size = 0
        if (fade) releaseGlow(nowMs) else { curGlow = -1; java.util.Arrays.fill(gKey, -1) }
        currentKey = -1
        // Thư pháp: đóng dấu son ở chỗ nhấc tay.
        if (fade && style == SwipeTrailStyle.CALLIGRAPHY && !lastX.isNaN()) { sealX = lastX; sealY = lastY; sealT0 = nowMs }
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
            val gone = nowMs - fadeStart
            if (gone >= fadeMs) { size = 0; return false }
            strokeAlpha = max(0f, 1f - gone.toFloat() / FADE_MS)
            fadeFrac = gone.toFloat() / fadeMs
        } else { strokeAlpha = 1f; fadeFrac = 0f }
        val ref = if (active) nowMs else fadeStart
        val cutoff = ref - tailMs
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
            SwipeTrailStyle.BRUSH -> { brush(n, false); return true }
            SwipeTrailStyle.CALLIGRAPHY -> { brush(n, true); return true }
            SwipeTrailStyle.MELT -> melt(n, ref)
            SwipeTrailStyle.COMET -> lengths(n)
            else -> {}
        }
        outN = n
        return true
    }

    /** Tan chảy: điểm càng cũ càng chảy xuống ([SwipeTrailFx.meltSag]); rồi chiều dài cộng dồn để chia đoạn. */
    private fun melt(n: Int, ref: Long) {
        for (k in 0 until n) outY[k] += (SwipeTrailFx.meltSag((ref - tt[k]).toDouble() / tailMs) * density).toFloat()
        lengths(n)
    }

    /** Chiều dài cộng dồn (px) — chia đoạn theo chiều dài (Tan chảy, Sao chổi; = iOS strokeStart / strokeEnd). */
    private fun lengths(n: Int) {
        cum[0] = 0f
        for (k in 1 until n) {
            val dx = outX[k] - outX[k - 1]; val dy = outY[k] - outY[k - 1]
            cum[k] = cum[k - 1] + sqrt(dx * dx + dy * dy)
        }
    }

    /**
     * Tan chảy: vị trí (chỉ số thực, 0…outN−1) ở tỉ lệ chiều dài [frac] của nét khung hiện tại — View dựng đoạn
     * [MELT_SEGMENTS][i]…[i+1] từ hai mốc này (= iOS strokeStart / strokeEnd).
     */
    fun cut(frac: Double): Float {
        val n = outN
        if (n < 2) return 0f
        val total = cum[n - 1]
        if (total <= 0f) return (frac * (n - 1)).toFloat()
        val goal = (min(1.0, max(0.0, frac)) * total).toFloat()
        var k = 1
        while (k < n - 1 && cum[k] < goal) k++
        val seg = cum[k] - cum[k - 1]
        return if (seg <= 0f) k.toFloat() else (k - 1) + ((goal - cum[k - 1]) / seg).coerceIn(0f, 1f)
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

    /**
     * Dải kín: n điểm cạnh trái rồi n điểm cạnh phải (ngược) vào outX/outY (2n). [calli] = Thư pháp: bề rộng
     * còn theo hướng nét (ngòi xiên) + mực đọng ở chỗ chậm ([SwipeTrailFx.calliWidth]) — = iOS buildBrush.
     */
    private fun brush(n: Int, calli: Boolean) {
        // Nửa bề rộng (px) mỗi điểm: tốc độ dp/ms → bề rộng → làm mượt → vuốt nhọn hai đầu.
        var w = SwipeTrailFx.BRUSH_MAX
        for (k in 0 until n) {
            if (k > 0) {
                val dx = (outX[k] - outX[k - 1]) / density; val dy = (outY[k] - outY[k - 1]) / density
                val dt = max(0.001, (tt[k] - tt[k - 1]).toDouble())
                val v = sqrt((dx * dx + dy * dy).toDouble()) / dt
                w = SwipeTrailFx.brushSmooth(w, if (calli) SwipeTrailFx.calliWidth(v, dx.toDouble(), dy.toDouble())
                    else SwipeTrailFx.brushWidth(v))
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

    /** Còn gì phải vẽ khung sau (đang vuốt / đang mờ / còn hạt / ô sáng / dấu triện)? false ⇒ View ngừng hẹn khung. */
    fun isAnimating(nowMs: Long): Boolean {
        if (active && size > 0) return true
        if (!active && size > 1 && nowMs - fadeStart < fadeMs) return true
        if (sealT0 >= 0) { if (nowMs - sealT0 < sealMs) return true; sealT0 = -1L }
        for (i in 0 until glowCount) if (gKey[i] >= 0) {
            if (gLeave[i] == Long.MAX_VALUE || nowMs - gLeave[i] < glowFadeMs) return true
            gKey[i] = -1
        }
        for (i in 0 until particleCount) if (alive[i]) {
            if (nowMs - pt0[i] < trDur[i % vCount]) return true
            alive[i] = false
        }
        return false
    }

    /** Dọn hết (ẩn bàn phím / đổi kiểu). */
    fun clear() {
        size = 0; active = false; java.util.Arrays.fill(alive, false); outN = 0
        java.util.Arrays.fill(gKey, -1); curGlow = -1; currentKey = -1; sealT0 = -1L
    }

    /** Số ô sáng đang hiện (test). */
    fun litGlows(nowMs: Long): Int { val a = FloatArray(1); var n = 0; for (i in 0 until glowCount) if (glow(i, nowMs, a) >= 0) n++; return n }

    companion object {
        const val CAP = 128
        const val TAIL_MS = 300L
        const val FADE_MS = 200L
        /** Trần số phím chữ nhận cho Phím sáng theo đường / Ma trận (bàn chữ ≤ ~33 phím). */
        const val KEY_CAP = 48
    }
}
