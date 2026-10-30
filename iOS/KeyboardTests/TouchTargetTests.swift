// Chọn phím theo ngữ cảnh (TouchTarget) — song sinh Android TouchSimTests.kt: hợp đồng,
// parity số với Kotlin, và hồi quy mô phỏng gõ chạm rút gọn (câu Tatoeba giữ lại).
import XCTest
import TelexCore

final class TouchTargetTests: XCTestCase {
    private static let prior = TelexKeyPrior.fromLexicon()
    private var prior: TelexKeyPrior { Self.prior }

    // MARK: hình học QWERTY iPhone dọc (pt): bước 40, mặt 34; hàng 54, mặt 42 — như TouchSim.Geo

    private struct Geo {
        var rects: [CGRect] = []
        var keys: [Character] = []
        var index: [Character: Int] = [:]
        init() {
            let rows: [(String, CGFloat)] = [("qwertyuiop", 0), ("asdfghjkl", 0.5), ("zxcvbnm", 1.5)]
            for (r, row) in rows.enumerated() {
                for (i, c) in row.0.enumerated() {
                    let cx = (row.1 + CGFloat(i) + 0.5) * 40, cy = (CGFloat(r) + 0.5) * 54
                    index[c] = rects.count
                    rects.append(CGRect(x: cx - 17, y: cy - 21, width: 34, height: 42))
                    keys.append(c)
                }
            }
        }
        /// Router gần-nhất (như KeyboardView.nearestLetterButton).
        func nearest(_ p: CGPoint) -> Int? {
            guard p.y >= 0 else { return nil }
            var best = -1; var bestD = CGFloat.greatestFiniteMagnitude
            for (i, f) in rects.enumerated() {
                if f.insetBy(dx: -3, dy: -5.5).contains(p) { return i }
                let dx = max(f.minX - p.x, 0, p.x - f.maxX), dy = max(f.minY - p.y, 0, p.y - f.maxY)
                if dx * dx + dy * dy < bestD { best = i; bestD = dx * dx + dy * dy }
            }
            return bestD <= 21 * 21 ? best : nil
        }
    }
    private let g = Geo()

    // MARK: hợp đồng

    func testVariants() {
        XCTAssertEqual(TelexSpell.variants("tiếng")?.map(\.keys), ["tieengs", "tieesng"])
        XCTAssertEqual(TelexSpell.variants("tiếng")?.map(\.share), [0.6, 0.4])
        XCTAssertEqual(TelexSpell.variants("được")?.map(\.keys), ["dduwowcj", "dduwowjc", "dduowcj", "dduowjc"])
        XCTAssertEqual(TelexSpell.variants("hòa")?.map(\.keys), ["hoaf"])
        XCTAssertNil(TelexSpell.variants("a1"))
    }

    /// Số chốt từ Android TouchSimTests.parityNumbers — cùng dữ liệu ⇒ cùng trie.
    func testParityWithKotlin() throws {
        XCTAssertEqual(prior.trie.nodeCount, 63370)
        let cases: [(String, Character, Float)] = [
            ("", "t", 0.16052505), ("", "z", 2.420141e-5), ("th", "a", 0.25838506), ("ng", "u", 0.49238884),
            ("k", "o", 0.002160288), ("tie", "e", 0.99860436), ("dd", "u", 0.17761526), ("hel", "l", 0.17500657),
        ]
        for (raw, c, want) in cases {
            let f = try XCTUnwrap(prior.forRaw(raw))
            let v = try XCTUnwrap(f(c))
            XCTAssertEqual(v, want, accuracy: want * 1e-3, "\(raw)→\(c)")
        }
        XCTAssertNil(prior.forRaw("qqq"))
        // VNI: trie theo phím Telex ⇒ không prior (router cũ), Telex ⇒ như forRaw.
        XCTAssertNil(prior.forTyping("tie", vniMode: true))
        XCTAssertEqual(try XCTUnwrap(prior.forTyping("tie", vniMode: false)?("e")), try XCTUnwrap(prior.forRaw("tie")?("e")))
        XCTAssertNil(prior.forRaw(String(repeating: "a", count: TelexKeyPrior.maxRaw + 1)))
    }

    /// Chỉ phím chữ: "." cạnh "m" không bao giờ bị đổi sang chữ (hay ngược lại), kể cả prior cho "." điểm.
    func testPunctuationNeverRerouted() {
        let iM = g.index["m"]!, m = g.rects[iM]
        let dot = CGRect(x: m.maxX + 6, y: m.minY, width: m.width, height: m.height)
        let rects = g.rects + [dot], iDot = rects.count - 1
        let keys = g.keys + ["."]
        let nearDot = CGPoint(x: dot.minX + 0.05 * m.width, y: m.midY)
        let nearM = CGPoint(x: m.maxX - 0.05 * m.width, y: m.midY)
        XCTAssertEqual(TouchTarget.choose(nearDot, rects: rects, keys: keys, nearest: iDot,
                                          prior: { $0 == "m" ? 1 : 0 }), iDot)
        XCTAssertEqual(TouchTarget.choose(nearM, rects: rects, keys: keys, nearest: iM,
                                          prior: { $0 == "." ? 1 : 0 }), iM)
        // đối chứng: cùng hình học, phím đó là CHỮ thì đổi được (test trên không rỗng)
        let keysZ = g.keys + ["z"]
        XCTAssertEqual(TouchTarget.choose(nearM, rects: rects, keys: keysZ, nearest: iM,
                                          prior: { $0 == "z" ? 1 : 0 }), iDot)
        XCTAssertEqual(TouchTarget.choose(nearDot, rects: rects, keys: keysZ, nearest: iDot,
                                          prior: { $0 == "m" ? 1 : 0 }), iM)
    }

    func testKeyCenterAlwaysWins() {
        let iQ = g.index["q"]!, iW = g.index["w"]!
        let onlyW: (Character) -> Float? = { $0 == "w" ? 1 : 0 }
        let r = g.rects[iQ]
        XCTAssertEqual(TouchTarget.choose(CGPoint(x: r.midX, y: r.midY), rects: g.rects, keys: g.keys,
                                          nearest: iQ, prior: onlyW), iQ)
        let edge = CGPoint(x: r.maxX - 0.05 * r.width, y: r.midY)
        XCTAssertEqual(TouchTarget.choose(edge, rects: g.rects, keys: g.keys, nearest: iQ, prior: onlyW), iW)
        XCTAssertEqual(TouchTarget.choose(edge, rects: g.rects, keys: g.keys, nearest: iQ, prior: { _ in nil }), iQ)
        XCTAssertEqual(TouchTarget.choose(edge, rects: g.rects, keys: g.keys, nearest: iQ, prior: { _ in 1 / 26 }), iQ)
    }

    // MARK: hồi quy mô phỏng (400 câu, người gõ "vừa" σ .22/.27 + lệch xuống, và "cẩn thận" σ .15)

    /// RNG xác định (SplitMix64 + Box–Muller).
    private struct RNG {
        var s: UInt64
        mutating func next() -> UInt64 {
            s &+= 0x9E3779B97F4A7C15
            var z = s
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
        mutating func uniform() -> Double { Double(next() >> 11) / Double(1 << 53) }
        mutating func gauss() -> Double {
            let u = max(uniform(), 1e-12), v = uniform()
            return (-2 * log(u)).squareRoot() * cos(2 * .pi * v)
        }
    }

    private func compose(_ raw: String) -> String {
        var e = TelexEngine()
        e.freeMarking = true; e.simpleTelex = true; e.liveSpellCheck = true
        e.quickTelex = false; e.modernTone = false; e.teencode = false
        for ch in raw { _ = e.feed(ch) }
        return SyllableLM.normalize(e.composed)
    }

    private func heldout() throws -> [[String]] {
        let url = try XCTUnwrap(Bundle(for: TouchTargetTests.self).url(forResource: "bigram-heldout", withExtension: "txt"))
        return try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
            .filter { !$0.hasPrefix("#") && !$0.isEmpty }
            .map { $0.split(separator: " ").map(String.init) }
    }

    /// (từ sai, tổng từ, chạm đổi nhầm, tổng chạm)
    private func simulate(_ sents: [[String]], sx: Double, sy: Double, by: Double, smart: Bool, seed: UInt64)
        -> (wrong: Int, words: Int, bad: Int, taps: Int) {
        var rng = RNG(s: seed)
        var wrong = 0, words = 0, bad = 0, taps = 0
        for sent in sents {
            for syl in sent {
                let want = SyllableLM.normalize(syl)
                let vs = (TelexSpell.variants(syl) ?? []).filter { compose($0.keys) == want }
                guard !vs.isEmpty else { continue }
                var r = rng.uniform() * Double(vs.reduce(0) { $0 + $1.share })
                var intended = vs.last!.keys
                for v in vs { r -= Double(v.share); if r <= 0 { intended = v.keys; break } }
                var typed = ""
                for ch in intended {
                    let k = g.index[ch]!
                    let c = CGPoint(x: g.rects[k].midX, y: g.rects[k].midY)
                    let raw = CGPoint(x: c.x + 40 * sx * rng.gauss(), y: c.y + 40 * (by + sy * rng.gauss()))
                    let p = TouchGeometry.keySelectionPoint(raw)
                    guard let n = g.nearest(p) else { taps += 1; continue }
                    var m = n
                    if smart, let f = prior.forRaw(typed) {
                        m = TouchTarget.choose(p, rects: g.rects, keys: g.keys, nearest: n, prior: f)
                    }
                    taps += 1
                    if n == k && m != k { bad += 1 }
                    typed.append(g.keys[m])
                }
                words += 1
                if compose(typed) != want { wrong += 1 }
            }
        }
        return (wrong, words, bad, taps)
    }

    func testSimulationReducesSlipsSafely() throws {
        let all = try heldout()
        let sub = Array(all.enumerated().filter { $0.offset % 2 == 1 }.map(\.element).prefix(400))
        let aMid = simulate(sub, sx: 0.22, sy: 0.27, by: 0.12, smart: false, seed: 3)
        let bMid = simulate(sub, sx: 0.22, sy: 0.27, by: 0.12, smart: true, seed: 3)
        let aCar = simulate(sub, sx: 0.15, sy: 0.15, by: 0.10, smart: false, seed: 3)
        let bCar = simulate(sub, sx: 0.15, sy: 0.15, by: 0.10, smart: true, seed: 3)
        print("TOUCHSIM iOS vừa: từ sai \(aMid.wrong) → \(bMid.wrong) / \(aMid.words), đổi nhầm \(bMid.bad)/\(bMid.taps)"
              + " | cẩn thận: \(aCar.wrong) → \(bCar.wrong)")
        XCTAssertLessThanOrEqual(Double(bMid.wrong), Double(aMid.wrong) * 0.6)
        XCTAssertLessThanOrEqual(Double(bMid.bad) * 1000, Double(bMid.taps) * 1.5)
        XCTAssertLessThanOrEqual(bCar.wrong, aCar.wrong)
    }

    /// Độ trễ lúc chạm (forRaw + choose, chạm vùng biên ngẫu nhiên).
    func testLatency() throws {
        try SlowTests.require()
        var rng = RNG(s: 9)
        let raws = ["", "t", "th", "ng", "nguo", "tie", "kh", "dduow", "mo", "vie"]
        let pts = (0..<1024).map { _ -> CGPoint in
            let k = Int(rng.next() % 26)
            return CGPoint(x: g.rects[k].midX + 12 * rng.gauss(), y: g.rects[k].midY + 14 * rng.gauss())
        }
        var sink = 0
        let n = 10_000
        // Lấy lô NHANH NHẤT trong 5 lô: máy bận (build song song) không làm test chập chờn.
        var us = Double.infinity
        for _ in 0..<5 {
            let t0 = CFAbsoluteTimeGetCurrent()
            for i in 0..<n {
                let p = pts[i & 1023]
                guard let near = g.nearest(p), let f = prior.forRaw(raws[i % raws.count]) else { continue }
                sink &+= TouchTarget.choose(p, rects: g.rects, keys: g.keys, nearest: near, prior: f)
            }
            us = min(us, (CFAbsoluteTimeGetCurrent() - t0) * 1e6 / Double(n))
        }
        let t1 = CFAbsoluteTimeGetCurrent()
        let fresh = TelexKeyPrior.fromLexicon()
        print(String(format: "TOUCHSIM iOS router+prior %.2f µs/chạm (sink %d); dựng trie %.0f ms (%d nút)",
                     us, sink, (CFAbsoluteTimeGetCurrent() - t1) * 1000, fresh.trie.nodeCount))
        XCTAssertLessThan(us, 100)   // build Debug -Onone trên simulator; Release nhanh hơn nhiều
    }
}
