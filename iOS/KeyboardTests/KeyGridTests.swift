import XCTest
import UIKit

/// Lưới phím xếp tay (KeyGrid.swift) thay UIStackView + Auto Layout: các luật bề rộng / chiều
/// cao / thang ưu tiên vùng hàng phải cho ĐÚNG khung bản stack cũ (số đo bản cũ ghi ở từng test).
final class KeyGridTests: XCTestCase {
    typealias W = KeyRowLayout.Width

    // MARK: bề rộng trong hàng

    func testEqualKeysFillRow() {
        // Hàng q…p 390pt: lề 6.67, khe 6 ⇒ phím (390 − 13.34 − 54) / 10.
        let w = KeyRowLayout.widths(Array(repeating: W.equal, count: 10), rowWidth: 390,
                                    inner: 390 - 13.34, spacing: 54, ref: nil)
        for x in w { XCTAssertEqual(x, 32.266, accuracy: 0.001) }
    }

    func testThirdRowLettersFollowAnchorAndShiftBackShareRest() {
        // ⇧ z…m ⌫: chữ = q (neo), ⇧ = ⌫ chia đôi phần còn lại (khe ⇧↔z, m↔⌫ = 12).
        let q: CGFloat = 32.266
        let items: [W] = [.flex] + Array(repeating: .units(1), count: 7) + [.flex]
        let spacing: CGFloat = 6 * 6 + 2 * 12
        let w = KeyRowLayout.widths(items, rowWidth: 390, inner: 390 - 13.34, spacing: spacing, ref: q)
        XCTAssertEqual(w[1], q, accuracy: 0.0001)
        XCTAssertEqual(w[0], w[8], accuracy: 0.0001)
        XCTAssertEqual(w.reduce(0, +) + spacing, 390 - 13.34, accuracy: 0.0001)
    }

    func testBottomRowFractionsOfWholeRowAndSpaceTakesRest() {
        // [123 .108][😊 .108][space][, .071][return .156] — phần của CẢ hàng (kể cả lề) như
        // widthAnchor(equalTo: stack.widthAnchor, multiplier:) cũ.
        let items: [W] = [.fraction(0.108), .fraction(0.108), .flex, .fraction(0.071), .fraction(0.156)]
        let w = KeyRowLayout.widths(items, rowWidth: 390, inner: 390 - 13.34, spacing: 24, ref: nil)
        XCTAssertEqual(w[0], 42.12, accuracy: 0.001)
        XCTAssertEqual(w[2], 390 - 13.34 - 24 - 390 * (0.108 * 2 + 0.071 + 0.156), accuracy: 0.001)
    }

    func testPadAnchorRowDefinesKeyWidth() {
        // iPad 834 hàng neo [tab 1.31] q…p [⌫ 1.31]: lề 3, khe 10 ⇒ q = (834 − 6 − 110) / 12.62.
        let items: [W] = [.units(1.31)] + Array(repeating: .units(1), count: 10) + [.units(1.31)]
        let q = KeyRowLayout.anchorWidth(items, rowWidth: 834, inner: 828, spacing: 110)
        XCTAssertEqual(q, 718 / 12.62, accuracy: 0.0001)
        // Hàng có một phím co giãn: phần còn lại cho nó.
        let r2: [W] = [.units(1.67)] + Array(repeating: .units(1), count: 9) + [.flex]
        let w = KeyRowLayout.widths(r2, rowWidth: 834, inner: 828, spacing: 100, ref: q)
        XCTAssertEqual(w.last!, 728 - 10.67 * q, accuracy: 0.0001)
    }

    /// Hàng 3 bàn số iPhone (.fillProportionally cũ): #+= và 5 dấu bằng nhau theo phần nội dung,
    /// ⌫ nhận phần còn lại — đo bản UIStackView: 390 ⇒ 47.55 / 55.40.
    func testProportionalRowMatchesStackView() {
        let intrinsic: [CGFloat] = [30, 30, 30, 30, 30, 30, 21.6667]
        let group = [0, -1, -1, -1, -1, -1, 6]
        let minimum: [CGFloat] = [0, 0, 0, 0, 0, 0, 42]
        let inner: CGFloat = 390 - 13.3333
        let w = KeyRowLayout.proportional(intrinsic: intrinsic, group: group, minimum: minimum,
                                          inner: inner, spacing: 36)
        XCTAssertEqual(w[0], 47.545, accuracy: 0.01)
        XCTAssertEqual(w[1], 47.545, accuracy: 0.01)
        XCTAssertEqual(w[6], 55.40, accuracy: 0.02)
        // Một tay (hàng hẹp): ⌫ chạm sàn 42 ⇒ dấu co lại, #+= giữ phần của nó (38.67 / 37.93 / 42).
        let narrow = KeyRowLayout.proportional(intrinsic: intrinsic, group: group, minimum: minimum,
                                               inner: 306.33, spacing: 36)
        XCTAssertEqual(narrow[0], 38.67, accuracy: 0.01)
        XCTAssertEqual(narrow[1], 37.93, accuracy: 0.01)
        XCTAssertEqual(narrow[6], 42, accuracy: 0.0001)
    }

    // MARK: chiều cao hàng

    func testRowHeightsWithTrimAndNumberRow() {
        // 4 hàng, hàng đáy cắt 4: 212 ⇒ 54 / 54 / 54 / 50.
        XCTAssertEqual(KeyRowLayout.heights(total: 212, count: 4, spec: .ref(numberRow: nil, trim: 4), header: nil),
                       [54, 54, 54, 50])
        // Hàng số = 0.8·r + 2.2 (khe 11): tổng giữ đúng.
        let num = KeyRowLayout.Heights.NumberRow(multiplier: 0.8, constant: 2.2)
        let h = KeyRowLayout.heights(total: 257.4, count: 5, spec: .ref(numberRow: num, trim: 4), header: nil)
        XCTAssertEqual(h.reduce(0, +), 257.4, accuracy: 0.0001)
        XCTAssertEqual(h[0], 0.8 * h[1] + 2.2, accuracy: 0.0001)
        XCTAssertEqual(h[4], h[1] - 4, accuracy: 0.0001)
        // Ô tìm emoji: hàng đầu cố định, hàng chữ chia phần còn lại.
        let e = KeyRowLayout.heights(total: 300, count: 4, spec: .equal, header: 60)
        XCTAssertEqual(e, [60, 60, 60, 60, 60])
    }

    // MARK: thang ưu tiên vùng hàng (thay constraint rows ↔ view)

    func testRowsAreaPriorityLadder() {
        // Host cấp đúng: đỉnh = strip, cao = rows.
        var a = KeyRowLayout.rowsArea(viewHeight: 247, bottomInset: 0, top: 35, rows: 212, minTop: 2)
        XCTAssertEqual(a.top, 35); XCTAssertEqual(a.height, 212)
        // Host cấp dư 25: phím hấp thụ (đỉnh giữ strip @997 hơn cao = rows @900).
        a = KeyRowLayout.rowsArea(viewHeight: 272, bottomInset: 0, top: 35, rows: 212, minTop: 2)
        XCTAssertEqual(a.top, 35); XCTAssertEqual(a.height, 237)
        // Dư quá trần +60: phần dư tràn lên trên.
        a = KeyRowLayout.rowsArea(viewHeight: 400, bottomInset: 0, top: 35, rows: 212, minTop: 2)
        XCTAssertEqual(a.height, 272); XCTAssertEqual(a.top, 128)
        // Cấp thiếu: strip nhường trước (cao ≥ rows @998), tới sàn đỉnh (@999) phím mới co.
        a = KeyRowLayout.rowsArea(viewHeight: 230, bottomInset: 0, top: 35, rows: 212, minTop: 2)
        XCTAssertEqual(a.height, 212); XCTAssertEqual(a.top, 18)
        a = KeyRowLayout.rowsArea(viewHeight: 120, bottomInset: 0, top: 35, rows: 212, minTop: 2)
        XCTAssertEqual(a.top, 2); XCTAssertEqual(a.height, 118)
        // Safe area / nâng bàn phím: đáy cách đáy view.
        a = KeyRowLayout.rowsArea(viewHeight: 265, bottomInset: 18, top: 35, rows: 212, minTop: 2)
        XCTAssertEqual(a.top + a.height, 247)
    }

    func testPixelRoundingOfEdges() {
        // Từng mép làm tròn riêng (khung 83.2 / 32.267 @3x ⇒ 83.33 / 32.0 như Auto Layout).
        let r = KeyRowLayout.rounded(x0: 83.2, x1: 115.467, y0: 0, y1: 43, scale: 3)
        XCTAssertEqual(r.minX, 250.0 / 3, accuracy: 1e-9)
        XCTAssertEqual(r.width, 32, accuracy: 1e-9)
        // Nửa pixel (kể cả sai số cộng dồn) làm tròn lên.
        XCTAssertEqual(KeyRowLayout.px(794.4999999, 3), 2384.0 / 3, accuracy: 1e-9)
    }

    // MARK: phím (UIControl thay UIButton)

    @MainActor func testKeyButtonIsAccessibleLikeUIButton() {
        let b = KeyboardView.KeyButton()
        b.setTitle("q", for: .normal)
        XCTAssertTrue(b.isAccessibilityElement)
        XCTAssertEqual(b.accessibilityLabel, "q")
        XCTAssertTrue(b.accessibilityTraits.contains(.button))
        b.accessibilityLabel = "Shift"
        XCTAssertEqual(b.accessibilityLabel, "Shift")
    }

    /// Như UIButton (custom): icon sẫm lại khi đè nếu không có ảnh đè riêng; có ảnh đè thì dùng nó.
    @MainActor func testIconDimsWhenHighlightedLikeUIButton() throws {
        let b = KeyboardView.KeyButton(frame: CGRect(x: 0, y: 0, width: 61, height: 43))
        b.tintColor = .white
        b.setImage(UIImage(systemName: "shift"), for: .normal)
        b.layoutIfNeeded()
        let iv = try XCTUnwrap(b.imageView)
        b.isHighlighted = true
        var w: CGFloat = 0, a: CGFloat = 0
        XCTAssertTrue(iv.tintColor.getWhite(&w, alpha: &a))
        XCTAssertEqual(w, 8.0 / 15, accuracy: 0.01)
        b.isHighlighted = false
        XCTAssertTrue(iv.tintColor.getWhite(&w, alpha: &a))
        XCTAssertEqual(w, 1, accuracy: 0.001)
        let fill = UIImage(systemName: "delete.left.fill")
        b.setImage(fill, for: .highlighted)
        b.isHighlighted = true
        XCTAssertTrue(iv.image === fill)
        XCTAssertTrue(iv.tintColor.getWhite(&w, alpha: &a))
        XCTAssertEqual(w, 1, accuracy: 0.001, "ảnh đè riêng: không sẫm thêm")
    }

    /// Khung icon / nhãn như UIButton (đo bản UIButton 11/2026): icon căn giữa làm tròn XUỐNG pixel,
    /// nhãn cỡ làm tròn lên điểm nguyên, gốc làm tròn gần nhất.
    @MainActor func testContentFramesMatchUIButton() throws {
        let b = KeyboardView.KeyButton(frame: CGRect(x: 0, y: 0, width: 61, height: 43))
        b.setImage(UIImage(systemName: "delete.left"), for: .normal)
        b.layoutIfNeeded()
        let iv = try XCTUnwrap(b.imageView)
        let u = UIButton(type: .custom)
        u.frame = b.frame
        u.setImage(UIImage(systemName: "delete.left"), for: .normal)
        u.layoutIfNeeded()
        assertFrame(iv.frame, try XCTUnwrap(u.imageView).frame)
        let t = KeyboardView.KeyButton(frame: CGRect(x: 0, y: 0, width: 97.0 / 3, height: 43))
        t.titleFont = .systemFont(ofSize: 22)
        t.setTitle("d", for: .normal)
        t.layoutIfNeeded()
        let ut = UIButton(type: .custom)
        ut.frame = t.frame
        ut.setTitle("d", for: .normal)
        ut.titleLabel?.font = .systemFont(ofSize: 22)
        ut.layoutIfNeeded()
        assertFrame(try XCTUnwrap(t.titleLabel).frame, try XCTUnwrap(ut.titleLabel).frame)
    }

    private func assertFrame(_ a: CGRect, _ b: CGRect, file: StaticString = #filePath, line: UInt = #line) {
        for (x, y) in [(a.minX, b.minX), (a.minY, b.minY), (a.width, b.width), (a.height, b.height)] {
            XCTAssertEqual(x, y, accuracy: 0.01, "\(a) vs \(b)", file: file, line: line)
        }
    }

    // MARK: iPad hàng số (bug cũ: ràng buộc xung đột ⇒ cả hàng chữ rộng 0)

    @MainActor func testPadNumberRowKeysKeepUnits() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .pad)
        let kb = KeyboardView(needsGlobe: true, inputController: nil) { _ in }
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 834, height: 600))
        host.addSubview(kb)
        kb.frame = CGRect(x: 0, y: 0, width: 834, height: 400)
        kb.numberRowEnabled = true
        kb.configureInputKind(.normal)
        kb.layoutIfNeeded()
        kb.frame.size.height = kb.debugRequestedHeight
        kb.setNeedsLayout(); kb.layoutIfNeeded()
        let q = try XCTUnwrap(kb.debugLetterFrame("q"))
        XCTAssertGreaterThan(q.width, 40)
        let one = try XCTUnwrap(kb.debugKeyButton("1")).frame, minus = try XCTUnwrap(kb.debugKeyButton("-")).frame
        XCTAssertEqual(one.width, q.width, accuracy: 1)
        XCTAssertEqual(minus.width, 1.31 * q.width, accuracy: 1)
    }
}
