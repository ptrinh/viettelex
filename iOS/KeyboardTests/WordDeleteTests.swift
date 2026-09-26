import XCTest
import UIKit

/// Vuốt trái trên ⌫ = xoá theo từ (kiểu Gboard) + giữ ⌫ >3s: ranh giới từ, ngưỡng
/// kéo → số từ, kế hoạch xoá khi nhấc tay (không xoá dư sau lần xoá lúc chạm xuống),
/// khôi phục chèn đúng chuỗi.
final class WordDeleteTests: XCTestCase {

    private func del(_ ctx: String, _ n: Int) -> Int { WordDelete.charsToDelete(context: ctx, words: n) }

    // MARK: ranh giới từ

    func testVietnameseWords() {
        XCTAssertEqual(del("xin chào", 1), 4)
        XCTAssertEqual(del("xin chào", 2), 8)
        XCTAssertEqual(del("Người Việt Nam", 2), 8)      // " Việt" + "Nam"
    }

    func testDecomposedDiacriticsCountAsOneCharacter() {
        let nfd = "tie\u{0302}\u{0301}ng Vie\u{0302}\u{0323}t"   // "tiếng Việt" dạng NFD
        XCTAssertEqual(del(nfd, 1), 4)
        XCTAssertEqual(del(nfd, 2), 10)
    }

    func testTrailingWhitespaceGoesWithWord() {
        XCTAssertEqual(del("xin chào  ", 1), 6)
        XCTAssertEqual(del("xin   chào", 2), 10)
        XCTAssertEqual(del("   ", 1), 3)                  // chỉ còn khoảng trắng → xoá hết
    }

    func testPunctuationGoesWithWord() {
        XCTAssertEqual(del("Xin chào, bạn!", 1), 4)       // "bạn!"
        XCTAssertEqual(del("Xin chào, bạn!", 2), 10)      // + "chào, "
        XCTAssertEqual(del("ok...", 1), 5)
        XCTAssertEqual(del("?!", 1), 2)
        XCTAssertEqual(del("don't stop", 2), 10)          // dấu nháy trong từ
        XCTAssertEqual(del("e-mail", 1), 6)
    }

    func testEmoji() {
        XCTAssertEqual(del("vui quá 😂😂", 1), 2)
        XCTAssertEqual(del("vui quá 😂😂", 2), 6)
        XCTAssertEqual(del("hay😂", 1), 1)
        XCTAssertEqual(del("hay😂", 2), 4)
        XCTAssertEqual(del("nhà 👨‍👩‍👧", 1), 1)             // ZWJ = 1 grapheme
        XCTAssertEqual(del("năm 2026", 1), 4)             // chữ số không phải emoji
    }

    func testStartOfFieldAndNewline() {
        XCTAssertEqual(del("", 1), 0)
        XCTAssertEqual(del("chào", 5), 4)                 // không vượt context
        XCTAssertEqual(del("dòng một\nhai", 1), 3)
        XCTAssertEqual(del("dòng một\nhai", 2), 7)
        XCTAssertEqual(del("xin chào", 0), 0)
    }

    func testComposingWordIsFirstWord() {
        XCTAssertEqual(WordDelete.charsToDelete(context: "xin chà", composed: "chà", words: 1), 3)
        XCTAssertEqual(WordDelete.charsToDelete(context: "xin chà", composed: "chà", words: 2), 7)
        XCTAssertEqual(WordDelete.charsToDelete(context: "a.b", composed: "a.b", words: 1), 3)
        XCTAssertEqual(WordDelete.charsToDelete(context: "a.b", composed: "", words: 1), 1)
    }

    func testAvailableWords() {
        XCTAssertEqual(WordDelete.availableWords(context: "xin chào bạn"), 3)
        XCTAssertEqual(WordDelete.availableWords(context: "xin chào bạn", limit: 2), 2)
        XCTAssertEqual(WordDelete.availableWords(context: ""), 0)
    }

    // MARK: ngưỡng kéo → số từ

    func testDragToWords() {
        let step: CGFloat = 32
        XCTAssertEqual(WordDelete.words(dragLeft: -40, step: step, max: 9), 0)
        XCTAssertEqual(WordDelete.words(dragLeft: 0, step: step, max: 9), 0)
        XCTAssertEqual(WordDelete.words(dragLeft: 15.9, step: step, max: 9), 0)
        XCTAssertEqual(WordDelete.words(dragLeft: 16, step: step, max: 9), 1)
        XCTAssertEqual(WordDelete.words(dragLeft: 47.9, step: step, max: 9), 1)
        XCTAssertEqual(WordDelete.words(dragLeft: 48, step: step, max: 9), 2)
        XCTAssertEqual(WordDelete.words(dragLeft: 16 + 4 * step, step: step, max: 9), 5)
        XCTAssertEqual(WordDelete.words(dragLeft: 400, step: step, max: 3), 3)
        XCTAssertEqual(WordDelete.words(dragLeft: 400, step: step, max: 0), 0)
    }

    func testSwipeStepClamp() {
        XCTAssertEqual(WordDelete.swipeStep(letterKeyWidth: nil), 32)
        XCTAssertEqual(WordDelete.swipeStep(letterKeyWidth: 10), 24)
        XCTAssertEqual(WordDelete.swipeStep(letterKeyWidth: 33), 33)
        XCTAssertEqual(WordDelete.swipeStep(letterKeyWidth: 90), 56)
    }

    // MARK: kế hoạch khi nhấc tay

    /// Áp kế hoạch lên context hiện tại (mô phỏng deleteBackward/insertText).
    private func apply(_ p: WordDelete.Plan, to current: String) -> String {
        String(current.dropLast(p.deleteNow)) + p.reinsert
    }

    func testPlanAccountsForTouchDownDelete() throws {
        // chạm ⌫ đã xoá "o" → vuốt 1 từ chỉ xoá thêm "chà"
        let p = try XCTUnwrap(WordDelete.plan(snapshot: "xin chào", composed: "",
                                              current: "xin chà", words: 1))
        XCTAssertEqual(p, .init(deleteNow: 3, reinsert: "", removed: "chào", remaining: "xin "))
        XCTAssertEqual(apply(p, to: "xin chà"), "xin ")
    }

    func testPlanNoOverDeleteWhenTouchDownAteWholeWord() throws {
        let p = try XCTUnwrap(WordDelete.plan(snapshot: "xin a", composed: "",
                                              current: "xin ", words: 1))
        XCTAssertEqual(p.deleteNow, 0)
        XCTAssertEqual(p.removed, "a")
        XCTAssertEqual(apply(p, to: "xin "), "xin ")
        let p2 = try XCTUnwrap(WordDelete.plan(snapshot: "xin a", composed: "",
                                               current: "xin ", words: 2))
        XCTAssertEqual(apply(p2, to: "xin "), "")
    }

    func testCancelReinsertsTouchDownDelete() throws {
        let p = try XCTUnwrap(WordDelete.plan(snapshot: "xin chào", composed: "",
                                              current: "xin chà", words: 0))
        XCTAssertEqual(p, .init(deleteNow: 0, reinsert: "o", removed: "", remaining: "xin chào"))
        XCTAssertEqual(apply(p, to: "xin chà"), "xin chào")
    }

    func testComposingWordPlan() throws {
        let p = try XCTUnwrap(WordDelete.plan(snapshot: "anh yêu em", composed: "em",
                                              current: "anh yêu e", words: 2))
        XCTAssertEqual(p.removed, "yêu em")
        XCTAssertEqual(apply(p, to: "anh yêu e"), "anh ")
    }

    func testFailSafe() {
        XCTAssertNil(WordDelete.plan(snapshot: nil, composed: "", current: "abc", words: 1))
        XCTAssertNil(WordDelete.plan(snapshot: "abc", composed: "", current: nil, words: 1))
        // từ đang soạn không còn ở cuối context → lệch → không xoá
        XCTAssertNil(WordDelete.plan(snapshot: "xin chào", composed: "bạn",
                                     current: "xin chà", words: 1))
    }

    func testTouchDownRedrewWordFallsBackToCurrent() throws {
        // engine vẽ lại từ ("cá" → "ca"), current không phải tiền tố snapshot
        let p = try XCTUnwrap(WordDelete.plan(snapshot: "ăn cá", composed: "cá",
                                              current: "ăn ca", words: 1))
        XCTAssertEqual(p.deleteNow, 2)
        XCTAssertEqual(p.removed, "ca")
        XCTAssertEqual(apply(p, to: "ăn ca"), "ăn ")
    }

    func testEmptyField() throws {
        let p = try XCTUnwrap(WordDelete.plan(snapshot: "", composed: "", current: "", words: 1))
        XCTAssertEqual(p, .init(deleteNow: 0, reinsert: "", removed: "", remaining: ""))
    }

    // MARK: khôi phục

    func testRestoreRoundTrip() throws {
        let cases: [(String, Int)] = [
            ("Xin chào, bạn!", 2), ("vui quá 😂😂", 2), ("tie\u{0302}\u{0301}ng Vie\u{0302}\u{0323}t", 1),
            ("dòng một\nhai  ", 3), ("chào", 4),
        ]
        for (snap, n) in cases {
            let current = String(snap.dropLast())      // lần xoá lúc chạm ⌫
            let p = try XCTUnwrap(WordDelete.plan(snapshot: snap, composed: "",
                                                  current: current, words: n))
            let after = apply(p, to: current)
            XCTAssertEqual(after, p.remaining, snap)
            let tail = WordDelete.restoreTail(p.remaining)
            XCTAssertTrue(WordDelete.canRestore(context: after, tail: tail))
            XCTAssertEqual(after + p.removed, snap, "khôi phục phải ra đúng chuỗi gốc: \(snap)")
        }
    }

    func testRestoreRefusedWhenCaretMoved() {
        XCTAssertTrue(WordDelete.canRestore(context: "xin ", tail: "xin "))
        XCTAssertFalse(WordDelete.canRestore(context: "chỗ khác", tail: "xin "))
        XCTAssertTrue(WordDelete.canRestore(context: nil, tail: "xin "))
        XCTAssertTrue(WordDelete.canRestore(context: "gì cũng được", tail: ""))
    }

    // MARK: KeyboardView — gesture qua test hook

    @MainActor private func makeKeyboard(limit: Int, keys: @escaping (KeyboardView.Key) -> Void)
        -> KeyboardView {
        let kb = KeyboardView(needsGlobe: false, inputController: nil, onKey: keys)
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 320))
        host.addSubview(kb)
        kb.frame = host.bounds
        kb.layoutIfNeeded()
        kb.wordSwipeLimit = { limit }
        return kb
    }

    @MainActor func testSwipeGestureOnView() throws {
        var backspaces = 0, touchDowns = 0
        var ended: [Int] = []
        let kb = makeKeyboard(limit: 5) { if case .backspace = $0 { backspaces += 1 } }
        kb.onBackspaceTouchDown = { touchDowns += 1 }
        kb.onWordSwipeEnd = { ended.append($0) }
        let step = WordDelete.swipeStep(letterKeyWidth: kb.debugLetterFrame("q")?.width)

        // kéo dưới ngưỡng = chạm thường: 1 lần xoá, không vuốt
        XCTAssertNil(kb.debugBackspaceSwipe(from: 350, through: [345, 340]))
        XCTAssertEqual(ended, [])
        XCTAssertEqual(backspaces, 1); XCTAssertEqual(touchDowns, 1)

        // kéo qua 1 bước sau ngưỡng → 2 từ
        let x2 = 350 - (WordDelete.swipeActivation + step + 1)
        XCTAssertEqual(kb.debugBackspaceSwipe(from: 350, through: [340, x2]), "\u{232B} 2 từ")
        XCTAssertEqual(ended, [2])

        // kéo sang trái rồi quay về → huỷ (0)
        XCTAssertEqual(kb.debugBackspaceSwipe(from: 350, through: [300, 349]), "Huỷ")
        XCTAssertEqual(ended, [2, 0])
        XCTAssertEqual(backspaces, 3)                 // mỗi lần chạm vẫn xoá 1 như cũ
    }

    @MainActor func testSwipeClampsAndNeedsWords() {
        var ended: [Int] = []
        let kb = makeKeyboard(limit: 1) { _ in }
        kb.onWordSwipeEnd = { ended.append($0) }
        kb.debugBackspaceSwipe(from: 350, through: [100])
        XCTAssertEqual(ended, [1])

        let empty = makeKeyboard(limit: 0) { _ in }
        empty.onWordSwipeEnd = { ended.append($0) }
        XCTAssertNil(empty.debugBackspaceSwipe(from: 350, through: [100]))
        XCTAssertEqual(ended, [1])                    // không có từ → không vuốt
    }

    @MainActor func testRestoreChipTakesFirstSlot() {
        let kb = makeKeyboard(limit: 1) { _ in }
        kb.setSuggestionsEnabled(true)
        var set = KeyboardView.SuggestionSet()
        set.nextWords = ["a", "b", "c"]
        set.restoreLabel = "Khôi phục"
        kb.showSuggestions(set)
        XCTAssertEqual(kb.debugSlotPayloads(), [KeyboardView.restoreToken, "a", "b"])
        set.restoreLabel = nil
        kb.showSuggestions(set)
        XCTAssertEqual(kb.debugSlotPayloads(), ["a", "b", "c"])
    }
}
