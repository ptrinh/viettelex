import XCTest
import UIKit

/// Hàng phím số tuỳ chọn (27/09/2026, người dùng Laban than thiếu hàng số):
/// plane chữ có thêm 1…0 ở trên cùng, PHÍM số 0.8× phím chữ (12/10/2026 — trước 0.75× cả
/// hàng kể khe ⇒ phím số 69% phím chữ, tester 1.2.8 "nhỏ quá, không cân đối"); plane số giữ 4 hàng.
final class NumberRowTests: XCTestCase {
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    private var trim: CGFloat { KeyGeometry.bottomRowTrim(pad: isPad, landscape: false) }

    @MainActor private func makeKeyboard(numberRow: Bool,
                                         onKey: @escaping (KeyboardView.Key) -> Void = { _ in })
        -> (KeyboardView, UIView) {
        let kb = KeyboardView(needsGlobe: false, inputController: nil, onKey: onKey)
        let w: CGFloat = isPad ? 834 : 390
        let host = UIView(frame: CGRect(x: 0, y: 0, width: w, height: 320))
        host.addSubview(kb)
        kb.frame = host.bounds
        kb.numberRowEnabled = numberRow
        kb.layoutIfNeeded()
        return (kb, host)
    }

    @MainActor private func assertNumberRowLayout(_ kb: KeyboardView, file: StaticString = #filePath,
                                                  line: UInt = #line) throws {
        let rows = kb.debugRowFrames()
        XCTAssertEqual(rows.count, 5, file: file, line: line)
        guard rows.count == 5 else { return }
        // Khe trên hàng: iPhone theo bàn phím gốc (11), iPad 10 (KeyGeometry.rowSpec).
        let gap = kb.rowSpec.gap
        XCTAssertEqual(rows[0].height, KeyGeometry.numberRowHeight(unit: rows[1].height, gap: gap),
                       accuracy: 0.5, file: file, line: line)
        for r in rows[2..<4] {
            XCTAssertEqual(r.height, rows[1].height, accuracy: 0.5, file: file, line: line)
        }
        // iPhone dọc: hàng đáy thấp hơn bottomRowTrim (KeyGeometry — khớp vị trí stock).
        XCTAssertEqual(rows[4].height, rows[1].height - trim, accuracy: 0.5, file: file, line: line)
        let q = try XCTUnwrap(kb.debugLetterFrame("q"))
        let z = try XCTUnwrap(kb.debugLetterFrame("z"))
        let a = try XCTUnwrap(kb.debugLetterFrame("a"))
        XCTAssertEqual(z.width, q.width, accuracy: 0.5, file: file, line: line)
        XCTAssertEqual(a.width, q.width, accuracy: 0.5, file: file, line: line)
        XCTAssertGreaterThan(q.minY, rows[0].maxY - 0.5, file: file, line: line)
        let one = try XCTUnwrap(kb.debugKeyButton("1"), file: file, line: line)
        let f = kb.convert(one.bounds, from: one)
        XCTAssertEqual(f.midX, q.midX, accuracy: 0.5, "1 thẳng cột q", file: file, line: line)
        XCTAssertEqual(f.width, q.width, accuracy: 0.5, file: file, line: line)
        // Phím số (không tính khe) = 0.8× phím chữ — cân đối, không còn "nhỏ quá".
        XCTAssertEqual(f.height, q.height * KeyLayout.numberKeyRatio, accuracy: 0.75, file: file, line: line)
        XCTAssertGreaterThanOrEqual(f.height / q.height, 0.78, file: file, line: line)
    }

    func testKeyAreaHeightAddsANumberRowOfEightyPercentKeys() {
        let gap = KeyGeometry.rowGap
        XCTAssertEqual(KeyLayout.keyAreaHeight(base: 216, adjust: 0, numberRow: false), 216)
        // dọc: hàng 54 = khe 10 + phím 44 ⇒ hàng số = 10 + 0.8 × 44 = 45.2
        XCTAssertEqual(KeyLayout.numberRowHeight(unit: 54), 45.2, accuracy: 0.001)
        XCTAssertEqual(KeyLayout.keyAreaHeight(base: 216, adjust: 0, numberRow: true),
                       216 + 45.2, accuracy: 0.001)
        // chỉnh ±pt mỗi hàng: hàng số ăn 0.8 phần
        XCTAssertEqual(KeyLayout.keyAreaHeight(base: 240, adjust: 5, numberRow: true),
                       260 + gap + 0.8 * (65 - gap), accuracy: 0.001)
        // rowUnit là nghịch đảo của keyAreaHeight (máy gập / ngang / iPad / chỉnh hàng)
        for base: CGFloat in [162, 208, 216, 240, 280] {
            for adj: CGFloat in [-10, 0, 10] {
                for nr in [false, true] {
                    let area = KeyLayout.keyAreaHeight(base: base, adjust: adj, numberRow: nr)
                    XCTAssertEqual(KeyLayout.rowUnit(keyArea: area, numberRow: nr), (base + 4 * adj) / 4,
                                   accuracy: 0.001, "base=\(base) adj=\(adj) nr=\(nr)")
                }
            }
        }
        // Mọi chiều cao hàng thực tế (ngang 162/4 … iPad): phím số = 0.8 × phím chữ.
        for unit: CGFloat in [36, 40.5, 52, 54, 60, 70] {
            let numKey = KeyLayout.numberRowHeight(unit: unit) - gap
            XCTAssertEqual(numKey / (unit - gap), 0.8, accuracy: 0.001, "unit=\(unit)")
        }
    }

    @MainActor func testOffByDefaultKeepsFourEqualRows() {
        let kb = KeyboardView(needsGlobe: false, inputController: nil, onKey: { _ in })
        XCTAssertFalse(kb.numberRowEnabled)
        let (kb2, _) = makeKeyboard(numberRow: false)
        let rows = kb2.debugRowFrames()
        XCTAssertEqual(rows.count, 4)
        for r in rows.dropLast() { XCTAssertEqual(r.height, rows[0].height, accuracy: 0.5) }
        XCTAssertEqual(rows[3].height, rows[0].height - trim, accuracy: 0.5)
        XCTAssertNil(kb2.debugKeyButton("1"))
    }

    @MainActor func testLettersPlaneGetsShorterNumberRow() throws {
        let (kb, _) = makeKeyboard(numberRow: true)
        try assertNumberRowLayout(kb)
        // Phím số là button thật (hitTest trả thẳng) — router phím chữ không cướp.
        let one = try XCTUnwrap(kb.debugKeyButton("1"))
        let f = kb.convert(one.bounds, from: one)
        let hit = kb.hitTest(CGPoint(x: f.midX, y: f.midY), with: nil)
        XCTAssertTrue(hit === one)
        // Chạm q vẫn là router (phím chữ).
        let q = try XCTUnwrap(kb.debugLetterFrame("q"))
        XCTAssertTrue(kb.hitTest(CGPoint(x: q.midX, y: q.midY), with: nil) === kb)
    }

    @MainActor func testDigitInsertsTextKey() throws {
        var got: [KeyboardView.Key] = []
        let (kb, _) = makeKeyboard(numberRow: true, onKey: { got.append($0) })
        let seven = try XCTUnwrap(kb.debugKeyButton("7"))
        seven.sendActions(for: .touchDown)
        seven.sendActions(for: .touchUpInside)
        guard case .text("7")? = got.last else { return XCTFail("\(got)") }
    }

    @MainActor func testNumberRowSurvivesPlaneCache() throws {
        let (kb, _) = makeKeyboard(numberRow: true)
        kb.debugCycleThroughNumbers()
        kb.layoutIfNeeded()
        try assertNumberRowLayout(kb)
        kb.debugCycleThroughTemplates()
        kb.setNeedsLayout(); kb.layoutIfNeeded()
        try assertNumberRowLayout(kb)
    }

    @MainActor func testNumbersPlaneKeepsFourRows() {
        let (kb, _) = makeKeyboard(numberRow: true)
        // iPad: plane số stock (đã có hàng tab 1…0) — chưa đổi, xem báo cáo field 18/10/2026.
        guard isPad else { return }
        kb.debugSetPlane(numbers: true)
        kb.layoutIfNeeded()
        let rows = kb.debugRowFrames()
        XCTAssertEqual(rows.count, 4)
        for r in rows { XCTAssertEqual(r.height, rows[0].height, accuracy: 0.5) }
    }

    // MARK: field report 18/10/2026 — "hàng phím số khi bấm shift lại bị mất dẫn đến hụt hàng,
    // khoảng cách các phím ko cân đối khi chuyển dễ bị bấm nhầm".

    /// Khung mọi nút phím + phím chữ (toạ độ kb) — so trước/sau một thao tác.
    @MainActor private func keyFrames(_ kb: KeyboardView) -> [CGRect] {
        kb.debugAllKeyButtons().map { kb.convert($0.bounds, from: $0) }
    }
    @MainActor private func assertSameFrames(_ a: [CGRect], _ b: [CGRect], _ what: String,
                                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.count, b.count, what, file: file, line: line)
        for (x, y) in zip(a, b) {
            XCTAssertEqual(x.minX, y.minX, accuracy: 0.5, what, file: file, line: line)
            XCTAssertEqual(x.minY, y.minY, accuracy: 0.5, what, file: file, line: line)
            XCTAssertEqual(x.width, y.width, accuracy: 0.5, what, file: file, line: line)
            XCTAssertEqual(x.height, y.height, accuracy: 0.5, what, file: file, line: line)
        }
    }

    /// Shift / Caps Lock ở plane chữ KHÔNG được đổi số hàng, cao hàng hay vị trí phím nào
    /// (kể cả hàng số, cả khi hàng số cao bằng hàng chữ).
    @MainActor func testShiftAndCapsNeverMoveKeys() throws {
        for (nr, full) in [(false, false), (true, false), (true, true)] {
            let what = "numberRow=\(nr) full=\(full)"
            let (kb, host) = makeKeyboard(numberRow: nr)
            kb.numberRowFullHeight = full
            kb.setNeedsLayout(); kb.layoutIfNeeded()
            let rows0 = kb.debugRowFrames(), keys0 = keyFrames(kb)
            let digits0 = KeyLayout.digits.compactMap { kb.debugKeyButton($0).map { kb.convert($0.bounds, from: $0) } }
            XCTAssertEqual(digits0.count, nr ? 10 : 0, what)
            let shift = try XCTUnwrap(kb.debugControl("Shift"), what)
            // Mặc định ON (đầu câu) → chạm: OFF → chạm nhanh 2 lần: Caps Lock.
            for step in ["off", "on", "caps"] {
                shift.sendActions(for: .touchDown)
                shift.sendActions(for: .touchUpInside)
                kb.setNeedsLayout(); kb.layoutIfNeeded()
                assertSameFrames(kb.debugRowFrames(), rows0, "\(what) rows after \(step)")
                assertSameFrames(keyFrames(kb), keys0, "\(what) keys after \(step)")
                let digits = KeyLayout.digits.compactMap { kb.debugKeyButton($0).map { kb.convert($0.bounds, from: $0) } }
                assertSameFrames(digits, digits0, "\(what) digits after \(step)")
                // Hàng số vẫn là chữ số (không đổi sang !@#).
                if nr { XCTAssertEqual(kb.debugRowLabels().first, KeyLayout.digits, what) }
            }
            withExtendedLifetime(host) {}
        }
    }

    /// Pure: bật hàng số ⇒ plane 123 / #+= iPhone có đúng hàng 1…0 + 2 hàng ký hiệu; không ký tự
    /// nào lặp trong một plane (kể cả hàng 3 . , ? ! '). Tắt ⇒ như cũ.
    func testPhoneSymbolicRowsWithNumberRow() {
        XCTAssertEqual(KeyLayout.phoneSymbolicRows(numbers: true, numberRow: false), KeyLayout.phoneNumberRows)
        XCTAssertEqual(KeyLayout.phoneSymbolicRows(numbers: false, numberRow: false), KeyLayout.phoneSymbolRows)
        XCTAssertEqual(KeyLayout.phoneNumberRows.first, KeyLayout.digits)
        for numbers in [true, false] {
            let rows = KeyLayout.phoneSymbolicRows(numbers: numbers, numberRow: true)
            XCTAssertEqual(rows.count, 3)
            XCTAssertEqual(rows.first, KeyLayout.digits, "hàng số giữ nguyên chữ số")
            for r in rows { XCTAssertEqual(r.count, 10) }
            let all = rows.flatMap { $0 } + [".", ",", "?", "!", "'"]
            XCTAssertEqual(Set(all).count, all.count, "numbers=\(numbers): ký tự lặp")
        }
        // Không mất ký tự nào so với bản 4 hàng.
        let on = Set(KeyLayout.phoneSymbolicRows(numbers: true, numberRow: true).flatMap { $0 }
            + KeyLayout.phoneSymbolicRows(numbers: false, numberRow: true).flatMap { $0 })
        let off = Set((KeyLayout.phoneNumberRows + KeyLayout.phoneSymbolRows).flatMap { $0 })
        XCTAssertTrue(off.isSubset(of: on))
    }

    /// #142: bật hàng số, plane 123 vẫn để hàng - / : ; ( ) … ở vị trí thứ 3 từ dưới lên (ngay trên
    /// hàng . , ? ! ') như bàn phím gốc; plane #+= giữ hàng _ \ | … ở vị trí đó.
    func testNumberPlaneKeepsStockPunctuationRowPosition() {
        let num = KeyLayout.phoneSymbolicRows(numbers: true, numberRow: true)
        XCTAssertEqual(num.last, KeyLayout.phoneNumberRows.last)
        XCTAssertEqual(num[1], KeyLayout.phoneSymbolRows.first)
        let sym = KeyLayout.phoneSymbolicRows(numbers: false, numberRow: true)
        XCTAssertEqual(sym.last, KeyLayout.phoneSymbolRows.last)
    }

    /// Chuyển ABC ↔ 123 ↔ #+= khi bật hàng số: cùng 5 hàng, cùng chiều cao từng hàng, hàng 1…0
    /// đứng YÊN (cùng khung) — trước đây plane số 4 hàng giãn ra cả vùng ⇒ mọi phím nhảy dọc.
    @MainActor func testNumbersPlaneKeepsLettersRowGeometry() throws {
        guard !isPad else { return }
        for full in [false, true] {
            let what = "full=\(full)"
            let (kb, host) = makeKeyboard(numberRow: true)
            kb.numberRowFullHeight = full
            kb.setNeedsLayout(); kb.layoutIfNeeded()
            let rows0 = kb.debugRowFrames()
            XCTAssertEqual(rows0.count, 5, what)
            let digits0 = KeyLayout.digits.compactMap { kb.debugKeyButton($0).map { kb.convert($0.bounds, from: $0) } }
            XCTAssertEqual(digits0.count, 10, what)
            for symbols in [false, true, false] {      // lần 2 sang 123: từ planeCache
                kb.debugSetPlane(numbers: true)
                if symbols {
                    let more = try XCTUnwrap(kb.debugControl("Ký hiệu"), what)
                    more.sendActions(for: .touchDown)
                }
                kb.setNeedsLayout(); kb.layoutIfNeeded()
                let plane = "\(what) plane=\(kb.debugPlaneName)"
                XCTAssertEqual(kb.debugPlaneName, symbols ? "symbols" : "numbers")
                assertSameFrames(kb.debugRowFrames(), rows0, "\(plane) rows")
                XCTAssertEqual(kb.debugRowLabels().first, KeyLayout.digits, plane)
                let digits = KeyLayout.digits.compactMap { kb.debugKeyButton($0).map { kb.convert($0.bounds, from: $0) } }
                assertSameFrames(digits, digits0, "\(plane) digits")
                kb.debugSetPlane(numbers: false)
                kb.setNeedsLayout(); kb.layoutIfNeeded()
                assertSameFrames(kb.debugRowFrames(), rows0, "\(plane) back to letters")
            }
            withExtendedLifetime(host) {}
        }
    }

    /// Tắt hàng số: plane số giữ 4 hàng như cũ (không đổi gì khi tính năng tắt).
    @MainActor func testNumbersPlaneWithoutNumberRowUnchanged() {
        let (kb, host) = makeKeyboard(numberRow: false)
        let rows0 = kb.debugRowFrames()
        kb.debugSetPlane(numbers: true)
        kb.setNeedsLayout(); kb.layoutIfNeeded()
        XCTAssertEqual(kb.debugRowFrames().count, 4)
        assertSameFrames(kb.debugRowFrames(), rows0, "no number row")
        withExtendedLifetime(host) {}
    }

    @MainActor func testToggleOffRestoresLayout() {
        let (kb, _) = makeKeyboard(numberRow: true)
        kb.numberRowEnabled = false
        kb.layoutIfNeeded()
        XCTAssertEqual(kb.debugRowFrames().count, 4)
        XCTAssertNil(kb.debugKeyButton("1"))
    }

    /// Gõ vuốt lấy tâm a–z từ frame thật: đủ 26 chữ, không lẫn phím số.
    @MainActor func testSwipeLayoutStillLettersOnly() throws {
        let (kb, _) = makeKeyboard(numberRow: true)
        let layout = try XCTUnwrap(kb.swipeLayout())
        XCTAssertEqual(layout.centers.count, 52)
        XCTAssertTrue(layout.centers.allSatisfy(\.isFinite))
        let q = try XCTUnwrap(kb.debugLetterFrame("q"))
        let qi = Int(Character("q").asciiValue! - Character("a").asciiValue!)
        XCTAssertEqual(CGFloat(layout.centers[2 * qi]), q.midX, accuracy: 0.5)
        XCTAssertEqual(CGFloat(layout.centers[2 * qi + 1]), q.midY, accuracy: 0.5)
    }
}
