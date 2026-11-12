import UIKit

/// Bàn phím số lớn kiểu Apple (lưới 3×4: 1…9, [góc], 0, ⌫) cho ô CHỈ nhận số — mã OTP,
/// số tiền, số lượng… Phần THUẦN (chọn kiểu theo trait ô, nhãn, hình học); KeyboardView
/// dựng UIKit (`buildKeypad`). Song sinh ý tưởng Android `Plane.NUMPAD/PHONE` nhưng hình
/// dáng theo stock iOS: chữ cái nhỏ dưới số (2 ABC, 3 DEF…), không phím cách / return.
///
/// Khi nào hiện (iPhone; iPad giữ plane 123 như stock iPad):
/// - `.numberPad`, `.asciiCapableNumberPad` → `.digits` (góc trái dưới: ABC).
/// - `.decimalPad` → `.decimal` (góc: ABC + dấu thập phân THEO VÙNG của máy).
/// - `.phonePad` → `.phone` (góc: ABC * #; giữ 0 ra +). Apple nói ô phone pad / name phone
///   pad luôn dùng bàn phím hệ thống (App Extension Programming Guide › Custom Keyboard) —
///   nhánh này chỉ phòng hờ. `.namePhonePad` (tên HOẶC số) giữ bàn chữ như stock.
/// - `textContentType == .oneTimeCode` ở ô bàn phím mặc định → `.digits` (ô OTP web/app hay
///   không khai keyboardType số).
/// - `.numbersAndPunctuation` → nil: cần dấu câu ⇒ giữ plane 123.
enum NumericKeypad {
    enum Style: Equatable {
        case digits
        case decimal(separator: String)
        case phone
    }

    /// Phím ở ô góc trái dưới (trái → phải, chia đều bề ngang một ô số).
    enum CornerKey: Equatable {
        case globe          // chỉ khi host cần phím đổi bàn phím (máy có nút Home)
        case letters        // "ABC" → bàn chữ đầy đủ
        case text(String)   // dấu thập phân / * / #
        case paste          // 📋 dán số vừa copy (chỉ khi có Toàn quyền — bàn phím không có thì không đọc được clipboard)
    }

    /// THUẦN: trait ô → kiểu bàn số, nil = không dùng bàn số lớn.
    static func style(keyboardType: UIKeyboardType, contentType: UITextContentType?,
                      isPad: Bool, decimalSeparator: String? = Locale.current.decimalSeparator) -> Style? {
        guard !isPad else { return nil }
        switch keyboardType {
        case .numberPad, .asciiCapableNumberPad: return .digits
        case .decimalPad: return .decimal(separator: separator(decimalSeparator))
        case .phonePad: return .phone
        case .default, .asciiCapable:
            return contentType == .oneTimeCode ? .digits : nil
        default: return nil
        }
    }

    /// Dấu thập phân hiển thị: theo định dạng vùng của máy (Locale.current — chính là locale
    /// app host dùng để parse số), KHÔNG theo ngôn ngữ gõ VI/EN. Chỉ nhận "," / "."; lạ ⇒ ".".
    static func separator(_ s: String?) -> String {
        s == "," ? "," : "."
    }

    /// Lưới số 3 hàng trên.
    static let gridRows: [[String]] = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"]]

    /// Chữ cái nhỏ dưới số như bàn số stock.
    static func letters(under digit: String, style: Style) -> String {
        switch digit {
        case "2": return "ABC"
        case "3": return "DEF"
        case "4": return "GHI"
        case "5": return "JKL"
        case "6": return "MNO"
        case "7": return "PQRS"
        case "8": return "TUV"
        case "9": return "WXYZ"
        case "0": return style == .phone ? "+" : ""
        default: return ""
        }
    }

    /// Ô góc trái dưới. [paste]: thêm 📋 cuối ô (báo lỗi 13/11/2026: bàn số không có cách
    /// dán số điện thoại vừa copy).
    static func corner(style: Style, needsGlobe: Bool, paste: Bool = false) -> [CornerKey] {
        var out: [CornerKey] = needsGlobe ? [.globe] : []
        out.append(.letters)
        switch style {
        case .digits: break
        case .decimal(let sep): out.append(.text(sep))
        case .phone: out += [.text("*"), .text("#")]
        }
        if paste { out.append(.paste) }
        return out
    }

    /// 📋 Dán: làm sạch chữ trong clipboard theo kiểu bàn số TRƯỚC khi chèn (ô số hay từ chối
    /// cả chuỗi lẫn ký tự lạ). Song sinh Android `NumericPaste.clean`.
    /// - `.phone`: chữ số + `*` `#`; `+` chỉ khi đứng đầu ("+84 903-389-710" → "+84903389710").
    /// - `.digits`: chỉ chữ số ("0903 389 710" → "0903389710", "1.000.000" → "1000000").
    /// - `.decimal`: chữ số + "." ",".
    /// Chữ số Unicode khác (toàn khổ, Ả Rập…) đổi về 0-9. Không có chữ số nào ⇒ "" (không chèn).
    static func cleanPaste(_ text: String?, style: Style) -> String {
        guard let text, !text.isEmpty else { return "" }
        var out = ""
        var hasDigit = false
        for u in text.unicodeScalars {
            if u.properties.numericType == .decimal, let v = u.properties.numericValue, v >= 0, v <= 9 {
                out.append(String(Int(v))); hasDigit = true
                continue
            }
            switch style {
            case .phone:
                if u == "*" || u == "#" { out.unicodeScalars.append(u) }
                else if (u == "+" || u == "\u{FF0B}") && out.isEmpty { out.append("+") }
            case .decimal:
                if u == "." || u == "," { out.unicodeScalars.append(u) }
            case .digits: break
            }
        }
        return hasDigit ? out : ""
    }

    /// Giữ phím → ký tự thay thế. "0" ở bàn điện thoại ra "+" (như stock); dấu thập phân ra
    /// dấu còn lại (app parse "." dù máy vùng VN).
    static func holdChoices(for key: String, style: Style) -> [String] {
        switch (key, style) {
        case ("0", .phone): return ["+"]
        case (",", .decimal): return ["."]
        case (".", .decimal): return [","]
        default: return []
        }
    }

    /// Bề ngang tối đa của lưới (iPhone ngang / máy gập mở): ô số không phình quá ~180pt.
    static let maxWidth: CGFloat = 560

    /// Lề trái/phải mỗi hàng: lề thường, hoặc căn giữa khi vùng phím rộng hơn maxWidth.
    static func sideMargin(keysWidth: CGFloat, margin: CGFloat) -> CGFloat {
        max(margin, (keysWidth - maxWidth) / 2)
    }

    /// Bề ngang một ô số (3 ô + 2 khe vừa vùng phím trừ lề).
    static func cellWidth(keysWidth: CGFloat, margin: CGFloat, gap: CGFloat) -> CGFloat {
        let m = sideMargin(keysWidth: keysWidth, margin: margin)
        return max((keysWidth - 2 * m - 2 * gap) / 3, 0)
    }

    /// Cỡ chữ: số / chữ cái phụ. Ngang (hàng thấp ~32pt) bỏ dòng chữ cái (letters 0).
    static func typography(landscape: Bool) -> (digit: CGFloat, letters: CGFloat) {
        landscape ? (22, 0) : (26, 10)
    }

}

extension FieldTraits {
    /// Kiểu bàn số lớn cho ô này (nil = bàn thường / plane 123).
    func keypadStyle(isPad: Bool, decimalSeparator: String? = Locale.current.decimalSeparator)
        -> NumericKeypad.Style? {
        NumericKeypad.style(keyboardType: keyboardType, contentType: contentType,
                            isPad: isPad, decimalSeparator: decimalSeparator)
    }
}
