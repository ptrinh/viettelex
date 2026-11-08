package com.viettelex.keyboard

import kotlin.math.cos
import kotlin.math.hypot

/**
 * "Mắt AI" — nhân vật Bạn đồng hành [BuddyCharacter.AI] (Plus, 11/2026): quả cầu năng lượng có mống mắt + đồng tử ở ô
 * nhân vật của thanh gợi ý (cùng công tắc / "Vị trí & cỡ"). Phần THUẦN — song sinh iOS AIEye.swift (cùng số, test chung);
 * vẽ: app/.../ime/AIEyeView.
 *
 *  • Đồng tử NHÌN về phím vừa bấm (hướng tâm mắt → tâm phím, kẹp trong mống mắt — [pupilOffset]).
 *  • Gõ nhanh (mức [ComboMeter]) ⇒ đồng tử co + quầng sáng mạnh lên.
 *  • Nghỉ [IDLE_AFTER] ⇒ thở [BREATH_CYCLES] nhịp rồi lim dim (mí khép nửa) và ĐỨNG YÊN — không hoạt ảnh vô hạn.
 *  • Chớp mắt chỉ khi đang gõ (mỗi [BLINK_EVERY] phím của chuỗi gõ hiện tại).
 */
object AIEye {
    /** Bán kính (tỉ lệ cạnh ngắn khung vẽ): quả cầu, mống mắt, đồng tử; lề an toàn. */
    const val ORB = 0.42
    const val IRIS = 0.25
    const val PUPIL = 0.10
    const val MARGIN = 0.02
    /** Khoảng cách (dp / pt) tới phím mà đồng tử chạm mép mống mắt. */
    const val GAZE = 120.0
    val PUPIL_SCALES = doubleArrayOf(1.0, 0.86, 0.74, 0.62)
    val GLOWS = doubleArrayOf(0.6, 0.75, 0.88, 1.0)
    const val REST_GLOW = 0.5
    const val BREATH_AMP = 0.35
    const val IDLE_AFTER = 2.0
    const val BREATH_PERIOD = 1.6
    const val BREATH_CYCLES = 3
    const val BREATH_END = IDLE_AFTER + BREATH_PERIOD * BREATH_CYCLES
    const val OPEN_LID = 1.0
    const val REST_LID = 0.5
    const val BLINK_LID = 0.08
    const val BLINK_TIME = 0.16
    const val BLINK_EVERY = 9
    const val LOOK_TIME = 0.12
    const val LID_TIME = 0.35
    const val HALO_INNER = 0xA855F7
    const val HALO_OUTER = 0x22D3EE
    val ORB_COLORS = intArrayOf(0x3B2A7A, 0x151A3A, 0x070A18)
    val IRIS_COLORS = intArrayOf(0xA5F3FC, 0x22D3EE, 0x7C3AED)
    const val PUPIL_COLOR = 0x0B1020
    const val RING_COLOR = 0x67E8F9
    const val LID_COLOR = 0x0A0E22

    enum class Phase { ACTIVE, BREATHING, RESTING }

    /** Đồng tử lệch tối đa (cùng đơn vị với [side]). */
    fun maxOffset(side: Double): Double = maxOf(0.0, (IRIS - PUPIL - MARGIN) * side)

    /**
     * Lệch đồng tử khi mắt ở ([ex], [ey]) nhìn ([tx], [ty]): đúng HƯỚNG, độ dài = [radius] × min(1, khoảng cách / [gaze])
     * ⇒ không bao giờ quá [radius]. Trùng tâm ⇒ (0, 0). Ghi vào [out].
     */
    fun pupilOffset(ex: Double, ey: Double, tx: Double, ty: Double, radius: Double, out: DoubleArray, gaze: Double = GAZE) {
        val dx = tx - ex; val dy = ty - ey
        val d = hypot(dx, dy)
        if (d <= 1e-9 || radius <= 0) { out[0] = 0.0; out[1] = 0.0; return }
        val k = radius * minOf(1.0, d / maxOf(gaze, 1e-9)) / d
        out[0] = dx * k; out[1] = dy * k
    }

    fun level(lv: Int): Int = lv.coerceIn(0, PUPIL_SCALES.size - 1)
    fun pupilScale(lv: Int): Double = PUPIL_SCALES[level(lv)]
    fun glow(lv: Int): Double = GLOWS[level(lv)]

    fun phase(sinceLastPress: Double): Phase = when {
        sinceLastPress < IDLE_AFTER -> Phase.ACTIVE
        sinceLastPress < BREATH_END -> Phase.BREATHING
        else -> Phase.RESTING
    }

    /** Còn bao lâu (giây) tới lần đổi trạng thái kế; lim dim ⇒ null (không hẹn gì nữa). */
    fun nextDeadline(sinceLastPress: Double): Double? = when (phase(sinceLastPress)) {
        Phase.ACTIVE -> IDLE_AFTER - sinceLastPress
        Phase.BREATHING -> BREATH_END - sinceLastPress
        Phase.RESTING -> null
    }

    /** Độ đậm quầng khi thở, [s] giây kể từ lúc bắt đầu thở; ngoài khoảng ⇒ [REST_GLOW]. */
    fun breathGlow(s: Double): Double {
        if (s <= 0 || s >= BREATH_PERIOD * BREATH_CYCLES) return REST_GLOW
        return REST_GLOW + BREATH_AMP * (1 - cos(2 * Math.PI * s / BREATH_PERIOD)) / 2
    }

    fun openness(p: Phase): Double = if (p == Phase.RESTING) REST_LID else OPEN_LID
    /** Mép dưới mí (từ đỉnh quả cầu) với độ mở [o], bán kính [r]: mở = 0, lim dim = r, khép = 2r. */
    fun lidEdge(o: Double, r: Double): Double = (1 - o.coerceIn(0.0, 1.0)) * 2 * r
    fun blinks(n: Int): Boolean = n > 0 && n % BLINK_EVERY == 0
}

/** Đồng hồ thuần của mắt (giây): phím cuối + số phím của chuỗi gõ hiện tại. = iOS AIEyeClock. */
class AIEyeClock {
    var lastPress = -Double.MAX_VALUE; private set
    var streak = 0; private set

    fun phase(t: Double): AIEye.Phase = AIEye.phase(t - lastPress)
    fun nextDeadline(t: Double): Double? = AIEye.nextDeadline(t - lastPress)?.let { t + it }
    fun press(t: Double): Int {
        if (phase(t) == AIEye.Phase.RESTING) streak = 0
        lastPress = t
        streak++
        return streak
    }
    fun reset() { lastPress = -Double.MAX_VALUE; streak = 0 }
}
