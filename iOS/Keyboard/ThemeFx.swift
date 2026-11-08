// Theme JSON tương tác KHÔNG cần mã: "particles" (hạt tự tạo) + "keywords" (từ khoá tự tạo). CHỈ dữ liệu — không biểu
// thức / kịch bản / mã (App Store 2.5.2). Song sinh android/keyboard/.../ThemeFx.kt: cùng luật đọc, cùng chuỗi chuẩn,
// cùng hàm phát hạt (FxRandom chung) — fixture chung theme-json-cases.txt + ca THEMEFX.
//
// "particles" (tuỳ chọn, object; mọi khoá tuỳ chọn — thiếu = mặc định):
//   "glyphs":   ["🍜","🌸"]  1…8 hình, mỗi hình MỘT ký tự hiển thị (một grapheme: emoji, emoji ghép ZWJ, cờ, chữ có dấu…)
//   "shape":    "circle" | "star" | "heart" | "square" | "spark"   (không dùng cùng "glyphs"; thiếu cả hai = "circle")
//   "colors":   ["#FF4D8D", …] 1…8 màu #RRGGBB / #AARRGGBB (hình vẽ + chữ thường; emoji giữ màu riêng). Thiếu = màu nhấn.
//   "count":     1…12   hạt mỗi lần bấm (mặc định 4)
//   "spread":    0…360  độ — góc xoè (mặc định 60; 360 = toả tròn)
//   "direction": -360…360 độ — hướng bay: 0 = lên, 90 = phải, 180 = xuống (mặc định 0)
//   "speed":     20…600 pt/giây (mặc định 120)
//   "gravity":   -800…800 pt/giây² — dương kéo xuống, âm đẩy lên (mặc định 0)
//   "lifeMs":    200…2500 mili-giây sống (mặc định 900) — JSON theme chỉ có số nguyên nên dùng ms thay cho giây
//   "size":      8…48 pt (mặc định 16)
//   "sizeJitter":0…100 % lệch cỡ ngẫu nhiên (mặc định 0)
//   "spin":      -720…720 độ/giây (mặc định 0)
//   "fade":      "out" (mặc định: rõ rồi mờ dần nửa sau) | "inOut" (hiện dần, rồi mờ)
//   "origin":    "key" (phím vừa bấm, mặc định) | "bottom" (mép dưới bàn phím) | "top" (mép trên), x theo phím
// Số ngoài khoảng ⇒ kẹp + cảnh báo clamped; sai kiểu ⇒ wrongType; giá trị lạ / hình không hợp lệ ⇒ badValue; màu sai ⇒
// badColor; khoá lạ ⇒ unknownKey. Dùng: chọn hiệu ứng "Theo giao diện" (KeyEffect.theme — id "theme"), hoặc theme đặt
// "effect":"theme" (áp một lần lúc chọn theme như mọi "effect"). "Theo giao diện" mà theme không có "particles" ⇒
// chùm sao mặc định (ThemeParticles.fallback) theo màu nhấn.
//
// "keywords" (tuỳ chọn, mảng 1…20 mục; rỗng = không có):
//   [{"words": ["yêu","love"], "burst": {…như "particles"…}?, "text": "chữ ngắn ≤ 16"?}, …]
//   "words": 1…8 từ, mỗi từ ≤ 32 ký tự, chỉ CHỮ (có dấu được), tối đa HAI từ cách nhau một dấu cách ("năm mới").
//   Khớp ở RANH GIỚI TỪ (gõ xong từ + cách / dấu câu) như hiệu ứng "Từ khoá": không phân biệt hoa thường, DẤU TIẾNG VIỆT
//   CÓ NGHĨA ("yêu" ≠ "yeu" — muốn khớp cả hai thì ghi cả hai), cụm hai từ khớp với từ liền trước. Từ trùng ở nhiều mục ⇒
//   mục đầu thắng. Từ nhạy cảm (SensitiveWords) không bao giờ nổ. "burst" thiếu ⇒ "particles" của theme, không có thì
//   chùm tim mặc định. "text" bay lên từ phím rồi mờ.
//   Chạy CÙNG mọi hiệu ứng đang chọn (kể cả "Không") khi theme có "keywords" + Plus + không tiết kiệm pin. Theme không có
//   "keywords" ⇒ không tra từ nào (0 chi phí).
//
// Trần (CPU / RAM): ≤ 12 hạt mỗi chùm, chùm xoay vòng ≤ KeyEffectPool.cap hạt sống mỗi hệ (hạt theme / chùm từ khoá);
// animation dựng MỘT lần mỗi chùm (Core Animation chạy phần còn lại); tra từ O(1) mỗi ranh giới; cắt theo bàn phím.
// Bản vá theme có sẵn (KeyStyle) không có "particles" / "keywords" — "Chép JSON" đi nguyên từ đặc tả.
import Foundation

// MARK: - Mô hình

struct ThemeParticles: Equatable {
    var glyphs: [String]? = nil
    var shape: String? = nil
    var colors: [UInt32]? = nil
    var count: Int? = nil
    var spread: Int? = nil
    var direction: Int? = nil
    var speed: Int? = nil
    var gravity: Int? = nil
    var lifeMs: Int? = nil
    var size: Int? = nil
    var sizeJitter: Int? = nil
    var spin: Int? = nil
    var fade: String? = nil
    var origin: String? = nil

    static let shapes = ["circle", "star", "heart", "square", "spark"]
    static let fades = ["out", "inOut"]
    static let origins = ["key", "bottom", "top"]
    static let maxGlyphs = 8
    static let maxColors = 8
    /// Khoảng từng trường số (Android ThemeParticles.RANGES y hệt).
    static let ranges: [(key: String, range: ClosedRange<Int>)] = [
        ("count", 1...12), ("spread", 0...360), ("direction", -360...360), ("speed", 20...600),
        ("gravity", -800...800), ("lifeMs", 200...2500), ("size", 8...48), ("sizeJitter", 0...100), ("spin", -720...720),
    ]
    static let keys: Set<String> = Set(["glyphs", "shape", "colors", "fade", "origin"] + ranges.map(\.key))

    subscript(int k: String) -> Int? {
        get {
            switch k {
            case "count": return count
            case "spread": return spread
            case "direction": return direction
            case "speed": return speed
            case "gravity": return gravity
            case "lifeMs": return lifeMs
            case "size": return size
            case "sizeJitter": return sizeJitter
            case "spin": return spin
            default: return nil
            }
        }
        set {
            switch k {
            case "count": count = newValue
            case "spread": spread = newValue
            case "direction": direction = newValue
            case "speed": speed = newValue
            case "gravity": gravity = newValue
            case "lifeMs": lifeMs = newValue
            case "size": size = newValue
            case "sizeJitter": sizeJitter = newValue
            case "spin": spin = newValue
            default: break
            }
        }
    }

    // Giá trị thực dùng (mặc định khi thiếu).
    var effCount: Int { count ?? 4 }
    var effSpread: Int { spread ?? 60 }
    var effDirection: Int { direction ?? 0 }
    var effSpeed: Int { speed ?? 120 }
    var effGravity: Int { gravity ?? 0 }
    var effLifeMs: Int { lifeMs ?? 900 }
    var effSize: Int { size ?? 16 }
    var effSizeJitter: Int { sizeJitter ?? 0 }
    var effSpin: Int { spin ?? 0 }
    var effShape: String { shape ?? "circle" }
    var fadesIn: Bool { fade == "inOut" }
    var effOrigin: String { origin ?? "key" }
    var life: Double { Double(effLifeMs) / 1000 }

    /// "Theo giao diện" khi theme không có "particles": chùm sao nhỏ theo màu nhấn.
    static let fallback = ThemeParticles(shape: "star", count: 5, spread: 120, speed: 140, gravity: 220, lifeMs: 800,
                                         size: 12, sizeJitter: 30, spin: 180)
    /// Chùm từ khoá khi mục không có "burst" và theme không có "particles": tim toả tròn.
    static let keywordFallback = ThemeParticles(shape: "heart", colors: [0xFFFF3B6B, 0xFFFF7AA2, 0xFFE91E63], count: 8,
                                                spread: 360, speed: 110, gravity: -40, lifeMs: 1000, size: 14,
                                                sizeJitter: 30)

    /// Số chùm xoay vòng (mỗi lần bấm một chùm): tổng hạt sống ≤ KeyEffectPool.cap.
    static func slots(perBurst n: Int) -> Int { max(1, min(8, KeyEffectPool.cap / max(n, 1))) }

    /// Hạt thứ `i` của lần bấm số `seed` — hàm thuần, Android y hệt (cùng FxRandom). Đơn vị pt / giây / radian.
    func particle(_ i: Int, seed: Int) -> ThemeParticle {
        var r = FxRandom(seed: seed &* 131 &+ i)
        let n = max(effCount, 1)
        let spread = Double(effSpread), dir = Double(effDirection)
        var deg: Double
        if n == 1 { deg = dir }
        else if effSpread >= 360 { deg = dir + 360 * Double(i) / Double(n) }
        else { deg = dir - spread / 2 + spread * Double(i) / Double(n - 1) }
        deg += (r.next() - 0.5) * spread / Double(n) * 0.5
        let a = deg * .pi / 180
        let sp = Double(effSpeed) * (0.8 + 0.4 * r.next())
        let jitter = Double(effSizeJitter) / 100
        let sz = max(4, Double(effSize) * (1 + jitter * (r.next() * 2 - 1)))
        let life = self.life
        return ThemeParticle(vx: sin(a) * sp, vy: -cos(a) * sp, gravity: Double(effGravity), life: life, size: sz,
                             rotation: Double(effSpin) * .pi / 180 * life, fadeIn: fadesIn,
                             colorIndex: i % max(colors?.count ?? 1, 1), glyphIndex: i % max(glyphs?.count ?? 1, 1))
    }
}

/// Một hạt đã giải: vận tốc đầu (pt/s), gia tốc dọc, đời (s), cỡ (pt), góc quay tổng (rad).
struct ThemeParticle: Equatable {
    var vx: Double, vy: Double, gravity: Double, life: Double, size: Double, rotation: Double
    var fadeIn: Bool
    var colorIndex: Int, glyphIndex: Int

    /// Độ dời khỏi gốc ở giây `t` (ném xiên: y = vy·t + ½·g·t²).
    func offset(_ t: Double) -> (x: Double, y: Double) {
        let u = max(0, min(t, life))
        return (vx * u, vy * u + 0.5 * gravity * u * u)
    }
    /// Độ đục ở giây `t`: "out" = 1 tới nửa đời rồi mờ; "inOut" = hiện dần 15% đầu.
    func alpha(_ t: Double) -> Double {
        guard life > 0, t >= 0, t < life else { return 0 }
        let f = t / life
        if fadeIn, f < 0.15 { return f / 0.15 }
        return f < 0.5 ? 1 : max(0, (1 - f) / 0.5)
    }
    /// Số mốc keyframe của đường bay (iOS) — đủ mượt cho đường cong trọng lực.
    static let pathSteps = 8
}

struct ThemeKeyword: Equatable {
    var words: [String]
    var burst: ThemeParticles? = nil
    var text: String? = nil

    static let maxEntries = 20
    static let maxWords = 8
    static let maxWordLength = 32
    static let maxText = 16
    static let keys: Set<String> = ["words", "burst", "text"]
}

/// Bảng tra từ khoá tự tạo (dựng MỘT lần lúc hiện bàn phím). Luật như "Từ khoá" có sẵn: bỏ ký tự không phải chữ ở hai
/// đầu, chữ thường, dấu có nghĩa; cụm hai từ ưu tiên (từ liền trước + từ vừa chốt); từ nhạy cảm ⇒ không.
struct ThemeKeywordTable: Equatable {
    let entries: [ThemeKeyword]
    private let index: [String: Int]

    init(_ entries: [ThemeKeyword]) {
        self.entries = Array(entries.prefix(ThemeKeyword.maxEntries))
        var m: [String: Int] = [:]
        for (i, e) in self.entries.enumerated() {
            for w in e.words { let k = Self.normalize(w); if !k.isEmpty, m[k] == nil { m[k] = i } }
        }
        index = m
    }
    var isEmpty: Bool { index.isEmpty }

    /// Chữ thường + NFC (người dùng có thể dán chữ dựng sẵn hay tổ hợp — engine luôn ra dựng sẵn).
    static func normalize(_ s: String) -> String { s.lowercased().precomposedStringWithCanonicalMapping }
    private static func clean(_ s: String) -> String {
        normalize(s.trimmingCharacters(in: CharacterSet.letters.inverted))
    }

    /// Chỉ số mục cho từ vừa chốt `word` (từ liền trước `prev`). O(1); nil = không khớp.
    func lookup(word: String, prev: String?) -> Int? {
        guard !index.isEmpty else { return nil }
        let w = Self.clean(word)
        guard !w.isEmpty, w.unicodeScalars.count <= ThemeKeyword.maxWordLength else { return nil }
        let p = prev.map(Self.clean)
        if EmojiWords.blocked(w, prev: p) { return nil }
        if let p, !p.isEmpty, let i = index[p + " " + w] { return i }
        return index[w]
    }
}

/// Phần tương tác của theme đang dùng (bàn phím giải một lần lúc hiện).
struct ThemeFx: Equatable {
    var particles: ThemeParticles?
    var keywords: ThemeKeywordTable?

    /// Từ đặc tả: không có gì ⇒ nil (0 chi phí).
    static func make(_ spec: ThemeSpec?) -> ThemeFx? {
        guard let spec else { return nil }
        let table = spec.keywords.map(ThemeKeywordTable.init).flatMap { $0.isEmpty ? nil : $0 }
        guard spec.particles != nil || table != nil else { return nil }
        return ThemeFx(particles: spec.particles, keywords: table)
    }
    /// Chùm của mục từ khoá `i`.
    func burst(keyword i: Int) -> ThemeParticles {
        let e = keywords?.entries
        let own = e.flatMap { $0.indices.contains(i) ? $0[i].burst : nil }
        return own ?? particles ?? .keywordFallback
    }
    /// Số chùm từ khoá xoay vòng: mọi mục ≤ 10 phần tử ⇒ 2, không thì 1 (tổng ≤ KeyEffectPool.cap).
    var keywordSlots: Int {
        guard let k = keywords else { return 0 }
        let worst = k.entries.indices.map { burst(keyword: $0).effCount + (k.entries[$0].text == nil ? 0 : 1) }.max() ?? 0
        return worst <= KeyEffectPool.cap / 2 ? 2 : 1
    }
}

/// Phần tương tác thực chạy — hàm thuần (test): hết Plus / tiết kiệm pin ⇒ nil (như KeyEffectPolicy).
enum ThemeFxPolicy {
    static func active(_ fx: ThemeFx?, plus: Bool, lowPower: Bool) -> ThemeFx? {
        guard let fx, plus, !lowPower else { return nil }
        return fx
    }
    /// Đọc lúc hiện bàn phím (applyAppearance) — không mỗi phím. Theme không có gì ⇒ không hỏi Plus / pin.
    static func current(_ spec: ThemeSpec?) -> ThemeFx? {
        guard let fx = ThemeFx.make(spec) else { return nil }
        return active(fx, plus: KeyEffectGate.allows, lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled)
    }
}

/// Gốc chùm theo "origin" (toạ độ overlay — gốc bounds có thể khác 0 (#151)): "key" = tâm phím; "bottom" / "top" = mép
/// dưới / trên bàn phím (lùi nửa cỡ hạt), x theo phím. x luôn kẹp trong bàn phím. Android y hệt.
enum ThemeFxOrigin {
    static func point(_ origin: String, key: (x: Double, y: Double), size: Double,
                      bounds: (minX: Double, minY: Double, maxX: Double, maxY: Double)) -> (x: Double, y: Double) {
        let x = min(max(key.x, bounds.minX), bounds.maxX)
        switch origin {
        case "bottom": return (x, bounds.maxY - size / 2)
        case "top": return (x, bounds.minY + size / 2)
        default: return (x, min(max(key.y, bounds.minY), bounds.maxY))
        }
    }
}

// MARK: - Hình (glyph) — một grapheme, luật thuần chung hai nền tảng

enum ThemeGlyph {
    static let maxScalars = 16

    private static func isExtender(_ v: UInt32) -> Bool {
        (0xFE00...0xFE0F).contains(v) || (0x1F3FB...0x1F3FF).contains(v) || v == 0x20E3 || (0x0300...0x036F).contains(v)
            || (0xE0020...0xE007F).contains(v) || (0x1AB0...0x1AFF).contains(v) || (0x20D0...0x20FF).contains(v)
    }
    private static func isRegional(_ v: UInt32) -> Bool { (0x1F1E6...0x1F1FF).contains(v) }
    private static func isSpaceOrControl(_ v: UInt32) -> Bool {
        v <= 0x20 || (0x7F...0xA0).contains(v) || v == 0x1680 || (0x2000...0x200B).contains(v) || v == 0x2028
            || v == 0x2029 || v == 0x202F || v == 0x205F || v == 0x3000 || v == 0xFEFF
    }

    /// Đúng MỘT ký tự hiển thị: ký tự gốc + dấu kết hợp / bộ chọn biến thể / màu da / tag, chuỗi ZWJ, hoặc một cờ (2 ký
    /// hiệu vùng). Không khoảng trắng / điều khiển. Android `ThemeGlyph.isSingle` y hệt (theo code point).
    static func isSingle(_ scalars: [UInt32]) -> Bool {
        guard let first = scalars.first, scalars.count <= maxScalars else { return false }
        if scalars.contains(where: isSpaceOrControl) { return false }
        if isExtender(first) || first == 0x200D { return false }
        if isRegional(first) { return scalars.count == 2 && isRegional(scalars[1]) }
        var i = 1
        while i < scalars.count {
            let v = scalars[i]
            if isExtender(v) { i += 1; continue }
            if v == 0x200D {
                guard i + 1 < scalars.count, !isExtender(scalars[i + 1]), scalars[i + 1] != 0x200D,
                      !isRegional(scalars[i + 1]) else { return false }
                i += 2
                continue
            }
            return false
        }
        return true
    }
    static func isSingle(_ s: String) -> Bool { isSingle(s.unicodeScalars.map(\.value)) }
}

/// Từ khoá hợp lệ: 1–2 phần cách nhau đúng một dấu cách, mỗi phần chỉ chữ (gồm dấu kết hợp), ≤ 32 ký tự.
enum ThemeKeywordWord {
    static func isValid(_ s: String) -> Bool {
        let parts = s.split(separator: " ", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count) else { return false }
        for p in parts {
            guard !p.isEmpty, p.unicodeScalars.allSatisfy({ CharacterSet.letters.contains($0) }) else { return false }
        }
        return true
    }
}

// MARK: - Đọc / kiểm (ThemeSpecParser gọi; lỗi cùng bảng mã)

enum ThemeFxParser {
    static func particles(_ v: StrictJSON, _ p: String) -> (ThemeParticles?, [ThemeIssue]) {
        var issues: [ThemeIssue] = []
        func err(_ c: ThemeIssue.Code, _ path: String) { issues.append(ThemeIssue(code: c, path: path)) }
        guard case .object(let m) = v else { return (nil, [ThemeIssue(code: .wrongType, path: p)]) }
        for (k, _) in m where !ThemeParticles.keys.contains(k) { err(.unknownKey, p + "." + k) }
        let d = Dictionary(m, uniquingKeysWith: { a, _ in a })
        var out = ThemeParticles()
        if let g = d["glyphs"] {
            if case .array(let a) = g {
                if a.isEmpty || a.count > ThemeParticles.maxGlyphs { err(.badValue, p + ".glyphs") }
                var list: [String] = []
                for (i, e) in a.enumerated() {
                    let ip = p + ".glyphs[\(i)]"
                    guard case .string(let s) = e else { err(.wrongType, ip); continue }
                    guard ThemeGlyph.isSingle(s) else { err(.badValue, ip); continue }
                    list.append(s)
                }
                out.glyphs = list
            } else { err(.wrongType, p + ".glyphs") }
        }
        if let s = d["shape"] {
            if case .string(let sh) = s {
                if !ThemeParticles.shapes.contains(sh) { err(.badValue, p + ".shape") }
                else if d["glyphs"] != nil { err(.badValue, p + ".shape") }   // "glyphs" hoặc "shape", không cả hai
                else { out.shape = sh }
            } else { err(.wrongType, p + ".shape") }
        }
        if let cv = d["colors"] {
            if case .array(let a) = cv {
                if a.isEmpty || a.count > ThemeParticles.maxColors { err(.badValue, p + ".colors") }
                var list: [UInt32] = []
                for (i, e) in a.enumerated() {
                    let ip = p + ".colors[\(i)]"
                    guard case .string(let s) = e else { err(.wrongType, ip); continue }
                    guard let c = ThemeColorCode.parse(s) else { err(.badColor, ip); continue }
                    list.append(c)
                }
                out.colors = list
            } else { err(.wrongType, p + ".colors") }
        }
        for (k, r) in ThemeParticles.ranges {
            guard let x = d[k] else { continue }
            guard case .int(let n) = x else { err(.wrongType, p + "." + k); continue }
            if !r.contains(n) { err(.clamped, p + "." + k) }
            out[int: k] = min(max(n, r.lowerBound), r.upperBound)
        }
        func pick(_ k: String, _ allowed: [String]) -> String? {
            guard let x = d[k] else { return nil }
            guard case .string(let s) = x else { err(.wrongType, p + "." + k); return nil }
            guard allowed.contains(s) else { err(.badValue, p + "." + k); return nil }
            return s
        }
        out.fade = pick("fade", ThemeParticles.fades)
        out.origin = pick("origin", ThemeParticles.origins)
        return (issues.contains(where: \.isError) ? nil : out, issues)
    }

    static func keywords(_ v: StrictJSON) -> ([ThemeKeyword]?, [ThemeIssue]) {
        var issues: [ThemeIssue] = []
        func err(_ c: ThemeIssue.Code, _ path: String) { issues.append(ThemeIssue(code: c, path: path)) }
        guard case .array(let a) = v else { return (nil, [ThemeIssue(code: .wrongType, path: "keywords")]) }
        if a.count > ThemeKeyword.maxEntries { return (nil, [ThemeIssue(code: .badValue, path: "keywords")]) }
        var out: [ThemeKeyword] = []
        for (i, e) in a.enumerated() {
            let p = "keywords[\(i)]"
            guard case .object(let m) = e else { err(.wrongType, p); continue }
            for (k, _) in m where !ThemeKeyword.keys.contains(k) { err(.unknownKey, p + "." + k) }
            let d = Dictionary(m, uniquingKeysWith: { a, _ in a })
            var entry = ThemeKeyword(words: [])
            switch d["words"] {
            case nil: err(.missingKey, p + ".words")
            case .array(let ws)?:
                if ws.isEmpty || ws.count > ThemeKeyword.maxWords { err(.badValue, p + ".words") }
                for (j, w) in ws.enumerated() {
                    let wp = p + ".words[\(j)]"
                    guard case .string(let s) = w else { err(.wrongType, wp); continue }
                    if s.unicodeScalars.count > ThemeKeyword.maxWordLength { err(.tooLong, wp); continue }
                    guard ThemeKeywordWord.isValid(s) else { err(.badValue, wp); continue }
                    entry.words.append(s)
                }
            default: err(.wrongType, p + ".words")
            }
            if let b = d["burst"] {
                let (pt, is2) = particles(b, p + ".burst")
                issues += is2
                entry.burst = pt
            }
            if let t = d["text"] {
                if case .string(let s) = t {
                    let tt = s.trimmingCharacters(in: .whitespaces)
                    if tt.isEmpty { err(.badValue, p + ".text") }
                    else if tt.unicodeScalars.count > ThemeKeyword.maxText { err(.tooLong, p + ".text") }
                    else { entry.text = tt }
                } else { err(.wrongType, p + ".text") }
            }
            out.append(entry)
        }
        if issues.contains(where: \.isError) { return (nil, issues) }
        return (out.isEmpty ? nil : out, issues)
    }

    // MARK: ghi chuẩn

    static func json(_ t: ThemeParticles) -> StrictJSON {
        var m: [(String, StrictJSON)] = []
        if let g = t.glyphs { m.append(("glyphs", .array(g.map { .string($0) }))) }
        if let s = t.shape { m.append(("shape", .string(s))) }
        if let c = t.colors { m.append(("colors", .array(c.map { .string(ThemeColorCode.format($0)) }))) }
        for (k, _) in ThemeParticles.ranges { if let n = t[int: k] { m.append((k, .int(n))) } }
        if let f = t.fade { m.append(("fade", .string(f))) }
        if let o = t.origin { m.append(("origin", .string(o))) }
        return .object(m)
    }

    static func json(_ ks: [ThemeKeyword]) -> StrictJSON {
        .array(ks.map { k in
            var m: [(String, StrictJSON)] = [("words", .array(k.words.map { .string($0) }))]
            if let b = k.burst { m.append(("burst", json(b))) }
            if let t = k.text { m.append(("text", .string(t))) }
            return .object(m)
        })
    }
}

extension ThemeSettings {
    /// Đặc tả theme đang dùng sau cổng Plus (tự tạo, hoặc có sẵn) — nil với Hệ thống / Kính.
    var effectiveSpec: ThemeSpec? { effectiveCustom ?? effectiveTheme.spec }
}
