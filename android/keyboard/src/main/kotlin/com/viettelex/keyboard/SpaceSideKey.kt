package com.viettelex.keyboard

/**
 * "Phím cạnh dấu cách" (setting [Keys.SPACE_SIDE_KEY]; cùng chuỗi với iOS App Group
 * "spaceSideKey"): phím hẹp cạnh space ở hàng đáy bàn CHỮ điện thoại, ô thường.
 * Tablet (Android, 16/10/2026): COMMA ≡ PERIOD ≡ BOTH = "," trái + "." phải space (space giữa hàng);
 * OFF = bỏ cả hai, space rộng hơn, vẫn giữa — KeyLayout.tabletPunct.
 *  - [COMMA] (mặc định, bố cục cũ): "," bên phải space — giữ ra "." và dấu câu khác.
 *  - [PERIOD]: "." cùng chỗ, cùng cỡ — giữ ra "," (chọn sẵn) và dấu câu khác.
 *  - [BOTH] ("Cả hai", 16/10/2026): "," bên TRÁI + "." bên phải space, mỗi phím hẹp như trên,
 *    space co lại. "," giữ popup dấu câu; "." không popup (như "." tablet).
 *  - [OFF]: không phím; space rộng thêm. Space đôi vẫn ra ". ".
 * Ô URL / email, plane số / ký hiệu không đổi; iOS iPad không theo tuỳ chọn. Đọc lúc dựng layout — 0 chi phí mỗi phím.
 */
enum class SpaceSideKey(val id: String) {
    COMMA("comma"), PERIOD("period"), BOTH("both"), OFF("off");

    /** Phím hẹp bên PHẢI space (null = không có). */
    val right: String? get() = when (this) { COMMA -> ","; PERIOD, BOTH -> "."; OFF -> null }

    /** Phím hẹp bên TRÁI space (chỉ [BOTH]). */
    val left: String? get() = if (this == BOTH) "," else null

    /** Dòng cài đặt "Cỡ phím chấm và phẩy" chỉ hiện khi có phím cạnh dấu cách (OFF ⇒ ẩn; giá trị giữ nguyên). */
    val showsLargeKeysSetting: Boolean get() = this != OFF

    companion object {
        val DEFAULT = COMMA
        val IDS: Set<String> = entries.map { it.id }.toSet()
        /** Giá trị lạ / thiếu ⇒ [DEFAULT]. */
        fun of(raw: Any?): SpaceSideKey = entries.firstOrNull { it.id == raw } ?: DEFAULT
    }
}

/**
 * "Nút emoji" (setting [Keys.EMOJI_KEY_PLACEMENT]; cùng chuỗi iOS App Group "emojiKeyPlacement"):
 *  - [BOTTOM] (mặc định): phím 😊 ở hàng đáy bàn chữ như cũ.
 *  - [TOP] ("Thanh trên"): bỏ 😊 khỏi hàng đáy bàn chữ (space ăn chỗ), nút 😊 lên thanh gợi ý
 *    (cạnh ⌄, hiện cả khi có gợi ý lẫn khi thu gọn). Thanh không hiện ở ô này (tắt gợi ý / ô
 *    không có thanh) ⇒ 😊 vẫn ở hàng đáy — emoji không bao giờ mất lối vào.
 * Đọc lúc dựng layout — 0 chi phí mỗi phím.
 */
enum class EmojiKeyPlacement(val id: String) {
    BOTTOM("bottom"), TOP("top");

    companion object {
        val DEFAULT = BOTTOM
        val IDS: Set<String> = entries.map { it.id }.toSet()
        fun of(raw: Any?): EmojiKeyPlacement = entries.firstOrNull { it.id == raw } ?: DEFAULT

        /** 😊 lên thanh trên ⇔ chọn [TOP] VÀ thanh gợi ý đang hiện (có chỗ vẽ nút). */
        fun inStrip(p: EmojiKeyPlacement, stripShown: Boolean): Boolean = p == TOP && stripShown
    }
}

/**
 * "Cỡ chữ trên phím" (Android, setting [Keys.KEY_LABEL_SIZE]): [MEDIUM] mặc định (Gboard: chữ
 * 22 sp), [LARGE] phóng chữ / ký hiệu / icon trên phím (chữ ×[letterScale], phím chức năng
 * nhỏ hơn) — KeyboardView còn kẹp theo bề ngang phím để không tràn phím hẹp.
 */
enum class KeyLabelSize(val id: String) {
    MEDIUM("medium"), LARGE("large");

    /** Hệ số chữ cái / số / dấu câu trên phím. */
    val letterScale: Float get() = if (this == LARGE) 1.22f else 1f
    /** Nhãn phím chức năng (?123, ABC), icon (⇧ ⌫ 😊 ↵), số bàn số. */
    val controlScale: Float get() = if (this == LARGE) 1.12f else 1f
    /** Chữ phụ nhỏ ở góc phím (ký tự giữ lâu). */
    val hintScale: Float get() = if (this == LARGE) 1.1f else 1f

    companion object {
        val DEFAULT = MEDIUM
        val IDS: Set<String> = entries.map { it.id }.toSet()
        fun of(raw: Any?): KeyLabelSize = entries.firstOrNull { it.id == raw } ?: DEFAULT
    }
}
