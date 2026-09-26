package com.viettelex.android.ime

import android.text.InputType.*
import android.view.inputmethod.EditorInfo
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class FieldMappingTest {
    private fun m(type: Int, opts: Int = 0) = FieldMapping.map(type, opts)

    @Test fun plainTextTypesTelex() {
        val f = m(TYPE_CLASS_TEXT or TYPE_TEXT_FLAG_CAP_SENTENCES)
        assertFalse(f.passthrough); assertFalse(f.isSecure)
        assertTrue(f.capSentences); assertTrue(f.suggestionsAllowed)
        assertEquals(InputKind.NORMAL, f.kind)
    }

    @Test fun noSuggestionsOnlyHidesBar() {
        // Quyết định §12: nhiều app chat đặt NO_SUGGESTIONS — Telex vẫn chạy.
        val f = m(TYPE_CLASS_TEXT or TYPE_TEXT_FLAG_NO_SUGGESTIONS)
        assertFalse(f.passthrough)
        assertFalse(f.suggestionsAllowed)
    }

    @Test fun passwordsAreSecureLiteral() {
        for (v in listOf(TYPE_TEXT_VARIATION_PASSWORD, TYPE_TEXT_VARIATION_WEB_PASSWORD, TYPE_TEXT_VARIATION_VISIBLE_PASSWORD)) {
            val f = m(TYPE_CLASS_TEXT or v)
            assertTrue(f.isSecure); assertFalse(f.suggestionsAllowed)
        }
        val pin = m(TYPE_CLASS_NUMBER or TYPE_NUMBER_VARIATION_PASSWORD)
        assertTrue(pin.isSecure); assertEquals(InputKind.NUMBER, pin.kind)
    }

    @Test fun passthroughVariations() {
        // Regression: thanh địa chỉ Chrome (URI) và ô tìm (FILTER) phải gõ được tiếng Việt.
        assertFalse(m(TYPE_CLASS_TEXT or TYPE_TEXT_VARIATION_URI).passthrough)
        assertTrue(m(TYPE_CLASS_TEXT or TYPE_TEXT_VARIATION_EMAIL_ADDRESS).passthrough)
        assertTrue(m(TYPE_CLASS_TEXT or TYPE_TEXT_VARIATION_WEB_EMAIL_ADDRESS).passthrough)
        assertTrue(m(TYPE_CLASS_TEXT or TYPE_TEXT_VARIATION_VISIBLE_PASSWORD).passthrough)
        assertFalse(m(TYPE_CLASS_TEXT or TYPE_TEXT_VARIATION_FILTER).passthrough)
        assertFalse(m(TYPE_CLASS_TEXT or TYPE_TEXT_VARIATION_SHORT_MESSAGE).passthrough)
        assertFalse(m(TYPE_CLASS_TEXT or TYPE_TEXT_VARIATION_PERSON_NAME).passthrough)
    }

    @Test fun kinds() {
        assertEquals(InputKind.EMAIL, m(TYPE_CLASS_TEXT or TYPE_TEXT_VARIATION_EMAIL_ADDRESS).kind)
        assertEquals(InputKind.URL, m(TYPE_CLASS_TEXT or TYPE_TEXT_VARIATION_URI).kind)
        assertEquals(InputKind.PHONE, m(TYPE_CLASS_PHONE).kind)
        assertEquals(InputKind.DATETIME, m(TYPE_CLASS_DATETIME).kind)
        assertEquals(InputKind.NUMBER, m(TYPE_CLASS_NUMBER or TYPE_NUMBER_FLAG_DECIMAL).kind)
        assertEquals(Plane.PHONE, InputKind.PHONE.padPlane)
        assertEquals(Plane.NUMPAD, InputKind.NUMBER.padPlane)
        assertEquals(Plane.NUMPAD, InputKind.DATETIME.padPlane)
        assertEquals(null, InputKind.NORMAL.padPlane)
    }

    @Test fun numberFlags() {
        val plain = m(TYPE_CLASS_NUMBER)
        assertFalse(plain.numberSigned); assertFalse(plain.numberDecimal)
        val web = m(0x6002)   // <input type=number> Chrome: NUMBER | DECIMAL | 0x4000 (không SIGNED)
        assertEquals(InputKind.NUMBER, web.kind)
        assertTrue(web.numberSigned); assertTrue(web.numberDecimal)   // web number cho số âm → có "−"
        val signed = m(TYPE_CLASS_NUMBER or TYPE_NUMBER_FLAG_SIGNED)
        assertTrue(signed.numberSigned); assertFalse(signed.numberDecimal)
        val tel = m(0x4003)   // <input type=tel> Chrome
        assertEquals(InputKind.PHONE, tel.kind)
        assertFalse(tel.numberSigned)
        // cờ số không rò sang lớp khác (bit 0x1000 của TEXT là CAP_CHARACTERS)
        assertFalse(m(TYPE_CLASS_TEXT or 0x1000).numberSigned)
    }

    @Test fun numericPadsAreLiteralWithoutBar() {
        for (t in listOf(TYPE_CLASS_NUMBER, TYPE_CLASS_PHONE, TYPE_CLASS_DATETIME, 0x6002, 0x4003)) {
            val f = m(t)
            assertTrue(f.passthrough); assertFalse(f.suggestionsAllowed)
        }
        val pin = m(TYPE_CLASS_NUMBER or TYPE_NUMBER_VARIATION_PASSWORD)
        assertTrue(pin.isSecure); assertTrue(pin.passthrough)
        assertEquals(Plane.NUMPAD, pin.kind.padPlane)
    }

    @Test fun typeNullIsRawLiteral() {
        val f = m(TYPE_NULL)
        assertTrue(f.rawKeys); assertTrue(f.passthrough); assertFalse(f.suggestionsAllowed)
        assertEquals(0, f.actionId)
    }

    @Test fun returnKeyLabels() {
        val t = TYPE_CLASS_TEXT
        assertEquals("go", m(t, EditorInfo.IME_ACTION_GO).returnLabel)
        assertEquals("search", m(t, EditorInfo.IME_ACTION_SEARCH).returnLabel)
        assertEquals("send", m(t, EditorInfo.IME_ACTION_SEND).returnLabel)
        assertEquals("next", m(t, EditorInfo.IME_ACTION_NEXT).returnLabel)
        assertEquals("done", m(t, EditorInfo.IME_ACTION_DONE).returnLabel)
        assertEquals(EditorInfo.IME_ACTION_SEND, m(t, EditorInfo.IME_ACTION_SEND).actionId)
        assertEquals("return", m(t, EditorInfo.IME_ACTION_UNSPECIFIED).returnLabel)
        assertEquals(0, m(t, EditorInfo.IME_ACTION_NONE).actionId)
    }

    @Test fun multilineOrNoEnterActionIsNewline() {
        val ml = m(TYPE_CLASS_TEXT or TYPE_TEXT_FLAG_MULTI_LINE, EditorInfo.IME_ACTION_SEND)
        assertEquals("return", ml.returnLabel); assertEquals(0, ml.actionId)
        val ne = m(TYPE_CLASS_TEXT, EditorInfo.IME_ACTION_SEND or EditorInfo.IME_FLAG_NO_ENTER_ACTION)
        assertEquals("return", ne.returnLabel); assertEquals(0, ne.actionId)
    }

    @Test fun noPersonalizedLearningFlag() {
        // Regression: Chrome ẩn danh đặt IME_FLAG_NO_PERSONALIZED_LEARNING — trước đây bị bỏ qua.
        val inc = m(TYPE_CLASS_TEXT or TYPE_TEXT_VARIATION_URI, EditorInfo.IME_FLAG_NO_PERSONALIZED_LEARNING)
        assertTrue(inc.noLearning); assertFalse(inc.passthrough); assertTrue(inc.suggestionsAllowed)
        assertFalse(m(TYPE_CLASS_TEXT).noLearning)
    }

    @Test fun allThreeCapModes() {
        // Regression: trước chỉ đọc CAP_SENTENCES.
        assertTrue(m(TYPE_CLASS_TEXT or TYPE_TEXT_FLAG_CAP_WORDS).capWords)
        assertTrue(m(TYPE_CLASS_TEXT or TYPE_TEXT_FLAG_CAP_CHARACTERS).capCharacters)
        val plain = m(TYPE_CLASS_TEXT)
        assertFalse(plain.capSentences); assertFalse(plain.capWords); assertFalse(plain.capCharacters)
        // bit 0x1000 của lớp NUMBER không phải CAP_CHARACTERS
        assertFalse(m(TYPE_CLASS_NUMBER or 0x1000).capCharacters)
    }

    @Test fun pixelLauncherSearchGetsSearchKey() {
        // Regression (HeliBoard #1989): Pixel Launcher đặt MULTI_LINE + NO_ENTER_ACTION cho ô tìm.
        val type = TYPE_CLASS_TEXT or TYPE_TEXT_FLAG_MULTI_LINE
        val opts = EditorInfo.IME_ACTION_SEARCH or EditorInfo.IME_FLAG_NO_ENTER_ACTION
        val px = FieldMapping.map(type, opts, FieldMapping.PIXEL_LAUNCHER)
        assertEquals("search", px.returnLabel); assertEquals(EditorInfo.IME_ACTION_SEARCH, px.actionId)
        // app khác cùng cờ vẫn xuống dòng
        val other = FieldMapping.map(type, opts, "com.example.notes")
        assertEquals("return", other.returnLabel); assertEquals(0, other.actionId)
    }

    @Test fun customActionLabelPerformsCustomActionId() {
        val f = FieldMapping.map(TYPE_CLASS_TEXT, EditorInfo.IME_FLAG_NO_ENTER_ACTION, null,
            hasActionLabel = true, customActionId = 42)
        assertEquals(42, f.actionId); assertEquals("done", f.returnLabel)
        // ô nhiều dòng: vẫn xuống dòng
        val ml = FieldMapping.map(TYPE_CLASS_TEXT or TYPE_TEXT_FLAG_MULTI_LINE, 0, null,
            hasActionLabel = true, customActionId = 42)
        assertEquals(0, ml.actionId)
        // nhãn không kèm actionId → như thường
        assertEquals(EditorInfo.IME_ACTION_SEND, FieldMapping.map(TYPE_CLASS_TEXT, EditorInfo.IME_ACTION_SEND,
            null, hasActionLabel = true, customActionId = 0).actionId)
    }

    @Test fun contradictoryNoSuggestionsIgnored() {
        // Regression: Google Keep đặt NO_SUGGESTIONS kèm AUTO_CORRECT/AUTO_COMPLETE → bar phải hiện.
        assertTrue(m(TYPE_CLASS_TEXT or TYPE_TEXT_FLAG_NO_SUGGESTIONS or TYPE_TEXT_FLAG_AUTO_CORRECT).suggestionsAllowed)
        assertTrue(m(TYPE_CLASS_TEXT or TYPE_TEXT_FLAG_NO_SUGGESTIONS or TYPE_TEXT_FLAG_AUTO_COMPLETE).suggestionsAllowed)
        assertFalse(m(TYPE_CLASS_TEXT or TYPE_TEXT_FLAG_NO_SUGGESTIONS).suggestionsAllowed)
    }

    @Test fun forceAsciiIsLiteral() {
        val f = m(TYPE_CLASS_TEXT, EditorInfo.IME_FLAG_FORCE_ASCII)
        assertTrue(f.passthrough); assertFalse(f.isSecure); assertFalse(f.suggestionsAllowed)
    }

    @Test fun multilineVisiblePasswordIsChatNotPassword() {
        // Regression: app RN/Flutter dùng VISIBLE_PASSWORD để tắt gợi ý ô chat → vẫn gõ Telex.
        val chat = m(TYPE_CLASS_TEXT or TYPE_TEXT_VARIATION_VISIBLE_PASSWORD or TYPE_TEXT_FLAG_MULTI_LINE)
        assertFalse(chat.isSecure); assertFalse(chat.passthrough); assertFalse(chat.suggestionsAllowed)
        val pw = m(TYPE_CLASS_TEXT or TYPE_TEXT_VARIATION_VISIBLE_PASSWORD)
        assertTrue(pw.isSecure); assertTrue(pw.passthrough)
    }
}
