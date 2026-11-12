// SwipeVocabTests.swift — từ vựng gõ vuốt theo công tắc "Lọc từ nhạy cảm" (SwipeVocab). Song sinh
// android SwipeVocabTests.kt; fixture chung Fixtures/swipe-vocab.tsv (Kotlin sinh, ở đây khớp
// từng dòng): E filter folded words (expand 40, %.4f) | P filter case words expected (câu đường
// sạch qua SwipeTyping.finish + EngineBridge, như SwipeReviseParityTests.phrase).
import XCTest

final class SwipeVocabTests: XCTestCase {
    override func tearDown() { SwipeVocab.filterSensitive = true }

    private func sensitive(_ text: String) -> Bool {
        text.split(separator: " ").contains { SensitiveWords.set.contains($0.lowercased()) }
    }

    func testTableAgreesWithFilterList() {
        for e in SwipeVocab.chat + SwipeVocab.always { XCTAssertFalse(SensitiveWords.set.contains(e.word), e.word) }
        XCTAssertEqual(Set(SwipeVocab.sensitiveEntries(SeedData.unigrams).map(\.word)), SensitiveWords.set)
        XCTAssertFalse(SwipeVocab.build(filter: true).words.values.joined().contains { SensitiveWords.set.contains($0.word) })
        // sàn chỉ cho từ vnlexicon không có; từ có sẵn (đĩ, cứt…) giữ tần suất vnlexicon
        var off: [String: Int] = [:]
        for w in SwipeVocab.build(filter: false).words.values.joined() { off[w.word] = Int(w.score) }
        XCTAssertEqual(Set(SensitiveWords.set.filter { off[$0] == nil }), Set(["đĩ", "cứt", "dâm", "điếm", "lìn"]))
        XCTAssertTrue(off.filter { SensitiveWords.set.contains($0.key) }.values.allSatisfy { $0 >= SwipeVocab.sensitiveFloor })
    }

    /// Lọc bật: KHÔNG dạng nào (lexicon + thêm) bung ra từ nhạy cảm — kể cả đĩ, cứt, dâm, điếm có sẵn.
    func testFilteredExpansionNeverSensitive() {
        SwipeVocab.filterSensitive = true
        let v = SwipeVocab.current
        for f in v.forms.folded {
            XCTAssertFalse(SwipeDecoder.expand(f, limit: 64).contains { SensitiveWords.set.contains($0.word) }, f)
        }
        SwipeVocab.filterSensitive = false
        XCTAssertEqual(SwipeDecoder.expand("dit", limit: 1).first?.word, "địt")
        XCTAssertTrue(SwipeDecoder.expand("cut", limit: 8).contains { $0.word == "cứt" })
        XCTAssertEqual(SwipeDecoder.expand("dcm", limit: 8).map(\.word), ["đcm", "dcm"])
    }

    /// Từ một chữ vuốt theo phím Telex (11/2026, Phil: "ở, ạ… rất khó vuốt; ow là ở, aj là ạ, ừ thì uw là đủ").
    /// Song sinh Android singleLetterWordsSwipeByTelexKeys; đường + điểm khớp qua fixture swipe-vocab.tsv.
    func testSingleLetterWordsSwipeByTelexKeys() {
        func top(_ f: String) -> String? { SwipeDecoder.expand(f, limit: 1).first?.word }
        XCTAssertEqual(top("ow"), "ở")
        XCTAssertEqual(top("uw"), "ừ")
        XCTAssertEqual(top("aj"), "ạ")
        XCTAssertEqual(top("af"), "à")
        XCTAssertEqual(top("ys"), "ý")
        XCTAssertEqual(top("owr"), "ở")
        XCTAssertEqual(top("uhm"), "uhm")
        XCTAssertEqual(SwipeDecoder.expand("ow", limit: 8).map(\.word), ["ở", "ờ", "ơ", "ợ", "ớ"])
        XCTAssertEqual(SwipeVocab.telexPaths("ở").full, "owr")
        XCTAssertEqual(SwipeVocab.telexPaths("ở").family, "ow")
        XCTAssertEqual(SwipeVocab.telexPaths("ồ").full, "of")
        XCTAssertNil(SwipeVocab.telexPaths("a").full)
        XCTAssertFalse(SwipeVocab.telexEntries.contains { SwipeVocab.telexSkip.contains($0.path ?? "") })
        // đường trùng từ tiếng Anh thông dụng hơn thì bỏ: "as", "is", "of"… vẫn là tiếng Anh
        for p in SwipeVocab.telexSkip { XCTAssertNil(SwipeVocab.current.index(of: p), p) }
    }

    /// Tên riêng viết kiểu Anh + chuỗi địa danh thêm 11/2026 (Phil: Saigon, Singapore, Paris, Google).
    func testProperNounTableAdditions() {
        XCTAssertEqual(DisplayCase.apply("saigon"), "Saigon")
        XCTAssertEqual(DisplayCase.apply("hanoi"), "Hanoi")
        XCTAssertEqual(DisplayCase.apply("vietnam"), "Vietnam")
        XCTAssertEqual(DisplayCase.apply("huế"), "Huế")
        XCTAssertEqual(DisplayCase.apply("whatsapp"), "WhatsApp")
        XCTAssertEqual(DisplayCase.apply("quốc", after: "hàn"), "Quốc")
        XCTAssertEqual(DisplayCase.apply("quốc", after: "trung"), "Quốc")
        XCTAssertEqual(DisplayCase.apply("quốc", after: "tổ"), "quốc")
        XCTAssertEqual(DisplayCase.apply("bình", after: "hòa"), "bình")
        XCTAssertTrue(CuratedPairs.next(after: "đà", prev2: nil).contains("nẵng"))
    }

    func testChatAbbreviationsAlwaysThere() {
        for filter in [true, false] {
            SwipeVocab.filterSensitive = filter
            XCTAssertEqual(SwipeDecoder.expand("ko", limit: 1).first?.word, "ko")
            XCTAssertEqual(SwipeDecoder.expand("dc", limit: 1).first?.word, "đc")
            XCTAssertGreaterThanOrEqual(SwipeVocab.current.index(of: "nma") ?? -1, SwipeLexicon.forms.count)
        }
    }

    /// Đổi công tắc giữa hai cú vuốt: decoder dựng lại template theo từ vựng mới.
    func testDecoderFollowsSwitch() {
        let par = SwipeReviseParityTests()
        SwipeVocab.filterSensitive = false
        XCTAssertEqual(par.phrase(["dkm"], first: .capitalized), "Đkm")
        SwipeVocab.filterSensitive = true
        XCTAssertFalse(sensitive(par.phrase(["dkm"], first: .capitalized)))
    }

    func testFixtureMatchesAndroid() throws {
        let url = try XCTUnwrap(Bundle(for: SwipeVocabTests.self).url(forResource: "swipe-vocab", withExtension: "tsv"))
        let par = SwipeReviseParityTests()
        var n = (e: 0, p: 0)
        var mismatches: [String] = []
        for line in try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
        where !line.hasPrefix("#") && !line.isEmpty {
            let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            SwipeVocab.filterSensitive = f[1] == "1"
            let got: String
            let want: String
            if f[0] == "E" {
                got = SwipeDecoder.expand(f[2], limit: 40).map { "\($0.word):" + String(format: "%.4f", $0.score) }
                    .joined(separator: ",")
                want = f.count > 3 ? f[3] : ""; n.e += 1
            } else {
                got = par.phrase(f[3].split(separator: " ").map(String.init), first: f[2] == "F" ? .capitalized : .lower)
                want = f[4]; n.p += 1
                if f[1] == "1" { XCTAssertFalse(sensitive(got), "lọc bật ra từ nhạy cảm: \(line) ⇒ \(got)") }
                print("VOCAB iOS lọc \(f[1] == "1" ? "bật" : "tắt") '\(f[3])' → '\(got)'")
            }
            if got != want { mismatches.append("\(line)  ⇒ iOS: \(got)") }
        }
        print("VOCAB-PARITY iOS: E \(n.e) P \(n.p), lệch \(mismatches.count)")
        XCTAssertTrue(mismatches.isEmpty, mismatches.prefix(10).joined(separator: "\n"))
        XCTAssertGreaterThan(n.p, 60)
        // tắt lọc không đổi từ thường cùng hình trong câu thường
        for g in ["người lớn", "lớn lên", "rất lớn", "lớn nhất", "các bạn", "buổi sáng", "đi đâu", "đủ rồi"] {
            let words = g.split(separator: " ").map(String.init)
            SwipeVocab.filterSensitive = true
            let on = par.phrase(words, first: .capitalized)
            SwipeVocab.filterSensitive = false
            XCTAssertEqual(par.phrase(words, first: .capitalized), on, g)
        }
    }
}
