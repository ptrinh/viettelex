import XCTest
import UIKit

/// Bàn phím tách đôi (Settings → Giao diện → "Bàn phím tách đôi", mặc định TẮT): hình học
/// thuần (SplitLayout) + view thật — chạm, G/V lặp, khe giữa chết, gõ vuốt / một tay tắt,
/// và TẮT = y hệt bàn phím cũ.
final class SplitKeyboardTests: XCTestCase {
    // MARK: Hàm thuần

    func testOnlyWhenWideAndEnabled() {
        for w: CGFloat in [375, 402, 440, 466, 599] {
            XCTAssertFalse(SplitLayout.active(setting: true, width: w), "\(w)")   // iPhone dọc / Duo gập
        }
        for w: CGFloat in [600, 669, 750, 801, 834, 1194] {
            XCTAssertTrue(SplitLayout.active(setting: true, width: w), "\(w)")
            XCTAssertFalse(SplitLayout.active(setting: false, width: w), "tắt: \(w)")
        }
    }

    func testMetricsMatchStockProportions() {
        // Duo mở (view 801, lề 6.5, khe 6): stock nửa 303, bước 57.
        let m = SplitLayout.metrics(width: 801, margin: 6.5, gap: 6)
        XCTAssertEqual(m.pitch, 55.25, accuracy: 0.1)
        XCTAssertEqual(m.keyWidth, m.pitch - 6, accuracy: 0.001)
        XCTAssertEqual(m.half, 5.5 * m.pitch - 6, accuracy: 0.001)
        XCTAssertEqual(m.half, 801 * SplitLayout.halfFraction - 6.5, accuracy: 0.5)
        XCTAssertGreaterThan(m.centerGap(width: 801, margin: 6.5), 3 * m.pitch, "khe giữa rộng như stock")
        // iPad ngang rất rộng: bước phím có trần, nửa không phình.
        let wide = SplitLayout.metrics(width: 1366, margin: 3, gap: 10)
        XCTAssertEqual(wide.pitch, SplitLayout.maxPitch)
        // Bề ngang tối thiểu: phím vẫn ≥ phím iPhone dọc (33).
        XCTAssertGreaterThan(SplitLayout.metrics(width: 600, margin: 6.5, gap: 6).keyWidth, 33)
    }

    func testLetterRowsFollowAppleDuplicates() {
        let rows = SplitLayout.letterRows
        XCTAssertEqual(rows.map(\.left), ["qwert", "asdfg", "zxcv"])
        XCTAssertEqual(rows.map(\.right), ["yuiop", "ghjkl", "vbnm"])
        let all = Set(rows.flatMap { Array($0.left + $0.right) })
        XCTAssertEqual(all.count, 26)
        let both = Set(rows.flatMap { Array($0.left) }).intersection(rows.flatMap { Array($0.right) })
        XCTAssertEqual(both, ["g", "v"], "Apple lặp G và V ở nửa phải")
        let h = SplitLayout.halves(Array("1234567890"))
        XCTAssertEqual(String(h.left), "12345"); XCTAssertEqual(String(h.right), "67890")
    }

    // MARK: View thật

    @MainActor private func makeKeyboard(width: CGFloat = 801, split: Bool,
                                         keys: @escaping (KeyboardView.Key) -> Void = { _ in }) -> (KeyboardView, UIView) {
        let kb = KeyboardView(needsGlobe: false, inputController: nil, onKey: keys)
        let host = UIView(frame: CGRect(x: 0, y: 0, width: width, height: 500))
        host.addSubview(kb)
        kb.frame = CGRect(x: 0, y: 0, width: width, height: 300)
        kb.debugScreenSize = CGSize(width: 951, height: 669)
        kb.configureInputKind(.normal)
        kb.setSuggestionsEnabled(true)
        kb.layoutIfNeeded()
        if split { kb.debugSetSplit(true) }
        kb.frame.size.height = kb.debugRequestedHeight
        kb.setNeedsLayout(); kb.layoutIfNeeded()
        return (kb, host)
    }
    private func frame(_ kb: KeyboardView, _ v: UIView) -> CGRect { kb.convert(v.bounds, from: v) }

    @MainActor func testSplitGeometry() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom == .pad)
        let (kb, _) = makeKeyboard(split: true)
        XCTAssertTrue(kb.debugIsSplit)
        XCTAssertEqual(kb.debugLetterKeyCount, 28, "26 chữ + G, V lặp")
        let m = SplitLayout.metrics(width: 801, margin: KeyGeometry.sideMargin(pad: false), gap: 6)
        let q = try XCTUnwrap(kb.debugLetterFrame("q")), t = try XCTUnwrap(kb.debugLetterFrame("t"))
        let y = try XCTUnwrap(kb.debugLetterFrame("y")), p = try XCTUnwrap(kb.debugLetterFrame("p"))
        XCTAssertEqual(q.width, m.keyWidth, accuracy: 0.5)
        XCTAssertEqual(q.minX, 6.5, accuracy: 0.5)
        XCTAssertEqual(p.maxX, 801 - 6.5, accuracy: 0.5)
        XCTAssertGreaterThan(y.minX - t.maxX, 2 * m.pitch, "khe giữa")
        // Hàng 2 nửa trái thụt nửa phím: A dưới khe Q/W.
        XCTAssertEqual(try XCTUnwrap(kb.debugLetterFrame("a")).minX, q.minX + m.pitch / 2, accuracy: 0.5)
        // Mọi hàng (kể cả hàng đáy) cao đều, không hàng nào bị ép.
        let rows = kb.debugRowFrames()
        XCTAssertEqual(rows.count, 4)
        for r in rows { XCTAssertEqual(r.height, rows[0].height, accuracy: 0.5) }
        for label in ["Số", "Emoji", "Xuống dòng"] {
            let f = frame(kb, try XCTUnwrap(kb.debugControl(label)))
            XCTAssertEqual(f.height, q.height, accuracy: 0.5, label)
        }
        let ret = frame(kb, try XCTUnwrap(kb.debugControl("Xuống dòng")))
        XCTAssertEqual(ret.maxX, 801 - 6.5, accuracy: 0.5)
    }

    /// Chạm: G hai nửa đều ra "g"; khe giữa không ra phím nào; mép phím vẫn nhận phím gần nhất.
    @MainActor func testTouchesInSplit() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom == .pad)
        var typed: [String] = []
        let (kb, _) = makeKeyboard(split: true) { k in
            if case .letter(let c) = k { typed.append(String(c).lowercased()) }
        }
        let gs = (kb.debugLetterFrames("g"))
        XCTAssertEqual(gs.count, 2)
        var t: TimeInterval = 100
        for g in gs { kb.benchTap(at: CGPoint(x: g.midX, y: g.midY), time: t); t += 1 }
        XCTAssertEqual(typed, ["g", "g"])
        // Giữa khe trung tâm (hàng 1) — không phím.
        typed = []
        let tf = try XCTUnwrap(kb.debugLetterFrame("t")), yf = try XCTUnwrap(kb.debugLetterFrame("y"))
        kb.benchTap(at: CGPoint(x: (tf.maxX + yf.minX) / 2, y: tf.midY), time: t); t += 1
        XCTAssertEqual(typed, [], "khe giữa là vùng chết như Apple")
        // Mép ngoài của T (lấn vào khe 5pt) vẫn là T.
        kb.benchTap(at: CGPoint(x: tf.maxX + 5, y: tf.midY), time: t); t += 1
        XCTAssertEqual(typed, ["t"])
        // Khe giữa hàng đáy: không phải nút nào.
        let rows = kb.debugRowFrames()
        let bottom = try XCTUnwrap(rows.last)
        let hit = kb.hitTest(CGPoint(x: 400.5, y: bottom.midY), with: nil)
        XCTAssertFalse(hit is UIControl)
        XCTAssertFalse(hit === kb)
    }

    @MainActor func testSwipeAndOneHandOffWhenSplit() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom == .pad)
        let (kb, _) = makeKeyboard(split: true)
        XCTAssertNil(kb.swipeLayout(), "gõ vuốt tắt khi tách")
        kb.configureOneHand(.left)
        kb.setNeedsLayout(); kb.layoutIfNeeded()
        XCTAssertFalse(kb.debugOneHandActive)
        XCTAssertEqual(try XCTUnwrap(kb.debugLetterFrame("q")).minX, 6.5, accuracy: 0.5)
    }

    @MainActor func testNumberPlaneSplits() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom == .pad)
        let (kb, _) = makeKeyboard(split: true)
        kb.debugSetPlane(numbers: true)
        kb.setNeedsLayout(); kb.layoutIfNeeded()
        let five = frame(kb, try XCTUnwrap(kb.debugKeyButton("5")))
        let six = frame(kb, try XCTUnwrap(kb.debugKeyButton("6")))
        XCTAssertGreaterThan(six.minX - five.maxX, 100)
        XCTAssertNotNil(kb.debugControl("Ký hiệu"))
        XCTAssertNotNil(kb.debugControl("Xoá"))
        kb.debugSetPlane(numbers: false)
        kb.setNeedsLayout(); kb.layoutIfNeeded()
        XCTAssertEqual(kb.debugLetterKeyCount, 28)
    }

    /// Công tắc TẮT (mặc định) hoặc máy hẹp: bố cục y hệt bàn phím không có tính năng này.
    @MainActor func testOffOrNarrowIsUnchanged() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom == .pad)
        let (off, _) = makeKeyboard(split: false)
        XCTAssertFalse(off.debugIsSplit)
        XCTAssertEqual(off.debugLetterKeyCount, 26)
        XCTAssertNotNil(off.swipeLayout())
        let (narrow, _) = makeKeyboard(width: 402, split: true)
        XCTAssertFalse(narrow.debugIsSplit)
        let (plain, _) = makeKeyboard(width: 402, split: false)
        XCTAssertEqual(narrow.debugRowFrames(), plain.debugRowFrames())
        for s in ["q", "a", "z", "m"] {
            XCTAssertEqual(narrow.debugLetterFrame(s), plain.debugLetterFrame(s), s)
        }
    }

    /// Gập ⇄ mở / xoay khi công tắc bật: bề ngang qua ngưỡng ⇒ vào/ra kiểu tách tại chỗ.
    @MainActor func testWidthChangeTogglesSplit() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom == .pad)
        let (kb, _) = makeKeyboard(split: true)
        XCTAssertTrue(kb.debugIsSplit)
        kb.frame.size.width = 466
        kb.setNeedsLayout(); kb.layoutIfNeeded()
        XCTAssertFalse(kb.debugIsSplit)
        XCTAssertEqual(kb.debugLetterKeyCount, 26)
        kb.frame.size.width = 801
        kb.setNeedsLayout(); kb.layoutIfNeeded()
        XCTAssertTrue(kb.debugIsSplit)
        XCTAssertEqual(try XCTUnwrap(kb.debugLetterFrame("p")).maxX, 801 - 6.5, accuracy: 0.5)
    }
}
