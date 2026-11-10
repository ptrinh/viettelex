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

/// Xếp hạng thanh gợi ý — logic THUẦN (song sinh android SuggestRank trong
/// SuggestionSupport.kt; sửa ở đây thì sửa y hệt bên kia). Hợp đồng: docs/IOS-SUGGESTIONS.md
/// (tầng 1, 2, 7).
///
/// Inline (đang gõ dở): `ln(freq+1) + 2.5·ln(count+1) + 4·[trong nextWords] + 1.5·[chỉ thiếu dấu]
/// + LM`, LM = min(cap, weight·PMI(ngữ cảnh → ứng viên)) — nhân `bigramDamp` khi UserLangModel
/// đã có ý kiến về chính lượt này (một ứng viên nằm trong nextWords): khi đó cap·damp = 3.96 < 4
/// ⇒ ứng viên trong nextWords luôn hơn ứng viên chỉ có LM (còn lại ngang nhau) — cá nhân thắng.
/// Không ứng viên nào trong nextWords (người dùng mới, prev lạ) ⇒ LM đủ mạnh. PMI: có dòng
/// trigram (prev2, prev) và ứng viên có mục trigram ⇒ PMI trigram, không thì bigram.
///
/// Từ kế tiếp (sau dấu cách, `nextFill`): có dòng trigram (prev2, prev) ⇒ từ người dùng đã gõ
/// ĐÚNG bộ ba này (≥ `learnedTriMin` lượt) trước, rồi top trigram tĩnh, rồi nextWords cá nhân/seed;
/// không có ⇒ như cũ: nextWords cá nhân/seed trước, thiếu thì lấp bằng top bigram tĩnh.
/// Điểm tĩnh = PMI + nextFreqWeight·freq/255 (PMI thuần nghiêng về cặp hiếm). vnlm.bin =
/// SyllableLM (vnbigram.bin cũ đã bỏ 28/09/2026).
enum SuggestRank {
    struct Params {
        var bigramWeight = SuggestRank.bigramWeight
        var bigramCap = SuggestRank.bigramCap
        var bigramDamp = SuggestRank.bigramDamp
        var nextFreqWeight = SuggestRank.nextFreqWeight
        /// false ⇒ chỉ bigram (như trước 28/09/2026 — đo so sánh).
        var useTrigram = true
        var learnedTriMin = SuggestRank.learnedTriMin
        var triOnlyRow = SuggestRank.triOnlyRow
    }

    // chọn trên heldout (27/09/2026, lưới trong android SuggestBigramTests.tuneGrid); cap·damp < 4.
    // 28/09/2026 chuyển sang bigram của vnlm.bin: nextFreqWeight 12 → 10. Cùng ngày thêm trigram
    // (android SuggestTrigramTests.tuneDev, tập DEV suggest-dev.txt): w 2.5 → 3, cap 8 → 12,
    // damp 0.45 → 0.33.
    static let bigramWeight = 3.0
    static let bigramCap = 12.0
    static let bigramDamp = 0.33
    static let nextFreqWeight = 10.0
    static let learnedTriMin = 2
    /// Dòng trigram ≥ chừng này mục ⇒ top từ kế tiếp chỉ lấy từ nó (khỏi duyệt cả dòng bigram).
    static let triOnlyRow = 6

    /// Xếp pool VNSuggest (chưa lọc nhạy cảm). `pmi[i]` = PMI của `pool[i]` (nil = không có âm
    /// tiết trước / bảng). Hoà điểm giữ thứ tự pool (tần suất tĩnh) — Kotlin y hệt.
    static func rankInline(_ pool: [VNSuggest.Match], pmi: [Float]?, typedLen: Int,
                           count: (String) -> Int, ctx: Set<String>, _ p: Params = Params()) -> [String] {
        let damp = pool.contains { ctx.contains($0.word) } ? p.bigramDamp : 1
        var scored: [(Int, Double)] = []
        scored.reserveCapacity(pool.count)
        for (i, m) in pool.enumerated() {
            var b = 0.0
            if let pmi, i < pmi.count, pmi[i] > 0 { b = min(p.bigramCap, p.bigramWeight * Double(pmi[i])) * damp }
            let s = log(Double(m.freq) + 1) + 2.5 * log(Double(count(m.word)) + 1)
                + (ctx.contains(m.word) ? 4 : 0) + (m.word.count == typedLen ? 1.5 : 0) + b
            scored.append((i, s))
        }
        return scored.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }.map { pool[$0.0].word }
    }

    /// PMI (vnlm.bin, chỉ mục tường minh — thiếu = 0) của từng ứng viên sau (`prev2`, `prev`):
    /// mục trigram nếu có, không thì mục bigram (nil nếu prev không có dòng bigram). Chạy nền.
    static func inlinePmi(_ pool: [VNSuggest.Match], prev: String?, prev2: String? = nil,
                          lm: SyllableLM? = SyllableLM.shared, _ p: Params = Params()) -> [Float]? {
        guard let prev, let lm, !pool.isEmpty, let id = VNSuggest.lexiconId(of: prev) else { return nil }
        let id2 = p.useTrigram ? prev2.flatMap { VNSuggest.lexiconId(of: $0) } ?? -1 : -1
        guard let ctx = lm.context(prev2: id2, prev1: id), ctx.bigramSize > 0 else { return nil }
        return ctx.explicitAll(pool.map(\.id))
    }

    /// Top `limit` âm tiết hay theo sau `prev` theo bigram tĩnh vnlm.bin (chữ thường, dạng lexicon).
    static func bigramNext(_ prev: String, limit: Int, lm: SyllableLM? = SyllableLM.shared,
                           _ p: Params = Params()) -> [String] {
        contextNext(prev, prev2: nil, limit: limit, lm: lm, p)
    }

    /// Top `limit` âm tiết sau (`prev2`, `prev`) theo vnlm.bin: có dòng trigram (prev2, prev) ⇒
    /// chấm bằng trigram (KN lùi bigram cho mục chỉ có ở bigram — `SyllableLM.Context.forEachNext`),
    /// không thì bigram như `bigramNext`.
    static func contextNext(_ prev: String, prev2: String?, limit: Int, lm: SyllableLM? = SyllableLM.shared,
                            _ p: Params = Params()) -> [String] {
        topNext(prev, prev2: prev2, limit: limit, lm: lm, p)?.words ?? []
    }

    /// Từ kế tiếp sau dấu cách (≤ `need`, CHƯA đệm topWords). `personal` = nextWords cá nhân/seed
    /// đã lọc nhạy cảm (≤ 6), `triCount` = số lượt người dùng gõ (prev2, prev → w), `filter` lọc
    /// nhạy cảm cho phần tĩnh. `need` = số ô ("Số từ gợi ý", mặc định 3 — hành vi cũ).
    /// `chain` = chuỗi seed ba từ sau (`prev2`, `prev`) ĐÃ lọc (SensitiveWords.chain + filter) — đứng
    /// ngay sau bộ ba người dùng đã gõ, trước trigram tĩnh / cá nhân.
    static func nextFill(_ prev: String, prev2: String?, personal: [String], triCount: (String) -> Int,
                         filter: ([String]) -> [String] = { $0 }, need: Int = 3, chain: [String] = [],
                         lm: SyllableLM? = SyllableLM.shared, _ p: Params = Params()) -> [String] {
        let limit = max(6, need + 3)
        let tri = prev2 != nil && p.useTrigram ? topNext(prev, prev2: prev2, limit: limit, lm: lm, p) : nil
        if let tri, tri.trigram {
            let learned = Array(personal.filter { triCount($0) >= p.learnedTriMin }.prefix(min(2, need)))
            return SuggestionFill.pad(learned, with: chain + filter(tri.words) + personal, need: need)
        }
        let base = chain.isEmpty ? Array(personal.prefix(need)) : SuggestionFill.pad(chain, with: personal, need: need)
        if base.count >= need { return base }
        return SuggestionFill.pad(base, with: filter(tri?.words ?? bigramNext(prev, limit: limit, lm: lm, p)), need: need)
    }

    /// #146: có đệm ô trống của "từ kế tiếp" bằng từ phổ biến nhất (topWords / SwipeEnglish.top)
    /// không. Đệm chung chung chỉ hợp lý khi chưa có từ trước (`prev` nil — đầu ô) hoặc từ trước
    /// là âm tiết Việt. Từ trước là tiếng Anh (`english` = đang ở chế độ Tiếng Anh, hoặc từ Anh
    /// không phải âm tiết Việt giữa câu Việt — "they") ⇒ KHÔNG đệm: "they" → "the of and" (top
    /// unigram) là gợi ý sai; chỉ còn bằng chứng ngữ cảnh thật (cặp cá nhân / seed).
    /// `isEnglish`/`isVietSyllable` nhận từ chữ thường; chỉ gọi khi cần (ít ô hơn cần). Android y hệt.
    /// Hỏi âm tiết Việt TRƯỚC (10/11/2026): `V || !E` ≡ `!E || V` (hai hàm thuần), nhưng từ trước là
    /// âm tiết Việt — trường hợp thường gặp — thì không bao giờ chạm lexicon tiếng Anh.
    /// Không mặc định `SwipeEnglish.contains`: file này còn biên dịch ở chỗ không có SwipeEnglish
    /// (windows/app/tools/gen_prediction_golden.sh) — caller truyền vào.
    static func padsWithTopWords(_ prev: String?, english: Bool,
                                 isEnglish: (String) -> Bool,
                                 isVietSyllable: (String) -> Bool = { VNSuggest.lexiconId(of: $0) != nil }) -> Bool {
        guard let prev else { return true }
        if english { return false }
        let low = prev.lowercased()
        return isVietSyllable(low) || !isEnglish(low)
    }

    /// Ô "từ kế tiếp" sau từ tiếng Anh khi `padsWithTopWords` = false: `base` (cặp cá nhân) trước,
    /// rồi `table` (= EnglishNext.next(after: prev), bảng Tatoeba) chưa có — KHÔNG đệm top unigram
    /// (the/of/and). `filter` = SensitiveWords, `display` = hoa/thường hiển thị. Android y hệt.
    /// Bảng truyền vào (không gọi EnglishNext ở đây): file này còn biên dịch ở chỗ không có nó.
    static func englishNextFill(_ base: [String], table: [String], need: Int, typed: String = "",
                                filter: ([String]) -> [String] = { $0 },
                                display: (String) -> String = { $0 }) -> [String] {
        if base.count >= need || table.isEmpty { return Array(base.prefix(need)) }
        return SuggestionFill.pad(base, with: filter(table).map(display), need: need, excluding: typed)
    }

    /// Kết quả `topNext`: id (điểm giảm dần) + điểm; `trigram` = chấm bằng dòng trigram.
    struct Top {
        var ids: [Int], scores: [Double]
        let trigram: Bool
        var words: [String] { ids.map { VNSuggest.display($0) } }
    }

    /// Top `limit` (id, điểm) sau (`prev2`, `prev`) — nil nếu không có dữ liệu. Chèn vào mảng cỡ
    /// limit, không sort.
    static func topNext(_ prev: String, prev2: String?, limit: Int, lm: SyllableLM? = SyllableLM.shared,
                        _ p: Params = Params()) -> Top? {
        guard let lm, limit > 0, let pid = VNSuggest.lexiconId(of: prev) else { return nil }
        let ctx = p.useTrigram ? prev2.flatMap { VNSuggest.lexiconId(of: $0) }
            .flatMap { lm.context(prev2: $0, prev1: pid) } : nil
        let tri = ctx?.hasTrigram == true
        var ids = [Int](repeating: 0, count: limit), sc = [Double](repeating: 0, count: limit), n = 0
        let fw = p.nextFreqWeight / 255
        func push(_ id: Int, _ pmi: Float) {
            let s = Double(pmi) + fw * Double(VNSuggest.freq(id: id))
            if n == limit && s <= sc[n - 1] { return }
            var j: Int
            if n < limit { j = n; n += 1 } else { j = n - 1 }
            while j > 0 && sc[j - 1] < s { sc[j] = sc[j - 1]; ids[j] = ids[j - 1]; j -= 1 }
            sc[j] = s; ids[j] = id
        }
        if let ctx, tri {
            // dòng trigram đủ dài ⇒ chỉ nó (bỏ duyệt cả dòng bigram prev — dòng "của"/"và" hàng
            // nghìn mục); ngắn ⇒ trộn đủ hai dòng (KN lùi γ3 + s2)
            if ctx.forEachTrigram(push) < p.triOnlyRow {
                n = 0
                ctx.forEachNext(push)
            }
        } else {
            let row = lm.bigram(pid)
            guard row.size > 0 else { return nil }
            row.forEach(push)
        }
        guard n > 0 else { return nil }
        return Top(ids: Array(ids.prefix(n)), scores: Array(sc.prefix(n)), trigram: tri)
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

/// "Tự thêm dấu cách sau dấu câu" (autoSpaceAfterPunct, mặc định TẮT). Phần THUẦN — bản
/// Kotlin song sinh: android/keyboard/.../SuggestionSupport.kt (AutoSpace), test hai bên
/// cùng số liệu. Controller: sau phím . , ? ! ; : chèn " " và nhớ lại; phím kế là dấu cách
/// ⇒ nuốt, ⌫ ⇒ chỉ xoá dấu cách tự thêm, dấu câu / "/" / xuống dòng ⇒ gỡ dấu cách trước
/// nó, ngoặc/nháy đóng ⇒ gỡ rồi dời dấu cách ra sau ngoặc ("hi." + ")" → "hi.) ").
enum AutoSpace {
    static let triggers: Set<Character> = [".", ",", "?", "!", ";", ":"]
    static let closers: Set<Character> = [")", "]", "}", "\"", "'", "”", "’", "»", "›"]

    enum Reaction: Equatable {
        /// Không đụng dấu cách tự thêm.
        case keep
        /// Gỡ dấu cách tự thêm rồi xử lý phím như thường.
        case remove
        /// Gỡ, chèn ký tự, rồi thêm lại dấu cách sau nó.
        case carry
    }

    /// Phím chèn chữ `s` ngay sau dấu cách tự thêm.
    static func reaction(toText s: String) -> Reaction {
        guard s.count == 1, let c = s.first else { return .keep }
        if closers.contains(c) { return .carry }
        if triggers.contains(c) || c == "/" { return .remove }
        return .keep
    }

    /// Vừa chèn `punct`: có thêm dấu cách không. `before` = chữ trước con trỏ SAU khi chèn
    /// (phải kết thúc bằng `punct`), `after` = chữ sau con trỏ (nil = không đọc được).
    static func shouldAdd(punct: String, before: String, after: String?) -> Bool {
        guard punct.count == 1, let p = punct.first, triggers.contains(p),
              before.last == p else { return false }
        // Đã có khoảng trắng / dấu câu / ngoặc đóng ngay sau con trỏ (sửa giữa câu).
        if let a = after?.first, a.isWhitespace || triggers.contains(a) || closers.contains(a) { return false }
        let token = before.dropLast().split(omittingEmptySubsequences: false,
                                            whereSeparator: { $0.isWhitespace }).last ?? ""
        guard let prev = token.last else { return false }          // dấu câu đứng riêng (" :)")
        if prev.isNumber, p == "." || p == "," || p == ":" { return false }   // 3.5 · 1,000 · 10:30
        if token.contains("@") || token.contains("/") { return false }        // email, URL, đường dẫn
        return !looksLikeDomain(token)
    }

    /// Dấu hút dấu cách của gợi ý vừa nhận: kết câu, ngoặc đóng, nháy đóng. Không ":" ";".
    static let suggestionSnappers: Set<Character> = [".", ",", "?", "!", ")", "\"", "”", "’", "»"]

    /// Vừa nhận gợi ý (chèn `inserted` = "từ " — dấu cách là của CHÍNH gợi ý): phím kế chèn `s`
    /// có xoá dấu cách đó không ("từ ." → "từ."), như bàn phím iOS gốc. `before` = chữ trước con
    /// trỏ, phải còn kết thúc bằng `inserted` (con trỏ chưa dời; nil ⇒ không). `"` thẳng chỉ khi
    /// là nháy ĐÓNG (số `"` trong dòng đang lẻ). Song sinh Android AutoSpace.snapsSuggestionSpace.
    static func snapsSuggestionSpace(_ s: String, before: String?, inserted: String) -> Bool {
        guard s.count == 1, let c = s.first, suggestionSnappers.contains(c),
              inserted.count > 1, inserted.last == " ",
              let b = before, b.unicodeScalars.reversed().starts(with: inserted.unicodeScalars.reversed())
        else { return false }
        if c == "\"" {
            let line = b.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" }).last ?? ""
            return line.filter { $0 == "\"" }.count % 2 == 1
        }
        return true
    }

    /// "www.google", "vnexpress.net", "a.b-c.io": các đoạn giữa dấu chấm đều là chữ/số/-,
    /// đoạn cuối ≥ 2 ký tự. "e.g", "U.S", "hi.." thì không.
    static func looksLikeDomain(_ token: Substring) -> Bool {
        if token.lowercased().hasPrefix("www") { return true }
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2, let last = parts.last, last.count >= 2 else { return false }
        return parts.allSatisfy { !$0.isEmpty && $0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" } }
    }
}

#if canImport(UIKit)
/// ONBOARDING-SPEC §8 — tô nền gợi ý sửa khi gõ sai (THUẦN, song sinh Android CorrectionHint): ô 1 =
/// chữ gốc `typed` (ngoặc kép — SuggestionSlots.arrange), ô giữa = `fix` tô nền (đúng chữ dấu cách sẽ
/// áp), ô còn lại = ứng viên kế (đang có trên thanh, bỏ trùng). Không emoji: ô cuối dành cho ứng viên.
/// Chỉ sắp lại ứng viên ĐÃ tính cho thanh gợi ý — không tính thêm gì.
enum CorrectionHint {
    /// `need`: số ô ứng viên (= "Số từ gợi ý" − 1, ô nguyên văn đã trừ).
    static func apply(_ set: inout KeyboardView.SuggestionSet, typed: String, fix: String, need: Int) {
        var seen = Set([fix.lowercased(), typed.lowercased()])
        var words = [fix]
        for w in [set.word, set.word2].compactMap({ $0 }) + set.moreWords where seen.insert(w.lowercased()).inserted {
            words.append(w)
        }
        words = Array(words.prefix(max(need, 1)))
        set.literal = typed
        set.word = fix
        set.word2 = words.count > 1 ? words[1] : nil
        set.moreWords = Array(words.dropFirst(2))
        set.emojis = []
        set.correction = true
    }
}
#endif
