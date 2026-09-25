// AdjacentKeyFixer — gợi ý sửa lỗi CHẠM TRƯỢT sang phím kề (feature flag, 25/09/2026).
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
        // 1 sửa. Đảo 2 phím liền nhau XÉT TRƯỚC và thắng nếu có: nó giữ nguyên đúng
        // bộ phím đã bấm — bằng chứng mạnh hơn thay phím ("cahcs" → cách, không phải
        // "các" dù "các" phổ biến hơn).
        for i in lower.indices.dropLast() where lower[i] != lower[i + 1] {
            var c = lower; c.swapAt(i, i + 1); consider(c)
        }
        if best == nil {
            for i in lower.indices {
                for n in neighbors[lower[i]] ?? [] { var c = lower; c[i] = n; consider(c) }
            }
        }
        // 2 sửa (chỉ khi 1 sửa không ra, từ ngắn — ~n²·25 lần compose, vẫn < 1 ms).
        if best == nil, lower.count <= 8 {
            for i in lower.indices {
                for j in lower.indices where j > i {
                    for a in neighbors[lower[i]] ?? [] {
                        for b in neighbors[lower[j]] ?? [] {
                            var c = lower; c[i] = a; c[j] = b; consider(c)
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
}
