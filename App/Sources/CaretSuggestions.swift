// CaretSuggestions.swift — ba loại gợi ý cạnh con trỏ nữa cho macOS (maintainer 28/09/2026),
// dùng CHUNG ô gợi ý + luật của CaretHint (MathHint.swift): chỉ hiện khi rất chắc; chỉ áp
// dụng bằng Tab (hoặc click ô ứng viên); không bao giờ tự thay; đọc lại màn hình trước khi
// thay (như gõ tắt / chip số); không chạy ở ô mật khẩu; phím thường không tốn gì ngoài
// điểm kích hoạt (ranh giới từ).
//
//  1. SỬA LỖI GÕ SAI (mặc định BẬT) — ranh giới từ (dấu cách , ; ! ? ")"): từ vừa gõ không
//     là âm tiết Việt / tiếng Anh / từ chat ⇒ thay ĐÚNG MỘT phím bằng phím KỀ trên bàn phím
//     cứng (AdjacentKeyFixer.oneEditCandidates + physicalNeighbors) hoặc đảo hai phím liền
//     nhau; chỉ gợi ý khi ứng viên rất phổ biến VÀ bỏ xa ứng viên thứ hai. Không có điểm chạm
//     như iOS nên ngưỡng dò riêng cho Mac (TypoFixEvalTests — mô phỏng lỗi gõ phím cứng trên
//     câu heldout + tập giữ nguyên tiếng Anh/chat/từ lạ/không dấu): xem `TypoFixLogic.defaults`.
//     Tab thay từ, GIỮ ký tự ranh giới. Esc = "đừng gợi ý từ này nữa" (trong phiên).
//  2. THÊM DẤU CHO CÂU KHÔNG DẤU (mặc định TẮT) — ≥3 âm tiết không dấu hợp lệ liên tiếp,
//     kích hoạt: ". ! ?" ngay sau cụm, HOẶC dừng gõ `pauseDelay` giây sau một dấu cách (người
//     gõ chat không chấm câu; khi đang gõ liền mạch thì không bao giờ bật lên giữa chừng).
//     KHÔNG kích hoạt ở Enter (Enter có thể đã gửi tin). Tính trong PROCESS CON Thêm dấu có sẵn
//     (TextActionTransform.addTonesViaHelper — dữ liệu ~1 MB không vào process IME), ngoài
//     main; gõ tiếp là huỷ (thế hệ phím). Tab thay cả cụm.
//  3. NGÀY GIỜ (mặc định BẬT) — "hôm nay␣" / "ngày mai␣" / "hôm qua␣" ⇒ "28/09/2026";
//     "bây giờ␣" ⇒ "21:35"; tiếng Anh (today/tomorrow/yesterday/now) chỉ khi từ trước là
//     tiếng Anh ("see you tomorrow␣"). Tab THAY cụm bằng ngày/giờ (ví dụ maintainer: gõ
//     "hôm nay" → gợi ý "28/09/2026"); muốn giữ chữ thì Esc / gõ tiếp. Âm lịch hôm nay
//     (lịch Việt Nam, UTC+7 — LunarCalendar.swift): "âm lịch␣" / "ngày âm␣" / "ÂL␣" ⇒
//     "30/9 năm Bính Ngọ" (tháng nhuận: "1/6 nhuận năm Ất Tỵ").
import Foundation
import TelexCore

// MARK: - Tiếng Anh nhẹ (không giải mã enlexicon ra [String])

/// Tra enlexicon.bin trực tiếp trên mmap: chỉ giữ bảng offset (4 byte/từ, ~80 KB) thay vì
/// SwipeEnglish.lexicon (~1 MB heap mảng String + khoá vuốt). Cùng nội dung — test so khớp.
enum EnglishLite {
    private static let table: (data: Data, offsets: [UInt32])? = {
        final class BundleToken {}
        guard let url = Bundle(for: BundleToken.self).url(forResource: "enlexicon", withExtension: "bin"),
              let d = try? Data(contentsOf: url, options: .alwaysMapped) else { return nil }
        return d.withUnsafeBytes { raw -> (Data, [UInt32])? in
            let b = raw.bindMemory(to: UInt8.self)
            guard b.count >= 8, b[0] == 0x56, b[1] == 0x54, b[2] == 0x45, b[3] == 0x31 else { return nil }
            let n = Int(b[4]) | Int(b[5]) << 8 | Int(b[6]) << 16 | Int(b[7]) << 24
            var offs = [UInt32](); offs.reserveCapacity(n)
            var p = 8
            for _ in 0..<n {
                guard p + 2 <= b.count else { return nil }
                let len = Int(b[p])
                guard len > 0, p + 2 + len <= b.count else { return nil }
                offs.append(UInt32(p)); p += 2 + len
            }
            return (d, offs)
        }
    }()

    static var count: Int { table?.offsets.count ?? 0 }

    /// Từ chữ thường a–z có trong enlexicon không (binary search theo byte).
    static func contains(_ word: String) -> Bool { frequency(of: word) != nil }

    /// Tần suất (0–255, cùng thang vnlexicon) của từ chữ thường a–z; nil = không có.
    static func frequency(of word: String) -> Int? {
        guard let t = table, !word.isEmpty else { return nil }
        let w = Array(word.utf8)
        return t.data.withUnsafeBytes { raw -> Int? in
            let b = raw.bindMemory(to: UInt8.self)
            func cmp(_ i: Int) -> Int {       // entry i so với w: -1 <, 0 =, 1 >
                let p = Int(t.offsets[i]), len = Int(b[p])
                let m = min(len, w.count)
                for k in 0..<m where b[p + 2 + k] != w[k] { return b[p + 2 + k] < w[k] ? -1 : 1 }
                return len == w.count ? 0 : (len < w.count ? -1 : 1)
            }
            var lo = 0, hi = t.offsets.count
            while lo < hi {
                let mid = (lo + hi) / 2
                let c = cmp(mid)
                if c == 0 { return Int(b[Int(t.offsets[mid]) + 1]) }
                if c < 0 { lo = mid + 1 } else { hi = mid }
            }
            return nil
        }
    }

    /// Từ bắt đầu bằng `typed` (a–z, không phân biệt hoa thường), tần suất giảm dần, tối đa
    /// `limit`, bỏ chính từ đang gõ, chữ hoa theo chữ đang gõ — CÙNG kết quả với
    /// SwipeEnglish.completions (test so khớp) nhưng đọc thẳng trên mmap, không giải mã
    /// lexicon ra heap (gợi ý từ — WordPrediction.swift).
    static func completions(_ typed: String, limit: Int = 24) -> [VNSuggest.Match] {
        let low = typed.lowercased()
        guard let t = table, !low.isEmpty, limit > 0,
              low.unicodeScalars.allSatisfy({ $0.value >= 97 && $0.value <= 122 }) else { return [] }
        let w = Array(low.utf8)
        return t.data.withUnsafeBytes { raw -> [VNSuggest.Match] in
            let b = raw.bindMemory(to: UInt8.self)
            func less(_ i: Int) -> Bool {          // entry i < w (theo byte)
                let p = Int(t.offsets[i]), len = Int(b[p])
                let m = min(len, w.count)
                for k in 0..<m where b[p + 2 + k] != w[k] { return b[p + 2 + k] < w[k] }
                return len < w.count
            }
            func hasPrefix(_ i: Int) -> (prefix: Bool, exact: Bool) {
                let p = Int(t.offsets[i]), len = Int(b[p])
                guard len >= w.count else { return (false, false) }
                for k in 0..<w.count where b[p + 2 + k] != w[k] { return (false, false) }
                return (true, len == w.count)
            }
            var lo = 0, hi = t.offsets.count
            while lo < hi {
                let mid = (lo + hi) / 2
                if less(mid) { lo = mid + 1 } else { hi = mid }
            }
            var hits: [(f: UInt8, i: Int)] = []
            var i = lo
            while i < t.offsets.count {
                let h = hasPrefix(i)
                guard h.prefix else { break }
                if !h.exact { hits.append((b[Int(t.offsets[i]) + 1], i)) }
                i += 1
            }
            hits.sort { $0.f != $1.f ? $0.f > $1.f : $0.i < $1.i }
            return hits.prefix(limit).map { h in
                let p = Int(t.offsets[h.i]), len = Int(b[p])
                let word = String(decoding: UnsafeBufferPointer(rebasing: b[(p + 2)..<(p + 2 + len)]), as: UTF8.self)
                return VNSuggest.Match(word: SwipeEnglish.matchCase(word, typed), freq: Int(h.f))
            }
        }
    }
}

// MARK: - 1. Sửa lỗi gõ sai

enum TypoFixLogic {
    /// Loại sửa MỘT lỗi: thay phím kề / đảo hai phím liền nhau / bỏ phím thừa / thêm phím sót.
    enum Edit: Equatable, CaseIterable { case sub, swap, del, ins }

    struct Cand: Equatable {
        let word: String
        let freq: Int
        let edit: Edit
    }

    /// `minFreq`: tần suất lexicon (0–255) tối thiểu của ứng viên; `margin`: hơn ứng viên thứ
    /// hai (mọi loại sửa đang bật) ít nhất bấy nhiêu; `edits`: loại sửa được đề xuất.
    struct Params: Equatable {
        var minLen: Int
        var minFreq: Int
        var margin: Int
        var edits: Set<Edit>
        var rivals: Set<Edit> = []
    }

    /// Dò trên DEV bằng TypoFixEvalTests (28/09/2026): đề xuất thay-phím-kề + đảo phím, bỏ/thêm
    /// phím chỉ làm ĐỐI THỦ (đề xuất cả chúng không tăng recall ở cùng precision); lưới
    /// minFreq 110–210 × margin 0–120 — đây là điểm P cao nhất còn giữ R (DEV P 98.5% R 17.6%).
    static let defaults = Params(minLen: 3, minFreq: 150, margin: 80, edits: [.sub, .swap], rivals: [.del, .ins])

    /// Điểm kích hoạt (rẻ, không tra lexicon): ranh giới sửa được (dấu cách , ; ! ? ")" — không
    /// "." : ' vì tên miền/giờ/"don't"), phím thô 3–10 chữ a–z, chữ trên màn hình toàn chữ cái
    /// và KHÔNG là âm tiết Việt hợp lệ.
    static func worthChecking(boundary: String?, raw: String, word: String, minLen: Int = defaults.minLen) -> Bool {
        guard let b = boundary, AutoCorrect.triggers(b),
              (minLen...10).contains(raw.count),
              raw.unicodeScalars.allSatisfy({ ($0.value | 0x20) >= 97 && ($0.value | 0x20) <= 122 }),
              !word.isEmpty, word.allSatisfy(\.isLetter) else { return false }
        return !SyllableValidator.isValidSyllable(word)
    }

    private static let letters = Array("abcdefghijklmnopqrstuvwxyz")

    /// Mọi ứng viên MỘT sửa ra từ có trong lexicon (khác chữ hiện tại). Thay phím chỉ bằng phím
    /// KỀ trên bàn phím cứng (AdjacentKeyFixer.oneEditCandidates + physicalNeighbors).
    static func candidates(_ lower: String, compose: (String) -> String, frequency: (String) -> Int?,
                           hasCompletion: (String) -> Bool, edits: Set<Edit> = Set(Edit.allCases)) -> [Cand] {
        var out: [Cand] = []
        if edits.contains(.sub) {
            out += AdjacentKeyFixer.oneEditCandidates(lower, compose: compose, frequency: frequency,
                                                      hasCompletion: hasCompletion,
                                                      neighbors: AdjacentKeyFixer.physicalNeighbors)
                .map { Cand(word: $0.word, freq: $0.freq, edit: .sub) }
        }
        let c0 = Array(lower), current = compose(lower)
        func consider(_ c: [Character], _ e: Edit) {
            let w = compose(String(c))
            guard w != current, let f = frequency(w) else { return }
            out.append(Cand(word: w, freq: f, edit: e))
        }
        if edits.contains(.swap) {
            for i in 0..<max(0, c0.count - 1) where c0[i] != c0[i + 1] {
                var c = c0; c.swapAt(i, i + 1); consider(c, .swap)
            }
        }
        if edits.contains(.del), c0.count > 2 {
            for i in c0.indices where i == 0 || c0[i] != c0[i - 1] {   // bỏ một trong hai chữ lặp = như nhau
                var c = c0; c.remove(at: i); consider(c, .del)
            }
        }
        if edits.contains(.ins), c0.count < 10 {
            for i in 0...c0.count {
                for l in letters where i == 0 || c0[i - 1] != l {        // chèn sau chữ giống hệt = chèn trước nó
                    var c = c0; c.insert(l, at: i); consider(c, .ins)
                }
            }
        }
        return out
    }

    /// Ứng viên đủ chắc: từ đứng đầu (theo tần suất) phải đến từ một loại sửa trong `p.edits`,
    /// phổ biến (≥ minFreq) và hơn từ thứ hai ≥ margin — từ thứ hai tính trong `edits ∪ rivals`
    /// (loại sửa không đề xuất vẫn là đối thủ: "tooik" có thể là "tôi" + phím thừa). nil = không.
    static func pick(_ cands: [Cand], p: Params = defaults) -> Cand? {
        var best: [String: Cand] = [:]
        var proposable: Set<String> = []
        for c in cands where p.edits.contains(c.edit) || p.rivals.contains(c.edit) {
            if p.edits.contains(c.edit) { proposable.insert(c.word) }
            if let b = best[c.word], b.freq >= c.freq { continue }
            best[c.word] = c
        }
        let sorted = best.values.sorted { $0.freq != $1.freq ? $0.freq > $1.freq : $0.word < $1.word }
        guard let top = sorted.first, proposable.contains(top.word), top.freq >= p.minFreq else { return nil }
        if sorted.count > 1, top.freq - sorted[1].freq < p.margin { return nil }
        return top
    }

    // MARK: Tiếng Anh ("spellnig" → spelling — Phil 16/10/2026)

    /// Sửa tiếng Anh: chỉ khi KHÔNG có bản sửa tiếng Việt. Ứng viên MỘT sửa trên PHÍM THÔ (không
    /// qua Telex) có trong enlexicon: thay phím kề / đảo hai phím liền nhau luôn được đề xuất;
    /// bỏ phím thừa / thêm phím sót chỉ đề xuất khi từ ≥ `insDelMinLen` chữ (ngắn hơn: đối thủ).
    /// Ứng viên tiếng Việt (mọi loại sửa) là ĐỐI THỦ — hai lexicon cùng thang tần suất 0–255.
    /// Dò bằng TypoFixEvalTests.testEnglishTuneGridOnDev (câu Anh Tatoeba DEV).
    /// Từ dài (≥ `longMinLen` chữ) hiếm khi cách một từ thật đúng MỘT sửa một cách tình cờ ⇒ ngưỡng
    /// tần suất riêng, thấp hơn (`longMinFreq`: "spellnig" → spelling, tần suất 99).
    struct EnglishParams: Equatable {
        var minFreq: Int
        var margin: Int
        var insDelMinLen: Int
        var longMinLen: Int = 99
        var longMinFreq: Int = 255
    }

    // 18/10/2026 (tần suất vnlexicon corpus hội thoại — đối thủ Việt mạnh lên): minFreq 140 → 135 giữ recall DEV
    // (35,9 → 36,0 %; 140: 35,4 %), oan trên tập giữ nguyên 20 → 14, EN P 95,4 → 95,2 %.
    static let englishDefaults = EnglishParams(minFreq: 135, margin: 60, insDelMinLen: 5, longMinLen: 7, longMinFreq: 60)

    /// Mọi chuỗi MỘT sửa của `lower` (a–z) có trong enlexicon (`frequency`), khác chính nó.
    static func englishCandidates(_ lower: String, frequency: (String) -> Int?) -> [Cand] {
        let c0 = Array(lower)
        var out: [Cand] = []
        func consider(_ c: [Character], _ e: Edit) {
            let w = String(c)
            guard w != lower, let f = frequency(w) else { return }
            out.append(Cand(word: w, freq: f, edit: e))
        }
        for i in c0.indices {
            for n in AdjacentKeyFixer.physicalNeighbors[c0[i]] ?? [] where n != c0[i] {
                var c = c0; c[i] = n; consider(c, .sub)
            }
        }
        for i in 0..<max(0, c0.count - 1) where c0[i] != c0[i + 1] {
            var c = c0; c.swapAt(i, i + 1); consider(c, .swap)
        }
        if c0.count > 2 {
            for i in c0.indices where i == 0 || c0[i] != c0[i - 1] {
                var c = c0; c.remove(at: i); consider(c, .del)
            }
        }
        for i in 0...c0.count {
            for l in letters where i == 0 || c0[i - 1] != l {
                var c = c0; c.insert(l, at: i); consider(c, .ins)
            }
        }
        return out
    }

    /// Từ tiếng Anh đứng đầu (theo tần suất) trong `en` ∪ `rivals` (tiếng Việt), nếu đề xuất
    /// được, phổ biến (≥ minFreq) và hơn từ thứ hai ≥ margin. nil = không.
    static func englishPick(_ en: [Cand], rivals: [Cand], typedLen: Int,
                            p: EnglishParams = englishDefaults) -> Cand? {
        var best: [String: Cand] = [:]
        var proposable: Set<String> = []
        let insDel = typedLen >= p.insDelMinLen
        for c in en {
            if c.edit == .sub || c.edit == .swap || insDel { proposable.insert(c.word) }
            if let b = best[c.word], b.freq >= c.freq { continue }
            best[c.word] = c
        }
        for c in rivals {
            if let b = best[c.word], b.freq >= c.freq { continue }
            best[c.word] = c
        }
        let sorted = best.values.sorted { $0.freq != $1.freq ? $0.freq > $1.freq : $0.word < $1.word }
        let minFreq = typedLen >= p.longMinLen ? min(p.minFreq, p.longMinFreq) : p.minFreq
        guard let top = sorted.first, proposable.contains(top.word), top.freq >= minFreq else { return nil }
        if sorted.count > 1, top.freq - sorted[1].freq < p.margin { return nil }
        return top
    }

    /// Bản sửa cho từ (phím thô `raw`) hoặc nil. `isKnown`: dạng chữ thường (phím thô và dạng
    /// engine ra) là từ đã biết — tiếng Anh / chat / từng Esc ⇒ không gợi ý. `englishFrequency`
    /// (enlexicon) ≠ nil ⇒ không có bản sửa tiếng Việt thì thử bản sửa tiếng Anh.
    static func correction(raw: String, compose: (String) -> String, frequency: (String) -> Int?,
                           hasCompletion: (String) -> Bool, isKnown: (String) -> Bool,
                           englishFrequency: ((String) -> Int?)? = nil, filterSensitive: Bool = true,
                           p: Params = defaults, ep: EnglishParams = englishDefaults) -> String? {
        guard (p.minLen...10).contains(raw.count), raw.allSatisfy({ $0.isASCII && $0.isLetter }) else { return nil }
        let lower = raw.lowercased()
        if isKnown(lower) { return nil }
        let current = compose(lower)
        if current != lower, isKnown(current.lowercased()) { return nil }
        if frequency(current) != nil || hasCompletion(current) { return nil }
        let vn = candidates(lower, compose: compose, frequency: frequency,
                            hasCompletion: hasCompletion, edits: p.edits.union(p.rivals))
        let best: Cand
        if let b = pick(vn, p: p) {
            best = b
        } else if let ef = englishFrequency,
                  let b = englishPick(englishCandidates(lower, frequency: ef), rivals: vn, typedLen: lower.count, p: ep) {
            best = b
        } else {
            return nil
        }
        // "Lọc từ nhạy cảm" bật (như thanh gợi ý iOS): không chủ động đưa từ tục — bỏ hẳn lượt
        // này (không lùi về ứng viên thứ hai: nó chưa chắc hơn đủ xa).
        if SensitiveWords.filter([best.word], enabled: filterSensitive).isEmpty { return nil }
        if raw.first?.isUppercase == true, let f = best.word.first {
            return f.uppercased() + best.word.dropFirst()
        }
        return best.word
    }

    /// Từ chat/viết tắt (seed iOS/Android: ko, dc, mn…) không phải âm tiết — coi là đã biết.
    static let chatWords: Set<String> = Set(SeedData.unigrams.keys.filter { w in
        w.allSatisfy { $0.isASCII && $0.isLetter } && !VNSuggest.contains(w)
    })

    /// Tiếng Anh: enlexicon + từ mở mạch tiếng Anh của engine (the, is, you…).
    static func isEnglish(_ w: String) -> Bool {
        EnglishLite.contains(w) || EnglishContextLookup.opensEnglishRun(w)
    }

    /// Từ đã biết trên Mac: tiếng Anh + từ chat.
    static func isKnown(_ w: String) -> Bool { isEnglish(w) || chatWords.contains(w) }

    /// Engine nháp cùng setting với bộ gõ (không đụng engine thật) — raw → chữ hiển thị.
    static func composer(_ flags: AppState.EngineFlags) -> (String) -> String {
        { raw in
            var e = TelexEngine()
            e.apply(flags)
            for ch in raw { _ = e.feed(ch) }
            return e.composed
        }
    }

    /// Bản sửa dùng lexicon thật (VNSuggest — vnlexicon.bin mmap). Gọi ngoài main.
    static func lexiconCorrection(raw: String, flags: AppState.EngineFlags, filterSensitive: Bool = true) -> String? {
        correction(raw: raw, compose: composer(flags),
                   frequency: { VNSuggest.frequency(of: $0) },
                   hasCompletion: { !VNSuggest.matches($0, poolLimit: 1).isEmpty },
                   isKnown: isKnown, englishFrequency: { EnglishLite.frequency(of: $0) },
                   filterSensitive: filterSensitive)
    }

    /// Gợi ý nếu màn hình (`before`, kết thúc ở con trỏ) đúng là `word` + `boundary`, từ đứng
    /// riêng (đầu văn bản / sau khoảng trắng), và chữ hoa hợp lệ (hoa đầu chỉ ở đầu câu).
    static func suggestion(before: String, word: String, boundary: String, raw: String,
                           fix: String) -> CaretSuggestion? {
        let replace = word + boundary
        guard fix != word, CaretHintLogic.standsAlone(before: before, token: replace) else { return nil }
        let head = String(before.unicodeScalars.dropLast(replace.unicodeScalars.count))
        guard AutoCorrect.caseAllows(raw, sentenceStart: AutoCorrect.isSentenceStart(head)) else { return nil }
        return CaretSuggestion(kind: .typo, display: fix, replace: replace, insert: fix + boundary)
    }
}

// MARK: - 2. Thêm dấu cho cụm không dấu

enum ToneRunLogic {
    static let minSyllables = 3
    /// Dừng gõ bấy nhiêu giây sau dấu cách ⇒ mời thêm dấu (kích hoạt thứ hai, xem đầu file).
    static let pauseDelay: TimeInterval = 0.9
    /// Trần số âm tiết của một cụm (một câu chat).
    static let maxSyllables = 40
    /// Cửa sổ đọc màn hình (UTF-16) cho cụm.
    static let window = 320

    enum Trigger: Equatable { case sentenceEnd, pause }

    private static let edgePunct = Set(",;:\"'()[]…“”‘’.!?")

    /// Chunk (không khoảng trắng) là âm tiết KHÔNG DẤU hợp lệ — bỏ dấu câu hai đầu; chữ a–z
    /// (hoa đầu được), không phải từ mở mạch tiếng Anh (the, is, you…).
    static func isUnaccentedSyllable(_ chunk: Substring, insideRun: Bool = false) -> Bool {
        var c = chunk
        while let f = c.first, edgePunct.contains(f) { c = c.dropFirst() }
        while let l = c.last, edgePunct.contains(l) { c = c.dropLast() }
        guard !c.isEmpty, c.count <= 7,
              c.unicodeScalars.allSatisfy({ ($0.value >= 97 && $0.value <= 122) || ($0.value >= 65 && $0.value <= 90) }),
              !c.dropFirst().contains(where: \.isUppercase) || c.allSatisfy(\.isUppercase) else { return false }
        let w = c.lowercased()
        // Từ mở mạch tiếng Anh (go, the, is…) chỉ chặn ở ĐẦU cụm; đã ở giữa cụm tiếng Việt
        // không dấu ("Minh dang go tieng Viet") thì là âm tiết Việt (gõ) — Phil 18/10/2026.
        guard insideRun || !EnglishContextLookup.opensEnglishRun(w) else { return false }
        // Dạng không dấu của vần bắt buộc mũ/móc: ie→iê (tiếng, Việt), ye→yê (yêu), uo→uô/ươ
        // (không, trường), ua→ưa (mưa) — Phil 18/10/2026: "tieng", "truong" bị coi là không hợp lệ
        // nên cụm bị cắt. Mỗi dạng thử cả không dấu lẫn dấu sắc (vần tắc -c -ch -p -t).
        var forms = [w]
        for (from, tos) in Self.hatPairs where w.contains(from) {
            for to in tos { forms.append(w.replacingOccurrences(of: from, with: to)) }
        }
        for f in forms {
            if SyllableValidator.isValidSyllable(f, teencode: false) { return true }
            guard let i = f.firstIndex(where: { "aeiouyâêôơư".contains($0) }) else { continue }
            let acute = (String(f[...i]) + "\u{301}" + String(f[f.index(after: i)...])).precomposedStringWithCanonicalMapping
            if SyllableValidator.isValidSyllable(acute, teencode: false) { return true }
        }
        return false
    }

    static let hatPairs: [(String, [String])] = [("ie", ["iê"]), ("ye", ["yê"]), ("uo", ["uô", "ươ"]), ("ua", ["ưa"])]

    /// Số đứng giữa câu không dấu ("cap 3", "luc 10:30", "ngay 16/10") — giữ nguyên, không
    /// đếm là âm tiết nhưng cũng KHÔNG ngắt cụm (Phil 18/10/2026: "...hop lop cap 3." không
    /// ra gợi ý vì "3" làm đếm lại từ đầu). Dấu câu cuối (3. 3,) bỏ qua khi xét.
    static func isNeutralNumber(_ chunk: Substring) -> Bool {
        var c = chunk
        while let l = c.last, ".,!?;:)".contains(l) { c = c.dropLast() }
        guard !c.isEmpty, c.count <= 12, c.contains(where: \.isNumber) else { return false }
        return c.allSatisfy { $0.isNumber || ".,:/-".contains($0) }
    }

    /// Đếm âm tiết không dấu liên tiếp theo dòng phím (chỉ ở ranh giới — không đọc màn hình).
    struct Tracker: Equatable {
        private(set) var count = 0
        mutating func reset() { count = 0 }

        /// `chunk` = cụm đã chốt ngay trước ranh giới (ShortcutTail.run), `boundary` = ký tự vừa gõ.
        mutating func feed(chunk: String, boundary: String) -> Trigger? {
            guard let b = boundary.first, boundary.count == 1 else { count = 0; return nil }
            if b.isNewline { count = 0; return nil }
            if b.isWhitespace {
                if chunk.isEmpty { return nil }                                  // hai dấu cách
                if let l = chunk.last, ".!?".contains(l) { count = 0; return nil }  // câu đã kết (đã xét ở dấu câu)
                if isNeutralNumber(Substring(chunk)) { return count >= minSyllables ? .pause : nil }
                count = isUnaccentedSyllable(Substring(chunk), insideRun: count > 0) ? min(count + 1, maxSyllables) : 0
                return count >= minSyllables ? .pause : nil
            }
            if ".!?".contains(b) {
                let ok = !chunk.isEmpty && isUnaccentedSyllable(Substring(chunk), insideRun: count > 0)
                let n = ok ? count + 1 : (!chunk.isEmpty && isNeutralNumber(Substring(chunk)) ? count : 0)
                count = 0
                return n >= minSyllables ? .sentenceEnd : nil
            }
            return nil   // , ; : … — chunk được xét lại ở dấu cách kế (kèm dấu câu)
        }
    }

    /// Cụm để thêm dấu ở cuối `before` (văn bản trước con trỏ): các chunk âm tiết không dấu
    /// liên tiếp tính từ cuối (kể cả khoảng trắng/dấu câu cuối), dừng ở xuống dòng, ở chunk
    /// khác, ở chunk kết câu trước đó (không kéo câu trước vào). nil nếu < `minSyllables`.
    static func run(before: String) -> String? {
        let s = Array(before.unicodeScalars)
        var end = s.count
        var start = end, n = 0
        func isWs(_ c: Unicode.Scalar) -> Bool { c == " " || c == "\t" || c == "\u{00A0}" }
        func isNl(_ c: Unicode.Scalar) -> Bool { c == "\n" || c == "\r" }
        while end > 0 {
            var ws = end
            while ws > 0, isWs(s[ws - 1]) { ws -= 1 }
            if ws > 0, isNl(s[ws - 1]) { break }
            if ws == 0 { break }
            var cs = ws
            while cs > 0, !isWs(s[cs - 1]), !isNl(s[cs - 1]) { cs -= 1 }
            var u = String.UnicodeScalarView(); u.append(contentsOf: s[cs..<ws])
            let chunk = String(u)
            if n > 0, let l = chunk.last, ".!?".contains(l) { break }   // hết câu trước
            if isNeutralNumber(Substring(chunk)) {                      // số giữ nguyên, không đếm
                start = cs; end = cs; continue
            }
            guard isUnaccentedSyllable(Substring(chunk), insideRun: n > 0) else { break }
            n += 1
            start = cs
            end = cs
            if n >= maxSyllables { break }
        }
        guard n >= minSyllables else { return nil }
        var u = String.UnicodeScalarView(); u.append(contentsOf: s[start...])
        return String(u)
    }

    /// Cụm đã chạy Thêm dấu mà KHÔNG ra gợi ý (process con trả nil / không đổi gì): mỗi lần
    /// dừng gõ ≥ `pauseDelay` sau một âm tiết mới từng kích hoạt lại cả hai lần đọc AX lẫn
    /// spawn nguyên executable VietTelex — cho cùng một câu đã biết là vô ích. Chỉ thử lại
    /// khi cụm dài thêm ≥ `retryAfterSyllables` âm tiết (thêm ngữ cảnh mới đáng một lần
    /// spawn), khi sang cụm khác, hoặc ở cuối câu (". ! ?" — kích hoạt chủ ý).
    static let retryAfterSyllables = 2

    /// Số chunk (âm tiết) của một cụm — tách theo khoảng trắng.
    static func syllableCount(_ run: String) -> Int {
        run.split(whereSeparator: { $0.isWhitespace }).count
    }

    struct FruitlessMemo: Equatable {
        private(set) var run: String?
        mutating func note(fruitless run: String) { self.run = run }
        mutating func clear() { run = nil }

        /// Có nên chạy Thêm dấu cho `run` không.
        func allows(_ run: String, trigger: Trigger) -> Bool {
            guard trigger == .pause, let last = self.run, run.hasPrefix(last) else { return true }
            return syllableCount(run) - syllableCount(last) >= retryAfterSyllables
        }
    }

    /// Gợi ý từ kết quả Thêm dấu (cùng độ dài scalar — AddTones giữ nguyên dấu câu/khoảng
    /// trắng). nil nếu không đổi gì hay kết quả lạ.
    static func suggestion(run: String, restored: String) -> CaretSuggestion? {
        guard !run.isEmpty, restored != run,
              restored.unicodeScalars.count == run.unicodeScalars.count else { return nil }
        var display = restored.trimmingCharacters(in: .whitespaces)
        if display.count > 60 { display = "…" + display.suffix(59) }
        return CaretSuggestion(kind: .tones, display: display, replace: run, insert: restored)
    }
}

// MARK: - 3. Ngày giờ

enum DateHintLogic {
    enum Phrase: Equatable { case today, tomorrow, yesterday, now, lunar }

    private static let vietnamese: [String: [String: Phrase]] = [
        "hôm": ["nay": .today, "qua": .yesterday],
        "ngày": ["mai": .tomorrow, "âm": .lunar],
        "bây": ["giờ": .now],
        "âm": ["lịch": .lunar],
    ]
    /// Một từ đứng riêng (từ trước bất kỳ): "ÂL␣" ⇒ âm lịch hôm nay.
    private static let single: [String: Phrase] = ["âl": .lunar]

    /// Cụm hai từ tiếng Việt? (khi đó Tab thay cả hai từ, không thì chỉ từ cuối).
    private static func isPair(prevRun: String, run: String) -> Bool {
        vietnamese[prevRun.lowercased().precomposedStringWithCanonicalMapping]?[
            run.lowercased().precomposedStringWithCanonicalMapping] != nil
    }
    private static let english: [String: Phrase] = [
        "today": .today, "tomorrow": .tomorrow, "yesterday": .yesterday, "now": .now,
    ]

    /// Dấu cách vừa gõ sau cụm ngày giờ? `run` = từ vừa chốt, `prevRun` = cụm trước nó.
    /// Tiếng Anh chỉ khi từ trước là tiếng Anh (`isEnglish`) — "now" đứng một mình không bật.
    static func detect(boundary: String?, prevRun: String, run: String,
                       isEnglish: (String) -> Bool) -> Phrase? {
        guard boundary == " ", !run.isEmpty, run.count <= 9 else { return nil }
        let w = run.lowercased().precomposedStringWithCanonicalMapping
        let p = prevRun.lowercased().precomposedStringWithCanonicalMapping
        if let m = vietnamese[p]?[w] { return m }
        if let m = single[w] { return m }
        if let m = english[w], !p.isEmpty, p.allSatisfy({ $0.isASCII && $0.isLetter }), isEnglish(p) { return m }
        return nil
    }

    /// "28/09/2026" (ngày), "21:35" (giờ), lịch Gregorian theo múi giờ máy; âm lịch hôm nay
    /// "30/9 năm Bính Ngọ" (ngày dương theo múi giờ máy, đổi sang âm lịch Việt Nam UTC+7).
    static func format(_ p: Phrase, now: Date, timeZone: TimeZone = .current) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let day: Date
        switch p {
        case .now:
            let c = cal.dateComponents([.hour, .minute], from: now)
            return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
        case .lunar:
            let c = cal.dateComponents([.day, .month, .year], from: now)
            return LunarCalendar.text(day: c.day ?? 1, month: c.month ?? 1, year: c.year ?? 2000)
        case .today: day = now
        case .tomorrow: day = cal.date(byAdding: .day, value: 1, to: now) ?? now
        case .yesterday: day = cal.date(byAdding: .day, value: -1, to: now) ?? now
        }
        let c = cal.dateComponents([.day, .month, .year], from: day)
        return String(format: "%02d/%02d/%04d", c.day ?? 1, c.month ?? 1, c.year ?? 2000)
    }

    /// Gợi ý: màn hình kết thúc bằng "<prevRun> <run> " đứng riêng ⇒ thay cả cụm bằng ngày/giờ.
    static func suggestion(before: String, prevRun: String, run: String, phrase: Phrase,
                           now: Date, timeZone: TimeZone = .current) -> CaretSuggestion? {
        let replace = (isPair(prevRun: prevRun, run: run) ? prevRun + " " : "") + run + " "
        guard CaretHintLogic.standsAlone(before: before, token: replace) else { return nil }
        let value = format(phrase, now: now, timeZone: timeZone)
        return CaretSuggestion(kind: .date, display: value, replace: replace, insert: value + " ")
    }
}

extension CaretHintLogic {
    /// `before` kết thúc đúng bằng `token` (so UTF-16) và token đứng riêng — cùng quy tắc
    /// ShortcutScreen.tokenRange mà bước áp dụng sẽ kiểm lại trên màn hình.
    static func standsAlone(before: String, token: String) -> Bool {
        let n = (before as NSString).length
        return ShortcutScreen.tokenRange(caret: n, token: token, window: before, windowStart: 0) != nil
    }
}
