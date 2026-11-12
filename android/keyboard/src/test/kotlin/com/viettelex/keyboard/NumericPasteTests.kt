package com.viettelex.keyboard

import com.viettelex.keyboard.NumericPaste.Field
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test

/** Phím 📋 bàn số (báo lỗi 13/11/2026: ô số điện thoại không dán được số vừa copy). */
class NumericPasteTests {
    @Before fun setUp() { TestAssets.install() }

    @Test fun phoneStripsSeparators() {
        assertEquals("0903389710", NumericPaste.clean("0903 389 710", Field.PHONE))
        assertEquals("+84903389710", NumericPaste.clean("+84 903-389-710", Field.PHONE))
        assertEquals("0903389710", NumericPaste.clean("(090) 338.9710\n", Field.PHONE))
        assertEquals("*101#", NumericPaste.clean(" *101# ", Field.PHONE))
        // "+" giữa chuỗi bỏ; số toàn khổ đổi về ASCII
        assertEquals("0903", NumericPaste.clean("09+03", Field.PHONE))
        assertEquals("0903", NumericPaste.clean("０９０３", Field.PHONE))
    }

    @Test fun numberFieldKeepsDigitsOnly() {
        assertEquals("0903389710", NumericPaste.clean("0903 389 710", Field.NUMBER))
        assertEquals("84903389710", NumericPaste.clean("+84 903-389-710", Field.NUMBER))
        assertEquals("1000000", NumericPaste.clean("1.000.000 đ", Field.NUMBER))
        assertEquals("-25", NumericPaste.clean("-25", Field.NUMBER, signed = true))
        assertEquals("25", NumericPaste.clean("-25", Field.NUMBER))
    }

    @Test fun decimalKeepsSeparators() {
        assertEquals("1234,5", NumericPaste.clean("1 234,5", Field.DECIMAL))
        assertEquals("-3.14", NumericPaste.clean("−3.14", Field.DECIMAL, signed = true))
    }

    @Test fun datetimeOnlyTrims() {
        assertEquals("13/11/2026 10:30", NumericPaste.clean("  13/11/2026 10:30\n", Field.DATETIME))
    }

    @Test fun nothingNumericInsertsNothing() {
        assertEquals("", NumericPaste.clean("xin chào", Field.PHONE))
        assertEquals("", NumericPaste.clean("+", Field.PHONE))
        assertEquals("", NumericPaste.clean(null, Field.NUMBER))
        assertEquals("", NumericPaste.clean("", Field.DATETIME))
    }

    private class FakeClip(var text: String? = null) : ClipboardSource {
        override var changeCount = 1
        override fun hasText() = text != null
        override fun readText() = text
    }

    @Test fun sessionPasteFilteredInsertsCleanedText() {
        val clip = FakeClip("+84 903-389-710")
        val s = KeyboardSession(UserLangModel(), clip)
        s.startInput(KeyboardSettings(), FieldTraits())
        val p = MockProxy()
        assertEquals("+84903389710", s.pasteFiltered(p) { NumericPaste.clean(it, Field.PHONE) })
        assertEquals("+84903389710", p.text)
        // clipboard không có số ⇒ không chèn gì
        clip.text = "abc"
        assertEquals("", s.pasteFiltered(p) { NumericPaste.clean(it, Field.PHONE) })
        assertEquals("+84903389710", p.text)
    }
}
