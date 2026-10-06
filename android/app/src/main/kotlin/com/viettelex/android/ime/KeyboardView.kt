package com.viettelex.android.ime

import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.os.SystemClock
import android.view.Choreographer
import android.view.MotionEvent
import android.view.View
import android.view.animation.DecelerateInterpolator
import com.viettelex.android.R
import com.viettelex.keyboard.CommaPopup
import com.viettelex.keyboard.DomainPopup
import com.viettelex.keyboard.EmojiKeyAction
import com.viettelex.keyboard.EmojiKeyMenu
import com.viettelex.keyboard.KeyAlternates
import com.viettelex.keyboard.KeyVariants
import com.viettelex.keyboard.EmojiSearch
import com.viettelex.keyboard.EmojiSearchSession
import com.viettelex.keyboard.GestureClassifier
import com.viettelex.keyboard.Key
import com.viettelex.keyboard.KeyCommitQueue
import com.viettelex.keyboard.KeyboardLanguage
import com.viettelex.keyboard.SpaceFlick
import com.viettelex.keyboard.SpaceMark
import com.viettelex.keyboard.SwipeLayout
import com.viettelex.keyboard.SwipePath
import com.viettelex.keyboard.SwipeSuggest
import com.viettelex.keyboard.TemplateItem
import com.viettelex.keyboard.TextTool
import com.viettelex.keyboard.TouchGeometry
import com.viettelex.keyboard.TouchLog
import kotlin.math.abs
import com.viettelex.keyboard.tr

/**
 * Vùng PHÍM của bàn phím (port iOS KeyboardView, phần rows): MỘT View vẽ mọi phím
 * bằng Canvas và là MỘT mặt touch multi-pointer (spec §5). Strip gợi ý và balloon là
 * view anh em riêng ([StripView], [BalloonView]) để gõ chữ KHÔNG ghi lại display
 * list của ~40 phím: phím chữ không đổi hình khi bấm (balloon lo), nên chỉ overlay
 * balloon bị invalidate — lớp phím chỉ vẽ lại khi shift / plane / pressed phím chức
 * năng đổi.
 *
 * Không Handler/timer nào chạy khi không có ngón trên phím (0% CPU idle).
 */
@SuppressLint("ViewConstructor")
class KeyboardView(
    context: Context,
    private val theme: ImeTheme,
    private val balloon: BalloonView,
    private val feedback: Feedback,
    /** Vệt gõ vuốt (overlay cùng toạ độ); null = không vẽ. */
    private val trail: SwipeTrailView? = null,
) : View(context) {

    interface Listener {
        fun onKey(key: Key)
        /** Điểm chạm của phím chữ sắp [onKey] (lệch so với tâm phím, theo cỡ phím) — cho tự sửa. */
        fun onLetterTouch(dx: Float, dy: Float) {}
        /**
         * Trackpad: bước đã gom theo frame (≤ 1 lần/frame). Mặc định = phím MoveCursor;
         * IME dời con trỏ NHẸ (không auto-shift/gợi ý mỗi bước) tới [onTrackpadEnd].
         */
        fun onTrackpadMove(delta: Int, vertical: Boolean) { onKey(Key.MoveCursor(delta, vertical)) }
        /** Nhả trackpad (sau bước cuối): IME cập nhật auto-shift + gợi ý một lần. */
        fun onTrackpadEnd() {}
        /** Vuốt nhanh phím cách (chỉ khi [configureSpaceFlick] bật): đổi Tiếng Việt ↔ Tiếng Anh. */
        fun onSpaceFlick() {}
        /** Giữ ⌫ > 3 s — xoá theo từ. */
        fun onDeleteWord()
        /** Vuốt trái trên ⌫ vừa vượt ngưỡng; false ⇒ không hỗ trợ ở ô này (bỏ lượt vuốt). */
        fun onSwipeDeleteStart(): Boolean
        /** Số từ muốn chọn theo quãng kéo; trả số từ thực chọn. */
        fun onSwipeDeleteUpdate(words: Int): Int
        /** Nhấc tay ([commit]) hoặc huỷ (ACTION_CANCEL / bàn phím ẩn). */
        fun onSwipeDeleteEnd(commit: Boolean)
        fun onGlobe(longPress: Boolean)
        /** Gõ giọng nói: mục 🎤 menu giữ 😊 (TalkBack: giữ lâu ","), chỉ khi [setVoiceAvailable]. */
        fun onVoiceInput()
        /** Mục ✋ menu giữ 😊: bật/tắt một tay (IME nhớ bên cũ). */
        fun onToggleOneHand()
        /** Mục 🪟 menu giữ 😊: bật/tắt bàn phím thả nổi (#112). */
        fun onToggleFloating() {}
        /** Mục ⚙ menu giữ 😊: mở app VietTelex. */
        fun onOpenSettings()
        fun onDismissKeyboard()
        fun onTemplate(item: TemplateItem)
        fun onOpenTemplates()
        /** Chạm một thao tác công cụ văn bản (Plus) trong lưới mẫu câu. */
        fun onTextTool(tool: TextTool)
        fun onPlaneChanged(plane: Plane)
        /** Recents emoji (đọc/ghi pref). */
        fun emojiRecents(): List<String>
        fun noteEmojiUsed(e: String)

        // --- gõ vuốt (chỉ gọi khi [swipeTyping] bật) ---
        /** Tâm phím a–z theo toạ độ view (đổi cỡ / xoay / plane chữ dựng lại). */
        fun onSwipeLayout(layout: SwipeLayout)
        /** Ngón vừa thành VUỐT: huỷ chữ đã chèn lúc chạm. false ⇒ coi như chạm (bỏ vuốt). */
        fun onSwipeTypingStart(): Boolean
        /** Nhấc tay: [path] toạ độ view (đã dời điểm chọn như hit-test), [case] theo shift. */
        fun onSwipeTypingEnd(path: SwipePath, case: SwipeSuggest.Case)
        /** Huỷ (ACTION_CANCEL / bàn phím ẩn) sau khi đã huỷ chữ đầu. */
        fun onSwipeTypingCancel()

        // --- bảng sửa văn bản / một tay ---
        /** Ô bảng sửa (trừ SELECT/CLOSE — view tự lo); [selecting] = chế độ chọn đang bật. */
        fun onEditAction(action: EditAction, selecting: Boolean)
        /** Rail / nút một tay đổi chế độ — IME lưu prefs rồi gọi lại [setOneHand]. */
        fun onOneHandChange(side: OneHandSide)
    }

    var listener: Listener? = null

    enum class Shift { OFF, ON, CAPS }

    // --- cấu hình (đặt bởi IME mỗi lần hiện; rebuild khi chữ ký đổi) ---
    var plane = Plane.LETTERS; private set
    var shift = Shift.ON; private set
    private var returnLabel = "return"
    private var inputKind = InputKind.NORMAL
    private var needsGlobe = false
    private var showLogo = true
    /** Ô phóng to chữ khi bấm (Keys.KEY_PREVIEW); tắt ⇒ không show balloon phím chữ/ký tự. */
    var keyPreview = true

    // --- giữ phím chữ ra ký tự phụ (KeyAlternates, issue #98) ---
    /** Bảng đang dùng (IME đặt theo cài đặt + hàng số + TalkBack). Rỗng ⇒ không nhãn, không hẹn giờ. */
    private var alts: Map<Char, String> = emptyMap()
    fun setAlternates(map: Map<Char, String>) {
        if (map == alts) return
        alts = map
        dropAlt()
        if (plane == Plane.LETTERS || plane == Plane.EMOJI_SEARCH) invalidate()
    }
    private var altHold: KeyAlternates.Hold? = null
    private var altPid = -1
    private var altKey: LaidKey? = null
    private var altShiftWas = Shift.OFF
    private val altRun = Runnable { fireAlt() }
    private var templatesEnabled = true
    private var templates: List<TemplateItem> = emptyList()

    // --- popup nhiều lựa chọn kiểu stock iOS (DomainPopup / KeyVariants) ---
    // Giữ "." bàn chữ ô URL / email ⇒ đuôi tên miền; giữ "," bàn chữ ⇒ dấu câu (CommaPopup);
    // giữ 😊 ⇒ menu icon (EmojiKeyMenu, cuối file); giữ phím bàn số / ký hiệu ⇒ biến thể
    // (" → ” “ „ » «, $ → ₫ € …). Ô gốc chọn sẵn, trượt chọn, nhấc chèn, trượt xa huỷ.
    /** IME tắt khi TalkBack / touch exploration (giữ là cử chỉ của trình đọc). */
    var popoversEnabled = true
        set(v) { if (field != v) { field = v; if (!v) { dropPopover(); dropEmojiMenu() }; invalidate() } }
    private var popHold: DomainPopup.Hold? = null
    private var popPid = -1
    private var popKey: LaidKey? = null
    private var popVariants = false
    private var popX = 0f
    private var popY = 0f
    private val popRun = Runnable { firePopover() }

    /**
     * Công cụ văn bản (PlusGate TEXT_TOOLS) — hai lối vào: hàng công cụ cuối bảng sửa văn
     * bản (EditPanel, ô [EditPanel.TOOL_PREFIX]…, gọi thẳng [Listener.onTextTool] và ở lại
     * bảng) và chip đầu lưới mẫu câu (☰). Đổi cờ ⇒ chữ ký layout đổi ⇒ bảng sửa dựng lại.
     */
    var textToolsEnabled = false
        set(v) {
            if (field != v) {
                field = v; if (!v) textToolsMode = false
                refreshTemplatesPane()
                if (plane == Plane.EDIT) rebuild()
            }
        }
    private var textToolsMode = false

    private fun refreshTemplatesPane() {
        if (textToolsMode) {
            templatesPane.setItems(emptyList())
            templatesPane.setExtras(listOf(tr("‹ Mẫu câu") to TOOLS_BACK) + TextTool.entries.map { it.label to it.id }, gear = false)
        } else {
            templatesPane.setItems(templates)
            templatesPane.setExtras(if (textToolsEnabled) listOf(tr("Aa Công cụ văn bản") to TOOLS_ENTRY) else emptyList(), gear = true)
        }
        if (plane == Plane.TEMPLATES) rebuild()
    }
    var keyAreaPx = theme.dp(218f); private set

    private var keys: List<LaidKey> = emptyList()
    private var builtSig = ""
    private val planeCache = HashMap<Plane, List<LaidKey>>()

    private val commits = KeyCommitQueue()
    private var lastShiftTap = 0L
    private var lastSpaceTap = 0L

    // --- pointer → phím (id pointer ≤ 31) ---
    private val ptrKey = arrayOfNulls<LaidKey>(MAX_PTR)
    private val ptrDownX = FloatArray(MAX_PTR)
    private val ptrDownY = FloatArray(MAX_PTR)
    /** Pointer đang thuộc pane emoji/mẫu câu thay vì phím. */
    private val ptrPane = BooleanArray(MAX_PTR)
    private var balloonOwner: LaidKey? = null

    // --- paint (tạo 1 lần) ---
    private val d = theme.density
    private val radius = theme.dp(KeyLayout.KEY_RADIUS)
    private val facePaint = theme.fill(theme.keyFill)
    /** Viền 1dp (theme tương phản cao / kính) — stroke thường, không offscreen. */
    private val borderPaint = theme.keyBorder?.let { c ->
        Paint(Paint.ANTI_ALIAS_FLAG).apply { color = c; style = Paint.Style.STROKE; strokeWidth = theme.dp(1f) }
    }
    // Gboard: chữ 22 sp regular, nhãn chức năng 14 sp medium (font hệ thống sans-serif)
    private val letterPaint = theme.text(22f)
    private val controlPaint = theme.text(14f, medium = true)
    private val badgePaint = theme.text(14f, medium = true)
    private val iconPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = theme.ink }
    private val letterOff = theme.centerOffset(letterPaint)
    private val controlOff = theme.centerOffset(controlPaint)
    private val digitPaint = theme.text(24f)
    private val digitOff = theme.centerOffset(digitPaint)
    private val sidePaint = theme.text(20f)
    private val sideOff = theme.centerOffset(sidePaint)
    private val hintPaint = theme.text(10f, medium = true)
    private val hintOff = theme.centerOffset(hintPaint)
    private val hintLift = theme.dp(6f)
    private val hintDrop = theme.dp(12f)
    private val keyPressed = theme.pressed(theme.keyFill)
    private val specialPressed = theme.pressed(theme.specialFill)
    private val actionPressed = theme.blend(theme.action, theme.actionInk, 0.12f)
    // Logo Vᴛ mờ ở góc phải phím space như iOS (thay nhãn "Tiếng Việt").
    private val logoPaint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG).apply {
        colorFilter = android.graphics.PorterDuffColorFilter(theme.withAlpha(theme.ink, 0.16f), android.graphics.PorterDuff.Mode.SRC_IN)
    }
    private val logo: android.graphics.Bitmap? by lazy { android.graphics.BitmapFactory.decodeResource(resources, R.drawable.ime_space_logo) }
    private val logoEn: android.graphics.Bitmap? by lazy { android.graphics.BitmapFactory.decodeResource(resources, R.drawable.ime_space_logo_en) }
    private val logoRect = android.graphics.RectF()
    /** Mã "VI"/"EN" góc dưới-phải phím cách khi bật vuốt đổi ngôn ngữ (SpaceMark) — mờ như stock. */
    private val codeColor = theme.withAlpha(theme.ink, 0.45f)
    private val codePaint = theme.text(if (theme.tablet) 12f else 10.5f, color = codeColor, medium = true,
        align = Paint.Align.RIGHT)

    /**
     * Chọn phím theo ngữ cảnh (thử nghiệm, SmartTouch): IME trả P(phím | từ đang gõ) lúc
     * chạm, null = không biết / tắt. null (mặc định) ⇒ router gần-nhất như cũ.
     */
    var letterPrior: (() -> ((Char) -> Float?)?)? = null

    // --- gõ vuốt ---
    /** IME bật khi setting + loại ô + không TalkBack. Tắt ⇒ không tính layout, không theo dõi ngón. */
    var swipeTyping = false
        set(v) {
            if (field == v) return
            field = v
            if (v) publishSwipeLayout() else { abortSwipe(); swipeLayout = null; swipePath = null }
        }
    private val classifier = GestureClassifier()
    private var swipePid = -1
    private var swiping = false
    private var swipeShift = Shift.OFF
    private var swipeKey: LaidKey? = null
    private var swipePath: SwipePath? = null
    private var swipeLayout: SwipeLayout? = null
    private var lastLetterDownT = Long.MIN_VALUE / 2
    private val yOffPx = TouchGeometry.yOffset * d

    private val emojiPane = EmojiPane(this, theme, feedback)
    // Tìm emoji (27/09/2026): plane EMOJI_SEARCH = ô tìm + plane chữ; phím vào [search]
    // (Telex riêng), không tới ô nhập. return / 😊 → về lưới emoji; ?123 → plane số.
    private val searchBar = EmojiSearchBar(this, theme)
    private var search = EmojiSearchSession()
    /** Cài đặt engine cho ô tìm (IME đặt mỗi lần hiện). */
    var searchSettings = com.viettelex.keyboard.KeyboardSettings()
    private val templatesPane = TemplatesPane(this, theme, feedback)

    // --- trackpad / giữ phím ---
    private var trackpad = false
    private var spaceKey: LaidKey? = null
    private val trackpadGesture = TrackpadGesture()
    /** Gom bước theo frame: ≤ 1 lệnh dời con trỏ (IPC) mỗi vsync. */
    private val trackpadBatch = TrackpadBatcher()
    private var trackpadFramePosted = false
    private val trackpadFrame = Choreographer.FrameCallback {
        trackpadFramePosted = false
        trackpadBatch.drain()?.let { sendTrackpadStep(it) }
    }
    private var spacePtr = -1
    private var bsPtr = -1
    private var bsHoldStart = 0L
    private var bsTick = 0
    private var bsRepeating = false
    /** Vuốt ⌫: 0 chưa, 1 đang vuốt, -1 ô không hỗ trợ (lượt này). */
    private var bsSwipe = 0
    private var bsSwipeAsked = 0
    private var bsSwipeWords = 0
    private var globePtr = -1
    private var globeFired = false
    private val slop = theme.dp(10f)   // allowableMovement của UILongPressGestureRecognizer

    private val spaceHoldRun = Runnable { beginTrackpad() }
    private val bsStartRun = Runnable {
        bsRepeating = true; bsHoldStart = SystemClock.uptimeMillis(); bsTick = 0
        postDelayed(bsTickRun, BS_INTERVAL)
    }
    private val bsTickRun = object : Runnable {
        override fun run() {
            val held = SystemClock.uptimeMillis() - bsHoldStart
            if (held > 3000 && plane != Plane.EMOJI_SEARCH) {
                bsTick++
                if (bsTick % 4 == 1) listener?.onDeleteWord()
            } else {
                emit(Key.Backspace)
                if (held > 1600) emit(Key.Backspace)
            }
            postDelayed(this, BS_INTERVAL)
        }
    }
    private val hintInset = theme.dp(9f)
    private var switcherHint = false
    fun setSwitcherHint(on: Boolean) {
        if (on == switcherHint) return
        switcherHint = on
        keys.firstOrNull { it.kind == KeyKind.EMOJI }?.let { invalidateKey(it) }
    }
    private val globeLongRun = Runnable { globeFired = true; listener?.onGlobe(true) }

    // --- giữ lâu "," = gõ giọng nói (kiểu Gboard; chỉ khi có IME giọng nói) ---
    private var voiceAvailable = false
    private var commaPtr = -1
    private var commaKey: LaidKey? = null
    private val voiceLongRun = Runnable {
        val k = commaKey ?: return@Runnable
        commits.disarm(k)                 // không chèn "," khi nhấc tay
        commaPtr = -1
        listener?.onVoiceInput()
    }
    fun setVoiceAvailable(on: Boolean) {
        if (on == voiceAvailable) return
        voiceAvailable = on
        keys.firstOrNull { it.kind == KeyKind.PUNCT && it.label == "," }?.let { invalidateKey(it) }
    }
    // Popup bật (không TalkBack): giữ "," = popup dấu câu (CommaPopup); hai hành vi cũ dưới chỉ còn cho TalkBack.
    /** "," bàn chữ có popup dấu câu (không TalkBack). */
    private fun isCommaPopup(k: LaidKey) = popoversEnabled && plane == Plane.LETTERS && k.kind == KeyKind.PUNCT && k.label == ","
    private fun isVoiceComma(k: LaidKey) = !popoversEnabled && voiceAvailable && plane == Plane.LETTERS && k.kind == KeyKind.PUNCT && k.label == ","
    // --- giữ "," ra "." (KeyAlternates.commaHold: bảng ký tự phụ không rỗng) — chỉ khi "," KHÔNG
    // phải phím giọng nói (có IME giọng nói ⇒ giữ nguyên hành động cũ, không ra ".") ---
    private var periodFired = false
    private fun isPeriodComma(k: LaidKey) =
        !popoversEnabled && plane == Plane.LETTERS && k.kind == KeyKind.PUNCT && k.label == "," && KeyAlternates.commaHold(alts, voiceAvailable)
    /** Hết giờ mà "," còn chờ chốt ⇒ đổi thành "." (chốt lúc nhấc / khi ngón khác chạm, như ","). */
    private val periodRun = Runnable {
        val k = commaKey ?: return@Runnable
        if (!KeyAlternates.holdComma(commits, k, ::textFire)) return@Runnable
        periodFired = true
        feedback.longPress(this)
        showBalloon(k, KeyAlternates.COMMA_ALT)
    }
    private fun cancelCommaHold() {
        if (commaPtr < 0) return
        removeCallbacks(voiceLongRun); removeCallbacks(periodRun)
        if (periodFired) commaKey?.let { hideBalloon(it) }
        periodFired = false
        commaPtr = -1; commaKey = null
    }

    /** Ô cho giữ lâu Enter = xuống dòng thật (IME đặt theo [FieldConfig.holdNewline]). */
    var holdNewline = false
    private var returnPtr = -1
    private val returnHoldRun = Runnable {
        val k = ptrKey.getOrNull(returnPtr)
        // Ngón khác chạm xuống đã flush (chốt) phím Enter ⇒ không còn là giữ lâu.
        if (k == null || k.kind != KeyKind.RETURN || !commits.isArmed(k)) return@Runnable
        commits.disarm(k)                 // nhả tay KHÔNG gửi action
        feedback.longPress(this)
        showBalloon(k, "↵")
        emit(Key.LineBreak)
    }

    // --- badge "ViệtTelex" ---
    private var badgeAlpha = 0f
    private var badgeAnim: ValueAnimator? = null
    private val badgeText = context.getString(R.string.ime_badge)

    private val spaceFire: () -> Unit = {
        val now = SystemClock.uptimeMillis()
        // Bàn số: space luôn literal (không double-space → ". ").
        val pad = plane == Plane.PHONE || plane == Plane.NUMPAD
        emit(if (!pad && now - lastSpaceTap < DOUBLE_SPACE_MS) Key.DoubleSpacePeriod else Key.Space)
        lastSpaceTap = now
    }
    private val newlineFire: () -> Unit = { emit(Key.Newline) }
    private val textFires = HashMap<String, () -> Unit>()
    private fun textFire(s: String) = textFires.getOrPut(s) { val k = Key.Text(s); { emit(k) } }

    /** Mọi phím đi qua đây: plane tìm emoji giữ phím cho ô tìm, còn lại tới IME. */
    private fun emit(k: Key) {
        if (plane != Plane.EMOJI_SEARCH) { listener?.onKey(k); return }
        when (k) {
            is Key.Letter -> search.type(k.ch)
            is Key.Text -> { if (k.replacesLetter) search.backspace(); search.insert(k.text) }
            Key.Space, Key.DoubleSpacePeriod -> search.space()
            Key.Backspace -> search.backspace()
            Key.Newline, Key.LineBreak -> { setPlane(Plane.EMOJI); return }
            else -> return
        }
        refreshSearch()
    }

    private fun refreshSearch() {
        val q = search.query
        searchBar.update(q, if (q.isBlank()) listener?.emojiRecents() ?: emptyList() else EmojiSearch.search(q))
        invalidate()
    }

    internal fun searchClear() {
        feedback.click(Feedback.MODIFIER, this)
        search.clear()
        refreshSearch()
    }

    /** Test/debug: query + kết quả đang hiện của ô tìm. */
    internal val searchState: Pair<String, List<String>> get() = search.query to searchBar.results

    init {
        isHapticFeedbackEnabled = true
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
    }

    // MARK: cấu hình

    fun configure(returnLabel: String, kind: InputKind, needsGlobe: Boolean, showLogo: Boolean,
                  templatesEnabled: Boolean, templates: List<TemplateItem>, keyAreaPx: Float,
                  numberSigned: Boolean = false, numberDecimal: Boolean = false, numberRow: Boolean = false,
                  periodKey: Boolean = false) {
        this.numberRow = numberRow
        this.periodKey = periodKey
        this.numberSigned = numberSigned
        this.numberDecimal = numberDecimal
        this.returnLabel = returnLabel
        this.needsGlobe = needsGlobe
        this.showLogo = showLogo
        this.templatesEnabled = templatesEnabled
        this.templates = templates
        if (this.keyAreaPx != keyAreaPx) { this.keyAreaPx = keyAreaPx; requestLayout() }
        // Loại ô: số ⇒ plane 123; chữ ⇒ shift ON (nếu có) rớt về OFF như iOS configureInputKind.
        inputKind = kind
        plane = kind.padPlane ?: Plane.LETTERS
        if (plane == Plane.LETTERS && shift == Shift.ON) shift = Shift.OFF
        textToolsMode = false
        refreshTemplatesPane()
        rebuild()
        listener?.onPlaneChanged(plane)
    }

    fun setNeedsGlobe(on: Boolean) {
        if (on == needsGlobe) return
        needsGlobe = on
        rebuild()
    }

    /** Auto-shift đầu câu: chỉ nâng OFF→ON, không bao giờ hạ CAPS. */
    fun setAutoShift(on: Boolean) {
        if (shift == Shift.CAPS || plane == Plane.EMOJI_SEARCH) return
        val want = if (on) Shift.ON else Shift.OFF
        if (shift != want) { shift = want; if (plane == Plane.LETTERS) invalidate() }
    }

    fun setPlane(p: Plane) {
        if (p == Plane.TEMPLATES && !templatesEnabled) return
        if (plane == p) return
        // Rời plane chữ sang ?123 / =\< / emoji: tắt Caps Lock + shift một-lần (như iOS stock;
        // Phil 06/10/2026). Về chữ IME đánh giá lại viết hoa đầu câu (onPlaneChanged).
        if (plane == Plane.LETTERS && PlanePolicy.clearsShiftLeavingLetters(p)) shift = Shift.OFF
        plane = p
        if (p == Plane.LETTERS && shift == Shift.ON) shift = Shift.OFF
        if (p == Plane.EMOJI) emojiPane.open(listener?.emojiRecents() ?: emptyList())
        if (p == Plane.EMOJI_SEARCH) {
            search = EmojiSearchSession(searchSettings)
            shift = Shift.OFF
            searchBar.reset()
        }
        if (p == Plane.TEMPLATES) templatesPane.resetScroll()
        if (textToolsMode) { textToolsMode = false; refreshTemplatesPane() }
        editSelecting = false
        rebuild()
        listener?.onPlaneChanged(p)
    }

    /** Một tay: dựng lại plane ở bề ngang hẹp (planeCache theo chữ ký). */
    fun setOneHand(side: OneHandSide) {
        if (side == oneHand) return
        cancelAllTouches()
        oneHand = side
        rebuild()
    }

    /** Icon con trỏ trên thanh gợi ý: mở / đóng bảng sửa văn bản. */
    fun toggleEditPanel() {
        setPlane(if (plane == Plane.EDIT) Plane.LETTERS else Plane.EDIT)
    }

    /** IME báo ô đang có vùng chọn (onUpdateSelection) — ô Sao chép / Cắt sáng lên. */
    fun setEditHasSelection(on: Boolean) {
        if (on == editHasSelection) return
        editHasSelection = on
        if (plane == Plane.EDIT) invalidate()
    }

    fun toggleTemplates() {
        if (!templatesEnabled) return
        setPlane(if (plane == Plane.TEMPLATES) Plane.LETTERS else Plane.TEMPLATES)
    }

    private var numberSigned = false
    private var numberDecimal = false
    private var numberRow = false
    private var periodKey = false
    /** Chế độ một tay (IME chỉ đặt khác OFF trên điện thoại). */
    var oneHand = OneHandSide.OFF; private set
    private fun signature() = "$returnLabel|$inputKind|$needsGlobe|$width|$keyAreaPx|$numberSigned|$numberDecimal|$numberRow|$periodKey|$oneHand|$textToolsEnabled"

    private fun rebuild() {
        if (width == 0) return
        dropAlt()                         // phím có thể dời / đổi plane
        dropPopover()
        val sig = signature()
        if (sig != builtSig) { planeCache.clear(); builtSig = sig }
        keys = planeCache.getOrPut(plane) {
            KeyLayout.build(LayoutConfig(plane, width.toFloat(), keyAreaPx, d, inputKind, needsGlobe,
                theme.tablet, returnLabel, numberSigned, numberDecimal, numberRow, oneHand,
                editTools = textToolsEnabled, periodKey = periodKey))
        }
        railSpan = if (OneHand.appliesTo(plane)) OneHand.rail(width.toFloat(), oneHand) else null
        spaceKey = keys.firstOrNull { it.kind == KeyKind.SPACE }
        spaceKey?.let {
            val sz = theme.dp(22f)
            logoRect.set(it.right - theme.dp(10f) - sz, it.centerY - sz / 2, it.right - theme.dp(10f), it.centerY + sz / 2)
        }
        val paneBottom = if (plane == Plane.TEMPLATES) keyAreaPx - KeyLayout.rowUnit(keyAreaPx, numberRow) else keyAreaPx
        templatesPane.layout(width.toFloat(), paneBottom)
        emojiPane.layout(width.toFloat(), keyAreaPx)
        searchBar.layout(width.toFloat(), KeyLayout.searchHeaderPx(keyAreaPx))
        if (plane == Plane.EMOJI_SEARCH) refreshSearch()
        publishSwipeLayout()
        invalidate()
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        setMeasuredDimension(MeasureSpec.getSize(widthMeasureSpec), Math.round(keyAreaPx))
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        rebuild()
    }

    /** Bàn phím ẩn: dọn mọi pointer/timer — không để Handler nào sống. */
    /** Hẹn giờ ẩn (VietTelexIME.releaseIdle): nhả dữ liệu emoji nếu không đang ở lưới emoji. */
    fun releaseIdleCaches() { if (plane != Plane.EMOJI) emojiPane.releaseData() }

    fun onHidden() {
        cancelAllTouches()
        badgeAnim?.cancel(); badgeAlpha = 0f
        flickAnim?.cancel(); flickAnim = null; carouselOn = false
        emojiPane.onHidden()
        searchBar.reset()
        templatesPane.onHidden()
    }

    // MARK: badge ngôn ngữ

    /** "ViệtTelex" giữa space 0.7 s rồi fade 0.3 s; logo Vᴛ ẩn trong lúc đó. */
    fun showLanguageBadge() {
        badgeAnim?.cancel()
        badgeAlpha = 1f
        badgeAnim = ValueAnimator.ofFloat(1f, 0f).apply {
            startDelay = 700; duration = 300
            interpolator = DecelerateInterpolator()
            addUpdateListener { badgeAlpha = it.animatedValue as Float; invalidateSpace() }
            start()
        }
        invalidateSpace()
    }

    private fun invalidateSpace() {
        val k = spaceKey ?: return
        @Suppress("DEPRECATION")
        invalidate(k.left.toInt(), k.top.toInt(), k.right.toInt() + 1, k.bottom.toInt() + 1)
    }

    @Suppress("DEPRECATION")
    private fun invalidateKey(k: LaidKey) =
        invalidate(k.left.toInt() - 1, k.top.toInt() - 1, k.right.toInt() + 1, k.bottom.toInt() + 1)

    // MARK: vẽ

    override fun onDraw(c: Canvas) {
        when (plane) {
            Plane.EMOJI -> { emojiPane.draw(c); return }
            Plane.TEMPLATES -> templatesPane.draw(c)
            Plane.EMOJI_SEARCH -> searchBar.draw(c)
            else -> Unit
        }
        val ks = keys
        for (i in ks.indices) drawKey(c, ks[i])
        railSpan?.let { drawRail(c, it) }
    }

    // MARK: một tay — rail (dải trống: nút đổi bên + thoát)

    private var railSpan: Pair<Float, Float>? = null
    private var railPressed = -1
    private var railPtr = -1
    private val railFill = theme.fill(theme.specialFill)

    private fun railCenter(i: Int): Pair<Float, Float> {
        val r = railSpan ?: return 0f to 0f
        return (r.first + r.second) / 2 to keyAreaPx * (if (i == 0) 0.3f else 0.7f)
    }

    private fun drawRail(c: Canvas, r: Pair<Float, Float>) {
        val rad = minOf((r.second - r.first) / 2 - theme.dp(4f), theme.dp(22f))
        if (rad <= 0f) return
        for (i in 0..1) {
            val (cx, cy) = railCenter(i)
            railFill.color = if (railPressed == i) specialPressed else theme.specialFill
            c.drawCircle(cx, cy, rad, railFill)
            icon(c, if (i == 0) ImeIcons.SWAP else ImeIcons.EXPAND, cx, cy, 20f, theme.ink, (255 * theme.labelAlpha).toInt())
        }
    }

    // MARK: bảng sửa văn bản

    /** Chế độ chọn của bảng sửa (ô "Chọn"). */
    private var editSelecting = false
    private var editHasSelection = false
    private var editPtr = -1
    private var editRepeatKey: LaidKey? = null
    private val editRepeatRun = object : Runnable {
        override fun run() {
            val k = editRepeatKey ?: return
            fireEdit(k)
            postDelayed(this, EDIT_REPEAT_MS)
        }
    }

    private fun editEnabled(a: EditAction) = !a.needsSelection || editHasSelection

    private fun fireEdit(k: LaidKey) {
        EditPanel.toolOf(k.insert)?.let { listener?.onTextTool(it); return }   // ở lại bảng sửa
        val a = EditAction.of(k.insert) ?: return
        when (a) {
            EditAction.SELECT -> { editSelecting = !editSelecting; invalidate() }
            EditAction.CLOSE -> setPlane(Plane.LETTERS)
            EditAction.DELETE -> listener?.onKey(Key.Backspace)
            else -> if (editEnabled(a)) listener?.onEditAction(a, editSelecting)
        }
    }

    private fun drawEditKey(c: Canvas, k: LaidKey, alpha: Int) {
        if (EditPanel.toolOf(k.insert) != null) {
            drawLabel(c, k.label, k.centerX, k.centerY, controlPaint, controlOff, alpha); return
        }
        val a = EditAction.of(k.insert) ?: return
        val cx = k.centerX; val cy = k.centerY
        val al = if (editEnabled(a)) alpha else (alpha * 0.35f).toInt()
        when {
            a == EditAction.DELETE -> icon(c, ImeIcons.DELETE, cx, cy, 22f, theme.ink, al)
            EditPanel.isGlyph(a) -> drawLabel(c, k.label, cx, cy, letterPaint, letterOff, al)
            else -> drawLabel(c, k.label, cx, cy, controlPaint, controlOff, al)
        }
    }

    private fun drawKey(c: Canvas, k: LaidKey) {
        // Gboard: phím phẳng bo góc, KHÔNG bóng; phím chức năng tô màu phụ (secondary
        // container); enter là pill màu nhấn. Nhấn = state layer ink 12%.
        val special = KeyKind.isSpecial(k.kind) && k.kind != KeyKind.RETURN
        var face = when {
            k.kind == KeyKind.RETURN -> if (k.pressed) actionPressed else theme.action
            k.kind == KeyKind.SHIFT && shift == Shift.CAPS -> theme.chip
            k.kind == KeyKind.EDIT && editSelecting && k.insert == "SELECT" -> theme.chip
            special -> if (k.pressed) specialPressed else theme.specialFill
            k.kind == KeyKind.LETTER || k.kind == KeyKind.CHAR -> theme.keyFill   // popup lo phản hồi
            k.kind == KeyKind.PAD && k.side -> if (k.pressed) specialPressed else theme.specialFill
            else -> if (k.pressed) keyPressed else theme.keyFill
        }
        if (trackpad) face = theme.keyFill
        facePaint.color = face
        val r = if (k.kind == KeyKind.RETURN) minOf(k.width, k.height) / 2 else radius
        c.drawRoundRect(k.left, k.top, k.right, k.bottom, r, r, facePaint)
        borderPaint?.let { bp ->
            val h = bp.strokeWidth / 2
            c.drawRoundRect(k.left + h, k.top + h, k.right - h, k.bottom - h, r, r, bp)
        }

        // 0.2 khi trackpad; × độ trong suốt ký tự (alpha paint — không offscreen).
        val contentAlpha = ((if (trackpad) 51 else 255) * theme.labelAlpha).toInt()
        val cx = k.centerX; val cy = k.centerY
        when (k.kind) {
            KeyKind.LETTER -> {
                drawLabel(c, if (shift == Shift.OFF) k.label else k.upper, cx, cy, letterPaint, letterOff, contentAlpha)
                // Ký tự phụ nhỏ, mờ ở góc trên-phải như Gboard.
                if (alts.isNotEmpty()) alts[k.label[0]]?.let {
                    drawLabel(c, it, k.right - hintInset + theme.dp(2f), k.top + hintInset, hintPaint, hintOff, (contentAlpha * 0.55f).toInt())
                }
            }
            KeyKind.CHAR -> drawLabel(c, k.label, cx, cy, letterPaint, letterOff, contentAlpha)
            KeyKind.PAD -> if (k.hint.isEmpty()) {
                drawLabel(c, k.label, cx, cy, if (k.side) sidePaint else digitPaint, if (k.side) sideOff else digitOff, contentAlpha)
            } else {
                // Số + chữ nhỏ bên dưới (bàn điện thoại Gboard)
                drawLabel(c, k.label, cx, cy - hintLift, digitPaint, digitOff, contentAlpha)
                drawLabel(c, k.hint, cx, cy + hintDrop, hintPaint, hintOff, (contentAlpha * 0.7f).toInt())
            }
            KeyKind.PUNCT -> {
                drawLabel(c, k.label, cx, cy, letterPaint, letterOff, contentAlpha)
                // Gợi ý giữ lâu kiểu Gboard ở góc trên-phải phím ",": "." (popup dấu câu); TalkBack: 🎤.
                if (isVoiceComma(k)) icon(c, ImeIcons.MIC, k.right - hintInset, k.top + hintInset, 10f, theme.ink, (contentAlpha * 0.55f).toInt())
                else if (isPeriodComma(k) || isCommaPopup(k)) drawLabel(c, KeyAlternates.COMMA_ALT, k.right - hintInset + theme.dp(2f), k.top + hintInset, hintPaint, hintOff, (contentAlpha * 0.55f).toInt())
            }
            KeyKind.PLANE, KeyKind.MORE -> drawLabel(c, k.label, cx, cy, controlPaint, controlOff, contentAlpha)
            KeyKind.SHIFT -> {
                val id = when (shift) { Shift.CAPS -> ImeIcons.CAPS; Shift.ON -> ImeIcons.SHIFT_FILL; Shift.OFF -> ImeIcons.SHIFT }
                icon(c, id, cx, cy, 22f, theme.ink, contentAlpha)
            }
            KeyKind.BACKSPACE -> {
                if (k.pressed && !trackpad) {
                    icon(c, ImeIcons.DELETE_FILL, cx, cy, 22f, theme.ink, contentAlpha)
                    icon(c, ImeIcons.DELETE_X, cx, cy, 22f, face, 255)
                } else icon(c, ImeIcons.DELETE, cx, cy, 22f, theme.ink, contentAlpha)
                // Vuốt ⌫: số từ sẽ xoá ở góc trên-phải (xem trước khi không bôi đen được).
                if (bsSwipe == 1 && bsSwipeWords > 0)
                    drawLabel(c, "−$bsSwipeWords", k.right - hintInset - theme.dp(2f), k.top + hintInset, hintPaint, hintOff, contentAlpha)
            }
            KeyKind.GLOBE -> icon(c, ImeIcons.GLOBE, cx, cy, 21f, theme.ink, contentAlpha)
            KeyKind.EMOJI -> {
                icon(c, ImeIcons.FACE, cx, cy, 22f, theme.ink, contentAlpha)
                // Gợi ý giữ lâu kiểu Gboard: 🌐 nhỏ, mờ ở góc trên-phải — chỉ khi thanh điều hướng
                // KHÔNG có nút đổi bàn phím (Android 16 báo qua onCustomImeSwitcherButtonRequestedVisible).
                if (switcherHint) icon(c, ImeIcons.GLOBE, k.right - hintInset, k.top + hintInset, 10f, theme.ink, (contentAlpha * 0.55f).toInt())
            }
            KeyKind.CLEAR -> icon(c, ImeIcons.TRASH, cx, cy, 21f, theme.ink, contentAlpha)
            KeyKind.EDIT -> drawEditKey(c, k, contentAlpha)
            KeyKind.DISMISS -> icon(c, ImeIcons.KB_DISMISS, cx, cy, 22f, theme.ink, contentAlpha)
            KeyKind.RETURN -> {
                val id = when (returnLabel) {
                    "search" -> ImeIcons.SEARCH
                    "send" -> ImeIcons.SEND
                    "done" -> ImeIcons.CHECK
                    "go", "next" -> ImeIcons.ARROW_RIGHT
                    else -> ImeIcons.RETURN
                }
                icon(c, id, cx, cy, 22f, theme.actionInk, contentAlpha)
            }
            KeyKind.SPACE -> {
                // Badge "ViệtTelex" lúc hiện rồi mờ dần về logo Vᴛ (như iOS).
                if (badgeAlpha > 0f) {
                    badgePaint.alpha = (badgeAlpha * contentAlpha).toInt()
                    c.drawText(if (spaceLanguage == KeyboardLanguage.EN) KeyboardLanguage.EN.displayName else badgeText,
                        cx, cy + badgeOff, badgePaint)
                }
                if (carouselOn) { drawCarousel(c, k, contentAlpha); return }
                if (badgeAlpha < 1f) when (val m = SpaceMark.choose(spaceFlickEnabled, showLogo, spaceLanguage)) {
                    is SpaceMark.Code -> {
                        codePaint.alpha = (android.graphics.Color.alpha(codeColor) * (1f - badgeAlpha) * contentAlpha / 255f).toInt()
                        c.drawText(m.text, k.right - theme.dp(if (theme.tablet) 10f else 7f),
                            k.bottom - theme.dp(if (theme.tablet) 7f else 5f), codePaint)
                    }
                    is SpaceMark.Logo -> {
                        val bmp = if (m.language == KeyboardLanguage.EN) logoEn else logo
                        if (bmp != null) {
                            logoPaint.alpha = ((1f - badgeAlpha) * contentAlpha).toInt()
                            c.drawBitmap(bmp, null, logoRect, logoPaint)
                        }
                    }
                    SpaceMark.None -> {}
                }
            }
        }
    }

    private val badgeOff = theme.centerOffset(badgePaint)

    // MARK: vuốt phím cách đổi Tiếng Việt ↔ Tiếng Anh (SpaceFlick, kiểu HeliBoard)
    // Kéo ngang: nhãn ngôn ngữ hiện tại trượt theo ngón + mờ dần, nhãn kia trượt vào từ phía
    // đối diện. Nhấc nhanh (trước ngưỡng trackpad) đủ ~1 phím ⇒ đổi: nhãn mới vào giữa, sáng
    // một nhịp rồi mờ đi, logo Vᴛ/E đổi theo. Không đủ ⇒ trượt về, mờ đi. Giống iOS.
    private var spaceFlickEnabled = false
    var spaceLanguage = KeyboardLanguage.VI
        set(v) { if (field != v) { field = v; invalidateSpace() } }
    private var flickDownT = 0L
    private var carouselOn = false
    private var carouselFrom = KeyboardLanguage.VI
    private var carQ = 0f
    private var carCurA = 0f
    private var carNextA = 0f
    private var flickAnim: android.animation.Animator? = null
    private val flickPaint = theme.text(16f)
    private val flickOff = theme.centerOffset(flickPaint)

    fun configureSpaceFlick(enabled: Boolean, language: KeyboardLanguage) {
        spaceFlickEnabled = enabled
        if (!enabled && carouselOn) { flickAnim?.cancel(); carouselOn = false }
        spaceLanguage = language
        invalidateSpace()
    }

    /** Bề rộng phím chữ (dp) — thước ngưỡng flick. */
    private fun flickKeyWidthDp(): Float =
        (keys.firstOrNull { it.kind == KeyKind.LETTER || it.kind == KeyKind.CHAR }?.width ?: (width / 10f)) / d

    private fun moveFlick(dx: Float, dy: Float) {
        val q = SpaceFlick.progress(dx / d, dy / d, SystemClock.uptimeMillis() - flickDownT,
            SpaceFlick.previewSpan(flickKeyWidthDp()))
        if (q == 0f) { if (carouselOn && flickAnim == null) retractCarousel(); return }
        if (!carouselOn || flickAnim != null) { flickAnim?.cancel(); flickAnim = null; carouselOn = true; carouselFrom = spaceLanguage }
        setCarousel(q)
    }

    private fun setCarousel(q: Float) {
        carQ = q; carCurA = 0.6f * (1 - abs(q)); carNextA = 0.6f * abs(q)
        invalidateSpace()
    }

    private fun endFlick(k: LaidKey, dx: Float, dy: Float, t: Long, cancelled: Boolean) {
        val dir = if (cancelled || !commits.isArmed(k) || plane == Plane.EMOJI_SEARCH) null
            else SpaceFlick.classify(dx / d, dy / d, t - flickDownT, flickKeyWidthDp())
        if (dir == null) { if (carouselOn) retractCarousel(); return }
        commits.disarm(k)                 // flick không ra dấu cách
        feedback.tick(this)
        if (!carouselOn) { carouselOn = true; carouselFrom = spaceLanguage; setCarousel(if (dir == SpaceFlick.Direction.LEFT) -0.2f else 0.2f) }
        listener?.onSpaceFlick()
        // nhãn mới vào giữa, sáng một nhịp (~0,5 s) rồi mờ — như HeliBoard
        val q0 = carQ; val n0 = carNextA; val c0 = carCurA
        val target = if (dir == SpaceFlick.Direction.LEFT) -1f else 1f
        val slide = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = 180; interpolator = DecelerateInterpolator()
            addUpdateListener { val f = it.animatedValue as Float
                carQ = q0 + (target - q0) * f; carNextA = n0 + (1 - n0) * f; carCurA = c0 * (1 - f); invalidateSpace() }
        }
        val fade = ValueAnimator.ofFloat(1f, 0f).apply {
            startDelay = 500; duration = 300
            addUpdateListener { carNextA = it.animatedValue as Float; invalidateSpace() }
        }
        runCarousel(android.animation.AnimatorSet().apply { playSequentially(slide, fade) })
    }

    private fun retractCarousel() {
        val q0 = carQ; val n0 = carNextA; val c0 = carCurA
        runCarousel(ValueAnimator.ofFloat(1f, 0f).apply {
            duration = 150
            addUpdateListener { val f = it.animatedValue as Float
                carQ = q0 * f; carNextA = n0 * f; carCurA = c0 * f; invalidateSpace() }
        })
    }

    private fun runCarousel(a: android.animation.Animator) {
        flickAnim?.cancel()
        flickAnim = a
        a.addListener(object : android.animation.AnimatorListenerAdapter() {
            private var canceled = false
            override fun onAnimationCancel(animation: android.animation.Animator) { canceled = true }
            override fun onAnimationEnd(animation: android.animation.Animator) {
                if (flickAnim === a) flickAnim = null
                if (!canceled) { carouselOn = false; invalidateSpace() }
            }
        })
        a.start()
    }

    /** q ∈ [-1, 1]: nhãn hiện tại lệch q·W/2 theo ngón, nhãn kia theo sau một nửa bề ngang. */
    private fun drawCarousel(c: Canvas, k: LaidKey, contentAlpha: Int) {
        val w = k.width
        val off = carQ * w / 2
        val y = k.centerY + flickOff
        c.save()
        c.clipRect(k.left, k.top, k.right, k.bottom)
        flickPaint.alpha = (carCurA * contentAlpha).toInt()
        if (flickPaint.alpha > 0) c.drawText(carouselFrom.displayName, k.centerX + off, y, flickPaint)
        flickPaint.alpha = (carNextA * contentAlpha).toInt()
        if (flickPaint.alpha > 0)
            c.drawText(carouselFrom.toggled.displayName, k.centerX + off - (if (carQ < 0) -1 else 1) * w / 2, y, flickPaint)
        c.restore()
    }

    private fun drawLabel(c: Canvas, s: String, cx: Float, cy: Float, p: Paint, off: Float, alpha: Int) {
        p.alpha = alpha
        c.drawText(s, cx, cy + off, p)
    }

    private fun icon(c: Canvas, id: Int, cx: Float, cy: Float, sizeDp: Float, color: Int, alpha: Int) {
        iconPaint.color = color
        iconPaint.alpha = (android.graphics.Color.alpha(color) * alpha) / 255
        ImeIcons.draw(c, id, cx, cy, sizeDp * d, iconPaint)
    }

    // MARK: touch

    @SuppressLint("ClickableViewAccessibility")
    override fun onTouchEvent(e: MotionEvent): Boolean {
        if (plane == Plane.EMOJI) emojiPane.track(e) else if (plane == Plane.TEMPLATES) templatesPane.track(e)
        when (e.actionMasked) {
            MotionEvent.ACTION_DOWN, MotionEvent.ACTION_POINTER_DOWN -> {
                val i = e.actionIndex
                down(e.getPointerId(i), e.getX(i), e.getY(i), e)
            }
            MotionEvent.ACTION_MOVE -> for (i in 0 until e.pointerCount) {
                val pid = e.getPointerId(i)
                if (pid == altPid) altMove(e.getX(i), e.getY(i))
                if (pid == swipePid) swipeMove(e, i) else move(pid, e.getX(i), e.getY(i))
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_POINTER_UP -> {
                val i = e.actionIndex
                up(e.getPointerId(i), e.getX(i), e.getY(i), cancelled = false, t = e.eventTime)
            }
            MotionEvent.ACTION_CANCEL -> for (i in 0 until e.pointerCount)
                up(e.getPointerId(i), e.getX(i), e.getY(i), cancelled = true)
        }
        return true
    }

    private fun down(pid: Int, x: Float, y: Float, e: MotionEvent) {
        if (pid !in 0 until MAX_PTR) return
        // Đang vuốt: ngón khác bỏ qua (không gõ chữ lạc); đang chờ phân loại: khoá là chạm.
        if (swiping) return
        if (swipePid >= 0 && pid != swipePid) { classifier.pointerAdded(); stopSwipeTracking() }
        settleAlt()                       // ký tự phụ đang giữ chốt TRƯỚC phím mới
        settlePopover()                   // popup đang mở chốt ô đang chọn TRƯỚC phím mới
        ptrDownX[pid] = x; ptrDownY[pid] = y
        if (plane == Plane.EMOJI) { commits.flush(); ptrPane[pid] = true; emojiPane.down(pid, x, y); return }
        if (plane == Plane.TEMPLATES && templatesPane.contains(x, y)) {
            commits.flush(); ptrPane[pid] = true; templatesPane.down(pid, x, y); return
        }
        if (plane == Plane.EMOJI_SEARCH && searchBar.contains(y)) {
            commits.flush(); ptrPane[pid] = true; searchBar.down(pid, x); return
        }
        if (railSpan != null && railPtr < 0) {
            val b = OneHand.railButton(width.toFloat(), keyAreaPx, oneHand, x, y)
            if (b >= 0) {
                commits.flush()
                feedback.click(Feedback.MODIFIER, this)
                railPtr = pid; railPressed = b; invalidate()
                return
            }
        }
        val hit = KeyLayout.hit(keys, plane, x, y, TouchGeometry.yOffset * d, d, e.eventTime - lastLetterDownT)
        cancelCommaHold()                 // ngón khác chạm ⇒ "," đang giữ là gõ thường
        if (TouchLog.enabled) {
            val lag = (SystemClock.uptimeMillis() - e.eventTime).toDouble()
            TouchLog.touchBegan(activeCount(), e.pointerCount, lag, hit != null, (y / d).toDouble(),
                hit?.let { if (it.kind == KeyKind.LETTER) it.label else null })
        }
        if (hit == null) return
        // ĐẦU TIÊN: chốt các phím nhấc-mới-chốt đang đè (thứ tự khi gõ chồng ngón).
        commits.flush(hit)
        // Chọn phím theo ngữ cảnh (thử nghiệm) — SAU flush để prior thấy từ đang gõ mới nhất.
        val prior = if (hit.kind == KeyKind.LETTER && plane == Plane.LETTERS) letterPrior?.invoke() else null
        val k = if (prior != null) SmartTouch.refine(keys, hit, x, y - TouchGeometry.yOffset * d, prior) else hit
        ptrKey[pid] = k
        when (k.kind) {
            KeyKind.LETTER -> {
                feedback.click(Feedback.LETTER, this)
                if (keyPreview) showBalloon(k, if (shift == Shift.OFF) k.label else k.upper)
                val ch = (if (shift == Shift.OFF) k.label else k.upper)[0]
                val shiftWas = shift
                if (plane == Plane.LETTERS) listener?.onLetterTouch(
                    (x - (k.left + k.right) / 2) / (k.right - k.left),
                    (y - TouchGeometry.yOffset * d - (k.top + k.bottom) / 2) / (k.bottom - k.top))
                emit(Key.Letter(ch))
                if (shift == Shift.ON) { shift = Shift.OFF; invalidate() }
                val since = e.eventTime - lastLetterDownT
                lastLetterDownT = e.eventTime
                if (swipeTyping && plane == Plane.LETTERS && activeCount() == 1)
                    startSwipeTracking(pid, k, x, y, e.eventTime, since, shiftWas)
                if (alts.isNotEmpty()) armAlt(pid, k, x, y, shiftWas)
            }
            KeyKind.CHAR -> {
                feedback.click(Feedback.LETTER, this)
                if (keyPreview) showBalloon(k, k.label)
                commits.arm(k, textFire(k.insert))
                armPopover(pid, k, x, y)
            }
            KeyKind.PAD -> {
                feedback.click(Feedback.LETTER, this)
                press(k)
                commits.arm(k, textFire(k.insert))
            }
            KeyKind.PUNCT -> {
                feedback.click(Feedback.LETTER, this)
                press(k)
                commits.arm(k, textFire(k.insert))
                if (isVoiceComma(k)) {
                    commaPtr = pid; commaKey = k
                    postDelayed(voiceLongRun, GLOBE_HOLD_MS)
                } else if (isPeriodComma(k)) {
                    commaPtr = pid; commaKey = k; periodFired = false
                    postDelayed(periodRun, KeyAlternates.HOLD_MS)
                } else armPopover(pid, k, x, y)
            }
            KeyKind.SPACE -> {
                feedback.click(Feedback.SPACE, this)
                press(k)
                commits.arm(k, spaceFire)
                spacePtr = pid
                flickDownT = e.eventTime
                removeCallbacks(spaceHoldRun)
                postDelayed(spaceHoldRun, SPACE_HOLD_MS)
            }
            KeyKind.RETURN -> {
                feedback.click(Feedback.RETURN, this)
                press(k)
                commits.arm(k, newlineFire)
                if (holdNewline) {
                    returnPtr = pid
                    removeCallbacks(returnHoldRun)
                    postDelayed(returnHoldRun, RETURN_HOLD_MS)
                }
            }
            KeyKind.SHIFT -> {
                feedback.click(Feedback.MODIFIER, this)
                val now = SystemClock.uptimeMillis()
                shift = if (now - lastShiftTap < SHIFT_DOUBLE_MS) Shift.CAPS
                        else if (shift == Shift.OFF) Shift.ON else Shift.OFF
                lastShiftTap = now
                k.pressed = true
                invalidate()   // mọi nhãn chữ đổi hoa/thường
            }
            KeyKind.BACKSPACE -> {
                feedback.click(Feedback.DELETE, this)
                press(k)
                emit(Key.Backspace)
                bsPtr = pid; bsRepeating = false
                bsSwipe = 0; bsSwipeAsked = 0; bsSwipeWords = 0
                removeCallbacks(bsStartRun); removeCallbacks(bsTickRun)
                postDelayed(bsStartRun, BS_HOLD_MS)
            }
            KeyKind.EDIT -> {
                feedback.click(Feedback.MODIFIER, this)
                press(k)
                val a = EditAction.of(k.insert)
                // Mũi tên / xoá: chạy NGAY lúc chạm (như ⌫), giữ thì lặp; ô khác chạy lúc nhấc.
                if (a != null && a.repeats) {
                    fireEdit(k)
                    editPtr = pid; editRepeatKey = k
                    removeCallbacks(editRepeatRun)
                    postDelayed(editRepeatRun, EDIT_HOLD_MS)
                }
            }
            KeyKind.GLOBE, KeyKind.EMOJI -> {
                // 😊: bấm = plane emoji (lúc nhấc), giữ lâu = danh sách bàn phím (thay phím 🌐).
                feedback.click(Feedback.MODIFIER, this)
                press(k)
                globePtr = pid; globeFired = false
                removeCallbacks(globeLongRun); removeCallbacks(emojiMenuRun)
                // 😊 + popup bật: giữ = menu (🌐 🎤 ✋ ⚙); 🌐 thật / TalkBack: danh sách bàn phím như cũ.
                if (k.kind == KeyKind.EMOJI && popoversEnabled) { menuX = x; menuY = y; postDelayed(emojiMenuRun, KeyAlternates.HOLD_MS) }
                else postDelayed(globeLongRun, GLOBE_HOLD_MS)
            }
            else -> {   // PLANE, MORE, EMOJI, CLEAR, DISMISS: hành động lúc nhấc
                feedback.click(Feedback.MODIFIER, this)
                press(k)
            }
        }
    }

    private fun move(pid: Int, x: Float, y: Float) {
        if (pid !in 0 until MAX_PTR) return
        if (ptrPane[pid]) {
            when (plane) {
                Plane.EMOJI -> emojiPane.move(pid, x, y)
                Plane.EMOJI_SEARCH -> searchBar.move(pid, x)
                else -> templatesPane.move(pid, x, y)
            }
            return
        }
        if (pid == popPid) popoverMove(x, y)
        if (pid == globePtr) { menuX = x; menuY = y; emojiMenuMove(x, y) }
        val k = ptrKey[pid] ?: return
        val movedFar = abs(x - ptrDownX[pid]) > slop || abs(y - ptrDownY[pid]) > slop
        when {
            k.kind == KeyKind.SPACE && pid == spacePtr -> {
                if (trackpad) {
                    // dp: cùng ngưỡng với iOS (pt). Trục/tăng tốc: TrackpadGesture.
                    trackpadGesture.move(x / d, y / d, SystemClock.uptimeMillis())?.let {
                        trackpadBatch.add(it)?.let { prev -> sendTrackpadStep(prev) }
                        if (!trackpadFramePosted) {
                            trackpadFramePosted = true
                            Choreographer.getInstance().postFrameCallback(trackpadFrame)
                        }
                    }
                } else {
                    if (movedFar) removeCallbacks(spaceHoldRun)
                    if (spaceFlickEnabled && plane != Plane.EMOJI_SEARCH) moveFlick(x - ptrDownX[pid], y - ptrDownY[pid])
                }
            }
            k.kind == KeyKind.BACKSPACE && pid == bsPtr -> moveBackspace(k, x - ptrDownX[pid], y - ptrDownY[pid], movedFar)
            pid == commaPtr && movedFar && !periodFired -> cancelCommaHold()   // đã ra "." thì trôi không huỷ
        }
    }

    private fun up(pid: Int, x: Float, y: Float, cancelled: Boolean, t: Long = SystemClock.uptimeMillis()) {
        if (pid !in 0 until MAX_PTR) return
        if (ptrPane[pid]) {
            ptrPane[pid] = false
            if (plane == Plane.EMOJI) emojiPane.up(pid, x, y, cancelled)
            else if (plane == Plane.TEMPLATES) templatesPane.up(pid, x, y, cancelled)
            else if (plane == Plane.EMOJI_SEARCH) searchBar.up(pid, x, cancelled)
            return
        }
        if (pid == railPtr) {
            val b = railPressed
            railPtr = -1; railPressed = -1; invalidate()
            if (!cancelled && OneHand.railButton(width.toFloat(), keyAreaPx, oneHand, x, y) == b) {
                listener?.onOneHandChange(if (b == 0) OneHand.switched(oneHand) else OneHandSide.OFF)
            }
            return
        }
        if (pid == swipePid) {
            val wasSwiping = swiping
            stopSwipeTracking()
            if (wasSwiping) { finishSwipe(pid, x, y, t, cancelled); return }
        }
        val k = ptrKey[pid] ?: run { if (TouchLog.enabled) TouchLog.touchEnded(cancelled, false); return }
        ptrKey[pid] = null
        if (TouchLog.enabled) TouchLog.touchEnded(cancelled, true)
        when (k.kind) {
            KeyKind.LETTER -> {
                hideBalloon(k)
                if (pid == altPid) {
                    val alt = altHold?.commit
                    dropAlt()
                    if (alt != null) commitAlt(alt, k)   // cancel vẫn chốt như chữ thường
                }
            }
            KeyKind.CHAR -> {
                hideBalloon(k); commits.release(k)   // popup đã mở ⇒ chèn ô đang chọn
                if (pid == popPid) dropPopover()
            }
            KeyKind.PUNCT, KeyKind.PAD -> {
                if (pid == commaPtr) cancelCommaHold()
                commits.release(k)        // giữ lâu giọng nói ⇒ disarm rồi, không chèn gì; giữ ra "." ⇒ chèn "."
                if (pid == popPid) dropPopover()
            }
            KeyKind.RETURN -> {
                if (pid == returnPtr) { removeCallbacks(returnHoldRun); returnPtr = -1; hideBalloon(k) }
                commits.release(k)        // đã giữ lâu ⇒ đã disarm, không có gì để chốt
            }
            KeyKind.SPACE -> {
                if (pid == spacePtr) {
                    removeCallbacks(spaceHoldRun); spacePtr = -1
                    if (spaceFlickEnabled && !trackpad) endFlick(k, x - ptrDownX[pid], y - ptrDownY[pid], t, cancelled)
                    // Cancel VẪN chốt (KeyCommitQueue); trackpad đã disarm nên không có space.
                    commits.release(k)
                    if (trackpad) endTrackpad()
                } else commits.release(k)
            }
            KeyKind.BACKSPACE -> if (pid == bsPtr) {
                removeCallbacks(bsStartRun); removeCallbacks(bsTickRun)
                bsPtr = -1; bsRepeating = false
                endSwipe(commit = !cancelled)
            }
            KeyKind.GLOBE -> if (pid == globePtr) {
                removeCallbacks(globeLongRun); globePtr = -1
                if (!globeFired && !cancelled) listener?.onGlobe(false)
            }
            KeyKind.EMOJI -> if (pid == globePtr) {
                removeCallbacks(globeLongRun); removeCallbacks(emojiMenuRun); globePtr = -1
                val menu = menuHold
                if (menu != null) {
                    val a = menu.selection?.let { menuActions.getOrNull(it) }
                    dropEmojiMenu()
                    k.pressed = false; invalidateKey(k)
                    if (a != null && !cancelled) runMenuAction(a)
                } else if (!globeFired && !cancelled) controlAction(k)
            }
            KeyKind.SHIFT -> Unit
            KeyKind.EDIT -> if (pid == editPtr) {
                removeCallbacks(editRepeatRun); editPtr = -1; editRepeatKey = null
            } else if (!cancelled) fireEdit(k)
            else -> if (!cancelled) controlAction(k)
        }
        if (k.pressed) { k.pressed = false; if (k.kind == KeyKind.SHIFT) invalidate() else invalidateKey(k) }
    }

    // MARK: vuốt ⌫ xoá theo từ (kiểu Gboard)

    /** Bước kéo = bề rộng một phím chữ (plane số/ký hiệu: phím CHAR). */
    private fun swipeStepPx(): Float =
        maxOf(theme.dp(24f), keys.firstOrNull { it.kind == KeyKind.LETTER || it.kind == KeyKind.CHAR }?.width ?: theme.dp(32f))

    private fun moveBackspace(k: LaidKey, dx: Float, dy: Float, movedFar: Boolean) {
        if (bsRepeating || plane == Plane.EMOJI_SEARCH) return   // giữ-lặp / ô tìm: không vuốt xoá từ
        if (movedFar) removeCallbacks(bsStartRun)
        val step = swipeStepPx()
        val act = SwipeDelete.activatePx(step, theme.dp(16f))
        if (bsSwipe == 0 && SwipeDelete.activates(dx, dy, act)) {
            bsSwipe = if (listener?.onSwipeDeleteStart() == true) 1 else -1
        }
        if (bsSwipe != 1) return
        val want = SwipeDelete.words(-dx, act, step)
        if (want == bsSwipeAsked) return
        bsSwipeAsked = want
        val got = listener?.onSwipeDeleteUpdate(want) ?: 0
        if (got != bsSwipeWords) {
            bsSwipeWords = got
            feedback.tick(this)
            invalidateKey(k)
        }
    }

    private fun endSwipe(commit: Boolean) {
        val was = bsSwipe
        bsSwipe = 0; bsSwipeAsked = 0; bsSwipeWords = 0
        if (was == 1) listener?.onSwipeDeleteEnd(commit)
    }

    private fun controlAction(k: LaidKey) {
        when (k.kind) {
            KeyKind.PLANE -> setPlane(if (plane == Plane.LETTERS || plane == Plane.EMOJI_SEARCH) Plane.NUMBERS
                                      else inputKind.padPlane ?: Plane.LETTERS)
            KeyKind.MORE -> setPlane(if (plane == Plane.NUMBERS) Plane.SYMBOLS else Plane.NUMBERS)
            KeyKind.EMOJI -> setPlane(Plane.EMOJI)
            KeyKind.CLEAR -> emit(Key.ClearField)
            KeyKind.DISMISS -> listener?.onDismissKeyboard()
        }
    }

    private fun press(k: LaidKey) { k.pressed = true; invalidateKey(k) }

    private fun activeCount(): Int { var n = 0; for (k in ptrKey) if (k != null) n++; return n }

    private fun cancelAllTouches() {
        abortSwipe()
        dropAlt()
        // Bàn phím ẩn / đổi một tay giữa lúc popup mở: không chèn đuôi đang chọn (flush dưới).
        popKey?.let { if (popHold?.fired == true) commits.disarm(it) }
        dropPopover()
        dropEmojiMenu()
        for (i in 0 until MAX_PTR) {
            ptrKey[i]?.pressed = false
            ptrKey[i] = null; ptrPane[i] = false
        }
        commits.flush()
        endSwipe(commit = false)
        removeCallbacks(spaceHoldRun); removeCallbacks(bsStartRun); removeCallbacks(bsTickRun)
        removeCallbacks(globeLongRun); removeCallbacks(emojiMenuRun); removeCallbacks(returnHoldRun); removeCallbacks(editRepeatRun)
        cancelCommaHold()
        spacePtr = -1; bsPtr = -1; globePtr = -1; returnPtr = -1; bsRepeating = false
        editPtr = -1; editRepeatKey = null; railPtr = -1; railPressed = -1
        if (trackpad) endTrackpad()
        balloon.hide(); balloonOwner = null
        invalidate()
    }

    // MARK: gõ vuốt

    /** Tâm phím chữ a–z (plane chữ) → decoder; bước phím = khoảng cách tâm q→w. */
    private fun publishSwipeLayout() {
        if (!swipeTyping || plane != Plane.LETTERS || keys.isEmpty()) return
        val m = KeyLayout.letterCenters(keys)
        val q = m['q'] ?: return
        val w = m['w'] ?: return
        val kw = w.first - q.first
        if (kw <= 0f) return
        val l = SwipeLayout(kw, m)
        if (l == swipeLayout) return
        abortSwipe()
        swipeLayout = l
        swipePath = SwipePath(minDistance = kw / 5f)
        listener?.onSwipeLayout(l)
    }

    private fun startSwipeTracking(pid: Int, k: LaidKey, x: Float, y: Float, t: Long, since: Long, shiftWas: Shift) {
        val l = swipeLayout ?: return
        val p = swipePath ?: return
        classifier.begin(x / d, y / d, t, k.left / d, k.top / d, k.right / d, k.bottom / d, l.keyWidth / d, since)
        p.reset()
        p.add(x, y - yOffPx, t / 1000.0)
        swipePid = pid; swipeKey = k; swipeShift = shiftWas
    }

    private fun stopSwipeTracking() {
        classifier.end()
        swipePid = -1
        swiping = false
        swipeKey = null
    }

    /** ACTION_MOVE của ngón đang theo dõi: duyệt cả điểm lịch sử (vuốt nhanh gộp nhiều mẫu/khung). */
    private fun swipeMove(e: MotionEvent, i: Int) {
        for (h in 0 until e.historySize) {
            swipePoint(e.getHistoricalX(i, h), e.getHistoricalY(i, h), e.getHistoricalEventTime(h))
            if (swipePid < 0) return
        }
        swipePoint(e.getX(i), e.getY(i), e.eventTime)
    }

    private fun swipePoint(x: Float, y: Float, t: Long) {
        val p = swipePath ?: return
        p.add(x, y - yOffPx, t / 1000.0)
        if (swiping) { trail?.add(x, y, t); return }
        when (classifier.move(x / d, y / d, t)) {
            GestureClassifier.State.SWIPE -> beginSwipe(p)
            GestureClassifier.State.TAP -> stopSwipeTracking()
            else -> Unit
        }
    }

    private fun beginSwipe(p: SwipePath) {
        if (listener?.onSwipeTypingStart() != true) { stopSwipeTracking(); return }
        swiping = true
        dropAlt()
        swipeKey?.let { hideBalloon(it) }
        // Chữ đầu đã huỷ ⇒ shift một-lần bị nhả lúc chạm phải bật lại (từ vuốt viết hoa).
        if (swipeShift == Shift.ON && shift == Shift.OFF) { shift = Shift.ON; invalidate() }
        val tr = trail ?: return
        tr.begin()
        for (j in 0 until p.count) tr.add(p.xs[j], p.ys[j] + yOffPx, (p.ts[j] * 1000).toLong())
    }

    private fun finishSwipe(pid: Int, x: Float, y: Float, t: Long, cancelled: Boolean) {
        ptrKey[pid]?.let { hideBalloon(it) }
        ptrKey[pid] = null
        val p = swipePath
        if (cancelled || p == null) {
            trail?.end(fade = false)
            listener?.onSwipeTypingCancel()
            return
        }
        p.add(x, y - yOffPx, t / 1000.0, force = true)
        trail?.end(fade = true)
        val case = when (shift) {
            Shift.CAPS -> SwipeSuggest.Case.ALL
            Shift.ON -> SwipeSuggest.Case.FIRST
            Shift.OFF -> SwipeSuggest.Case.LOWER
        }
        listener?.onSwipeTypingEnd(p, case)
        if (shift == Shift.ON) { shift = Shift.OFF; invalidate() }
    }

    /** Bỏ lượt vuốt đang dở (ẩn bàn phím / đổi layout / tắt tính năng). */
    private fun abortSwipe() {
        val was = swiping
        val pid = swipePid
        stopSwipeTracking()
        if (!was) return
        if (pid in 0 until MAX_PTR) { ptrKey[pid]?.let { hideBalloon(it) }; ptrKey[pid] = null }
        trail?.end(fade = false)
        listener?.onSwipeTypingCancel()
    }

    // MARK: giữ phím ra ký tự phụ

    /** Chạm phím có ký tự phụ: hẹn giờ [KeyAlternates.HOLD_MS]; chữ đã chèn lúc chạm. */
    private fun armAlt(pid: Int, k: LaidKey, x: Float, y: Float, shiftWas: Shift) {
        val alt = alts[k.label[0]] ?: return
        altHold = KeyAlternates.Hold(alt, x / d, y / d)
        altPid = pid; altKey = k; altShiftWas = shiftWas
        removeCallbacks(altRun)
        postDelayed(altRun, KeyAlternates.HOLD_MS)
    }

    private fun altMove(x: Float, y: Float) {
        if (altHold?.move(x / d, y / d) == true) dropAlt()
    }

    /** Hết giờ, ngón chưa trôi / chưa thành vuốt ⇒ balloon hiện ký tự phụ (kể cả khi tắt phóng to chữ). */
    private fun fireAlt() {
        val h = altHold ?: return
        val k = altKey ?: return
        if (swiping || !h.fire()) return
        if (swipePid == altPid) stopSwipeTracking()   // đã là giữ: trôi sau đó không thành vuốt
        feedback.longPress(this)
        showBalloon(k, h.alt)
    }

    /** Ngón mới chạm: giữ chưa đủ giờ ⇒ chỉ là chạm; đã bắn ⇒ chốt NGAY (checkpoint đúng phím). */
    private fun settleAlt() {
        val h = altHold ?: return
        val k = altKey
        dropAlt()
        val alt = h.commit ?: return
        if (k != null) { hideBalloon(k); commitAlt(alt, k) }
    }

    private fun dropAlt() {
        if (altHold == null) return
        removeCallbacks(altRun)
        altHold = null; altPid = -1; altKey = null
    }

    private fun commitAlt(alt: String, k: LaidKey) {
        hideBalloon(k)
        if (altShiftWas == Shift.ON && shift == Shift.OFF) { shift = Shift.ON; invalidate() }
        emit(Key.Text(alt, replacesLetter = true))
    }

    // MARK: popup nhiều lựa chọn (DomainPopup / KeyVariants)

    /** Lựa chọn của phím [k] trên plane hiện tại; rỗng ⇒ không hẹn giờ (0 chi phí). */
    private fun popoverChoices(k: LaidKey): List<String> {
        if (!popoversEnabled) return emptyList()
        return when (plane) {
            Plane.LETTERS -> if (k.kind != KeyKind.PUNCT) emptyList() else DomainPopup.choices(
                when (inputKind) {
                    InputKind.URL -> DomainPopup.Field.URL
                    InputKind.EMAIL -> DomainPopup.Field.EMAIL
                    else -> DomainPopup.Field.NORMAL
                }, k.label, lettersPlane = true).ifEmpty { CommaPopup.choices(k.label, lettersPlane = true) }
            Plane.NUMBERS, Plane.SYMBOLS -> KeyVariants.variants(k.label, symbolPlane = true,
                numericField = inputKind.padPlane != null)
            else -> emptyList()
        }
    }

    /** Chạm phím có popup (đã arm ký tự gốc): hẹn giờ như giữ phím chữ. */
    private fun armPopover(pid: Int, k: LaidKey, x: Float, y: Float) {
        val choices = popoverChoices(k)
        if (choices.isEmpty()) return
        dropPopover()
        popHold = DomainPopup.Hold(choices)
        popPid = pid; popKey = k; popX = x; popY = y
        popVariants = plane != Plane.LETTERS || k.label == ","     // ô hẹp, chữ lớn như biến thể ký tự
        postDelayed(popRun, KeyAlternates.HOLD_MS)
    }

    /** Hết giờ: phím còn chờ chốt ⇒ mở popup (ô gốc chọn sẵn), nhấc/ngón khác chạm chèn ô đang chọn. */
    private fun firePopover() {
        val h = popHold ?: return
        val k = popKey ?: return
        val n = h.choices.size
        val wDp = width / d
        // "," bàn chữ: 10 ô ⇒ ô hẹp hơn để hàng loe từ phím (cạnh phải space) sang trái gọn.
        val comma = plane == Plane.LETTERS && k.label == ","
        val itemW = minOf(if (comma) CommaPopup.itemWidthDp(theme.tablet)
            else if (popVariants) (if (theme.tablet) 56f else 38f) else (if (theme.tablet) 68f else 56f),
            (wDp - 4f) / n)
        val l = DomainPopup.layout(k.centerX / d, itemW, n, wDp)
        // Toạ độ dp theo overlay (strip + phím): popup được phép lấn lên strip, kẹp ở 0.
        val off = top / d
        val panelH = if (theme.tablet) 52f else 46f
        val popTop = maxOf((k.top / d + off) - 8f - panelH, 0f)
        val ok = h.fire(commits, k, l, popTop, k.bottom / d + off, popX / d, popY / d + off) { s -> emit(Key.Text(s)) }
        if (!ok) { dropPopover(); return }
        hideBalloon(k)
        val inset = 4f
        balloon.showPopup((l.originX - inset) * d, popTop * d, (l.originX + l.width + inset) * d, (popTop + panelH) * d,
            FloatArray(n) { l.slotMinX(it) * d }, itemW * d, h.choices,
            if (popVariants) (if (theme.tablet) 26f else 24f) else (if (theme.tablet) 20f else 18f),
            h.selection ?: -1)
        feedback.tick(this)
    }

    private fun popoverMove(x: Float, y: Float) {
        popX = x; popY = y
        val h = popHold ?: return
        if (!h.fired || !h.move(x / d, y / d + top / d)) return
        balloon.selectPopup(h.selection ?: -1)
        if (h.selection != null) feedback.tick(this)
    }

    /** Ngón khác chạm: chưa đủ giờ ⇒ chỉ là chạm (ký tự gốc chốt bởi flush); đã mở ⇒ chốt ô đang chọn NGAY. */
    private fun settlePopover() {
        val h = popHold ?: return
        val k = popKey
        if (h.fired && k != null) commits.release(k)
        dropPopover()
    }

    private fun dropPopover() {
        if (popHold == null) return
        removeCallbacks(popRun)
        if (popHold?.fired == true) balloon.hidePopup()
        popHold = null; popPid = -1; popKey = null
    }

    // MARK: menu giữ 😊 (EmojiKeyMenu) — cùng hàng ô DomainPopup, ô là icon, chạy lúc nhấc

    private var menuHold: DomainPopup.Hold? = null
    private var menuActions: List<EmojiKeyAction> = emptyList()
    private var menuX = 0f
    private var menuY = 0f
    private val emojiMenuRun = Runnable { openEmojiMenu() }

    private fun menuIcon(a: EmojiKeyAction): Int = when (a) {
        EmojiKeyAction.SWITCH_KEYBOARD -> ImeIcons.GLOBE
        EmojiKeyAction.VOICE -> ImeIcons.MIC
        // Đang một tay ⇒ mục là "thoát" (icon ↔ đầy bề ngang như rail).
        EmojiKeyAction.ONE_HAND -> if (oneHand != OneHandSide.OFF) ImeIcons.EXPAND else ImeIcons.ONE_HAND
        EmojiKeyAction.FLOATING -> if (floatingOn) ImeIcons.DOCK else ImeIcons.FLOAT
        EmojiKeyAction.SETTINGS -> ImeIcons.SETTINGS
    }

    /** Bàn phím đang thả nổi (IME đặt) — menu giữ 😊: 🪟 thành "gắn lại", ẩn ✋ một tay. */
    var floatingOn = false

    private fun openEmojiMenu() {
        val k = ptrKey.getOrNull(globePtr)?.takeIf { it.kind == KeyKind.EMOJI } ?: return
        val acts = EmojiKeyMenu.actions(voiceAvailable, oneHandAvailable = !theme.tablet && !floatingOn,
            floatingAvailable = true)
        val h = DomainPopup.Hold(acts.map { EmojiKeyMenu.label(it, oneHand != OneHandSide.OFF, floatingOn) })
        val n = acts.size
        val wDp = width / d
        val itemW = minOf(if (theme.tablet) 56f else 48f, (wDp - 4f) / n)
        val l = DomainPopup.layout(k.centerX / d, itemW, n, wDp)
        val off = top / d
        val panelH = if (theme.tablet) 52f else 46f
        val popTop = maxOf((k.top / d + off) - 8f - panelH, 0f)
        if (!h.open(l, popTop, k.bottom / d + off, menuX / d, menuY / d + off)) return
        globeFired = true                 // nhấc không mở plane emoji
        menuHold = h; menuActions = acts
        val inset = 4f
        balloon.showPopup((l.originX - inset) * d, popTop * d, (l.originX + l.width + inset) * d, (popTop + panelH) * d,
            FloatArray(n) { l.slotMinX(it) * d }, itemW * d, h.choices, 18f, h.selection ?: -1,
            icons = IntArray(n) { menuIcon(acts[it]) })
        feedback.longPress(this)
    }

    private fun emojiMenuMove(x: Float, y: Float) {
        val h = menuHold ?: return
        if (!h.move(x / d, y / d + top / d)) return
        balloon.selectPopup(h.selection ?: -1)
        if (h.selection != null) feedback.tick(this)
    }

    private fun dropEmojiMenu() {
        removeCallbacks(emojiMenuRun)
        if (menuHold == null) return
        balloon.hidePopup()
        menuHold = null; menuActions = emptyList()
    }

    private fun runMenuAction(a: EmojiKeyAction) {
        feedback.click(Feedback.MODIFIER, this)
        when (a) {
            EmojiKeyAction.SWITCH_KEYBOARD -> listener?.onGlobe(true)
            EmojiKeyAction.VOICE -> listener?.onVoiceInput()
            EmojiKeyAction.ONE_HAND -> listener?.onToggleOneHand()
            EmojiKeyAction.FLOATING -> listener?.onToggleFloating()
            EmojiKeyAction.SETTINGS -> listener?.onOpenSettings()
        }
    }

    /** Test/debug: menu giữ 😊 đang mở + mục chọn. */
    internal val emojiMenuState: Pair<Boolean, EmojiKeyAction?> get() =
        (menuHold != null) to menuHold?.selection?.let { menuActions.getOrNull(it) }

    /** Test/debug: popup đang hiện + ô chọn. */
    internal val popoverState: Pair<Boolean, String?> get() = balloon.popupVisible to popHold?.chosen

    // MARK: trackpad

    private fun beginTrackpad() {
        val k = spaceKey ?: return
        if (spacePtr < 0) return
        trackpad = true
        if (carouselOn) { flickAnim?.cancel(); carouselOn = false }
        trackpadBatch.clear()
        trackpadGesture.begin(lastX[spacePtr] / d, lastY[spacePtr] / d, SystemClock.uptimeMillis())
        balloon.hide(); balloonOwner = null
        // Nhả ra KHÔNG có dấu cách (stock), kể cả khi chưa di con trỏ.
        commits.disarm(k)
        invalidate()
    }

    private var lastX = FloatArray(MAX_PTR)
    private var lastY = FloatArray(MAX_PTR)

    override fun dispatchTouchEvent(e: MotionEvent): Boolean {
        for (i in 0 until e.pointerCount) {
            val id = e.getPointerId(i)
            if (id in 0 until MAX_PTR) { lastX[id] = e.getX(i); lastY[id] = e.getY(i) }
        }
        return super.dispatchTouchEvent(e)
    }

    private fun sendTrackpadStep(s: TrackpadGesture.Step) {
        if (plane == Plane.EMOJI_SEARCH) return
        listener?.onTrackpadMove(s.count, s.axis == TrackpadGesture.Axis.V)
    }

    private fun endTrackpad() {
        trackpad = false
        if (trackpadFramePosted) { Choreographer.getInstance().removeFrameCallback(trackpadFrame); trackpadFramePosted = false }
        trackpadBatch.drain()?.let { sendTrackpadStep(it) }
        listener?.onTrackpadEnd()
        invalidate()
    }

    // MARK: balloon

    private fun showBalloon(k: LaidKey, text: String) {
        balloonOwner = k
        balloon.show(k.left, k.top + top, k.right, k.bottom + top, text)
    }

    private fun hideBalloon(k: LaidKey) {
        if (balloonOwner === k) { balloon.hide(); balloonOwner = null }
    }

    // MARK: pane callbacks

    internal fun paneEmoji(e: String) {
        listener?.noteEmojiUsed(e)
        listener?.onKey(Key.Text(e))
    }
    internal fun paneBackspace() = listener?.onKey(Key.Backspace)
    internal fun paneABC() = setPlane(Plane.LETTERS)
    internal fun paneSearch() = setPlane(Plane.EMOJI_SEARCH)
    internal fun paneKaomoji(s: String) = listener?.onKey(Key.Text(s))
    internal fun paneTemplate(item: TemplateItem) {
        setPlane(Plane.LETTERS)
        listener?.onTemplate(item)
    }
    internal fun paneGear() = listener?.onOpenTemplates()
    internal fun paneExtra(id: String) {
        when (id) {
            TOOLS_ENTRY, TOOLS_BACK -> {
                textToolsMode = id == TOOLS_ENTRY
                templatesPane.resetScroll()
                refreshTemplatesPane()
            }
            else -> {
                val tool = TextTool.byId(id) ?: return
                setPlane(Plane.LETTERS)
                listener?.onTextTool(tool)
            }
        }
    }

    override fun computeScroll() {
        if (plane == Plane.EMOJI) emojiPane.computeScroll()
        else if (plane == Plane.TEMPLATES) templatesPane.computeScroll()
    }

    companion object {
        private const val MAX_PTR = 32
        const val DOUBLE_SPACE_MS = 350L
        const val SHIFT_DOUBLE_MS = 300L
        const val SPACE_HOLD_MS = 300L
        const val BS_HOLD_MS = 500L
        const val BS_INTERVAL = 90L
        const val GLOBE_HOLD_MS = 500L
        const val RETURN_HOLD_MS = 450L
        private const val TOOLS_ENTRY = "\uE000tools"
        private const val TOOLS_BACK = "\uE000back"
        const val EDIT_HOLD_MS = 400L
        const val EDIT_REPEAT_MS = 70L
    }
}
