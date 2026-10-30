// Evaluation.swift — chạy cả corpus cho một cấu hình, tính số đo, đọc/ghi golden.
//
// Số đo theo nhóm (vi, en, mix, tech, collide, teen); "overall" = TRUNG BÌNH KHÔNG TRỌNG SỐ của
// các nhóm (nhóm nhỏ như teen nặng ngang nhóm lớn — đúng chủ ý: mỗi kiểu gõ một phiếu).
//   lazy_wrong       % từ sai, người gõ lười (không bao giờ bật/tắt bộ gõ)
//   lazy_vi_wrong    % từ VIỆT sai (trên số từ Việt)
//   lazy_en_wrong    % từ ANH sai (trên số từ Anh; nhóm không có từ Anh thì bỏ)
//   toggles_per_100  số lần bật/tắt bộ gõ / 100 từ, người gõ lý tưởng
//   ideal_wrong      % từ vẫn sai dù người gõ lý tưởng (cả hai chế độ đều không ra đúng)
// Mọi số: CÀNG THẤP CÀNG TỐT.

import Foundation
import TelexCore

public struct Counts: Sendable {
    public var sentences = 0, words = 0, vi = 0, en = 0
    public var lazyWrongVI = 0, lazyWrongEN = 0, idealWrong = 0, toggles = 0

    mutating func add(_ o: Counts) {
        sentences += o.sentences; words += o.words; vi += o.vi; en += o.en
        lazyWrongVI += o.lazyWrongVI; lazyWrongEN += o.lazyWrongEN
        idealWrong += o.idealWrong; toggles += o.toggles
    }

    private func pct(_ a: Int, _ b: Int) -> Double? { b == 0 ? nil : 100 * Double(a) / Double(b) }

    public var metrics: [String: Double] {
        var m: [String: Double] = [:]
        m["lazy_wrong"] = pct(lazyWrongVI + lazyWrongEN, words)
        m["lazy_vi_wrong"] = pct(lazyWrongVI, vi)
        m["lazy_en_wrong"] = pct(lazyWrongEN, en)
        m["toggles_per_100"] = pct(toggles, words)
        m["ideal_wrong"] = pct(idealWrong, words)
        return m
    }
}

public let metricNames = ["lazy_wrong", "lazy_vi_wrong", "lazy_en_wrong", "toggles_per_100", "ideal_wrong"]
public let categoryOrder = ["vi", "en", "mix", "tech", "collide", "teen"]

/// Một từ sai (người gõ lười).
public struct WrongWord: Sendable {
    public let target: String
    public let output: String      // "∅" khi lệch số từ
    public let english: Bool
}

public struct WrongLine: Sendable {
    public let sentence: MixedSentence
    public let output: String
    public let wrong: [WrongWord]
}

public struct ConfigResult: Sendable {
    public let config: SimConfig
    /// split → nhóm → đếm
    public var counts: [String: [String: Counts]] = [:]
    public var wrongLines: [WrongLine] = []
    /// Thời gian từng lệnh engine ở lượt gõ lười: phím chữ (feed, ⌫) và phím ranh giới.
    public var latencyKeyNs: [UInt64] = []
    public var latencyBoundaryNs: [UInt64] = []

    /// split → nhóm (+ "overall") → số đo
    public func metrics(split: String) -> [String: [String: Double]] {
        let cats = counts[split] ?? [:]
        var out: [String: [String: Double]] = [:]
        for (c, n) in cats { out[c] = n.metrics }
        var overall: [String: Double] = [:]
        for m in metricNames {
            let vals = cats.values.compactMap { $0.metrics[m] }
            if !vals.isEmpty { overall[m] = vals.reduce(0, +) / Double(vals.count) }
        }
        out["overall"] = overall
        return out
    }
}

public enum Evaluation {
    /// Chạy mọi câu (cả val lẫn test) cho một cấu hình. `timing`: đo thời gian từng lệnh engine
    /// (feed / ⌫ / chốt ranh giới) ở lượt gõ lười.
    public static func run(_ corpus: [MixedSentence], _ cfg: SimConfig, timing: Bool = false,
                           options: TypistOptions = TypistOptions()) -> ConfigResult {
        var r = ConfigResult(config: cfg)
        var samples: [UInt64] = [], bsamples: [UInt64] = []
        if timing { samples.reserveCapacity(corpus.count * 64); bsamples.reserveCapacity(corpus.count * 16) }
        for s in corpus {
            let plans = Typist.plan(s, options)
            let lz = Runner.lazy(s, plans, cfg, timing: timing, samples: &samples, boundarySamples: &bsamples)
            let id = Runner.ideal(s, plans, cfg)
            var c = Counts()
            c.sentences = 1
            c.words = s.words.count
            var wrong: [WrongWord] = []
            for (i, eng) in s.english.enumerated() {
                if eng { c.en += 1 } else { c.vi += 1 }
                if !lz.correct[i] {
                    if eng { c.lazyWrongEN += 1 } else { c.lazyWrongVI += 1 }
                    wrong.append(WrongWord(target: s.words[i], output: lz.outWords[i] ?? "∅", english: eng))
                }
                if !id.correct[i] { c.idealWrong += 1 }
            }
            c.toggles = id.toggles
            r.counts[s.split, default: [:]][s.category, default: Counts()].add(c)
            if !wrong.isEmpty { r.wrongLines.append(WrongLine(sentence: s, output: lz.output, wrong: wrong)) }
        }
        r.latencyKeyNs = samples
        r.latencyBoundaryNs = bsamples
        return r
    }

    // MARK: Golden

    public static func goldenJSON(_ results: [ConfigResult], tolerance: Double) -> Data {
        var cfgs: [String: Any] = [:]
        for r in results {
            var splits: [String: Any] = [:]
            for split in ["val", "test"] {
                var cats: [String: Any] = [:]
                for (c, m) in r.metrics(split: split) {
                    cats[c] = m.mapValues { NSDecimalNumber(string: String(format: "%.3f", $0)) }
                }
                splits[split] = cats
            }
            cfgs[r.config.name] = splits
        }
        let root: [String: Any] = [
            "_doc": "Golden của mô phỏng gõ câu trộn (docs/REGRESSION.md). Mọi số càng thấp càng tốt; "
                + "MixedTypingGoldenTests fail khi số đo hiện tại > golden + tolerance_pp. "
                + "Cập nhật: cd TelexCore && swift run -c release mixed-eval --write-golden",
            "tolerance_pp": tolerance,
            "configs": cfgs,
        ]
        return (try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])) ?? Data()
    }

    public struct Comparison: Sendable {
        public var regressions: [String] = []
        public var improvements: [String] = []
        public var missing: [String] = []
    }

    /// So kết quả với golden. Số đo nào > golden + tol ⇒ regression; < golden − tol ⇒ cải thiện.
    public static func compare(_ results: [ConfigResult], golden: Data) throws -> Comparison {
        guard let root = try JSONSerialization.jsonObject(with: golden) as? [String: Any],
              let cfgs = root["configs"] as? [String: Any] else { throw GoldenError.malformed }
        let tol = (root["tolerance_pp"] as? Double) ?? 0.05
        var cmp = Comparison()
        for r in results {
            guard let splits = cfgs[r.config.name] as? [String: Any] else { cmp.missing.append(r.config.name); continue }
            for split in ["val", "test"] {
                let now = r.metrics(split: split)
                let gold = splits[split] as? [String: [String: Double]] ?? [:]
                for (cat, gm) in gold {
                    for (m, g) in gm {
                        let key = "\(r.config.name)/\(split)/\(cat)/\(m)"
                        guard let v = now[cat]?[m] else { cmp.missing.append(key); continue }
                        if v > g + tol { cmp.regressions.append("\(key): \(fmt3(v)) > golden \(fmt3(g))") }
                        else if v < g - tol { cmp.improvements.append("\(key): \(fmt3(v)) < golden \(fmt3(g))") }
                    }
                }
            }
        }
        return cmp
    }

    public enum GoldenError: Error { case malformed }

    private static func fmt3(_ v: Double) -> String { String(format: "%.3f", v) }
}
