// SwipePractice.swift — CHẾ ĐỘ LUYỆN VUỐT (app, không phải bàn phím), phần THUẦN: từ mục
// tiêu, chấm một nét, hình học bàn phím mẫu, định dạng nét vuốt thật để xuất/đánh giá decoder.
// Song sinh android/keyboard/src/main/kotlin/com/viettelex/keyboard/SwipePractice.kt, cùng
// định dạng JSON (fixture chung KeyboardTests/Fixtures/swipe-traces-sample.json).
//
// Xuất (v1): {"format":"viettelex-swipe-traces","version":1,"platform","exported","traces":[…]};
// trace = {"target","folded","lang":"vi"|"en","keyWidth","keys":{"a":[x,y]…},
// "points":[[x,y,ms]…],"decoded":[top-K],"time":epoch ms}. Toạ độ cùng hệ với keyWidth.
// Lưu trên máy dạng JSON Lines (Application Support, không sao lưu iCloud) — không gửi mạng.
// Đánh giá decoder trên file xuất: Scripts/eval-swipe-traces.sh.
import CoreGraphics
import Foundation

struct SwipeTrace: Equatable, Codable {
    var target: String
    var folded: String
    var lang: String
    var keyWidth: Double
    var keys: [String: [Double]]
    /// x, y, ms kể từ điểm đầu.
    var points: [[Double]]
    var decoded: [String]
    var time: Int64

    var language: SwipeLang { lang == "en" ? .en : .vi }
    /// Đúng khi top-1 lúc ghi = chuỗi mục tiêu.
    var hit: Bool { decoded.first == folded }

    var layout: SwipeLayout? {
        guard keyWidth > 0 else { return nil }
        var m: [Character: (x: Float, y: Float)] = [:]
        for (k, v) in keys where k.count == 1 && v.count >= 2 { m[Character(k)] = (Float(v[0]), Float(v[1])) }
        return SwipeLayout(keyWidth: Float(keyWidth), centers: m)
    }

    func path() -> SwipePath {
        var p = SwipePath(minDistance: Float(keyWidth) / 5)
        for (i, pt) in points.enumerated() where pt.count >= 3 {
            p.add(x: Float(pt[0]), y: Float(pt[1]), t: pt[2] / 1000, force: i == points.count - 1)
        }
        return p
    }

    static func r2(_ v: Float) -> Double { (Double(v) * 100).rounded() / 100 }

    init(target: String, folded: String, lang: SwipeLang, layout: SwipeLayout,
         path p: SwipePath, decoded: [String], time: Int64) {
        self.target = target
        self.folded = folded
        self.lang = lang == .en ? "en" : "vi"
        keyWidth = Self.r2(layout.keyWidth)
        var k: [String: [Double]] = [:]
        for (i, ch) in "abcdefghijklmnopqrstuvwxyz".enumerated() where layout.centers[i * 2].isFinite {
            k[String(ch)] = [Self.r2(layout.centers[i * 2]), Self.r2(layout.centers[i * 2 + 1])]
        }
        keys = k
        points = (0..<p.count).map { [Self.r2(p.xs[$0]), Self.r2(p.ys[$0]), Self.r2(Float((p.ts[$0] - p.ts[0]) * 1000))] }
        self.decoded = decoded
        self.time = time
    }
}

enum SwipePractice {
    static let format = "viettelex-swipe-traces"
    static let version = 1
    static let maxTraces = 5000

    struct Target: Equatable {
        let word: String
        let folded: String
        let lang: SwipeLang
    }

    /// Số phím sau gộp chữ lặp (luu → lu) — 1 phím là chạm, không phải nét vuốt.
    static func keyCount(_ folded: String) -> Int {
        var n = 0
        var prev: Character = " "
        for c in folded { if c != prev { n += 1 }; prev = c }
        return n
    }

    /// Âm tiết Việt phổ biến (tần suất lexicon; bằng nhau giữ thứ tự id — parity Kotlin).
    static let vietnamese: [Target] = {
        let ids = (0..<VNLexicon2Data.count).map { ($0, Int(VNLexicon2Data.freq($0))) }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }
        var seen = Set<String>(), out: [Target] = []
        for (id, _) in ids {
            let w = VNSuggest.display(id)
            let f = SwipeLexicon.fold(w)
            guard keyCount(f) >= 2, SwipeLexicon.index(of: f) != nil, seen.insert(w).inserted else { continue }
            out.append(Target(word: w, folded: f, lang: .vi))
            if out.count == viPool { break }
        }
        return out
    }()

    /// Từ tiếng Anh phổ biến, ≥ 3 chữ, KHÔNG trùng chuỗi dạng Việt (the/thế — nét y hệt).
    static let english: [Target] = {
        let en = SwipeEnglish.lexicon
        let words = en.freq.indices.sorted { en.freq[$0] != en.freq[$1] ? en.freq[$0] > en.freq[$1] : $0 < $1 }
            .lazy.map { en.word($0) }
            .filter { $0.count >= 3 && SwipeLexicon.index(of: $0) == nil }
            .prefix(enPool)
        return words.map { Target(word: $0, folded: $0, lang: .en) }
    }()

    private static let viPool = 400
    private static let enPool = 120
    /// ~1/5 mục tiêu là tiếng Anh.
    private static let enEvery: UInt64 = 5

    /// Mục tiêu thứ `i` của phiên `seed` — tất định (SplitMix64 như SwipeSim).
    static func target(seed: Int64, _ i: Int) -> Target {
        var z = UInt64(bitPattern: seed) &+ UInt64(i + 1) &* 0x9E3779B97F4A7C15
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        z ^= z >> 31
        let r = z >> 1
        let pool = r % enEvery == 0 && !english.isEmpty ? english : vietnamese
        return pool[Int((r / enEvery) % UInt64(pool.count))]
    }

    /// Giải mã một nét như bàn phím; ngữ cảnh ngôn ngữ theo mục tiêu (luyện từng từ rời).
    static func decode(_ d: SwipeDecoder, _ path: SwipePath, lang: SwipeLang, topK: Int = 5) -> [SwipeCandidate] {
        d.decode(path, topK: topK, context: nil,
                 english: lang == .en ? SwipeLangContext.englishPrior : SwipeLangContext.defaultPrior)
    }

    // MARK: JSON

    struct Export: Codable {
        var format: String
        var version: Int
        var platform: String
        var exported: String
        var traces: [SwipeTrace]
    }

    private static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return e
    }

    /// Một dòng JSON Lines để ghi nối vào kho trên máy.
    static func line(_ t: SwipeTrace) -> String {
        (try? encoder().encode(t)).map { String(decoding: $0, as: UTF8.self) } ?? ""
    }

    /// Đọc kho JSON Lines (dòng hỏng bỏ qua).
    static func parseLines(_ text: String) -> [SwipeTrace] {
        let d = JSONDecoder()
        return text.split(separator: "\n").compactMap { l in
            guard let t = try? d.decode(SwipeTrace.self, from: Data(l.utf8)), valid(t) else { return nil }
            return t
        }
    }

    private static func valid(_ t: SwipeTrace) -> Bool {
        t.keyWidth > 0 && !t.points.isEmpty && t.points.allSatisfy { $0.count >= 3 }
    }

    static func export(_ traces: [SwipeTrace], platform: String = "ios", now: Date = Date()) -> Data {
        let f = ISO8601DateFormatter()
        let doc = Export(format: format, version: version, platform: platform,
                         exported: f.string(from: now), traces: traces)
        return ((try? encoder().encode(doc)) ?? Data()) + Data("\n".utf8)
    }

    /// Đọc tài liệu xuất; nil nếu không phải định dạng này / phiên bản mới hơn.
    static func parseExport(_ data: Data) -> [SwipeTrace]? {
        guard let doc = try? JSONDecoder().decode(Export.self, from: data),
              doc.format == format, doc.version <= version else { return nil }
        return doc.traces.filter(valid)
    }

    struct Report: Equatable {
        var n = 0, top1 = 0, top3 = 0, recorded = 0
    }

    /// Độ chính xác một tập nét theo decoder hiện tại.
    static func evaluate(_ traces: [SwipeTrace]) -> Report {
        var r = Report()
        var cache: (SwipeLayout, SwipeDecoder)?
        for t in traces {
            guard let l = t.layout else { continue }
            let d: SwipeDecoder
            if let c = cache, c.0 == l { d = c.1 } else { d = SwipeDecoder(); d.setLayout(l); cache = (l, d) }
            let c = decode(d, t.path(), lang: t.language).map(\.folded)
            r.n += 1
            if c.first == t.folded { r.top1 += 1 }
            if c.prefix(3).contains(t.folded) { r.top3 += 1 }
            if t.hit { r.recorded += 1 }
        }
        return r
    }
}

/// Bàn phím mẫu của Luyện vuốt: CÙNG công thức hình học với KeyboardView iPhone (KeyGeometry:
/// lề 6.5, khe 6, hàng 54 = khe 10 + phím 44; hàng 2 thụt nửa bước; hàng 3 căn giữa, chữ
/// rộng bằng hàng 1). Toạ độ tính từ đỉnh vùng phím.
enum PracticeKeyboardGeometry {
    static let margin: CGFloat = 6.5
    static let gap: CGFloat = 6
    static let rows = ["qwertyuiop", "asdfghjkl", "zxcvbnm"]

    static func pitch(width: CGFloat) -> CGFloat { KeyGeometry.letterPitch(width: width, margin: margin, gap: gap) }

    static func height(rowHeight: CGFloat = 54) -> CGFloat { CGFloat(rows.count) * rowHeight }

    /// Khung từng phím chữ.
    static func keys(width: CGFloat, rowHeight: CGFloat = 54) -> [(Character, CGRect)] {
        let p = pitch(width: width), kw = p - gap
        let kh = rowHeight - KeyGeometry.rowGap
        var out: [(Character, CGRect)] = []
        for (r, row) in rows.enumerated() {
            let y = CGFloat(r) * rowHeight + KeyGeometry.rowGap
            for (i, ch) in row.enumerated() {
                let cx: CGFloat
                switch r {
                case 0: cx = margin + kw / 2 + CGFloat(i) * p
                case 1: cx = KeyGeometry.indentedMargin(width: width, margin: margin, gap: gap, units: 0.5)
                    + kw / 2 + CGFloat(i) * p
                default: cx = width / 2 + CGFloat(i - 3) * p
                }
                out.append((ch, CGRect(x: cx - kw / 2, y: y, width: kw, height: kh)))
            }
        }
        return out
    }

    /// nil khi chưa có bề rộng (GeometryReader đo lần đầu = 0 ⇒ bước phím 0, SwipeLayout
    /// precondition crash — Phil 27/09 bấm "Luyện vuốt" là văng app).
    static func layout(width: CGFloat, rowHeight: CGFloat = 54) -> SwipeLayout? {
        guard pitch(width: width) > 0 else { return nil }
        var m: [Character: (x: Float, y: Float)] = [:]
        for (c, f) in keys(width: width, rowHeight: rowHeight) { m[c] = (Float(f.midX), Float(f.midY)) }
        return SwipeLayout(keyWidth: Float(pitch(width: width)), centers: m)
    }
}
