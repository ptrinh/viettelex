package com.viettelex.android.ime

import com.viettelex.keyboard.KeyCommitQueue

/**
 * Chạm bắt đầu trong dải cử chỉ hệ thống trái/phải (điều hướng bằng cử chỉ: vuốt từ mép vào
 * = Quay lại). Hệ thống chỉ nhận ra cử chỉ SAU khi ngón đã trôi vào trong, rồi giật con trỏ
 * (pilferPointers) ⇒ bàn phím nhận ACTION_CANCEL. Phím chữ / ⌫ vốn chạy lúc DOWN nên chữ đã
 * vào ô trước khi CANCEL tới (lỗi "Pp" khi vuốt Quay lại từ phím p).
 *
 * Cách sửa: chạm trong dải mép là TẠM — chữ / ⌫ arm vào [KeyCommitQueue] như dấu câu, chốt
 * lúc nhấc (hoặc khi ngón khác chạm, giữ thứ tự gõ chồng); bị huỷ (CANCEL / UP mang
 * FLAG_CANCELED) ⇒ bỏ, không gõ gì. Chạm ngoài dải mép không đổi gì (chữ vẫn chèn lúc DOWN).
 * KHÔNG chặn cử chỉ Quay lại (không đặt systemGestureExclusionRects).
 * THUẦN — pinned by EdgeTouchTest.
 */
object EdgeTouch {
    /** Cờ MotionEvent.FLAG_CANCELED (API 33; máy cũ không bao giờ đặt). */
    const val FLAG_CANCELED = 0x20

    /**
     * [windowX] toạ độ ngang trong cửa sổ IME; [windowWidth] bề rộng cửa sổ; [insetLeft] /
     * [insetRight] = WindowInsets systemGestures trái/phải (px; 0 khi nav 3 nút).
     */
    fun inGestureZone(windowX: Float, windowWidth: Int, insetLeft: Int, insetRight: Int): Boolean =
        (insetLeft > 0 && windowX < insetLeft) ||
            (insetRight > 0 && windowWidth > 0 && windowX >= windowWidth - insetRight)

    /** ACTION_UP / ACTION_POINTER_UP mang FLAG_CANCELED (hệ thống huỷ ngón đó) ⇒ coi như CANCEL. */
    fun upCancelled(flags: Int): Boolean = (flags and FLAG_CANCELED) != 0

    /**
     * Nhấc / huỷ ngón giữ phím [id]: chạm tạm ở mép mà bị huỷ ⇒ bỏ phím chờ; còn lại chốt như
     * cũ (cancel ngoài mép VẪN chốt — hợp đồng KeyCommitQueue). false = vừa BỎ một phím đang
     * chờ; true = đã chốt, hoặc phím đã chốt từ trước (ngón khác chạm / giữ ký tự phụ).
     */
    fun settle(q: KeyCommitQueue, id: Any, edge: Boolean, cancelled: Boolean): Boolean {
        if (edge && cancelled) {
            if (!q.isArmed(id)) return true
            q.disarm(id); return false
        }
        q.release(id)
        return true
    }
}
