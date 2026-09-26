import XCTest

/// Regression 26/09/2026: iPad vuốt xuống ra ký tự phụ từng huỷ chữ bằng ⌫ →
/// "tieng" + vuốt s ra "tiến#" (⌫ xoá "g" chứ không gỡ dấu sắc). Giờ huỷ đúng phím.
final class LetterUndoTests: XCTestCase {
    private func typed(_ keys: String, _ bridge: EngineBridge, _ proxy: MockProxy) {
        for ch in keys {
            if ch == " " { bridge.boundary(" ", proxy: proxy) } else { bridge.letter(ch, proxy: proxy) }
        }
    }

    func testUndoToneKeyRestoresWord() {
        let p = MockProxy(), b = EngineBridge(settings: KeyboardSettings())
        typed("tieng", b, p)
        b.letter("s", proxy: p)
        XCTAssertEqual(p.text, "tiéng")
        XCTAssertTrue(b.undoLastLetter(proxy: p))
        b.boundary("#", proxy: p)
        XCTAssertEqual(p.text, "tieng#")
    }

    func testUndoCircumflexAndPlainLetter() {
        let p = MockProxy(), b = EngineBridge(settings: KeyboardSettings())
        typed("vie", b, p)
        b.letter("e", proxy: p)                       // viê
        XCTAssertTrue(b.undoLastLetter(proxy: p))
        XCTAssertEqual(p.text, "vie")
        b.letter("t", proxy: p)                       // engine về đúng "vie" ⇒ gõ tiếp bình thường
        XCTAssertEqual(p.text, "viet")

        let p2 = MockProxy(), b2 = EngineBridge(settings: KeyboardSettings())
        typed("xin ", b2, p2)
        b2.letter("a", proxy: p2)
        XCTAssertTrue(b2.undoLastLetter(proxy: p2))
        XCTAssertEqual(p2.text, "xin ")
    }

    func testUndoOnlyRightAfterTheLetter() {
        let p = MockProxy(), b = EngineBridge(settings: KeyboardSettings())
        typed("an", b, p)
        b.boundary(" ", proxy: p)
        XCTAssertFalse(b.undoLastLetter(proxy: p))    // đã có thao tác khác xen vào
    }

    func testUndoRefusesWhenContextDisagrees() {
        let p = MockProxy(), b = EngineBridge(settings: KeyboardSettings())
        typed("tieng", b, p)
        b.letter("s", proxy: p)
        p.fakeContext = "khác hẳn"
        XCTAssertFalse(b.undoLastLetter(proxy: p))
        XCTAssertEqual(p.text, "tiéng")               // không sửa mù
    }
}
