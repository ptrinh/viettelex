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

    /**
     * Shift sau khi phím CHAR (hàng số 1…0 trên plane chữ — thường, tách đôi, một tay, tablet)
     * vừa CHỐT ký tự: như phím chữ — nhả Shift một-lần (đầu câu hay ⇧ tay), Caps Lock giữ.
     * Issue #143 (song sinh iOS): viết hoa đầu câu + hàng số, gõ "1" đầu câu ⇒ chữ kế vẫn
     * hoa, vì phím số gửi Key.Text mà session không đánh giá lại viết hoa sau Key.Text.
     * Plane 123 / ký hiệu không đổi (rời plane chữ đã tắt shift; về ABC thì đánh giá lại).
     * [armedOn] = plane lúc phím được arm (chốt có thể trễ tới lúc nhấc / ngón kế chạm).
     */
    fun shiftAfterCharKey(armedOn: Plane, shift: KeyboardView.Shift): KeyboardView.Shift =
        if (armedOn == Plane.LETTERS && shift == KeyboardView.Shift.ON) KeyboardView.Shift.OFF else shift

    /**
     * Dấu KẾT VẾ: chạm ở plane ?123 / =\< ⇒ về plane chữ NGAY, không cần dấu cách (Phil
     * 06/11/2026, không công tắc). Gồm dạng in ấn trong hàng biến thể (… ” ’ »). Ngoặc / nháy
     * MỞ (( “ ‘ «), @ / # $ % & * - _ + = [ { < > \ |, số, tiền tệ, toán: giữ plane.
     */
    val CLAUSE_ENDERS: Set<String> = setOf(".", ",", "?", "!", ")", "\"", "'", ":", ";",
        "…", "”", "’", "»")
    /** Dấu nằm GIỮA số: ngay sau chữ số thì ở lại plane số ("2.5", "1,000", "10:30"). */
    val DIGIT_SEPARATORS: Set<String> = setOf(".", ",", ":")

    /**
     * Vừa chèn [inserted] trên plane [on] (chạm, giữ chọn biến thể — mọi Key.Text của plane).
     * [before] = ký tự ngay trước con trỏ TRƯỚC khi chèn (chỉ cần khi [inserted] thuộc
     * [DIGIT_SEPARATORS]). Ô số (bàn số riêng — [InputKind.padPlane]) ở lại plane số.
     * Song sinh iOS PlanePolicy.returnToLettersAfterSymbol.
     */
    fun returnToLettersAfterSymbol(inserted: String, on: Plane, numericField: Boolean, before: Char?): Boolean {
        if (on != Plane.NUMBERS && on != Plane.SYMBOLS) return false
        if (numericField || inserted !in CLAUSE_ENDERS) return false
        return !(inserted in DIGIT_SEPARATORS && before != null && before in '0'..'9')
    }
}
