package com.viettelex.android.ime

import com.viettelex.keyboard.TextProxy
import com.viettelex.keyboard.TouchLog
import com.viettelex.keyboard.WriteMode
import java.text.BreakIterator

/**
 * Mặt tối thiểu của InputConnection mà [IcProxy] dùng — tách ra để unit test bằng fake
 * (android.jar trong unit test chỉ là stub). Bản thật: [AndroidEditorPort].
 * Offset/độ dài đều là đơn vị UTF-16, trừ [deleteCodePointsBefore].
 */
interface EditorPort {
    fun beginBatch()
    fun endBatch()
    fun commitText(text: CharSequence): Boolean
    fun deleteBefore(utf16: Int): Boolean
    fun deleteCodePointsBefore(count: Int): Boolean
    /** Xoá quanh con trỏ (clearAll). */
    fun deleteSurrounding(before: Int, after: Int): Boolean
    fun textBefore(n: Int): CharSequence?
    fun textAfter(n: Int): CharSequence?
    fun setSelection(start: Int, end: Int): Boolean
    fun finishComposing(): Boolean
    fun performEditorAction(actionId: Int): Boolean
    /** Gửi DOWN+UP của phím [key] (qua key event — BẤT ĐỒNG BỘ so với commitText). */
    fun sendKey(key: PortKey)
    /** Gõ [text] bằng key event ký tự (app chỉ nhận phím — [WriteMode.KEY_ONLY]). */
    fun sendText(text: CharSequence) { commitText(text) }

    enum class PortKey { DEL, ENTER, LEFT, RIGHT }
}

/**
 * TextProxy trên InputConnection (spec §4): diff engine = deleteSurroundingTextInCodePoints
 * + commitText, gói trong beginBatchEdit/endBatchEdit bởi IME. Mỗi edit báo cho
 * [SelectionTracker] vị trí con trỏ mong đợi (§4.1).
 *
 * - ⌫ khi không soạn: xoá grapheme cuối bằng deleteSurroundingText (đồng bộ thứ tự với
 *   commitText); KEYCODE_DEL chỉ cho TYPE_NULL / ô trống / không đọc được (app tự xử lý,
 *   vd. xoá chip); có selection ⇒ commitText("").
 * - [shadow]: bản sao ~256 ký tự trước con trỏ, cập nhật theo edit của chính mình —
 *   giảm IPC getTextBeforeCursor trên main thread (Chrome có thể chặn tới 2 s). Chỉ dùng
 *   khi [SelectionTracker.reliable]; đổi từ ngoài ⇒ [invalidateShadow].
 * - Mọi edit kiểm giá trị trả về; thất bại ⇒ con trỏ "không biết", bỏ shadow, IME đọc
 *   [takeFailure] để reset engine.
 *
 * THUẦN (không Android API) — pinned by IcProxyTest.
 */
class IcProxy(
    private val portOf: () -> EditorPort?,
    private val tracker: SelectionTracker,
    private val nanoTime: () -> Long = System::nanoTime,
) : TextProxy {
    private var ic: EditorPort? = null
    var secure = false
    /** TYPE_NULL: chỉ key event. */
    var rawKeys = false
    /** Ô URI (thanh địa chỉ): trackpad dùng DPAD như cũ. */
    var uriField = false
    /** EditorInfo.IME_ACTION_*; 0 ⇒ "\n" = KEYCODE_ENTER. */
    var actionId = 0
    /**
     * Cách ghi theo app ([WriteMode.forPackage]): COMMIT như thường; DEL_VIA_KEY_EVENT
     * (ONLYOFFICE bỏ qua deleteSurroundingText) xoá bằng KEYCODE_DEL; KEY_ONLY (WPS bản
     * Xiaomi/Huawei, HSL — sandbox Linux) mọi thứ qua key event. Hai chế độ key event đi
     * CÙNG một hàng đợi nên giữ đúng thứ tự xoá→chèn; con trỏ/shadow coi là không biết.
     */
    var writeMode = WriteMode.COMMIT
    /** Đã gửi KEYCODE_DEL trong batch này ⇒ chèn tiếp PHẢI đi key event (cùng hàng đợi,
     *  đúng thứ tự); commitText sẽ chạy TRƯỚC phím DEL còn nằm trong hàng đợi. */
    private var keyDelQueued = false
    private var depth = 0
    private val shadow = TextShadow(CONTEXT_CAP)
    private var failed = false
    private var finishComposingPending = false

    /** Số lần đọc IPC getTextBeforeCursor (test / log). */
    var ipcReads = 0
        private set

    /** Mở batch; trả false nếu không có ô nhập. */
    fun begin(): Boolean {
        val c = portOf() ?: return false
        if (depth++ == 0) {
            ic = c
            c.beginBatch()
            // App để sót composing span (candidatesStart != -1): chốt trước khi ghi tiếp.
            if (finishComposingPending) { finishComposingPending = false; c.finishComposing() }
        }
        return true
    }

    fun end() {
        if (depth == 0) return
        if (--depth == 0) { ic?.endBatch(); ic = null; keyDelQueued = false }
    }

    private fun conn(): EditorPort? = ic ?: portOf()

    /** onStartInputView: [initialBefore] = getInitialTextBeforeCursor đã đối chiếu initialSel (null nếu không tin). */
    fun startInput(initialBefore: CharSequence?, atFieldStart: Boolean) {
        failed = false
        finishComposingPending = false
        if (initialBefore != null) shadow.set(initialBefore, atFieldStart) else shadow.invalidate()
    }

    /** Đổi từ ngoài (onUpdateSelection không khớp mốc): văn bản trước con trỏ phải đọc lại. */
    fun invalidateShadow() = shadow.invalidate()

    /** onUpdateSelection báo composing span còn sót ⇒ finishComposingText ở phím kế. */
    fun finishComposingOnNextEdit() { finishComposingPending = true }

    /** true (một lần) nếu có edit thất bại từ lần gọi trước — IME reset engine. */
    fun takeFailure(): Boolean { val f = failed; failed = false; return f }

    private fun fail(what: String) {
        failed = true
        tracker.unknown()
        shadow.invalidate()
        TouchLog.write("ic $what FAILED → reset")
    }

    override val isSecure: Boolean get() = secure

    override fun insertText(text: String) {
        if (text.isEmpty()) return
        val c = conn() ?: return
        if (text == "\n") { newline(c); return }
        if (writeMode == WriteMode.KEY_ONLY || (keyDelQueued && writeMode != WriteMode.COMMIT)) {
            c.sendText(text); tracker.unknown(); shadow.invalidate(); return
        }
        if (!c.commitText(text)) { fail("commitText"); return }
        tracker.inserted(text.length)
        shadow.inserted(text)
    }

    override fun deleteCodePoints(count: Int) {
        if (count <= 0) return
        val c = conn() ?: return
        // Đổi code point → UTF-16 theo shadow (emoji ngoài BMP khi xoá theo từ); không có
        // shadow thì chữ Việt dựng sẵn (BMP) ⇒ code point = đơn vị UTF-16.
        if (writeMode != WriteMode.COMMIT) {
            repeat(count) { c.sendKey(EditorPort.PortKey.DEL) }
            keyDelQueued = true
            tracker.unknown(); shadow.invalidate(); return
        }
        val units = shadow.utf16ForCodePoints(count) ?: count
        if (!c.deleteCodePointsBefore(count)) { fail("deleteSurroundingTextInCodePoints"); return }
        tracker.deleted(units)
        shadow.deleted(units)
    }

    /**
     * ⌫ "như user" khi không soạn. deleteSurroundingText theo grapheme cuối (emoji ZWJ,
     * cờ, dấu kết hợp — BreakIterator), KHÔNG KEYCODE_DEL: key event đi hàng đợi riêng
     * (ViewRootImpl.dispatchKeyFromIme post Message) nên lệch thứ tự với commitText cùng batch.
     */
    override fun deleteBackward() {
        val c = conn() ?: return
        if (rawKeys || writeMode != WriteMode.COMMIT) { keyDel(c); return }
        if (tracker.hasSelection) {
            if (c.commitText("")) tracker.inserted(0) else fail("commitText(\"\")")
            return
        }
        val before = contextBeforeInput()
        if (before.isNullOrEmpty()) { keyDel(c); return }   // ô trống / không đọc được: để app xử lý
        val n = Graphemes.lastLength(before)
        if (!c.deleteBefore(n)) { keyDel(c); return }
        tracker.deleted(n)
        shadow.deleted(n)
    }

    private fun keyDel(c: EditorPort) {
        c.sendKey(EditorPort.PortKey.DEL)
        keyDelQueued = true
        tracker.unknown()
        shadow.invalidate()
    }

    override fun contextBeforeInput(): String? {
        if (tracker.reliable) shadow.text()?.let { return it }
        return readBefore()
    }

    /** Đọc IPC (đo thời gian, ghi TouchLog) và nạp lại shadow. */
    private fun readBefore(): String? {
        val c = conn() ?: return null
        val t0 = nanoTime()
        val s = c.textBefore(CONTEXT_CAP)?.toString()
        ipcReads++
        if (TouchLog.enabled) TouchLog.write(String.format("ic getTextBeforeCursor %.1fms len=%d",
            (nanoTime() - t0) / 1e6, s?.length ?: -1))
        if (s != null) shadow.set(s, s.length < CONTEXT_CAP) else shadow.invalidate()
        return s
    }

    /**
     * Fail-safe trước khi xoá từ đang soạn. App đã chứng minh báo selection đúng
     * ([SelectionTracker.reliable]) ⇒ so với shadow (không IPC); chưa ⇒ đọc thật.
     */
    override fun confirmTail(expected: String): Boolean {
        if (expected.isEmpty()) return true
        // Key event đến app bất đồng bộ ⇒ text đọc được luôn trễ; so đuôi sẽ báo lệch oan.
        if (writeMode != WriteMode.COMMIT) return true
        val before = (if (tracker.reliable) shadow.text() else null) ?: readBefore() ?: return true
        // Shadow/IPC cắt 256 ký tự: từ dài hơn chỉ so phần còn thấy.
        val ok = before.endsWith(expected) ||
            (before.length >= CONTEXT_CAP && expected.endsWith(before))
        if (!ok) {
            TouchLog.write("ic tail mismatch len=${before.length} expected=${expected.length}")
            shadow.invalidate()
        }
        return ok
    }

    override fun clearAll() {
        val c = conn() ?: return
        c.commitText("")                     // xoá selection (nếu có)
        c.deleteSurrounding(20_000, 20_000)  // giới hạn an toàn như iOS
        tracker.unknown()
        shadow.invalidate()
    }

    private fun newline(c: EditorPort) {
        if (actionId != 0 && !rawKeys) c.performEditorAction(actionId) else c.sendKey(EditorPort.PortKey.ENTER)
        tracker.unknown()
        shadow.invalidate()
    }

    /**
     * Trackpad: [delta] grapheme trái/phải. Biết chắc con trỏ ⇒ setSelection (giới hạn
     * trong văn bản, không thoát focus ở đầu/cuối ô như DPAD); TYPE_NULL / URI / không
     * đọc được ⇒ DPAD như cũ.
     */
    fun moveCursor(delta: Int) {
        if (delta == 0) return
        val c = conn() ?: return
        val steps = minOf(kotlin.math.abs(delta), 64)
        val cur = tracker.cursor
        if (!rawKeys && !uriField && tracker.reliable && cur >= 0 && !tracker.hasSelection) {
            if (delta < 0) {
                val before = contextBeforeInput()
                if (before != null && before.length <= cur) {
                    val units = Graphemes.unitsBack(before, steps)
                    if (units == 0) return                    // đầu ô
                    if (c.setSelection(cur - units, cur - units)) {
                        tracker.movedTo(cur - units); shadow.deleted(units); return
                    }
                }
            } else {
                val after = c.textAfter(CONTEXT_CAP)?.toString()
                if (after != null) {
                    val units = Graphemes.unitsForward(after, steps)
                    if (units == 0) return                    // cuối ô
                    if (c.setSelection(cur + units, cur + units)) {
                        tracker.movedTo(cur + units); shadow.inserted(after.substring(0, units)); return
                    }
                }
            }
        }
        val key = if (delta < 0) EditorPort.PortKey.LEFT else EditorPort.PortKey.RIGHT
        repeat(steps) { c.sendKey(key) }
        tracker.unknown()
        shadow.invalidate()
    }

    // MARK: vuốt ⌫ xoá theo từ (điều phối ở SwipeDeleteController)

    /** Ảnh chụp lúc bắt đầu vuốt: [anchor] ≥ 0 ⇒ biết chắc con trỏ, được bôi đen bằng setSelection. */
    class SwipeContext(val before: String, val anchor: Int)

    /** null ⇒ tắt tính năng (mật khẩu, TYPE_NULL, không đọc được chữ trước con trỏ). */
    fun swipeContext(): SwipeContext? {
        if (secure || rawKeys) return null
        conn() ?: return null
        val before = contextBeforeInput() ?: return null
        val cur = tracker.cursor
        val canSelect = writeMode == WriteMode.COMMIT && tracker.reliable && !tracker.hasSelection &&
            cur >= before.length
        return SwipeContext(before, if (canSelect) cur else -1)
    }

    /** Bôi đen [units] UTF-16 trước [anchor] (0 ⇒ thu về con trỏ tại [anchor]). */
    fun selectBefore(anchor: Int, units: Int): Boolean {
        val c = conn() ?: return false
        val ok = c.setSelection(anchor - units, anchor)
        shadow.invalidate()                   // selection đổi "trước con trỏ"; đọc lại khi cần
        if (!ok) { tracker.unknown(); return false }
        if (units == 0) tracker.movedTo(anchor) else tracker.selectedByMe(anchor - units, anchor)
        return true
    }

    /** Xoá đoạn đang bôi đen (commitText("")); con trỏ về [start]. */
    fun deleteSelected(start: Int): Boolean {
        val c = conn() ?: return false
        if (!c.commitText("")) { fail("commitText(\"\") swipe"); return false }
        tracker.movedTo(start)
        shadow.invalidate()
        return true
    }

    /**
     * Xoá đúng [text] ngay trước con trỏ khi KHÔNG bôi đen được. COMMIT: fail-safe
     * [confirmTail] rồi deleteSurroundingText theo UTF-16; key event: một DEL mỗi grapheme.
     */
    fun deleteExact(text: String): Boolean {
        if (text.isEmpty()) return false
        val c = conn() ?: return false
        if (rawKeys || writeMode != WriteMode.COMMIT) {
            repeat(WordBoundary.graphemeCount(text)) { c.sendKey(EditorPort.PortKey.DEL) }
            keyDelQueued = true
            tracker.unknown(); shadow.invalidate()
            return true
        }
        if (!confirmTail(text)) return false
        if (!c.deleteBefore(text.length)) { fail("deleteSurroundingText swipe"); return false }
        tracker.deleted(text.length)
        shadow.deleted(text.length)
        return true
    }

    companion object {
        /** Độ dài văn bản trước con trỏ đọc/giữ (đủ cho auto-shift, email, xoá theo từ). */
        const val CONTEXT_CAP = 256
    }
}

/**
 * Bản sao văn bản trước con trỏ (≤ [cap] UTF-16). [atStart] = đang giữ TOÀN BỘ tới đầu ô.
 * Còn quá ít chữ mà chưa tới đầu ô ⇒ tự vô hiệu (đừng để auto-shift tưởng ô trống).
 */
class TextShadow(private val cap: Int) {
    private val sb = StringBuilder()
    private var valid = false
    private var atStart = false

    fun set(s: CharSequence, atFieldStart: Boolean) {
        sb.setLength(0)
        if (s.length > cap) { sb.append(s, s.length - cap, s.length); atStart = false }
        else { sb.append(s); atStart = atFieldStart }
        valid = true
        checkLow()
    }

    fun invalidate() { valid = false; sb.setLength(0) }

    fun text(): String? = if (valid) sb.toString() else null

    fun inserted(s: String) {
        if (!valid) return
        sb.append(s)
        if (sb.length > cap) {
            // Không cắt đôi surrogate ở đầu.
            var cut = sb.length - cap
            if (cut < sb.length && Character.isLowSurrogate(sb[cut])) cut++
            sb.delete(0, cut)
            atStart = false
        }
    }

    fun deleted(utf16: Int) {
        if (!valid || utf16 <= 0) return
        if (utf16 > sb.length) {
            if (atStart) sb.setLength(0) else invalidate()
            return
        }
        sb.setLength(sb.length - utf16)
        checkLow()
    }

    /** Số UTF-16 của [count] code point cuối; null nếu shadow không đủ để biết. */
    fun utf16ForCodePoints(count: Int): Int? {
        if (!valid) return null
        var end = sb.length
        var k = 0
        while (k < count && end > 0) { end -= Character.charCount(Character.codePointBefore(sb, end)); k++ }
        return if (k == count) sb.length - end else null
    }

    private fun checkLow() {
        if (!atStart && sb.length < LOW) invalidate()
    }

    private companion object { const val LOW = 32 }
}

/** Đếm grapheme (BreakIterator) — không bao giờ cắt đôi surrogate. */
object Graphemes {
    /** Độ dài UTF-16 của grapheme cuối; 0 nếu rỗng. */
    fun lastLength(s: CharSequence): Int = unitsBack(s, 1)

    /** Số UTF-16 lùi [steps] grapheme từ cuối [s] (dừng ở đầu). */
    fun unitsBack(s: CharSequence, steps: Int): Int {
        if (s.isEmpty() || steps <= 0) return 0
        val str = s.toString()
        val bi = BreakIterator.getCharacterInstance()
        bi.setText(str)
        var pos = str.length
        repeat(steps) {
            if (pos <= 0) return@repeat
            var p = bi.preceding(pos)
            if (p == BreakIterator.DONE) p = 0
            // An toàn: ít nhất một code point trọn vẹn.
            val cpStart = pos - Character.charCount(str.codePointBefore(pos))
            pos = minOf(p, cpStart)
        }
        return str.length - pos
    }

    /** Số UTF-16 tiến [steps] grapheme từ đầu [s] (dừng ở cuối). */
    fun unitsForward(s: CharSequence, steps: Int): Int {
        if (s.isEmpty() || steps <= 0) return 0
        val str = s.toString()
        val bi = BreakIterator.getCharacterInstance()
        bi.setText(str)
        var pos = 0
        repeat(steps) {
            if (pos >= str.length) return@repeat
            var p = bi.following(pos)
            if (p == BreakIterator.DONE) p = str.length
            pos = maxOf(p, pos + Character.charCount(str.codePointAt(pos)))
        }
        return pos
    }
}

/**
 * EditorInfo.initialSelStart không tin tuyệt đối: đối chiếu với độ dài
 * getInitialTextBeforeCursor (API 30+). Lệch ⇒ coi con trỏ không biết.
 */
object InitialSelection {
    /**
     * @param beforeLen độ dài getInitialTextBeforeCursor([requested]); null = app không cấp.
     * @return true nếu initialSel dùng được.
     */
    fun trusted(selStart: Int, selEnd: Int, beforeLen: Int?, requested: Int): Boolean {
        if (selStart < 0 || selEnd < 0) return false
        if (beforeLen == null) return true            // không có căn cứ đối chiếu
        val start = minOf(selStart, selEnd)
        return when {
            beforeLen > start -> false                // nhiều chữ hơn vị trí con trỏ: sai chắc
            beforeLen == start -> true
            else -> beforeLen >= requested            // bị cắt do mình xin ít; ngắn hơn ⇒ lệch
        }
    }

    /** Văn bản ban đầu có chạm đầu ô (dùng cho shadow). */
    fun reachesFieldStart(selStart: Int, selEnd: Int, beforeLen: Int): Boolean =
        beforeLen == minOf(selStart, selEnd)
}
