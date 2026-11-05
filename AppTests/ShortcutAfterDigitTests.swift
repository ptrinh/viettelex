import XCTest
@testable import VietTelex

/// Issue #82 (16/09/2026): gõ tắt `h→giờ` nở luôn trong "5h" thành "5giờ" vì chữ số
/// là boundary trong Telex — từ "h" không biết nó dính số. Chuẩn quen thuộc: "5h" là một
/// token, gõ tắt chỉ nở khi từ đứng riêng ("5 h" → "5 giờ").
final class ShortcutAfterDigitTests: XCTestCase {
    func testDigitBeforeWordBlocksExpansion() {
        XCTAssertFalse(TelexInputController.shortcutExpansionAllowed(afterDigit: true))   // 5h, 5k, 10k
        XCTAssertTrue(TelexInputController.shortcutExpansionAllowed(afterDigit: false))   // h, "5 h", "(h"
    }

    func testDigitDetection() {
        for c in "0123456789".utf8 { XCTAssertTrue(TelexInputController.isAsciiDigit(c)) }
        for c in " (.,-h".utf8 { XCTAssertFalse(TelexInputController.isAsciiDigit(c), String(UnicodeScalar(c))) }
        XCTAssertFalse(TelexInputController.isAsciiDigit(nil))
    }

    /// Issue #87 (21/09/2026): "/h3" → "/giờ3" trong Lark. Slash command / hashtag /
    /// mention là token như "5h": từ dính sau `/` `#` `@` không được nở gõ tắt.
    func testTokenOpenersGlue() {
        for c in "/#@0123456789".utf8 { XCTAssertTrue(TelexInputController.gluesShortcutToken(c), String(UnicodeScalar(c))) }
        // Gõ tắt khớp iOS/Android (27/09/2026): ký tự NỐI token (URL, email, tên file,
        // "a-ko", "x.ko") cũng dính — như ShortcutTable.isGlued bên iOS.
        for c in "._-:\\~&=+%".utf8 { XCTAssertTrue(TelexInputController.gluesShortcutToken(c), String(UnicodeScalar(c))) }
        for c in " (,h\n!?)".utf8 { XCTAssertFalse(TelexInputController.gluesShortcutToken(c), String(UnicodeScalar(c))) }
        XCTAssertFalse(TelexInputController.gluesShortcutToken(nil))
    }
}
