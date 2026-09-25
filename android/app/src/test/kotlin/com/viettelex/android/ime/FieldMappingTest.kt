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
        assertTrue(m(TYPE_CLASS_TEXT or TYPE_TEXT_VARIATION_URI).passthrough)
        assertTrue(m(TYPE_CLASS_TEXT or TYPE_TEXT_VARIATION_EMAIL_ADDRESS).passthrough)
        assertTrue(m(TYPE_CLASS_TEXT or TYPE_TEXT_VARIATION_WEB_EMAIL_ADDRESS).passthrough)
        assertTrue(m(TYPE_CLASS_TEXT or TYPE_TEXT_VARIATION_VISIBLE_PASSWORD).passthrough)
        assertTrue(m(TYPE_CLASS_TEXT or TYPE_TEXT_VARIATION_FILTER).passthrough)
        assertFalse(m(TYPE_CLASS_TEXT or TYPE_TEXT_VARIATION_SHORT_MESSAGE).passthrough)
        assertFalse(m(TYPE_CLASS_TEXT or TYPE_TEXT_VARIATION_PERSON_NAME).passthrough)
    }

    @Test fun kinds() {
        assertEquals(InputKind.EMAIL, m(TYPE_CLASS_TEXT or TYPE_TEXT_VARIATION_EMAIL_ADDRESS).kind)
        assertEquals(InputKind.URL, m(TYPE_CLASS_TEXT or TYPE_TEXT_VARIATION_URI).kind)
        assertEquals(InputKind.NUMBER, m(TYPE_CLASS_PHONE).kind)
        assertEquals(InputKind.NUMBER, m(TYPE_CLASS_DATETIME).kind)
        assertEquals(InputKind.NUMBER, m(TYPE_CLASS_NUMBER or TYPE_NUMBER_FLAG_DECIMAL).kind)
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
}
