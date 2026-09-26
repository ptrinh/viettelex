// Lõi gõ vuốt: độ chính xác trên đường vuốt giả, ca khó, parity với bản Kotlin
// (fixture Fixtures/swipe-paths.txt). Cùng bộ ca với android SwipeDecoderTests.kt.
import XCTest

/// Sinh đường vuốt giả — song sinh SwipeSim trong android/keyboard/src/test/…/SwipeDecoderTests.kt.
/// Tâm phím + nhiễu Gaussian σ·phím (điểm điều khiển), lệch đầu/cuối tuỳ chọn, làm mượt
/// Catmull-Rom, mỗi mẫu ~0.35 phím (≈ vuốt 20 phím/s lấy mẫu 60Hz) + rung 0.04 phím,
/// rồi đi qua SwipePath (lọc 1/5 phím) như bản tích hợp.
struct SwipeSim {
    private var s: UInt64
    init(seed: UInt64) { s = seed }

    private mutating func next() -> UInt64 {
        s = s &+ 0x9E3779B97F4A7C15
        var z = s
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func uniform() -> Double { Double(next() >> 11) * (1.0 / 9007199254740992.0) }
    mutating func gauss() -> Double {
        let u1 = max(uniform(), 1e-12), u2 = uniform()
        return (-2 * log(u1)).squareRoot() * cos(2 * Double.pi * u2)
    }

    static func collapse(_ s: String) -> String {
        var out = ""
        for c in s where out.last != c { out.append(c) }
        return out
    }

    private static func catmull(_ p0: Double, _ p1: Double, _ p2: Double, _ p3: Double,
                                _ t: Double) -> Double {
        let t2 = t * t, t3 = t2 * t
        return 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2
                      + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)
    }

    mutating func path(_ word: String, _ layout: SwipeLayout, sigma: Double = 0.25,
                       endOffset: Double = 0, jitter: Double = 0.04,
                       step: Double = 0.35) -> SwipePath {
        let w = Double(layout.keyWidth)
        let keys = Array(Self.collapse(word))
        var cx = [Double](repeating: 0, count: keys.count), cy = cx
        for (i, ch) in keys.enumerated() {
            let c = layout.center(of: ch)!
            cx[i] = Double(c.x) + gauss() * sigma * w
            cy[i] = Double(c.y) + gauss() * sigma * w
        }
        if endOffset > 0 {
            var a = uniform() * 2 * Double.pi
            cx[0] += cos(a) * endOffset * w; cy[0] += sin(a) * endOffset * w
            a = uniform() * 2 * Double.pi
            let e = keys.count - 1
            cx[e] += cos(a) * endOffset * w; cy[e] += sin(a) * endOffset * w
        }
        var p = SwipePath(minDistance: layout.keyWidth / 5)
        if keys.count == 1 {
            for i in 0..<4 {
                p.add(x: Float(cx[0] + gauss() * jitter * w), y: Float(cy[0] + gauss() * jitter * w),
                      t: Double(i) / 60)
            }
            return p
        }
        var t = 0.0
        let m = keys.count
        for sg in 0..<(m - 1) {
            let i0 = max(sg - 1, 0), i1 = sg, i2 = sg + 1, i3 = min(sg + 2, m - 1)
            let n = max(2, Int(ceil(hypot(cx[i2] - cx[i1], cy[i2] - cy[i1]) / (step * w))))
            for j in 0..<n {
                let u = Double(j) / Double(n)
                let x = Self.catmull(cx[i0], cx[i1], cx[i2], cx[i3], u) + gauss() * jitter * w
                let y = Self.catmull(cy[i0], cy[i1], cy[i2], cy[i3], u) + gauss() * jitter * w
                p.add(x: Float(x), y: Float(y), t: t); t += 1.0 / 60
            }
        }
        p.add(x: Float(cx[m - 1]), y: Float(cy[m - 1]), t: t, force: true)
        return p
    }
}

final class SwipeDecoderTests: XCTestCase {
    private let layout = SwipeLayout.qwerty(keyWidth: 40, rowHeight: 54)
    private func decoder() -> SwipeDecoder {
        let d = SwipeDecoder(); d.setLayout(layout); return d
    }

    /// 500 dạng không dấu phổ biến nhất (≥ 2 phím sau gộp lặp) — cùng thứ tự bản Kotlin.
    private func corpus(_ n: Int = 500) -> [String] {
        let f = SwipeLexicon.forms
        return (0..<f.count)
            .filter { SwipeSim.collapse(f.folded[$0]).count >= 2 }
            .sorted { f.freq[$0] != f.freq[$1] ? f.freq[$0] > f.freq[$1] : f.folded[$0] < f.folded[$1] }
            .prefix(n).map { f.folded[$0] }
    }

    private func accuracy(_ d: SwipeDecoder, _ words: [String], seed: UInt64, sigma: Double = 0.25,
                          endOffset: Double = 0) -> (Double, Double) {
        var sim = SwipeSim(seed: seed)
        var t1 = 0, t3 = 0
        for w in words {
            let r = d.decode(sim.path(w, layout, sigma: sigma, endOffset: endOffset), topK: 3)
                .map(\.folded)
            if r.first == w { t1 += 1 }
            if r.contains(w) { t3 += 1 }
        }
        return (Double(t1) / Double(words.count), Double(t3) / Double(words.count))
    }

    /// String.hashCode của Java — để seed từng ca giống bản Kotlin.
    private func javaHash(_ s: String) -> UInt64 {
        var h: Int32 = 0
        for u in s.utf16 { h = h &* 31 &+ Int32(u) }
        return UInt64(UInt32(bitPattern: h)) & 0xFFFF
    }

    private func hitRate(_ d: SwipeDecoder, _ word: String, _ k: Int, n: Int = 20,
                         sigma: Double = 0.2, endOffset: Double = 0) -> Double {
        var sim = SwipeSim(seed: javaHash(word))
        var hit = 0
        for _ in 0..<n where d.decode(sim.path(word, layout, sigma: sigma, endOffset: endOffset),
                                      topK: k).contains(where: { $0.folded == word }) {
            hit += 1
        }
        return Double(hit) / Double(n)
    }

    private func cleanTop(_ d: SwipeDecoder, _ w: String, _ k: Int) -> Bool {
        var sim = SwipeSim(seed: 1)
        return d.decode(sim.path(w, layout, sigma: 0, jitter: 0), topK: k)
            .contains { $0.folded == w }
    }

    func testLexiconForms() {
        let f = SwipeLexicon.forms
        XCTAssertEqual(f.count, 1666)
        XCTAssertNotNil(SwipeLexicon.index(of: "viet"))
        XCTAssertNil(SwipeLexicon.index(of: "zzz"))
        let i = SwipeLexicon.index(of: "boong")!
        let keys = (Int(f.keyStart[i])..<Int(f.keyStart[i + 1]))
            .map { String(UnicodeScalar(f.keys[$0] + 97)) }.joined()
        XCTAssertEqual(keys, "bong")
    }

    func testAccuracyTop500() {
        let d = decoder(), words = corpus()
        let (a1, a3) = accuracy(d, words, seed: 42)
        let (b1, b3) = accuracy(d, words, seed: 7, sigma: 0.3)
        let (c1, c3) = accuracy(d, words, seed: 42, endOffset: 0.5)
        print(String(format: "SWIPE accuracy σ0.25: top1 %.3f top3 %.3f | σ0.3: %.3f/%.3f | lệch đầu/cuối 0.5: %.3f/%.3f",
                     a1, a3, b1, b3, c1, c3))
        XCTAssertGreaterThanOrEqual(a1, 0.85); XCTAssertGreaterThanOrEqual(a3, 0.98)
        XCTAssertGreaterThanOrEqual(b1, 0.78); XCTAssertGreaterThanOrEqual(b3, 0.95)
        XCTAssertGreaterThanOrEqual(c1, 0.62); XCTAssertGreaterThanOrEqual(c3, 0.88)
    }

    func testVietExpandsToAccented() {
        let d = decoder()
        XCTAssertGreaterThanOrEqual(hitRate(d, "viet", 3), 0.9)
        let words = SwipeDecoder.expand("viet").map(\.word)
        XCTAssertTrue(Set(words.prefix(3)).isSuperset(of: ["việt", "viết"]), "\(words)")
        XCTAssertTrue(SwipeDecoder.expand("di").map(\.word).contains("đi"))
    }

    func testHardPairsInTop3() {
        let d = decoder()
        for w in ["cho", "co", "nay", "ngay", "trong", "truong", "bua", "nua"] {
            let r = hitRate(d, w, 3)
            XCTAssertGreaterThanOrEqual(r, 0.85, "\(w) top-3 rate \(r)")
        }
    }

    func testRepeatedLetters() {
        let d = decoder()
        XCTAssertGreaterThanOrEqual(hitRate(d, "luu", 3), 0.9)
        XCTAssertGreaterThanOrEqual(hitRate(d, "boong", 3), 0.85)
        XCTAssertEqual(SwipeDecoder.expand("luu").first?.word, "lưu")
    }

    func testTwoLetterWords() {
        let d = decoder()
        for w in ["an", "em", "di", "la", "ta", "va", "de", "no"] {
            XCTAssertTrue(cleanTop(d, w, 1), "\(w) top-1 (đường sạch)")
            XCTAssertGreaterThanOrEqual(hitRate(d, w, 3), 0.9, "\(w) top-3 nhiễu")
        }
    }

    func testEndpointsOffsetHalfKey() {
        let d = decoder()
        for w in ["khong", "nguoi", "duoc", "viet", "chung"] {
            let r = hitRate(d, w, 3, sigma: 0.15, endOffset: 0.5)
            XCTAssertGreaterThanOrEqual(r, 0.8, "\(w) lệch nửa phím: \(r)")
        }
    }

    func testContextReranks() {
        let d = decoder()
        var sim = SwipeSim(seed: 3)
        let p = sim.path("cho", layout, sigma: 0, jitter: 0)
        // c-h-o thẳng hàng: hình học không phân biệt được với "co" → tần suất quyết
        XCTAssertEqual(d.decode(p, topK: 3).first?.folded, "co")
        XCTAssertEqual(d.decode(p, topK: 3) { $0 == "cho" ? 3 : 0 }.first?.folded, "cho")
        XCTAssertEqual(SwipeDecoder.expand("cho") { $0 == "chó" ? 5 : 0 }.first?.word, "chó")
    }

    func testLayoutChangeRebuildsAndOtherLayoutWorks() {
        let d = decoder()
        var s5 = SwipeSim(seed: 5)
        _ = d.decode(s5.path("khong", layout), topK: 1)
        XCTAssertTrue((1...1_000_000).contains(d.templateBytes), "RAM \(d.templateBytes)")
        let l2 = SwipeLayout.qwerty(keyWidth: 36, rowHeight: 58, originX: 3, originY: 10)
        d.setLayout(l2)
        XCTAssertEqual(d.templateBytes, 0)
        var sim = SwipeSim(seed: 9)
        var ok = 0
        for w in corpus(100) where d.decode(sim.path(w, l2), topK: 3).contains(where: { $0.folded == w }) {
            ok += 1
        }
        XCTAssertGreaterThanOrEqual(ok, 95, "top3 layout 2 = \(ok)/100")
    }

    func testSwipePathFiltersAndCaps() {
        var p = SwipePath(minDistance: 8, capacity: 4)
        XCTAssertTrue(p.add(x: 0, y: 0, t: 0))
        XCTAssertFalse(p.add(x: 3, y: 4, t: 0.01))        // 5 < 8
        XCTAssertTrue(p.add(x: 6, y: 8, t: 0.02))         // 10
        XCTAssertEqual(p.count, 2); XCTAssertEqual(p.length, 10, accuracy: 1e-4)
        XCTAssertTrue(p.add(x: 7, y: 8, t: 0.03, force: true))
        XCTAssertEqual(p.count, 3)
        p.add(x: 20, y: 8, t: 0.04); XCTAssertEqual(p.count, 4)
        p.add(x: 40, y: 8, t: 0.05)                        // đầy → ghi đè điểm cuối
        XCTAssertEqual(p.count, 4); XCTAssertEqual(p.xs[3], 40)
        XCTAssertEqual(p.length, 44, accuracy: 1e-3)       // 10+1+33
        XCTAssertEqual(p.duration, 0.05, accuracy: 1e-9)
        p.reset(); XCTAssertEqual(p.count, 0)
        XCTAssertTrue(SwipeDecoder().decode(p).isEmpty)
    }

    func testBenchmark() {
        let d = decoder()
        _ = SwipeLexicon.forms
        let t0 = CFAbsoluteTimeGetCurrent(); d.prepare()
        let build = (CFAbsoluteTimeGetCurrent() - t0) * 1000
        var sim = SwipeSim(seed: 11)
        let paths = corpus(200).map { sim.path($0, layout) }
        for p in paths { _ = d.decode(p, topK: 5) }
        let t1 = CFAbsoluteTimeGetCurrent()
        for p in paths { _ = d.decode(p, topK: 5) }
        let per = (CFAbsoluteTimeGetCurrent() - t1) * 1000 / Double(paths.count)
        print(String(format: "SWIPE benchmark iOS: dựng template %.1f ms, decode %.3f ms/đường, RAM template %d B",
                     build, per, d.templateBytes))
        XCTAssertLessThan(per, 20)   // Debug -Onone trên simulator; Release nhanh hơn nhiều
    }

    /// Fixture sinh bởi bản Kotlin (SWIPE_WRITE_FIXTURE=1): top-1 hai bản phải trùng khít.
    func testFixtureParityWithKotlin() throws {
        let url = try XCTUnwrap(Bundle(for: SwipeDecoderTests.self)
            .url(forResource: "swipe-paths", withExtension: "txt"))
        let text = try String(contentsOf: url, encoding: .utf8)
        let d = decoder()
        var n = 0, same = 0
        var diffs: [String] = []
        for line in text.split(separator: "\n") where !line.hasPrefix("#") && !line.isEmpty {
            let cols = line.split(separator: "\t")
            let pts = cols[2].split(separator: ";").map { $0.split(separator: ",") }
            let xs = pts.map { Float(String($0[0]))! }, ys = pts.map { Float(String($0[1]))! }
            n += 1
            let top = d.decode(xs: xs, ys: ys, count: xs.count, topK: 1).first?.folded
            if top == String(cols[1]) { same += 1 } else { diffs.append("\(cols[0]): \(top ?? "-") ≠ \(cols[1])") }
        }
        XCTAssertGreaterThanOrEqual(n, 150)
        XCTAssertEqual(same, n, "lệch Kotlin: \(diffs)")
    }
}
