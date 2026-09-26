package com.viettelex.keyboard

/** Lát cắt InputConnection mà bridge/session cần (≈ UITextDocumentProxy). */
interface TextProxy {
    /** commitText(text, 1). */
    fun insertText(text: String)
    /** Xoá đúng [count] code point trước con trỏ (diff của engine). */
    fun deleteCodePoints(count: Int)
    /** Một lần ⌫ "như user" (KEYCODE_DEL / grapheme) khi không đang soạn. */
    fun deleteBackward()
    /** Ô mật khẩu ⇒ literal, bỏ engine. */
    val isSecure: Boolean
    /** Văn bản trước con trỏ (vài trăm ký tự là đủ); null nếu không đọc được. */
    fun contextBeforeInput(): String? = null
    /** 🗑 mẫu câu: xoá sạch ô (giới hạn an toàn 20 000 ký tự). */
    fun clearAll() {}
    /**
     * Fail-safe TRƯỚC khi xoá chữ của từ đang soạn: văn bản trước con trỏ có kết thúc
     * bằng [expected] (từ engine đang giữ) không. false ⇒ ô đã đổi mà mình không được
     * báo — caller reset engine và chèn literal thay vì xoá mù. Không đọc được ⇒ true
     * (không có căn cứ, giữ hành vi cũ).
     */
    fun confirmTail(expected: String): Boolean = true

    /**
     * Ô cho phép SỬA LẠI từ đã chốt (⌫ mở lại từ, phím dấu nạp lại từ trước con trỏ):
     * đọc được chữ và ghi bằng commitText/deleteSurroundingText đồng bộ. false ở ô
     * TYPE_NULL, ô URI (omnibox tự hoàn tất chữ), app chỉ nhận key event. Mặc định false.
     */
    val canReEdit: Boolean get() = false
    /** Đang có selection (không rỗng) — sửa lại từ sẽ đè lên nó ⇒ không làm. */
    val hasSelection: Boolean get() = false
    /** Vài ký tự SAU con trỏ; null nếu không đọc được. */
    fun contextAfterInput(): String? = null
}

/** Main-thread scheduler (Android: Handler main looper). */
interface MainThread {
    fun post(r: Runnable)
    fun postDelayed(delayMs: Long, r: Runnable): Cancellable
}

fun interface Cancellable { fun cancel() }

/** Chạy ngay tại chỗ — cho test/in-memory. postDelayed giữ lại tới khi [runPending]. */
class ImmediateMainThread : MainThread {
    private val pending = ArrayList<Runnable>()
    override fun post(r: Runnable) = r.run()
    override fun postDelayed(delayMs: Long, r: Runnable): Cancellable {
        pending.add(r)
        return Cancellable { pending.remove(r) }
    }
    fun runPending() { val p = pending.toList(); pending.clear(); p.forEach { it.run() } }
    val pendingCount: Int get() = pending.size
}

/** Nguồn clipboard cho nút Dán (§7.1). */
interface ClipboardSource {
    /** Tăng mỗi lần primary clip đổi (IME đếm trong addPrimaryClipChangedListener). */
    val changeCount: Int
    /** Clip hiện tại là text (chỉ đọc ClipDescription, không đọc nội dung). */
    fun hasText(): Boolean
    /** Nội dung — chỉ gọi khi user chạm Dán. */
    fun readText(): String?
}

internal object Cp {
    fun count(s: String): Int = s.codePointCount(0, s.length)
    fun dropLast(s: String, n: Int): String {
        if (n <= 0) return s
        var end = s.length
        var k = n
        while (k > 0 && end > 0) { end = s.offsetByCodePoints(end, -1); k-- }
        return s.substring(0, end)
    }
    fun lastCodePoint(s: String): Int? = if (s.isEmpty()) null else s.codePointBefore(s.length)
    fun capitalizeFirst(w: String): String {
        if (w.isEmpty()) return w
        val first = w.codePointAt(0)
        val n = Character.charCount(first)
        return String(Character.toChars(first)).uppercase() + w.substring(n)
    }
}
