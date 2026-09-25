import XCTest
import UIKit

/// Regression 26/09/2026: phím sáng trên nền tối — `.default` phải theo style của host,
/// và style `.unspecified` (view chưa vào window) không được coi là quyết định cuối.
final class AppearancePolicyTests: XCTestCase {
    func testDefaultFollowsHostStyle() {
        XCTAssertTrue(AppearancePolicy.isDark(appearance: .default, style: .dark))
        XCTAssertFalse(AppearancePolicy.isDark(appearance: .default, style: .light))
    }
    func testExplicitAppearanceWins() {
        XCTAssertTrue(AppearancePolicy.isDark(appearance: .dark, style: .light))
        XCTAssertFalse(AppearancePolicy.isDark(appearance: .light, style: .dark))
    }
}
