package com.viettelex.android.ime

import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.inputmethodservice.InputMethodService
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.os.Process
import android.os.SystemClock
import android.util.Log
import android.view.View
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import androidx.core.view.WindowInsetsControllerCompat
import com.viettelex.android.BuildConfig
import com.viettelex.android.shared.DebugLog
import com.viettelex.android.shared.VTPrefs
import com.viettelex.keyboard.Cancellable
import com.viettelex.keyboard.EmojiRecents
import com.viettelex.keyboard.FieldTraits
import com.viettelex.keyboard.Key
import com.viettelex.keyboard.KeyboardData
import com.viettelex.keyboard.KeyboardSession
import com.viettelex.keyboard.Keys
import com.viettelex.keyboard.MainThread
import com.viettelex.keyboard.SuggestionPlan
import com.viettelex.keyboard.TemplateItem
import com.viettelex.keyboard.Templates
import com.viettelex.keyboard.UserLangModel
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

/**
 * Bàn phím VietTelex (port iOS KeyboardViewController — phần nối dây; logic nằm ở
 * [KeyboardSession] của module :keyboard). Không Compose, không thư viện ngoài.
 *
 * Luồng: phím (touch-down) → session.handle trong MỘT batch edit → auto-shift ngay
 * lượt main kế → gợi ý sau 30 ms (phím mới huỷ lượt cũ) → phần nặng (VNSuggest +
 * AdjacentKeyFixer) trên HandlerThread "vt-suggest" → kết quả áp nếu còn hiện hành.
 * Không Handler nào được đặt khi không gõ.
 */
class VietTelexIME : InputMethodService(), KeyboardView.Listener, StripView.Listener {

    private val handler = Handler(Looper.getMainLooper())
    private val mainThread = object : MainThread {
        override fun post(r: Runnable) { handler.post(r) }
        override fun postDelayed(delayMs: Long, r: Runnable): Cancellable {
            handler.postDelayed(r, delayMs); return Cancellable { handler.removeCallbacks(r) }
        }
    }
    private lateinit var prefs: SharedPreferences
    private lateinit var model: UserLangModel
    private lateinit var clipboard: AndroidClipboard
    private lateinit var session: KeyboardSession
    private val tracker = SelectionTracker()
    private val proxy by lazy { IcProxy(this, tracker) }
    private val feedback by lazy { Feedback(this) }

    private var worker: Handler? = null
    private var workerThread: HandlerThread? = null

    private var root: ImeRootView? = null
    private var keyboard: KeyboardView? = null
    private var strip: StripView? = null
    private var theme: ImeTheme? = null

    private var field = FieldMapping.map(0, 0)
    private var pendingGen = 0
    private var collapsed = false

    private val autoShiftRun = Runnable { if (pendingGen == session.generation) applyAutoShift() }
    private val suggestRun = Runnable { if (pendingGen == session.generation) refreshBar() }

    private val prefListener = SharedPreferences.OnSharedPreferenceChangeListener { _, key ->
        // App vừa "Xóa từ đã học": bỏ model trong RAM NGAY (không bao giờ ghi đè lại).
        if (key == Keys.USERLM_RESET_AT) model.reloadAfterExternalErase()
        // Bật/tắt kiểu gõ trong app khi bàn phím đang mở (ô Thử gõ) → áp ngay, không đợi mở lại.
        else if (key in Keys.ENGINE_KEYS) session.bridge.applySettings(VTPrefs.settings(prefs))
    }

    override fun onCreate() {
        val t0 = SystemClock.elapsedRealtime()
        super.onCreate()
        prefs = VTPrefs.of(this)
        KeyboardData.install(AssetBlobs.provider(assets))
        DebugLog.configure(this, prefs.getBoolean(Keys.DEBUG_TOUCH_LOG, false))
        model = UserLangModel(File(filesDir, Keys.USERLM_FILE), mainThread)
        clipboard = AndroidClipboard(this)
        session = KeyboardSession(model, clipboard)
        model.onReady = { refreshBar() }
        prefs.registerOnSharedPreferenceChangeListener(prefListener)
        if (BuildConfig.DEBUG) Log.d(TAG, "perf onCreate ${SystemClock.elapsedRealtime() - t0} ms")
    }

    override fun onDestroy() {
        prefs.unregisterOnSharedPreferenceChangeListener(prefListener)
        clipboard.release()
        workerThread?.quitSafely()
        session.finishInput()
        super.onDestroy()
    }

    /** iOS không có extract mode — luôn hiện bàn phím thường, kể cả ngang. */
    override fun onEvaluateFullscreenMode() = false

    override fun onCreateInputView(): View {
        val t0 = SystemClock.elapsedRealtime()
        val th = ImeTheme(this)
        theme = th
        val balloon = BalloonView(this, th)
        val kb = KeyboardView(this, th, balloon, feedback)
        val st = StripView(this, th, feedback)
        kb.listener = this
        st.listener = this
        val r = ImeRootView(this, th, kb, st, balloon)
        keyboard = kb; strip = st; root = r
        kb.setSwitcherHint(switcherHintVisible)
        styleWindow(th, r)
        if (BuildConfig.DEBUG) Log.d(TAG, "perf onCreateInputView ${SystemClock.elapsedRealtime() - t0} ms")
        return r
    }

    @Suppress("DEPRECATION")
    private fun styleWindow(th: ImeTheme, v: View) {
        val w = window?.window ?: return
        if (Build.VERSION.SDK_INT < 35) w.navigationBarColor = th.bg
        if (Build.VERSION.SDK_INT >= 29) w.isNavigationBarContrastEnforced = false
        WindowInsetsControllerCompat(w, v).isAppearanceLightNavigationBars = !th.dark
    }

    override fun onStartInputView(info: EditorInfo, restarting: Boolean) {
        val t0 = SystemClock.elapsedRealtime()
        super.onStartInputView(info, restarting)
        val kb = keyboard ?: return
        val st = strip ?: return
        val th = theme ?: return
        val settings = VTPrefs.settings(prefs)
        DebugLog.configure(this, settings.debugTouchLog)
        field = FieldMapping.map(info.inputType, info.imeOptions)
        proxy.secure = field.isSecure
        proxy.rawKeys = field.rawKeys
        proxy.actionId = field.actionId
        tracker.reset(info.initialSelStart, info.initialSelEnd)
        handler.removeCallbacks(autoShiftRun); handler.removeCallbacks(suggestRun)

        session.startInput(settings, FieldTraits(
            isSecure = field.isSecure, passthrough = field.passthrough,
            capSentences = field.capSentences, suggestionsAllowed = field.suggestionsAllowed))
        feedback.hapticsEnabled = settings.hapticFeedback

        collapsed = prefs.getBoolean(Keys.SUGGESTION_BAR_COLLAPSED, false)
        session.barCollapsed = collapsed
        val barOn = session.suggestionsActive
        st.configure(barOn, collapsed, settings.templatesEnabled)
        val templates = if (settings.templatesEnabled) VTPrefs.templates(this, prefs) else emptyList()
        kb.configure(field.returnLabel, field.kind, needsGlobe(), settings.showSpaceLogo,
            settings.templatesEnabled, templates,
            th.dp(KeyLayout.keyAreaDp(th.tablet, th.landscape, settings.rowHeightAdjust)),
            field.numberSigned, field.numberDecimal)
        st.setPlane(kb.plane)
        root?.refreshInsets()
        root?.requestLayout()

        session.invalidatePasteCache()
        applyAutoShift()
        refreshBar()                  // ô trống → gợi mở đầu ngay khi hiện
        if (BuildConfig.DEBUG) Log.d(TAG, "perf onStartInputView ${SystemClock.elapsedRealtime() - t0} ms")
    }

    override fun onWindowShown() {
        super.onWindowShown()
        root?.refreshInsets()           // Android 15+: chừa dải cho nút ⌄/🌐 của hệ thống
        keyboard?.showLanguageBadge()   // "ViệtTelex" thoáng trên space như stock
        keyboard?.setNeedsGlobe(needsGlobe())
        if (BuildConfig.DEBUG) logMemory()
    }

    override fun onFinishInputView(finishingInput: Boolean) {
        super.onFinishInputView(finishingInput)
        handler.removeCallbacks(autoShiftRun); handler.removeCallbacks(suggestRun)
        keyboard?.onHidden()
        strip?.onHidden()
        root?.balloon?.hide()
        session.finishInput()
    }

    override fun onComputeInsets(outInsets: InputMethodService.Insets) {
        super.onComputeInsets(outInsets)
        // Toàn khung input view nhận touch — chạm vào khe không rơi sang app (§5).
        outInsets.touchableInsets = InputMethodService.Insets.TOUCHABLE_INSETS_CONTENT
    }

    override fun onUpdateSelection(oldSelStart: Int, oldSelEnd: Int, newSelStart: Int, newSelEnd: Int,
                                   candidatesStart: Int, candidatesEnd: Int) {
        super.onUpdateSelection(oldSelStart, oldSelEnd, newSelStart, newSelEnd, candidatesStart, candidatesEnd)
        if (!tracker.onUpdate(newSelStart, newSelEnd)) return
        // Đổi từ NGOÀI (chạm chỗ khác, select-all, app tự sửa): quên từ + ngữ cảnh.
        session.externalSelectionChange()
        applyAutoShift()
        refreshBar()
    }

    // MARK: phím

    override fun onKey(key: Key) {
        if (!proxy.begin()) return
        val out = try { session.handle(key, proxy) } finally { proxy.end() }
        if (key is Key.MoveCursor) proxy.moveCursor(key.delta)
        if (key is Key.Letter) strip?.hidePasteCard()
        pendingGen = out.generation
        if (out.needsAutoShift) { handler.removeCallbacks(autoShiftRun); handler.post(autoShiftRun) }
        handler.removeCallbacks(suggestRun)
        handler.postDelayed(suggestRun, SUGGEST_DELAY_MS)
    }

    override fun onDeleteWord() {
        if (!proxy.begin()) return
        try { session.deleteWordBackward(proxy) } finally { proxy.end() }
        applyAutoShift()
        refreshBar()
    }

    override fun onGlobe(longPress: Boolean) {
        val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
        if (longPress) { imm.showInputMethodPicker(); return }
        if (Build.VERSION.SDK_INT >= 28) switchToNextInputMethod(false)
        else {
            val token = window?.window?.attributes?.token ?: return
            @Suppress("DEPRECATION") imm.switchToNextInputMethod(token, false)
        }
    }

    /** Không có phím 🌐 trên bàn phím (user chốt 26/09): đổi bàn phím bằng nút của thanh điều hướng hệ thống. */
    private fun needsGlobe(): Boolean = false

    /**
     * API 36: hệ thống báo khi thanh điều hướng KHÔNG vẽ nút đổi bàn phím → hiện gợi ý 🌐 nhỏ
     * trên phím 😊 (giữ lâu = chọn bàn phím). Có nút hệ thống thì ẩn gợi ý. Dưới API 36 thanh
     * điều hướng luôn có nút khi máy có ≥2 bàn phím → không hiện gợi ý.
     */
    override fun onCustomImeSwitcherButtonRequestedVisible(visible: Boolean) {
        switcherHintVisible = visible
        keyboard?.setSwitcherHint(visible)
    }
    private var switcherHintVisible = false

    override fun onDismissKeyboard() = requestHideSelf(0)

    override fun onPlaneChanged(plane: Plane) {
        strip?.setPlane(plane)
    }

    override fun emojiRecents(): List<String> = EmojiRecents.decode(prefs.getString(Keys.EMOJI_RECENTS, null))

    override fun noteEmojiUsed(e: String) {
        val next = EmojiRecents.noteUsed(emojiRecents(), e)
        prefs.edit().putString(Keys.EMOJI_RECENTS, EmojiRecents.encode(next)).apply()
    }

    // MARK: mẫu câu

    override fun onTemplate(item: TemplateItem) {
        val text = item.text
        if (!Templates.isDynamic(text)) { insertTemplate(text); return }
        // Mẫu động: fetch lúc chạm (timeout 4 s), lỗi ⇒ chèn chính URL.
        val w = worker()
        w.post {
            val bytes = try {
                val c = URL(text).openConnection() as HttpURLConnection
                c.connectTimeout = Templates.FETCH_TIMEOUT_MS
                c.readTimeout = Templates.FETCH_TIMEOUT_MS
                try {
                    c.inputStream.use { ins ->
                        val buf = ByteArray(Templates.FETCH_MAX_BYTES)
                        var n = 0
                        while (n < buf.size) { val r = ins.read(buf, n, buf.size - n); if (r < 0) break; n += r }
                        buf.copyOf(n)
                    }
                } finally { c.disconnect() }
            } catch (_: Exception) { null }
            handler.post { insertTemplate(Templates.bodyFromResponse(bytes) ?: text) }
        }
    }

    private fun insertTemplate(text: String) {
        if (!proxy.begin()) return
        try { session.insertTemplate(text, proxy) } finally { proxy.end() }
        applyAutoShift()
        refreshBar()
    }

    override fun onOpenTemplates() {
        try {
            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("viettelex://maucau"))
                .setPackage(packageName)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP))
        } catch (e: Exception) {
            Log.w(TAG, "open templates: $e")
        }
    }

    // MARK: strip

    override fun onSuggestion(item: String) {
        if (!proxy.begin()) return
        try { session.acceptSuggestion(item, proxy) } finally { proxy.end() }
        applyAutoShift()
        refreshBar()
    }

    override fun onToggleTemplates() { keyboard?.toggleTemplates() }

    override fun onBarToggled(collapsed: Boolean) {
        this.collapsed = collapsed
        prefs.edit().putBoolean(Keys.SUGGESTION_BAR_COLLAPSED, collapsed).apply()
        session.barCollapsed = collapsed
        if (!collapsed) refreshBar()
    }

    override fun onStripHeightChanged() { root?.requestLayout() }

    // MARK: auto-shift + gợi ý

    private fun applyAutoShift() {
        val on = session.updateAutoShift(proxy) ?: return
        keyboard?.setAutoShift(on)
    }

    private fun refreshBar() {
        val st = strip ?: return
        if (!session.suggestionsActive || session.barCollapsed) return
        when (val plan = session.requestSuggestions(proxy)) {
            is SuggestionPlan.Ready -> st.show(plan.set)
            is SuggestionPlan.Background -> {
                val job = plan.job
                worker().post {
                    val r = job.compute()
                    handler.post { session.completeSuggestions(job, r)?.let { strip?.show(it) } }
                }
            }
        }
    }

    private fun worker(): Handler = worker ?: run {
        val t = HandlerThread("vt-suggest", Process.THREAD_PRIORITY_DEFAULT).also { it.start() }
        workerThread = t
        Handler(t.looper).also { worker = it }
    }

    private fun logMemory() {
        val rt = Runtime.getRuntime()
        val heap = (rt.totalMemory() - rt.freeMemory()) / 1_048_576.0
        val pss = android.os.Debug.getPss() / 1024.0
        Log.d(TAG, String.format("mem: heap %.1f MB, pss %.1f MB", heap, pss))
    }

    companion object {
        private const val TAG = "VTKB"
        const val SUGGEST_DELAY_MS = 30L
    }
}
