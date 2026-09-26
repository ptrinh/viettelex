package com.viettelex.android.ime

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SelectionTrackerSafetyTest {
    @Test fun unknownReportIsNotExternal() {
        val t = SelectionTracker()
        t.reset(5, 5)
        t.inserted(1)
        assertFalse(t.onUpdate(-1, -1))       // app "không biết"
        assertEquals(-1, t.cursor)
        assertFalse(t.reliable)
        assertFalse(t.onUpdate(9, 9))         // báo kế tiếp nhận làm mốc
        assertEquals(9, t.cursor)
    }

    @Test fun reliableOnlyAfterExactMatch() {
        val t = SelectionTracker()
        t.reset(-1, -1)
        t.inserted(1)
        assertFalse(t.onUpdate(3, 3))         // khớp wildcard
        assertFalse(t.reliable)
        t.inserted(1)
        assertFalse(t.onUpdate(4, 4))
        assertTrue(t.reliable)
        t.reset(0, 0)
        assertFalse(t.reliable)
    }

    @Test fun insertReplacesReportedSelection() {
        val t = SelectionTracker()
        t.reset(0, 0)
        assertTrue(t.onUpdate(2, 6))
        assertTrue(t.hasSelection)
        t.inserted(1)                         // commitText thay selection
        assertFalse(t.hasSelection)
        assertFalse(t.onUpdate(3, 3))
    }
}

class InitialSelectionTest {
    @Test fun consistentFullText() = assertTrue(InitialSelection.trusted(4, 4, 4, 256))
    @Test fun noInitialTextTrusted() = assertTrue(InitialSelection.trusted(7, 7, null, 256))
    @Test fun truncatedByRequest() = assertTrue(InitialSelection.trusted(1000, 1000, 256, 256))
    @Test fun moreTextThanCursorIsWrong() = assertFalse(InitialSelection.trusted(0, 0, 12, 256))
    @Test fun shorterTextIsMismatch() = assertFalse(InitialSelection.trusted(50, 50, 10, 256))
    @Test fun negativeUnknown() = assertFalse(InitialSelection.trusted(-1, -1, null, 256))
    @Test fun selectionUsesStart() = assertTrue(InitialSelection.trusted(8, 3, 3, 256))
}
