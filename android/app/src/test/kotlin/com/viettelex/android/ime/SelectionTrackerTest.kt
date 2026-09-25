package com.viettelex.android.ime

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SelectionTrackerTest {

    @Test fun ownEditIsNotExternal() {
        val t = SelectionTracker()
        t.reset(0, 0)
        t.inserted(1)                       // "a"
        assertFalse(t.onUpdate(1, 1))
    }

    @Test fun belatedUpdatesWhileTypingFast() {
        // Gõ nhanh: 3 edit gửi đi trước khi update đầu tiên về — không được reset.
        val t = SelectionTracker()
        t.reset(10, 10)
        t.inserted(1)                       // 11
        t.deleted(1); t.inserted(1)         // v → ư: 10, 11
        t.inserted(1)                       // 12
        assertFalse(t.onUpdate(11, 11))
        assertFalse(t.onUpdate(11, 11))     // update giữa batch cũng khớp mốc
        assertFalse(t.onUpdate(12, 12))
    }

    @Test fun intermediateDeleteStateAccepted() {
        // App không tôn trọng batch edit ⇒ báo cả trạng thái sau delete.
        val t = SelectionTracker()
        t.reset(5, 5)
        t.deleted(2); t.inserted(3)         // 3 → 6
        assertFalse(t.onUpdate(3, 3))
        assertFalse(t.onUpdate(6, 6))
    }

    @Test fun tapElsewhereIsExternal() {
        val t = SelectionTracker()
        t.reset(4, 4)
        t.inserted(1)
        assertFalse(t.onUpdate(5, 5))
        assertTrue(t.onUpdate(0, 0))
    }

    @Test fun selectionIsExternal() {
        val t = SelectionTracker()
        t.reset(4, 4)
        assertTrue(t.onUpdate(0, 4))
    }

    @Test fun wildcardAcceptsUnknownDelta() {
        val t = SelectionTracker()
        t.reset(8, 8)
        t.unknown()                          // KEYCODE_DEL xoá emoji 2 đơn vị
        assertFalse(t.onUpdate(6, 6))
        // sau đó con trỏ đã biết lại: edit kế khớp chính xác
        t.inserted(1)
        assertFalse(t.onUpdate(7, 7))
        assertTrue(t.onUpdate(2, 2))
    }

    @Test fun unknownStartUsesWildcards() {
        val t = SelectionTracker()
        t.reset(-1, -1)
        t.inserted(1)
        assertFalse(t.onUpdate(42, 42))
        t.inserted(1)
        assertFalse(t.onUpdate(43, 43))
    }

    @Test fun duplicateReportIgnored() {
        val t = SelectionTracker()
        t.reset(3, 3)
        assertFalse(t.onUpdate(3, 3))
    }
}
