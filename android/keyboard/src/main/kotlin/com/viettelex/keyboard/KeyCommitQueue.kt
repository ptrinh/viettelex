package com.viettelex.keyboard

/**
 * Thứ tự chốt phím khi gõ chồng ngón (port iOS). Phím chữ chèn lúc DOWN; space /
 * dấu câu / số / return: [arm] lúc DOWN, [release] lúc UP hoặc CANCEL, [flush] khi
 * ngón KHÁC chạm xuống, [disarm] khi vào trackpad. [id] = định danh phím (so sánh
 * bằng identity: truyền cùng object phím).
 */
class KeyCommitQueue {
    private class Pending(val id: Any, val fire: () -> Unit)
    private val pending = ArrayList<Pending>(4)

    val isEmpty: Boolean get() = pending.isEmpty()

    fun arm(id: Any, fire: () -> Unit) {
        // cùng phím đè lần nữa khi lần trước chưa nhấc: lần trước là phím thật — chốt.
        release(id)
        pending.add(Pending(id, fire))
    }

    /** Chốt mọi phím đang chờ trừ [except], theo thứ tự chạm. */
    fun flush(except: Any? = null) {
        if (pending.isEmpty()) return
        val fired = pending.filter { it.id !== except }
        pending.removeAll { it.id !== except }
        for (p in fired) p.fire()
    }

    fun release(id: Any) {
        val i = pending.indexOfFirst { it.id === id }
        if (i < 0) return
        pending.removeAt(i).fire()
    }

    fun disarm(id: Any) { pending.removeAll { it.id === id } }
}
