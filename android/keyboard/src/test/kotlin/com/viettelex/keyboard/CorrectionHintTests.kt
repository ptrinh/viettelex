package com.viettelex.keyboard

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * ONBOARDING-SPEC §8 — tô nền gợi ý sửa khi gõ sai. Parity iOS CorrectionHintTests.
 * Ô tô nền và dấu cách dùng CHUNG một quyết định ([KeyboardSession] correctionDecision).
 */
class CorrectionHintTests {
    @Before fun setUp() = TestAssets.install()

    private val center = AutoCorrect.Touch(0f, 0f)

    private fun session(autoCorrect: Boolean = true, bar: Boolean = true, traits: FieldTraits = FieldTraits()) =
        KeyboardSession(UserLangModel(), null).also {
            it.startInput(KeyboardSettings(autoCorrect = autoCorrect, showSuggestions = bar), traits)
        }

    /** Gõ [keys] (chạm giữa phím). */
    private fun KeyboardSession.type(p: TextProxy, keys: String) {
        for (c in keys) handle(if (c == ' ') Key.Space else Key.Letter(c), p, center)
    }

    private fun slots(set: SuggestionSet): List<BarChip?> =
        (SuggestionSlots.arrange(set, undoAsPill = true, bestInMiddle = true) as BarLayout.Slots).slots

    // MARK: AutoCorrect — ứng viên chạm đúp

    @Test fun doubledKeyIsACandidateWithoutTouchEvidence() {
        val b = EngineBridge(KeyboardSettings())
        fun fix(raw: String) = AutoCorrect.correction(raw, List(raw.length) { center }, compose = { b.composeTrial(it) },
            frequency = { VNSuggest.frequency(it) },
            hasCompletion = { VNSuggest.matches(it, poolLimit = 1).isNotEmpty() },
            isKnown = { AutoCorrect.isEnglish(it) })
        assertEquals("anh", fix("anhh"))
        assertEquals("Anh", fix("Anhh"))
        assertEquals("đi", fix("ddii"))
        assertNull(fix("toii"))                                               // "toi" (100) không đủ phổ biến
        assertNull(fix("anh"))                                                // từ hợp lệ
    }

    // MARK: thanh gợi ý

    @Test fun invalidWordShowsQuotedTypedThenHighlightedFix() {
        val s = session(); val p = MockProxy()
        s.type(p, "Anhh")
        val set = s.suggestionsNow(p)!!
        assertTrue(set.correction)
        val sl = slots(set)
        assertEquals("“Anhh”", sl[0]?.label)                        // ô 1: chữ gõ trong ngoặc kép
        assertEquals(SuggestionSet.KEEP_TYPED_PREFIX + "Anhh", sl[0]?.payload)
        assertEquals("Anh", sl[1]?.label)
        assertTrue(sl[1]!!.highlight)                                         // ô giữa tô nền
        assertFalse(sl[0]!!.highlight)
        assertTrue(sl.drop(2).none { it?.highlight == true })
    }

    @Test fun validWordIsNotHighlighted() {
        val s = session(); val p = MockProxy()
        s.type(p, "anh")
        val set = s.suggestionsNow(p)!!
        assertFalse(set.correction)
        assertTrue(slots(set).none { it?.highlight == true })
        assertEquals("anh", slots(set)[0]?.label)                             // Android: nguyên văn không ngoặc kép
    }

    @Test fun spaceWithAutoCorrectAppliesExactlyTheHighlightedSlot() {
        val s = session(); val p = MockProxy()
        s.type(p, "Anhh")
        val shown = slots(s.suggestionsNow(p)!!).first { it?.highlight == true }!!.label
        s.type(p, " ")
        assertEquals("$shown ", p.text)
        assertEquals("Anh ", p.text)
    }

    @Test fun tappingQuotedSlotKeepsWordAndIsNotCorrectedNextTime() {
        val s = session(); val p = MockProxy()
        var saved = 0
        s.onAutoCorrectRejected = { saved++ }
        s.type(p, "Anhh")
        s.acceptSuggestion(slots(s.suggestionsNow(p)!!)[0]!!.payload, p)
        assertEquals("Anhh ", p.text)
        assertTrue("anhh" in s.autoCorrectRejected)
        assertEquals(1, saved)
        s.type(p, "anhh")
        assertFalse(s.suggestionsNow(p)!!.correction)                         // không tô lại
        s.type(p, " ")
        assertEquals("Anhh anhh ", p.text)                                    // không sửa lại
    }

    @Test fun autoCorrectOffShowsHintButSpaceDoesNotCorrect() {
        val s = session(autoCorrect = false); val p = MockProxy()
        assertTrue(s.wantsTouches)                                            // thanh gợi ý bật ⇒ cần điểm chạm
        s.type(p, "Anhh")
        val sl = slots(s.suggestionsNow(p)!!)
        assertEquals("Anh", sl[1]?.label)
        assertTrue(sl[1]!!.highlight)
        s.type(p, " ")
        assertEquals("Anhh ", p.text)
    }

    @Test fun barOffCostsNothing() {
        assertFalse(session(autoCorrect = false, bar = false).wantsTouches)   // không ghi điểm chạm
        val s = session(autoCorrect = true, bar = false); val p = MockProxy()
        s.type(p, "Anhh ")
        assertEquals("Anh ", p.text)                                          // tự sửa vẫn chạy như cũ
    }

    /** Hoa giữa câu = tên riêng: dấu cách không sửa ⇒ không tô (thanh và dấu cách không lệch nhau). */
    @Test fun noHighlightWhereSpaceWouldNotCorrect() {
        val s = session(); val p = MockProxy()
        p.insertText("gặp ")
        s.type(p, "Anhh")
        assertFalse(s.suggestionsNow(p)!!.correction)
        s.type(p, " ")
        assertEquals("gặp Anhh ", p.text)
        val name = session(traits = FieldTraits(capWords = true)); val q = MockProxy()
        assertFalse(name.wantsTouches)                                        // ô tên: không tự sửa, không tô
    }

    @Test fun arrangeHighlightFollowsWordAcrossLayouts() {
        val set = SuggestionSet(literal = "Anhh", word = "Anh", word2 = "ánh", correction = true)
        val one = (SuggestionSlots.arrange(set, undoAsPill = true, bestInMiddle = true, count = 1) as BarLayout.Slots).slots
        assertEquals(BarChip("Anh", "Anh", highlight = true), one[0])
        val five = (SuggestionSlots.arrange(set, undoAsPill = true, bestInMiddle = true, count = 5) as BarLayout.Slots).slots
        assertEquals(listOf(false, true, false), five.take(3).map { it?.highlight })
        val plain = slots(set.copy(correction = false))
        assertEquals("Anhh", plain[0]?.payload)
        assertTrue(plain.none { it?.highlight == true })
    }

    @Test fun correctionHintReordersExistingCandidatesOnly() {
        val set = SuggestionSet(literal = "anhh", word = "ánh", word2 = "Anh", emojis = listOf("x"))
        val h = CorrectionHint.apply(set, typed = "Anhh", fix = "Anh", need = 2)
        assertEquals("Anhh", h.literal)
        assertEquals("Anh", h.word)
        assertEquals("ánh", h.word2)                                          // ứng viên kế, bỏ trùng
        assertTrue(h.emojis.isEmpty())
        assertTrue(h.correction)
    }
}
