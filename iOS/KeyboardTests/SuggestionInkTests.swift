import XCTest

/// "Màu chữ gợi ý" (SuggestionInk, khoá `suggestionInk`: muted/bright, mặc định Xám như stock) —
/// quyết định màu THUẦN theo theme × cài đặt × sáng/tối.
final class SuggestionInkTests: XCTestCase {
    private func ink(_ t: KeyboardTheme, dark: Bool, _ m: SuggestionInk) -> (ink: RGBA, bar: RGBA, behind: RGBA) {
        let p = t.palette(systemDark: dark)
        let behind = SuggestionInk.behindBar(p, systemDark: dark, wallpaper: false)
        return (SuggestionInk.color(barInk: p.barInk, behind: behind, mode: m), p.barInk, behind)
    }
    private func contrast(_ c: RGBA, _ bg: RGBA) -> Double { RGBA.contrast(c.over(bg), bg) }

    func testParseDefaultsToMuted() {
        XCTAssertEqual(SuggestionInk.defaultValue, .muted)
        XCTAssertEqual(SuggestionInk.parse(nil), .muted)
        XCTAssertEqual(SuggestionInk.parse("neon"), .muted)
        XCTAssertEqual(SuggestionInk.parse(1), .muted)
        XCTAssertEqual(SuggestionInk.parse("bright"), .bright)
        XCTAssertEqual(SuggestionInk.parse("muted"), .muted)
    }

    /// Hệ thống, tối: secondaryLabel UIKit (#EBEBF5 @ 60%) — không còn trắng tuyền (góp ý tester).
    func testSystemDarkMutedIsStockSecondaryLabel() {
        let r = ink(.system, dark: true, .muted)
        XCTAssertEqual(r.ink, SuggestionInk.stockDark.alpha(0.6))
        XCTAssertLessThan(contrast(r.ink, r.behind), contrast(r.bar, r.behind))
        XCTAssertGreaterThanOrEqual(contrast(r.ink, r.behind), SuggestionInk.minContrast)
    }

    /// Hệ thống, sáng: sắc #3C3C43, ~60% (nhích lên vừa đủ 3:1 trên kính sáng).
    func testSystemLightMutedIsStockGrey() {
        let r = ink(.system, dark: false, .muted)
        XCTAssertEqual(RGBA(r: r.ink.r, g: r.ink.g, b: r.ink.b), SuggestionInk.stockLight)
        XCTAssertGreaterThanOrEqual(r.ink.a, 0.6)
        XCTAssertLessThanOrEqual(r.ink.a, 0.7)
        XCTAssertGreaterThanOrEqual(contrast(r.ink, r.behind), SuggestionInk.minContrast)
        XCTAssertLessThan(contrast(r.ink, r.behind), contrast(r.bar, r.behind))
    }

    /// Sáng = như trước (barInk nguyên vẹn) cho mọi theme, cả sáng lẫn tối.
    func testBrightKeepsBarInk() {
        for t in KeyboardTheme.allCases {
            for d in [false, true] {
                let r = ink(t, dark: d, .bright)
                XCTAssertEqual(r.ink, r.bar, "\(t) dark=\(d)")
            }
        }
    }

    /// Mọi theme × sáng/tối: Xám dịu hơn Sáng nhưng vẫn ≥ 3:1; theme chữ màu giữ sắc của theme.
    func testMutedAcrossAllThemes() {
        for t in KeyboardTheme.allCases {
            for d in [false, true] {
                let r = ink(t, dark: d, .muted)
                let ctx = "\(t) dark=\(d)"
                XCTAssertGreaterThanOrEqual(contrast(r.ink, r.behind), SuggestionInk.minContrast, ctx)
                XCTAssertLessThanOrEqual(contrast(r.ink, r.behind), contrast(r.bar, r.behind) + 1e-9, ctx)
                if r.ink != r.bar {
                    let tint = SuggestionInk.stockTint(for: r.bar) ?? RGBA(r: r.bar.r, g: r.bar.g, b: r.bar.b)
                    XCTAssertEqual(RGBA(r: r.ink.r, g: r.ink.g, b: r.ink.b), tint, ctx)
                    XCTAssertLessThan(r.ink.a, r.bar.a, ctx)
                }
            }
        }
    }

    /// Theme chữ màu (không đen/trắng thuần) giữ sắc, chỉ giảm độ đậm.
    func testCustomColouredInkKeepsHue() {
        let teal = RGBA(r: 0, g: 0.35, b: 0.4)
        let bg = RGBA(hex: 0xF4FBFB)
        let m = SuggestionInk.color(barInk: teal, behind: bg, mode: .muted)
        XCTAssertEqual(RGBA(r: m.r, g: m.g, b: m.b), teal)
        XCTAssertEqual(m.a, 0.6, accuracy: 1e-9)
        XCTAssertEqual(SuggestionInk.color(barInk: teal, behind: bg, mode: .bright), teal)
    }

    /// barInk vốn kém tương phản: Xám không làm tệ hơn ⇒ giữ barInk.
    func testLowContrastInkFallsBackToBright() {
        let ink = RGBA(hex: 0xB0B0B0), bg = RGBA(hex: 0xC8C8C8)
        XCTAssertEqual(SuggestionInk.color(barInk: ink, behind: bg, mode: .muted), ink)
    }

    /// Nền sau thanh: nền theme đè lên kính hệ thống; ảnh nền ⇒ tông lớp phủ.
    func testBehindBar() {
        let sys = KeyboardTheme.system.palette(systemDark: true)
        XCTAssertEqual(SuggestionInk.behindBar(sys, systemDark: true, wallpaper: false),
                       KeyboardTransparency.systemBackdrop(dark: true))
        XCTAssertEqual(SuggestionInk.behindBar(sys, systemDark: true, wallpaper: true), .black)
        let oled = KeyboardTheme.oled.palette(systemDark: false)
        if let bg = oled.background {
            XCTAssertEqual(SuggestionInk.behindBar(oled, systemDark: false, wallpaper: false),
                           bg.over(KeyboardTransparency.systemBackdrop(dark: false)))
        }
    }
}
