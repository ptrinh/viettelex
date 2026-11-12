package com.viettelex.android.ime

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.SoundPool
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import com.viettelex.keyboard.KeySoundSynth
import com.viettelex.keyboard.SwipeSoundCustom
import com.viettelex.keyboard.SwipeSoundEnvelope
import com.viettelex.keyboard.SwipeSoundFx
import com.viettelex.keyboard.SwipeSoundMeter
import com.viettelex.keyboard.SwipeSoundStyle
import java.io.File

/**
 * "Âm thanh nét vuốt" — phát (song sinh iOS Keyboard/SwipeSound.swift). Mẫu lặp liền mạch
 * ([KeySoundSynth.swipeLoopSamples], 22,05 kHz, WAV cache ≈ 44–62 KB) nạp vào MỘT SoundPool riêng khi kiểu khác Tắt —
 * Tắt / âm lượng 0 ⇒ IME không tạo đối tượng này dùng ([VietTelexIME.applySwipeSound] đặt `KeyboardView.swipeSound = null`,
 * 0 chi phí). SoundPool rảnh không tốn CPU (không luồng render như AVAudioEngine).
 *
 * Vuốt: [begin] phát vòng lặp (loop −1) ở âm lượng 0; mỗi điểm [move] chỉ cập nhật [SwipeSoundMeter] (không cấp phát,
 * không gọi SoundPool); nhịp [SwipeSoundFx.TICK] (25 ms) trên main đặt âm lượng theo tốc độ đã làm mượt
 * ([SwipeSoundEnvelope]) — chỉ chạy trong lúc vuốt + tắt dần, dừng hẳn sau đó. Nhấc tay / huỷ ⇒ tắt dần 100 ms rồi stop.
 * Im khi máy để Rung/Im lặng (đọc ringer MỘT lần mỗi cú vuốt, cache 2 s — như âm phím). Âm lượng = thanh "Âm lượng"
 * của Âm thanh phím ([KeySoundSynth.gain]).
 *
 * Roi vụt / Tia sét / Plasma / Đũa phép: thêm mẫu tiếng nhấc tay ([KeySoundSynth.swipeLiftSamples]) — nhấc tay (không
 * phải huỷ) ⇒ phát MỘT lần, to theo [SwipeSoundFx.liftGain] của tốc độ 80 ms cuối. Đũa phép: lớp hạt dày
 * ([KeySoundSynth.swipeLayerSamples]) chạy song song, âm lượng × âm lượng² ⇒ vuốt nhanh dày hơn. Pool tối đa 3 stream.
 * Âm của bạn: vòng lặp = file đã xử lý ([SwipeSoundCustom], noBackupFilesDir); vắng/hỏng ⇒ Bút chì.
 */
class SwipeSoundPlayer(private val ctx: Context) {
    private val audio = ctx.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val main = Handler(Looper.getMainLooper())
    private var pool: SoundPool? = null
    private var sampleId = 0
    private var layerId = 0
    private var liftId = 0
    /** Id mẫu đã nạp xong (SoundPool báo theo từng mẫu). */
    private val loadedIds = HashSet<Int>()
    /** Kiểu đang nạp (NONE = chưa dựng). */
    var style = SwipeSoundStyle.NONE
        private set
    /** Khoá đã nạp: kiểu + (Âm của bạn) ngày sửa + cỡ file ⇒ đổi file là nạp lại. */
    private var loadedKey = ""
    private var gain = 0f
    private var stream = 0
    private var layerStream = 0
    private var active = false
    private var ticking = false
    private var lastMoveMs = 0L
    private val meter = SwipeSoundMeter()
    private val env = SwipeSoundEnvelope(SwipeSoundFx.TICK)
    private var ringerNormal = true
    private var ringerCheckedAt = 0L

    /** Test/log: số cú vuốt đã phát tiếng. */
    var plays = 0
        private set

    /** Đang giữ SoundPool (test). */
    val hasPool: Boolean get() = pool != null

    /** Áp lúc bàn phím hiện: [s] = kiểu thực phát (đã qua SwipeSoundPolicy). Tắt ⇒ nhả hết. Đổi kiểu/file ⇒ nạp lại. */
    fun configure(s: SwipeSoundStyle, volumePercent: Int, worker: (Runnable) -> Unit) {
        gain = KeySoundSynth.gain(volumePercent)
        if (s == SwipeSoundStyle.NONE || volumePercent <= 0) { release(); return }
        val custom = customFile(ctx)
        val key = if (s == SwipeSoundStyle.CUSTOM) "custom@${custom.lastModified()}#${custom.length()}" else s.id
        if (pool != null && key == loadedKey) return
        release()
        style = s; loadedKey = key
        val p = SoundPool.Builder().setMaxStreams(3).setAudioAttributes(
            AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build()).build()
        pool = p
        p.setOnLoadCompleteListener { sp, id, status -> if (sp === pool && status == 0) loadedIds += id }
        val dir = ctx.cacheDir
        worker(Runnable {
            val f = if (s == SwipeSoundStyle.CUSTOM && SwipeSoundCustom.load(custom) != null) custom
                else loopFile(dir, if (s == SwipeSoundStyle.CUSTOM) SwipeSoundStyle.PENCIL else s)
            val layer = if (KeySoundSynth.swipeLayerSamples(s).isNotEmpty()) cacheFile(dir, s, "layer") else null
            val lift = if (s.hasLift) cacheFile(dir, s, "lift") else null
            main.post {
                if (pool === p && loadedKey == key && f != null) {
                    sampleId = p.load(f.path, 1)
                    layer?.let { layerId = p.load(it.path, 1) }
                    lift?.let { liftId = p.load(it.path, 1) }
                }
            }
        })
    }

    private fun ready(id: Int) = id > 0 && id in loadedIds

    /** Ngón vừa thành cú vuốt ([x], [y] dp, [tMs] = eventTime uptimeMillis). */
    fun begin(x: Float, y: Float, tMs: Long) {
        val p = pool ?: return
        if (!ready(sampleId)) return
        if (!ringerNormal()) return
        active = true
        meter.reset(x.toDouble(), y.toDouble(), tMs / 1000.0)
        lastMoveMs = tMs
        env.begin()
        if (stream == 0) {
            stream = p.play(sampleId, 0f, 0f, 1, -1, 1f); env.reset()
            if (stream != 0 && ready(layerId)) layerStream = p.play(layerId, 0f, 0f, 1, -1, 1f)
        }
        if (stream == 0) { active = false; return }
        plays++
        if (!ticking) { ticking = true; main.postDelayed(tick, TICK_MS) }
    }

    /** Một điểm vuốt — chỉ đo tốc độ (không SoundPool, không cấp phát). */
    fun move(x: Float, y: Float, tMs: Long) {
        if (!active) return
        meter.move(x.toDouble(), y.toDouble(), tMs / 1000.0)
        lastMoveMs = tMs
    }

    /**
     * Nhấc tay ([liftAtMs] = eventTime của lần nhấc) / huỷ (null): tắt dần [SwipeSoundFx.FADE_OUT] rồi dừng. Nhấc tay ở kiểu
     * có tiếng nhấc tay ⇒ phát một lần, to theo tốc độ [SwipeSoundFx.LIFT_WINDOW] cuối (gần như đứng yên ⇒ không kêu).
     */
    fun end(liftAtMs: Long? = null) {
        if (!active) return
        active = false
        env.release()
        val p = pool ?: return
        if (liftAtMs != null && style.hasLift && ready(liftId)) {
            val g = SwipeSoundFx.liftGain(meter.recentSpeed(liftAtMs / 1000.0)).toFloat() * gain
            if (g > 0f) p.play(liftId, g, g, 2, 0, 1f)
        }
    }

    private val tick = object : Runnable {
        override fun run() {
            val p = pool
            if (p == null || stream == 0) { ticking = false; return }
            val since = (SystemClock.uptimeMillis() - lastMoveMs) / 1000.0
            val e = env.next(SwipeSoundFx.target(meter.gain, since))
            if (env.finished) {
                stopLoops(p); ticking = false
                return
            }
            val g = e.toFloat() * gain
            p.setVolume(stream, g, g)
            if (layerStream != 0) { val l = (e * e).toFloat() * gain; p.setVolume(layerStream, l, l) }
            main.postDelayed(this, TICK_MS)
        }
    }

    private fun stopLoops(p: SoundPool?) {
        if (stream != 0) { p?.stop(stream); stream = 0 }
        if (layerStream != 0) { p?.stop(layerStream); layerStream = 0 }
    }

    /** Ẩn bàn phím: dừng tiếng (GIỮ mẫu đã nạp — nhả ở [release]). */
    fun onHidden() {
        active = false
        main.removeCallbacks(tick); ticking = false
        stopLoops(pool)
        env.reset()
    }

    /** Nhả SoundPool (Tắt, đổi kiểu, hẹn giờ ẩn / thiếu RAM, huỷ service). */
    fun release() {
        onHidden()
        pool?.release()
        pool = null; sampleId = 0; layerId = 0; liftId = 0; loadedIds.clear()
        style = SwipeSoundStyle.NONE; loadedKey = ""
    }

    private fun ringerNormal(): Boolean {
        val now = SystemClock.uptimeMillis()
        if (now - ringerCheckedAt >= 2000) {
            ringerCheckedAt = now
            ringerNormal = runCatching { audio.ringerMode == AudioManager.RINGER_MODE_NORMAL }.getOrDefault(true)
        }
        return ringerNormal
    }

    companion object {
        val TICK_MS = (SwipeSoundFx.TICK * 1000).toLong()

        /** File "Âm của bạn" đã xử lý (noBackupFilesDir — không vào Auto Backup / file sao lưu). */
        fun customFile(ctx: Context): File = File(ctx.noBackupFilesDir, SwipeSoundCustom.FILE_NAME)

        /** WAV cache của vòng lặp (ghi một lần, tên theo phiên bản thuật toán + kiểu). */
        fun loopFile(dir: File, s: SwipeSoundStyle): File? = cacheFile(dir, s, "loop")

        /** WAV cache: [part] = "loop" | "layer" (lớp hạt dày) | "lift" (tiếng nhấc tay). */
        fun cacheFile(dir: File, s: SwipeSoundStyle, part: String): File? = runCatching {
            val name = if (part == "loop") "swipesound-v$LOOP_VERSION-${s.id}.wav" else "swipesound-v$LOOP_VERSION-${s.id}-$part.wav"
            val f = File(dir, name)
            if (!f.exists() || f.length() == 0L) {
                val samples = when (part) {
                    "layer" -> KeySoundSynth.swipeLayerSamples(s)
                    "lift" -> KeySoundSynth.swipeLiftSamples(s)
                    else -> KeySoundSynth.swipeLoopSamples(s)
                }
                val tmp = File(dir, "$name.tmp")
                tmp.writeBytes(KeySoundSynth.wav(samples, KeySoundSynth.SWIPE_SAMPLE_RATE))
                tmp.renameTo(f)
            }
            f
        }.getOrNull()

        /** Đổi khi đổi công thức vòng lặp ⇒ file cache cũ không dùng nữa. */
        const val LOOP_VERSION = 1
    }
}
