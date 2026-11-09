package com.viettelex.android.ime

import com.viettelex.keyboard.KeyCommitQueue
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Lỗi: điều hướng cử chỉ, ô bình luận đang "P", vuốt Quay lại từ mép PHẢI bắt đầu trên phím p
 * ⇒ ô thành "Pp" rồi bàn phím đóng. Nguyên nhân: phím chữ chèn lúc DOWN, hệ thống nhận ra cử
 * chỉ sau đó và gửi ACTION_CANCEL — quá muộn. Sửa: chạm trong dải cử chỉ mép là TẠM
 * (KeyCommitQueue), huỷ ⇒ bỏ. Mô phỏng đúng trình tự KeyboardView.down/up/onTouchEvent.
 */
class EdgeTouchTest {
    // Màn 1080 px, dải cử chỉ trái/phải 60 px (giá trị thường gặp ở điều hướng cử chỉ).
    private val w = 1080; private val inset = 60
    private val field = StringBuilder("P")
    private val q = KeyCommitQueue()
    private val held = HashMap<Int, Pair<String, Boolean>>()   // pid → (phím, edge)

    /** Số lần gửi tin (return) — vuốt Quay lại không bao giờ được gửi. */
    private var sent = 0

    /** KeyboardView.down: chữ / ⌫ ngoài mép chèn ngay, trong mép arm; space / return luôn arm. */
    private fun down(pid: Int, key: String, windowX: Float) {
        q.flush(key)                                        // FlushRoute: chốt phím đang chờ trước
        val edge = EdgeTouch.inGestureZone(windowX, w, inset, inset)
        held[pid] = key to edge
        val fire = {
            when (key) {
                "⌫" -> field.setLength(field.length - 1)
                "⏎" -> sent++
                else -> field.append(key)
            }
        }
        if (edge || key == " " || key == "⏎") q.arm(key) { fire() } else fire()
    }

    private fun up(pid: Int, flags: Int = 0) {
        val (key, edge) = held.remove(pid)!!
        EdgeTouch.settle(q, key, edge, EdgeTouch.upCancelled(flags))
    }

    private fun cancel(pid: Int) {
        val (key, edge) = held.remove(pid)!!
        EdgeTouch.settle(q, key, edge, cancelled = true)
    }

    @Test fun backGestureFromRightEdgeOverPDoesNotType() {
        down(0, "p", 1050f)          // phím p sát mép phải, trong dải 60 px
        assertEquals("chưa chèn gì lúc DOWN", "P", field.toString())
        cancel(0)                    // hệ thống giật con trỏ ⇒ ACTION_CANCEL
        assertEquals("P", field.toString())
        q.flush()                    // phím kế tiếp chạm xuống: không có chữ p sót lại
        assertEquals("P", field.toString())
    }

    @Test fun backGestureDeliveredAsUpWithFlagCanceledDoesNotType() {
        down(0, "p", 1050f)
        up(0, flags = EdgeTouch.FLAG_CANCELED)
        assertEquals("P", field.toString())
    }

    @Test fun backGestureFromLeftEdgeOverBackspaceDoesNotDelete() {
        down(0, "⌫", 20f)
        cancel(0)
        assertEquals("P", field.toString())
    }

    @Test fun backGestureOverReturnAtEdgeNeverSends() {
        down(0, "⏎", 1050f)
        cancel(0)
        q.flush()
        assertEquals(0, sent)
        down(0, "⏎", 1050f)
        up(0, flags = EdgeTouch.FLAG_CANCELED)
        assertEquals(0, sent)
    }

    @Test fun backGestureOverSpaceAtEdgeInsertsNothing() {
        down(0, " ", 30f)            // space chạm trong dải mép trái (một tay / phím rộng)
        cancel(0)
        q.flush()
        assertEquals("P", field.toString())
    }

    @Test fun returnAndSpaceAtEdgeStillWorkOnPlainTap() {
        down(0, " ", 30f); up(0)
        down(0, "⏎", 1050f); up(0)
        assertEquals("P ", field.toString())
        assertEquals(1, sent)
    }

    @Test fun returnAndSpaceAwayFromEdgeStillCommitOnCancel() {
        down(0, " ", 540f); cancel(0)
        down(0, "⏎", 900f); cancel(0)
        assertEquals("P ", field.toString())
        assertEquals(1, sent)
    }

    @Test fun plainTapAtEdgeStillTypesOnLift() {
        down(0, "p", 1050f)
        up(0)
        assertEquals("Pp", field.toString())
    }

    @Test fun awayFromEdgeTypesOnDownAndCancelStillCommits() {
        down(0, "o", 980f)           // phím o: ngoài dải mép ⇒ chèn ngay lúc DOWN như cũ
        assertEquals("Po", field.toString())
        cancel(0)
        assertEquals("Po", field.toString())
    }

    @Test fun rollingFromEdgeKeyKeepsOrderAndLaterCancelDoesNotDrop() {
        down(0, "p", 1050f)
        down(1, "o", 980f)           // ngón khác chạm ⇒ chốt p trước o
        assertEquals("Ppo", field.toString())
        assertTrue("p đã chốt ⇒ settle báo đã chốt", EdgeTouch.settle(q, "p", edge = true, cancelled = true))
        held.remove(0); up(1)
        assertEquals("Ppo", field.toString())
    }

    @Test fun settleReportsDropOnlyWhenSomethingPendingWasDropped() {
        q.arm("p") {}
        assertFalse(EdgeTouch.settle(q, "p", edge = true, cancelled = true))
        assertFalse(q.isArmed("p"))
    }

    @Test fun gestureZoneGeometry() {
        assertTrue(EdgeTouch.inGestureZone(1050f, w, inset, inset))
        assertTrue(EdgeTouch.inGestureZone(1020f, w, inset, inset))
        assertFalse(EdgeTouch.inGestureZone(1019f, w, inset, inset))
        assertTrue(EdgeTouch.inGestureZone(59f, w, inset, inset))
        assertFalse(EdgeTouch.inGestureZone(60f, w, inset, inset))
        assertFalse(EdgeTouch.inGestureZone(540f, w, inset, inset))
        // nav 3 nút: insets = 0 ⇒ không có dải mép
        assertFalse(EdgeTouch.inGestureZone(0f, w, 0, 0))
        assertFalse(EdgeTouch.inGestureZone(1079f, w, 0, 0))
        assertFalse(EdgeTouch.upCancelled(0))
        assertTrue(EdgeTouch.upCancelled(0x20))
        @Suppress("InlinedApi")
        assertEquals(android.view.MotionEvent.FLAG_CANCELED, EdgeTouch.FLAG_CANCELED)
    }
}
