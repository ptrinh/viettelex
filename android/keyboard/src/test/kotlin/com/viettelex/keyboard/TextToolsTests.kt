package com.viettelex.keyboard

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.text.Normalizer

/**
 * Công cụ văn bản theo fixture chung iOS/KeyboardTests/Fixtures/text-tools.txt (cùng bộ ca
 * với iOS TextToolsTests.swift) + luồng thay chữ trên proxy giả (chọn / trước con trỏ /
 * fail-safe / hoàn tác). Luồng qua IcProxy thật: app TextToolsIcProxyTest.
 */
class TextToolsTests {
    private fun nfd(s: String) = Normalizer.normalize(s, Normalizer.Form.NFD)
    private fun decode(s: String) = s.replace("␣", " ").replace("⏎", "\n")

    @Test fun fixture() {
        val f = listOf("../../iOS", "../iOS", "iOS").map { File(it, "KeyboardTests/Fixtures/text-tools.txt") }
            .firstOrNull { it.exists() } ?: error("không thấy iOS/KeyboardTests/Fixtures/text-tools.txt")
        var n = 0
        for (line in f.readLines()) {
            if (line.isEmpty() || line.startsWith("#")) continue
            val c = line.split("|")
            assertEquals("dòng fixture lạ: $line", 3, c.size)
            val op = c[0].split("@")
            val tool = TextTool.byId(op[0]) ?: error("op lạ ${c[0]}")
            val input = decode(c[1]).let { if (op.size > 1) nfd(it) else it }
            val expected = decode(c[2])
            assertEquals("${c[0]} «$input»", expected, TextTools.apply(tool, input))
            n++
        }
        assertTrue(n > 140)
    }

    /** 67 chữ có dấu × hoa/thường = 134: khứ hồi HOA ⇄ thường, xoá dấu ra đúng chữ gốc. */
    @Test fun allVietnameseLettersRoundTrip() {
        val tones = listOf("̀", "́", "̃", "̉", "̣")
        val lower = ArrayList<String>()
        for (v in "aăâeêioôơuưy") {
            if (v !in "aeiouy") lower += v.toString()
            for (t in tones) lower += TextTools.nfc("$v$t")
        }
        lower += "đ"
        assertEquals(67, lower.size)
        for (l in lower) {
            val u = TextTools.apply(TextTool.UPPER, l)
            assertEquals("«$l» HOA phải là 1 ký tự dựng sẵn", 1, u.codePointCount(0, u.length))
            assertNotEquals(l, u)
            assertEquals(l, TextTools.apply(TextTool.LOWER, u))
            assertEquals(u, TextTools.apply(TextTool.UPPER, u))
            assertEquals(u, TextTools.apply(TextTool.TITLE, l))
            assertEquals(u, TextTools.apply(TextTool.SENTENCE, u))
            assertEquals(u, TextTools.apply(TextTool.UPPER, nfd(l)))
            val plain = TextTools.apply(TextTool.STRIP_DIACRITICS, l)
            val want = if (l == "đ") "d" else nfd(l).substring(0, 1)
            assertEquals("xoá dấu «$l»", want, plain)
            assertEquals(plain.uppercase(), TextTools.apply(TextTool.STRIP_DIACRITICS, u))
        }
    }

    // --- nguồn chữ ---

    @Test fun sourcePrefersSelection() {
        assertEquals(TextTools.Source("chào", true), TextTools.source("chào", "xin "))
        assertEquals(TextTools.Source("xin chào", false), TextTools.source("  ", "xin chào"))
    }

    @Test fun sourceStopsAtNewline() {
        assertEquals(TextTools.Source("dòng hai ", false), TextTools.source(null, "dòng một\ndòng hai "))
        assertEquals(TextTools.Source("bé", false), TextTools.source(null, "a\r\nbé"))
        assertNull(TextTools.source(null, "chữ\n"))
        assertNull(TextTools.source(null, "123 !"))
        assertNull(TextTools.source(null, null))
        assertNull(TextTools.source(null, ""))
    }

    @Test fun sourceTruncatedDropsPartialWord() {
        assertEquals(TextTools.Source("việt", false), TextTools.source(null, "ếng việt", truncatedStart = true))
        assertNull(TextTools.source(null, "ếng", truncatedStart = true))
        assertEquals(TextTools.Source("ếng việt", false), TextTools.source(null, "x\nếng việt", truncatedStart = true))
    }

    // --- luồng thay chữ ---

    /** before + [sel] + after; insertText thay vùng chọn; xoá theo code point. */
    private class SelProxy(var before: String, var sel: String = "", var after: String = "") : TextProxy {
        var readable = true
        var deletes = 0
        val text get() = before + sel + after
        override fun insertText(text: String) { sel = ""; before += text }
        override fun deleteCodePoints(count: Int) { deletes += count; before = Cp.dropLast(before, count) }
        override fun deleteBackward() = deleteCodePoints(1)
        override val isSecure = false
        override fun contextBeforeInput(): String? = if (readable) before else null
        override fun selectedText(): String? = sel.ifEmpty { null }
        override fun confirmTail(expected: String): Boolean = !readable || before.endsWith(expected)
    }

    @Test fun replaceBeforeCursorAndUndo() {
        val p = SelProxy("Mở đầu\nxin chào thế giới")
        val out = TextToolRunner.apply(TextTool.UPPER, p) as TextToolRunner.Outcome.Applied
        assertEquals("Mở đầu\nXIN CHÀO THẾ GIỚI", p.text)
        assertEquals(TextTools.Undo("xin chào thế giới", "XIN CHÀO THẾ GIỚI"), out.undo)
        assertTrue(TextToolRunner.undo(out.undo, p))
        assertEquals("Mở đầu\nxin chào thế giới", p.text)
    }

    @Test fun replaceSelectionOnlyTouchesSelection() {
        val p = SelProxy("Tôi nói ", "tiếng việt", " hay")
        val out = TextToolRunner.apply(TextTool.STRIP_DIACRITICS, p) as TextToolRunner.Outcome.Applied
        assertEquals("Tôi nói tieng viet hay", p.text)
        assertEquals(0, p.deletes)
        assertTrue(TextToolRunner.undo(out.undo, p))
        assertEquals("Tôi nói tiếng việt hay", p.text)
    }

    @Test fun nfdFieldDeletesByCodePoint() {
        // Android xoá theo code point ⇒ ô NFD vẫn thay đúng (khác iOS phải từ chối).
        val p = SelProxy(nfd("tiếng việt"))
        val out = TextToolRunner.apply(TextTool.UPPER, p) as TextToolRunner.Outcome.Applied
        assertEquals("TIẾNG VIỆT", p.text)
        assertTrue(TextToolRunner.undo(out.undo, p))
        assertEquals(nfd("tiếng việt"), p.text)
    }

    @Test fun truncatedContextKeepsPartialWord() {
        val p = SelProxy("ếng việt")
        TextToolRunner.apply(TextTool.UPPER, p, contextCap = 8)
        assertEquals("ếng VIỆT", p.text)
    }

    @Test fun unchangedAndNoSourceDoNothing() {
        val p = SelProxy("ĐÃ HOA")
        assertEquals(TextToolRunner.Outcome.Unchanged, TextToolRunner.apply(TextTool.UPPER, p))
        assertEquals(TextToolRunner.Outcome.NoSource, TextToolRunner.apply(TextTool.UPPER, SelProxy("\n")))
        assertEquals(0, p.deletes)
    }

    @Test fun failsafeTailMismatchNoDelete() {
        val p = object : TextProxy {
            var text = "abc xyz"
            override fun insertText(text: String) { this.text += text }
            override fun deleteCodePoints(count: Int) { text = Cp.dropLast(text, count) }
            override fun deleteBackward() = deleteCodePoints(1)
            override val isSecure = false
            override fun contextBeforeInput(): String? = text
            override fun confirmTail(expected: String) = false   // ô đổi ngầm
        }
        assertEquals(TextToolRunner.Outcome.FailSafe, TextToolRunner.apply(TextTool.UPPER, p))
        assertEquals("abc xyz", p.text)
    }

    @Test fun undoRefusesWhenTextMoved() {
        val p = SelProxy("xin chào")
        val out = TextToolRunner.apply(TextTool.TITLE, p) as TextToolRunner.Outcome.Applied
        assertEquals("Xin Chào", p.text)
        p.before += "!"
        assertFalse(TextToolRunner.undo(out.undo, p))
        assertEquals("Xin Chào!", p.text)
    }

    // MARK: nút "Thêm dấu" (thẻ Công cụ / bảng sửa văn bản)

    @Test fun addTonesButtonBeforeCursorKeepsTonedPrefix() {
        TestAssets.install()
        val p = SelProxy("Mở đầu\nHôm nay toi di hoc ")
        val out = TextToolRunner.addTones(p, null) as TextToolRunner.Outcome.Applied
        assertEquals("Mở đầu\nHôm nay tôi đi học ", p.text)
        assertTrue(TextToolRunner.undo(out.undo, p))
        assertEquals("Mở đầu\nHôm nay toi di hoc ", p.text)
    }

    @Test fun addTonesButtonSelectionOnly() {
        TestAssets.install()
        val p = SelProxy("A: ", "khong co gi", " — ok")
        TextToolRunner.addTones(p, null) as TextToolRunner.Outcome.Applied
        assertEquals("A: không có gì — ok", p.text)
        assertEquals(0, p.deletes)
    }

    @Test fun addTonesButtonNothingToDo() {
        TestAssets.install()
        assertEquals(TextToolRunner.Outcome.Unchanged, TextToolRunner.addTones(SelProxy("hello world"), null))
        assertEquals(TextToolRunner.Outcome.NoSource, TextToolRunner.addTones(SelProxy("tôi đi học"), null))
        assertEquals(TextToolRunner.Outcome.NoSource, TextToolRunner.addTones(SelProxy("\n"), null))
        // context bị cắt đầu ⇒ bỏ mẩu từ dở
        assertEquals("toi di", TextToolRunner.addTonesSource(null, "xtoi toi di", contextCap = 11)?.text)
        assertNull(TextToolRunner.addTonesSource(null, "abcdef", contextCap = 6))
    }
}
