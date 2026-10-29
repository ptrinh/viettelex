import XCTest
import UIKit

/// "Chiều cao thanh gợi ý" (SuggestionBarHeight, khoá `suggestionBarHeight`: low/medium/high,
/// mặc định medium) — Phil 18/10/2026: bar 30pt thấp, chạm nhầm. Bàn phím chỉ cộng delta vào strip
/// mở: tổng cao tăng ĐÚNG delta, hàng phím / thu gọn / tắt giữ nguyên. Song sinh Android
/// SuggestionBarHeightTests.kt.
final class SuggestionBarHeightTests: XCTestCase {
    typealias H = SuggestionBarHeight

    // MARK: Hàm thuần

    func testParseAndDefault() {
        XCTAssertEqual(H.defaultValue, .medium)
        XCTAssertEqual(H.parse(nil), .medium)
        XCTAssertEqual(H.parse("low"), .low)
        XCTAssertEqual(H.parse("medium"), .medium)
        XCTAssertEqual(H.parse("high"), .high)
        XCTAssertEqual(H.parse("tall"), .medium, "giá trị lạ ⇒ Vừa")
        XCTAssertEqual(H.parse(2), .medium, "sai kiểu ⇒ Vừa")
        let d = UserDefaults(suiteName: "vt-bar-height")!
        d.removePersistentDomain(forName: "vt-bar-height")
        XCTAssertEqual(H.load(d), .medium)
        d.set("high", forKey: H.key)
        XCTAssertEqual(H.load(d), .high)
        d.removePersistentDomain(forName: "vt-bar-height")
    }

    func testNominalDeltaAndLandscapeCap() {
        XCTAssertEqual(H.allCases.map(\.nominal), [30, 36, 44])
        XCTAssertEqual(H.allCases.map { $0.delta(landscape: false) }, [0, 6, 14])
        XCTAssertEqual(H.allCases.map { $0.delta(landscape: true) }, [0, 6, 6], "ngang: Cao kẹp về Vừa")
        XCTAssertEqual(H.allCases.map { $0.rowHeight(landscape: false) }, [20, 26, 34])
        XCTAssertEqual(H.allCases.map { $0.slotFontSize(landscape: false) }, [17, 18, 19])
        XCTAssertEqual(H.allCases.map { $0.chipFontSize(landscape: false) }, [14, 15, 15])
        XCTAssertEqual(H.high.slotFontSize(landscape: true), 18)
    }

    /// Ảnh nền (app) cắt theo đúng chiều cao bàn phím: strip cộng delta.
    func testWallpaperSizeFollowsBarHeight() {
        let screen = CGSize(width: 402, height: 874)
        let low = Wallpaper.keyboardSize(screenSize: screen, pad: false, landscape: false, rowHeightAdjust: 0,
                                         numberRow: false, suggestions: true, barHeight: .low)
        XCTAssertEqual(low.height, 212 + 29, "Thấp = bố cục cũ")
        for h in H.allCases {
            let s = Wallpaper.keyboardSize(screenSize: screen, pad: false, landscape: false, rowHeightAdjust: 0,
                                           numberRow: false, suggestions: true, barHeight: h)
            XCTAssertEqual(s.height, low.height + h.delta(landscape: false), "\(h)")
            let off = Wallpaper.keyboardSize(screenSize: screen, pad: false, landscape: false, rowHeightAdjust: 0,
                                             numberRow: false, suggestions: false, barHeight: h)
            XCTAssertEqual(off.height, 212, "tắt gợi ý: không strip, \(h)")
            let land = Wallpaper.keyboardSize(screenSize: screen, pad: false, landscape: true, rowHeightAdjust: 0,
                                              numberRow: false, suggestions: true, barHeight: h)
            XCTAssertEqual(land.height, 196 + h.delta(landscape: true), "ngang \(h)")
        }
    }

    /// Tester 29/10/2026 ("chữ hơi cao lên phía trên, cả icon clipboard nữa"): hàng nội dung bar
    /// ghim ở y=4 ⇒ tâm cao hơn tâm dải thấy được (đỉnh bàn phím → đỉnh phím hàng đầu) ~6pt.
    /// rowTop canh giữa dải đó, không thò xuống dưới strip, không cao hơn đệm trên.
    func testRowTopCentersInVisibleBand() {
        let gap: CGFloat = 11, pad = KeyboardView.barTopPad
        for h in H.allCases {
            let row = h.rowHeight(landscape: false), strip = 29 + h.delta
            let top = H.rowTop(strip: strip, capGap: gap, row: row, topPad: pad)
            XCTAssertLessThanOrEqual(top + row, strip, "\(h): không lấn xuống phím")
            XCTAssertGreaterThanOrEqual(top, pad, "\(h)")
            XCTAssertEqual(top + row / 2, (strip + gap) / 2, accuracy: 1.5, "\(h): tâm hàng ≈ tâm dải thấy được")
            XCTAssertGreaterThan(top, pad, "\(h): bản cũ ghim ở đệm trên ⇒ cao quá")
        }
        // Không có khe trên phím: canh giữa strip.
        XCTAssertEqual(H.rowTop(strip: 40, capGap: 0, row: 20, topPad: 4), 10)
        // Strip chật: không cao hơn đệm trên.
        XCTAssertEqual(H.rowTop(strip: 22, capGap: 0, row: 20, topPad: 4), 4)
    }

    /// Chữ gợi ý (tâm bar), ☰, 📋, 😊 cùng một tâm, và tâm đó ≈ tâm dải đỉnh bàn phím → đỉnh phím
    /// hàng đầu — có / không hàng số, mọi mức chiều cao.
    @MainActor func testTextAndIconsCenteredInVisibleBand() throws {
        let d = try XCTUnwrap(UserDefaultsProvider.shared)
        let saved = (d.object(forKey: "numberRow"), d.object(forKey: "emojiKeyPlacement"))
        defer {
            d.set(saved.0, forKey: "numberRow"); d.set(saved.1, forKey: "emojiKeyPlacement")
        }
        d.set("top", forKey: "emojiKeyPlacement")
        for numberRow in [false, true] {
            d.set(numberRow, forKey: "numberRow")
            let (kb, host) = makeKeyboard(width: isPad ? 834 : 402)
            _ = host
            kb.applyAppearance(.dark, style: .dark)
            kb.setClipboardButton(visible: true)
            kb.showSuggestions(.init(nextWords: ["Có", "Không", "Nó"]))
            for h in H.allCases {
                kb.debugSetBarHeight(h); settle(kb)
                let tag = "\(h) numberRow=\(numberRow)"
                let c = kb.debugBarVerticalCenters()
                XCTAssertNotNil(c.icons["burger"], tag)
                XCTAssertNotNil(c.icons["clip"], tag)
                if !isPad { XCTAssertNotNil(c.icons["emoji"], tag) }
                for (name, y) in c.icons { XCTAssertEqual(y, c.bar, accuracy: 0.5, "\(tag): \(name) lệch tâm chữ") }
                for dv in kb.debugStripLayout().dividers {
                    XCTAssertEqual(dv.midY, c.bar, accuracy: 0.5, "\(tag): vạch ngăn")
                }
                XCTAssertEqual(c.bar, c.capTop / 2, accuracy: 1.5, "\(tag): tâm dải thấy được")
            }
            withExtendedLifetime(kb) {}
        }
    }

    // MARK: View thật

    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    @MainActor private func makeKeyboard(width: CGFloat) -> (KeyboardView, UIView) {
        let kb = KeyboardView(needsGlobe: false, inputController: nil) { _ in }
        let host = UIView(frame: CGRect(x: 0, y: 0, width: width, height: 400))
        host.addSubview(kb)
        kb.frame = CGRect(x: 0, y: 0, width: width, height: 300)
        kb.configureInputKind(.normal)
        kb.setSuggestionsEnabled(true)
        kb.layoutIfNeeded()
        settle(kb)
        return (kb, host)
    }

    /// Host cấp đúng mức xin.
    @MainActor private func settle(_ kb: KeyboardView) {
        kb.frame.size.height = kb.debugRequestedHeight
        kb.setNeedsLayout(); kb.layoutIfNeeded()
    }

    @MainActor private func qHeight(_ kb: KeyboardView) throws -> CGFloat {
        try XCTUnwrap(kb.debugLetterFrame("q")).height
    }

    /// Mỗi mức: tổng cao = Thấp + delta, hàng phím y nguyên, bar cao 20 + delta, vùng chạm ô gợi ý
    /// phủ trọn bar và nở xuống đúng tới mép hàng phím (không lấn Q–P).
    @MainActor func testOpenBarGrowsKeyboardExactlyByDelta() throws {
        var widths: [(CGFloat, Bool)] = [(isPad ? 834 : 390, false)]
        if !isPad { widths.append((874, true)) }   // iPhone ngang
        for (width, landscape) in widths {
            let (kb, host) = makeKeyboard(width: width)
            _ = host
            kb.debugSetBarHeight(.low); settle(kb)
            let h0 = kb.debugRequestedHeight, top0 = kb.debugRowsTop, q0 = try qHeight(kb)
            for h in H.allCases {
                kb.debugSetBarHeight(h); settle(kb)
                let d = h.delta(landscape: landscape)
                let tag = "\(h) w\(width)"
                XCTAssertEqual(kb.debugRequestedHeight, h0 + d, accuracy: 0.01, tag)
                XCTAssertEqual(kb.debugRowsTop, top0 + d, accuracy: 0.01, tag)
                XCTAssertEqual(kb.debugOpenStrip, top0 + d, accuracy: 0.01, tag)
                XCTAssertEqual(try qHeight(kb), q0, accuracy: 0.5, "hàng phím giữ nguyên — \(tag)")
                XCTAssertEqual(kb.debugBarRow, 20 + d, tag)
                let bar = kb.debugStripLayout().bar
                XCTAssertEqual(bar.minY, H.rowTop(strip: kb.debugOpenStrip, capGap: kb.rowSpec.gap,
                                                  row: 20 + d, topPad: KeyboardView.barTopPad), accuracy: 0.01, tag)
                XCTAssertEqual(bar.height, 20 + d, accuracy: 0.01, tag)
                let hit = kb.debugSlotHitRect
                XCTAssertLessThanOrEqual(hit.minY, bar.minY, tag)
                XCTAssertEqual(hit.maxY, kb.debugRowsTop, accuracy: 0.5, "vùng chạm tới mép hàng phím — \(tag)")
                XCTAssertEqual(kb.debugSlotFontSize, h.slotFontSize(landscape: landscape), tag)
            }
            withExtendedLifetime(kb) {}
        }
    }

    /// Tắt gợi ý: chiều cao KHÔNG phụ thuộc mức (trạng thái thu gọn ⌄ đã bỏ 10/2026).
    @MainActor func testOffUnchanged() {
        let (kb, host) = makeKeyboard(width: isPad ? 834 : 390)
        _ = host
        var off: [CGFloat] = []
        for h in H.allCases {
            kb.debugSetBarHeight(h)
            kb.setSuggestionsEnabled(false, reserveStrip: false); settle(kb)
            off.append(kb.debugRequestedHeight)
            kb.setSuggestionsEnabled(true); settle(kb)
        }
        XCTAssertEqual(Set(off).count, 1, "tắt: \(off)")
        kb.debugSetBarHeight(.low); settle(kb)
        XCTAssertGreaterThan(kb.debugRequestedHeight, off[0], "mở cao hơn tắt")
    }

    /// Plane emoji giữ nguyên tổng cao (lưới ăn cả strip) ở mọi mức.
    @MainActor func testEmojiPlaneKeepsTotalPerOption() {
        for h in H.allCases {
            let c = KeyLayout.chrome(keyArea: 212, strip: 29 + h.delta, mode: .keys)
            let e = KeyLayout.chrome(keyArea: 212, strip: 29 + h.delta, mode: .emoji)
            XCTAssertEqual(e.total, c.total, "\(h)")
            XCTAssertEqual(c.total, 241 + h.delta, "\(h)")
        }
    }
}
