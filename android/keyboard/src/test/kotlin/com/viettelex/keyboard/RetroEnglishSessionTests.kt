package com.viettelex.keyboard

import org.junit.Before
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * "Tự sửa từ phía trước" — sửa ngược tiếng Anh ở bàn phím Android (EngineBridge + KeyboardSession).
 * Engine: docs/DESIGN.md "Sửa ngược tiếng Anh". Công tắc TẮT ⇒ chỉ mời qua chip; BẬT ⇒ tự áp +
 * chip "Khôi phục" / ⌫ ngay sau trả lại. contextualEnglish TẮT ⇒ không gì cả. Song sinh iOS
 * RetroEnglishBridgeTests.
 */
class RetroEnglishSessionTests {
    @Before fun setUp() = TestAssets.install()

    private fun settings(contextual: Boolean = true, auto: Boolean, frequency: Boolean = false) =
        KeyboardSettings(contextualEnglish = contextual, retroEnglishAuto = auto, simpleTelex = true, freeMarking = true,
            englishByFrequency = frequency)

    private fun EngineBridge.type(p: TextProxy, keys: String) {
        for (c in keys) when (c) {
            ' ' -> boundary(" ", p)
            '⏎' -> boundary("\n", p)
            '⌫' -> backspace(p)
            else -> letter(c, p)
        }
    }

    // Từ Anh MẠNH "fast" chốt mạch một mình: phép sửa đến ở chính "fast" (05/11/2026; trước đó
    // "very fast" — giờ "very" đã bắn sớm một từ nên bỏ khỏi câu mẫu, như iOS).
    private val sentence = "His car is fast "
    private val vietnamese = "Hí cả í fast "
    private val english = "His car is fast "

    // MARK: cài đặt

    @Test fun switchVisibleOnlyWithContextualEnglish() {
        assertTrue(RetroEnglishUI.switchVisible(contextualEnglish = true))
        assertFalse(RetroEnglishUI.switchVisible(contextualEnglish = false))
        assertFalse(RetroEnglishUI.switchVisible(contextualEnglish = true, vniMode = true))
    }

    @Test fun settingDefaultOffLoadsAndBacksUp() {
        assertFalse(KeyboardSettings().retroEnglishAuto)
        assertEquals("retroactiveEnglish", Keys.RETRO_ENGLISH_AUTO)          // cùng key macOS/iOS
        assertTrue(KeyboardSettings.load { if (it == Keys.RETRO_ENGLISH_AUTO) true else null }.retroEnglishAuto)
        assertTrue(BackupSettings.all.any { it.key == Keys.RETRO_ENGLISH_AUTO })
        assertTrue(Keys.RETRO_ENGLISH_AUTO in Keys.ENGINE_KEYS)
    }

    @Test fun frequencySettingDefaultOffLoadsAndBacksUp() {
        assertFalse(KeyboardSettings().englishByFrequency)
        assertEquals("englishByFrequency", Keys.ENGLISH_BY_FREQUENCY)       // cùng key macOS/iOS
        assertTrue(KeyboardSettings.load { if (it == Keys.ENGLISH_BY_FREQUENCY) true else null }.englishByFrequency)
        assertTrue(BackupSettings.all.any { it.key == Keys.ENGLISH_BY_FREQUENCY })
        assertTrue(Keys.ENGLISH_BY_FREQUENCY in Keys.ENGINE_KEYS)
    }

    // MARK: đoán từ trùng theo tần suất — lật lại luôn tự áp

    /** Ghi lại chữ trên màn hình ngay lúc "\n" được chèn (lật lại phải xong TRƯỚC Enter). */
    private class EnterSpy(val inner: MockProxy) : TextProxy by inner {
        var textAtEnter: String? = null
        override fun insertText(text: String) {
            if (text.contains('\n')) textAtEnter = inner.text
            inner.insertText(text)
        }
    }

    @Test fun frequencyFlipAppliesInOfferMode() {
        val p = MockProxy(); val b = EngineBridge(settings(auto = false, frequency = true))
        b.type(p, "his ")
        assertEquals("his ", p.text)                                       // đầu cụm: tiếng Anh
        b.type(p, "huwngr ")
        assertEquals("hí hửng ", p.text)                                   // lật lại, không chờ chip
        assertNull(b.retroOffer)
        assertFalse(b.retroUndoAvailable)
    }

    @Test fun frequencyFlipAppliesBeforeEnter() {
        for (auto in listOf(false, true)) {
            val spy = EnterSpy(MockProxy()); val b = EngineBridge(settings(auto = auto, frequency = true))
            b.type(spy, "his huwngr⏎")
            assertEquals("hí hửng", spy.textAtEnter)
            assertEquals("hí hửng\n", spy.inner.text)
            assertNull(b.retroOffer)
        }
    }

    @Test fun frequencyFlipSkippedOnMismatch() {
        val inner = MockProxy()
        val lying = object : TextProxy by inner {
            override fun contextBeforeInput(): String = "khác hẳn"
        }
        val b = EngineBridge(settings(auto = false, frequency = true))
        for (c in "his huwngr ") if (c == ' ') b.boundary(" ", lying) else b.letter(c, lying)
        assertEquals("his hửng ", inner.text)
        assertNull(b.retroOffer)                                           // lệch: bỏ, không mời
    }

    @Test fun frequencyOffKeepsVietnamese() {
        val p = MockProxy(); val b = EngineBridge(settings(auto = false, frequency = false))
        b.type(p, "his huwngr ")
        assertEquals("hí hửng ", p.text)
        val p2 = MockProxy(); val b2 = EngineBridge(settings(auto = false, frequency = false))
        b2.type(p2, "his ")
        assertEquals("hí ", p2.text)
    }

    @Test fun sessionFrequencyFlipInChipMode() {
        val s = KeyboardSession(UserLangModel(), null)
            .also { it.startInput(settings(auto = false, frequency = true).also { st -> st.autoCapitalize = false }, FieldTraits()) }
        val p = MockProxy()
        s.type(p, "his huwngr ")
        assertEquals("hí hửng ", p.text)
        assertFalse(s.suggestionsNow(p)?.action == SuggestionSet.RETRO_OFFER_TOKEN)
        val s2 = KeyboardSession(UserLangModel(), null)
            .also { it.startInput(settings(auto = false, frequency = true).also { st -> st.autoCapitalize = false }, FieldTraits()) }
        val spy = EnterSpy(MockProxy())
        s2.type(spy, "his huwngr")
        s2.handle(Key.Newline, spy)
        assertEquals("hí hửng", spy.textAtEnter)
        assertEquals("hí hửng\n", spy.inner.text)
    }

    // MARK: bridge — công tắc TẮT

    @Test fun offerWhenSwitchOff() {
        val p = MockProxy(); val b = EngineBridge(settings(auto = false))
        b.type(p, sentence)
        assertEquals(vietnamese, p.text)                                   // KHÔNG tự viết lại
        val c = assertNotNull(b.retroOffer)
        assertFalse(b.retroUndoAvailable)
        assertEquals("His car is", EngineBridge.retroLabel(c, p.text))
        assertTrue(b.applyRetroOffer(p))
        assertEquals(english, p.text)
        assertNull(b.retroOffer)
        assertFalse(b.applyRetroOffer(p))
    }

    @Test fun offerGoneOnNextKey() {
        val p = MockProxy(); val b = EngineBridge(settings(auto = false))
        b.type(p, sentence)
        b.type(p, "n")
        assertNull(b.retroOffer)
        val p2 = MockProxy(); val b2 = EngineBridge(settings(auto = false))
        b2.type(p2, sentence)
        b2.type(p2, "⌫")
        assertNull(b2.retroOffer)
    }

    @Test fun offerMismatchDoesNotEdit() {
        val p = MockProxy(); val b = EngineBridge(settings(auto = false))
        b.type(p, sentence)
        p.sb.setLength(0); p.sb.append("Hi ca i very fast ")              // host đổi chữ
        assertFalse(b.applyRetroOffer(p))
        assertEquals("Hi ca i very fast ", p.text)
    }

    // MARK: bridge — công tắc BẬT

    @Test fun autoApplyAndRestore() {
        val p = MockProxy(); val b = EngineBridge(settings(auto = true))
        b.type(p, sentence)
        assertEquals(english, p.text)
        assertNull(b.retroOffer)
        assertTrue(b.retroUndoAvailable)
        assertTrue(b.revertRetro(p))
        assertEquals(vietnamese, p.text)
        assertFalse(b.retroUndoAvailable)
        assertFalse(b.revertRetro(p))
    }

    @Test fun backspaceRightAfterAutoFixRestores() {
        val p = MockProxy(); val b = EngineBridge(settings(auto = true))
        b.type(p, sentence)
        b.type(p, "⌫")
        assertEquals(vietnamese, p.text)                                   // ⌫ đầu = Khôi phục
        assertTrue(b.revertedRetro)
        b.revertedRetro = false
        b.type(p, "⌫")                                                     // ⌫ kế: xoá thường
        assertEquals(vietnamese.dropLast(1), p.text)
    }

    @Test fun backspaceAfterAutoFixMismatchIsNormalDelete() {
        val p = MockProxy(); val b = EngineBridge(settings(auto = true))
        b.type(p, sentence)
        p.insertText(" ")                                                  // host thêm chữ
        b.type(p, "⌫")
        assertEquals(english, p.text)
        assertFalse(b.revertedRetro)
        val p2 = MockProxy(); val b2 = EngineBridge(settings(auto = true))
        b2.type(p2, sentence)
        p2.sb.setLength(0); p2.sb.append("x")
        assertFalse(b2.revertRetro(p2))
        assertEquals("x", p2.text)
    }

    @Test fun autoApplyMismatchDoesNotEdit() {
        val inner = MockProxy()
        val lying = object : TextProxy {
            override fun insertText(text: String) = inner.insertText(text)
            override fun deleteCodePoints(count: Int) = inner.deleteCodePoints(count)
            override fun deleteBackward() = inner.deleteBackward()
            override val isSecure = false
            override fun contextBeforeInput(): String = "khác hẳn"
        }
        val b = EngineBridge(settings(auto = true))
        for (c in sentence) if (c == ' ') b.boundary(" ", lying) else b.letter(c, lying)
        assertEquals(vietnamese, inner.text)
        assertFalse(b.retroUndoAvailable)
        assertNull(b.retroOffer)
    }

    @Test fun enterNeverRewrites() {
        for (auto in listOf(false, true)) {
            val p = MockProxy(); val b = EngineBridge(settings(auto = auto))
            b.type(p, "His car is fast⏎")
            assertEquals("Hí cả í fast\n", p.text)
            assertNull(b.retroOffer)
            assertFalse(b.retroUndoAvailable)
        }
    }

    @Test fun contextualEnglishOffDoesNothing() {
        for (auto in listOf(false, true)) {
            val p = MockProxy(); val b = EngineBridge(settings(contextual = false, auto = auto))
            b.type(p, sentence)
            assertTrue(p.text.startsWith("Hí cả í "), p.text)
            assertNull(b.retroOffer)
            assertFalse(b.retroUndoAvailable)
            b.type(p, "⌫")
            assertFalse(b.revertedRetro)
        }
    }

    // MARK: session — chip trên thanh gợi ý

    private fun session(auto: Boolean, contextual: Boolean = true) =
        KeyboardSession(UserLangModel(), null).also { it.startInput(settings(contextual, auto), FieldTraits()) }

    private fun KeyboardSession.type(p: TextProxy, keys: String) {
        for (c in keys) handle(when (c) { ' ' -> Key.Space; '⌫' -> Key.Backspace; else -> Key.Letter(c) }, p)
    }

    @Test fun sessionOfferChipAppliesOnTap() {
        val s = session(auto = false); val p = MockProxy()
        s.type(p, sentence)
        assertEquals(vietnamese, p.text)
        val set = s.suggestionsNow(p)!!
        assertEquals(SuggestionSet.RETRO_OFFER_TOKEN, set.action)
        assertEquals("His car is", set.actionLabel)
        val l = SuggestionSlots.arrange(set, undoAsPill = true, bestInMiddle = true) as BarLayout.Slots
        assertEquals(SuggestionSet.RETRO_OFFER_TOKEN, l.slots[0]?.payload)  // chip dẫn đầu
        s.acceptSuggestion(SuggestionSet.RETRO_OFFER_TOKEN, p)
        assertEquals(english, p.text)
        assertFalse(s.suggestionsNow(p)?.action == SuggestionSet.RETRO_OFFER_TOKEN)
    }

    @Test fun sessionOfferChipGoneOnNextKey() {
        val s = session(auto = false); val p = MockProxy()
        s.type(p, sentence)
        s.type(p, "n")
        s.type(p, "⌫")
        assertFalse(s.suggestionsNow(p)?.action == SuggestionSet.RETRO_OFFER_TOKEN)
        s.acceptSuggestion(SuggestionSet.RETRO_OFFER_TOKEN, p)              // chạm chip cũ: không làm gì
        assertEquals(vietnamese, p.text)
    }

    @Test fun sessionAutoFixShowsRestoreChip() {
        val s = session(auto = true); val p = MockProxy()
        s.type(p, sentence)
        assertEquals(english, p.text)
        val set = s.suggestionsNow(p)!!
        assertEquals(SuggestionSet.UNDO_RETRO_TOKEN, set.action)
        assertEquals("↩︎ Khôi phục", set.actionLabel)
        s.acceptSuggestion(SuggestionSet.UNDO_RETRO_TOKEN, p)
        assertEquals(vietnamese, p.text)
        assertFalse(s.suggestionsNow(p)?.action == SuggestionSet.UNDO_RETRO_TOKEN)
    }

    /**
     * SETTINGS-CLEANUP-SPEC §2: chip mời + chip hoàn tác thực sự lên thanh gợi ý — dẫn đầu ô 0 ở mọi
     * số ô (StripView dùng đúng SuggestionSlots.arrange này), nhãn không rỗng, chạm = payload đúng.
     */
    @Test fun retroChipsLeadTheBarAtEverySlotCount() {
        for (auto in listOf(false, true)) {
            val s = session(auto = auto); val p = MockProxy()
            s.type(p, sentence)
            val set = s.suggestionsNow(p)!!
            val token = if (auto) SuggestionSet.UNDO_RETRO_TOKEN else SuggestionSet.RETRO_OFFER_TOKEN
            assertEquals(token, set.action)
            for (n in 1..5) {
                val l = SuggestionSlots.arrange(set, undoAsPill = true, bestInMiddle = true, count = n) as BarLayout.Slots
                assertEquals(n, l.slots.size)
                val lead = assertNotNull(l.slots[0], "auto=$auto n=$n")
                assertEquals(token, lead.payload)
                assertTrue(lead.label.isNotBlank())
            }
        }
        L10n.lang = "en"
        try { assertEquals("↩︎ Undo", EngineBridge.RETRO_UNDO_LABEL) } finally { L10n.lang = L10n.DEFAULT }
    }

    @Test fun sessionBackspaceRightAfterAutoFixRestores() {
        val s = session(auto = true); val p = MockProxy()
        s.type(p, sentence)
        s.type(p, "⌫")
        assertEquals(vietnamese, p.text)
        assertFalse(s.suggestionsNow(p)?.action == SuggestionSet.UNDO_RETRO_TOKEN)
        s.type(p, "⌫")
        assertEquals(vietnamese.dropLast(1), p.text)
    }

    @Test fun sessionRestoreChipGoneOnNextKey() {
        val s = session(auto = true); val p = MockProxy()
        s.type(p, sentence)
        s.type(p, "n")
        assertFalse(s.suggestionsNow(p)?.action == SuggestionSet.UNDO_RETRO_TOKEN)
    }

    @Test fun sessionContextualOffNoChip() {
        for (auto in listOf(false, true)) {
            val s = session(auto = auto, contextual = false); val p = MockProxy()
            s.type(p, sentence)
            val a = s.suggestionsNow(p)?.action
            assertFalse(a == SuggestionSet.RETRO_OFFER_TOKEN || a == SuggestionSet.UNDO_RETRO_TOKEN)
            assertTrue(p.text.startsWith("Hí cả í "), p.text)
        }
    }
}
