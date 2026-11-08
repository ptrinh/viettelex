package com.viettelex.keyboard

import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.sin

/**
 * "Hiệu ứng khi bấm phím" (Plus, Phil 19/10/2026) — THUẦN, song sinh
 * iOS/Keyboard/KeyEffects.swift: cùng khoá [Keys.KEY_EFFECT] (`keyEffect`), cùng id, cùng quỹ đạo.
 * "Không" (mặc định) ⇒ IME không tạo overlay (0 chi phí). Bật: chữ chèn TRƯỚC, overlay
 * (app/.../ime/KeyEffectView) vẽ ở lượt sau; ≤ [KeyEffectPool.CAP] hạt, mảng cấp sẵn — không cấp
 * phát mỗi khung hình. Tự tắt khi Trình tiết kiệm pin ([KeyEffectPolicy]).
 */
enum class KeyEffect(val id: String, val viTitle: String) {
    NONE("none", "Không"), // l10n-key
    HEART("heart", "Trái tim"), // l10n-key
    BUBBLE("bubble", "Bong bóng"), // l10n-key
    RIPPLE("ripple", "Gợn sóng"), // l10n-key
    PETAL("petal", "Cánh hoa"), // l10n-key
    FIREWORK("firework", "Pháo hoa"), // l10n-key
    FLASH("flash", "Nháy sáng"), // l10n-key
    MATRIX("matrix", "Matrix"), // l10n-key
    LIGHTNING("lightning", "Tia sét"), // l10n-key
    EMOJIWORD("emojiword", "Emoji theo chữ"), // l10n-key
    BLOSSOM("blossom", "Hoa đào / mai"), // l10n-key
    COMBO("combo", "Lửa combo"), // l10n-key
    INK("ink", "Mực loang"), // l10n-key
    WAVE("wave", "Sóng nước"), // l10n-key
    SNOW("snow", "Tuyết rơi"), // l10n-key
    // Bộ đủ món (theme Vũ trụ, 10/2026). Chỉ thêm CUỐI (id sao lưu / theme JSON).
    METEOR("meteor", "Sao băng"), // l10n-key
    // Bộ theme đủ món 10/2026: đốm sáng mềm dựng sẵn ([GlowSprite]) — Trung Thu, Halloween.
    LANTERN("lantern", "Đèn lồng"), // l10n-key
    SMOKE("smoke", "Sương ma"), // l10n-key
    // Theme Ghi-ta (10/2026): đoạn dây ở khe hàng gần phím rung sóng dừng rồi đứng yên ([StringPluck]).
    STRING("string", "Rung dây"), // l10n-key
    // Đợt 3 (11/2026): tia plasma nối phím, rung combo, laser từ phím cách, glitch, dấu thanh, từ khoá (pháo đỏ / lì xì).
    PLASMA("plasma", "Plasma"), // l10n-key
    SHAKE("shake", "Rung combo"), // l10n-key
    LASER("laser", "Laser"), // l10n-key
    GLITCH("glitch", "Glitch"), // l10n-key
    TONE("tone", "Dấu thanh"), // l10n-key
    KEYWORD("keyword", "Từ khoá"), // l10n-key
    LETTERS("letters", "Chữ bay"), // l10n-key
    SAND("sand", "Hạt cát"), // l10n-key
    // Theme Biển (11/2026): sóng vỗ bờ + bọt bắn + bong bóng + cá bơi khi combo ([SeaFx]).
    SEA("sea", "Biển"), // l10n-key
    // Theme "AI" (11/2026): chữ vừa ra vỡ thành vài "token" phát sáng bay vào thanh gợi ý ([TokenStream]).
    TOKENS("tokens", "Token AI"), // l10n-key
    // Theme Neon Night Club (11/2026): Sàn nhảy LED — phím vừa bấm + các phím quanh thắp neon thành vòng vuông lan ra.
    DANCEFLOOR("dancefloor", "Sàn nhảy LED"), // l10n-key
    // Theme Gõ mõ / Kính màu (11/2026): Công đức ("+1 công đức" bay lên + đếm trong ngày), Nắng qua kính (ô kính sáng lên
    // + tia nắng chéo, gõ dồn ⇒ ánh nến mép dưới) — [MeritFx], [SunlightFx].
    MERIT("merit", "Công đức"), // l10n-key
    SUNLIGHT("sunlight", "Nắng qua kính"); // l10n-key

    val title: String get() = tr(viTitle)

    /** Mọi kiểu trừ "Không" thuộc Plus. */
    val isPlus: Boolean get() = this != NONE

    /** Kiểu "hạt bay ra từ phím" (quỹ đạo [trajectory]). */
    val isParticle: Boolean get() = this in PARTICLES

    /** Chỉ bắn khi IME xếp sẵn sự kiện (từ vừa chốt / dấu vừa bỏ): phím thường không hẹn vẽ gì. = iOS isQueued. */
    val isQueued: Boolean get() = this == EMOJIWORD || this == TONE || this == KEYWORD || this == LETTERS || this == TOKENS

    /** IME phải so từ đang soạn trước/sau phím (dấu vừa bỏ / chữ vừa ra) — kiểu khác: không đọc gì. = iOS needsComposeDiff. */
    val needsComposeDiff: Boolean get() = this == TONE || this == LETTERS || this == TOKENS

    /** IME phải ghi từ vừa chốt ở ranh giới (tra bảng). = iOS needsBoundaryWord. */
    val needsBoundaryWord: Boolean get() = this == EMOJIWORD || this == KEYWORD

    /** Hạt là ẢNH đốm sáng mềm dựng sẵn ([GlowSprite]), không path: Đèn lồng, Sương ma. = iOS usesGlow. */
    val usesGlow: Boolean get() = this == LANTERN || this == SMOKE

    /** Dải z: Matrix / Mực loang / Sóng nước vẽ trên nền nhưng DƯỚI phím. */
    val band: KeyEffectBand get() = when (this) {
        MATRIX, INK, WAVE, STRING -> KeyEffectBand.BELOW_KEYS
        else -> KeyEffectBand.ABOVE_KEYS
    }

    /** Màu cố định (RGB, không theo màu nhấn) — hạt i dùng màu i % size. Rỗng = màu nhấn. = iOS fixedColors. */
    val fixedColors: IntArray get() = when (this) {
        BLOSSOM -> intArrayOf(0xFF8FB1, 0xFFC93C)
        COMBO -> intArrayOf(0xFF7A1A, 0xFFC21A, 0xFF3B30)
        SNOW -> intArrayOf(0xFFFFFF)
        METEOR -> intArrayOf(MeteorStreak.COLOR)
        MATRIX -> intArrayOf(MatrixRain.GREEN)
        LANTERN -> intArrayOf(0xFFA03C, 0xFFD27A)
        SMOKE -> intArrayOf(0xA594C8, 0x8B7BAA, 0xC2B8D6)
        else -> IntArray(0)
    }

    /** Số hạt mỗi lần bấm (Lửa combo: tối đa — mức combo quyết định số hạt thật). */
    val particlesPerTap: Int get() = when (this) {
        HEART, BUBBLE, PETAL, BLOSSOM, COMBO -> 3
        RIPPLE, METEOR -> 1
        FIREWORK -> 6
        SNOW -> 4
        LANTERN -> 2
        SMOKE -> 3
        else -> 0
    }

    /** Số quỹ đạo dựng sẵn (bội của [particlesPerTap]) — xem [variant]. */
    val variantCount: Int get() = particlesPerTap * 2

    /** Quỹ đạo thứ [v] (dp, giây, radian) — y hệt iOS KeyEffect.trajectory. */
    fun trajectory(v: Int): KeyEffectTrajectory {
        val n = maxOf(variantCount, 1)
        val t = if (n > 1) (v - (n - 1) / 2.0) / ((n - 1) / 2.0) else 0.0
        return when (this) {
            HEART -> KeyEffectTrajectory(t * 24, -(46 + (v % 3) * 7.0), 0.5, 1.0 + (v % 2) * 0.15, t * 0.35,
                0.8 + (v % 3) * 0.05)
            BUBBLE -> KeyEffectTrajectory(t * 16, -(52 + (v % 3) * 8.0), 0.4, 1.0 + (v % 2) * 0.2, 0.0,
                0.9 + (v % 2) * 0.1)
            RIPPLE -> KeyEffectTrajectory(0.0, 0.0, 0.35, 1.6 + (v % 2) * 0.2, 0.0, 0.45)
            PETAL -> KeyEffectTrajectory(t * 34, 12 + (v % 3) * 8.0, 0.7, 1.0, t * 2.4 + 0.6, 0.95)
            FIREWORK -> {
                val a = v * 2 * Math.PI / n
                val d = 30.0 + (v % 2) * 6
                KeyEffectTrajectory(cos(a) * d, sin(a) * d, 1.0, 0.4, 0.0, 0.55)
            }
            BLOSSOM -> KeyEffectTrajectory(t * 30, -(40 + (v % 3) * 9.0), 0.6, 1.0, t * 1.6 + 0.4, 1.0, sway = 6.0)
            COMBO -> KeyEffectTrajectory(t * 8, -(26 + (v % 3) * 6.0), 1.0, 0.35, 0.0, 0.5)
            SNOW -> KeyEffectTrajectory(t * 14, 40 + (v % 3) * 8.0, 0.8, 1.0 + (v % 2) * 0.15, t * 1.2, 1.2, sway = 7.0)
            METEOR -> {   // vệt lao CHÉO lên-phải đúng góc của hình (không xoay), dài ra rồi tắt
                val d = MeteorStreak.DISTANCE + (v % 2) * 8
                KeyEffectTrajectory(cos(MeteorStreak.ANGLE) * d, sin(MeteorStreak.ANGLE) * d, 0.55, 1.0, 0.0, MeteorStreak.DURATION)
            }
            LANTERN -> KeyEffectTrajectory(t * 10, -(56 + (v % 2) * 10.0), 1.0, 0.55 + (v % 2) * 0.1, 0.0,
                1.2 - (1 - v % 2) * 0.1, sway = 4.0)
            SMOKE -> KeyEffectTrajectory(t * 12, -(26 + (v % 3) * 6.0), 0.5, 1.7 + (v % 2) * 0.3, 0.0,
                0.9 + (v % 3) * 0.1, sway = 5.0)
            else -> KeyEffectTrajectory(0.0, 0.0, 1.0, 1.0, 0.0, 0.0)
        }
    }

    /** Quỹ đạo của hạt [i] trong lần bấm số [seed]: trải đều, mỗi lần lệch chút. */
    fun variant(i: Int, seed: Int): Int {
        val stride = maxOf(variantCount / maxOf(particlesPerTap, 1), 1)
        return (i * stride + abs(seed) % stride) % maxOf(variantCount, 1)
    }

    companion object {
        val DEFAULT = NONE
        val IDS: Set<String> = entries.map { it.id }.toSet()
        val PARTICLES: Set<KeyEffect> = setOf(HEART, BUBBLE, RIPPLE, PETAL, FIREWORK, BLOSSOM, COMBO, SNOW, METEOR, LANTERN, SMOKE)
        /** Giá trị lạ / thiếu ⇒ [DEFAULT]. */
        fun of(raw: Any?): KeyEffect = entries.firstOrNull { it.id == raw } ?: DEFAULT
    }
}

/**
 * "Rung dây" (theme Ghi-ta, 10/2026): bấm phím ⇒ đoạn dây ngang ở khe hàng gần phím nhất rung sóng dừng tắt dần
 * ~0.3 s rồi đứng yên. Hàm thuần — iOS StringPluck y hệt (test số chung). Path dựng cho chiều dài chuẩn
 * [UNIT_LENGTH], co giãn ngang theo phím; biên độ khung f: A·cos(2π·cycles·t/T)·e^(−t/τ), khung cuối = 0.
 */
object StringPluck {
    const val DURATION = 0.3
    const val FRAMES = 18
    const val AMPLITUDE = 3.0
    const val CYCLES = 4.0
    const val DECAY = 0.09
    const val UNIT_LENGTH = 100.0
    const val POINTS = 16
    const val LENGTH_FACTOR = 2.2
    const val MIN_LENGTH = 44.0
    const val MAX_LENGTH = 150.0
    /** Số đoạn dây rung cùng lúc (pool xoay vòng). */
    const val POOL = 4
    const val SWEEP_SLACK = 0.05
    /** Không có khe (một hàng): dây nằm dưới phím cách mép này. */
    const val FALLBACK_OFFSET = 4.0

    fun length(keyWidth: Double): Double = (keyWidth * LENGTH_FACTOR).coerceIn(MIN_LENGTH, MAX_LENGTH)

    /** Biên độ (dp) ở khung [f] (0…FRAMES). */
    fun amplitude(f: Int): Double {
        if (f <= 0) return AMPLITUDE
        if (f >= FRAMES) return 0.0
        val t = f.toDouble() / FRAMES * DURATION
        return AMPLITUDE * cos(2 * Math.PI * CYCLES * t / DURATION) * exp(-t / DECAY)
    }

    /** Điểm dây ở khung [f] (chiều dài [UNIT_LENGTH], tâm tại gốc): [x, y] với y = a·sin(πu). */
    fun shape(f: Int): List<DoubleArray> {
        val a = amplitude(f)
        return (0..POINTS).map { i ->
            val u = i.toDouble() / POINTS
            doubleArrayOf((u - 0.5) * UNIT_LENGTH, a * sin(Math.PI * u))
        }
    }

    /** Biên độ hiện tại sau [dt] giây kể từ lúc gảy (nội suy tuyến tính giữa hai khung; ≥ DURATION ⇒ 0). */
    fun amplitudeAt(dt: Double): Double {
        if (dt <= 0) return AMPLITUDE
        if (dt >= DURATION) return 0.0
        val x = dt / DURATION * FRAMES
        val f = x.toInt()
        return amplitude(f) + (amplitude(f + 1) - amplitude(f)) * (x - f)
    }

    /** Độ mờ sau [dt] giây: 1 tới 70 % thời gian rồi tắt tuyến tính về 0 (iOS keyframe [1, 1, 0] @ [0, .7, 1]). */
    fun alphaAt(dt: Double): Double = when {
        dt < 0 || dt >= DURATION -> 0.0
        dt <= 0.7 * DURATION -> 1.0
        else -> 1 - (dt - 0.7 * DURATION) / (0.3 * DURATION)
    }

    /** Còn bao lâu nữa mới dọn (≤ 0 ⇒ dọn ngay). */
    fun sweepDelay(sinceLastPluck: Double): Double = DURATION + SWEEP_SLACK - sinceLastPluck

    /** Khe chứa dây gần phím nhất: (tâm y, chỉ số khe). Hoà ⇒ khe dưới. Không có khe ⇒ ngay dưới phím, chỉ số 0. */
    fun target(keyTop: Double, keyBottom: Double, gaps: List<ThemeDecoration.Gap>): Pair<Double, Int> {
        val mid = (keyTop + keyBottom) / 2
        var best: Pair<Double, Int>? = null
        var bestD = Double.POSITIVE_INFINITY
        gaps.forEachIndexed { i, g ->
            val d = abs(g.center - mid)
            if (d < bestD - 1e-9 || (abs(d - bestD) <= 1e-9 && g.center > (best?.first ?: Double.NEGATIVE_INFINITY))) {
                bestD = d; best = g.center to i
            }
        }
        return best ?: ((keyBottom + FALLBACK_OFFSET) to 0)
    }
}

/**
 * "Sao băng" (theme Vũ trụ): MỘT hạt vector — hình giọt (đầu tròn, đuôi dài phía sau) đặt sẵn theo góc bay, lao
 * chéo từ tâm phím rồi tắt. Không xoay, không ảnh ⇒ dùng chung đường hạt. iOS MeteorStreak y hệt (test số chung).
 */
object MeteorStreak {
    /** Hướng bay (rad, y xuống): lên-phải ≈ −35°. */
    const val ANGLE = -0.61
    const val DISTANCE = 56.0
    const val DURATION = 0.5
    const val LENGTH = 26.0
    const val HEAD_RADIUS = 2.4
    const val ARC_STEPS = 6
    /** Vàng ấm; theme sáng có viền mảnh [EDGE] để thấy trên phím sáng. */
    const val COLOR = 0xFFE7A0
    const val EDGE = 0xB07A1A

    /** Đa giác (dp, tâm đầu tại gốc): nửa vòng đầu phía trước ([ARC_STEPS] đoạn) rồi mũi đuôi — [x0, y0, x1, y1, …]. */
    fun polygon(): DoubleArray {
        val out = DoubleArray(2 * (ARC_STEPS + 2))
        for (k in 0..ARC_STEPS) {
            val phi = ANGLE + Math.PI / 2 - k * Math.PI / ARC_STEPS
            out[2 * k] = HEAD_RADIUS * cos(phi); out[2 * k + 1] = HEAD_RADIUS * sin(phi)
        }
        out[2 * (ARC_STEPS + 1)] = -cos(ANGLE) * LENGTH; out[2 * (ARC_STEPS + 1) + 1] = -sin(ANGLE) * LENGTH
        return out
    }
}

data class KeyEffectTrajectory(
    val dx: Double, val dy: Double,
    val scaleFrom: Double, val scaleTo: Double,
    val rotation: Double,
    val duration: Double,
    /** Lắc ngang (dp): x cộng sway·sin(2π·f) — tuyết / hoa trôi. */
    val sway: Double = 0.0,
)

/**
 * Đốm sáng mềm (Đèn lồng / Sương ma): bitmap gradient tròn dựng MỘT lần mỗi màu lúc đổi kiểu — bấm phím chỉ
 * dời / co giãn / mờ (RenderThread). Điểm dừng gradient = iOS GlowSprite.
 */
object GlowSprite {
    /** Đường kính ảnh (dp). */
    const val SIZE = 26.0
    /** Lõi sáng ấm của đèn lồng. */
    const val CORE = 0xFFF4D6
    fun positions(e: KeyEffect): DoubleArray =
        if (e == KeyEffect.LANTERN) doubleArrayOf(0.0, 0.28, 0.6, 1.0) else doubleArrayOf(0.0, 0.45, 1.0)
    fun alphas(e: KeyEffect): DoubleArray =
        if (e == KeyEffect.LANTERN) doubleArrayOf(1.0, 0.9, 0.35, 0.0) else doubleArrayOf(0.5, 0.32, 0.0)
}

enum class KeyEffectBand {
    ABOVE_KEYS, BELOW_KEYS;

    companion object {
        /**
         * Vị trí chèn overlay vào view gốc IME (con vẽ theo thứ tự; nền + ảnh nền vẽ trong onDraw của view
         * gốc, TRƯỚC mọi con): dải dưới phím ⇒ ngay trước KeyboardView (trên nền, dưới phím); còn lại ⇒
         * ngay dưới balloon (trên phím / tiền cảnh, dưới ô phóng to).
         */
        fun insertIndex(band: KeyEffectBand, keyboardIndex: Int, balloonIndex: Int): Int =
            if (band == BELOW_KEYS) keyboardIndex else balloonIndex
    }
}

/** Cổng Plus: đi cùng quyền theme cao cấp (như ảnh nền / tuỳ chỉnh nâng cao). */
object KeyEffectGate {
    val allows: Boolean get() = PlusGate.isUnlocked(PlusFeature.PREMIUM_THEMES)
    fun allows(e: KeyEffect): Boolean = !e.isPlus || allows
}

/** Kiểu thực chạy — tắt / hết Plus / tiết kiệm pin ⇒ [KeyEffect.NONE]. */
object KeyEffectPolicy {
    /** Tắt hiệu ứng động của hệ thống KHÔNG tắt hiệu ứng phím (Phil 19/10/2026) — overlay tự đếm giờ
     *  (SystemClock), không phụ thuộc ValueAnimator. */
    fun active(setting: KeyEffect, plus: Boolean, powerSave: Boolean): KeyEffect =
        if (setting == KeyEffect.NONE || !plus || powerSave) KeyEffect.NONE else setting
}

/** Ô pool xoay vòng: đủ [capacity] hạt thì hạt cũ nhất bị thay (gõ nhanh không dồn hạt). */
class KeyEffectPool(capacity: Int = CAP) {
    val capacity: Int = maxOf(1, capacity)
    var cursor = 0
        private set
    fun next(): Int { val i = cursor; cursor = (cursor + 1) % capacity; return i }

    companion object { const val CAP = 20 }
}

/**
 * Mô phỏng hạt cho overlay Android: mảng cấp sẵn theo [KeyEffectPool.CAP], quỹ đạo tính sẵn lúc
 * [configure] ⇒ [spawn] / [sample] không cấp phát. Sau [sample] đọc kết quả ở [sx]…[sRot].
 */
class KeyEffectParticles(capacity: Int = KeyEffectPool.CAP) {
    val capacity = maxOf(1, capacity)
    private val pool = KeyEffectPool(this.capacity)
    private val x0 = FloatArray(this.capacity)
    private val y0 = FloatArray(this.capacity)
    private val start = LongArray(this.capacity)
    private val variant = IntArray(this.capacity)
    private val alive = BooleanArray(this.capacity)
    private val scaleK = FloatArray(this.capacity)
    private val index = IntArray(this.capacity)
    private var trajs: Array<KeyEffectTrajectory> = emptyArray()
    private var seed = 0

    var effect: KeyEffect = KeyEffect.NONE
        private set

    fun configure(e: KeyEffect) {
        if (e == effect && trajs.size == e.variantCount) return
        effect = e
        trajs = Array(e.variantCount) { e.trajectory(it) }
        clear()
    }

    fun clear() { alive.fill(false) }

    /** Một lần bấm tại ([x], [y]) (px) lúc [nowMs]; [count] hạt (mặc định đủ), cỡ nhân [scale] (Lửa combo). */
    fun spawn(x: Float, y: Float, nowMs: Long, count: Int = effect.particlesPerTap, scale: Float = 1f) {
        seed++
        for (i in 0 until minOf(count, effect.particlesPerTap)) {
            val s = pool.next()
            x0[s] = x; y0[s] = y; start[s] = nowMs
            variant[s] = effect.variant(i, seed)
            scaleK[s] = scale
            index[s] = i
            alive[s] = true
        }
    }

    /** Hạt thứ mấy trong lần bấm (màu / hình theo thứ tự) — đọc sau [sample]. */
    var sIndex = 0; private set

    fun aliveCount(): Int = alive.count { it }

    var sx = 0f; private set
    var sy = 0f; private set
    var sScale = 1f; private set
    var sAlpha = 1f; private set
    /** Độ quay (độ). */
    var sRot = 0f; private set

    /** Trạng thái hạt [slot] lúc [nowMs] ([density]: px mỗi dp); false = không còn bay (đã tắt). */
    fun sample(slot: Int, nowMs: Long, density: Float): Boolean {
        if (!alive[slot]) return false
        val v = variant[slot]
        if (v >= trajs.size) { alive[slot] = false; return false }
        val t = trajs[v]
        var f = ((nowMs - start[slot]) / (t.duration * 1000.0)).toFloat()
        if (f >= 1f) { alive[slot] = false; return false }
        if (f < 0f) f = 0f
        val e = 1f - (1f - f) * (1f - f)          // easeOut như iOS
        val k = scaleK[slot]
        val sw = if (t.sway != 0.0) t.sway * sin(f * 2 * Math.PI) else 0.0
        sx = x0[slot] + ((t.dx * e + sw) * k).toFloat() * density
        sy = y0[slot] + (t.dy * e * k).toFloat() * density
        sScale = (t.scaleFrom + (t.scaleTo - t.scaleFrom) * f).toFloat() * k
        sIndex = index[slot]
        sAlpha = if (f < 0.5f) 1f else 1f - (f - 0.5f) / 0.5f
        sRot = Math.toDegrees(t.rotation * f).toFloat()
        return true
    }
}

// MARK: hàm thuần đợt 2 (Nháy sáng, Matrix, Tia sét, Emoji theo chữ, Lửa combo, Mực loang, Sóng nước)
// — song sinh iOS KeyEffects.swift, CÙNG SỐ (test chéo hai nền tảng).

/** LCG 32-bit tất định (Int tràn số) — cùng chuỗi số với iOS FxRandom (UInt32). */
class FxRandom(seed: Int) {
    var state: Int = seed * -1640531535 + 1      // 2654435761 dạng Int32
        private set
    /** 0…1. */
    fun next(): Double {
        state = state * 1103515245 + 12345
        return ((state ushr 8) and 0xFFFF) / 65535.0
    }
}

/**
 * "Nháy sáng": MỘT lớp phủ cả bàn phím nháy độ mờ. Dịu mắt: đỉnh thấp, chỉ tắt dần, trần nhịp ≥ 60 ms
 * giữa hai lần nháy; gõ nhanh hơn ⇒ bỏ qua (xung đang chạy tiếp, không chồng).
 */
class FlashPulse {
    var last = Long.MIN_VALUE / 2; private set
    var fired = 0; private set

    /** true ⇒ phát lại xung lúc [nowMs]. */
    fun trigger(nowMs: Long): Boolean {
        if (nowMs - last < MIN_INTERVAL_MS) return false
        last = nowMs; fired++
        return true
    }

    companion object {
        const val PEAK = 0.25
        const val DURATION_MS = 120L
        const val MIN_INTERVAL_MS = 60L
        /** Độ mờ sau [dtMs] kể từ lúc nháy: tắt dần (1−x)². */
        fun alpha(dtMs: Long): Double {
            if (dtMs < 0 || dtMs >= DURATION_MS) return 0.0
            val x = 1.0 - dtMs.toDouble() / DURATION_MS
            return PEAK * x * x
        }
    }
}

/** "Tia sét": đường gấp khúc tất định từ đỉnh xuống tâm phím (gốc = tâm phím). = iOS LightningBolt. */
object LightningBolt {
    const val SEGMENTS = 7
    const val VARIANTS = 6
    const val DURATION_MS = 180L

    /** Ghi (SEGMENTS+1) điểm x,y vào [out] (cỡ ≥ 2·(SEGMENTS+1)) — không cấp phát. */
    fun points(height: Double, variant: Int, out: DoubleArray) {
        // LCG của FxRandom viết thẳng (không tạo đối tượng — đường mỗi phím không cấp phát).
        var st = (variant * 7919 + 17) * -1640531535 + 1
        st = st * 1103515245 + 12345
        val h = maxOf(height, 1.0)
        val amp = minOf(14.0, h * 0.12)
        val sx = (((st ushr 8) and 0xFFFF) / 65535.0 - 0.5) * minOf(40.0, h * 0.4)
        out[0] = sx; out[1] = -h
        for (i in 1 until SEGMENTS) {
            val f = i.toDouble() / SEGMENTS
            st = st * 1103515245 + 12345
            val off = (((st ushr 8) and 0xFFFF) / 65535.0 - 0.5) * 2 * amp * sin(f * Math.PI)
            out[2 * i] = sx * (1 - f) + off; out[2 * i + 1] = -h * (1 - f)
        }
        out[2 * SEGMENTS] = 0.0; out[2 * SEGMENTS + 1] = 0.0
    }
}

/** "Tia sét": phím "vỡ" thành [COUNT] mảnh (quạt từ tâm) — CHỈ lớp phủ; phím thật không bị đụng. */
object LightningShards {
    const val COUNT = 5
    const val FLIGHT = 18.0
    const val DURATION_MS = 320L
    const val DELAY_MS = 50L
    private val JITTER = doubleArrayOf(0.0, 0.25, -0.2, 0.15, -0.1)
    val angles = DoubleArray(COUNT) { -Math.PI / 2 + 0.3 + it * 2 * Math.PI / COUNT + JITTER[it] }

    /** Đa giác quanh tâm phím: xs/ys + trọng tâm + diện tích. */
    class Piece(val xs: DoubleArray, val ys: DoubleArray, val cx: Double, val cy: Double, val area: Double)

    fun dirX(i: Int): Double = cos(mid(i))
    fun dirY(i: Int): Double = sin(mid(i))
    fun rotation(i: Int): Double = if (i % 2 == 0) 0.5 else -0.45
    private fun mid(i: Int): Double {
        val a0 = angles[i]; val a1 = if (i + 1 < COUNT) angles[i + 1] else angles[0] + 2 * Math.PI
        return (a0 + a1) / 2
    }

    fun pieces(w: Double, h: Double): List<Piece> {
        val hw = maxOf(w, 1.0) / 2; val hh = maxOf(h, 1.0) / 2
        fun edge(a: Double): Pair<Double, Double> {
            val c = cos(a); val s = sin(a)
            val t = minOf(if (abs(c) > 1e-9) hw / abs(c) else Double.MAX_VALUE, if (abs(s) > 1e-9) hh / abs(s) else Double.MAX_VALUE)
            return c * t to s * t
        }
        val a0 = angles[0]
        val corners = listOf(hw to hh, -hw to hh, -hw to -hh, hw to -hh).map { c ->
            var a = kotlin.math.atan2(c.second, c.first)
            while (a < a0) a += 2 * Math.PI
            while (a >= a0 + 2 * Math.PI) a -= 2 * Math.PI
            a to c
        }.sortedBy { it.first }
        return (0 until COUNT).map { i ->
            val s = angles[i]; val e = if (i + 1 < COUNT) angles[i + 1] else a0 + 2 * Math.PI
            val pts = ArrayList<Pair<Double, Double>>()
            pts.add(0.0 to 0.0); pts.add(edge(s))
            for (c in corners) if (c.first > s && c.first < e) pts.add(c.second)
            pts.add(edge(e))
            var a2 = 0.0; var cx = 0.0; var cy = 0.0
            for (k in pts.indices) {
                val p = pts[k]; val q = pts[(k + 1) % pts.size]
                val cr = p.first * q.second - q.first * p.second
                a2 += cr; cx += (p.first + q.first) * cr; cy += (p.second + q.second) * cr
            }
            val area = a2 / 2
            Piece(DoubleArray(pts.size) { pts[it].first }, DoubleArray(pts.size) { pts[it].second },
                if (abs(area) > 1e-9) cx / (6 * area) else 0.0, if (abs(area) > 1e-9) cy / (6 * area) else 0.0, abs(area))
        }
    }
}

/**
 * "Lửa combo": mức combo theo tốc độ gõ (số phím trong ~2 s), nguội sau ~1 s không gõ. Mức 0 = không
 * lửa; 1…3 = số ngọn + cỡ lớn dần. Mảng vòng cấp sẵn. = iOS ComboMeter.
 */
class ComboMeter {
    private val times = LongArray(CAPACITY) { Long.MIN_VALUE / 2 }
    private var head = 0
    private var last = Long.MIN_VALUE / 2

    fun press(nowMs: Long): Int {
        if (nowMs - last > COOLDOWN_MS) reset()
        last = nowMs
        times[head] = nowMs; head = (head + 1) % CAPACITY
        return level(nowMs)
    }

    fun level(nowMs: Long): Int {
        if (nowMs - last > COOLDOWN_MS) return 0
        var n = 0
        for (x in times) if (x <= nowMs && nowMs - x <= WINDOW_MS) n++
        var lv = 0
        for (th in THRESHOLDS) if (n >= th) lv++
        return lv
    }

    fun reset() { times.fill(Long.MIN_VALUE / 2); head = 0 }

    companion object {
        const val WINDOW_MS = 2000L
        const val COOLDOWN_MS = 1000L
        val THRESHOLDS = intArrayOf(6, 10, 14)
        val SCALES = doubleArrayOf(0.0, 0.8, 1.05, 1.35)
        const val CAPACITY = 16
    }
}

/** "Sóng nước" — số vòng mỗi lần bấm, nhịp lệch. = iOS WaveRings. */
object WaveRings {
    const val RINGS = 3
    const val STAGGER_MS = 200L
    const val DURATION_MS = 1200L
    const val RADIUS = 18.0
    const val SCALE_FROM = 0.15
    const val SCALE_TO = 5.5
    /** Số đợt sóng xoay vòng (mỗi lần bấm một đợt). */
    const val SLOTS = 3
}

/** "Mực loang". = iOS InkBloom. */
object InkBloom {
    const val SIZE = 48.0
    const val SCALE_FROM = 0.25
    const val SCALE_TO = 3.2
    const val PEAK_ALPHA = 0.45
    const val DURATION_MS = 1000L
    const val SLOTS = 4
}

/** "Matrix": cột chữ xanh rơi — dải ảnh dựng MỘT lần, chỉ dời vị trí. = iOS MatrixRain. */
object MatrixRain {
    const val GREEN = 0x00FF41
    const val HEAD = 0xD8FFE0
    val GLYPHS = "ABCDEFGHJKLMNPQRSTUVXYZ0123456789ăâđêôơưĂÂĐÊÔƠƯ".toCharArray()
    const val ROWS = 18
    const val STRIP_COUNT = 4
    const val GLYPH_SIZE = 13.0
    const val LINE_HEIGHT = 15.0
    const val COLUMN_WIDTH = 14.0
    const val SPACING = 18.0
    const val IDLE_AFTER_MS = 2500L
    const val FADE_OUT_MS = 400L
    const val STRIP_HEIGHT = ROWS * LINE_HEIGHT

    fun columnCount(widthDp: Double): Int = minOf(28, maxOf(1, (widthDp / SPACING).toInt()))

    class Column(val strip: Int, val duration: Double, val phase: Double, val jitter: Double)
    fun column(i: Int): Column {
        val r = FxRandom(i * 31 + 7)
        return Column(i % STRIP_COUNT, 1.3 + r.next() * 1.2, r.next(), (r.next() - 0.5) * 4)
    }

    fun glyph(strip: Int, row: Int): Char {
        val r = FxRandom(strip * 101 + row * 7 + 3)
        return GLYPHS[(r.next() * (GLYPHS.size - 1)).toInt()]
    }

    fun rowAlpha(row: Int): Double {
        val f = row.toDouble() / maxOf(ROWS - 1, 1)
        return 0.08 + 0.92 * Math.pow(f, 1.6)
    }

    fun maxOpacity(dark: Boolean): Double = if (dark) 0.85 else 0.5
    fun intensity(presses: Int): Double = minOf(1.0, 0.55 + 0.15 * maxOf(presses - 1, 0))

    /** Đỉnh cột (dp) lúc [tMs] trên vùng cao [heightDp] — rơi lặp (như iOS animation position.y). */
    fun columnTop(c: Column, tMs: Long, heightDp: Double): Double {
        val d = c.duration * 1000
        val f = ((tMs + c.phase * d) % d + d) % d / d
        return -STRIP_HEIGHT + f * (heightDp + STRIP_HEIGHT)
    }
}

/** Đồng hồ chạy/dừng Matrix: chạy khi gõ; nghỉ ~2,5 s ⇒ mờ dần rồi dừng hẳn (0 khung hình). = iOS MatrixClock. */
class MatrixClock(var idleAfterMs: Long = MatrixRain.IDLE_AFTER_MS) {
    var lastInput = Long.MIN_VALUE / 2; private set
    var running = false; private set
    var presses = 0; private set

    /** true nếu vừa khởi động. */
    fun poke(nowMs: Long): Boolean {
        val started = !running
        running = true
        if (nowMs - lastInput > idleAfterMs) presses = 0
        presses++
        lastInput = nowMs
        return started
    }

    fun idleRemaining(nowMs: Long): Long = idleAfterMs - (nowMs - lastInput)

    /** Hệ số mờ lúc [nowMs]: 1 khi đang gõ, giảm dần trong FADE_OUT sau khi nghỉ; ≤ 0 ⇒ dừng. */
    fun fade(nowMs: Long): Double {
        val over = -idleRemaining(nowMs)
        return if (over <= 0) 1.0 else 1.0 - over.toDouble() / MatrixRain.FADE_OUT_MS
    }

    fun stop() { running = false; presses = 0 }
}

/**
 * "Emoji theo chữ": bảng nhỏ, tra O(1) ở RANH GIỚI TỪ bằng từ vừa chốt. Không phân biệt dấu (trừ mục
 * strict dễ nhầm, vd "ngủ" ≠ "ngu"); từ tục / cặp tục ([SensitiveWords]) ⇒ không emoji. = iOS EmojiWords.
 */
object EmojiWords {
    class Entry(val form: String, val emoji: String, val strict: Boolean)
    private fun e(f: String, em: String, strict: Boolean = false) = Entry(f, em, strict)
    val entries: List<Entry> = listOf(
        e("haha", "😂"), e("hihi", "😂"), e("hehe", "😂"), e("kkk", "😂"), e("kaka", "😂"), e("lol", "😂"),
        e("lmao", "😂"), e("hài", "😂", true),
        e("yêu", "❤️"), e("thương", "❤️"), e("love", "❤️"), e("iu", "❤️"),
        e("chúc mừng", "🎉"), e("congrats", "🎉"), e("congratulations", "🎉"), e("hpbd", "🎉"), e("sinh nhật", "🎉"),
        e("party", "🎉"),
        e("buồn", "😢"), e("sad", "😢"), e("khóc", "😢", true), e("huhu", "😢"), e("hic", "😢"),
        e("ok", "👌"), e("oke", "👌"), e("okay", "👌"), e("okie", "👌"), e("okela", "👌"),
        e("cảm ơn", "🙏"), e("cám ơn", "🙏"), e("thanks", "🙏"), e("thank", "🙏"), e("thx", "🙏"), e("tks", "🙏"),
        e("ngủ", "😴", true), e("ngủ ngon", "😴"), e("buồn ngủ", "😴"), e("sleep", "😴"),
        e("tết", "🧧"), e("năm mới", "🧧"), e("lì xì", "🧧"), e("lixi", "🧧"),
        e("cà phê", "☕"), e("cafe", "☕"), e("coffee", "☕"),
        e("phở", "🍜", true), e("bánh kem", "🎂"), e("noel", "🎄"), e("giáng sinh", "🎄"),
        e("hoa", "🌸", true), e("mưa", "🌧️", true), e("nắng", "☀️", true), e("tuyệt vời", "🤩"),
        e("xin chào", "👋"), e("hello", "👋"), e("bye", "👋"),
    )

    private val MARKS = Regex("\\p{Mn}+")
    fun fold(s: String): String =
        MARKS.replace(java.text.Normalizer.normalize(s.lowercase().replace('đ', 'd'), java.text.Normalizer.Form.NFD), "")

    private val exact: Map<String, String> = HashMap<String, String>().also { m -> entries.forEach { m.putIfAbsent(it.form, it.emoji) } }
    private val folded: Map<String, String> = HashMap<String, String>().also { m ->
        entries.filter { !it.strict }.forEach { m.putIfAbsent(fold(it.form), it.emoji) }
    }
    val distinctEmojis: List<String> get() = entries.map { it.emoji }.distinct().sorted()

    private fun clean(s: String): String = s.trim { !it.isLetter() }.lowercase()
    private fun match(k: String): String? = if (k.isEmpty()) null else exact[k] ?: folded[fold(k)]

    /** Emoji cho từ vừa chốt [word] (từ liền trước [prev] — cụm 2 từ ưu tiên). Tục ⇒ null. */
    fun lookup(word: String, prev: String?): String? {
        val w = clean(word)
        if (w.isEmpty() || w.length > 24) return null
        val p = prev?.let(::clean)
        if (blocked(w, p)) return null
        if (!p.isNullOrEmpty()) match("$p $w")?.let { return it }
        return match(w)
    }

    fun blocked(w: String, prev: String?): Boolean {
        if (w.split(' ').any { it in SensitiveWords.set }) return true
        if (prev != null && (prev in SensitiveWords.set || SensitiveWords.isPair(prev, w))) return true
        return false
    }
}

// MARK: đợt 3 (11/2026): Plasma, Rung combo, Laser, Glitch, Dấu thanh, Từ khoá, Chữ bay, Hạt cát
// — hàm thuần song sinh iOS KeyEffects.swift, CÙNG SỐ (test chéo hai nền tảng).

/** LCG của [FxRandom] viết thẳng (không tạo đối tượng): trạng thái kế. */
internal fun fxStep(st: Int): Int = st * 1103515245 + 12345
/** Giá trị 0…1 của trạng thái [st]. */
internal fun fxValue(st: Int): Double = ((st ushr 8) and 0xFFFF) / 65535.0
/** Trạng thái đầu của hạt giống [seed] (= FxRandom(seed).state). */
internal fun fxSeed(seed: Int): Int = seed * -1640531535 + 1

/**
 * "Plasma": tia điện tím nối phím TRƯỚC với phím vừa bấm — gõ nhanh thành chuỗi, mỗi tia tắt nhanh. Hai phím cách
 * nhau quá [CHAIN_MS] (hay cùng phím) ⇒ không nối, chỉ đốm lửa nhỏ tại phím. = iOS PlasmaArc.
 */
object PlasmaArc {
    const val CHAIN_MS = 500L
    const val SEGMENTS = 8
    const val DURATION_MS = 220L
    const val MAX_JITTER = 9.0
    /** Ngắn hơn (dp) ⇒ cùng phím: không nối. */
    const val MIN_LENGTH = 6.0
    const val POOL = 4
    const val VARIANTS = 6
    const val COLOR = 0xB44CFF
    const val CORE = 0xF3E0FF
    const val SPARK_RADIUS = 7.0

    /**
     * (SEGMENTS+1) điểm x,y từ (x0,y0) tới (x1,y1) vào [out]: lệch vuông góc tất định theo [variant], bao sin (hai đầu
     * đúng tâm phím). [unit] = px mỗi dp (iOS 1) — trần lệch tính theo dp. Không cấp phát.
     */
    fun points(x0: Double, y0: Double, x1: Double, y1: Double, variant: Int, out: DoubleArray, unit: Double = 1.0) {
        val dx = x1 - x0; val dy = y1 - y0
        val len = kotlin.math.hypot(dx, dy)
        val nx = if (len > 1e-9) -dy / len else 0.0
        val ny = if (len > 1e-9) dx / len else 0.0
        val amp = minOf(MAX_JITTER * unit, len * 0.15)
        var st = fxSeed(variant * 7919 + 29)
        out[0] = x0; out[1] = y0
        for (i in 1 until SEGMENTS) {
            val f = i.toDouble() / SEGMENTS
            st = fxStep(st)
            val off = (fxValue(st) - 0.5) * 2 * amp * sin(f * Math.PI)
            out[2 * i] = x0 + dx * f + nx * off; out[2 * i + 1] = y0 + dy * f + ny * off
        }
        out[2 * SEGMENTS] = x1; out[2 * SEGMENTS + 1] = y1
    }

    /** Độ mờ sau [dtMs]: giữ 30 % rồi tắt tuyến tính. */
    fun alpha(dtMs: Long): Double {
        if (dtMs < 0 || dtMs >= DURATION_MS) return 0.0
        val f = dtMs.toDouble() / DURATION_MS
        return if (f < 0.3) 1.0 else 1.0 - (f - 0.3) / 0.7
    }
}

/** Chuỗi Plasma: nhớ phím trước (toạ độ dp + giờ). = iOS PlasmaChain. */
class PlasmaChain {
    var prevX = 0.0; private set
    var prevY = 0.0; private set
    private var lastX = 0.0
    private var lastY = 0.0
    private var last = Long.MIN_VALUE / 2

    /** Một phím tại ([x], [y]) (dp) lúc [nowMs]: true ⇒ nối tia từ ([prevX], [prevY]). */
    fun press(x: Double, y: Double, nowMs: Long): Boolean {
        val link = nowMs - last <= PlasmaArc.CHAIN_MS && kotlin.math.hypot(x - lastX, y - lastY) >= PlasmaArc.MIN_LENGTH
        prevX = lastX; prevY = lastY
        lastX = x; lastY = y; last = nowMs
        return link
    }

    fun reset() { last = Long.MIN_VALUE / 2 }
}

/**
 * "Rung combo": gõ nhanh ⇒ nội dung bàn phím rung kiểu đòn trúng trong game đối kháng, mạnh dần theo mức [ShakeMeter]
 * (3 / 5 / 7 dp), ~0,25 s, 3–4 nhịp tắt dần, ngang + chút dọc. Chỉ dời HÌNH vẽ rồi về 0. Giảm chuyển động KHÔNG tắt
 * (Phil 08/11/2026, như mọi hiệu ứng khác). = iOS ShakeFx.
 */
object ShakeFx {
    const val MAX = 7.0
    val AMPS = doubleArrayOf(0.0, 3.0, 5.0, 7.0)
    /** 7 đoạn × 35 ms (iOS duration = 0,245). */
    const val DURATION_MS = 245L
    /** Khung hình (tỉ lệ biên độ) — dao động tắt dần, đầu/cuối 0. */
    val XS = doubleArrayOf(0.0, 1.0, -0.85, 0.65, -0.45, 0.28, -0.12, 0.0)
    val YS = doubleArrayOf(0.0, -0.35, 0.3, -0.22, 0.15, -0.08, 0.03, 0.0)

    /** Biên độ (dp) cho mức [ShakeMeter] [level]. */
    fun amplitude(level: Int): Double = minOf(MAX, AMPS[level.coerceIn(0, AMPS.size - 1)])

    private fun sample(k: DoubleArray, dtMs: Long, amp: Double): Double {
        if (dtMs <= 0 || dtMs >= DURATION_MS || amp == 0.0) return 0.0
        val x = dtMs.toDouble() / DURATION_MS * (k.size - 1)
        val i = x.toInt()
        return amp * (k[i] + (k[i + 1] - k[i]) * (x - i))
    }
    fun offsetX(dtMs: Long, amp: Double): Double = sample(XS, dtMs, amp)
    fun offsetY(dtMs: Long, amp: Double): Double = sample(YS, dtMs, amp)
}

/**
 * Mức rung: số phím trong [WINDOW_MS] gần nhất (kể cả phím này) ≥ 4 / 6 / 8 ⇒ mức 1 / 2 / 3 — gõ nhanh bình thường
 * (≈ 3,5 phím/s) đã lên mức 1. Riêng với [ComboMeter] (Lửa combo giữ ngưỡng cũ). = iOS ShakeMeter.
 */
class ShakeMeter {
    private val times = LongArray(CAPACITY) { Long.MIN_VALUE / 2 }
    private var head = 0

    fun press(nowMs: Long): Int {
        times[head] = nowMs; head = (head + 1) % CAPACITY
        var n = 0
        for (x in times) if (x <= nowMs && nowMs - x <= WINDOW_MS) n++
        var lv = 0
        for (th in THRESHOLDS) if (n >= th) lv++
        return lv
    }

    fun reset() { times.fill(Long.MIN_VALUE / 2); head = 0 }

    companion object {
        const val WINDOW_MS = 1200L
        val THRESHOLDS = intArrayOf(4, 6, 8)
        const val CAPACITY = 8
    }
}

/** "Laser": tia mảnh sáng từ phím cách bắn lên phím vừa bấm, tắt nhanh. = iOS LaserBeam. */
object LaserBeam {
    const val DURATION_MS = 160L
    /** Thời gian đầu tia chạy từ phím cách tới phím. */
    const val TRAVEL_MS = 40L
    const val COLOR = 0xFF2D55
    const val GLOW_WIDTH = 4.0
    const val CORE_WIDTH = 1.2
    const val POOL = 3
    /** Không biết phím cách: gốc ở giữa đáy, cách đáy chừng này (dp). */
    const val FALLBACK_INSET = 4.0

    /** Phím vừa bấm nằm trong phím cách ⇒ không bắn (tia dài 0). */
    fun fires(spaceL: Double, spaceT: Double, spaceR: Double, spaceB: Double, kx: Double, ky: Double): Boolean =
        !(kx >= spaceL && kx <= spaceR && ky >= spaceT && ky <= spaceB)

    /** Tỉ lệ đường đã chạy (0…1) sau [dtMs]. */
    fun reach(dtMs: Long): Double = (dtMs.toDouble() / TRAVEL_MS).coerceIn(0.0, 1.0)

    fun alpha(dtMs: Long): Double {
        if (dtMs < 0 || dtMs >= DURATION_MS) return 0.0
        val f = dtMs.toDouble() / DURATION_MS
        return if (f < 0.25) 1.0 else 1.0 - (f - 0.25) / 0.75
    }
}

/**
 * "Glitch": phím vừa bấm nhiễu hình ~120 ms — lệch kênh màu (lục lam / hồng) + vài lát ngang lệch trái/phải, đổi mỗi
 * [STEP_MS]. Chỉ lớp phủ (lát = màu phím), phím thật không bị đụng. = iOS GlitchFx.
 */
object GlitchFx {
    const val DURATION_MS = 120L
    const val STEP_MS = 30L
    const val STEPS = 4
    const val SLICES = 3
    const val MAX_SHIFT = 4.0
    const val SPLIT = 2.0
    const val CYAN = 0x00E5FF
    const val MAGENTA = 0xFF2BD6
    const val POOL = 2
    const val VARIANTS = 8

    /** Lát [SLICES] ở bước [step] (lần bấm [variant]) vào [out] (cỡ 3·SLICES): (đỉnh 0…1, cao 0…1, lệch −1…1). */
    fun slices(step: Int, variant: Int, out: DoubleArray) {
        var st = fxSeed(variant * 131 + step * 17 + 5)
        for (k in 0 until SLICES) {
            st = fxStep(st); val h = 0.08 + fxValue(st) * 0.14
            st = fxStep(st); val y = fxValue(st) * (1 - h)
            st = fxStep(st); val dx = fxValue(st) * 2 - 1
            out[3 * k] = y; out[3 * k + 1] = h; out[3 * k + 2] = dx
        }
    }

    /** Bước hiện tại sau [dtMs]; ≥ STEPS ⇒ hết. */
    fun step(dtMs: Long): Int = if (dtMs < 0) STEPS else (dtMs / STEP_MS).toInt()
    /** Lệch kênh màu bước [step]: bước lẻ một nửa. */
    fun split(step: Int): Double = if (step % 2 == 0) SPLIT else SPLIT / 2
}

/** Kiểu hình "Dấu thanh": 5 dấu thanh + mũ (â ê ô ă) / râu (ơ ư) / gạch đ. Thứ tự = iOS ToneFx. */
enum class ToneFx { SAC, HUYEN, HOI, NGA, NANG, HAT, HORN, STROKE }

/**
 * "Dấu thanh": so từ đang soạn TRƯỚC/SAU phím ⇒ dấu vừa bỏ. Bảng ký tự (không cấp phát, không chuẩn hoá chuỗi);
 * nhận cả dấu rời (U+0300…). Chỉ chạy khi chọn kiểu này. = iOS ToneMarks.
 */
object ToneMarks {
    /** Mỗi hàng 6 ký tự: không dấu, sắc, huyền, hỏi, ngã, nặng. */
    private const val TABLE = "aáàảãạăắằẳẵặâấầẩẫậeéèẻẽẹêếềểễệiíìỉĩịoóòỏõọôốồổỗộơớờởỡợuúùủũụưứừửữựyýỳỷỹỵ"
    private const val BASES = "aăâeêioôơuưy"

    /** Mã ký tự: 3 bit thấp = dấu thanh (0…5), bit 3+ = 1 mũ / 2 râu / 3 gạch. */
    fun code(c: Char): Int {
        when (c.code) {
            0x301 -> return 1; 0x300 -> return 2; 0x309 -> return 3; 0x303 -> return 4; 0x323 -> return 5
            0x302, 0x306 -> return 1 shl 3
            0x31B -> return 2 shl 3
        }
        val l = c.lowercaseChar()
        if (l == 'đ') return 3 shl 3
        val i = TABLE.indexOf(l)
        if (i < 0) return 0
        val mod = when (BASES[i / 6]) { 'ă', 'â', 'ê', 'ô' -> 1; 'ơ', 'ư' -> 2; else -> 0 }
        return (i % 6) or (mod shl 3)
    }

    /** Dấu thanh của từ + số mũ / râu / gạch, gói: dấu | mũ<<8 | râu<<16 | gạch<<24. */
    fun summary(w: CharSequence): Int {
        var tone = 0; var hats = 0; var horns = 0; var strokes = 0
        for (i in 0 until w.length) {
            val c = code(w[i])
            if (c and 7 != 0) tone = c and 7
            when (c shr 3) { 1 -> hats++; 2 -> horns++; 3 -> strokes++ }
        }
        return tone or (minOf(hats, 255) shl 8) or (minOf(horns, 255) shl 16) or (minOf(strokes, 127) shl 24)
    }

    /** Dấu vừa bỏ khi từ đổi từ [before] thành [after]; null = không (gỡ dấu, chữ thường, ranh giới…). */
    fun detect(before: CharSequence, after: CharSequence): ToneFx? {
        if (after.isEmpty()) return null
        val b = summary(before); val a = summary(after)
        val ta = a and 0xFF; val tb = b and 0xFF
        if (ta != 0 && ta != tb) return when (ta) { 1 -> ToneFx.SAC; 2 -> ToneFx.HUYEN; 3 -> ToneFx.HOI; 4 -> ToneFx.NGA; else -> ToneFx.NANG }
        if ((a ushr 24) > (b ushr 24)) return ToneFx.STROKE
        if ((a shr 16 and 0xFF) > (b shr 16 and 0xFF)) return ToneFx.HORN
        if ((a shr 8 and 0xFF) > (b shr 8 and 0xFF)) return ToneFx.HAT
        return null
    }
}

/** Màu + quỹ đạo của "Dấu thanh" (dp, giây). = iOS ToneBurst. */
object ToneBurst {
    const val SPARKS = 4
    const val POOL = 4
    /** Sắc vàng, huyền xanh, hỏi tím, ngã ngọc, nặng cam; mũ/râu/gạch vàng nhạt. */
    fun color(k: ToneFx): Int = when (k) {
        ToneFx.SAC -> 0xFFC83D; ToneFx.HUYEN -> 0x4FC3F7; ToneFx.HOI -> 0xB388FF
        ToneFx.NGA -> 0x26C6DA; ToneFx.NANG -> 0xFF7043; else -> 0xFFE082
    }
    /** Số hình mỗi lần: sắc/huyền = chùm tia lửa, còn lại 1. */
    fun count(k: ToneFx): Int = if (k == ToneFx.SAC || k == ToneFx.HUYEN) SPARKS else 1
    /** Ngã: giãn NGANG từ scaleFrom tới scaleTo (dọc giữ 1) — gợn sóng. */
    fun stretchesX(k: ToneFx): Boolean = k == ToneFx.NGA
    /** Nặng: rơi nhanh dần (giọt nước). */
    fun easeIn(k: ToneFx): Boolean = k == ToneFx.NANG

    /** Sắc: tia lửa bay lên-phải; huyền: xuống-trái; hỏi: móc xoáy; ngã: sóng ngã giãn; nặng: giọt rơi; mũ…: lấp lánh. */
    fun trajectory(k: ToneFx, i: Int): KeyEffectTrajectory = when (k) {
        ToneFx.SAC, ToneFx.HUYEN -> {
            val base = if (k == ToneFx.SAC) -Math.PI / 4 else 3 * Math.PI / 4
            val a = base + (i - 1.5) * 0.28
            val d = 26.0 + (i % 2) * 8
            KeyEffectTrajectory(cos(a) * d, sin(a) * d, 1.0, 0.4, 0.0, 0.42)
        }
        ToneFx.HOI -> KeyEffectTrajectory(0.0, -18.0, 0.6, 1.3, -1.2, 0.5)
        ToneFx.NGA -> KeyEffectTrajectory(0.0, -10.0, 0.6, 2.0, 0.0, 0.5)
        ToneFx.NANG -> KeyEffectTrajectory(0.0, 28.0, 1.0, 0.8, 0.0, 0.55)
        else -> KeyEffectTrajectory(0.0, -14.0, 0.4, 1.4, 0.0, 0.4)
    }
}

enum class KeywordKind { LAUGH, LOVE, ANGRY, TET }

/**
 * "Từ khoá": từ vừa chốt khớp bảng nhỏ ⇒ chùm hình theo nghĩa: cười (mặt cười), yêu (tim), giận (khói bốc), Tết
 * (pháo đỏ nổ + xác pháo rơi + lì xì bay lên). Tra O(1) ở RANH GIỚI TỪ. Từ Việt khớp ĐÚNG dấu (không phân biệt hoa
 * thường): "tết" ≠ "tet", "thương" ≠ "thường"; tiếng cười lặp ("hahaha", "kkkk") khớp theo đơn vị lặp. Lọc từ tục như
 * Emoji theo chữ. Bảng y hệt iOS KeywordBursts.
 */
object KeywordBursts {
    class Entry(val form: String, val kind: KeywordKind)
    val entries: List<Entry> = listOf(
        Entry("haha", KeywordKind.LAUGH), Entry("hihi", KeywordKind.LAUGH), Entry("hehe", KeywordKind.LAUGH),
        Entry("kkk", KeywordKind.LAUGH),
        Entry("yêu", KeywordKind.LOVE), Entry("thương", KeywordKind.LOVE), Entry("love", KeywordKind.LOVE),
        Entry("giận", KeywordKind.ANGRY), Entry("bực", KeywordKind.ANGRY),
        Entry("tết", KeywordKind.TET), Entry("năm mới", KeywordKind.TET), Entry("lì xì", KeywordKind.TET),
        Entry("lixi", KeywordKind.TET),
    )
    /** Tiếng cười lặp: (đơn vị, số lần tối thiểu). */
    val LAUGH_UNITS: List<Pair<String, Int>> = listOf("ha" to 2, "hi" to 2, "he" to 2, "k" to 3)
    private val table: Map<String, KeywordKind> = HashMap<String, KeywordKind>().also { m -> entries.forEach { m.putIfAbsent(it.form, it.kind) } }

    private fun clean(s: String): String = s.trim { !it.isLetter() }.lowercase()

    /** [w] là đơn vị cười lặp đủ lần. */
    fun isLaugh(w: String): Boolean = LAUGH_UNITS.any { (u, n) ->
        w.length >= u.length * n && w.length % u.length == 0 && (0 until w.length / u.length).all { w.startsWith(u, it * u.length) }
    }

    /** Kiểu chùm cho từ vừa chốt [word] (từ liền trước [prev] — cụm 2 từ ưu tiên: "chúc mừng năm mới" ⇒ "năm mới"). */
    fun lookup(word: String, prev: String?): KeywordKind? {
        val w = clean(word)
        if (w.isEmpty() || w.length > 24) return null
        val p = prev?.let(::clean)
        if (EmojiWords.blocked(w, p)) return null
        if (!p.isNullOrEmpty()) table["$p $w"]?.let { return it }
        return table[w] ?: if (isLaugh(w)) KeywordKind.LAUGH else null
    }

    /** Hình của hạt chùm Từ khoá. */
    enum class Shape { EMOJI, HEART, PUFF, CRACKER, SPARK, PAPER, ENVELOPE }

    /**
     * Một hạt: hình, màu RGB (EMOJI: chỉ số trong [emojis]), điểm xuất phát lệch khỏi phím ([x0], [y0] dp), quỹ đạo,
     * trễ (giây), rơi nhanh dần ([easeIn]).
     */
    class Particle(val shape: Shape, val color: Int, val x0: Double, val y0: Double, val traj: KeyEffectTrajectory,
                   val delay: Double, val easeIn: Boolean = false)

    fun emojis(k: KeywordKind): List<String> = when (k) {
        KeywordKind.LAUGH -> listOf("😂", "🤣", "😆")
        KeywordKind.ANGRY -> listOf("😤")
        else -> emptyList()
    }
    val allEmojis: List<String> get() = KeywordKind.entries.flatMap(::emojis).distinct()

    const val RED = 0xE53935
    const val GOLD = 0xFFC83D
    /** Pháo: bay lên trong [CRACKER_RISE] giây rồi nổ ở đỉnh. */
    const val CRACKER_RISE = 0.35
    /** Số chùm Từ khoá xoay vòng cùng lúc. */
    const val POOL = 2

    private val cache = HashMap<KeywordKind, List<Particle>>()

    /** Các hạt của chùm [k] — tất định, ≤ [KeyEffectPool.CAP]; dựng một lần. */
    fun particles(k: KeywordKind): List<Particle> = cache.getOrPut(k) { build(k) }

    private fun build(k: KeywordKind): List<Particle> = when (k) {
        KeywordKind.LAUGH -> (0 until 3).map { i ->
            val t = i - 1.0
            Particle(Shape.EMOJI, i, 0.0, 0.0, KeyEffectTrajectory(t * 24, -(52 + (1 - abs(t)) * 12), 0.6, 1.1, t * 0.3, 1.0), i * 0.06)
        }
        KeywordKind.LOVE -> (0 until 5).map { i ->
            val t = (i - 2) / 2.0
            Particle(Shape.HEART, intArrayOf(0xFF3B6B, 0xFF7AA2, 0xE91E63)[i % 3], 0.0, 0.0,
                KeyEffectTrajectory(t * 30, -(44 + (i % 3) * 8.0), 0.5, 1.1, t * 0.3, 0.95, sway = 5.0), i * 0.04)
        }
        KeywordKind.ANGRY -> listOf(Particle(Shape.EMOJI, 0, 0.0, 0.0, KeyEffectTrajectory(0.0, -22.0, 0.6, 1.2, 0.0, 0.8), 0.0)) +
            (0 until 4).map { i ->
                val side = if (i % 2 == 0) -1.0 else 1.0
                Particle(Shape.PUFF, 0xB0B0B0, side * 10, -6.0,
                    KeyEffectTrajectory(side * (10 + i * 3.0), -(30 + i * 4.0), 0.5, 1.8, 0.0, 0.8, sway = 3.0), 0.08 + i * 0.06)
            }
        KeywordKind.TET -> {
            val out = ArrayList<Particle>(20)
            for (c in 0 until 2) {
                val side = if (c == 0) -1.0 else 1.0
                val rise = 56.0 + c * 10
                val start = c * 0.12
                out.add(Particle(Shape.CRACKER, RED, side * 6, 0.0, KeyEffectTrajectory(side * 14, -rise, 1.0, 0.9, side * 0.4, CRACKER_RISE), start))
                val px = side * 20; val py = -rise
                for (s in 0 until 5) {   // nổ: tia vàng / đỏ toả tròn ở đỉnh
                    val a = s * 2 * Math.PI / 5 + c * 0.6
                    out.add(Particle(Shape.SPARK, if (s % 2 == 0) GOLD else RED, px, py,
                        KeyEffectTrajectory(cos(a) * 22, sin(a) * 22, 1.0, 0.4, 0.0, 0.45), start + CRACKER_RISE))
                }
                for (b in 0 until 3) {   // xác pháo đỏ rơi, lắc, xoay
                    val t = b - 1.0
                    out.add(Particle(Shape.PAPER, RED, px, py,
                        KeyEffectTrajectory(t * 18 + side * 6, 44 + b * 12.0, 1.0, 0.9, t * 3 + side, 1.0, sway = 6.0),
                        start + CRACKER_RISE + 0.03, easeIn = true))
                }
            }
            for (e in 0 until 2) {       // lì xì bay lên
                val side = if (e == 0) -1.0 else 1.0
                out.add(Particle(Shape.ENVELOPE, RED, side * 4, 0.0,
                    KeyEffectTrajectory(side * (20 + e * 8.0), -(70 + e * 10.0), 0.7, 1.0, side * 0.25, 1.3, sway = 6.0), 0.1 + e * 0.15))
            }
            out
        }
    }

    /** Thời gian chùm [k] (giây) — hết thì thôi vẽ. */
    fun lifetime(k: KeywordKind): Double = particles(k).maxOf { it.delay + it.traj.duration }
}

/**
 * "Chữ bay": ĐÚNG chữ vừa ra (kể cả dấu — lấy từ engine, không phải nhãn phím) bay lên từ phím, hơi xoay/lệch rồi mờ.
 * Pool [POOL] chữ. = iOS FlyingLetters.
 */
object FlyingLetters {
    const val POOL = 6
    const val DURATION = 0.7
    const val RISE = 46.0
    const val SIZE = 22.0

    /**
     * Chữ vừa ra khi từ đang soạn đổi [before] → [after]: dài ra ⇒ ký tự cuối; cùng độ dài ⇒ ký tự cuối cùng KHÁC
     * ("hoan"+"s" ⇒ "á", "tuong"+"w" ⇒ "ơ"). Từ rỗng (ký hiệu, ngoài soạn từ) ⇒ [typed] nếu là đúng một ký tự in
     * được. Không đổi / khoảng trắng ⇒ null.
     */
    fun glyph(before: String, after: String, typed: String?): String? {
        if (after.isNotEmpty()) {
            if (after == before) return null
            var i = after.length - 1
            if (after.length == before.length) while (i > 0 && after[i] == before[i]) i--
            if (i > 0 && Character.isLowSurrogate(after[i])) i--
            return after.substring(i, minOf(after.length, i + Character.charCount(after.codePointAt(i))))
        }
        val t = typed ?: return null
        if (t.isBlank() || t.codePointCount(0, t.length) != 1) return null
        return t
    }

    /** Lệch ngang (dp) tất định theo lần bấm [seed]. */
    fun drift(seed: Int): Double = (fxValue(fxStep(fxSeed(seed * 37 + 11))) - 0.5) * 24
    /** Xoay (rad) tất định theo lần bấm [seed]. */
    fun spin(seed: Int): Double = (fxValue(fxStep(fxStep(fxSeed(seed * 37 + 11)))) - 0.5) * 0.6
}

/**
 * "Hạt cát": chạm phím ⇒ vài hạt rơi xuống đáy bàn phím rồi TÍCH LẠI thành đống thấp (mảng chiều cao theo cột — không
 * mô phỏng hạt đã đáp). Trần [MAX_HEIGHT]; ngừng gõ [IDLE_MS] ⇒ lún dần trong [SINK_MS] rồi sạch; ẩn bàn phím ⇒ xoá.
 * Mảng cấp sẵn, không cấp phát. Đơn vị dp (iOS pt). = iOS SandPile.
 */
class SandPile(widthUnits: Double) {
    val columns: Int = columnsFor(widthUnits)
    val heights = DoubleArray(columns)

    fun column(x: Double): Int = (x / COLUMN).toInt().coerceIn(0, columns - 1)
    fun surface(x: Double): Double = heights[column(x)]
    val isEmpty: Boolean get() = heights.all { it <= 1e-6 }
    val maxHeight: Double get() = heights.max()

    /** Một hạt đáp tại [x]: cột cao thêm [GRAIN] (trần — đầy thì lăn sang cột thấp hơn), rồi sạt cho dốc ≤ [SLOPE]. */
    fun deposit(x: Double) {
        var c = column(x)
        var guard = 0
        while (heights[c] + GRAIN > MAX_HEIGHT) {
            val l = if (c > 0) heights[c - 1] else Double.MAX_VALUE
            val r = if (c < columns - 1) heights[c + 1] else Double.MAX_VALUE
            if (minOf(l, r) >= heights[c] || guard++ > columns) return   // đáy phẳng đã đầy: bỏ hạt
            c = if (l <= r) c - 1 else c + 1
        }
        heights[c] += GRAIN
        relax(c)
    }

    private fun relax(start: Int) {
        var c = start
        for (pass in 0 until columns) {
            val l = if (c > 0) heights[c] - heights[c - 1] else 0.0
            val r = if (c < columns - 1) heights[c] - heights[c + 1] else 0.0
            if (l <= SLOPE && r <= SLOPE) return
            val n = if (l >= r) c - 1 else c + 1
            val move = (heights[c] - heights[n]) / 2
            heights[c] -= move; heights[n] += move
            c = n
        }
    }

    /** Nhân mọi cột với [f] (lún). */
    fun scale(f: Double) { val k = f.coerceIn(0.0, 1.0); for (i in heights.indices) heights[i] *= k }
    fun clear() { heights.fill(0.0) }

    companion object {
        const val COLUMN = 3.0
        /** Số cột cho bề ngang [w] (dp). */
        fun columnsFor(w: Double): Int = maxOf(1, Math.ceil(maxOf(w, 1.0) / COLUMN).toInt())
        const val GRAIN = 0.6
        const val MAX_HEIGHT = 5.0
        const val SLOPE = 0.9
        const val GRAINS_PER_TAP = 3
        const val GRAIN_SIZE = 1.8
        /** Gia tốc rơi (dp/s²). */
        const val GRAVITY = 1800.0
        const val IDLE_MS = 1200L
        const val SINK_MS = 1500L
        const val COLOR = 0xD9B26A
        /** Hạt đang bay tối đa (pool). */
        const val FLYING = 12

        /** Thời gian rơi [d] dp (giây). */
        fun fallTime(d: Double): Double = Math.sqrt(2 * maxOf(d, 0.0) / GRAVITY)
        /** Hệ số còn lại của đống sau [idleMs] không gõ: 1 tới IDLE_MS rồi giảm tuyến tính về 0 trong SINK_MS. */
        fun sinkFactor(idleMs: Long): Double = when {
            idleMs <= IDLE_MS -> 1.0
            idleMs >= IDLE_MS + SINK_MS -> 0.0
            else -> 1.0 - (idleMs - IDLE_MS).toDouble() / SINK_MS
        }
        /** Lệch ngang hạt [i] của lần bấm [seed] (dp). */
        fun spread(i: Int, seed: Int): Double = (fxValue(fxStep(fxSeed(seed * 53 + i * 7 + 3))) - 0.5) * 16
    }
}

/**
 * "Biển" (theme Biển, 11/2026): SÓNG VỖ BỜ là phần chính — gõ ⇒ một con sóng cuộn từ đỉnh bàn phím xuống đáy (đáy = bờ
 * cát): mặt sóng cong, mép bọt trắng; chạm bờ thì vỡ bọt tràn dọc đáy rồi rút, để lại vệt ướt mờ dần. Gõ liên tiếp ⇒ sóng
 * nối nhau (cách nhau ≥ [LAUNCH_GAP], tối đa [MAX_WAVES] — sóng mới không bao giờ cướp sóng đang chạy); gõ nhanh (mức
 * [ComboMeter]) ⇒ sóng to hơn. Phụ: vài giọt bọt bắn ở phím + 2 bong bóng lắc lên rồi vỡ thành vòng; combo lên
 * [FISH_LEVEL] ⇒ một chú cá bơi ngang một lần. Nghỉ gõ = không còn khung hình nào. Thời gian giây, đơn vị dp (iOS pt).
 * = iOS SeaFx (test số chung).
 * Phil 08/11/2026: sóng chạy nhanh quá ⇒ chậm ~1,9× như sóng lừng ngoài biển (cuộn 1,15 s êm — chậm lúc đầu, đều, chỉ nhanh
 * dần chút trước khi chạm bờ; vỡ 0,55 s; rút 1,3 s) + mỗi con sóng mới một tiếng "ào" ([KeySoundSynth.surfSamples], tiếng
 * vỡ trùng lúc sóng chạm bờ) khi Âm thanh phím bật.
 */
object SeaFx {
    // Sóng vỗ bờ
    const val MAX_WAVES = 3
    const val LAUNCH_GAP = 1.0
    /** Cuộn từ đỉnh xuống bờ / vỡ bọt tràn lên / rút (giây). */
    const val ROLL = 1.15
    const val BREAK = 0.55
    const val RECEDE = 1.3
    const val LIFE = ROLL + BREAK + RECEDE
    const val BODY_HEIGHT = 26.0
    const val BODY_ALPHA = 0.22
    const val FOAM_ALPHA = 0.85
    const val FOAM_WIDTH = 2.5
    const val CREST_AMP = 3.5
    const val WAVELENGTH = 110.0
    const val DRIFT = 16.0
    const val WASH_MAX = 14.0
    const val WET_PEAK = 0.3
    /** Bước lấy mẫu mép sóng (dp). */
    const val STEP = 8.0
    /** Cỡ sóng theo mức combo 0…3. */
    val SIZES = doubleArrayOf(1.0, 1.2, 1.4, 1.65)

    fun size(level: Int): Double = SIZES[level.coerceIn(0, SIZES.size - 1)]
    /** Sóng mới chỉ khi sóng trước đã đi được [LAUNCH_GAP] (gõ dồn ⇒ chỉ bọt + bong bóng). */
    fun shouldLaunch(sinceLast: Double): Boolean = sinceLast >= LAUNCH_GAP
    /**
     * Tỉ lệ quãng đỉnh → bờ của mép sóng: sóng lừng — khởi chậm (tốc độ 0,3), đều giữa chừng, nhanh dần CHÚT trước khi chạm
     * bờ (tốc độ cuối 1,5; u² cũ = 0 → 2 như rơi). f(u) = 0,3u + 0,9u² − 0,2u³: f′ > 0, f″ > 0 trên [0, 1].
     */
    fun travel(t: Double): Double = when {
        t <= 0.0 -> 0.0
        t >= ROLL -> 1.0
        else -> { val u = t / ROLL; u * (0.3 + u * (0.9 - 0.2 * u)) }
    }
    fun driftX(t: Double): Double = DRIFT * (t / ROLL).coerceIn(0.0, 1.0)
    /** Pha mép sóng của ô sóng [slot]. */
    fun phase(slot: Int): Double = (abs(slot) % 7) * 0.9
    /** Mép sóng (lệch y, dp) tại [x] — hai điều hoà lệch pha ⇒ đỉnh nhọn lệch như sóng sắp cuộn. */
    fun crestOffset(x: Double, phase: Double): Double {
        val th = 2 * Math.PI * x / WAVELENGTH + phase
        return CREST_AMP * (sin(th) + 0.3 * sin(2 * th + 0.6))
    }
    fun bodyTop(x: Double, phase: Double): Double = -BODY_HEIGHT + 0.5 * crestOffset(x + WAVELENGTH / 3, phase)
    fun washTop(x: Double, phase: Double): Double = -WASH_MAX + 0.4 * crestOffset(x, phase + 1)
    fun waveAlpha(t: Double): Double = when {
        t < 0.0 || t >= ROLL + BREAK -> 0.0
        t < ROLL -> 1.0
        else -> 1 - (t - ROLL) / BREAK
    }
    /** Chiều cao bọt tràn ở bờ (dp): dâng nhanh khi vỡ, rút tuyến tính. */
    fun washHeight(t: Double, size: Double): Double {
        val a = t - ROLL
        if (a <= 0.0 || t >= LIFE) return 0.0
        if (a < BREAK) { val u = a / BREAK; return WASH_MAX * size * (1 - (1 - u) * (1 - u)) }
        return WASH_MAX * size * (1 - (a - BREAK) / RECEDE)
    }
    /** Vệt ướt lúc nước rút: đậm nhất khi bọt bắt đầu rút, mờ về 0. */
    fun wetAlpha(t: Double): Double {
        val a = t - ROLL - BREAK
        if (a < 0.0 || t >= LIFE) return 0.0
        return WET_PEAK * (1 - a / RECEDE)
    }

    // Bọt bắn + bong bóng ở phím
    const val DROPLETS_PER_TAP = 3
    const val BUBBLES_PER_TAP = 2
    const val TAP_SLOTS = 4
    const val LAYERS_PER_TAP = DROPLETS_PER_TAP + BUBBLES_PER_TAP
    val DROPLET_DX = doubleArrayOf(-14.0, 3.0, 15.0)
    val DROPLET_PEAK = doubleArrayOf(16.0, 22.0, 13.0)
    const val DROPLET_SINK = 12.0
    const val DROPLET_DURATION = 0.45
    const val DROPLET_RADIUS = 1.8
    /** Giọt [i] ở tỉ lệ thời gian [f]: vòng cung lên rồi rơi (gốc = phím). Ghi (x, y) vào [out]. */
    fun droplet(i: Int, f: Double, out: DoubleArray) {
        val k = f.coerceIn(0.0, 1.0); val j = i % DROPLETS_PER_TAP
        out[0] = DROPLET_DX[j] * k
        out[1] = -DROPLET_PEAK[j] * 4 * k * (1 - k) + DROPLET_SINK * k * k
    }
    val BUBBLE_DX = doubleArrayOf(-5.0, 6.0)
    val BUBBLE_RISE = doubleArrayOf(44.0, 56.0)
    const val BUBBLE_DURATION = 0.9
    const val BUBBLE_RADIUS = 3.5
    const val BUBBLE_SWAY = 3.5
    const val POP_AT = 0.85
    const val POP_SCALE = 1.8
    /** Bong bóng [i] ở [f]: ghi (x, y, scale, alpha) vào [out]. Từ [POP_AT] phồng tới [POP_SCALE] + tan (vòng "póc"). */
    fun bubble(i: Int, f: Double, out: DoubleArray) {
        val k = f.coerceIn(0.0, 1.0); val j = i % BUBBLES_PER_TAP
        val e = 1 - (1 - k) * (1 - k)
        out[0] = BUBBLE_DX[j] + BUBBLE_SWAY * sin(2 * Math.PI * 1.5 * k + j * Math.PI)
        out[1] = -BUBBLE_RISE[j] * e
        if (k < POP_AT) { out[2] = 0.6 + 0.4 * k / POP_AT; out[3] = 1.0 } else {
            val p = (k - POP_AT) / (1 - POP_AT)
            out[2] = 1 + (POP_SCALE - 1) * p; out[3] = 1 - p
        }
    }

    // Cá bơi khi gõ combo
    const val FISH_LEVEL = 2
    const val FISH_COOLDOWN = 4.0
    const val FISH_DURATION = 2.8
    const val FISH_SIZE = 24.0
    const val FISH_MARGIN = 14.0
    const val FISH_BOB = 3.0
    val FISH_GLYPHS = listOf("🐟", "🐠") // l10n-skip (emoji)
    /** Cá bơi khi mức combo VỪA lên [FISH_LEVEL] và đã nghỉ cá ≥ [FISH_COOLDOWN] giây. */
    fun fishShouldSwim(level: Int, previous: Int, sinceLastFish: Double): Boolean =
        level >= FISH_LEVEL && previous < FISH_LEVEL && sinceLastFish >= FISH_COOLDOWN
    fun fishRightToLeft(seq: Int): Boolean = seq % 2 == 0
    fun fishY(seq: Int, height: Double): Double = height * (0.25 + 0.35 * fxValue(fxStep(fxSeed(seq * 29 + 5))))
    fun fishX(f: Double, width: Double, rightToLeft: Boolean): Double {
        val k = f.coerceIn(0.0, 1.0); val a = FISH_MARGIN; val b = maxOf(width - FISH_MARGIN, FISH_MARGIN)
        return if (rightToLeft) b + (a - b) * k else a + (b - a) * k
    }
    fun fishBobY(f: Double): Double = FISH_BOB * sin(2 * Math.PI * 3 * f)
    fun fishAlpha(f: Double): Double = if (f < 0.0 || f >= 1.0) 0.0 else minOf(1.0, f / 0.1, (1 - f) / 0.1)

    // Tiếng sóng vỗ ([KeySoundSynth.surfSamples]): MỖI CON SÓNG MỚI một tiếng (không mỗi phím), chỉ khi Âm thanh phím bật.
    /** Tối đa bấy nhiêu tiếng sóng chồng nhau (tiếng 1,6 s, sóng cách ≥ [LAUNCH_GAP] ⇒ ≤ 2) — tiếng thứ 3 thay tiếng cũ nhất. */
    const val SURF_VOICES = 2
    /** Âm lượng tiếng sóng theo cỡ sóng: cỡ thường 0,7 → cỡ combo lớn nhất 1,0 (nhân âm lượng phím của user). */
    fun surfVolume(size: Double): Double = 0.7 + 0.3 * ((size - 1) / (SIZES[SIZES.size - 1] - 1)).coerceIn(0.0, 1.0)
}

/**
 * "Token AI" (theme AI, 11/2026): ĐÚNG chữ engine vừa ra (như Chữ bay — [FlyingLetters.glyph]) loé ở mép trên phím rồi VỠ
 * thành 3…6 "token" (chip bo tròn nhỏ, gradient phát sáng tím / lam / hồng) bay theo đường cong (Bézier bậc 2) VÀO thanh
 * gợi ý (tâm dải gợi ý, hoặc Mắt AI nếu đang bật). Gợi ý đổi THẬT ⇒ vệt sáng quét dải MỘT lần ([ShimmerGate]).
 * Hàm thuần = iOS TokenStream — CÙNG SỐ (test chéo hai nền tảng). Đơn vị dp (iOS pt) — đường cong tính bằng px thì
 * truyền khung px, chỉ hằng số dp nhân density.
 */
object TokenStream {
    /** Số chùm bay cùng lúc (xoay vòng). */
    const val POOL = 4
    const val MIN_CHIPS = 3
    const val MAX_CHIPS = 6
    /** Trần chip đang có (mọi chùm). */
    const val CAP = POOL * MAX_CHIPS
    const val CHIP_W = 7.0
    const val CHIP_H = 4.0
    const val CHIP_RADIUS = 2.0
    /** Màu chip (RGB): tím, lam ngọc, hồng — chip i gradient màu i → màu i+1. */
    val COLORS = intArrayOf(0xA855F7, 0x22D3EE, 0xF472B6)
    const val GLYPH_TIME = 0.16
    const val GLYPH_SIZE = 20.0
    const val FLIGHT = 0.55
    const val STAGGER = 0.035
    const val SPREAD = 6.0
    const val BEND = 42.0
    /** Điểm điều khiển / đích cách mép ≥ INSET ⇒ cả đường cong (bao lồi) nằm TRONG bàn phím. */
    const val INSET = 2.0
    const val END_SCALE = 0.45

    /** Số chip: 3 + số dấu (NFD, tối đa 2) + chẵn/lẻ mã chữ gốc ⇒ 3…6. "b" 3, "a" 4, "đ" 4, "á" 5, "ế" 6. */
    fun chipCount(glyph: String): Int {
        val nfd = java.text.Normalizer.normalize(glyph, java.text.Normalizer.Form.NFD)
        if (nfd.isEmpty()) return MIN_CHIPS
        val base = nfd.codePointAt(0)
        val n = nfd.codePointCount(0, nfd.length)
        return minOf(MAX_CHIPS, MIN_CHIPS + minOf(n - 1, 2) + base % 2)
    }

    /** Hệ số toả chip [i] trong [n] chip: −1…1. */
    fun fan(i: Int, n: Int): Double = if (n > 1) (i - (n - 1) / 2.0) / ((n - 1) / 2.0) else 0.0

    /** Kẹp (x, y) vào [inset, w − inset] × [inset, h − inset] → [out] (x, y). [inset] cùng đơn vị với w/h. */
    fun clamp(x: Double, y: Double, w: Double, h: Double, out: DoubleArray, inset: Double = INSET) {
        out[0] = x.coerceIn(inset, maxOf(inset, w - inset)); out[1] = y.coerceIn(inset, maxOf(inset, h - inset))
    }

    /** Điểm xuất phát chip [i]/[n] quanh mép trên phím ([kx], [ky]) → [out]. [unit] = px mỗi dp (1 = dp). */
    fun start(kx: Double, ky: Double, i: Int, n: Int, w: Double, h: Double, out: DoubleArray, unit: Double = 1.0) =
        clamp(kx + (i - (n - 1) / 2.0) * SPREAD * unit, ky, w, h, out, INSET * unit)

    /**
     * Điểm điều khiển — lệch VUÔNG GÓC khỏi trung điểm, cùng phía cho cả chùm (vòng cung vồng LÊN; bay thẳng đứng ⇒
     * sang phải), chip ngoài cong hơn; kẹp trong khung ⇒ đường cong không ra ngoài bàn phím. → [out].
     */
    fun control(x0: Double, y0: Double, x1: Double, y1: Double, i: Int, n: Int, w: Double, h: Double, out: DoubleArray,
                unit: Double = 1.0) {
        val dx = x1 - x0; val dy = y1 - y0
        val len = Math.hypot(dx, dy)
        if (len <= 1e-9) { clamp(x0, y0, w, h, out, INSET * unit); return }
        var nx = -dy / len; var ny = dx / len
        if (ny > 0 || (ny == 0.0 && nx < 0)) { nx = -nx; ny = -ny }
        val k = minOf(BEND * unit, len * 0.35) * (0.55 + 0.45 * fan(i, n))
        clamp((x0 + x1) / 2 + nx * k, (y0 + y1) / 2 + ny * k, w, h, out, INSET * unit)
    }

    /** Điểm Bézier bậc 2 tại [t] (đã qua [ease]) → [out]. */
    fun point(x0: Double, y0: Double, cx: Double, cy: Double, x1: Double, y1: Double, t: Double, out: DoubleArray) {
        val u = 1 - t
        out[0] = u * u * x0 + 2 * u * t * cx + t * t * x1
        out[1] = u * u * y0 + 2 * u * t * cy + t * t * y1
    }

    fun delay(i: Int): Double = GLYPH_TIME / 2 + i * STAGGER
    val lifetime: Double get() = delay(MAX_CHIPS - 1) + FLIGHT
    fun ease(f: Double): Double { val x = f.coerceIn(0.0, 1.0); return x * x }
    fun alpha(f: Double): Double = when {
        f < 0 || f > 1 -> 0.0
        f < 0.12 -> f / 0.12
        f < 0.75 -> 1.0
        else -> (1 - f) / 0.25
    }
    fun scale(f: Double): Double = 1 - (1 - END_SCALE) * f.coerceIn(0.0, 1.0)
}

/**
 * Vệt sáng quét thanh gợi ý khi gợi ý ĐỔI THẬT (Token AI): cùng danh sách từ ⇒ không; rỗng ⇒ không; đổi quá dồn
 * (< [MIN_GAP] từ lần quét trước) ⇒ bỏ. = iOS ShimmerGate.
 */
class ShimmerGate {
    var words: List<String> = emptyList(); private set
    private var last = -Double.MAX_VALUE

    /** Gợi ý đang hiện là [w] lúc [t] (giây) ⇒ true = quét một lần. */
    fun update(w: List<String>, t: Double): Boolean {
        if (w == words) return false
        words = w
        if (w.isEmpty() || t - last < MIN_GAP) return false
        last = t
        return true
    }
    fun reset() { words = emptyList(); last = -Double.MAX_VALUE }

    companion object {
        const val DURATION = 0.3
        const val MIN_GAP = 0.35
        const val BAND = 0.35
        const val PEAK_ALPHA = 0.35
        /** Mép trái vệt ở tiến độ [f] với dải rộng [w]: từ −BAND·w tới w. */
        fun left(f: Double, w: Double): Double { val b = BAND * w; return -b + f.coerceIn(0.0, 1.0) * (w + b) }
    }
}

/**
 * "Sàn nhảy LED" (theme Neon Night Club, 11/2026): phím vừa bấm + các ô quanh nó thắp neon hồng / tím / lục lam như sàn
 * nhảy LED — vòng 0 (chính phím) rồi vòng vuông 1, 2 lan ra cách nhau [RING_DELAY], mỗi ô tắt trong [TILE_LIFE]. Ô hàng xóm
 * theo lưới bước = cỡ phím × ([PITCH_X], [PITCH_Y]); phím rộng (cách / Enter) ⇒ ô hàng xóm rộng tối đa 0,85 × cao, dời ra
 * ngoài mép phím. Gõ dồn ([ComboMeter] mức 3) ⇒ cả bàn phím nháy một nhịp (trần 1,2 s, ≤ 120 ô). Chỉ vector. = iOS DanceFloor.
 */
object DanceFloor {
    const val RINGS = 3
    const val RING_DELAY = 0.06
    const val TILE_LIFE = 0.26
    const val PEAK = 0.55
    const val PITCH_X = 1.18
    const val PITCH_Y = 1.28
    const val UNIT_ASPECT = 0.85
    const val CORNER_FACTOR = 0.18
    /** Hồng, tím, lục lam (= [SpotlightFx.COLORS]). */
    val COLORS = intArrayOf(0xFF2FD0, 0x9B5CFF, 0x2FE6FF)
    const val POOL = 3
    const val FLICKER_LEVEL = 3
    const val FLICKER_COOLDOWN = 1.2
    const val FLICKER_DURATION = 0.2
    const val FLICKER_PEAK = 0.22
    const val MAX_GRID = 120

    data class Tile(val ring: Int, val color: Int, val x: Double, val y: Double, val w: Double, val h: Double)

    fun ring(i: Int, j: Int): Int = maxOf(kotlin.math.abs(i), kotlin.math.abs(j))
    fun colorIndex(i: Int, j: Int, seed: Int): Int = (((i - j + seed) % 3) + 3) % 3
    /** Độ sáng ô vòng [ring] sau [dt] giây kể từ lúc bấm: bật ngay khi tới lượt vòng, tắt (1−u)². */
    fun alpha(dt: Double, ring: Int): Double {
        val t = dt - ring * RING_DELAY
        if (t < 0 || t >= TILE_LIFE) return 0.0
        val u = t / TILE_LIFE
        return PEAK * (1 - u) * (1 - u)
    }
    /** Toàn bộ chùm tắt hẳn sau (giây). */
    val LIFETIME: Double get() = (RINGS - 1) * RING_DELAY + TILE_LIFE
    /** Nháy cả bàn phím: sáng 0–60 ms, tắt 60–100 ms, sáng lại rồi tắt dần tới 200 ms. */
    fun flickerAlpha(dt: Double): Double {
        if (dt < 0 || dt >= FLICKER_DURATION) return 0.0
        if (dt < 0.06) return FLICKER_PEAK
        if (dt < 0.10) return 0.0
        return FLICKER_PEAK * (1 - (dt - 0.10) / 0.10)
    }
    /** Cổng nháy cả bàn phím: chỉ ở mức combo ≥ [FLICKER_LEVEL], cách nhau ≥ [FLICKER_COOLDOWN]. */
    class FlickerGate {
        var last = Double.NEGATIVE_INFINITY; private set
        var fired = 0; private set
        fun trigger(level: Int, t: Double): Boolean {
            if (level < FLICKER_LEVEL || t - last < FLICKER_COOLDOWN) return false
            last = t; fired++
            return true
        }
    }

    /** Bề rộng ô hàng xóm. */
    fun unit(w: Double, h: Double): Double = minOf(w, h * UNIT_ASPECT)
    /** Tâm ô (i, j) quanh phím tâm (cx, cy) cỡ w × h. */
    fun center(i: Int, j: Int, cx: Double, cy: Double, w: Double, h: Double): DoubleArray {
        val u = unit(w, h)
        val sx = if (i == 0) 0.0 else if (i > 0) 1.0 else -1.0
        return doubleArrayOf(cx + sx * ((w - u) / 2 + kotlin.math.abs(i) * u * PITCH_X), cy + j * h * PITCH_Y)
    }

    /** Các ô vòng 0…RINGS−1 (vòng 0 = đúng khung phím), thứ tự hàng j rồi cột i (−2…2). */
    fun tiles(cx: Double, cy: Double, w: Double, h: Double, seed: Int): List<Tile> {
        val out = ArrayList<Tile>(25)
        val n = RINGS - 1; val u = unit(w, h)
        for (j in -n..n) for (i in -n..n) {
            val c = center(i, j, cx, cy, w, h)
            out.add(Tile(ring(i, j), colorIndex(i, j, seed), c[0], c[1], if (i == 0 && j == 0) w else u, h))
        }
        return out
    }

    /** Lưới phủ cả bàn phím (nháy combo) theo bước của phím vừa bấm — tâm ô trong khung, trần [MAX_GRID] ô. */
    fun grid(bx: Double, by: Double, bw: Double, bh: Double, cx: Double, cy: Double, w: Double, h: Double, seed: Int): List<Tile> {
        val u = unit(w, h); val px = u * PITCH_X; val py = h * PITCH_Y
        if (px <= 1 || py <= 1 || bw <= 0 || bh <= 0) return emptyList()
        val i0 = kotlin.math.floor((bx - cx) / px).toInt(); val i1 = kotlin.math.ceil((bx + bw - cx) / px).toInt()
        val j0 = kotlin.math.floor((by - cy) / py).toInt(); val j1 = kotlin.math.ceil((by + bh - cy) / py).toInt()
        val out = ArrayList<Tile>()
        for (j in j0..j1) for (i in i0..i1) {
            val x = cx + i * px; val y = cy + j * py
            if (x < bx || x > bx + bw || y < by || y > by + bh || out.size >= MAX_GRID) continue
            out.add(Tile(0, colorIndex(i, j, seed), x, y, u, h))
        }
        return out
    }
}

/**
 * "Sàn nhảy LED" — cú FLASH stroboscope: bấm PHÍM CÁCH (hết một từ — trùng nhịp kick của âm Nhịp club) ⇒ lớp phủ TOÀN
 * bàn phím, SAU phím (nền / ảnh / nhân vật loé sáng, chữ phím vẫn đọc được), trắng ngả màu neon của nhịp, lên [RISE]
 * rồi tắt (1−u)² trong [FALL]. Phím chữ không flash. AN TOÀN cảm quang (WCAG 2.3.1): tối đa [MAX_PER_SECOND] lần mỗi
 * giây — [Gate] dùng CHUNG với nhịp nháy cả bàn phím của [DanceFloor]; quá thì bỏ qua. Không phụ thuộc Giảm chuyển động.
 * = iOS BeatFlash.
 */
object BeatFlash {
    const val RISE = 0.02
    const val FALL = 0.11
    const val DURATION = RISE + FALL
    const val PEAK = 0.6
    const val MAX_PER_SECOND = 3
    const val WINDOW = 1.0
    /** Phần màu neon trộn vào trắng. */
    const val TINT_MIX = 0.35

    /** Độ đục sau [dt] giây kể từ cú flash. */
    fun alpha(dt: Double): Double {
        if (dt < 0 || dt >= DURATION) return 0.0
        if (dt < RISE) return PEAK * dt / RISE
        val u = (dt - RISE) / FALL
        return PEAK * (1 - u) * (1 - u)
    }

    /** Màu nhịp thứ [i]: trắng trộn [TINT_MIX] màu [DanceFloor.COLORS] (0xRRGGBB). */
    fun tint(i: Int): Int {
        val n = DanceFloor.COLORS.size
        val c = DanceFloor.COLORS[((i % n) + n) % n]
        fun ch(sh: Int): Int {
            val v = ((c shr sh) and 0xFF).toDouble()
            return Math.round(255 * (1 - TINT_MIX) + v * TINT_MIX).toInt() shl sh
        }
        return ch(16) or ch(8) or ch(0)
    }

    /** Cổng an toàn: ≤ [MAX_PER_SECOND] lần trong mọi khoảng [WINDOW] giây. Dùng chung cho flash phím cách + nháy cả bàn phím. */
    class Gate {
        private val times = DoubleArray(MAX_PER_SECOND) { Double.NEGATIVE_INFINITY }
        private var head = 0
        var fired = 0; private set
        fun trigger(t: Double): Boolean {
            if (t - times[head] < WINDOW) return false
            times[head] = t; head = (head + 1) % times.size
            fired++
            return true
        }
        fun reset() { times.fill(Double.NEGATIVE_INFINITY); head = 0 }
    }
}
