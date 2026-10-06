package com.viettelex.android.ime

/**
 * Luật đổi plane (THUẦN — pinned by PlanePolicyTest). Bản Android của iOS PlanePolicy.
 */
object PlanePolicy {
    /**
     * Về plane chữ (ABC từ 123/#+=, emoji, mẫu câu, bảng sửa): IME đánh giá lại viết hoa
     * đầu câu theo context LÚC ĐÓ thay vì để shift tắt (KeyboardView.setPlane hạ shift
     * một-lần). Bug tester iOS 1.2.x, Android cùng bệnh: gõ "." ở plane 123 + "Tự thêm dấu
     * cách" ⇒ ". " rồi về ABC, chữ kế không viết hoa. Stock đánh giá lại.
     * Plane tìm emoji không tính (phím vào ô tìm, không tới ô nhập).
     */
    fun reevaluatesShift(to: Plane): Boolean = to == Plane.LETTERS

    /**
     * Rời plane chữ: tắt Caps Lock (và shift một-lần) khi sang ?123 / =\< / emoji / tìm emoji
     * — Caps Lock → ?123 → ABC về chữ thường như iOS stock (Phil 06/10/2026; song sinh iOS
     * PlanePolicy.clearsShiftLeavingLetters). Mẫu câu / bảng sửa (phủ lên, không đổi bàn
     * chữ) giữ shift. Về ABC thì [reevaluatesShift] áp lại viết hoa đầu câu.
     */
    fun clearsShiftLeavingLetters(to: Plane): Boolean =
        to == Plane.NUMBERS || to == Plane.SYMBOLS || to == Plane.EMOJI || to == Plane.EMOJI_SEARCH
}
