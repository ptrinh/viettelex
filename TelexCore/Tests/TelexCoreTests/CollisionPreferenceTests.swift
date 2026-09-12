import XCTest
@testable import TelexCore

/// "Ưu tiên khi trùng" (maintainer 12/09/2026, default app = tiếng Việt): từ vừa là
/// English trong bảng collision vừa là âm tiết Việt hợp lệ. Kết thúc chuỗi tranh
/// cãi từng-từ (#60 last/lát, PR#76 list/lít, his/hí) — user chọn, không phải
/// maintainer quyết hộ.
final class CollisionPreferenceTests: XCTestCase {
    private func sentence(_ text: String, vietnamese: Bool) -> String {
        var e = TelexEngine()
        e.liveSpellCheck = true; e.contextualEnglish = true
        e.collisionPrefersVietnamese = vietnamese
        var out: [String] = []
        for word in text.split(separator: " ") {
            for ch in word { _ = e.feed(ch) }
            out.append(e.commitText(autoRestore: true))
            // commitText resets the buffer but keeps the English-run context.
        }
        return out.joined(separator: " ")
    }

    func testVietnameseWinsStandalone() {
        XCTAssertEqual(sentence("last", vietnamese: true), "lát")
        XCTAssertEqual(sentence("list", vietnamese: true), "lít")
        XCTAssertEqual(sentence("mootj list", vietnamese: true), "một lít")
        // "his" nằm trong protect-list (his→hí là chính sách cũ) — Việt ở cả hai chế độ.
        XCTAssertEqual(sentence("his", vietnamese: true), "hí")
        XCTAssertEqual(sentence("his", vietnamese: false), "hí")
    }

    func testEnglishWinsIsTheOldBehavior() {
        XCTAssertEqual(sentence("last", vietnamese: false), "last")
        XCTAssertEqual(sentence("list", vietnamese: false), "list")
    }

    func testEnglishRunStillRestoresUnderVietnamesePriority() {
        // Hybrid: trong mạch tiếng Anh (từ trước là English) bảng collision vẫn
        // khôi phục — "the list" không thành "the lít".
        XCTAssertEqual(sentence("the list", vietnamese: true), "the list")
        XCTAssertEqual(sentence("she last", vietnamese: true), "she last")
    }

    func testInvalidSyllablesAndGesturesUnchanged() {
        // Không phải âm tiết Việt → vẫn về raw, bất kể ưu tiên.
        XCTAssertEqual(sentence("text", vietnamese: true), "text")
        XCTAssertEqual(sentence("google", vietnamese: true), "google")
        // Escape gõ đúp vẫn là đường tiếng Anh khi ưu tiên Việt: lisst → list.
        XCTAssertEqual(sentence("lisst", vietnamese: true), "list")
        // Dấu cuối từ vẫn là đường tiếng Việt khi ưu tiên Anh: lits → lít.
        XCTAssertEqual(sentence("lits", vietnamese: false), "lít")
    }
}
