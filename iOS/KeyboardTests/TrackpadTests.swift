// Trackpad giữ phím cách: cử chỉ hai trục độc lập (lọc hướng) + tăng tốc; lên/xuống theo
// dòng HIỂN THỊ ước lượng (ngắt cứng + tự ngắt, giữ cột grapheme); context dời theo lệnh
// mình gửi khi host trả context trễ. Cử chỉ cùng bộ ca với android TrackpadTest.
import UIKit
import XCTest

final class TrackpadGestureTests: XCTestCase {

    /// Kéo từ (0,0) qua các điểm, mỗi điểm cách `dt` giây; trả mọi bước.
    private func drag(_ pts: [(Double, Double)], dt: Double) -> [TrackpadGesture.Step] {
        var g = TrackpadGesture()
        g.begin(x: 0, y: 0, t: 0)
        var t = 0.0
        return pts.compactMap { p in t += dt; return g.move(x: p.0, y: p.1, t: t) }
    }
    private func sum(_ s: [TrackpadGesture.Step], _ axis: TrackpadGesture.Axis) -> Int {
        s.filter { $0.axis == axis }.reduce(0) { $0 + $1.count }
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
        // Ngang 300pt, trôi xuống 60pt (> 2 dòng, ~11°): không bước dọc nào, ngang đủ.
        let steps = drag((1...100).map { (Double($0) * 3, Double($0) * 0.6) }, dt: 0.03)
        XCTAssertTrue(steps.allSatisfy { $0.axis == .horizontal })
        XCTAssertEqual(sum(steps, .horizontal), 300 / 9)
    }

    func testVerticalDragMovesLinesDespiteJitter() {
        // 4pt / 60ms xuống, rung ngang ±2pt: 96pt ⇒ 4 dòng.
        let steps = drag((1...24).map { ($0 % 2 == 0 ? 2 : -2, Double($0) * 4) }, dt: 0.06)
        XCTAssertTrue(steps.allSatisfy { $0.axis == .vertical })
        XCTAssertEqual(steps.reduce(0) { $0 + $1.count }, 4)
    }

    /// Hồi quy "chỉ đi được mỗi 1 dòng": kéo dọc lệch ngang ~17° (ngón cái kéo xuống
    /// thường lệch) — bản khoá trục cũ ra bước ngang trước (dx đủ 9pt sau ~22pt dọc) rồi
    /// xoá dy ⇒ không bao giờ đổi dòng.
    func testMostlyVerticalWithDriftChangesLinesOnly() {
        let steps = drag((1...30).map { (Double($0) * 1.2, Double($0) * 4) }, dt: 0.05)
        XCTAssertEqual(sum(steps, .vertical), 120 / 24)
        XCTAssertEqual(sum(steps, .horizontal), 0)
    }

    func testDiagonalDragMovesBothAxes() {
        // 45°, 3pt/30ms mỗi trục (≈100 pt/s, không tăng tốc): 300pt ⇒ ~33 ký tự + ~12 dòng.
        let steps = drag((1...100).map { (Double($0) * 3, -Double($0) * 3) }, dt: 0.03)
        XCTAssertGreaterThanOrEqual(sum(steps, .horizontal), 32)
        XCTAssertLessThanOrEqual(sum(steps, .horizontal), 33)
        XCTAssertGreaterThanOrEqual(sum(steps, .vertical), -12)
        XCTAssertLessThanOrEqual(sum(steps, .vertical), -11)
    }

    func testTurningFromHorizontalToVerticalInOneDrag() {
        // Ngang 90pt rồi rẽ xuống 96pt (L): 10 ký tự rồi ~4 dòng (vài pt đầu khúc rẽ
        // còn tính hướng ngang — bỏ, không bao giờ dư).
        var pts = (1...30).map { (Double($0) * 3, 0.0) }
        pts += (1...24).map { (90.0, Double($0) * 4) }
        let steps = drag(pts, dt: 0.05)
        XCTAssertEqual(sum(steps, .horizontal), 10)
        XCTAssertGreaterThanOrEqual(sum(steps, .vertical), 3)
        XCTAssertLessThanOrEqual(sum(steps, .vertical), 4)
        XCTAssertEqual(steps.firstIndex { $0.axis == .vertical }.map { i in
            steps[i...].allSatisfy { $0.axis == .vertical } }, true)
        // Dọc rồi quay ngang: vài pt đầu còn mang hướng dọc (bỏ), sau đó 9pt = 1 ký tự.
        var g = TrackpadGesture()
        g.begin(x: 0, y: 0, t: 0)
        XCTAssertEqual(g.move(x: 0, y: 30, t: 0.1)?.axis, .vertical)
        XCTAssertNil(g.move(x: 4, y: 30, t: 0.2))
        XCTAssertNil(g.move(x: 8, y: 30, t: 0.3))
        XCTAssertNil(g.move(x: 12, y: 30, t: 0.4))
        XCTAssertEqual(g.move(x: 16, y: 30, t: 0.5), .init(axis: .horizontal, count: 1))
    }

    func testUpIsNegativeAndFastVerticalAccelerates() {
        let slow = drag((1...6).map { (0, -Double($0) * 4) }, dt: 0.06)
        XCTAssertEqual(slow.reduce(0) { $0 + $1.count }, -1)
        let fast = drag((1...4).map { (0, Double($0) * 30) }, dt: 0.016)   // ×3
        XCTAssertEqual(fast.last, .init(axis: .vertical, count: 6))           // 2 dòng × 3
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

    // MARK: ngắt cứng (charsPerLine 0 — như bản cũ)

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
        XCTAssertNil(VerticalMove.offset(before: "", after: "", lines: 1))          // không có context
        XCTAssertEqual(VerticalMove.offset(before: "a\nbc\nde", after: "", lines: -5), -6)  // chỉ có 2 dòng
        XCTAssertEqual(VerticalMove.offset(before: "", after: "a\nb\nc", lines: 2), 4)
        XCTAssertEqual(VerticalMove.offset(before: "ab\r\ncd", after: "", lines: -1), -4)   // \r\n một ngắt
        XCTAssertEqual(VerticalMove.offset(before: "x", after: "", lines: 0), 0)
    }

    /// Dòng đầu/cuối của phần THẤY ĐƯỢC: host hay cắt context (có khi chỉ còn đoạn hiện
    /// tại) ⇒ bản cũ trả nil = kẹt. Giờ: về mép phần thấy được; đã ở mép ⇒ ±1 vượt sang
    /// dòng khuất (đầu/cuối văn bản thật: host kẹp).
    func testFirstAndLastVisibleLine() {
        XCTAssertEqual(VerticalMove.offset(before: "abc", after: "def", lines: -1), -3)
        XCTAssertEqual(VerticalMove.offset(before: "abc", after: "def", lines: 1), 3)
        XCTAssertEqual(VerticalMove.offset(before: "", after: "def", lines: -1), -1)
        XCTAssertEqual(VerticalMove.offset(before: "abc", after: "", lines: 2), 1)
        XCTAssertEqual(VerticalMove.offset(before: "x\nabc", after: "", lines: 1), 1)
        XCTAssertEqual(VerticalMove.offset(before: "e\u{301}😀", after: "", lines: -1, charsPerLine: 30), -4)
    }

    // MARK: dòng tự ngắt

    func testLayoutWordWrap() {
        typealias L = VerticalMove.Line
        let lay = { (s: String, n: Int) in VerticalMove.layout(Array(s), charsPerLine: n) }
        XCTAssertEqual(lay("aaaa bbbb cccc dddd", 10),
                       [L(start: 0, end: 10, hardEnd: false), L(start: 10, end: 19, hardEnd: true)])
        XCTAssertEqual(lay("aaaaaaaa bb cc", 10),                       // ngắt sau dấu cách gần nhất
                       [L(start: 0, end: 9, hardEnd: false), L(start: 9, end: 14, hardEnd: true)])
        XCTAssertEqual(lay("abcdefghijklmnop", 5).map(\.start), [0, 5, 10, 15])   // từ quá dài: cắt cứng
        XCTAssertEqual(lay("abcde     ", 5), [L(start: 0, end: 10, hardEnd: true)])  // cách treo
        XCTAssertEqual(lay("abcde   fg", 5),
                       [L(start: 0, end: 8, hardEnd: false), L(start: 8, end: 10, hardEnd: true)])
        XCTAssertEqual(lay("ab\n\ncd", 10),                              // dòng trống là một dòng
                       [L(start: 0, end: 2, hardEnd: true), L(start: 3, end: 3, hardEnd: true),
                        L(start: 4, end: 6, hardEnd: true)])
        XCTAssertEqual(lay("abc", 0), [L(start: 0, end: 3, hardEnd: true)])
        XCTAssertEqual(lay("", 10), [L(start: 0, end: 0, hardEnd: true)])
    }

    func testWrappedParagraphKeepsColumn() {
        // cpl 10: "aaaa bbbb |cccc dddd" — hai dòng hiển thị, không có \n (ca tester báo).
        XCTAssertEqual(VerticalMove.offset(before: "aaaa bbbb cc", after: "cc dddd", lines: -1, charsPerLine: 10), -10)
        XCTAssertEqual(VerticalMove.offset(before: "aa", after: "aa bbbb cccc dddd", lines: 1, charsPerLine: 10), 10)
        // Dòng đích ngắn hơn cột ⇒ cuối dòng; dòng tự ngắt ⇒ trước dấu cách treo (cột 9 tối đa).
        XCTAssertEqual(VerticalMove.offset(before: "aaaaaaaa", after: " bb cc", lines: 1, charsPerLine: 10), 6)
        XCTAssertEqual(VerticalMove.offset(before: "aaaa bbbb cccc dddd", after: " eeeeeeeeee",
                                           lines: -1, charsPerLine: 10), -10)
        // Nhiều dòng một lúc; quá số dòng thấy được ⇒ dòng đầu.
        let para = "11111 2222 33333 4444 55555 6666 7777"
        XCTAssertEqual(VerticalMove.layout(Array(para), charsPerLine: 10).map(\.start), [0, 11, 22, 33])
        XCTAssertEqual(VerticalMove.offset(before: para, after: "", lines: -2, charsPerLine: 10), -(37 - 15))   // dòng 2, cột 4
        XCTAssertEqual(VerticalMove.offset(before: para, after: "", lines: -9, charsPerLine: 10), -37 + 4)
    }

    func testMixedHardAndSoftBreaks() {
        // Đoạn 1 tự ngắt 2 dòng, \n, đoạn 2 một dòng, \n, đoạn 3 tự ngắt.
        let text = "aaaa bbbb cccc\nxy\nddddd eeee ffff"
        // dòng: [0,10) "aaaa bbbb " · [10,14) "cccc" · [15,17) "xy" · [18,29) "ddddd eeee " · [29,33)
        let lay = VerticalMove.layout(Array(text), charsPerLine: 10)
        XCTAssertEqual(lay.map(\.start), [0, 10, 15, 18, 29])
        let at = { (i: Int, n: Int) -> Int? in
            let b = String(text.prefix(i)), a = String(text.dropFirst(i))
            return VerticalMove.offset(before: b, after: a, lines: n, charsPerLine: 10).map { i + $0 }
        }
        XCTAssertEqual(at(16, -1), 11)       // "x|y" lên ⇒ dòng tự ngắt CUỐI của đoạn trên, cột 1
        XCTAssertEqual(at(3, 1), 13)         // dòng tự ngắt ⇒ dòng sau cùng đoạn
        XCTAssertEqual(at(13, 1), 17)        // "ccc|c" xuống ⇒ "xy" ngắn ⇒ cuối
        XCTAssertEqual(at(17, 1), 20)        // cuối "xy" xuống ⇒ dòng đầu đoạn 3 cột 2
        XCTAssertEqual(at(30, -1), 19)       // dòng 2 đoạn 3 lên ⇒ dòng 1 đoạn 3 (cột 1)
        XCTAssertEqual(at(30, -3), 11)       // 3 dòng: đoạn 3 → "xy" → "cccc" (cột 1)
        XCTAssertEqual(at(5, 3), 23)
    }

    func testTruncatedContextStillMoves() {
        // Host cắt before giữa đoạn: coi đầu phần thấy được là đầu dòng — vẫn lên được.
        let before = "ng dài lắm rồi đây là phần cuối của nó"   // không có \n
        let off = VerticalMove.offset(before: before, after: "", lines: -1, charsPerLine: 12)
        XCTAssertNotNil(off)
        XCTAssertLessThan(off!, 0)
        XCTAssertGreaterThan(off!, -before.utf16.count)
        // Phần thấy được ngắn hơn một dòng ⇒ về đầu; lần đọc sau (host đưa thêm) đi tiếp.
        XCTAssertEqual(VerticalMove.offset(before: "đây", after: "", lines: -1, charsPerLine: 40), -3)
    }

    func testVietnameseCombiningAndEmojiWrapped() {
        // Tiếng Việt DẠNG TỔ HỢP (NFD): "Việt" = 4 grapheme nhưng 6 UTF-16; cột theo grapheme.
        let viet = "Vie\u{302}\u{323}t"
        let line1 = "\(viet) Nam "                      // 9 grapheme
        let line2 = "😀\(viet) 👨\u{200D}👩\u{200D}👧"   // 7 grapheme
        let text = line1 + line2
        XCTAssertEqual(VerticalMove.layout(Array(text), charsPerLine: 10).map(\.start), [0, 9])
        // Con trỏ sau "😀Việ" (cột 4) ⇒ lên: sau "Việt" (cột 4) của dòng 1.
        let before = line1 + "😀Vie\u{302}\u{323}"
        let after = String(text.dropFirst(before.count))
        let off = VerticalMove.offset(before: before, after: after, lines: -1, charsPerLine: 10)!
        XCTAssertEqual(before.utf16.count + off, viet.utf16.count)
        // Xuống từ cột 7 dòng 1 ("Việt Na|m") ⇒ dòng 2 có 7 grapheme, hardEnd ⇒ sau family.
        let b2 = "\(viet) Na", a2 = String(text.dropFirst(b2.count))
        XCTAssertEqual(b2.utf16.count + VerticalMove.offset(before: b2, after: a2, lines: 1, charsPerLine: 10)!,
                       text.utf16.count)
    }

    func testCharsPerLine() {
        XCTAssertEqual(VerticalMove.charsPerLine(fieldWidth: 354, avgAdvance: 8), 44)
        XCTAssertEqual(VerticalMove.charsPerLine(fieldWidth: 20, avgAdvance: 8), VerticalMove.minCharsPerLine)
        XCTAssertEqual(VerticalMove.charsPerLine(fieldWidth: 0, avgAdvance: 8), 0)
        XCTAssertEqual(VerticalMove.charsPerLine(fieldWidth: 300, avgAdvance: 0), 0)
    }

    /// Hiệu chỉnh: so dòng ước lượng với ngắt dòng THẬT của TextKit (UITextView/Notes dùng
    /// TextKit, body 17pt) trên ô rộng như iPhone 17 (402pt − lề). Không khớp từng ký tự
    /// (font tỉ lệ) nhưng số dòng và đầu dòng phải gần — sai lệch in ra để theo dõi.
    @MainActor func testCalibrationAgainstTextKit() {
        let traits = UITraitCollection(preferredContentSizeCategory: .large)
        let font = UIFont.preferredFont(forTextStyle: .body, compatibleWith: traits)
        let adv = VerticalMove.avgAdvance(
            sampleWidth: Double((VerticalMove.sample as NSString).size(withAttributes: [.font: font]).width))
        let para = "Hôm qua mình đi chợ mua rau, thịt và cá để nấu bữa tối cho cả nhà. Trời mưa to nên "
            + "đường rất đông, kẹt xe gần một tiếng đồng hồ. Về đến nhà thì ai cũng đói, nhưng món canh "
            + "chua cá lóc vẫn ngon như mọi khi. Tối nay chắc mình sẽ đọc sách một chút rồi đi ngủ sớm."
        for screen in [375.0, 402.0, 440.0] {
            let width = screen - VerticalMove.fieldInset
            let cpl = VerticalMove.charsPerLine(fieldWidth: width, avgAdvance: adv)
            let ours = VerticalMove.layout(Array(para), charsPerLine: cpl).map(\.start)
            // TextKit thật: UITextView mặc định có padding 5pt mỗi bên.
            let storage = NSTextStorage(string: para, attributes: [.font: font])
            let lm = NSLayoutManager()
            let tc = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
            lm.addTextContainer(tc); storage.addLayoutManager(lm)
            var starts: [Int] = []
            lm.enumerateLineFragments(forGlyphRange: lm.glyphRange(for: tc)) { _, _, _, r, _ in
                let cr = lm.characterRange(forGlyphRange: r, actualGlyphRange: nil)
                starts.append(para.distance(from: para.startIndex,
                                            to: String.Index(utf16Offset: cr.location, in: para)))
            }
            let drift = zip(ours, starts).map { abs($0 - $1) }.max() ?? 0
            print("TRACKPAD calibration screen=\(screen) adv=\(String(format: "%.2f", adv)) cpl=\(cpl) "
                  + "lines ours=\(ours.count) textkit=\(starts.count) maxStartDrift=\(drift) ours=\(ours) tk=\(starts)")
            // Đo 07/10/2026 (simulator):375 lệch ≤6 ký tự, 402/440 khớp tuyệt đối.
            XCTAssertEqual(ours.count, starts.count, "screen \(screen)")
            XCTAssertLessThanOrEqual(drift, 8, "screen \(screen)")
        }
        XCTAssertGreaterThan(adv, 6); XCTAssertLessThan(adv, 10)
    }
}

final class TrackpadContextTests: XCTestCase {

    func testStaleReadUsesShiftedViewFreshReadReplaces() {
        var c = TrackpadContext()
        XCTAssertEqual(c.resolve(before: "abc", after: "def").before, "abc")
        c.moved(by: -2)
        let v = c.resolve(before: "abc", after: "def")              // host chưa kịp
        XCTAssertEqual(v.before, "a"); XCTAssertEqual(v.after, "bcdef")
        let f = c.resolve(before: "ab", after: "cdef")              // host đã cập nhật
        XCTAssertEqual(f.before, "ab"); XCTAssertEqual(f.after, "cdef")
        c.reset()
        XCTAssertEqual(c.resolve(before: "x", after: "").before, "x")
    }

    func testMovedClampsAndSnapsToGrapheme() {
        var c = TrackpadContext()
        _ = c.resolve(before: "a😀", after: "e\u{301}b")
        c.moved(by: -1)                                          // giữa cặp surrogate ⇒ trước 😀
        XCTAssertEqual(c.before, "a"); XCTAssertEqual(c.after, "😀e\u{301}b")
        c.moved(by: 100)
        XCTAssertEqual(c.before, "a😀e\u{301}b"); XCTAssertEqual(c.after, "")
        c.moved(by: -100)
        XCTAssertEqual(c.before, ""); XCTAssertEqual(c.after, "a😀e\u{301}b")
        var unread = TrackpadContext()
        unread.moved(by: 3)                                      // chưa đọc ⇒ bỏ qua
        XCTAssertEqual(unread.before, "")
    }

    /// Nhiều bước dọc liên tiếp trong MỘT lần kéo khi host trả context trễ (chỉ cập nhật
    /// sau mỗi 2 lệnh): đọc lại context cũ mà không dời view ⇒ tính cột từ chỗ đã rời
    /// (bản trước: "ab\ncdefgh\nij" từ cuối "ij" lên 2 lần rơi vào "cdefg|h" thay vì "ab").
    func testConsecutiveStepsWithLaggingHost() {
        struct Host {
            let doc: String
            var caret: Int              // UTF-16
            var shown: (String, String) = ("", "")
            mutating func sync() {
                let i = String.Index(utf16Offset: caret, in: doc)
                shown = (String(doc[..<i]), String(doc[i...]))
            }
            mutating func adjust(_ off: Int) { caret = min(max(caret + off, 0), doc.utf16.count) }
        }
        func run(_ doc: String, start: Int, steps: [TrackpadGesture.Step], cpl: Int, lagEvery: Int) -> Int {
            var h = Host(doc: doc, caret: start); h.sync()
            var ctx = TrackpadContext()
            for (n, s) in steps.enumerated() {
                let v = ctx.resolve(before: h.shown.0, after: h.shown.1)
                let off: Int
                if s.axis == .horizontal { off = s.count }
                else { off = VerticalMove.offset(before: v.before, after: v.after, lines: s.count, charsPerLine: cpl) ?? 0 }
                ctx.moved(by: off)
                h.adjust(off)
                if (n + 1) % lagEvery == 0 { h.sync() }
            }
            return h.caret
        }
        let up = TrackpadGesture.Step(axis: .vertical, count: -1)
        let down = TrackpadGesture.Step(axis: .vertical, count: 1)
        let right = TrackpadGesture.Step(axis: .horizontal, count: 1)
        let doc = "ab\ncdefgh\nij"
        for lag in [1, 2, 3] {
            XCTAssertEqual(run(doc, start: 12, steps: [up, up], cpl: 0, lagEvery: lag), 2, "lag \(lag)")
            XCTAssertEqual(run(doc, start: 1, steps: [down, right, down], cpl: 0, lagEvery: lag), 12, "lag \(lag)")
        }
        // Đoạn tự ngắt (cpl 10) + ngắt cứng, kéo lên liên tục qua 4 dòng, host trễ.
        let para = "aaaa bbbb cccc dddd eeee ffff\ngggg hhhh"
        XCTAssertEqual(run(para, start: 32, steps: [up, up, up], cpl: 10, lagEvery: 2), 2)
        XCTAssertEqual(run(para, start: 2, steps: [down, down, down], cpl: 10, lagEvery: 3), 32)
    }
}
