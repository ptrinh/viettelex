import XCTest
import UIKit

/// Hình học hàng phím iPhone so với bàn phím Apple gốc (đo 27/09/2026 — KeyGeometry) +
/// vùng chạm hàng đáy / khe (mục 9) + đổi plane một chạm (mục 10).
final class KeyGeometryTests: XCTestCase {
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    // MARK: thuần

    func testPitchAndIndentMatchStock() {
        // 402pt, lề 6.5, khe 6 → phím 33.5 (stock 33.3), bước 39.5 (stock 39.5).
        let pitch = KeyGeometry.letterPitch(width: 402, margin: 6.5, gap: 6)
        XCTAssertEqual(pitch, 39.5, accuracy: 0.3)
        // Hàng a…l thụt nửa bước: mép a = 26.25 (stock 26.3).
        XCTAssertEqual(KeyGeometry.indentedMargin(width: 402, margin: 6.5, gap: 6, units: 0.5),
                       26.3, accuracy: 0.3)
        XCTAssertEqual(KeyGeometry.sideMargin(pad: false), 6.5)
        XCTAssertEqual(KeyGeometry.sideMargin(pad: true), 3)
        XCTAssertEqual(KeyGeometry.bottomRowTrim(pad: false, landscape: false), 4)
        XCTAssertEqual(KeyGeometry.bottomRowTrim(pad: false, landscape: true), 0)
        XCTAssertEqual(KeyGeometry.bottomRowTrim(pad: true, landscape: false), 0)
        // Phím đáy 43 (stock) trong vùng 50: khe trên 7 — trước 6 + 44 trông cao hơn stock.
        XCTAssertEqual(KeyGeometry.bottomRowTopMargin(pad: false, landscape: false), 7)
        XCTAssertEqual(KeyGeometry.bottomRowTopMargin(pad: false, landscape: true), KeyGeometry.rowGap)
        XCTAssertEqual(KeyGeometry.bottomRowTopMargin(pad: true, landscape: false), KeyGeometry.rowGap)
    }

    /// Chữ phím khớp stock (đo ảnh @3x 27/09): SF Compact, thường 24.5 / hoa-số 22.7, cùng
    /// baseline 28pt dưới đỉnh phím 43. Trước: SF Pro 23 căn giữa → chữ thường nhỏ + thấp.
    func testTypographyMatchesStock() {
        typealias T = KeyGeometry.Typography
        XCTAssertEqual(T.lowercaseSize, 24.5)
        XCTAssertEqual(T.keycapSize, 22.7)
        XCTAssertEqual(T.planeKeySize, 18.9)
        XCTAssertEqual(T.fallbackKeycapSize, 21.3)
        for s in ["a", "q", "đ", "ư", "ấ"] { XCTAssertTrue(T.isLowercase(s), s) }
        for s in ["A", "Đ", "1", ",", "#+=", "", "@"] { XCTAssertFalse(T.isLowercase(s), s) }
        XCTAssertEqual(T.size(for: "q", compact: true), 24.5)
        XCTAssertEqual(T.size(for: "Q", compact: true), 22.7)
        XCTAssertEqual(T.size(for: "7", compact: true), 22.7)
        XCTAssertEqual(T.size(for: "Q", compact: false), 21.3)
        // Baseline: phím 43 → 28 từ đỉnh; phím 44 (hàng chữ, nhô 1pt trên) → 29 (đáy trùng stock).
        XCTAssertEqual(T.baselineFromTop(keyHeight: 43), 28)
        XCTAssertEqual(T.baselineFromTop(keyHeight: 44), 29)
        XCTAssertEqual(T.baselineFromTop(keyHeight: 30.5), 28 * 30.5 / 43, accuracy: 0.001)
        // SF metrics (asc 0.952, desc −0.241) 24.5pt trên phím 44: căn giữa → baseline 30.7,
        // phải dời lên 1.7pt.
        let dy = T.titleOffsetY(keyHeight: 44, ascender: 0.952 * 24.5, descender: -0.241 * 24.5)
        XCTAssertEqual(dy, -1.71, accuracy: 0.02)
    }

    /// Chữ phím iPad khớp stock iPadOS 27 (đo ảnh @2x 27/09, iPad Pro 11"/mini/13"): SF Compact
    /// cùng cỡ hoa/thường theo HƯỚNG máy, khối chữ + ký tự phụ căn theo tâm phím. Trước:
    /// SF Pro 23 dạt đáy (baseline cách đáy 12.5, stock 7), ký tự phụ SF 13 bám đỉnh.
    func testPadTypographyMatchesStock() {
        typealias P = KeyGeometry.Typography.Pad
        let p = P.metrics(landscape: false), l = P.metrics(landscape: true)
        XCTAssertEqual(p, P.portrait)
        XCTAssertEqual(l, P.landscape)
        XCTAssertEqual([p.letterSize, p.digitSize, p.hintSize, p.labelSize, p.punctSize, p.iconPointSize],
                       [22, 22, 12.5, 14.6, 20.3, 22.5])
        XCTAssertEqual([l.letterSize, l.digitSize, l.hintSize, l.labelSize, l.punctSize, l.iconPointSize],
                       [26.6, 26.8, 15.5, 19.4, 30, 23.5])
        XCTAssertEqual([p.letterBaselineBelowCenter, p.hintBaselineAboveCenter, p.digitBaselineBelowCenter],
                       [18.25, 8.75, 8.5])
        XCTAssertEqual([l.letterBaselineBelowCenter, l.hintBaselineAboveCenter, l.digitBaselineBelowCenter],
                       [22.25, 12, 9.25])
        // Góc dưới (đo ink 27/09 tối: stock icon cách đáy 5 / 9, nhãn 7.5 / 13; bản trước
        // 4 / 7.5 và 5.5 / 10.5 — "icon/text gần bottom quá").
        XCTAssertEqual([p.labelBaselineAboveBottom, p.labelSideInset, p.iconSideInset, p.iconBottomInset],
                       [8.5, 7.5, 5.5, 5.5])
        XCTAssertEqual([l.labelBaselineAboveBottom, l.labelSideInset, l.iconSideInset, l.iconBottomInset],
                       [13.5, 10, 8.5, 9.5])
        // Phím stock cao 54.5 / 74; compact (mini): icon + nhãn giữa phím.
        XCTAssertEqual([p.stockKeyHeight, l.stockKeyHeight], [54.5, 74])
        XCTAssertEqual([p.centerIconPointSize, p.centerLabelSize, p.centerToggleLabelSize], [23.5, 20, 18])
        XCTAssertEqual([l.centerIconPointSize, l.centerLabelSize, l.centerToggleLabelSize], [25, 27, 23])
        XCTAssertEqual([p.punctUpperBaselineBelowCenter, p.punctLowerBaselineBelowCenter], [-1.25, 16.5])
        XCTAssertEqual([l.punctUpperBaselineBelowCenter, l.punctLowerBaselineBelowCenter], [-0.5, 19.5])
        XCTAssertEqual(P.hintAlpha(dark: true), 0.30)
        XCTAssertEqual(P.hintAlpha(dark: false), 0.25)
        // Lề trong ảnh SF Symbol trừ ra: 22.5pt → lề cạnh 5.5 − 1.35, đáy 5.5 − 2.025.
        let ins = P.iconContentInsets(p)
        XCTAssertEqual(ins.side, 4.15, accuracy: 0.001)
        XCTAssertEqual(ins.bottom, 3.475, accuracy: 0.001)
        // iPhone KHÔNG đổi.
        XCTAssertEqual(KeyGeometry.Typography.lowercaseSize, 24.5)
        XCTAssertEqual(KeyGeometry.Typography.keycapSize, 22.7)
    }

    /// Baseline iPad theo TÂM phím, co theo chiều cao phím (Phil 27/09 tối: "text gần bottom
    /// quá"). Stock 54.5: baseline chữ 18.25 dưới tâm = cách đáy 9. Phím mình 50: bản trước
    /// giữ nguyên 18 → cách đáy 7 (khe đáy chữ 6.5 thay 9.5); nay 16.74 → cách đáy 8.26.
    func testPadLetterBaselineFollowsKeyCenter() {
        typealias T = KeyGeometry.Typography
        let p = T.Pad.portrait, l = T.Pad.landscape
        XCTAssertEqual(p.scaled(p.letterBaselineBelowCenter, keyHeight: 54.5), 18.25, accuracy: 1e-9)
        let below = p.scaled(p.letterBaselineBelowCenter, keyHeight: 50)
        XCTAssertEqual(below, 16.74, accuracy: 0.01)
        XCTAssertEqual(50 / 2 - below, 8.26, accuracy: 0.01)
        // Tỉ lệ khe đáy / chiều cao phím = stock (9 / 54.5).
        XCTAssertEqual((25 - below) / 50, (54.5 / 2 - 18.25) / 54.5, accuracy: 1e-6)
        XCTAssertEqual(p.scaled(p.hintBaselineAboveCenter, keyHeight: 50), 8.03, accuracy: 0.01)
        // Ngang: phím 65 (stock 74) → 19.54 dưới tâm.
        XCTAssertEqual(l.scaled(l.letterBaselineBelowCenter, keyHeight: 65), 19.54, accuracy: 0.01)
        XCTAssertEqual(p.scaled(3, keyHeight: 0), 3)          // chưa layout: không chia 0
        // UIButton căn giữa hộp dòng Compact 22 (asc 0.952, desc −0.241) trên phím 50:
        // baseline tự nhiên 25 + 7.82 = 32.82 → dời xuống 8.92 để về 41.74.
        let dy = T.offsetY(toBaseline: 25 + below, keyHeight: 50, ascender: 0.952 * 22, descender: -0.241 * 22)
        XCTAssertEqual(dy, 8.92, accuracy: 0.01)
        // offsetY(toBaseline:) trùng titleOffsetY của iPhone khi target = baseline iPhone.
        XCTAssertEqual(T.offsetY(toBaseline: T.baselineFromTop(keyHeight: 44), keyHeight: 44,
                                 ascender: 23.3, descender: -5.9),
                       T.titleOffsetY(keyHeight: 44, ascender: 23.3, descender: -5.9), accuracy: 1e-9)
    }

    func testNearestSplitsGapByDistance() {
        let upper = CGRect(x: 0, y: 0, width: 40, height: 44)
        let lower = CGRect(x: 0, y: 54, width: 40, height: 44)   // khe 10
        XCTAssertEqual(KeyGeometry.nearest(CGPoint(x: 20, y: 47), in: [upper, lower], reach: 22)?.index, 0)
        XCTAssertEqual(KeyGeometry.nearest(CGPoint(x: 20, y: 51), in: [upper, lower], reach: 22)?.index, 1)
        XCTAssertNil(KeyGeometry.nearest(CGPoint(x: 90, y: 20), in: [upper], reach: 22))
    }

    func testSelectionPointNeverLeavesKeyAreaTop() {
        // Chạm 1pt dưới đỉnh vùng phím: dời lên 4pt thì ra ngoài → router bỏ (mất phím).
        XCTAssertEqual(TouchGeometry.keySelectionPoint(CGPoint(x: 5, y: 101), top: 100).y, 100)
        XCTAssertEqual(TouchGeometry.keySelectionPoint(CGPoint(x: 5, y: 150), top: 100).y, 146)
        XCTAssertEqual(TouchGeometry.keySelectionPoint(CGPoint(x: 5, y: 90), top: 100).y, 90)
    }

    // MARK: bàn phím thật

    @MainActor private func makeKeyboard(onKey: @escaping (KeyboardView.Key) -> Void = { _ in })
        -> (KeyboardView, UIView) {
        let kb = KeyboardView(needsGlobe: false, inputController: nil, onKey: onKey)
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 402, height: 212))
        host.addSubview(kb)
        kb.frame = host.bounds          // gợi ý tắt: strip 0 ⇒ chỉ headroom balloon trên vùng phím 212
        kb.layoutIfNeeded()
        // Host cấp đúng mức xin (212 + headroom balloon 20 — KeyLayout.balloonHeadroom).
        host.frame.size.height = kb.debugRequestedHeight; kb.frame = host.bounds
        kb.layoutIfNeeded()
        return (kb, host)
    }

    private func frame(_ kb: KeyboardView, _ c: UIControl) -> CGRect { kb.convert(c.bounds, from: c) }

    /// Tâm phím (tính từ ĐÁY view) ≈ stock (tính từ đáy màn hình − 75pt vùng 🌐/mic).
    /// Trước: cả 3 hàng chữ cao hơn stock 5–6pt (bản phát hành 11pt).
    @MainActor func testLetterRowsMatchStockFromBottom() throws {
        try XCTSkipIf(isPad)
        let (kb, _) = makeKeyboard()
        let h = kb.bounds.height
        XCTAssertEqual(h, 212 + KeyLayout.balloonHeadroom, accuracy: 0.5)   // vùng phím 212 + headroom balloon
        let stock = KeyGeometry.Stock.rowCentersFromScreenBottom.map {
            $0 - KeyGeometry.Stock.viewBottomAboveScreenBottom
        }
        for (i, s) in ["q", "a", "z"].enumerated() {
            let f = try XCTUnwrap(kb.debugLetterFrame(s))
            XCTAssertEqual(h - f.midY, stock[i], accuracy: 1, "hàng \(s)")
            XCTAssertEqual(f.height, 44, accuracy: 0.5)
        }
        let num = try XCTUnwrap(kb.debugControl("Số"))
        let nf = frame(kb, num)
        XCTAssertEqual(nf.maxY, h, accuracy: 0.5, "hàng đáy sát đáy view")
        XCTAssertEqual(nf.height, KeyGeometry.Stock.keyHeight, accuracy: 0.3, "phím đáy cao 43 như stock")
        XCTAssertEqual(h - nf.midY, stock[3], accuracy: 5, "đáy view cao hơn đáy phím stock 4pt")
    }

    @MainActor func testColumnsAndBottomRowMatchStock() throws {
        try XCTSkipIf(isPad)
        let (kb, _) = makeKeyboard()
        let expect: [(String, CGFloat)] = [("q", 23.3), ("p", 378.8), ("a", 43.0), ("l", 359.0)]
        for (s, x) in expect {
            XCTAssertEqual(try XCTUnwrap(kb.debugLetterFrame(s)).midX, x, accuracy: 1, s)
        }
        let num = frame(kb, try XCTUnwrap(kb.debugControl("Số")))
        let emoji = frame(kb, try XCTUnwrap(kb.debugControl("Emoji")))
        let comma = frame(kb, try XCTUnwrap(kb.debugKeyButton(",")))
        let ret = frame(kb, try XCTUnwrap(kb.debugControl("Xuống dòng")))
        XCTAssertEqual(num.midX, KeyGeometry.Stock.planeKeyMidX, accuracy: 1.5)
        XCTAssertEqual(emoji.midX, KeyGeometry.Stock.emojiKeyMidX, accuracy: 1.5)
        // "," plane chữ hẹp hơn stock "." (KeyLayout.phoneLettersComma, 06/10/2026): MÉP PHẢI
        // giữ chỗ stock, tâm dời phải nửa phần cắt.
        let stockHalf = 402 * KeyLayout.units("comma", in: KeyLayout.phoneBottom)! / 2
        XCTAssertEqual(comma.maxX, 402 * KeyGeometry.Stock.periodMidXFraction + stockHalf, accuracy: 2)
        XCTAssertEqual(comma.width, 402 * KeyLayout.phoneLettersComma, accuracy: 1)
        XCTAssertEqual(ret.midX, 402 * KeyGeometry.Stock.returnMidXFraction, accuracy: 2)
    }

    /// Mục 9: khe trên hàng đáy + mép trái — trước là vùng chết (chạm cao 123 mất, cao
    /// emoji ra chữ z). Giờ trả đúng nút gần nhất.
    @MainActor func testBottomRowGapsHitNearestButton() throws {
        try XCTSkipIf(isPad)
        let (kb, _) = makeKeyboard()
        for label in ["Số", "Emoji", "Dấu cách", "Xuống dòng"] {
            let c = try XCTUnwrap(kb.debugControl(label))
            let f = frame(kb, c)
            for p in [CGPoint(x: f.midX, y: f.minY - 2.5), CGPoint(x: f.midX, y: f.minY - 1)] {
                XCTAssertTrue(kb.hitTest(p, with: nil) === c, "\(label) chạm cao \(f.minY - p.y)pt")
            }
        }
        let num = try XCTUnwrap(kb.debugControl("Số"))
        XCTAssertTrue(kb.hitTest(CGPoint(x: 1, y: frame(kb, num).midY), with: nil) === num, "mép trái")
        // Quét cả khe ⇧ ↔ 123: điểm nào cũng phải thuộc một trong hai nút (trước: dải chết).
        let shift = try XCTUnwrap(kb.debugControl("Shift"))
        let sf = frame(kb, shift), nf = frame(kb, num)
        var y = sf.maxY
        while y <= nf.minY {
            let v = kb.hitTest(CGPoint(x: nf.midX, y: y), with: nil)
            XCTAssertTrue(v === shift || v === num, "khe ⇧/123 y=\(y): \(String(describing: v))")
            y += 0.5
        }
        // Khe giữa 123 và emoji: về nút gần hơn.
        let e = try XCTUnwrap(kb.debugControl("Emoji"))
        let ef = frame(kb, e)
        XCTAssertTrue(kb.hitTest(CGPoint(x: ef.minX - 1, y: ef.midY), with: nil) === e)
    }

    /// Plane số không có router chữ: khe giữa các hàng số từng chết 4.5pt mỗi hàng.
    @MainActor func testNumbersPlaneHasNoDeadGaps() throws {
        try XCTSkipIf(isPad)
        let (kb, _) = makeKeyboard()
        kb.debugSetPlane(numbers: true)
        kb.setNeedsLayout(); kb.layoutIfNeeded()
        let one = try XCTUnwrap(kb.debugKeyButton("1"))
        let dash = try XCTUnwrap(kb.debugKeyButton("-"))
        let f1 = frame(kb, one), fd = frame(kb, dash)
        XCTAssertGreaterThan(fd.minY, f1.maxY, "rows=\(kb.debugRowFrames()) f1=\(f1) fd=\(fd)")
        var y = f1.maxY
        while y < fd.minY {
            let v = kb.hitTest(CGPoint(x: f1.midX, y: y), with: nil)
            XCTAssertTrue(v === one || v === dash, "khe y=\(y)")
            y += 0.5
        }
        let abc = try XCTUnwrap(kb.debugControl("Chữ"))
        let fa = frame(kb, abc)
        let more = try XCTUnwrap(kb.debugControl("Ký hiệu"))
        var yy = frame(kb, more).maxY
        while yy <= fa.minY {
            let v = kb.hitTest(CGPoint(x: fa.midX, y: yy), with: nil)
            XCTAssertTrue(v === more || v === abc, "khe #+=/ABC y=\(yy)")
            yy += 0.5
        }
        let hv = kb.hitTest(CGPoint(x: fa.midX, y: fa.minY - 2.5), with: nil)
        XCTAssertTrue(hv === abc, "\(String(describing: hv)) rows=\(kb.debugRowFrames()) abc=\(fa)")
        let rows = kb.debugRowFrames()
        XCTAssertEqual(rows[3].height, rows[0].height - KeyGeometry.bottomRowTrim(pad: false, landscape: false),
                       accuracy: 0.5)
    }

    /// Mục 10: 123 ↔ ABC đổi ngay lúc CHẠM (như stock) — không cần touch-up (hệ thống huỷ
    /// touch sát vùng 🌐/mic, hay ngón trượt khỏi phím ⇒ trước đây phải bấm lại).
    @MainActor func testPlaneKeysSwitchOnTouchDown() throws {
        let (kb, _) = makeKeyboard()
        for i in 0..<5 {
            try XCTUnwrap(kb.debugControl("Số")).sendActions(for: .touchDown)
            XCTAssertEqual(kb.debugPlaneName, "numbers", "lần \(i)")
            kb.layoutIfNeeded()
            try XCTUnwrap(kb.debugControl("Chữ")).sendActions(for: .touchDown)
            XCTAssertEqual(kb.debugPlaneName, "letters", "lần \(i)")
            kb.layoutIfNeeded()
        }
        // #+= cũng vậy
        try XCTUnwrap(kb.debugControl("Số")).sendActions(for: .touchDown)
        try XCTUnwrap(kb.debugControl("Ký hiệu")).sendActions(for: .touchDown)
        XCTAssertEqual(kb.debugPlaneName, "symbols")
    }

    @MainActor func testEmojiOpensEvenIfTouchCancelled() throws {
        let (kb, _) = makeKeyboard()
        try XCTUnwrap(kb.debugControl("Emoji")).sendActions(for: .touchCancel)
        XCTAssertEqual(kb.debugPlaneName, "emoji")
    }

    /// Nhãn phím chữ thật: font Compact (nếu có) đúng cỡ theo hoa/thường, baseline cách đáy
    /// phím 15pt như stock — cả sau khi bật/tắt shift (retitle tại chỗ).
    @MainActor func testLetterLabelsSitOnStockBaseline() throws {
        try XCTSkipIf(isPad)
        let (kb, _) = makeKeyboard()
        func check(_ title: String, size: CGFloat, _ note: String) throws {
            let b = try XCTUnwrap(kb.debugKeyButton(title), note)
            b.layoutIfNeeded()
            let l = try XCTUnwrap(b.titleLabel), f = try XCTUnwrap(l.font)
            XCTAssertEqual(f.pointSize, size, accuracy: 0.01, note)
            if KeyboardView.hasCompactFont {
                XCTAssertTrue(f.fontName.localizedCaseInsensitiveContains("compact"), f.fontName)
            }
            let baseline = l.frame.midY + (f.ascender + f.descender) / 2
            XCTAssertEqual(b.bounds.height - baseline, 15, accuracy: 0.5, "\(note) h=\(b.bounds.height)")
        }
        let T = KeyGeometry.Typography.self
        let c = KeyboardView.hasCompactFont
        let lowerFirst = kb.debugKeyButton("q") != nil
        try check(lowerFirst ? "q" : "Q", size: T.size(for: lowerFirst ? "q" : "Q", compact: c), "ban đầu")
        try XCTUnwrap(kb.debugControl("Shift")).sendActions(for: .touchDown)
        kb.layoutIfNeeded()
        try check(lowerFirst ? "Q" : "q", size: T.size(for: lowerFirst ? "Q" : "q", compact: c), "sau shift")
        // Plane số: chữ số cỡ keycap, cùng baseline.
        kb.debugSetPlane(numbers: true)
        kb.setNeedsLayout(); kb.layoutIfNeeded()
        try check("7", size: T.size(for: "7", compact: c), "plane số")
    }

    /// iPad (chạy trên simulator iPad): chữ Compact 22 hoa lẫn thường, baseline 18.25 dưới tâm
    /// phím stock 54.5 (co theo phím thật), ký tự phụ Compact 12.5 baseline 8.75 trên tâm;
    /// plane số: phím có ký tự phụ (@) như chữ, hàng số 22 / 8.5 dưới tâm.
    @MainActor func testPadLabelsSitOnStockBaseline() throws {
        try XCTSkipUnless(isPad)
        let kb = KeyboardView(needsGlobe: true, inputController: nil, onKey: { _ in })
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 834, height: 240))
        host.addSubview(kb)
        kb.frame = host.bounds
        kb.layoutIfNeeded()
        let P = KeyGeometry.Typography.Pad.portrait
        func check(_ title: String, size: CGFloat, below: CGFloat, hint: String?, _ note: String) throws {
            let b = try XCTUnwrap(kb.debugKeyButton(title), note)
            b.layoutIfNeeded()
            let h = b.bounds.height
            XCTAssertGreaterThan(h, 40, note)
            let l = try XCTUnwrap(b.titleLabel), f = try XCTUnwrap(l.font)
            XCTAssertEqual(f.pointSize, size, accuracy: 0.01, note)
            if KeyboardView.hasCompactFont {
                XCTAssertTrue(f.fontName.localizedCaseInsensitiveContains("compact"), f.fontName)
            }
            let baseline = l.frame.midY + (f.ascender + f.descender) / 2
            XCTAssertEqual(baseline - h / 2, P.scaled(below, keyHeight: h), accuracy: 0.5, "\(note) h=\(h)")
            guard let hint else { return }
            let hl = try XCTUnwrap(b.subviews.compactMap { $0 as? UILabel }.first { $0.text == hint }, note)
            let hf = try XCTUnwrap(hl.font)
            XCTAssertEqual(hf.pointSize, P.hintSize, accuracy: 0.01, note)
            XCTAssertEqual(h / 2 - (hl.frame.minY + hf.ascender), P.scaled(P.hintBaselineAboveCenter, keyHeight: h),
                           accuracy: 0.5, "\(note) hint")
        }
        let lowerFirst = kb.debugKeyButton("q") != nil
        try check(lowerFirst ? "q" : "Q", size: P.letterSize, below: P.letterBaselineBelowCenter, hint: "1", "ban đầu")
        try XCTUnwrap(kb.debugControl("Shift")).sendActions(for: .touchDown)
        kb.layoutIfNeeded()
        try check(lowerFirst ? "Q" : "q", size: P.letterSize, below: P.letterBaselineBelowCenter, hint: "1", "sau shift")
        kb.debugSetPlane(numbers: true)
        kb.setNeedsLayout(); kb.layoutIfNeeded()
        try check("7", size: P.digitSize, below: P.digitBaselineBelowCenter, hint: nil, "plane số")
        try check("@", size: P.letterSize, below: P.letterBaselineBelowCenter, hint: "¥", "plane số @")
    }

    /// iPad: hàng đáy cao bằng các hàng trên (bug 27/09: safe area đáy lọt vào layoutMargins
    /// hàng đáy → phím 45 thay 50, icon ☺︎ cách đáy 2pt).
    @MainActor func testPadBottomRowKeysAsTallAsLetterKeys() throws {
        try XCTSkipUnless(isPad)
        let kb = KeyboardView(needsGlobe: true, inputController: nil, onKey: { _ in })
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 834, height: 240))
        host.addSubview(kb)
        kb.frame = host.bounds
        kb.layoutIfNeeded()
        let q = try XCTUnwrap(kb.debugKeyButton("q") ?? kb.debugKeyButton("Q"))
        let space = try XCTUnwrap(kb.debugControl("Dấu cách"))
        let emoji = try XCTUnwrap(kb.debugControl("Emoji"))
        XCTAssertEqual(space.bounds.height, q.bounds.height, accuracy: 0.5)
        XCTAssertEqual(emoji.bounds.height, q.bounds.height, accuracy: 0.5)
        for v in [space, emoji] {
            XCTAssertFalse(v.superview?.insetsLayoutMarginsFromSafeArea ?? true)
        }
    }

    /// iPad plane .?123 / #+= đúng stock iPadOS 27 (thứ tự phím từng hàng, 🌐 đầu hàng đáy),
    /// cả kiểu full (11"/13") lẫn compact (mini). Trước: plane số kiểu iPhone [ABC][🌐]….
    @MainActor func testPadNumberAndSymbolPlanesMatchStock() throws {
        try XCTSkipUnless(isPad)
        var typed: [String] = []
        let kb = KeyboardView(needsGlobe: true, inputController: nil, onKey: { k in
            if case .text(let t) = k { typed.append(t) }
        })
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 834, height: 240))
        host.addSubview(kb)
        kb.frame = host.bounds
        let digits = "1234567890".map(String.init)
        let numRow2 = ["@", "#", "$", "&", "*", "(", ")", "'", "\""]
        let numRow3 = ["%", "-", "+", "=", "/", ";", ":", ",", "."]   // "!," "?." → nhãn a11y dưới
        let symRow2 = ["¥", "£", "€", "_", "^", "[", "]", "{", "}"]
        let symRow3 = ["§", "|", "~", "…", "\\", "<", ">", "!", "?"]
        for compact in [false, true] {
            kb.debugSetPadStyle(compact: compact)
            kb.debugSetPlane(numbers: true)
            kb.layoutIfNeeded()
            var rows = kb.debugRowLabels()
            XCTAssertEqual(rows.count, 4)
            guard rows.count == 4 else { return }
            if compact {
                XCTAssertEqual(rows[0], digits + ["Xoá"])
                XCTAssertEqual(rows[1], ["␣"] + numRow2 + ["Xuống dòng"])
                XCTAssertEqual(rows[2], ["Ký hiệu"] + numRow3 + ["Ký hiệu"])
                XCTAssertEqual(rows[3], ["Bàn phím tiếp theo", "Chữ", "Emoji", "Dấu cách", ",", "Chữ", "Ẩn bàn phím"])
            } else {
                XCTAssertEqual(rows[0], ["Tab"] + digits + ["Xoá"])
                XCTAssertEqual(rows[1], [","] + numRow2 + ["Xuống dòng"])
                XCTAssertEqual(rows[2], ["Ký hiệu"] + numRow3 + ["Ký hiệu"])
                XCTAssertEqual(rows[3], ["Bàn phím tiếp theo", "Chữ", "Emoji", "Dấu cách", "Chữ", "Ẩn bàn phím"])
            }
            // Ký tự phụ stock + vuốt xuống / giữ ra đúng ký tự đó; chạm thường ra ký tự chính.
            for (k, h) in KeyLayout.padNumberHints { XCTAssertEqual(kb.debugPadHint(k), h, k) }
            typed.removeAll()
            kb.debugPadAlternate("@")
            // Nhấc tay sau khi giữ ⇒ balloon ký tự phụ phải tắt (trước đây kẹt trên phím — Phil 27/09).
            XCTAssertFalse(kb.debugBalloonVisible, "balloon ký tự phụ phải ẩn khi nhấc tay")
            let at = try XCTUnwrap(kb.debugKeyButton("@"))
            at.sendActions(for: .touchDown); at.sendActions(for: .touchUpInside)
            XCTAssertEqual(typed, ["¥", "@"])
            XCTAssertTrue(kb.debugPadAltArmsOnTouchDown("%"))      // giữ phím: hẹn giờ chạy
            // #+=
            try XCTUnwrap(kb.debugControl("Ký hiệu")).sendActions(for: .touchDown)
            kb.layoutIfNeeded()
            rows = kb.debugRowLabels()
            XCTAssertEqual(Array(rows[0].dropFirst(compact ? 0 : 1).prefix(10)), digits)
            XCTAssertEqual(rows[1], [compact ? "␣" : "₫"] + symRow2 + ["Xuống dòng"])
            XCTAssertEqual(rows[2], ["Số"] + symRow3 + ["Số"])
            XCTAssertEqual(rows[3].first, "Bàn phím tiếp theo")
            if compact { XCTAssertEqual(rows[3][4], "₫") }
            XCTAssertNil(kb.debugPadHint("¥"))
        }
    }

    /// Chạm sát đỉnh vùng phím (khe trên q) vẫn ra q (trước: dời lên 4pt → ra ngoài → mất).
    @MainActor func testTouchAtKeyAreaTopStillTypes() throws {
        var typed: [KeyboardView.Key] = []
        let (kb, _) = makeKeyboard { typed.append($0) }
        let q = try XCTUnwrap(kb.debugLetterFrame("q"))
        let areaTop = q.minY - KeyGeometry.rowGap          // đỉnh vùng phím (dưới headroom balloon)
        kb.debugTouch(from: CGPoint(x: q.midX, y: areaTop + 1), through: [], start: 100)
        guard case .letter(let c)? = typed.first else { return XCTFail("mất phím: \(typed)") }
        XCTAssertEqual(String(c).lowercased(), "q")
    }
}
