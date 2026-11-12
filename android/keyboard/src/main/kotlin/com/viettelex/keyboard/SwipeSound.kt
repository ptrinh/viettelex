package com.viettelex.keyboard

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.hypot
import kotlin.math.roundToInt
import kotlin.math.sin
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
 * Roi vụt / Tia sét / Plasma / Đũa phép: thêm MỘT tiếng ngắn lúc nhấc tay (không khi huỷ), to theo tốc độ ngón ~80 ms cuối
 * ([SwipeSoundFx.liftGain] — ngón gần như đứng yên ⇒ không kêu). Đũa phép thêm lớp hạt dày (× âm lượng²) ⇒ vuốt nhanh dày
 * hơn. "Âm của bạn" (custom): file người dùng chọn, xử lý thành vòng lặp ([SwipeSoundCustom]) — vắng/hỏng ⇒ Bút chì.
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
    MARKER("marker", "Bút dạ"), // l10n-key
    WHIP("whip", "Roi vụt"), // l10n-key
    LIGHTNING("lightning", "Tia sét"), // l10n-key
    PLASMA("plasma", "Plasma"), // l10n-key
    WAND("wand", "Đũa phép"), // l10n-key
    CUSTOM("custom", "Âm của bạn"); // l10n-key

    val title: String get() = tr(viTitle)

    /** Tắt + Bút chì miễn phí; còn lại thuộc Plus. */
    val isPlus: Boolean get() = this != NONE && this != PENCIL
    /** Có tiếng ngắn lúc nhấc tay ([KeySoundSynth.swipeLiftSamples]). */
    val hasLift: Boolean get() = this == WHIP || this == LIGHTNING || this == PLASMA || this == WAND

    companion object {
        val DEFAULT = NONE
        /** Kiểu miễn phí thay cho kiểu Plus khi chưa có Plus / tiết kiệm pin. */
        val FALLBACK = PENCIL
        val IDS: Set<String> = entries.map { it.id }.toSet()
        /** Kiểu tổng hợp (có vòng lặp riêng trong KeySoundSynth) — trừ Tắt và Âm của bạn. */
        val SYNTHESIZED: List<SwipeSoundStyle> = entries.filter { it != NONE && it != CUSTOM }
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
    /** Tiếng nhấc tay: đo tốc độ trong chừng này giây cuối trước khi nhấc. */
    const val LIFT_WINDOW = 0.08
    /** Dưới tốc độ này (dp/s, trung bình [LIFT_WINDOW] cuối) ⇒ không có tiếng nhấc tay (ngón gần như đứng yên). */
    const val LIFT_MIN = 150.0
    /** Bản nghe thử trong app: độ to tiếng nhấc tay cố định (nét mẫu chậm dần về 0 ở cuối). */
    const val PREVIEW_LIFT_GAIN = 0.8

    /** Tốc độ (đã làm mượt) → 0…1: căn bậc hai cho cảm giác đều tay, trần 1. */
    fun speedGain(speed: Double): Double {
        if (speed <= SPEED_MIN) return 0.0
        return sqrt(min(1.0, (speed - SPEED_MIN) / (SPEED_FULL - SPEED_MIN)))
    }

    /** Độ to tiếng nhấc tay 0…1 theo tốc độ ~80 ms cuối: dưới [LIFT_MIN] ⇒ 0; căn bậc hai, đủ cỡ từ [SPEED_FULL]. */
    fun liftGain(speed: Double): Double {
        if (speed <= LIFT_MIN) return 0.0
        return sqrt(min(1.0, (speed - LIFT_MIN) / (SPEED_FULL - LIFT_MIN)))
    }

    /** Đích âm lượng: ngón đứng yên quá [HOLD] ⇒ 0. */
    fun target(gain: Double, sinceMove: Double): Double = if (sinceMove > HOLD) 0.0 else gain

    /** EMA tốc độ: [inst] = tốc độ tức thời, [dt] = giây kể từ điểm trước. */
    fun smooth(prev: Double, inst: Double, dt: Double): Double {
        val a = 1 - exp(-min(dt, MAX_DT) / SPEED_TAU)
        return prev + (inst - prev) * a
    }
}

/** Đo tốc độ ngón (main, mỗi điểm vuốt) — không cấp phát (vòng đệm cấp một lần). = iOS SwipeSoundMeter. */
class SwipeSoundMeter {
    var speed = 0.0
        private set
    private var lastX = 0.0
    private var lastY = 0.0
    private var lastT = 0.0
    /** Vòng đệm các đoạn gần nhất (quãng đường, giờ cuối đoạn) — cho tốc độ [SwipeSoundFx.LIFT_WINDOW] cuối lúc nhấc tay. */
    private val segD = DoubleArray(RING)
    private val segT = DoubleArray(RING)
    private var head = 0
    private var filled = 0

    fun reset(x: Double, y: Double, t: Double) { lastX = x; lastY = y; lastT = t; speed = 0.0; filled = 0 }

    /** Một điểm mới (toạ độ pt/dp, thời gian giây). */
    fun move(x: Double, y: Double, t: Double) {
        val dt = t - lastT
        if (dt < SwipeSoundFx.MIN_DT) return          // điểm gộp trùng giờ: đo từ điểm cũ ở lần sau
        val dist = hypot(x - lastX, y - lastY)
        speed = SwipeSoundFx.smooth(speed, dist / dt, dt)
        lastX = x; lastY = y; lastT = t
        segD[head] = dist; segT[head] = t
        head = (head + 1) % RING
        filled = min(filled + 1, RING)
    }

    val gain: Double get() = SwipeSoundFx.speedGain(speed)

    /**
     * Tốc độ trung bình trong [SwipeSoundFx.LIFT_WINDOW] giây trước [now] (quãng đường các đoạn kết thúc trong cửa sổ /
     * cửa sổ). Ngón đứng yên lâu hơn cửa sổ trước khi nhấc ⇒ 0.
     */
    fun recentSpeed(now: Double): Double {
        val from = now - SwipeSoundFx.LIFT_WINDOW
        var sum = 0.0
        for (k in 0 until filled) {
            val j = (head - 1 - k + RING) % RING
            if (segT[j] < from) break
            if (segT[j] <= now + 1e-9) sum += segD[j]
        }
        return sum / SwipeSoundFx.LIFT_WINDOW
    }

    companion object { const val RING = 32 }
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

/**
 * "Âm của bạn": file người dùng chọn → MỘT vòng lặp liền mạch (22,05 kHz mono). Xử lý thuần (= iOS SwipeSoundCustom):
 * giải mã ở app (MediaCodec, KeySoundImport.decode) → [process] → WAV trong noBackupFilesDir ([FILE_NAME]; IME cùng
 * process đọc). Chỉ trên máy: không tải lên đâu, KHÔNG vào Auto Backup / file sao lưu (như âm phím tự chọn).
 */
object SwipeSoundCustom {
    /** Tối đa chừng này giây làm vòng lặp (phần sau bị cắt). */
    const val MAX_DURATION = 3.0
    /** Âm ngắn hơn ⇒ lặp lại nối tiếp cho đủ (vòng quá ngắn nghe như rè). */
    const val MIN_LOOP = 0.5
    /** Cùng đỉnh với vòng lặp tổng hợp (Bút chì / Phấn bảng). */
    const val TARGET_PEAK = 0.30f
    const val FILE_NAME = "swipesound-custom.wav"

    class Failure(val silent: Boolean) : Exception(if (silent) "silent" else "empty")
    data class Result(val samples: FloatArray, val truncated: Boolean)

    /**
     * mono ở [sampleRate] → 22,05 kHz, bỏ lặng đầu/cuối, cắt ≤ [MAX_DURATION], nối đuôi vào đầu bằng trộn công suất đều
     * 80 ms (như vòng tổng hợp ⇒ không "tách"), chuẩn hoá đỉnh [TARGET_PEAK].
     */
    fun process(mono: FloatArray, sampleRate: Double): Result {
        if (mono.isEmpty() || sampleRate <= 0) throw Failure(silent = false)
        val sr = KeySoundSynth.SWIPE_SAMPLE_RATE.toDouble()
        val x = KeySoundCustom.resample(mono, sampleRate, sr)
        val peak = x.maxOf { abs(it) }
        if (peak < 0.001f) throw Failure(silent = true)
        val thr = maxOf(peak * 0.05f, 0.001f)
        val first = x.indexOfFirst { abs(it) >= thr }.coerceAtLeast(0)
        val last = x.indexOfLast { abs(it) >= thr }.let { if (it < 0) x.size - 1 else it }
        val f = (KeySoundSynth.SWIPE_CROSSFADE * sr).roundToInt()
        val cap = (MAX_DURATION * sr).roundToInt()
        val avail = last + 1 - first
        val truncated = avail > cap + f
        var y = x.copyOfRange(first, first + minOf(avail, cap + f))
        val need = (MIN_LOOP * sr).roundToInt() + f
        if (y.size < need) {
            // Âm ngắn: mở/đóng 5 ms rồi lặp lại nối tiếp cho đủ.
            val e = minOf(y.size / 2, (0.005 * sr).roundToInt())
            for (i in 0 until e) {
                val w = (0.5 - 0.5 * cos(PI * i / e)).toFloat()
                y[i] *= w; y[y.size - 1 - i] *= w
            }
            val reps = (need + y.size - 1) / y.size
            val z = FloatArray(reps * y.size)
            for (r in 0 until reps) y.copyInto(z, r * y.size)
            y = z
        }
        val len = y.size - f
        val out = FloatArray(len) { i ->
            if (i < f) {
                val w = i.toDouble() / f
                (y[i] * sin(PI / 2 * w) + y[len + i] * cos(PI / 2 * w)).toFloat()
            } else y[i]
        }
        val p2 = out.maxOf { abs(it) }
        if (p2 <= 0f) throw Failure(silent = true)
        val g = TARGET_PEAK / p2
        return Result(FloatArray(len) { out[it] * g }, truncated)
    }

    /** Vòng lặp đã xử lý (WAV 22,05 kHz mono). null ⇒ vắng/hỏng. */
    fun load(f: java.io.File?): FloatArray? {
        if (f == null || !f.isFile) return null
        val (s, rate) = runCatching { KeySoundSynth.parseWav(f.readBytes()) }.getOrNull() ?: return null
        if (s.isEmpty() || s.size > (MAX_DURATION * KeySoundSynth.SWIPE_SAMPLE_RATE).toInt() + 16) return null
        return KeySoundCustom.resample(s, rate, KeySoundSynth.SWIPE_SAMPLE_RATE.toDouble())
    }

    /** Vòng lặp phát cho "Âm của bạn": file hợp lệ, không thì Bút chì (giá trị lưu giữ nguyên). */
    fun resolvedLoop(custom: FloatArray?): FloatArray =
        if (custom != null && custom.isNotEmpty()) custom else KeySoundSynth.swipeLoopSamples(SwipeSoundStyle.PENCIL)
}
