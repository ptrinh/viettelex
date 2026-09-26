import UIKit

/// Khi nào gõ LITERAL (bỏ Telex) theo trait của ô nhập.
///
/// Trước đây: mọi ô `autocorrectionType == .no` ⇒ literal. Sai với ô tìm kiếm —
/// thanh địa chỉ Safari/Chrome và Spotlight đều tắt autocorrect nhưng người dùng
/// cần gõ tiếng Việt ở đó. Giờ chỉ literal ở ô có NGỮ NGHĨA không phải chữ Việt:
/// email, URL thuần, username, mã OTP, mật khẩu (giống Android FieldMapping).
enum FieldPolicy {
    static func passthrough(keyboardType: UIKeyboardType,
                            contentType: UITextContentType?) -> Bool {
        switch keyboardType {
        case .emailAddress, .URL: return true
        default: break
        }
        guard let c = contentType else { return false }
        let literal: Set<UITextContentType> = [
            .username, .emailAddress, .URL, .oneTimeCode, .password, .newPassword,
        ]
        return literal.contains(c)
    }
}

extension FieldPolicy {
    /// Auto-shift theo kiểu viết hoa của ô: true = bật shift, false = tắt, nil =
    /// để nguyên. Host KHÔNG khai báo (nil) = mặc định UITextInputTraits là
    /// `.sentences` — trước đây nil bị coi như "không viết hoa" nên ô trống vẫn
    /// hiện phím chữ thường (feedback iPad 26/09/2026).
    static func autoShift(autocap: UITextAutocapitalizationType?, before: String) -> Bool? {
        switch autocap ?? .sentences {
        case .none: return nil
        case .allCharacters: return true
        case .words:
            return before.isEmpty || before.last?.isWhitespace == true
        case .sentences:
            let t = before.trimmingCharacters(in: .whitespaces)
            return before.isEmpty
                || (before.hasSuffix(" ") && (t.hasSuffix(".") || t.hasSuffix("!") || t.hasSuffix("?")))
                || before.hasSuffix("\n")
        @unknown default: return nil
        }
    }
}
