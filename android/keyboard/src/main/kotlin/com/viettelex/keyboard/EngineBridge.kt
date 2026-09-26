package com.viettelex.keyboard

import com.viettelex.telexcore.TelexAction
import com.viettelex.telexcore.TelexEngine

/**
 * Keo giữa TelexEngine và [TextProxy] — port 1:1 iOS EngineBridge. Mỗi phím →
 * diff tối thiểu (xoá N code point + chèn). Không Android API.
 */
class EngineBridge(settings: KeyboardSettings = KeyboardSettings()) {
    private var settings = settings
    private val engine = TelexEngine().also { configure(it, true) }

    /** Ô không autocorrect (mã/username): gõ LITERAL, bỏ engine. */
    var passthrough = false

    private fun configure(e: TelexEngine, contextual: Boolean) {
        e.freeMarking = settings.freeMarking
        e.simpleTelex = settings.simpleTelex
        e.liveSpellCheck = settings.liveSpellCheck
        e.quickTelex = settings.quickTelex
        e.modernTone = settings.modernTone
        e.teencode = settings.teencode
        if (contextual) e.contextualEnglish = settings.contextualEnglish
    }

    /**
     * Settings đổi khi bàn phím ĐANG hiện (Android: app settings cùng màn hình với ô Thử gõ,
     * không có onStartInputView mới) — áp ngay vào engine, không reset chữ đang gõ.
     */
    fun applySettings(s: KeyboardSettings) { settings = s; configure(engine, true) }

    /** Phím chữ (đã theo shift). */
    fun letter(ch: Char, proxy: TextProxy) {
        if (proxy.isSecure || passthrough) { proxy.insertText(ch.toString()); return }
        val before = engine.composed
        val action = engine.feed(ch)
        if (action is TelexAction.Replace && action.backspaces > 0 && !proxy.confirmTail(before)) {
            // Chữ trên màn hình không còn là từ engine đang giữ (ô bị đổi mà không được báo):
            // KHÔNG xoá mù — quên từ, bắt đầu từ mới bằng chính phím này.
            TouchLog.write("tail mismatch (letter) → reset")
            reset()
            val fresh = engine.feed(ch)
            if (fresh is TelexAction.Replace && fresh.backspaces > 0) { reset(); proxy.insertText(ch.toString()) }
            else apply(fresh, ch.toString(), proxy)
            return
        }
        apply(action, ch.toString(), proxy)
    }

    /**
     * Space / return / dấu câu: boundary → auto-restore rồi chèn [text]. Trả từ ĐÃ
     * CHỐT (sau auto-restore) để model học đúng thứ nằm trên màn hình.
     */
    fun boundary(text: String, proxy: TextProxy): String {
        if (proxy.isSecure || passthrough) { proxy.insertText(text); return "" }
        val before = engine.composed
        val action = engine.commitBoundary(settings.autoRestore)
        if (action is TelexAction.Replace && action.backspaces > 0 && !proxy.confirmTail(before)) {
            // Auto-restore cần xoá nhưng chữ trước con trỏ không khớp: bỏ restore, không học.
            TouchLog.write("tail mismatch (boundary) → reset")
            reset()
            proxy.insertText(text)
            return ""
        }
        var final = before
        if (action is TelexAction.Replace) final = Cp.dropLast(before, action.backspaces) + action.insert
        apply(action, "", proxy)
        proxy.insertText(text)
        return final
    }

    fun backspace(proxy: TextProxy) {
        if (proxy.isSecure || passthrough || engine.isEmpty) { proxy.deleteBackward(); return }
        val before = engine.composed
        when (val a = engine.backspace()) {
            is TelexAction.Replace -> {
                if (a.backspaces > 0 && !proxy.confirmTail(before)) {
                    // Từ đang soạn không còn trên màn hình: ⌫ thường, quên từ.
                    TouchLog.write("tail mismatch (backspace) → reset")
                    reset()
                    proxy.deleteBackward()
                    return
                }
                if (a.backspaces > 0) proxy.deleteCodePoints(a.backspaces)
                if (a.insert.isNotEmpty()) proxy.insertText(a.insert)
            }
            else -> proxy.deleteBackward()
        }
    }

    /** Đổi ô / con trỏ dời / ẩn bàn phím → quên từ + ngữ cảnh tiếng Anh. */
    fun reset() { engine.reset(); engine.resetContext() }

    val isComposing: Boolean get() = !engine.isEmpty
    val composedWord: String get() = engine.composed
    val rawWord: String get() = engine.rawKeystrokes
    val autoFixAdjacent: Boolean get() = settings.autoFixAdjacent

    /** Cache AdjacentKeyFixer theo raw — sống cùng bridge (cùng setting). */
    val adjacentFixCache = AdjacentKeyFixer.Cache()

    /**
     * Dạng hiển thị engine SẼ ra cho [raw] với đúng setting — engine scratch riêng
     * (như iOS: KHÔNG set contextualEnglish). Gọi được ngoài main thread.
     */
    fun composeTrial(raw: String): String {
        val e = TelexEngine()
        configure(e, false)
        for (ch in raw) e.feed(ch)
        return e.composed
    }

    /** Từ boundary SẼ chốt (peek non-mutating). */
    val predictedCommit: String get() = engine.peekCommitText(settings.autoRestore)

    private fun apply(action: TelexAction, literal: String, proxy: TextProxy) {
        when (action) {
            is TelexAction.Replace -> {
                TouchLog.edit(action.backspaces, Cp.count(action.insert), action.insert)
                if (action.backspaces > 0) proxy.deleteCodePoints(action.backspaces)
                if (action.insert.isNotEmpty()) proxy.insertText(action.insert)
            }
            TelexAction.Passthrough -> {
                TouchLog.edit(0, Cp.count(literal), literal)
                if (literal.isNotEmpty()) proxy.insertText(literal)
            }
            TelexAction.None -> {}
        }
    }
}
