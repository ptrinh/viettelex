// Gõ vuốt giai đoạn 3 — từ tiếng Anh xen câu Việt. Cùng bộ ca với
// android/keyboard/src/test/…/SwipeEnglishTests.kt; parity top-1 qua
// Fixtures/swipe-paths-en.txt (sinh bởi bản Kotlin, SWIPE_WRITE_FIXTURE=1).
import XCTest

final class SwipeEnglishTests: XCTestCase {
    private let layout = SwipeLayout.qwerty(keyWidth: 40, rowHeight: 54)
    private func decoder() -> SwipeDecoder {
        let d = SwipeDecoder(); d.setLayout(layout); return d
    }

    /// n từ Anh phổ biến nhất (≥ 2 phím sau gộp lặp) — cùng thứ tự bản Kotlin.
    private func englishCorpus(_ n: Int = 1000) -> [String] {
        let e = SwipeEnglish.lexicon
        return (0..<e.count)
            .filter { SwipeSim.collapse(e.word($0)).count >= 2 }
            .sorted { e.freq[$0] != e.freq[$1] ? e.freq[$0] > e.freq[$1] : e.word($0) < e.word($1) }
            .prefix(n).map { e.word($0) }
    }

    private func vnCorpus(_ n: Int = 500) -> [String] {
        let f = SwipeLexicon.forms
        return (0..<f.count)
            .filter { SwipeSim.collapse(f.folded[$0]).count >= 2 }
            .sorted { f.freq[$0] != f.freq[$1] ? f.freq[$0] > f.freq[$1] : f.folded[$0] < f.folded[$1] }
            .prefix(n).map { f.folded[$0] }
    }

    private func accuracy(_ d: SwipeDecoder, _ words: [String], lang: SwipeLang,
                          prior: SwipeEnglishPrior?, seed: UInt64 = 42, sigma: Double = 0.25,
                          endOffset: Double = 0) -> (Double, Double) {
        var sim = SwipeSim(seed: seed)
        var t1 = 0, t3 = 0
        for w in words {
            let r = d.decode(sim.path(w, layout, sigma: sigma, endOffset: endOffset), topK: 3,
                             english: prior)
            if let f = r.first, f.lang == lang, f.folded == w { t1 += 1 }
            if r.contains(where: { $0.lang == lang && $0.folded == w }) { t3 += 1 }
        }
        return (Double(t1) / Double(words.count), Double(t3) / Double(words.count))
    }

    private func clean(_ w: String) -> SwipePath {
        var sim = SwipeSim(seed: 1)
        return sim.path(w, layout, sigma: 0, jitter: 0)
    }

    func testLexiconLoadsAndBuckets() {
        let e = SwipeEnglish.lexicon
        XCTAssertTrue((10_000...20_100).contains(e.count), "\(e.count)")   // 20.000 + SUPPLEMENT của gen-enlexicon
        XCTAssertTrue(SwipeEnglish.contains("check") && SwipeEnglish.contains("mail"))
        XCTAssertFalse(SwipeEnglish.contains("a"))
        XCTAssertFalse(SwipeEnglish.contains("fuck"))
        XCTAssertEqual(Int(e.swipe.bucketStart[676]), e.count)
        let i = SwipeEnglish.index(of: "hello")!
        let keys = (Int(e.swipe.keyStart[i])..<Int(e.swipe.keyStart[i + 1]))
            .map { String(UnicodeScalar(e.swipe.keys[$0] + 97)) }.joined()
        XCTAssertEqual(keys, "helo")
    }

    func testClassifyContext() {
        XCTAssertEqual(SwipeLangContext.classify("tôi"), .vi)
        XCTAssertEqual(SwipeLangContext.classify("check"), .en)
        XCTAssertEqual(SwipeLangContext.classify("The"), .en)
        XCTAssertEqual(SwipeLangContext.classify("email"), .neutral)
        XCTAssertEqual(SwipeLangContext.classify("anh"), .vi)
        XCTAssertEqual(SwipeLangContext.classify(nil), .neutral)
        XCTAssertEqual(SwipeLangContext.classify("thế", swipedEnglish: true), .en)
        XCTAssertEqual(SwipeLangContext.prior(prev1: .en, prev2: .vi), SwipeLangContext.englishPrior)
        XCTAssertEqual(SwipeLangContext.prior(prev1: .neutral, prev2: .neutral), SwipeLangContext.defaultPrior)
    }

    /// Tiền nghiệm liên tục ngôn ngữ — cùng ca với SwipeEnglishTests.kt continuityPrior.
    func testContinuityPrior() {
        func p(_ k: SwipeLangContext.Kind...) -> SwipeEnglishPrior { SwipeLangContext.prior(k) }
        let def = SwipeLangContext.defaultPrior, en = SwipeLangContext.englishPrior
        // không có ngữ cảnh / toàn trung tính / mạch Việt ⇒ y hệt DEFAULT (từ rời không đổi)
        XCTAssertEqual(p(), def)
        XCTAssertEqual(p(.neutral, .neutral, .neutral), def)
        XCTAssertEqual(p(.vi), def)
        XCTAssertEqual(p(.vi, .vi, .vi), def)
        // một từ Anh liền trước ⇒ englishPrior; mạch dài hơn ⇒ mạnh hơn, có trần
        XCTAssertEqual(p(.en), en)
        XCTAssertEqual(p(.en, .vi, .en), en)                         // từ Việt cắt mạch
        XCTAssertEqual(p(.en, .en).bias, 0.5, accuracy: 1e-4)
        XCTAssertEqual(p(.en, .en, .en).bias, 0.68, accuracy: 1e-4)
        XCTAssertEqual(p(.en, .en, .en).margin, 0)
        XCTAssertLessThanOrEqual(p(.en, .en, .en, .en).bias, p(.en, .en, .en).bias + 1e-6)
        let far = p(.neutral, .en)
        XCTAssertTrue(far.bias > def.bias && far.bias < en.bias, "\(far)")
        XCTAssertTrue(far.margin > 0 && far.margin < def.margin, "\(far)")
        XCTAssertGreaterThan(p(.neutral, .en, .en).bias, far.bias)
        XCTAssertEqual(p(.vi, .en, .en), def)                        // "check mail cho …"
        let c = SwipeLangContext.continuity
        XCTAssertLessThanOrEqual(p(.en, .en, .en).bias, c.enBias + c.enGain * (c.enCap - 1) + 1e-6)
    }

    func testContinuityKinds() {
        let none: (String?) -> Bool = { _ in false }
        XCTAssertEqual(SwipeLangContext.kinds(composing: false, pending: nil, pendingEnglish: false,
                                              recent: ["tôi", "thích", "check"], english: none), [.en, .vi, .vi])
        XCTAssertEqual(SwipeLangContext.kinds(composing: true, pending: "này", pendingEnglish: false,
                                              recent: ["tôi", "thích", "check"], english: none), [.vi, .en, .vi])
        XCTAssertEqual(SwipeLangContext.kinds(composing: true, pending: nil, pendingEnglish: false,
                                              recent: ["check"], english: none), [.neutral, .en])
        XCTAssertEqual(SwipeLangContext.kinds(composing: false, pending: nil, pendingEnglish: false,
                                              recent: ["to"], english: { $0 == "to" }), [.en])
        XCTAssertEqual(SwipeLangContext.kinds(composing: true, pending: "can", pendingEnglish: true,
                                              recent: [], english: none), [.en])
        XCTAssertEqual(SwipeLangContext.kinds(composing: false, pending: nil, pendingEnglish: false,
                                              recent: [], english: none), [])
    }

    func testCollisionPrefersVietnameseAndOffersEnglish() {
        let d = decoder()
        let prior = SwipeLangContext.prior(prev1: SwipeLangContext.classify("tôi"), prev2: .neutral)
        let r = d.decode(clean("the"), topK: 5, english: prior)
        XCTAssertEqual(r.first?.folded, "the"); XCTAssertEqual(r.first?.lang, .vi)
        XCTAssertTrue(r.contains { $0.lang == .en && $0.folded == "the" }, "\(r)")
        let en = SwipeLangContext.prior(prev1: SwipeLangContext.classify("check"), prev2: .vi)
        let m = d.decode(clean("mail"), topK: 5, english: en)
        XCTAssertEqual(m.first?.folded, "mail"); XCTAssertEqual(m.first?.lang, .en)
        XCTAssertTrue(m.contains { $0.lang == .vi })
        for w in ["hello", "good", "meeting", "check", "file"] {
            let h = d.decode(clean(w), topK: 5, english: SwipeLangContext.englishPrior)
            XCTAssertTrue(h.contains { $0.lang == .en && $0.folded == w }, "\(w): \(h)")
        }
    }

    func testArbitrateMarginAndCrossLanguage() {
        let en = SwipeCandidate(folded: "the", score: 3.0, lang: .en)
        let vi = SwipeCandidate(folded: "the", score: 2.7)
        let vi2 = SwipeCandidate(folded: "tha", score: 2.0)
        XCTAssertEqual(SwipeDecoder.arbitrate([en, vi], topK: 2, margin: 0.5), [vi, en])
        XCTAssertEqual(SwipeDecoder.arbitrate([en, vi], topK: 2, margin: 0.2), [en, vi])
        XCTAssertEqual(SwipeDecoder.arbitrate([en, vi], topK: 2, margin: 0), [en, vi])
        XCTAssertEqual(SwipeDecoder.arbitrate([vi, vi2, en], topK: 2, margin: 0.5), [vi, vi2, en])
    }

    func testMeasureEnglishAndVietnamese() throws {
        try SlowTests.require()
        let d = decoder()
        let en = englishCorpus(), vn = vnCorpus()
        let (e1d, e3d) = accuracy(d, en, lang: .en, prior: SwipeLangContext.defaultPrior)
        let (e1e, e3e) = accuracy(d, en, lang: .en, prior: SwipeLangContext.englishPrior)
        let (b1, b3) = accuracy(d, vn, lang: .vi, prior: nil)
        let (v1, v3) = accuracy(d, vn, lang: .vi, prior: SwipeLangContext.defaultPrior)
        let (bb1, _) = accuracy(d, vn, lang: .vi, prior: nil, seed: 7, sigma: 0.3)
        let (vb1, _) = accuracy(d, vn, lang: .vi, prior: SwipeLangContext.defaultPrior, seed: 7, sigma: 0.3)
        print(String(format: "SWIPE-EN iOS top1000 Anh: ngữ cảnh Việt %.3f/%.3f | mạch Anh %.3f/%.3f | Việt tắt EN %.3f/%.3f → bật %.3f/%.3f | σ0.3 %.3f→%.3f",
                     e1d, e3d, e1e, e3e, b1, b3, v1, v3, bb1, vb1))
        XCTAssertGreaterThanOrEqual(v1, b1 - 0.01)
        XCTAssertGreaterThanOrEqual(vb1, bb1 - 0.01)
        XCTAssertGreaterThanOrEqual(v1, 0.85); XCTAssertGreaterThanOrEqual(v3, 0.98)
        XCTAssertGreaterThanOrEqual(e3e, 0.85); XCTAssertGreaterThanOrEqual(e1e, 0.65)
        XCTAssertGreaterThanOrEqual(e3d, 0.80)
    }

    func testBenchmarkWithEnglish() throws {
        try SlowTests.require()
        let d = decoder()
        d.prepare()
        let t0 = CFAbsoluteTimeGetCurrent(); _ = SwipeEnglish.lexicon
        let load = (CFAbsoluteTimeGetCurrent() - t0) * 1000
        var sim = SwipeSim(seed: 11)
        let paths = (vnCorpus(100) + englishCorpus(100)).map { sim.path($0, layout) }
        for p in paths { _ = d.decode(p, topK: 5, english: SwipeLangContext.defaultPrior) }
        let t1 = CFAbsoluteTimeGetCurrent()
        for p in paths { _ = d.decode(p, topK: 5, english: SwipeLangContext.defaultPrior) }
        let per = (CFAbsoluteTimeGetCurrent() - t1) * 1000 / Double(paths.count)
        let t2 = CFAbsoluteTimeGetCurrent()
        for p in paths { _ = d.decode(p, topK: 5) }
        let base = (CFAbsoluteTimeGetCurrent() - t2) * 1000 / Double(paths.count)
        print(String(format: "SWIPE-EN benchmark iOS: nạp từ điển %.1f ms, decode %.3f ms/đường (không EN %.3f)",
                     load, per, base))
        XCTAssertLessThan(per, 40)   // Debug -Onone trên simulator
    }

    func testFixtureParityWithKotlin() throws {
        let url = try XCTUnwrap(Bundle(for: SwipeEnglishTests.self)
            .url(forResource: "swipe-paths-en", withExtension: "txt"))
        let text = try String(contentsOf: url, encoding: .utf8)
        let d = decoder()
        var n = 0, same = 0
        var diffs: [String] = []
        for line in text.split(separator: "\n") where !line.hasPrefix("#") && !line.isEmpty {
            let cols = line.split(separator: "\t")
            let pts = cols[3].split(separator: ";").map { $0.split(separator: ",") }
            let xs = pts.map { Float(String($0[0]))! }, ys = pts.map { Float(String($0[1]))! }
            let prior = cols[1] == "en" ? SwipeLangContext.englishPrior : SwipeLangContext.defaultPrior
            n += 1
            let top = d.decode(xs: xs, ys: ys, count: xs.count, topK: 3, english: prior).first
            let got = top.map { ($0.lang == .en ? "en:" : "vi:") + $0.folded } ?? "-"
            if got == String(cols[2]) { same += 1 } else { diffs.append("\(cols[0]): \(got) ≠ \(cols[2])") }
        }
        XCTAssertGreaterThanOrEqual(n, 150)
        XCTAssertEqual(same, n, "lệch Kotlin: \(diffs)")
    }
}
