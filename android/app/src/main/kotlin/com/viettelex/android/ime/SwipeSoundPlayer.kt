package com.viettelex.android.ime

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.SoundPool
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import com.viettelex.keyboard.KeySoundSynth
import com.viettelex.keyboard.SwipeSoundEnvelope
import com.viettelex.keyboard.SwipeSoundFx
import com.viettelex.keyboard.SwipeSoundMeter
import com.viettelex.keyboard.SwipeSoundStyle
import java.io.File

/**
 * "Âm thanh nét vuốt" — phát (song sinh iOS Keyboard/SwipeSound.swift). Mẫu lặp liền mạch
 * ([KeySoundSynth.swipeLoopSamples], 22,05 kHz, WAV cache ≈ 44–62 KB) nạp vào MỘT SoundPool riêng (1 stream) khi kiểu
 * khác Tắt — Tắt / âm lượng 0 ⇒ IME không tạo đối tượng này dùng ([VietTelexIME.applySwipeSound] đặt
 * `KeyboardView.swipeSound = null`, 0 chi phí). SoundPool rảnh không tốn CPU (không luồng render như AVAudioEngine).
 *
 * Vuốt: [begin] phát vòng lặp (loop −1) ở âm lượng 0; mỗi điểm [move] chỉ cập nhật [SwipeSoundMeter] (không cấp phát,
 * không gọi SoundPool); nhịp [SwipeSoundFx.TICK] (25 ms) trên main đặt âm lượng theo tốc độ đã làm mượt
 * ([SwipeSoundEnvelope]) — chỉ chạy trong lúc vuốt + tắt dần, dừng hẳn sau đó. Nhấc tay / huỷ ⇒ tắt dần 100 ms rồi stop.
 * Im khi máy để Rung/Im lặng (đọc ringer MỘT lần mỗi cú vuốt, cache 2 s — như âm phím). Âm lượng = thanh "Âm lượng"
 * của Âm thanh phím ([KeySoundSynth.gain]).
 */
class SwipeSoundPlayer(private val ctx: Context) {
    private val audio = ctx.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val main = Handler(Looper.getMainLooper())
    private var pool: SoundPool? = null
    private var sampleId = 0
    @Volatile private var loaded = false
    /** Kiểu đang nạp (NONE = chưa dựng). */
    var style = SwipeSoundStyle.NONE
        private set
    private var gain = 0f
    private var stream = 0
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

    /** Áp lúc bàn phím hiện: [s] = kiểu thực phát (đã qua SwipeSoundPolicy). Tắt ⇒ nhả hết. Đổi kiểu ⇒ nạp lại. */
    fun configure(s: SwipeSoundStyle, volumePercent: Int, worker: (Runnable) -> Unit) {
        gain = KeySoundSynth.gain(volumePercent)
        if (s == SwipeSoundStyle.NONE || volumePercent <= 0) { release(); return }
        if (pool != null && s == style) return
        release()
        style = s
        val p = SoundPool.Builder().setMaxStreams(1).setAudioAttributes(
            AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build()).build()
        pool = p
        p.setOnLoadCompleteListener { sp, id, status -> if (sp === pool && status == 0 && id == sampleId) loaded = true }
        val dir = ctx.cacheDir
        worker(Runnable {
            val f = loopFile(dir, s)
            main.post { if (pool === p && style == s && f != null) sampleId = p.load(f.path, 1) }
        })
    }

    /** Ngón vừa thành cú vuốt ([x], [y] dp, [tMs] = eventTime uptimeMillis). */
    fun begin(x: Float, y: Float, tMs: Long) {
        val p = pool ?: return
        if (!loaded || sampleId <= 0) return
        if (!ringerNormal()) return
        active = true
        meter.reset(x.toDouble(), y.toDouble(), tMs / 1000.0)
        lastMoveMs = tMs
        env.begin()
        if (stream == 0) { stream = p.play(sampleId, 0f, 0f, 1, -1, 1f); env.reset() }
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

    /** Nhấc tay / huỷ: tắt dần [SwipeSoundFx.FADE_OUT] rồi dừng. */
    fun end() {
        if (!active) return
        active = false
        env.release()
    }

    private val tick = object : Runnable {
        override fun run() {
            val p = pool
            if (p == null || stream == 0) { ticking = false; return }
            val since = (SystemClock.uptimeMillis() - lastMoveMs) / 1000.0
            val g = env.next(SwipeSoundFx.target(meter.gain, since)).toFloat() * gain
            if (env.finished) {
                p.stop(stream); stream = 0; ticking = false
                return
            }
            p.setVolume(stream, g, g)
            main.postDelayed(this, TICK_MS)
        }
    }

    /** Ẩn bàn phím: dừng tiếng (GIỮ mẫu đã nạp — nhả ở [release]). */
    fun onHidden() {
        active = false
        main.removeCallbacks(tick); ticking = false
        if (stream != 0) { pool?.stop(stream); stream = 0 }
        env.reset()
    }

    /** Nhả SoundPool (Tắt, đổi kiểu, hẹn giờ ẩn / thiếu RAM, huỷ service). */
    fun release() {
        onHidden()
        pool?.release()
        pool = null; sampleId = 0; loaded = false; style = SwipeSoundStyle.NONE
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

        /** WAV cache của vòng lặp (ghi một lần, tên theo phiên bản thuật toán + kiểu). */
        fun loopFile(dir: File, s: SwipeSoundStyle): File? = runCatching {
            val name = "swipesound-v$LOOP_VERSION-${s.id}.wav"
            val f = File(dir, name)
            if (!f.exists() || f.length() == 0L) {
                val tmp = File(dir, "$name.tmp")
                tmp.writeBytes(KeySoundSynth.wav(KeySoundSynth.swipeLoopSamples(s), KeySoundSynth.SWIPE_SAMPLE_RATE))
                tmp.renameTo(f)
            }
            f
        }.getOrNull()

        /** Đổi khi đổi công thức vòng lặp ⇒ file cache cũ không dùng nữa. */
        const val LOOP_VERSION = 1
    }
}
