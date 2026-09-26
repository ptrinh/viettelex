// Regression: "không gõ được tiếng Việt trong ô search App Store" (26/09/2026) —
// host gán lại text mỗi phím → textWillChange đến MUỘN (applyingEdit đã false) →
// reset mù giữa từ. Và fail-safe: không bao giờ deleteBackward × N khi chữ trước con
// trỏ không còn là thứ mình định xoá.
import XCTest
import UIKit
import TelexCore

final class CompositionSyncVerdictTests: XCTestCase {

    func testKeepWhenContextStillEndsWithComposedWord() {
        XCTAssertEqual(CompositionSync.verdict(context: "tìm viê", composed: "viê"), .keep)
        XCTAssertEqual(CompositionSync.verdict(context: "viê", composed: "viê"), .keep)
    }

    func testResetWhenContextDiverges() {
        // con trỏ dời / đổi ô / host xoá ô
        XCTAssertEqual(CompositionSync.verdict(context: "hello ", composed: "viê"), .reset)
        XCTAssertEqual(CompositionSync.verdict(context: "", composed: "viê"), .reset)
        XCTAssertEqual(CompositionSync.verdict(context: "viê ", composed: "viê"), .reset)
    }

    func testNilContextIsUnknownNotEmpty() {
        // iOS 16+ có host trả nil thay "" — không biết thì KHÔNG được coi là khớp.
        XCTAssertEqual(CompositionSync.verdict(context: nil, composed: "viê"), .unknown)
    }

    func testSelectionForcesReset() {
        XCTAssertEqual(CompositionSync.verdict(context: "viê", composed: "viê", selectedText: "abc"), .reset)
        XCTAssertEqual(CompositionSync.verdict(context: "viê", composed: "viê", selectedText: ""), .keep)
    }

    func testNothingComposingResets() {
        XCTAssertEqual(CompositionSync.verdict(context: "abc", composed: ""), .reset)
    }

    func testCanonicalEquivalenceNFD() {
        // host chuẩn hoá NFD vẫn phải khớp từ NFC engine chèn
        let nfd = "việt".decomposedStringWithCanonicalMapping
        XCTAssertEqual(CompositionSync.verdict(context: "x " + nfd, composed: "việt"), .keep)
        XCTAssertTrue(CompositionSync.canDelete(4, expected: "việt", context: { nfd }))
    }

    func testDiagnosticNeverNeedsContent() {
        XCTAssertEqual(CompositionSync.diagnostic(context: nil, composed: "a").len, -1)
        let d = CompositionSync.diagnostic(context: "ab viê", composed: "viê")
        XCTAssertEqual(d.len, 6); XCTAssertTrue(d.suffix)
        XCTAssertFalse(CompositionSync.diagnostic(context: "abc", composed: "").suffix)
    }
}

final class CompositionSyncCanDeleteTests: XCTestCase {

    func testBelowThresholdNeverReadsContext() {
        var reads = 0
        XCTAssertTrue(CompositionSync.canDelete(1, expected: "a", context: { reads += 1; return "zzz" }))
        XCTAssertTrue(CompositionSync.canDelete(0, expected: "", context: { reads += 1; return "zzz" }))
        XCTAssertEqual(reads, 0)
    }

    func testMismatchBlocksMultiDelete() {
        XCTAssertFalse(CompositionSync.canDelete(2, expected: "viêt", context: { "hello" }))
        XCTAssertTrue(CompositionSync.canDelete(2, expected: "viêt", context: { "tôi viêt" }))
    }

    func testNilContextAllows() {
        // không biết → hành vi cũ (xoá), kẻo host không báo context là hỏng Telex
        XCTAssertTrue(CompositionSync.canDelete(3, expected: "viêt", context: { nil }))
    }

    func testNeverDeleteBeyondExpectedWord() {
        XCTAssertFalse(CompositionSync.canDelete(5, expected: "viêt", context: { "a viêt" }))
    }
}

final class CompositionSyncBridgeTests: XCTestCase {

    /// Mô phỏng host kiểu ô search App Store: sau MỖI phím, textWillChange/DidChange
    /// đến muộn (ngoài handle). Trước đây → bridge.reset() mỗi phím → "vieetj".
    private func typeWithLateHostCallbacks(_ keys: String, proxy: MockProxy) {
        let bridge = EngineBridge(settings: KeyboardSettings())
        for ch in keys {
            if ch == " " { bridge.boundary(" ", proxy: proxy) } else { bridge.letter(ch, proxy: proxy) }
            if CompositionSync.verdict(context: proxy.contextBeforeInput,
                                       composed: bridge.composedWord) != .keep {
                bridge.reset()
            }
        }
    }

    func testLateTextWillChangeKeepsComposition() {
        let p = MockProxy()
        typeWithLateHostCallbacks("tim vieetj ", proxy: p)
        XCTAssertEqual(p.text, "tim việt ")
    }

    func testFailSafeLetterDoesNotDeleteForeignText() {
        let p = MockProxy()
        let b = EngineBridge(settings: KeyboardSettings())
        for ch in "vieet" { b.letter(ch, proxy: p) }
        XCTAssertEqual(p.text, "viêt")
        // Host báo con trỏ đã sang chỗ khác: 'j' (định xoá 2 để vẽ "ệt") phải chèn literal.
        p.fakeContext = "hello"
        b.letter("j", proxy: p)
        XCTAssertEqual(p.text, "viêtj")
        XCTAssertEqual(b.composedWord, "j")      // từ mới bắt đầu từ phím này
    }

    func testNilContextStillTypesVietnamese() {
        let p = MockProxy()
        p.fakeContext = .some(nil)
        let b = EngineBridge(settings: KeyboardSettings())
        for ch in "vieetj" { b.letter(ch, proxy: p) }
        b.boundary(" ", proxy: p)
        XCTAssertEqual(p.text, "việt ")
    }

    func testFailSafeBoundarySkipsAutoRestore() {
        let p = MockProxy()
        let b = EngineBridge(settings: KeyboardSettings())
        for ch in "google" { b.letter(ch, proxy: p) }
        let shown = p.text
        XCTAssertNotEqual(shown, "google")       // engine đang hiện dạng có dấu
        p.fakeContext = "abc"
        let final = b.boundary(" ", proxy: p)
        XCTAssertEqual(p.text, shown + " ")      // không xoá gì, chỉ chèn space
        XCTAssertEqual(final, shown)
        XCTAssertFalse(b.isComposing)
    }

    func testFailSafeBackspaceFallsBackToSingleDelete() {
        let p = MockProxy()
        let b = EngineBridge(settings: KeyboardSettings())
        for ch in "toans" { b.letter(ch, proxy: p) }
        let shown = p.text
        p.fakeContext = "xyz"
        b.backspace(proxy: p)
        XCTAssertEqual(p.text, String(shown.dropLast()))
        XCTAssertFalse(b.isComposing)
    }
}

final class CompositionSyncClearTests: XCTestCase {

    func testClearAllWithLiveContext() {
        let p = MockProxy(); p.text = "một hai ba"
        let sent = CompositionSync.clearBefore(context: { p.contextBeforeInput },
                                               deleteBackward: { p.deleteBackward() })
        XCTAssertEqual(p.text, ""); XCTAssertEqual(sent, 10)
    }

    func testClearAllWithWindowedContext() {
        // host chỉ trả cửa sổ 4 ký tự cuối → nhiều lượt, vẫn xoá sạch
        let p = MockProxy(); p.text = "abcdefghij"
        CompositionSync.clearBefore(context: { p.text.isEmpty ? "" : String(p.text.suffix(4)) },
                                    deleteBackward: { p.deleteBackward() })
        XCTAssertEqual(p.text, "")
    }

    func testClearStopsWhenContextIsStale() {
        // host không cập nhật context sau deleteBackward → dừng sau 1 lượt, không xoá mù
        let p = MockProxy(); p.text = String(repeating: "x", count: 100)
        let sent = CompositionSync.clearBefore(context: { "xxxxx" },
                                               deleteBackward: { p.deleteBackward() })
        XCTAssertEqual(sent, 5)
        XCTAssertEqual(p.text.count, 95)
    }

    func testMoveToEndStopsWhenStale() {
        var moved = 0
        CompositionSync.moveToEnd(contextAfter: { "abc" }, adjust: { moved += $0 })
        XCTAssertEqual(moved, 3)
    }
}

final class FieldTraitsTests: XCTestCase {

    func testReconfigureOnlyWhenChanged() {
        let a = FieldTraits(keyboardType: .default, returnKeyType: .search)
        XCTAssertTrue(FieldTraits.needsReconfigure(old: nil, new: a))
        XCTAssertFalse(FieldTraits.needsReconfigure(old: a, new: a))
        var b = a; b.returnKeyType = .send
        XCTAssertTrue(FieldTraits.needsReconfigure(old: a, new: b))
        var c = a; c.contentType = .emailAddress
        XCTAssertTrue(FieldTraits.needsReconfigure(old: a, new: c))
    }

    func testDerivedPolicy() {
        XCTAssertEqual(FieldTraits(keyboardType: .numberPad).inputKind, .number)
        XCTAssertEqual(FieldTraits(keyboardType: .emailAddress).inputKind, .email)
        XCTAssertEqual(FieldTraits(keyboardType: .URL).inputKind, .url)
        XCTAssertEqual(FieldTraits(keyboardType: .webSearch).inputKind, .normal)
        XCTAssertTrue(FieldTraits(keyboardType: .emailAddress).passthrough)
        XCTAssertFalse(FieldTraits(keyboardType: .webSearch, autocorrection: .no).passthrough)
        XCTAssertFalse(FieldTraits(autocorrection: .no).allowsSuggestions)
        XCTAssertFalse(FieldTraits(secure: true).allowsSuggestions)
        XCTAssertTrue(FieldTraits().allowsSuggestions)
    }

    func testLogDescriptionHasTraitKeys() {
        let d = FieldTraits(keyboardType: .webSearch, returnKeyType: .search).logDescription
        XCTAssertTrue(d.contains("keyboardType=\(UIKeyboardType.webSearch.rawValue)"))
        XCTAssertTrue(d.contains("returnKeyType=\(UIReturnKeyType.search.rawValue)"))
        XCTAssertTrue(d.contains("textContentType=nil"))
    }
}
