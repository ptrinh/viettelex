// "Sửa lỗi bằng Apple Intelligence" (Plus, iOS 26+, mặc định TẮT) — phần THUẦN (test được,
// không UIKit, không FoundationModels):
//  - chọn chế độ theo vùng chọn (≥ 2 từ ⇒ chip "✨ Sửa lỗi"; đúng 1 từ ⇒ từ thay thế),
//  - dựng prompt (instructions + nội dung, ngữ cảnh quanh từ có giới hạn độ dài),
//  - kiểm kết quả model (bỏ đầu ra đổi độ dài quá đà, mất xuống dòng / emoji…),
//  - so khác theo TỪ để tô chỗ đã sửa trong bảng xem trước.
// Gọi model: VTIntelligence/IntelligenceEngine.swift (framework app chủ, dlopen —
// Keyboard/AIAssistLoader.swift). Glue bàn phím: Keyboard/AIAssist.swift.
// Feature flags & perf: công tắc TẮT ⇒ controller không giữ AIAssist (nil), không đọc
// selectedText, không dlopen, không prewarm — 0 chi phí.
import Foundation

/// Payload chip của tính năng (ký tự Private Use như KeyboardView.*Token). Cả bốn là chip DẪN
/// ĐẦU (SuggestionSlots.arrange đặt ở slot đầu).
enum AITokens {
    static let proofread = "\u{E000}aiProofread"
    static let busy = "\u{E000}aiBusy"
    static let undo = "\u{E000}aiUndo"
    static let notice = "\u{E000}aiNotice"
    static let lead: Set<String> = [proofread, busy, undo, notice]
}

// MARK: chế độ theo vùng chọn

enum AIMode: Equatable {
    case none
    /// ≥ 2 từ: chip "✨ Sửa lỗi" (đoạn chọn nguyên văn).
    case proofread(String)
    /// Đúng 1 từ: gợi ý tối đa 3 từ thay thế (từ đã bỏ khoảng trắng hai đầu).
    case alternatives(String)
}

enum AIText {
    /// Đoạn dài hơn thì không mời (context model trên máy có hạn; xem trước phải gọn).
    static let maxProofreadChars = 1000
    /// Từ dài hơn ⇒ không phải "một từ" để thay.
    static let maxWordChars = 32
    /// Ngữ cảnh quanh từ được chọn (mỗi phía).
    static let contextChars = 160
    /// Hạn giờ mỗi yêu cầu. Đo trên simulator (30/10/2026): lần đầu KHÔNG prewarm 5,6–8,0 s,
    /// các lần sau 1,3–2,8 s ⇒ 10 s (prewarm lúc có vùng chọn thường đưa lần đầu về mức "ấm").
    static let timeout: TimeInterval = 10
    /// Ngăn mục danh sách trong chuỗi trả từ framework (khớp IntelligenceEngine.listSeparator).
    static let listSeparator: Character = "\u{1E}"

    static func isSpace(_ c: Character) -> Bool { c.isWhitespace }

    /// Các "từ" (chuỗi không khoảng trắng có ít nhất một chữ cái).
    static func words(_ s: String) -> [Substring] {
        s.split(whereSeparator: { $0.isWhitespace }).filter { $0.contains(where: \.isLetter) }
    }

    static func mode(selected: String?) -> AIMode {
        guard let sel = selected, sel.contains(where: \.isLetter) else { return .none }
        let w = words(sel)
        if w.count >= 2 {
            return sel.count <= maxProofreadChars ? .proofread(sel) : .none
        }
        let core = sel.trimmingCharacters(in: .whitespacesAndNewlines)
        // Một "từ" thật: không khoảng trắng bên trong, đủ ngắn, chữ cái là chính.
        guard w.count == 1, !core.contains(where: \.isWhitespace), core.count <= maxWordChars else { return .none }
        let letters = core.filter(\.isLetter).count
        guard letters * 2 >= core.count else { return .none }
        return .alternatives(stripEdgePunctuation(core))
    }

    /// Bỏ dấu câu dính hai đầu ("bạn," → "bạn") — vẫn giữ dấu nháy/gạch nối giữa từ.
    static func stripEdgePunctuation(_ s: String) -> String {
        var t = Substring(s)
        while let f = t.first, !f.isLetter, !f.isNumber { t = t.dropFirst() }
        while let l = t.last, !l.isLetter, !l.isNumber { t = t.dropLast() }
        return t.isEmpty ? s : String(t)
    }

    // MARK: prompt

    static let proofreadInstructions = """
    You are a careful proofreader for text typed on a phone keyboard. The text is usually \
    Vietnamese, often mixed with English. Fix: spelling mistakes and typos; Vietnamese words \
    typed without tone marks or with wrong tone marks (choose the marks that fit the sentence: \
    "ban oi" → "bạn ơi", "khong" → "không"); and clear grammar mistakes in either language \
    ("I has" → "I have"). Keep the meaning, wording, tone and mix of languages: do not \
    translate, do not rephrase, do not add or remove sentences, do not explain. Keep chat slang \
    and abbreviations (ko, dc, ok), names, URLs, numbers, emoji, punctuation style, \
    capitalization of correct words and line breaks. If there are no mistakes, return the text \
    unchanged.
    Example: "toi dang o nha, ban co ranh ko" → "tôi đang ở nhà, bạn có rảnh ko"
    Example: "She go to school yesterday" → "She went to school yesterday"
    """

    /// Đoạn nhiều dòng: model hay gộp dòng / lộ khung JSON (đo trên simulator 30/10/2026) ⇒ gửi
    /// TỪNG DÒNG có chữ thành một mục ("Line k: …"), nhận lại mảng cùng số mục, ráp lại đúng
    /// ký tự xuống dòng / dòng trống / khoảng trắng hai đầu gốc (TranslateText.linePlan/assemble).
    static func proofreadPrompt(_ text: String) -> String {
        proofreadPrompt(lines: TranslateText.linePlan(text).cores)
    }

    static func proofreadPrompt(lines: [String]) -> String {
        let n = lines.count
        var out = n == 1 ? "Proofread this line. Return exactly 1 corrected line.\n"
            : "Proofread each of these \(n) lines separately. Return exactly \(n) corrected lines, in the same order.\n"
        for (i, l) in lines.enumerated() { out += "\nLine \(i + 1): \(l)" }
        return out
    }

    /// Bỏ tiền tố "Line 3:" model chép lại từ prompt.
    static func stripLinePrefix(_ s: String) -> String {
        guard let r = s.range(of: #"^\s*Line \d+\s*:\s?"#, options: .regularExpression) else { return s }
        return String(s[r.upperBound...])
    }

    /// Ráp các dòng model trả (chuỗi ngăn bằng listSeparator) vào chữ gốc rồi kiểm
    /// (validateProofread). nil = số dòng lệch / đầu ra đáng ngờ.
    static func assembleProofread(original: String, output: String) -> String? {
        let plan = TranslateText.linePlan(original)
        guard !plan.cores.isEmpty else { return nil }
        // Model hay trả cả đoạn trong MỘT mục (vẫn giữ xuống dòng) ⇒ tách mọi mục theo dòng, bỏ
        // dòng trống (dòng trống gốc không gửi đi — ráp lại từ plan), rồi số dòng phải khớp.
        let parts = output.split(separator: listSeparator, omittingEmptySubsequences: false)
            .flatMap { $0.split(whereSeparator: \.isNewline) }
            .map { stripLinePrefix(String($0)).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard parts.count == plan.indices.count else { return nil }
        let fixed = parts.map { stripWrappingQuotes($0, unless: "") }
        guard let joined = TranslateText.assemble(lines: plan.lines, breaks: plan.breaks,
                                                  indices: plan.indices, translated: fixed) else { return nil }
        return validateProofread(original: original, output: joined)
    }

    static let alternativesInstructions = """
    You suggest replacements for one word the user selected in a sentence typed on a phone \
    keyboard (usually Vietnamese, sometimes English). Give up to 3 alternatives that could \
    replace the selected word in THIS sentence with the same meaning: synonyms of the same \
    word type, or the correct spelling / correct Vietnamese tone marks if the word is a typo. \
    Answer in the language of the selected word (never translate it): a Vietnamese word gets \
    Vietnamese alternatives, an English word gets English alternatives. Each alternative is one word or a short phrase of at \
    most 3 words, and must read naturally when put in place of the selected word. Never return \
    the selected word itself. No explanations.
    Example: "Món này ⟦ngon⟧ lắm" → "tuyệt", "hấp dẫn", "ngon miệng"
    Example: "Phòng này ⟦rộng⟧ quá" → "thoáng", "rộng rãi", "to"
    Example: "Gửi mình bản ⟦draft⟧ nhé" → "version", "copy", "outline"
    """

    /// Ngữ cảnh trước từ: tối đa `limit` ký tự cuối, trong cùng đoạn (sau lần xuống dòng cuối),
    /// bỏ mẩu từ bị cắt dở ở đầu.
    static func clipBefore(_ s: String?, limit: Int = contextChars) -> String {
        guard var s = s, !s.isEmpty else { return "" }
        if let nl = s.lastIndex(where: \.isNewline) { s = String(s[s.index(after: nl)...]) }
        guard s.count > limit else { return s }
        var t = Substring(s.suffix(limit))
        if let sp = t.firstIndex(where: \.isWhitespace) { t = t[t.index(after: sp)...] }
        return String(t)
    }

    /// Ngữ cảnh sau từ: tối đa `limit` ký tự đầu, tới lần xuống dòng đầu, bỏ mẩu từ cắt dở ở cuối.
    static func clipAfter(_ s: String?, limit: Int = contextChars) -> String {
        guard var s = s, !s.isEmpty else { return "" }
        if let nl = s.firstIndex(where: \.isNewline) { s = String(s[..<nl]) }
        guard s.count > limit else { return s }
        var t = Substring(s.prefix(limit))
        if let sp = t.lastIndex(where: \.isWhitespace) { t = t[..<sp] }
        return String(t)
    }

    static func alternativesPrompt(word: String, before: String?, after: String?) -> String {
        let b = clipBefore(before), a = clipAfter(after)
        return "Sentence (the selected word is between ⟦ and ⟧):\n\(b)⟦\(word)⟧\(a)\n\nSelected word: \(word)\n"
            + languageHint(word, context: b + a)
    }

    /// Model nhỏ hay dịch từ Việt sang Anh (đo 30/10/2026: "đẹp" → beautiful) ⇒ nói rõ ngôn ngữ.
    /// Có chữ cái mang dấu / đ ⇒ chắc tiếng Việt; toàn ASCII ⇒ để model phân biệt tiếng Anh với
    /// tiếng Việt gõ không dấu.
    static func languageHint(_ word: String, context: String = "") -> String {
        func accented(_ s: String) -> Bool {
            s.precomposedStringWithCanonicalMapping.unicodeScalars.contains { $0.value >= 0xC0 && $0.properties.isAlphabetic }
        }
        if accented(word) { return "The selected word is Vietnamese: answer with Vietnamese words only." }
        if !context.isEmpty, !accented(context), context.contains(where: \.isLetter) {
            return "The sentence is English: answer with English words only."
        }
        return "If the selected word is English, answer in English. If it is Vietnamese typed without tone marks, answer in Vietnamese with correct tone marks."
    }

    // MARK: kiểm kết quả

    /// Ký tự emoji (để bắt model làm rơi / thêm emoji).
    static func isEmojiScalar(_ u: Unicode.Scalar) -> Bool {
        u.properties.isEmojiPresentation || (u.properties.isEmoji && u.value >= 0x2100 && u.value != 0x200D)
    }

    static func emojiSignature(_ s: String) -> [UInt32] {
        s.unicodeScalars.filter(isEmojiScalar).map(\.value).sorted()
    }

    static func newlineCount(_ s: String) -> Int { s.filter(\.isNewline).count }

    /// Kiểm + chuẩn hoá bản sửa của model. nil = bỏ (đầu ra đáng ngờ). Trả về chữ gốc (y nguyên)
    /// nếu model không đổi gì — caller so `==` để báo "không thấy lỗi".
    static func validateProofread(original: String, output: String) -> String? {
        let o = TranslateText.splitWhitespace(original)
        var out = output.trimmingCharacters(in: .whitespacesAndNewlines)
        out = stripWrappingQuotes(out, unless: o.core)
        guard !out.isEmpty, !o.core.isEmpty else { return nil }
        let a = o.core.count, b = out.count
        // Thêm dấu thanh không đổi số ký tự (NFC); sửa chính tả/ngữ pháp chỉ lệch ít.
        guard Double(b) >= Double(a) * 0.7 - 3, Double(b) <= Double(a) * 1.4 + 6 else { return nil }
        let wa = words(o.core).count, wb = words(out).count
        guard Double(wb) >= Double(wa) * 0.6 - 1, Double(wb) <= Double(wa) * 1.5 + 2 else { return nil }
        guard newlineCount(out) == newlineCount(o.core) else { return nil }
        guard emojiSignature(out) == emojiSignature(o.core) else { return nil }
        let fixed = o.lead + out.precomposedStringWithCanonicalMapping + o.trail
        return fixed == original ? original : fixed
    }

    /// Model hay bọc kết quả trong ngoặc kép — bỏ khi chữ gốc không bọc.
    static func stripWrappingQuotes(_ s: String, unless original: String) -> String {
        let pairs: [(Character, Character)] = [("\"", "\""), ("\u{201C}", "\u{201D}"), ("«", "»"), ("'", "'")]
        for (l, r) in pairs where s.count >= 2 && s.first == l && s.last == r {
            if original.first == l && original.last == r { return s }
            return String(s.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return s
    }

    /// Lọc từ thay thế: bỏ trống / trùng / trùng từ gốc / quá dài / nhiều dòng; theo kiểu hoa
    /// của từ gốc (HOA HẾT, Hoa đầu). Tối đa `limit`.
    static func validateAlternatives(word: String, outputs: [String], limit: Int = 3) -> [String] {
        let key = { (s: String) in s.precomposedStringWithCanonicalMapping.lowercased() }
        var seen: Set<String> = [key(word)]
        var out: [String] = []
        let letters = word.filter(\.isLetter)
        let allCaps = letters.count >= 2 && letters.allSatisfy(\.isUppercase)
        let cap = letters.first?.isUppercase == true
        for raw in outputs {
            var s = stripEdgePunctuation(raw.trimmingCharacters(in: .whitespacesAndNewlines))
            s = stripWrappingQuotes(s, unless: "")
            guard !s.isEmpty, s.count <= 40, !s.contains(where: \.isNewline),
                  s.contains(where: \.isLetter),
                  s.split(whereSeparator: \.isWhitespace).count <= 3 else { continue }
            if allCaps { s = s.uppercased() }
            else if cap, let f = s.first, f.isLowercase { s = f.uppercased() + s.dropFirst() }
            s = s.precomposedStringWithCanonicalMapping
            guard seen.insert(key(s)).inserted else { continue }
            out.append(s)
            if out.count == limit { break }
        }
        return out
    }

    /// Vùng chọn sau khi thay từ (giữ khoảng trắng / dấu câu dính quanh từ: "bạn," → "cậu,").
    /// nil khi vùng chọn không còn chứa từ.
    static func replaceWord(in selection: String, word: String, with alt: String) -> String? {
        guard let r = selection.range(of: word) else { return nil }
        return selection.replacingCharacters(in: r, with: alt)
    }

    /// Tách chuỗi danh sách trả từ framework.
    static func splitList(_ s: String) -> [String] {
        s.split(separator: listSeparator, omittingEmptySubsequences: true).map(String.init)
    }
}

// MARK: sửa cả ô (không có vùng chọn)

/// Không chọn gì ⇒ chip "✨ Sửa lỗi" sửa TOÀN BỘ chữ trong ô (trước + sau con trỏ) — chỉ khi ô
/// ngắn và bàn phím chắc chắn thấy HẾT ô. iOS chỉ đưa bàn phím một cửa sổ chữ quanh con trỏ (có
/// host cắt theo đoạn/độ dài) ⇒ trước khi thay, controller dời con trỏ về CUỐI rồi về ĐẦU và đọc
/// lại: cuối phải (trước = cả ô, sau = rỗng), đầu phải (trước = rỗng, sau = cả ô). Không chắc ⇒ bỏ.
enum AIField {
    /// Ô dài hơn thì không mời (xem trước gọn; model trên máy nhanh).
    static let maxChars = 500

    /// Chữ cả ô nếu đủ điều kiện mời: có ≥ 2 từ, ≤ maxChars ký tự. nil = không mời.
    static func eligible(before: String?, after: String?) -> String? {
        let full = (before ?? "") + (after ?? "")
        guard full.count <= maxChars, AIText.words(full).count >= 2 else { return nil }
        return full
    }

    /// So khớp từng scalar (không coi NFC ≡ NFD là một: xoá theo scalar phải đúng y chữ).
    static func same(_ a: String, _ b: String) -> Bool { a.unicodeScalars.elementsEqual(b.unicodeScalars) }

    /// Ô (đọc quanh con trỏ hiện tại) đúng là `expected`.
    static func matches(before: String?, after: String?, expected: String) -> Bool {
        same((before ?? "") + (after ?? ""), expected)
    }

    /// Con trỏ ở CUỐI ô và ô đúng là `expected`.
    static func atEnd(before: String?, after: String?, expected: String) -> Bool {
        (after ?? "").isEmpty && same(before ?? "", expected)
    }

    /// Con trỏ ở ĐẦU ô và ô đúng là `expected`.
    static func atStart(before: String?, after: String?, expected: String) -> Bool {
        (before ?? "").isEmpty && same(after ?? "", expected)
    }

    /// Số lần deleteBackward để xoá sạch `text` khi con trỏ ở cuối ô và ô CHỈ chứa `text`.
    /// Host xoá mỗi lần một Character (👨‍👩‍👧, "ệ") hoặc một scalar (ô NFD, vài web view) — mỗi lần
    /// xoá ít nhất một scalar ⇒ số scalar luôn đủ; lần thừa ở đầu ô không làm gì (đã kiểm ô chỉ
    /// có `text`, con trỏ ở đầu thì không còn gì phía trước).
    static func deleteCount(_ text: String) -> Int { text.unicodeScalars.count }

    /// Bước dời con trỏ tới tận cuối / đầu đoạn `s`: adjustTextPosition có host tính theo
    /// Character, có host theo UTF-16 ⇒ dùng số UTF-16 (≥ số Character); dời quá thì dừng ở mép ô.
    static func caretOffset(_ s: String) -> Int { s.utf16.count }
}

// MARK: so khác theo từ

struct WordDiffSegment: Equatable {
    let text: String
    let changed: Bool
}

enum WordDiff {
    /// Tách thành token: cụm không khoảng trắng (từ, kèm dấu câu dính) và cụm khoảng trắng.
    static func tokenize(_ s: String) -> [String] {
        var out: [String] = []
        var cur = ""
        var curSpace: Bool?
        for c in s {
            let sp = c.isWhitespace
            if curSpace != nil, curSpace != sp { out.append(cur); cur = "" }
            cur.append(c); curSpace = sp
        }
        if !cur.isEmpty { out.append(cur) }
        return out
    }

    /// Đoạn của `corrected`, đánh dấu từ KHÔNG có trong dãy con chung dài nhất (LCS theo từ)
    /// với `original`. Khoảng trắng luôn "không đổi"; đoạn liền nhau cùng cờ được gộp.
    static func diff(original: String, corrected: String) -> [WordDiffSegment] {
        let a = tokenize(original).filter { !$0.allSatisfy(\.isWhitespace) }
        let tb = tokenize(corrected)
        let bIdx = tb.indices.filter { !tb[$0].allSatisfy(\.isWhitespace) }
        let b = bIdx.map { tb[$0] }
        let n = a.count, m = b.count
        // LCS O(n·m) — n, m ≤ ~250 từ (AIText.maxProofreadChars).
        var dp = [[Int]](repeating: [Int](repeating: 0, count: m + 1), count: n + 1)
        if n > 0 && m > 0 {
            for i in stride(from: n - 1, through: 0, by: -1) {
                for j in stride(from: m - 1, through: 0, by: -1) {
                    dp[i][j] = a[i] == b[j] ? dp[i + 1][j + 1] + 1 : max(dp[i + 1][j], dp[i][j + 1])
                }
            }
        }
        var keep = Set<Int>()   // chỉ số trong b thuộc LCS
        var i = 0, j = 0
        while i < n && j < m {
            if a[i] == b[j] { keep.insert(j); i += 1; j += 1 }
            else if dp[i + 1][j] >= dp[i][j + 1] { i += 1 }
            else { j += 1 }
        }
        var changedAt = Set<Int>()   // chỉ số token trong tb
        for (k, t) in bIdx.enumerated() where !keep.contains(k) { changedAt.insert(t) }
        var segs: [WordDiffSegment] = []
        for (k, tok) in tb.enumerated() {
            let ch = changedAt.contains(k)
            if let last = segs.last, last.changed == ch {
                segs[segs.count - 1] = WordDiffSegment(text: last.text + tok, changed: ch)
            } else {
                segs.append(WordDiffSegment(text: tok, changed: ch))
            }
        }
        return segs
    }

    /// Số từ đã sửa (từ của bản sửa không thuộc LCS).
    static func changedWordCount(original: String, corrected: String) -> Int {
        diff(original: original, corrected: corrected).filter(\.changed)
            .map { max(1, AIText.words($0.text).count) }.reduce(0, +)
    }
}

// MARK: kết quả + lỗi

enum AIFailure: Error, Equatable {
    case unavailable, guardrail, tooLong, unsupportedLanguage, timeout, failed
    /// Đầu ra model không qua kiểm (AIText.validate…).
    case rejected

    /// Mã từ IntelligenceEngine (`IntelligenceCode`); 0 (ok) ⇒ nil.
    init?(engineCode: Int32) {
        switch engineCode {
        case 0: return nil
        case 1: self = .unavailable
        case 2: self = .guardrail
        case 3: self = .tooLong
        case 4: self = .unsupportedLanguage
        case 5: self = .timeout
        default: self = .failed
        }
    }

    /// Thông báo ngắn (chip trên thanh gợi ý) — lỗi "êm", không hộp thoại.
    var message: String {
        switch self {
        case .unavailable: return L("✨ Apple Intelligence chưa sẵn sàng")
        case .guardrail: return L("✨ Không sửa được đoạn này")
        case .tooLong: return L("✨ Đoạn quá dài")
        case .unsupportedLanguage: return L("✨ Chưa hỗ trợ ngôn ngữ này")
        case .timeout: return L("✨ Quá lâu — thử lại sau")
        case .failed, .rejected: return L("✨ Không sửa được")
        }
    }
}

/// Đua một việc bất đồng bộ với hạn giờ — trả nil khi quá hạn (việc bị huỷ nhưng có thể vẫn
/// chạy tiếp ngoài tiến trình; kết quả muộn bị bỏ). KHÔNG dùng task group: group chờ mọi con
/// xong mới trả, mà việc gọi qua C callback không biết huỷ ⇒ hạn giờ vô nghĩa. Thuần, test bằng
/// việc giả.
enum AITimeout {
    final class OneShot<T>: @unchecked Sendable {
        private let lock = NSLock()
        private var cont: CheckedContinuation<T, Never>?
        private var pending: T??
        func attach(_ c: CheckedContinuation<T, Never>) {
            lock.lock()
            if let p = pending { lock.unlock(); c.resume(returning: p!); return }
            cont = c
            lock.unlock()
        }
        /// true nếu đây là lần trả đầu tiên.
        @discardableResult
        func resume(_ v: T) -> Bool {
            lock.lock()
            if pending != nil { lock.unlock(); return false }
            pending = .some(v)
            let c = cont; cont = nil
            lock.unlock()
            c?.resume(returning: v)
            return true
        }
    }

    static func race<T: Sendable>(seconds: TimeInterval,
                                  _ op: @escaping @Sendable () async -> T) async -> T? {
        let box = OneShot<T?>()
        let work = Task { box.resume(await op()) }
        let timer = Task {
            try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
            if !Task.isCancelled, box.resume(nil) { work.cancel() }
        }
        let r = await withCheckedContinuation { box.attach($0) }
        timer.cancel()
        return r
    }
}
