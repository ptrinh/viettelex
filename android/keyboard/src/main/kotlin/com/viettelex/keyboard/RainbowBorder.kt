package com.viettelex.keyboard

import kotlin.math.floor
import kotlin.math.max

/**
 * Viền phím cầu vồng — theme "Gaming RGB" (slot "borderFx":"rainbow"). Hằng số + hàm thuần chung iOS
 * (iOS/Keyboard/RainbowBorder.swift, cùng số — test chéo). Vẽ: app/.../ime/RainbowBorderView (MỘT dải gradient che
 * bằng viền mọi phím, chỉ trượt khi đang gõ; nghỉ ⇒ giảm tốc + mờ dần xuống ánh nghỉ rồi thôi hẹn khung hình).
 *
 * PHỦ KÍN: một chu kỳ màu = một bề ngang W, dải rộng 2W = W + một chu kỳ, độ lệch hiển thị luôn lấy dư theo chu kỳ
 * (∈ [0, 1)) ⇒ dải luôn phủ [0, W] (bug iOS "tắt đèn từ phía phải qua" 19/10/2026: vòng lặp không lấy dư).
 */
object RainbowBorder {
    /** Một chu kỳ cầu vồng trượt hết một bề ngang bàn phím (giây) — ở tốc độ đầy. */
    const val PERIOD = 4.0
    /** Nghỉ gõ chừng này ⇒ bắt đầu dừng (giây). */
    const val IDLE_AFTER = 1.2
    /** Độ dày viền (dp). */
    const val LINE_WIDTH = 1.5
    /** Giảm tốc từ tốc độ đầy tới dừng (giây). */
    const val DECEL_TIME = 1.0
    /** Tăng tốc từ đứng yên tới tốc độ đầy (giây). */
    const val ACCEL_TIME = 0.4
    /** Mờ dần xuống ánh nghỉ (giây) — cùng lúc giảm tốc. */
    const val FADE_OUT_TIME = 1.0
    /** Sáng lại 100% khi gõ tiếp (giây). */
    const val FADE_IN_TIME = 0.2
    /** Độ sáng (alpha) ánh nghỉ. */
    const val REST_ALPHA = 0.58
    /** Số chu kỳ màu trên dải (dải rộng = STRIP_PERIODS · W; cần ≥ W + một chu kỳ). */
    const val STRIP_PERIODS = 2
    /** Một chu kỳ màu (RGB); dải gradient lặp HAI lần để dịch đúng một bề ngang là liền mạch. */
    val HUES = intArrayOf(0xFF3B30, 0xFF9500, 0xFFCC00, 0x34C759, 0x00C7BE, 0x007AFF, 0xAF52DE, 0xFF3B30)

    /** Màu (RGB) + vị trí (0…1) của dải 2 chu kỳ — 15 điểm, y hệt iOS stops(). */
    fun stops(): Pair<IntArray, DoubleArray> {
        val n = HUES.size - 1
        val colors = ArrayList<Int>(); val pos = ArrayList<Double>()
        for (cycle in 0 until 2) for (i in 0 until n) { colors.add(HUES[i]); pos.add((cycle + i.toDouble() / n) / 2) }
        colors.add(HUES[n]); pos.add(1.0)
        return colors.toIntArray() to pos.toDoubleArray()
    }

    /** Lấy dư theo chu kỳ: luôn trong [0, 1). */
    fun wrap(x: Double): Double {
        val v = x - floor(x)
        return if (v >= 1) 0.0 else v
    }

    /** Độ lệch (0…1 bề ngang) sau [elapsed] giây chạy đầy tốc kể từ lệch [from] — tuần hoàn, luôn trong [0, 1). */
    fun offset(from: Double, elapsed: Double): Double = wrap(from + elapsed / PERIOD)

    /** Khoảng (đầu, cuối) (đơn vị bề ngang) dải phủ khi lệch [offset] (dải ở x = −offset·W, rộng STRIP_PERIODS·W). */
    fun coverage(offset: Double): Pair<Double, Double> = -offset to (STRIP_PERIODS - offset)
}

/**
 * Đường chuyển động của dải (thuần; iOS RainbowMotion y hệt). Đơn vị: chu kỳ màu (= một bề ngang); tốc độ đầy =
 * 1/PERIOD chu kỳ/giây. Từ [t0] ở [x0], tốc độ đổi tuyến tính [v0] → [v1] trong [ramp] giây rồi giữ [v1].
 */
data class RainbowMotion(
    val t0: Double = 0.0, val x0: Double = 0.0, val v0: Double = 0.0, val v1: Double = 0.0, val ramp: Double = 0.0,
) {
    val rampEnd: Double get() = t0 + ramp

    /** Quãng đã đi (chưa lấy dư). */
    fun travelled(t: Double): Double {
        val tau = max(0.0, t - t0)
        if (tau < ramp) return x0 + v0 * tau + (v1 - v0) * tau * tau / (2 * ramp)
        return x0 + (v0 + v1) * ramp / 2 + v1 * (tau - ramp)
    }
    fun velocity(t: Double): Double {
        val tau = max(0.0, t - t0)
        return if (tau < ramp) v0 + (v1 - v0) * tau / ramp else v1
    }
    /** Độ lệch hiển thị (đã lấy dư, ∈ [0, 1)). */
    fun offset(t: Double): Double = RainbowBorder.wrap(travelled(t))

    /** Gõ tiếp lúc [t]: tăng tốc từ tốc độ hiện tại tới đầy (đang giảm tốc dở ⇒ ramp ngắn hơn, không giật). */
    fun resumed(t: Double): RainbowMotion {
        val v = velocity(t)
        return RainbowMotion(t, offset(t), v, FULL_SPEED, RainbowBorder.ACCEL_TIME * max(0.0, 1 - v / FULL_SPEED))
    }
    /** Nghỉ lúc [t]: giảm tốc đều tới dừng (từ tốc độ đầy mất DECEL_TIME). */
    fun settled(t: Double): RainbowMotion {
        val v = velocity(t)
        return RainbowMotion(t, offset(t), v, 0.0, RainbowBorder.DECEL_TIME * v / FULL_SPEED)
    }

    companion object {
        const val FULL_SPEED = 1 / RainbowBorder.PERIOD
        fun rest(x: Double) = RainbowMotion(x0 = RainbowBorder.wrap(x))
    }
}

/** Độ sáng dải theo thời gian (thuần; iOS RainbowFade y hệt): [from] → [to] trong [duration] giây, ease in-out. */
data class RainbowFade(
    val t0: Double = 0.0, val from: Double = RainbowBorder.REST_ALPHA, val to: Double = RainbowBorder.REST_ALPHA,
    val duration: Double = 0.0,
) {
    val end: Double get() = t0 + duration
    fun alpha(t: Double): Double {
        if (duration <= 0 || t >= end) return to
        val u = max(0.0, (t - t0) / duration)
        return from + (to - from) * u * u * (3 - 2 * u)
    }
    fun toward(a: Double, t: Double, d: Double) = RainbowFade(t, alpha(t), a, d)
}

/** Đồng hồ "chỉ chạy khi đang gõ" (thuần; giây) — iOS RainbowClock y hệt. */
class RainbowClock(var idleAfter: Double = RainbowBorder.IDLE_AFTER) {
    var running = false
        private set
    var lastInput = Double.NEGATIVE_INFINITY
        private set

    /** Một phím lúc [t]; true = vừa chuyển nghỉ → chạy. */
    fun poke(t: Double): Boolean {
        lastInput = t
        if (running) return false
        running = true
        return true
    }

    /** Còn bao lâu nữa thì nghỉ (≤ 0 ⇒ nghỉ ngay). */
    fun idleRemaining(t: Double): Double = idleAfter - (t - lastInput)

    fun stop() { running = false }
}

/**
 * Bộ điều khiển của RainbowBorderView (thuần — test trên JVM): đồng hồ + chuyển động + độ sáng. View chỉ hỏi
 * [frame] mỗi khung để lấy độ lệch / alpha (thuộc tính RenderNode) và có hẹn khung tiếp không.
 */
class RainbowDriver(idleAfter: Double = RainbowBorder.IDLE_AFTER) {
    val clock = RainbowClock(idleAfter)
    var motion = RainbowMotion()
        private set
    var fade = RainbowFade()
        private set
    val running: Boolean get() = clock.running

    /** Một phím lúc [t]; true = vừa chuyển nghỉ → chạy (view hẹn khung hình). */
    fun poke(t: Double): Boolean {
        if (!clock.poke(t)) return false
        motion = motion.resumed(t)
        fade = fade.toward(1.0, t, RainbowBorder.FADE_IN_TIME)
        return true
    }

    /** Một khung hình lúc [t]: chuyển sang dừng dần nếu đã nghỉ đủ; true = cần khung tiếp (còn chạy / còn dừng / mờ). */
    fun frame(t: Double): Boolean {
        if (clock.running && clock.idleRemaining(t) <= 0) settle(t)
        return clock.running || t < motion.rampEnd || t < fade.end
    }

    /** Nghỉ: giảm tốc tới dừng + mờ xuống ánh nghỉ cùng lúc. */
    fun settle(t: Double) {
        clock.stop()
        motion = motion.settled(t)
        fade = fade.toward(RainbowBorder.REST_ALPHA, t, RainbowBorder.FADE_OUT_TIME)
    }

    /** Ẩn bàn phím: đứng yên ngay ở ánh nghỉ. */
    fun halt(t: Double) {
        clock.stop()
        motion = RainbowMotion.rest(motion.offset(t))
        fade = RainbowFade()
    }

    fun offset(t: Double) = motion.offset(t)
    fun alpha(t: Double) = fade.alpha(t)
}

/**
 * "borderFx":"aurora" (theme AI, 11/2026): viền phím gradient ĐỨNG YÊN (tím → lam ngọc → hồng theo bề ngang bàn phím,
 * cùng lớp viền với cầu vồng nhưng không chạy) + dải cực quang tĩnh dọc mép trên (vẽ một lần trong nền). 0 chi phí mỗi
 * phím, 0 hoạt ảnh. = iOS AuroraFx (test số chung).
 */
object AuroraFx {
    /** Viền phím: màu (RGB) + vị trí 0…1 bề ngang. */
    val BORDER_COLORS = intArrayOf(0x8B5CF6, 0x22D3EE, 0xF472B6)
    val BORDER_STOPS = doubleArrayOf(0.0, 0.55, 1.0)
    const val BORDER_ALPHA = 0.85
    const val LINE_WIDTH = 1.0
    /** Dải cực quang: cao (dp) từ mép trên nội dung; màu ngang; độ đậm mép trên → 0 ở đáy dải. */
    const val BAND_HEIGHT = 56.0
    val BAND_COLORS = intArrayOf(0x7C3AED, 0x22D3EE, 0xA855F7, 0x06B6D4)
    val BAND_STOPS = doubleArrayOf(0.0, 0.4, 0.7, 1.0)
    const val BAND_ALPHA = 0.32
    /** Độ đậm dải theo độ sâu [y] (dp, 0 = mép trên) — giảm bậc hai. */
    fun bandOpacity(y: Double): Double {
        if (y < 0 || y >= BAND_HEIGHT) return 0.0
        val f = 1 - y / BAND_HEIGHT
        return BAND_ALPHA * f * f
    }
}
