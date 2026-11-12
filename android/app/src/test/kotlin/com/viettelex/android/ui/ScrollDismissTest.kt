package com.viettelex.android.ui

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Báo lỗi 13/11/2026 "bàn phím hay bị ẩn, chỉ trong app cài đặt": app đóng bàn phím ở MỌI cú
 * kéo tay (cả khi trang không cuộn). Giờ chỉ khi trang thật sự dịch ≥ ngưỡng trong một cú kéo.
 */
class ScrollDismissTest {
    @Test fun dragThatDoesNotMoveThePageKeepsKeyboard() {
        val d = ScrollDismiss(60f)
        // kéo trong ô nhập nhiều dòng / trang ngắn / mép trang: trang không dịch
        repeat(20) { assertFalse(d.onScroll(userInput = true, pageDeltaPx = 0f)) }
    }

    @Test fun smallPageNudgeKeepsKeyboard() {
        val d = ScrollDismiss(60f)
        assertFalse(d.onScroll(true, 20f))
        assertFalse(d.onScroll(true, -20f))
    }

    @Test fun realScrollDismissesOncePerDrag() {
        val d = ScrollDismiss(60f)
        assertFalse(d.onScroll(true, 40f))
        assertTrue(d.onScroll(true, 30f))
        assertFalse(d.onScroll(true, 100f))     // đã đóng trong cú kéo này
        d.reset()
        assertFalse(d.onScroll(true, 30f))
        assertTrue(d.onScroll(true, 40f))
    }

    @Test fun programmaticScrollNeverDismisses() {
        // bringIntoView của ô vừa focus (bàn phím đẩy trang lên) không phải tay người dùng
        val d = ScrollDismiss(60f)
        assertFalse(d.onScroll(userInput = false, pageDeltaPx = 500f))
    }
}
