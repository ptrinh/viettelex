import XCTest

/// Regression: gõ ký hiệu ở plane 123 rồi space không quay về plane chữ.
final class PlanePolicyTests: XCTestCase {
    func testSpaceAfterSymbolReturnsToLetters() {
        XCTAssertTrue(PlanePolicy.returnToLettersOnSpace(inSymbolPlane: true, typedInPlane: true, numericField: false))
    }
    func testSpaceWithoutTypingStaysInSymbols() {
        XCTAssertFalse(PlanePolicy.returnToLettersOnSpace(inSymbolPlane: true, typedInPlane: false, numericField: false))
    }
    func testNumericFieldStaysInNumbers() {
        XCTAssertFalse(PlanePolicy.returnToLettersOnSpace(inSymbolPlane: true, typedInPlane: true, numericField: true))
    }
    func testLettersPlaneUnaffected() {
        XCTAssertFalse(PlanePolicy.returnToLettersOnSpace(inSymbolPlane: false, typedInPlane: true, numericField: false))
    }
}

/// Dấu kết vế ở plane 123/#+= về chữ ngay, không cần dấu cách (Phil 06/11/2026).
/// Song sinh Android PlanePolicyTest.clauseEnderTable.
final class ClauseEndReturnTests: XCTestCase {
    /// (văn bản trước con trỏ, ký tự vừa chạm, về chữ?)
    static let table: [(before: String, key: String, returns: Bool, why: String)] = [
        ("2", ".", false, "2.5 — thập phân"),
        ("1", ",", false, "1,000 — hàng nghìn"),
        ("10", ":", false, "10:30 — giờ"),
        ("ok", ".", true, "ok."),
        ("ok", ",", true, "ok,"),
        ("hi", "!", true, "hi!"),
        ("hi", "?", true, "hi?"),
        ("", "(", false, "( mở ngoặc giữ plane"),
        ("(a", ")", true, "(a) — ) về chữ"),
        ("(1", ")", true, ") sau số vẫn về chữ"),
        ("say", "\"", true, "nháy kép"),
        ("it", "'", true, "nháy đơn"),
        ("note", ":", true, "note:"),
        ("a", ";", true, "a;"),
        ("2", ";", true, "; sau số vẫn về chữ"),
        ("2", "!", true, "! sau số vẫn về chữ"),
        ("wait", "\u{2026}", true, "…"),
        ("2", "\u{2026}", true, "… sau số vẫn về chữ"),
        ("x", "\u{201D}", true, "” đóng"),
        ("x", "\u{2019}", true, "’ đóng"),
        ("x", "\u{00BB}", true, "» đóng"),
        ("", "\u{201C}", false, "“ mở giữ plane"),
        ("", "\u{2018}", false, "‘ mở giữ plane"),
        ("", "\u{00AB}", false, "« mở giữ plane"),
        ("", ".", true, "đầu ô: . về chữ"),
        ("a ", ".", true, "sau dấu cách: . về chữ"),
    ] + ["@", "/", "#", "$", "%", "&", "*", "-", "_", "+", "=", "[", "{", "<", ">", "\\", "|",
         "1", "0", "₫", "€", "×", "÷", "]", "}", "~"].map { ("ok", $0, false, "\($0) giữ plane") }

    func testTable() {
        for c in Self.table {
            XCTAssertEqual(PlanePolicy.returnToLettersAfterSymbol(c.key, inSymbolPlane: true, numericField: false,
                                                                  before: c.before.last), c.returns, c.why)
        }
    }

    func testLettersPlaneAndNumericFieldUnaffected() {
        for k in PlanePolicy.clauseEnders {
            XCTAssertFalse(PlanePolicy.returnToLettersAfterSymbol(k, inSymbolPlane: false, numericField: false, before: "a"), k)
            XCTAssertFalse(PlanePolicy.returnToLettersAfterSymbol(k, inSymbolPlane: true, numericField: true, before: "a"), k)
        }
    }

    /// Mọi biến thể in ấn ĐÓNG có trong bàn 123/#+= đều thuộc bảng (không sót khi thêm biến thể).
    func testTypographicVariantsCovered() {
        for v in ["\u{2026}", "\u{201D}", "\u{2019}", "\u{00BB}"] {
            XCTAssertTrue(KeyVariants.table.values.contains { $0.contains(v) }, v)
            XCTAssertTrue(PlanePolicy.clauseEnders.contains(v), v)
        }
    }

    @MainActor private func makeKeyboard(_ kind: KeyboardView.InputKind = .normal) -> (KeyboardView, UIView) {
        let kb = KeyboardView(needsGlobe: false, inputController: nil) { _ in }
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 320))
        host.addSubview(kb)
        kb.frame = host.bounds
        kb.configureInputKind(kind)
        kb.layoutIfNeeded()
        return (kb, host)
    }

    /// Đường thật (chốt của phím 123): "." sau chữ về chữ + viết hoa lại; "." sau số ở lại.
    @MainActor func testViewReturnsAndReevaluatesShift() {
        let (kb, host) = makeKeyboard()
        _ = host
        kb.debugSetPlane(numbers: true)
        kb.contextBeforeProbe = { "2" }
        kb.debugTapSymbol(".")
        XCTAssertEqual(kb.debugPlaneName, "numbers", "2.5")
        kb.debugTapSymbol("5")
        XCTAssertEqual(kb.debugPlaneName, "numbers")
        kb.debugTapSymbol("(")
        XCTAssertEqual(kb.debugPlaneName, "numbers")
        kb.contextBeforeProbe = { "k" }
        kb.autoShiftProbe = { true }
        kb.debugTapSymbol(".")
        XCTAssertEqual(kb.debugPlaneName, "letters", "ok.")
        XCTAssertTrue(kb.debugShiftOn, "về chữ sau \".\" đánh giá lại viết hoa như chạm ABC")
    }

    @MainActor func testViewNumericFieldStays() {
        let (kb, host) = makeKeyboard(.number)
        _ = host
        kb.debugSetPlane(numbers: true)
        kb.contextBeforeProbe = { "a" }
        kb.debugTapSymbol(",")
        XCTAssertEqual(kb.debugPlaneName, "numbers")
    }
}

/// Regression (tester iOS 1.2.x): bật "Tự thêm dấu cách sau dấu câu", gõ "." ở plane
/// 123 → ". " tự thêm, chạm ABC về chữ ⇒ chữ kế KHÔNG viết hoa (code cũ ép shift off
/// khi về plane chữ). Giữ "," ra "." ở plane chữ thì vẫn đúng (không đổi plane).
final class ShiftOnReturnToLettersTests: XCTestCase {
    func testPolicyFollowsAutoShift() {
        XCTAssertTrue(PlanePolicy.shiftOnReturnToLetters(autoShift: true))
        XCTAssertFalse(PlanePolicy.shiftOnReturnToLetters(autoShift: false))
        XCTAssertFalse(PlanePolicy.shiftOnReturnToLetters(autoShift: nil))   // công tắc tắt: như cũ
    }

    func testContextAfterAutoSpaceCapitalizes() {
        for p in [".", "!", "?"] {
            let a = FieldPolicy.autoShift(autocap: .sentences, before: "Xin chào\(p) ")
            XCTAssertTrue(PlanePolicy.shiftOnReturnToLetters(autoShift: a), p)
        }
        let mid = FieldPolicy.autoShift(autocap: .sentences, before: "giá 5")
        XCTAssertFalse(PlanePolicy.shiftOnReturnToLetters(autoShift: mid))
    }

    @MainActor private func makeKeyboard() -> (KeyboardView, UIView) {
        let kb = KeyboardView(needsGlobe: false, inputController: nil) { _ in }
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 320))
        host.addSubview(kb)
        kb.frame = host.bounds
        kb.configureInputKind(.normal)
        kb.layoutIfNeeded()
        return (kb, host)
    }

    /// Đường thật: ABC chạm ở plane số sau khi ". " vừa bật auto-shift.
    @MainActor func testABCAfterAutoSpaceKeepsShift() throws {
        let (kb, host) = makeKeyboard()
        _ = host
        kb.setAutoShift(false)                                   // đang giữa câu
        try XCTUnwrap(kb.debugControl("Số")).sendActions(for: .touchDown)
        XCTAssertEqual(kb.debugPlaneName, "numbers")
        kb.setAutoShift(true)                                    // "." + dấu cách tự thêm
        kb.autoShiftProbe = { true }
        try XCTUnwrap(kb.debugControl("Chữ")).sendActions(for: .touchDown)
        XCTAssertEqual(kb.debugPlaneName, "letters")
        XCTAssertTrue(kb.debugShiftOn, "sau \". \" về ABC phải viết hoa chữ kế")
    }

    @MainActor func testABCMidSentenceDropsShift() throws {
        let (kb, host) = makeKeyboard()
        _ = host
        try XCTUnwrap(kb.debugControl("Số")).sendActions(for: .touchDown)
        kb.autoShiftProbe = { false }
        try XCTUnwrap(kb.debugControl("Chữ")).sendActions(for: .touchDown)
        XCTAssertFalse(kb.debugShiftOn)
    }
}
