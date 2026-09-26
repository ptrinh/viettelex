package com.viettelex.keyboard

import kotlin.math.ln

/** Phím gửi vào [KeyboardSession.handle] (≈ KeyboardView.Key iOS). */
sealed class Key {
    /** Phím chữ, đã theo shift. */
    data class Letter(val ch: Char) : Key()
    /** Số / ký hiệu / dấu câu (boundary + ngắt câu). */
    data class Text(val text: String) : Key()
    object Space : Key()
    /** Space thứ 2 trong < 0.35 s (IME đo nhịp). */
    object DoubleSpacePeriod : Key()
    object Newline : Key()
    object Backspace : Key()
    /** Trackpad: session reset; IME tự dời con trỏ [delta] ký tự, hoặc [delta] dòng
     *  khi [vertical] (âm = trái/lên). */
    data class MoveCursor(val delta: Int, val vertical: Boolean = false) : Key()
    /** 🗑 plane mẫu câu: xoá sạch ô (qua [TextProxy.clearAll]). */
    object ClearField : Key()
}

/** Đặc tính ô nhập (từ EditorInfo). */
data class FieldTraits(
    val isSecure: Boolean = false,
    /** Gõ literal, bỏ Telex (spec §12: URI/EMAIL/VISIBLE_PASSWORD/FILTER). */
    val passthrough: Boolean = false,
    /** TYPE_TEXT_FLAG_CAP_SENTENCES — auto-shift đầu câu. */
    val capSentences: Boolean = false,
    /** Ô cho phép thanh gợi ý (không secure, không passthrough, …). */
    val suggestionsAllowed: Boolean = true,
    /** TYPE_TEXT_FLAG_CAP_WORDS — auto-shift đầu mỗi từ (ô tên người, tiêu đề…). */
    val capWords: Boolean = false,
    /** TYPE_TEXT_FLAG_CAP_CHARACTERS — luôn viết hoa (mã, biển số…). */
    val capCharacters: Boolean = false,
    /**
     * EditorInfo.initialCapsMode ≠ 0 — editor tự tính lúc mở ô. Chỉ dùng khi KHÔNG đọc
     * được chữ trước con trỏ (getTextBeforeCursor = null) và chưa gõ phím nào.
     */
    val initialCaps: Boolean = false,
    /**
     * IME_FLAG_NO_PERSONALIZED_LEARNING (Chrome ẩn danh, app nhạy cảm): KHÔNG ghi từ vào
     * UserLangModel. Gợi ý vẫn hiện (chỉ đọc).
     */
    val noLearning: Boolean = false,
    /** EditorInfo.packageName — tra bảng [WriteMode]. */
    val packageName: String? = null,
) {
    /** Cách ghi chữ vào ô theo app (bảng [WriteMode.forPackage]). */
    val writeMode: WriteMode get() = WriteMode.forPackage(packageName)
}

/**
 * Cách lớp ghi (IcProxy) đẩy chữ vào ô — vài editor văn phòng xử lý sai
 * commitText/deleteSurroundingText.
 *
 * IcProxy.writeMode áp bảng này (VietTelexIME.onStartInputView):
 *  - [COMMIT]: commitText + deleteSurroundingTextInCodePoints.
 *  - [DEL_VIA_KEY_EVENT]: commitText nhưng xoá bằng KEYCODE_DEL (ONLYOFFICE bỏ qua deleteSurroundingText).
 *  - [KEY_ONLY]: mọi thứ qua key event (WPS bản Xiaomi/Huawei, HSL).
 */
enum class WriteMode {
    COMMIT, DEL_VIA_KEY_EVENT, KEY_ONLY;

    companion object {
        private val KEY_ONLY_PKGS = listOf("com.huawei.hsl", "cn.wps.huawei")

        fun forPackage(pkg: String?): WriteMode {
            if (pkg.isNullOrEmpty()) return COMMIT
            fun under(base: String) = pkg == base || pkg.startsWith("$base.")
            return when {
                pkg.startsWith("com.xiaomi.wps") || KEY_ONLY_PKGS.any(::under) -> KEY_ONLY
                pkg.startsWith("com.onlyoffice.") -> DEL_VIA_KEY_EVENT
                else -> COMMIT
            }
        }
    }
}

/** Kiểu viết hoa tự động của ô (TYPE_TEXT_FLAG_CAP_*). */
enum class CapMode { NONE, SENTENCES, WORDS, CHARACTERS }

/** Kết quả một phím: IME dùng [generation] để coalesce auto-shift + gợi ý 30 ms. */
data class KeyOutcome(val needsAutoShift: Boolean, val generation: Int)

/** Nội dung thanh gợi ý (≈ KeyboardView.SuggestionSet). */
data class SuggestionSet(
    val literal: String? = null,
    val word: String? = null,
    /** Ứng viên inline thứ hai (khi không có emoji). */
    val word2: String? = null,
    val emojis: List<String> = emptyList(),
    /** Gợi ý khi CHƯA gõ (đầu câu / sau space / email / TLD). */
    val nextWords: List<String> = emptyList(),
    /** Thẻ Dán thay cả bar. */
    val paste: Boolean = false,
    val pasteIsImage: Boolean = false,
) {
    val isEmpty: Boolean get() = literal == null && word == null && word2 == null && emojis.isEmpty() && nextWords.isEmpty()
    /** So để bỏ vẽ lại khi không đổi. */
    fun signature(): String = listOf(literal, word, word2, emojis.joinToString("\u0002"),
        nextWords.joinToString("\u0002"), paste.toString()).joinToString("\u0001")

    companion object {
        /** Payload chạm thẻ Dán → truyền vào acceptSuggestion. */
        const val PASTE_TOKEN = "paste"
        const val PASTE_IMAGE_TOKEN = "pasteImage"
    }
}

sealed class SuggestionPlan {
    /** Vẽ ngay; [set] null = không vẽ gì (bar tắt / thu gọn). */
    data class Ready(val set: SuggestionSet?) : SuggestionPlan()
    /** Chạy [SuggestJob.compute] ở thread nền, rồi [KeyboardSession.completeSuggestions] trên main. */
    class Background(val job: SuggestJob) : SuggestionPlan()
}

/** Phần nặng của gợi ý khi đang gõ dở (VNSuggest + AdjacentKeyFixer) — thread-safe. */
class SuggestJob internal constructor(
    internal val req: Int, internal val gen: Int, internal val bridge: EngineBridge,
    val composed: String, val raw: String, internal val predicted: String, private val wantFix: Boolean,
) {
    class Result(val pool: List<VNSuggest.Match>, val fix: String?)
    fun compute(): Result {
        val pool = VNSuggest.matches(composed, poolLimit = 24, excluding = composed.lowercase())
        val fix = if (pool.isEmpty() && wantFix) AdjacentKeyFixer.lexiconCorrection(raw, bridge) else null
        return Result(pool, fix)
    }
}

/**
 * "Bộ não" controller — port 1:1 phần logic của KeyboardViewController.swift (không UI):
 * engine bridge, học từ, gợi ý 6 tầng, backspace-undo auto-restore, nút Dán, xoá theo
 * từ, mẫu câu. Mọi hàm gọi trên MAIN thread, trừ [SuggestJob.compute].
 */
class KeyboardSession(
    val langModel: UserLangModel,
    private val clipboard: ClipboardSource? = null,
    /** Đồng hồ ms (nút Dán: 180 s / cache 2 s). */
    private val clock: () -> Long = System::currentTimeMillis,
) {
    var bridge = EngineBridge(); private set
    private var lastWord: String? = null
    private var lastWord2: String? = null
    private var learnEnabled = true
    private var filterSensitive = true
    private var traits = FieldTraits()
    private var lastResetAt: Long? = null
    /** Chưa gõ phím nào từ startInput — [FieldTraits.initialCaps] còn hiệu lực. */
    private var initialCapsPending = true

    /** Tăng mỗi phím — IME so với KeyOutcome.generation để bỏ lượt cũ. */
    var generation = 0; private set
    private var suggestReq = 0
    private var lastInsertWasSpace = false
    /** Auto-shift đang bật (gợi ý viết hoa chữ đầu). */
    var autoShiftOn = false; private set
    /** Bar tắt ở setting hoặc ô cấm. */
    var suggestionsActive = true; private set
    /** Bar thu gọn — pipeline gợi ý ngừng. IME set theo chevron. */
    var barCollapsed = false
    private var lastKeyWasEmailTrigger = false
    private var restoreUndoRaw: String? = null
    private var restoreUndoComposed: String? = null
    private var undoOfferActive = false
    private var ctxCacheKey: String? = null
    /** Từ chốt gần nhất + biên nhận học — ⌫ mở lại từ đó thì rút lại lượt học (không học trùng). */
    private class LastCommit(val word: String, val prev1: String?, val prev2: String?, val learned: UserLangModel.Learned?)
    private var lastCommit: LastCommit? = null
    private var ctxCache: Set<String> = emptySet()

    /** Gõ vuốt bật cho ô hiện tại (IME quyết: setting + loại ô + TalkBack). */
    var swipeTypingActive = false
        private set
    /** Từ vừa vuốt, còn là composition đang mở (null khi phím/thao tác khác xen vào). */
    private var swipeWord: String? = null
    private var swipeAlts: List<String> = emptyList()

    init {
        langModel.isKnownWord = { VNSuggest.contains(it) }
        langModel.seedIfEmpty(SeedData::load)
    }

    // MARK: vòng đời

    /** onStartInputView: settings mới, bridge mới, reset trạng thái (viewWillAppear). */
    fun startInput(settings: KeyboardSettings, field: FieldTraits) {
        if (lastResetAt != null && lastResetAt != settings.userlmResetAt) langModel.reloadAfterExternalErase()
        lastResetAt = settings.userlmResetAt
        TouchLog.session("android")
        bridge = EngineBridge(settings)
        bridge.passthrough = field.passthrough
        traits = field
        lastKeyWasEmailTrigger = false
        clearUndo()
        learnEnabled = settings.learnWords && !field.noLearning
        initialCapsPending = true
        filterSensitive = settings.filterSensitive
        suggestionsActive = settings.showSuggestions && field.suggestionsAllowed && !field.isSecure && !field.passthrough
        lastWord = null; lastWord2 = null
        lastInsertWasSpace = false
        lastCommit = null
        clearSwipe()
        setSwipeTyping(false)
    }

    /** IME bật/tắt gõ vuốt cho ô hiện tại (sau [startInput]). Tắt ⇒ bridge thôi ghi checkpoint. */
    fun setSwipeTyping(on: Boolean) {
        swipeTypingActive = on
        bridge.trackLetterUndo = on
        if (!on) clearSwipe()
    }

    private fun clearSwipe() { swipeWord = null; swipeAlts = emptyList() }

    /** onFinishInputView (viewWillDisappear). */
    fun finishInput() { langModel.saveNow() }

    /** Con trỏ/selection đổi từ NGOÀI (textWillChange): quên từ + ngữ cảnh. */
    fun externalSelectionChange() {
        TouchLog.host("selectionChanged", false, bridge.isComposing)
        bridge.reset(); lastWord = null; lastWord2 = null
        clearUndo()
        lastCommit = null
        clearSwipe()
    }

    private fun clearUndo() { restoreUndoRaw = null; restoreUndoComposed = null; undoOfferActive = false }

    /**
     * Auto-shift theo cờ CAP_* của ô: trả true/false; null = không đụng shift (ô không cờ
     * CAP, hoặc KHÔNG đọc được chữ trước con trỏ — null ≠ ô trống, trước đây coi null là ""
     * nên bật shift sai giữa câu). Chỉ nâng OFF→ON là việc của IME (không hạ CAPS).
     */
    fun updateAutoShift(proxy: TextProxy): Boolean? {
        val mode = capMode(traits)
        if (mode == CapMode.NONE) return null
        val before = proxy.contextBeforeInput()
        val auto = when {
            before != null -> autoShiftFor(before, mode)
            mode == CapMode.CHARACTERS -> true
            initialCapsPending -> traits.initialCaps
            else -> return null
        }
        autoShiftOn = auto
        return auto
    }

    // MARK: phím

    fun handle(key: Key, proxy: TextProxy): KeyOutcome {
        val t0 = if (TouchLog.enabled) System.nanoTime() else 0L
        val swiped = swipeWord?.takeIf { it == bridge.composedWord }
        clearSwipe()
        when (key) {
            is Key.Letter -> { bridge.letter(key.ch, proxy); clearUndo() }
            is Key.Text -> {
                commitAndLearn(bridge.boundary(key.text, proxy))
                lastWord = null; lastWord2 = null
                clearUndo()
            }
            Key.Space -> {
                val composedBefore = bridge.composedWord
                val committed = bridge.boundary(" ", proxy)
                if (composedBefore.isNotEmpty() && committed != composedBefore) {
                    restoreUndoRaw = committed; restoreUndoComposed = composedBefore
                } else { restoreUndoRaw = null; restoreUndoComposed = null }
                undoOfferActive = false
                commitAndLearn(committed)
            }
            Key.DoubleSpacePeriod -> {
                val ctx = proxy.contextBeforeInput() ?: ""
                if (TypingHeuristics.doubleSpaceMakesPeriod(ctx, lastInsertWasSpace)) {
                    // Xoá space bằng deleteSurroundingText (qua deleteCodePoints), KHÔNG
                    // deleteBackward: KEYCODE_DEL đi đường key event bất đồng bộ (ViewRootImpl
                    // post Message) nên có thể tới SAU commitText(". ") → "chữ ." thay vì "chữ. ".
                    proxy.deleteCodePoints(1)
                    proxy.insertText(". ")
                    lastWord = null; lastWord2 = null
                } else {
                    commitAndLearn(bridge.boundary(" ", proxy))
                }
                // Space đôi có thể đã thành ". ": ⌫ sau đó không được mở lại từ.
                bridge.forgetLastCommit()
                clearUndo()
            }
            is Key.MoveCursor -> {
                bridge.reset(); lastWord = null; lastWord2 = null; clearUndo()
            }
            Key.Newline -> {
                commitAndLearn(bridge.boundary("\n", proxy))
                // Enter có thể là "gửi"/performEditorAction: ⌫ sau đó không mở lại từ cũ.
                bridge.forgetLastCommit()
                lastWord = null; lastWord2 = null; clearUndo()
            }
            Key.ClearField -> {
                proxy.clearAll()
                bridge.reset(); lastWord = null; lastWord2 = null; clearUndo()
            }
            Key.Backspace -> if (swiped != null && proxy.confirmTail(swiped)) {
                // ⌫ ĐẦU TIÊN ngay sau vuốt: xoá cả từ vuốt (từ chưa chốt ⇒ ngữ cảnh giữ nguyên).
                proxy.deleteCodePoints(Cp.count(swiped))
                bridge.reset()
                clearUndo()
            } else {
                if (!bridge.isComposing && lastInsertWasSpace && restoreUndoRaw != null) undoOfferActive = true
                else clearUndo()
                if (bridge.backspace(proxy)) onReopened()
                else if (!bridge.isComposing) { lastWord = null; lastWord2 = null }
            }
        }
        lastInsertWasSpace = key == Key.Space || key == Key.DoubleSpacePeriod
        lastKeyWasEmailTrigger = key is Key.Text && (key.text == "@" || key.text == ".")
        initialCapsPending = false
        val needsAutoShift = when (key) {
            Key.Space, Key.Newline, Key.DoubleSpacePeriod, Key.Backspace, is Key.MoveCursor, Key.ClearField -> true
            // CAP_CHARACTERS: shift ON bị bàn phím hạ sau mỗi chữ → bật lại.
            else -> traits.capCharacters
        }
        if (TouchLog.enabled) {
            val (kind, ch) = when (key) {
                is Key.Letter -> "letter" to key.ch.toString()
                is Key.Text -> "text" to key.text
                Key.Space -> "space" to null
                Key.DoubleSpacePeriod -> "doubleSpace" to null
                Key.Backspace -> "backspace" to null
                Key.Newline -> "newline" to null
                is Key.MoveCursor -> "cursor" to null
                Key.ClearField -> "clear" to null
            }
            TouchLog.key(kind, bridge.isComposing, (System.nanoTime() - t0) / 1e6, ch)
        }
        generation++
        return KeyOutcome(needsAutoShift, generation)
    }

    // MARK: gõ vuốt

    /**
     * Ngón vừa chuyển từ chạm sang VUỐT: huỷ phím chữ đã chèn lúc chạm xuống (checkpoint
     * engine, không ⌫). false ⇒ không huỷ được (ô đổi / thao tác khác xen) — IME coi là chạm.
     */
    fun undoLastLetter(proxy: TextProxy): Boolean {
        val ok = bridge.undoLastLetter(proxy)
        generation++
        return ok
    }

    /** Điểm ngữ cảnh cho decoder: từ trước = từ đang soạn (sẽ được chốt) hoặc từ chốt gần nhất. */
    fun swipeContext(): SwipeSuggest.Context {
        val pending = if (bridge.isComposing) bridge.predictedCommit.takeIf { UserLangModel.learnable(it) } else null
        return if (bridge.isComposing) SwipeSuggest.context(langModel, pending, if (pending != null) lastWord else null)
        else SwipeSuggest.context(langModel, lastWord, lastWord2)
    }

    /**
     * Nhấc tay khỏi đường vuốt: chốt từ đang soạn (nếu có, kèm dấu cách), dấu cách treo
     * nếu liền trước là chữ, chèn [choice] rồi seed engine bằng nó ⇒ composition đang mở
     * (phím dấu Telex sửa được, ⌫ đầu xoá cả từ, thanh gợi ý hiện biến thể).
     */
    fun commitSwipe(choice: SwipeChoice, proxy: TextProxy): KeyOutcome {
        clearUndo(); clearSwipe()
        if (bridge.isComposing) {
            commitAndLearn(bridge.boundary(" ", proxy))
        } else if (SwipeSuggest.needsLeadingSpace(proxy.contextBeforeInput())) {
            bridge.boundary(" ", proxy)
        }
        proxy.insertText(choice.word)
        if (bridge.adoptWord(choice.word)) {
            swipeWord = choice.word
            swipeAlts = choice.alternatives
        }
        lastInsertWasSpace = false
        lastKeyWasEmailTrigger = false
        initialCapsPending = false
        TouchLog.write("swipe: ${Cp.count(choice.word)} chars, ${choice.alternatives.size} alts")
        generation++
        return KeyOutcome(true, generation)
    }

    /** Đang hiện biến thể của từ vừa vuốt (test / IME). */
    val swipeAlternatives: List<String>? get() = swipeWord?.takeIf { it == bridge.composedWord }?.let { swipeAlts }

    /** Giữ ⌫ > 3 s: xoá theo TỪ (khoảng trắng đuôi rồi tới đầu từ). */
    fun deleteWordBackward(proxy: TextProxy) {
        bridge.reset(); lastWord = null; lastWord2 = null; clearUndo()
        val before = proxy.contextBeforeInput() ?: ""
        if (before.isEmpty()) return
        var end = before.length
        var count = 0
        fun lastCp() = before.codePointBefore(end)
        while (end > 0 && (lastCp() == ' '.code || lastCp() == '\n'.code)) { end--; count++ }
        while (end > 0 && !(lastCp() == ' '.code || lastCp() == '\n'.code)) {
            end -= Character.charCount(lastCp()); count++
        }
        proxy.deleteCodePoints(maxOf(count, 1))
    }

    /**
     * Mẫu câu (sau khi IME đã fetch mẫu động): xoá từ đang soạn, chèn nguyên văn,
     * reset engine, KHÔNG học. IME gọi updateAutoShift + refresh bar sau đó.
     */
    fun insertTemplate(text: String, proxy: TextProxy) {
        val n = Cp.count(bridge.composedWord)
        if (n > 0 && proxy.confirmTail(bridge.composedWord)) proxy.deleteCodePoints(n)
        proxy.insertText(text)
        bridge.reset(); lastWord = null; lastWord2 = null; clearUndo()
    }

    /**
     * ⌫ vừa mở lại từ chốt trước: từ đó quay về trạng thái "đang gõ" — rút lượt học của nó
     * (chốt lại sẽ học đúng một lần, kể cả khi đã sửa dấu) và trả ngữ cảnh về trước nó.
     */
    private fun onReopened() {
        clearUndo()
        val lc = lastCommit
        lastCommit = null
        if (lc != null && lc.word == bridge.composedWord) {
            lc.learned?.let { langModel.retract(it) }
            lastWord = lc.prev1; lastWord2 = lc.prev2
        } else { lastWord = null; lastWord2 = null }
    }

    private fun commitAndLearn(word: String, accepted: Boolean = false) {
        lastCommit = null
        if (word.isEmpty()) return
        val learned = if (learnEnabled) langModel.record(word, lastWord, lastWord2, if (accepted) 2 else 1) else null
        lastCommit = LastCommit(word, lastWord, lastWord2, learned)
        if (UserLangModel.learnable(word)) { lastWord2 = lastWord; lastWord = word }
        else { lastWord = null; lastWord2 = null }
    }

    // MARK: gợi ý

    private fun caseForContext(w: String) = if (autoShiftOn) Cp.capitalizeFirst(w) else w

    private fun padWords(base: List<String>, need: Int, typed: String = ""): List<String> {
        if (base.size >= need) return base.take(need)
        val cands = SensitiveWords.filter(langModel.topWords(need + 12), filterSensitive)
            .map { caseForContext(DisplayCase.apply(it)) }
        return SuggestionFill.pad(base, cands, need, typed)
    }

    /** Gọi sau debounce 30 ms (hoặc khi hiện bàn phím / selection đổi / bật bar). */
    fun requestSuggestions(proxy: TextProxy): SuggestionPlan {
        suggestReq++
        if (!suggestionsActive || barCollapsed) return SuggestionPlan.Ready(null)
        swipeAlternatives?.let { return SuggestionPlan.Ready(SuggestionSet(nextWords = it)) }
        val composed = bridge.composedWord
        var literal: String? = null
        if (composed.isEmpty() && undoOfferActive) literal = restoreUndoComposed
        if (composed.isEmpty() && lastKeyWasEmailTrigger) {
            val before = proxy.contextBeforeInput()
            val last = before?.split(' ')?.lastOrNull { it.isNotEmpty() }
            if (last != null) {
                if (last.endsWith("@") && Cp.count(last) > 1)
                    return SuggestionPlan.Ready(SuggestionSet(nextWords = EMAIL_SUFFIXES))
                if (last.endsWith(".") && Cp.count(last) > 1 &&
                    last.dropLast(1).codePoints().allMatch { Character.isLetterOrDigit(it) })
                    return SuggestionPlan.Ready(SuggestionSet(nextWords = DOMAIN_TLDS))
            }
        }
        if (composed.isNotEmpty()) {
            val b = bridge
            return SuggestionPlan.Background(SuggestJob(suggestReq, generation, b, composed,
                b.rawWord, b.predictedCommit, b.autoFixAdjacent))
        }
        val prev = lastWord
        val next: List<String> = if (prev != null) {
            val n = SensitiveWords.filter(langModel.nextWords(prev, lastWord2, 6), filterSensitive)
                .take(3).map { caseForContext(DisplayCase.apply(it, prev)) }
            padWords(n, 3)
        } else {
            val top = SensitiveWords.filter(langModel.topWords(6), filterSensitive)
                .take(3).map { caseForContext(DisplayCase.apply(it)) }
            padWords(top, 3)
        }
        val paste = pasteOffer(proxy)
        return SuggestionPlan.Ready(SuggestionSet(literal = literal, nextWords = next, paste = paste))
    }

    /** Áp kết quả nền; null nếu đã lỗi thời (phím mới / lượt mới / từ khác / bar tắt). */
    fun completeSuggestions(job: SuggestJob, result: SuggestJob.Result): SuggestionSet? {
        if (job.req != suggestReq || job.gen != generation || bridge !== job.bridge ||
            job.bridge.composedWord != job.composed || !suggestionsActive || barCollapsed) return null
        return composingSuggestions(job.composed, job.raw, job.predicted, result.pool, result.fix)
    }

    /** Đồng bộ (test / debug): tính luôn trên thread gọi. */
    fun suggestionsNow(proxy: TextProxy): SuggestionSet? = when (val p = requestSuggestions(proxy)) {
        is SuggestionPlan.Ready -> p.set
        is SuggestionPlan.Background -> completeSuggestions(p.job, p.job.compute())
    }

    private fun composingSuggestions(composed: String, raw: String, predicted: String,
                                     pool: List<VNSuggest.Match>, fix: String?): SuggestionSet {
        val literal = if (predicted == composed) raw else composed
        var word: String? = null
        var word2: String? = null
        if (pool.isNotEmpty()) {
            val ctxKey = (lastWord ?: "") + "\u0001" + (lastWord2 ?: "")
            if (ctxKey != ctxCacheKey) {
                ctxCache = lastWord?.let { langModel.nextWords(it, lastWord2, 24).toSet() } ?: emptySet()
                ctxCacheKey = ctxKey
            }
            val ctx = ctxCache
            val typedLen = Cp.count(composed)
            fun score(w: String, f: Int): Double =
                ln(f + 1.0) + 2.5 * ln(langModel.count(w) + 1.0) +
                    (if (w in ctx) 4.0 else 0.0) + (if (Cp.count(w) == typedLen) 1.5 else 0.0)
            val ranked = SensitiveWords.filter(
                pool.map { it.word to score(it.word, it.freq) }.sortedByDescending { it.second }.map { it.first },
                filterSensitive)
            word = ranked.firstOrNull()?.let { DisplayCase.apply(it, lastWord) }
            word2 = ranked.getOrNull(1)?.let { DisplayCase.apply(it, lastWord) }
        } else if (fix != null) {
            word = fix
        }
        var emojis: List<String> = emptyList()
        val cLow = composed.lowercase()
        lastWord?.let { emojis = EmojiSuggest.emojis(it.lowercase() + " " + cLow) }
        if (emojis.isEmpty()) emojis = EmojiSuggest.emojis(composed)
        if (emojis.isEmpty()) emojis = EmojiSuggest.emojis(raw.lowercase())
        if (emojis.isEmpty()) {
            val words = padWords(listOfNotNull(word, word2), 2, composed)
            word = words.firstOrNull()
            word2 = if (words.size > 1) words.last() else null
        }
        return SuggestionSet(literal = literal, word = word, word2 = word2, emojis = emojis)
    }

    // MARK: nút Dán

    private var pasteSeenChange = -1
    private var pasteSeenAt = Long.MIN_VALUE / 2
    private var pasteUsedChange = -1
    private var pasteCheckedAt = Long.MIN_VALUE / 2
    private var pasteCached = false

    /** Bàn phím vừa hiện hẳn / clipboard đổi: bỏ cache 2 s. */
    fun invalidatePasteCache() { pasteCheckedAt = Long.MIN_VALUE / 2 }

    /** Kết quả nút Dán gần nhất (IME so trước/sau invalidate để quyết refresh). */
    val pasteCachedValue: Boolean get() = pasteCached

    internal fun pasteOffer(proxy: TextProxy): Boolean {
        val cb = clipboard ?: return false
        val last = proxy.contextBeforeInput()?.let { Cp.lastCodePoint(it) }
        if (last != null && !Character.isWhitespace(last)) return false
        val now = clock()
        if (now - pasteCheckedAt < 2000) return pasteCached
        pasteCheckedAt = now
        val cc = cb.changeCount
        if (cc != pasteSeenChange) { pasteSeenChange = cc; pasteSeenAt = now }
        val has = cb.hasText()
        pasteCached = cc != pasteUsedChange && has && now - pasteSeenAt < 180_000
        if (TouchLog.enabled) TouchLog.write("paste: cc=$cc used=$pasteUsedChange hasText=${if (has) 1 else 0} " +
            "age=${(now - pasteSeenAt) / 1000}s → ${if (pasteCached) 1 else 0}")
        return pasteCached
    }

    // MARK: chạm gợi ý

    /**
     * Chạm slot (QuickType): emoji thay từ; từ thay từ + space (học weight 2); fragment
     * (`gmail.com`, `com`) chèn không space; [SuggestionSet.PASTE_TOKEN] dán clipboard.
     * Sau đó IME gọi updateAutoShift + refresh bar, phát click.
     */
    fun acceptSuggestion(item: String, proxy: TextProxy) {
        if (item == SuggestionSet.PASTE_IMAGE_TOKEN) {
            pasteUsedChange = clipboard?.changeCount ?: -1; pasteCached = false
            return
        }
        if (item == SuggestionSet.PASTE_TOKEN) {
            val cb = clipboard
            val s = cb?.readText()
            if (!s.isNullOrEmpty()) proxy.insertText(s)
            pasteUsedChange = cb?.changeCount ?: -1
            pasteCached = false
            bridge.reset(); lastWord = null; lastWord2 = null
            return
        }
        val sw = swipeWord
        if (sw != null && sw == bridge.composedWord && item in swipeAlts) {
            // Chạm biến thể của từ vừa vuốt: thay từ, vẫn là composition mở (chưa học — học khi chốt).
            if (!proxy.confirmTail(sw)) { clearSwipe(); bridge.reset(); return }
            proxy.deleteCodePoints(Cp.count(sw))
            proxy.insertText(item)
            if (bridge.adoptWord(item)) {
                swipeAlts = swipeAlts.map { if (it == item) sw else it }
                swipeWord = item
            } else clearSwipe()
            return
        }
        clearSwipe()
        val uRaw = restoreUndoRaw; val uComposed = restoreUndoComposed
        if (undoOfferActive && uRaw != null && uComposed != null && item == uComposed && bridge.composedWord.isEmpty()) {
            if (!proxy.confirmTail(uRaw)) {
                // Chữ vừa chốt không còn trước con trỏ: không xoá mù, bỏ lời mời hoàn tác.
                clearUndo(); bridge.reset()
                return
            }
            proxy.deleteCodePoints(Cp.count(uRaw))
            proxy.insertText("$uComposed ")
            clearUndo()
            bridge.reset()
            commitAndLearn(uComposed, accepted = true)
            return
        }
        clearUndo()
        val isFragment = item.contains('.') || item.contains('@')
        val isWord = !isFragment && item.isNotEmpty() && Character.isLetter(item.codePointAt(0))
        val n = Cp.count(bridge.composedWord)
        // Fail-safe: từ đang soạn không còn trước con trỏ ⇒ chèn, không xoá mù.
        if (n > 0 && proxy.confirmTail(bridge.composedWord)) proxy.deleteCodePoints(n)
        proxy.insertText(if (isWord) "$item " else item)
        bridge.reset()
        if (isWord) commitAndLearn(item, accepted = true) else { lastWord = null; lastWord2 = null }
    }

    companion object {
        val EMAIL_SUFFIXES = listOf("gmail.com", "yahoo.com", "outlook.com")
        val DOMAIN_TLDS = listOf("com", "vn", "net")

        /** Auto-shift thuần: ô trống, hoặc " " sau .!?, hoặc sau \n. */
        fun autoShiftFor(before: String): Boolean {
            val t = before.trim(' ', '\t')
            return before.isEmpty() ||
                (before.endsWith(" ") && (t.endsWith(".") || t.endsWith("!") || t.endsWith("?"))) ||
                before.endsWith("\n")
        }

        /** Mode mạnh nhất của ô (≈ bitmask TextUtils.getCapsMode: có bit nào là shift). */
        fun capMode(t: FieldTraits): CapMode = when {
            t.capCharacters -> CapMode.CHARACTERS
            t.capWords -> CapMode.WORDS
            t.capSentences -> CapMode.SENTENCES
            else -> CapMode.NONE
        }

        /**
         * Auto-shift thuần theo mode (logic tương đương TextUtils.getCapsMode, không cần
         * android.jar): CHARACTERS luôn hoa; WORDS đầu ô hoặc sau khoảng trắng (bỏ qua
         * ngoặc/nháy mở như getCapsMode: `("` rồi mới tới chữ); SENTENCES như [autoShiftFor].
         */
        fun autoShiftFor(before: String, mode: CapMode): Boolean = when (mode) {
            CapMode.NONE -> false
            CapMode.CHARACTERS -> true
            CapMode.SENTENCES -> autoShiftFor(before)
            CapMode.WORDS -> {
                val t = before.trimEnd('"', '\'', '(', '[', '{', '“', '‘', '«')
                t.isEmpty() || t.last().isWhitespace()
            }
        }
    }
}
