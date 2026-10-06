/// Khi nào tự quay về plane CHỮ như stock iOS: đang ở plane 123/#+= mà đã gõ
/// ít nhất một ký tự, nhấn space → về chữ (feedback 26/09/2026: gõ "," xong
/// space vẫn kẹt ở 123). Ô số (keyboardType số) thì ở lại plane số.
enum PlanePolicy {
    static func returnToLettersOnSpace(inSymbolPlane: Bool, typedInPlane: Bool,
                                       numericField: Bool) -> Bool {
        inSymbolPlane && typedInPlane && !numericField
    }

    /// Chạm ABC (123/#+= → chữ): shift bật hay tắt. `autoShift` = viết hoa đầu câu
    /// đánh giá theo context LÚC CHẠM (nil = công tắc tắt / ô không viết hoa).
    /// Bug tester 1.2.x: gõ "." ở plane 123 + "Tự thêm dấu cách" → ". " rồi về ABC,
    /// code cũ ép shift = off vô điều kiện ⇒ chữ kế không viết hoa. Stock đánh giá lại.
    static func shiftOnReturnToLetters(autoShift: Bool?) -> Bool {
        autoShift ?? false
    }

    /// Plane đích (thuần, KeyboardView ánh xạ plane riêng của nó sang đây).
    enum Target { case letters, symbols, emoji, emojiSearch, templates }

    /// Rời plane chữ: stock iOS TẮT Caps Lock (và shift một-lần) khi sang 123/#+= hay
    /// emoji — Caps Lock → 123 → ABC về chữ thường (Phil 06/10/2026: trước đây vẫn hoa).
    /// Mẫu câu (bảng phủ của VietTelex, không đổi bàn chữ) giữ shift. Về ABC thì
    /// shiftOnReturnToLetters đánh giá lại viết hoa đầu câu. Song sinh Android
    /// PlanePolicy.clearsShiftLeavingLetters.
    static func clearsShiftLeavingLetters(to target: Target) -> Bool {
        switch target {
        case .symbols, .emoji, .emojiSearch: return true
        case .letters, .templates: return false
        }
    }
}
