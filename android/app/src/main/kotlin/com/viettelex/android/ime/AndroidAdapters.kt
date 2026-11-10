package com.viettelex.android.ime

import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Context
import android.content.res.AssetManager
import android.os.SystemClock
import android.view.KeyEvent
import android.view.inputmethod.InputConnection
import com.viettelex.keyboard.ClipboardSource
import java.io.FileInputStream
import java.nio.ByteBuffer
import java.nio.channels.FileChannel

/** [EditorPort] thật trên một InputConnection (logic nằm ở [IcProxy], thuần). */
class AndroidEditorPort(val ic: InputConnection) : EditorPort {
    override fun beginBatch() { ic.beginBatchEdit() }
    override fun endBatch() { ic.endBatchEdit() }
    override fun commitText(text: CharSequence) = ic.commitText(text, 1)
    override fun deleteBefore(utf16: Int) = ic.deleteSurroundingText(utf16, 0)
    override fun deleteCodePointsBefore(count: Int) = ic.deleteSurroundingTextInCodePoints(count, 0)
    override fun deleteSurrounding(before: Int, after: Int) = ic.deleteSurroundingText(before, after)
    override fun textBefore(n: Int): CharSequence? = ic.getTextBeforeCursor(n, 0)
    override fun textAfter(n: Int): CharSequence? = ic.getTextAfterCursor(n, 0)
    override fun selectedText(): CharSequence? = ic.getSelectedText(0)
    override fun setSelection(start: Int, end: Int) = ic.setSelection(start, end)
    override fun finishComposing() = ic.finishComposingText()
    override fun performEditorAction(actionId: Int) = ic.performEditorAction(actionId)

    @Suppress("DEPRECATION")   // ACTION_MULTIPLE + chuỗi: cách duy nhất gửi ký tự Unicode qua key event
    override fun sendText(text: CharSequence) {
        ic.sendKeyEvent(KeyEvent(android.os.SystemClock.uptimeMillis(), text.toString(),
            android.view.KeyCharacterMap.VIRTUAL_KEYBOARD, 0))
    }

    override fun sendKey(key: EditorPort.PortKey) {
        val code = when (key) {
            EditorPort.PortKey.DEL -> KeyEvent.KEYCODE_DEL
            EditorPort.PortKey.ENTER -> KeyEvent.KEYCODE_ENTER
            EditorPort.PortKey.LEFT -> KeyEvent.KEYCODE_DPAD_LEFT
            EditorPort.PortKey.RIGHT -> KeyEvent.KEYCODE_DPAD_RIGHT
            EditorPort.PortKey.UP -> KeyEvent.KEYCODE_DPAD_UP
            EditorPort.PortKey.DOWN -> KeyEvent.KEYCODE_DPAD_DOWN
            EditorPort.PortKey.HOME -> KeyEvent.KEYCODE_MOVE_HOME
            EditorPort.PortKey.END -> KeyEvent.KEYCODE_MOVE_END
            EditorPort.PortKey.A -> KeyEvent.KEYCODE_A
            EditorPort.PortKey.C -> KeyEvent.KEYCODE_C
            EditorPort.PortKey.V -> KeyEvent.KEYCODE_V
            EditorPort.PortKey.X -> KeyEvent.KEYCODE_X
            EditorPort.PortKey.Z -> KeyEvent.KEYCODE_Z
        }
        send(code, 0)
    }

    override fun sendKeyMeta(key: EditorPort.PortKey, shift: Boolean, ctrl: Boolean) {
        var meta = 0
        if (shift) meta = meta or KeyEvent.META_SHIFT_ON or KeyEvent.META_SHIFT_LEFT_ON
        if (ctrl) meta = meta or KeyEvent.META_CTRL_ON or KeyEvent.META_CTRL_LEFT_ON
        if (meta == 0) { sendKey(key); return }
        val code = when (key) {
            EditorPort.PortKey.LEFT -> KeyEvent.KEYCODE_DPAD_LEFT
            EditorPort.PortKey.RIGHT -> KeyEvent.KEYCODE_DPAD_RIGHT
            EditorPort.PortKey.UP -> KeyEvent.KEYCODE_DPAD_UP
            EditorPort.PortKey.DOWN -> KeyEvent.KEYCODE_DPAD_DOWN
            EditorPort.PortKey.HOME -> KeyEvent.KEYCODE_MOVE_HOME
            EditorPort.PortKey.END -> KeyEvent.KEYCODE_MOVE_END
            EditorPort.PortKey.A -> KeyEvent.KEYCODE_A
            EditorPort.PortKey.C -> KeyEvent.KEYCODE_C
            EditorPort.PortKey.V -> KeyEvent.KEYCODE_V
            EditorPort.PortKey.X -> KeyEvent.KEYCODE_X
            EditorPort.PortKey.Z -> KeyEvent.KEYCODE_Z
            EditorPort.PortKey.DEL -> KeyEvent.KEYCODE_DEL
            EditorPort.PortKey.ENTER -> KeyEvent.KEYCODE_ENTER
        }
        send(code, meta)
    }

    private fun send(code: Int, meta: Int) {
        val t = SystemClock.uptimeMillis()
        val flags = KeyEvent.FLAG_SOFT_KEYBOARD or KeyEvent.FLAG_KEEP_TOUCH_MODE
        ic.sendKeyEvent(KeyEvent(t, t, KeyEvent.ACTION_DOWN, code, 0, meta, -1, 0, flags))
        ic.sendKeyEvent(KeyEvent(t, t, KeyEvent.ACTION_UP, code, 0, meta, -1, 0, flags))
    }

    override fun menuAction(action: EditorPort.MenuAction): Boolean = ic.performContextMenuAction(when (action) {
        EditorPort.MenuAction.SELECT_ALL -> android.R.id.selectAll
        EditorPort.MenuAction.COPY -> android.R.id.copy
        EditorPort.MenuAction.CUT -> android.R.id.cut
        EditorPort.MenuAction.PASTE -> android.R.id.paste
        EditorPort.MenuAction.UNDO -> android.R.id.undo
        EditorPort.MenuAction.REDO -> android.R.id.redo
    })
}

/**
 * Nguồn clipboard cho nút Dán (§7.1): đếm đổi bằng addPrimaryClipChangedListener; chỉ
 * đọc ClipDescription (không bật toast "đã dán") cho tới khi user chạm.
 */
class AndroidClipboard(context: Context) : ClipboardSource {
    /**
     * Context ỨNG DỤNG, không phải service: ClipboardManager giữ context nó được lấy từ, và
     * binder listener chỉ được thả khi system_server GC proxy ⇒ lấy từ service thì mỗi lần đổi
     * IME rò nguyên một VietTelexIME (RAM-AUDIT #2).
     */
    private val ctx: Context = context.applicationContext ?: context
    private val cm = ctx.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
    @Volatile private var count = 0
    /**
     * Gọi (main thread) mỗi lần clip đổi — IME ghi lịch sử clipboard. Listener chỉ sống
     * khi process IME sống (VietTelex là bàn phím đang chọn); copy lúc process chết thì
     * bù ở lần hiện kế ([ClipDescription.getTimestamp] ≤ 180 s).
     */
    var onChanged: (() -> Unit)? = null
    private val listener = ClipboardManager.OnPrimaryClipChangedListener { count++; onChanged?.invoke() }

    init { cm.addPrimaryClipChangedListener(listener) }

    fun release() = cm.removePrimaryClipChangedListener(listener)

    override val changeCount: Int get() = count

    /**
     * ClipDescription của clip hiện tại — một binder mỗi lần clip đổi ([count]) / mỗi lần hiện
     * ([invalidateFacts]); hasText / isSensitive / clipId đọc từ đây.
     */
    private val facts = ClipFactsCache {
        try {
            cm.primaryClipDescription?.let { d ->
                ClipFacts(text = d.hasMimeType(ClipDescription.MIMETYPE_TEXT_PLAIN) || d.hasMimeType("text/*"),
                    timestamp = d.timestamp,
                    sensitive = d.extras?.getBoolean(EXTRA_IS_SENSITIVE, false) == true)
            }
        } catch (_: Exception) { null }
    }

    /** Bàn phím vừa hiện: quyền đọc clipboard có thể vừa đổi ⇒ đọc lại ClipDescription ở lần cần kế. */
    fun invalidateFacts() = facts.invalidate()

    override fun hasText(): Boolean = facts.get(count)?.let { it.text && isRecent(it.timestamp) } ?: false

    /**
     * Clip copy TRƯỚC khi process IME sống thì listener không thấy — dùng timestamp hệ
     * thống (API 26) để không mời dán clip cũ > 180 s. Chịu cả hai time base.
     */
    private fun isRecent(ts: Long): Boolean {
        if (ts <= 0) return true
        val now = if (ts > 1_000_000_000_000L) System.currentTimeMillis() else SystemClock.elapsedRealtime()
        return now - ts < 180_000
    }

    /** Android 13+: app nguồn đánh dấu EXTRA_IS_SENSITIVE (mật khẩu, OTP từ trình quản lý mật khẩu). */
    override fun isSensitive(): Boolean = facts.get(count)?.sensitive == true

    override fun readText(): String? = try {
        cm.primaryClip?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.coerceToText(ctx)?.toString()
            .also { readHash = it?.hashCode(); readHashCount = count }
    } catch (_: Exception) { null }

    /** Hash nội dung ĐÃ đọc (chip/lịch sử) cho clip hiện tại — chỉ dự phòng cho [clipId]. */
    private var readHash: Int? = null
    private var readHashCount = -1

    /**
     * Id bền: timestamp hệ thống của ClipDescription (API 26, không đọc nội dung, giữ qua lần
     * process IME chết). Không có ⇒ hash nội dung nếu đã đọc sẵn, cuối cùng changeCount.
     */
    override fun clipId(): Long {
        val ts = facts.get(count)?.timestamp ?: 0L
        if (ts > 0) return ts
        val h = readHash
        return if (h != null && readHashCount == count) (1L shl 40) + h else -1L - count
    }

    private companion object {
        /** = ClipDescription.EXTRA_IS_SENSITIVE (API 33); hằng chuỗi để chạy cả máy cũ. */
        const val EXTRA_IS_SENSITIVE = "android.content.extra.IS_SENSITIVE"
    }
}

/** Blob assets: mmap (asset không nén) — fallback đọc cả file. */
object AssetBlobs {
    fun provider(am: AssetManager): (String) -> ByteBuffer = { name ->
        try {
            am.openFd(name).use { fd ->
                FileInputStream(fd.fileDescriptor).channel.use { ch ->
                    ch.map(FileChannel.MapMode.READ_ONLY, fd.startOffset, fd.length)
                }
            }
        } catch (_: Exception) {
            ByteBuffer.wrap(am.open(name).use { it.readBytes() })
        }
    }
}
