package com.viettelex.android.ime

import com.viettelex.keyboard.Keys
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Bộ nhớ đệm thuần trên đường hiện bàn phím (docs/PERF-IME-SHOW.md, đợt 10/11/2026). */
class ShowPathCachesTest {

    /** Trình tiết kiệm pin: tối đa MỘT lần đọc mỗi lần hiện; không ai hỏi ⇒ 0 lần. */
    @Test fun powerSaveReadAtMostOncePerShow() {
        var binder = 0
        val f = PerShowFlag { binder++; true }
        f.reset()
        assertEquals("không tính năng nào hỏi ⇒ không đọc", 0, binder)
        assertTrue(f.get()); assertTrue(f.get()); assertTrue(f.get())   // Đập chuột + Đèn rọi + Lơ lửng
        assertEquals(1, binder)
        f.reset()                                       // lần hiện kế: đọc lại (pin có thể vừa bật/tắt)
        f.get()
        assertEquals(2, binder)
        assertEquals(2, f.reads)
    }

    /** ClipDescription: một binder mỗi mục clipboard (changeCount), không phải mỗi lượt nút Dán. */
    @Test fun clipDescriptionFetchedOncePerClipChange() {
        var binder = 0
        val c = ClipFactsCache { binder++; ClipFacts(text = true, timestamp = 1234L, sensitive = false) }
        repeat(5) { c.get(0) }                          // hasText + clipId + isSensitive, nhiều lượt bar
        assertEquals(1, binder)
        repeat(3) { c.get(1) }                          // listener: clip đổi
        assertEquals(2, binder)
        c.invalidate()                                  // bàn phím hiện lại: quyền đọc có thể vừa đổi
        assertEquals(1234L, c.get(1)?.timestamp)
        assertEquals(3, binder)
        assertEquals(3, c.fetches)
    }

    /** Lần đọc lúc thiếu quyền (null) không bị giữ qua lần hiện sau. */
    @Test fun clipDescriptionNullIsRetriedAfterShow() {
        var allowed = false
        val c = ClipFactsCache { if (allowed) ClipFacts(true, 0L, false) else null }
        assertEquals(null, c.get(0))
        allowed = true
        assertEquals(null, c.get(0))                    // cùng clip, cùng lần hiện: giữ kết quả
        c.invalidate()
        assertTrue(c.get(0)!!.text)
    }

    /** Ba file prefs mở trước ở onCreate (nạp song song), file cài đặt mở cuối. */
    @Test fun prefsPrimeOrderCoversColdPathFiles() {
        val order = ImePrefFiles.PRIME_ORDER
        assertEquals(setOf(ImePrefFiles.STATE, Keys.RUNTIME_PREFS, Keys.PREFS), order.toSet())
        assertEquals(Keys.PREFS, order.last())
        assertFalse(order.dropLast(1).contains(Keys.PREFS))
    }
}
