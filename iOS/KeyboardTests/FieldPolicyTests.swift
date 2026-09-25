import XCTest

/// Regression: không gõ được tiếng Việt ở thanh địa chỉ Safari/Chrome và Spotlight
/// (ô tìm kiếm tắt autocorrect) — passthrough không còn dựa vào autocorrect.
final class FieldPolicyTests: XCTestCase {
    func testSearchFieldsKeepTelex() {
        XCTAssertFalse(FieldPolicy.passthrough(keyboardType: .webSearch, contentType: nil))
        XCTAssertFalse(FieldPolicy.passthrough(keyboardType: .default, contentType: nil))
    }
    func testLiteralFields() {
        XCTAssertTrue(FieldPolicy.passthrough(keyboardType: .emailAddress, contentType: nil))
        XCTAssertTrue(FieldPolicy.passthrough(keyboardType: .URL, contentType: nil))
        XCTAssertTrue(FieldPolicy.passthrough(keyboardType: .default, contentType: .username))
        XCTAssertTrue(FieldPolicy.passthrough(keyboardType: .default, contentType: .oneTimeCode))
    }
}
