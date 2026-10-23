// Thứ tự ưu tiên các loại chip tranh slot trên thanh gợi ý — THUẦN, song sinh
// android/keyboard/.../SuggestionSlots.kt, cùng bảng ca kiểm (SuggestionSlotsTests).
// Tài liệu: iOS/docs/IOS-SUGGESTIONS.md mục "Thứ tự ưu tiên slot".
//
// Từ cao xuống thấp (tầng trên thắng / đè tầng dưới):
//  1. Hoàn tác một lượt — "↩︎ Khôi phục" (vuốt ⌫), "↩︎ Hoàn tác" công cụ văn bản
//     (restoreLabel/restorePayload), "↩︎ Hoàn tác" thêm dấu (undoTonesToken). iOS: slot
//     đầu, gợi ý dời phải; Android: một pill giữa bar.
//  2. Clipboard vừa copy — tối đa 2 chip tách STK/SĐT/OTP + ô "Dán" nguyên văn, thắng
//     thẻ Dán; cả hai thay cả bar.
//  3. "Thêm dấu" (addTonesToken) — slot đầu, nhường clipboard.
//  4. Chip số — slot 1 (GIỮA khi 3 ô); nội dung từ đó dời phải một ô (ô cuối là vùng
//     emoji thì vẫn là emoji). Kết quả phép tính "…=" (MathResults) — slot ĐẦU như bàn phím gốc,
//     mọi chip khác dời phải một ô.
//  5. Chữ — nguyên văn / ứng viên (chip gõ tắt nằm ở ứng viên chính) / emoji, hoặc từ kế
//     tiếp (bigram, email/TLD, biến thể gõ vuốt).
// Số ô: cài đặt "Số từ gợi ý" (SuggestionCount) — Tự động = 3; xem `arrange`.
import Foundation

struct BarChip: Equatable {
    let label: String
    let payload: String
}

enum BarLayout: Equatable {
    /// Một pill giữa bar (Android dùng cho hoàn tác; iOS không dùng).
    case pill(BarChip)
    /// Chip chia đều bar (clipboard).
    case chips([BarChip])
    /// Thẻ Dán thay cả bar.
    case pasteCard
    /// `count` slot trái→phải + emoji (vùng slot CUỐI; slots[count-1] khi đó = nil).
    case slots([BarChip?], emojis: [String])
}

enum SuggestionSlots {
    /// Số emoji tối đa trong vùng emoji (ô cuối): 3 khi ≤ 3 ô; ô hẹp hơn (4–5 ô) ⇒ 2.
    static func maxEmojis(count: Int) -> Int { count <= 3 ? 3 : 2 }

    /// Thứ tự ô cho từ kế tiếp (hạng 0, 1, 2…). `bestInMiddle` (Android/Gboard): hạng 0 ở ô
    /// GIỮA ((count−1)/2), rồi xen kẽ trái/phải ra ngoài — 3 ô: [1, 0, 2]; 5 ô: [2, 1, 3, 0, 4].
    /// iOS: trái→phải.
    static func nextOrder(count: Int, bestInMiddle: Bool) -> [Int] {
        guard bestInMiddle, count > 1 else { return Array(0..<max(count, 0)) }
        let c = (count - 1) / 2
        var order = [c]
        var d = 1
        while order.count < count {
            if c - d >= 0 { order.append(c - d) }
            if c + d < count { order.append(c + d) }
            d += 1
        }
        return order
    }

    /// Ô "chính" (Android tô đậm): từ kế tiếp + `bestInMiddle` ⇒ ô giữa; còn lại ô ngay sau
    /// nguyên văn / chip dẫn đầu (1), 1 ô ⇒ 0. 3 ô ⇒ luôn 1 như trước.
    static func primaryIndex(count: Int, nextWords: Bool, bestInMiddle: Bool) -> Int {
        guard count > 1 else { return 0 }
        return nextWords && bestInMiddle ? (count - 1) / 2 : 1
    }

    /// `undoAsPill`: Android true, iOS false. `bestInMiddle`: từ kế tiếp tốt nhất ở giữa
    /// (Android/Gboard) hay trái (iOS). `count`: số ô (SuggestionCount.fit, 1…5; mặc định 3).
    ///
    /// Tổng quát hoá bố cục 3 ô (count = 3 giữ NGUYÊN hành vi cũ):
    ///  - Đang gõ: ô 0 = nguyên văn, ô 1 = ứng viên chính, rồi word2, moreWords… theo thứ tự
    ///    đọc; có emoji (count ≥ 3) ⇒ ô CUỐI là vùng emoji. count = 1 ⇒ chỉ ứng viên chính
    ///    (không có thì nguyên văn); count < 3 ⇒ không vùng emoji.
    ///  - Từ kế tiếp: `nextOrder`.
    ///  - Chip dẫn đầu (hoàn tác / Thêm dấu / ↩︎ từ cũ / ↩︎ chữ gốc): ô 0, chữ dời phải.
    ///  - Chip số: chèn ở ô 1 (count = 1: ô 0), phần sau dời phải; kết quả phép tính: chèn ô 0.
    static func arrange(_ set: KeyboardView.SuggestionSet, undoAsPill: Bool = false,
                        bestInMiddle: Bool = false, pasteLabel: String = "Dán",
                        count: Int = SuggestionCount.autoSlots) -> BarLayout {
        let n = min(max(count, 1), SuggestionCount.max)
        var action: BarChip?
        if let l = set.actionLabel, let p = set.actionPayload { action = BarChip(label: l, payload: p) }
        // 1. hoàn tác một lượt
        var undo: BarChip?
        if let r = set.restoreLabel {
            undo = BarChip(label: r, payload: set.restorePayload ?? KeyboardView.restoreToken)
        } else if let a = action, a.payload == KeyboardView.undoTonesToken {
            undo = a
        }
        if let u = undo, undoAsPill { return .pill(u) }
        // 2. clipboard
        if undo == nil, !set.clipChips.isEmpty {
            var chips = set.clipChips.prefix(2).map { BarChip(label: $0.display, payload: $0.insert) }
            if set.paste, chips.count < 3 { chips.append(BarChip(label: pasteLabel, payload: KeyboardView.pasteToken)) }
            return .chips(chips)
        }
        if undo == nil, set.paste { return .pasteCard }
        // 5. chữ
        var slots = [BarChip?](repeating: nil, count: n)
        let emojis = set.nextWords.isEmpty && n >= 3 ? Array(set.emojis.prefix(maxEmojis(count: n))) : []
        if !set.nextWords.isEmpty {
            for (i, w) in zip(nextOrder(count: n, bestInMiddle: bestInMiddle), set.nextWords) {
                slots[i] = BarChip(label: w, payload: w)
            }
        } else if n == 1 {
            if let w = set.word ?? set.literal { slots[0] = BarChip(label: w, payload: w) }
        } else {
            if let l = set.literal { slots[0] = BarChip(label: "\u{201C}\(l)\u{201D}", payload: l) }
            // ứng viên theo vị trí (word, word2, moreWords…) vào ô 1…; ô cuối nhường emoji
            let words: [String?] = [set.word, set.word2] + set.moreWords.map { $0 }
            let room = n - 1 - (emojis.isEmpty ? 0 : 1)
            for (i, w) in words.prefix(room).enumerated() { slots[1 + i] = w.map { BarChip(label: $0, payload: $0) } }
        }
        // 1 (slot) / 3. hoàn tác, "Thêm dấu", "↩︎ từ cũ" (vuốt vừa sửa từ trước) hoặc "↩︎ chữ
        // gốc" (vừa tự sửa) chiếm slot đầu, chữ dời phải theo thứ tự đọc.
        let lead = undo ?? action.flatMap {
            [KeyboardView.addTonesToken, KeyboardView.undoReviseToken,
             KeyboardView.undoAutoCorrectToken, KeyboardView.retroOfferToken,
             KeyboardView.undoRetroToken].contains($0.payload) ? $0 : nil
        }
        if let lead {
            let words = set.nextWords.isEmpty ? slots.compactMap { $0 }
                : set.nextWords.prefix(n).map { BarChip(label: $0, payload: $0) }
            slots = [lead] + (0..<(n - 1)).map { $0 < words.count ? words[$0] : nil }
        }
        // 4. chip số: ô 1 (giữa khi 3 ô); phần sau dời phải.
        if let n2 = set.number {
            insert(&slots, BarChip(label: n2, payload: KeyboardView.numberToken), at: min(1, n - 1))
        }
        // 4. kết quả phép tính: slot đầu; còn lại dời phải.
        if let m = set.math {
            insert(&slots, BarChip(label: m, payload: KeyboardView.mathToken), at: 0)
        }
        if !emojis.isEmpty { slots[n - 1] = nil }
        return .slots(slots, emojis: emojis)
    }

    /// Chèn `chip` ở ô `i`, các ô sau dời phải một ô (ô cuối rơi ra), giữ nguyên số ô.
    private static func insert(_ slots: inout [BarChip?], _ chip: BarChip, at i: Int) {
        slots.insert(chip, at: i)
        slots.removeLast()
    }
}
