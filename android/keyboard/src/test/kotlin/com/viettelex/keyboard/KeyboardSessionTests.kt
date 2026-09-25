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
}
