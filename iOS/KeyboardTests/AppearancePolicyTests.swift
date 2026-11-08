import XCTest
import UIKit

/// Regression 26/09/2026: phím sáng trên nền tối — `.default` phải theo style của host,
/// và style `.unspecified` (view chưa vào window) không được coi là quyết định cuối.
final class AppearancePolicyTests: XCTestCase {
    func testDefaultFollowsHostStyle() {
        XCTAssertTrue(AppearancePolicy.isDark(appearance: .default, style: .dark))
        XCTAssertFalse(AppearancePolicy.isDark(appearance: .default, style: .light))
    }
    /// Phil 08/11/2026: luôn theo chế độ của máy — app/ô xin .light/.dark KHÔNG đổi bảng màu theme.
    func testFieldAppearanceIgnoredFollowsDevice() {
        XCTAssertFalse(AppearancePolicy.isDark(appearance: .dark, style: .light))
        XCTAssertTrue(AppearancePolicy.isDark(appearance: .light, style: .dark))
    }

    /// Bug Phil 19/10/2026 (chập chờn): nền + thanh gợi ý tối nhưng phím sáng. MỌI chỗ phải ra cùng một
    /// kết quả từ cùng đầu vào — appearance của ô thắng; .default theo trait view (chưa vào window ⇒
    /// trait controller).
    func testPresentationDarkSingleSource() {
        typealias P = AppearancePolicy
        XCTAssertTrue(P.presentationDark(fieldAppearance: .default, viewStyle: .dark, controllerStyle: .light))
        XCTAssertFalse(P.presentationDark(fieldAppearance: .default, viewStyle: .light, controllerStyle: .dark))
        XCTAssertTrue(P.presentationDark(fieldAppearance: .default, viewStyle: .unspecified, controllerStyle: .dark))
        XCTAssertTrue(P.presentationDark(fieldAppearance: nil, viewStyle: .unspecified, controllerStyle: .dark))
        XCTAssertTrue(P.presentationDark(fieldAppearance: .light, viewStyle: .dark, controllerStyle: .dark))
        XCTAssertFalse(P.presentationDark(fieldAppearance: .dark, viewStyle: .light, controllerStyle: .light))
        for a in [UIKeyboardAppearance.default, .light, .dark] {
            for v in [UIUserInterfaceStyle.unspecified, .light, .dark] {
                for c in [UIUserInterfaceStyle.light, .dark] {
                    XCTAssertEqual(P.presentationDark(fieldAppearance: a, viewStyle: v, controllerStyle: c),
                                   P.isDark(appearance: a, style: v == .unspecified ? c : v))
                }
            }
        }
    }
}
