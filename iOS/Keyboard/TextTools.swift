// TextTools — CÔNG CỤ VĂN BẢN (gói Plus, PlusGate .textTools): HOA / thường /
// Hoa Đầu Mỗi Từ / Hoa đầu câu / Xoá dấu tiếng Việt, áp lên vùng chọn hoặc đoạn
// trước con trỏ. Logic THUẦN (không UIKit) — bản Kotlin android/keyboard/…/TextTools.kt
// phải cho CÙNG kết quả trên fixture chung KeyboardTests/Fixtures/text-tools.txt.
//
// Để hai nền tảng khớp nhau, mọi phép duyệt đi theo Unicode scalar (≡ code point
// bên Kotlin) và phân loại theo General Category — không dựa vào Character/grapheme
// của Swift. Kết quả luôn ở dạng dựng sẵn NFC (đầu vào NFC hay tổ hợp NFD đều nhận).
import Foundation

enum TextTool: String, CaseIterable {
    case upper, lower, title, sentence, stripDiacritics

    /// Nhãn chip trong danh sách công cụ.
    var label: String {
        switch self {
        case .upper: return "HOA"
        case .lower: return L("thường")
        case .title: return L("Hoa đầu từ")
        case .sentence: return L("Hoa đầu câu")
        case .stripDiacritics: return L("Xoá dấu")
        }
    }
}

enum TextTools {

    // MARK: biến đổi

    static func apply(_ tool: TextTool, _ text: String) -> String {
        let s = text.precomposedStringWithCanonicalMapping
        let out: String
        switch tool {
        case .upper: out = s.uppercased()
        case .lower: out = s.lowercased()
        case .title: out = titleCase(s)
        case .sentence: out = sentenceCase(s)
        case .stripDiacritics: out = stripDiacritics(s)
        }
        return out.precomposedStringWithCanonicalMapping
    }

    private static func upper(_ c: Unicode.Scalar) -> String { String(c).uppercased() }
    private static func lower(_ c: Unicode.Scalar) -> String { String(c).lowercased() }

    private static func isLetter(_ c: Unicode.Scalar) -> Bool {
        switch c.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter:
            return true
        default: return false
        }
    }

    private static func isMark(_ c: Unicode.Scalar) -> Bool {
        switch c.properties.generalCategory {
        case .nonspacingMark, .spacingMark, .enclosingMark: return true
        default: return false
        }
    }

    private static func isDigit(_ c: Unicode.Scalar) -> Bool {
        c.properties.generalCategory == .decimalNumber
    }

    private static func isWordChar(_ c: Unicode.Scalar) -> Bool {
        isLetter(c) || isMark(c) || isDigit(c)
    }

    /// Thuộc tính White_Space của Unicode (liệt kê tay — Kotlin isWhitespace khác định nghĩa).
    static func isSpace(_ c: Unicode.Scalar) -> Bool {
        switch c.value {
        case 0x09...0x0D, 0x20, 0x85, 0xA0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029,
             0x202F, 0x205F, 0x3000: return true
        default: return false
        }
    }

    private static func isApostrophe(_ c: Unicode.Scalar) -> Bool {
        c == "'" || c == "\u{2019}"
    }

    /// Hoa Đầu Mỗi Từ: chữ đầu mỗi từ HOA, còn lại thường. Dấu nháy kẹp giữa hai chữ
    /// ("don't") thuộc về từ.
    static func titleCase(_ s: String) -> String {
        let cs = Array(s.unicodeScalars)
        var out = ""
        var inWord = false
        for (i, c) in cs.enumerated() {
            if isLetter(c) || isDigit(c) {
                out += inWord ? lower(c) : upper(c)
                inWord = true
            } else if isMark(c) {
                out.unicodeScalars.append(c)
            } else if isApostrophe(c), inWord, i + 1 < cs.count, isLetter(cs[i + 1]) {
                out.unicodeScalars.append(c)
            } else {
                out.unicodeScalars.append(c)
                inWord = false
            }
        }
        return out
    }

    private static func isSentenceEnd(_ c: Unicode.Scalar) -> Bool {
        c == "." || c == "!" || c == "?" || c == "\u{2026}"
    }

    private static func isNewline(_ c: Unicode.Scalar) -> Bool {
        c == "\n" || c == "\r" || c == "\u{2028}" || c == "\u{2029}"
    }

    /// Hoa đầu câu: tất cả thường, chữ đầu văn bản / sau .!?… + khoảng trắng / sau
    /// xuống dòng thì HOA. "3.5" hay "vd.com" không phải hết câu (không có khoảng trắng).
    static func sentenceCase(_ s: String) -> String {
        var out = ""
        var capNext = true
        var pendingEnd = false
        for c in s.unicodeScalars {
            if isLetter(c) {
                out += capNext ? upper(c) : lower(c)
                capNext = false; pendingEnd = false
            } else if isDigit(c) {
                out.unicodeScalars.append(c)
                capNext = false; pendingEnd = false
            } else if isNewline(c) {
                out.unicodeScalars.append(c)
                capNext = true; pendingEnd = false
            } else if isSpace(c) {
                out.unicodeScalars.append(c)
                if pendingEnd { capNext = true }
            } else {
                if isSentenceEnd(c) { pendingEnd = true }
                out.unicodeScalars.append(c)
            }
        }
        return out
    }

    /// Xoá dấu: tách NFD, bỏ dấu tổ hợp U+0300–U+036F, đ→d, Đ→D.
    static func stripDiacritics(_ s: String) -> String {
        var out = String.UnicodeScalarView()
        for c in s.decomposedStringWithCanonicalMapping.unicodeScalars {
            switch c.value {
            case 0x0300...0x036F: continue
            case 0x0111: out.append("d")
            case 0x0110: out.append("D")
            default: out.append(c)
            }
        }
        return String(out)
    }

    // MARK: nguồn chữ

    struct Source: Equatable {
        let text: String
        /// true = vùng chọn (insertText thay thẳng); false = đoạn trước con trỏ (xoá rồi chèn).
        let isSelection: Bool
    }

    /// Vùng chọn (nếu có chữ), không thì đoạn trước con trỏ tính từ lần xuống dòng cuối.
    /// `truncatedStart`: context bị cắt đầu (cửa sổ đọc có giới hạn) mà không thấy
    /// xuống dòng → bỏ mẩu từ đầu bị cắt dở. Không có chữ cái nào → nil.
    static func source(selected: String?, before: String?, truncatedStart: Bool = false) -> Source? {
        if let sel = selected, hasLetter(sel) { return Source(text: sel, isSelection: true) }
        guard let b = before, !b.isEmpty else { return nil }
        let cs = Array(b.unicodeScalars)
        var start = 0
        if let nl = cs.lastIndex(where: isNewline) {
            start = nl + 1
        } else if truncatedStart {
            guard let sp = cs.firstIndex(where: { isSpace($0) }) else { return nil }
            start = sp + 1
        }
        var seg = String.UnicodeScalarView()
        seg.append(contentsOf: cs[start...])
        let text = String(seg)
        return hasLetter(text) ? Source(text: text, isSelection: false) : nil
    }

    private static func hasLetter(_ s: String) -> Bool { s.unicodeScalars.contains(where: isLetter) }

    /// Ô đang dùng dạng dựng sẵn: deleteBackward × Character mới xoá đúng (ô NFD bị cắt vào dấu).
    static func isNFC(_ s: String) -> Bool {
        s.unicodeScalars.elementsEqual(s.precomposedStringWithCanonicalMapping.unicodeScalars)
    }

    struct Undo: Equatable {
        /// Chữ gốc (chèn lại khi hoàn tác).
        let original: String
        /// Chữ đã thay (đang nằm ngay trước con trỏ).
        let result: String
    }
}
