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
    STRING("string", "Rung dây"); // l10n-key

    val title: String get() = tr(viTitle)

    /** Mọi kiểu trừ "Không" thuộc Plus. */
    val isPlus: Boolean get() = this != NONE

    /** Kiểu "hạt bay ra từ phím" (quỹ đạo [trajectory]). */
    val isParticle: Boolean get() = this in PARTICLES

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
