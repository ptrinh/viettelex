package com.viettelex.android.ime

/**
 * Phát hiện "con trỏ bị dời từ NGOÀI" (spec §4.1, thay textWillChange của iOS).
 *
 * onUpdateSelection tới BẤT ĐỒNG BỘ, thường trễ sau edit của chính mình: gõ
 * nhanh thì edit 2 đã gửi trước khi update của edit 1 về. Vì vậy giữ một hàng
 * đợi các vị trí con trỏ MONG ĐỢI (mỗi thao tác đẩy một mốc, kể cả mốc giữa
 * delete→insert phòng app không tôn trọng batch edit). Update khớp một mốc ⇒
 * của mình (bỏ các mốc cũ hơn). Không khớp mốc nào ⇒ đổi từ ngoài.
 *
 * [WILDCARD] = thao tác không biết trước độ dời (KEYCODE_DEL xoá cả grapheme,
 * ENTER, xoá sạch ô): khớp mọi vị trí, một lần.
 *
 * newSelStart < 0 = app "không biết" (spec InputMethodService) — KHÔNG phải đổi từ
 * ngoài: con trỏ thành chưa biết, báo kế tiếp được nhận làm mốc.
 *
 * [reliable]: app đã báo ít nhất một update khớp CHÍNH XÁC mốc của mình trong phiên ⇒
 * báo cáo selection theo kịp edit của mình, [cursor] dùng được làm offset tuyệt đối
 * (setSelection) và bản sao văn bản (shadow) trong IcProxy tin được.
 *
 * THUẦN — pinned by SelectionTrackerTest.
 */
class SelectionTracker {
    private val queue = IntArray(CAP)
    private var n = 0

    /** Vị trí con trỏ mới nhất đã biết/mong đợi (UTF-16); -1 = chưa biết. */
    var cursor = -1
        private set

    /** Xem doc lớp. */
    var reliable = false
        private set

    /** Selection (không rỗng) app báo gần nhất; -1 = không có. */
    private var selStart = -1
    private var selEnd = -1
    val hasSelection: Boolean get() = selStart >= 0

    fun reset(selStart: Int, selEnd: Int) {
        n = 0
        reliable = false
        cursor = if (selStart >= 0 && selStart == selEnd) selStart else -1
        setSelection(selStart, selEnd)
    }

    private fun setSelection(a: Int, b: Int) {
        if (a >= 0 && b >= 0 && a != b) { selStart = minOf(a, b); selEnd = maxOf(a, b) }
        else { selStart = -1; selEnd = -1 }
    }

    /** Mình vừa xoá `count` đơn vị UTF-16 trước con trỏ. */
    fun deleted(count: Int) {
        if (count <= 0) return
        if (hasSelection) { unknown(); return }       // xoá trước selection: không tính dời
        if (cursor < 0) { push(WILDCARD); return }
        cursor = maxOf(0, cursor - count)
        push(cursor)
    }

    /** Mình vừa chèn chuỗi dài `len` (UTF-16) tại con trỏ (commitText thay cả selection). */
    fun inserted(len: Int) {
        if (hasSelection) {
            cursor = selStart + len
            setSelection(-1, -1)
            push(cursor)
            return
        }
        if (len <= 0) return
        if (cursor < 0) { push(WILDCARD); return }
        cursor += len
        push(cursor)
    }

    /** Mình vừa setSelection(pos, pos). */
    fun movedTo(pos: Int) {
        setSelection(-1, -1)
        cursor = pos
        push(pos)
    }

    /** Thao tác không biết trước con trỏ về đâu. */
    fun unknown() {
        cursor = -1
        setSelection(-1, -1)
        push(WILDCARD)
    }

    val hasPending: Boolean get() = n > 0

    /** @return true nếu đây là thay đổi từ NGOÀI (phải reset engine). */
    fun onUpdate(newSelStart: Int, newSelEnd: Int): Boolean {
        if (newSelStart < 0 || newSelEnd < 0) {
            // "Không biết" — không reset engine; mốc cũ vô nghĩa, nhận báo kế tiếp làm mốc.
            n = 0; cursor = -1; reliable = false
            setSelection(-1, -1)
            push(WILDCARD)
            return false
        }
        if (newSelStart != newSelEnd) {
            n = 0; cursor = -1
            setSelection(newSelStart, newSelEnd)
            return true
        }
        setSelection(-1, -1)
        for (i in 0 until n) {
            val q = queue[i]
            if (q == WILDCARD || q == newSelStart) {
                if (q != WILDCARD) reliable = true
                drop(i + 1)
                // Mốc cuối vừa khớp ⇒ con trỏ chắc chắn; còn mốc sau ⇒ giữ dự đoán.
                if (n == 0) cursor = newSelStart
                return false
            }
        }
        if (n == 0 && newSelStart == cursor) return false   // app báo lặp
        n = 0
        cursor = newSelStart
        return true
    }

    private fun push(v: Int) {
        if (n == CAP) drop(1)
        queue[n++] = v
    }

    private fun drop(k: Int) {
        if (k >= n) { n = 0; return }
        System.arraycopy(queue, k, queue, 0, n - k)
        n -= k
    }

    companion object {
        const val WILDCARD = Int.MIN_VALUE
        private const val CAP = 32
    }
}
