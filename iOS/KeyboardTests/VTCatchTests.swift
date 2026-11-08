import XCTest

/// Crash thật 28/09/2026 (iOS 27.0, build 1.2(7)): UIKit NÉM NSException khi đọc trait
/// của textDocumentProxy lúc chưa sẵn sàng. vtSafe/VTCatchException phải nuốt lỗi.
final class VTCatchTests: XCTestCase {
    func testCatchesObjCException() {
        let e = VTCatchException {
            NSException(name: .invalidArgumentException, reason: "_controllerState", userInfo: nil).raise()
        }
        XCTAssertEqual(e?.name, .invalidArgumentException)
        XCTAssertNil(VTCatchException { _ = 1 + 1 })
    }

    func testSafeReadFallsBackOnException() {
        let v: UIKeyboardType = vtSafe(.default) {
            NSException(name: .invalidArgumentException, reason: "boom", userInfo: nil).raise()
            return .emailAddress
        }
        XCTAssertEqual(v, .default)
        XCTAssertEqual(vtSafe(.default) { UIKeyboardType.emailAddress }, .emailAddress)
    }
}

/// Phím trắng trên nền tối (Phil 28/09/2026): trait sáng lúc mở rồi mới thành tối ⇒
/// controller gọi lại updateDark mỗi lần layout; KeyboardView phải đổi palette ngay.
final class LateDarkTraitTests: XCTestCase {
    @MainActor func testLateDarkTraitSwitchesPalette() {
        let kb = KeyboardView(needsGlobe: false, inputController: nil) { _ in }
        kb.frame = CGRect(x: 0, y: 0, width: 393, height: 260)
        kb.applyAppearance(.default, style: .light)
        XCTAssertFalse(kb.isDarkAppearance)
        kb.updateDark(AppearancePolicy.isDark(appearance: .default, style: .dark))
        XCTAssertTrue(kb.isDarkAppearance)
        kb.updateDark(AppearancePolicy.isDark(appearance: .light, style: .dark))   // host xin sáng: vẫn theo máy (tối)
        XCTAssertTrue(kb.isDarkAppearance)
        kb.updateDark(AppearancePolicy.isDark(appearance: .default, style: .light))
        XCTAssertFalse(kb.isDarkAppearance)
    }
}
