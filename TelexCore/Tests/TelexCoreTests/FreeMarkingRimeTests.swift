import XCTest
@testable import TelexCore

/// Issue #58 (25/08/2026): với "Bỏ dấu tự do" bật, "ngoeof" ra "ngồe" — chữ o thứ
/// hai bị reach-back fold thành ô XUYÊN QUA chữ e ở giữa, trong khi "oeo" (và
/// "oao") là vần thật (ngoèo, khoèo, ngoáo). Literal thắng đúng một hình đó;
/// các fold 1.3.1 khác giữ nguyên.
final class FreeMarkingRimeTests: XCTestCase {
    private func free(_ keys: String) -> String {
        var e = TelexEngine()
        e.freeMarking = true
        for ch in keys { _ = e.feed(ch) }
        return e.composed
    }

    func testOeoStaysLiteralRime() {
        XCTAssertEqual(free("ngoeof"), "ngoèo")   // the reported bug
        XCTAssertEqual(free("khoeof"), "khoèo")
        XCTAssertEqual(free("ngoanwf"), "ngoằn")  // reporter's first word, unchanged
    }

    func testOaoStaysLiteralRime() {
        XCTAssertEqual(free("ngoaos"), "ngoáo")
    }

    func testExistingFoldsUntouched() {
        XCTAssertEqual(free("coto"), "côt")       // fold across coda
        XCTAssertEqual(free("daua"), "dâu")       // a-fold across u (1.3.1)
        XCTAssertEqual(free("theme"), "thêm")     // e-fold across coda
        XCTAssertEqual(free("coio"), "côi")       // o-fold across i (not e/a)
        XCTAssertEqual(free("ama"), "âm")
    }
}
