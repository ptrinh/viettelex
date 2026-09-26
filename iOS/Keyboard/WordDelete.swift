// WordDelete — logic THUẦN (không UIKit) cho xoá theo TỪ:
//   • giữ ⌫ >3s (deleteWordBackward) — 1 từ mỗi nhịp;
//   • vuốt trái trên ⌫ (kiểu Gboard) — kéo bao xa thì xoá bấy nhiêu từ, nhấc tay mới xoá.
//
// "Một từ" tính từ con trỏ lùi về: khoảng trắng + dấu câu liền trước con trỏ đi KÈM
// với từ đứng trước chúng (như Gboard: "xin chào, |" vuốt 1 từ → "xin |"). Emoji liền
// nhau là một đơn vị riêng. Đếm theo Character (grapheme) — cùng đơn vị với
// deleteBackward của iOS (chữ có dấu tổ hợp, emoji ZWJ đều là 1 lần xoá).
//
// Fail-safe (tinh thần CompositionSync): context nil = KHÔNG BIẾT → không xoá mù;
// từ đang soạn không còn nằm cuối context = lệch → không xoá.
import CoreGraphics

enum WordDelete {

    // MARK: ranh giới từ

    static func isEmoji(_ c: Character) -> Bool {
        guard let s = c.unicodeScalars.first else { return false }
        // Chữ số / # / * cũng mang cờ isEmoji (keycap) → chỉ tính khi có biến thể
        // hoặc nằm ngoài vùng ASCII/ký hiệu cũ.
        return s.properties.isEmojiPresentation
            || (s.properties.isEmoji && (c.unicodeScalars.count > 1 || s.value > 0x238C))
    }

    /// Khoảng trắng, xuống dòng, dấu câu, ký hiệu (không phải emoji).
    static func isSeparator(_ c: Character) -> Bool {
        if isEmoji(c) { return false }
        return c.isWhitespace || c.isPunctuation || c.isSymbol
    }

    /// Nối trong từ: "don't", "e-mail" — chỉ khi hai bên đều là chữ.
    private static func isJoiner(_ c: Character) -> Bool {
        c == "'" || c == "\u{2019}" || c == "-"
    }

    /// Số ký tự của MỘT đơn vị từ kết thúc tại `end` (exclusive) trong `chars`.
    static func unitLength(_ chars: [Character], end: Int) -> Int {
        var i = end
        while i > 0, isSeparator(chars[i - 1]) { i -= 1 }   // trắng + dấu câu đuôi
        if i > 0 {
            if isEmoji(chars[i - 1]) {
                while i > 0, isEmoji(chars[i - 1]) { i -= 1 }
            } else {
                while i > 0 {
                    let c = chars[i - 1]
                    if !isSeparator(c) && !isEmoji(c) { i -= 1; continue }
                    // dấu nối kẹp giữa hai chữ ("don't") thuộc về từ
                    if isJoiner(c), i >= 2, i < end, !isSeparator(chars[i - 2]),
                       !isEmoji(chars[i - 2]) {
                        i -= 1; continue
                    }
                    break
                }
            }
        }
        return end - i
    }

    /// Số ký tự cần deleteBackward để xoá `words` từ trước con trỏ. Hết context thì
    /// dừng (không bao giờ vượt `context.count`).
    static func charsToDelete(context: String, words: Int) -> Int {
        let chars = Array(context)
        var end = chars.count
        var n = 0
        while n < words, end > 0 {
            end -= unitLength(chars, end: end)
            n += 1
        }
        return chars.count - end
    }

    /// Như trên nhưng từ đang soạn (engine không rỗng, đã nằm cuối context) là từ
    /// thứ nhất nguyên vẹn — kể cả khi nó chứa ký tự ngoài lớp "chữ".
    static func charsToDelete(context: String, composed: String, words: Int) -> Int {
        guard words > 0 else { return 0 }
        guard !composed.isEmpty, context.hasSuffix(composed) else {
            return charsToDelete(context: context, words: words)
        }
        let head = String(context.dropLast(composed.count))
        return composed.count + charsToDelete(context: head, words: words - 1)
    }

    /// Có bao nhiêu từ để xoá (tối đa `limit`) — kẹp số từ trên nhãn xem trước.
    static func availableWords(context: String, limit: Int = 50) -> Int {
        let chars = Array(context)
        var end = chars.count
        var n = 0
        while n < limit, end > 0 {
            end -= unitLength(chars, end: end)
            n += 1
        }
        return n
    }

    // MARK: vuốt ⌫ → số từ

    /// Kéo ngang tối thiểu (pt) trước khi coi là vuốt — trên dung sai chạm và trên
    /// allowableMovement 10pt của long-press (vuốt thật thì giữ-lặp đã fail).
    static let swipeActivation: CGFloat = 16

    /// Bước kéo = bề rộng một phím chữ (kẹp cho iPad / phím lạ).
    static func swipeStep(letterKeyWidth w: CGFloat?) -> CGFloat {
        guard let w, w > 0 else { return 32 }
        return min(max(w, 24), 56)
    }

    /// Kéo sang TRÁI `dragLeft` pt (âm = sang phải) → số từ sẽ xoá.
    /// Dưới ngưỡng kích hoạt → 0 (huỷ); sau đó mỗi `step` thêm 1 từ; kẹp ở `max`.
    static func words(dragLeft: CGFloat, step: CGFloat, max maxWords: Int,
                      activation: CGFloat = swipeActivation) -> Int {
        guard dragLeft >= activation, maxWords > 0, step > 0 else { return 0 }
        let n = 1 + Int(((dragLeft - activation) / step).rounded(.down))
        return min(n, maxWords)
    }

    // MARK: kế hoạch xoá khi nhấc tay

    struct Plan: Equatable {
        /// deleteBackward thêm bao nhiêu lần (ngoài lần xoá lúc chạm xuống).
        var deleteNow: Int
        /// Chèn lại (khi lần xoá lúc chạm xuống đã xoá DƯ so với kế hoạch — vd. huỷ).
        var reinsert: String
        /// Toàn bộ chuỗi đã biến mất so với lúc chạm xuống → ô "Khôi phục".
        var removed: String
        /// Phần context còn lại sau khi xoá (để kiểm tra trước khi khôi phục).
        var remaining: String
    }

    /// `snapshot` = context NGAY TRƯỚC lần xoá lúc chạm ⌫ (cùng `composed` lúc đó);
    /// `current` = context lúc nhấc tay (đã mất ký tự của lần chạm xuống).
    /// nil = không làm gì (context không biết / từ đang soạn lệch).
    static func plan(snapshot: String?, composed: String, current: String?,
                     words: Int) -> Plan? {
        guard let snap = snapshot, let cur = current else { return nil }
        if !composed.isEmpty, !snap.hasSuffix(composed) { return nil }
        // Lần chạm xuống phải chỉ CẮT ĐUÔI snapshot; khác đi (engine vẽ lại từ, host
        // tự sửa…) thì lấy context hiện tại làm gốc, không bù lần chạm.
        let base: String, already: Int
        let snapChars = Array(snap), curChars = Array(cur)
        if curChars.count <= snapChars.count, Array(snapChars.prefix(curChars.count)) == curChars {
            base = snap; already = snapChars.count - curChars.count
        } else {
            base = cur; already = 0
        }
        let baseChars = Array(base)
        let baseComposed = base == snap ? composed : ""
        let total = charsToDelete(context: base, composed: baseComposed, words: words)
        let remaining = String(baseChars.prefix(baseChars.count - total))
        let removed = String(baseChars.suffix(total))
        if total >= already {
            return Plan(deleteNow: total - already, reinsert: "", removed: removed,
                        remaining: remaining)
        }
        let reinsert = String(baseChars[(baseChars.count - already)..<(baseChars.count - total)])
        return Plan(deleteNow: 0, reinsert: reinsert, removed: removed, remaining: remaining)
    }

    /// Khôi phục an toàn? Chữ trước con trỏ phải còn kết thúc bằng đuôi đã ghi lúc
    /// xoá (con trỏ dời / đổi ô → không chèn lạc chỗ). nil = không biết → cho.
    static func canRestore(context: String?, tail: String) -> Bool {
        guard let ctx = context else { return true }
        return tail.isEmpty ? true : ctx.hasSuffix(tail)
    }

    /// Đuôi ngắn của phần còn lại, dùng cho canRestore.
    static func restoreTail(_ remaining: String) -> String {
        String(remaining.suffix(16))
    }
}
