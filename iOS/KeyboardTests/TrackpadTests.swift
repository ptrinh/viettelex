// Trackpad giữ phím cách: lên/xuống theo ký tự xuống dòng (giữ cột, grapheme) +
// tăng tốc + hysteresis trục. Cùng bộ ca với android TrackpadTest.
import XCTest

final class TrackpadGestureTests: XCTestCase {

    /// Kéo từ (0,0) qua các điểm, mỗi điểm cách `dt` giây; trả mọi bước.
    private func drag(_ pts: [(Double, Double)], dt: Double) -> [TrackpadGesture.Step] {
        var g = TrackpadGesture()
        g.begin(x: 0, y: 0, t: 0)
        var t = 0.0
        return pts.compactMap { p in t += dt; return g.move(x: p.0, y: p.1, t: t) }
    }

    func testSlowHorizontalIsExactPerCharacter() {
        // 3pt / 50ms = 60 pt/s: 90pt ⇒ đúng 10 ký tự, mỗi bước 1.
        let steps = drag((1...30).map { (Double($0) * 3, 0) }, dt: 0.05)
        XCTAssertEqual(steps.reduce(0) { $0 + $1.count }, 10)
        XCTAssertTrue(steps.allSatisfy { $0.axis == .horizontal && $0.count == 1 })
    }

    func testFastHorizontalAccelerates() {
        // 30pt / 16ms ≈ 1875 pt/s ⇒ ×5; bước cuối 4 ô (dư cộng dồn) × 5.
        let steps = drag((1...6).map { (Double($0) * 30, 0) }, dt: 0.016)
        XCTAssertEqual(steps.last, .init(axis: .horizontal, count: 20))
        XCTAssertGreaterThan(steps.reduce(0) { $0 + $1.count }, 180 / 9)
    }

    func testLeftIsNegative() {
        let steps = drag((1...10).map { (-Double($0) * 3, 0) }, dt: 0.05)
        XCTAssertEqual(steps.reduce(0) { $0 + $1.count }, -3)
    }

    func testSlightlyDiagonalHorizontalNeverChangesLine() {
        // Ngang 300pt, trôi xuống 60pt (> 2 dòng): không bước dọc nào.
        let steps = drag((1...100).map { (Double($0) * 3, Double($0) * 0.6) }, dt: 0.03)
        XCTAssertTrue(steps.allSatisfy { $0.axis == .horizontal })
    }

    func testVerticalDragMovesLinesDespiteJitter() {
        // 4pt / 60ms xuống, rung ngang ±2pt: 96pt ⇒ 4 dòng.
        let steps = drag((1...24).map { ($0 % 2 == 0 ? 2 : -2, Double($0) * 4) }, dt: 0.06)
        XCTAssertTrue(steps.allSatisfy { $0.axis == .vertical })
        XCTAssertEqual(steps.reduce(0) { $0 + $1.count }, 4)
    }

    func testUpIsNegativeAndFastVerticalAccelerates() {
        let slow = drag((1...6).map { (0, -Double($0) * 4) }, dt: 0.06)
        XCTAssertEqual(slow.reduce(0) { $0 + $1.count }, -1)
        let fast = drag((1...4).map { (0, Double($0) * 30) }, dt: 0.016)   // ×3
        XCTAssertEqual(fast.last, .init(axis: .vertical, count: 6))           // 2 dòng × 3
    }

    func testVerticalModeNeedsTwoCharactersToReturnHorizontal() {
        var g = TrackpadGesture()
        g.begin(x: 0, y: 0, t: 0)
        XCTAssertEqual(g.move(x: 0, y: 30, t: 0.1)?.axis, .vertical)
        XCTAssertNil(g.move(x: 12, y: 30, t: 0.2))           // 12 < 18: vẫn dọc, chưa bước
        XCTAssertEqual(g.move(x: 20, y: 30, t: 0.3), .init(axis: .horizontal, count: 2))
    }

    func testAccelerateCurve() {
        let a = { (u: Int, v: Double) in TrackpadGesture.accelerate(u, speed: v, slow: 300, fast: 1500, max: 5) }
        XCTAssertEqual(a(3, 100), 3)
        XCTAssertEqual(a(-2, 300), -2)
        XCTAssertEqual(a(1, 900), 3)
        XCTAssertEqual(a(-1, 9999), -5)
        XCTAssertEqual(a(0, 9999), 0)
    }
}

final class VerticalMoveTests: XCTestCase {

    func testKeepsColumnAndClampsToShortLine() {
        XCTAssertEqual(VerticalMove.offset(before: "abcdef\nxyz", after: "", lines: -1), -7)  // "abc|def"
        XCTAssertEqual(VerticalMove.offset(before: "ab\nwxyz", after: "", lines: -1), -5)     // "ab" ngắn ⇒ cuối
        XCTAssertEqual(VerticalMove.offset(before: "ab", after: "cd\nwxyz", lines: 1), 5)     // "wx|yz"
        XCTAssertEqual(VerticalMove.offset(before: "abcd", after: "\nxy", lines: 1), 3)       // cuối "xy"
    }

    func testGraphemeColumnsAndUTF16Offsets() {
        // "😀é" = 2 cột (😀 = 2 UTF-16, é tổ hợp = 2 UTF-16).
        let before = "a😀bc\n😀e\u{301}"
        XCTAssertEqual(VerticalMove.offset(before: before, after: "", lines: -1),
                       3 - before.utf16.count)                 // sau "a😀"
        let family = "👨\u{200D}👩\u{200D}👧"
        XCTAssertEqual(VerticalMove.offset(before: "😀e\u{301}", after: "\nx\(family)y", lines: 1),
                       1 + 1 + family.utf16.count)             // sau family trọn vẹn
    }

    func testBoundariesAndMultipleLines() {
        XCTAssertNil(VerticalMove.offset(before: "abc", after: "def", lines: -1))  // dòng đầu / tự ngắt
        XCTAssertNil(VerticalMove.offset(before: "abc", after: "def", lines: 1))   // dòng cuối
        XCTAssertNil(VerticalMove.offset(before: "", after: "", lines: 1))
        XCTAssertEqual(VerticalMove.offset(before: "a\nbc\nde", after: "", lines: -5), -6)  // chỉ có 2 dòng
        XCTAssertEqual(VerticalMove.offset(before: "", after: "a\nb\nc", lines: 2), 4)
        XCTAssertEqual(VerticalMove.offset(before: "ab\r\ncd", after: "", lines: -1), -4)   // \r\n một ngắt
        XCTAssertEqual(VerticalMove.offset(before: "x", after: "", lines: 0), 0)
    }
}
