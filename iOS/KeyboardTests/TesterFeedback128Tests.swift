// Góp ý tester Plus bản 1.2.8 (12/10/2026):
//  1. rung/âm không có ở phím "." (và ",", "@", "/", ⇧, 🌐, phím dấu iPad)
//  3. tắt Mẫu câu ⇒ mất ☰ ⇒ không còn lối bật một tay trên bàn phím
//  6. phím sát viền (q, p, -) không có ô phóng to
//  7. phím "chìm" khi bấm như stock, cả khi tắt phóng to (công tắc "Phím sẫm khi bấm")
// (5. hàng số: NumberRowTests.)
import XCTest
import UIKit

final class TesterFeedback128Tests: XCTestCase {
    private let suite = "vt-tester-128-tests"
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    private var width: CGFloat { isPad ? 834 : 390 }

    @MainActor private func withKeyboard(_ pairs: [String: Any] = [:], globe: Bool = false,
                                         kind: KeyboardView.InputKind = .normal,
                                         _ body: (KeyboardView) throws -> Void) rethrows {
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        for (k, v) in pairs { d.set(v, forKey: k) }
        let saved = UserDefaultsProvider.shared
        UserDefaultsProvider.shared = d
        defer { UserDefaultsProvider.shared = saved; d.removePersistentDomain(forName: suite) }
        let kb = KeyboardView(needsGlobe: globe, inputController: nil) { _ in }
        let host = UIView(frame: CGRect(x: 0, y: 0, width: width, height: 320))
        host.addSubview(kb)
        kb.frame = host.bounds
        kb.applyAppearance(.light, style: .light)
        kb.setSuggestionsEnabled(true)
        if kind != .normal { kb.configureInputKind(kind) }
        kb.setNeedsLayout(); kb.layoutIfNeeded()
        try body(kb)
        withExtendedLifetime(host) {}
    }

    // MARK: 1. âm / rung mọi phím

    /// Mọi nút phím của plane đang hiện: chạm xuống phải qua KeyboardView.feedback (âm +
    /// rung dùng CHUNG đường đó — rung chỉ thêm cờ hapticsEnabled). ⌫ / space dùng selector
    /// có UIEvent (đã có clickDelete / clickModifier) — bỏ qua để không giả event.
    @MainActor private func assertEveryKeyClicks(_ kb: KeyboardView, _ ctx: String,
                                                 file: StaticString = #filePath, line: UInt = #line) {
        let skip: Set<String> = [L("Xoá"), L("Dấu cách")]
        let keys = kb.debugAllKeyButtons()
        XCTAssertGreaterThan(keys.count, 10, ctx, file: file, line: line)
        for b in keys where b.superview != nil && !skip.contains(b.accessibilityLabel ?? "") {
            let name = b.accessibilityLabel ?? b.currentTitle ?? "?"
            KeyboardView.debugLastClickRoute = nil
            b.sendActions(for: .touchDown)
            XCTAssertNotNil(KeyboardView.debugLastClickRoute, "\(ctx): phím \(name) im lặng / không rung",
                            file: file, line: line)
            b.sendActions(for: .touchCancel)
        }
    }

    @MainActor func testEveryKeyFeedsBackOnTouchDown() {
        // Bàn chữ thường (có ","), có 🌐 + ⇧.
        withKeyboard(globe: true) { kb in assertEveryKeyClicks(kb, "chữ") }
        // Thanh địa chỉ (".") — đúng phím tester báo; ô URL (". /"), email ("@ .").
        withKeyboard(kind: .search) { kb in assertEveryKeyClicks(kb, "search") }
        withKeyboard(kind: .url) { kb in assertEveryKeyClicks(kb, "url") }
        withKeyboard(kind: .email) { kb in assertEveryKeyClicks(kb, "email") }
        // Hàng số + plane số / ký hiệu.
        withKeyboard(["numberRow": true]) { kb in assertEveryKeyClicks(kb, "hàng số") }
        withKeyboard { kb in
            kb.debugSetPlane(numbers: true); kb.layoutIfNeeded()
            assertEveryKeyClicks(kb, "plane số")
        }
    }

    /// Hồi quy trực tiếp: "." hàng đáy ô tìm kiếm / địa chỉ (Safari) có âm + rung + ô phóng to.
    @MainActor func testPeriodKeyInSearchFieldClicksAndPreviews() throws {
        try withKeyboard(kind: .search) { kb in
            let dot = try XCTUnwrap(kb.debugKeyButton("."))
            KeyboardView.debugLastClickRoute = nil
            dot.sendActions(for: .touchDown)
            XCTAssertNotNil(KeyboardView.debugLastClickRoute, "\".\" im lặng / không rung")
            XCTAssertTrue(kb.debugBalloonVisible, "\".\" có ô phóng to như phím ký tự")
            dot.sendActions(for: .touchCancel)
        }
    }

    // MARK: 3. một tay khi tắt Mẫu câu

    func testLeftZoneDecision() {
        XCTAssertEqual(KeyboardView.leftZone(templatesEnabled: true, pad: false, split: false), .templates)
        XCTAssertEqual(KeyboardView.leftZone(templatesEnabled: true, pad: true, split: false), .templates)
        XCTAssertEqual(KeyboardView.leftZone(templatesEnabled: false, pad: false, split: false), .oneHand)
        XCTAssertEqual(KeyboardView.leftZone(templatesEnabled: false, pad: true, split: false), .none)
        XCTAssertEqual(KeyboardView.leftZone(templatesEnabled: false, pad: false, split: true), .none)
    }

    /// ☰ hiện khi Mẫu câu HOẶC Công cụ văn bản bật (user 10/2026). Công cụ = Plus mở khoá
    /// VÀ công tắc (KeyboardSettings.textToolsActive) — khoá Plus ⇒ như tắt.
    func testLeftZoneMatrixWithTextToolsAndPlusGate() {
        for templates in [false, true] {
            for toolsSwitch in [false, true] {
                for unlocked in [false, true] {
                    for (pad, split) in [(false, false), (true, false), (false, true)] {
                        var s = KeyboardSettings()
                        s.textToolsEnabled = toolsSwitch
                        let tools = s.textToolsActive(unlocked: unlocked)
                        let z = KeyboardView.leftZone(templatesEnabled: templates, toolsEnabled: tools,
                                                      pad: pad, split: split)
                        let want: KeyboardView.LeftZone = templates ? .templates
                            : (toolsSwitch && unlocked) ? .tools
                            : (pad || split) ? .none : .oneHand
                        XCTAssertEqual(z, want, "templates=\(templates) tools=\(toolsSwitch) unlocked=\(unlocked) pad=\(pad) split=\(split)")
                    }
                }
            }
        }
    }

    /// Mẫu câu tắt + Công cụ bật: chạm ☰ mở THẲNG danh sách công cụ (không mẫu câu, không
    /// "‹ Mẫu câu"); chạm lần nữa đóng; giữ lâu vẫn bật/tắt một tay.
    @MainActor func testToolsOnlyLeftZoneOpensTextTools() {
        withKeyboard(["templatesEnabled": false]) { kb in
            kb.textToolsEnabled = true
            kb.layoutIfNeeded()
            XCTAssertEqual(kb.debugLeftZone, .tools)
            XCTAssertTrue(kb.debugBurgerVisible)
            XCTAssertEqual(kb.debugLeftZoneSymbol, L("Công cụ văn bản"))
            kb.debugTapLeftZone()
            kb.layoutIfNeeded()
            XCTAssertTrue(kb.debugInTemplates, "chạm ☰ ⇒ mở lưới công cụ")
            XCTAssertFalse(kb.debugOneHandActive)
            let extras = kb.debugTemplateExtras
            XCTAssertEqual(Array(extras.prefix(TextTool.allCases.count)), TextTool.allCases.map(\.label),
                           "danh sách công cụ hiện ngay: \(extras)")
            XCTAssertFalse(extras.contains { $0.hasPrefix("\u{2039}") }, "không có nút quay về mẫu câu")
            XCTAssertFalse(kb.debugTemplateSegmented, "chỉ-công-cụ: không thanh chọn")
            XCTAssertTrue(extras.contains(L("Thêm dấu")) == PlusGate.isUnlocked(.sentenceDiacritics))
            XCTAssertFalse(kb.debugTemplatesLoaded, "không đọc danh sách mẫu câu")
            var applied: [TextTool] = []
            kb.onTextTool = { applied.append($0) }
            XCTAssertTrue(kb.debugSelectTemplateChip(0))
            XCTAssertEqual(applied, [TextTool.allCases[0]], "chạm công cụ ⇒ áp")
            XCTAssertFalse(kb.debugInTemplates, "áp xong về bàn phím chữ")
            kb.debugTapLeftZone()
            XCTAssertTrue(kb.debugInTemplates)
            kb.debugTapLeftZone()
            XCTAssertFalse(kb.debugInTemplates, "chạm lần nữa ⇒ đóng")
            if !isPad {
                kb.debugHoldBurger()
                XCTAssertTrue(kb.debugOneHandActive, "giữ lâu ☰ vẫn bật một tay")
                kb.debugHoldBurger()
            }
            // Công cụ tắt lúc đang mở ⇒ về bàn phím chữ, ô mép trái thành một tay / ẩn.
            kb.debugTapLeftZone()
            XCTAssertTrue(kb.debugInTemplates)
            kb.textToolsEnabled = false
            XCTAssertFalse(kb.debugInTemplates)
            XCTAssertEqual(kb.debugLeftZone, isPad ? .none : .oneHand)
        }
    }

    @MainActor func testTemplatesOffLeftZoneTogglesOneHand() throws {
        try XCTSkipIf(isPad, "iPad không có chế độ một tay")
        withKeyboard(["templatesEnabled": false]) { kb in
            var saved: [OneHandSide] = []
            kb.onOneHandChange = { saved.append($0) }
            XCTAssertTrue(kb.debugBurgerVisible, "ô mép trái vẫn hiện (nút một tay)")
            XCTAssertEqual(kb.debugLeftZoneSymbol, L("Bật chế độ một tay"))
            kb.debugTapLeftZone()
            XCTAssertTrue(kb.debugOneHandActive, "chạm ⇒ bật một tay")
            XCTAssertFalse(kb.debugInTemplates)
            XCTAssertFalse(kb.debugTemplatesLoaded, "không đọc danh sách mẫu câu")
            kb.layoutIfNeeded()
            XCTAssertEqual(kb.debugLeftZoneSymbol, L("Thoát chế độ một tay"))
            kb.debugTapLeftZone()
            XCTAssertFalse(kb.debugOneHandActive, "chạm lần nữa ⇒ tắt")
            XCTAssertEqual(saved, [.right, .off], "controller được báo để lưu")
            // Giữ lâu cũng bật/tắt (cùng cử chỉ như ☰).
            kb.debugHoldBurger()
            XCTAssertTrue(kb.debugOneHandActive)
        }
    }

    @MainActor func testTemplatesOnLeftZoneStillOpensTemplates() {
        withKeyboard { kb in
            XCTAssertEqual(kb.debugLeftZone, .templates)
            kb.debugTapLeftZone()
            XCTAssertTrue(kb.debugInTemplates, "chạm ☰ vẫn mở mẫu câu như cũ")
            XCTAssertFalse(kb.debugOneHandActive)
        }
    }

    // MARK: 6. ô phóng to ở phím sát viền

    func testBalloonFrameStaysOnScreenAtEdges() {
        let top: CGFloat = 0
        for W: CGFloat in [320, 375, 390, 402, 430, 568, 690, 744, 834, 932, 1024, 1366] {
            let keyW = (W - 13 - 9 * 6) / 10            // 10 phím, lề 6.5, khe 6
            let y: CGFloat = 60
            let left = CGRect(x: 6.5, y: y, width: keyW, height: 44)
            let right = CGRect(x: W - 6.5 - keyW, y: y, width: keyW, height: 44)
            let mid = CGRect(x: W / 2 - keyW / 2, y: y, width: keyW, height: 44)
            for (name, k) in [("trái", left), ("phải", right), ("giữa", mid)] {
                let f = BalloonGeometry.frame(keyRect: k, containerWidth: W, topLimit: top)
                XCTAssertGreaterThanOrEqual(f.minX, 0, "W=\(W) \(name): tràn trái")
                XCTAssertLessThanOrEqual(f.maxX, W + 0.001, "W=\(W) \(name): tràn phải")
                XCTAssertLessThanOrEqual(f.minX, k.minX + 0.001, "W=\(W) \(name): phím lọt ngoài bubble")
                XCTAssertGreaterThanOrEqual(f.maxX, k.maxX - 0.001, "W=\(W) \(name): phím lọt ngoài bubble")
                XCTAssertEqual(f.width, max(keyW + 24, 52), accuracy: 0.001)
                XCTAssertEqual(f.maxY, k.maxY, accuracy: 0.001)
                XCTAssertGreaterThanOrEqual(f.minY, top)
            }
            // Giữa màn hình: căn giữa phím như cũ.
            let fm = BalloonGeometry.frame(keyRect: mid, containerWidth: W, topLimit: top)
            XCTAssertEqual(fm.midX, mid.midX, accuracy: 0.001)
            // Sát mép: dời vào trong, mép bubble trùng mép màn hình.
            XCTAssertEqual(BalloonGeometry.frame(keyRect: left, containerWidth: W, topLimit: top).minX, 0, accuracy: 0.001)
            XCTAssertEqual(BalloonGeometry.frame(keyRect: right, containerWidth: W, topLimit: top).maxX, W, accuracy: 0.001)
        }
        // Hàng trên cùng: đỉnh không vượt topLimit (extension không vẽ được phía trên).
        let topRow = BalloonGeometry.frame(keyRect: CGRect(x: 100, y: 20, width: 33, height: 44),
                                           containerWidth: 390, topLimit: 0)
        XCTAssertEqual(topRow.minY, 0)
    }

    func testBalloonMinimumVisibleTime() {
        XCTAssertEqual(BalloonGeometry.hideDelay(shownFor: 0), BalloonGeometry.minVisible, accuracy: 1e-9)
        XCTAssertEqual(BalloonGeometry.hideDelay(shownFor: 0.03), BalloonGeometry.minVisible - 0.03, accuracy: 1e-9)
        XCTAssertEqual(BalloonGeometry.hideDelay(shownFor: 0.08), 0)
        XCTAssertLessThanOrEqual(BalloonGeometry.minVisible, 0.1, "không kéo dài ô phóng to khi gõ thường")
    }

    @MainActor func testEdgeKeysShowBalloonInsideKeyboard() throws {
        try withKeyboard { kb in
            for s in ["q", "p", "a", "l", "z", "m"] {
                let b = try XCTUnwrap(kb.debugLetterButton(s))
                b.sendActions(for: .touchDown)
                let f = try XCTUnwrap(kb.debugBalloonFrame, "\(s): không có ô phóng to")
                XCTAssertGreaterThanOrEqual(f.minX, -0.001, "\(s)")
                XCTAssertLessThanOrEqual(f.maxX, kb.bounds.width + 0.001, "\(s)")
                b.sendActions(for: .touchUpInside)
            }
            // "-" (plane số, phím đầu hàng 2) cũng có ô phóng to trong khung.
            kb.debugSetPlane(numbers: true); kb.layoutIfNeeded()
            let minus = try XCTUnwrap(kb.debugKeyButton("-"))
            minus.sendActions(for: .touchDown)
            let f = try XCTUnwrap(kb.debugBalloonFrame)
            XCTAssertGreaterThanOrEqual(f.minX, -0.001)
            minus.sendActions(for: .touchCancel)
        }
    }

    /// iOS giao began + ended cùng lúc (touch sát mép bị hoãn) ⇒ ô phóng to vẫn kịp hiện
    /// ~70ms rồi tự ẩn; chạm phím kế huỷ hẹn ẩn và dời ô sang phím mới.
    @MainActor func testInstantTapKeepsBalloonBriefly() throws {
        try withKeyboard { kb in
            let q = try XCTUnwrap(kb.debugLetterButton("q"))
            q.sendActions(for: .touchDown)
            q.sendActions(for: .touchUpInside)
            XCTAssertTrue(kb.debugBalloonVisible, "chưa ẩn ngay")
            XCTAssertTrue(kb.debugBalloonHidePending)
            RunLoop.main.run(until: Date().addingTimeInterval(BalloonGeometry.minVisible + 0.1))
            XCTAssertFalse(kb.debugBalloonVisible, "tự ẩn sau minVisible")
            XCTAssertFalse(kb.debugBalloonHidePending)
            // Chạm nhanh q rồi w: hẹn ẩn của q bị huỷ, ô ở w không bị ẩn oan.
            let w = try XCTUnwrap(kb.debugLetterButton("w"))
            q.sendActions(for: .touchDown); q.sendActions(for: .touchUpInside)
            w.sendActions(for: .touchDown)
            XCTAssertFalse(kb.debugBalloonHidePending)
            RunLoop.main.run(until: Date().addingTimeInterval(BalloonGeometry.minVisible + 0.1))
            XCTAssertTrue(kb.debugBalloonVisible, "ô của w (đang đè) không bị hẹn ẩn của q tắt")
            w.sendActions(for: .touchUpInside)
        }
    }

    // MARK: 7. phím sẫm khi bấm

    func testPressHighlightSettingDefault() {
        XCTAssertEqual(KeyboardView.keyPressHighlightSetting(nil), KeyboardView.keyPressHighlightDefault)
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        XCTAssertEqual(KeyboardView.keyPressHighlightSetting(d), KeyboardView.keyPressHighlightDefault)
        d.set(false, forKey: KeyboardView.keyPressHighlightKey)
        XCTAssertFalse(KeyboardView.keyPressHighlightSetting(d))
        d.set(true, forKey: KeyboardView.keyPressHighlightKey)
        XCTAssertTrue(KeyboardView.keyPressHighlightSetting(d))
        d.removePersistentDomain(forName: suite)
    }

    @MainActor func testPressedLetterDarkensAndRestores() throws {
        // Bật, kể cả khi TẮT ô phóng to (đúng góp ý: stock vẫn "chìm" phím).
        try withKeyboard([KeyboardView.keyPressHighlightKey: true, KeyboardView.keyPreviewKey: false]) { kb in
            let a = try XCTUnwrap(kb.debugLetterButton("a"))
            let c = kb.debugKeyColors(a)
            let pressed = try XCTUnwrap(c.pressed, "phím chữ có màu đè")
            XCTAssertNotEqual(pressed, c.normal)
            for end: UIControl.Event in [.touchUpInside, .touchUpOutside, .touchCancel] {
                a.sendActions(for: .touchDown)
                XCTAssertEqual(kb.debugKeyColors(a).current, pressed, "đè ⇒ sẫm")
                XCTAssertFalse(kb.debugBalloonVisible, "phóng to tắt ⇒ không balloon")
                a.sendActions(for: end)
                // Nhả ngay sau đè (< minVisible, như touch sát mép giao một lượt) ⇒ thôi sẫm trễ.
                XCTAssertEqual(kb.debugKeyColors(a).current, pressed, "vẫn sẫm đủ minVisible")
                RunLoop.main.run(until: Date().addingTimeInterval(BalloonGeometry.minVisible + 0.05))
                XCTAssertEqual(kb.debugKeyColors(a).current, c.normal, "nhả/huỷ ⇒ về màu thường")
            }
            // Đường router thật (chạm tâm phím rồi nhấc).
            let f = try XCTUnwrap(kb.debugLetterFrame("a"))
            kb.debugTouch(from: CGPoint(x: f.midX, y: f.midY), through: [], start: 1)
            RunLoop.main.run(until: Date().addingTimeInterval(BalloonGeometry.minVisible + 0.05))
            XCTAssertEqual(kb.debugKeyColors(a).current, c.normal)
            // Phím số hàng số / plane số cũng sẫm.
            kb.debugSetPlane(numbers: true); kb.layoutIfNeeded()
            let seven = try XCTUnwrap(kb.debugKeyButton("7"))
            seven.sendActions(for: .touchDown)
            XCTAssertEqual(kb.debugKeyColors(seven).current, kb.debugKeyColors(seven).pressed)
            seven.sendActions(for: .touchCancel)
            RunLoop.main.run(until: Date().addingTimeInterval(BalloonGeometry.minVisible + 0.05))
            XCTAssertEqual(kb.debugKeyColors(seven).current, kb.debugKeyColors(seven).normal)
        }
    }

    /// TẮT ⇒ phím chữ/số không có màu đè (closure chạm thoát ngay — 0 chi phí), nền không đổi.
    @MainActor func testPressHighlightOffCostsNothing() throws {
        try withKeyboard([KeyboardView.keyPressHighlightKey: false]) { kb in
            let a = try XCTUnwrap(kb.debugLetterButton("a"))
            XCTAssertNil(kb.debugKeyColors(a).pressed)
            let before = kb.debugKeyColors(a).current
            a.sendActions(for: .touchDown)
            XCTAssertEqual(kb.debugKeyColors(a).current, before)
            a.sendActions(for: .touchUpInside)
            kb.debugSetPlane(numbers: true); kb.layoutIfNeeded()
            XCTAssertNil(kb.debugKeyColors(try XCTUnwrap(kb.debugKeyButton("7"))).pressed)
        }
    }

    /// Bật/tắt công tắc khi bàn phím hiện lại ⇒ dựng lại plane (chữ ký rebuild), không lẫn cache.
    @MainActor func testTogglingSettingRebuilds() throws {
        try withKeyboard { kb in
            XCTAssertEqual(kb.debugKeyColors(try XCTUnwrap(kb.debugLetterButton("a"))).pressed != nil,
                           KeyboardView.keyPressHighlightDefault)
            kb.keyPressHighlightEnabled = !KeyboardView.keyPressHighlightDefault
            kb.layoutIfNeeded()
            XCTAssertEqual(kb.debugKeyColors(try XCTUnwrap(kb.debugLetterButton("a"))).pressed != nil,
                           !KeyboardView.keyPressHighlightDefault)
        }
    }

    /// Micro-bench đường chạm phím chữ qua router (routeDown → sendActions → routeUp), BẬT vs
    /// TẮT "Phím sẫm khi bấm". In "PRESSBENCH …" để báo cáo; chỉ chặn hồi quy thô.
    @MainActor func testPressHighlightTouchCost() throws {
        // Cùng một bàn phím, BẬT/TẮT xen kẽ 6 vòng mỗi bên (khử nhiễu làm nóng / thứ tự);
        // lấy vòng nhanh nhất mỗi bên (2000 chạm/vòng, phóng to tắt để chỉ đo phần sẫm phím).
        var best: [Bool: Double] = [false: .infinity, true: .infinity]
        try withKeyboard([KeyboardView.keyPreviewKey: false]) { kb in
            for round in 0..<12 {
                let on = round % 2 == 1
                kb.keyPressHighlightEnabled = on
                kb.layoutIfNeeded()
                let pts = try "asdfghjkl".map { s -> CGPoint in
                    let f = try XCTUnwrap(kb.debugLetterFrame(String(s))); return CGPoint(x: f.midX, y: f.midY)
                }
                for _ in 0..<50 { for p in pts { kb.debugTouch(from: p, through: [], start: 1) } }   // làm nóng
                let n = 2000
                let t0 = CACurrentMediaTime()
                for i in 0..<n { kb.debugTouch(from: pts[i % pts.count], through: [], start: 1) }
                best[on] = min(best[on]!, (CACurrentMediaTime() - t0) / Double(n) * 1e6)
            }
        }
        let off = best[false]!, on = best[true]!
        let line = String(format: "PRESSBENCH per_tap_us off=%.2f on=%.2f delta=%.2f", off, on, on - off)
        print(line)
        XCTContext.runActivity(named: line) { _ in }
        XCTAssertLessThan(on - off, 20, "sẫm phím không được thêm cỡ chục µs mỗi chạm")
    }
}
