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
