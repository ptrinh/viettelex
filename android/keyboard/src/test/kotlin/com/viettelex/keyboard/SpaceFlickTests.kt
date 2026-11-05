package com.viettelex.keyboard

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * Vuốt phím cách đổi Tiếng Việt ↔ Tiếng Anh — port iOS SpaceFlickTests.swift (cùng số liệu):
 * phân loại flick, trạng thái ngôn ngữ, chế độ Tiếng Anh của EngineBridge, gợi ý tiếng Anh,
 * lọc gõ vuốt; thêm luồng KeyboardSession.
 */
class SpaceFlickTests {
    @Before fun setUp() = TestAssets.install()

    // MARK: phân loại

    @Test fun flickDirections() {
        assertEquals(SpaceFlick.Direction.RIGHT, SpaceFlick.classify(50f, 4f, 150, 37f))
        assertEquals(SpaceFlick.Direction.LEFT, SpaceFlick.classify(-45f, -10f, 200, 37f))
    }

    @Test fun tooShortSlowOrVerticalIsNotFlick() {
        assertNull(SpaceFlick.classify(30f, 0f, 100, 37f))
        assertNull(SpaceFlick.classify(80f, 0f, 300, 37f))
        assertNull(SpaceFlick.classify(60f, 31f, 100, 37f))
        assertNull(SpaceFlick.classify(0f, 0f, 50, 37f))
    }

    @Test fun distanceFloorAndSpeed() {
        assertNull(SpaceFlick.classify(20f, 0f, 50, 10f))
        assertEquals(SpaceFlick.Direction.RIGHT, SpaceFlick.classify(25f, 0f, 50, 10f))
        assertNull(SpaceFlick.classify(25f, 0f, 290, 10f))
    }

    @Test fun previewProgress() {
        val span = SpaceFlick.previewSpan(37f)
        assertEquals(74f, span, 0f)
        assertEquals(0f, SpaceFlick.progress(5f, 0f, 50, span), 0f)
        assertEquals(0.5f, SpaceFlick.progress(37f, 0f, 100, span), 0f)
        assertEquals(-1f, SpaceFlick.progress(-200f, 0f, 100, span), 0f)
        assertEquals(0f, SpaceFlick.progress(37f, 0f, 310, span), 0f)
        assertEquals(0f, SpaceFlick.progress(20f, 30f, 100, span), 0f)
    }

    /** #147: kéo chậm sau khi đã trượt quá slop (trackpad không thể bật) vẫn đổi ngôn ngữ. */
    @Test fun slowDragAfterSlopToggles() {
        // 1,2 s, 50 dp ⇒ trước đây null (quá giờ + chậm)
        assertNull(SpaceFlick.classify(50f, 4f, 1200, 37f))
        assertEquals(SpaceFlick.Direction.RIGHT, SpaceFlick.classify(50f, 4f, 1200, 37f, trackpadPossible = false))
        assertEquals(SpaceFlick.Direction.LEFT, SpaceFlick.classify(-40f, 10f, 800, 37f, trackpadPossible = false))
        assertEquals(SpaceFlick.Direction.RIGHT, SpaceFlick.classify(25f, 0f, 290, 10f, trackpadPossible = false))
        // vẫn cần đủ quãng + chủ yếu ngang
        assertNull(SpaceFlick.classify(30f, 0f, 1200, 37f, trackpadPossible = false))
        assertNull(SpaceFlick.classify(60f, 31f, 1200, 37f, trackpadPossible = false))
        assertNull(SpaceFlick.classify(0f, 0f, 1200, 37f, trackpadPossible = false))
        // nhanh: không đổi hành vi
        assertEquals(SpaceFlick.Direction.RIGHT, SpaceFlick.classify(50f, 4f, 150, 37f, trackpadPossible = false))
    }

    @Test fun slowDragPreviewKeepsTracking() {
        val span = SpaceFlick.previewSpan(37f)
        assertEquals(0f, SpaceFlick.progress(37f, 0f, 1000, span), 0f)
        assertEquals(0.5f, SpaceFlick.progress(37f, 0f, 1000, span, trackpadPossible = false), 0f)
        assertEquals(-1f, SpaceFlick.progress(-200f, 0f, 2000, span, trackpadPossible = false), 0f)
        assertEquals(0f, SpaceFlick.progress(5f, 0f, 1000, span, trackpadPossible = false), 0f)
        assertEquals(0f, SpaceFlick.progress(20f, 30f, 1000, span, trackpadPossible = false), 0f)
    }

    // MARK: trạng thái ngôn ngữ

    @Test fun languageStateForcedVietnameseWhenOff() {
        assertEquals(KeyboardLanguage.VI, KeyboardLanguage.effective("en", false))
        assertEquals(KeyboardLanguage.EN, KeyboardLanguage.effective("en", true))
        assertEquals(KeyboardLanguage.VI, KeyboardLanguage.effective(null, true))
        assertEquals(KeyboardLanguage.VI, KeyboardLanguage.effective("xx", true))
        assertEquals(KeyboardLanguage.EN, KeyboardLanguage.VI.toggled)
        assertEquals(KeyboardLanguage.VI, KeyboardLanguage.EN.toggled)
        assertEquals("English", KeyboardLanguage.EN.displayName)
        assertEquals("Tiếng Việt", KeyboardLanguage.VI.displayName)
    }

    @Test fun settingDefaultsOff() {
        assertFalse(KeyboardSettings().spaceSwipeLanguage)
        assertTrue(KeyboardSettings.load { if (it == Keys.SPACE_SWIPE_LANGUAGE) true else null }.spaceSwipeLanguage)
        assertEquals(SettingKind.Bool(false), BackupSettings.byKey[Keys.SPACE_SWIPE_LANGUAGE]?.kind)
    }

    // MARK: EngineBridge chế độ Tiếng Anh

    private fun run(keys: String, b: EngineBridge, p: MockProxy) {
        for (ch in keys) when (ch) {
            ' ' -> b.boundary(" ", p)
            '⌫' -> b.backspace(p)
            else -> b.letter(ch, p)
        }
    }

    private fun english(s: KeyboardSettings = KeyboardSettings()): Pair<EngineBridge, MockProxy> {
        val b = EngineBridge(s); val p = MockProxy()
        b.setEnglish(true, p)
        return b to p
    }

    @Test fun englishModeTypesRawKeys() {
        val (b, p) = english()
        run("vieetj hows ", b, p)
        assertEquals("vieetj hows ", p.text)
        run("wordd", b, p)
        assertEquals("wordd", b.composedWord)
        assertEquals("wordd", b.rawWord)
        assertEquals("wordd", b.predictedCommit)
        assertTrue(b.isComposing)
        assertEquals("wordd", b.boundary(".", p))
        assertEquals("vieetj hows wordd.", p.text)
        assertFalse(b.isComposing)
    }

    @Test fun englishBackspace() {
        val (b, p) = english()
        run("cat⌫⌫", b, p)
        assertEquals("c", p.text)
        assertEquals("c", b.composedWord)
        run("⌫⌫", b, p)
        assertEquals("", p.text)
        assertFalse(b.isComposing)
    }

    @Test fun englishShortcutsStillExpand() {
        val (b, p) = english(KeyboardSettings(shortcuts = ShortcutTable(mapOf("brb" to "be right back"))))
        assertNull(b.shortcutPreview)
        run("brb", b, p)
        assertEquals("be right back", b.shortcutPreview)
        assertEquals("be right back", b.boundary(" ", p))
        assertEquals("be right back ", p.text)
        assertTrue(b.expandedAtLastBoundary)
        run("⌫", b, p)
        assertEquals("brb ", p.text)
    }

    @Test fun englishIgnoresVNIDigits() {
        val (b, p) = english(KeyboardSettings(vniMode = true))
        run("viet", b, p)
        assertFalse(b.vniDigit('5', p))
    }

    @Test fun englishUndoLastLetter() {
        val (b, p) = english()
        b.trackLetterUndo = true
        run("ab", b, p)
        assertTrue(b.undoLastLetter(p))
        assertEquals("a", p.text)
        assertEquals("a", b.composedWord)
    }

    @Test fun switchCommitsHalfComposedWord() {
        val b = EngineBridge(); val p = MockProxy()
        run("vieetj", b, p)
        assertEquals("việt", b.setEnglish(true, p))
        assertEquals("việt", p.text)
        assertFalse(b.isComposing)
        run("s", b, p)
        assertEquals("việts", p.text)
        assertEquals("s", b.setEnglish(false, p))
        run("s", b, p)
        assertEquals("việtss", p.text)
        assertEquals("", b.setEnglish(false, p))
    }

    @Test fun switchAutoRestoresEnglishWord() {
        val b = EngineBridge(); val p = MockProxy()
        run("google", b, p)
        assertEquals("google", b.setEnglish(true, p))
        assertEquals("google", p.text)
    }

    @Test fun vietnameseUnchangedWhenNotEnglish() {
        val b = EngineBridge(); val p = MockProxy()
        run("vieetj ", b, p)
        assertEquals("việt ", p.text)
        assertFalse(b.englishMode)
    }

    // MARK: gợi ý tiếng Anh

    private fun lexicon(entries: List<Pair<String, Int>>): SwipeEnglish.Lexicon {
        val sorted = entries.sortedBy { it.first }
        val out = java.io.ByteArrayOutputStream()
        out.write("VTE1".toByteArray())
        val n = sorted.size
        out.write(byteArrayOf(n.toByte(), (n shr 8).toByte(), (n shr 16).toByte(), (n shr 24).toByte()))
        for ((w, f) in sorted) { out.write(w.length); out.write(f); out.write(w.toByteArray()) }
        return SwipeEnglish.parse(java.nio.ByteBuffer.wrap(out.toByteArray()))!!
    }

    @Test fun englishCompletions() {
        val lex = lexicon(listOf("hello" to 200, "help" to 220, "he" to 250, "helm" to 90, "world" to 240))
        assertEquals(listOf("help", "hello", "helm"), SwipeEnglish.completions("hel", lex = lex).map { it.word })
        assertEquals(listOf("help", "hello"), SwipeEnglish.completions("he", 2, lex).map { it.word })
        assertEquals("Help", SwipeEnglish.completions("Hel", lex = lex).first().word)
        assertEquals("HELP", SwipeEnglish.completions("HEL", lex = lex).first().word)
        assertEquals(220, SwipeEnglish.completions("hel", lex = lex).first().freq)
        assertTrue(SwipeEnglish.completions("việt", lex = lex).isEmpty())
        assertTrue(SwipeEnglish.completions("", lex = lex).isEmpty())
        assertTrue(SwipeEnglish.completions("xyz", lex = lex).isEmpty())
        assertEquals(listOf("he", "world"), SwipeEnglish.topWords(2, lex))
    }

    @Test fun realLexiconHasCompletions() {
        assertTrue(SwipeEnglish.completions("th").isNotEmpty())
        assertEquals(12, SwipeEnglish.top.size)
    }

    @Test fun swipeEnglishOnlyFilter() {
        val c = listOf(SwipeCandidate("the", 1f, SwipeLang.VI), SwipeCandidate("the", 0.9f, SwipeLang.EN),
            SwipeCandidate("then", 0.5f, SwipeLang.EN))
        assertEquals(listOf("the", "then"), SwipeSuggest.englishOnly(c).map { it.folded })
        assertTrue(SwipeSuggest.englishOnly(c).all { it.lang == SwipeLang.EN })
    }

    // MARK: KeyboardSession

    private fun session(on: Boolean): KeyboardSession {
        val s = KeyboardSession(UserLangModel(), null) { 0L }
        s.startInput(KeyboardSettings(spaceSwipeLanguage = on), FieldTraits())
        return s
    }

    @Test fun sessionToggleDisabledWhenOff() {
        val s = session(false); val p = MockProxy()
        s.restoreLanguage("en", p)
        assertEquals(KeyboardLanguage.VI, s.language)
        assertNull(s.toggleLanguage(p))
        s.handle(Key.Letter('a'), p); s.handle(Key.Letter('a'), p)
        assertEquals("â", p.text)
    }

    @Test fun sessionToggleCommitsAndSwitches() {
        val s = session(true); val p = MockProxy()
        s.restoreLanguage(null, p)
        for (ch in "vieetj ") if (ch == ' ') s.handle(Key.Space, p) else s.handle(Key.Letter(ch), p)
        assertEquals(KeyboardLanguage.EN, s.toggleLanguage(p))
        assertEquals("việt ", p.text)
        for (ch in "hello") s.handle(Key.Letter(ch), p)
        assertEquals("việt hello", p.text)
        s.handle(Key.Space, p)
        assertEquals(KeyboardLanguage.VI, s.toggleLanguage(p))
        assertFalse(s.bridge.englishMode)
        assertEquals("việt hello ", p.text)
    }

    // MARK: §7 vuốt khi đang gõ dở một từ — chuyển luôn từ đó

    private fun typeKeys(s: KeyboardSession, p: MockProxy, keys: String) {
        for (ch in keys) when (ch) {
            ' ' -> s.handle(Key.Space, p)
            in '0'..'9' -> s.handle(Key.Text(ch.toString()), p)
            else -> s.handle(Key.Letter(ch), p)
        }
    }

    private fun flickSession(vni: Boolean = false, strict: Boolean = true): Pair<KeyboardSession, MockProxy> {
        val s = KeyboardSession(UserLangModel(), null) { 0L }
        s.startInput(KeyboardSettings(spaceSwipeLanguage = true, vniMode = vni, autoRestore = strict, liveSpellCheck = strict), FieldTraits())
        val p = MockProxy()
        s.restoreLanguage(null, p)
        return s to p
    }

    /** Gõ [keys] ở VI, vuốt EN ⇒ [en]; vuốt VI ⇒ [vi] (khứ hồi). Từ vẫn đang soạn. */
    private fun roundTrip(keys: String, vi: String, en: String, vni: Boolean = false, strict: Boolean = true) {
        val (s, p) = flickSession(vni, strict)
        typeKeys(s, p, keys)
        assertEquals(vi, p.text)
        assertEquals(KeyboardLanguage.EN, s.toggleLanguage(p))
        assertEquals(en, p.text)
        assertTrue(s.bridge.englishMode)
        assertEquals(en, s.bridge.composedWord)
        assertEquals(KeyboardLanguage.VI, s.toggleLanguage(p))
        assertEquals(vi, p.text)
        assertFalse(s.bridge.englishMode)
        assertEquals(vi, s.bridge.composedWord)
        assertEquals(keys, s.bridge.rawWord)
    }

    @Test fun convertHis() = roundTrip("His", "Hí", "His")
    /**
     * Mặc định (tự khôi phục + kiểm tra chính tả) "very" đã hiện "very" giữa từ; tắt hai công
     * tắc đó mới thấy "vẻy" như bảng spec.
     */
    @Test fun convertVery() = roundTrip("very", "vẻy", "very", strict = false)
    @Test fun convertVeryDefaultSettings() = roundTrip("very", "very", "very")
    @Test fun convertKeepsCaps() = roundTrip("HIS", "HÍ", "HIS")
    @Test fun convertHornsAndBreve() = roundTrip("dduwowcj", "được", "dduwowcj")
    @Test fun convertVNI() = roundTrip("hi1", "hí", "hi1", vni = true)

    @Test fun convertEnglishFirstThenVietnamese() {
        val (s, p) = flickSession()
        s.toggleLanguage(p)                       // EN, chưa có từ
        typeKeys(s, p, "His")
        assertEquals("His", p.text)
        assertEquals(KeyboardLanguage.VI, s.toggleLanguage(p))
        assertEquals("Hí", p.text)
        typeKeys(s, p, " ")                       // từ đã chuyển chốt như gõ tay
        assertEquals("Hí ", p.text)
    }

    @Test fun convertedWordKeepsComposingInTarget() {
        val (s, p) = flickSession()
        typeKeys(s, p, "vie")
        s.toggleLanguage(p)                       // "vie" (EN)
        typeKeys(s, p, "ws")                      // EN: không Telex
        assertEquals("views", p.text)
        s.toggleLanguage(p)                       // VI: chạy lại "views"
        assertEquals(s.bridge.composeTrial("views"), p.text)
    }

    @Test fun convertEmptyWordIsOldBehavior() {
        val (s, p) = flickSession()
        assertEquals(KeyboardLanguage.EN, s.toggleLanguage(p))
        assertEquals("", p.text)
        assertFalse(s.bridge.isComposing)
    }

    @Test fun convertAfterSpaceLeavesCommittedWord() {
        val (s, p) = flickSession()
        typeKeys(s, p, "His ")
        val before = p.text
        s.toggleLanguage(p)
        assertEquals(before, p.text)
        s.toggleLanguage(p)
        assertEquals(before, p.text)
    }

    @Test fun convertOnlyTouchesComposingWord() {
        val (s, p) = flickSession()
        typeKeys(s, p, "vieetj His")
        s.toggleLanguage(p)
        assertEquals("việt His", p.text)
        s.toggleLanguage(p)
        assertEquals("việt Hí", p.text)
    }

    /** IME ở bảng số/emoji ⇒ không chuyển: chốt từ rồi đổi như cũ. */
    @Test fun convertNotOnNumberOrEmojiPlane() {
        val (s, p) = flickSession()
        typeKeys(s, p, "His")
        assertEquals(KeyboardLanguage.EN, s.toggleLanguage(p, convertWord = false))
        assertEquals("Hí", p.text)
        assertFalse(s.bridge.isComposing)
    }

    /** Engine đã đóng băng tiếng Anh giữa từ: sang EN là phím gốc, về VI chạy lại toàn bộ phím. */
    @Test fun convertEnglishFrozenPrefix() {
        val (s, p) = flickSession()
        typeKeys(s, p, "google")
        val vi = p.text
        s.toggleLanguage(p)
        assertEquals("google", p.text)
        s.toggleLanguage(p)
        assertEquals(vi, p.text)
        assertEquals("google", s.bridge.rawWord)
    }

    /** Chữ trên màn hình không còn là từ đang soạn ⇒ không xoá mù, đổi như cũ. */
    @Test fun convertTailMismatchFallsBack() {
        val (s, p) = flickSession()
        typeKeys(s, p, "His")
        p.sb.append("x")
        s.toggleLanguage(p)
        assertTrue(p.text.endsWith("x"))
        assertFalse(s.bridge.isComposing)
    }

    @Test fun bridgeConvertNoComposingReturnsFalse() {
        val b = EngineBridge(); val p = MockProxy()
        assertFalse(b.convertComposing(true, p))
        run("vieetj ", b, p)
        assertFalse(b.convertComposing(true, p))
        assertEquals("việt ", p.text)
        assertFalse(b.englishMode)
    }

    @Test fun sessionRestoresEnglishAndSuggestsEnglish() {
        val s = session(true); val p = MockProxy()
        s.restoreLanguage("en", p)
        assertTrue(s.bridge.englishMode)
        for (ch in "helo") s.handle(Key.Letter(ch), p)
        assertEquals("helo", p.text)
        val set = s.suggestionsNow(p)!!
        assertEquals("helo", set.literal)
    }

    /**
     * Gợi ý sau dấu cách ở chế độ Tiếng Anh chạy trên MAIN: không được nạp từ điển Anh (~1.4 MB
     * parse) đồng bộ khi hâm nóng nền chưa xong / vừa nhả lúc ẩn lâu — coi như chưa biết.
     */
    @Test fun englishSuggestionsDoNotLoadLexiconOnMain() {
        val s = session(true); val p = MockProxy()
        s.restoreLanguage("en", p)
        for (ch in "hello world ") if (ch == ' ') s.handle(Key.Space, p) else s.handle(Key.Letter(ch), p)
        SwipeEnglish.release()
        assertNotNull(s.suggestionsNow(p))
        assertFalse(SwipeEnglish.isLoaded)
        assertFalse(SwipeEnglish.containsIfLoaded("hello"))
        // Hâm nóng xong ⇒ tra được như contains.
        assertTrue(SwipeEnglish.contains("hello"))
        assertTrue(SwipeEnglish.containsIfLoaded("hello"))
        assertFalse(SwipeEnglish.containsIfLoaded("xqzv"))
        assertEquals(12, SwipeEnglish.topIfReady?.size ?: SwipeEnglish.top.size)
    }
}
