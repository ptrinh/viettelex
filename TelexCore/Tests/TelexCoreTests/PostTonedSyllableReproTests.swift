import XCTest
@testable import TelexCore

/// Tái hiện lỗi: khi gõ xong một từ tiếng Việt đã hoàn chỉnh có dấu (ví dụ `được`),
/// sau đó nhập thêm ký tự `u`, trạng thái hiển thị bị biến đổi bất thường (mất dấu
/// thanh/dấu móc, lộ phím Telex thô `j`, hoặc nhảy thứ tự ký tự) thay vì giữ nguyên
/// phần chữ đã tạo dấu trước đó.
///
/// Chưa áp dụng fix trong `TelexEngine` — chỉ ghi nhận test tái hiện để xác nhận
/// hành vi mong muốn trước.
/// Tham chiếu / chia sẻ từ quá trình đối chiếu hành vi bộ gõ tại:
/// https://github.com/stevedat/VieLotus-IM
final class PostTonedSyllableReproTests: XCTestCase {

    private func configuredEngine() -> TelexEngine {
        var e = TelexEngine()
        e.freeMarking = true
        e.liveSpellCheck = true
        e.teencode = false
        e.contextualEnglish = true
        e.collisionPrefersVietnamese = true
        e.modernTone = false
        return e
    }

    func testTypingUAfterCompletedDuocReproduction() {
        // Các thứ tự phím Telex hợp lệ đều cho ra "được" trước khi gõ thêm "u":
        // - "dduowcj" + "u" -> hiện tại biến thành "đươcju" (mất dấu nặng, lộ phím thô 'j')
        // - "dduowjc" + "u" -> hiện tại biến thành "đươjcu" (mất dấu nặng, 'j' nhảy trước 'c')
        // - "ddujowc" + "u" -> hiện tại biến thành "đujơcu" (mất móc 'ư' -> 'u', mất nặng, 'j' nhảy vào giữa)
        // - "duowcjd" + "u" -> hiện tại biến thành "đươcju" (mất dấu nặng, lộ phím thô 'j')
        let sequences = ["dduowcj", "dduowjc", "ddujowc", "duowcjd"]

        for seq in sequences {
            var e = configuredEngine()
            for ch in seq { _ = e.feed(ch) }
            XCTAssertEqual(e.composed, "được", "Tiền điều kiện: '\(seq)' phải tạo thành 'được'")

            let action = e.feed("u")
            XCTExpectFailure("Chờ xác nhận hướng xử lý khi gõ tiếp 'u' sau từ đã hoàn chỉnh 'được' (\(seq) + u)") {
                XCTAssertEqual(e.composed, "đượcu", "Chuỗi '\(seq)u' bị biến đổi thành '\(e.composed)' (action: \(action))")
            }
        }
    }
}
