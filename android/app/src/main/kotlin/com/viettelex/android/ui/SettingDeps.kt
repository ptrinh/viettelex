package com.viettelex.android.ui

// Công tắc phụ thuộc — docs/SETTINGS-CLEANUP-SPEC.md §0.4 + bảng §6 (06/11/2026). Mục con nằm ngay
// dưới mục cha (cùng trang/nhóm) ⇒ ẨN khi cha làm nó vô tác dụng; mục cha ở trang khác ⇒ mờ + lý do.
// Chỉ là hiển thị: không đổi key, không đổi giá trị đã lưu, engine không đổi. Hàm thuần để test.

internal object SettingDeps {
    /** Lý do làm mờ "Gợi ý sửa lỗi chạm trượt" (nhóm Chạm trượt, khác nhóm Thanh gợi ý). */
    const val NEEDS_SUGGESTIONS = "Cần bật Thanh gợi ý" // l10n-key

    /** Dòng của nhóm "Thanh gợi ý" (trang Sửa lỗi & gợi ý), theo thứ tự hiển thị. */
    enum class SuggestionRow { Toggle, Count, DismissButton, InNoSuggestFields, NumberChips, MathResults, AddTones, FilterSensitive }

    /**
     * Thanh gợi ý tắt ⇒ ẩn các mục chỉ hiện trên thanh (số từ, nút ẩn bàn phím ⌄, gợi ý cả khi app tắt
     * gợi ý, số tiền, phép tính, Thêm dấu). "Lọc từ nhạy cảm" luôn hiện (§6: không phụ thuộc).
     */
    fun suggestionRows(showSuggestions: Boolean): List<SuggestionRow> =
        if (showSuggestions) SuggestionRow.entries
        else listOf(SuggestionRow.Toggle, SuggestionRow.FilterSensitive)

    /** "Gợi ý sửa lỗi chạm trượt" chỉ hiện trên thanh gợi ý ⇒ thanh tắt: mờ + lý do. */
    fun autoFixAdjacentReason(showSuggestions: Boolean): String? = if (showSuggestions) null else NEEDS_SUGGESTIONS

    /**
     * "Tự sửa từ gõ sai" và "Chọn phím thông minh": engine tắt lặng ở VNI (KeyboardSession: autoCorrectOn
     * cần !vniMode; TelexKeyPrior.forTyping trả null khi VNI). Bộ chọn Telex/VNI ở tab khác ⇒ mờ + lý do.
     */
    fun telexOnlyReason(vniMode: Boolean): String? = if (vniMode) MixedTypingUI.TELEX_ONLY else null

    /** Dòng của trang Gõ vuốt, theo thứ tự hiển thị. */
    enum class SwipeRow { Toggle, SwipeEnglish, NeuralModel, Trail, TrailSound, Practice }

    /** Gõ vuốt tắt ⇒ chỉ còn công tắc (Vuốt từ tiếng Anh, neural + ghi công, hiệu ứng + âm thanh nét vuốt, luyện vuốt ẩn). */
    fun swipeRows(swipeOn: Boolean): List<SwipeRow> = if (swipeOn) SwipeRow.entries else listOf(SwipeRow.Toggle)
}
