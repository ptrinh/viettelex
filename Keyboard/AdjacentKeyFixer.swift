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
    static let neighbors: [Character: [Character]] = {
        var pos: [Character: (row: Int, x: Double)] = [:]
        for (r, row) in rows.enumerated() {
            for (i, k) in row.keys.enumerated() { pos[k] = (r, row.offset + Double(i)) }
        }
        var out: [Character: [Character]] = [:]
        for (k, p) in pos {
            out[k] = pos.filter { other, q in
                other != k && ((q.row == p.row && abs(q.x - p.x) <= 1.01)
                    || (abs(q.row - p.row) == 1 && abs(q.x - p.x) <= 0.6))
            }.map(\.key).sorted()
        }
        return out
    }()

    /// - raw: phím đã gõ của từ hiện tại (chữ ascii).
    /// - compose: raw → dạng hiển thị engine sẽ ra (cùng setting với bàn phím).
    /// - frequency: tần suất trong lexicon, nil = không phải từ.
    /// - hasCompletion: dạng hiển thị còn là TIỀN TỐ của từ nào đó (đang gõ dở) → không sửa.
    static func correction(raw: String,
                           compose: (String) -> String,
                           frequency: (String) -> Int?,
                           hasCompletion: (String) -> Bool) -> String? {
        let keys = Array(raw)
        guard (2...10).contains(keys.count),
              keys.allSatisfy({ $0.isASCII && $0.isLetter }) else { return nil }
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
}
