package com.viettelex.android.ime

import com.viettelex.keyboard.EngineBridge
import com.viettelex.keyboard.WriteMode
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Sửa lại từ đã chốt qua IcProxy thật: guard theo ô + onUpdateSelection của chính mình không reset. */
class ReEditIcProxyTest {
    private val tracker = SelectionTracker()

    private fun proxy(ed: FakeEditor): IcProxy {
        tracker.reset(ed.selStart, ed.selEnd)
        return IcProxy({ ed }, tracker).also { it.startInput(null, false) }
    }

    /** Một phím trong batch rồi app báo selection (như onUpdateSelection) — true nếu bị coi là đổi từ NGOÀI. */
    private fun key(p: IcProxy, ed: FakeEditor, f: () -> Unit): Boolean {
        p.begin(); try { f() } finally { p.end() }
        return tracker.onUpdate(ed.selStart, ed.selEnd)
    }

    @Test fun reopenThroughIcProxyIsNotExternal() {
        val ed = FakeEditor(); val p = proxy(ed); val b = EngineBridge()
        for (c in "thays") assertFalse(key(p, ed) { b.letter(c, p) })
        assertFalse(key(p, ed) { b.boundary(" ", p) })
        assertEquals("tháy ", ed.text)
        var reopened = false
        assertFalse(key(p, ed) { reopened = b.backspace(p) })
        assertTrue(reopened)
        assertEquals("tháy", ed.text)
        assertFalse(key(p, ed) { b.letter('a', p) })
        assertEquals("thấy", ed.text)
    }

    @Test fun reopenSkippedWhenEditorChangedSilently() {
        val ed = FakeEditor(); val p = proxy(ed); val b = EngineBridge()
        for (c in "thays") key(p, ed) { b.letter(c, p) }
        key(p, ed) { b.boundary(" ", p) }
        // Chưa chứng minh reliable ⇒ IcProxy đọc thật; app đã đổi chữ mà không báo.
        tracker.reset(-1, -1)
        ed.sb.setLength(0); ed.sb.append("khác "); ed.selStart = 5; ed.selEnd = 5
        var reopened = true
        key(p, ed) { reopened = b.backspace(p) }
        assertFalse(reopened)
        assertEquals("khác", ed.text)
    }

    @Test fun firstLetterAfterOwnBoundaryDoesNotReadContext() {
        val ed = FakeEditor(); tracker.reset(-1, -1)
        val p = IcProxy({ ed }, tracker).also { it.startInput(null, false) }
        val b = EngineBridge()
        for (c in "anh") key(p, ed) { b.letter(c, p) }
        key(p, ed) { b.boundary(" ", p) }
        val reads = ed.reads
        key(p, ed) { b.letter('a', p) }        // phím "biến đổi" nhưng trước nó là space của mình
        assertEquals(reads, ed.reads)
        assertEquals("anh a", ed.text)
    }

    @Test fun seedThroughIcProxy() {
        val ed = FakeEditor("xin chao"); val p = proxy(ed); val b = EngineBridge()
        assertFalse(key(p, ed) { b.letter('f', p) })
        assertEquals("xin chào", ed.text)
    }

    @Test fun seedNotAppliedMidWord() {
        val ed = FakeEditor("chaoban", selStart = 4); val p = proxy(ed); val b = EngineBridge()
        key(p, ed) { b.letter('f', p) }
        assertEquals("chaofban", ed.text)
    }

    @Test fun selectionFromTrackerBlocks() {
        val p = proxy(FakeEditor("chao ban", selStart = 5, selEnd = 8))
        assertTrue(p.hasSelection)
    }

    @Test fun unreliableCursorAsksEditorForSelection() {
        val ed = FakeEditor("chao"); val p = proxy(ed)
        tracker.reset(-1, -1)
        assertFalse(p.hasSelection)
        ed.selStart = 0                         // app chọn chữ mà mình chưa được báo
        assertTrue(p.hasSelection)
    }

    @Test fun canReEditGuards() {
        val p = proxy(FakeEditor())
        assertTrue(p.canReEdit)
        p.writeMode = WriteMode.DEL_VIA_KEY_EVENT; assertFalse(p.canReEdit)
        p.writeMode = WriteMode.KEY_ONLY; assertFalse(p.canReEdit)
        p.writeMode = WriteMode.COMMIT
        p.rawKeys = true; assertFalse(p.canReEdit); p.rawKeys = false
        p.uriField = true; assertFalse(p.canReEdit); p.uriField = false
        p.secure = true; assertFalse(p.canReEdit)
    }

    @Test fun uriFieldTypesLiteral() {
        val ed = FakeEditor("chao"); val p = proxy(ed); p.uriField = true
        val b = EngineBridge()
        key(p, ed) { b.letter('f', p) }
        assertEquals("chaof", ed.text)
    }

    @Test fun contextAfterReadsEditor() {
        val ed = FakeEditor("ab", selStart = 1); val p = proxy(ed)
        assertEquals("b", p.contextAfterInput())
        ed.readable = false
        assertNull(p.contextAfterInput())
    }
}
