package com.viettelex.keyboard

/**
 * Phím 📋 Dán trên bàn số (Plane.PHONE / NUMPAD): làm sạch chữ trong clipboard theo loại ô
 * TRƯỚC khi chèn — ô số thường từ chối cả chuỗi nếu lẫn ký tự lạ (DigitsKeyListener), nên
 * "0903 389 710" phải thành "0903389710". THUẦN (test được, iOS có bản song sinh
 * `NumericKeypad.cleanPaste`).
 *
 *  - [Field.PHONE]   : chữ số + `*` `#`; `+` chỉ khi đứng đầu ("+84 903-389-710" → "+84903389710").
 *  - [Field.NUMBER]  : chỉ chữ số ("1.000.000" → "1000000"); [signed] ⇒ giữ "-" đứng đầu.
 *  - [Field.DECIMAL] : chữ số + "." "," (ô tự hiểu dấu thập phân); [signed] ⇒ giữ "-" đứng đầu.
 *  - [Field.DATETIME]: chỉ cắt khoảng trắng hai đầu (ngày giờ cần "/" ":" " ").
 * Chữ số Unicode khác (toàn khổ ０-９, Ả Rập…) đổi về 0-9. Không còn gì ⇒ "" (không chèn).
 */
object NumericPaste {
    enum class Field { PHONE, NUMBER, DECIMAL, DATETIME }

    fun clean(text: String?, field: Field, signed: Boolean = false): String {
        if (text.isNullOrEmpty()) return ""
        if (field == Field.DATETIME) return text.trim()
        val out = StringBuilder(text.length)
        var i = 0
        while (i < text.length) {
            val cp = text.codePointAt(i)
            i += Character.charCount(cp)
            val digit = if (Character.isDigit(cp)) Character.getNumericValue(cp) else -1
            when {
                digit in 0..9 -> out.append('0' + digit)
                field == Field.PHONE && (cp == '*'.code || cp == '#'.code) -> out.appendCodePoint(cp)
                field == Field.PHONE && (cp == '+'.code || cp == '＋'.code) -> if (out.isEmpty()) out.append('+')
                field == Field.DECIMAL && (cp == '.'.code || cp == ','.code) -> out.appendCodePoint(cp)
                signed && field != Field.PHONE && (cp == '-'.code || cp == '−'.code) -> if (out.isEmpty()) out.append('-')
            }
        }
        // Chỉ còn dấu (không có số nào) ⇒ không chèn rác.
        return if (out.any { it in '0'..'9' }) out.toString() else ""
    }
}
