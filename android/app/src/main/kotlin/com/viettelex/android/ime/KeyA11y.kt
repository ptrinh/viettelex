package com.viettelex.android.ime

import com.viettelex.keyboard.tr

/** Nhãn TalkBack cho một phím (hàm thuần để test). Phím chữ đọc đúng hoa/thường đang hiện. */
object KeyA11y {
    fun describe(kind: Int, label: String, upper: String, insert: String, shifted: Boolean, returnLabel: String): String =
        when (kind) {
            KeyKind.LETTER -> if (shifted) upper else label
            KeyKind.SHIFT -> tr("Shift")
            KeyKind.BACKSPACE -> tr("Xoá")
            KeyKind.SPACE -> tr("Dấu cách")
            KeyKind.RETURN -> returnLabel.takeIf { it.isNotBlank() && it != "return" } ?: tr("Xuống dòng")
            KeyKind.EMOJI -> tr("Emoji")
            KeyKind.GLOBE -> tr("Đổi bàn phím")
            KeyKind.CLEAR -> tr("Xoá hết")
            KeyKind.DISMISS -> tr("Ẩn bàn phím")
            KeyKind.PASTE -> tr("Dán")
            KeyKind.PLANE, KeyKind.MORE -> when (insert) {
                "ABC" -> tr("Chữ cái")
                "123" -> tr("Số")
                "#+=" -> tr("Ký hiệu")
                else -> label.ifBlank { insert }
            }
            else -> label.ifBlank { insert }
        }
}
