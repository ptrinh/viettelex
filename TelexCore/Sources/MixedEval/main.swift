// mixed-eval — mô phỏng gõ câu trộn Việt–Anh, từng phím qua TelexEngine thật.
//
//   cd TelexCore && swift run -c release mixed-eval [tuỳ chọn]
//     --config NAME     chỉ chạy một cấu hình (default | retro | no-context); mặc định: cả ba
//     --diff-config N   cấu hình in diff từng dòng (mặc định: default)
//     --lines N         số dòng diff in ra (mặc định 60; 0 = không in; -1 = tất cả)
//     --top N           số mẫu lỗi hay gặp nhất (mặc định 25)
//     --unlock-test     in cả diff/mẫu lỗi của tập TEST (đừng dùng khi đang chỉnh luật)
//     --trace "đoạn"    in vết gõ từng phím của câu chứa đoạn đó (cấu hình --config)
//     --check           so với golden, exit 1 nếu tụt
//     --write-golden    ghi TelexCore/Corpus/mixed-typing-golden.json
// Chi tiết: docs/REGRESSION.md mục "Mô phỏng gõ câu trộn".

import Foundation
import MixedTyping

let args = Array(CommandLine.arguments.dropFirst())
@MainActor func opt(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}
@MainActor func flag(_ name: String) -> Bool { args.contains(name) }

let configs = opt("--config").map { n in SimConfig.all.filter { $0.name == n } } ?? SimConfig.all
guard !configs.isEmpty else { print("không có cấu hình \(opt("--config") ?? "")"); exit(2) }
let diffConfig = opt("--diff-config") ?? "default"
let lineLimit = Int(opt("--lines") ?? "60") ?? 60
let topN = Int(opt("--top") ?? "25") ?? 25
let unlock = flag("--unlock-test")
let diffSplits: Set<String> = unlock ? ["val", "test"] : ["val"]

#if DEBUG
let buildKind = "debug (số latency không có nghĩa — dùng -c release)"
#else
let buildKind = "release"
#endif

let corpus: [MixedSentence]
do { corpus = try MixedCorpus.load() } catch { print("không đọc được corpus: \(error)"); exit(2) }

// --trace "đoạn câu": in vết gõ từng phím của các câu chứa đoạn đó (cấu hình --config, mặc định default).
if let needle = opt("--trace") {
    let cfg = configs.count == 1 ? configs[0] : SimConfig.appDefault
    for s in corpus where s.text.contains(needle) {
        if s.split == "test" && !unlock { print("[test] \(s.text) — tập test khoá, thêm --unlock-test"); continue }
        print("[\(s.split)/\(s.category)] \(s.text)  (cấu hình \(cfg.name))")
        for l in Runner.trace(s, cfg) { print(l) }
        print("")
    }
    exit(0)
}

var perCat: [String: (Int, Int)] = [:]
for s in corpus { perCat[s.category, default: (0, 0)].0 += s.split == "val" ? 1 : 0; perCat[s.category, default: (0, 0)].1 += s.split == "test" ? 1 : 0 }
print("Corpus: \(corpus.count) câu, \(corpus.reduce(0) { $0 + $1.words.count }) từ — " +
      categoryOrder.compactMap { c in perCat[c].map { "\(c) \($0.0)+\($0.1)" } }.joined(separator: ", ") + " (val+test)")
print("Build: \(buildKind)\n")

func f(_ v: Double?) -> String { v.map { String(format: "%6.2f", $0) } ?? "     –" }

let t0 = Date()
var results: [ConfigResult] = []
for cfg in configs {
    let r = Evaluation.run(corpus, cfg, timing: true)
    results.append(r)
    print("== \(cfg.name): \(cfg.summary)")
    for split in ["val", "test"] {
        let m = r.metrics(split: split)
        print("  [\(split)]   nhóm     lazy%  lazyVI%  lazyEN%  toggle/100  ideal%   (câu/từ)")
        for c in categoryOrder + ["overall"] {
            guard let x = m[c] else { continue }
            let n = r.counts[split]?[c]
            let size = n.map { "(\($0.sentences)/\($0.words))" } ?? "(trung bình nhóm)"
            print("           \(c.padding(toLength: 8, withPad: " ", startingAt: 0)) \(f(x["lazy_wrong"]))  \(f(x["lazy_vi_wrong"]))   \(f(x["lazy_en_wrong"]))     \(f(x["toggles_per_100"]))   \(f(x["ideal_wrong"]))   \(size)")
        }
    }
    func latLine(_ label: String, _ xs: [UInt64]) -> String {
        let lat = xs.sorted()
        guard !lat.isEmpty else { return "" }
        let mean = Double(lat.reduce(0, +)) / Double(lat.count)
        let p999 = lat[min(lat.count - 1, Int(Double(lat.count) * 0.999))]
        return label + String(format: " (%d): mean %.0f ns, p99.9 %llu ns, max %llu ns", lat.count, mean, p999, lat.last!)
    }
    print("  latency " + latLine("tất cả", r.latencyKeyNs + r.latencyBoundaryNs))
    print("          " + latLine("phím chữ (feed/⌫)", r.latencyKeyNs))
    print("          " + latLine("ranh giới (chốt + sửa ngược)", r.latencyBoundaryNs))
    print("")
}

if let r = results.first(where: { $0.config.name == diffConfig }) ?? results.first {
    let lines = r.wrongLines.filter { diffSplits.contains($0.sentence.split) }
    // Mẫu lỗi: cặp (đích → ra), chữ thường.
    var pat: [String: (n: Int, en: Bool)] = [:]
    for l in lines { for w in l.wrong { pat["\(w.target.lowercased()) → \(w.output.lowercased())", default: (0, w.english)].n += 1 } }
    print("== Mẫu lỗi hay gặp (\(r.config.name), \(diffSplits.sorted().joined(separator: "+")), người gõ lười): \(pat.count) mẫu")
    for (k, v) in pat.sorted(by: { $0.value.n != $1.value.n ? $0.value.n > $1.value.n : $0.key < $1.key }).prefix(topN) {
        print(String(format: "  %4d  ", v.n) + (v.en ? "EN" : "VI") + "  " + k)
    }
    if lineLimit != 0 {
        print("\n== Diff từng dòng (\(r.config.name), \(diffSplits.sorted().joined(separator: "+"))): \(lines.count) dòng có từ sai")
        for l in lines.prefix(lineLimit < 0 ? Int.max : lineLimit) {
            print("  [\(l.sentence.split)/\(l.sentence.category)] \(l.sentence.text)")
            print("      → \(l.output)")
            print("      ✗ " + l.wrong.map { "\($0.target)→\($0.output)\($0.english ? "(en)" : "")" }.joined(separator: ", "))
        }
    }
    print("")
}

print(String(format: "Thời gian: %.1f s", Date().timeIntervalSince(t0)))

if flag("--write-golden") {
    guard configs.count == SimConfig.all.count else { print("--write-golden cần chạy cả ba cấu hình"); exit(2) }
    let data = Evaluation.goldenJSON(results, tolerance: 0.05)
    do { try data.write(to: MixedCorpus.goldenURL); print("Đã ghi \(MixedCorpus.goldenURL.path)") }
    catch { print("ghi golden lỗi: \(error)"); exit(2) }
}

if flag("--check") {
    do {
        let cmp = try Evaluation.compare(results, golden: Data(contentsOf: MixedCorpus.goldenURL))
        for s in cmp.improvements { print("  cải thiện: \(s)") }
        for s in cmp.regressions { print("  TỤT: \(s)") }
        if !cmp.regressions.isEmpty { print("REGRESSION so với golden"); exit(1) }
        print(cmp.improvements.isEmpty ? "Khớp golden." : "Không tụt; có cải thiện — cập nhật golden bằng --write-golden.")
    } catch { print("đọc golden lỗi: \(error)"); exit(2) }
}
