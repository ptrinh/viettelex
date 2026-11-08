package com.viettelex.keyboard

import kotlin.math.ceil
import kotlin.math.sin

/**
 * "Mưa" (theme Mưa đêm, 11/2026): mưa đêm êm trên ô kính — chậm, dịu, ấm dần.
 *  • Mưa nền: khi đang gõ, vài hạt mưa có vệt trượt xuống "ô kính" (cả bàn phím, rất mờ), trượt — dừng — trượt tiếp
 *    ([PROFILES]), tối đa [MAX_DROPS]; hạt mới chỉ sinh lúc bấm phím, cách nhau ≥ [spawnGap] ⇒ ngừng gõ thì các hạt đang
 *    trượt chạy nốt ([DROP_LIFE] = [IDLE_AFTER]) rồi thôi — nghỉ = 0 khung hình.
 *  • Bấm phím: một giọt rơi xuống đúng phím, loang một vòng nhỏ, rồi lăn xuống để lại vệt ướt ngắn mờ dần.
 *  • Mưa tạnh dần: mỗi lần bàn phím hiện mưa đậm (1.0); cứ [STEP_KEYS] phím mưa thưa đi [STEP_DROP] (sàn
 *    [FLOOR_INTENSITY]), ánh đèn vàng ấm ở góc dưới phải sáng dần 0 → [GLOW_MAX]. Ẩn bàn phím ⇒ về đầu.
 * = iOS RainFx (KeyEffects.swift) — CÙNG SỐ (test chéo hai nền tảng). Thời gian giây, đơn vị dp (iOS pt).
 */
object RainFx {
    // Mưa tạnh dần
    const val STEP_KEYS = 40
    const val STEP_DROP = 0.1
    const val FLOOR_INTENSITY = 0.2
    /** Độ đậm của mưa sau [keys] phím kể từ lúc bàn phím hiện: 1.0 → giảm [STEP_DROP] mỗi [STEP_KEYS] phím, sàn 0.2. */
    fun intensity(keys: Int): Double = maxOf(FLOOR_INTENSITY, 1 - STEP_DROP * (maxOf(keys, 0) / STEP_KEYS))
    const val GLOW_MAX = 0.6
    /** Ánh đèn ấm: 0 khi mưa đậm nhất → [GLOW_MAX] khi mưa thưa tới sàn. */
    fun glow(keys: Int): Double = GLOW_MAX * (1 - intensity(keys)) / (1 - FLOOR_INTENSITY)
    /** Chuyển độ sáng đèn khi mưa thưa một nấc: êm (smoothstep) trong [GLOW_FADE] giây — không bao giờ nháy. */
    const val GLOW_FADE = 1.5
    fun glowAt(from: Double, to: Double, t: Double): Double {
        val u = (t / GLOW_FADE).coerceIn(0.0, 1.0)
        return from + (to - from) * u * u * (3 - 2 * u)
    }
    const val GLOW_COLOR = 0xFFB25C
    val GLOW_STOPS = doubleArrayOf(0.0, 0.45, 1.0)
    val GLOW_ALPHAS = doubleArrayOf(0.42, 0.17, 0.0)
    fun glowCenterX(w: Double): Double = w * 0.9
    fun glowCenterY(h: Double): Double = h * 0.94
    fun glowRadius(w: Double, h: Double): Double = minOf(0.55 * w, 0.9 * h)

    // Mưa nền
    const val MAX_DROPS = 12
    const val DROP_LIFE = 3.0
    const val IDLE_AFTER = 3.0
    const val BASE_GAP = 0.25
    fun spawnGap(intensity: Double): Double = BASE_GAP / maxOf(intensity, FLOOR_INTENSITY)
    fun shouldSpawn(sinceLast: Double, intensity: Double): Boolean = sinceLast >= spawnGap(intensity) - 1e-9
    fun maxInFlight(intensity: Double): Int = minOf(MAX_DROPS, ceil(DROP_LIFE / spawnGap(intensity) - 1e-9).toInt())
    fun isIdle(sinceLastKey: Double): Boolean = sinceLastKey >= IDLE_AFTER
    /** Ba kiểu trượt (t, y xen kẽ): trượt — đọng — trượt — đọng — trượt hết kính. */
    val PROFILES = arrayOf(
        doubleArrayOf(0.0, 0.0, 0.18, 0.22, 0.40, 0.25, 0.58, 0.55, 0.74, 0.57, 1.0, 1.0),
        doubleArrayOf(0.0, 0.0, 0.25, 0.34, 0.50, 0.37, 0.66, 0.66, 0.80, 0.68, 1.0, 1.0),
        doubleArrayOf(0.0, 0.0, 0.12, 0.14, 0.34, 0.16, 0.55, 0.48, 0.72, 0.50, 1.0, 1.0))
    fun profile(slot: Int): Int = ((slot % PROFILES.size) + PROFILES.size) % PROFILES.size
    fun travel(f: Double, profile: Int): Double {
        val k = PROFILES[profile(profile)]
        if (f <= 0.0) return 0.0
        if (f >= 1.0) return 1.0
        var i = 2
        while (i < k.size) {
            if (f <= k[i]) return k[i - 1] + (k[i + 1] - k[i - 1]) * (f - k[i - 2]) / (k[i] - k[i - 2])
            i += 2
        }
        return 1.0
    }
    const val START_ABOVE = 4.0
    const val OVERSHOOT = 18.0
    fun travelDistance(h: Double): Double = h + START_ABOVE + OVERSHOOT
    const val DROP_PEAK_ALPHA = 0.45
    fun dropAlpha(f: Double): Double = if (f < 0.0 || f >= 1.0) 0.0 else DROP_PEAK_ALPHA * minOf(1.0, f / 0.06, (1 - f) / 0.1)
    const val DROP_MARGIN = 10.0
    fun dropX(seq: Int, w: Double): Double = DROP_MARGIN + maxOf(w - 2 * DROP_MARGIN, 0.0) * fxValue(fxStep(fxSeed(seq * 37 + 11)))
    const val HEAD_RX = 1.5
    const val HEAD_RY = 2.1
    const val STREAK_LENGTH = 16.0
    const val STREAK_WIDTH = 1.0
    const val STREAK_ALPHA = 0.55

    // Giọt ở phím
    const val TAP_SLOTS = 6
    const val LAYERS_PER_TAP = 3
    const val FALL_TIME = 0.12
    const val FALL_FROM = 16.0
    const val ROLL_START = 0.2
    const val ROLL_TIME = 1.1
    const val ROLL_DISTANCE = 30.0
    const val ROLL_WIGGLE = 2.5
    const val TRAIL_FADE = 0.8
    const val TAP_LIFE = ROLL_START + ROLL_TIME + TRAIL_FADE
    const val TAP_DROP_RADIUS = 2.2
    const val TAP_DROP_ALPHA = 0.9
    /** Giọt ở phím (gốc = tâm phím, y xuống): ghi (x, y, alpha) vào [out]. */
    fun drop(t: Double, out: DoubleArray) {
        when {
            t < 0.0 -> { out[0] = 0.0; out[1] = -FALL_FROM; out[2] = 0.0 }
            t < FALL_TIME -> { val u = t / FALL_TIME; out[0] = 0.0; out[1] = -FALL_FROM * (1 - u * u); out[2] = TAP_DROP_ALPHA }
            t < ROLL_START -> { out[0] = 0.0; out[1] = 0.0; out[2] = TAP_DROP_ALPHA }
            t < ROLL_START + ROLL_TIME -> {
                val u = (t - ROLL_START) / ROLL_TIME
                out[0] = rollX(u); out[1] = ROLL_DISTANCE * u * u; out[2] = TAP_DROP_ALPHA * (if (u < 0.7) 1.0 else (1 - u) / 0.3)
            }
            else -> { out[0] = rollX(1.0); out[1] = ROLL_DISTANCE; out[2] = 0.0 }
        }
    }
    fun rollX(u: Double): Double = ROLL_WIGGLE * sin(Math.PI * u)
    const val RING_FROM = 1.5
    const val RING_TO = 11.0
    const val RING_TIME = 0.4
    const val RING_ALPHA = 0.7
    const val RING_WIDTH = 1.0
    /** Vòng loang: ghi (bán kính, alpha) vào [out]. */
    fun ring(t: Double, out: DoubleArray) {
        val a = t - FALL_TIME
        if (a < 0.0 || a >= RING_TIME) { out[0] = 0.0; out[1] = 0.0; return }
        val u = a / RING_TIME; val e = 1 - (1 - u) * (1 - u)
        out[0] = RING_FROM + (RING_TO - RING_FROM) * e; out[1] = RING_ALPHA * (1 - u)
    }
    const val TRAIL_ALPHA = 0.35
    const val TRAIL_WIDTH = 1.6
    /** Vệt ướt: ghi (phần đã lăn 0…1 theo quãng, alpha) vào [out]. */
    fun trail(t: Double, out: DoubleArray) {
        val a = t - ROLL_START
        if (a < 0.0) { out[0] = 0.0; out[1] = 0.0; return }
        val u = minOf(a / ROLL_TIME, 1.0)
        if (a < ROLL_TIME) { out[0] = u * u; out[1] = TRAIL_ALPHA; return }
        val fade = (a - ROLL_TIME) / TRAIL_FADE
        out[0] = 1.0; out[1] = if (fade < 1) TRAIL_ALPHA * (1 - fade) else 0.0
    }
}
