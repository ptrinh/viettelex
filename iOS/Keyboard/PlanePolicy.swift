/// Khi nào tự quay về plane CHỮ như stock iOS: đang ở plane 123/#+= mà đã gõ
/// ít nhất một ký tự, nhấn space → về chữ (feedback 26/09/2026: gõ "," xong
/// space vẫn kẹt ở 123). Ô số (keyboardType số) thì ở lại plane số.
enum PlanePolicy {
    static func returnToLettersOnSpace(inSymbolPlane: Bool, typedInPlane: Bool,
                                       numericField: Bool) -> Bool {
        inSymbolPlane && typedInPlane && !numericField
    }
}
