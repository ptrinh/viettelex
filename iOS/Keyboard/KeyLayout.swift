// KeyLayout — bảng tỉ lệ phím THUẦN (không UIKit) để unit-test được. KeyboardView
// dựng constraint từ đây. Quy tắc (bug 26/09/2026: nút 🌐 hàng đáy iPad nhảy
// size; hàng 1 iPad thành 12 phím bằng nhau sau khi từ mẫu câu về): mỗi hàng chỉ
// được ĐÚNG MỘT phím co giãn (units = nil), hoặc không phím nào nếu hàng đó là
// hàng neo quyết định bề rộng phím chữ. Hai phím "tự do" = UIKit chia tuỳ lúc.
import CoreGraphics

enum KeyLayout {
    struct Key { let id: String; let units: CGFloat? }   // nil = co giãn

    /// iPad plane chữ — units = bội số bề rộng phím chữ q. Hàng 1 KHÔNG có phím
    /// co giãn: nó quyết định q. Đo ảnh iPad Pro 11" stock.
    static let padRows: [[Key]] = [
        [Key(id: "tab", units: 1.31)] + letters("qwertyuiop") + [Key(id: "back", units: 1.31)],
        [Key(id: "caps", units: 1.67)] + letters("asdfghjkl") + [Key(id: "return", units: nil)],
        [Key(id: "shiftL", units: 2.2)] + letters("zxcvbnm")
            + [Key(id: "!,", units: 1), Key(id: "?.", units: 1), Key(id: "shiftR", units: nil)],
    ]
    static let padAnchorRow = 0

    /// Hàng đáy — units = PHẦN của bề rộng hàng (multiplier theo stack width).
    static let padBottom: [Key] = [
        Key(id: "globe", units: 0.068), Key(id: "plane", units: 0.068),
        Key(id: "emoji", units: 0.068), Key(id: "space", units: nil),
        Key(id: "comma", units: 0.068), Key(id: "plane2", units: 0.102),
        Key(id: "dismiss", units: 0.102),
    ]
    static let phoneBottom: [Key] = [
        Key(id: "plane", units: 0.12), Key(id: "globe", units: 0.10),
        Key(id: "emoji", units: 0.12), Key(id: "space", units: nil),
        Key(id: "comma", units: 0.075), Key(id: "return", units: 0.14),
    ]

    static func units(_ id: String, in row: [Key]) -> CGFloat? {
        row.first { $0.id == id }?.units
    }

    private static func letters(_ s: String) -> [Key] {
        s.map { Key(id: String($0), units: 1) }
    }

    // MARK: kiểm tra (test dùng)

    static func flexCount(_ row: [Key]) -> Int { row.filter { $0.units == nil }.count }

    /// Bề rộng phím chữ q do hàng neo quyết định.
    static func padLetterWidth(rowWidth w: CGFloat, gap: CGFloat, margin: CGFloat) -> CGFloat {
        let row = padRows[padAnchorRow]
        let units = row.compactMap(\.units).reduce(0, +)
        return (w - 2 * margin - gap * CGFloat(row.count - 1)) / units
    }

    /// Bề rộng phím co giãn của hàng `i` (≤ 0 = tràn hàng).
    static func padFlexWidth(row i: Int, rowWidth w: CGFloat, gap: CGFloat, margin: CGFloat) -> CGFloat {
        let q = padLetterWidth(rowWidth: w, gap: gap, margin: margin)
        let row = padRows[i]
        let fixed = row.compactMap(\.units).reduce(0, +) * q
        return w - 2 * margin - gap * CGFloat(row.count - 1) - fixed
    }
}
