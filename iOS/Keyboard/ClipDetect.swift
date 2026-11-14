// Chip tách từ nội dung vừa copy (OTP / SĐT / địa chỉ / STK) — hàm THUẦN, không UIKit.
// Hợp đồng dùng chung với Android (keyboard/ClipDetect.kt) — sửa luật phải sửa
// cả hai và giữ test vector khớp (ClipDetectTests ở cả hai bên).
import Foundation

struct ClipChip: Equatable {
    enum Kind: Equatable { case otp, phone, address, account }
    let kind: Kind
    /// OTP/SĐT/STK: chỉ chữ số (SĐT chuẩn hoá về 0xxxxxxxxx). Địa chỉ: nguyên văn đã gọn.
    let value: String
    let label: String
}

enum ClipDetect {
    static let maxLength = 500

    /// Tối đa 1 chip mỗi loại (lần xuất hiện đầu), thứ tự OTP → SĐT → địa chỉ → STK.
    static func detect(_ text: String) -> [ClipChip] {
        guard !text.isEmpty, text.count <= maxLength else { return [] }
        let chars = Array(text)
        let folded = fold(chars)
        let tokens = wordTokens(folded)
        var out: [ClipChip] = []

        // OTP
        let otpRuns = runs(chars, seps: []).filter { (4...8).contains($0.digits.count) && bounded(chars, $0) && !followedByCurrency(folded, $0.end) }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var otp: String?
        if (4...8).contains(trimmed.count), trimmed.allSatisfy(\.isASCIIDigit) {
            otp = trimmed
        } else if !otpRuns.isEmpty {
            otp = otpAfterKeyword(tokens: tokens, runs: otpRuns)
        }
        if let v = otp { out.append(ClipChip(kind: .otp, value: v, label: L("Dán OTP %@", v))) }

        // SĐT
        var phone: String?, phoneRaw: String?
        for r in runs(chars, seps: [" ", ".", "-"], allowPlus: true) where bounded(chars, r) {
            if let p = phonePrefix(r) { phone = p.normalized; phoneRaw = p.raw; break }
        }
        if let v = phone { out.append(ClipChip(kind: .phone, value: v, label: L("Dán SĐT %@", short(v)))) }

        // Địa chỉ
        if let a = AddressDetect.detect(text) { out.append(ClipChip(kind: .address, value: a, label: L("Dán địa chỉ"))) }

        // STK
        let hasAccountKeyword = tokens.contains { ["stk", "tk", "account", "acc"].contains($0.word) }
            || String(folded).contains("tai khoan") || String(folded).contains("a/c")
        for r in runs(chars, seps: [" ", "-"]) where bounded(chars, r) {
            let d = r.digits
            guard (6...19).contains(d.count), d != phone, d != phoneRaw, d != otp,
                  !followedByCurrency(folded, r.end) else { continue }
            guard hasAccountKeyword || d.count >= 9 else { continue }
            out.append(ClipChip(kind: .account, value: d, label: L("Dán STK %@", short(d))))
            break
        }
        return out
    }

    /// Ô đang điền là ô địa chỉ / SĐT / OTP (trait hệ điều hành) ⇒ chip loại đó lên đầu
    /// (dải chỉ hiện 2 chip). Không biết loại ô ⇒ giữ thứ tự mặc định.
    static func prioritize(_ chips: [ClipChip], for kind: ClipChip.Kind?) -> [ClipChip] {
        guard let k = kind, let i = chips.firstIndex(where: { $0.kind == k }), i > 0 else { return chips }
        var c = chips
        c.insert(c.remove(at: i), at: 0)
        return c
    }

    // MARK: nội bộ

    struct Run { let start: Int; let end: Int; let digits: String; let groups: [String] }

    /// Dãy chữ số, cho phép MỘT ký tự phân cách (thuộc `seps`) giữa hai chữ số.
    /// `end` là chỉ số NGAY SAU chữ số cuối. `allowPlus`: '+' ngay trước tính vào.
    static func runs(_ c: [Character], seps: Set<Character>, allowPlus: Bool = false) -> [Run] {
        var out: [Run] = []
        var i = 0
        while i < c.count {
            guard c[i].isASCIIDigit else { i += 1; continue }
            var start = i
            if allowPlus, i > 0, c[i - 1] == "+" { start = i - 1 }
            var groups: [String] = [""]
            var j = i
            while j < c.count {
                if c[j].isASCIIDigit { groups[groups.count - 1].append(c[j]); j += 1 }
                else if seps.contains(c[j]), j + 1 < c.count, c[j + 1].isASCIIDigit {
                    groups.append(""); j += 1
                } else { break }
            }
            out.append(Run(start: start, end: j, digits: groups.joined(), groups: groups))
            i = j
        }
        return out
    }

    /// Biên: không kề chữ cái/chữ số; không kề [.,:/] mà bên kia là chữ số
    /// (tiền "1,234,567", giờ "12:30", ngày "27/09").
    static func bounded(_ c: [Character], _ r: Run) -> Bool {
        func bad(_ i: Int, _ step: Int) -> Bool {
            guard i >= 0, i < c.count else { return false }
            let ch = c[i]
            if ch.isLetter || ch.isNumber { return true }
            if ".,:/".contains(ch) {
                let k = i + step
                return k >= 0 && k < c.count && c[k].isASCIIDigit
            }
            return false
        }
        return !bad(r.start - 1, -1) && !bad(r.end, 1)
    }

    static func phonePrefix(_ r: Run) -> (normalized: String, raw: String)? {
        var acc = ""
        for g in r.groups {
            acc += g
            if let p = normalizePhone(acc) { return (p, acc) }
        }
        return nil
    }

    /// 10 số đầu 03/05/07/08/09 (di động) hoặc 11 số đầu 02 (bàn); +84/84 → 0.
    static func normalizePhone(_ digits: String) -> String? {
        var d = digits
        if d.hasPrefix("84"), d.count == 11 || d.count == 12 {
            let rest = d.dropFirst(2)
            d = rest.hasPrefix("0") ? String(rest) : "0" + rest
        }
        guard d.hasPrefix("0") else { return nil }
        let second = d.dropFirst().first
        if d.count == 10, let s = second, "35789".contains(s) { return d }
        if d.count == 11, second == "2" { return d }
        return nil
    }

    private static let strongOTPKeywords: Set<String> = ["otp", "code", "passcode", "verification"]

    /// OTP khi có keyword: dãy 4–8 số đầu tiên SAU keyword; "ma" (mã) chỉ tính khi
    /// dãy số nằm trong 50 ký tự sau nó; keyword mạnh mà không có dãy phía sau →
    /// dãy đầu tiên của cả chuỗi.
    private static func otpAfterKeyword(tokens: [(word: String, start: Int)], runs: [Run]) -> String? {
        var fallback = false
        for t in tokens {
            if strongOTPKeywords.contains(t.word) {
                if let r = runs.first(where: { $0.start > t.start }) { return r.digits }
                fallback = true
            } else if t.word == "ma",
                      let r = runs.first(where: { $0.start > t.start }), r.start - t.start <= 50 {
                return r.digits
            }
        }
        return fallback ? runs.first?.digits : nil
    }

    private static let currencyWords: Set<String> = ["vnd", "d", "dong", "usd", "k"]

    private static func followedByCurrency(_ f: [Character], _ end: Int) -> Bool {
        var i = end
        while i < f.count, f[i] == " " { i += 1 }
        var w = ""
        while i < f.count, f[i].isLetter { w.append(f[i]); i += 1 }
        return currencyWords.contains(w)
    }

    private static func short(_ v: String) -> String {
        v.count <= 6 ? v : String(v.prefix(4)) + "…"
    }

    /// Gập dấu + chữ thường TỪNG ký tự (giữ nguyên chỉ số với chuỗi gốc).
    static func fold(_ chars: [Character]) -> [Character] {
        chars.map { ch in
            if ch == "đ" || ch == "Đ" { return "d" }
            let f = String(ch).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            return f.count == 1 ? f.first! : (String(ch).lowercased().first ?? ch)
        }
    }

    private static func wordTokens(_ f: [Character]) -> [(word: String, start: Int)] {
        var out: [(String, Int)] = []
        var i = 0
        while i < f.count {
            guard f[i].isLetter else { i += 1; continue }
            let s = i
            var w = ""
            while i < f.count, f[i].isLetter { w.append(f[i]); i += 1 }
            out.append((w, s))
        }
        return out
    }
}

/// Địa chỉ Việt Nam trong nội dung vừa copy (thông tin giao hàng…). Luật THUẦN, chặt —
/// bỏ sót thì vẫn còn Dán nguyên văn, hiện nhầm mới phiền. Song sinh Android AddressDetect.
///  1. Tách đoạn theo xuống dòng , ; | và " - ".
///  2. Đoạn có nhãn "Địa chỉ:/ĐC:/Đ/c:/Address:" ⇒ lấy phần sau nhãn + các đoạn kế tới khi
///     gặp đoạn có SĐT hoặc nhãn khác ("Tên:", "Ghi chú:").
///  3. Không nhãn: mỗi đoạn chấm các "tầng" — số nhà, đường/ngõ/hẻm…, phường/xã, quận/huyện,
///     tỉnh/thành (từ khoá phải đi kèm chữ HOA hoặc số: "Quận 3", "P.14", "xã Tân Lập";
///     "quán phở" không tính). Lấy khúc liền nhau (không vượt đoạn có SĐT/nhãn) có ≥ 2 tầng,
///     ít nhất một tầng là số nhà / phường-xã / quận-huyện.
enum AddressDetect {
    static let maxOutput = 200

    enum Level: Hashable { case house, street, ward, district, province }

    private enum PartKind { case label(String), boundary, content }

    static func detect(_ raw: String) -> String? {
        let text = raw.precomposedStringWithCanonicalMapping
        let parts = split(text).map { ($0, classify($0)) }
        // 1. có nhãn
        for (i, p) in parts.enumerated() {
            guard case .label(let rest) = p.1 else { continue }
            var out = rest.isEmpty ? [] : [rest]
            var j = i + 1
            while j < parts.count, case .content = parts[j].1 { out.append(parts[j].0); j += 1 }
            return finish(out)
        }
        // 2. không nhãn: khúc tốt nhất trong từng dải giữa các ranh giới
        var best: (score: Int, parts: [String])?
        var lo: Int?, hi = 0, levels = Set<Level>(), head = ""
        func close() {
            if let l = lo, accepts(levels), levels.count > (best?.score ?? 0) {
                // Đoạn đầu: bỏ lời dẫn trước dấu hiệu đầu tiên ("ship giúp e về 25 Trần Phú").
                best = (levels.count, [head] + parts[l...hi].dropFirst().map(\.0))
            }
            lo = nil; levels = []
        }
        for (i, p) in parts.enumerated() {
            guard case .content = p.1 else { close(); continue }
            let (lv, from) = Self.scan(p.0)
            guard !lv.isEmpty else { continue }
            if lo == nil { lo = i; head = String(Array(p.0)[from...]) }
            hi = i; levels.formUnion(lv)
        }
        close()
        return best.flatMap { finish($0.parts) }
    }

    /// ≥ 2 tầng, trong đó có số nhà / phường-xã / quận-huyện ("Phở Hà Nội" = đường + tỉnh: không).
    static func accepts(_ l: Set<Level>) -> Bool {
        l.count >= 2 && !l.isDisjoint(with: [.house, .ward, .district])
    }

    // MARK: tách + phân loại đoạn

    static func split(_ text: String) -> [String] {
        let c = Array(text)
        var out: [String] = [], cur = ""
        func flush() {
            let t = cur.trimmingCharacters(in: .whitespaces)
            if !t.isEmpty { out.append(t) }
            cur = ""
        }
        for (i, ch) in c.enumerated() {
            if ch.isNewline || ",;|".contains(ch) { flush(); continue }
            if ch == "-" || ch == "–", i > 0, i + 1 < c.count, c[i - 1] == " ", c[i + 1] == " " { flush(); continue }
            cur.append(ch)
        }
        flush()
        return out
    }

    private static let addressLabels: Set<String> = [
        "dc", "d/c", "d.c", "add", "addr", "address", "noi nhan", "giao den", "giao toi",
        "ship den", "ship toi", "gui den", "gui toi",
    ]

    private static func classify(_ p: String) -> PartKind {
        let o = Array(p), f = ClipDetect.fold(o)
        let fs = String(f)
        if let c = f.prefix(26).firstIndex(of: ":") {
            let head = String(f[..<c]).trimmingCharacters(in: .whitespaces)
            if !head.isEmpty, head.allSatisfy({ $0.isLetter || " /.".contains($0) }) {
                let rest = String(o[(c + 1)...]).trimmingCharacters(in: .whitespaces)
                if head.hasPrefix("dia chi") || addressLabels.contains(head) { return .label(rest) }
                let first = head.split(separator: " ").first.map(String.init) ?? head
                if !keywordWords.contains(first) { return .boundary }
            }
        } else if fs.hasPrefix("dia chi ") {
            return .label(String(o.dropFirst(8)).trimmingCharacters(in: .whitespaces))
        }
        if containsPhone(o) { return .boundary }
        return .content
    }

    private static func containsPhone(_ c: [Character]) -> Bool {
        ClipDetect.runs(c, seps: [" ", ".", "-"], allowPlus: true)
            .contains { ClipDetect.bounded(c, $0) && ClipDetect.phonePrefix($0) != nil }
    }

    private static let trailingParticles: Set<String> = ["nhé", "nha", "nhe", "nhá", "nhen", "ạ", "nhé.", "nha."]

    private static func finish(_ parts: [String]) -> String? {
        var words = parts.joined(separator: ", ").split(whereSeparator: \.isWhitespace).map(String.init)
        // Tiểu từ cuối câu nhắn ("…Đà Nẵng nhé").
        while let w = words.last, trailingParticles.contains(w.lowercased()) { words.removeLast() }
        var s = words.joined(separator: " ")
        while let l = s.last, ".,;-–: ".contains(l) { s.removeLast() }
        guard s.count <= maxOutput, s.filter(\.isLetter).count >= 4 else { return nil }
        return s
    }

    // MARK: tầng địa chỉ trong một đoạn

    /// Từ khoá đầy đủ (đã gập dấu) — phải đi kèm chữ HOA hoặc số phía sau.
    private static let fullKeywords: [(words: [String], level: Level)] = [
        (["to", "dan", "pho"], .street), (["khu", "do", "thi"], .street), (["khu", "dan", "cu"], .street),
        (["thanh", "pho"], .province), (["thi", "xa"], .district), (["thi", "tran"], .ward),
        (["khu", "pho"], .street), (["so", "nha"], .house), (["chung", "cu"], .street), (["toa", "nha"], .street),
        (["phuong"], .ward), (["xa"], .ward), (["ward"], .ward),
        (["quan"], .district), (["huyen"], .district), (["district"], .district),
        (["tinh"], .province), (["province"], .province), (["city"], .province),
        (["duong"], .street), (["pho"], .street), (["ngo"], .street), (["ngach"], .street), (["hem"], .street),
        (["kiet"], .street), (["thon"], .street), (["xom"], .street), (["ap"], .street),
        (["lo"], .street), (["street"], .street), (["road"], .street), (["lane"], .street), (["alley"], .street),
    ]
    /// Viết tắt: dính số ("P14", "Q3") hoặc có chấm/khoảng trắng rồi chữ HOA/số ("P. Bến Nghé",
    /// "TP HCM"); một chữ cái thì bắt buộc dính số hoặc có chấm.
    private static let abbreviations: [String: Level] = [
        "p": .ward, "x": .ward, "tt": .ward, "q": .district, "h": .district, "tx": .district,
        "tp": .province, "kp": .street, "kdc": .street, "kdt": .street, "cc": .street, "d": .street,
        "sn": .house,
    ]
    private static let keywordWords: Set<String> = Set(fullKeywords.compactMap { $0.words.first })
        .union(abbreviations.keys)

    /// Tỉnh/thành (34 đơn vị sau sáp nhập 2025 + tên cũ còn hay dùng), đã gập dấu. Chữ đầu phải HOA.
    private static let provinces: [[String]] = [
        "ha noi", "ho chi minh", "sai gon", "hai phong", "da nang", "can tho", "hue", "thua thien hue",
        "lai chau", "dien bien", "son la", "lang son", "quang ninh", "thanh hoa", "nghe an", "ha tinh",
        "cao bang", "tuyen quang", "lao cai", "thai nguyen", "phu tho", "bac ninh", "hung yen",
        "ninh binh", "quang tri", "quang ngai", "gia lai", "khanh hoa", "lam dong", "dak lak", "dak nong",
        "dong nai", "tay ninh", "vinh long", "dong thap", "ca mau", "an giang", "ha giang", "yen bai",
        "bac kan", "vinh phuc", "bac giang", "hoa binh", "hai duong", "thai binh", "ha nam", "nam dinh",
        "quang binh", "quang nam", "kon tum", "binh dinh", "phu yen", "ninh thuan", "binh thuan",
        "binh phuoc", "binh duong", "vung tau", "long an", "tien giang", "ben tre", "tra vinh",
        "hau giang", "soc trang", "bac lieu", "kien giang", "nha trang", "da lat", "bien hoa",
    ].map { $0.split(separator: " ").map(String.init) }
    /// Viết liền / viết tắt thành phố (chỉ khi viết HOA toàn bộ, trừ "tphcm").
    private static let cityTokens: Set<String> = ["hcm", "tphcm", "hn", "sg", "hcmc"]

    private struct Tok { let s: String; let start: Int; let end: Int; let digit: Bool }

    static func levels(_ p: String) -> Set<Level> { scan(p).levels }

    /// Tầng + vị trí (Character) dấu hiệu đầu tiên trong đoạn.
    static func scan(_ p: String) -> (levels: Set<Level>, from: Int) {
        let o = Array(p), f = ClipDetect.fold(o)
        var toks: [Tok] = []
        var i = 0
        while i < f.count {
            let d = f[i].isASCIIDigit
            guard d || f[i].isLetter else { i += 1; continue }
            let s = i
            while i < f.count, d ? f[i].isASCIIDigit : f[i].isLetter { i += 1 }
            toks.append(Tok(s: String(f[s..<i]), start: s, end: i, digit: d))
        }
        func isUpper(_ k: Int) -> Bool { k < o.count && o[k].isUppercase }
        /// Ký tự đầu sau `end` khi bỏ qua khoảng trắng và "." — (vị trí, có chấm).
        func next(_ end: Int) -> (Int, Bool) {
            var k = end, dot = false
            while k < f.count, f[k] == " " || f[k] == "." { if f[k] == "." { dot = true }; k += 1 }
            return (k, dot)
        }
        func capOrDigit(_ k: Int) -> Bool { k < o.count && (o[k].isUppercase || o[k].isASCIIDigit) }

        var out = Set<Level>()
        var from: Int?
        func hit(_ l: Level, _ at: Int) { out.insert(l); if from == nil { from = at } }
        var t = 0
        while t < toks.count {
            let tok = toks[t]
            if tok.digit {
                // Số nhà: 1–5 chữ số, trước là đầu đoạn/khoảng trắng; ở đầu đoạn hoặc ngay sau là
                // tên viết HOA ("ở 12 Nguyễn Trãi"). "Phường 14", "P.14", "12:30" không tính.
                let prevOK = tok.start == 0 || f[tok.start - 1] == " "
                let nextTok = t + 1 < toks.count ? toks[t + 1] : nil
                let followedByName = nextTok.map { !$0.digit && isUpper($0.start) && $0.start > tok.end } ?? false
                if tok.s.count <= 5, prevOK, tok.start == 0 || followedByName { hit(.house, tok.start) }
                t += 1; continue
            }
            // Tỉnh/thành
            if isUpper(tok.start), let n = provinces.first(where: { w in
                t + w.count <= toks.count && (0..<w.count).allSatisfy { toks[t + $0].s == w[$0] && !toks[t + $0].digit }
            }) {
                hit(.province, tok.start); t += n.count; continue
            }
            if cityTokens.contains(tok.s),
               tok.s == "tphcm" || (tok.start..<tok.end).allSatisfy({ o[$0].isUppercase }) {
                hit(.province, tok.start); t += 1; continue
            }
            // "Số 5" ⇒ số nhà
            if tok.s == "so", t + 1 < toks.count, toks[t + 1].digit { hit(.house, tok.start); t += 1; continue }
            // Từ khoá đầy đủ
            if let kw = fullKeywords.first(where: { k in
                t + k.words.count <= toks.count && (0..<k.words.count).allSatisfy { toks[t + $0].s == k.words[$0] }
            }) {
                let end = toks[t + kw.words.count - 1].end
                if capOrDigit(next(end).0) { hit(kw.level, tok.start) }
                t += kw.words.count; continue
            }
            // Viết tắt
            if let lv = abbreviations[tok.s] {
                let attachedDigit = tok.end < f.count && f[tok.end].isASCIIDigit
                let (k, dot) = next(tok.end)
                let ok = attachedDigit || (capOrDigit(k) && (dot || tok.s.count >= 2))
                // "8h30", "2x3": viết tắt dính chữ/số phía trước không tính.
                if ok, tok.start == 0 || !(f[tok.start - 1].isLetter || f[tok.start - 1].isASCIIDigit) { hit(lv, tok.start) }
            }
            t += 1
        }
        return (out, from ?? 0)
    }
}

/// Heuristic nội dung "giống bí mật" (mật khẩu / API key / OTP) → hết hạn sớm (2 phút).
enum ClipSensitivity {
    static func looksSecret(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return false }
        if (4...8).contains(t.count), t.allSatisfy(\.isASCIIDigit) { return true }
        if ClipDetect.detect(t).contains(where: { $0.kind == .otp }) { return true }
        guard !t.contains(where: \.isWhitespace) else { return false }
        if t.contains("://") || t.lowercased().hasPrefix("www.") { return false }
        if let at = t.firstIndex(of: "@"), t[at...].contains(".") { return false }
        var classes = 0
        if t.contains(where: \.isLowercase) { classes += 1 }
        if t.contains(where: \.isUppercase) { classes += 1 }
        if t.contains(where: \.isASCIIDigit) { classes += 1 }
        if t.contains(where: { !$0.isLetter && !$0.isNumber }) { classes += 1 }
        if (8...64).contains(t.count), classes >= 3 { return true }
        if t.count >= 20, t.contains(where: \.isLetter), t.contains(where: \.isASCIIDigit) { return true }
        return false
    }
}

extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
