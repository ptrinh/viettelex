// Xuống dòng KHÔNG gửi (giữ lâu Return, hoặc bật ⇧ rồi chạm Return) — tester 30/10/2026,
// ô chat web ("Muse AI" trong trình duyệt): Return luôn gửi tin.
//
// Bàn phím bên thứ ba không gửi được Shift+Enter. `insertText("\n")` một mình bị WebKit
// biến thành phím Enter ⇒ trang bắt Enter = Gửi. Manh mối của tester: gõ tắt bung ra
// "chữ + \n + chữ" thì XUỐNG DÒNG mà không gửi, còn nội dung chỉ "\n" / khoảng trắng thì
// vẫn gửi ⇒ "\n" NẰM TRONG một chuỗi dài hơn được chèn như văn bản, không phải phím Enter.
// (GIẢ ĐỊNH theo manh mối đó — chưa kiểm chứng trên Safari thật.)
//
// Mẹo: xoá vài ký tự ngay trước con trỏ rồi chèn lại chúng + "\n" trong MỘT lệnh
// insertText ("…o" → ⌫ → "o\n"). Ô native (UITextView) kết quả y hệt một "\n" thường.
// Phần mang theo = ký tự không phải khoảng trắng cuối cùng + mọi khoảng trắng sau nó
// (khoảng trắng một mình có thể vẫn bị coi là Enter). Chỉ mang khi CHẮC ⌫ xoá đúng
// từng ký tự: mỗi Character đúng MỘT scalar trong BMP, không phải dấu kết hợp/ZWJ/
// bộ chọn biến thể. Emoji (kể cả 😀 ngoài BMP), cờ, chuỗi ZWJ, chữ tổ hợp NFD, "\r\n"
// ⇒ không mang, chèn "\n" trơn (có thể vẫn gửi — chấp nhận, an toàn hơn xoá lệch chữ).
// Có vùng chọn ⇒ ⌫ sẽ xoá vùng chọn ⇒ "\n" trơn. Không đọc được context / context lệch
// với chữ vừa chèn ⇒ "\n" trơn. Pure — LineBreakTests.
import Foundation

enum LineBreak {
    /// Mang tối đa bấy nhiêu ký tự (ký tự chữ + khoảng trắng sau nó).
    static let maxCarry = 8

    enum Plan: Equatable {
        /// `insertText("\n")` thường.
        case plain
        /// `deleteBackward()` × `carry.count` rồi `insertText(carry + "\n")` một lần.
        case carry(String)
    }

    /// - Parameters:
    ///   - context: chữ trước con trỏ (documentContextBeforeInput); nil = host không cho biết.
    ///   - hasSelection: đang có vùng chọn.
    ///   - justInserted: chuỗi vừa chèn ngay trước trong cùng phím (nil = không có / không biết) —
    ///     context không kết thúc bằng nó ⇒ context cũ (host trễ) ⇒ không mạo hiểm xoá.
    static func plan(context: String?, hasSelection: Bool, justInserted: String? = nil) -> Plan {
        guard !hasSelection, let ctx = context, !ctx.isEmpty else { return .plain }
        if let j = justInserted, !j.isEmpty, !ctx.hasSuffix(j) { return .plain }
        var carry: [Character] = []
        for ch in ctx.reversed() {
            guard carry.count < maxCarry, isSafe(ch) else { return .plain }
            carry.append(ch)
            if !isBlank(ch) { return .carry(String(carry.reversed())) }
        }
        return .plain                        // toàn khoảng trắng: không có chữ để "kèm"
    }

    /// Một Character mà một lần ⌫ chắc chắn xoá trọn và chèn lại y hệt.
    static func isSafe(_ ch: Character) -> Bool {
        let scalars = ch.unicodeScalars
        guard scalars.count == 1, let s = scalars.first else { return false }
        guard s.value <= 0xFFFF else { return false }               // ngoài BMP: cặp surrogate
        if s.value == 0x200D || s.value == 0x200C { return false }  // ZWJ / ZWNJ
        if (0xFE00...0xFE0F).contains(s.value) { return false }     // bộ chọn biến thể
        if isBlank(ch) { return true }
        switch s.properties.generalCategory {
        case .nonspacingMark, .spacingMark, .enclosingMark, .control,
             .surrogate, .privateUse, .unassigned, .format,
             .lineSeparator, .paragraphSeparator:
            return false
        default:
            return true
        }
    }

    static func isBlank(_ ch: Character) -> Bool { ch == " " || ch == "\t" || ch == "\n" || ch == "\u{00A0}" }

    /// Thực thi trên `proxy` (đã chốt từ đang gõ). Trả plan đã dùng (log/test).
    @discardableResult
    static func insert(proxy: TextProxyLike, justInserted: String? = nil) -> Plan {
        let p = plan(context: proxy.hasSelection ? nil : proxy.contextBeforeInput,
                     hasSelection: proxy.hasSelection, justInserted: justInserted)
        switch p {
        case .plain:
            proxy.insertText("\n")
        case .carry(let s):
            for _ in 0..<s.count { proxy.deleteBackward() }
            proxy.insertText(s + "\n")
        }
        return p
    }
}
