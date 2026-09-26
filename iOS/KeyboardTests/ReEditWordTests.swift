// Sửa dấu từ đã gõ xong trên iOS: ⌫ mở lại từ vừa chốt (reopenLastCommit) và
// phím dấu/mũ nạp lại từ ngay trước con trỏ (seed). Mọi ca lệch phải KHÔNG sửa
// màn hình (chỉ làm việc gốc của phím: ⌫ xoá 1 ký tự, chữ chèn literal).
import XCTest
import TelexCore

final class ReEditWordTests: XCTestCase {

    private func run(_ keys: String, on p: MockProxy, bridge b: EngineBridge) {
        for ch in keys {
            if ch == " " || ch == "." { b.boundary(String(ch), proxy: p) }
            else if ch == "⌫" { b.backspace(proxy: p) }
            else { b.letter(ch, proxy: p) }
        }
    }

    private func type(_ keys: String, initial: String = "",
                      settings: KeyboardSettings = KeyboardSettings()) -> String {
        let p = MockProxy(); p.text = initial
        run(keys, on: p, bridge: EngineBridge(settings: settings))
        return p.text
    }

    private var off: KeyboardSettings { var s = KeyboardSettings(); s.reEditWord = false; return s }

    // MARK: ⌫ mở lại từ vừa chốt

    func testReopenAddsCircumflex() {
        XCTAssertEqual(type("thays ⌫a"), "thấy")
        XCTAssertEqual(type("thays ⌫a "), "thấy ")
    }

    func testReopenAddsTone() {
        XCTAssertEqual(type("vieetj ⌫z"), "viêt")      // bỏ dấu cũng được
        XCTAssertEqual(type("hoa ⌫f "), "hòa ")
        XCTAssertEqual(type("xin chao ⌫f"), "xin chào")
    }

    func testReopenAfterPunctuation() {
        XCTAssertEqual(type("thays.⌫a"), "thấy")
    }

    func testReopenReportsAndOnlyOnce() {
        let p = MockProxy(); let b = EngineBridge(settings: KeyboardSettings())
        run("chao ", on: p, bridge: b)
        XCTAssertTrue(b.backspace(proxy: p))
        XCTAssertEqual(b.composedWord, "chao")
        // Xoá hết từ rồi ⌫ thêm: không có gì để mở lại nữa → xoá thường.
        run("⌫⌫⌫⌫", on: p, bridge: b)
        XCTAssertEqual(p.text, "")
        XCTAssertFalse(b.isComposing)
    }

    func testDoubleSpaceNoReopen() {
        // ⌫ xoá space thứ hai: engine rỗng lúc chốt lần 2 → không mở lại.
        XCTAssertEqual(type("chao  ⌫f"), "chao f")
    }

    func testReopenContextMismatchLeavesScreen() {
        let p = MockProxy(); let b = EngineBridge(settings: KeyboardSettings())
        run("thays ", on: p, bridge: b)
        p.fakeContext = "hello "                 // host báo chữ khác trước con trỏ
        XCTAssertFalse(b.backspace(proxy: p))
        XCTAssertEqual(p.text, "tháy")           // ⌫ chỉ xoá space
        XCTAssertFalse(b.isComposing)
        p.fakeContext = nil
        b.letter("a", proxy: p)
        XCTAssertEqual(p.text, "tháya")          // không sửa từ cũ
    }

    func testReopenNilContextDoesNothing() {
        let p = MockProxy(); let b = EngineBridge(settings: KeyboardSettings())
        run("thays ", on: p, bridge: b)
        p.fakeContext = .some(nil)
        XCTAssertFalse(b.backspace(proxy: p))
        XCTAssertEqual(p.text, "tháy")
        XCTAssertFalse(b.isComposing)
    }

    func testReopenNFDContextRejected() {
        let p = MockProxy(); let b = EngineBridge(settings: KeyboardSettings())
        run("thays ", on: p, bridge: b)
        p.fakeContext = "tha\u{301}y "           // cùng chữ nhưng NFD
        XCTAssertFalse(b.backspace(proxy: p))
        XCTAssertFalse(b.isComposing)
    }

    func testReopenSkippedWithSelectionOrOmnibox() {
        let p = MockProxy(); let b = EngineBridge(settings: KeyboardSettings())
        run("thays ", on: p, bridge: b)
        p.hasSelection = true
        XCTAssertFalse(b.backspace(proxy: p))
        let p2 = MockProxy(); let b2 = EngineBridge(settings: KeyboardSettings())
        b2.reachBackAllowed = false
        run("thays ⌫a", on: p2, bridge: b2)
        XCTAssertEqual(p2.text, "tháya")
    }

    func testReopenForgottenAfterRewrite() {
        let p = MockProxy(); let b = EngineBridge(settings: KeyboardSettings())
        run("thays ", on: p, bridge: b)
        b.forgetLastCommit()
        XCTAssertFalse(b.backspace(proxy: p))
        XCTAssertEqual(p.text, "tháy")
    }

    /// Từ bị auto-restore (engine không capture) → reopen nil; ⌫ chỉ xoá space và
    /// engine rỗng — đúng điều kiện controller dùng để chào backspace-undo (restoreUndo).
    func testAutoRestoredWordNotReopened() {
        let p = MockProxy(); let b = EngineBridge(settings: KeyboardSettings())
        for ch in "google" { b.letter(ch, proxy: p) }
        let composed = b.composedWord
        let committed = b.boundary(" ", proxy: p)
        XCTAssertNotEqual(composed, committed)   // restoreUndo sẽ được set
        XCTAssertFalse(b.backspace(proxy: p))
        XCTAssertEqual(p.text, "google")
        XCTAssertFalse(b.isComposing)            // → undoOfferActive vẫn bật như cũ
    }

    // MARK: Seed từ trước con trỏ

    func testSeedAddsTone() {
        XCTAssertEqual(type("j", initial: "viêt"), "việt")
        XCTAssertEqual(type("s", initial: "xin toan"), "xin toán")
        XCTAssertEqual(type("j", initial: "Viêt"), "Việt")
        XCTAssertEqual(type("z", initial: "việt"), "viêt")
    }

    func testSeedHornKey() {
        XCTAssertEqual(type("w", initial: "tu"), "tư")
    }

    /// a e o d KHÔNG nạp lại từ (user 26/09/2026): "to" + o = "too", không phải "tô".
    func testSeedIgnoresCircumflexAndDKeys() {
        XCTAssertEqual(type("o", initial: "to"), "too")
        XCTAssertEqual(type("e", initial: "viet"), "viete")
        XCTAssertEqual(type("d", initial: "d"), "dd")
        XCTAssertEqual(type("a", initial: "tha"), "thaa")
    }

    func testSeedThenKeepsComposing() {
        XCTAssertEqual(type("sn ", initial: "toa"), "toán ")
    }

    // MARK: Công tắc

    func testToggleOffDisablesBoth() {
        XCTAssertEqual(type("thays ⌫a", settings: off), "tháya")
        XCTAssertEqual(type("hoa ⌫f", settings: off), "hoaf")
        XCTAssertEqual(type("j", initial: "viêt", settings: off), "viêtj")
        XCTAssertEqual(type("s", initial: "toan", settings: off), "toans")
    }

    func testSeedNoTransformIsLiteral() {
        XCTAssertEqual(type("a", initial: "ch"), "cha")
        XCTAssertEqual(type("s", initial: "google"), "googles")
    }

    func testSeedMidWordIsLiteral() {
        let p = MockProxy(); p.text = "vi"; p.textAfter = "et"
        EngineBridge(settings: KeyboardSettings()).letter("s", proxy: p)
        XCTAssertEqual(p.text, "vis")
    }

    func testSeedNilAfterContextTreatedAsEnd() {
        let p = MockProxy(); p.text = "viêt"; p.fakeAfter = .some(nil)
        EngineBridge(settings: KeyboardSettings()).letter("j", proxy: p)
        XCTAssertEqual(p.text, "việt")
    }

    func testSeedSkippedWhenUnknownOrUnsafe() {
        let p = MockProxy(); p.text = "viet"; p.fakeContext = .some(nil)
        EngineBridge(settings: KeyboardSettings()).letter("j", proxy: p)
        XCTAssertEqual(p.text, "vietj")

        let p2 = MockProxy(); p2.text = "viet"; p2.hasSelection = true
        EngineBridge(settings: KeyboardSettings()).letter("j", proxy: p2)
        XCTAssertEqual(p2.text, "vietj")

        let p3 = MockProxy(); p3.text = "viet"
        let b3 = EngineBridge(settings: KeyboardSettings()); b3.passthrough = true
        b3.letter("j", proxy: p3)
        XCTAssertEqual(p3.text, "vietj")

        let p4 = MockProxy(); p4.text = "viet"
        let b4 = EngineBridge(settings: KeyboardSettings()); b4.reachBackAllowed = false
        b4.letter("j", proxy: p4)
        XCTAssertEqual(p4.text, "vietj")

        let p5 = MockProxy(); p5.text = "vie\u{302}t"   // NFD
        EngineBridge(settings: KeyboardSettings()).letter("j", proxy: p5)
        XCTAssertEqual(p5.text, "vie\u{302}tj")
    }

    func testNewWordAfterSpaceUnaffected() {
        XCTAssertEqual(type("viet sao "), "viet sao ")
        XCTAssertEqual(type("ddi "), "đi ")
    }

    func testPureHelpers() {
        XCTAssertEqual(CompositionSync.trailingWord("xin chào"), "chào")
        XCTAssertNil(CompositionSync.trailingWord("xin "))
        XCTAssertNil(CompositionSync.trailingWord(""))
        XCTAssertTrue(CompositionSync.endsWithWord("xin chào", "chào"))
        XCTAssertTrue(CompositionSync.endsWithWord("chào", "chào"))
        XCTAssertFalse(CompositionSync.endsWithWord("xchào", "chào"))
        XCTAssertFalse(CompositionSync.endsWithWord("cha\u{300}o", "chào"))
    }
}
