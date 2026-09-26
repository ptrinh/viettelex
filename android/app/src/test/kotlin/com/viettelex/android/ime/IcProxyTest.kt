package com.viettelex.android.ime

import com.viettelex.keyboard.WriteMode
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Ô nhập giả: văn bản + selection; key event áp BẤT ĐỒNG BỘ (sau endBatch) như AOSP. */
class FakeEditor(initial: String = "", var selStart: Int = initial.length, var selEnd: Int = selStart) : EditorPort {
    val sb = StringBuilder(initial)
    val text: String get() = sb.toString()
    val keys = ArrayList<EditorPort.PortKey>()
    private val pendingKeys = ArrayList<Any>()   // PortKey hoặc String (sendText)
    /** Mô phỏng app bỏ qua lệnh: ONLYOFFICE (deleteSurrounding) / WPS sandbox (commitText). */
    var ignoreDeletes = false
    var ignoreCommits = false
    var reads = 0
    var failWrites = false
    var finishComposingCalls = 0
    var setSelections = 0
    var readable = true
    private var depth = 0

    override fun beginBatch() { depth++ }
    override fun endBatch() { if (--depth == 0) flushKeys() }
    private fun flushKeys() {
        for (k in pendingKeys) when (k) {
            is String -> replaceSel(k)
            EditorPort.PortKey.DEL -> if (selStart != selEnd) replaceSel("") else if (selStart > 0) {
                val n = Character.charCount(Character.codePointBefore(sb, selStart))
                sb.delete(selStart - n, selStart); selStart -= n; selEnd = selStart
            }
            EditorPort.PortKey.LEFT -> { if (selStart > 0) selStart--; selEnd = selStart }
            EditorPort.PortKey.RIGHT -> { if (selEnd < sb.length) selEnd++; selStart = selEnd }
            EditorPort.PortKey.ENTER -> replaceSel("\n")
        }
        pendingKeys.clear()
    }
    private fun replaceSel(t: CharSequence) {
        sb.replace(selStart, selEnd, t.toString()); selStart += t.length; selEnd = selStart
    }
    override fun commitText(text: CharSequence): Boolean {
        if (failWrites) return false; if (!ignoreCommits) replaceSel(text); return true
    }
    override fun sendText(text: CharSequence) { pendingKeys.add(text.toString()); if (depth == 0) flushKeys() }
    override fun deleteBefore(utf16: Int): Boolean {
        if (failWrites) return false
        val n = minOf(utf16, selStart); sb.delete(selStart - n, selStart); selStart -= n; selEnd -= n; return true
    }
    override fun deleteCodePointsBefore(count: Int): Boolean {
        if (failWrites) return false
        if (ignoreDeletes) return true
        var p = selStart
        repeat(count) { if (p > 0) p -= Character.charCount(Character.codePointBefore(sb, p)) }
        return deleteBefore(selStart - p)
    }
    override fun deleteSurrounding(before: Int, after: Int): Boolean {
        val a = maxOf(0, selStart - before); val b = minOf(sb.length, selEnd + after)
        sb.delete(a, b); selStart = a; selEnd = a; return true
    }
    override fun textBefore(n: Int): CharSequence? { reads++; if (!readable) return null; return sb.substring(maxOf(0, selStart - n), selStart) }
    override fun textAfter(n: Int): CharSequence? = if (!readable) null else sb.substring(selEnd, minOf(sb.length, selEnd + n))
    override fun setSelection(start: Int, end: Int): Boolean { setSelections++; selStart = start; selEnd = end; return true }
    override fun finishComposing(): Boolean { finishComposingCalls++; return true }
    override fun performEditorAction(actionId: Int) = true
    override fun sendKey(key: EditorPort.PortKey) { keys.add(key); pendingKeys.add(key); if (depth == 0) flushKeys() }
}

class IcProxyTest {
    private val tracker = SelectionTracker()
    private fun proxy(ed: FakeEditor, reliable: Boolean = true): IcProxy {
        tracker.reset(ed.selStart, ed.selEnd)
        val p = IcProxy({ ed }, tracker)
        p.startInput(null, false)
        if (reliable) {                        // app đã báo một update khớp mốc
            p.begin(); p.insertText("x"); p.end()
            tracker.onUpdate(ed.selStart, ed.selEnd)
            p.begin(); p.deleteCodePoints(1); p.end()
            tracker.onUpdate(ed.selStart, ed.selEnd)
            assertTrue(tracker.reliable)
        }
        return p
    }
    private fun IcProxy.batch(f: IcProxy.() -> Unit) { begin(); try { f() } finally { end() } }

    // Mục 1: ⌫ / double-space không dùng KEYCODE_DEL bất đồng bộ.

    @Test fun deleteThenInsertSameBatchKeepsOrder() {
        val ed = FakeEditor("chữ ")
        val p = proxy(ed)
        p.batch { deleteBackward(); insertText(". ") }
        assertEquals("chữ. ", ed.text)
        assertTrue(ed.keys.isEmpty())
    }

    @Test fun backspaceDeletesWholeZwjEmoji() {
        val family = "👨‍👩‍👧"   // 👨‍👩‍👧
        val ed = FakeEditor("a$family")
        val p = proxy(ed)
        p.batch { deleteBackward() }
        assertEquals("a", ed.text)
        assertTrue(ed.keys.isEmpty())
    }

    @Test fun backspaceDeletesFlagAndSurrogate() {
        val ed = FakeEditor("x🇻🇳😀")          // 🇻🇳😀
        val p = proxy(ed)
        p.batch { deleteBackward() }
        assertEquals("x🇻🇳", ed.text)
        p.batch { deleteBackward() }
        assertEquals("x", ed.text)
    }

    @Test fun backspaceCombiningMark() {
        val ed = FakeEditor("aé")                                    // e + dấu sắc tổ hợp
        val p = proxy(ed)
        p.batch { deleteBackward() }
        assertEquals("a", ed.text)
    }

    @Test fun emptyFieldUsesKeyDel() {
        val ed = FakeEditor("")
        val p = proxy(ed, reliable = false)
        p.batch { deleteBackward() }
        assertEquals(listOf(EditorPort.PortKey.DEL), ed.keys)
    }

    @Test fun unreadableFieldUsesKeyDel() {
        val ed = FakeEditor("abc").also { it.readable = false }
        val p = proxy(ed, reliable = false)
        p.batch { deleteBackward() }
        assertEquals(listOf(EditorPort.PortKey.DEL), ed.keys)
        assertEquals("ab", ed.text)
    }

    @Test fun typeNullUsesKeyDel() {
        val ed = FakeEditor("abc")
        val p = proxy(ed).also { it.rawKeys = true }
        p.batch { deleteBackward() }
        assertEquals(listOf(EditorPort.PortKey.DEL), ed.keys)
    }

    @Test fun selectionDeletedByEmptyCommit() {
        val ed = FakeEditor("hello world")
        val p = proxy(ed)
        ed.selStart = 0; ed.selEnd = 5
        assertTrue(tracker.onUpdate(0, 5))
        p.invalidateShadow()
        p.batch { deleteBackward() }
        assertEquals(" world", ed.text)
        assertTrue(ed.keys.isEmpty())
        assertFalse(tracker.onUpdate(0, 0))     // mốc đúng: không phải đổi từ ngoài
    }

    // Mục 6: shadow giảm IPC.

    @Test fun shadowServesContextWithoutIpcWhenReliable() {
        val ed = FakeEditor("")
        val p = proxy(ed)
        p.contextBeforeInput()
        val r0 = ed.reads
        p.batch { insertText("xin"); insertText(" ") }
        assertEquals("xin ", p.contextBeforeInput())
        p.batch { deleteCodePoints(1); insertText(". ") }
        assertEquals("xin. ", p.contextBeforeInput())
        assertEquals(r0, ed.reads)
        p.invalidateShadow()                     // đổi từ ngoài
        ed.sb.insert(0, "A"); ed.selStart++; ed.selEnd++
        assertEquals("Axin. ", p.contextBeforeInput())
        assertEquals(r0 + 1, ed.reads)
    }

    @Test fun unreliableAlwaysReads() {
        val ed = FakeEditor("abc")
        val p = proxy(ed, reliable = false)
        p.contextBeforeInput(); p.contextBeforeInput()
        assertEquals(2, ed.reads)
    }

    @Test fun initialTextSeedsShadow() {
        val ed = FakeEditor("Chào")
        tracker.reset(4, 4)
        val p = IcProxy({ ed }, tracker)
        p.startInput("Chào", atFieldStart = true)
        p.batch { insertText("x") }; tracker.onUpdate(5, 5)
        assertEquals("Chàox", p.contextBeforeInput())
        assertEquals(0, ed.reads)
    }

    @Test fun shadowTracksSurrogatesForWordDelete() {
        val ed = FakeEditor("")
        val p = proxy(ed)
        p.contextBeforeInput()
        p.batch { insertText("a 😀😀") }
        p.batch { deleteCodePoints(2) }                  // xoá theo từ: 2 code point = 4 UTF-16
        assertEquals("a ", ed.text)
        assertEquals("a ", p.contextBeforeInput())
        assertFalse(tracker.onUpdate(2, 2))
    }

    // Mục 2: fail-safe trước khi xoá.

    @Test fun confirmTailReadsWhenUnreliable() {
        val ed = FakeEditor("xin chao ")
        val p = proxy(ed, reliable = false)
        assertFalse(p.confirmTail("tie"))
        ed.sb.append("tie"); ed.selStart += 3; ed.selEnd = ed.selStart
        assertTrue(p.confirmTail("tie"))
        assertEquals(2, ed.reads)
    }

    @Test fun confirmTailUsesShadowWhenReliable() {
        val ed = FakeEditor("")
        val p = proxy(ed)
        p.contextBeforeInput()
        val r0 = ed.reads
        p.batch { insertText("tie") }
        assertTrue(p.confirmTail("tie"))
        assertEquals(r0, ed.reads)
    }

    @Test fun confirmTailUnreadableKeepsOldBehavior() {
        val ed = FakeEditor("abc").also { it.readable = false }
        assertTrue(proxy(ed, reliable = false).confirmTail("zz"))
    }

    // Mục 5: composing span sót.

    @Test fun finishComposingOnNextEditOnce() {
        val ed = FakeEditor("")
        val p = proxy(ed)
        p.finishComposingOnNextEdit()
        p.batch { insertText("a") }
        p.batch { insertText("b") }
        assertEquals(1, ed.finishComposingCalls)
    }

    // Mục 7: trackpad.

    @Test fun trackpadUsesSetSelectionWhenCursorKnown() {
        val ed = FakeEditor("ab😀cd")
        val p = proxy(ed)
        p.moveCursor(-3)                                // d, c, 😀
        assertEquals(2, ed.selStart)
        assertTrue(ed.keys.isEmpty())
        assertFalse(tracker.onUpdate(2, 2))
        p.moveCursor(1)                                 // qua 😀 (2 UTF-16)
        assertEquals(4, ed.selStart)
        assertFalse(tracker.onUpdate(4, 4))
        p.moveCursor(-10)                               // chặn ở đầu ô
        assertEquals(0, ed.selStart)
        p.moveCursor(-1)                                // đầu ô: không làm gì, không DPAD
        assertTrue(ed.keys.isEmpty())
    }

    @Test fun trackpadFallsBackToDpad() {
        val ed = FakeEditor("abc")
        val p = proxy(ed, reliable = false)
        p.moveCursor(-2)
        assertEquals(listOf(EditorPort.PortKey.LEFT, EditorPort.PortKey.LEFT), ed.keys)
        val ed2 = FakeEditor("abc")
        val p2 = proxy(ed2).also { it.uriField = true }
        p2.moveCursor(-1)
        assertEquals(listOf(EditorPort.PortKey.LEFT), ed2.keys)
        assertEquals(0, ed2.setSelections)
    }

    // Mục 8: giá trị trả về.

    @Test fun failedWriteReportsFailureAndForgetsCursor() {
        val ed = FakeEditor("abc")
        val p = proxy(ed)
        ed.failWrites = true
        p.batch { insertText("x") }
        assertTrue(p.takeFailure())
        assertFalse(p.takeFailure())
        assertEquals(-1, tracker.cursor)
        p.batch { deleteCodePoints(1) }
        assertTrue(p.takeFailure())
    }

    // Thuần.

    @Test fun graphemeHelpers() {
        assertEquals(0, Graphemes.lastLength(""))
        assertEquals(1, Graphemes.lastLength("ab"))
        assertEquals(2, Graphemes.lastLength("a😀"))
        assertEquals(4, Graphemes.unitsForward("🇻🇳x", 1))
        assertEquals(3, Graphemes.unitsBack("abc", 9))
    }

    @Test fun textShadowInvalidatesWhenTooShort() {
        val s = TextShadow(256)
        s.set("x".repeat(40), atFieldStart = false)
        s.deleted(20)                                  // còn 20 < 32, chưa tới đầu ô
        assertNull(s.text())
        s.set("abc", atFieldStart = true)
        s.deleted(5)
        assertEquals("", s.text())                     // ô trống thật
    }

    // WriteMode theo app (bảng WriteMode.forPackage) — regression 26/09/2026.
    private fun telexVieet(p: IcProxy) {
        p.begin(); p.insertText("vie"); p.end()
        p.begin(); p.deleteCodePoints(1); p.insertText("ê"); p.end()   // e→ê như engine
    }

    @Test fun delViaKeyEventForAppsIgnoringDeleteSurrounding() {
        val bad = FakeEditor().apply { ignoreDeletes = true }
        telexVieet(proxy(bad, reliable = false))
        assertEquals("vieê", bad.text)            // COMMIT: app nuốt lệnh xoá ⇒ nhân chữ

        val ed = FakeEditor().apply { ignoreDeletes = true }
        val p = proxy(ed, reliable = false).apply { writeMode = WriteMode.DEL_VIA_KEY_EVENT }
        telexVieet(p)
        assertEquals("viê", ed.text)
    }

    @Test fun keyOnlyForSandboxedApps() {
        val ed = FakeEditor().apply { ignoreCommits = true; ignoreDeletes = true }
        val p = proxy(ed, reliable = false).apply { writeMode = WriteMode.KEY_ONLY }
        telexVieet(p)
        assertEquals("viê", ed.text)
        p.begin(); p.deleteBackward(); p.end()
        assertEquals("vi", ed.text)
        assertTrue(p.confirmTail("không khớp"))   // key event trễ ⇒ không so đuôi
    }
}
