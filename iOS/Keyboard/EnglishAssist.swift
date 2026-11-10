// EnglishAssist.swift — GỢI Ý TIẾNG ANH GIỮA CÂU VIỆT trên thanh gợi ý (góp ý người dùng
// 19/10/2026: "nhiều khi có từ tiếng Anh dài mà không nhớ cách viết"). Bản Kotlin song sinh:
// android/keyboard/src/main/kotlin/com/viettelex/keyboard/EnglishAssist.kt — sửa ở đây thì
// sửa y hệt bên kia (test hai bên dùng cùng ví dụ).
//
// Ở chế độ tiếng Việt, phím thô (a–z, ≥ 4 phím) của từ đang gõ:
//   1. HOÀN THÀNH: là tiền tố từ tiếng Anh và cách đọc tiếng Việt yếu ⇒ trộn từ tiếng Anh
//      (xếp theo tần suất enlexicon) vào thanh. Cùng ngưỡng với macOS
//      (App/Sources/WordPrediction.swift `PredictionLogic.prefersEnglish`): không âm tiết Việt
//      nào khớp ⇒ tiếng Anh luôn; có ⇒ chỉ khi từ Anh đầu ≥ `minFreq` và hơn âm tiết Việt
//      mạnh nhất ≥ `margin`, và chữ đang hiện không là âm tiết Việt có tần suất ≥ `maxExact`.
//   2. SỬA CHÍNH TẢ: không từ tiếng Anh nào bắt đầu bằng phím thô, không âm tiết Việt nào
//      khớp, ≥ `typoMinLen` phím ⇒ từ tiếng Anh cách phím thô ≤ 1 sửa (≤ 2 khi ≥ `typoLongLen`
//      phím) — tính cả "đang gõ dở" (khoảng cách tới TIỀN TỐ của từ: "acomm" → accommodation).
//      Sửa = thay / thêm / bỏ một chữ hoặc đảo hai chữ liền nhau (Damerau OSA). Giữ chữ đầu
//      (lỗi chính tả hầu như không ở chữ đầu) ⇒ chỉ quét ~1/20 lexicon. Tối đa `typoLimit`.
//
// HIỆU NĂNG: chạy trên hàng đợi nền của thanh gợi ý (như VNSuggest/AdjacentKeyFixer). Từ rõ
// là tiếng Việt (chữ đang hiện là âm tiết phổ biến) hoặc phím thô < 4 / không phải a–z ⇒ trả
// nil TRƯỚC khi chạm lexicon tiếng Anh (0 chi phí thêm). Lexicon = SwipeEnglish.lexicon (đọc tại
// chỗ trên mmap, nạp sẵn ở nền sau khung đầu — warmUpData) — không thêm RAM.
// Nhận gợi ý: đường chạm gợi ý có sẵn (xoá từ đang gõ, chèn nguyên văn + dấu cách, reset
// engine) ⇒ Telex không bỏ dấu lại.
import Foundation

enum EnglishAssist {
    /// = PredictionLogic.englishMinRaw (macOS).
    static let minRaw = 4
    /// = PredictionLogic.englishMinFreq / englishMargin / englishMaxExact (macOS).
    static let minFreq = 150
    static let margin = 80
    static let maxExact = 60
    /// Phím thô dài hơn ⇒ không phải một từ (dán chuỗi, mã…) — bỏ.
    static let maxRaw = 24
    /// Số từ hoàn thành tối đa trả về.
    static let completionLimit = 6
    /// Sửa chính tả: phím thô tối thiểu, ngưỡng cho khoảng cách 2, tần suất tối thiểu, số gợi ý.
    static let typoMinLen = 5
    static let typoLongLen = 8
    static let typoMinFreq = 80
    static let typoLimit = 2

    enum Kind: Equatable { case completion, correction }

    struct Result: Equatable {
        /// Từ tiếng Anh chữ thường (dạng lexicon), xếp hạng — bên gọi lo hoa/thường + lọc.
        let words: [String]
        let kind: Kind
    }

    /// Cổng rẻ (không tra gì): phím thô 4…24 chữ a–z (hoa/thường).
    static func eligible(raw: String) -> Bool {
        let n = raw.utf8.count
        guard n >= minRaw, n <= maxRaw else { return false }
        return raw.utf8.allSatisfy { ($0 | 0x20) >= 97 && ($0 | 0x20) <= 122 }
    }

    /// Gợi ý tiếng Anh cho từ đang gõ (nil = không gì). `pool` = VNSuggest.matches(composed)
    /// (đã bỏ chính composed), `typedFreq` = VNSuggest.frequency(of: composed). `lex` chỉ được
    /// đọc khi qua hết cổng tiếng Việt.
    static func suggest(raw: String, composed: String, pool: [VNSuggest.Match], typedFreq: Int?,
                        lex: @autoclosure () -> SwipeEnglish.Lexicon = SwipeEnglish.lexicon) -> Result? {
        guard eligible(raw: raw) else { return nil }
        // Telex đã bỏ dấu/thanh (chữ hiện có ký tự ngoài ASCII) mà vẫn có âm tiết Việt khớp ⇒ đang gõ
        // tiếng Việt: không tính gì thêm. (Từ Anh dài làm hỏng âm tiết ⇒ engine trả lại phím thô, ASCII.)
        if !pool.isEmpty, composed.utf8.contains(where: { $0 >= 0x80 }) { return nil }
        let n = composed.count
        var exact = typedFreq ?? -1, best = typedFreq ?? -1
        for m in pool {
            best = max(best, m.freq)
            if m.word.count == n { exact = max(exact, m.freq) }
        }
        // Rõ là tiếng Việt ("thin" ~ thìn, "chan" ~ chán, "nguowif" → người): không tra tiếng Anh.
        if exact >= maxExact { return nil }
        // Âm tiết Việt khớp đã mạnh tới mức không từ Anh nào (tần suất ≤ 255) hơn nổi `margin`.
        if !pool.isEmpty, best > 255 - margin { return nil }
        let lexicon = lex()
        guard lexicon.count > 0 else { return nil }
        let low = raw.lowercased()
        let comps = SwipeEnglish.completions(low, limit: completionLimit, in: lexicon)
        if let top = comps.first {
            guard pool.isEmpty || (top.freq >= minFreq && top.freq - best >= margin) else { return nil }
            return Result(words: comps.map(\.word), kind: .completion)
        }
        // Không từ Anh nào bắt đầu bằng phím thô: sửa chính tả — chỉ khi tiếng Việt không khớp gì
        // và chính phím thô không phải một từ tiếng Anh ("hello" không có từ dài hơn).
        guard pool.isEmpty, low.utf8.count >= typoMinLen,
              SwipeEnglish.index(of: low, in: lexicon) == nil else { return nil }
        let fixes = corrections(low, in: lexicon)
        return fixes.isEmpty ? nil : Result(words: fixes, kind: .correction)
    }

    /// Từ tiếng Anh cách `low` (a–z chữ thường) ≤ 1 sửa (≤ 2 khi ≥ typoLongLen chữ), cùng chữ
    /// đầu, tần suất ≥ typoMinFreq. Khớp cả từ trước khớp tiền tố (đang gõ dở); rồi khoảng
    /// cách tăng dần, tần suất giảm dần.
    static func corrections(_ low: String, in lex: SwipeEnglish.Lexicon, limit: Int = typoLimit) -> [String] {
        let r = Array(low.utf8)
        let n = r.count
        guard n >= typoMinLen, let first = r.first else { return [] }
        let maxD = n >= typoLongLen ? 2 : 1
        // dải từ bắt đầu bằng chữ đầu (từ đã sort theo byte; đọc tại chỗ trên mmap, không dựng String)
        func lower(_ b: UInt8) -> Int { [b].withUnsafeBufferPointer { lex.lowerBound($0) } }
        let start = lower(first)
        let end = first >= 122 ? lex.count : lower(first + 1)
        // (khoảng cách, cả từ?, tần suất, chỉ số)
        var hits: [(d: Int, whole: Bool, f: Int, i: Int)] = []
        // ba hàng DP (OSA cần hàng i-2) — cấp một lần, dùng lại cho mọi từ
        let rows = UnsafeMutablePointer<Int>.allocate(capacity: 3 * (n + 1))
        defer { rows.deallocate() }
        r.withUnsafeBufferPointer { rb in
            var i = start
            while i < end {
                defer { i += 1 }
                let f = Int(lex.freq[i])
                guard f >= typoMinFreq else { continue }
                let m = lex.wordLength(i)
                guard m >= n - maxD else { continue }
                let d = lex.withWordBytes(i) { distance($0, rb, maxD: maxD, rows: rows) }
                if let full = d.full, full > 0 {
                    hits.append((full, true, f, i))
                } else if m > n, let p = d.prefix, p > 0 {
                    hits.append((p, false, f, i))
                }
            }
        }
        hits.sort {
            if $0.whole != $1.whole { return $0.whole }
            if $0.d != $1.d { return $0.d < $1.d }
            return $0.f != $1.f ? $0.f > $1.f : $0.i < $1.i
        }
        return hits.prefix(limit).map { lex.word($0.i) }
    }

    /// Khoảng cách Damerau (OSA) ≤ `maxD` giữa từ `w` và phím thô `r`: `full` = cả từ, `prefix` =
    /// nhỏ nhất trên các tiền tố của `w` dài |r|±maxD (đang gõ dở). nil = > maxD. Chỉ tính dải chéo
    /// rộng 2·maxD+1 (ô ngoài dải chắc chắn > maxD) và chỉ tới hàng |r|+maxD ⇒ ≤ ~70 ô mỗi từ.
    static func distance(_ w: UnsafeBufferPointer<UInt8>, _ r: UnsafeBufferPointer<UInt8>, maxD: Int,
                         rows: UnsafeMutablePointer<Int>) -> (full: Int?, prefix: Int?) {
        let n = r.count, m = w.count, inf = maxD + 1, stride = n + 1
        let last = min(m, n + maxD)
        guard m >= n - maxD else { return (nil, nil) }
        // hàng 0
        for j in 0...n { rows[j] = j <= maxD ? j : inf }
        var full: Int?, prefix: Int?
        var base0 = 0, base1 = stride, base2 = 2 * stride   // hàng i-1, i, i-2
        var prevChar: UInt8 = 0
        var row = 1
        while row <= last {
            let c = w[row - 1]
            let lo = max(1, row - maxD), hi = min(n, row + maxD)
            rows[base1] = row <= maxD ? row : inf
            if lo > 1 { rows[base1 + lo - 1] = inf }
            var rowMin = rows[base1]
            if lo <= hi {
                for j in lo...hi {
                    let cost = c == r[j - 1] ? 0 : 1
                    var v = min(rows[base0 + j] + 1, rows[base1 + j - 1] + 1, rows[base0 + j - 1] + cost)
                    if row > 1, j > 1, c == r[j - 2], prevChar == r[j - 1] { v = min(v, rows[base2 + j - 2] + 1) }
                    if v > inf { v = inf }
                    rows[base1 + j] = v
                    if v < rowMin { rowMin = v }
                }
            }
            if hi < n { rows[base1 + hi + 1] = inf }
            if row >= n - maxD, hi == n, rows[base1 + n] <= maxD {
                prefix = min(prefix ?? inf, rows[base1 + n])
            }
            if row == m, hi == n, rows[base1 + n] <= maxD { full = rows[base1 + n] }
            if rowMin > maxD { break }
            (base2, base0, base1) = (base0, base1, base2)
            prevChar = c
            row += 1
        }
        return (full, prefix)
    }

    /// "Lọc từ nhạy cảm" (cùng bộ lọc với gợi ý tiếng Việt: từ, cặp sau `prev`, bộ ba). enlexicon
    /// vốn không có từ tục tiếng Anh — lọc ở đây giữ đúng hợp đồng nếu dữ liệu đổi.
    static func filtered(_ r: Result?, after prev: String?, prev2: String?, enabled: Bool) -> Result? {
        guard let r else { return nil }
        let w = SensitiveWords.filter(r.words, after: prev, prev2: prev2, enabled: enabled)
        return w.isEmpty ? nil : Result(words: w, kind: r.kind)
    }

    /// Trộn vào danh sách tiếng Việt đã xếp hạng: hoàn thành ⇒ 2 từ Anh đầu dẫn, rồi tiếng Việt,
    /// rồi phần còn lại; sửa chính tả (tiếng Việt không khớp gì) ⇒ bản sửa tiếng Việt (nếu có)
    /// trước, rồi từ Anh. Bỏ trùng (không phân biệt hoa thường).
    static func merge(vietnamese: [String], english: Result?) -> [String] {
        guard let e = english, !e.words.isEmpty else { return vietnamese }
        let ordered: [String]
        switch e.kind {
        case .completion: ordered = Array(e.words.prefix(2)) + vietnamese + e.words.dropFirst(2)
        case .correction: ordered = vietnamese + e.words
        }
        var seen = Set<String>(), out: [String] = []
        for w in ordered where seen.insert(w.lowercased()).inserted { out.append(w) }
        return out
    }
}
