import XCTest
import UIKit

/// Regression 26/09/2026: về plane chữ từ planeCache (vd. sau mẫu câu / 123) mất
/// ràng buộc GIỮA các hàng (UIKit tự gỡ khi row rời hierarchy) → phím lệch cỡ.
final class PlaneCacheLayoutTests: XCTestCase {
    @MainActor func testCrossRowWidthsSurvivePlaneCache() throws {
        let kb = KeyboardView(needsGlobe: false, inputController: nil, onKey: { _ in })
        let w: CGFloat = UIDevice.current.userInterfaceIdiom == .pad ? 834 : 390
        let host = UIView(frame: CGRect(x: 0, y: 0, width: w, height: 320))
        host.addSubview(kb)
        kb.frame = host.bounds
        kb.layoutIfNeeded()
        let q0 = try XCTUnwrap(kb.debugLetterFrame("q"))
        let z0 = try XCTUnwrap(kb.debugLetterFrame("z"))
        XCTAssertEqual(z0.width, q0.width, accuracy: 0.5)

        kb.debugCycleThroughNumbers()
        kb.layoutIfNeeded()
        kb.debugCycleThroughTemplates()
        kb.setNeedsLayout(); kb.layoutIfNeeded()
        let q1 = try XCTUnwrap(kb.debugLetterFrame("q"))
        let z1 = try XCTUnwrap(kb.debugLetterFrame("z"))
        XCTAssertEqual(z1.width, q1.width, accuracy: 0.5)
        XCTAssertEqual(z1.width, z0.width, accuracy: 0.5)
        // Hàng 2 (iPad: caps 1.67q + a…l + return co giãn) — lệch rõ nhất khi mất neo.
        let a1 = try XCTUnwrap(kb.debugLetterFrame("a"))
        XCTAssertEqual(a1.width, q1.width, accuracy: 0.5)
    }
}
