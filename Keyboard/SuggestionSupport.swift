// SuggestionSupport — logic THUẦN (không UIKit, không proxy) rút ra khỏi
// KeyboardViewController để unit-test được: đệm thanh gợi ý cho đủ 3, và quyết
// định double-space → ". ". Controller chỉ còn nối dây (đọc proxy/model).
import Foundation

enum SuggestionFill {
    /// Đệm `base` cho đủ `need` phần tử, lấy thêm từ `candidates` theo thứ tự,
    /// LOẠI TRÙNG (so lowercased) và loại `excluding` (từ đang gõ). Trả tối đa
    /// `need` phần tử. Giữ nguyên thứ tự: base trước, rồi candidate mới.
    static func pad(_ base: [String], with candidates: [String],
                    need: Int, excluding: String = "") -> [String] {
        if base.count >= need { return Array(base.prefix(need)) }
        var out = base
        var seen = Set(base.map { $0.lowercased() })
        if !excluding.isEmpty { seen.insert(excluding.lowercased()) }
        for c in candidates {
            if out.count >= need { break }
            if seen.insert(c.lowercased()).inserted { out.append(c) }
        }
        return out
    }
}

enum TypingHeuristics {
    /// Double-space có nên biến space vừa gõ thành ". " không (hành vi Apple).
    /// Điều kiện: phím trước là space, cuối ô đang là đúng " ", và ký tự ngay
    /// trước space đó là chữ/số (không phải khoảng trắng hay dấu câu) — tránh
    /// biến "␣␣" đầu ô / sau dấu câu thành ". .".
    static func doubleSpaceMakesPeriod(context: String, lastWasSpace: Bool) -> Bool {
        guard lastWasSpace, context.hasSuffix(" "),
              let prev = context.dropLast().last else { return false }
        return !prev.isWhitespace
            && prev != "." && prev != "!" && prev != "?" && prev != ","
    }
}
