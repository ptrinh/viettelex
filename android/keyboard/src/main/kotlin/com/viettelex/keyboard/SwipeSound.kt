package com.viettelex.keyboard

import kotlin.math.exp
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

/**
 * "Âm thanh nét vuốt" (Gõ vuốt → Âm thanh nét vuốt) — THUẦN, song sinh iOS/Shared/SwipeSoundStyles.swift:
 * cùng khoá [Keys.SWIPE_SOUND] (`swipeSound`), cùng id, cùng số. Trong lúc ngón đang vuốt một từ: tiếng lặp
 * liên tục, nhỏ, như dụng cụ lướt trên mặt giấy/bảng — to/nhỏ theo tốc độ ngón (đứng yên ⇒ im), tắt dần
 * ~100 ms khi nhấc tay. Mẫu lặp tổng hợp trong [KeySoundSynth.swipeLoopSamples] (không file âm thanh).
 *
 * "Tắt" (mặc định) + "Bút chì" miễn phí; còn lại Plus (cùng cổng với Hiệu ứng nét vuốt) — chưa có Plus / bật
 * Trình tiết kiệm pin ⇒ phát Bút chì, giá trị lưu giữ nguyên.
 *
 * Luật hiệu năng: Tắt (hoặc âm lượng phím 0 %) ⇒ IME không dựng SoundPool, KeyboardView giữ `swipeSound = null`
 * — đường vuốt chỉ đọc một biến null. Bật: mỗi điểm vuốt chỉ cập nhật [SwipeSoundMeter] (vài phép tính, không cấp
 * phát); âm lượng đặt theo nhịp [SwipeSoundFx.TICK] trên main, chỉ trong lúc vuốt + tắt dần.
 */
enum class SwipeSoundStyle(val id: String, val viTitle: String) {
    NONE("none", "Tắt"), // l10n-key
    PENCIL("pencil", "Bút chì"), // l10n-key
    BRUSH("brush", "Chổi lông"), // l10n-key
    CHALK("chalk", "Phấn bảng"), // l10n-key
    MARKER("marker", "Bút dạ"); // l10n-key

    val title: String get() = tr(viTitle)

    /** Tắt + Bút chì miễn phí; còn lại thuộc Plus. */
    val isPlus: Boolean get() = this != NONE && this != PENCIL

    companion object {
        val DEFAULT = NONE
        /** Kiểu miễn phí thay cho kiểu Plus khi chưa có Plus / tiết kiệm pin. */
        val FALLBACK = PENCIL
        val IDS: Set<String> = entries.map { it.id }.toSet()
        /** Giá trị lạ / thiếu ⇒ Tắt. */
        fun of(raw: Any?): SwipeSoundStyle = entries.firstOrNull { it.id == raw } ?: DEFAULT
        /** Kiểu hiện ở dòng cài đặt: kiểu Plus khi chưa có Plus ⇒ Bút chì (giá trị lưu giữ nguyên). */
        fun displayed(raw: Any?, plus: Boolean = SwipeSoundGate.allows): SwipeSoundStyle =
            of(raw).let { if (it.isPlus && !plus) FALLBACK else it }
    }
}

/** Cổng Plus: như Hiệu ứng nét vuốt (quyền theme cao cấp). */
object SwipeSoundGate {
    val allows: Boolean get() = SwipeTrailGate.allows
    fun allows(s: SwipeSoundStyle): Boolean = !s.isPlus || allows
}

/** Kiểu thực phát — hàm thuần (test). = iOS SwipeSoundPolicy. */
object SwipeSoundPolicy {
    /** Tắt / âm lượng 0 ⇒ Tắt (0 chi phí). Kiểu Plus chưa có Plus / tiết kiệm pin ⇒ Bút chì. */
    fun active(setting: SwipeSoundStyle, plus: Boolean, powerSave: Boolean, volumePercent: Int): SwipeSoundStyle = when {
        setting == SwipeSoundStyle.NONE || volumePercent <= 0 -> SwipeSoundStyle.NONE
        setting.isPlus && (!plus || powerSave) -> SwipeSoundStyle.FALLBACK
        else -> setting
    }
}

/** Số + hàm thuần dùng chung hai nền tảng (iOS SwipeSoundFx cùng số). Tốc độ: pt/s (iOS) = dp/s (Android). */
object SwipeSoundFx {
    /** Dưới tốc độ này ⇒ im (ngón gần như đứng yên). */
    const val SPEED_MIN = 40.0
    /** Từ tốc độ này trở lên ⇒ to hết cỡ (trần 1). */
    const val SPEED_FULL = 1500.0
    /** Làm mượt tốc độ (EMA) — hằng thời gian, giây. */
    const val SPEED_TAU = 0.05
    /** Bước thời gian tối đa đưa vào EMA (điểm cách nhau quá xa không làm nhảy tốc độ). */
    const val MAX_DT = 0.1
    /** Điểm gộp cách nhau dưới chừng này giây ⇒ chờ điểm sau (tránh chia cho ~0). */
    const val MIN_DT = 0.001
    /** Không có điểm mới quá chừng này ⇒ ngón đứng yên ⇒ đích = 0. */
    const val HOLD = 0.08
    /** Âm lượng tiến về đích (mở / nhỏ dần khi chậm lại) — hằng thời gian, giây. */
    const val RAMP_TAU = 0.03
    /** Nhấc tay / huỷ: tắt dần TUYẾN TÍNH trong chừng này giây (từ mức đang có về 0). */
    const val FADE_OUT = 0.1
    /** Android: nhịp đặt âm lượng SoundPool lúc đang vuốt (giây). iOS chạy từng mẫu trong render. */
    const val TICK = 0.025

    /** Tốc độ (đã làm mượt) → 0…1: căn bậc hai cho cảm giác đều tay, trần 1. */
    fun speedGain(speed: Double): Double {
        if (speed <= SPEED_MIN) return 0.0
        return sqrt(min(1.0, (speed - SPEED_MIN) / (SPEED_FULL - SPEED_MIN)))
    }

    /** Đích âm lượng: ngón đứng yên quá [HOLD] ⇒ 0. */
    fun target(gain: Double, sinceMove: Double): Double = if (sinceMove > HOLD) 0.0 else gain

    /** EMA tốc độ: [inst] = tốc độ tức thời, [dt] = giây kể từ điểm trước. */
    fun smooth(prev: Double, inst: Double, dt: Double): Double {
        val a = 1 - exp(-min(dt, MAX_DT) / SPEED_TAU)
        return prev + (inst - prev) * a
    }
}

/** Đo tốc độ ngón (main, mỗi điểm vuốt) — không cấp phát. = iOS SwipeSoundMeter. */
class SwipeSoundMeter {
    var speed = 0.0
        private set
    private var lastX = 0.0
    private var lastY = 0.0
    private var lastT = 0.0

    fun reset(x: Double, y: Double, t: Double) { lastX = x; lastY = y; lastT = t; speed = 0.0 }

    /** Một điểm mới (toạ độ pt/dp, thời gian giây). */
    fun move(x: Double, y: Double, t: Double) {
        val dt = t - lastT
        if (dt < SwipeSoundFx.MIN_DT) return          // điểm gộp trùng giờ: đo từ điểm cũ ở lần sau
        val inst = hypot(x - lastX, y - lastY) / dt
        speed = SwipeSoundFx.smooth(speed, inst, dt)
        lastX = x; lastY = y; lastT = t
    }

    val gain: Double get() = SwipeSoundFx.speedGain(speed)
}

/**
 * Vỏ âm lượng 0…1 theo bước [step] giây (iOS: 1 mẫu; Android: [SwipeSoundFx.TICK]). Đang vuốt: tiến về đích
 * (hằng thời gian [SwipeSoundFx.RAMP_TAU]); nhấc tay ([release]): giảm tuyến tính về 0 trong [SwipeSoundFx.FADE_OUT].
 * = iOS SwipeSoundEnvelope.
 */
class SwipeSoundEnvelope(step: Double) {
    private val k = 1 - exp(-step / SwipeSoundFx.RAMP_TAU)
    private val fadeFrac = step / SwipeSoundFx.FADE_OUT
    var gain = 0.0
        private set
    var releasing = false
        private set
    private var fadeStep = 0.0

    fun begin() { releasing = false }

    fun release() {
        if (releasing) return
        releasing = true
        fadeStep = max(gain * fadeFrac, 1e-9)
    }

    fun next(target: Double): Double {
        gain = if (releasing) max(0.0, gain - fadeStep) else gain + (target - gain) * k
        return gain
    }

    /** Đã tắt hẳn sau nhấc tay ⇒ dừng phát. */
    val finished: Boolean get() = releasing && gain <= 0.0

    fun reset() { gain = 0.0; releasing = false; fadeStep = 0.0 }
}
