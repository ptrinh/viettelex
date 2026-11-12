package com.viettelex.keyboard

import java.text.Normalizer
import java.util.Locale

/**
 * CÔNG CỤ VĂN BẢN (gói Plus, [PlusFeature.TEXT_TOOLS]): HOA / thường / Hoa Đầu Mỗi Từ /
 * Hoa đầu câu / Xoá dấu tiếng Việt, áp lên vùng chọn hoặc đoạn trước con trỏ.
 * Bản Kotlin của iOS Keyboard/TextTools.swift — CÙNG kết quả trên fixture chung
 * iOS/KeyboardTests/Fixtures/text-tools.txt. Duyệt theo code point, phân loại theo
 * General Category; kết quả luôn NFC (đầu vào NFC hay NFD đều nhận).
 */
enum class TextTool(val viLabel: String) {
    UPPER("HOA"),
    LOWER("thường"),
    TITLE("Hoa đầu từ"),
    SENTENCE("Hoa đầu câu"),
    STRIP_DIACRITICS("Xoá dấu");

    /** Nhãn theo ngôn ngữ giao diện ([L10n]); [viLabel] = khoá dịch. */
    val label: String get() = tr(viLabel)

    /** Tên trong fixture chung (khớp rawValue bên Swift). */
    val id: String get() = when (this) {
        UPPER -> "upper"; LOWER -> "lower"; TITLE -> "title"
        SENTENCE -> "sentence"; STRIP_DIACRITICS -> "stripDiacritics"
    }

    companion object {
        fun byId(id: String): TextTool? = entries.firstOrNull { it.id == id }
    }
}

object TextTools {

    fun apply(tool: TextTool, text: String): String {
        val s = nfc(text)
        val out = when (tool) {
            TextTool.UPPER -> s.uppercase(Locale.ROOT)
            TextTool.LOWER -> s.lowercase(Locale.ROOT)
            TextTool.TITLE -> titleCase(s)
            TextTool.SENTENCE -> sentenceCase(s)
            TextTool.STRIP_DIACRITICS -> stripDiacritics(s)
        }
        return nfc(out)
    }

    fun nfc(s: String): String = Normalizer.normalize(s, Normalizer.Form.NFC)

    private fun upper(cp: Int) = String(Character.toChars(cp)).uppercase(Locale.ROOT)
    private fun lower(cp: Int) = String(Character.toChars(cp)).lowercase(Locale.ROOT)

    private fun isLetter(cp: Int) = when (Character.getType(cp).toByte()) {
        Character.UPPERCASE_LETTER, Character.LOWERCASE_LETTER, Character.TITLECASE_LETTER,
        Character.MODIFIER_LETTER, Character.OTHER_LETTER -> true
        else -> false
    }

    private fun isMark(cp: Int) = when (Character.getType(cp).toByte()) {
        Character.NON_SPACING_MARK, Character.COMBINING_SPACING_MARK, Character.ENCLOSING_MARK -> true
        else -> false
    }

    private fun isDigit(cp: Int) = Character.getType(cp).toByte() == Character.DECIMAL_DIGIT_NUMBER

    /** Thuộc tính White_Space của Unicode (liệt kê tay — giống hệt bản Swift). */
    fun isSpace(cp: Int) = cp in 0x09..0x0D || cp == 0x20 || cp == 0x85 || cp == 0xA0 || cp == 0x1680 ||
        cp in 0x2000..0x200A || cp == 0x2028 || cp == 0x2029 || cp == 0x202F || cp == 0x205F || cp == 0x3000

    private fun isApostrophe(cp: Int) = cp == '\''.code || cp == 0x2019

    private fun isSentenceEnd(cp: Int) = cp == '.'.code || cp == '!'.code || cp == '?'.code || cp == 0x2026

    private fun isNewline(cp: Int) = cp == '\n'.code || cp == '\r'.code || cp == 0x2028 || cp == 0x2029

    private fun cps(s: String): IntArray = s.codePoints().toArray()

    /** Hoa Đầu Mỗi Từ: chữ đầu mỗi từ HOA, còn lại thường; nháy kẹp giữa hai chữ thuộc về từ. */
    fun titleCase(s: String): String {
        val cs = cps(s)
        val out = StringBuilder(s.length)
        var inWord = false
        for (i in cs.indices) {
            val c = cs[i]
            when {
                isLetter(c) || isDigit(c) -> { out.append(if (inWord) lower(c) else upper(c)); inWord = true }
                isMark(c) -> out.appendCodePoint(c)
                isApostrophe(c) && inWord && i + 1 < cs.size && isLetter(cs[i + 1]) -> out.appendCodePoint(c)
                else -> { out.appendCodePoint(c); inWord = false }
            }
        }
        return out.toString()
    }

    /** Hoa đầu câu: tất cả thường; chữ đầu văn bản / sau .!?… + khoảng trắng / sau xuống dòng thì HOA. */
    fun sentenceCase(s: String): String {
        val out = StringBuilder(s.length)
        var capNext = true
        var pendingEnd = false
        for (c in cps(s)) {
            when {
                isLetter(c) -> { out.append(if (capNext) upper(c) else lower(c)); capNext = false; pendingEnd = false }
                isDigit(c) -> { out.appendCodePoint(c); capNext = false; pendingEnd = false }
                isNewline(c) -> { out.appendCodePoint(c); capNext = true; pendingEnd = false }
                isSpace(c) -> { out.appendCodePoint(c); if (pendingEnd) capNext = true }
                else -> { if (isSentenceEnd(c)) pendingEnd = true; out.appendCodePoint(c) }
            }
        }
        return out.toString()
    }

    /** Xoá dấu: tách NFD, bỏ dấu tổ hợp U+0300–U+036F, đ→d, Đ→D. */
    fun stripDiacritics(s: String): String {
        val out = StringBuilder(s.length)
        for (c in cps(Normalizer.normalize(s, Normalizer.Form.NFD))) {
            when (c) {
                in 0x0300..0x036F -> {}
                0x0111 -> out.append('d')
                0x0110 -> out.append('D')
                else -> out.appendCodePoint(c)
            }
        }
        return out.toString()
    }

    // --- nguồn chữ ---

    /** [isSelection]: vùng chọn (commitText thay thẳng); false = đoạn trước con trỏ (xoá rồi chèn). */
    data class Source(val text: String, val isSelection: Boolean)

    /**
     * Vùng chọn (nếu có chữ), không thì đoạn trước con trỏ tính từ lần xuống dòng cuối.
     * [truncatedStart]: context bị cắt đầu mà không thấy xuống dòng ⇒ bỏ mẩu từ cắt dở.
     */
    fun source(selected: String?, before: String?, truncatedStart: Boolean = false): Source? {
        if (selected != null && hasLetter(selected)) return Source(selected, true)
        if (before.isNullOrEmpty()) return null
        val cs = cps(before)
        var start = 0
        val nl = cs.indexOfLast { isNewline(it) }
        if (nl >= 0) start = nl + 1
        else if (truncatedStart) {
            val sp = cs.indexOfFirst { isSpace(it) }
            if (sp < 0) return null
            start = sp + 1
        }
        val text = String(cs, start, cs.size - start)
        return if (hasLetter(text)) Source(text, false) else null
    }

    private fun hasLetter(s: String) = cps(s).any { isLetter(it) }

    /** [result] đang nằm ngay trước con trỏ; hoàn tác = xoá nó, chèn lại [original]. */
    data class Undo(val original: String, val result: String)
}

/** Luồng thay chữ trên [TextProxy] (IcProxy: confirmTail/WriteMode lo fail-safe). */
object TextToolRunner {
    sealed class Outcome {
        data class Applied(val undo: TextTools.Undo) : Outcome()
        /** Biến đổi không đổi gì ⇒ không động vào ô. */
        object Unchanged : Outcome()
        /** Không có chữ để áp. */
        object NoSource : Outcome()
        /** Đuôi lệch ⇒ không xoá mù. */
        object FailSafe : Outcome()
    }

    /** [contextCap]: cửa sổ đọc tối đa của proxy — context dài đúng bằng nó coi như bị cắt đầu. */
    fun apply(tool: TextTool, proxy: TextProxy, contextCap: Int = Int.MAX_VALUE): Outcome {
        val before = proxy.contextBeforeInput()
        val src = TextTools.source(proxy.selectedText(), before, before != null && before.length >= contextCap)
            ?: return Outcome.NoSource
        return replace(proxy, src, TextTools.apply(tool, src.text))
    }

    /**
     * Nút "Thêm dấu" (thẻ Công cụ / bảng sửa văn bản, Plus SENTENCE_DIACRITICS): vùng chọn nếu có
     * chữ, không thì đoạn không dấu cuối trước con trỏ ([AddTones.segment] — như chip tự hiện).
     * Chạy [AddTones.restore] trên máy (không mạng); độ dài giữ nguyên, chữ đã có dấu giữ nguyên.
     */
    fun addTones(proxy: TextProxy, personal: AddTones.Personal?, contextCap: Int = Int.MAX_VALUE): Outcome {
        val src = addTonesSource(proxy.selectedText(), proxy.contextBeforeInput(), contextCap) ?: return Outcome.NoSource
        return replace(proxy, src, AddTones.restore(src.text, personal).text)
    }

    /** Nguồn cho "Thêm dấu": vùng chọn có chữ, không thì [AddTones.segment] (context bị cắt đầu ⇒ bỏ mẩu từ dở). */
    fun addTonesSource(selected: String?, before: String?, contextCap: Int = Int.MAX_VALUE): TextTools.Source? {
        if (selected != null && selected.any { it.isLetter() }) return TextTools.Source(selected, true)
        var b = before ?: return null
        if (b.length >= contextCap) {
            val sp = b.indexOfFirst { it.isWhitespace() }
            if (sp < 0) return null
            b = b.substring(sp + 1)
        }
        val seg = AddTones.segment(b)
        return if (seg.any { it.isLetter() }) TextTools.Source(seg, false) else null
    }

    private fun replace(proxy: TextProxy, src: TextTools.Source, result: String): Outcome {
        if (TextTools.nfc(src.text) == TextTools.nfc(result)) return Outcome.Unchanged
        if (src.isSelection) {
            proxy.insertText(result)            // commitText thay vùng chọn
        } else {
            if (!proxy.confirmTail(src.text)) return Outcome.FailSafe
            proxy.deleteCodePoints(Cp.count(src.text))
            proxy.insertText(result)
        }
        return Outcome.Applied(TextTools.Undo(src.text, result))
    }

    /** Hoàn tác một lần; đuôi không còn là chữ vừa thay ⇒ false, không xoá gì. */
    fun undo(u: TextTools.Undo, proxy: TextProxy): Boolean {
        if (!proxy.confirmTail(u.result)) return false
        proxy.deleteCodePoints(Cp.count(u.result))
        proxy.insertText(u.original)
        return true
    }
}
