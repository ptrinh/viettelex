package com.viettelex.android.ime

import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Context
import android.content.res.AssetManager
import android.inputmethodservice.InputMethodService
import android.os.SystemClock
import android.view.KeyEvent
import android.view.inputmethod.InputConnection
import com.viettelex.keyboard.ClipboardSource
import com.viettelex.keyboard.TextProxy
import java.io.FileInputStream
import java.nio.ByteBuffer
import java.nio.channels.FileChannel

/**
 * TextProxy trên InputConnection (spec §4): diff engine = deleteSurroundingTextInCodePoints
 * + commitText, gói trong beginBatchEdit/endBatchEdit bởi IME. Mỗi edit báo cho
 * [SelectionTracker] vị trí con trỏ mong đợi (§4.1).
 */
class IcProxy(private val ims: InputMethodService, private val tracker: SelectionTracker) : TextProxy {
    private var ic: InputConnection? = null
    var secure = false
    /** TYPE_NULL: chỉ key event. */
    var rawKeys = false
    /** EditorInfo.IME_ACTION_*; 0 ⇒ "\n" = KEYCODE_ENTER. */
    var actionId = 0
    private var depth = 0

    /** Mở batch; trả false nếu không có ô nhập. */
    fun begin(): Boolean {
        val c = ims.currentInputConnection ?: return false
        if (depth++ == 0) { ic = c; c.beginBatchEdit() }
        return true
    }

    fun end() {
        if (depth == 0) return
        if (--depth == 0) { ic?.endBatchEdit(); ic = null }
    }

    private fun conn(): InputConnection? = ic ?: ims.currentInputConnection

    override val isSecure: Boolean get() = secure

    override fun insertText(text: String) {
        if (text.isEmpty()) return
        val c = conn() ?: return
        if (text == "\n") { newline(c); return }
        c.commitText(text, 1)
        tracker.inserted(text.length)
    }

    override fun deleteCodePoints(count: Int) {
        if (count <= 0) return
        val c = conn() ?: return
        c.deleteSurroundingTextInCodePoints(count, 0)
        // Diff engine chỉ xoá chữ Việt dựng sẵn (BMP) ⇒ code point = đơn vị UTF-16.
        tracker.deleted(count)
    }

    /** ⌫ "như user": KEYCODE_DEL xoá cả grapheme (emoji ZWJ) / cả selection, chạy cả TYPE_NULL. */
    override fun deleteBackward() {
        val c = conn() ?: return
        sendKey(c, KeyEvent.KEYCODE_DEL)
        tracker.unknown()
    }

    override fun contextBeforeInput(): String? = conn()?.getTextBeforeCursor(256, 0)?.toString()

    override fun clearAll() {
        val c = conn() ?: return
        c.commitText("", 1)                         // xoá selection (nếu có)
        c.deleteSurroundingText(20_000, 20_000)     // giới hạn an toàn như iOS
        tracker.unknown()
    }

    private fun newline(c: InputConnection) {
        if (actionId != 0 && !rawKeys) c.performEditorAction(actionId) else sendKey(c, KeyEvent.KEYCODE_ENTER)
        tracker.unknown()
    }

    /** Trackpad: một ký tự trái/phải mỗi bước. */
    fun moveCursor(delta: Int) {
        val c = conn() ?: return
        val code = if (delta < 0) KeyEvent.KEYCODE_DPAD_LEFT else KeyEvent.KEYCODE_DPAD_RIGHT
        repeat(minOf(kotlin.math.abs(delta), 64)) { sendKey(c, code) }
        tracker.unknown()
    }

    private fun sendKey(c: InputConnection, code: Int) {
        val t = SystemClock.uptimeMillis()
        val flags = KeyEvent.FLAG_SOFT_KEYBOARD or KeyEvent.FLAG_KEEP_TOUCH_MODE
        c.sendKeyEvent(KeyEvent(t, t, KeyEvent.ACTION_DOWN, code, 0, 0, -1, 0, flags))
        c.sendKeyEvent(KeyEvent(t, t, KeyEvent.ACTION_UP, code, 0, 0, -1, 0, flags))
    }
}

/**
 * Nguồn clipboard cho nút Dán (§7.1): đếm đổi bằng addPrimaryClipChangedListener; chỉ
 * đọc ClipDescription (không bật toast "đã dán") cho tới khi user chạm.
 */
class AndroidClipboard(private val ctx: Context) : ClipboardSource {
    private val cm = ctx.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
    @Volatile private var count = 0
    private val listener = ClipboardManager.OnPrimaryClipChangedListener { count++ }

    init { cm.addPrimaryClipChangedListener(listener) }

    fun release() = cm.removePrimaryClipChangedListener(listener)

    override val changeCount: Int get() = count

    override fun hasText(): Boolean = try {
        val d = cm.primaryClipDescription
        d != null && (d.hasMimeType(ClipDescription.MIMETYPE_TEXT_PLAIN) || d.hasMimeType("text/*")) && isRecent(d)
    } catch (_: Exception) { false }

    /**
     * Clip copy TRƯỚC khi process IME sống thì listener không thấy — dùng timestamp hệ
     * thống (API 26) để không mời dán clip cũ > 180 s. Chịu cả hai time base.
     */
    private fun isRecent(d: ClipDescription): Boolean {
        val ts = d.timestamp
        if (ts <= 0) return true
        val now = if (ts > 1_000_000_000_000L) System.currentTimeMillis() else SystemClock.elapsedRealtime()
        return now - ts < 180_000
    }

    override fun readText(): String? = try {
        cm.primaryClip?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.coerceToText(ctx)?.toString()
    } catch (_: Exception) { null }
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
