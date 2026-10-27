// BẢN SAO NGUYÊN VẸN UserLangModel TRƯỚC khi đổi sang bảng gọn (intern id + file nhị phân VTL2).
// Chỉ dùng trong test: property test so đầu ra cũ ≡ mới, ghi file plist kiểu cũ cho test chuyển
// đổi, làm mốc "trước" khi đo RAM/độ trễ. KHÔNG sửa logic ở đây.
// UserLangModel — datastore cá nhân hóa cho thanh gợi ý. Học từ user hay gõ
// (unigram), cặp từ (bigram) và bộ ba (trigram — tiếng Việt đơn âm tiết nên
// "cảm ơn → nhiều" chỉ trigram mới bắt được) để gợi ý từ ĐẦU CÂU và từ KẾ TIẾP.
//
// Thiết kế theo khảo cứu 2026-07-24 (Gboard/SwiftKey/Grammarly — cache n-gram
// model interpolate với static seed):
// - bi/tri là nested dict (prev → next → count): lookup O(1) mỗi phím, không
//   scan toàn bảng.
// - Ranking = linear interpolation với Bayesian shrinkage λ = n/(n+K): prev
//   mới gặp 1-2 lần thì tin seed tĩnh, gặp nhiều thì tin dữ liệu cá nhân —
//   một lần gõ nhầm không đè được seed curated.
// - "Learning vs suggesting" (Grammarly): từ NGOÀI lexicon phải đạt count ≥3
//   mới được gợi ý (vẫn đếm từ lần đầu) — chặn học typo.
// - Time decay: mỗi ≥7 ngày nhân mọi count với 0.7^tuần lúc load; kèm cap
//   cứng halve-when-full.
// - Persist binary plist (nhanh hơn JSON lúc cold-start), atomic, coalesce 5s.
// - PERF: decode/encode/IO chạy trên serial queue .utility — init trả về ngay,
//   bảng swap-in trên main khi decode xong (~50ms đầu gợi ý rỗng, chấp nhận);
//   record() trong cửa sổ chờ được buffer và phát lại sau swap-in.
//
// PRIVACY: chỉ đếm TẦN SUẤT (không câu, không thứ tự, không timestamp per-từ);
// ô mật khẩu không đi qua đây; toggle "Học từ hay dùng" + nút xóa trong app.
import Foundation

final class LegacyUserLangModel {
    private(set) var uni: [String: Int] = [:]
    private(set) var bi: [String: [String: Int]] = [:]    // prev1 → next → count
    private(set) var tri: [String: [String: Int]] = [:]   // "p2␁p1" → next → count
    private var lastDecay = Date()
    private var biPairs = 0
    private var triPairs = 0
    private var uniTotal = 0        // Σ uni.values — incremental, không reduce mỗi phím
    /// Từ user tự thêm (màn Từ điển cá nhân): key lowercase → dạng hiển thị ("VietTelex").
    private(set) var manual: [String: String] = [:]

    /// Lexicon tĩnh — controller nạp VNLexicon vào; từ trong lexicon được gợi ý
    /// ngay, từ lạ cần đạt ngưỡng. Mặc định false để tests kiểm soát được.
    var isKnownWord: (String) -> Bool = { _ in false } {
        didSet { knownCache.removeAll(); topCache = nil }
    }

    /// Gọi trên main sau khi bảng trên đĩa swap-in xong (controller có thể
    /// refresh thanh gợi ý). Không gọi ở chế độ in-memory (tests).
    var onReady: (() -> Void)?

    private let fileURL: URL?
    private var saveWork: DispatchWorkItem?

    // Encode/decode/IO nền — mọi đọc/ghi bảng vẫn ở main thread.
    private let ioQueue = DispatchQueue(label: "com.viettelex.userlm.legacy.io", qos: .utility)
    private var isLoaded = false
    private var loadGeneration = 0    // eraseAll() giữa chừng → bỏ kết quả load cũ
    private var pendingRecords: [(word: String, prev1: String?, prev2: String?, weight: Int)] = []
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

    /// Store thật trong App Group; truyền nil cho tests (in-memory).
    init(appGroup: String? = AppFlavor.appGroup) {
        if let g = appGroup,
           let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: g) {
            fileURL = dir.appendingPathComponent("userlm.plist")
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
    static func openSharedForEditing(appGroup: String = AppFlavor.appGroup) -> LegacyUserLangModel? {
        guard let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
        else { return nil }
        return LegacyUserLangModel(fileURL: dir.appendingPathComponent("userlm.plist"), synchronous: true)
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

    private func finishLoad(_ t: LoadedTables?) {
        if let t {
            uni = t.uni; bi = t.bi; tri = t.tri; lastDecay = t.lastDecay
            manual = t.manual
            keepManual()
            biPairs = t.biPairs; triPairs = t.triPairs; uniTotal = uni.values.reduce(0, +)
        }
        isLoaded = true
        topCache = nil
        if uni.isEmpty, let seed = pendingSeed {
            applySeed(unigrams: seed.uni(), bigrams: seed.bi())
        }
        pendingSeed = nil
        let queued = pendingRecords
        pendingRecords = []
        for r in queued { record(word: r.word, after: r.prev1, prev2: r.prev2, weight: r.weight) }
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

    @discardableResult
    func record(word: String, after prev1: String?, prev2: String? = nil, weight: Int = 1) -> Learned? {
        guard isLoaded else {
            if pendingRecords.count < Self.pendingRecordCap {
                pendingRecords.append((word, prev1, prev2, weight))
            }
            return nil
        }
        guard Self.learnable(word) else { return nil }
        let w = word.lowercased()
        uni[w, default: 0] += weight
        uniTotal += weight
        bumpTopCache(w)
        var biKey: String?, triKey: String?
        if let p1 = prev1?.lowercased(), Self.learnable(p1) {
            if bi[p1]?[w] == nil { biPairs += 1 }
            bi[p1, default: [:]][w, default: 0] += weight
            biKey = p1
            // trigram chỉ ghi khi cặp (p2,p1) đã có nền — giảm noise/chỗ
            if let p2 = prev2?.lowercased(), Self.learnable(p2),
               (bi[p2]?[p1] ?? 0) >= 2 {
                let key = p2 + Self.sep + p1
                if tri[key]?[w] == nil { triPairs += 1 }
                tri[key, default: [:]][w, default: 0] += weight
                triKey = key
            }
        }
        pruneIfNeeded()
        scheduleSave()
        return Learned(word: w, prev1: biKey, triKey: triKey, weight: weight)
    }

    /// Rút lại một lần `record`. Không âm, bỏ mục về 0. Giống Android `retract`.
    func retract(_ l: Learned) {
        guard let had = uni[l.word] else { return }
        if had <= l.weight { uni.removeValue(forKey: l.word) } else { uni[l.word] = had - l.weight }
        uniTotal -= min(had, l.weight)
        topCache = nil
        func dec(_ m: inout [String: [String: Int]], _ k: String) -> Bool {
            guard let c = m[k]?[l.word] else { return false }
            if c > l.weight { m[k]?[l.word] = c - l.weight; return false }
            m[k]?.removeValue(forKey: l.word)
            if m[k]?.isEmpty == true { m.removeValue(forKey: k) }
            return true
        }
        if let k = l.prev1, dec(&bi, k) { biPairs -= 1 }
        if let k = l.triKey, dec(&tri, k) { triPairs -= 1 }
        scheduleSave()
    }

    /// Từ của người dùng: thêm tay, hoặc đã gõ đủ nhiều để được gợi ý — tự sửa không đụng.
    func isUserWord(_ w: String) -> Bool {
        let k = w.lowercased()
        return manual[k] != nil || (uni[k] ?? 0) >= Self.unknownSuggestThreshold
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
        cachedKnown(w) || manual[w] != nil || (uni[w] ?? 0) >= Self.unknownSuggestThreshold
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
        return uni.compactMap { k, c -> Entry? in
            guard q.isEmpty || Self.fold(k).contains(q) else { return nil }
            return Entry(word: manual[k] ?? k, count: c, manual: manual[k] != nil)
        }.sorted { $0.count != $1.count ? $0.count > $1.count : $0.word.lowercased() < $1.word.lowercased() }
    }

    /// Xoá hẳn một từ: unigram, mọi bigram/trigram có từ đó (ở vị trí trước hay sau), và
    /// dấu "thêm tay". true nếu có gì bị xoá.
    @discardableResult
    func removeWord(_ word: String) -> Bool {
        let w = word.lowercased()
        var changed = manual.removeValue(forKey: w) != nil
        if uni.removeValue(forKey: w) != nil { changed = true }
        if bi.removeValue(forKey: w) != nil { changed = true }
        for k in Array(bi.keys) where bi[k]?[w] != nil {
            bi[k]?[w] = nil; changed = true
            if bi[k]?.isEmpty == true { bi[k] = nil }
        }
        for k in Array(tri.keys) {
            if k.components(separatedBy: Self.sep).contains(w) { tri[k] = nil; changed = true; continue }
            if tri[k]?[w] != nil {
                tri[k]?[w] = nil; changed = true
                if tri[k]?.isEmpty == true { tri[k] = nil }
            }
        }
        guard changed else { return false }
        biPairs = bi.values.reduce(0) { $0 + $1.count }
        triPairs = tri.values.reduce(0) { $0 + $1.count }
        uniTotal = uni.values.reduce(0, +)
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
        let had = uni[w] ?? 0
        if had < Self.manualCount { uni[w] = Self.manualCount; uniTotal += Self.manualCount - had }
        topCache = nil
        scheduleSave()
        return true
    }

    /// Từ thêm tay khớp tiền tố đang gõ (bỏ dấu, không phân biệt hoa/thường), dạng hiển thị.
    func manualCompletions(_ prefix: String, limit: Int = 2) -> [String] {
        guard !manual.isEmpty, !prefix.isEmpty else { return [] }
        let f = Self.fold(prefix)
        return manual.filter { k, d in d != prefix && Self.fold(k).hasPrefix(f) }
            .sorted { a, b in
                let ca = uni[a.key] ?? 0, cb = uni[b.key] ?? 0
                return ca != cb ? ca > cb : a.key < b.key
            }
            .prefix(limit).map { $0.value }
    }

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
        for k in manual.keys where (uni[k] ?? 0) < 1 { uni[k] = 1 }
    }

    // MARK: gợi ý

    /// Top từ user hay dùng nhất — cho field trống chưa gõ gì.
    /// Cached: chỉ tính lại sau record/decay/prune/seed; sort trước rồi mới
    /// chạy suggestable() (memoized) trên phần đầu bảng — không probe lexicon
    /// cho cả ~3000 từ.
    func topWords(limit: Int) -> [String] {
        if let c = topCache, c.k >= limit { return Array(c.words.prefix(limit)) }
        let sorted = uni.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
        var keys: [String] = [], out: [String] = []
        out.reserveCapacity(limit)
        for (w, _) in sorted where suggestable(w) {
            keys.append(w)
            out.append(manual[w] ?? w)
            if out.count >= limit { break }
        }
        topCache = (limit, keys, out)
        return out
    }

    #if DEBUG
    /// Test hook: bảng unigram (khoá chữ thường → count).
    func debugUnigrams() -> [String: Int] { uni }
    #endif

    /// `w` vừa tăng count: cập nhật top-K TẠI CHỖ (K ≤ ~20) thay vì bỏ cache — trước đây
    /// mỗi dấu cách sort lại tới 3000 từ trên main (topWords ở padWords sau mỗi từ).
    /// Thứ tự giống hệt sort đầy đủ: count giảm dần, hoà theo khoá tăng dần.
    private func bumpTopCache(_ w: String) {
        guard var c = topCache else { return }
        let n = uni[w] ?? 0
        func before(_ a: String, _ ca: Int, _ b: String) -> Bool {
            let cb = uni[b] ?? 0
            return ca != cb ? ca > cb : a < b
        }
        if let i = c.keys.firstIndex(of: w) {
            c.keys.remove(at: i); c.words.remove(at: i)
        } else if !suggestable(w) {
            return
        } else if c.keys.count >= c.k, let last = c.keys.last, !before(w, n, last) {
            return                                  // vẫn không lọt top-K
        }
        let j = c.keys.firstIndex { !before($0, uni[$0] ?? 0, w) } ?? c.keys.count
        c.keys.insert(w, at: j); c.words.insert(manual[w] ?? w, at: j)
        if c.keys.count > c.k { c.keys.removeLast(); c.words.removeLast() }
        topCache = c
    }

    /// Từ kế tiếp sau (prev2, prev1): interpolation trigram ⊕ bigram ⊕ unigram
    /// ⊕ seed tĩnh, mỗi tầng có shrinkage riêng.
    func nextWords(after prev1: String, prev2: String? = nil, limit: Int) -> [String] {
        let p1 = prev1.lowercased()
        let biBucket = bi[p1] ?? [:]
        let triBucket = prev2.flatMap { tri[$0.lowercased() + Self.sep + p1] } ?? [:]
        let seeds = Self.seedNext[p1] ?? []

        let biTotal = biBucket.values.reduce(0, +)
        let triTotal = triBucket.values.reduce(0, +)
        let uniTotal = max(self.uniTotal, 1)
        let lamTri = Double(triTotal) / (Double(triTotal) + 2)
        let lamBi = Double(biTotal) / (Double(biTotal) + 4)

        var cands = Set(biBucket.keys).union(triBucket.keys).union(seeds)
        cands = cands.filter { suggestable($0) || seeds.contains($0) }

        func score(_ w: String) -> Double {
            let pTri = triTotal > 0 ? Double(triBucket[w] ?? 0) / Double(triTotal) : 0
            let pBi = biTotal > 0 ? Double(biBucket[w] ?? 0) / Double(biTotal) : 0
            let pUni = Double(uni[w] ?? 0) / Double(uniTotal)
            let pSeed: Double = seeds.firstIndex(of: w).map { pow(0.5, Double($0)) } ?? 0
            return lamTri * pTri
                + lamBi * pBi
                + 0.1 * pUni
                + (1 - lamBi) * 0.9 * pSeed
        }
        // score() tính MỘT lần mỗi từ (comparator gọi score bên trong sorted{}
        // là 2·n·log n lượt) rồi sort tuple.
        return cands.map { ($0, score($0)) }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }
            .prefix(limit).map { manual[$0.0] ?? $0.0 }
    }

    /// Điểm cá nhân của một từ (re-rank completion của lexicon).
    /// Key trong uni đã lowercase sẵn — chỉ alloc lowercased khi lookup thô miss.
    func count(of word: String) -> Int { uni[word] ?? uni[word.lowercased()] ?? 0 }

    /// Số lần cặp (prev → word) đã gặp (bigram cá nhân + seed) — AddTones chấm lưới âm tiết.
    func bigramCount(_ prev: String, _ word: String) -> Int { bi[prev.lowercased()]?[word] ?? 0 }

    /// Số lần bộ ba (prev2, prev → word) người dùng đã gõ (không có seed) — thanh gợi ý ưu tiên.
    func trigramCount(_ prev2: String, _ prev: String, _ word: String) -> Int {
        guard let t = tri[prev2.lowercased() + Self.sep + prev.lowercased()] else { return 0 }
        return t[word] ?? t[word.lowercased()] ?? 0
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
        guard uni.isEmpty else { return }
        applySeed(unigrams: unigrams(), bigrams: bigrams())
    }

    private func applySeed(unigrams: [String: Int], bigrams: [(String, String, Int)]) {
        uni = unigrams
        uniTotal = unigrams.values.reduce(0, +)
        for (a, b, c) in bigrams {
            if bi[a]?[b] == nil { biPairs += 1 }
            bi[a, default: [:]][b] = c
        }
        topCache = nil
        save()
    }

    // MARK: persistence (binary plist — cold-start nhanh hơn JSON)

    // Layout trên đĩa TRÙNG với PropertyListEncoder(Snapshot) v2 cũ
    // {version, uni, bi, tri, lastDecay} — đọc/ghi qua PropertyListSerialization
    // (nhanh hơn Codable nhiều lần), user cũ đọc thẳng không cần migrate.
    private struct LoadedTables {
        var uni: [String: Int]
        var bi: [String: [String: Int]]
        var tri: [String: [String: Int]]
        var lastDecay: Date
        var biPairs: Int
        var triPairs: Int
        var uniTotal: Int
        var manual: [String: String]
    }
    private struct LegacySnapshot: Codable { var uni: [String: Int]; var bi: [String: Int] }

    private static func readTables(from url: URL) -> LoadedTables? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        var uni: [String: Int] = [:]
        var bi: [String: [String: Int]] = [:]
        var tri: [String: [String: Int]] = [:]
        var lastDecay = Date()
        var manual: [String: String] = [:]
        if let dict = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any],
           let u = dict["uni"] as? [String: Int] {
            uni = u
            bi = dict["bi"] as? [String: [String: Int]] ?? [:]
            tri = dict["tri"] as? [String: [String: Int]] ?? [:]
            lastDecay = dict["lastDecay"] as? Date ?? Date()
            for d in dict["manual"] as? [String] ?? [] { manual[d.lowercased()] = d }
        } else if let old = try? JSONDecoder().decode(LegacySnapshot.self, from: data) {
            // v1 (userlm.json cùng nội dung): migrate bigram phẳng → nested
            uni = old.uni
            for (k, c) in old.bi {
                let parts = k.split(separator: Character(sep), maxSplits: 1)
                guard parts.count == 2 else { continue }
                bi[String(parts[0]), default: [:]][String(parts[1])] = c
            }
        } else {
            return nil
        }
        return LoadedTables(
            uni: uni, bi: bi, tri: tri, lastDecay: lastDecay,
            biPairs: bi.values.reduce(0) { $0 + $1.count },
            triPairs: tri.values.reduce(0) { $0 + $1.count },
            uniTotal: uni.values.reduce(0, +),
            manual: manual
        )
    }

    /// Snapshot COW trên main (rẻ), encode + ghi atomic trên ioQueue.
    func save() {
        saveWork?.cancel(); saveWork = nil
        guard isLoaded, let url = fileURL else { return }
        let snap = snapshotPlist()
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
        let snap = snapshotPlist()
        let done = DispatchSemaphore(value: 0)
        ioQueue.async { Self.write(snap, to: url); done.signal() }
        ProcessInfo.processInfo.performExpiringActivity(
            withReason: "VietTelex: lưu dữ liệu học từ") { expired in
            guard !expired else { return }
            _ = done.wait(timeout: .now() + 10)
        }
    }

    private func snapshotPlist() -> [String: Any] {
        // "manual" (từ thêm tay) — key mới, bản cũ đọc bỏ qua.
        ["version": 3, "uni": uni, "bi": bi, "tri": tri, "lastDecay": lastDecay,
         "manual": Array(manual.values)]
    }

    private static func write(_ plist: [String: Any], to url: URL) {
        guard let data = try? PropertyListSerialization.data(
            fromPropertyList: plist, format: .binary, options: 0)
        else { return }
        try? data.write(to: url, options: .atomic)
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
        let snap = snapshotPlist()
        ioQueue.sync { Self.write(snap, to: url) }
    }

    /// App đã sửa/xoá userlm.plist (Từ điển cá nhân / "Xóa từ đã học" — mốc userlmResetAt
    /// trong App Group đổi): bỏ bảng trong RAM, huỷ ghi chờ (không bao giờ ghi đè bản của
    /// app), nạp lại file (vắng ⇒ seed lại).
    func reloadAfterExternalEdit() {
        loadGeneration += 1              // load đang bay (nếu có) bị bỏ kết quả
        saveWork?.cancel(); saveWork = nil
        uni = [:]; bi = [:]; tri = [:]; manual = [:]; biPairs = 0; triPairs = 0; uniTotal = 0
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
        uni = [:]; bi = [:]; tri = [:]; biPairs = 0; triPairs = 0; uniTotal = 0
        pendingRecords = []; pendingSeed = nil
        topCache = nil
        if let url = fileURL {
            ioQueue.async { try? FileManager.default.removeItem(at: url) }
        }
    }

    // MARK: decay

    /// Hồ sơ phản ánh thói quen GẦN ĐÂY: mỗi ≥7 ngày, count *= 0.7^tuần
    /// (một timestamp toàn cục duy nhất — không lưu thời gian per-từ).
    func decayIfDue(now: Date = Date()) {
        let weeks = Int(now.timeIntervalSince(lastDecay) / (7 * 86400))
        guard weeks >= 1 else { return }
        let f = pow(0.7, Double(weeks))
        func decayed(_ c: Int) -> Int? { let v = Int(Double(c) * f); return v > 0 ? v : nil }
        uni = uni.compactMapValues(decayed)
        bi = bi.compactMapValues { inner in
            let d = inner.compactMapValues(decayed); return d.isEmpty ? nil : d
        }
        tri = tri.compactMapValues { inner in
            let d = inner.compactMapValues(decayed); return d.isEmpty ? nil : d
        }
        keepManual()
        biPairs = bi.values.reduce(0) { $0 + $1.count }
        triPairs = tri.values.reduce(0) { $0 + $1.count }
        uniTotal = uni.values.reduce(0, +)
        lastDecay = now
        topCache = nil
        save()
    }

    /// Quá trần cứng: chia đôi mọi count (từ hiếm rơi về 0 và bị loại).
    private func pruneIfNeeded() {
        if uni.count > Self.uniCap {
            uni = uni.compactMapValues { $0 / 2 == 0 ? nil : $0 / 2 }
            keepManual()
            uniTotal = uni.values.reduce(0, +)
            topCache = nil
        }
        if biPairs > Self.biCap {
            bi = bi.compactMapValues { inner in
                let d = inner.compactMapValues { $0 / 2 == 0 ? nil : $0 / 2 }
                return d.isEmpty ? nil : d
            }
            biPairs = bi.values.reduce(0) { $0 + $1.count }
        }
        if triPairs > Self.triCap {
            tri = tri.compactMapValues { inner in
                let d = inner.compactMapValues { $0 / 2 == 0 ? nil : $0 / 2 }
                return d.isEmpty ? nil : d
            }
            triPairs = tri.values.reduce(0) { $0 + $1.count }
        }
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
