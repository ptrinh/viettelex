// Tester 1.2.10: "Phím sẫm khi bấm" không hiện khi chạm mép trái q / a / 1, mép phải p / l / 0
// và ở ⇧ / ⌫ / 123 / return — còn ô phóng to thì có. Nguyên nhân: phím sát mép màn hình bị
// iOS giữ touch (phân xử cử chỉ hệ thống) rồi giao began + ended CÙNG một vòng runloop ⇒ phím
// sẫm rồi thôi sẫm trước khi lên màn hình. Ô phóng to đã có minVisible (BalloonGeometry), nền
// đè thì chưa. Thêm: ⇧ đổi trạng thái ở touchDown ghi đè nền đè; 123/ABC gỡ phím ngay lúc chạm.
//
// Mỗi điểm chạm: phím SẪM phải đúng là phím NHẬN input (router chữ hoặc nút hitTest chọn), và
// nhấc tay tức thì (giao một lượt như sát mép) vẫn để phím sẫm ≥ minVisible rồi mới thôi.
import XCTest
import UIKit

final class KeyPressHighlightEdgeTests: XCTestCase {
    private let suite = "vt-press-edge-tests"
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    @MainActor private func withKeyboard(width: CGFloat, numberRow: Bool, highlight: Bool = true,
                                         _ body: (KeyboardView, () -> KeyboardView.Key?) throws -> Void) rethrows {
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        d.set(highlight, forKey: KeyboardView.keyPressHighlightKey)
        d.set(false, forKey: KeyboardView.keyPreviewKey)
        let saved = UserDefaultsProvider.shared
        UserDefaultsProvider.shared = d
        defer { UserDefaultsProvider.shared = saved; d.removePersistentDomain(forName: suite) }
        var last: KeyboardView.Key?
        let kb = KeyboardView(needsGlobe: false, inputController: nil) { last = $0 }
        let host = UIView(frame: CGRect(x: 0, y: 0, width: width, height: 320))
        host.addSubview(kb)
        kb.frame = host.bounds
        kb.applyAppearance(.light, style: .light)
        kb.numberRowEnabled = numberRow
        kb.keyPressHighlightEnabled = highlight
        kb.setNeedsLayout(); kb.layoutIfNeeded()
        try body(kb, { last })
        withExtendedLifetime(host) {}
    }

    private func name(_ b: UIButton?) -> String {
        guard let b else { return "nil" }
        return b.accessibilityLabel ?? b.currentTitle ?? "?"
    }

    /// Chạm tại `p` đi đúng đường thật: hitTest → (router chữ | nút thật). Nhấc tay NGAY (như
    /// touch sát mép bị giao một lượt). Trả phím sẫm lúc đè + phím nhận input.
    @MainActor private func edgeTap(_ kb: KeyboardView, at p: CGPoint, last: () -> KeyboardView.Key?,
                                    expectDeferred: Bool = true, _ ctx: String,
                                    file: StaticString = #filePath, line: UInt = #line) throws {
        let hit = kb.debugHitTest(p, time: 1)
        var pressed: [UIButton] = []
        var receiver: UIButton?
        var released: () -> Void = {}
        if hit === kb {
            let token = NSObject(), id = ObjectIdentifier(token)
            kb.debugRouteDown(id, at: p, time: 1)
            pressed = kb.debugPressedKeys()
            guard case .letter(let ch)? = last() else {
                return XCTFail("\(ctx): router không chèn chữ", file: file, line: line)
            }
            receiver = kb.debugLetterButton(String(ch).lowercased())
            released = { kb.debugRouteUp(id, at: p, time: 1); withExtendedLifetime(token) {} }
        } else if let c = hit as? UIButton {
            c.sendActions(for: .touchDown)
            pressed = kb.debugPressedKeys()
            receiver = c
            released = { c.sendActions(for: .touchUpInside) }
        } else {
            return XCTFail("\(ctx): không phím nào nhận chạm (\(String(describing: hit)))", file: file, line: line)
        }
        let r = try XCTUnwrap(receiver, ctx, file: file, line: line)
        if r.isDescendant(of: kb) {
            XCTAssertEqual(pressed.map(name), [name(r)], "\(ctx): phím sẫm ≠ phím nhận input", file: file, line: line)
            XCTAssertTrue(pressed.first === r, "\(ctx): phím sẫm ≠ phím nhận input", file: file, line: line)
        } else {
            // 123/ABC: plane đổi lúc chạm — phím plane mới tại đúng chỗ ngón tay sẫm thay.
            XCTAssertEqual(pressed.count, 1, "\(ctx): phím plane mới phải sẫm", file: file, line: line)
        }
        let shown = pressed
        released()
        if expectDeferred {
            XCTAssertEqual(kb.debugPressedKeys().map(name), shown.map(name),
                           "\(ctx): began+ended một lượt ⇒ vẫn sẫm đủ minVisible", file: file, line: line)
        }
        RunLoop.main.run(until: Date().addingTimeInterval(BalloonGeometry.minVisible + 0.05))
        XCTAssertEqual(kb.debugPressedKeys().map(name), [], "\(ctx): nhả ⇒ hết sẫm", file: file, line: line)
        for b in shown { XCTAssertEqual(kb.debugKeyColors(b).current, kb.debugKeyColors(b).normal, ctx,
                                        file: file, line: line) }
    }

    private func frame(_ kb: KeyboardView, _ c: UIView) -> CGRect { kb.convert(c.bounds, from: c) }

    @MainActor private func runEdgeMatrix(width: CGFloat, numberRow: Bool) throws {
        try withKeyboard(width: width, numberRow: numberRow) { kb, last in
            let ctx = "w=\(width) numberRow=\(numberRow)"
            // Mép trái q / a, mép phải p / l: trong lề, ngoài khung phím (và sát mép màn hình).
            for (s, left) in [("q", true), ("a", true), ("p", false), ("l", false)] {
                let f = try XCTUnwrap(kb.debugLetterFrame(s))
                for x in left ? [f.minX / 2, 0.5, f.minX - 0.5] : [(f.maxX + width) / 2, width - 0.5, f.maxX + 0.5] {
                    try edgeTap(kb, at: CGPoint(x: x, y: f.midY), last: last, "\(ctx) mép \(s) x=\(x)")
                }
            }
            // Khe giữa phím cùng hàng + khe giữa hai hàng.
            let q = try XCTUnwrap(kb.debugLetterFrame("q")), w = try XCTUnwrap(kb.debugLetterFrame("w"))
            let a = try XCTUnwrap(kb.debugLetterFrame("a")), z = try XCTUnwrap(kb.debugLetterFrame("z"))
            let m = try XCTUnwrap(kb.debugLetterFrame("m"))
            try edgeTap(kb, at: CGPoint(x: (q.maxX + w.minX) / 2, y: q.midY), last: last, "\(ctx) khe q|w")
            try edgeTap(kb, at: CGPoint(x: a.midX, y: (q.maxY + a.minY) / 2), last: last, "\(ctx) khe hàng q/a")
            // Phím chức năng: tâm, sát mép màn hình, khe cạnh phím chữ.
            let shift = try XCTUnwrap(kb.debugControl("Shift"))
            let del = try XCTUnwrap(kb.debugControl(L("Xoá")))
            let ret = try XCTUnwrap(kb.debugControl(L("Xuống dòng")))
            let sf = frame(kb, shift), df = frame(kb, del), rf = frame(kb, ret)
            for (f, edgeX, key) in [(sf, CGFloat(0.5), "⇧"), (df, width - 0.5, "⌫"), (rf, width - 0.5, "return")] {
                try edgeTap(kb, at: CGPoint(x: f.midX, y: f.midY), last: last, "\(ctx) \(key) tâm")
                try edgeTap(kb, at: CGPoint(x: edgeX, y: f.midY), last: last, "\(ctx) \(key) mép")
            }
            try edgeTap(kb, at: CGPoint(x: (sf.maxX + z.minX) / 2, y: z.midY), last: last, "\(ctx) khe ⇧|z")
            try edgeTap(kb, at: CGPoint(x: (m.maxX + df.minX) / 2, y: m.midY), last: last, "\(ctx) khe m|⌫")
            // Hàng số: mép trái 1, mép phải 0.
            if numberRow {
                let one = frame(kb, try XCTUnwrap(kb.debugKeyButton("1")))
                let zero = frame(kb, try XCTUnwrap(kb.debugKeyButton("0")))
                try edgeTap(kb, at: CGPoint(x: one.minX / 2, y: one.midY), last: last, "\(ctx) mép 1")
                try edgeTap(kb, at: CGPoint(x: 0.5, y: one.midY), last: last, "\(ctx) mép 1 sát màn hình")
                try edgeTap(kb, at: CGPoint(x: (zero.maxX + width) / 2, y: zero.midY), last: last, "\(ctx) mép 0")
                try edgeTap(kb, at: CGPoint(x: width - 0.5, y: zero.midY), last: last, "\(ctx) mép 0 sát màn hình")
            }
            // 123 (mép trái hàng đáy) ⇒ plane số, ABC tại chỗ ngón sẫm; ABC mép trái ⇒ về chữ.
            let more = try XCTUnwrap(kb.debugControl(L("Số")))
            let mf = frame(kb, more)
            try edgeTap(kb, at: CGPoint(x: 0.5, y: mf.midY), last: last, "\(ctx) 123 mép")
            XCTAssertEqual(kb.debugPlaneName, "numbers", ctx)
            kb.setNeedsLayout(); kb.layoutIfNeeded()   // không window: plane mới cần ép layout
            let abc = try XCTUnwrap(kb.debugControl(L("Chữ")))
            try edgeTap(kb, at: CGPoint(x: 0.5, y: frame(kb, abc).midY), last: last, "\(ctx) ABC mép")
            XCTAssertEqual(kb.debugPlaneName, "letters", ctx)
            kb.setNeedsLayout(); kb.layoutIfNeeded()
            XCTAssertTrue(kb.debugPressedKeys().isEmpty, ctx)
        }
    }

    @MainActor func testEdgeTouchesHighlightTheInputKeyStandardPhone() throws {
        try XCTSkipIf(isPad, "bố cục iPhone")
        for nr in [false, true] { try runEdgeMatrix(width: 402, numberRow: nr) }
    }

    @MainActor func testEdgeTouchesHighlightTheInputKeyLargePhone() throws {
        try XCTSkipIf(isPad, "bố cục iPhone")
        for nr in [false, true] { try runEdgeMatrix(width: 440, numberRow: nr) }
    }

    /// Chạm lâu (≥ minVisible) ⇒ thôi sẫm NGAY lúc nhấc, không hẹn giờ.
    @MainActor func testSlowTapReleasesImmediately() throws {
        try XCTSkipIf(isPad, "bố cục iPhone")
        try withKeyboard(width: 402, numberRow: false) { kb, _ in
            let a = try XCTUnwrap(kb.debugLetterButton("a"))
            a.sendActions(for: .touchDown)
            RunLoop.main.run(until: Date().addingTimeInterval(BalloonGeometry.minVisible + 0.02))
            a.sendActions(for: .touchUpInside)
            XCTAssertFalse(kb.debugReleasePending(a))
            XCTAssertEqual(kb.debugKeyColors(a).current, kb.debugKeyColors(a).normal)
        }
    }

    /// Chạm lại phím đang chờ thôi sẫm ⇒ huỷ hẹn, vẫn sẫm suốt lần đè mới.
    @MainActor func testRepressCancelsPendingRelease() throws {
        try XCTSkipIf(isPad, "bố cục iPhone")
        try withKeyboard(width: 402, numberRow: false) { kb, _ in
            let a = try XCTUnwrap(kb.debugLetterButton("a"))
            a.sendActions(for: .touchDown)
            a.sendActions(for: .touchUpInside)
            XCTAssertTrue(kb.debugReleasePending(a))
            a.sendActions(for: .touchDown)
            XCTAssertFalse(kb.debugReleasePending(a))
            RunLoop.main.run(until: Date().addingTimeInterval(BalloonGeometry.minVisible + 0.05))
            XCTAssertEqual(kb.debugKeyColors(a).current, kb.debugKeyColors(a).pressed, "đang đè lần 2 ⇒ vẫn sẫm")
            a.sendActions(for: .touchCancel)
            RunLoop.main.run(until: Date().addingTimeInterval(BalloonGeometry.minVisible + 0.05))
            XCTAssertEqual(kb.debugKeyColors(a).current, kb.debugKeyColors(a).normal)
        }
    }

    /// ⇧ đổi trạng thái lúc chạm (applyShiftAppearance) nhưng vẫn sẫm khi đè; nhả ⇒ nền trạng thái mới.
    @MainActor func testShiftKeepsPressedFillWhileHeld() throws {
        try XCTSkipIf(isPad, "bố cục iPhone")
        try withKeyboard(width: 402, numberRow: false) { kb, _ in
            let shift = try XCTUnwrap(kb.debugControl("Shift") as? UIButton)
            // Hai lần: tự viết hoa đầu câu (bật) → tắt, rồi tắt → bật (cách > 0.3s, không thành caps).
            for _ in 0..<2 {
                let before = kb.debugShiftOn
                shift.sendActions(for: .touchDown)
                XCTAssertNotEqual(kb.debugShiftOn, before)
                XCTAssertEqual(kb.debugKeyColors(shift).current, kb.debugKeyColors(shift).pressed, "đè ⇒ sẫm")
                RunLoop.main.run(until: Date().addingTimeInterval(0.35))
                shift.sendActions(for: .touchUpInside)
                XCTAssertEqual(kb.debugKeyColors(shift).current, kb.debugKeyColors(shift).normal)
                XCTAssertNotEqual(kb.debugKeyColors(shift).current, kb.debugKeyColors(shift).pressed, "nhả ⇒ hết sẫm")
            }
        }
    }

    /// Công tắc TẮT: phím chữ / số không bao giờ sẫm, kể cả chạm mép.
    @MainActor func testEdgeTouchesNoHighlightWhenOff() throws {
        try XCTSkipIf(isPad, "bố cục iPhone")
        for width: CGFloat in [402, 440] {
            try withKeyboard(width: width, numberRow: true, highlight: false) { kb, last in
                for s in ["q", "a", "p", "l"] {
                    let f = try XCTUnwrap(kb.debugLetterFrame(s))
                    let x = s == "q" || s == "a" ? f.minX / 2 : (f.maxX + width) / 2
                    let p = CGPoint(x: x, y: f.midY)
                    XCTAssertTrue(kb.debugHitTest(p, time: 1) === kb)
                    let token = NSObject(), id = ObjectIdentifier(token)
                    kb.debugRouteDown(id, at: p, time: 1)
                    XCTAssertTrue(kb.debugPressedKeys().isEmpty, "w=\(width) \(s)")
                    kb.debugRouteUp(id, at: p, time: 1)
                    withExtendedLifetime(token) {}
                }
                for d in ["1", "0"] {
                    let b = try XCTUnwrap(kb.debugKeyButton(d))
                    XCTAssertNil(kb.debugKeyColors(b).pressed)
                    b.sendActions(for: .touchDown)
                    XCTAssertTrue(kb.debugPressedKeys().isEmpty, "w=\(width) \(d)")
                    b.sendActions(for: .touchUpInside)
                }
                _ = last
            }
        }
    }

    /// Bug Phil 19/10/2026 (tối, theme Hệ thống, Caps bật): bấm 123 rồi ABC (về bàn chữ) ⇒ phím 123 MẤT
    /// nền (chỉ còn nhãn trên nền bàn phím) trong khi mọi phím khác còn nền. Khoá: sau vòng đổi plane,
    /// phím 123 có nền = nền phím chức năng, không còn sẫm treo — mọi tổ hợp sáng/tối × Caps × sẫm-khi-bấm.
    @MainActor func testPlaneRoundTripKeeps123KeyFill() throws {
        for dark in [true, false] { for caps in [true, false] { for highlight in [true, false] {
        for fast in [true, false] { for upEvent in [UIControl.Event.touchUpInside, .touchCancel, .touchUpOutside] {
            let ctx = "dark=\(dark) caps=\(caps) highlight=\(highlight) fast=\(fast) up=\(upEvent.rawValue)"
            try withKeyboard(width: 390, numberRow: false, highlight: highlight) { kb, _ in
                kb.applyAppearance(dark ? .dark : .light, style: dark ? .dark : .light)
                kb.setNeedsLayout(); kb.layoutIfNeeded()
                if caps {
                    let sh = try XCTUnwrap(kb.debugControl("Shift"), ctx)
                    for _ in 0..<2 { sh.sendActions(for: .touchDown); sh.sendActions(for: .touchUpInside) }
                    if !kb.debugShiftCaps {   // ⇧ đầu có thể đã bật sẵn (đầu câu) ⇒ thêm một lần
                        let s2 = try XCTUnwrap(kb.debugControl("Shift"), ctx)
                        s2.sendActions(for: .touchDown); s2.sendActions(for: .touchUpInside)
                    }
                    XCTAssertTrue(kb.debugShiftCaps, ctx)
                }
                for label in [L("Số"), L("Chữ")] {
                    let c = try XCTUnwrap(kb.debugControl(label), "\(ctx) \(label)")
                    c.sendActions(for: .touchDown)
                    kb.setNeedsLayout(); kb.layoutIfNeeded()
                    c.sendActions(for: upEvent)
                    if !fast { RunLoop.main.run(until: Date().addingTimeInterval(BalloonGeometry.minVisible + 0.05)) }
                    kb.setNeedsLayout(); kb.layoutIfNeeded()
                }
                RunLoop.main.run(until: Date().addingTimeInterval(BalloonGeometry.minVisible + 0.05))
                XCTAssertEqual(kb.debugPlaneName, "letters", ctx)
                let more = try XCTUnwrap(kb.debugControl(L("Số")), ctx)
                let col = kb.debugKeyColors(more as! UIButton)
                let fn = kb.debugPalette.fnFill.ui
                XCTAssertEqual(col.current, fn, "\(ctx): phím 123 phải có nền phím chức năng")
                XCTAssertEqual(col.normal, fn, ctx)
                XCTAssertTrue(kb.debugPressedKeys().isEmpty, ctx)
                // Phím chức năng khác (emoji / ⌫) cùng nền — đối chiếu.
                if let bs = kb.debugControl(L("Xoá")) as? UIButton { XCTAssertEqual(kb.debugKeyColors(bs).current, fn, ctx) }
            }
        } } } } }
    }

    /// Bug Phil 19/10/2026: nền / thanh gợi ý tối, phím sáng. Đổi sáng/tối GIỮA CHỪNG khi đang ở plane khác
    /// (plane cũ nằm trong cache) rồi đổi plane: phím mọi plane, chữ thanh gợi ý và ô phóng to phải cùng
    /// MỘT chế độ với palette.
    @MainActor func testAppearanceFlipAcrossPlanesStaysConsistent() throws {
        try withKeyboard(width: 390, numberRow: false) { kb, _ in
            kb.showSuggestions(.init(nextWords: ["một", "hai", "ba"]))
            func check(_ dark: Bool, _ ctx: String) throws {
                kb.setNeedsLayout(); kb.layoutIfNeeded()
                let p = kb.debugPalette
                XCTAssertEqual(p.isDark, dark, ctx)
                XCTAssertEqual(p, ThemeSettings().palette(systemDark: dark, wallpaperActive: false), ctx)
                let key = try XCTUnwrap(kb.debugPlaneName == "letters" ? kb.debugLetterButton("a") : kb.debugKeyButton("1"), ctx)
                XCTAssertEqual(kb.debugKeyColors(key).normal, p.keyFill.ui, "\(ctx): nền phím")
                XCTAssertEqual(key.titleColor(for: .normal) ?? key.tintColor, p.keyInk.ui, "\(ctx): chữ phím")
                if let ink = kb.debugBarInkApplied { XCTAssertEqual(ink, p.barInk.ui, "\(ctx): chữ thanh gợi ý") }
                if let label = kb.debugSuggestionLabelInk {
                    let want = SuggestionInk.color(barInk: p.barInk,
                                                   behind: SuggestionInk.behindBar(p, systemDark: dark, wallpaper: false),
                                                   mode: .muted)
                    XCTAssertEqual(label, want.ui, "\(ctx): chữ ô gợi ý (Xám mặc định)")
                }
                XCTAssertEqual(kb.debugPopupStyle, KeyPopupStyle.make(p, style: .default, systemDark: dark, wallpaper: false), ctx)
            }
            try check(false, "sáng, chữ")
            kb.debugSetPlane(numbers: true); try check(false, "sáng, số")
            kb.updateDark(true); try check(true, "tối, số")
            kb.debugSetPlane(numbers: false); try check(true, "tối, chữ (từ cache)")
            kb.debugSetPlane(numbers: true); try check(true, "tối, số lại")
            kb.updateDark(false); try check(false, "sáng, số")
            kb.debugSetPlane(numbers: false); try check(false, "sáng, chữ (từ cache)")
            // applyAppearance (lần hiện mới) cũng vậy.
            kb.applyAppearance(.dark, style: .light); try check(true, "ô xin .dark")
            kb.applyAppearance(.default, style: .dark); try check(true, ".default theo trait tối")
            kb.applyAppearance(.default, style: .light); try check(false, ".default theo trait sáng")
        }
    }
}
