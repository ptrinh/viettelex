package com.viettelex.keyboard

import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test

/**
 * Lớp ghi chữ: double-space không dùng KEYCODE_DEL bất đồng bộ; fail-safe không xoá mù
 * khi chữ trước con trỏ không còn là từ engine đang giữ.
 */
class WriteSafetyTests {
    @Before fun setUp() = TestAssets.install()

    private fun session(): KeyboardSession =
        KeyboardSession(UserLangModel()).also { it.startInput(KeyboardSettings(), FieldTraits()) }

    private fun KeyboardSession.typeKeys(p: TextProxy, keys: String) {
        for (c in keys) handle(if (c == ' ') Key.Space else Key.Letter(c), p)
    }

    /**
     * Mô phỏng AOSP: deleteBackward = KEYCODE_DEL đi hàng đợi key event, chỉ áp SAU các
     * commitText cùng batch. Trước fix double-space ra "chữ ." (xoá nhầm chữ cuối).
     */
    private class AsyncDelProxy : TextProxy {
        val sb = StringBuilder()
        private var pendingDel = 0
        override val isSecure = false
        override fun insertText(text: String) { sb.append(text) }
        override fun deleteCodePoints(count: Int) {
            repeat(count) { if (sb.isNotEmpty()) sb.setLength(sb.offsetByCodePoints(sb.length, -1)) }
        }
        override fun deleteBackward() { pendingDel++ }
        override fun contextBeforeInput(): String = sb.toString()
        /** Hết batch: key event tới. */
        fun flush() { val n = pendingDel; pendingDel = 0; deleteCodePoints(n) }
    }

    @Test fun testDoubleSpaceDoesNotUseAsyncKeyDel() {
        val s = session(); val p = AsyncDelProxy()
        s.typeKeys(p, "chuwx ")
        p.flush()
        s.handle(Key.DoubleSpacePeriod, p)
        p.flush()
        assertEquals("chữ. ", p.sb.toString())
    }

    @Test fun testLetterAfterSilentExternalChangeDoesNotBlindDelete() {
        val s = session(); val p = MockProxy()
        s.typeKeys(p, "tie")
        // App tự thay nội dung ô mà không báo selection (vd. chat app gửi rồi đặt lại chữ).
        p.sb.setLength(0); p.sb.append("xin chao ")
        s.handle(Key.Letter('e'), p)          // tiee → tiê cần xoá 1 — không được xoá "o"… của app
        assertEquals("xin chao e", p.text)
        s.typeKeys(p, "m")
        assertEquals("xin chao em", p.text)   // engine đã bắt đầu từ mới
    }

    @Test fun testBackspaceAfterSilentExternalChangeIsPlainDelete() {
        val s = session(); val p = MockProxy()
        s.typeKeys(p, "vieetj")               // việt
        p.sb.setLength(0); p.sb.append("abc")
        s.handle(Key.Backspace, p)
        assertEquals("ab", p.text)
        s.typeKeys(p, "s")                    // engine đã quên "việ" — 's' là chữ, không phải dấu
        assertEquals("abs", p.text)
    }

    @Test fun testBoundaryRestoreSkippedOnMismatch() {
        val s = session(); val p = MockProxy()
        s.typeKeys(p, "google")               // gôgle — space sẽ restore thành google (cần xoá)
        p.sb.setLength(0); p.sb.append("khác")
        s.handle(Key.Space, p)
        assertEquals("khác ", p.text)
    }

    @Test fun testAcceptSuggestionOnMismatchInsertsWithoutDeleting() {
        val s = session(); val p = MockProxy()
        s.typeKeys(p, "nguoi")
        p.sb.setLength(0); p.sb.append("ab")
        s.acceptSuggestion("người", p)
        assertEquals("abngười ", p.text)
    }

    @Test fun testConsistentFieldStillReplaces() {
        val s = session(); val p = MockProxy()
        s.typeKeys(p, "tieengs vieetj ")
        assertEquals("tiếng việt ", p.text)
    }
}
