// EnglishNextWordTests.swift — #146: sau một từ tiếng Anh ("they" + dấu cách) thanh gợi ý hiện
// "the / of / and" — đó là top unigram tiếng Anh (SwipeEnglish.top) dùng để ĐỆM ô trống
// (padWords), không phải ngữ cảnh. Từ trước tiếng Anh ⇒ không đệm từ phổ biến; cặp cá nhân
// trước, rồi bảng từ kế tiếp tiếng Anh `EnglishNext` (Tatoeba, Scripts/english-next.tsv). Âm tiết
// Việt và đầu ô giữ nguyên. Song sinh android EnglishNextWordTests.kt. Kỳ vọng lấy từ BẢNG (không
// chép cứng — bảng sinh lại được).
import XCTest

final class EnglishNextWordTests: XCTestCase {

    private let generic: Set<String> = ["the", "of", "and"]

    /// Mô phỏng nhánh "từ kế tiếp" của KeyboardViewController.padWords (sau `prev`).
    private func fill(_ base: [String], prev: String?, english: Bool, need: Int = 3) -> [String] {
        guard base.count < need else { return Array(base.prefix(need)) }
        if let prev, !SuggestRank.padsWithTopWords(prev, english: english, isEnglish: { SwipeEnglish.contains($0) }) {
            return SuggestRank.englishNextFill(base, table: EnglishNext.next(after: prev), need: need,
                                               filter: { SensitiveWords.filter($0, after: prev, prev2: nil, enabled: true) })
        }
        return SuggestionFill.pad(base, with: SwipeEnglish.top, need: need)
    }

    /// Từ kế tiếp mong đợi sau `prev` khi không có cặp cá nhân: đúng bảng, tối đa 3.
    private func tableNext(_ prev: String) -> [String] { Array(EnglishNext.next(after: prev).prefix(3)) }

    func testTableShape() {
        let h = EnglishNext.heads
        XCTAssertEqual(h.count, EnglishNext.followers.count)
        XCTAssertTrue((300...500).contains(h.count))
        for i in 1..<h.count { XCTAssertLessThan(h[i - 1], h[i]) }
        for f in EnglishNext.followers { XCTAssertTrue((1...3).contains(f.split(separator: " ").count), f) }
        XCTAssertFalse(EnglishNext.next(after: "they").isEmpty)
        XCTAssertEqual(EnglishNext.next(after: "they"), EnglishNext.next(after: "They"))
        XCTAssertTrue(EnglishNext.next(after: "kubernetes").isEmpty)
        XCTAssertTrue(EnglishNext.next(after: "").isEmpty)
        XCTAssertFalse(EnglishNext.followers.contains { $0.split(separator: " ").contains("i") }, "\"I\" viết hoa")
    }

    func testEnglishNextFillPure() {
        let table = ["are", "were", "have"]
        XCTAssertEqual(SuggestRank.englishNextFill([], table: table, need: 3), ["are", "were", "have"])
        XCTAssertEqual(SuggestRank.englishNextFill(["were"], table: table, need: 3), ["were", "are", "have"],
                       "cá nhân trước, bỏ trùng")
        XCTAssertEqual(SuggestRank.englishNextFill(["x"], table: [], need: 3), ["x"], "bảng rỗng ⇒ không đệm")
        XCTAssertEqual(SuggestRank.englishNextFill([], table: table, need: 3, filter: { $0.filter { $0 != "were" } }),
                       ["are", "have"], "lọc nhạy cảm")
        XCTAssertEqual(SuggestRank.englishNextFill(["a", "b", "c", "d"], table: table, need: 3), ["a", "b", "c"])
    }

    func testGatePure() {
        let en: (String) -> Bool = { ["they", "can", "hello"].contains($0) }
        let vi: (String) -> Bool = { ["can", "tôi"].contains($0) }
        XCTAssertTrue(SuggestRank.padsWithTopWords(nil, english: true, isEnglish: en, isVietSyllable: vi), "đầu ô")
        XCTAssertTrue(SuggestRank.padsWithTopWords(nil, english: false, isEnglish: en, isVietSyllable: vi))
        XCTAssertFalse(SuggestRank.padsWithTopWords("they", english: true, isEnglish: en, isVietSyllable: vi))
        XCTAssertFalse(SuggestRank.padsWithTopWords("They", english: false, isEnglish: en, isVietSyllable: vi),
                       "từ Anh giữa câu Việt")
        XCTAssertTrue(SuggestRank.padsWithTopWords("tôi", english: false, isEnglish: en, isVietSyllable: vi))
        XCTAssertTrue(SuggestRank.padsWithTopWords("can", english: false, isEnglish: en, isVietSyllable: vi),
                      "trùng Anh–Việt ⇒ coi là Việt")
        XCTAssertTrue(SuggestRank.padsWithTopWords("xyzq", english: false, isEnglish: en, isVietSyllable: vi))
    }

    func testGateRealLexicons() {
        let en: (String) -> Bool = { SwipeEnglish.contains($0) }
        XCTAssertFalse(SuggestRank.padsWithTopWords("they", english: false, isEnglish: en))
        XCTAssertTrue(SuggestRank.padsWithTopWords("tôi", english: false, isEnglish: en))
        XCTAssertTrue(SuggestRank.padsWithTopWords("the", english: false, isEnglish: en), "\"the\" cũng là âm tiết Việt")
    }

    func testTheyUsesTable() {
        // Trước #146: SwipeEnglish.top đệm ⇒ the/of/and.
        XCTAssertTrue(SwipeEnglish.top.prefix(3).contains { generic.contains($0) })
        let expected = tableNext("they")
        XCTAssertFalse(expected.isEmpty)
        let enMode = fill([], prev: "they", english: true)
        XCTAssertEqual(enMode, expected, "chế độ Tiếng Anh: đúng bảng")
        XCTAssertFalse(enMode.contains { generic.contains($0) && !expected.contains($0) })
        let viMode = fill([], prev: "they", english: false)
        XCTAssertEqual(viMode, expected, "từ Anh giữa câu Việt: đúng bảng")
        // cặp cá nhân vẫn đứng đầu
        let mine = ["love", "like", "want", "go"].first { !expected.contains($0) }!
        XCTAssertEqual(fill([mine], prev: "they", english: true), [mine] + expected.prefix(2))
        // từ Anh không có trong bảng ⇒ không đệm gì
        XCTAssertTrue(fill([], prev: "kubernetes", english: true).isEmpty)
        // đầu ô chế độ Tiếng Anh: vẫn đệm đủ như cũ
        XCTAssertEqual(fill([], prev: nil, english: true).count, 3)
    }

    func testVietnameseSyllableStillGetsBigram() {
        XCTAssertFalse(SuggestRank.bigramNext("xin", limit: 6).isEmpty)
        let next = SuggestRank.nextFill("xin", prev2: nil, personal: [], triCount: { _ in 0 })
        XCTAssertEqual(next.count, 3)
        XCTAssertTrue(SuggestRank.padsWithTopWords("xin", english: false, isEnglish: { SwipeEnglish.contains($0) }))
    }

    func testSlangInEnglishLexicon() {
        for w in ["flex", "cringe", "slay", "rizz", "simp", "skincare", "freeship", "livestream", "chill", "vibe"] {
            XCTAssertTrue(SwipeEnglish.contains(w), w)
        }
    }

    func testCheckMidVietnameseUsesTable() {
        XCTAssertEqual(fill([], prev: "check", english: false), tableNext("check"))
    }

    func testMixedCuratedPairsAreSwipeOnly() {
        XCTAssertTrue(CuratedPairs.next(after: "out", prev2: nil).contains("trình"))
        XCTAssertTrue(CuratedPairs.swipe(nil, "đu", "trend"))
        XCTAssertFalse(CuratedPairs.has(nil, "out", "trình"), "không cho Thêm dấu")
    }

    /// Mô phỏng nhánh "vừa space sau một từ" (chế độ Tiếng Việt) của KeyboardViewController với
    /// người dùng MỚI (UserLangModel chỉ có seed).
    private func stripAfter(_ prev: String, prev2: String? = nil, _ m: UserLangModel) -> [String] {
        let personal = SensitiveWords.filter(m.nextWords(after: prev, prev2: prev2, limit: 6),
                                             after: prev, prev2: prev2, enabled: true)
        let chain = SensitiveWords.filter(SensitiveWords.chain(after: prev, prev2: prev2),
                                          after: prev, prev2: prev2, enabled: true)
        let next = SuggestRank.nextFill(prev, prev2: prev2, personal: personal,
                                        triCount: { w in prev2.map { m.trigramCount($0, prev, w) } ?? 0 },
                                        filter: { SensitiveWords.filter($0, after: prev, prev2: prev2, enabled: true) },
                                        need: 3, chain: chain)
        return fill(next, prev: prev, english: false)
    }

    /// 04/11/2026 (#146): cặp trộn Việt–Anh trên thanh TỪ KẾ TIẾP sau dấu cách — đến từ SeedData
    /// (Scripts/seed-curated.txt), nên chỉ có ở người dùng mới / sau "Xoá từ đã học".
    func testMixedPairsOnNextWordStripAfterSeed() {
        let m = UserLangModel(appGroup: nil)
        m.isKnownWord = { VNSuggest.contains($0) }
        m.seedIfEmpty(unigrams: SeedData.unigrams, bigrams: SeedData.bigrams)
        for (prev, want) in [("đu", "trend"), ("out", "trình"), ("check", "var"), ("real", "hay")] {
            let next = stripAfter(prev, m)
            XCTAssertTrue(next.contains(want), "\(prev) → \(next)")
        }
        XCTAssertEqual(stripAfter("real", m).first, "hay")
        XCTAssertEqual(stripAfter("hay", prev2: "real", m).first, "fake", "chuỗi seed ba từ real hay fake")
        XCTAssertFalse(stripAfter("hay", m).contains("fake"), "\"hay\" một mình không gợi fake")
    }
}
