// EnglishNextWordTests.swift — #146: sau một từ tiếng Anh ("they" + dấu cách) thanh gợi ý hiện
// "the / of / and" — đó là top unigram tiếng Anh (SwipeEnglish.top) dùng để ĐỆM ô trống
// (padWords), không phải ngữ cảnh. Từ trước tiếng Anh ⇒ không đệm từ phổ biến; chỉ giữ bằng
// chứng thật (cặp cá nhân / seed). Âm tiết Việt và đầu ô giữ nguyên. Song sinh android
// EnglishNextWordTests.kt.
import XCTest

final class EnglishNextWordTests: XCTestCase {

    private let generic: Set<String> = ["the", "of", "and"]

    /// Mô phỏng nhánh "từ kế tiếp" của KeyboardViewController.padWords (sau `prev`).
    private func fill(_ base: [String], prev: String?, english: Bool, need: Int = 3) -> [String] {
        guard base.count < need else { return Array(base.prefix(need)) }
        guard SuggestRank.padsWithTopWords(prev, english: english, isEnglish: { SwipeEnglish.contains($0) })
        else { return base }
        return SuggestionFill.pad(base, with: SwipeEnglish.top, need: need)
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

    func testTheyHasNoGenericFill() {
        // Trước fix: SwipeEnglish.top đệm ⇒ the/of/and.
        XCTAssertTrue(SwipeEnglish.top.prefix(3).contains { generic.contains($0) })
        let enMode = fill([], prev: "they", english: true)
        XCTAssertTrue(enMode.isEmpty, "\(enMode)")
        let viMode = fill([], prev: "they", english: false)
        XCTAssertTrue(viMode.allSatisfy { !generic.contains($0) }, "\(viMode)")
        XCTAssertTrue(viMode.isEmpty)
        // cặp cá nhân vẫn giữ
        XCTAssertEqual(fill(["are"], prev: "they", english: true), ["are"])
        // đầu ô chế độ Tiếng Anh: vẫn đệm đủ như cũ
        XCTAssertEqual(fill([], prev: nil, english: true).count, 3)
    }

    func testVietnameseSyllableStillGetsBigram() {
        XCTAssertFalse(SuggestRank.bigramNext("xin", limit: 6).isEmpty)
        let next = SuggestRank.nextFill("xin", prev2: nil, personal: [], triCount: { _ in 0 })
        XCTAssertEqual(next.count, 3)
        XCTAssertTrue(SuggestRank.padsWithTopWords("xin", english: false, isEnglish: { SwipeEnglish.contains($0) }))
    }
}
