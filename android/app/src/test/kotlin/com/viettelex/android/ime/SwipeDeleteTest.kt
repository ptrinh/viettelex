package com.viettelex.android.ime

import com.viettelex.keyboard.EngineBridge
import com.viettelex.keyboard.KeyboardSettings
import com.viettelex.keyboard.WriteMode
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Vuốt trái trên ⌫ xoá theo từ (kiểu Gboard). */
class SwipeDeleteTest {

    // MARK: ranh giới từ (hàm thuần)

    private fun steps(s: String, max: Int = 64): List<String> =
        WordBoundary.stops(s, max).map { s.substring(s.length - it) }

    @Test fun wordStepsIncludeSeparatorBefore() {
        assertEquals(listOf("bạn", "chào bạn", "xin chào bạn"), steps("xin chào bạn"))
        assertEquals(listOf("chào, ", "xin chào, "), steps("xin chào, "))
        assertEquals(listOf("   "), steps("   "))
        assertArrayEquals(IntArray(0), WordBoundary.stops(""))
    }

    @Test fun vietnameseDiacriticsPrecomposedAndCombining() {
        assertEquals(listOf("đường", "Con đường"), steps("Con đường"))
        val decomposed = "tiếng Việt"      // dấu tổ hợp (NFD)
        assertEquals(listOf("Việt", decomposed), steps(decomposed))
    }

    @Test fun emojiAndFlagsAreWholeWords() {
        val family = "👨‍👩‍👧"   // 👨‍👩‍👧
        assertEquals(listOf(family, "ok $family"), steps("ok $family"))
        val vn = "🇻🇳"                                  // 🇻🇳
        assertEquals(listOf("$vn ", "😀$vn ", "hi 😀$vn "), steps("hi 😀$vn "))
    }

    @Test fun newlineIsHardBoundary() {
        assertEquals(listOf("\n", "abc\n", "x abc\n"), steps("x abc\n"))
        assertEquals(listOf("  ", "\n  ", "abc\n  "), steps("abc\n  "))
    }

    @Test fun maxStopsAndUnitsBack() {
        assertEquals(listOf("c", "b c"), steps("a b c", max = 2))
        assertEquals(3, WordBoundary.unitsBack("a b c", 2))
        assertEquals(5, WordBoundary.unitsBack("a b c", 99))
        assertEquals(0, WordBoundary.unitsBack("a b c", 0))
        assertEquals(3, WordBoundary.graphemeCount("a😀é"))
    }

    // MARK: ngưỡng kéo → số từ

    @Test fun dragDistanceToWords() {
        val act = 18f; val step = 36f
        assertEquals(0, SwipeDelete.words(0f, act, step))
        assertEquals(0, SwipeDelete.words(17.9f, act, step))
        assertEquals(1, SwipeDelete.words(18f, act, step))
        assertEquals(1, SwipeDelete.words(53f, act, step))
        assertEquals(2, SwipeDelete.words(54f, act, step))
        assertEquals(3, SwipeDelete.words(90f, act, step))
        assertEquals(0, SwipeDelete.words(-40f, act, step))          // kéo qua phải điểm chạm
        assertEquals(18f, SwipeDelete.activatePx(36f, 16f), 0f)
        assertEquals(16f, SwipeDelete.activatePx(20f, 16f), 0f)
    }

    @Test fun activationNeedsLeftwardHorizontalMove() {
        assertTrue(SwipeDelete.activates(-20f, 5f, 18f))
        assertFalse(SwipeDelete.activates(-10f, 0f, 18f))           // chưa tới ngưỡng (rung tay)
        assertFalse(SwipeDelete.activates(30f, 0f, 18f))            // sang phải
        assertFalse(SwipeDelete.activates(-20f, 25f, 18f))          // dọc trội hơn
    }

    // MARK: controller trên FakeEditor

    private val tracker = SelectionTracker()
    private fun proxy(ed: FakeEditor, reliable: Boolean = true): IcProxy {
        tracker.reset(ed.selStart, ed.selEnd)
        val p = IcProxy({ ed }, tracker)
        p.startInput(null, false)
        if (reliable) {
            p.begin(); p.insertText("x"); p.end(); tracker.onUpdate(ed.selStart, ed.selEnd)
            p.begin(); p.deleteCodePoints(1); p.end(); tracker.onUpdate(ed.selStart, ed.selEnd)
            assertTrue(tracker.reliable)
        }
        return p
    }
    private fun <T> IcProxy.batch(f: () -> T): T { begin(); try { return f() } finally { end() } }

    @Test fun selectsWordsWithSetSelectionAndDeletesOnLift() {
        val ed = FakeEditor("xin chào bạn")
        val p = proxy(ed)
        val c = SwipeDeleteController(p)
        assertTrue(c.start())
        assertTrue(c.selecting)
        assertEquals(1, c.update(1))
        assertEquals(9 to 12, ed.selStart to ed.selEnd)             // bôi đen "bạn"
        assertFalse(tracker.onUpdate(9, 12))                         // selection của mình ≠ đổi từ ngoài
        assertEquals(2, c.update(2))
        assertEquals(4 to 12, ed.selStart to ed.selEnd)
        assertEquals(1, c.update(1))                                 // kéo ngược: bớt
        assertEquals(9 to 12, ed.selStart to ed.selEnd)
        c.update(2)
        val deleted = p.batch { c.finish(commit = true) }
        assertEquals("chào bạn", deleted)
        assertEquals("xin ", ed.text)
        assertFalse(tracker.onUpdate(4, 12))                         // update trễ vẫn là của mình
        assertFalse(tracker.onUpdate(4, 4))
        assertEquals(4, tracker.cursor)
        assertFalse(c.active)
    }

    @Test fun dragBackToZeroCancelsAndRestoresCursor() {
        val ed = FakeEditor("xin chào bạn")
        val p = proxy(ed)
        val c = SwipeDeleteController(p)
        c.start(); c.update(2)
        c.update(0)
        assertEquals(12 to 12, ed.selStart to ed.selEnd)
        assertNull(p.batch { c.finish(commit = true) })
        assertEquals("xin chào bạn", ed.text)
        assertEquals(12 to 12, ed.selStart to ed.selEnd)
    }

    @Test fun cancelledTouchRestoresCursor() {
        val ed = FakeEditor("xin chào bạn")
        val p = proxy(ed)
        val c = SwipeDeleteController(p)
        c.start(); c.update(2)
        assertNull(c.finish(commit = false))
        assertEquals("xin chào bạn", ed.text)
        assertEquals(12 to 12, ed.selStart to ed.selEnd)
        assertFalse(tracker.onUpdate(4, 12))
        assertFalse(tracker.onUpdate(12, 12))
    }

    @Test fun restoreReinsertsDeletedText() {
        val ed = FakeEditor("Tôi đi học 😀")
        val p = proxy(ed)
        val c = SwipeDeleteController(p)
        c.start(); c.update(2)
        val deleted = p.batch { c.finish(commit = true) }!!
        assertEquals("Tôi đi ", ed.text)
        p.batch { p.insertText(deleted) }                           // chạm "↩︎ Khôi phục"
        assertEquals("Tôi đi học 😀", ed.text)
    }

    @Test fun clampsToAvailableWords() {
        val ed = FakeEditor("a b")
        val c = SwipeDeleteController(proxy(ed))
        c.start()
        assertEquals(2, c.update(10))
        assertEquals(0 to 3, ed.selStart to ed.selEnd)
    }

    @Test fun unreliableCursorPreviewsThenDeletesExact() {
        val ed = FakeEditor("xin chào bạn")
        val p = proxy(ed, reliable = false)
        val c = SwipeDeleteController(p)
        assertTrue(c.start())
        assertFalse(c.selecting)
        c.update(1)
        assertEquals("bạn", c.preview)
        assertEquals(0, ed.setSelections)                            // không bôi đen mù
        assertEquals("bạn", p.batch { c.finish(commit = true) })
        assertEquals("xin chào ", ed.text)
        assertTrue(ed.keys.isEmpty())
    }

    @Test fun unreliableTailMismatchDoesNotDeleteBlind() {
        val ed = FakeEditor("xin chào bạn")
        val p = proxy(ed, reliable = false)
        val c = SwipeDeleteController(p)
        c.start(); c.update(1)
        ed.sb.append("!"); ed.selStart++; ed.selEnd++                // ô đổi mà không được báo
        assertNull(p.batch { c.finish(commit = true) })
        assertEquals("xin chào bạn!", ed.text)
    }

    @Test fun delViaKeyEventUsesDelKeysPerGrapheme() {
        val ed = FakeEditor("ok 😀 bạn")
        val p = proxy(ed).apply { writeMode = WriteMode.DEL_VIA_KEY_EVENT }
        val c = SwipeDeleteController(p)
        assertTrue(c.start())
        assertFalse(c.selecting)                                     // không setSelection
        c.update(2)
        assertEquals("😀 bạn", c.preview)
        assertEquals("😀 bạn", p.batch { c.finish(commit = true) })
        assertEquals("ok ", ed.text)
        assertEquals(5, ed.keys.size)                                // 😀 ␣ b ạ n
        assertEquals(0, ed.setSelections)
    }

    @Test fun keyOnlyUsesDelKeys() {
        val ed = FakeEditor("xin chào")
        val p = proxy(ed, reliable = false).apply { writeMode = WriteMode.KEY_ONLY }
        val c = SwipeDeleteController(p)
        c.start(); c.update(1)
        p.batch { c.finish(commit = true) }
        assertEquals("xin ", ed.text)
        assertTrue(ed.keys.all { it == EditorPort.PortKey.DEL })
        assertEquals(0, ed.setSelections)
    }

    @Test fun disabledWhenSecureUnreadableOrEmpty() {
        val sec = FakeEditor("abc")
        assertFalse(SwipeDeleteController(proxy(sec).apply { secure = true }).start())
        val raw = FakeEditor("abc")
        assertFalse(SwipeDeleteController(proxy(raw).apply { rawKeys = true }).start())
        val unread = FakeEditor("abc")
        val pu = proxy(unread, reliable = false); unread.readable = false
        assertFalse(SwipeDeleteController(pu).start())
        assertFalse(SwipeDeleteController(proxy(FakeEditor(""), reliable = false)).start())
    }

    @Test fun composingWordIsFirstWordAndEngineResets() {
        val ed = FakeEditor("Xin ")
        val p = proxy(ed)
        val bridge = EngineBridge(KeyboardSettings())
        for (ch in "chaof") p.batch { bridge.letter(ch, p) }
        assertEquals("Xin chào", ed.text)
        assertTrue(bridge.isComposing)
        p.batch { bridge.backspace(p) }                              // ⌫ lúc chạm xuống
        assertEquals("Xin chà", ed.text)
        bridge.reset()                                               // IME: onSwipeDeleteStart
        val c = SwipeDeleteController(p)
        c.start(); c.update(1)
        assertEquals("chà", c.preview)                               // không xoá dư chữ đã xoá lúc chạm
        p.batch { c.finish(commit = true) }
        assertEquals("Xin ", ed.text)
        for (ch in "ddi") p.batch { bridge.letter(ch, p) }           // từ mới, không dính từ cũ
        assertEquals("Xin đi", ed.text)
    }
}
