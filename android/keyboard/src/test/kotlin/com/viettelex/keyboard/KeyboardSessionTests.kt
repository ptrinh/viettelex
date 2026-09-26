package com.viettelex.keyboard

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/** Hành vi controller iOS (KeyboardViewController) — port logic thuần. */
class KeyboardSessionTests {
    @Before fun setUp() = TestAssets.install()

    private class FakeClip(var text: String? = null) : ClipboardSource {
        override var changeCount = 0
        override fun hasText() = text != null
        override fun readText() = text
        fun copy(s: String) { text = s; changeCount++ }
    }

    private var now = 1_000_000L
    private val clip = FakeClip()
    private fun session(settings: KeyboardSettings = KeyboardSettings(),
                        traits: FieldTraits = FieldTraits(capSentences = true)): KeyboardSession {
        val s = KeyboardSession(UserLangModel(), clip) { now }
        s.startInput(settings, traits)
        return s
    }

    private fun KeyboardSession.typeKeys(p: TextProxy, keys: String) {
        for (c in keys) handle(if (c == ' ') Key.Space else Key.Letter(c), p)
    }

    @Test fun testEmptyFieldShowsTop3Seeds() {
        val s = session(); val p = MockProxy()
        assertEquals(true, s.updateAutoShift(p))
        val set = s.suggestionsNow(p)!!
        assertEquals(listOf("Em", "Anh", "Tôi"), set.nextWords)   // đầu câu ⇒ viết hoa
    }

    @Test fun testNextWordsAfterSpace() {
        val s = session(traits = FieldTraits()); val p = MockProxy()
        s.typeKeys(p, "camr ")
        assertEquals("cảm ", p.text)
        assertEquals("ơn", s.suggestionsNow(p)!!.nextWords.first())
    }

    @Test fun testComposingLiteralSlotAndCandidates() {
        val s = session(traits = FieldTraits()); val p = MockProxy()
        s.typeKeys(p, "nguoi")
        val set = s.suggestionsNow(p)!!
        assertEquals("nguoi", set.literal)            // predicted == composed ⇒ raw
        assertEquals("người", set.word)
    }

    @Test fun testAcceptWordReplacesAndAddsSpace() {
        val s = session(traits = FieldTraits()); val p = MockProxy()
        s.typeKeys(p, "nguoi")
        val before = s.langModel.count("người")
        s.acceptSuggestion("người", p)
        assertEquals("người ", p.text)
        assertEquals(before + 2, s.langModel.count("người"))
        assertFalse(s.bridge.isComposing)
    }

    @Test fun testAdjacentFixWhenNoCandidates() {
        val s = session(traits = FieldTraits()); val p = MockProxy()
        s.typeKeys(p, "ohims")
        assertEquals("phím", s.suggestionsNow(p)!!.word)
    }

    @Test fun testEmailAndTldRules() {
        val s = session(traits = FieldTraits()); val p = MockProxy()
        s.typeKeys(p, "phuc")
        s.handle(Key.Text("@"), p)
        assertEquals(KeyboardSession.EMAIL_SUFFIXES, s.suggestionsNow(p)!!.nextWords)
        s.acceptSuggestion("gmail.com", p)
        assertEquals("phuc@gmail.com", p.text)          // fragment: không space
        val p2 = MockProxy(); val s2 = session(traits = FieldTraits())
        s2.typeKeys(p2, "github"); s2.handle(Key.Text("."), p2)
        assertEquals(KeyboardSession.DOMAIN_TLDS, s2.suggestionsNow(p2)!!.nextWords)
    }

    @Test fun testDoubleSpacePeriod() {
        val s = session(traits = FieldTraits()); val p = MockProxy()
        s.typeKeys(p, "xin ")
        s.handle(Key.DoubleSpacePeriod, p)
        assertEquals("xin. ", p.text)
        // đầu ô: không thành ". "
        val p2 = MockProxy(); val s2 = session(traits = FieldTraits())
        s2.handle(Key.Space, p2); s2.handle(Key.DoubleSpacePeriod, p2)
        assertEquals("  ", p2.text)
    }

    @Test fun testAutoShiftRules() {
        assertTrue(KeyboardSession.autoShiftFor(""))
        assertTrue(KeyboardSession.autoShiftFor("Xong. "))
        assertTrue(KeyboardSession.autoShiftFor("Hả? "))
        assertTrue(KeyboardSession.autoShiftFor("a\n"))
        assertFalse(KeyboardSession.autoShiftFor("xin "))
        assertFalse(KeyboardSession.autoShiftFor("Xong."))
        assertNull(session(traits = FieldTraits(capSentences = false)).updateAutoShift(MockProxy()))
    }

    @Test fun testBackspaceUndoAfterAutoRestore() {
        val s = session(traits = FieldTraits()); val p = MockProxy()
        s.typeKeys(p, "google ")
        val composed = "gôgle"                      // engine restore gôgle → google
        assertEquals("google ", p.text)
        s.handle(Key.Backspace, p)
        val set = s.suggestionsNow(p)!!
        assertEquals(composed, set.literal)
        assertEquals("google", p.text)
        s.acceptSuggestion(composed, p)
        assertEquals("$composed ", p.text)
    }

    @Test fun testPasteOfferConditions() {
        val s = session(traits = FieldTraits()); val p = MockProxy()
        assertFalse(s.suggestionsNow(p)!!.paste)       // clipboard trống
        clip.copy("copied"); s.invalidatePasteCache()
        assertTrue(s.suggestionsNow(p)!!.paste)
        s.acceptSuggestion(SuggestionSet.PASTE_TOKEN, p)
        assertEquals("copied", p.text)
        s.invalidatePasteCache()
        assertFalse(s.suggestionsNow(p)!!.paste)       // đã dùng / trước con trỏ không trắng
        val p2 = MockProxy(); clip.copy("new"); s.invalidatePasteCache()
        assertTrue(s.suggestionsNow(p2)!!.paste)       // thấy đổi lúc này
        now += 181_000; s.invalidatePasteCache()
        assertFalse(s.suggestionsNow(p2)!!.paste)      // quá 180 s kể từ lần thấy đổi
        clip.copy("again"); s.invalidatePasteCache()
        assertTrue(s.suggestionsNow(p2)!!.paste)
        now += 1000; clip.text = null                  // cache 2 s
        assertTrue(s.suggestionsNow(p2)!!.paste)
    }

    @Test fun testStaleBackgroundResultDropped() {
        val s = session(traits = FieldTraits()); val p = MockProxy()
        s.typeKeys(p, "ng")
        val plan = s.requestSuggestions(p) as SuggestionPlan.Background
        val r = plan.job.compute()
        s.handle(Key.Letter('u'), p)                   // phím mới tới trước
        assertNull(s.completeSuggestions(plan.job, r))
    }

    @Test fun testCollapsedBarStopsPipeline() {
        val s = session(traits = FieldTraits()); val p = MockProxy()
        s.barCollapsed = true
        assertNull(s.suggestionsNow(p))
        val sec = session(traits = FieldTraits(isSecure = true))
        assertFalse(sec.suggestionsActive)
    }

    @Test fun testTemplateInsertAndDeleteWord() {
        val s = session(traits = FieldTraits()); val p = MockProxy()
        s.typeKeys(p, "xin chao")
        s.insertTemplate("Chúc ngủ ngon", p)
        assertEquals("xin Chúc ngủ ngon", p.text)
        assertFalse(s.bridge.isComposing)
        p.insertText("  ")
        s.deleteWordBackward(p)
        assertEquals("xin Chúc ngủ ", p.text)
        s.handle(Key.ClearField, p)
        assertEquals("", p.text)
    }

    @Test fun testLearnsCommittedWordsAndNotSecure() {
        val s = session(traits = FieldTraits()); val p = MockProxy()
        val before = s.langModel.count("việt")
        s.typeKeys(p, "vieetj ")
        assertEquals(before + 1, s.langModel.count("việt"))
        val sec = KeyboardSession(UserLangModel(), null) { now }
        sec.startInput(KeyboardSettings(), FieldTraits(isSecure = true))
        val sp = MockProxy(isSecureField = true)
        for (c in "vieetj ") sec.handle(if (c == ' ') Key.Space else Key.Letter(c), sp)
        assertEquals("vieetj ", sp.text)
        assertEquals(0, sec.langModel.count("vieetj"))
    }

    @Test fun testResetAtChangeReloadsModel() {
        val s = session(traits = FieldTraits()); val p = MockProxy()
        val seeded = s.langModel.count("việt")
        s.typeKeys(p, "vieetj ")
        assertEquals(seeded + 1, s.langModel.count("việt"))
        s.startInput(KeyboardSettings(userlmResetAt = 123), FieldTraits())
        assertEquals(seeded, s.langModel.count("việt"))
        assertTrue(s.langModel.topWords(3).isNotEmpty())   // seed lại
    }

    @Test fun testSignatureStable() {
        val a = SuggestionSet(word = "a", emojis = listOf("x"))
        assertEquals(a.signature(), a.copy().signature())
        assertTrue(a.signature() != a.copy(word = "b").signature())
        assertNotNull(SuggestionSet().signature())
    }

    /** Ô không cho đọc ngược (getTextBeforeCursor = null). */
    private class NullCtxProxy : TextProxy {
        val inner = MockProxy()
        override val isSecure: Boolean get() = false
        override fun insertText(text: String) = inner.insertText(text)
        override fun deleteCodePoints(count: Int) = inner.deleteCodePoints(count)
        override fun deleteBackward() = inner.deleteBackward()
        override fun contextBeforeInput(): String? = null
        override fun clearAll() = inner.clearAll()
    }

    @Test fun testNullContextKeepsShift() {
        // Regression: context null bị coi là ô trống ⇒ bật shift sai giữa câu.
        val s = session(traits = FieldTraits(capSentences = true)); val p = NullCtxProxy()
        assertEquals(false, s.updateAutoShift(p))          // initialCaps=false, chưa gõ
        s.typeKeys(p, "xin ")
        assertNull(s.updateAutoShift(p))                    // đã gõ: không đoán
        val s2 = session(traits = FieldTraits(capSentences = true, initialCaps = true))
        assertEquals(true, s2.updateAutoShift(NullCtxProxy()))   // editor báo initialCapsMode
        val chars = session(traits = FieldTraits(capCharacters = true))
        assertEquals(true, chars.updateAutoShift(NullCtxProxy()))
    }

    @Test fun testCapModes() {
        assertTrue(KeyboardSession.autoShiftFor("nguyễn ", CapMode.WORDS))
        assertTrue(KeyboardSession.autoShiftFor("", CapMode.WORDS))
        assertTrue(KeyboardSession.autoShiftFor("nói \"", CapMode.WORDS))
        assertFalse(KeyboardSession.autoShiftFor("nguyễn", CapMode.WORDS))
        assertTrue(KeyboardSession.autoShiftFor("abc", CapMode.CHARACTERS))
        assertFalse(KeyboardSession.autoShiftFor("xin ", CapMode.SENTENCES))
        assertEquals(CapMode.CHARACTERS, KeyboardSession.capMode(FieldTraits(capSentences = true, capCharacters = true)))
        assertEquals(CapMode.NONE, KeyboardSession.capMode(FieldTraits()))
        // ô CAP_WORDS: sau space bật shift; CAP_CHARACTERS: phím chữ cũng xin auto-shift lại
        val w = session(traits = FieldTraits(capWords = true)); val p = MockProxy()
        w.typeKeys(p, "an ")
        assertEquals(true, w.updateAutoShift(p))
        val c = session(traits = FieldTraits(capCharacters = true))
        assertTrue(c.handle(Key.Letter('A'), MockProxy()).needsAutoShift)
        assertFalse(session(traits = FieldTraits()).handle(Key.Letter('a'), MockProxy()).needsAutoShift)
    }

    @Test fun testNoPersonalizedLearning() {
        // Regression: IME_FLAG_NO_PERSONALIZED_LEARNING (Chrome ẩn danh) không được học từ.
        val s = session(traits = FieldTraits(noLearning = true)); val p = MockProxy()
        val before = s.langModel.count("người")
        s.typeKeys(p, "nguoi ")
        s.typeKeys(p, "nguoi"); s.acceptSuggestion("người", p)
        assertEquals(before, s.langModel.count("người"))
        assertNotNull(s.suggestionsNow(p))                  // gợi ý vẫn hiện
        // ô thường cùng session: học lại
        s.startInput(KeyboardSettings(), FieldTraits())
        s.typeKeys(p, "nguoi"); s.acceptSuggestion("người", p)
        assertEquals(before + 2, s.langModel.count("người"))
    }

    @Test fun testWriteModeTable() {
        assertEquals(WriteMode.KEY_ONLY, WriteMode.forPackage("com.xiaomi.wps"))
        assertEquals(WriteMode.KEY_ONLY, WriteMode.forPackage("com.xiaomi.wpsoffice"))
        assertEquals(WriteMode.KEY_ONLY, WriteMode.forPackage("com.huawei.hsl"))
        assertEquals(WriteMode.KEY_ONLY, WriteMode.forPackage("cn.wps.huawei"))
        assertEquals(WriteMode.DEL_VIA_KEY_EVENT, WriteMode.forPackage("com.onlyoffice.documents"))
        assertEquals(WriteMode.COMMIT, WriteMode.forPackage("com.huawei.hslx"))
        assertEquals(WriteMode.COMMIT, WriteMode.forPackage(null))
        assertEquals(WriteMode.COMMIT, WriteMode.forPackage("com.android.chrome"))
        assertEquals(WriteMode.KEY_ONLY, FieldTraits(packageName = "cn.wps.huawei").writeMode)
    }
}
