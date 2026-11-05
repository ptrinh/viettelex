import XCTest
import UIKit

/// Chế độ một tay (27/09/2026): thu hẹp 0.82 bề ngang, dồn trái/phải, rail đổi bên/thoát.
/// Mọi hình học phím (router, gõ vuốt, hàng số, planeCache) phải theo vùng hẹp.
final class OneHandTests: XCTestCase {
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    private let w: CGFloat = 390

    // MARK: thuần

    func testInsetsAndRail() {
        XCTAssertEqual(OneHand.insets(width: 400, side: .off).left, 0)
        let l = OneHand.insets(width: 400, side: .left)
        XCTAssertEqual(l.left, 0); XCTAssertEqual(l.right, 400 * (1 - OneHand.ratio), accuracy: 0.001)
        let r = OneHand.insets(width: 400, side: .right)
        XCTAssertEqual(r.left, 400 * (1 - OneHand.ratio), accuracy: 0.001); XCTAssertEqual(r.right, 0)
        XCTAssertNil(OneHand.rail(width: 400, side: .off))
        XCTAssertEqual(OneHand.rail(width: 400, side: .left)!.x, 400 * OneHand.ratio, accuracy: 0.001)
        XCTAssertEqual(OneHand.rail(width: 400, side: .right)!.x, 0)
        XCTAssertEqual(OneHand.rail(width: 400, side: .right)!.width, 400 * (1 - OneHand.ratio), accuracy: 0.001)
    }

    func testToggleSwitchResolve() {
        XCTAssertEqual(OneHandSide.left.switched, .right)
        XCTAssertEqual(OneHandSide.off.switched, .off)
        XCTAssertEqual(OneHand.toggled(.off), .right)
        XCTAssertEqual(OneHand.toggled(.off, preferred: .left), .left)
        XCTAssertEqual(OneHand.toggled(.right), .off)
        // App vừa đổi (group ≠ đã thấy) ⇒ theo app.
        XCTAssertEqual(OneHand.resolve(group: "left", seenGroup: nil, local: "right"), .left)
        XCTAssertEqual(OneHand.resolve(group: "off", seenGroup: "left", local: "right"), .off)
        // App không đổi ⇒ trạng thái bàn phím tự lưu thắng.
        XCTAssertEqual(OneHand.resolve(group: "left", seenGroup: "left", local: "off"), .off)
        XCTAssertEqual(OneHand.resolve(group: nil, seenGroup: nil, local: "right"), .right)
        XCTAssertEqual(OneHand.resolve(group: nil, seenGroup: nil, local: nil), .off)
        XCTAssertEqual(OneHand.resolve(group: "junk", seenGroup: nil, local: nil), .off)
    }

    // MARK: hình học trên KeyboardView thật

    @MainActor private func makeKeyboard(_ side: OneHandSide, numberRow: Bool = false,
                                         onKey: @escaping (KeyboardView.Key) -> Void = { _ in })
        -> (KeyboardView, UIView) {
        let kb = KeyboardView(needsGlobe: false, inputController: nil, onKey: onKey)
        let host = UIView(frame: CGRect(x: 0, y: 0, width: w, height: 320))
        host.addSubview(kb)
        kb.frame = host.bounds
        kb.numberRowEnabled = numberRow
        kb.configureOneHand(side)
        kb.setNeedsLayout(); kb.layoutIfNeeded()
        return (kb, host)
    }

    private func span(_ side: OneHandSide) -> (x0: CGFloat, width: CGFloat) {
        let i = OneHand.insets(width: w, side: side)
        return (i.left, w - i.left - i.right)
    }

    @MainActor private func assertNarrowed(_ kb: KeyboardView, _ side: OneHandSide,
                                           file: StaticString = #filePath, line: UInt = #line) throws {
        let (x0, sw) = span(side)
        for r in kb.debugRowFrames() {
            XCTAssertEqual(r.minX, x0, accuracy: 0.5, file: file, line: line)
            XCTAssertEqual(r.width, sw, accuracy: 0.5, file: file, line: line)
        }
        for ch in "qwertyuiopasdfghjklzxcvbnm" {
            let f = try XCTUnwrap(kb.debugLetterFrame(String(ch)), file: file, line: line)
            XCTAssertGreaterThanOrEqual(f.minX, x0 - 0.5, "\(ch)", file: file, line: line)
            XCTAssertLessThanOrEqual(f.maxX, x0 + sw + 0.5, "\(ch)", file: file, line: line)
        }
        let q = try XCTUnwrap(kb.debugLetterFrame("q"))
        let p = try XCTUnwrap(kb.debugLetterFrame("p"))
        let a = try XCTUnwrap(kb.debugLetterFrame("a"))
        let z = try XCTUnwrap(kb.debugLetterFrame("z"))
        XCTAssertEqual(q.minX, x0 + KeyGeometry.sideMargin(pad: isPad), accuracy: 0.5, file: file, line: line)
        XCTAssertEqual(p.maxX, x0 + sw - KeyGeometry.sideMargin(pad: isPad), accuracy: 0.5, file: file, line: line)
        XCTAssertEqual(a.width, q.width, accuracy: 0.5, file: file, line: line)
        XCTAssertEqual(z.width, q.width, accuracy: 0.5, file: file, line: line)
        // Hàng 2 thụt nửa phím THEO VÙNG HẸP (không theo cả view).
        XCTAssertEqual(a.minX, x0 + KeyGeometry.indentedMargin(width: sw, margin: KeyGeometry.sideMargin(pad: isPad), gap: 6, units: 0.5), accuracy: 0.5, file: file, line: line)
    }

    @MainActor func testLettersNarrowToEachSide() throws {
        guard !isPad else { return }
        for side in [OneHandSide.left, .right] {
            let (kb, _) = makeKeyboard(side)
            try assertNarrowed(kb, side)
        }
    }

    /// Tìm emoji thuộc họ emoji: ô tìm + chữ đầy bề ngang, không rail (Android y hệt).
    @MainActor func testEmojiSearchStaysFullWidth() throws {
        guard !isPad else { return }
        let (kb, _) = makeKeyboard(.right)
        _ = kb.debugEmojiSearch([])
        kb.setNeedsLayout(); kb.layoutIfNeeded()
        XCTAssertEqual(try XCTUnwrap(kb.debugLetterFrame("q")).minX, KeyGeometry.sideMargin(pad: isPad), accuracy: 0.5)
        XCTAssertTrue(kb.debugRailFrames().isEmpty)
        for r in kb.debugRowFrames() { XCTAssertEqual(r.width, w, accuracy: 0.5) }
    }

    @MainActor func testOffKeepsFullWidth() throws {
        let (kb, _) = makeKeyboard(.off)
        let q = try XCTUnwrap(kb.debugLetterFrame("q"))
        // iPad: hàng 1 bắt đầu bằng Tab nên q không nằm sát lề — chỉ iPhone so lề.
        if !isPad { XCTAssertEqual(q.minX, KeyGeometry.sideMargin(pad: false), accuracy: 0.5) }
        XCTAssertTrue(kb.debugRailFrames().isEmpty)
    }

    /// Router: chạm tâm phím chữ trong vùng hẹp ra đúng chữ (qua đường routeDown thật).
    @MainActor func testRouterTypesNarrowedLetters() throws {
        guard !isPad else { return }
        for side in [OneHandSide.left, .right] {
            var got: [Character] = []
            let (kb, _) = makeKeyboard(side, onKey: { if case .letter(let c) = $0 { got.append(c) } })
            var t: TimeInterval = 100
            for ch in "qalpzm" {
                let f = try XCTUnwrap(kb.debugLetterFrame(String(ch)))
                let pt = CGPoint(x: f.midX, y: f.midY + TouchGeometry.yOffset)
                XCTAssertTrue(kb.hitTest(pt, with: nil) === kb, "\(side) \(ch)")
                kb.debugTouch(from: pt, through: [pt], start: t)
                t += 1
            }
            XCTAssertEqual(String(got).lowercased(), "qalpzm", "\(side)")
        }
    }

    /// Rail: 2 nút trong dải trống; chạm trúng button (không bị router cướp); đổi bên / thoát.
    @MainActor func testRailSwitchesAndExits() throws {
        guard !isPad else { return }
        var saved: [OneHandSide] = []
        let (kb, _) = makeKeyboard(.right)
        kb.onOneHandChange = { saved.append($0) }
        let rail = try XCTUnwrap(OneHand.rail(width: w, side: .right))
        let frames = kb.debugRailFrames()
        XCTAssertEqual(frames.count, 2)
        for f in frames {
            XCTAssertGreaterThanOrEqual(f.minX, rail.x - 0.5)
            XCTAssertLessThanOrEqual(f.maxX, rail.x + rail.width + 0.5)
            XCTAssertTrue(kb.hitTest(CGPoint(x: f.midX, y: f.midY), with: nil) is KeyboardView.KeyButton)
        }
        kb.debugTapRail(0)
        kb.layoutIfNeeded()
        XCTAssertEqual(kb.oneHand, .left)
        try assertNarrowed(kb, .left)
        kb.debugTapRail(1)
        kb.layoutIfNeeded()
        XCTAssertEqual(kb.oneHand, .off)
        XCTAssertEqual(saved, [.left, .off])
        XCTAssertEqual(try XCTUnwrap(kb.debugLetterFrame("q")).minX, KeyGeometry.sideMargin(pad: isPad), accuracy: 0.5)
        XCTAssertTrue(kb.debugRailFrames().isEmpty)
    }

    /// Gõ vuốt lấy tâm phím THẬT: dời theo vùng hẹp, bước phím co theo tỉ lệ.
    @MainActor func testSwipeLayoutFollowsNarrowedKeys() throws {
        guard !isPad else { return }
        let (full, _) = makeKeyboard(.off)
        let (kb, _) = makeKeyboard(.right)
        let lf = try XCTUnwrap(full.swipeLayout())
        let l = try XCTUnwrap(kb.swipeLayout())
        XCTAssertEqual(l.keyWidth, lf.keyWidth * Float(OneHand.ratio), accuracy: 1.5)
        for ch in "qmhz" {
            let f = try XCTUnwrap(kb.debugLetterFrame(String(ch)))
            let i = Int(ch.asciiValue! - Character("a").asciiValue!)
            XCTAssertEqual(CGFloat(l.centers[2 * i]), f.midX, accuracy: 0.5)
            XCTAssertEqual(CGFloat(l.centers[2 * i + 1]), f.midY, accuracy: 0.5)
            XCTAssertGreaterThan(CGFloat(l.centers[2 * i]), span(.right).x0)
        }
    }

    /// Hàng số + một tay cùng lúc: 5 hàng trong vùng hẹp, 1 thẳng cột q.
    @MainActor func testNumberRowWithOneHand() throws {
        guard !isPad else { return }
        let (kb, _) = makeKeyboard(.left, numberRow: true)
        XCTAssertEqual(kb.debugRowFrames().count, 5)
        try assertNarrowed(kb, .left)
        let one = try XCTUnwrap(kb.debugKeyButton("1"))
        let f = kb.convert(one.bounds, from: one)
        let q = try XCTUnwrap(kb.debugLetterFrame("q"))
        XCTAssertEqual(f.midX, q.midX, accuracy: 0.5)
        XCTAssertLessThanOrEqual(f.maxX, span(.left).width + 0.5)
    }

    /// Tổ hợp tích hợp: hàng số (VNI tự bật) + một tay + tìm emoji.
    /// Chữ thu hẹp 5 hàng → tìm emoji đầy bề ngang (ô tìm + 5 hàng) → về chữ vẫn thu hẹp
    /// đúng (planeCache + ràng buộc chéo hàng còn).
    @MainActor func testNumberRowOneHandEmojiSearch() throws {
        guard !isPad else { return }
        let (kb, _) = makeKeyboard(.right, numberRow: true)
        kb.textToolsEnabled = true
        try assertNarrowed(kb, .right)
        XCTAssertEqual(kb.debugRowFrames().count, 5)
        _ = kb.debugEmojiSearch([])
        kb.setNeedsLayout(); kb.layoutIfNeeded()
        XCTAssertEqual(kb.debugRowFrames().count, 6)                 // ô tìm + hàng số + 4 hàng chữ
        for r in kb.debugRowFrames() { XCTAssertEqual(r.width, w, accuracy: 0.5) }
        let rows = kb.debugRowFrames()
        // Ô tìm cao cố định (KeyLayout.emojiSearchBarHeight), KHÔNG chia keyArea với hàng chữ
        // (29/09/2026: trước bằng một hàng chữ ⇒ phím bị ép).
        XCTAssertEqual(rows[0].height, KeyLayout.emojiSearchBarHeight(strip: 0), accuracy: 0.5)  // không bật gợi ý: strip 0
        XCTAssertTrue(kb.debugRailFrames().isEmpty)
        kb.debugSetPlane(numbers: false)
        kb.setNeedsLayout(); kb.layoutIfNeeded()
        XCTAssertEqual(kb.debugRowFrames().count, 5)
        try assertNarrowed(kb, .right)
    }

    /// Về từ planeCache (123 / mẫu câu đầy bề ngang) vẫn thu hẹp đúng, ràng buộc chéo hàng còn.
    @MainActor func testSurvivesPlaneCacheAndTemplates() throws {
        guard !isPad else { return }
        let (kb, _) = makeKeyboard(.right)
        kb.debugCycleThroughNumbers()
        kb.layoutIfNeeded()
        try assertNarrowed(kb, .right)
        kb.debugCycleThroughTemplates()
        kb.setNeedsLayout(); kb.layoutIfNeeded()
        try assertNarrowed(kb, .right)
    }

    @MainActor func testPlaneNumbersNarrowedToo() {
        guard !isPad else { return }
        let (kb, _) = makeKeyboard(.left)
        kb.debugSetPlane(numbers: true)
        kb.layoutIfNeeded()
        let (x0, sw) = span(.left)
        for r in kb.debugRowFrames() {
            XCTAssertEqual(r.minX, x0, accuracy: 0.5)
            XCTAssertEqual(r.width, sw, accuracy: 0.5)
        }
        XCTAssertEqual(kb.debugRailFrames().count, 2)
    }

    /// Bảng sửa văn bản đã bỏ — giữ lâu burger là lối bật/tắt một tay trên bàn phím.
    @MainActor func testHoldBurgerTogglesAndIPadIgnores() {
        let (kb, _) = makeKeyboard(.off)
        kb.lastOneHandSide = .left
        kb.debugHoldBurger()
        XCTAssertEqual(kb.oneHand, isPad ? .off : .left)
        kb.debugHoldBurger()
        XCTAssertEqual(kb.oneHand, .off)
    }
}
