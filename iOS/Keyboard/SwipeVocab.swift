// SwipeVocab.swift — TỪ VỰNG GÕ VUỐT = 1666 dạng của vnlexicon (SwipeLexicon) + từ chat/viết
// tắt (luôn có) + từ tục (chỉ khi TẮT "Lọc từ nhạy cảm" — cùng công tắc thanh gợi ý). Song sinh
// android SwipeVocab.kt — sửa bảng/hằng ở đây thì sửa y hệt bên kia.
//
// - Lọc BẬT (mặc định): SwipeDecoder.expand bỏ mọi âm tiết trong SensitiveWords.set (vnlexicon có
//   sẵn đĩ, cứt, dâm, điếm) ⇒ vuốt không bao giờ ra từ nhạy cảm, kể cả qua bung dấu.
// - Lọc TẮT: thêm âm tiết tục vnlexicon không có (địt, lồn, cặc, buồi, đụ) vào dạng sẵn có và
//   viết tắt tục (vl, đcm, dkm…) thành dạng mới.
//
// `chat`: viết tắt chat của seed (ko, dc, ok, vs, mn, vd, ib, cmt, stt, kb, uk, oke, okie, haha…) +
// nma, ntn, nx, bt, ms. Từ tục = cả SensitiveWords.set, tần suất từ seed (`sensitiveEntries`). Thô
// tục KHÔNG nằm trong SensitiveWords (vú, ngu, dái, cu, nắc, mày, vãi…) vnlexicon có sẵn ⇒ luôn có.
// Tần suất cùng thang vnlexicon (0–255; điểm = λ·f/255). Từ 1 chữ (k, j) không vuốt được — chạm là
// ra. Chi phí: dựng một lần mỗi chế độ (lười), đổi công tắc ⇒ decoder dựng lại template một lần;
// 0 việc ở đường phím chữ.
import Foundation

enum SwipeVocab {
    struct Entry {
        let word: String
        let freq: Int
        var sensitive = false
        /// Đường vuốt khác dạng không dấu của từ (nét kiểu Telex: "ow" → ở). nil = fold(word).
        var path: String? = nil
    }

    /// Chat / viết tắt — luôn có (không nằm trong SensitiveWords.set).
    static let chat: [Entry] = [
        .init(word: "ko", freq: 150), .init(word: "đc", freq: 140), .init(word: "dc", freq: 120),
        .init(word: "ok", freq: 150), .init(word: "oke", freq: 100), .init(word: "okie", freq: 80),
        .init(word: "vs", freq: 110), .init(word: "mn", freq: 110), .init(word: "nma", freq: 100),
        .init(word: "ntn", freq: 110), .init(word: "nx", freq: 100), .init(word: "bt", freq: 110),
        .init(word: "ms", freq: 110), .init(word: "vd", freq: 80), .init(word: "ib", freq: 90),
        .init(word: "cmt", freq: 90), .init(word: "stt", freq: 70), .init(word: "kb", freq: 70),
        .init(word: "uk", freq: 90), .init(word: "haha", freq: 120), .init(word: "hihi", freq: 110),
        .init(word: "hehe", freq: 100), .init(word: "huhu", freq: 90), .init(word: "kaka", freq: 60),
        .init(word: "uhm", freq: 110),   // Phil 12/11/2026
    ]

    /// Thô tục KHÔNG nằm trong SensitiveWords.set — luôn có, nhưng vnlexicon ghi tần suất gần 0 (nắc
    /// 0,01 điểm; dạng "nac" thua "ngac" cùng hình) ⇒ nâng. Chỉ nâng khi không cướp từ thường phổ
    /// biến (vú/vụ, ngu/ngủ, dái/đại giữ nguyên — cần ngữ cảnh).
    static let always: [Entry] = [.init(word: "nắc", freq: 140)]

    /// Từ tục khi TẮT lọc = TOÀN BỘ SensitiveWords.set (theo chương trình), tần suất = seed·51/10
    /// (như TouchTarget.chatWords). Từ vnlexicon ĐÃ CÓ (đĩ, cứt, dâm, điếm) giữ tần suất vnlexicon nếu
    /// cao hơn; từ vnlexicon KHÔNG có được sàn `sensitiveFloor` — seed ghi từ tục rất thấp (lồn 5 ⇒
    /// 25), không sàn thì không bao giờ ra. Thứ tự: theo dạng không dấu, dạng có "đ" trước.
    static let sensitiveFloor = 150

    static func sensitiveEntries(_ seed: [String: Int]) -> [Entry] {
        SensitiveWords.set.sorted { a, b in
            let fa = SwipeLexicon.fold(a), fb = SwipeLexicon.fold(b)
            if fa != fb { return fa < fb }
            let da = a.contains("đ"), db = b.contains("đ")
            if da != db { return da }
            return a < b
        }.map { Entry(word: $0, freq: min(max((seed[$0] ?? 0) * 51 / 10, 0), 255), sensitive: true) }
    }

    // MARK: Từ một chữ — vuốt theo phím Telex (11/2026)

    /// Âm tiết MỘT chữ (ở, ạ, à, ừ, ý…) chỉ có một phím ⇒ không vuốt được. Cho vuốt đúng dãy phím
    /// Telex của nó: nguyên âm [+ w nếu có móc] + phím dấu (s f r x j) — "aj" → ạ, "af" → à,
    /// "owr" → ở, "uwf" → ừ, "ys" → ý. Mũ (ô, ê) gõ lặp chữ nên trên đường vuốt gộp mất: "of" là
    /// cả ò lẫn ồ, xếp theo tần suất. Họ móc còn có nét tắt KHÔNG phím dấu: "ow" → ở ờ ơ ợ ớ,
    /// "uw" → ừ ư ứ ự ử (mạnh nhất đứng đầu, còn lại ở phương án). Tần suất = vnlexicon.
    /// Bỏ đường trùng từ tiếng Anh thông dụng hơn (`telexSkip`) và đường trùng dạng vnlexicon.
    /// Song sinh Android SwipeVocab.telexEntries; thứ tự: đường, tần suất giảm, từ.
    static let telexSkip: Set<String> = ["as", "is", "us", "of", "or", "if", "os"]

    /// Đường Telex của âm tiết một chữ `w`: (đủ phím dấu, nét tắt họ móc) — nil nếu không có.
    static func telexPaths(_ w: String) -> (full: String?, family: String?) {
        let sc = Array(w.decomposedStringWithCanonicalMapping.unicodeScalars)
        guard let b = sc.first, "aeiouy".unicodeScalars.contains(b) else { return (nil, nil) }
        var horn = false, tone = ""
        for u in sc.dropFirst() {
            switch u.value {
            case 0x31B, 0x306: horn = true          // móc (ơ ư), trăng (ă)
            case 0x302: break                       // mũ: lặp chữ, gộp trên đường vuốt
            case 0x301: tone = "s"
            case 0x300: tone = "f"
            case 0x309: tone = "r"
            case 0x303: tone = "x"
            case 0x323: tone = "j"
            default: return (nil, nil)
            }
        }
        let stem = String(Character(b)) + (horn ? "w" : "")
        let full = stem + tone
        return (full.count >= 2 ? full : nil, horn && !tone.isEmpty ? stem : nil)
    }

    static let telexEntries: [Entry] = {
        let lex = SwipeLexicon.forms
        var out: [Entry] = []
        for v in ["a", "e", "i", "o", "u", "y"] {
            guard let f = SwipeLexicon.index(of: v) else { continue }
            for id in Int(lex.idStart[f])..<Int(lex.idStart[f + 1]) {
                let w = VNSuggest.display(id)
                let p = telexPaths(w)
                for path in [p.full, p.family] {
                    guard let path, !telexSkip.contains(path), SwipeLexicon.index(of: path) == nil else { continue }
                    out.append(Entry(word: w, freq: Int(VNLexicon2Data.freq(id)), path: path))
                }
            }
        }
        return out.sorted { a, b in
            if a.path != b.path { return a.path! < b.path! }
            if a.freq != b.freq { return a.freq > b.freq }
            return a.word < b.word
        }
    }()

    /// Bảng đầy đủ theo chế độ: chat + thô tục luôn có (+ tục khi tắt lọc, tần suất từ seed)
    /// + nét Telex của từ một chữ + từ của bảng Gõ tắt (`shortcutEntries`, rỗng khi tắt Gõ tắt).
    static func entries(filter: Bool, shortcuts sc: [Entry] = []) -> [Entry] {
        let base = (filter ? chat + always : chat + always + sensitiveEntries(SeedData.unigrams)) + telexEntries
        return sc.isEmpty ? base : base + sc.filter { !(filter && isSensitive($0.word.lowercased())) }
    }

    // MARK: Gõ tắt (10/2026)

    /// Khoá gõ tắt thuần chữ ("vn", "sdt", "ko"): vuốt khoá ⇒ chèn nội dung bung (EngineBridge
    /// .swipeShortcutExpansion) — tần suất vừa phải: thắng dạng hiếm, thua từ thường cùng hình.
    static let shortcutKeyFreq = 120
    /// Từ một chữ của nội dung bung (≤ 3 từ, vd "SenPrints") — giữ ĐÚNG hoa/thường; thấp hơn khoá.
    static let shortcutWordFreq = 100
    static let shortcutMaxWords = 3
    static let shortcutMaxLen = 24
    /// Trần số mục thêm từ bảng gõ tắt (bảng + Thay thế văn bản iOS có thể tới 2000 dòng).
    static let shortcutCap = 500

    /// Mục từ vựng vuốt sinh từ bảng gõ tắt — THUẦN, song sinh Android SwipeVocab.shortcutEntries
    /// (fixture chung Fixtures/swipe-shortcuts.tsv). Thứ tự: khoá (sắp theo khoá) rồi từ của nội dung
    /// (sắp theo từ), cắt ở `shortcutCap`.
    ///  • Khoá: thuần chữ, ≥ 2 chữ cái, ≤ 24, bỏ dấu ra a–z, khoá viết thường (khoá hoa "VN" chỉ khớp khi
    ///    gõ đúng hoa — vuốt ra chữ thường nên bỏ). Khoá ký hiệu/số/chữ+số ("->", "k2") không vuốt được.
    ///  • Từ của nội dung (≤ 3 từ, tách khoảng trắng; dấu câu đầu/cuối bỏ): thuần chữ, ≥ 2, ≤ 24, bỏ dấu
    ///    ra a–z, và CHƯA có trong vnlexicon (âm tiết) hay từ điển tiếng Anh vuốt ("Việt", "Company"
    ///    đã vuốt được — hoa/thường do DisplayCase / hoa/thường đã học lo), không trùng khoá.
    static func shortcutEntries(_ table: ShortcutTable,
                                isLexiconWord: (String) -> Bool = { lexiconFreq($0) >= 0 },
                                isEnglishWord: (String) -> Bool = { SwipeEnglish.contains($0) }) -> [Entry] {
        func swipeable(_ w: String) -> Bool {
            guard w.count >= 2, w.count <= shortcutMaxLen, w.allSatisfy({ $0.isLetter }) else { return false }
            return SwipeLexicon.fold(w).utf8.allSatisfy { $0 >= 97 && $0 <= 122 }
        }
        var keys: [String] = [], seen = Set<String>()
        for k in table.entries.keys where ShortcutTable.isWordKey(k) && k == k.lowercased() && swipeable(k) {
            keys.append(k); seen.insert(k)
        }
        keys.sort()
        var words = Set<String>()
        for v in table.entries.values {
            let parts = v.split(whereSeparator: { $0.isWhitespace })
            guard parts.count <= shortcutMaxWords else { continue }
            for p in parts {
                let w = String(p.drop(while: { !$0.isLetter }).reversed().drop(while: { !$0.isLetter }).reversed())
                    .precomposedStringWithCanonicalMapping
                let l = w.lowercased()
                guard swipeable(w), !seen.contains(l), !isLexiconWord(l), !isEnglishWord(l) else { continue }
                words.insert(w)
            }
        }
        // cùng chữ khác hoa ("SenPrints"/"Senprints") ⇒ giữ một, theo thứ tự byte ổn định
        var byLower: [String: String] = [:]
        for w in words.sorted() where byLower[w.lowercased()] == nil { byLower[w.lowercased()] = w }
        let ws = byLower.values.sorted()
        let out = keys.map { Entry(word: $0, freq: shortcutKeyFreq) } + ws.map { Entry(word: $0, freq: shortcutWordFreq) }
        return Array(out.prefix(shortcutCap))
    }

    nonisolated(unsafe) private static var shortcutStore: [Entry] = []
    nonisolated(unsafe) private static var shortcutSig: [String] = []

    /// Mục gõ tắt hiện dùng (đặt bằng `setShortcuts`).
    static var shortcuts: [Entry] {
        lock.lock(); defer { lock.unlock() }
        return shortcutStore
    }

    /// Đặt lúc bàn phím hiện (cùng chỗ đọc công tắc lọc) và khi bảng gõ tắt hiệu lực đổi (Thay thế
    /// văn bản iOS nạp xong). Bảng không đổi ⇒ không làm gì; đổi ⇒ bỏ cache — decoder thấy Vocab mới
    /// (so định danh) và dựng lại template MỘT lần. nil/rỗng = tắt Gõ tắt.
    /// true nếu từ vựng đổi.
    @discardableResult
    static func setShortcuts(_ table: ShortcutTable?) -> Bool {
        let e = table.map { shortcutEntries($0) } ?? []
        let sig = e.map { "\($0.word)\t\($0.freq)" }
        lock.lock(); defer { lock.unlock() }
        guard sig != shortcutSig else { return false }
        shortcutStore = e; shortcutSig = sig
        cache.removeAll()
        return true
    }

    /// Tần suất (0–255) của âm tiết `word` trong vnlexicon, -1 nếu không có.
    static func lexiconFreq(_ word: String) -> Int {
        guard let i = SwipeLexicon.index(of: SwipeLexicon.fold(word)) else { return -1 }
        let lex = SwipeLexicon.forms
        for id in Int(lex.idStart[i])..<Int(lex.idStart[i + 1]) where VNSuggest.display(id) == word {
            return Int(VNLexicon2Data.freq(id))
        }
        return -1
    }

    final class Vocab {
        let filter: Bool
        /// Dạng lexicon (0..<SwipeLexicon.forms.count) + dạng mới (dải id lexicon rỗng).
        let forms: SwipeLexicon.Forms
        /// Từ thêm theo dạng không dấu (cả dạng lexicon lẫn dạng mới), thứ tự `entries`;
        /// SwipeWord.score = tần suất thô (0–255).
        let words: [String: [SwipeWord]]
        private let extraIndex: [String: Int]

        init(filter: Bool, forms: SwipeLexicon.Forms, words: [String: [SwipeWord]], extraIndex: [String: Int]) {
            self.filter = filter; self.forms = forms; self.words = words; self.extraIndex = extraIndex
        }

        /// Chỉ số dạng trong `forms`, nil nếu không có.
        func index(of folded: String) -> Int? {
            SwipeLexicon.index(of: folded) ?? extraIndex[folded]
        }
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var filterOn = true
    nonisolated(unsafe) private static var cache: [Bool: Vocab] = [:]

    /// Đặt lúc bàn phím hiện (KeyboardViewController, cùng chỗ đọc filterSensitive).
    static var filterSensitive: Bool {
        get { lock.lock(); defer { lock.unlock() }; return filterOn }
        set { lock.lock(); filterOn = newValue; lock.unlock() }
    }

    /// Từ vựng theo công tắc hiện tại (dựng lười, giữ cả hai chế độ).
    static var current: Vocab {
        lock.lock(); defer { lock.unlock() }
        if let v = cache[filterOn] { return v }
        let v = build(filter: filterOn, shortcuts: shortcutStore)   // đang giữ lock: KHÔNG gọi `shortcuts`
        cache[filterOn] = v
        return v
    }

    /// Cảnh báo bộ nhớ (10/11/2026): bỏ từ vựng dựng sẵn. `keepActive` (bàn phím đang hiện) ⇒ giữ bản của chế độ
    /// lọc ĐANG dùng (decoder đang giữ template theo nó), chỉ bỏ chế độ kia; false (ẩn) ⇒ bỏ hết. Dựng lại lười.
    static func purge(keepActive: Bool) {
        lock.lock(); defer { lock.unlock() }
        if keepActive { cache = cache.filter { $0.key == filterOn } } else { cache.removeAll() }
    }

    /// Chế độ lọc có từ vựng đang nằm cache (test).
    static var cachedModes: Set<Bool> { lock.lock(); defer { lock.unlock() }; return Set(cache.keys) }

    static func isSensitive(_ word: String) -> Bool { SensitiveWords.set.contains(word) }

    static func build(filter: Bool, shortcuts: [Entry] = []) -> Vocab {
        let lex = SwipeLexicon.forms
        var words: [String: [SwipeWord]] = [:]
        for e in entries(filter: filter, shortcuts: shortcuts) {
            let f = e.path ?? SwipeLexicon.fold(e.word)
            let lf = e.path != nil || SwipeLexicon.index(of: f) == nil ? -1 : lexiconFreq(e.word)
            // có sẵn trong vnlexicon: chỉ thay khi bảng cao hơn; không có: từ tục được sàn
            let fr = lf < 0 && e.sensitive ? max(e.freq, sensitiveFloor) : e.freq
            if lf >= fr { continue }
            if words[f]?.contains(where: { $0.word == e.word }) == true { continue }   // "ko" chat + khoá gõ tắt
            words[f, default: []].append(SwipeWord(word: e.word, score: Float(fr)))
        }
        let added = words.keys.filter { SwipeLexicon.index(of: $0) == nil }.sorted()
        let fc = lex.count
        let n = lex.idStart[fc]
        var keys = lex.keys
        var keyStart = lex.keyStart
        for a in added {
            var last: UInt8 = 255
            for b in a.utf8 {
                let k = b &- 97
                if k != last { keys.append(k); last = k }
            }
            keyStart.append(Int32(keys.count))
        }
        let forms = SwipeLexicon.Forms(
            folded: lex.folded + added,
            idStart: Array(lex.idStart.prefix(fc)) + Array(repeating: n, count: added.count + 1),
            // tần suất dạng = mạnh nhất của dạng, tính cả từ thêm (nắc nâng dạng "nac")
            freq: (lex.folded + added).enumerated().map { k, f in
                let ex = words[f]?.map { Int($0.score) }.max() ?? 0
                return UInt8(k < fc ? max(Int(lex.freq[k]), ex) : ex)
            },
            keys: keys, keyStart: keyStart)
        var extraIndex: [String: Int] = [:]
        for (k, a) in added.enumerated() { extraIndex[a] = fc + k }
        return Vocab(filter: filter, forms: forms, words: words, extraIndex: extraIndex)
    }
}
