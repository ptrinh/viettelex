import XCTest
import TelexCore
@testable import MixedTyping

// Mô phỏng gõ câu trộn Việt–Anh (docs/REGRESSION.md "Mô phỏng gõ câu trộn"): chạy cả corpus
// TelexCore/Corpus/mixed-typing.tsv qua engine thật cho 3 cấu hình, so với golden
// TelexCore/Corpus/mixed-typing-golden.json. Fail khi BẤT KỲ số đo nào (nhóm × split × cấu
// hình) tệ hơn golden quá tolerance_pp. Cải thiện thì chỉ in ra — cập nhật golden bằng
//   cd TelexCore && swift run -c release mixed-eval --write-golden
// và ghi số mới vào docs/REGRESSION.md.
final class MixedTypingGoldenTests: XCTestCase {

    func testMetricsDoNotRegressAgainstGolden() throws {
        let corpus = try MixedCorpus.load()
        XCTAssertGreaterThan(corpus.count, 2000)
        let results = SimConfig.all.map { Evaluation.run(corpus, $0) }
        for r in results {
            let o = r.metrics(split: "val")["overall"] ?? [:]
            print("MIXED \(r.config.name) val overall: " + String(format: "lazy %.2f%% · toggles/100 %.2f · ideal %.2f%%",
                         o["lazy_wrong"] ?? -1, o["toggles_per_100"] ?? -1, o["ideal_wrong"] ?? -1))
        }
        let cmp = try Evaluation.compare(results, golden: Data(contentsOf: MixedCorpus.goldenURL))
        for s in cmp.improvements { print("MIXED cải thiện (cập nhật golden): \(s)") }
        XCTAssertTrue(cmp.missing.isEmpty, "golden thiếu/thừa số đo: \(cmp.missing)")
        XCTAssertTrue(cmp.regressions.isEmpty, "mô phỏng gõ câu trộn TỤT:\n" + cmp.regressions.joined(separator: "\n"))
    }

    // MARK: Người gõ mô phỏng — chính nó phải đúng thì số đo mới có nghĩa.

    private func keys(_ w: String, seed: UInt64 = 1, end: Bool = true) -> String {
        var o = TypistOptions()
        if end { o.toneEnd = 1; o.uowShort = 0; o.loneW = 0 }
        var rng = SplitMix64(seed: seed)
        return String(Typist.telexKeys(w, &rng, o) ?? [])
    }

    func testTelexKeysCanonical() {
        XCTAssertEqual(keys("việt"), "vieetj")
        XCTAssertEqual(keys("được"), "dduwowcj")
        XCTAssertEqual(keys("Đà"), "Ddaf")
        XCTAssertEqual(keys("ĐÀ"), "DDAF")
        XCTAssertEqual(keys("Ấy"), "Aays")
        XCTAssertEqual(keys("quyển"), "quyeenr")
        XCTAssertEqual(keys("giữa"), "giuwax")
        XCTAssertEqual(keys("ăn"), "awn")
    }

    /// Mọi biến thể vị trí phím thanh / ươ / w đơn mà người gõ sinh ra phải gõ ra đúng từ đích
    /// với engine mặc định — nếu không, lỗi do người gõ chứ không phải do engine.
    func testEveryTypistVariantTypesTheWordAlone() {
        let words = ["người", "được", "tiếng", "Việt", "hoà", "thuỷ", "trường", "nhưng", "ở", "ừ",
                     "giữa", "quyển", "khuya", "Đà", "tư", "mưa", "hướng", "chuyện", "cứu", "ĐƯỢC"]
        for w in words {
            for seed in 1...40 as ClosedRange<UInt64> {
                var rng = SplitMix64(seed: seed)
                let k = Typist.telexKeys(w, &rng, TypistOptions())!
                var e = SimConfig.appDefault.engine(category: "vi")
                for c in k { _ = e.feed(c) }
                let out = e.commitText(autoRestore: true)
                XCTAssertEqual(MixedCorpus.canon(out), MixedCorpus.canon(w), "\(w) gõ \(String(k)) → \(out)")
            }
        }
    }

    func testCanonIgnoresTonePlacementOnly() {
        XCTAssertEqual(MixedCorpus.canon("hoà"), MixedCorpus.canon("hòa"))
        XCTAssertEqual(MixedCorpus.canon("thuý"), MixedCorpus.canon("thúy"))
        XCTAssertNotEqual(MixedCorpus.canon("hí"), MixedCorpus.canon("his"))
        XCTAssertNotEqual(MixedCorpus.canon("Anh"), MixedCorpus.canon("anh"))
        XCTAssertNotEqual(MixedCorpus.canon("hò"), MixedCorpus.canon("hó"))
    }

    /// Bộ so golden phải bắt được tụt (và chỉ tụt): hạ golden một số đo ⇒ regression.
    func testCompareFlagsRegression() throws {
        let corpus = Array(try MixedCorpus.load().prefix(200))
        let r = Evaluation.run(corpus, .appDefault)
        var root = try JSONSerialization.jsonObject(with: Evaluation.goldenJSON([r], tolerance: 0.05)) as! [String: Any]
        XCTAssertTrue(try Evaluation.compare([r], golden: JSONSerialization.data(withJSONObject: root)).regressions.isEmpty)
        var cfgs = root["configs"] as! [String: Any]
        var splits = cfgs["default"] as! [String: Any]
        var cats = splits["val"] as! [String: Any]
        var overall = cats["overall"] as! [String: Any]
        let v = (overall["lazy_wrong"] as! NSNumber).doubleValue
        overall["lazy_wrong"] = v - 0.5
        cats["overall"] = overall; splits["val"] = cats; cfgs["default"] = splits; root["configs"] = cfgs
        let cmp = try Evaluation.compare([r], golden: JSONSerialization.data(withJSONObject: root))
        XCTAssertEqual(cmp.regressions.count, 1)
        XCTAssertTrue(cmp.regressions.first?.hasPrefix("default/val/overall/lazy_wrong") ?? false)
    }

    func testDeterministic() throws {
        let corpus = Array(try MixedCorpus.load().prefix(300))
        let a = Evaluation.run(corpus, .retro), b = Evaluation.run(corpus, .retro)
        XCTAssertEqual(a.metrics(split: "val")["overall"], b.metrics(split: "val")["overall"])
    }
}
