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
import android.text.InputType
import android.util.Log
import android.view.KeyEvent
import android.view.View
import android.view.accessibility.AccessibilityManager
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import androidx.core.view.WindowInsetsControllerCompat
import com.viettelex.android.BuildConfig
import com.viettelex.android.shared.DebugLog
import com.viettelex.android.shared.DiskStamp
import com.viettelex.android.shared.PrefSync
import com.viettelex.android.shared.VTPrefs
import com.viettelex.keyboard.ThemeSettings
import com.viettelex.keyboard.AutoCorrect
import com.viettelex.keyboard.KeyAlternates
import com.viettelex.keyboard.Cancellable
import com.viettelex.keyboard.EmojiData
import com.viettelex.keyboard.ClipboardHistory
import com.viettelex.keyboard.ClipboardTTL
import com.viettelex.keyboard.EmojiRecents
import com.viettelex.keyboard.FieldTraits
import com.viettelex.keyboard.FutoSwipe
import com.viettelex.keyboard.Key
import com.viettelex.keyboard.KeyCommand
import com.viettelex.keyboard.KeyboardData
import com.viettelex.keyboard.KeyboardSession
import com.viettelex.keyboard.KeyboardSettings
import com.viettelex.keyboard.Keys
import com.viettelex.keyboard.MainThread
import com.viettelex.keyboard.SuggestionCase
import com.viettelex.keyboard.SuggestionPlan
import com.viettelex.keyboard.SwipeDecoder
import com.viettelex.keyboard.SwipeEnglish
import com.viettelex.keyboard.SwipeLayout
import com.viettelex.keyboard.SwipePath
import com.viettelex.keyboard.SwipeSuggest
import com.viettelex.keyboard.SyllableLM
import com.viettelex.keyboard.WriteMode
import com.viettelex.keyboard.TemplateItem
import com.viettelex.keyboard.PlusFeature
import com.viettelex.keyboard.PlusGate
import com.viettelex.keyboard.TextTool
import com.viettelex.keyboard.TextToolRunner
import com.viettelex.keyboard.TextTools
import com.viettelex.keyboard.TranslateController
import com.viettelex.keyboard.TranslateJob
import com.viettelex.keyboard.TranslateResult
import com.viettelex.keyboard.TranslateRunner
import com.viettelex.keyboard.TelexKeyPrior
import com.viettelex.keyboard.Templates
import com.viettelex.keyboard.TouchLog
import com.viettelex.keyboard.UserLangModel
import java.io.File
import java.util.BitSet
import java.net.HttpURLConnection
import java.net.URL
import com.viettelex.keyboard.tr
import com.viettelex.keyboard.L10n

/**
 * Bàn phím VietTelex (port iOS KeyboardViewController — phần nối dây; logic nằm ở
 * [KeyboardSession] của module :keyboard). Không Compose, không thư viện ngoài.
 *
 * Luồng: phím (touch-down) → session.handle trong MỘT batch edit → auto-shift ngay
 * lượt main kế → gợi ý sau 30 ms (phím mới huỷ lượt cũ) → phần nặng (VNSuggest +
 * AdjacentKeyFixer) trên HandlerThread "vt-suggest" → kết quả áp nếu còn hiện hành.
 * Không Handler nào được đặt khi không gõ.
 */
class VietTelexIME : InputMethodService(), KeyboardView.Listener, StripView.Listener, ClipboardPane.Listener {

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
    private var portCache: AndroidEditorPort? = null
    private val proxy by lazy { IcProxy({ port() }, tracker) }
    private val swipe by lazy { SwipeDeleteController(proxy) }
    /** Đoạn vừa vuốt ⌫ xoá — ô "Khôi phục" một lượt; phím khác bất kỳ gỡ. */
    private var swipeUndo: String? = null
    /** Công cụ văn bản vừa áp ⇒ ô "↩︎ Hoàn tác" / ⌫ ngay sau (một lượt). */
    private var toolUndo: TextTools.Undo? = null
    /** Dịch trên máy (Plus): controller rẻ; client ML Kit chỉ tạo khi chạm "Dịch", đóng 30 s sau lượt cuối (MlKitBackend). */
    private val translate by lazy { TranslateController(com.viettelex.android.translate.TranslateFeature.engineFactory(this)) }
    private var translateUsed = false
    private val clearStatusRun = Runnable { strip?.showStatus(null) }

    /** Wrapper cache theo InputConnection hiện hành (không cấp phát mỗi phím). */
    private fun port(): EditorPort? {
        val ic = currentInputConnection ?: return null
        portCache?.let { if (it.ic === ic) return it }
        return AndroidEditorPort(ic).also { portCache = it }
    }
    private val feedback by lazy { Feedback(this) }
    private val voice by lazy { VoiceInput(this) }
    private var voiceChecked = false

    private var worker: Handler? = null
    private var workerThread: HandlerThread? = null

    private var root: ImeRootView? = null
    private var keyboard: KeyboardView? = null
    private var strip: StripView? = null
    private var theme: ImeTheme? = null

    private var field = FieldMapping.map(0, 0)
    private var pendingGen = 0

    private val autoShiftRun = Runnable { if (pendingGen == session.generation) applyAutoShift() }
    private val suggestRun = Runnable { if (pendingGen == session.generation) refreshBar() }
    /**
     * Shift đổi ⇒ vẽ lại bar như Gboard. Trễ bằng [SUGGEST_DELAY_MS] để lượt gợi ý của chính
     * phím vừa gõ (dấu cách ⇒ auto-shift) chạy trước — session thấy bar đã đúng thì bỏ qua.
     */
    private val shiftRun = Runnable {
        syncShift()
        if (session.shiftNeedsRefresh()) refreshBar()
    }

    // --- gõ vuốt ---
    /**
     * Lõi giải mã (KHÔNG thread-safe): mọi truy cập nằm trong synchronized(swipeLock) —
     * prepare() chạy trên worker, setLayout/decode trên main. null khi tính năng tắt (0 RAM).
     */
    private var swipeDecoder: SwipeDecoder? = null
    private val swipeLock = Any()
    private var swipeSetting = false
    /**
     * FUTO Swipe (thử nghiệm, mặc định tắt): null = tắt ⇒ không tải model. Decode/setLayout dưới
     * swipeLock; TẢI weights thì KHÔNG (FutoSwipe tự khoá riêng) ⇒ vuốt lúc đang tải không chặn
     * main — decode thấy model chưa sẵn ⇒ SHARK2.
     */
    @Volatile private var futo: FutoSwipe? = null
    private var futoSetting = false
    private var swipeFieldOk = false
    private var accessibility: AccessibilityManager? = null
    private val touchExplorationListener = AccessibilityManager.TouchExplorationStateChangeListener { updateSwipeTyping() }

    /**
     * Cache setting (prefs.all + parse gõ tắt ≈ vài trăm µs–ms) — trước đây đọc lại 2–3 lần mỗi
     * lần focus ô (onStartInput + onStartInputView + theme). App cài đặt chạy process ":settings"
     * riêng: thay đổi của nó tới qua [PrefSync] (broadcast ⇒ [onPrefChanged]) và lưới an toàn
     * [syncPrefsFromDisk] mỗi lần hiện; thay đổi của chính IME qua [prefListener].
     */
    private var settingsCache: KeyboardSettings? = null
    private fun settings(): KeyboardSettings = settingsCache ?: VTPrefs.settings(prefs).also { settingsCache = it }
    /** Mẫu câu đã nạp (asset YAML / pref JSON) — nạp lười lần đầu cần, xoá khi pref đổi. */
    private var templatesCache: List<TemplateItem>? = null
    /** Pref đổi từ lần so theme trước ⇒ phải dựng lại ImeTheme để so chữ ký. */
    private var themeStale = true
    private var themeUiMode = -1
    /** Ngôn ngữ giao diện lúc dựng input view hiện tại ([L10n]). */
    private var viewLang = L10n.DEFAULT

    private val prefListener = SharedPreferences.OnSharedPreferenceChangeListener { _, key -> onPrefChanged(key) }
    /** Broadcast của process cài đặt ([PrefSync.listen]) — null khi chưa đăng ký. */
    private var prefReceiver: android.content.BroadcastReceiver? = null
    /** Mốc file prefs — đổi mà lỡ broadcast ⇒ đọc lại + bỏ cache lúc hiện bàn phím. */
    private val prefStamp by lazy { val f = PrefSync.file(this); DiskStamp { f.lastModified() to f.length() } }
    /** Mốc "Xóa từ đã học"/sửa từ điển (USERLM_RESET_AT) đã áp cho model trong RAM. */
    private var userLmResetSeen = 0L

    /** Một key prefs đổi (process này hoặc process cài đặt): bỏ cache + áp ngay phần cần áp. */
    private fun onPrefChanged(key: String?) {
        settingsCache = null
        themeStale = true
        if (key == Keys.USER_TEMPLATES || key == Keys.TEMPLATES_ENABLED) templatesCache = null
        // App vừa "Xóa từ đã học": bỏ model trong RAM NGAY (không bao giờ ghi đè lại).
        if (key == Keys.USERLM_RESET_AT) checkUserLmReset()
        // Bật/tắt gõ vuốt trong app khi bàn phím đang mở (ô Thử gõ).
        else if (key == Keys.SWIPE_TYPING) { swipeSetting = settings().swipeTyping; updateSwipeTyping() }
        else if (key == Keys.SWIPE_ENGLISH) session.swipeEnglish = settings().swipeEnglish
        else if (key == Keys.AUTO_CAPITALIZE) session.autoCapitalize = settings().autoCapitalize
        else if (key == Keys.SWIPE_FUTO) { futoSetting = settings().swipeFuto; updateSwipeTyping() }
        else if (key == Keys.SMART_TOUCH) { smartTouchSetting = settings().smartTouch; warmSmartTouch() }
        else if (key == Keys.HARDWARE_TELEX) hwSetting = settings().hardwareTelex
        else if (key == Keys.LONG_PRESS_NUMBERS || key == Keys.LONG_PRESS_SYMBOLS || key == Keys.HOLD_SHIFT_SYMBOLS) updateAlternates()
        // Bật/tắt kiểu gõ trong app khi bàn phím đang mở (ô Thử gõ) → áp ngay, không đợi mở lại.
        else if (key in Keys.ENGINE_KEYS) session.bridge.applySettings(settings())
        // Tắt lịch sử clipboard trong app: bỏ bản RAM (app đã xoá file). Đổi "Giữ lịch sử" ⇒
        // hạn mới cho bản RAM (áp ở lần prune kế tiếp).
        else if (key == Keys.CLIPBOARD_HISTORY || key == Keys.CLIPBOARD_TTL)
            settings().let { syncClipHistory(it.clipboardHistory, it.clipboardTtl) }
        // Bật/tắt thả nổi trong app khi bàn phím đang mở (ô Thử gõ) → áp ngay.
        else if (key == Keys.FLOATING_KEYBOARD && inputShown) applyFloating(settings().floatingKeyboard)
        // Bật/tắt bàn phím tách đôi trong app khi bàn phím đang mở → áp ngay.
        else if (key == Keys.SPLIT_KEYBOARD && inputShown) keyboard?.setSplit(settings().splitKeyboard)
    }

    /**
     * Ghi prefs cài đặt từ IME (thả nổi, một tay, thu gọn bar): đọc lại file trước (process cài
     * đặt có thể vừa ghi) — SharedPreferences ghi CẢ map, map cũ sẽ đè thay đổi của app.
     */
    private fun editPrefs(): SharedPreferences.Editor = PrefSync.reload(this).edit()

    /** Mốc sửa từ điển đổi ⇒ nạp lại model từ file (app đã ghi/xoá); trùng mốc ⇒ không làm gì. */
    private fun checkUserLmReset() {
        val at = prefs.getLong(Keys.USERLM_RESET_AT, 0L)
        if (at == userLmResetSeen) return
        userLmResetSeen = at
        model.reloadAfterExternalErase()
    }

    /**
     * Lưới an toàn đa process: file prefs đổi từ lần hiện trước (process cài đặt ghi lúc IME
     * không nhận được broadcast) ⇒ đọc lại từ đĩa, bỏ mọi cache cài đặt/theme/mẫu câu. 2 stat.
     */
    private fun syncPrefsFromDisk() {
        if (!prefStamp.changed()) return
        PrefSync.reload(this)
        settingsCache = null
        themeStale = true
        templatesCache = null
        checkUserLmReset()
    }

    override fun onCreate() {
        val t0 = SystemClock.elapsedRealtime()
        super.onCreate()
        prefs = VTPrefs.of(this)
        com.viettelex.android.plus.PlusPrefs.install(this)   // PlusGate đọc cờ Plus từ prefs chung
        KeyboardData.install(AssetBlobs.provider(assets))
        // Emoji mới hơn mức API chắc có → hỏi font hệ thống (ẩn emoji máy không vẽ được).
        EmojiData.trusted = EmojiData.trustedVersion(Build.VERSION.SDK_INT)
        val glyphPaint = android.graphics.Paint()
        EmojiData.glyphCheck = { e -> synchronized(glyphPaint) { glyphPaint.hasGlyph(e) } }
        DebugLog.configure(this, prefs.getBoolean(Keys.DEBUG_TOUCH_LOG, false))
        model = UserLangModel(File(filesDir, Keys.USERLM_FILE), mainThread)
        clipboard = AndroidClipboard(this)
        session = KeyboardSession(model, clipboard)
        // Tự sửa: từ từng hoàn tác (không sửa lại) — trạng thái bàn phím, không sao lưu.
        session.autoCorrectRejected = AutoCorrect.Rejected.decode(stateStore().getString(Keys.AUTO_CORRECT_REJECTED, null))
        session.onAutoCorrectRejected = {
            stateStore().edit().putString(Keys.AUTO_CORRECT_REJECTED, session.autoCorrectRejected.encode()).apply()
        }
        syncClipHistory(prefs.getBoolean(Keys.CLIPBOARD_HISTORY, false), ClipboardTTL.of(prefs.getString(Keys.CLIPBOARD_TTL, null)))
        clipboard.onChanged = { onClipChanged() }
        // Mời dán một lần mỗi mục clipboard: chỉ lưu id (timestamp ClipDescription), không nội dung.
        session.pasteOnce.reload(stateStore().getLong(Keys.PASTE_OFFERED_ID, Long.MIN_VALUE).takeIf { it != Long.MIN_VALUE })
        session.pasteOnce.persist = { stateStore().edit().putLong(Keys.PASTE_OFFERED_ID, it).apply() }
        model.onReady = { refreshBar() }
        prefs.registerOnSharedPreferenceChangeListener(prefListener)
        userLmResetSeen = prefs.getLong(Keys.USERLM_RESET_AT, 0L)
        prefStamp.changed()                                  // ghi nhận mốc ban đầu
        PrefSync.forward(this)                               // thay đổi của IME (thả nổi, một tay…) ⇒ app
        prefReceiver = PrefSync.listen(this) { keys -> keys.forEach { onPrefChanged(it) } }
        accessibility = (getSystemService(Context.ACCESSIBILITY_SERVICE) as? AccessibilityManager)?.also {
            it.addTouchExplorationStateChangeListener(touchExplorationListener)
        }
        if (BuildConfig.DEBUG) Log.d(TAG, "perf onCreate ${SystemClock.elapsedRealtime() - t0} ms")
    }

    override fun onDestroy() {
        cancelTranslate()                              // đóng client ML Kit nếu đang dịch
        prefs.unregisterOnSharedPreferenceChangeListener(prefListener)
        prefReceiver?.let { PrefSync.unlisten(this, it) }; prefReceiver = null
        accessibility?.removeTouchExplorationStateChangeListener(touchExplorationListener)
        accessibility = null
        clipboard.release()
        clipboard.onChanged = null
        feedback.releaseSound()
        handler.removeCallbacksAndMessages(null)   // gợi ý / auto-shift / hẹn giờ ẩn còn chờ
        workerThread?.quitSafely()
        session.finishInput()
        // Vỏ service cũ có thể bị framework giữ lâu sau khi đổi IME (pool RecordingCanvas giữ nav
        // bar của IME → context = service này): thả mọi thứ nặng nó đang trỏ tới (RAM-AUDIT #2).
        model.onReady = null
        model.close()                                 // ghi nốt thay đổi chờ, bỏ bảng RAM
        session.clipHistory = null                    // chỉ bản RAM (file giữ nguyên)
        // (dữ liệu cấp process — từ điển Anh, trie, emoji — để service mới dùng tiếp)
        root?.dropWallpaper()
        clipPane?.listener = null
        keyboard?.listener = null; keyboard?.letterPrior = null
        strip?.listener = null
        // Service (mInputView) + khung mInputFrame vẫn giữ cây view ⇒ thay bằng view rỗng, rồi đo lại
        // khung (FrameLayout giữ con cũ trong mMatchParentChildren tới lần onMeasure kế) để cả cây GC được.
        root?.let { r ->
            val frame = r.parent as? View
            runCatching {
                setInputView(View(this))
                val any = View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED)
                frame?.measure(any, any)
            }
        }
        root = null; keyboard = null; strip = null; clipPane = null; theme = null
        portCache = null
        synchronized(swipeLock) { swipeDecoder = null; futo = null }
        super.onDestroy()
    }

    /** iOS không có extract mode — luôn hiện bàn phím thường, kể cả ngang. */
    override fun onEvaluateFullscreenMode() = false

    override fun onCreateInputView(): View {
        val t0 = SystemClock.elapsedRealtime()
        val th = freshTheme()
        theme = th
        val balloon = BalloonView(this, th)
        val trail = SwipeTrailView(this, th)
        val kb = KeyboardView(this, th, balloon, feedback, trail)
        val st = StripView(this, th, feedback)
        kb.listener = this
        kb.letterPrior = ::smartTouchPrior
        st.listener = this
        st.onPasteOffer = { session.pasteOfferVisible(it) }
        val r = ImeRootView(this, th, kb, st, balloon, trail)
        keyboard = kb; strip = st; root = r
        viewLang = L10n.lang
        kb.setSwitcherHint(switcherHintVisible)
        styleWindow(th, r)
        if (BuildConfig.DEBUG) Log.d(TAG, "perf onCreateInputView ${SystemClock.elapsedRealtime() - t0} ms")
        return r
    }

    /**
     * "Hiệu ứng khi bấm phím" (Plus): kiểu + cổng Plus + Trình tiết kiệm pin + hiệu ứng động hệ thống —
     * đọc MỘT lần mỗi lần hiện. Không ⇒ gỡ overlay (không còn view nào, 0 chi phí mỗi phím).
     */
    private fun applyKeyEffect(setting: com.viettelex.keyboard.KeyEffect, th: ImeTheme, kb: KeyboardView) {
        val r = root ?: return
        val fx = if (setting == com.viettelex.keyboard.KeyEffect.NONE) setting else com.viettelex.keyboard.KeyEffectPolicy.active(
            setting, com.viettelex.keyboard.KeyEffectGate.allows(setting),
            powerSave = (getSystemService(POWER_SERVICE) as? android.os.PowerManager)?.isPowerSaveMode == true)
        session.trackBoundaryWord = fx == com.viettelex.keyboard.KeyEffect.EMOJIWORD || root?.buddy != null
        if (fx == com.viettelex.keyboard.KeyEffect.NONE) {
            r.effects?.halt()
            r.effects = null; kb.effects = null
            return
        }
        val v = r.effects ?: KeyEffectView(this, th.density)
        v.configure(fx, th.action, th.keyFill, th.dark)
        r.effects = v          // dải dưới / trên phím theo kiểu vừa cấu hình
        kb.effects = v
        r.refreshStringGaps()  // Rung dây: khe hàng cho overlay (đã layout thì đặt ngay)
    }

    /**
     * "Hiệu ứng nét vuốt": kiểu + cổng Plus + Trình tiết kiệm pin; "Theo giao diện" ⇒ "swipe" của theme đang dùng —
     * đọc MỘT lần mỗi lần hiện. Tắt ⇒ KeyboardView không giữ vệt (không add/vẽ gì), view ẩn.
     */
    private fun applySwipeTrail(setting: com.viettelex.keyboard.SwipeTrailStyle, th: ImeTheme, kb: KeyboardView) {
        val r = root ?: return
        val style = if (!setting.isPlus) setting else com.viettelex.keyboard.SwipeTrailPolicy.active(
            setting, com.viettelex.keyboard.SwipeTrailGate.allows(setting),
            themeSwipe = if (setting == com.viettelex.keyboard.SwipeTrailStyle.THEME) th.settings.effectiveKeyStyle.swipe else null,
            powerSave = (getSystemService(POWER_SERVICE) as? android.os.PowerManager)?.isPowerSaveMode == true)
        if (style == com.viettelex.keyboard.SwipeTrailStyle.NONE) {
            r.trail.clear()
            r.trail.visibility = View.GONE
            kb.trail = null
            return
        }
        r.trail.configure(style)
        r.trail.visibility = View.VISIBLE
        kb.trail = r.trail
    }

    /**
     * "Bạn đồng hành" (Plus): nhân vật + cổng Plus + Trình tiết kiệm pin + mùa lễ (theme lễ / ngày) — đọc MỘT lần
     * mỗi lần hiện. Tắt ⇒ gỡ view, strip không chừa ô (0 chi phí mỗi phím).
     */
    private fun applyBuddy(setting: com.viettelex.keyboard.BuddyCharacter, style: com.viettelex.keyboard.BuddyStyle,
                           placement: com.viettelex.keyboard.BuddyPlacement, th: ImeTheme, st: StripView) {
        val r = root ?: return
        val c = com.viettelex.keyboard.BuddyPolicy.active(setting, com.viettelex.keyboard.BuddyGate.allows(setting))
        if (c == com.viettelex.keyboard.BuddyCharacter.OFF) {
            r.buddy = null; st.buddyDp = 0f
            session.trackBoundaryWord = r.effects?.effect == com.viettelex.keyboard.KeyEffect.EMOJIWORD
            return
        }
        val low = (getSystemService(POWER_SERVICE) as? android.os.PowerManager)?.isPowerSaveMode == true
        val cal = java.util.Calendar.getInstance()
        val season = com.viettelex.keyboard.BuddySeason.resolve(th.settings.effectiveTheme.id,
            cal.get(java.util.Calendar.YEAR), cal.get(java.util.Calendar.MONTH) + 1, cal.get(java.util.Calendar.DAY_OF_MONTH))
        val old = r.buddy
        // Kiểu vẽ riêng nhân vật (Hoạt hình mặc định / Vẽ nét) — đổi ⇒ dựng view mới, chỉ nạp tài nguyên kiểu đó.
        if (old != null && old.character == c && old.season == season && old.artStyle == style) {
            old.lowPower = low; old.setBar(com.viettelex.keyboard.BuddyHalo.opaque(th.bg, th.dark))
        } else {
            r.buddy = BuddyView(this, c, th.density, com.viettelex.keyboard.BuddyHalo.opaque(th.bg, th.dark), low, season,
                artStyle = style)
        }
        r.buddyPlacement = placement
        st.buddyDp = placement.zoneWidth(StripGeometry.BUDDY_W.toDouble()).toFloat()
        session.trackBoundaryWord = true
    }

    /** Bạn đồng hành: phản ứng theo từ vừa chốt (tra O(1), chỉ ở ranh giới). */
    private fun buddyBoundary() {
        val b = root?.buddy ?: return
        val w = session.boundaryWord ?: return
        b.wordCommitted(w, session.boundaryPrev, session.boundaryPrev2)
    }

    /**
     * Đập chuột (theme có "game":"mole" — [com.viettelex.keyboard.MoleGame]): theme + Plus + không tiết kiệm pin + không
     * TalkBack — đọc MỘT lần mỗi lần hiện. Không ⇒ gỡ view (0 chi phí mỗi phím), không nạp mẫu "éc".
     */
    private fun applyMole(th: ImeTheme, kb: KeyboardView) {
        val r = root ?: return
        val on = com.viettelex.keyboard.MolePolicy.active(th.keyStyle.game,
            PlusGate.isUnlocked(PlusFeature.PREMIUM_THEMES),
            powerSave = (getSystemService(POWER_SERVICE) as? android.os.PowerManager)?.isPowerSaveMode == true,
            talkBack = accessibility?.isTouchExplorationEnabled == true)
        feedback.setSqueakEnabled(on)
        if (!on) { r.mole = null; kb.mole = null; return }
        val v = r.mole ?: MoleView(this, th.density)
        v.keyFrame = { c, out -> kb.moleKeyFrame(c, out, v) }
        v.context = {
            val set = strip?.shownSet
            session.bridge.composedWord to (listOfNotNull(set?.word, set?.word2) + (set?.nextWords ?: emptyList()))
        }
        if (r.mole == null) moleStats = MoleStatsFile.read(this)
        v.onHit = { streak ->
            feedback.squeak()
            val st = moleStats.record(1, streak, com.viettelex.keyboard.MoleStats.dayNumber())
            moleStats = st
            worker().post { MoleStatsFile.write(this, st) }
            st.today
        }
        r.mole = v
        kb.mole = v
    }

    /** Thống kê Đập chuột trong RAM (đọc file lúc gắn view, ghi file trên worker mỗi lần đập). */
    private var moleStats = com.viettelex.keyboard.MoleStats()

    /** "Emoji theo chữ": phím ranh giới vừa chốt từ ⇒ tra bảng O(1) (chỉ khi chọn kiểu này). */
    private fun fxBoundaryEmoji() {
        buddyBoundary()
        val fx = root?.effects ?: return
        if (fx.effect != com.viettelex.keyboard.KeyEffect.EMOJIWORD) return
        val w = session.boundaryWord ?: return
        com.viettelex.keyboard.EmojiWords.lookup(w, session.boundaryPrev)?.let { fx.queueEmoji(it) }
    }

    /** Theme từ cài đặt hiện tại (rẻ: vài lần đọc màu resource, không giải ảnh). */
    private fun freshTheme(): ImeTheme {
        val all = prefs.all
        return ImeTheme(this, ThemeSettings.load { all[it] }, File(filesDir, Keys.WALLPAPER_FILE).exists())
    }

    @Suppress("DEPRECATION")
    private fun styleWindow(th: ImeTheme, v: View) {
        val w = window?.window ?: return
        // Thả nổi: dải nav bar trong suốt (app bên dưới lộ ra, khung không dính đáy).
        if (Build.VERSION.SDK_INT < 35) w.navigationBarColor = if (floatingNow) android.graphics.Color.TRANSPARENT else th.bg
        if (Build.VERSION.SDK_INT >= 29) w.isNavigationBarContrastEnforced = false
        WindowInsetsControllerCompat(w, v).isAppearanceLightNavigationBars = !th.dark
    }

    override fun onStartInputView(info: EditorInfo, restarting: Boolean) {
        val t0 = SystemClock.elapsedRealtime()
        super.onStartInputView(info, restarting)
        handler.removeCallbacks(idleRelease)
        syncPrefsFromDisk()
        // Đổi theme/ảnh nền trong app → dựng lại input view (màu/Paint tạo sẵn trong view).
        // Chỉ dựng ImeTheme để so khi pref đổi hoặc sáng/tối hệ thống đổi (không mỗi lần focus ô).
        val uiMode = resources.configuration.uiMode
        // Ngôn ngữ giao diện (Tính Năng → Ngôn ngữ): đọc MỘT lần mỗi lần hiện bàn phím; view đang
        // giữ chữ dựng sẵn (Dán, Khôi phục, …) ⇒ đổi ngôn ngữ thì dựng lại view. 0 chi phí mỗi phím.
        L10n.load { prefs.getString(it, null) }
        if (theme != null && (viewLang != L10n.lang ||
                ((themeStale || uiMode != themeUiMode) && freshTheme().signature != theme?.signature)))
            setInputView(onCreateInputView())
        themeStale = false; themeUiMode = uiMode
        rewarmAfterIdle()
        val kb = keyboard ?: return
        val st = strip ?: return
        val th = theme ?: return
        val settings = settings()
        DebugLog.configure(this, settings.debugTouchLog)
        // Đã gõ phím cứng trên ô này (onStartInput đã dựng ô, tracker/engine đang sống):
        // KHÔNG dựng lại từ EditorInfo cũ (initialSel đã lỗi thời) — chỉ lo phần giao diện.
        if (!hwTyped) configureField(info, settings)
        kb.holdNewline = field.holdNewline   // giữ lâu Enter = xuống dòng (ô nhiều dòng)
        feedback.hapticsEnabled = settings.hapticFeedback
        feedback.hapticStrength = settings.hapticStrength
        // Âm thanh phím riêng: TẮT ⇒ nhả/không dựng gì (tiếng hệ thống như cũ).
        feedback.configureSound(settings.keySound, settings.keySoundVolume, settings.keySoundStyle) { worker().post(it) }
        kb.searchSettings = settings
        syncClipHistory(settings.clipboardHistory, settings.clipboardTtl)
        // Copy lúc process IME chưa sống (listener không thấy) → bù khi hiện, không làm mới mục cũ.
        if (session.recordClip(field.isSecure, onlyIfNew = true)) saveClipHistory()
        closeClipboardPane()
        swipeSetting = settings.swipeTyping
        futoSetting = settings.swipeFuto
        // Chỉ ô chữ ghi COMMIT thường: không secure/passthrough (URI, email, mật khẩu hiện,
        // filter), không TYPE_NULL, không ô URL, không app phải ghi bằng key event.
        swipeFieldOk = !field.isSecure && !field.passthrough && !field.rawKeys && !proxy.uriField &&
            proxy.writeMode == WriteMode.COMMIT
        // Chọn phím theo ngữ cảnh: chỉ ô chữ thường (email/URL/mật khẩu gõ literal ⇒ router cũ).
        smartTouchSetting = settings.smartTouch
        smartTouchFieldOk = !field.isSecure && !field.passthrough && !proxy.uriField
        warmSmartTouch()

        inputShown = true
        // Nút ⌄ thu gọn đã bỏ (10/2026): bar luôn mở; khoá "suggestionBarCollapsed" cũ không còn đọc.
        session.barCollapsed = false
        // Ô cấm gợi ý chữ nhưng không nhạy cảm (StripMode.TOOLS): vẫn ☰/con trỏ/📋 + Dán (#113).
        val barOn = session.stripMode.shown
        // "Nút emoji" = Thanh trên: chỉ khi strip CÓ vẽ (barOn) — không thì 😊 ở lại hàng đáy.
        // TalkBack: strip không đọc được (importantForAccessibility NO) ⇒ giữ phím 😊 cho người dùng trợ năng.
        val emojiInStrip = com.viettelex.keyboard.EmojiKeyPlacement.inStrip(settings.emojiKeyPlacement,
            barOn && accessibility?.isTouchExplorationEnabled != true)
        st.configure(barOn, settings.templatesEnabled,
            reserved = KeyLayout.stripReserved(settings.showSuggestions), emojiButton = emojiInStrip,
            slotSetting = settings.suggestionCount,
            // "Chiều cao thanh gợi ý" — điện thoại ngang kẹp ở Vừa (màn thấp).
            barHeight = settings.suggestionBarHeight, landscapeCap = th.landscape && !th.tablet)
        applyFloating(settings.floatingKeyboard, settings)
        kb.setEditHasSelection(info.initialSelStart >= 0 && info.initialSelStart != info.initialSelEnd)
        st.setExtras(clipButton = settings.clipboardHistory, open = false)
        val templates = if (settings.templatesEnabled)
            templatesCache ?: VTPrefs.templates(this, prefs).also { templatesCache = it } else emptyList()
        kb.configure(field.returnLabel, field.kind, needsGlobe(), settings.showSpaceLogo,
            settings.templatesEnabled, templates,
            th.dp(KeyLayout.keyAreaDp(th.tablet, th.landscape, settings.rowHeightAdjust, settings.numberRow,
                settings.numberRowFullHeight, resources.configuration.screenHeightDp.toFloat())),
            field.numberSigned, field.numberDecimal, settings.numberRow, settings.numberRowFullHeight,
            settings.spaceSideKey, emojiInStrip, settings.keyLabelSize, settings.splitKeyboard)
        kb.keyPreview = settings.keyPreview
        kb.keyPressHighlight = settings.keyPressHighlight
        applyKeyEffect(settings.keyEffect, th, kb)
        applyBuddy(settings.buddy, settings.buddyStyle, settings.buddyPlacement, th, st)
        applySwipeTrail(settings.swipeTrail, th, kb)
        applyMole(th, kb)
        kb.configureSpaceFlick(settings.spaceSwipeLanguage, session.language)
        if (session.language == com.viettelex.keyboard.KeyboardLanguage.EN) warmEnglish()
        // Plus + công tắc "Công cụ văn bản" (mặc định bật) + không phải ô mật khẩu.
        kb.textToolsEnabled = settings.textToolsActive(PlusGate.isUnlocked(PlusFeature.TEXT_TOOLS), field.isSecure)
        // Dịch nằm trong Công cụ ⇒ tắt Công cụ là tắt luôn Dịch.
        // APK ngoài Play (không tải được module :translate) ⇒ ẩn hẳn Dịch.
        kb.translateEnabled = kb.textToolsEnabled && PlusGate.isUnlocked(PlusFeature.TRANSLATE) &&
            com.viettelex.android.translate.TranslateFeature.offered(this)
        st.toolsEnabled = kb.textToolsEnabled || kb.translateEnabled   // ☰ khi Mẫu câu tắt
        st.setPlane(kb.plane)
        // Giữ lâu "," = gõ giọng nói: chỉ khi máy có IME giọng nói (đọc lại khi vào ô mới —
        // user có thể bật/tắt trong Cài đặt), không ở ô mật khẩu.
        if (!restarting || !voiceChecked) { voice.refresh(); voiceChecked = true }
        kb.setVoiceAvailable(voice.available && !field.isSecure)
        updateSwipeTyping()
        root?.refreshInsets()
        root?.requestLayout()

        session.invalidatePasteCache()
        if (!restarting) session.pasteOnce.ended()   // ô mới: lời mời dán đang hiện coi như bỏ qua
        applyAutoShift()
        refreshBar()                  // ô trống → gợi mở đầu ngay khi hiện
        if (BuildConfig.DEBUG) Log.d(TAG, "perf onStartInputView ${SystemClock.elapsedRealtime() - t0} ms")
    }

    /** Ô nhập → FieldMapping, IcProxy, tracker, session. Gọi ở onStartInputView (và onStartInput khi có phím cứng). */
    private fun configureField(info: EditorInfo, settings: KeyboardSettings) {
        field = FieldMapping.map(info.inputType, info.imeOptions, info.packageName,
            hasActionLabel = info.actionLabel != null, customActionId = info.actionId)
        proxy.secure = field.isSecure
        proxy.rawKeys = field.rawKeys
        proxy.multiLine = field.multiLine
        proxy.writeMode = com.viettelex.keyboard.WriteMode.forPackage(info.packageName)
        proxy.actionId = field.actionId
        proxy.uriField = (info.inputType and InputType.TYPE_MASK_CLASS) == InputType.TYPE_CLASS_TEXT &&
            (info.inputType and InputType.TYPE_MASK_VARIATION) == InputType.TYPE_TEXT_VARIATION_URI
        startTracking(info)
        handler.removeCallbacks(autoShiftRun); handler.removeCallbacks(suggestRun); handler.removeCallbacks(shiftRun)
        clearSwipeUndo()

        session.startInput(settings, FieldTraits(
            isSecure = field.isSecure, passthrough = field.passthrough,
            capSentences = field.capSentences, suggestionsAllowed = field.suggestionsAllowed,
            capWords = field.capWords, capCharacters = field.capCharacters,
            initialCaps = info.initialCapsMode != 0, noLearning = field.noLearning,
            packageName = info.packageName, urlField = proxy.uriField,
            emailField = field.kind == InputKind.EMAIL, stripTools = field.stripTools,
            lowercaseSuggestions = field.lowercaseSuggestions, appNoSuggestions = field.appNoSuggestions,
            emailCompose = field.emailCompose))
        // Bảng gõ tắt đổi ⇒ từ vựng vuốt mới: dựng lại template ở nền (cú vuốt kế khỏi chờ).
        if (session.takeSwipeVocabChanged()) swipeDecoder?.let { dec ->
            if (dec.layout != null) worker().post { synchronized(swipeLock) { if (swipeDecoder === dec) dec.prepare() } }
        }
        // Ngôn ngữ (vuốt phím cách) lưu riêng: ghi không đụng prefs cài đặt (listener/theme).
        session.restoreLanguage(stateStore().getString(Keys.KEYBOARD_LANGUAGE, null), proxy)
        hwSetting = settings.hardwareTelex
        fieldReady = true
    }

    /**
     * initialSel không tin tuyệt đối: đối chiếu độ dài getInitialTextBeforeCursor (API 30+);
     * lệch ⇒ con trỏ không biết. Khớp ⇒ nạp luôn shadow (khỏi IPC lượt đầu).
     */
    private fun startTracking(info: EditorInfo) {
        val before = if (Build.VERSION.SDK_INT >= 30 && !field.isSecure)
            info.getInitialTextBeforeCursor(IcProxy.CONTEXT_CAP, 0) else null
        val s = info.initialSelStart; val e = info.initialSelEnd
        val ok = InitialSelection.trusted(s, e, before?.length, IcProxy.CONTEXT_CAP)
        if (ok) tracker.reset(s, e) else tracker.reset(-1, -1)
        if (!ok && s >= 0 && TouchLog.enabled) TouchLog.write("initialSel $s..$e lệch initialTextBefore len=${before?.length}")
        proxy.startInput(if (ok) before else null,
            ok && before != null && InitialSelection.reachesFieldStart(s, e, before.length))
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
        cancelTranslate()
        swipeFieldOk = false
        // FUTO Swipe / từ điển Anh / ảnh nền / emoji: GIỮ qua các lần hiện (giải lại mỗi lần hiện
        // tốn ~4.7 MB cấp phát) — nhả khi ẩn lâu ([idleRelease]; onTrimMemory hầu như không tới).
        handler.removeCallbacks(idleRelease)
        handler.postDelayed(idleRelease, IDLE_RELEASE_MS)
        handler.removeCallbacks(autoShiftRun); handler.removeCallbacks(suggestRun); handler.removeCallbacks(shiftRun)
        trackpadMoved = false                  // ô đóng: không auto-shift/gợi ý lúc nhả trackpad
        keyboard?.onHidden()
        feedback.releaseSound()                // âm phím riêng: nhả SoundPool khi ẩn
        closeClipboardPane()
        inputShown = false
        session.pasteOnce.ended()              // ẩn bàn phím: lời mời dán đang hiện coi như bỏ qua
        clearSwipeUndo()
        strip?.onHidden()
        root?.balloon?.hide()
        root?.effects?.halt()                  // Matrix…: ẩn bàn phím ⇒ dừng hẳn, không còn khung hình
        root?.buddy?.halt()                    // Bạn đồng hành: không hẹn giờ khi ẩn
        root?.rainbow?.halt()                  // Gaming RGB: đứng yên ở cầu vồng tĩnh
        session.finishInput()
    }

    /**
     * Hệ thống thiếu RAM: như hẹn giờ ẩn ([releaseIdle]) nhưng ngay. API 34+ gần như không gửi
     * (IME đang chọn ở oom_adj 100) ⇒ đường chính là [idleRelease]. Trie chọn phím thông minh là
     * asset mmap (0 heap) ⇒ KHÔNG nhả (trước đây nhả 0.86 MB, lần hiện sau tốn 31 MB rác).
     */
    override fun onTrimMemory(level: Int) {
        super.onTrimMemory(level)
        // FUTO Swipe (thử nghiệm): nhả ~3.4 MB khi THIẾU RAM thật (tải lại lười ở lần vuốt/hiện sau).
        // KHÔNG nhả ở UI_HIDDEN (gửi mỗi lần bàn phím ẩn ⇒ giải lại weights mỗi lần hiện).
        if (ImeTrim.releaseFuto(level)) synchronized(swipeLock) { futo?.release() }
        if (!ImeTrim.releaseIdle(level, inputShown)) return
        releaseIdle()
        settingsCache = null
    }

    /** Hẹn giờ ẩn (RAM-AUDIT #6): bàn phím ẩn liền [IDLE_RELEASE_MS] ⇒ nhả dữ liệu nạp lại được. */
    private val idleRelease = Runnable { if (!inputShown) releaseIdle() }

    /** Đã nhả gì ở [releaseIdle] ⇒ lần hiện kế nạp lại NỀN ([rewarmAfterIdle]). */
    private var englishReleased = false
    private var wallpaperReleased = false

    /**
     * Nhả dữ liệu dựng lại được: model FUTO (~3.4 MB), từ điển Anh (~1.4 MB), template gõ vuốt,
     * ảnh nền (bitmap), String emoji, bảng clipboard (view), cache mẫu câu. Tất cả có đường dự
     * phòng khi chưa nạp lại xong (SHARK2, nền màu theme, …) — không chặn phím đầu.
     */
    private fun releaseIdle() {
        synchronized(swipeLock) { futo?.release(); swipeDecoder = null }
        if (SwipeEnglish.isLoaded) { SwipeEnglish.release(); englishReleased = true }
        if (root?.dropWallpaper() == true) wallpaperReleased = true
        WallpaperBitmap.drop()
        EmojiData.releaseCategories()
        keyboard?.releaseIdleCaches()
        clipPane?.let { if (it.visibility != View.VISIBLE) { it.listener = null; root?.overlay = null; clipPane = null } }
        templatesCache = null
    }

    /**
     * Hiện lại sau [releaseIdle]: nạp lại những gì đã nhả trên MỘT luồng nền ưu tiên thấp riêng
     * (không chen hàng đợi gợi ý của worker ⇒ phím/gợi ý đầu không chờ). Hiếm: ≤ 1 lần / 3 phút ẩn.
     */
    private fun rewarmAfterIdle() {
        val english = englishReleased; val wall = wallpaperReleased
        if (!english && !wall) return
        englishReleased = false; wallpaperReleased = false
        val jobs = ArrayList<Runnable>(2)
        if (english) jobs += Runnable { SwipeEnglish.lexicon }
        if (wall) root?.reloadWallpaper { jobs += it }
        if (jobs.isEmpty()) return
        Thread({ jobs.forEach { it.run() } }, "vt-rewarm").apply { priority = Thread.MIN_PRIORITY + 1 }.start()
    }

    override fun onComputeInsets(outInsets: InputMethodService.Insets) {
        super.onComputeInsets(outInsets)
        val r = root
        if (r != null && r.floating && !r.panel.isEmpty && r.isAttachedToWindow) {
            // Thả nổi (#112, như Gboard): app không co (content/visible top = đáy cửa sổ), chỉ khung
            // nhận chạm — ngoài khung chạm rơi xuống app.
            val decorH = window?.window?.decorView?.height ?: 0
            val top = FloatingKeyboard.contentTopInsets(decorH)
            outInsets.contentTopInsets = top
            outInsets.visibleTopInsets = top
            r.getLocationInWindow(insetsLoc)
            val p = r.panel
            val g = FloatingKeyboard.touchRegion(insetsLoc[0], insetsLoc[1], p.left, p.top, p.right, p.bottom)
            outInsets.touchableInsets = InputMethodService.Insets.TOUCHABLE_INSETS_REGION
            outInsets.touchableRegion.set(g[0], g[1], g[2], g[3])
            return
        }
        // Toàn khung input view nhận touch — chạm vào khe không rơi sang app (§5).
        outInsets.touchableInsets = InputMethodService.Insets.TOUCHABLE_INSETS_CONTENT
    }
    private val insetsLoc = IntArray(2)

    // MARK: thả nổi (#112)

    /** Thả nổi đang áp ở input view hiện tại. */
    private val floatingNow: Boolean get() = root?.floating == true

    /**
     * Áp chế độ thả nổi lên view hiện tại: vị trí theo chiều màn hình (prefs trạng thái), một tay
     * tắt (menu ✋ ẩn), "Nâng bàn phím" bỏ qua. Tắt ⇒ y như cũ (một tay + nâng theo cài đặt).
     */
    private fun applyFloating(on: Boolean, settings: KeyboardSettings = settings()) {
        val r = root ?: return
        val th = theme ?: return
        val kb = keyboard ?: return
        val st = strip ?: return
        if (on) {
            val (fx, fy) = FloatingKeyboard.load(th.landscape) { stateStore().getString(it, null) }
            r.onFloatMoved = { x, y -> FloatingKeyboard.save(th.landscape, x, y) { k, v -> stateStore().edit().putString(k, v).apply() } }
            r.onFloatExit = { setFloatingPref(false) }
            r.setFloating(true, fx, fy)
            r.raisePx = 0
        } else {
            r.setFloating(false)
            r.onFloatMoved = null; r.onFloatExit = null
            r.raisePx = ImeInsets.raisePx(settings.keyboardRaise, th.density)
        }
        kb.floatingOn = on
        st.oneHandAvailable = !th.tablet && !on
        kb.setOneHand(if (th.tablet || on) OneHandSide.OFF else OneHandSide.fromPref(settings.oneHandMode))
        styleWindow(th, r)
    }

    /** Ghi công tắc (app + sao lưu thấy) rồi áp ngay. */
    private fun setFloatingPref(on: Boolean) {
        editPrefs().putBoolean(Keys.FLOATING_KEYBOARD, on).apply()
        applyFloating(on)
    }

    override fun onToggleFloating() = setFloatingPref(!floatingNow)

    override fun onUpdateSelection(oldSelStart: Int, oldSelEnd: Int, newSelStart: Int, newSelEnd: Int,
                                   candidatesStart: Int, candidatesEnd: Int) {
        super.onUpdateSelection(oldSelStart, oldSelEnd, newSelStart, newSelEnd, candidatesStart, candidatesEnd)
        // Mình không dùng composing text: span còn (app/IME trước để sót) ⇒ chốt ở phím kế.
        if (candidatesStart != -1) proxy.finishComposingOnNextEdit()
        if (newSelStart < 0) proxy.invalidateShadow()   // "không biết": không reset engine, chỉ đọc lại chữ
        keyboard?.setEditHasSelection(newSelStart >= 0 && newSelStart != newSelEnd)
        if (!tracker.onUpdate(newSelStart, newSelEnd)) return
        // Đổi từ NGOÀI (chạm chỗ khác, select-all, app tự sửa): quên từ + ngữ cảnh.
        proxy.invalidateShadow()
        session.externalSelectionChange()
        clearSwipeUndo()
        applyAutoShift()
        refreshBar()
    }

    // MARK: bàn phím cứng

    /** Công tắc "Telex cho bàn phím cứng" (Keys.HARDWARE_TELEX). */
    private var hwSetting = true
    /** configureField đã chạy cho ô hiện tại. */
    private var fieldReady = false
    /** Đã tiêu thụ ít nhất một phím cứng trên ô hiện tại. */
    private var hwTyped = false
    /** keyCode đã nuốt ở ACTION_DOWN ⇒ nuốt luôn ACTION_UP (app không nhận up mồ côi). */
    private val hwConsumed = BitSet()

    /**
     * Có phím cứng thì bàn phím ảo thường KHÔNG hiện (onEvaluateInputViewShown mặc định) ⇒
     * onStartInputView không chạy: dựng ô ngay ở đây để tracker theo dõi từ đầu. Không có
     * phím cứng ⇒ để onStartInputView lo như cũ (không tốn gì thêm cho người chỉ gõ chạm).
     */
    override fun onStartInput(attribute: EditorInfo, restarting: Boolean) {
        super.onStartInput(attribute, restarting)
        fieldReady = false
        hwTyped = false
        hwConsumed.clear()
        syncPrefsFromDisk()
        val settings = settings()
        hwSetting = settings.hardwareTelex
        if (hwSetting && hardKeyboardPresent()) configureField(attribute, settings)
    }

    override fun onFinishInput() {
        if (hwTyped) session.finishInput()     // bàn phím ảo không hiện ⇒ onFinishInputView không lưu model
        fieldReady = false
        hwTyped = false
        hwConsumed.clear()
        super.onFinishInput()
    }

    private fun hardKeyboardPresent(): Boolean {
        val c = resources.configuration
        return c.keyboard != android.content.res.Configuration.KEYBOARD_NOKEYS &&
            c.hardKeyboardHidden != android.content.res.Configuration.HARDKEYBOARDHIDDEN_YES
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent): Boolean =
        onHardwareKeyDown(keyCode, event) || super.onKeyDown(keyCode, event)

    override fun onKeyUp(keyCode: Int, event: KeyEvent): Boolean {
        if (keyCode >= 0 && hwConsumed.get(keyCode)) { hwConsumed.clear(keyCode); return true }
        return super.onKeyUp(keyCode, event)
    }

    /**
     * Phím cứng → cùng đường với phím chạm ([onKey]: batch IcProxy, confirmTail, tracker,
     * WriteMode). Chữ hoa/thường CHỈ theo Shift/CapsLock thật của KeyEvent — không đọc shift
     * của bàn phím ảo, không auto-shift (Funput #462: shift một lần phải nhả ngay).
     */
    private fun onHardwareKeyDown(keyCode: Int, event: KeyEvent): Boolean {
        if (!hwSetting || currentInputConnection == null) return false
        if (!fieldReady) configureField(currentInputEditorInfo ?: return false, settings())
        if (!hwSetting || field.isSecure || (field.passthrough && !field.emailCompose) || field.rawKeys) return false
        val meta = event.metaState
        val k = HardwareKeys.classify(keyCode, meta, event.getUnicodeChar(meta))
        when (k) {
            HwKey.Pass -> {
                // Ctrl+C, mũi tên, Tab, Esc…: app tự xử lý; từ đang soạn coi như xong.
                if (session.bridge.isComposing) session.externalSelectionChange()
                return false
            }
            HwKey.Enter -> {
                // Chốt từ (auto-restore) rồi để Enter thật tới app: Shift+Enter, "Enter để gửi",
                // IME action của TextView đều giữ nguyên hành vi bàn phím cứng.
                clearSwipeUndo()
                if (proxy.begin()) try { session.commitComposing(proxy) } finally { proxy.end() }
                resetIfEditFailed()
                return false
            }
            else -> {}
        }
        val key = HardwareKeys.sessionKey(k, session.bridge.isComposing) ?: return false
        hwTyped = true
        hwConsumed.set(keyCode)
        onKey(key)
        // Bàn phím ảo đang hiện song song: shift một-lần của nó nhả NGAY khi gõ chữ cứng.
        if (key is Key.Letter) keyboard?.setAutoShift(false)
        return true
    }

    // MARK: phím

    private var stateStoreCache: SharedPreferences? = null
    private fun stateStore(): SharedPreferences =
        stateStoreCache ?: getSharedPreferences("ime_state", MODE_PRIVATE).also { stateStoreCache = it }

    /** enlexicon + bảng từ phổ biến nạp nền (lần đầu vào Tiếng Anh), khỏi trễ phím đầu. */
    private fun warmEnglish() { worker().post { com.viettelex.keyboard.SwipeEnglish.top } }

    /** Vuốt phím cách: đổi Tiếng Việt ↔ Tiếng Anh (chốt từ đang gõ, lưu trạng thái). */
    override fun onSpaceFlick() {
        clearSwipeUndo()
        if (!proxy.begin()) return
        val lang = try { session.toggleLanguage(proxy) } finally { proxy.end() }
        resetIfEditFailed()
        if (lang == null) return
        stateStore().edit().putString(Keys.KEYBOARD_LANGUAGE, lang.id).apply()
        keyboard?.spaceLanguage = lang
        if (lang == com.viettelex.keyboard.KeyboardLanguage.EN) warmEnglish()
        pendingGen = session.generation
        handler.removeCallbacks(suggestRun)
        refreshBar()
    }

    /** Điểm chạm phím chữ sắp emit (chỉ giữ khi tự sửa bật) — [onKey] chuyển cho session. */
    private var pendingTouch: AutoCorrect.Touch? = null

    override fun onLetterTouch(dx: Float, dy: Float) {
        pendingTouch = if (session.wantsTouches) AutoCorrect.Touch(dx, dy) else null
    }

    override fun onKey(key: Key) {
        val touch = if (key is Key.Letter) pendingTouch else null
        pendingTouch = null
        if (key == Key.Backspace && toolUndo != null) { undoTextTool(); return }   // ⌫ ngay sau = hoàn tác
        clearSwipeUndo()
        if (!proxy.begin()) return
        val out = try { session.handle(key, proxy, touch) } finally { proxy.end() }
        if (session.trackBoundaryWord) fxBoundaryEmoji()
        root?.buddy?.let { if (key == Key.Backspace) it.deletePressed() else it.keyPressed() }
        if (key is Key.MoveCursor) {
            if (key.vertical) proxy.moveCursorVertical(key.delta) else proxy.moveCursor(key.delta)
        }
        resetIfEditFailed()
        if (key is Key.Letter) strip?.hidePasteCard()
        pendingGen = out.generation
        if (out.needsAutoShift) { handler.removeCallbacks(autoShiftRun); handler.post(autoShiftRun) }
        handler.removeCallbacks(suggestRun)
        handler.postDelayed(suggestRun, SUGGEST_DELAY_MS)
    }

    /** Đang kéo trackpad: đã reset session ở bước đầu, auto-shift/gợi ý hoãn tới lúc nhả. */
    private var trackpadMoved = false

    /**
     * Bước trackpad (đã gom theo frame ở KeyboardView). Bước đầu: reset session như phím
     * MoveCursor; các bước sau chỉ dời con trỏ (1 IPC setSelection, không batch/đọc lại/
     * auto-shift/gợi ý) — [onTrackpadEnd] cập nhật một lần.
     */
    override fun onTrackpadMove(delta: Int, vertical: Boolean) {
        if (!trackpadMoved) {
            clearSwipeUndo()
            if (!proxy.begin()) return
            try { pendingGen = session.handle(Key.MoveCursor(delta, vertical), proxy).generation } finally { proxy.end() }
            handler.removeCallbacks(autoShiftRun); handler.removeCallbacks(suggestRun)
            trackpadMoved = true
        }
        if (vertical) proxy.moveCursorVertical(delta) else proxy.moveCursor(delta)
        resetIfEditFailed()
    }

    /** Giữ ⇧ + kéo phím cách: vùng chọn đang mở rộng (đọc văn bản một lần ở bước đầu). */
    private var shiftSelect: ShiftSelect? = null
    private var shiftSelectTried = false

    override fun onTrackpadSelect(delta: Int, vertical: Boolean) {
        if (!trackpadMoved) {
            clearSwipeUndo()
            if (!proxy.begin()) return
            try { session.commitComposing(proxy) } finally { proxy.end() }
            handler.removeCallbacks(autoShiftRun); handler.removeCallbacks(suggestRun)
            trackpadMoved = true
        }
        if (vertical) {          // lên/xuống theo dòng hiển thị: app tự mở rộng (Shift+↑/↓)
            shiftSelect = null; shiftSelectTried = true
            proxy.shiftArrow(if (delta < 0) EditorPort.PortKey.UP else EditorPort.PortKey.DOWN, kotlin.math.abs(delta))
            return
        }
        if (!shiftSelectTried) { shiftSelectTried = true; shiftSelect = proxy.beginShiftSelect() }
        val sel = shiftSelect
        if (sel == null) {
            proxy.shiftArrow(if (delta < 0) EditorPort.PortKey.LEFT else EditorPort.PortKey.RIGHT, kotlin.math.abs(delta))
            return
        }
        if (sel.move(delta) != null && !proxy.applyShiftSelect(sel)) shiftSelect = null
        resetIfEditFailed()
    }

    override fun onTrackpadEnd() {
        shiftSelect = null; shiftSelectTried = false
        if (!trackpadMoved) return
        trackpadMoved = false
        applyAutoShift()
        refreshBar()
    }

    override fun onDeleteWord() {
        root?.buddy?.deletePressed()
        clearSwipeUndo()
        if (!proxy.begin()) return
        try { session.deleteWordBackward(proxy) } finally { proxy.end() }
        resetIfEditFailed()
        applyAutoShift()
        refreshBar()
    }

    // MARK: chọn phím theo ngữ cảnh (thử nghiệm)

    private var smartTouchSetting = true
    private var smartTouchFieldOk = false

    /** Dựng trie prior (~vài chục ms) trên worker một lần; chưa xong ⇒ router cũ. */
    private fun warmSmartTouch() {
        if (!smartTouchSetting) { TelexKeyPrior.release(); return }   // tắt ⇒ nhả trie (0 RAM)
        if (TelexKeyPrior.sharedIfReady == null) worker().post { if (smartTouchSetting) TelexKeyPrior.warmUp() }
    }

    /** Gọi lúc chạm phím chữ (main): P(phím | từ đang gõ), null = không đổi phím. */
    private fun smartTouchPrior(): ((Char) -> Float?)? {
        if (!smartTouchSetting || !smartTouchFieldOk || !::session.isInitialized) return null
        val b = session.bridge
        if (b.passthrough) return null
        return TelexKeyPrior.sharedIfReady?.forTyping(b.rawWord, b.vniMode)
    }

    // MARK: gõ vuốt

    /** Bật khi: setting + ô hợp lệ + KHÔNG TalkBack/touch exploration. Tắt ⇒ bỏ decoder (template GC được). */
    private fun updateSwipeTyping() {
        updateAlternates()
        val allowed = swipeSetting && accessibility?.isTouchExplorationEnabled != true
        val on = allowed && swipeFieldOk
        if (!on) {
            keyboard?.swipeTyping = false
            if (::session.isInitialized) session.setSwipeTyping(false)
            // Tắt hẳn ⇒ bỏ (0 RAM). Chỉ ô này không cho vuốt (mật khẩu, URL…) ⇒ giữ decoder + FUTO
            // cho ô kế (khỏi giải lại weights); hẹn giờ ẩn vẫn nhả.
            if (!allowed) synchronized(swipeLock) { swipeDecoder = null; futo = null }
            return
        }
        val fresh = swipeDecoder == null
        if (fresh) synchronized(swipeLock) { swipeDecoder = SwipeDecoder() }
        updateFuto()
        session.setSwipeTyping(true)
        if (fresh) keyboard?.swipeTyping = false   // decoder mới (sau onTrimMemory) ⇒ phát lại layout
        keyboard?.swipeTyping = true      // → onSwipeLayout khi plane chữ đã dựng
    }

    /** Giữ phím chữ ra ký tự phụ (KeyAlternates): tắt khi TalkBack (giữ là cử chỉ của trình đọc). */
    private fun updateAlternates() {
        if (!::session.isInitialized) return
        val st = settings()
        val m = KeyAlternates.map(st.longPressNumbers, st.longPressSymbols, st.numberRow,
            accessibility = accessibility?.isTouchExplorationEnabled == true)
        keyboard?.setAlternates(m)
        keyboard?.setShiftAlternates(KeyAlternates.shiftMap(st.holdShiftSymbols, st.longPressNumbers, st.longPressSymbols,
            st.numberRow, accessibility = accessibility?.isTouchExplorationEnabled == true))
        keyboard?.popoversEnabled = accessibility?.isTouchExplorationEnabled != true
        session.setLetterAlternates(m.isNotEmpty())
        // "Vuốt phím để sao chép/dán": tắt khi TalkBack (vuốt là cử chỉ của trình đọc).
        val kc = st.swipeKeyCommands && accessibility?.isTouchExplorationEnabled != true
        keyboard?.keyCommands = kc
        session.setKeyCommands(kc)
    }

    /** Công tắc FUTO Swipe: bật ⇒ tạo + tải model ở nền (nhả lúc ẩn thì tải lại); tắt ⇒ bỏ. */
    private fun updateFuto() {
        val f = synchronized(swipeLock) {
            if (!futoSetting) { futo = null; return }
            futo ?: FutoSwipe { AssetBlobs.provider(assets)(Keys.ASSET_FUTO) }.also { f ->
                swipeDecoder?.layout?.let { f.setLayout(it) }
                futo = f
            }
        }
        worker().post { if (futo === f) f.load() }
    }

    override fun onSwipeLayout(layout: SwipeLayout) {
        val dec = swipeDecoder ?: return
        synchronized(swipeLock) { dec.setLayout(layout); futo?.setLayout(layout) }
        // Dựng template nền (~320 KB) — một luồng nhờ swipeLock; decode chờ nếu chưa xong.
        worker().post {
            synchronized(swipeLock) { if (swipeDecoder === dec) dec.prepare() }
            if (session.swipeEnglish) SwipeEnglish.lexicon     // nạp từ điển Anh ở nền (lazy, thread-safe)
            SyllableLM.shared       // map mô hình trigram (vnlm.bin — thanh gợi ý + Thêm dấu cũng dùng)
        }
    }

    override fun onSwipeTypingStart(): Boolean {
        if (!session.swipeTypingActive) return false
        clearSwipeUndo()
        if (!proxy.begin()) return false
        val ok = try { session.undoLastLetter(proxy) } finally { proxy.end() }
        resetIfEditFailed()
        if (ok) { handler.removeCallbacks(suggestRun); handler.removeCallbacks(autoShiftRun) }
        return ok
    }

    override fun onSwipeTypingEnd(path: SwipePath, case: SwipeSuggest.Case) {
        val dec = swipeDecoder ?: return
        val ctx = session.swipeContext()
        val t0 = if (TouchLog.enabled) System.nanoTime() else 0L
        // ctx.english != null ⇒ thêm ứng viên tiếng Anh (công tắc "Vuốt từ tiếng Anh"); điểm
        // cá nhân của từ tiếng Anh = ctx.englishWord (không có bigram tĩnh — chỉ cho âm tiết Việt).
        val cands = synchronized(swipeLock) {
            val enCtx = if (ctx.english != null) ctx.englishWord else null
            // FUTO Swipe (thử nghiệm): null khi tắt / model chưa sẵn ⇒ SHARK2 như cũ
            futo?.decode(path, SwipeSuggest.TOP_K, ctx.folded, ctx.english, enCtx, dec)
                ?: dec.decode(path, SwipeSuggest.TOP_K, ctx.folded, ctx.english, enCtx).also {
                    futo?.let { f -> worker().post { if (futo === f) f.load() } }
                }
        }
        // chọn từ + (nếu có) sửa lại từ vuốt trước theo ngữ cảnh hai phía (SwipeRevise)
        val res = session.resolveSwipe(cands, ctx, case)
        if (TouchLog.enabled) TouchLog.write(String.format(java.util.Locale.ROOT, "swipe decode %.1fms pts=%d cands=%d",
            (System.nanoTime() - t0) / 1e6, path.count, cands.size))
        if (res == null || !proxy.begin()) { applyAutoShift(); refreshBar(); return }
        val out = try { session.commitSwipe(res, proxy) } finally { proxy.end() }
        keyboard?.swipeCommitted()          // "Pháo hoa cuối nét" (kiểu khác: 0 việc)
        resetIfEditFailed()
        strip?.hidePasteCard()
        pendingGen = out.generation
        applyAutoShift()
        refreshBar()
    }

    override fun onSwipeTypingCancel() {
        applyAutoShift()
        refreshBar()
    }

    // MARK: vuốt ⌫ xoá theo từ

    override fun onSwipeDeleteStart(): Boolean {
        clearSwipeUndo()
        if (!swipe.start()) return false
        // Từ đang soạn là "từ thứ nhất" trên màn hình (ranh giới tính từ chữ thật): quên nó trong engine.
        handler.removeCallbacks(suggestRun)
        session.externalSelectionChange()
        return true
    }

    override fun onSwipeDeleteUpdate(words: Int): Int {
        val n = swipe.update(words)
        if (!swipe.selecting) strip?.showSwipePreview(swipe.preview)
        return n
    }

    override fun onSwipeDeleteEnd(commit: Boolean) {
        strip?.showSwipePreview(null)
        val deleted = if (proxy.begin()) try { swipe.finish(commit) } finally { proxy.end() } else { swipe.finish(false); null }
        resetIfEditFailed()
        swipeUndo = deleted
        strip?.showRestore(deleted != null)
        applyAutoShift()
        refreshBar()
    }

    override fun onRestoreDeleted() {
        if (toolUndo != null) { undoTextTool(); return }
        val text = swipeUndo ?: return
        clearSwipeUndo()
        if (!proxy.begin()) return
        try { session.externalSelectionChange(); proxy.insertText(text) } finally { proxy.end() }
        resetIfEditFailed()
        applyAutoShift()
        refreshBar()
    }

    private fun clearSwipeUndo() {
        if (swipeUndo == null && toolUndo == null) return
        swipeUndo = null
        toolUndo = null
        strip?.showRestore(false)
    }

    // MARK: công cụ văn bản (Plus) — logic thuần ở keyboard/TextTools.kt

    /**
     * Áp [tool] lên vùng chọn (getSelectedText) hoặc đoạn trước con trỏ (tới xuống dòng).
     * Lối vào hiện tại: chip đầu lưới mẫu câu; bảng sửa văn bản gộp sau gọi thẳng hàm này.
     */
    override fun onTextTool(tool: TextTool) {
        if (keyboard?.textToolsEnabled != true) return   // Plus + công tắc (đặt lúc vào ô)
        clearSwipeUndo()
        handler.removeCallbacks(suggestRun)
        if (!proxy.begin()) return
        val out = try {
            session.commitComposing(proxy)          // từ đang soạn chốt trước (thuộc đoạn cần đổi)
            TextToolRunner.apply(tool, proxy, IcProxy.CONTEXT_CAP)
        } finally { proxy.end() }
        resetIfEditFailed()
        when (out) {
            is TextToolRunner.Outcome.Applied -> {
                toolUndo = out.undo
                strip?.showRestore(true, tr("Hoàn tác"))
            }
            TextToolRunner.Outcome.FailSafe -> TouchLog.write("failsafe: text tool ${tool.id} tail mismatch → skip")
            else -> {}
        }
        applyAutoShift()
        refreshBar()
    }

    // MARK: dịch trên máy (Plus) — logic thuần ở keyboard/Translate.kt, ML Kit ở translate/

    /**
     * Dịch vùng chọn / đoạn trước con trỏ (giống công cụ văn bản) sang ngôn ngữ đích đã chọn
     * trong app ([Keys.TRANSLATE_TARGET]); đoạn đã là ngôn ngữ đích ⇒ dịch sang tiếng Việt.
     * Chạy nền (ML Kit), thanh gợi ý hiện "Đang dịch…"; kết quả chỉ ghi nếu ô chưa đổi.
     */
    override fun onTranslate() {
        if (!PlusGate.isUnlocked(PlusFeature.TRANSLATE) || proxy.isSecure) return
        clearSwipeUndo()
        handler.removeCallbacks(suggestRun)
        if (!proxy.begin()) return
        val job = try {
            session.commitComposing(proxy)
            TranslateRunner.prepare(proxy, prefs.getString(Keys.TRANSLATE_TARGET, null), IcProxy.CONTEXT_CAP)
        } finally { proxy.end() }
        resetIfEditFailed()
        if (job == null) { refreshBar(); return }
        translateUsed = true
        showTranslateStatus(tr("Đang dịch…"), 0)
        translate.start(job) { j, r -> onTranslated(j, r) }
    }

    private fun onTranslated(job: TranslateJob, r: TranslateResult) {
        when (r) {
            is TranslateResult.Ok -> {
                showTranslateStatus(null, 0)
                if (!proxy.begin()) return
                val out = try { TranslateRunner.commit(job, r.text, proxy) } finally { proxy.end() }
                resetIfEditFailed()
                when (out) {
                    is TextToolRunner.Outcome.Applied -> {
                        session.externalSelectionChange()
                        toolUndo = out.undo
                        strip?.showRestore(true, tr("Hoàn tác"))
                    }
                    TextToolRunner.Outcome.FailSafe -> TouchLog.write("failsafe: translate field changed → drop result")
                    else -> {}
                }
                applyAutoShift()
                refreshBar()
            }
            TranslateResult.MissingModel -> showTranslateStatus(tr("Mở app VietTelex để tải gói dịch"), 3500)
            is TranslateResult.Failed -> {
                TouchLog.write("translate failed: ${r.reason}")
                showTranslateStatus(tr("Không dịch được — thử lại sau"), 2500)
            }
        }
    }

    /** [text] null = gỡ; [ms] > 0 = tự gỡ sau chừng đó. */
    private fun showTranslateStatus(text: String?, ms: Long) {
        handler.removeCallbacks(clearStatusRun)
        strip?.showStatus(text)
        if (text != null && ms > 0) handler.postDelayed(clearStatusRun, ms)
    }

    /** Ô đóng / IME huỷ: bỏ lượt đang dịch, đóng client. Chưa từng dịch ⇒ không đụng gì (0 chi phí). */
    private fun cancelTranslate() {
        if (!translateUsed) return
        translate.cancel()
        showTranslateStatus(null, 0)
    }

    private fun undoTextTool() {
        val u = toolUndo ?: return
        clearSwipeUndo()
        if (!proxy.begin()) return
        val ok = try { TextToolRunner.undo(u, proxy) } finally { proxy.end() }
        if (!ok) TouchLog.write("failsafe: text tool undo tail moved → skip")
        resetIfEditFailed()
        session.externalSelectionChange()
        applyAutoShift()
        refreshBar()
    }

    /** commitText/deleteSurroundingText trả false: màn hình không còn chắc khớp engine ⇒ quên từ. */
    private fun resetIfEditFailed() {
        if (proxy.takeFailure()) session.externalSelectionChange()
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

    override fun onVoiceInput() {
        if (!voice.launch()) { voice.refresh(); keyboard?.setVoiceAvailable(voice.available && !field.isSecure) }
    }

    override fun onPlaneChanged(plane: Plane) {
        strip?.setPlane(plane)
        // Về chữ: viết hoa đầu câu theo context lúc đó (". " tự thêm ở plane 123 ⇒ hoa) —
        // một lần đọc context mỗi lần đổi plane, không mỗi phím.
        if (inputShown && fieldReady && PlanePolicy.reevaluatesShift(plane)) applyAutoShift()
    }

    /** Recents emoji ở prefs trạng thái (không kích listener cài đặt/theme); bản cũ chuyển một lần. */
    override fun emojiRecents(): List<String> = EmojiRecents.load(
        state = { stateStore().getString(Keys.EMOJI_RECENTS, null) },
        legacy = { prefs.getString(Keys.EMOJI_RECENTS, null) },
        store = { stateStore().edit().putString(Keys.EMOJI_RECENTS, it).apply() },
        dropLegacy = { editPrefs().remove(Keys.EMOJI_RECENTS).apply() })

    override fun noteEmojiUsed(e: String) {
        val next = EmojiRecents.noteUsed(emojiRecents(), e)
        stateStore().edit().putString(Keys.EMOJI_RECENTS, EmojiRecents.encode(next)).apply()
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
        resetIfEditFailed()
        applyAutoShift()
        refreshBar()
    }

    override fun onOpenSettings() {
        try {
            val i = packageManager.getLaunchIntentForPackage(packageName) ?: return
            startActivity(i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP))
        } catch (e: Exception) {
            Log.w(TAG, "open settings: $e")
        }
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
        clearSwipeUndo()
        if (!proxy.begin()) return
        syncShift()
        try { session.acceptSuggestion(item, proxy) } finally { proxy.end() }
        root?.buddy?.cheer()
        resetIfEditFailed()
        // Chọn gợi ý = gõ một từ: Shift một-lần nhả (session đã hạ keyboardShift), Caps giữ.
        if (session.keyboardShift == SuggestionCase.Shift.OFF) keyboard?.setAutoShift(false)
        applyAutoShift()
        refreshBar()
    }

    override fun onToggleTemplates() { closeClipboardPane(); keyboard?.toggleTemplates() }

    // MARK: lịch sử clipboard

    /** Bàn phím đang hiện (ô hiện tại có ý nghĩa cho luật "ô mật khẩu"). */
    private var inputShown = false
    private var clipPane: ClipboardPane? = null
    private val clipFile by lazy { File(filesDir, Keys.CLIPBOARD_FILE) }

    /**
     * Bật ⇒ nạp file (một lần) + áp hạn [ttl] ("Giữ lịch sử clipboard") rồi prune — rút ngắn
     * hạn ⇒ mục quá hạn bị bỏ ngay lần hiện kế tiếp; tắt ⇒ bỏ RAM + xoá file.
     */
    private fun syncClipHistory(enabled: Boolean, ttl: ClipboardTTL) {
        if (!enabled) {
            if (session.clipHistory != null || clipFile.exists()) { session.clipHistory = null; clipFile.delete() }
            strip?.setExtras(clipButton = false, open = false)
            closeClipboardPane()
            return
        }
        session.clipHistory?.let { h ->
            if (h.ttlMs != ttl.ms) { h.ttlMs = ttl.ms; if (h.prune(System.currentTimeMillis())) saveClipHistory(h) }
            return
        }
        val text = try { if (clipFile.exists()) clipFile.readText() else null } catch (_: Exception) { null }
        session.clipHistory = ClipboardHistory.deserialize(text, ttlMs = ttl.ms).also {
            if (it.prune(System.currentTimeMillis())) saveClipHistory(it)
        }
    }

    /** Ghi nền (file nhỏ ≤ 20 mục × 4000 ký tự); chụp chuỗi trên main trước. */
    private fun saveClipHistory(h: ClipboardHistory? = session.clipHistory) {
        val data = h?.serialize() ?: return
        val f = clipFile
        worker().post {
            try {
                val tmp = File(f.parentFile, f.name + ".tmp")
                tmp.writeText(data)
                if (!tmp.renameTo(f)) { f.writeText(data); tmp.delete() }
            } catch (e: Exception) { Log.w(TAG, "clip save: $e") }
        }
    }

    private fun onClipChanged() {
        // Ô mật khẩu chỉ tính khi bàn phím đang hiện ở ô đó; ẩn ⇒ copy ở app khác.
        if (session.recordClip(inputShown && field.isSecure)) {
            saveClipHistory()
            if (clipPane?.visibility == View.VISIBLE) refreshClipboardPane()
        }
        if (inputShown) { session.invalidatePasteCache(); refreshBar() }
    }

    override fun onToggleClipboard() {
        if (clipPane?.visibility == View.VISIBLE) { closeClipboardPane(); return }
        val th = theme ?: return
        val r = root ?: return
        if (keyboard?.plane == Plane.TEMPLATES) keyboard?.toggleTemplates()
        val pane = clipPane ?: ClipboardPane(this, th).also { it.listener = this; clipPane = it; r.overlay = it }
        pane.visibility = View.VISIBLE
        refreshClipboardPane()
        pane.scrollTop()
        strip?.setExtras(clipButton = true, open = true)
    }

    private fun refreshClipboardPane() {
        val h = session.clipHistory
        clipPane?.show(h?.items(System.currentTimeMillis()) ?: emptyList(), h != null, session.incognito)
    }

    private fun closeClipboardPane() {
        val p = clipPane ?: return
        if (p.visibility != View.VISIBLE) return
        p.visibility = View.GONE
        strip?.setExtras(clipButton = session.clipHistory != null, open = false)
    }

    override fun onClipPick(text: String) {
        closeClipboardPane()
        clearSwipeUndo()
        if (!proxy.begin()) return
        try { session.insertClip(text, proxy) } finally { proxy.end() }
        resetIfEditFailed()
        applyAutoShift()
        refreshBar()
    }

    override fun onClipTogglePin(text: String) {
        val h = session.clipHistory ?: return
        val limit = PlusGate.pinnedClipLimit
        if (h.togglePin(text, limit)) { saveClipHistory(); refreshClipboardPane() }
        else if (limit != null && h.contains(text)) {
            clipPane?.showNotice(tr("Tối đa %d mục ghim — VietTelex Plus ghim không giới hạn.", limit))
        }
    }

    override fun onClipRemove(text: String) {
        if (session.clipHistory?.remove(text) == true) { saveClipHistory(); refreshClipboardPane() }
    }

    override fun onClipClearAll() {
        session.clipHistory?.clear()
        saveClipHistory(); refreshClipboardPane()
    }

    override fun onClipClose() = closeClipboardPane()

    // MARK: bảng sửa văn bản + một tay

    override fun onToggleEditPanel() { keyboard?.toggleEditPanel() }

    // --- nút 😊 trên strip ("Nút emoji" = Thanh trên) ---
    override fun onEmojiButton() { keyboard?.setPlane(Plane.EMOJI) }

    /** Toạ độ StripView → KeyboardView (cùng cha ImeRootView, kể cả thả nổi). */
    private fun stripToKbDy(): Float {
        val st = strip ?: return 0f; val kb = keyboard ?: return 0f
        return (st.top - kb.top).toFloat()
    }
    private fun stripToKbDx(): Float {
        val st = strip ?: return 0f; val kb = keyboard ?: return 0f
        return (st.left - kb.left).toFloat()
    }

    override fun onEmojiButtonHold(anchorCx: Float, anchorTop: Float, anchorBottom: Float, x: Float, y: Float): Boolean {
        val kb = keyboard ?: return false
        val dx = stripToKbDx(); val dy = stripToKbDy()
        return kb.stripEmojiHold(anchorCx + dx, anchorTop + dy, anchorBottom + dy, x + dx, y + dy)
    }
    override fun onEmojiButtonHoldMove(x: Float, y: Float) { keyboard?.stripEmojiMove(x + stripToKbDx(), y + stripToKbDy()) }
    override fun onEmojiButtonHoldEnd(cancel: Boolean) { keyboard?.stripEmojiRelease(cancel) }

    override fun onEditAction(action: EditAction, selecting: Boolean) {
        clearSwipeUndo()
        if (!proxy.begin()) return
        try {
            session.commitComposing(proxy)          // từ đang gõ chốt trước khi dời / cắt / dán
            EditCommands.run(action, selecting, proxy, tracker)
        } finally { proxy.end() }
        resetIfEditFailed()
        applyAutoShift()
        refreshBar()
    }

    // MARK: vuốt phím thẳng lên ⇒ lệnh (KeyCommandGesture)

    override fun keyCommandHasSelection(): Boolean = proxy.hasSelection

    override fun keyCommandLabel(cmd: KeyCommand): String =
        if (cmd.needsSelection && !proxy.hasSelection) tr("Chưa chọn chữ") else tr(cmd.label)

    /**
     * Nhấc tay lúc lệnh đang bật: gỡ chữ của phím (đã chèn lúc chạm — checkpoint như gõ vuốt;
     * không được thì ⌫), chốt từ đang gõ, rồi chạy lệnh của bảng sửa (performContextMenuAction,
     * dự phòng Ctrl+phím). [letterDeferred] ⇒ chữ chưa chèn, vùng chọn còn nguyên.
     */
    override fun onKeyCommand(cmd: KeyCommand, letterDeferred: Boolean) {
        clearSwipeUndo()
        if (!proxy.begin()) return
        try {
            if (!letterDeferred && !session.undoLastLetter(proxy)) session.handle(Key.Backspace, proxy)
            session.commitComposing(proxy)
            if (!cmd.needsSelection || proxy.hasSelection) EditCommands.run(KeyCommands.editAction(cmd), false, proxy, tracker)
        } finally { proxy.end() }
        resetIfEditFailed()
        handler.removeCallbacks(suggestRun)
        applyAutoShift()
        refreshBar()
    }

    override fun onToggleOneHand() {
        val kb = keyboard ?: return
        if (kb.splitActive) return          // tách đôi: một tay tạm tắt (như iOS)
        val last = OneHandSide.fromPref(prefs.getString(Keys.ONE_HAND_LAST, null))
        onOneHandChange(OneHand.toggled(kb.oneHand, last))
    }

    override fun onOneHandChange(side: OneHandSide) {
        if (theme?.tablet == true) return
        val e = editPrefs().putString(Keys.ONE_HAND_MODE, side.pref)
        if (side != OneHandSide.OFF) e.putString(Keys.ONE_HAND_LAST, side.pref)
        e.apply()
        if (floatingNow) return             // một tay tắt khi thả nổi (lưu lại, áp khi gắn lại)
        keyboard?.setOneHand(side)
    }

    // MARK: auto-shift + gợi ý

    private fun applyAutoShift() {
        val on = session.updateAutoShift(proxy) ?: return
        keyboard?.setAutoShift(on)
    }

    override fun onShiftChanged() {
        handler.removeCallbacks(shiftRun)
        handler.postDelayed(shiftRun, SUGGEST_DELAY_MS)
    }

    /** Shift thật của bàn phím ảo → session (hoa/thường gợi ý, SuggestionCase). */
    private fun syncShift() {
        val kb = keyboard ?: return
        session.keyboardShift = when (kb.shift) {
            KeyboardView.Shift.OFF -> SuggestionCase.Shift.OFF
            KeyboardView.Shift.ON -> SuggestionCase.Shift.ONCE
            KeyboardView.Shift.CAPS -> SuggestionCase.Shift.CAPS_LOCK
        }
    }

    private fun refreshBar() {
        val st = strip ?: return
        if (!session.stripMode.shown || session.barCollapsed) return
        syncShift()
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
        /** Bàn phím ẩn liền bấy lâu ⇒ [releaseIdle] — xem [ImeTrim.IDLE_RELEASE_MS]. */
        const val IDLE_RELEASE_MS = ImeTrim.IDLE_RELEASE_MS
    }
}

/** Chính sách onTrimMemory (hàm thuần để test; số = hằng ComponentCallbacks2). */
object ImeTrim {
    /**
     * Ẩn liền bấy lâu ⇒ nhả dữ liệu nạp lại được. 3 phút (trước 45 s — RAM-AUDIT #6): 45 s làm
     * người gõ ngắt quãng (chat) parse lại enlexicon 1.4 MB + giải lại weights FUTO gần như mỗi
     * lần mở bàn phím; 3 phút vẫn trả RAM khi thực sự thôi gõ.
     */
    const val IDLE_RELEASE_MS = 180_000L
    private const val RUNNING_LOW = 10
    private const val RUNNING_CRITICAL = 15
    private const val BACKGROUND = 40

    /** Thiếu RAM thật (RUNNING_LOW/CRITICAL — API < 34 — hoặc BACKGROUND+); UI_HIDDEN (20) thì không. */
    fun releaseFuto(level: Int): Boolean = level in RUNNING_LOW..RUNNING_CRITICAL || level >= BACKGROUND

    /** Nhả như hẹn giờ ẩn: BACKGROUND+ và bàn phím đang ẩn. */
    fun releaseIdle(level: Int, inputShown: Boolean): Boolean = level >= BACKGROUND && !inputShown
}
