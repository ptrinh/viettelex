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

/// Ảnh chụp trait của ô nhập — phần THUẦN của refreshFieldTraits(). Host đổi ô trong
/// cùng app (ô tìm kiếm ↔ ô bình luận…) KHÔNG gọi lại viewWillAppear, nên controller
/// đọc lại trait ở textDidChange/selectionDidChange và chỉ cấu hình lại bàn phím khi
/// ảnh chụp KHÁC lần trước (configureInputKind còn nhảy plane — gọi thừa là mất plane
/// số/ký hiệu đang mở). KHÔNG dùng documentIdentifier: nil trước khi phiên nhập thiết
/// lập → bẫy crash.
struct FieldTraits: Equatable {
    var keyboardType: UIKeyboardType = .default
    var returnKeyType: UIReturnKeyType = .default
    var appearance: UIKeyboardAppearance = .default
    var autocorrection: UITextAutocorrectionType = .default
    var contentType: UITextContentType?
    var secure = false

    /// Gõ literal (bỏ Telex)?
    var passthrough: Bool {
        FieldPolicy.passthrough(keyboardType: keyboardType, contentType: contentType)
    }

    /// Ô cho phép thanh gợi ý (stock tắt ở ô mật khẩu / autocorrection = .no).
    var allowsSuggestions: Bool { autocorrection != .no && !secure }

    /// Loại layout (web input type=number/email/url ánh xạ sang keyboardType).
    var inputKind: KeyboardView.InputKind {
        switch keyboardType {
        case .numberPad, .numbersAndPunctuation, .decimalPad,
             .phonePad, .asciiCapableNumberPad:
            return .number
        case .emailAddress: return .email
        case .URL: return .url
        default: return .normal
        }
    }

    /// Dòng header log chẩn đoán: chỉ loại trait, không có nội dung người dùng.
    var logDescription: String {
        "keyboardType=\(keyboardType.rawValue) returnKeyType=\(returnKeyType.rawValue)"
            + " autocorrectionType=\(autocorrection.rawValue)"
            + " textContentType=\(contentType?.rawValue ?? "nil") secure=\(secure ? 1 : 0)"
    }

    /// Cần cấu hình lại bàn phím? Lần đầu (old nil) luôn cần; sau đó chỉ khi trait đổi.
    static func needsReconfigure(old: FieldTraits?, new: FieldTraits) -> Bool {
        old != new
    }
}
