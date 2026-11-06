import XCTest

/// "Phím to" (LargeKeys, mặc định TẮT): "," "." hàng đáy rộng bằng phím emoji, ⇧ / ⌫ hàng Z
/// lấp khe. Hình học thuần — dựng hàng y như KeyboardView.bottomRow / buildLetters.
final class LargeKeysTests: XCTestCase {
    typealias Span = LargeKeys.Span

    /// (bề ngang, lề, khe, có 🌐) — dọc 375 SE (nút Home ⇒ 🌐), 390/393/402, máy lớn 430/440, ngang.
    struct Phone { let name: String; let width, margin, gap: CGFloat; let globe: Bool }
    static let phones: [Phone] = {
        let p = KeyGeometry.StockSize.standardPortrait, l = KeyGeometry.StockSize.largePortrait
        let se = KeyGeometry.StockSize.homeButtonPortrait, land = KeyGeometry.StockSize.landscape
        let seLand = KeyGeometry.StockSize.homeButtonLandscape
        return [
            Phone(name: "SE 375", width: 375, margin: se.sideMargin, gap: se.keyGap, globe: true),
            Phone(name: "390", width: 390, margin: p.sideMargin, gap: p.keyGap, globe: false),
            Phone(name: "393", width: 393, margin: p.sideMargin, gap: p.keyGap, globe: false),
            Phone(name: "402", width: 402, margin: p.sideMargin, gap: p.keyGap, globe: false),
            Phone(name: "430", width: 430, margin: l.sideMargin, gap: l.keyGap, globe: false),
            Phone(name: "440", width: 440, margin: l.sideMargin, gap: l.keyGap, globe: false),
            Phone(name: "SE ngang 667", width: 667, margin: seLand.sideMargin, gap: seLand.keyGap, globe: true),
            Phone(name: "ngang 844", width: 844, margin: land.sideMargin, gap: land.keyGap, globe: false),
            Phone(name: "ngang 956", width: 956, margin: land.sideMargin, gap: land.keyGap, globe: false),
        ]
    }()

    private func u(_ id: String) -> CGFloat { KeyLayout.units(id, in: KeyLayout.phoneBottom)! }

    /// Hàng đáy iPhone như KeyboardView.bottomRow: [123][🌐?][😊?][trái][space][phải][return].
    /// Trả (spans, chỉ số space, chỉ số các phím dấu câu, chỉ số emoji/123).
    private func bottomRow(_ ph: Phone, left: [(String, CGFloat)], right: [(String, CGFloat)],
                           emoji: Bool = true, on: Bool)
        -> (spans: [Span], space: Int, puncts: [Int], emoji: Int?, plane: Int) {
        var units: [CGFloat?] = [u("plane")]
        if ph.globe { units.append(u("globe")) }
        var emojiIdx: Int?
        if emoji { emojiIdx = units.count; units.append(u("emoji")) }
        let others = units.compactMap { $0 }.reduce(0, +) + u("return")
        let widths = LargeKeys.punctUnits((left + right).map { (title: $0.0, units: $0.1) },
                                          otherUnits: others, on: on)
        var puncts: [Int] = []
        for w in widths.prefix(left.count) { puncts.append(units.count); units.append(w) }
        let space = units.count
        units.append(nil)
        for w in widths.dropFirst(left.count) { puncts.append(units.count); units.append(w) }
        units.append(u("return"))
        let spans = LargeKeys.rowSpans(width: ph.width, margin: ph.margin,
                                       gaps: Array(repeating: ph.gap, count: units.count - 1), units: units)
        return (spans, space, puncts, emojiIdx, 0)
    }

    private func letterSides(_ side: SpaceSideKey) -> (left: [(String, CGFloat)], right: [(String, CGFloat)]) {
        let s = KeyLayout.phoneLettersSides(side)
        return (s.left.map { ($0, KeyLayout.phoneLettersComma) }, s.right.map { ($0, KeyLayout.phoneLettersComma) })
    }

    private func assertRowSound(_ spans: [Span], _ ph: Phone, gap: CGFloat, _ msg: String,
                                file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(spans.first!.x, ph.margin, accuracy: 0.001, msg, file: file, line: line)
        XCTAssertEqual(spans.last!.maxX, ph.width - ph.margin, accuracy: 0.001, "lấp kín hàng — \(msg)", file: file, line: line)
        for (a, b) in zip(spans, spans.dropFirst()) {
            XCTAssertGreaterThan(a.width, 0, msg, file: file, line: line)
            XCTAssertLessThanOrEqual(a.maxX, b.x + 0.001, "chồng phím — \(msg)", file: file, line: line)
            XCTAssertEqual(b.x - a.maxX, gap, accuracy: 0.6, "khe — \(msg)", file: file, line: line)
        }
    }

    private func assertSame(_ a: Span, _ b: Span, _ msg: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.x, b.x, accuracy: 0.001, msg, file: file, line: line)
        XCTAssertEqual(a.width, b.width, accuracy: 0.001, msg, file: file, line: line)
    }

    // MARK: Tắt = y như cũ

    func testDefaultIsOff() {
        XCTAssertFalse(LargeKeys.defaultValue)
        XCTAssertFalse(LargeKeys.load(nil))
        let d = UserDefaults(suiteName: "LargeKeysTests")!
        d.removePersistentDomain(forName: "LargeKeysTests")
        XCTAssertFalse(LargeKeys.load(d))
        d.set(true, forKey: LargeKeys.key)
        XCTAssertTrue(LargeKeys.load(d))
        d.removePersistentDomain(forName: "LargeKeysTests")
    }

    func testOffKeepsUnitsAndGaps() {
        let cases: [[(title: String, units: CGFloat)]] = [
            [(",", KeyLayout.phoneLettersComma)], [(".", KeyLayout.phoneLettersComma)],
            [(",", KeyLayout.phoneLettersComma), (".", KeyLayout.phoneLettersComma)],
            [("@", 0.11), (".", 0.09)], [(".", 0.075), ("/", 0.075)], [(",", 0.083)], [],
        ]
        for c in cases {
            XCTAssertEqual(LargeKeys.punctUnits(c, otherUnits: 0.372, on: false), c.map(\.units))
        }
        XCTAssertEqual(LargeKeys.shiftGap(on: false, standard: KeyboardView.shiftGap, keyGap: 6), KeyboardView.shiftGap)
        XCTAssertEqual(LargeKeys.shiftGap(on: true, standard: KeyboardView.shiftGap, keyGap: 6), 6)
    }

    /// Tắt: hàng Z = công thức cũ (⇧ = ⌫ = (W − 2·lề − 7 chữ − 6 khe − 2·12)/2).
    func testZRowOffMatchesCurrentLayout() {
        for ph in Self.phones {
            let s = LargeKeys.zRowSpans(width: ph.width, margin: ph.margin, keyGap: ph.gap,
                                        standardShiftGap: KeyboardView.shiftGap, on: false)
            let letter = (ph.width - 2 * ph.margin - 9 * ph.gap) / 10
            let side = (ph.width - 2 * ph.margin - 7 * letter - 6 * ph.gap - 2 * KeyboardView.shiftGap) / 2
            XCTAssertEqual(s.count, 9)
            XCTAssertEqual(s[0].width, side, accuracy: 0.001, ph.name)
            XCTAssertEqual(s[8].width, side, accuracy: 0.001, ph.name)
            XCTAssertEqual(s[1].x - s[0].maxX, KeyboardView.shiftGap, accuracy: 0.001, ph.name)
            XCTAssertEqual(s[8].maxX, ph.width - ph.margin, accuracy: 0.001, ph.name)
        }
    }

    // MARK: Bật — hàng đáy

    func testPunctTargetIsEmojiAnd123Width() {
        XCTAssertEqual(LargeKeys.punctUnits, u("emoji"))
        XCTAssertEqual(LargeKeys.punctUnits, u("plane"))
    }

    /// Mọi chế độ "Phím cạnh dấu cách" (plane chữ ô thường): "," / "." = bề rộng phím emoji
    /// (trừ SE có 🌐 + "Cả hai" — bị chặn để space đủ rộng, vẫn rộng hơn lúc tắt).
    func testLettersPlanePunctMatchesEmojiWidth() {
        for ph in Self.phones {
            for side in SpaceSideKey.allCases {
                let s = letterSides(side)
                let on = bottomRow(ph, left: s.left, right: s.right, on: true)
                let off = bottomRow(ph, left: s.left, right: s.right, on: false)
                let msg = "\(ph.name) \(side)"
                assertRowSound(on.spans, ph, gap: ph.gap, msg)
                assertRowSound(off.spans, ph, gap: ph.gap, msg)
                let emojiW = on.spans[on.emoji!].width
                let capped = ph.globe && side == .both
                for i in on.puncts {
                    if capped {
                        XCTAssertGreaterThan(on.spans[i].width, off.spans[i].width, msg)
                        XCTAssertLessThan(on.spans[i].width, emojiW, msg)
                    } else {
                        XCTAssertEqual(on.spans[i].width, emojiW, accuracy: 0.001, msg)
                    }
                }
                // Phím khác không đổi chỗ / cỡ ngoài space và dấu câu: 123 + return giữ nguyên.
                assertSame(on.spans[0], off.spans[0], msg)
                assertSame(on.spans.last!, off.spans.last!, msg)
                XCTAssertLessThanOrEqual(on.spans[on.space].width, off.spans[on.space].width, msg)
                XCTAssertGreaterThanOrEqual(on.spans[on.space].width, 80, "space quá hẹp — \(msg)")
            }
        }
    }

    /// Space không dưới mức tối thiểu ở mọi plane / ô (gồm chật nhất: SE 🌐 + Cả hai).
    func testSpaceKeepsMinimumEverywhere() {
        let rows: [(String, [(String, CGFloat)], [(String, CGFloat)], Bool)] = [
            ("plane số/ký hiệu", [], [(",", KeyLayout.units("comma", in: KeyLayout.phoneBottom)!)], true),
            ("mẫu câu (🗑 thay 😊)", [], [(",", KeyLayout.units("comma", in: KeyLayout.phoneBottom)!)], true),
            ("email", [], [("@", 0.11), (".", 0.09)], true),
            ("url", [], [(".", 0.075), ("/", 0.075)], true),
            ("địa chỉ", [], [(".", 0.075)], true),
            ("Cả hai + emoji trên thanh", [(",", KeyLayout.phoneLettersComma)], [(".", KeyLayout.phoneLettersComma)], false),
        ]
        for ph in Self.phones {
            for (name, l, r, emoji) in rows {
                let on = bottomRow(ph, left: l, right: r, emoji: emoji, on: true)
                let off = bottomRow(ph, left: l, right: r, emoji: emoji, on: false)
                let msg = "\(ph.name) \(name)"
                assertRowSound(on.spans, ph, gap: ph.gap, msg)
                // ≥ 80pt, hoặc đúng như lúc tắt (SE có 🌐 ô email: space vốn ~74 — không đổi).
                let sp = on.spans[on.space].width
                XCTAssertTrue(sp >= 80 || abs(sp - off.spans[off.space].width) < 0.001, "\(msg): \(sp)")
                let titles = (l + r).map(\.0)
                for (k, i) in on.puncts.enumerated() {
                    if LargeKeys.widens(titles[k]) {
                        XCTAssertGreaterThanOrEqual(on.spans[i].width, off.spans[i].width - 0.001, msg)
                    } else {
                        XCTAssertEqual(on.spans[i].width, off.spans[i].width, accuracy: 0.001, "\(titles[k]) giữ nguyên — \(msg)")
                    }
                }
            }
        }
    }

    // MARK: Bật — hàng Z

    func testZRowShiftAndBackspaceFillGap() {
        for ph in Self.phones {
            let off = LargeKeys.zRowSpans(width: ph.width, margin: ph.margin, keyGap: ph.gap,
                                          standardShiftGap: KeyboardView.shiftGap, on: false)
            let on = LargeKeys.zRowSpans(width: ph.width, margin: ph.margin, keyGap: ph.gap,
                                         standardShiftGap: KeyboardView.shiftGap, on: true)
            assertRowSound(on, ph, gap: ph.gap, ph.name)
            // Chữ z…m giữ nguyên cỡ và vị trí.
            for i in 1...7 { assertSame(on[i], off[i], "\(ph.name) chữ \(i)") }
            // ⇧ / ⌫ nở đúng phần khe thừa, sát khe chữ.
            let grow = KeyboardView.shiftGap - ph.gap
            XCTAssertEqual(on[0].width, off[0].width + grow, accuracy: 0.001, ph.name)
            XCTAssertEqual(on[8].width, off[8].width + grow, accuracy: 0.001, ph.name)
            XCTAssertEqual(on[0].x, off[0].x, accuracy: 0.001, ph.name)
            XCTAssertEqual(on[8].maxX, off[8].maxX, accuracy: 0.001, ph.name)
            XCTAssertEqual(on[1].x - on[0].maxX, ph.gap, accuracy: 0.001, ph.name)
            XCTAssertEqual(on[8].x - on[7].maxX, ph.gap, accuracy: 0.001, ph.name)
        }
    }

    // MARK: KeyboardView thật (iPhone) — frame sau Auto Layout khớp mô hình

    @MainActor private func makeKeyboard(width: CGFloat, side: SpaceSideKey, large: Bool) -> (KeyboardView, UIView) {
        let kb = KeyboardView(needsGlobe: false, inputController: nil) { _ in }
        let host = UIView(frame: CGRect(x: 0, y: 0, width: width, height: 320))
        host.addSubview(kb)
        kb.frame = host.bounds
        kb.spaceSideKey = side
        kb.largeKeys = large
        kb.layoutIfNeeded()
        return (kb, host)
    }

    private func frame(_ v: UIView?, in kb: KeyboardView) throws -> CGRect {
        let v = try XCTUnwrap(v)
        return kb.convert(v.bounds, from: v)
    }

    /// Phím có nhãn `t` (không phân biệt hoa thường) nằm thấp nhất (hàng đáy nếu có nhiều).
    @MainActor private func key(_ t: String, in kb: KeyboardView) throws -> CGRect {
        let bs = kb.debugAllKeyButtons().filter { ($0.currentTitle ?? "").lowercased() == t }
        let f = bs.map { kb.convert($0.bounds, from: $0) }.max { $0.minY < $1.minY }
        return try XCTUnwrap(f, "không thấy phím \(t)")
    }

    @MainActor func testKeyboardViewFramesFollowSetting() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom == .pad, "iPad không đổi")
        for side in [SpaceSideKey.comma, .both] {
            let (off, h0) = makeKeyboard(width: 393, side: side, large: false)
            let (on, h1) = makeKeyboard(width: 393, side: side, large: true)
            let emoji = try frame(on.debugControl("Emoji"), in: on)
            let comma = try key(",", in: on)
            let commaOff = try key(",", in: off)
            XCTAssertEqual(commaOff.width, 393 * KeyLayout.phoneLettersComma, accuracy: 0.5, "tắt = như cũ")
            XCTAssertEqual(comma.width, emoji.width, accuracy: 0.5, "\(side): ',' = 😊")
            if side == .both {
                XCTAssertEqual(try key(".", in: on).width, emoji.width, accuracy: 0.5)
            }
            let space = try frame(on.debugControl("Dấu cách"), in: on)
            let spaceOff = try frame(off.debugControl("Dấu cách"), in: off)
            XCTAssertLessThan(space.width, spaceOff.width)
            XCTAssertGreaterThan(space.width, 100)
            XCTAssertLessThanOrEqual(comma.maxX, try frame(on.debugControl("Xuống dòng"), in: on).minX)
            // Hàng Z: ⇧ / ⌫ nở, z / m không dời.
            let sh = try frame(on.debugControl("Shift"), in: on), shOff = try frame(off.debugControl("Shift"), in: off)
            let bk = try frame(on.debugControl("Xoá"), in: on), bkOff = try frame(off.debugControl("Xoá"), in: off)
            let z = try key("z", in: on), zOff = try key("z", in: off)
            let m = try key("m", in: on), mOff = try key("m", in: off)
            XCTAssertEqual(z.minX, zOff.minX, accuracy: 0.5); XCTAssertEqual(z.width, zOff.width, accuracy: 0.5)
            XCTAssertEqual(m.minX, mOff.minX, accuracy: 0.5)
            let grow = KeyboardView.shiftGap - KeyGeometry.StockSize.standardPortrait.keyGap
            XCTAssertEqual(sh.width, shOff.width + grow, accuracy: 0.5)
            XCTAssertEqual(bk.width, bkOff.width + grow, accuracy: 0.5)
            XCTAssertEqual(z.minX - sh.maxX, KeyGeometry.StockSize.standardPortrait.keyGap, accuracy: 0.5)
            XCTAssertEqual(bk.minX - m.maxX, KeyGeometry.StockSize.standardPortrait.keyGap, accuracy: 0.5)
            // Plane số: "," hàng đáy cũng = 😊.
            on.debugSetPlane(numbers: true); on.layoutIfNeeded()
            let nComma = try key(",", in: on)
            let nEmoji = try frame(on.debugControl("Emoji"), in: on)
            XCTAssertEqual(nComma.width, nEmoji.width, accuracy: 0.5, "plane số")
            // Tắt lại khi đang hiện ⇒ dựng lại như cũ.
            on.debugSetPlane(numbers: false); on.largeKeys = false
            on.setNeedsLayout(); on.layoutIfNeeded(); on.setNeedsLayout(); on.layoutIfNeeded()
            XCTAssertEqual(try key(",", in: on).width, commaOff.width, accuracy: 0.5)
            withExtendedLifetime((h0, h1)) {}
        }
    }

    /// Số đo cho báo cáo (393 / 440 dọc, comma mặc định + Cả hai).
    func testReportNumbers() {
        for ph in Self.phones where ph.name == "393" || ph.name == "440" {
            for side in [SpaceSideKey.comma, .both] {
                let s = letterSides(side)
                for on in [false, true] {
                    let r = bottomRow(ph, left: s.left, right: s.right, on: on)
                    let z = LargeKeys.zRowSpans(width: ph.width, margin: ph.margin, keyGap: ph.gap,
                                                standardShiftGap: KeyboardView.shiftGap, on: on)
                    let fmt: (CGFloat) -> String = { String(format: "%.1f", $0) }
                    print("LARGEKEYS \(ph.name) \(side) on=\(on): punct=\(r.puncts.map { fmt(r.spans[$0].width) }) "
                          + "space=\(fmt(r.spans[r.space].width)) emoji=\(fmt(r.spans[r.emoji!].width)) "
                          + "shift=\(fmt(z[0].width)) letter=\(fmt(z[1].width))")
                }
            }
        }
    }

    /// "Cỡ phím chấm và phẩy" ẩn khi "Phím cạnh dấu cách" = Tắt (06/11/2026).
    func testSettingHiddenWhenSideKeyOff() {
        XCTAssertFalse(LargeKeys.settingVisible(.off))
        for s in [SpaceSideKey.comma, .period, .both] { XCTAssertTrue(LargeKeys.settingVisible(s)) }
    }
}
