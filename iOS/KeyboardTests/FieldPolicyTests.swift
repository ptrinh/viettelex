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

/// Regression: ô không khai báo autocapitalization (nil) → ô trống vẫn chữ thường.
final class AutoShiftTests: XCTestCase {
    func testUndeclaredFieldCapitalizesSentenceStart() {
        XCTAssertEqual(FieldPolicy.autoShift(autocap: nil, before: ""), true)
        XCTAssertEqual(FieldPolicy.autoShift(autocap: nil, before: "Xin chào. "), true)
        XCTAssertEqual(FieldPolicy.autoShift(autocap: nil, before: "Xin chào "), false)
    }
    func testNoneLeavesShiftAlone() {
        XCTAssertNil(FieldPolicy.autoShift(autocap: UITextAutocapitalizationType.none, before: ""))
    }
    func testWordsAndAllCharacters() {
        XCTAssertEqual(FieldPolicy.autoShift(autocap: .words, before: "Nguyễn "), true)
        XCTAssertEqual(FieldPolicy.autoShift(autocap: .words, before: "Nguy"), false)
        XCTAssertEqual(FieldPolicy.autoShift(autocap: .allCharacters, before: "AB"), true)
    }
}
