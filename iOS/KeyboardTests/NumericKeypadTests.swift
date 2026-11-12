import XCTest
import UIKit

/// Bàn số lớn kiểu Apple (NumericKeypad): ô numberPad / decimalPad / OTP trên iPhone.
final class NumericKeypadTests: XCTestCase {
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    // MARK: chọn plane (thuần)

    func testStyleForEveryKeyboardTypeAndContentType() {
        let types: [UIKeyboardType] = [.default, .asciiCapable, .numbersAndPunctuation, .URL,
                                       .numberPad, .phonePad, .namePhonePad, .emailAddress,
                                       .decimalPad, .twitter, .webSearch, .asciiCapableNumberPad]
        let contents: [UITextContentType?] = [nil, .oneTimeCode, .password, .telephoneNumber, .name]
        for t in types {
            for c in contents {
                let got = NumericKeypad.style(keyboardType: t, contentType: c, isPad: false,
                                              decimalSeparator: ",")
                let want: NumericKeypad.Style?
                switch t {
                case .numberPad, .asciiCapableNumberPad: want = .digits
                case .decimalPad: want = .decimal(separator: ",")
                case .phonePad: want = .phone
                case .default, .asciiCapable: want = c == .oneTimeCode ? .digits : nil
                default: want = nil
                }
                XCTAssertEqual(got, want, "type \(t.rawValue) content \(c?.rawValue ?? "nil")")
                // iPad: luôn giữ hành vi cũ (plane 123 / chữ).
                XCTAssertNil(NumericKeypad.style(keyboardType: t, contentType: c, isPad: true))
            }
        }
    }

    func testNumbersAndPunctuationKeeps123Plane() {
        XCTAssertNil(NumericKeypad.style(keyboardType: .numbersAndPunctuation, contentType: nil, isPad: false))
        XCTAssertNil(NumericKeypad.style(keyboardType: .numbersAndPunctuation, contentType: .oneTimeCode,
                                         isPad: false))
        XCTAssertEqual(FieldTraits(keyboardType: .numbersAndPunctuation).inputKind, .number)
    }

    func testOTPOnDefaultKeyboardGetsKeypadButEmailOTPDoesNot() {
        let otp = FieldTraits(keyboardType: .default, contentType: .oneTimeCode)
        XCTAssertEqual(otp.keypadStyle(isPad: false), .digits)
        XCTAssertEqual(otp.inputKind, .normal)                 // ABC → bàn chữ thường
        XCTAssertTrue(otp.sensitive)                           // dải gợi ý trống
        XCTAssertNil(FieldTraits(keyboardType: .emailAddress, contentType: .oneTimeCode)
            .keypadStyle(isPad: false))
        XCTAssertNil(FieldTraits(keyboardType: .namePhonePad).keypadStyle(isPad: false))
    }

    func testDecimalSeparatorFollowsRegionNormalized() {
        XCTAssertEqual(NumericKeypad.separator(","), ",")
        XCTAssertEqual(NumericKeypad.separator("."), ".")
        XCTAssertEqual(NumericKeypad.separator(nil), ".")
        XCTAssertEqual(NumericKeypad.separator("٫"), ".")
        XCTAssertEqual(NumericKeypad.style(keyboardType: .decimalPad, contentType: nil, isPad: false,
                                           decimalSeparator: "."), .decimal(separator: "."))
        XCTAssertEqual(NumericKeypad.style(keyboardType: .decimalPad, contentType: nil, isPad: false,
                                           decimalSeparator: Locale(identifier: "vi_VN").decimalSeparator),
                       .decimal(separator: ","))
        XCTAssertEqual(NumericKeypad.style(keyboardType: .decimalPad, contentType: nil, isPad: false,
                                           decimalSeparator: Locale(identifier: "en_US").decimalSeparator),
                       .decimal(separator: "."))
    }

    func testCornerKeysAndHoldChoices() {
        XCTAssertEqual(NumericKeypad.corner(style: .digits, needsGlobe: false), [.letters])
        XCTAssertEqual(NumericKeypad.corner(style: .digits, needsGlobe: true), [.globe, .letters])
        XCTAssertEqual(NumericKeypad.corner(style: .decimal(separator: ","), needsGlobe: false),
                       [.letters, .text(",")])
        XCTAssertEqual(NumericKeypad.corner(style: .phone, needsGlobe: false),
                       [.letters, .text("*"), .text("#")])
        XCTAssertEqual(NumericKeypad.holdChoices(for: "0", style: .phone), ["+"])
        XCTAssertEqual(NumericKeypad.holdChoices(for: "0", style: .digits), [])
        XCTAssertEqual(NumericKeypad.holdChoices(for: ",", style: .decimal(separator: ",")), ["."])
        XCTAssertEqual(NumericKeypad.holdChoices(for: ".", style: .decimal(separator: ".")), [","])
        XCTAssertEqual(NumericKeypad.letters(under: "2", style: .digits), "ABC")
        XCTAssertEqual(NumericKeypad.letters(under: "7", style: .digits), "PQRS")
        XCTAssertEqual(NumericKeypad.letters(under: "1", style: .digits), "")
        XCTAssertEqual(NumericKeypad.letters(under: "0", style: .digits), "")
        XCTAssertEqual(NumericKeypad.letters(under: "0", style: .phone), "+")
    }

    // MARK: hình học (thuần)

    func testGeometryAcrossWidths() {
        let m: CGFloat = 6.5, gap: CGFloat = 6
        for w: CGFloat in [320, 375, 390, 402, 430, 440] {        // iPhone dọc
            XCTAssertEqual(NumericKeypad.sideMargin(keysWidth: w, margin: m), m)
            let c = NumericKeypad.cellWidth(keysWidth: w, margin: m, gap: gap)
            XCTAssertEqual(3 * c + 2 * gap + 2 * m, w, accuracy: 0.001)
            XCTAssertGreaterThan(c, 90)                             // ô to như stock
        }
        for w: CGFloat in [667, 740, 801, 852, 932] {              // ngang / máy gập mở
            let side = NumericKeypad.sideMargin(keysWidth: w, margin: m)
            XCTAssertEqual(w - 2 * side, NumericKeypad.maxWidth, accuracy: 0.001)
            let c = NumericKeypad.cellWidth(keysWidth: w, margin: m, gap: gap)
            XCTAssertLessThanOrEqual(c, 190)
        }
        // Một tay: vùng phím hẹp hơn vẫn đủ 3 ô.
        let one = 390 * OneHand.ratio
        XCTAssertEqual(3 * NumericKeypad.cellWidth(keysWidth: one, margin: m, gap: gap) + 2 * gap + 2 * m,
                       one, accuracy: 0.001)
        XCTAssertEqual(NumericKeypad.typography(landscape: false).letters, 10)
        XCTAssertEqual(NumericKeypad.typography(landscape: true).letters, 0)
    }

    // MARK: KeyboardView thật

    @MainActor private func makeKeyboard(_ style: NumericKeypad.Style?, kind: KeyboardView.InputKind = .number,
                                         width: CGFloat = 390, height: CGFloat = 320, globe: Bool = false,
                                         oneHand: OneHandSide = .off,
                                         onKey: @escaping (KeyboardView.Key) -> Void = { _ in })
        -> (KeyboardView, UIView) {
        let kb = KeyboardView(needsGlobe: globe, inputController: nil, onKey: onKey)
        let host = UIView(frame: CGRect(x: 0, y: 0, width: width, height: height))
        host.addSubview(kb)
        kb.frame = host.bounds
        kb.configureOneHand(oneHand)
        kb.configureInputKind(kind, keypad: style)
        kb.setNeedsLayout(); kb.layoutIfNeeded()
        return (kb, host)
    }

    private func frame(_ kb: KeyboardView, _ c: UIControl) -> CGRect { kb.convert(c.bounds, from: c) }

    @MainActor func testDigitsKeypadLayout() throws {
        try XCTSkipIf(isPad, "iPad không dùng bàn số lớn")
        let (kb, _) = makeKeyboard(.digits)
        XCTAssertTrue(kb.keypadShown)
        XCTAssertEqual(kb.debugRowLabels(), [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"],
                                             ["Chữ", "0", "Xoá"]])
        XCTAssertEqual(kb.debugKeypadLetters("2"), "ABC")
        XCTAssertEqual(kb.debugKeypadLetters("9"), "WXYZ")
        XCTAssertEqual(kb.debugKeypadLetters("1"), "")
        let one = try XCTUnwrap(kb.debugKeypadKey("1"))
        let f1 = frame(kb, one)
        let cell = NumericKeypad.cellWidth(keysWidth: 390, margin: KeyGeometry.sideMargin(pad: false), gap: 6)
        XCTAssertEqual(f1.width, cell, accuracy: 0.5)
        // Mọi ô cùng cỡ, thẳng cột: 0 dưới 8, ABC dưới 7, ⌫ dưới 9.
        for (top, bottom) in [("8", "0"), ("7", "Chữ"), ("9", "Xoá")] {
            let a = frame(kb, try XCTUnwrap(kb.debugKeypadKey(top)))
            let b = frame(kb, try XCTUnwrap(kb.debugKeypadKey(bottom)))
            XCTAssertEqual(a.midX, b.midX, accuracy: 0.5, bottom)
            XCTAssertEqual(a.width, b.width, accuracy: 0.5, bottom)
        }
        let rows = kb.debugRowFrames()
        XCTAssertEqual(rows.count, 4)
        for r in rows { XCTAssertEqual(r.height, rows[0].height, accuracy: 0.5) }
        // Không phím cách / return / emoji.
        XCTAssertNil(kb.debugControl(L("Dấu cách")))
        XCTAssertNil(kb.debugControl("Emoji"))
    }

    @MainActor func testDigitOutputAndABCRoundTrip() throws {
        try XCTSkipIf(isPad)
        var got: [KeyboardView.Key] = []
        let (kb, _) = makeKeyboard(.digits, onKey: { got.append($0) })
        for d in ["1", "0", "9"] {
            let k = try XCTUnwrap(kb.debugKeypadKey(d))
            k.sendActions(for: .touchDown); k.sendActions(for: .touchUpInside)
        }
        XCTAssertEqual(got.compactMap { if case .text(let s) = $0 { return s } else { return nil } },
                       ["1", "0", "9"])
        // ABC → bàn chữ; "123" ở bàn chữ → quay lại bàn số lớn (không plane 123).
        try XCTUnwrap(kb.debugKeypadKey("Chữ")).sendActions(for: .touchDown)
        kb.layoutIfNeeded()
        XCTAssertEqual(kb.debugPlaneName, "letters")
        XCTAssertFalse(kb.keypadShown)
        try XCTUnwrap(kb.debugControl(L("Số"))).sendActions(for: .touchDown)
        kb.layoutIfNeeded()
        XCTAssertTrue(kb.keypadShown)
        XCTAssertEqual(kb.debugKeypadLetters("2"), "ABC")       // khôi phục từ cache vẫn đủ nhãn
        XCTAssertNotNil(kb.debugKeypadKey("Xoá"))
    }

    @MainActor func testDecimalKeypadSeparatorAndHold() throws {
        try XCTSkipIf(isPad)
        var got: [String] = []
        let (kb, _) = makeKeyboard(.decimal(separator: ","), onKey: {
            if case .text(let s) = $0 { got.append(s) }
        })
        XCTAssertEqual(kb.debugRowLabels().last, ["Chữ", ",", "0", "Xoá"])
        let sep = try XCTUnwrap(kb.debugKeypadKey(","))
        let abc = try XCTUnwrap(kb.debugKeypadKey("Chữ"))
        let zero = try XCTUnwrap(kb.debugKeypadKey("0"))
        XCTAssertEqual(frame(kb, sep).width, frame(kb, abc).width, accuracy: 0.5)
        XCTAssertEqual(frame(kb, abc).width + 6 + frame(kb, sep).width, frame(kb, zero).width, accuracy: 0.5)
        sep.sendActions(for: .touchDown); sep.sendActions(for: .touchUpInside)
        kb.debugKeypadHold(",")
        XCTAssertEqual(got, [",", "."])
    }

    @MainActor func testPhoneKeypadStarHashAndPlus() throws {
        try XCTSkipIf(isPad)
        var got: [String] = []
        let (kb, _) = makeKeyboard(.phone, onKey: { if case .text(let s) = $0 { got.append(s) } })
        XCTAssertEqual(kb.debugRowLabels().last, ["Chữ", "*", "#", "0", "Xoá"])
        XCTAssertEqual(kb.debugKeypadLetters("0"), "+")
        kb.debugKeypadHold("0")
        let star = try XCTUnwrap(kb.debugKeypadKey("*"))
        star.sendActions(for: .touchDown); star.sendActions(for: .touchUpInside)
        XCTAssertEqual(got, ["+", "*"])
    }

    /// "Phím sẫm khi bấm": BẬT ⇒ phím số sẫm khi đè; TẮT ⇒ không màu đè (balloon theo phóng to).
    @MainActor func testPressHighlightFollowsSetting() throws {
        try XCTSkipIf(isPad)
        let (kb, _) = makeKeyboard(.decimal(separator: "."))
        for label in ["5", "."] {
            let k = try XCTUnwrap(kb.debugKeypadKey(label) as? KeyboardView.KeyButton)
            XCTAssertNotNil(kb.debugKeyColors(k).pressed, label)
        }
        kb.keyPressHighlightEnabled = false
        kb.layoutIfNeeded()
        for label in ["5", "."] {
            let k = try XCTUnwrap(kb.debugKeypadKey(label) as? KeyboardView.KeyButton)
            XCTAssertNil(kb.debugKeyColors(k).pressed, label)
            k.sendActions(for: .touchDown); k.sendActions(for: .touchCancel)
            XCTAssertEqual(kb.debugKeyColors(k).current, kb.debugKeyColors(k).normal, label)
        }
    }

    @MainActor func testGlobeJoinsCornerWhenNeeded() throws {
        try XCTSkipIf(isPad)
        let (kb, _) = makeKeyboard(.digits, globe: true)
        XCTAssertEqual(kb.debugRowLabels().last, [L("Bàn phím tiếp theo"), "Chữ", "0", "Xoá"])
    }

    @MainActor func testOTPKeypadOnNormalKind() throws {
        try XCTSkipIf(isPad)
        let (kb, _) = makeKeyboard(.digits, kind: .normal)
        XCTAssertTrue(kb.keypadShown)
        // Đổi sang ô thường (không bàn số) → bàn chữ.
        kb.configureInputKind(.normal, keypad: nil)
        kb.layoutIfNeeded()
        XCTAssertEqual(kb.debugPlaneName, "letters")
        // numberPad → bàn số lớn; numbersAndPunctuation (keypad nil) → plane 123 cũ.
        kb.configureInputKind(.number, keypad: .digits); kb.layoutIfNeeded()
        XCTAssertTrue(kb.keypadShown)
        kb.configureInputKind(.number, keypad: nil); kb.layoutIfNeeded()
        XCTAssertEqual(kb.debugPlaneName, "numbers")
    }

    @MainActor func testLandscapeCentersAndHidesLetters() throws {
        try XCTSkipIf(isPad)
        let (kb, host) = makeKeyboard(.digits, width: 852, height: 200)
        let one = frame(kb, try XCTUnwrap(kb.debugKeypadKey("1")))
        let three = frame(kb, try XCTUnwrap(kb.debugKeypadKey("3")))
        XCTAssertEqual(three.maxX - one.minX, NumericKeypad.maxWidth, accuracy: 0.5)
        XCTAssertEqual((one.minX + three.maxX) / 2, 426, accuracy: 0.5)   // căn giữa
        XCTAssertEqual(kb.debugKeypadLetters("2"), "")                     // ngang: bỏ dòng chữ
        // Xoay về dọc (không dựng lại plane): lề + chữ cái cập nhật tại chỗ.
        host.frame.size = CGSize(width: 390, height: 320)
        kb.frame = host.bounds
        kb.setNeedsLayout(); kb.layoutIfNeeded()
        let one2 = frame(kb, try XCTUnwrap(kb.debugKeypadKey("1")))
        XCTAssertEqual(one2.minX, KeyGeometry.sideMargin(pad: false), accuracy: 0.5)
        XCTAssertEqual(kb.debugKeypadLetters("2"), "ABC")
    }

    @MainActor func testOneHandNarrowsKeypad() throws {
        try XCTSkipIf(isPad)
        let (kb, _) = makeKeyboard(.digits, oneHand: .right)
        XCTAssertTrue(kb.debugOneHandActive)
        let span = 390 * OneHand.ratio
        let one = frame(kb, try XCTUnwrap(kb.debugKeypadKey("1")))
        let back = frame(kb, try XCTUnwrap(kb.debugKeypadKey("Xoá")))
        XCTAssertGreaterThanOrEqual(one.minX, 390 - span - 0.5)
        XCTAssertLessThanOrEqual(back.maxX, 390 + 0.5)
        XCTAssertEqual(one.width, NumericKeypad.cellWidth(keysWidth: span, margin: KeyGeometry.sideMargin(pad: false),
                                                          gap: 6), accuracy: 0.5)
    }

    @MainActor func testSplitSettingDoesNotSplitKeypad() throws {
        try XCTSkipIf(isPad)
        let (kb, _) = makeKeyboard(.digits, width: 801, height: 260)
        kb.debugSetSplit(true)
        kb.layoutIfNeeded()
        XCTAssertTrue(kb.keypadShown)
        XCTAssertEqual(kb.debugRowLabels().first, ["1", "2", "3"])
    }

    @MainActor func testGapTapRoutesToNearestKeypadKey() throws {
        try XCTSkipIf(isPad)
        let (kb, _) = makeKeyboard(.digits)
        let five = try XCTUnwrap(kb.debugKeypadKey("5"))
        let f = frame(kb, five)
        // Khe ngay trên phím 5 (giữa hàng 2 và hàng 5) → phím 5 (router khe, không vùng chết).
        let hit = kb.hitTest(CGPoint(x: f.midX, y: f.minY - 2), with: nil)
        XCTAssertTrue(hit === five || hit === kb.debugKeypadKey("2"))
    }

    // MARK: 📋 Dán (báo lỗi 13/11/2026: bàn số không có cách dán số điện thoại vừa copy)

    func testCornerPasteOnlyWhenEnabled() {
        XCTAssertEqual(NumericKeypad.corner(style: .digits, needsGlobe: false, paste: true), [.letters, .paste])
        XCTAssertEqual(NumericKeypad.corner(style: .phone, needsGlobe: true, paste: true),
                       [.globe, .letters, .text("*"), .text("#"), .paste])
        XCTAssertFalse(NumericKeypad.corner(style: .digits, needsGlobe: false).contains(.paste))
    }

    func testCleanPastePerStyle() {
        XCTAssertEqual(NumericKeypad.cleanPaste("0903 389 710", style: .digits), "0903389710")
        XCTAssertEqual(NumericKeypad.cleanPaste("+84 903-389-710", style: .phone), "+84903389710")
        XCTAssertEqual(NumericKeypad.cleanPaste("+84 903-389-710", style: .digits), "84903389710")
        XCTAssertEqual(NumericKeypad.cleanPaste(" *101# ", style: .phone), "*101#")
        XCTAssertEqual(NumericKeypad.cleanPaste("09+03", style: .phone), "0903")
        XCTAssertEqual(NumericKeypad.cleanPaste("０９０３", style: .digits), "0903")
        XCTAssertEqual(NumericKeypad.cleanPaste("1 234,5", style: .decimal(separator: ",")), "1234,5")
        XCTAssertEqual(NumericKeypad.cleanPaste("1.000.000 đ", style: .digits), "1000000")
        XCTAssertEqual(NumericKeypad.cleanPaste("xin chào", style: .phone), "")
        XCTAssertEqual(NumericKeypad.cleanPaste("+", style: .phone), "")
        XCTAssertEqual(NumericKeypad.cleanPaste(nil, style: .digits), "")
    }
}
