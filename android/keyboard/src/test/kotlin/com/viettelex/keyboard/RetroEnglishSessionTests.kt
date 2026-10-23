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

    private fun settings(contextual: Boolean = true, auto: Boolean) =
        KeyboardSettings(contextualEnglish = contextual, retroEnglishAuto = auto, simpleTelex = true, freeMarking = true)

    private fun EngineBridge.type(p: MockProxy, keys: String) {
        for (c in keys) when (c) {
            ' ' -> boundary(" ", p)
            '⏎' -> boundary("\n", p)
            '⌫' -> backspace(p)
            else -> letter(c, p)
        }
    }

    private val sentence = "His car is very fast "
    private val vietnamese = "Hí cả í very fast "
    private val english = "His car is very fast "

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
            b.type(p, "His car is very fast⏎")
            assertEquals("Hí cả í very fast\n", p.text)
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
