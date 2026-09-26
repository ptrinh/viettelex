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

    /**
     * Ký tự ngay trước con trỏ là ranh giới CHÍNH MÌNH vừa chèn ⇒ không có từ nào để nạp
     * lại, khỏi đọc context (IPC) ở chữ đầu mỗi từ.
     */
    private var afterOwnBoundary = false

    /**
     * Ghi checkpoint mỗi phím chữ để [undoLastLetter] huỷ được đúng phím đó khi nó hoá ra
     * là đầu một đường VUỐT (gõ vuốt). Tắt (mặc định) ⇒ không tốn gì.
     */
    var trackLetterUndo = false
        set(v) { field = v; if (!v) undo.valid = false }

    /**
     * Checkpoint của phím CHỮ gần nhất (port iOS `LetterUndo`). KHÔNG dùng ⌫ để huỷ:
     * engine.backspace() xoá chữ cuối ĐANG HIỆN chứ không gỡ phím vừa gõ — "tieng" + s
     * rồi ⌫ ra "tiến". Mọi thao tác khác ngoài letter() đều xoá checkpoint.
     * Engine snapshot cấp MỘT lần, copyInto mỗi phím (không cấp phát trên hot path).
     */
    private class LetterUndo {
        val engine = TelexEngine()
        var removed = ""      // chữ phím đó đã xoá khỏi màn hình
        var inserted = ""     // chữ phím đó đã chèn
        var ownBoundary = false
        var valid = false
    }
    private val undo = LetterUndo()

    private fun checkpoint(ownBoundary: Boolean) {
        if (!trackLetterUndo) return
        engine.copyInto(undo.engine)
        undo.ownBoundary = ownBoundary
    }

    private fun recordUndo(action: TelexAction, before: String, literal: String) {
        if (!trackLetterUndo) return
        when (action) {
            is TelexAction.Replace -> {
                undo.removed = before.substring(Cp.dropLast(before, action.backspaces).length)
                undo.inserted = action.insert
            }
            TelexAction.Passthrough -> { undo.removed = ""; undo.inserted = literal }
            TelexAction.None -> { undo.removed = ""; undo.inserted = "" }
        }
        undo.valid = true
    }

    /**
     * Huỷ phím chữ vừa gõ (chỉ khi chưa có thao tác nào khác xen vào): trả màn hình và
     * engine về đúng trước phím đó. Chữ trước con trỏ không kết thúc bằng thứ phím đó
     * đã chèn ⇒ không sửa gì, trả false (caller tự xử lý).
     */
    fun undoLastLetter(proxy: TextProxy): Boolean {
        if (!undo.valid) return false
        undo.valid = false
        if (!proxy.confirmTail(undo.inserted)) return false
        val n = Cp.count(undo.inserted)
        if (n > 0) proxy.deleteCodePoints(n)
        if (undo.removed.isNotEmpty()) proxy.insertText(undo.removed)
        undo.engine.copyInto(engine)
        afterOwnBoundary = undo.ownBoundary
        TouchLog.write("undo letter: -$n +${Cp.count(undo.removed)}")
        return true
    }

    /**
     * Từ vừa chèn nguyên khối (gõ vuốt) thành composition đang mở: phím dấu Telex sửa được,
     * ⌫ engine như từ gõ tay. false = từ không round-trip qua engine (engine để trống).
     */
    fun adoptWord(word: String): Boolean {
        undo.valid = false
        afterOwnBoundary = false
        val ok = engine.seed(word)
        if (!ok) engine.reset()
        return ok
    }

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
        undo.valid = false
        if (proxy.isSecure || passthrough) {
            checkpoint(afterOwnBoundary)
            proxy.insertText(ch.toString())
            recordUndo(TelexAction.Passthrough, "", ch.toString())
            return
        }
        val ownBoundary = afterOwnBoundary
        val seedable = settings.reEditWords && engine.isEmpty && !afterOwnBoundary && ReEdit.isTransformKey(ch)
        afterOwnBoundary = false
        checkpoint(ownBoundary)
        if (seedable && trySeed(ch, proxy)) return
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
        recordUndo(action, before, ch.toString())
    }

    /**
     * Space / return / dấu câu: boundary → auto-restore rồi chèn [text]. Trả từ ĐÃ
     * CHỐT (sau auto-restore) để model học đúng thứ nằm trên màn hình.
     */
    fun boundary(text: String, proxy: TextProxy): String {
        undo.valid = false
        if (proxy.isSecure || passthrough) { proxy.insertText(text); return "" }
        afterOwnBoundary = text.isNotEmpty() && !Character.isLetterOrDigit(text.codePointBefore(text.length))
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

    /**
     * Phím dấu/mũ khi engine rỗng, con trỏ ở CUỐI một từ đã có trên màn hình ("viet|" + j):
     * seed engine bằng từ đó rồi feed phím ⇒ "việt". Chỉ nhận khi seed khớp đúng từ VÀ phím
     * thật sự biến đổi nó; mọi trường hợp khác trả false (caller gõ literal như cũ).
     */
    private fun trySeed(ch: Char, proxy: TextProxy): Boolean {
        if (!proxy.canReEdit) return false
        val before = proxy.contextBeforeInput() ?: return false
        val word = ReEdit.trailingWord(before) ?: return false
        val after = proxy.contextAfterInput() ?: return false
        if (!ReEdit.atWordEnd(after) || proxy.hasSelection) return false
        if (!engine.seed(word)) return false
        val action = engine.feed(ch)
        if (action !is TelexAction.Replace || action.backspaces <= 0 ||
            engine.composed == word + ch) {
            engine.reset()
            return false
        }
        TouchLog.write("re-edit: seeded ${Cp.count(word)} chars")
        apply(action, ch.toString(), proxy)
        // Checkpoint = engine TRỐNG trước seed; màn hình: đuôi từ bị thay ↔ phần chèn.
        recordUndo(action, word, ch.toString())
        return true
    }

    /**
     * ⌫. Trả true khi vừa MỞ LẠI từ chốt trước: ⌫ xoá ký tự ranh giới như thường và
     * engine giữ lại đúng từ đó ("tháy" ␣ ⌫ a → "thấy"). Chỉ khi chữ trước con trỏ khớp
     * đúng từ + ranh giới; lệch ⇒ quên từ, ⌫ thường.
     */
    fun backspace(proxy: TextProxy): Boolean {
        undo.valid = false
        if (proxy.isSecure || passthrough) { proxy.deleteBackward(); return false }
        afterOwnBoundary = false
        if (engine.isEmpty) {
            val reopened = settings.reEditWords && engine.canReopenLastCommit && tryReopen(proxy)
            if (!reopened) { engine.forgetLastCommit(); proxy.deleteBackward() }
            return reopened
        }
        val before = engine.composed
        when (val a = engine.backspace()) {
            is TelexAction.Replace -> {
                if (a.backspaces > 0 && !proxy.confirmTail(before)) {
                    // Từ đang soạn không còn trên màn hình: ⌫ thường, quên từ.
                    TouchLog.write("tail mismatch (backspace) → reset")
                    reset()
                    proxy.deleteBackward()
                    return false
                }
                if (a.backspaces > 0) proxy.deleteCodePoints(a.backspaces)
                if (a.insert.isNotEmpty()) proxy.insertText(a.insert)
            }
            else -> proxy.deleteBackward()
        }
        return false
    }

    private fun tryReopen(proxy: TextProxy): Boolean {
        if (!proxy.canReEdit || proxy.hasSelection) return false
        val before = proxy.contextBeforeInput() ?: return false
        val word = engine.reopenLastCommit() ?: return false
        if (!ReEdit.endsWithWordThenBoundary(before, word)) {
            // App nuốt ranh giới / tự sửa chữ / con trỏ lệch: không sửa màn hình.
            TouchLog.write("re-open: screen disagrees → reset")
            engine.reset()
            return false
        }
        proxy.deleteBackward()          // xoá ký tự ranh giới
        TouchLog.write("re-open: ${Cp.count(word)} chars back")
        return true
    }

    /** Bỏ snapshot mở lại (Enter có thể đã gửi tin / xuống dòng mà ⌫ không đảo được). */
    fun forgetLastCommit() = engine.forgetLastCommit()

    /** Đổi ô / con trỏ dời / ẩn bàn phím → quên từ + ngữ cảnh tiếng Anh. */
    fun reset() { engine.reset(); engine.resetContext(); afterOwnBoundary = false; undo.valid = false }

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
