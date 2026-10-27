// UserLangModel — datastore cá nhân hóa cho thanh gợi ý. Học từ user hay gõ
// (unigram), cặp từ (bigram) và bộ ba (trigram — tiếng Việt đơn âm tiết nên
// "cảm ơn → nhiều" chỉ trigram mới bắt được) để gợi ý từ ĐẦU CÂU và từ KẾ TIẾP.
//
// Thiết kế theo khảo cứu 2026-07-24 (Gboard/SwiftKey/Grammarly — cache n-gram
// model interpolate với static seed):
// - Ranking = linear interpolation với Bayesian shrinkage λ = n/(n+K): prev
//   mới gặp 1-2 lần thì tin seed tĩnh, gặp nhiều thì tin dữ liệu cá nhân —
//   một lần gõ nhầm không đè được seed curated.
// - "Learning vs suggesting" (Grammarly): từ NGOÀI lexicon phải đạt count ≥3
//   mới được gợi ý (vẫn đếm từ lần đầu) — chặn học typo.
// - Time decay: mỗi ≥7 ngày nhân mọi count với 0.7^tuần lúc load; kèm cap
//   cứng halve-when-full.
// - PERF: decode/encode/IO chạy trên serial queue .utility — init trả về ngay,
//   bảng swap-in trên main khi decode xong (~50ms đầu gợi ý rỗng, chấp nhận);
//   record() trong cửa sổ chờ được buffer và phát lại sau swap-in.
//
// BẢNG GỌN (09/2026, RAM-AUDIT §5 — trước đây nested [String: [String: Int]], ~1 KB/mục):
// từ intern thành id Int32 (UserLMTables), uni là mảng count theo id, bi là "prev id →
// mảng sắp xếp (next id<<32 | count)", tri là "(p2<<32|p1) → slot → mảng như bi". Lookup
// vẫn O(1)/O(log n) mỗi phím; ngữ nghĩa (cap, decay, prune, retract, thứ tự gợi ý) y hệt bản cũ
// (property test so với LegacyUserLangModel). File: nhị phân VTL2 `userlm.bin` (little-endian,
// CRC32) — chung layout với Android; bản plist cũ `userlm.plist` được chuyển một lần rồi xoá.
// Sao lưu / Từ điển cá nhân đi qua `Plain` (dict như cũ) — JSON sao lưu không đổi.
//
// PRIVACY: chỉ đếm TẦN SUẤT (không câu, không thứ tự, không timestamp per-từ);
// ô mật khẩu không đi qua đây; toggle "Học từ hay dùng" + nút xoá trong app.
import Foundation

final class UserLangModel {
    private var t = UserLMTables()
    /// Hoa/thường đã học (CaseTable, UserLMTables.swift): dạng người dùng nhất quán viết giữa câu.
    private var cases = CaseTable()
    private var lastDecay = Date()
    /// Từ user tự thêm (màn Từ điển cá nhân): key lowercase → dạng hiển thị ("VietTelex").
    private(set) var manual: [String: String] = [:] { didSet { manualIndex = nil } }
    /// Chỉ mục tiền tố cho `manualCompletions` (đường gõ, mỗi phím): (UTF-8 của fold NFC,
    /// fold, key) sắp theo byte. Dựng lười lần đầu cần sau khi `manual` đổi (thêm/xoá/nạp —
    /// hiếm) ⇒ mỗi phím chỉ fold TIỀN TỐ + tìm nhị phân, không fold cả danh sách.
    private var manualIndex: [(bytes: [UInt8], fold: String, key: String)]?

    /// Bảng dạng dict (tests / công cụ) — dựng lại mỗi lần gọi, KHÔNG dùng trên đường gõ.
    var uni: [String: Int] { t.uniDict() }
    var bi: [String: [String: Int]] { t.biDict() }
    var tri: [String: [String: Int]] { t.triDict() }
    var uniCount: Int { t.uniN }
    var biPairCount: Int { t.biN }
    var triPairCount: Int { t.triN }

    /// Lexicon tĩnh — controller nạp VNLexicon vào; từ trong lexicon được gợi ý
    /// ngay, từ lạ cần đạt ngưỡng. Mặc định false để tests kiểm soát được.
    var isKnownWord: (String) -> Bool = { _ in false } {
        didSet { knownCache.removeAll(); topCache = nil }
    }

    /// Gọi trên main sau khi bảng trên đĩa swap-in xong (controller có thể
    /// refresh thanh gợi ý). Không gọi ở chế độ in-memory (tests).
    var onReady: (() -> Void)?

    /// Đường dẫn "gốc" (userlm.plist — tên cũ, giữ cho API); file thật là `compactURL(for:)`.
    private let fileURL: URL?
    private var saveWork: DispatchWorkItem?

    // Encode/decode/IO nền — mọi đọc/ghi bảng vẫn ở main thread.
    private let ioQueue = DispatchQueue(label: "com.viettelex.userlm.io", qos: .utility)
    private var isLoaded = false
    private var loadGeneration = 0    // eraseAll() giữa chừng → bỏ kết quả load cũ
    private var pendingRecords: [(word: String, prev1: String?, prev2: String?, weight: Int, caseEvidence: Bool)] = []
    private var pendingSeed: (uni: () -> [String: Int], bi: () -> [(String, String, Int)])?
    /// Nguồn seed gần nhất — để reloadAfterExternalEdit() seed lại khi file bị app xoá.
    private var seedSource: (uni: () -> [String: Int], bi: () -> [(String, String, Int)])?

    // Memo isKnownWord (VNSuggest.contains = binary search + alloc mỗi lần) —
    // tính hợp lệ của một từ không đổi trong đời keyboard.
    private var knownCache: [String: Bool] = [:]
    // Cache topWords — invalidate khi record/decay/prune/seed thay đổi uni.
    /// `keys` = khoá chữ thường, `words` = dạng hiển thị, cùng thứ tự (count giảm, khoá tăng).
    private var topCache: (k: Int, keys: [String], words: [String])?

    private static let uniCap = 3000
    private static let biCap = 6000
    private static let triCap = 3000
    private static let unknownSuggestThreshold = 3
    private static let pendingRecordCap = 128
    static let sep = "\u{1}"
    /// Count khởi điểm của từ thêm tay: ≥ ngưỡng gợi ý, xếp trên từ học 1-2 lần.
    static let manualCount = 5
    static let manualMaxLen = 24
    static let legacyFileName = "userlm.plist"

    /// Store thật trong App Group; truyền nil cho tests (in-memory).
    init(appGroup: String? = AppFlavor.appGroup) {
        if let g = appGroup,
           let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: g) {
            fileURL = dir.appendingPathComponent(Self.legacyFileName)
        } else {
            fileURL = nil
        }
        if let url = fileURL {
            loadAsync(from: url)
        } else {
            isLoaded = true          // in-memory: sẵn sàng ngay, tests đồng bộ
        }
    }

    /// Tests: store thật ở file tuỳ ý (App Group không có trong test hostless).
    /// `synchronous`: đọc file NGAY trên thread gọi (app — màn Từ điển cá nhân).
    init(fileURL url: URL, synchronous: Bool = false) {
        fileURL = url
        if synchronous {
            finishLoad(Self.readTables(from: url))
        } else {
            loadAsync(from: url)
        }
    }

    /// Store App Group mở đồng bộ cho app chứa (màn Từ điển cá nhân); nil nếu không có App Group.
    static func openSharedForEditing(appGroup: String = AppFlavor.appGroup) -> UserLangModel? {
        guard let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
        else { return nil }
        return UserLangModel(fileURL: dir.appendingPathComponent(legacyFileName), synchronous: true)
    }

    private func loadAsync(from url: URL) {
        let gen = loadGeneration
        ioQueue.async { [weak self] in
            let t = Self.readTables(from: url)
            DispatchQueue.main.async {
                guard let self, self.loadGeneration == gen else { return }
                self.finishLoad(t)
            }
        }
    }

    private func finishLoad(_ l: LoadedTables?) {
        if let l {
            t = l.tables; lastDecay = l.lastDecay; cases = l.cases
            manual = [:]
            for d in l.manual { manual[d.lowercased()] = d }
            keepManual()
        }
        isLoaded = true
        topCache = nil
        if t.uniN == 0, let seed = pendingSeed {
            applySeed(unigrams: seed.uni(), bigrams: seed.bi())
        }
        pendingSeed = nil
        let queued = pendingRecords
        pendingRecords = []
        for r in queued {
            record(word: r.word, after: r.prev1, prev2: r.prev2, weight: r.weight, caseEvidence: r.caseEvidence)
        }
        decayIfDue()
        onReady?()
    }

    // MARK: học

    /// Một từ vừa chốt. `prev1`/`prev2` = 1-2 từ đứng trước trong cùng câu.
    /// `weight`: 1 cho từ gõ thường, 2 cho suggestion được user bấm nhận
    /// (tín hiệu chất lượng cao hơn).
    /// Biên nhận một lần `record` — `retract` rút lại đúng lượt đó (vd hoàn tác tự sửa).
    struct Learned: Equatable {
        let word: String
        let prev1: String?
        let triKey: String?
        let weight: Int
    }

    /// `caseEvidence`: chữ hoa/thường của `word` (đúng như đã gõ) là bằng chứng GIỮA CÂU —
    /// caller tính bằng `DisplayCase.casingEvidence` (+ ô không tự hoa mỗi từ). false ⇒ không
    /// đụng bảng hoa/thường.
    @discardableResult
    func record(word: String, after prev1: String?, prev2: String? = nil, weight: Int = 1,
                caseEvidence: Bool = false) -> Learned? {
        guard isLoaded else {
            if pendingRecords.count < Self.pendingRecordCap {
                pendingRecords.append((word, prev1, prev2, weight, caseEvidence))
            }
            return nil
        }
        guard weight > 0, Self.learnable(word) else { return nil }
        let w = word.lowercased()
        let wid = t.intern(w)
        if caseEvidence {
            cases.observe(word.precomposedStringWithCanonicalMapping, key: w, priorCount: t.uni(wid))
        }
        t.setUni(wid, t.uni(wid) + weight)
        bumpTopCache(w)
        var biKey: String?, triKey: String?
        if let p1 = prev1?.lowercased(), Self.learnable(p1) {
            let pid = t.intern(p1)
            t.addBi(pid, wid, weight)
            biKey = p1
            // trigram chỉ ghi khi cặp (p2,p1) đã có nền — giảm noise/chỗ
            if let p2 = prev2?.lowercased(), Self.learnable(p2),
               let p2id = t.ids[p2], t.biCount(p2id, pid) >= 2 {
                t.addTri(UserLMTables.ctx(p2id, pid), wid, weight)
                triKey = p2 + Self.sep + p1
            }
        }
        pruneIfNeeded()
        scheduleSave()
        return Learned(word: w, prev1: biKey, triKey: triKey, weight: weight)
    }

    /// Rút lại một lần `record`. Không âm, bỏ mục về 0. Giống Android `retract`.
    func retract(_ l: Learned) {
        guard let wid = t.ids[l.word] else { return }
        let had = t.uni(wid)
        guard had > 0 else { return }
        t.setUni(wid, had <= l.weight ? 0 : had - l.weight)
        topCache = nil
        if let k = l.prev1, let pid = t.ids[k] { t.decBi(pid, wid, l.weight) }
        if let k = l.triKey {
            let parts = k.components(separatedBy: Self.sep)
            if parts.count == 2, let a = t.ids[parts[0]], let b = t.ids[parts[1]] {
                t.decTri(UserLMTables.ctx(a, b), wid, l.weight)
            }
        }
        scheduleSave()
    }

    /// Từ của người dùng: thêm tay, hoặc đã gõ đủ nhiều để được gợi ý — tự sửa không đụng.
    /// Dạng hoa/thường người dùng hay viết (`key` chữ thường) — nil nếu chưa đủ nhất quán.
    /// O(1), chỉ gọi cho vài ứng viên đang hiện / từ vuốt.
    func learnedCase(_ key: String) -> String? {
        cases.isEmpty ? nil : cases.preferred(key)
    }

    #if DEBUG
    var debugCaseCount: Int { cases.count }
    func debugCaseStat(_ key: String) -> CaseStat? { cases.stats[key] }
    #endif

    func isUserWord(_ w: String) -> Bool {
        let k = w.lowercased()
        return manual[k] != nil || t.uni(k) >= Self.unknownSuggestThreshold
    }

    /// Từ "học được": chữ cái thuần, ngắn, không chuỗi lặp kiểu "heeeyyy".
    static func learnable(_ w: String) -> Bool {
        guard !w.isEmpty, w.count <= 12, w.allSatisfy({ $0.isLetter }) else { return false }
        var run = 1
        var prev: Character?
        for c in w {
            run = (c == prev) ? run + 1 : 1
            if run >= 3 { return false }
            prev = c
        }
        return true
    }

    private func cachedKnown(_ w: String) -> Bool {
        if let v = knownCache[w] { return v }
        if knownCache.count > 4096 { knownCache.removeAll() }   // chặn phình vô hạn
        let v = isKnownWord(w)
        knownCache[w] = v
        return v
    }

    /// Được phép XUẤT HIỆN trong gợi ý chưa? (learning vs suggesting)
    private func suggestable(_ w: String) -> Bool {
        cachedKnown(w) || manual[w] != nil || t.uni(w) >= Self.unknownSuggestThreshold
    }

    // MARK: từ điển cá nhân (màn quản lý trong app)

    struct Entry: Equatable {
        let word: String      // dạng hiển thị
        let count: Int
        let manual: Bool
    }

    /// Mọi từ đã học + từ thêm tay, tần suất giảm dần (hoà: theo chữ cái). `query` ≠ rỗng:
    /// chỉ từ CHỨA chuỗi tìm (bỏ dấu, không phân biệt hoa/thường — "viet" khớp "việt").
    func entries(query: String = "") -> [Entry] {
        let q = Self.fold(query.trimmingCharacters(in: .whitespaces))
        var out: [Entry] = []
        for (i, c) in t.uniC.enumerated() where c > 0 {
            let k = t.words[i]
            guard q.isEmpty || Self.fold(k).contains(q) else { continue }
            out.append(Entry(word: manual[k] ?? cases.preferred(k) ?? k, count: Int(c), manual: manual[k] != nil))
        }
        return out.sorted { $0.count != $1.count ? $0.count > $1.count : $0.word.lowercased() < $1.word.lowercased() }
    }

    /// Xoá hẳn một từ: unigram, mọi bigram/trigram có từ đó (ở vị trí trước hay sau), và
    /// dấu "thêm tay". true nếu có gì bị xoá.
    @discardableResult
    func removeWord(_ word: String) -> Bool {
        let w = word.lowercased()
        var changed = manual.removeValue(forKey: w) != nil
        if cases.stats[w] != nil { cases.remove(w); changed = true }
        if let id = t.ids[w], t.removeWord(id) { changed = true }
        guard changed else { return false }
        t.compact()
        topCache = nil
        knownCache[w] = nil
        scheduleSave()
        return true
    }

    /// Thêm tay một từ (tên riêng, thuật ngữ) — được gợi ý ngay (không cần đạt ngưỡng từ
    /// lạ), hiện ở hoàn thiện từ khi gõ tiền tố, không bị decay/prune xoá. false nếu không hợp lệ.
    @discardableResult
    func addWord(_ raw: String) -> Bool {
        guard let display = Self.normalizeManual(raw) else { return false }
        let w = display.lowercased()
        manual[w] = display
        let id = t.intern(w)
        if t.uni(id) < Self.manualCount { t.setUni(id, Self.manualCount) }
        topCache = nil
        scheduleSave()
        return true
    }

    /// Từ thêm tay khớp tiền tố đang gõ (bỏ dấu, không phân biệt hoa/thường), dạng hiển thị.
    /// Gọi trên main MỖI PHÍM ⇒ dùng `manualIndex` (fold sẵn, sắp xếp) thay vì fold cả danh sách.
    func manualCompletions(_ prefix: String, limit: Int = 2) -> [String] {
        guard !manual.isEmpty, !prefix.isEmpty else { return [] }
        let f = Self.fold(prefix).precomposedStringWithCanonicalMapping
        let fb = Array(f.utf8)
        let idx = manualIndex ?? buildManualIndex()
        // Cận dưới theo byte: mọi chuỗi có tiền tố byte `fb` nằm liền một khối từ đây.
        var lo = 0, hi = idx.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if idx[mid].bytes.lexicographicallyPrecedes(fb) { lo = mid + 1 } else { hi = mid }
        }
        var hits: [String] = []
        var i = lo
        while i < idx.count, idx[i].bytes.starts(with: fb) {
            // hasPrefix theo Character (như bản cũ) — khác tiền tố byte chỉ ở dấu kết hợp lẻ.
            let e = idx[i]
            if e.fold.hasPrefix(f), let d = manual[e.key], d != prefix { hits.append(e.key) }
            i += 1
        }
        return hits
            .sorted { a, b in
                let ca = t.uni(a), cb = t.uni(b)
                return ca != cb ? ca > cb : a < b
            }
            .prefix(limit).compactMap { manual[$0] }
    }

    private func buildManualIndex() -> [(bytes: [UInt8], fold: String, key: String)] {
        let idx = manual.keys.map { k -> (bytes: [UInt8], fold: String, key: String) in
            let f = Self.fold(k).precomposedStringWithCanonicalMapping
            return (Array(f.utf8), f, k)
        }.sorted { $0.bytes.lexicographicallyPrecedes($1.bytes) }
        manualIndex = idx
        return idx
    }

    #if DEBUG
    /// Test: chỉ mục đã dựng chưa (bị bỏ khi `manual` đổi).
    var debugHasManualIndex: Bool { manualIndex != nil }
    #endif

    /// Chuẩn hoá từ nhập tay: bỏ khoảng trắng đầu/cuối, chỉ chữ cái, 1…24 ký tự. nil = không hợp lệ.
    static func normalizeManual(_ raw: String) -> String? {
        let w = raw.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
        guard !w.isEmpty, w.count <= manualMaxLen, w.allSatisfy({ $0.isLetter }) else { return nil }
        return w
    }

    /// Bỏ dấu + lowercase + đ→d.
    static func fold(_ s: String) -> String {
        s.lowercased().folding(options: .diacriticInsensitive, locale: nil)
            .replacingOccurrences(of: "đ", with: "d")
    }

    /// Từ thêm tay luôn còn trong uni (decay/prune không được xoá).
    private func keepManual() {
        for k in manual.keys where t.uni(k) < 1 { t.setUni(t.intern(k), 1) }
    }

    // MARK: gợi ý

    /// Top từ user hay dùng nhất — cho field trống chưa gõ gì.
    /// Cached: chỉ tính lại sau record/decay/prune/seed; sort trước rồi mới
    /// chạy suggestable() (memoized) trên phần đầu bảng — không probe lexicon
    /// cho cả ~3000 từ.
    func topWords(limit: Int) -> [String] {
        if let c = topCache, c.k >= limit { return Array(c.words.prefix(limit)) }
        var ranked: [(id: Int32, c: UInt32)] = []
        ranked.reserveCapacity(t.uniN)
        for (i, c) in t.uniC.enumerated() where c > 0 { ranked.append((Int32(i), c)) }
        let words = t.words
        ranked.sort { $0.c != $1.c ? $0.c > $1.c : words[Int($0.id)] < words[Int($1.id)] }
        var keys: [String] = [], out: [String] = []
        out.reserveCapacity(limit)
        for (id, _) in ranked {
            let w = words[Int(id)]
            guard suggestable(w) else { continue }
            keys.append(w)
            out.append(manual[w] ?? w)
            if out.count >= limit { break }
        }
        topCache = (limit, keys, out)
        return out
    }

    #if DEBUG
    /// Test hook: bảng unigram (khoá chữ thường → count).
    func debugUnigrams() -> [String: Int] { t.uniDict() }
    /// Test hook: số từ trong bảng intern (kể cả từ mồ côi chờ compact).
    var debugVocabCount: Int { t.words.count }
    #endif

    /// `w` vừa tăng count: cập nhật top-K TẠI CHỖ (K ≤ ~20) thay vì bỏ cache — trước đây
    /// mỗi dấu cách sort lại tới 3000 từ trên main (topWords ở padWords sau mỗi từ).
    /// Thứ tự giống hệt sort đầy đủ: count giảm dần, hoà theo khoá tăng dần.
    private func bumpTopCache(_ w: String) {
        guard var c = topCache else { return }
        let n = t.uni(w)
        func before(_ a: String, _ ca: Int, _ b: String) -> Bool {
            let cb = t.uni(b)
            return ca != cb ? ca > cb : a < b
        }
        if let i = c.keys.firstIndex(of: w) {
            c.keys.remove(at: i); c.words.remove(at: i)
        } else if !suggestable(w) {
            return
        } else if c.keys.count >= c.k, let last = c.keys.last, !before(w, n, last) {
            return                                  // vẫn không lọt top-K
        }
        let j = c.keys.firstIndex { !before($0, t.uni($0), w) } ?? c.keys.count
        c.keys.insert(w, at: j); c.words.insert(manual[w] ?? w, at: j)
        if c.keys.count > c.k { c.keys.removeLast(); c.words.removeLast() }
        topCache = c
    }

    /// Từ kế tiếp sau (prev2, prev1): interpolation trigram ⊕ bigram ⊕ unigram
    /// ⊕ seed tĩnh, mỗi tầng có shrinkage riêng.
    func nextWords(after prev1: String, prev2: String? = nil, limit: Int) -> [String] {
        let p1 = prev1.lowercased()
        let pid = t.ids[p1]
        let biBucket = pid.map { t.biB[Int($0)] } ?? []
        var triBucket: ContiguousArray<UInt64> = []
        if let pid, let p2 = prev2, let p2id = t.ids[p2.lowercased()],
           let slot = t.triIdx[UserLMTables.ctx(p2id, pid)] {
            triBucket = t.triB[Int(slot)]
        }
        let seeds = Self.seedNext[p1] ?? []

        var biTotal = 0, triTotal = 0
        for e in biBucket { biTotal += UserLMTables.cnt(e) }
        for e in triBucket { triTotal += UserLMTables.cnt(e) }
        let uniTotal = max(t.uniTotal, 1)
        let lamTri = Double(triTotal) / (Double(triTotal) + 2)
        let lamBi = Double(biTotal) / (Double(biTotal) + 4)

        // Ứng viên = bi ∪ tri (trộn 2 mảng sắp theo id) ∪ seed; count lấy luôn khi trộn.
        var cands: [(w: String, bc: Int, tc: Int)] = []
        cands.reserveCapacity(biBucket.count + triBucket.count + seeds.count)
        var i = 0, j = 0
        while i < biBucket.count || j < triBucket.count {
            let bn = i < biBucket.count ? UserLMTables.nid(biBucket[i]) : UInt32.max
            let tn = j < triBucket.count ? UserLMTables.nid(triBucket[j]) : UInt32.max
            let id = min(bn, tn)
            var bc = 0, tc = 0
            if bn == id { bc = UserLMTables.cnt(biBucket[i]); i += 1 }
            if tn == id { tc = UserLMTables.cnt(triBucket[j]); j += 1 }
            cands.append((t.words[Int(id)], bc, tc))
        }
        for s in seeds where !cands.contains(where: { $0.w == s }) { cands.append((s, 0, 0)) }

        func score(_ c: (w: String, bc: Int, tc: Int)) -> Double {
            let pTri = triTotal > 0 ? Double(c.tc) / Double(triTotal) : 0
            let pBi = biTotal > 0 ? Double(c.bc) / Double(biTotal) : 0
            let pUni = Double(t.uni(c.w)) / Double(uniTotal)
            let pSeed: Double = seeds.firstIndex(of: c.w).map { pow(0.5, Double($0)) } ?? 0
            return lamTri * pTri
                + lamBi * pBi
                + 0.1 * pUni
                + (1 - lamBi) * 0.9 * pSeed
        }
        // score() tính MỘT lần mỗi từ rồi sort tuple.
        return cands.filter { suggestable($0.w) || seeds.contains($0.w) }
            .map { ($0.w, score($0)) }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }
            .prefix(limit).map { manual[$0.0] ?? $0.0 }
    }

    /// Điểm cá nhân của một từ (re-rank completion của lexicon).
    /// Key trong uni đã lowercase sẵn — chỉ alloc lowercased khi lookup thô miss.
    func count(of word: String) -> Int {
        let c = t.uni(word)
        return c > 0 ? c : t.uni(word.lowercased())
    }

    /// Số lần cặp (prev → word) đã gặp (bigram cá nhân + seed) — AddTones chấm lưới âm tiết.
    func bigramCount(_ prev: String, _ word: String) -> Int {
        guard let p = t.ids[prev.lowercased()], let w = t.ids[word] else { return 0 }
        return t.biCount(p, w)
    }

    /// Số lần bộ ba (prev2, prev → word) người dùng đã gõ (không có seed) — thanh gợi ý ưu tiên.
    func trigramCount(_ prev2: String, _ prev: String, _ word: String) -> Int {
        guard let a = t.ids[prev2.lowercased()], let b = t.ids[prev.lowercased()],
              let s = t.triIdx[UserLMTables.ctx(a, b)] else { return 0 }
        if let w = t.ids[word] { let c = t.triCount(Int(s), w); if c > 0 { return c } }
        guard let w = t.ids[word.lowercased()] else { return 0 }
        return t.triCount(Int(s), w)
    }

    /// Seed ban đầu — chỉ khi datastore trống (lần đầu / sau reset).
    /// @autoclosure: literal seed (~1400 entries) KHÔNG được build khi store
    /// đã có dữ liệu; đang chờ load thì giữ closure lại, quyết sau swap-in.
    func seedIfEmpty(unigrams: @autoclosure @escaping () -> [String: Int],
                     bigrams: @autoclosure @escaping () -> [(String, String, Int)]) {
        seedSource = (unigrams, bigrams)
        guard isLoaded else {
            pendingSeed = (unigrams, bigrams)
            return
        }
        guard t.uniN == 0 else { return }
        applySeed(unigrams: unigrams(), bigrams: bigrams())
    }

    private func applySeed(unigrams: [String: Int], bigrams: [(String, String, Int)]) {
        // uni đang rỗng (điều kiện gọi) — gán thẳng như `uni = unigrams` bản cũ.
        for (w, c) in unigrams where c > 0 { t.setUni(t.intern(w), c) }
        for (a, b, c) in bigrams where c > 0 { t.setBi(t.intern(a), t.intern(b), c) }
        topCache = nil
        save()
    }

    // MARK: persistence (nhị phân VTL2 — xem UserLMCodec)

    private struct LoadedTables {
        var tables: UserLMTables
        var lastDecay: Date
        var manual: [String]
        var cases = CaseTable()
    }

    /// Dạng dict của store — ranh giới với sao lưu (BackupStore) / công cụ. `manual` = dạng hiển thị.
    struct Plain: Equatable {
        var uni: [String: Int] = [:]
        var bi: [String: [String: Int]] = [:]
        var tri: [String: [String: Int]] = [:]
        var manual: [String] = []
        var lastDecay = Date()
    }

    /// File nhị phân thật ứng với đường dẫn gốc (…/userlm.plist → …/userlm.bin).
    static func compactURL(for url: URL) -> URL {
        url.pathExtension == "bin" ? url : url.deletingPathExtension().appendingPathExtension("bin")
    }

    private static func readTables(from url: URL) -> LoadedTables? {
        let bin = compactURL(for: url)
        if let data = try? Data(contentsOf: bin), let d = UserLMCodec.decode(data) {
            // Lần chuyển trước ghi xong nhưng chưa kịp xoá bản cũ.
            if bin != url { try? FileManager.default.removeItem(at: url) }
            return LoadedTables(tables: d.tables, lastDecay: d.lastDecay, manual: d.manual, cases: d.cases)
        }
        // Chưa có (hoặc hỏng) bản nhị phân: đọc bản cũ, chuyển MỘT lần. Bản cũ chỉ bị xoá sau khi
        // file mới đã ghi xong VÀ đọc lại khớp từng byte; ghi hỏng ⇒ giữ nguyên bản cũ, lần sau thử lại.
        guard bin != url, let old = readLegacy(url) else { return nil }
        let tables = UserLMTables(uni: old.uni, bi: old.bi, tri: old.tri)
        if writeVerified(UserLMCodec.encode(tables, lastDecay: old.lastDecay, manual: old.manual), to: bin) {
            try? FileManager.default.removeItem(at: url)
        }
        return LoadedTables(tables: tables, lastDecay: old.lastDecay, manual: old.manual)
    }

    /// Layout cũ: binary plist {version, uni, bi, tri, lastDecay, manual} hoặc JSON v1 (bigram phẳng).
    private struct LegacySnapshot: Codable { var uni: [String: Int]; var bi: [String: Int] }
    static func readLegacy(_ url: URL) -> Plain? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        var p = Plain()
        if let dict = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any],
           let u = dict["uni"] as? [String: Int] {
            p.uni = u
            p.bi = dict["bi"] as? [String: [String: Int]] ?? [:]
            p.tri = dict["tri"] as? [String: [String: Int]] ?? [:]
            p.lastDecay = dict["lastDecay"] as? Date ?? Date()
            p.manual = dict["manual"] as? [String] ?? []
        } else if let old = try? JSONDecoder().decode(LegacySnapshot.self, from: data) {
            // v1 (userlm.json cùng nội dung): bigram phẳng "a␁b" → nested
            p.uni = old.uni
            for (k, c) in old.bi {
                let parts = k.split(separator: Character(sep), maxSplits: 1)
                guard parts.count == 2 else { continue }
                p.bi[String(parts[0]), default: [:]][String(parts[1])] = c
            }
        } else {
            return nil
        }
        return p
    }

    /// Sao lưu / Từ điển: đọc store (nhị phân, hoặc bản cũ chưa chuyển) thành dict. Không ghi gì.
    static func readPlain(at url: URL) -> Plain? {
        if let data = try? Data(contentsOf: compactURL(for: url)), let d = UserLMCodec.decode(data) {
            return Plain(uni: d.tables.uniDict(), bi: d.tables.biDict(), tri: d.tables.triDict(),
                         manual: d.manual, lastDecay: d.lastDecay)
        }
        return compactURL(for: url) == url ? nil : readLegacy(url)
    }

    /// Nhập sao lưu: ghi `p` thành store nhị phân (atomic, đọc lại kiểm tra) rồi bỏ bản cũ.
    @discardableResult
    static func writePlain(_ p: Plain, to url: URL) -> Bool {
        let bin = compactURL(for: url)
        let tables = UserLMTables(uni: p.uni, bi: p.bi, tri: p.tri)
        guard writeVerified(UserLMCodec.encode(tables, lastDecay: p.lastDecay, manual: p.manual), to: bin)
        else { return false }
        if bin != url { try? FileManager.default.removeItem(at: url) }
        return true
    }

    /// Xoá store (bản nhị phân + mọi bản cũ) — "Xoá từ đã học".
    static func removeStore(at url: URL) {
        let fm = FileManager.default
        try? fm.removeItem(at: compactURL(for: url))
        try? fm.removeItem(at: url)
        try? fm.removeItem(at: url.deletingPathExtension().appendingPathExtension("json"))
    }

    private static func writeVerified(_ data: Data, to url: URL) -> Bool {
        do { try data.write(to: url, options: .atomic) } catch { return false }
        return (try? Data(contentsOf: url)) == data
    }

    private struct Snapshot { let tables: UserLMTables; let lastDecay: Date; let manual: [String]; let cases: CaseTable }

    /// Snapshot COW trên main (rẻ — chỉ tăng refcount mảng), encode + ghi atomic trên ioQueue.
    func save() {
        saveWork?.cancel(); saveWork = nil
        guard isLoaded, let url = fileURL else { return }
        let snap = snapshot()
        ioQueue.async { Self.write(snap, to: url) }
    }

    /// Flush cho viewWillDisappear — extension có thể bị suspend/kill ngay sau.
    /// KHÔNG còn ioQueue.sync (chặn main đúng lúc bàn phím đang được ẩn):
    /// - Không có thay đổi chờ ghi (saveWork == nil — mọi mutation đều qua
    ///   scheduleSave()/save()) → khỏi encode + ghi cả file mỗi lần ẩn.
    /// - Ghi enqueue async lên ioQueue NGAY trên main → giữ thứ tự FIFO với các
    ///   save() trước/sau (snapshot cũ không thể ghi đè snapshot mới).
    /// - performExpiringActivity xin iOS thêm thời gian chạy nền cho tới khi ghi
    ///   xong (dùng được trong extension, khác beginBackgroundTask). Hết giờ
    ///   (expired) giữa chừng: .atomic ghi file tạm rồi rename → file cũ nguyên
    ///   vẹn, tệ nhất mất vài count chưa ghi (cache, không phải sổ cái).
    func saveNow() {
        guard saveWork != nil else { return }
        saveWork?.cancel(); saveWork = nil
        guard isLoaded, let url = fileURL else { return }
        let snap = snapshot()
        let done = DispatchSemaphore(value: 0)
        ioQueue.async { Self.write(snap, to: url); done.signal() }
        ProcessInfo.processInfo.performExpiringActivity(
            withReason: "VietTelex: lưu dữ liệu học từ") { expired in
            guard !expired else { return }
            _ = done.wait(timeout: .now() + 10)
        }
    }

    private func snapshot() -> Snapshot {
        Snapshot(tables: t, lastDecay: lastDecay, manual: Array(manual.values), cases: cases)
    }

    private static func write(_ s: Snapshot, to url: URL) {
        let data = UserLMCodec.encode(s.tables, lastDecay: s.lastDecay, manual: s.manual, cases: s.cases)
        let bin = compactURL(for: url)
        try? data.write(to: bin, options: .atomic)
    }

    /// Extension bị kill không báo trước: coalesce 5s sau record cuối, mất tối
    /// đa vài count — đây là cache, không phải sổ cái.
    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.save() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
    }

    /// App chứa: ghi NGAY (đồng bộ) — sau đó mới báo bàn phím nạp lại.
    func saveSync() {
        saveWork?.cancel(); saveWork = nil
        guard isLoaded, let url = fileURL else { return }
        let snap = snapshot()
        ioQueue.sync { Self.write(snap, to: url) }
    }

    /// App đã sửa/xoá store (Từ điển cá nhân / "Xoá từ đã học" — mốc userlmResetAt
    /// trong App Group đổi): bỏ bảng trong RAM, huỷ ghi chờ (không bao giờ ghi đè bản của
    /// app), nạp lại file (vắng ⇒ seed lại).
    func reloadAfterExternalEdit() {
        loadGeneration += 1              // load đang bay (nếu có) bị bỏ kết quả
        saveWork?.cancel(); saveWork = nil
        t = UserLMTables(); manual = [:]; cases = CaseTable()
        pendingRecords = []; pendingSeed = nil
        topCache = nil
        knownCache.removeAll()
        if let url = fileURL {
            isLoaded = false
            pendingSeed = seedSource
            loadAsync(from: url)
        } else {
            isLoaded = true
            if let s = seedSource { applySeed(unigrams: s.uni(), bigrams: s.bi()) }
        }
    }

    func eraseAll() {
        loadGeneration += 1              // load đang bay (nếu có) bị bỏ kết quả
        isLoaded = true
        saveWork?.cancel(); saveWork = nil
        manual = [:]
        t = UserLMTables()
        cases = CaseTable()
        pendingRecords = []; pendingSeed = nil
        topCache = nil
        if let url = fileURL {
            ioQueue.async { Self.removeStore(at: url) }
        }
    }

    // MARK: decay

    /// Hồ sơ phản ánh thói quen GẦN ĐÂY: mỗi ≥7 ngày, count *= 0.7^tuần
    /// (một timestamp toàn cục duy nhất — không lưu thời gian per-từ).
    func decayIfDue(now: Date = Date()) {
        let weeks = Int(now.timeIntervalSince(lastDecay) / (7 * 86400))
        guard weeks >= 1 else { return }
        let f = pow(0.7, Double(weeks))
        t.mapCounts(uni: true, bi: true, tri: true) { Int(Double($0) * f) }
        keepManual()
        t.compact()
        dropOrphanCases()
        lastDecay = now
        topCache = nil
        save()
    }

    /// Quá trần cứng: chia đôi mọi count (từ hiếm rơi về 0 và bị loại).
    private func pruneIfNeeded() {
        let u = t.uniN > Self.uniCap, b = t.biN > Self.biCap, r = t.triN > Self.triCap
        guard u || b || r else { return }
        t.mapCounts(uni: u, bi: b, tri: r) { $0 / 2 }
        if u { keepManual(); topCache = nil }
        t.compact()
        if u { dropOrphanCases() }
    }

    /// Từ rơi khỏi unigram (decay/prune) ⇒ bỏ luôn hoa/thường của nó.
    private func dropOrphanCases() {
        let tt = t
        cases.retain { tt.uni($0) > 0 }
    }

    // MARK: seed bigrams — mồi tĩnh khi chưa có dữ liệu cá nhân

    static let seedNext: [String: [String]] = [
        "anh": ["ơi", "đang", "có", "yêu"],
        "em": ["ơi", "yêu", "đang", "nhé"],
        "chị": ["ơi", "đang", "có"],
        "mẹ": ["ơi", "đang", "có"],
        "bạn": ["ơi", "có", "đang"],
        "mình": ["đang", "có", "sẽ", "nghĩ"],
        "tôi": ["đang", "có", "sẽ", "nghĩ"],
        "cảm": ["ơn"],
        "xin": ["chào", "lỗi", "phép"],
        "chúc": ["mừng", "ngủ", "sức"],
        "không": ["có", "phải", "biết", "sao"],
        "rất": ["vui", "đẹp", "ngon", "tốt"],
        "hôm": ["nay", "qua"],
        "ngày": ["mai", "mới", "nào"],
        "buổi": ["sáng", "trưa", "chiều", "tối"],
        "đi": ["làm", "học", "chơi", "ăn"],
        "ăn": ["cơm", "sáng", "trưa", "tối"],
        "đang": ["làm", "ăn", "đi", "ở"],
        "có": ["khỏe", "thể", "gì", "ai"],
        "làm": ["gì", "việc", "sao"],
        "yêu": ["em", "anh", "quá"],
        "ngủ": ["ngon", "sớm", "dậy"],
        "tạm": ["biệt"],
        "hẹn": ["gặp"],
        "gặp": ["lại", "nhau"],
        "vui": ["quá", "lắm", "vẻ"],
        "được": ["không", "rồi", "chưa"],
        "nhớ": ["em", "anh", "nhé"],
    ]
}

// Bảng gọn `UserLMTables` + codec VTL2 `UserLMCodec`: UserLMTables.swift (dùng chung macOS/Linux).
