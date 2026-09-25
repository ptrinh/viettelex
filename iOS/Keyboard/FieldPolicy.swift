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
