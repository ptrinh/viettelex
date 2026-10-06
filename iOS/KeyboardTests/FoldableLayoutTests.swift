import XCTest
import UIKit

/// Regression (Phil 06/10/2026, simulator "iPhone Duo" iOS 27.1): máy gập MỞ (màn 951×669,
/// view extension 801 rộng, trait regular/regular, safe area đáy 18 = vạch home) ⇒ hàng đáy
/// (123 / emoji / space / , / return) dẹt còn ~12pt chồng lên vùng 🌐/mic: chiều cao lấy kiểu
/// "iPhone ngang" (162) và stack hàng đáy ăn 18pt safe area vào lề dưới. Sửa: dạng bàn phím
/// theo hình học thật (KeyLayout.phoneForm) + hàng phím đặt TRÊN safe area đáy.
/// Các số iPhone 17 / iPhone ngang / iPad cũ được ghim lại — không đổi.
final class FoldableLayoutTests: XCTestCase {
    // Kích thước đo trên simulator (pt).
    private let iPhone17 = CGSize(width: 402, height: 874)
    private let duoFolded = CGSize(width: 466, height: 678)
    private let duoOpen = CGSize(width: 669, height: 951)

    // MARK: Hàm thuần

    func testPhoneFormFromRealGeometry() {
        // iPhone thường: như cũ theo bề ngang view.
        XCTAssertEqual(KeyLayout.phoneForm(viewWidth: 402, screenSize: iPhone17), .portrait)
        XCTAssertEqual(KeyLayout.phoneForm(viewWidth: 874, screenSize: CGSize(width: 874, height: 402)), .landscape)
        XCTAssertEqual(KeyLayout.phoneForm(viewWidth: 440, screenSize: CGSize(width: 440, height: 956)), .portrait)
        XCTAssertEqual(KeyLayout.phoneForm(viewWidth: 750, screenSize: CGSize(width: 956, height: 440)), .landscape)
        // Duo GẬP = một iPhone thường.
        XCTAssertEqual(KeyLayout.phoneForm(viewWidth: 466, screenSize: duoFolded), .portrait)
        XCTAssertEqual(KeyLayout.phoneForm(viewWidth: 678, screenSize: CGSize(width: 678, height: 466)), .landscape)
        // Duo MỞ: cả dọc lẫn ngang, kể cả khi view hẹp hơn màn hình (hệ thống chừa 🌐/mic).
        XCTAssertEqual(KeyLayout.phoneForm(viewWidth: 801, screenSize: CGSize(width: 951, height: 669)), .unfolded)
        XCTAssertEqual(KeyLayout.phoneForm(viewWidth: 669, screenSize: duoOpen), .unfolded)
        // Chưa biết màn hình: trait regular/regular (iPhone thường không bao giờ có) ⇒ mở.
        XCTAssertEqual(KeyLayout.phoneForm(viewWidth: 801, screenSize: nil, regularBoth: true), .unfolded)
        XCTAssertEqual(KeyLayout.phoneForm(viewWidth: 801, screenSize: nil), .landscape)
        XCTAssertEqual(KeyLayout.phoneForm(viewWidth: 0, screenSize: nil, sceneLandscape: true), .landscape)
    }

    /// Ghim số cũ: iPhone dọc 216 (trim 4 ⇒ vùng 212), ngang 162; iPad 240/300 nằm ở view.
    func testKeyAreaBasePinned() {
        XCTAssertEqual(KeyLayout.phoneKeyAreaBase(.portrait), 216)
        XCTAssertEqual(KeyLayout.phoneKeyAreaBase(.portrait), KeyGeometry.phonePortraitBase)
        XCTAssertEqual(KeyLayout.phoneKeyAreaBase(.landscape), 162)
        XCTAssertEqual(KeyLayout.phoneKeyAreaBase(.unfolded), 208)
        XCTAssertEqual(KeyGeometry.bottomRowTrim(pad: false, landscape: false), 4)
        XCTAssertEqual(KeyGeometry.bottomRowTrim(pad: false, landscape: true), 0)
        XCTAssertEqual(KeyGeometry.bottomRowTopMargin(pad: false, landscape: false), 7)
        XCTAssertEqual(KeyGeometry.bottomRowTopMargin(pad: true, landscape: false), 10)
    }

    func testSafeBottomOnlyPhoneAndCapped() {
        XCTAssertEqual(KeyLayout.keyboardSafeBottom(pad: false, viewSafeBottom: 0), 0)    // iPhone 17
        XCTAssertEqual(KeyLayout.keyboardSafeBottom(pad: false, viewSafeBottom: 18), 18)  // Duo mở
        XCTAssertEqual(KeyLayout.keyboardSafeBottom(pad: true, viewSafeBottom: 5), 0)     // iPad: như cũ
        XCTAssertEqual(KeyLayout.keyboardSafeBottom(pad: false, viewSafeBottom: 300), 40) // khung settle
        XCTAssertEqual(KeyLayout.keyboardSafeBottom(pad: false, viewSafeBottom: -3), 0)
    }

    // MARK: View thật

    @MainActor private func makeKeyboard(width: CGFloat, screen: CGSize?, safeBottom: CGFloat = 0)
        -> (KeyboardView, UIView) {
        let kb = KeyboardView(needsGlobe: false, inputController: nil) { _ in }
        let host = UIView(frame: CGRect(x: 0, y: 0, width: width, height: 500))
        host.addSubview(kb)
        kb.frame = CGRect(x: 0, y: 0, width: width, height: 300)
        kb.debugScreenSize = screen
        kb.configureInputKind(.normal)
        kb.setSuggestionsEnabled(true)
        kb.debugSetSafeBottom(safeBottom)
        kb.layoutIfNeeded()
        kb.frame.size.height = kb.debugRequestedHeight     // host cấp đúng mức xin
        kb.setNeedsLayout(); kb.layoutIfNeeded()
        return (kb, host)
    }

    private func frame(_ kb: KeyboardView, _ v: UIView) -> CGRect { kb.convert(v.bounds, from: v) }

    /// Bug chính: Duo mở — hàng đáy phải cao như hàng chữ và nằm TRÊN dải safe area 18pt.
    @MainActor func testUnfoldedBottomRowNotSquashed() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom == .pad)
        let (kb, _) = makeKeyboard(width: 801, screen: CGSize(width: 951, height: 669), safeBottom: 18)
        let q = try XCTUnwrap(kb.debugLetterFrame("q"))
        let num = frame(kb, try XCTUnwrap(kb.debugControl("Số")))
        let space = frame(kb, try XCTUnwrap(kb.debugControl("Dấu cách")))
        let ret = frame(kb, try XCTUnwrap(kb.debugControl("Xuống dòng")))
        XCTAssertEqual(q.height, 208 / 4 - KeyGeometry.rowGap, accuracy: 0.5)     // 42
        for f in [num, space, ret] {
            XCTAssertEqual(f.height, q.height, accuracy: 0.5, "hàng đáy cao bằng hàng chữ")
            XCTAssertLessThanOrEqual(f.maxY, kb.bounds.height - 18 + 0.5, "không lấn vạch home")
        }
        // Tổng xin = strip + vùng phím 208 + safe 18.
        XCTAssertEqual(kb.debugRequestedHeight, Self.strip + 208 + 18, accuracy: 0.5)
    }

    /// Cũ: Duo mở lấy hình học iPhone NGANG (phím 30pt). Không màn hình (test) ⇒ vẫn ngang.
    @MainActor func testUnfoldedTallerThanPhoneLandscape() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom == .pad)
        let (open, _) = makeKeyboard(width: 801, screen: CGSize(width: 951, height: 669))
        let (land, _) = makeKeyboard(width: 801, screen: CGSize(width: 874, height: 402))
        XCTAssertEqual(try XCTUnwrap(land.debugLetterFrame("q")).height, 162 / 4 - 10, accuracy: 0.5)
        XCTAssertEqual(try XCTUnwrap(open.debugLetterFrame("q")).height, 208 / 4 - 10, accuracy: 0.5)
    }

    /// Ghim iPhone 17 dọc / ngang: safe area 0 ⇒ y hệt trước (chiều cao xin, hàng đáy sát đáy).
    @MainActor func testIPhoneNumbersUnchanged() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom == .pad)
        let (p, _) = makeKeyboard(width: 402, screen: iPhone17)
        XCTAssertEqual(p.debugRequestedHeight, Self.strip + 212, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(p.debugLetterFrame("q")).height, 44, accuracy: 0.5)
        let pn = frame(p, try XCTUnwrap(p.debugControl("Số")))
        XCTAssertEqual(pn.height, 43, accuracy: 0.5)
        XCTAssertEqual(pn.maxY, p.bounds.height, accuracy: 0.5)
        let (l, _) = makeKeyboard(width: 874, screen: CGSize(width: 874, height: 402))
        XCTAssertEqual(l.debugRequestedHeight, Self.strip + 162, accuracy: 0.01)
        let ln = frame(l, try XCTUnwrap(l.debugControl("Số")))
        XCTAssertEqual(ln.height, 162 / 4 - 10, accuracy: 0.5)
        XCTAssertEqual(ln.maxY, l.bounds.height, accuracy: 0.5)
        // Duo gập = iPhone dọc.
        let (f, _) = makeKeyboard(width: 466, screen: duoFolded)
        XCTAssertEqual(f.debugRequestedHeight, Self.strip + 212, accuracy: 0.01)
    }

    /// Gập ⇄ mở trên cùng một view: hình học đổi theo bề ngang mới, không kẹt dạng cũ.
    @MainActor func testFoldUnfoldSwitchesForm() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom == .pad)
        let (kb, _) = makeKeyboard(width: 466, screen: duoFolded)
        XCTAssertEqual(kb.debugRequestedHeight, Self.strip + 212, accuracy: 0.01)
        kb.debugScreenSize = CGSize(width: 951, height: 669)
        kb.frame.size.width = 801
        kb.debugSetSafeBottom(18)
        kb.setNeedsLayout(); kb.layoutIfNeeded()
        XCTAssertEqual(kb.debugRequestedHeight, Self.strip + 208 + 18, accuracy: 0.01)
        kb.debugScreenSize = duoFolded
        kb.frame.size.width = 466
        kb.debugSetSafeBottom(0)
        kb.setNeedsLayout(); kb.layoutIfNeeded()
        XCTAssertEqual(kb.debugRequestedHeight, Self.strip + 212, accuracy: 0.01)
    }

    /// Bug 2 (Phil 06/10/2026, ảnh #63): Duo GẬP + xoay NGANG (màn 678×466, view 528, safe đáy 18)
    /// — hàng đáy vẫn dẹt khi xoay lúc bàn phím đang hiện: stack hàng iPhone còn
    /// insetsLayoutMarginsFromSafeArea = true ⇒ safe area lọt vào lề trước khi safeBottom kịp đổi.
    @MainActor func testFoldedLandscapeBottomRowNotSquashed() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom == .pad)
        let (kb, _) = makeKeyboard(width: 528, screen: CGSize(width: 678, height: 466), safeBottom: 18)
        let q = try XCTUnwrap(kb.debugLetterFrame("q"))
        for name in ["Số", "Dấu cách", "Xuống dòng"] {
            let f = frame(kb, try XCTUnwrap(kb.debugControl(name)))
            XCTAssertEqual(f.height, q.height, accuracy: 0.5, "\(name) cao bằng hàng chữ")
            XCTAssertLessThanOrEqual(f.maxY, kb.bounds.height - 18 + 0.5)
        }
        XCTAssertEqual(kb.debugRequestedHeight, Self.strip + 162 + 18, accuracy: 0.5)
    }

    /// Không stack hàng phím nào (chữ, số, tách đôi) được tự ăn safe area vào lề — safe area
    /// chỉ đi qua safeBottom, nên lỡ một nhịp cập nhật cũng không ép dẹt hàng đáy.
    @MainActor func testRowStacksIgnoreSafeAreaMargins() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom == .pad)
        for split in [false, true] {
            let (kb, _) = makeKeyboard(width: 801, screen: CGSize(width: 951, height: 669), safeBottom: 18)
            kb.debugSetSplit(split)
            kb.setNeedsLayout(); kb.layoutIfNeeded()
            let rows = kb.debugRowStacks
            XCTAssertFalse(rows.isEmpty)
            for r in rows { XCTAssertFalse(r.insetsLayoutMarginsFromSafeArea, "split=\(split)") }
        }
    }

    private static var strip: CGFloat { KeyboardView.openStrip }
}
