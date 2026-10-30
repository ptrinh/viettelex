import XCTest

/// Tester 30/10/2026 (ô chat web "Muse AI"): Return luôn gửi, cần xuống dòng KHÔNG gửi.
/// "\n" một mình = phím Enter của WebKit; "\n" nằm trong chuỗi dài hơn = chèn văn bản
/// (giả định theo manh mối gõ tắt "chữ\nchữ" — chưa kiểm chứng Safari thật). Xem LineBreak.swift.
final class LineBreakTests: XCTestCase {

    // MARK: plan (thuần)

    func testCarriesLastCharacter() {
        XCTAssertEqual(LineBreak.plan(context: "Xin chào", hasSelection: false), .carry("o"))
        XCTAssertEqual(LineBreak.plan(context: "tiếng Việt", hasSelection: false), .carry("t"))
        XCTAssertEqual(LineBreak.plan(context: "Chào bạn!", hasSelection: false), .carry("!"))
        XCTAssertEqual(LineBreak.plan(context: "đ", hasSelection: false), .carry("đ"))
    }

    func testCarriesTrailingWhitespaceWithLastCharacter() {
        // Khoảng trắng một mình có thể vẫn bị coi là Enter ⇒ kèm luôn chữ trước nó.
        XCTAssertEqual(LineBreak.plan(context: "hi ", hasSelection: false), .carry("i "))
        XCTAssertEqual(LineBreak.plan(context: "hi\n", hasSelection: false), .carry("i\n"))
        XCTAssertEqual(LineBreak.plan(context: "a \n\n", hasSelection: false), .carry("a \n\n"))
    }

    func testPlainWhenNothingSafeToCarry() {
        XCTAssertEqual(LineBreak.plan(context: nil, hasSelection: false), .plain)
        XCTAssertEqual(LineBreak.plan(context: "", hasSelection: false), .plain)
        XCTAssertEqual(LineBreak.plan(context: "   ", hasSelection: false), .plain)
        XCTAssertEqual(LineBreak.plan(context: "\n", hasSelection: false), .plain)
        XCTAssertEqual(LineBreak.plan(context: "x" + String(repeating: " ", count: 8), hasSelection: false), .plain)
    }

    func testPlainWithSelection() {
        // ⌫ sẽ xoá vùng chọn chứ không phải ký tự trước con trỏ.
        XCTAssertEqual(LineBreak.plan(context: "hello", hasSelection: true), .plain)
    }

    func testPlainForMultiScalarOrRiskyGraphemes() {
        let risky = ["👍🏽", "👨‍👩‍👧", "🇻🇳", "😀", "❤️", "e\u{0301}", "a\u{0323}\u{0302}", "\r\n", "1️⃣"]
        for g in risky {
            XCTAssertEqual(LineBreak.plan(context: "chào " + g, hasSelection: false), .plain, g.debugDescription)
            XCTAssertEqual(LineBreak.plan(context: "chào " + g + " ", hasSelection: false), .plain, g.debugDescription)
        }
        XCTAssertFalse(LineBreak.isSafe("\u{200D}"))
        XCTAssertFalse(LineBreak.isSafe("\u{FE0F}"))
        XCTAssertTrue(LineBreak.isSafe("ệ"))       // NFC một scalar
        XCTAssertTrue(LineBreak.isSafe("€"))
        XCTAssertTrue(LineBreak.isSafe("☺"))       // BMP, một scalar
    }

    func testPlainWhenContextStale() {
        // Vừa chèn "you" mà host chưa báo ⇒ không xoá theo context cũ.
        XCTAssertEqual(LineBreak.plan(context: "thank", hasSelection: false, justInserted: "you"), .plain)
        XCTAssertEqual(LineBreak.plan(context: "thank you", hasSelection: false, justInserted: "you"), .carry("u"))
    }

    // MARK: insert trên proxy giả

    func testInsertDeletesThenReinsertsInOneCall() {
        let p = RecordingProxy(text: "Xin chào")
        XCTAssertEqual(LineBreak.insert(proxy: p), .carry("o"))
        XCTAssertEqual(p.text, "Xin chào\n")
        XCTAssertEqual(p.ops, ["⌫", "o\n"])
    }

    func testInsertPlainOnEmptyField() {
        let p = RecordingProxy(text: "")
        XCTAssertEqual(LineBreak.insert(proxy: p), .plain)
        XCTAssertEqual(p.ops, ["\n"])
    }

    func testInsertPlainWithSelection() {
        let p = RecordingProxy(text: "hello")
        p.hasSelection = true
        LineBreak.insert(proxy: p)
        XCTAssertEqual(p.ops, ["\n"])
    }

    // MARK: phím Return (KeyboardView, thuần)

    private func isLineBreak(_ k: KeyboardView.Key) -> Bool { if case .lineBreak = k { return true }; return false }

    func testShiftReturnOnlyForHandShift() {
        XCTAssertTrue(isLineBreak(KeyboardView.returnTapKey(shiftOn: true, byHand: true, allowed: true)))
        // Viết hoa đầu câu tự động ⇒ Return gửi như cũ.
        XCTAssertFalse(isLineBreak(KeyboardView.returnTapKey(shiftOn: true, byHand: false, allowed: true)))
        XCTAssertFalse(isLineBreak(KeyboardView.returnTapKey(shiftOn: false, byHand: false, allowed: true)))
        XCTAssertFalse(isLineBreak(KeyboardView.returnTapKey(shiftOn: true, byHand: true, allowed: false)))
    }

    func testAllowedFields() {
        XCTAssertTrue(KeyboardView.lineBreakAllowed(kind: .normal, returnTitle: "return"))
        XCTAssertTrue(KeyboardView.lineBreakAllowed(kind: .normal, returnTitle: "send"))
        XCTAssertFalse(KeyboardView.lineBreakAllowed(kind: .normal, returnTitle: "go"))
        XCTAssertFalse(KeyboardView.lineBreakAllowed(kind: .normal, returnTitle: "search"))
        XCTAssertFalse(KeyboardView.lineBreakAllowed(kind: .normal, returnTitle: "next"))
        XCTAssertFalse(KeyboardView.lineBreakAllowed(kind: .search, returnTitle: "return"))
        XCTAssertFalse(KeyboardView.lineBreakAllowed(kind: .url, returnTitle: "return"))
        XCTAssertFalse(KeyboardView.lineBreakAllowed(kind: .email, returnTitle: "return"))
    }

    // MARK: controller thật + proxy giả

    @MainActor private func run(_ keys: [KeyboardView.Key]) -> KeyboardBenchTests.BenchProxy {
        let saved = UserDefaultsProvider.shared
        defer { UserDefaultsProvider.shared = saved }
        UserDefaultsProvider.shared = KeyboardBenchTests.makeDefaults("C")
        let r = KeyboardBenchTests.Rig()
        defer { r.close() }
        for k in keys { r.vc.debugHandle(k); KeyboardBenchTests.spin(0.02) }
        return r.proxy
    }

    @MainActor func testControllerLineBreakTravelsInsideLongerString() {
        let p = run("chaof".map { .letter($0) } + [.lineBreak])
        XCTAssertEqual(p.text, "chào\n")
        XCTAssertFalse(p.insertLog.contains("\n"), "newline không được đi một mình: \(p.insertLog)")
        XCTAssertEqual(p.insertLog.last, "o\n")
    }

    @MainActor func testControllerLineBreakThenKeepTyping() {
        let p = run("hi".map { .letter($0) } + [.lineBreak] + "ok".map { .letter($0) })
        XCTAssertEqual(p.text, "hi\nok")
    }

    @MainActor func testControllerPlainReturnUnchanged() {
        let p = run("hi".map { .letter($0) } + [.newline])
        XCTAssertEqual(p.text, "hi\n")
        XCTAssertEqual(p.insertLog.last, "\n")
    }
}

private final class RecordingProxy: TextProxyLike {
    var text: String
    var ops: [String] = []
    var hasSelection = false
    var isSecure: Bool { false }
    init(text: String) { self.text = text }
    var contextBeforeInput: String? { text }
    var contextAfterInput: String? { "" }
    func insertText(_ t: String) { ops.append(t); text += t }
    func deleteBackward() { ops.append("⌫"); if !text.isEmpty { text.removeLast() } }
}
