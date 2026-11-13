package com.viettelex.android.ime

import com.viettelex.keyboard.TextToolRunner
import com.viettelex.keyboard.TranslateDirection
import com.viettelex.keyboard.TranslateRunner
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Dịch trên máy qua IcProxy thật (FakeEditor): đọc nguồn, ghi kết quả muộn, hoàn tác, fail-safe khi ô đổi. */
class TranslateIcProxyTest {
    private val tracker = SelectionTracker()

    private fun proxy(ed: FakeEditor): IcProxy {
        tracker.reset(ed.selStart, ed.selEnd)
        return IcProxy({ ed }, tracker).also { it.startInput(null, false) }
    }

    private fun <T> IcProxy.batch(ed: FakeEditor, f: IcProxy.() -> T): T {
        begin(); try { return f() } finally { end(); tracker.onUpdate(ed.selStart, ed.selEnd) }
    }

    @Test fun beforeCursorTranslatedAndUndone() {
        val ed = FakeEditor("Dòng đầu\nxin chào bạn")
        val p = proxy(ed)
        val job = p.batch(ed) { TranslateRunner.prepare(this, "en", IcProxy.CONTEXT_CAP) }!!
        assertEquals("xin chào bạn", job.source.text)
        assertEquals(TranslateDirection.Plan("vi", "en"), job.plan)
        val out = p.batch(ed) { TranslateRunner.commit(job, "hello friend", this) }
        assertEquals("Dòng đầu\nhello friend", ed.text)
        val u = (out as TextToolRunner.Outcome.Applied).undo
        assertTrue(p.batch(ed) { TextToolRunner.undo(u, this) })
        assertEquals("Dòng đầu\nxin chào bạn", ed.text)
    }

    @Test fun selectionWithJapaneseTargetRoundTrip() {
        val ed = FakeEditor("A: こんにちは :B", selStart = 3, selEnd = 8)
        val p = proxy(ed)
        val job = p.batch(ed) { TranslateRunner.prepare(this, "ja", IcProxy.CONTEXT_CAP) }!!
        assertEquals(TranslateDirection.Plan("ja", "vi"), job.plan)          // đã là đích ⇒ sang tiếng Việt
        p.batch(ed) { TranslateRunner.commit(job, "xin chào", this) }
        assertEquals("A: xin chào :B", ed.text)
    }

    @Test fun fieldChangedWhileTranslatingDropsResult() {
        val ed = FakeEditor("xin chào")
        val p = proxy(ed)
        val job = p.batch(ed) { TranslateRunner.prepare(this, "en", IcProxy.CONTEXT_CAP) }!!
        p.batch(ed) { insertText(" nhé") }                                   // user gõ tiếp trong lúc dịch
        val out = p.batch(ed) { TranslateRunner.commit(job, "hello", this) }
        assertEquals(TextToolRunner.Outcome.FailSafe, out)
        assertEquals("xin chào nhé", ed.text)
    }

    @Test fun selectionChangedWhileTranslatingDropsResult() {
        val ed = FakeEditor("một hai ba", selStart = 0, selEnd = 3)
        val p = proxy(ed)
        val job = p.batch(ed) { TranslateRunner.prepare(this, "en", IcProxy.CONTEXT_CAP) }!!
        ed.selStart = 4; ed.selEnd = 7; tracker.onUpdate(4, 7)              // user chọn chỗ khác
        val out = p.batch(ed) { TranslateRunner.commit(job, "one", this) }
        assertEquals(TextToolRunner.Outcome.FailSafe, out)
        assertEquals("một hai ba", ed.text)
    }

    @Test fun nothingToTranslate() {
        val ed = FakeEditor("123 ")
        val p = proxy(ed)
        assertNull(p.batch(ed) { TranslateRunner.prepare(this, "en", IcProxy.CONTEXT_CAP) })
    }
}
