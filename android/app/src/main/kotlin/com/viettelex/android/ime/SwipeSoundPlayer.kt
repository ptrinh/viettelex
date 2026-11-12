package com.viettelex.android.ime

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.SoundPool
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import com.viettelex.keyboard.KeyInstrument
import com.viettelex.keyboard.KeySoundSynth
import com.viettelex.keyboard.SwipeKeyTracker
import com.viettelex.keyboard.SwipeLayout
import com.viettelex.keyboard.SwipeNoteMap
import com.viettelex.keyboard.SwipeSoundCustom
import com.viettelex.keyboard.SwipeSoundEnvelope
import com.viettelex.keyboard.SwipeSoundFx
import com.viettelex.keyboard.SwipeSoundMeter
import com.viettelex.keyboard.SwipeSoundStyle
import java.io.File
import kotlin.math.exp

/**
 * "Âm thanh nét vuốt" — phát (song sinh iOS Keyboard/SwipeSound.swift). Mẫu lặp liền mạch
 * ([KeySoundSynth.swipeLoopSamples], 22,05 kHz, WAV cache ≈ 44–62 KB) nạp vào MỘT SoundPool riêng khi kiểu khác Tắt —
 * Tắt / âm lượng 0 ⇒ IME không tạo đối tượng này dùng ([VietTelexIME.applySwipeSound] đặt `KeyboardView.swipeSound = null`,
 * 0 chi phí). SoundPool rảnh không tốn CPU (không luồng render như AVAudioEngine).
 *
 * Vuốt: [begin] phát vòng lặp (loop −1) ở âm lượng 0; mỗi điểm [move] chỉ cập nhật [SwipeSoundMeter] (không cấp phát,
 * không gọi SoundPool); nhịp [SwipeSoundFx.TICK] (25 ms) trên main đặt âm lượng theo tốc độ đã làm mượt
 * ([SwipeSoundEnvelope]) — chỉ chạy trong lúc vuốt + tắt dần, dừng hẳn sau đó. Nhấc tay / huỷ ⇒ tắt dần rồi stop.
 * Im khi máy để Rung/Im lặng (đọc ringer MỘT lần mỗi cú vuốt, cache 2 s — như âm phím). Âm lượng = thanh "Âm lượng"
 * của Âm thanh phím ([KeySoundSynth.gain]).
 *
 * Roi vụt / Tia sét / Plasma / Đũa phép / Sóng biển / Mèo kêu / Chim hót: thêm mẫu tiếng nhấc tay
 * ([KeySoundSynth.swipeLiftSamples]) — nhấc tay (không phải huỷ) ⇒ phát MỘT lần, to theo [SwipeSoundFx.liftGain] của tốc độ
 * 80 ms cuối. Đũa phép / Chim hót: lớp dày ([KeySoundSynth.swipeLayerSamples]) chạy song song, âm lượng × âm lượng².
 * Pool tối đa 3 stream. Âm của bạn: vòng lặp = file đã xử lý ([SwipeSoundCustom], noBackupFilesDir); vắng/hỏng ⇒ Bút chì.
 *
 * Nốt nhạc theo phím: 14 nốt ([KeySoundSynth.swipeNoteSamples], nhạc cụ theo Âm thanh phím, WAV cache ~26 KB/nốt) nạp vào
 * pool [SwipeSoundFx.NOTE_VOICES] stream (nốt thứ 7 thay nốt cũ nhất); mỗi điểm [SwipeKeyTracker.feed] O(1) không cấp phát,
 * vào phím mới ⇒ MỘT lần SoundPool.play (độ to theo tốc độ). Không vòng lặp, không nhịp — nốt ngân hết tự nhiên.
 * Sáo trúc: vòng lặp tiếng sáo; nhịp 25 ms trượt tốc độ phát về đích ([SwipeSoundFx.fluteRate] theo vị trí ngang, τ
 * [SwipeSoundFx.GLIDE_TAU]) bằng SoundPool.setRate (0,57…1,75 ⊂ 0,5…2); tắt dần 250 ms.
 */
class SwipeSoundPlayer(private val ctx: Context) {
    private val audio = ctx.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val main = Handler(Looper.getMainLooper())
    private var pool: SoundPool? = null
    private var sampleId = 0
    private var layerId = 0
    private var liftId = 0
    private val noteIds = IntArray(SwipeNoteMap.STEPS)
    /** Id mẫu đã nạp xong (SoundPool báo theo từng mẫu). */
    private val loadedIds = HashSet<Int>()
    /** Kiểu đang nạp (NONE = chưa dựng). */
    var style = SwipeSoundStyle.NONE
        private set
    /** Khoá đã nạp: kiểu + (Âm của bạn) ngày sửa + cỡ file / (Nốt nhạc theo phím) nhạc cụ ⇒ đổi là nạp lại. */
    private var loadedKey = ""
    private var gain = 0f
    private var stream = 0
    private var layerStream = 0
    private var active = false
    private var ticking = false
    private var lastMoveMs = 0L
    private val meter = SwipeSoundMeter()
    private var env = SwipeSoundEnvelope(SwipeSoundFx.TICK)
    private var ringerNormal = true
    private var ringerCheckedAt = 0L
    /** Dò phím dưới ngón (Nốt nhạc theo phím, Sáo trúc) — toạ độ dp như [begin]/[move]; dựng lại khi layout đổi. */
    private var tracker: SwipeKeyTracker? = null
    private var layoutRef: SwipeLayout? = null
    private var layoutDensity = 0f
    /** Sáo trúc: tốc độ phát hiện tại / đích. */
    private var rate = 1.0
    private var rateTarget = 1.0
    private val glideK = 1 - exp(-SwipeSoundFx.TICK / SwipeSoundFx.GLIDE_TAU)

    /** Test/log: số cú vuốt đã phát tiếng. */
    var plays = 0
        private set
    /** Test/log: số nốt đã gảy (Nốt nhạc theo phím). */
    var notesPlayed = 0
        private set

    /** Đang giữ SoundPool (test). */
    val hasPool: Boolean get() = pool != null

    /**
     * Áp lúc bàn phím hiện: [s] = kiểu thực phát (đã qua SwipeSoundPolicy). Tắt ⇒ nhả hết. Đổi kiểu/file/nhạc cụ ⇒ nạp lại.
     * [instrument] = nhạc cụ của Âm thanh phím (Nốt nhạc theo phím; không phải nhạc cụ ⇒ Đàn tranh).
     */
    fun configure(s: SwipeSoundStyle, volumePercent: Int, instrument: KeyInstrument = KeyInstrument.DANTRANH,
                  worker: (Runnable) -> Unit) {
        gain = KeySoundSynth.gain(volumePercent)
        if (s == SwipeSoundStyle.NONE || volumePercent <= 0) { release(); return }
        val custom = customFile(ctx)
        val key = when {
            s == SwipeSoundStyle.CUSTOM -> "custom@${custom.lastModified()}#${custom.length()}"
            s.isNotes -> "notes/${instrument.cacheTag}"
            else -> s.id
        }
        if (pool != null && key == loadedKey) return
        release()
        style = s; loadedKey = key
        env = SwipeSoundEnvelope(SwipeSoundFx.TICK, SwipeSoundFx.release(s))
        val p = SoundPool.Builder().setMaxStreams(if (s.isNotes) SwipeSoundFx.NOTE_VOICES else 3).setAudioAttributes(
            AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build()).build()
        pool = p
        p.setOnLoadCompleteListener { sp, id, status -> if (sp === pool && status == 0) loadedIds += id }
        val dir = ctx.cacheDir
        if (s.isNotes) {
            worker(Runnable {
                val files = (0 until SwipeNoteMap.STEPS).map { noteFile(dir, instrument, it) }
                main.post {
                    if (pool === p && loadedKey == key) files.forEachIndexed { i, f -> if (f != null) noteIds[i] = p.load(f.path, 1) }
                }
            })
            return
        }
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

    /** Tâm phím (px, cùng hệ swipePath) của layout gõ vuốt → dò phím theo dp ([density] px/dp). Trùng ⇒ không làm gì. */
    fun setLayout(l: SwipeLayout, density: Float) {
        if (l === layoutRef && density == layoutDensity) return
        layoutRef = l; layoutDensity = density
        val c = FloatArray(52) { val v = l.centers[it]; if (v.isFinite()) v / density else v }
        tracker = SwipeKeyTracker.of(c, l.keyWidth / density)
    }

    private fun ready(id: Int) = id > 0 && id in loadedIds

    /** Ngón vừa thành cú vuốt ([x], [y] dp, [tMs] = eventTime uptimeMillis). */
    fun begin(x: Float, y: Float, tMs: Long) {
        val p = pool ?: return
        if (style.isNotes) {
            if (!ringerNormal()) return
            active = true
            meter.reset(x.toDouble(), y.toDouble(), tMs / 1000.0)
            tracker?.reset()
            plays++
            hitKey(p, x, y)
            return
        }
        if (!ready(sampleId)) return
        if (!ringerNormal()) return
        active = true
        meter.reset(x.toDouble(), y.toDouble(), tMs / 1000.0)
        lastMoveMs = tMs
        env.begin()
        if (style.followsX) rateTarget = fluteRate(x).also { rate = it }   // cú vuốt mới: bắt cao độ ngay, không trượt
        if (stream == 0) {
            stream = p.play(sampleId, 0f, 0f, 1, -1, rate.toFloat()); env.reset()
            if (stream != 0 && ready(layerId)) layerStream = p.play(layerId, 0f, 0f, 1, -1, 1f)
        } else if (style.followsX) p.setRate(stream, rate.toFloat())
        if (stream == 0) { active = false; return }
        plays++
        if (!ticking) { ticking = true; main.postDelayed(tick, TICK_MS) }
    }

    /** Một điểm vuốt — đo tốc độ (+ dò phím / cao độ đích); không cấp phát. SoundPool chỉ khi vào phím mới (Nốt nhạc). */
    fun move(x: Float, y: Float, tMs: Long) {
        if (!active) return
        meter.move(x.toDouble(), y.toDouble(), tMs / 1000.0)
        lastMoveMs = tMs
        if (style.isNotes) pool?.let { hitKey(it, x, y) }
        else if (style.followsX) rateTarget = fluteRate(x)
    }

    /** Sáo trúc: tốc độ phát theo vị trí ngang; chưa có layout ⇒ cao độ gốc. */
    private fun fluteRate(x: Float): Double = tracker?.let { SwipeSoundFx.fluteRate(it.unitX(x.toDouble())) } ?: 1.0

    /** Nốt nhạc theo phím: vào phím mới ⇒ gảy nốt của bậc phím, to theo tốc độ đã làm mượt. */
    private fun hitKey(p: SoundPool, x: Float, y: Float) {
        val k = tracker?.feed(x.toDouble(), y.toDouble()) ?: return
        if (k < 0) return
        val id = noteIds[SwipeNoteMap.step(k)]
        if (!ready(id)) return
        val v = SwipeSoundFx.noteVelocity(meter.speed).toFloat() * gain
        if (p.play(id, v, v, 1, 0, 1f) != 0) notesPlayed++
    }

    /**
     * Nhấc tay ([liftAtMs] = eventTime của lần nhấc) / huỷ (null): tắt dần rồi dừng. Nhấc tay ở kiểu có tiếng nhấc tay ⇒
     * phát một lần, to theo tốc độ [SwipeSoundFx.LIFT_WINDOW] cuối (gần như đứng yên ⇒ không kêu). Nốt nhạc: nốt ngân hết.
     */
    fun end(liftAtMs: Long? = null) {
        if (!active) return
        active = false
        if (style.isNotes) return
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
            if (style.followsX) { rate += (rateTarget - rate) * glideK; p.setRate(stream, rate.toFloat()) }
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
        pool = null; sampleId = 0; layerId = 0; liftId = 0; noteIds.fill(0); loadedIds.clear()
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

        /** WAV cache: [part] = "loop" | "layer" (lớp dày) | "lift" (tiếng nhấc tay). */
        fun cacheFile(dir: File, s: SwipeSoundStyle, part: String): File? {
            val name = if (part == "loop") "swipesound-v$LOOP_VERSION-${s.id}.wav" else "swipesound-v$LOOP_VERSION-${s.id}-$part.wav"
            return writeOnce(dir, name) {
                when (part) {
                    "layer" -> KeySoundSynth.swipeLayerSamples(s)
                    "lift" -> KeySoundSynth.swipeLiftSamples(s)
                    else -> KeySoundSynth.swipeLoopSamples(s)
                }
            }
        }

        /** WAV cache nốt bậc [step] của nhạc cụ (Nốt nhạc theo phím). */
        fun noteFile(dir: File, inst: KeyInstrument, step: Int): File? =
            writeOnce(dir, "swipesound-v$LOOP_VERSION-notes-${inst.cacheTag}-$step.wav") { KeySoundSynth.swipeNoteSamples(inst, step) }

        private fun writeOnce(dir: File, name: String, samples: () -> FloatArray): File? = runCatching {
            val f = File(dir, name)
            if (!f.exists() || f.length() == 0L) {
                val tmp = File(dir, "$name.tmp")
                tmp.writeBytes(KeySoundSynth.wav(samples(), KeySoundSynth.SWIPE_SAMPLE_RATE))
                tmp.renameTo(f)
            }
            f
        }.getOrNull()

        /** Đổi khi đổi công thức vòng lặp ⇒ file cache cũ không dùng nữa. */
        const val LOOP_VERSION = 1
    }
}
