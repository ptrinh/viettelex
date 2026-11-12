package com.viettelex.keyboard

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.floor
import kotlin.math.hypot
import kotlin.math.pow
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
 * Nốt nhạc theo phím (notes): KHÔNG vòng lặp — mỗi phím chữ ngón đi qua (vào lõi phím, mỗi phím một nốt — [SwipeKeyTracker])
 * gảy một nốt ngắn ([SwipeNoteMap]: trái → phải trầm → cao ngũ cung, hàng lệch bậc), nhạc cụ theo Âm thanh phím nếu là
 * Piano / Đàn tranh / Ghi-ta, không thì Đàn tranh; to theo tốc độ ([SwipeSoundFx.noteVelocity]). Sáo trúc (flute): vòng lặp
 * tiếng sáo phát nhanh/chậm theo vị trí ngón ([SwipeSoundFx.fluteRate] — ~1,5 quãng tám, kéo nhẹ về ngũ cung), tắt dần
 * 250 ms. Sóng biển / Mèo kêu / Chim hót: vòng lặp + tiếng nhấc tay; Chim hót thêm lớp tiếng hót dày (× âm lượng²).
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
    NOTES("notes", "Nốt nhạc theo phím"), // l10n-key
    FLUTE("flute", "Sáo trúc"), // l10n-key
    WAVES("waves", "Sóng biển"), // l10n-key
    CAT("cat", "Mèo kêu"), // l10n-key
    BIRDS("birds", "Chim hót"), // l10n-key
    CUSTOM("custom", "Âm của bạn"); // l10n-key

    val title: String get() = tr(viTitle)

    /** Tắt + Bút chì miễn phí; còn lại thuộc Plus. */
    val isPlus: Boolean get() = this != NONE && this != PENCIL
    /** Có tiếng ngắn lúc nhấc tay ([KeySoundSynth.swipeLiftSamples]). */
    val hasLift: Boolean get() = when (this) {
        WHIP, LIGHTNING, PLASMA, WAND, WAVES, CAT, BIRDS -> true
        else -> false
    }
    /** Nốt nhạc theo phím: mỗi phím ngón đi qua một nốt (pool stream), không vòng lặp, không vỏ âm lượng theo tốc độ. */
    val isNotes: Boolean get() = this == NOTES
    /** Sáo trúc: vòng lặp phát với tốc độ (= cao độ) theo vị trí ngang của ngón. */
    val followsX: Boolean get() = this == FLUTE
    /** Cần toạ độ tâm phím ([SwipeKeyTracker]) để phát. */
    val needsLayout: Boolean get() = isNotes || followsX

    companion object {
        val DEFAULT = NONE
        /** Kiểu miễn phí thay cho kiểu Plus khi chưa có Plus / tiết kiệm pin. */
        val FALLBACK = PENCIL
        val IDS: Set<String> = entries.map { it.id }.toSet()
        /** Kiểu có vòng lặp tổng hợp riêng trong KeySoundSynth — trừ Tắt, Âm của bạn và Nốt nhạc theo phím (không vòng lặp). */
        val SYNTHESIZED: List<SwipeSoundStyle> = entries.filter { it != NONE && it != CUSTOM && it != NOTES }
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
    /** Sáo trúc: nhấc tay / huỷ tắt dần chậm hơn (hơi thở nhả ra), các kiểu khác [FADE_OUT]. */
    const val FLUTE_RELEASE = 0.25
    /** Sáo trúc: cao độ trượt về đích (portamento) — hằng thời gian, giây. */
    const val GLIDE_TAU = 0.04
    /** Sáo trúc: vòng lặp tổng hợp ở MIDI này (D5 ≈ 587,5 Hz); tốc độ phát 1 = cao độ gốc. */
    const val FLUTE_BASE = 74
    /** Sáo trúc: mép trái → mép phải vùng phím chữ = chừng này nửa cung (1,5 quãng tám, giữa = [FLUTE_BASE]). */
    const val FLUTE_SPAN = 18.0
    /** Sáo trúc: kéo cao độ về nốt ngũ cung gần nhất (0 = trượt tự do, 1 = nhảy hẳn nốt). */
    const val FLUTE_PULL = 0.7
    /** Nốt nhạc theo phím: độ to nốt = NOTE_FLOOR + (1 − NOTE_FLOOR) · speedGain(tốc độ) — vuốt chậm vẫn nghe. */
    const val NOTE_FLOOR = 0.4
    /** Nốt nhạc theo phím: số giọng (nốt chồng nhau tối đa; nốt thứ 7 thay nốt cũ nhất). */
    const val NOTE_VOICES = 6
    /** Nốt nhạc theo phím, bản nghe thử: độ to cố định mỗi nốt. */
    const val PREVIEW_NOTE_GAIN = 0.7

    /** Thời gian tắt dần khi nhấc tay / huỷ của kiểu. */
    fun release(s: SwipeSoundStyle): Double = if (s == SwipeSoundStyle.FLUTE) FLUTE_RELEASE else FADE_OUT

    /** Độ to nốt (Nốt nhạc theo phím) theo tốc độ ngón đã làm mượt. */
    fun noteVelocity(speed: Double): Double = NOTE_FLOOR + (1 - NOTE_FLOOR) * speedGain(speed)

    /** Nốt ngũ cung (C D E G A) gần MIDI thực [m] nhất (hoà ⇒ nốt thấp). */
    fun nearestPentatonic(m: Double): Int {
        val lo = floor(m).toInt()
        var best = lo
        var bd = Double.POSITIVE_INFINITY
        for (k in (lo - 2)..(lo + 3)) {
            when (((k % 12) + 12) % 12) {
                0, 2, 4, 7, 9 -> { val d = abs(k - m); if (d < bd) { bd = d; best = k } }
            }
        }
        return best
    }

    /**
     * Sáo trúc: MIDI (thực) theo vị trí ngang [u] 0…1 của ngón trên vùng phím chữ — tuyến tính [FLUTE_SPAN] nửa cung quanh
     * [FLUTE_BASE], kéo [FLUTE_PULL] về nốt ngũ cung gần nhất.
     */
    fun fluteMidi(u: Double): Double {
        val x = u.coerceIn(0.0, 1.0)
        val m = FLUTE_BASE - FLUTE_SPAN / 2 + FLUTE_SPAN * x
        return m + FLUTE_PULL * (nearestPentatonic(m) - m)
    }

    /** Sáo trúc: tốc độ phát vòng lặp (= tỉ lệ tần số so với [FLUTE_BASE]) — luôn trong 0,5…2 (giới hạn SoundPool). */
    fun fluteRate(u: Double): Double = 2.0.pow((fluteMidi(u) - FLUTE_BASE) / 12)

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
 * (hằng thời gian [SwipeSoundFx.RAMP_TAU]); nhấc tay ([release]): giảm tuyến tính về 0 trong [fade] (mặc định
 * [SwipeSoundFx.FADE_OUT]; Sáo trúc [SwipeSoundFx.FLUTE_RELEASE]). = iOS SwipeSoundEnvelope.
 */
class SwipeSoundEnvelope(step: Double, fade: Double = SwipeSoundFx.FADE_OUT) {
    private val k = 1 - exp(-step / SwipeSoundFx.RAMP_TAU)
    private val fadeFrac = step / fade
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

/**
 * Nốt nhạc theo phím: bảng phím → bậc ngũ cung (thuần, = iOS SwipeNoteMap). Trong hàng: trái → phải = trầm → cao (một bậc
 * mỗi phím); hàng trên lệch [ROW_SHIFT] bậc so với hàng dưới (q-hàng +4, a-hàng +2, z-hàng 0) ⇒ mỗi từ một đường giai điệu
 * riêng. Bậc 0…13 từ G3 (55) theo thang ngũ cung của nhạc cụ (Piano/Ghi-ta G A B D E, Đàn tranh G A C D E) ⇒ G3…D6.
 */
object SwipeNoteMap {
    val ROWS = listOf("qwertyuiop", "asdfghjkl", "zxcvbnm")
    val ROW_SHIFT = intArrayOf(4, 2, 0)
    const val BASE = 55
    /** Số bậc khác nhau (0…13) = số nốt dựng sẵn mỗi nhạc cụ. */
    const val STEPS = 14
    /** Bậc của chữ a…z (chỉ số 0…25). */
    val LETTER_STEPS: IntArray = IntArray(26) { k ->
        var st = 0
        for ((r, row) in ROWS.withIndex()) { val c = row.indexOf('a' + k); if (c >= 0) { st = c + ROW_SHIFT[r]; break } }
        st
    }

    fun step(letter: Int): Int = LETTER_STEPS[letter]

    fun midi(step: Int, scale: IntArray): Int = BASE + 12 * (step / 5) + scale[step % 5]
}

/**
 * Phím chữ dưới ngón đang vuốt (thuần, = iOS SwipeKeyTracker) — dựng MỘT lần từ tâm phím của layout gõ vuốt (52 số x,y của
 * a…z, như [SwipeLayout.centers]), mỗi điểm O(1) không cấp phát: chọn hàng gần nhất theo y, đoán cột theo bước phím rồi so
 * 3 tâm lân cận. Chỉ tính "vào phím" khi điểm nằm trong LÕI phím ([CORE] = 70 % bề ngang / khoảng hàng) ⇒ ngón rung ở ranh
 * giới hai phím không gảy lặp. [feed] trả phím mới (khác phím vừa gảy) hoặc −1 ⇒ mỗi phím một nốt.
 */
class SwipeKeyTracker private constructor(
    val keyWidth: Double,
    val rowHeight: Double,
    /** Mép trái / phải vùng phím chữ (Sáo trúc: vị trí ngang 0…1). */
    val minX: Double,
    val maxX: Double,
    private val rowY: DoubleArray,
    private val rowX: Array<DoubleArray>,
    private val rowLetter: Array<IntArray>,
) {
    var last = -1
        private set

    /** Chữ (0…25) có LÕI chứa điểm, −1 = không phím nào (khe, hàng số/cách, ngoài vùng). */
    fun key(x: Double, y: Double): Int {
        var best = -1
        var bd = Double.POSITIVE_INFINITY
        for (r in 0 until 3) {
            val d = abs(y - rowY[r])
            if (d < bd) { bd = d; best = r }
        }
        if (best < 0 || bd > CORE * rowHeight / 2) return -1
        val lx = rowX[best]
        val n = lx.size
        val g = floor((x - lx[0]) / keyWidth + 0.5).toInt().coerceIn(0, n - 1)
        var bc = -1
        var bdx = Double.POSITIVE_INFINITY
        for (c in maxOf(0, g - 1)..minOf(n - 1, g + 1)) {
            val dx = abs(x - lx[c])
            if (dx < bdx) { bdx = dx; bc = c }
        }
        if (bdx > CORE * keyWidth / 2) return -1
        return rowLetter[best][bc]
    }

    /** Một điểm vuốt: chữ VỪA vào (khác chữ đã gảy gần nhất) hoặc −1. */
    fun feed(x: Double, y: Double): Int {
        val k = key(x, y)
        if (k < 0 || k == last) return -1
        last = k
        return k
    }

    fun reset() { last = -1 }

    /** Vị trí ngang 0…1 trên vùng phím chữ (kẹp). */
    fun unitX(x: Double): Double = ((x - minX) / (maxX - minX)).coerceIn(0.0, 1.0)

    companion object {
        const val CORE = 0.7

        /** null ⇒ không có phím chữ nào / bước phím ≤ 0. [centers] 52 số (x, y của a…z; vô cực = không có phím). */
        fun of(centers: FloatArray, keyWidth: Float): SwipeKeyTracker? {
            if (keyWidth <= 0f || centers.size != 52) return null
            val kw = keyWidth.toDouble()
            val ys = DoubleArray(3)
            val xs = ArrayList<DoubleArray>(3)
            val ls = ArrayList<IntArray>(3)
            var lo = Double.POSITIVE_INFINITY
            var hi = Double.NEGATIVE_INFINITY
            for ((r, row) in SwipeNoteMap.ROWS.withIndex()) {
                val lx = ArrayList<Double>(); val ll = ArrayList<Int>()
                var sy = 0.0
                for (ch in row) {
                    val k = ch - 'a'
                    val x = centers[2 * k]
                    if (!x.isFinite()) continue
                    lx += x.toDouble(); ll += k; sy += centers[2 * k + 1].toDouble()
                    lo = minOf(lo, x.toDouble()); hi = maxOf(hi, x.toDouble())
                }
                xs += lx.toDoubleArray(); ls += ll.toIntArray()
                ys[r] = if (lx.isEmpty()) Double.POSITIVE_INFINITY else sy / lx.size
            }
            if (!lo.isFinite()) return null
            var rh = Double.POSITIVE_INFINITY
            for (r in 0 until 2) if (ys[r].isFinite() && ys[r + 1].isFinite()) rh = minOf(rh, abs(ys[r + 1] - ys[r]))
            return SwipeKeyTracker(kw, if (rh.isFinite() && rh > 0) rh else kw * 1.4, lo - kw / 2, hi + kw / 2,
                ys, xs.toTypedArray(), ls.toTypedArray())
        }

        /** Tâm QWERTY chuẩn (= [SwipeLayout.qwerty]: hàng 2 lệch 0,5 phím, hàng 3 lệch 1,5 phím) — bản nghe thử + test. */
        fun qwertyCenters(keyWidth: Float, rowHeight: Float): FloatArray {
            val c = FloatArray(52) { Float.POSITIVE_INFINITY }
            for ((r, rowPair) in listOf("qwertyuiop" to 0.5, "asdfghjkl" to 1.0, "zxcvbnm" to 2.0).withIndex()) {
                val (row, x0) = rowPair
                for ((i, ch) in row.withIndex()) {
                    val k = ch - 'a'
                    c[2 * k] = ((x0 + i) * keyWidth.toDouble()).toFloat()
                    c[2 * k + 1] = ((r + 0.5) * rowHeight.toDouble()).toFloat()
                }
            }
            return c
        }
    }
}
