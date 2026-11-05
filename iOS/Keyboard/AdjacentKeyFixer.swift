// AdjacentKeyFixer — gợi ý sửa lỗi CHẠM TRƯỢT sang phím kề (25/09/2026; mặc định BẬT,
// tắt ở app → Kiểu Gõ).
//
// Gõ nhanh trên iPhone hay trượt sang phím bên cạnh: "nbjeeuf" (nhiều: h→b, i→j),
// "ohims" (phím: p→o), "nayd" (này: f→d), "cahcs" (cách: đảo 2 phím). Khi từ đang gõ
// KHÔNG khớp từ nào trong lexicon (kể cả làm tiền tố), thử thay phím bằng phím kề
// (1 phím, rồi 2 phím) và đảo 2 phím liền nhau; chọn phương án ÍT sửa nhất, rồi
// tần suất cao nhất. Không tự thay — chỉ đưa lên thanh gợi ý (maintainer chốt).
// Pure: engine + lexicon được tiêm qua closure — pinned by AdjacentKeyFixerTests.
import Foundation

enum AdjacentKeyFixer {
    /// QWERTY iPhone: hàng 2 thụt 0.5 phím, hàng 3 (sau shift) thụt 1.5 phím.
    private static let rows: [(keys: [Character], offset: Double)] = [
        (Array("qwertyuiop"), 0), (Array("asdfghjkl"), 0.5), (Array("zxcvbnm"), 1.5),
    ]

    /// Phím kề: cùng hàng ±1, hàng trên/dưới có tâm lệch ≤ 0.6 phím.
    static let neighbors: [Character: [Character]] = neighborTable(rows)

    /// Bàn phím CỨNG (Mac, ANSI/ISO): hàng giữa thụt 0.25 phím, hàng dưới 0.75; phím hàng
    /// kề lệch ≤ 0.8 phím là kề (hai phím chéo trên/dưới) — "g" kề "t" "y" "v" "b", "z" kề "a" "s".
    static let physicalNeighbors: [Character: [Character]] = neighborTable([
        (Array("qwertyuiop"), 0), (Array("asdfghjkl"), 0.25), (Array("zxcvbnm"), 0.75),
    ], diagonal: 0.8)

    private static func neighborTable(_ rows: [(keys: [Character], offset: Double)],
                                      diagonal: Double = 0.6) -> [Character: [Character]] {
        var pos: [Character: (row: Int, x: Double)] = [:]
        for (r, row) in rows.enumerated() {
            for (i, k) in row.keys.enumerated() { pos[k] = (r, row.offset + Double(i)) }
        }
        var out: [Character: [Character]] = [:]
        for (k, p) in pos {
            out[k] = pos.filter { other, q in
                other != k && ((q.row == p.row && abs(q.x - p.x) <= 1.01)
                    || (abs(q.row - p.row) == 1 && abs(q.x - p.x) <= diagonal))
            }.map(\.key).sorted()
        }
        return out
    }

    /// - raw: phím đã gõ của từ hiện tại (chữ ascii; VNI thêm số mang dấu).
    /// - compose: raw → dạng hiển thị engine sẽ ra (cùng setting với bàn phím).
    /// - frequency: tần suất trong lexicon, nil = không phải từ.
    /// - hasCompletion: dạng hiển thị còn là TIỀN TỐ của từ nào đó (đang gõ dở) → không sửa.
    static func correction(raw: String,
                           compose: (String) -> String,
                           frequency: (String) -> Int?,
                           hasCompletion: (String) -> Bool) -> String? {
        let keys = Array(raw)
        guard (2...10).contains(keys.count),
              // số chỉ có ở VNI (phím dấu 1–9/0): giữ nguyên chỗ, không có phím kề
              keys.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return nil }
        let lower = keys.map { Character($0.lowercased()) }
        let current = compose(String(lower))
        if frequency(current) != nil || hasCompletion(current) { return nil }

        var best: (word: String, freq: Int)?
        func consider(_ cand: [Character]) {
            let w = compose(String(cand))
            guard w != current, let f = frequency(w) else { return }
            if best == nil || f > best!.freq { best = (w, f) }
        }
        // Cắt tỉa theo TIỀN TỐ CHẾT: tiền tố raw[0...k] (bỏ dấu THANH — phím thanh
        // gõ sau có thể đổi/xoá thanh, "cuxmj" → cụm) không còn là tiền tố của từ
        // nào thì phím gõ thêm chỉ thu hẹp thêm → mọi chỗ sửa phải ≤ chỗ chết đầu tiên. Trước đây thử mù ~n²·25
        // lần compose (5–11 ms/phím với từ tiếng Anh dài như "keyboard"); giờ phần
        // lớn nhánh chết sau 1–2 phím. Đối chiếu brute-force trên 1500 biến thể
        // chạm trượt: kết quả trùng 100% (25/09/2026).
        var alive: [String: Bool] = [:]
        func isAlive(_ p: ArraySlice<Character>) -> Bool {
            let key = String(p)
            if let v = alive[key] { return v }
            let v = hasCompletion(stripTones(compose(key)))
            alive[key] = v
            return v
        }
        /// Chỉ số đầu tiên k ≥ from mà c[0...k] chết; c.count nếu sống hết.
        func firstDead(_ c: [Character], from: Int) -> Int {
            var k = from
            while k < c.count, isAlive(c[...k]) { k += 1 }
            return k
        }
        let dead0 = firstDead(lower, from: 0)
        let editable = lower.indices.filter { $0 <= dead0 }
        // 1 sửa. Đảo 2 phím liền nhau XÉT TRƯỚC và thắng nếu có: nó giữ nguyên đúng
        // bộ phím đã bấm — bằng chứng mạnh hơn thay phím ("cahcs" → cách, không phải
        // "các" dù "các" phổ biến hơn).
        for i in editable where i + 1 < lower.count && lower[i] != lower[i + 1] {
            var c = lower; c.swapAt(i, i + 1); consider(c)
        }
        if best == nil {
            for i in editable {
                for n in neighbors[lower[i]] ?? [] { var c = lower; c[i] = n; consider(c) }
            }
        }
        // 2 sửa (chỉ khi 1 sửa không ra): i ≤ chỗ chết của raw gốc, j ≤ chỗ chết
        // sau khi đã sửa i.
        if best == nil, lower.count <= 8 {
            for i in editable {
                for a in neighbors[lower[i]] ?? [] {
                    var ci = lower; ci[i] = a
                    let deadI = firstDead(ci, from: i)
                    guard deadI > i else { continue }        // sửa i vẫn chết ngay tại i
                    for j in lower.indices where j > i && j <= deadI {
                        for b in neighbors[lower[j]] ?? [] {
                            var c = ci; c[j] = b; consider(c)
                        }
                    }
                }
            }
        }
        guard var w = best?.word else { return nil }
        if keys.first?.isUppercase == true, let f = w.first {       // giữ hoa đầu câu
            w = f.uppercased() + w.dropFirst()
        }
        return w
    }

    /// Chạm trượt MÀ VẪN RA TỪ HỢP LỆ — `correction` chỉ chạy khi không khớp gì nên bỏ
    /// sót: "casn" (ý là "caan" → cân, a trượt sang s) ra "cán". Phím thanh Telex s/f/r/x/j
    /// nằm giữa hàng chữ, cạnh nguyên âm. Thử thay MỘT phím thanh giữa từ (đứng sau nguyên
    /// âm, không phải phím cuối) bằng phím kề; nhận ứng viên phổ biến ít nhất bằng từ đang
    /// ra; ưu tiên nhân đôi nguyên âm ("as" ⇐ "aa"), rồi tần suất. Chỉ gợi ý (slot 3).
    /// Đo heldout 13.9k từ: bắt 76/85 ca aa/ee→s; gợi ý thừa ~0.4% từ (chỉ khi gõ dấu giữa từ).
    static func toneSlipCorrection(raw: String, compose: (String) -> String,
                                   frequency: (String) -> Int?) -> String? {
        let keys = Array(raw)
        guard (3...10).contains(keys.count),
              keys.allSatisfy({ $0.isASCII && $0.isLetter }) else { return nil }
        let lower = keys.map { Character($0.lowercased()) }
        let current = compose(String(lower))
        guard let curFreq = frequency(current) else { return nil }
        var best: String?
        var bestKey = -1
        for i in 1..<(lower.count - 1) {
            // phím thanh phải đứng sau nguyên âm (hoặc w): "tr" trong "tre" là phụ âm
            guard "sfrxj".contains(lower[i]), "aeiouyw".contains(lower[i - 1]) else { continue }
            for n in neighbors[lower[i]] ?? [] {
                var c = lower; c[i] = n
                let w = compose(String(c))
                guard w != current, let f = frequency(w) else { continue }
                let doubled = n == lower[i - 1] && "aeo".contains(n)
                // nhân đôi nguyên âm là bằng chứng mạnh: nhận cả ứng viên kém phổ biến hơn chút
                guard f >= curFreq - (doubled ? 10 : 0) else { continue }
                let key = (doubled ? 1 << 16 : 0) + f
                if key > bestKey { best = w; bestKey = key }
            }
        }
        guard var w = best else { return nil }
        if keys[0].isUppercase, let f = w.first { w = f.uppercased() + w.dropFirst() }
        return w
    }

    /// Ứng viên MỘT sửa: thay phím thứ `pos` bằng phím kề `key` ra từ `word`. `deletion`: bỏ phím
    /// thứ `pos` (chạm đúp — AutoCorrect.repeatCandidates); khi đó `key` = chính phím bị bỏ.
    struct Candidate: Equatable {
        let word: String
        let freq: Int
        let pos: Int
        let key: Character
        var deletion = false
    }

    /// MỌI cách thay đúng MỘT phím của `lower` (chữ thường) bằng phím kề ra từ hợp lệ (một từ có
    /// thể xuất hiện nhiều lần, khác vị trí). Không xét đảo phím: mô phỏng không có bằng chứng
    /// chạm cho nó và sửa oan tiếng lóng ("nma" → nam). Cắt tỉa tiền tố chết như `correction`.
    /// Dùng cho AutoCorrect (cần cả ứng viên thứ hai để đo độ chắc).
    /// `neighbors`: bảng phím kề — mặc định bàn phím iPhone; macOS truyền `physicalNeighbors`.
    static func oneEditCandidates(_ lower: String, compose: (String) -> String,
                                  frequency: (String) -> Int?,
                                  hasCompletion: (String) -> Bool,
                                  neighbors: [Character: [Character]] = neighbors) -> [Candidate] {
        let c0 = Array(lower)
        let current = compose(lower)
        var out: [Candidate] = []
        var k = 0
        while k < c0.count, hasCompletion(stripTones(compose(String(c0[...k])))) { k += 1 }
        for i in c0.indices where i <= k {
            for n in neighbors[c0[i]] ?? [] {
                var c = c0; c[i] = n
                let w = compose(String(c))
                guard w != current, let f = frequency(w) else { continue }
                out.append(Candidate(word: w, freq: f, pos: i, key: n))
            }
        }
        return out
    }

    /// Toạ độ tâm phím trên lưới QWERTY (hàng, cột theo bước phím) — cho AutoCorrect.evidence.
    static func keyPosition(_ c: Character) -> (row: Int, x: Double)? {
        for (r, row) in rows.enumerated() {
            if let i = row.keys.firstIndex(of: c) { return (r, row.offset + Double(i)) }
        }
        return nil
    }

    /// Bỏ 5 dấu thanh, giữ dấu chữ (ư, â, đ…): "cũm" → "cum". VNSuggest coi thanh
    /// trống là tương thích mọi thanh.
    static func stripTones(_ s: String) -> String {
        let tones: Set<UInt32> = [0x300, 0x301, 0x303, 0x309, 0x323]
        var out = String.UnicodeScalarView()
        for u in s.decomposedStringWithCanonicalMapping.unicodeScalars where !tones.contains(u.value) {
            out.append(u)
        }
        return String(out).precomposedStringWithCanonicalMapping
    }

    /// Bộ nhớ đệm theo PHÍM THÔ (raw) của từ — cùng raw thì cùng kết quả (setting
    /// cố định theo EngineBridge; bridge mới = cache mới). Gõ ⌫ rồi gõ lại, hay
    /// refresh bar (textDidChange, bật/tắt bar) không tính lại. Thread-safe: bàn
    /// phím gọi từ hàng đợi gợi ý nền.
    final class Cache: @unchecked Sendable {
        private let lock = NSLock()
        private var map: [String: String?] = [:]
        private let capacity: Int
        init(capacity: Int = 256) { self.capacity = capacity }

        func value(for raw: String, compute: () -> String?) -> String? {
            lock.lock()
            if let hit = map[raw] { lock.unlock(); return hit }
            lock.unlock()
            let v = compute()
            lock.lock()
            if map.count >= capacity { map.removeAll(keepingCapacity: true) }
            map[raw] = .some(v)
            lock.unlock()
            return v
        }
        var count: Int { lock.lock(); defer { lock.unlock() }; return map.count }
    }

    #if canImport(UIKit)   // EngineBridge chỉ có ở bàn phím iOS
    /// Bản sửa cho từ đang gõ theo đúng setting của `bridge`, qua cache của bridge.
    /// An toàn gọi ngoài main: chỉ dùng composeTrial (engine scratch riêng) + lexicon tĩnh.
    static func lexiconCorrection(raw: String, bridge: EngineBridge) -> String? {
        bridge.adjacentFixCache.value(for: raw) {
            correction(raw: raw,
                       compose: { bridge.composeTrial($0) },
                       frequency: { VNSuggest.frequency(of: $0) },
                       hasCompletion: { !VNSuggest.matches($0, poolLimit: 1).isEmpty })
        }
    }

    /// `toneSlipCorrection` theo setting của `bridge` (Telex; VNI không có phím thanh chữ),
    /// cache chung với `lexiconCorrection` (khoá tách bằng tiền tố).
    static func lexiconToneSlip(raw: String, bridge: EngineBridge) -> String? {
        guard !bridge.vniMode else { return nil }
        return bridge.adjacentFixCache.value(for: "\u{1}" + raw) {
            toneSlipCorrection(raw: raw, compose: { bridge.composeTrial($0) },
                               frequency: { VNSuggest.frequency(of: $0) })
        }
    }
    #endif
}
