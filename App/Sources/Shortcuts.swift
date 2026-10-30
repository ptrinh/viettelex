// Gõ tắt (text expansion) macOS — logic THUẦN, dùng chung IMKit controller
// (TelexInputController) + tap (TerminalTap) + test. Hành vi khớp bản iOS
// iOS/Keyboard/Shortcuts.swift và Android android/keyboard/.../Shortcuts.kt:
//
//  • khoá CHỮ ("ko", "đc", "cty"): tra lúc gõ ranh giới từ (space/Enter/dấu câu kết
//    thúc từ) theo dạng ĐÃ BIẾN ĐỔI trước ("ddc" → "đc"), rồi phím THÔ.
//  • khoá KÝ HIỆU/SỐ ("->", "√√", "k2", ":D"): tra lúc gõ khoảng trắng/Enter, so với
//    CẢ cụm ký tự liền nhau ngay trước con trỏ (từ khoảng trắng gần nhất) — "a->b"
//    không nở. macOS không có contextBeforeInput như iOS, nên cụm này lấy từ
//    ShortcutTail (ký tự chính mình thấy gõ), rồi IMKit ĐỌC LẠI màn hình để xác nhận
//    trước khi thay (ShortcutScreen) — chỉ đọc khi cụm khớp một khoá, không mỗi phím.
//  • khoá CHỮ+SỐ ("ad1", "sdt2", "2fa" — #109): đi đường cụm như khoá ký hiệu (Telex:
//    chữ số là ranh giới) nhưng nở ở cùng ranh giới với khoá chữ (cả dấu câu); VNI:
//    khớp qua phím thô của từ đang soạn ("ad1" soạn thành "ád").
//  • giữ hoa theo cách gõ: ko → không, Ko → Không, KO → KHÔNG; hoa lộn xộn không
//    nở; khoá ghi đúng y hệt được ưu tiên.
//  • ⌫ ngay sau khi nở trả lại đúng chữ đã gõ + ranh giới, một lần, chỉ khi màn hình
//    khớp (ShortcutUndo). Sau Enter không hoàn tác.
import Foundation

struct ShortcutTable: Equatable {
    private(set) var entries: [String: String]
    /// Có khoá nào không thuần chữ (cần so cụm trước con trỏ lúc gõ khoảng trắng).
    private(set) var hasTokenKeys: Bool

    init(_ entries: [String: String] = [:]) {
        var clean: [String: String] = [:]
        for (k, v) in entries where Self.isValidKey(k) && !v.isEmpty { clean[k] = v }
        self.entries = clean
        self.hasTokenKeys = clean.keys.contains { !Self.isWordKey($0) }
    }

    var isEmpty: Bool { entries.isEmpty }

    /// Khoá hợp lệ: không rỗng, ≤ 64 ký tự, không chứa khoảng trắng.
    static func isValidKey(_ k: String) -> Bool {
        !k.isEmpty && k.count <= 64 && !k.contains(where: { $0.isWhitespace })
    }

    /// Khoá thuần chữ — tra theo từ engine đang soạn.
    static func isWordKey(_ k: String) -> Bool { !k.isEmpty && k.allSatisfy { $0.isLetter } }

    /// Khoá CHỮ+SỐ ("ad1", "sdt2", "2fa" — issue #109): chỉ chữ và chữ số, có cả hai.
    /// Telex coi chữ số là ranh giới nên khoá này đi đường cụm (`tokenExpansion`) như
    /// khoá ký hiệu, nhưng NỞ như khoá chữ: cả ở dấu câu kết thúc từ (`triggers.alnum`)
    /// và cả khi cụm chưa neo mà màn hình không đọc được (`findForTap`). Thuần số
    /// ("123") vẫn là khoá ký hiệu/số (chỉ khoảng trắng — số thập phân, chip số).
    /// VNI: chữ số là phím dấu, khoá này khớp qua PHÍM THÔ của từ đang soạn
    /// (`wordExpansion`: "ad1" → "ád" vẫn khớp "ad1").
    static func isAlnumKey(_ k: String) -> Bool {
        var letter = false, digit = false
        for c in k {
            if c.isLetter { letter = true } else if c.isNumber { digit = true } else { return false }
        }
        return letter && digit
    }

    /// Nội dung sẽ nở cho `typed` (đã áp hoa/thường), nil = không khớp.
    /// 1. khớp nguyên văn; 2. khoá viết thường + `typed` viết hoa toàn bộ (≥ 2 chữ) ⇒
    /// nội dung VIẾT HOA; chỉ chữ đầu hoa ⇒ viết hoa chữ đầu; hoa lộn xộn ("kO") ⇒ nil.
    func expansion(for typed: String) -> String? {
        guard !typed.isEmpty else { return nil }
        if let e = entries[typed] { return e }
        let lower = typed.lowercased()
        guard lower != typed, let e = entries[lower] else { return nil }
        return Self.applyCase(typed: typed, to: e)
    }

    static func applyCase(typed: String, to e: String) -> String? {
        let letters = typed.filter { $0.isLetter }
        guard let first = letters.first else { return e }
        if letters.count >= 2, typed == typed.uppercased() { return e.uppercased() }
        let rest = letters.dropFirst()
        if first.isUppercase, String(rest) == String(rest).lowercased() {
            guard let c = e.first else { return e }
            return c.uppercased() + e.dropFirst()
        }
        return nil
    }

    /// Từ đang soạn: thử dạng hiển thị rồi phím thô (khoá chứa phím Telex như "ks" chỉ
    /// khớp qua phím thô). Khác iOS một chút: phím thô KHÔNG bắt buộc thuần chữ — giữ
    /// hành vi macOS cũ (VNI: phím thô có số).
    func wordExpansion(composed: String, raw: String) -> String? {
        if let e = expansion(for: composed) { return e }
        if raw != composed, let e = expansion(for: raw) { return e }
        return nil
    }

    /// Cụm không khoảng trắng cuối `context`. nil nếu rỗng.
    static func trailingToken(_ context: String) -> String? {
        var start = context.endIndex
        while start > context.startIndex {
            let prev = context.index(before: start)
            if context[prev].isWhitespace { break }
            start = prev
        }
        guard start < context.endIndex else { return nil }
        return String(context[start...])
    }

    /// Khoá ký hiệu/số khớp cụm cuối `context`: (cụm, nội dung). Chỉ khoá không thuần
    /// chữ (khoá chữ đi đường từ đang soạn).
    func tokenExpansion(context: String) -> (token: String, expansion: String)? {
        guard hasTokenKeys, let token = Self.trailingToken(context),
              !Self.isWordKey(token), let e = expansion(for: token) else { return nil }
        return (token, e)
    }

    /// Ký tự ranh giới có kích hoạt khoá CHỮ không: khoảng trắng/xuống dòng hoặc dấu
    /// câu kết thúc từ. Chữ số, @ / # - _ … KHÔNG (ko1, ko@, ko/ không phải từ riêng).
    static func triggersWord(_ boundary: String) -> Bool {
        guard let c = boundary.first else { return false }
        return c.isWhitespace || c.isNewline || wordTriggers.contains(c)
    }
    private static let wordTriggers: Set<Character> = [
        ".", ",", ";", ":", "!", "?", ")", "]", "}", "\"", "'", "…", "”", "’", "»",
    ]

    /// Khoá ký hiệu/số chỉ nở ở khoảng trắng / xuống dòng.
    static func triggersToken(_ boundary: String) -> Bool {
        guard let c = boundary.first else { return false }
        return c.isWhitespace || c.isNewline
    }
}

/// Kết quả tra gõ tắt ở một ranh giới.
enum ShortcutMatch: Equatable {
    /// Thay TỪ đang soạn bằng nội dung.
    case word(expansion: String)
    /// Thay cả cụm `token` (= phần đã chốt trước con trỏ + từ đang soạn) bằng nội dung.
    case token(token: String, expansion: String)

    var expansion: String {
        switch self {
        case let .word(e), let .token(_, e): return e
        }
    }

    /// Tra ở ranh giới: khoá CHỮ theo từ đang soạn trước, rồi khoá KÝ HIỆU/SỐ theo cả
    /// cụm `run + composed` (run = phần đã chốt liền trước từ, xem ShortcutTail).
    /// `allowAlnum`: ranh giới cho khoá chữ+số (#109) — cụm khớp mà là chữ+số thì nở
    /// cả khi `allowToken` tắt (dấu câu).
    static func find(in table: ShortcutTable, composed: String, raw: String, run: String,
                     allowWord: Bool, allowToken: Bool, allowAlnum: Bool = false) -> ShortcutMatch? {
        guard !table.isEmpty else { return nil }
        if allowWord, !composed.isEmpty,
           let e = table.wordExpansion(composed: composed, raw: raw) {
            return .word(expansion: e)
        }
        if allowToken || allowAlnum, table.hasTokenKeys {
            let cand = run + composed
            if !cand.isEmpty, let m = table.tokenExpansion(context: cand), m.token == cand,
               allowToken || ShortcutTable.isAlnumKey(cand) {
                return .token(token: cand, expansion: m.expansion)
            }
        }
        return nil
    }

    /// Tap: tra ở ranh giới với cụm `tail`. Cụm đã neo ⇒ tin dòng phím như trước. Cụm
    /// chưa neo (sau click / đổi ô — issue #99: "->" đầu ô Chrome/Lark phải gõ 2 lần)
    /// ⇒ khoá ký hiệu hỏi màn hình `screen(token)` (AX đọc lại): đứng riêng ⇒ nở, dính
    /// chữ trước ⇒ không. AX KHÔNG đọc được (Lark, Photoshop — #99 follow-up) ⇒ nở khi
    /// cụm bắt đầu ngay sau một lần dời con trỏ (`tail.afterJump`: click, phím điều
    /// hướng, ⌘/⌃-tổ hợp, Tab) — coi chỗ dời tới là neo. Đánh đổi (Phil duyệt): click
    /// ngay sau chữ rồi gõ "->" ("a|->") nở thành "a→"; ⌫ ngay sau vẫn hoàn tác. Khoá
    /// chữ không đổi. `screen` chỉ được gọi khi cụm ĐÃ khớp một khoá. Khoá chữ+số (#109)
    /// nở như khoá chữ: AX không đọc được vẫn nở (khoá chữ "ad" cũng không cần neo);
    /// AX thấy dính chữ trước ("x|ad1") thì không.
    static func findForTap(in table: ShortcutTable, composed: String, raw: String, tail: ShortcutTail,
                           allowWord: Bool, allowToken: Bool, allowAlnum: Bool = false,
                           screen: (String) -> ShortcutScreen.TokenVerdict) -> ShortcutMatch? {
        let m = find(in: table, composed: composed, raw: raw, run: tail.run,
                     allowWord: allowWord, allowToken: allowToken, allowAlnum: allowAlnum)
        guard case let .token(token, _)? = m, !tail.anchored else { return m }
        switch screen(token) {
        case .standsAlone: return m
        case .glued: return nil
        case .unreadable: return tail.afterJump || ShortcutTable.isAlnumKey(token) ? m : nil
        }
    }

    /// Ranh giới `boundary` (nil = Esc / phím không chèn ký tự) + từ có dính sau ký tự
    /// mở token (#82 số, #87 / # @ . _ -) ⇒ được tra khoá chữ / khoá ký hiệu không.
    /// Esc giữ hành vi cũ: khoá chữ có, khoá ký hiệu không. `alnum` = khoá chữ+số
    /// (#109): cùng bộ ranh giới với khoá chữ (khoảng trắng, xuống dòng, Tab, dấu câu kết
    /// thúc từ) nhưng KHÔNG bị chặn bởi `glued` — cụm khớp nguyên văn từ đầu cụm nên
    /// "5ad1" / "x.ad1" tự không khớp; "ad1" có chữ số nên luôn "dính số" ở Telex.
    static func triggers(boundary: String?, glued: Bool) -> (word: Bool, token: Bool, alnum: Bool) {
        guard let b = boundary else { return (!glued, false, false) }
        return (!glued && ShortcutTable.triggersWord(b), ShortcutTable.triggersToken(b),
                ShortcutTable.triggersWord(b))
    }
}

/// Cụm ký tự liền nhau ĐÃ CHỐT ngay trước con trỏ (từ khoảng trắng gần nhất), dựng
/// từ chính các phím mình thấy — không đọc màn hình mỗi phím. `anchored` = đầu cụm
/// chắc chắn đứng ngay sau một khoảng trắng/xuống dòng mình thấy gõ. Mọi sự kiện có
/// thể dời con trỏ (click, phím điều hướng, đổi ô, ⌘-tổ hợp) phải reset() — hoặc
/// caretMoved() ở đường tap khi chắc đó là một lần DỜI con trỏ (xem `afterJump`).
struct ShortcutTail: Equatable {
    /// Dài hơn khoá dài nhất (64) thì không khoá nào khớp được cho tới khoảng trắng kế.
    static let maxRun = 64
    /// Trần `recent` (> MathResults.maxLength + cụm số hai từ): đủ cho gợi ý cạnh con trỏ.
    static let maxRecent = 96
    private(set) var run = ""
    private(set) var anchored = false
    /// Cụm (chưa neo) bắt đầu NGAY tại chỗ con trỏ vừa dời tới (click / điều hướng /
    /// ⌘-tổ hợp / Tab) và từ đó chỉ có phím mình thấy gõ. Chỉ dùng khi AX không đọc
    /// được (ShortcutMatch.findForTap) — issue #99 follow-up (Lark, Photoshop).
    private(set) var afterJump = false
    private var runCount = 0
    /// Văn bản mình thấy hiện ra trước con trỏ từ lần reset/dời con trỏ gần nhất (kể cả
    /// khoảng trắng), ít nhất `maxRecent` ký tự cuối (cắt theo mẻ 32) — nguồn văn bản của gợi ý cạnh con
    /// trỏ khi AX không đọc được (Firefox, issue #104). `recentWhole` = `recent` là TOÀN
    /// BỘ văn bản kể từ một lần dời con trỏ (không bị cắt đầu).
    private(set) var recent = ""
    private(set) var recentWhole = false
    private var recentCount = 0          // = recent.count (String.count là O(n) — phím nóng)
    /// "\n" cuối `recent` (chỉ khoảng trắng theo sau) đến từ PHÍM Return, chưa chắc là xuống
    /// dòng thật: Enter chọn gợi ý (mention Discord/Slack, emoji, lệnh /) hay gửi tin không
    /// chèn "\n". Gõ tắt / ⌫-gõ-lại / dấu chấm nhấn đúp vẫn dùng `recent` như cũ; chỉ viết
    /// hoa đầu câu coi ngữ cảnh là không biết (`autoCapKnownText`) để đọc lại màn hình.
    private(set) var returnUnverified = false

    mutating func reset() {
        run = ""; runCount = 0; anchored = false; afterJump = false
        recent = ""; recentCount = 0; recentWhole = false
        returnUnverified = false
    }

    /// Phím Return/Enter đi qua: như append("\n") nhưng đánh dấu chưa xác nhận.
    mutating func appendReturn() {
        append("\n")
        returnUnverified = true
    }

    /// Ngữ cảnh dòng phím cho viết hoa đầu câu — xem SystemAutoText.autoCapKnownText.
    var autoCapKnownText: String? {
        SystemAutoText.autoCapKnownText(recent: recent, returnUnverified: returnUnverified)
    }

    /// Con trỏ vừa dời (click, phím điều hướng, ⌘/⌃-tổ hợp, Tab đổi ô): bỏ cụm, đánh
    /// dấu chỗ mới là điểm bắt đầu cụm.
    mutating func caretMoved() { reset(); afterJump = true; recentWhole = true }

    /// Văn bản vừa hiện ra trước con trỏ (từ đã chốt, ký tự ranh giới, nội dung nở).
    mutating func append(_ s: String) {
        for ch in s {
            if !(ch == " " || ch == "\t") { returnUnverified = false }
            if ch.isWhitespace || ch.isNewline {
                run = ""; runCount = 0; anchored = true; afterJump = false
            } else if runCount >= Self.maxRun {
                reset()                       // quá dài: đầu cụm không còn biết
                continue
            } else {
                run.append(ch); runCount += 1
            }
            recent.append(ch); recentCount += 1
            if recentCount > Self.maxRecent + 32 {             // cắt theo mẻ: không memmove mỗi ký tự
                recent.removeFirst(recentCount - Self.maxRecent); recentCount = Self.maxRecent
                recentWhole = false
            }
        }
    }

    /// ⌫ khi không có từ đang soạn: xoá ký tự cuối cụm; cụm rỗng ⇒ vừa xoá khoảng
    /// trắng, phần trước nó không biết ⇒ mất neo.
    mutating func backspace() {
        if run.isEmpty { anchored = false; afterJump = false } else { run.removeLast(); runCount -= 1 }
        if recent.isEmpty { recentWhole = false } else { recent.removeLast(); recentCount -= 1 }
    }

    /// Cụm vừa bị thay (khoá ký hiệu nở): bỏ cụm, giữ neo, rồi nối nội dung mới.
    mutating func replaceRun(with s: String) {
        if recentCount >= runCount { recent.removeLast(runCount); recentCount -= runCount }
        else { recent = ""; recentCount = 0; recentWhole = false }
        run = ""; runCount = 0
        append(s)
    }

    /// Đuôi `old` (mình vừa thấy gõ) vừa được thay bằng `new` (áp dụng gợi ý cạnh con
    /// trỏ). Đuôi không khớp ⇒ không còn biết gì phía trước: chỉ còn `new`.
    mutating func replaceSuffix(_ old: String, with new: String) {
        guard !old.isEmpty, recent.hasSuffix(old), recentCount >= old.count else {
            reset(); append(new); return
        }
        let base = String(recent.dropLast(old.count))
        let whole = recentWhole
        if whole { caretMoved() } else { reset() }
        append(base + new)
    }

    /// Văn bản CHẮC CHẮN nằm ngay trước con trỏ, dựng từ dòng phím (không đọc màn hình):
    /// cả `recent` khi nó bắt đầu đúng ở chỗ con trỏ dời tới (coi đó là đầu văn bản —
    /// cùng đánh đổi #99 Phil đã duyệt), không thì phần từ khoảng trắng ĐẦU TIÊN mình
    /// thấy gõ (phía trước nó là chữ không biết). nil = không biết gì.
    var knownText: String? {
        if recentWhole { return recent }
        guard let i = recent.firstIndex(where: { $0.isWhitespace || $0.isNewline }) else { return nil }
        return String(recent[i...])
    }
}

/// Lần nở gần nhất — ⌫ NGAY SAU đó trả lại đúng chữ đã gõ + ranh giới (một lần).
struct ShortcutUndo: Equatable {
    let typed: String
    let expansion: String
    let boundary: String

    /// Chỉ hứa hoàn tác khi ranh giới là MỘT ký tự in được, không phải xuống dòng
    /// (Enter có thể đã gửi tin; Tab dời focus).
    static func make(typed: String, expansion: String, boundary: String?) -> ShortcutUndo? {
        guard let b = boundary, b.count == 1, let c = b.first, !c.isNewline, c != "\t",
              !typed.isEmpty else { return nil }
        return ShortcutUndo(typed: typed, expansion: expansion, boundary: b)
    }

    /// Văn bản màn hình phải kết thúc bằng (ngay trước con trỏ) để được hoàn tác.
    var onScreen: String { expansion + boundary }
    var restored: String { typed + boundary }
}

/// Xác nhận màn hình trước khi thay (IMKit: đọc lại bằng attributedSubstring). So
/// UTF-16 chính xác — String == của Swift so tương đương chuẩn (NFD == NFC) nên một
/// ô NFD sẽ "khớp" mà độ dài range lệch.
enum ShortcutScreen {
    /// Cửa sổ cần đọc để xác nhận `text` nằm ngay trước `caret` (+1 ký tự trước nó để
    /// kiểm ranh giới). nil nếu caret không đủ chỗ.
    static func readWindow(caret: Int, text: String) -> NSRange? {
        let len = text.utf16.count
        guard len > 0, caret >= len else { return nil }
        let start = max(0, caret - len - 1)
        return NSRange(location: start, length: caret - start)
    }

    /// Range UTF-16 của khoá `token` nếu màn hình (cửa sổ `window` bắt đầu ở
    /// `windowStart`, kết thúc đúng ở `caret`) kết thúc bằng token VÀ token đứng riêng
    /// (đầu văn bản, hoặc ngay sau khoảng trắng/xuống dòng). Ngược lại nil.
    static func tokenRange(caret: Int, token: String, window: String, windowStart: Int) -> NSRange? {
        let w = Array(window.utf16), t = Array(token.utf16)
        guard !t.isEmpty, windowStart + w.count == caret, w.count >= t.count,
              Array(w.suffix(t.count)) == t else { return nil }
        let start = caret - t.count
        if start > 0 {
            guard w.count > t.count, let s = Unicode.Scalar(w[w.count - t.count - 1]),
                  Character(s).isWhitespace || Character(s).isNewline else { return nil }
        }
        return NSRange(location: start, length: t.count)
    }

    /// Màn hình nói gì về một cụm chưa neo (tap, issue #99).
    enum TokenVerdict: Equatable {
        /// Cụm nằm ngay trước con trỏ và đứng riêng (đầu văn bản / sau khoảng trắng).
        case standsAlone
        /// Cụm nằm ngay trước con trỏ nhưng DÍNH ký tự không trắng trước nó ("a->").
        case glued
        /// Không đọc được, hoặc đọc ra thứ không kết thúc bằng cụm mình vừa thấy gõ
        /// (caret giả — Lark báo 1 hằng số — hay cache AX trễ): màn hình không đáng tin.
        case unreadable
    }

    /// Tap (issue #99): cụm CHƯA NEO — gõ ngay sau click / đổi ô / đầu ô trống, tap
    /// không thấy khoảng trắng nào trước cụm. Đọc màn hình (AX, `read` = đọc UTF-16
    /// range của ô đang focus) xem cụm có đứng riêng trước con trỏ không. Chỉ gọi khi
    /// cụm đã khớp một khoá — không đọc mỗi phím.
    static func tokenVerdict(_ token: String, caret: Int?, read: (NSRange) -> String?) -> TokenVerdict {
        guard let caret, let window = readWindow(caret: caret, text: token),
              let text = read(window) else { return .unreadable }
        let w = Array(text.utf16), t = Array(token.utf16)
        guard !t.isEmpty, window.location + w.count == caret, w.count >= t.count,
              Array(w.suffix(t.count)) == t else { return .unreadable }
        return tokenRange(caret: caret, token: token, window: text, windowStart: window.location) != nil
            ? .standsAlone : .glued
    }

    /// true ⇔ màn hình xác nhận cụm đứng riêng (tokenVerdict == .standsAlone).
    static func confirmsToken(_ token: String, caret: Int?, read: (NSRange) -> String?) -> Bool {
        tokenVerdict(token, caret: caret, read: read) == .standsAlone
    }

    /// Range UTF-16 cần thay để hoàn tác `undo` nếu màn hình kết thúc ĐÚNG bằng nội
    /// dung đã nở + ranh giới. Ngược lại nil (⌫ thường).
    static func undoRange(caret: Int, undo: ShortcutUndo, window: String, windowStart: Int) -> NSRange? {
        let w = Array(window.utf16), t = Array(undo.onScreen.utf16)
        guard !t.isEmpty, windowStart + w.count == caret, w.count >= t.count,
              Array(w.suffix(t.count)) == t else { return nil }
        return NSRange(location: caret - t.count, length: t.count)
    }

    /// Ký tự một phím ranh giới vừa để lại trước con trỏ (đưa vào ShortcutTail), nil =
    /// không chèn gì đoán được (phím điều hướng/chức năng U+F700…, ký tự điều khiển).
    static func insertedText(_ characters: String?) -> String? {
        guard let s = characters, s.count == 1, let u = s.unicodeScalars.first else { return nil }
        if u.value < 0x20 || u.value == 0x7F || (0xF700...0xF8FF).contains(u.value) { return nil }
        return s
    }
}
