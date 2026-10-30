// Typist.swift — biến câu đích thành phím Telex như người thật gõ.
//
// • Từ Việt: â=aa ê=ee ô=oo ă=aw ơ=ow ư=uw đ=dd; ươ gõ "uow" (55%) hoặc "uwow"; ư đứng riêng
//   đôi khi gõ một phím "w" (12%: "nhw" → như). Phím thanh (s f r x j): cuối từ 75%, ngay sau
//   nguyên âm cuối của vần (trước phụ âm cuối) 13%, ngay sau nguyên âm mang dấu 12%.
//   Hoa: chữ đầu hoa thì phím nhân đôi/phím thanh thường ("Aas"); từ VIẾT HOA cả ⇒ mọi phím hoa.
// • Từ Anh: gõ nguyên văn.
// • Lỗi gõ: ~3% số từ (seed theo câu ⇒ tất định) — thay bằng phím kề (QWERTY), chèn phím kề,
//   đảo hai phím, gõ lặp. Người gõ gõ tiếp 0–2 phím rồi mới thấy, ⌫ cho tới khi chữ TRÊN MÀN
//   HÌNH trùng một tiền tố đúng, rồi gõ lại phần còn lại (đi đúng đường ⌫ của engine).

import Foundation

/// SplitMix64 — tất định, không phụ thuộc nền tảng.
public struct SplitMix64: Sendable {
    private var state: UInt64
    public init(seed: UInt64) { state = seed }
    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    /// [0, 1)
    public mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
    public mutating func below(_ n: Int) -> Int { Int(next() % UInt64(max(n, 1))) }
}

/// FNV-1a 64 trên UTF-8 — seed theo nội dung câu (thứ tự file không ảnh hưởng).
func fnv1a(_ s: String) -> UInt64 {
    var h: UInt64 = 0xcbf2_9ce4_8422_2325
    for b in s.utf8 { h ^= UInt64(b); h = h &* 0x100_0000_01b3 }
    return h
}

/// Một lỗi gõ: gõ `typed` (đã sai), rồi sửa về tiền tố đúng dài tối đa `resumeMax`.
struct Typo: Sendable {
    let typed: [Character]
    /// Số phím ĐÚNG mà `typed` đáng lẽ đã gõ (màn hình khớp bản đúng ⇒ người gõ không thấy lỗi).
    let consumed: Int
    let resumeMax: Int
    let kind: String
}

/// Kế hoạch gõ một từ ở chế độ Việt (IME bật).
struct WordPlan: Sendable {
    let intended: [Character]     // chuỗi phím đúng
    let typo: Typo?
}

public struct TypistOptions: Sendable {
    public var typoRate = 0.03
    public var toneEnd = 0.75, toneAfterNucleus = 0.13       // còn lại: sau nguyên âm mang dấu
    public var uowShort = 0.55, loneW = 0.12
    public init() {}
}

enum Typist {
    private static let toneKey: [UInt32: Character] = [0x301: "s", 0x300: "f", 0x309: "r", 0x303: "x", 0x323: "j"]

    private struct Unit { var keys: [Character]; var base: Character; var vowel: Bool; var tone: Bool; var mark: UInt32 }

    /// Phím Telex của một từ Việt. nil nếu có ký tự không gõ được bằng Telex.
    static func telexKeys(_ word: String, _ rng: inout SplitMix64, _ o: TypistOptions) -> [Character]? {
        let letters = Array(word)
        let allCaps = letters.count > 1 && letters.allSatisfy { $0.isUppercase }
        var units: [Unit] = []
        var tone: Character?
        for ch in letters {
            if ch == "đ" || ch == "Đ" {
                let upper = ch == "Đ"
                units.append(Unit(keys: upper ? (allCaps ? ["D", "D"] : ["D", "d"]) : ["d", "d"],
                                  base: "d", vowel: false, tone: false, mark: 0))
                continue
            }
            let sc = Array(String(ch).decomposedStringWithCanonicalMapping.unicodeScalars)
            guard let b0 = sc.first, b0.isASCII, Character(b0).isLetter else { return nil }
            let base = Character(b0)
            let lower = Character(base.lowercased())
            let second: (Character) -> Character = { c in allCaps ? Character(c.uppercased()) : c }
            // Chữ w THẬT trong từ Việt (teencode "wá" = quá): Telex chuẩn phải gõ "ww" (một w là ư).
            var keys: [Character] = lower == "w" ? [base, second("w")] : [base]
            var hasTone = false, mark: UInt32 = 0
            for m in sc.dropFirst() {
                if let t = toneKey[m.value] { tone = allCaps ? Character(t.uppercased()) : t; hasTone = true; continue }
                switch m.value {
                case 0x302: keys.append(second(lower)); mark = 0x302
                case 0x306, 0x31B: keys.append(second("w")); mark = m.value
                default: return nil
                }
            }
            units.append(Unit(keys: keys, base: lower, vowel: "aeiouy".contains(lower), tone: hasTone, mark: mark))
        }
        // Âm đệm thuộc phụ âm đầu: "qu", "gi" + nguyên âm.
        if units.count > 2, units[0].base == "q", units[1].base == "u" { units[1].vowel = false }
        if units.count > 2, units[0].base == "g", units[1].base == "i", units[2].vowel { units[1].vowel = false }
        // ươ / ư đứng riêng.
        for i in units.indices where units[i].base == "u" && units[i].mark == 0x31B {
            if i + 1 < units.count, units[i + 1].base == "o", units[i + 1].mark == 0x31B {
                if rng.unit() < o.uowShort { units[i].keys = [units[i].keys[0]] }      // "uow"
            } else if rng.unit() < o.loneW, i == 0 || !units[i - 1].vowel {
                let up = units[i].keys[0].isUppercase
                units[i].keys = [up ? "W" : "w"]                                      // "nhw"
            }
        }
        var keys: [Character] = []
        var afterTone = -1, afterNucleus = -1
        for u in units {
            keys += u.keys
            if u.tone { afterTone = keys.count }
            if u.vowel { afterNucleus = keys.count }
        }
        if let t = tone {
            let r = rng.unit()
            var at = keys.count
            if r >= o.toneEnd {
                at = r < o.toneEnd + o.toneAfterNucleus ? afterNucleus : afterTone
                if at < 0 { at = keys.count }
            }
            keys.insert(t, at: at)
        }
        return keys
    }

    private static let rows = ["qwertyuiop", "asdfghjkl", "zxcvbnm"].map(Array.init)

    static func neighbor(of c: Character, _ rng: inout SplitMix64) -> Character {
        let lc = Character(c.lowercased())
        for (r, row) in rows.enumerated() {
            guard let i = row.firstIndex(of: lc) else { continue }
            var cands: [Character] = []
            if i > 0 { cands.append(row[i - 1]) }
            if i + 1 < row.count { cands.append(row[i + 1]) }
            if r > 0, i < rows[r - 1].count { cands.append(rows[r - 1][i]) }
            if r + 1 < rows.count, i < rows[r + 1].count { cands.append(rows[r + 1][i]) }
            let n = cands[rng.below(cands.count)]
            return c.isUppercase ? Character(n.uppercased()) : n
        }
        return c
    }

    /// Kế hoạch gõ cả câu (một WordPlan mỗi từ), tất định theo nội dung câu.
    static func plan(_ s: MixedSentence, _ o: TypistOptions) -> [WordPlan] {
        var rng = SplitMix64(seed: fnv1a(s.text))
        var out: [WordPlan] = []
        for (w, eng) in zip(s.words, s.english) {
            let intended: [Character]
            if eng || w.allSatisfy({ $0.isASCII }) {
                intended = Array(w)
            } else {
                intended = telexKeys(w, &rng, o) ?? Array(w)
            }
            var typo: Typo?
            if intended.count >= 2, rng.unit() < o.typoRate {
                typo = makeTypo(intended, &rng)
            }
            out.append(WordPlan(intended: intended, typo: typo))
        }
        return out
    }

    private static func makeTypo(_ k: [Character], _ rng: inout SplitMix64) -> Typo {
        let n = k.count
        let p = rng.below(n)
        let r = rng.unit()
        let extra = { (avail: Int, rng: inout SplitMix64) -> Int in
            let u = rng.unit()
            return min(avail, u < 0.5 ? 0 : (u < 0.85 ? 1 : 2))
        }
        if r < 0.40 {                                           // thay bằng phím kề
            let e = extra(n - p - 1, &rng)
            return Typo(typed: Array(k[0..<p]) + [neighbor(of: k[p], &rng)] + Array(k[(p + 1)..<(p + 1 + e)]),
                        consumed: p + 1 + e, resumeMax: p, kind: "sub")
        } else if r < 0.65 {                                    // chèn phím kề
            let e = extra(n - p, &rng)
            return Typo(typed: Array(k[0..<p]) + [neighbor(of: k[p], &rng)] + Array(k[p..<(p + e)]),
                        consumed: p + e, resumeMax: p, kind: "ins")
        } else if r < 0.85, p + 1 < n {                         // đảo hai phím
            let e = extra(n - p - 2, &rng)
            return Typo(typed: Array(k[0..<p]) + [k[p + 1], k[p]] + Array(k[(p + 2)..<(p + 2 + e)]),
                        consumed: p + 2 + e, resumeMax: p, kind: "swap")
        } else {                                                // gõ lặp
            let e = extra(n - p - 1, &rng)
            return Typo(typed: Array(k[0...p]) + [k[p]] + Array(k[(p + 1)..<(p + 1 + e)]),
                        consumed: p + 1 + e, resumeMax: p + 1, kind: "dup")
        }
    }
}
