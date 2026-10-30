// TouchTarget.swift — CHỌN PHÍM THEO NGỮ CẢNH lúc chạm (thử nghiệm, kiểu iOS "dynamic
// touch targets"). Song sinh android/keyboard/src/main/kotlin/com/viettelex/keyboard/
// TouchTarget.kt — sửa ở đây thì sửa y hệt bên kia (tham số chọn bằng mô phỏng gõ chạm
// TouchSimTests bên Android: câu Tatoeba giữ lại, người gõ Gaussian 2D + lệch hệ thống).
//
// Router cũ chọn phím GẦN NHẤT. Ở đây, khi điểm chạm rơi vào VÙNG BIÊN giữa 2 phím, chọn
// argmax P(điểm | phím) · P(phím | các phím Telex đã gõ trong từ) — P ngữ cảnh lấy từ trie
// chuỗi phím Telex dựng từ vnlexicon + enlexicon + seed chat (tần suất). Chống cướp phím:
//  - điểm trong LÕI phím gần nhất ⇒ luôn phím đó (tâm phím luôn thắng);
//  - chỉ xét phím kề mà điểm chạm nằm sát (≤ reach · bề rộng phím);
//  - chỉ đổi khi log-điểm hơn ≥ margin; chuỗi đang gõ ngoài trie ⇒ không đổi.
// Chữ đã chèn KHÔNG bao giờ bị thay: quyết định đúng một lần lúc touchDown.
import Foundation
import CoreGraphics

/// Chuỗi phím Telex cho một âm tiết tiếng Việt (để dựng trie ngữ cảnh).
enum TelexSpell {
    /// Các cách gõ phổ biến kèm tỉ trọng (tổng 1): dấu thanh ở cuối (0.6) hoặc ngay sau
    /// nguyên âm trước phụ âm cuối (0.4); "ươ" gõ "uwow" hoặc "uow". nil nếu ký tự lạ.
    static func variants(_ syllable: String) -> [(keys: String, share: Float)]? {
        var chars: [String] = []
        var tone: Character?
        for u in syllable.lowercased().decomposedStringWithCanonicalMapping.unicodeScalars {
            switch u.value {
            case 0x302:
                guard let k = chars.last else { return nil }
                chars[chars.count - 1] = k + k
            case 0x306, 0x31B:
                guard let k = chars.last else { return nil }
                chars[chars.count - 1] = k + "w"
            case 0x301: tone = "s"
            case 0x300: tone = "f"
            case 0x309: tone = "r"
            case 0x303: tone = "x"
            case 0x323: tone = "j"
            case 0x111: chars.append("dd")
            case 0x61...0x7A: chars.append(String(Character(u)))
            default: return nil
            }
        }
        if chars.isEmpty { return nil }
        var lastVowel = -1
        for (i, c) in chars.enumerated() where "aeiouy".contains(c.first!) { lastVowel = i }
        var cores: [[String]] = [chars]
        if chars.count >= 2 {
            for i in 0..<(chars.count - 1) where chars[i] == "uw" && chars[i + 1] == "ow" {
                var c = chars; c[i] = "u"; cores.append(c)
            }
        }
        var out: [(keys: String, share: Float)] = []
        let share = 1 / Float(cores.count)
        for c in cores {
            let all = c.joined()
            guard let t = tone else { out.append((all, share)); continue }
            let hasCoda = lastVowel >= 0 && lastVowel < c.count - 1
            if !hasCoda { out.append((all + String(t), share)); continue }
            out.append((all + String(t), share * 0.6))
            let head = c[0...lastVowel].joined(), coda = c[(lastVowel + 1)...].joined()
            out.append((head + String(t) + coda, share * 0.4))
        }
        return out
    }
}

/// Trie chuỗi phím a–z, mỗi nút mang tổng trọng số các chuỗi đi qua (CSR gọn).
final class KeyTrie {
    private let edgeStart: [Int32]   // [node] → dải cạnh; count = nodes + 1
    private let edgeKey: [UInt8]     // 0…25, tăng dần trong dải
    private let edgeTo: [Int32]
    private let weights: [Float]

    var nodeCount: Int { weights.count }

    private init(edgeStart: [Int32], edgeKey: [UInt8], edgeTo: [Int32], weights: [Float]) {
        self.edgeStart = edgeStart; self.edgeKey = edgeKey; self.edgeTo = edgeTo; self.weights = weights
    }

    func child(_ node: Int, _ key: Int) -> Int {
        var e = Int(edgeStart[node]); let end = Int(edgeStart[node + 1])
        while e < end {
            let k = Int(edgeKey[e])
            if k == key { return Int(edgeTo[e]) }
            if k > key { return -1 }
            e += 1
        }
        return -1
    }

    /// Nút của chuỗi `raw` (a–z, hoa thường như nhau), -1 nếu không có.
    func node(_ raw: String) -> Int {
        var n = 0
        for u in raw.unicodeScalars {
            var v = Int(u.value)
            if v >= 0x41 && v <= 0x5A { v += 32 }
            let k = v - 0x61
            guard k >= 0 && k < 26 else { return -1 }
            n = child(n, k)
            if n < 0 { return -1 }
        }
        return n
    }

    func weight(_ node: Int) -> Float { weights[node] }

    final class Builder {
        private var children: [Int: Int] = [:]
        private var weights: [Float] = [0]

        func add(_ keys: String, _ w: Float) {
            guard w > 0, !keys.isEmpty,
                  keys.unicodeScalars.allSatisfy({ $0.value >= 0x61 && $0.value <= 0x7A }) else { return }
            var n = 0
            weights[0] += w
            for u in keys.unicodeScalars {
                let key = n * 32 + Int(u.value - 0x61)
                let c: Int
                if let e = children[key] { c = e } else { c = weights.count; weights.append(0); children[key] = c }
                weights[c] += w
                n = c
            }
        }

        func build() -> KeyTrie {
            let n = weights.count
            let edges = children.sorted { $0.key < $1.key }
            var start = [Int32](repeating: 0, count: n + 1)
            for (k, _) in edges { start[k / 32 + 1] += 1 }
            for i in 0..<n { start[i + 1] += start[i] }
            var key = [UInt8](repeating: 0, count: edges.count), to = [Int32](repeating: 0, count: edges.count)
            for (i, e) in edges.enumerated() { key[i] = UInt8(e.key % 32); to[i] = Int32(e.value) }
            return KeyTrie(edgeStart: start, edgeKey: key, edgeTo: to, weights: weights)
        }
    }
}

/// Tham số chọn phím (GIỮ Y HỆT bản Kotlin). Đơn vị: bề rộng / cao MẶT phím gần nhất.
struct TouchTargetParams {
    var sigmaX: Float, sigmaY: Float
    /// Lõi: điểm cách mọi mép > core·bề rộng (cao) ⇒ không bao giờ đổi.
    var coreX: Float, coreY: Float
    /// Phím kề chỉ được xét khi điểm cách mặt phím đó ≤ reach·bề rộng.
    var reach: Float
    /// Log-điểm phím kề phải hơn phím gần nhất ≥ margin (nat).
    var margin: Float
    /// Trộn đều: P = (1-floor)·P_trie + floor/26.
    var floor: Float
}

enum TouchTarget {
    /// σ dò lại 30/10/2026 (TouchSimTests.sigmaSweep, TOUCHSIM_SIGMA=1|test): σy < σx làm tăng lỗi khác hàng
    /// (σ theo cao phím đã gồm phím cao hơn rộng); σx 0.33–0.35 bớt lỗi Việt nhưng tăng đổi nhầm + lỗi chat ⇒ giữ 0.30/0.30.
    static let defaultParams = TouchTargetParams(
        sigmaX: 0.30, sigmaY: 0.30, coreX: 0.25, coreY: 0.25, reach: 0.45, margin: 1.0, floor: 0.20)

    /// `p` trong LÕI mặt phím `r` ⇒ phím đó thắng, khỏi tính gì thêm.
    static func inCore(_ p: CGPoint, _ r: CGRect, _ q: TouchTargetParams = defaultParams) -> Bool {
        let inX = Float(min(p.x - r.minX, r.maxX - p.x)), inY = Float(min(p.y - r.minY, r.maxY - p.y))
        return inX > q.coreX * Float(r.width) && inY > q.coreY * Float(r.height)
    }

    /// Chọn phím chữ cho điểm `p` (đã qua TouchGeometry.keySelectionPoint) khi router
    /// gần-nhất ra `nearest`; `prior` trả P(phím | ngữ cảnh) hoặc nil nếu không biết.
    static func choose(_ p: CGPoint, rects: [CGRect], keys: [Character], nearest: Int,
                       prior: (Character) -> Float?, params q: TouchTargetParams = defaultParams) -> Int {
        guard nearest >= 0, nearest < rects.count, nearest < keys.count else { return nearest }
        let r = rects[nearest]
        let w = Float(r.width), h = Float(r.height)
        guard w > 0, h > 0, isLetter(keys[nearest]), !inCore(p, r, q),
              let p0 = prior(keys[nearest]) else { return nearest }
        var best = nearest
        var bestS = score(p, r, w, h, p0, q) + q.margin
        let lim = CGFloat(q.reach * w)
        for i in rects.indices where i != nearest && i < keys.count && isLetter(keys[i]) {
            let f = rects[i]
            let dx = max(f.minX - p.x, 0, p.x - f.maxX), dy = max(f.minY - p.y, 0, p.y - f.maxY)
            if dx > lim || dy > lim || dx * dx + dy * dy > lim * lim { continue }
            guard let pi = prior(keys[i]) else { continue }
            let s = score(p, f, w, h, pi, q)
            if s > bestS { best = i; bestS = s }
        }
        return best
    }

    /// Chỉ phím chữ a–z tham gia: "." "," "'"… KHÔNG bao giờ bị đổi sang chữ (hay ngược lại) dù prior nói gì.
    @inline(__always) static func isLetter(_ c: Character) -> Bool {
        guard let a = c.asciiValue else { return false }
        return (a >= 0x61 && a <= 0x7A) || (a >= 0x41 && a <= 0x5A)
    }

    private static func score(_ p: CGPoint, _ f: CGRect, _ w: Float, _ h: Float, _ prior: Float,
                              _ q: TouchTargetParams) -> Float {
        let ux = Float(p.x - f.midX) / (q.sigmaX * w)
        let uy = Float(p.y - f.midY) / (q.sigmaY * h)
        let pr = (1 - q.floor) * prior + q.floor / 26
        return -0.5 * (ux * ux + uy * uy) + logf(pr)
    }
}

/// P(phím kế | chuỗi phím Telex đã gõ trong từ) từ trie tần suất.
final class TelexKeyPrior: @unchecked Sendable {
    let trie: KeyTrie
    init(trie: KeyTrie) { self.trie = trie }

    static let maxRaw = 12
    /// Thang tần suất vnlexicon: byte f ≈ 255·ln(count)/ln(max) ⇒ trọng số exp(λ·f).
    static let lambda: Float = 0.06
    /// Tỉ trọng từ tiếng Anh (enlexicon, cùng thang) so với âm tiết Việt.
    static let englishShare: Float = 0.1

    /// Prior theo kiểu gõ: trie dựng theo chuỗi phím TELEX (ee/aw/dd, s f r x j) — VNI
    /// (số là phím dấu) không khớp ⇒ nil, router gần-nhất như cũ. Android: forTyping.
    func forTyping(_ raw: String, vniMode: Bool) -> ((Character) -> Float?)? {
        vniMode ? nil : forRaw(raw)
    }

    /// Hàm prior cho router: nil nếu `raw` ngoài trie (không biết ⇒ không đổi phím).
    func forRaw(_ raw: String) -> ((Character) -> Float?)? {
        guard raw.unicodeScalars.count <= Self.maxRaw else { return nil }
        let n = trie.node(raw)
        guard n >= 0 else { return nil }
        let total = trie.weight(n)
        guard total > 0 else { return nil }
        let trie = self.trie
        return { ch in
            guard let a = ch.lowercased().unicodeScalars.first, ch.unicodeScalars.count == 1 else { return nil }
            let k = Int(a.value) - 0x61
            guard k >= 0 && k < 26 else { return nil }
            let c = trie.child(n, k)
            return c < 0 ? 0 : trie.weight(c) / total
        }
    }

    static func build(syllables: [(String, Int)], english: [(String, Int)] = [], chat: [(String, Int)] = [],
                      lambda: Float = lambda, englishShare: Float = englishShare) -> TelexKeyPrior {
        let b = KeyTrie.Builder()
        for (s, f) in syllables {
            let w = expf(lambda * Float(f - 255))
            for v in TelexSpell.variants(s) ?? [] { b.add(v.keys, w * v.share) }
        }
        if englishShare > 0 { for (word, f) in english { b.add(word, englishShare * expf(lambda * Float(f - 255))) } }
        for (word, f) in chat { b.add(word, expf(lambda * Float(f - 255))) }
        return TelexKeyPrior(trie: b.build())
    }

    /// Seed chat (log, max 50) → thang vnlexicon. Chỉ từ gõ nguyên phím a–z (ko, dc, ok…),
    /// sort theo chữ để thứ tự cộng trọng số giống Kotlin (LinkedHashMap theo file seed —
    /// thứ tự không đổi kết quả ngoài sai số float).
    static func chatWords(_ seed: [String: Int]) -> [(String, Int)] {
        seed.filter { w, _ in !w.isEmpty && w.unicodeScalars.allSatisfy { $0.value >= 0x61 && $0.value <= 0x7A } }
            .map { ($0.key, min(max($0.value * 51 / 10, 0), 255)) }
            .sorted { $0.0 < $1.0 }
    }

    /// Dựng từ vnlexicon + enlexicon + seed chat — vài chục ms, gọi ngoài main thread.
    static func fromLexicon(lambda: Float = lambda, englishShare: Float = englishShare) -> TelexKeyPrior {
        var syl: [(String, Int)] = []
        syl.reserveCapacity(VNLexicon2Data.count)
        for id in 0..<VNLexicon2Data.count { syl.append((VNSuggest.display(id), VNSuggest.freq(id: id))) }
        // Parse riêng (không giữ SwipeEnglish.lexicon trong RAM khi tắt gõ vuốt).
        final class BundleToken {}
        var en: [(String, Int)] = []
        if let url = Bundle(for: BundleToken.self).url(forResource: "enlexicon", withExtension: "bin"),
           let d = try? Data(contentsOf: url, options: .alwaysMapped), let lx = SwipeEnglish.parse(d) {
            en = (0..<lx.count).map { (lx.words[$0], Int(lx.freq[$0])) }
        }
        let chat = chatWords(SeedData.unigrams).filter { !VNSuggest.contains($0.0) }
        return build(syllables: syl, english: en, chat: chat, lambda: lambda, englishShare: englishShare)
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var cached: TelexKeyPrior?

    /// Bảng dùng chung; nil tới khi warmUp xong (router coi như tắt).
    static var sharedIfReady: TelexKeyPrior? { lock.lock(); defer { lock.unlock() }; return cached }

    @discardableResult
    static func warmUp() -> TelexKeyPrior {
        if let c = sharedIfReady { return c }
        let p = fromLexicon()
        lock.lock(); defer { lock.unlock() }
        if let c = cached { return c }
        cached = p
        return p
    }

    /// Dựng nền (utility queue) nếu chưa có.
    static func warmUpInBackground() {
        guard sharedIfReady == nil else { return }
        DispatchQueue.global(qos: .utility).async { warmUp() }
    }
}
