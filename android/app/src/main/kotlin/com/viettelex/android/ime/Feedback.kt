package com.viettelex.android.ime

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.SoundPool
import android.os.SystemClock
import android.view.HapticFeedbackConstants
import android.view.View
import com.viettelex.keyboard.ChordProgression
import com.viettelex.keyboard.HapticStrength
import com.viettelex.keyboard.KeyInstrument
import com.viettelex.keyboard.KeySoundCustom
import com.viettelex.keyboard.KeySoundStyle
import com.viettelex.keyboard.KeySoundSynth
import com.viettelex.keyboard.PianoEvent
import com.viettelex.keyboard.NoteMap
import com.viettelex.keyboard.PianoMap
import com.viettelex.keyboard.PianoPedal
import com.viettelex.keyboard.PianoSynth
import com.viettelex.keyboard.VoicePool
import java.io.File

/**
 * Âm + rung ở TOUCH-DOWN (spec §8). Âm: AudioManager.playSoundEffect — chỉ kêu khi
 * "Âm thanh khi chạm" của hệ thống bật. Rung: toggle hapticFeedback (mặc định TẮT) +
 * độ mạnh hapticStrength 10…100 % (giống iOS). Rung bằng Vibrator (quyền VIBRATE, qua
 * [KeyVibrator] — hiệu ứng rẻ pin nhất: primitive TICK có scale / one-shot ngắn) chứ không
 * performHapticFeedback: KEYBOARD_TAP bị hệ thống bỏ qua khi "Phản hồi khi chạm"/"Rung bàn
 * phím" tắt (FLAG_IGNORE_GLOBAL_SETTING vô hiệu từ API 33) và không chỉnh được độ mạnh.
 * Tắt rung ⇒ không lấy Vibrator, không dựng gì. Máy không có motor ⇒ performHapticFeedback.
 *
 * Âm thanh phím riêng (setting keySound, mặc định TẮT ⇒ playSoundEffect như trên): BẬT ⇒
 * tiếng theo kiểu keySoundStyle ([KeySoundSynth] 5 kiểu tổng hợp, hoặc âm tự chọn trong
 * noBackupFilesDir) qua SoundPool nạp sẵn, theo âm lượng thanh trượt, KHÔNG kèm tiếng hệ
 * thống; im khi máy ở Rung/Im lặng (như Gboard/AOSP LatinIME). SoundPool rảnh không tốn
 * CPU (không có luồng render liên tục như AVAudioEngine iOS) và được nhả khi ẩn bàn phím.
 * Kiểu "Hệ thống" (keySoundStyle = system) ⇒ y như TẮT: playSoundEffect, không dựng SoundPool,
 * không đọc ringer — 0 chi phí.
 *
 * Kiểu "Piano" (Phil 19/10/2026): mỗi phím một nốt ([PianoMap]); SoundPool maxStreams 16 = 8 giọng
 * thường + 8 giọng ngân, xoay vòng [VoicePool] — bấm nhiều ngón cùng lúc (ACTION_POINTER_DOWN) mỗi
 * ngón một nốt, giọng cùng cửa sổ 60 ms hạ 1/√n. Bộ nốt thường (22.05 kHz, 25 nốt + cách/Enter/⌫/
 * pedal ≈ 0.99 MB PCM16) nạp lúc hiện; bộ ngân (11.025 kHz 2.5 s ≈ 1.38 MB) nạp lười lần đầu đạp
 * pedal (Shift/Caps). Kiểu khác: đường 3 tiếng như cũ (thêm một phép so bool).
 *
 * Kiểu "Đàn tranh" (theme Sen Việt, 19/10/2026): CÙNG đường Piano ([KeyInstrument] chọn bảng nốt + bộ tổng hợp,
 * pool giọng / pedal / damper dùng chung). Bộ nốt thường 1.0 s ≈ 1.22 MB PCM16, bộ ngân ≈ 1.38 MB như Piano.
 *
 * Vòng hợp âm phím cách (10/2026): Piano / Ghi-ta có [NoteMap.progression] ⇒ mỗi hợp âm một WAV nạp sẵn
 * ([PianoEvent.chord]), [progression] (thuần, như iOS) chọn hợp âm: tiến mỗi lần cách, nghỉ > 3 s / kết câu ⇒ về đầu,
 * Enter ⇒ chủ rồi về đầu. Đàn tranh: hợp âm cách cố định. Ghi-ta (theme Ghi-ta): nốt 1.2 s ⇒ bộ thường ≈ 1.62 MB PCM16.
 */
class Feedback(private val ctx: Context) {
    private val audio = ctx.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val vibrator = KeyVibrator(ctx)
    @Volatile var hapticsEnabled = false
        set(v) { field = v; if (!v) vibrator.clear() }

    /** % đã kẹp. */
    @Volatile var hapticStrength = HapticStrength.DEFAULT
        set(v) { field = HapticStrength.clamp(v) }

    /** Rung một nhịp theo độ mạnh; false ⇒ không có Vibrator, gọi view.performHapticFeedback. */
    private fun vibrate(tick: Boolean): Boolean =
        vibrator.vibrate(if (tick) hapticStrength / 2 else hapticStrength)

    // --- Âm phím riêng (chỉ đụng trên main, trừ nạp WAV trên worker) ---
    private var soundEnabled = false
    private var soundStyle: String = KeySoundStyle.DEFAULT.id
    private var volumePercent = 50
    private var gain = KeySoundSynth.gain(50)
    private var pool: SoundPool? = null
    /** Khoá bộ mẫu đang nạp (kiểu + mtime file tự chọn) — đổi ⇒ nạp lại. */
    private var poolKey: String? = null
    /** id SoundPool theo [KeySoundSynth.Kind.ordinal]; 0 = chưa nạp xong. */
    private val ids = IntArray(KeySoundSynth.Kind.entries.size)
    /** Hệ số âm lượng từng loại (âm tự chọn: một file, xoá/chức năng nhỏ hơn chút). */
    private val kindGain = FloatArray(ids.size) { 1f }
    @Volatile private var loaded = BooleanArray(ids.size)
    /** Tiếng Enter riêng của kiểu (Máy chữ: "ding" về dòng) — 0 = không có ⇒ Enter dùng tiếng phím chức năng. */
    private var returnId = 0
    @Volatile private var returnLoaded = false
    private var ringerNormal = true
    private var ringerCheckedAt = 0L
    /** Test hook: đường âm lần bấm gần nhất. */
    var lastRoute: KeySoundSynth.Route? = null
        private set

    // --- Nhạc cụ mỗi phím một nốt (Piano / Đàn tranh) ---
    private var pianoMode = false
    /** Nhạc cụ đang nạp (khi [pianoMode]). */
    var instrument: KeyInstrument = KeyInstrument.PIANO
        private set
    private var noteMap: NoteMap = NoteMap.PIANO
    private val pianoIds = IntArray(128)
    private val sustainIds = IntArray(128)
    /** cách, Enter, ⌫, pedal, rồi hợp âm vòng 0…MAX_CHORDS−1 (thứ tự = [PianoEvent.extraIndex]). */
    private val pianoExtra = IntArray(4 + PianoEvent.MAX_CHORDS)
    @Volatile private var pianoLoaded = BooleanArray(PIANO_MAX_SAMPLE_IDS)
    private var pianoPool = VoicePool(PianoSynth.VOICES)
    private var sustainPool = VoicePool(PianoSynth.VOICES)
    private val pianoStreams = IntArray(PianoSynth.VOICES)
    private val sustainStreams = IntArray(PianoSynth.VOICES)
    /** 0 = chưa, 1 = đang dựng, 2 = đã nạp. */
    private var sustainState = 0
    private var soundWorker: ((Runnable) -> Unit)? = null
    private val main = android.os.Handler(android.os.Looper.getMainLooper())
    /** Pedal ngân (Shift/Caps người dùng bấm). */
    val pedal = PianoPedal()
    /** Vòng hợp âm phím cách (count 0 = không vòng: Đàn tranh / kiểu khác). */
    var progression = ChordProgression(0)
        private set
    private fun progressionClock(): Double = SystemClock.uptimeMillis() / 1000.0
    // --- "Éc" của theme Đập chuột ([com.viettelex.keyboard.MoleGame]) — chỉ nạp khi theme bật trò chơi ---
    private var squeakWanted = false
    private var squeakId = 0
    @Volatile private var squeakLoaded = false
    /** Test: số lần phát "éc". */
    var squeaks = 0
        private set

    /** Test/log: giọng lần phát piano gần nhất (≥ VOICES = giọng ngân). */
    var lastPianoVoice = -1
        private set

    /**
     * Áp setting lúc bàn phím hiện. BẬT ⇒ dựng SoundPool + nạp 3 mẫu ([worker] ghi WAV cache
     * lần đầu / đọc file tự chọn); TẮT ⇒ nhả hết (0 chi phí). Đổi kiểu/file ⇒ nạp lại.
     */
    fun configureSound(enabled: Boolean, volume: Int, style: String, worker: (Runnable) -> Unit) {
        soundEnabled = enabled
        soundStyle = style
        soundWorker = worker
        pedal.reset()
        progression = ChordProgression(KeyInstrument.of(style)?.map?.progression?.size ?: 0)
        volumePercent = volume.coerceIn(0, 100)
        gain = KeySoundSynth.gain(volumePercent)
        if (!needsPool(enabled, volumePercent, style)) { releaseSound(); return }
        refreshRinger(force = true)
        val customFile = customFile(ctx)
        val key = KeySoundCustom.bankKey(style, customFile)
        if (pool != null && key == poolKey) { loadSqueak(); return }
        releaseSound()
        val inst = KeyInstrument.of(style)
        val p = SoundPool.Builder().setMaxStreams(if (inst != null) 2 * PianoSynth.VOICES else 4).setAudioAttributes(
            AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build()).build()
        pool = p; poolKey = key
        val fresh = BooleanArray(ids.size); loaded = fresh
        val dir = ctx.cacheDir
        if (inst != null) { configurePiano(p, dir, inst, worker); loadSqueak(); return }
        p.setOnLoadCompleteListener { sp, sampleId, status ->
            if (sp !== pool || status != 0) return@setOnLoadCompleteListener
            for (i in ids.indices) if (ids[i] == sampleId) fresh[i] = true
            if (sampleId == returnId) returnLoaded = true
            if (sampleId == squeakId) squeakLoaded = true
        }
        loadSqueak()
        worker(Runnable {
            val files = soundFiles(dir, style, customFile)
            val ret = returnFile(dir, style)
            android.os.Handler(android.os.Looper.getMainLooper()).post {
                if (pool !== p) return@post
                if (ret != null) returnId = p.load(ret.path, 1)
                val custom = files.distinct().size == 1 && files[0] == customFile
                var sharedId = 0
                files.forEachIndexed { i, f ->
                    if (f == null) return@forEachIndexed
                    ids[i] = if (custom && sharedId != 0) sharedId else p.load(f.path, 1).also { sharedId = it }
                    kindGain[i] = if (custom) CUSTOM_KIND_GAIN[i] else 1f
                }
            }
        })
    }

    /** Piano / Đàn tranh: nạp bộ nốt thường (worker ghi WAV cache lần đầu, main nạp SoundPool). */
    private fun configurePiano(p: SoundPool, dir: File, inst: KeyInstrument, worker: (Runnable) -> Unit) {
        pianoMode = true
        instrument = inst; noteMap = inst.map
        soundWorker = worker
        pianoPool = VoicePool(PianoSynth.VOICES); sustainPool = VoicePool(PianoSynth.VOICES)
        val fresh = BooleanArray(PIANO_MAX_SAMPLE_IDS); pianoLoaded = fresh
        p.setOnLoadCompleteListener { sp, sampleId, status ->
            if (sp === pool && status == 0 && sampleId in fresh.indices) fresh[sampleId] = true
            if (sp === pool && status == 0 && sampleId == squeakId) squeakLoaded = true
        }
        worker(Runnable {
            val notes = inst.map.notes.map { it to pianoNoteFile(dir, inst, it, sustain = false) }
            val extras = pianoExtraFiles(dir, inst)
            main.post {
                if (pool !== p) return@post
                for ((m, f) in notes) if (f != null) pianoIds[m] = p.load(f.path, 1)
                // Cùng file (cách = hợp âm 0) ⇒ cùng sample id, không nạp đôi.
                val loadedIds = HashMap<String, Int>()
                extras.forEachIndexed { i, f ->
                    if (f != null && i < pianoExtra.size) pianoExtra[i] = loadedIds.getOrPut(f.path) { p.load(f.path, 1) }
                }
            }
        })
    }

    /** Bộ nốt ngân: dựng lười lần đầu đạp pedal. */
    private fun kickSustain() {
        if (sustainState != 0) return
        val p = pool ?: return
        val w = soundWorker ?: return
        sustainState = 1
        val dir = ctx.cacheDir
        val inst = instrument
        w(Runnable {
            val notes = inst.map.notes.map { it to pianoNoteFile(dir, inst, it, sustain = true) }
            main.post {
                if (pool !== p) return@post
                for ((m, f) in notes) if (f != null) sustainIds[m] = p.load(f.path, 1)
                sustainState = 2
            }
        })
    }

    /** Theme Đập chuột đang bật ⇒ nạp mẫu "éc" vào SoundPool (nếu có); tắt ⇒ bỏ. Theme khác: không gọi gì thêm. */
    fun setSqueakEnabled(on: Boolean) {
        squeakWanted = on
        if (!on) { squeakId = 0; squeakLoaded = false } else loadSqueak()
    }

    private fun loadSqueak() {
        val p = pool ?: return
        val w = soundWorker ?: return
        if (!squeakWanted || squeakId != 0) return
        squeakId = -1                                  // đang nạp
        val dir = ctx.cacheDir
        w(Runnable {
            val f = squeakFile(dir)
            main.post { if (pool === p && squeakWanted && f != null) squeakId = p.load(f.path, 1) }
        })
    }

    /** "Éc" khi đập trúng chuột: CHỈ khi Âm thanh phím (đường âm riêng) đang phát ([com.viettelex.keyboard.MolePolicy]). */
    fun squeak(): Boolean {
        val route = KeySoundSynth.route(soundEnabled, volumePercent, ringerNormal(), soundStyle)
        if (!squeakAllowed(route)) return false
        squeaks++
        if (squeakLoaded && squeakId > 0) pool?.play(squeakId, gain, gain, 2, 0, 1f)
        return true
    }

    /** Nhả SoundPool (ẩn bàn phím, thiếu RAM, tắt setting). */
    fun releaseSound() {
        pool?.release()
        pool = null
        poolKey = null
        ids.fill(0)
        loaded = BooleanArray(ids.size)
        returnId = 0; returnLoaded = false
        squeakId = 0; squeakLoaded = false
        pianoMode = false
        pianoIds.fill(0); sustainIds.fill(0); pianoExtra.fill(0)
        pianoStreams.fill(0); sustainStreams.fill(0)
        sustainState = 0
    }

    /** Phím ký tự có nhãn ([label]): Piano ⇒ nốt theo vị trí; kiểu khác ⇒ [click] như cũ. */
    fun clickKey(label: String?, kind: Int, view: View) {
        if (!pianoMode) { click(kind, view); return }
        val route = KeySoundSynth.route(soundEnabled, volumePercent, ringerNormal(), soundStyle)
        lastRoute = route
        if (progression.count > 0) progression.typed(progressionClock(), ChordProgression.isSentenceEnd(label))
        if (route == KeySoundSynth.Route.CUSTOM) playPiano(noteMap.midiForKey(label), pedal.noteTyped())
        haptic(view)
    }

    /** Kết câu không qua phím "." (cách đúp ⇒ ". "): vòng hợp âm cách về đầu. */
    fun sentenceEnd() {
        if (pianoMode && progression.count > 0) progression.typed(progressionClock(), true)
    }

    /** Sự kiện piano của phím không nhãn — đi qua vòng hợp âm (cách / Enter / ⌫ cập nhật [progression]). */
    private fun pianoEventFor(kind: Int): Int =
        if (progression.count > 0) progressionEvent(kind, progression, progressionClock()) else pianoEvent(kind)

    /** Người dùng bấm Shift, [result] = trạng thái SAU khi bấm. Piano ⇒ pedal/damper; kiểu khác ⇒ tiếng chức năng. */
    fun shiftPressed(result: PianoPedal.Shift, view: View) {
        if (!pianoMode) { click(MODIFIER, view); return }
        val route = KeySoundSynth.route(soundEnabled, volumePercent, ringerNormal(), soundStyle)
        lastRoute = route
        when (pedal.shiftPressed(result)) {
            PianoPedal.Action.PEDAL_DOWN -> if (route == KeySoundSynth.Route.CUSTOM) playPiano(PianoEvent.PEDAL, false)
            PianoPedal.Action.DAMPER -> damper()
            PianoPedal.Action.NONE -> {}
        }
        haptic(view)
    }

    /** Shift đổi không do bấm phím Shift: Caps tắt ⇒ damper. */
    fun shiftChanged(now: PianoPedal.Shift) {
        if (pianoMode && pedal.shiftChanged(now) == PianoPedal.Action.DAMPER) damper()
    }

    /** Piano: một sự kiện ([PianoEvent] / nốt MIDI). Chỉ lên lịch SoundPool, không cấp phát. */
    private fun playPiano(ev: Int, sustain: Boolean) {
        val p = pool ?: return
        var id = 0
        var sus = false
        if (ev >= 0) {
            if (ev > 127) return
            if (sustain) {
                if (sustainState == 2 && sustainIds[ev] != 0 && sustainIds[ev] < pianoLoaded.size && pianoLoaded[sustainIds[ev]]) {
                    id = sustainIds[ev]; sus = true
                } else kickSustain()
            }
            if (id == 0) id = pianoIds[ev]
        } else {
            val xi = PianoEvent.extraIndex(ev)
            id = if (xi < pianoExtra.size && pianoExtra[xi] != 0) pianoExtra[xi] else pianoExtra[0]   // hợp âm lạ ⇒ cách
            if (ev == PianoEvent.PEDAL) kickSustain()
        }
        if (id <= 0 || id >= pianoLoaded.size || !pianoLoaded[id]) return
        val now = SystemClock.uptimeMillis() / 1000.0
        val vp = if (sus) sustainPool else pianoPool
        val streams = if (sus) sustainStreams else pianoStreams
        val v = vp.allocate(now)
        val g = gain * VoicePool.chordScale(vp.simultaneous(now))
        for (i in 0 until vp.size) if (i != v && streams[i] != 0 && vp.isRecent(i, now)) p.setVolume(streams[i], g, g)
        streams[v] = p.play(id, g, g, 1, 0, 1f)
        lastPianoVoice = v + if (sus) PianoSynth.VOICES else 0
    }

    /** Tắt Caps (nhả pedal): nốt đang ngân tắt nhanh ~90 ms (3 nấc) thay vì ngân tiếp. */
    private fun damper() {
        val p = pool ?: return
        val s = sustainStreams.copyOf()
        val g = gain
        for (id in s) if (id != 0) p.setVolume(id, g * 0.35f, g * 0.35f)
        main.postDelayed({ if (pool === p) for (id in s) if (id != 0) p.setVolume(id, g * 0.12f, g * 0.12f) }, 40)
        main.postDelayed({ if (pool === p) for (id in s) if (id != 0) p.stop(id) }, 90)
        sustainStreams.fill(0)
    }

    private fun haptic(view: View) {
        if (hapticsEnabled && !vibrate(tick = false)) {
            view.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP,
                HapticFeedbackConstants.FLAG_IGNORE_VIEW_SETTING)
        }
    }

    fun click(kind: Int, view: View) {
        val route = KeySoundSynth.route(soundEnabled, volumePercent, ringerNormal(), soundStyle)
        lastRoute = route
        when (route) {
            KeySoundSynth.Route.SYSTEM -> audio.playSoundEffect(when (kind) {
                DELETE -> AudioManager.FX_KEYPRESS_DELETE
                SPACE -> AudioManager.FX_KEYPRESS_SPACEBAR
                RETURN -> AudioManager.FX_KEYPRESS_RETURN
                else -> AudioManager.FX_KEYPRESS_STANDARD
            })
            KeySoundSynth.Route.CUSTOM -> if (pianoMode) playPiano(pianoEventFor(kind), false)
            else if (kind == RETURN && returnLoaded) pool?.play(returnId, gain, gain, 1, 0, 1f)   // Máy chữ: "ding"
            else {
                val i = soundKind(kind).ordinal
                val g = gain * kindGain[i]
                if (loaded[i]) pool?.play(ids[i], g, g, 1, 0, 1f)
            }
            KeySoundSynth.Route.SILENT -> {}
        }
        if (hapticsEnabled && !vibrate(tick = false)) {
            view.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP,
                HapticFeedbackConstants.FLAG_IGNORE_VIEW_SETTING)
        }
    }

    /** Cù nhân vật: chỉ click hệ thống (tự tắt theo cài đặt âm bàn phím), không phát mẫu riêng/rung. */
    fun buddyClick() { audio.playSoundEffect(AudioManager.FX_KEYPRESS_STANDARD) }

    /** Nấc nhẹ (vuốt ⌫ thêm/bớt một từ): chỉ rung, không âm. */
    fun tick(view: View) {
        if (hapticsEnabled && !vibrate(tick = true)) view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK,
            HapticFeedbackConstants.FLAG_IGNORE_VIEW_SETTING)
    }

    /** Giữ lâu đã kích hoạt (Enter xuống dòng): rung LONG_PRESS; tắt rung app ⇒ theo cài đặt hệ thống. */
    fun longPress(view: View) {
        if (hapticsEnabled) view.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS,
            HapticFeedbackConstants.FLAG_IGNORE_VIEW_SETTING)
        else view.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
    }

    /** Ringer mode đọc qua binder — chỉ khi âm riêng bật, cache 2 s (gạt Rung/Im giữa lúc gõ vẫn kịp). */
    private fun ringerNormal(): Boolean {
        if (soundEnabled && KeySoundStyle.needsPool(soundStyle)) refreshRinger(force = false)
        return ringerNormal
    }

    private fun refreshRinger(force: Boolean) {
        val now = SystemClock.uptimeMillis()
        if (!force && now - ringerCheckedAt < 2000) return
        ringerCheckedAt = now
        ringerNormal = runCatching { audio.ringerMode == AudioManager.RINGER_MODE_NORMAL }.getOrDefault(true)
    }

    companion object {
        const val LETTER = 0
        const val DELETE = 1
        const val MODIFIER = 2
        const val SPACE = 3
        const val RETURN = 4
        private val CUSTOM_KIND_GAIN = floatArrayOf(1f, 0.9f, 0.82f)   // = KeySoundCustom.variant

        /** "Éc" chỉ khi đường âm riêng đang phát (Âm thanh phím bật, âm lượng > 0, máy không im) — test được. */
        fun squeakAllowed(route: KeySoundSynth.Route): Boolean =
            com.viettelex.keyboard.MolePolicy.shouldSqueak(route == KeySoundSynth.Route.CUSTOM)

        /** WAV "éc" (cache, ghi 1 lần). */
        fun squeakFile(dir: File): File? =
            cachedWav(dir, "keysound-v${KeySoundSynth.VERSION}-squeak.wav", KeySoundSynth.SAMPLE_RATE) { KeySoundSynth.squeakSamples() }

        /** Kiểu đã lưu là nhạc cụ mỗi phím một nốt (Piano / Đàn tranh — đường nốt riêng). */
        fun isPiano(style: String?): Boolean = KeyInstrument.of(style) != null

        /** Loại phím không mang nhãn ⇒ sự kiện piano (cách/Enter/⌫ riêng; còn lại C4 / C3). */
        fun pianoEvent(kind: Int): Int = when (kind) {
            LETTER -> PianoMap.FALLBACK_BASE
            DELETE -> PianoEvent.DELETE
            SPACE -> PianoEvent.SPACE
            RETURN -> PianoEvent.RETURN
            else -> PianoMap.MODIFIER_NOTE
        }

        /**
         * Phím không nhãn khi nhạc cụ có vòng hợp âm (thuần — test được): cách ⇒ hợp âm KẾ TIẾP ([PianoEvent.chord]);
         * Enter ⇒ chủ ([PianoEvent.RETURN]) rồi vòng về đầu; ⌫ ⇒ tính là đang gõ; còn lại như [pianoEvent].
         */
        fun progressionEvent(kind: Int, prog: ChordProgression, now: Double): Int {
            if (prog.count > 0) when (kind) {
                SPACE -> return PianoEvent.chord(prog.space(now))
                RETURN -> prog.returnKey(now)
                DELETE -> prog.typed(now, false)
            }
            return pianoEvent(kind)
        }

        /** Số sample id tối đa theo dõi (25 nốt + 4 âm + 25 nốt ngân < 128). */
        const val PIANO_MAX_SAMPLE_IDS = 128

        /** WAV nốt (cache, ghi 1 lần; tên kèm nhạc cụ + phiên bản thuật toán — Piano giữ tên cũ "keysound-piano-v1-…"). */
        fun pianoNoteFile(dir: File, inst: KeyInstrument, midi: Int, sustain: Boolean): File? =
            cachedWav(dir, "keysound-${inst.cacheTag}-${if (sustain) "sus" else "n"}-$midi.wav",
                if (sustain) PianoSynth.SUSTAIN_SAMPLE_RATE else PianoSynth.SAMPLE_RATE) { inst.note(midi, sustain) }
        fun pianoNoteFile(dir: File, midi: Int, sustain: Boolean): File? = pianoNoteFile(dir, KeyInstrument.PIANO, midi, sustain)

        /**
         * WAV cách / Enter / ⌫ / pedal, rồi hợp âm vòng (thứ tự = [PianoEvent.extraIndex]). Nhạc cụ có vòng: "cách" =
         * CÙNG file hợp âm 0 (không ghi / nạp thêm). Hợp âm Piano đổi (vòng 10/2026) ⇒ tên file mới "chordN".
         */
        fun pianoExtraFiles(dir: File, inst: KeyInstrument = KeyInstrument.PIANO): List<File?> {
            val chords = inst.map.progression.indices.map { i ->
                cachedWav(dir, "keysound-${inst.cacheTag}-chord$i.wav", PianoSynth.SAMPLE_RATE) { inst.chord(i) }
            }
            val space = if (chords.isNotEmpty()) chords[0]
                else cachedWav(dir, "keysound-${inst.cacheTag}-space.wav", PianoSynth.SAMPLE_RATE) { inst.space() }
            return listOf(space,
                cachedWav(dir, "keysound-${inst.cacheTag}-return.wav", PianoSynth.SAMPLE_RATE) { inst.returnChord() },
                cachedWav(dir, "keysound-${inst.cacheTag}-delete.wav", PianoSynth.SAMPLE_RATE) { inst.delete() },
                cachedWav(dir, "keysound-${inst.cacheTag}-pedal.wav", PianoSynth.SAMPLE_RATE) { inst.pedal() }) + chords
        }

        private fun cachedWav(dir: File, name: String, rate: Int, make: () -> FloatArray): File? = runCatching {
            val f = File(dir, name)
            if (!f.exists() || f.length() == 0L) {
                val tmp = File(dir, "$name.tmp")
                tmp.writeBytes(KeySoundSynth.wav(make(), rate))
                tmp.renameTo(f)
            }
            f
        }.getOrNull()

        /** Có dựng SoundPool không: BẬT + âm lượng > 0 + kiểu không phải "Hệ thống". */
        fun needsPool(enabled: Boolean, volume: Int, style: String?): Boolean =
            enabled && volume > 0 && KeySoundStyle.needsPool(style)

        /** Loại phím → tiếng: chữ / xoá / còn lại (cách, Enter, shift… như stock). */
        fun soundKind(kind: Int): KeySoundSynth.Kind = when (kind) {
            LETTER -> KeySoundSynth.Kind.LETTER
            DELETE -> KeySoundSynth.Kind.DELETE
            else -> KeySoundSynth.Kind.MODIFIER
        }

        /** File âm tự chọn đã xử lý (noBackupFilesDir — không vào Auto Backup). */
        fun customFile(ctx: Context): File = File(ctx.noBackupFilesDir, KeySoundCustom.FILE_NAME)

        /**
         * File cho 3 loại phím theo kiểu đã lưu: custom hợp lệ ⇒ cùng một file tự chọn; còn lại
         * (hoặc custom vắng/hỏng) ⇒ WAV tổng hợp của kiểu thật sự phát. Chạy trên worker.
         */
        fun soundFiles(dir: File, style: String, custom: File?): List<File?> {
            val ok = style == KeySoundStyle.CUSTOM.id && KeySoundCustom.load(custom) != null
            val st = KeySoundStyle.resolve(style, ok)
            return if (st == KeySoundStyle.CUSTOM) KeySoundSynth.Kind.entries.map { custom }
            else KeySoundSynth.Kind.entries.map { wavFile(dir, st, it) }
        }

        /** WAV tiếng Enter riêng của kiểu đã lưu (Máy chữ: "ding"); null = kiểu không có / custom / ghi lỗi. Chạy trên worker. */
        fun returnFile(dir: File, style: String): File? {
            val st = KeySoundStyle.resolve(style, false)
            if (KeySoundSynth.returnRecipe(st) == null) return null
            return runCatching {
                val f = File(dir, "keysound-v${KeySoundSynth.VERSION}-${st.id}-return.wav")
                if (!f.exists() || f.length() == 0L) {
                    val tmp = File(dir, f.name + ".tmp")
                    tmp.writeBytes(KeySoundSynth.wav(KeySoundSynth.returnSamples(st)!!))
                    tmp.renameTo(f)
                }
                f
            }.getOrNull()
        }

        /** WAV tất định ghi 1 lần vào cache (tên kèm VERSION + kiểu). null nếu ghi lỗi. */
        fun wavFile(dir: File, k: KeySoundSynth.Kind): File? = wavFile(dir, KeySoundStyle.DEFAULT, k)

        fun wavFile(dir: File, style: KeySoundStyle, k: KeySoundSynth.Kind): File? = runCatching {
            val f = File(dir, "keysound-v${KeySoundSynth.VERSION}-${style.id}-${k.name.lowercase()}.wav")
            if (!f.exists() || f.length() == 0L) {
                val tmp = File(dir, f.name + ".tmp")
                tmp.writeBytes(KeySoundSynth.wav(style, k))
                tmp.renameTo(f)
            }
            f
        }.getOrNull()
    }
}
