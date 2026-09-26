package com.viettelex.keyboard

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/** Sửa dấu từ đã gõ xong: ⌫ mở lại từ vừa chốt, phím dấu nạp lại từ trước con trỏ. */
class ReEditTests {
    @Before fun setUp() = TestAssets.install()

    private fun session(model: UserLangModel = UserLangModel(), traits: FieldTraits = FieldTraits(),
                        settings: KeyboardSettings = KeyboardSettings()) =
        KeyboardSession(model).also { it.startInput(settings, traits) }

    private fun KeyboardSession.typeKeys(p: TextProxy, keys: String) {
        for (c in keys) handle(when (c) {
            ' ' -> Key.Space
            '<' -> Key.Backspace
            '\n' -> Key.Newline
            '.' -> Key.Text(".")
            else -> Key.Letter(c)
        }, p)
    }

    // MARK: ⌫ mở lại từ

    @Test fun backspaceReopensLastWord() {
        val s = session(); val p = MockProxy()
        s.typeKeys(p, "thays ")
        assertEquals("tháy ", p.text)
        s.typeKeys(p, "<")
        assertEquals("tháy", p.text)
        assertTrue(s.bridge.isComposing)
        s.typeKeys(p, "a")
        assertEquals("thấy", p.text)
        s.typeKeys(p, " ")
        assertEquals("thấy ", p.text)
    }

    @Test fun backspaceReopensAfterPunctuation() {
        val s = session(); val p = MockProxy()
        s.typeKeys(p, "xin chao.<f")
        assertEquals("xin chào", p.text)
    }

    @Test fun reopenMidSentenceKeepsEarlierText() {
        val s = session(); val p = MockProxy()
        s.typeKeys(p, "toi thays <a ")
        assertEquals("toi thấy ", p.text)
    }

    @Test fun screenMismatchDoesNotEdit() {
        val s = session(); val p = MockProxy()
        s.typeKeys(p, "thays ")
        // App tự sửa chữ mà không báo selection.
        p.sb.setLength(0); p.sb.append("khác ")
        s.typeKeys(p, "<")
        assertEquals("khác", p.text)          // ⌫ thường
        assertFalse(s.bridge.isComposing)
        s.typeKeys(p, "n")
        assertEquals("khácn", p.text)
    }

    @Test fun boundaryMissingOnScreenDoesNotEdit() {
        val s = session(); val p = MockProxy()
        s.typeKeys(p, "thays ")
        p.sb.setLength(p.sb.length - 1)       // app nuốt space
        s.typeKeys(p, "<")
        assertEquals("thá", p.text)           // ⌫ thường, không mở lại
        assertFalse(s.bridge.isComposing)
    }

    @Test fun selectionPreventsReopenAndForgets() {
        val s = session(); val p = MockProxy()
        s.typeKeys(p, "thays ")
        p.selection = true
        s.typeKeys(p, "<")
        assertFalse(s.bridge.isComposing)
        p.selection = false
        // Snapshot đã bỏ: ⌫ tiếp không được hồi sinh từ cũ.
        s.typeKeys(p, "<")
        assertFalse(s.bridge.isComposing)
    }

    @Test fun fieldWithoutReEditIsPlainBackspace() {
        val s = session(); val p = MockProxy().also { it.reEdit = false }
        s.typeKeys(p, "thays <a")
        assertEquals("tháya", p.text)
    }

    @Test fun passthroughFieldIsPlain() {
        val s = session(traits = FieldTraits(passthrough = true)); val p = MockProxy()
        s.typeKeys(p, "thays <a")
        assertEquals("thaysa", p.text)
    }

    @Test fun newlineForgetsLastWord() {
        val s = session(); val p = MockProxy()
        s.typeKeys(p, "thays\n<")
        assertFalse(s.bridge.isComposing)
    }

    @Test fun externalSelectionChangeForgets() {
        val s = session(); val p = MockProxy()
        s.typeKeys(p, "thays ")
        s.externalSelectionChange()
        s.typeKeys(p, "<")
        assertFalse(s.bridge.isComposing)
    }

    @Test fun autoRestoredWordIsNotReopened() {
        val s = session(); val p = MockProxy()
        s.typeKeys(p, "google ")
        assertEquals("google ", p.text)
        s.typeKeys(p, "<")
        assertEquals("google", p.text)
        assertFalse(s.bridge.isComposing)     // lời mời hoàn tác auto-restore giữ nguyên đường cũ
    }

    // MARK: nạp lại từ trước con trỏ

    @Test fun seedAddsToneToWordBeforeCursor() {
        val s = session(); val p = MockProxy()
        p.sb.append("viêt")
        s.typeKeys(p, "j")
        assertEquals("việt", p.text)
        s.typeKeys(p, " ")
        assertEquals("việt ", p.text)
    }

    /** Giống hệt gõ liền "vietj" (Telex: j đặt nặng, không tự thêm mũ). */
    @Test fun seedMatchesFreshTyping() {
        val fresh = MockProxy()
        session().typeKeys(fresh, "vietj")
        val s = session(); val p = MockProxy()
        p.sb.append("viet")
        s.typeKeys(p, "j")
        assertEquals(fresh.text, p.text)
        assertEquals("viẹt", p.text)
    }

    @Test fun seedHornButNotDoubledVowel() {
        // a/e/o/d KHÔNG nạp lại (user 26/09/2026): con trỏ sau "to" gõ o = "too", không "tô".
        run { val s = session(); val p = MockProxy(); p.sb.append("ban to"); s.typeKeys(p, "o"); assertEquals("ban too", p.text) }
        run { val s = session(); val p = MockProxy(); p.sb.append("co"); s.typeKeys(p, "d"); assertEquals("cod", p.text) }
        run { val s = session(); val p = MockProxy(); p.sb.append("tu"); s.typeKeys(p, "w"); assertEquals("tư", p.text) }
        run { val s = session(); val p = MockProxy(); p.sb.append("việt"); s.typeKeys(p, "z"); assertEquals("viêt", p.text) }
    }

    @Test fun midWordIsLiteral() {
        val s = session(); val p = MockProxy()
        p.sb.append("viet"); p.after = "nam"
        s.typeKeys(p, "j")
        assertEquals("vietj", p.text)
    }

    @Test fun unreadableAfterIsLiteral() {
        val s = session(); val p = MockProxy()
        p.sb.append("viet"); p.after = null
        s.typeKeys(p, "j")
        assertEquals("vietj", p.text)
    }

    @Test fun nonTransformKeyIsLiteral() {
        val s = session(); val p = MockProxy()
        p.sb.append("viet")
        s.typeKeys(p, "n")
        assertEquals("vietn", p.text)
    }

    @Test fun keyThatDoesNotTransformIsLiteral() {
        val s = session(); val p = MockProxy()
        p.sb.append("ban")                    // "band": d không có gì để lặp
        s.typeKeys(p, "d")
        assertEquals("band", p.text)
    }

    @Test fun seedSkipsGluedTokens() {
        for (ctx in listOf("mp3a", "gmail.com", "a_viet")) {
            val s = session(); val p = MockProxy()
            p.sb.append(ctx)
            s.typeKeys(p, "s")
            assertEquals(ctx + "s", p.text)
        }
    }

    @Test fun seedSkippedWithSelectionOrWithoutReEdit() {
        run { val s = session(); val p = MockProxy(); p.sb.append("viet"); p.selection = true
            s.typeKeys(p, "j"); assertEquals("vietj", p.text) }
        run { val s = session(); val p = MockProxy().also { it.reEdit = false }; p.sb.append("viet")
            s.typeKeys(p, "j"); assertEquals("vietj", p.text) }
        run { val s = session(traits = FieldTraits(passthrough = true)); val p = MockProxy(); p.sb.append("viet")
            s.typeKeys(p, "j"); assertEquals("vietj", p.text) }
    }

    @Test fun nullContextIsLiteral() {
        val s = session()
        val p = object : TextProxy {
            val sb = StringBuilder("viet")
            override val isSecure = false
            override fun insertText(text: String) { sb.append(text) }
            override fun deleteCodePoints(count: Int) { repeat(count) { sb.setLength(sb.length - 1) } }
            override fun deleteBackward() = deleteCodePoints(1)
            override fun contextBeforeInput(): String? = null
            override val canReEdit = true
            override fun contextAfterInput() = ""
        }
        s.handle(Key.Letter('j'), p)
        assertEquals("vietj", p.sb.toString())
    }

    // MARK: học từ

    @Test fun reopenAndRecommitLearnsOnce() {
        val m = UserLangModel(); val s = session(m); val p = MockProxy()
        val base = m.count("việt")
        s.typeKeys(p, "vieetj ")
        assertEquals(base + 1, m.count("việt"))
        s.typeKeys(p, "< ")
        assertEquals("việt ", p.text)
        assertEquals(base + 1, m.count("việt"))
    }

    @Test fun correctedWordReplacesWrongLearning() {
        val m = UserLangModel(); val s = session(m); val p = MockProxy()
        val wrong = m.count("tháy"); val right = m.count("thấy")
        s.typeKeys(p, "thays ")
        assertEquals(wrong + 1, m.count("tháy"))
        s.typeKeys(p, "<a ")
        assertEquals("thấy ", p.text)
        assertEquals(wrong, m.count("tháy"))
        assertEquals(right + 1, m.count("thấy"))
    }

    @Test fun reopenKeepsBigramContext() {
        val m = UserLangModel(); val s = session(m); val p = MockProxy()
        val base = m.count("chào")
        s.typeKeys(p, "xin chaof ")
        repeat(3) { s.typeKeys(p, "< ") }     // mở lại "chào" rồi chốt lại, 3 lần
        assertEquals("xin chào ", p.text)
        assertEquals(base + 1, m.count("chào"))
        // Ngữ cảnh khôi phục đúng "xin": bigram xin→chào vẫn còn.
        assertTrue("chào" in m.nextWords("xin", null, 24))
    }

    @Test fun retractRemovesCounts() {
        val m = UserLangModel()
        val l = m.record("việt", null)
        assertTrue(l != null)
        m.retract(l!!)
        assertEquals(0, m.count("việt"))
        assertNull(m.record("a1", null))      // không learnable ⇒ không biên nhận
    }

    @Test fun toggleOffDisablesReopenAndSeed() {
        val off = KeyboardSettings(reEditWords = false)
        run {   // ⌫ sau dấu cách chỉ xoá dấu cách, a gõ thành chữ mới
            val s = session(settings = off); val p = MockProxy()
            s.typeKeys(p, "thays <a"); assertEquals("tháya", p.text)
        }
        run {
            val s = session(settings = off); val p = MockProxy(); p.sb.append("xin chao")
            s.typeKeys(p, "f"); assertEquals("xin chaof", p.text)
        }
        assertTrue(KeyboardSettings().reEditWords)   // mặc định BẬT
    }
}
