import XCTest
import UIKit

/// Góp ý người dùng 27/09/2026 (ảnh chụp bản phát hành, dark mode): lưới emoji to hơn +
/// thanh tìm luôn hiện, thẻ Dán đè chữ gợi ý + slot "lúc rộng lúc hẹp", trackpad lag,
/// công tắc ô phóng to chữ, nhãn mẫu câu "❓".
final class UXFeedbackTests: XCTestCase {

    private let w: CGFloat = UIDevice.current.userInterfaceIdiom == .pad ? 834 : 390

    @MainActor private func makeKeyboard(suggestions: Bool = true,
                                         onKey: @escaping (KeyboardView.Key) -> Void = { _ in })
        -> (KeyboardView, UIView) {
        let kb = KeyboardView(needsGlobe: false, inputController: nil, onKey: onKey)
        let host = UIView(frame: CGRect(x: 0, y: 0, width: w, height: 320))
        host.addSubview(kb)
        kb.frame = host.bounds
        kb.setSuggestionsEnabled(suggestions)
        kb.setNeedsLayout(); kb.layoutIfNeeded()
        return (kb, host)
    }

    // MARK: 1. emoji

    /// Số đo stock iOS 26/27 (simulator 28/09/2026 — góp ý Hữu Đông "emoji vẫn bé hơn
    /// stock"): glyph bbox 29.3pt iPhone / 44pt iPad (≈ 0.917 × pointSize 32 / 48), bước ngang
    /// 46 / 40 / 62 / 63, ô tìm 40, hàng category 40. Glyph KHÔNG co theo số hàng nữa
    /// (trước: iPad ô 41 → glyph 28pt; iPhone bật thanh gợi ý ô 43 → glyph 27.5pt).
    func testEmojiGridMatchesStockMetrics() {
        typealias M = EmojiGridMetrics
        // 29/09/2026 (tester 1.2.x: "emoji to hơn chút, thoáng hơn"): glyph +2pt, khe ngang
        // ≥ stock (bước − bbox glyph ≥ 16.7pt như stock iPhone).
        XCTAssertEqual(M.phonePortrait.pitchW, 50)
        XCTAssertEqual(M.phoneLandscape.pitchW, 46)
        XCTAssertEqual(M.padPortrait.pitchW, 70)
        XCTAssertEqual(M.padLandscape.pitchW, 72)
        for spec in [M.phonePortrait, M.phoneLandscape, M.padPortrait, M.padLandscape] {
            XCTAssertGreaterThanOrEqual(spec.pitchW - spec.font * 0.917, 16.5)
        }
        XCTAssertEqual(M.phonePortrait.font, 34)
        XCTAssertEqual(M.padPortrait.font, 52)
        XCTAssertEqual(M.phonePortrait.searchField, 40)
        XCTAssertEqual(M.phonePortrait.categoryRow, 40)
        XCTAssertEqual(M.padPortrait.searchField, 0, "iPad: 🔍 ở hàng category như stock")
        XCTAssertEqual(M.spec(pad: false, landscape: false), M.phonePortrait)
        XCTAssertEqual(M.spec(pad: false, landscape: true), M.phoneLandscape)
        XCTAssertEqual(M.spec(pad: true, landscape: false), M.padPortrait)
        XCTAssertEqual(M.spec(pad: true, landscape: true), M.padLandscape)

        // iPhone dọc — lưới đo trên simulator: tắt gợi ý 121.5 (3 hàng), bật gợi ý
        // (+34) 155.5 → 3 hàng thoáng (trước: 4 hàng 38.5 sát nhau); cao 193.5 → 4 hàng.
        let off = M.compute(gridHeight: 121.5, spec: M.phonePortrait)
        XCTAssertEqual(off, M(rows: 3, cellW: 50, cellH: 40.5, fontSize: 34))
        let on = M.compute(gridHeight: 155.5, spec: M.phonePortrait)
        XCTAssertEqual(on, M(rows: 3, cellW: 50, cellH: 51.5, fontSize: 34))
        XCTAssertEqual(M.compute(gridHeight: 193.5, spec: M.phonePortrait).rows, 4)
        // iPhone ngang: 2 hàng 43 (tắt gợi ý).
        XCTAssertEqual(M.compute(gridHeight: 86, spec: M.phoneLandscape),
                       M(rows: 2, cellW: 46, cellH: 43, fontSize: 32))
        // iPad dọc 186 → 3 hàng 62; ngang 246 → 4 hàng 61.5.
        XCTAssertEqual(M.compute(gridHeight: 186, spec: M.padPortrait),
                       M(rows: 3, cellW: 70, cellH: 62, fontSize: 52))
        XCTAssertEqual(M.compute(gridHeight: 246, spec: M.padLandscape),
                       M(rows: 4, cellW: 72, cellH: 61.5, fontSize: 52))

        for spec in [M.phonePortrait, M.phoneLandscape, M.padPortrait, M.padLandscape] {
            for h: CGFloat in stride(from: 60, through: 340, by: 7) {
                let m = M.compute(gridHeight: h, spec: spec)
                XCTAssertLessThanOrEqual(CGFloat(m.rows) * m.cellH, h + 0.01, "h=\(h): lưới tràn")
                XCTAssertLessThanOrEqual(m.rows, spec.maxRows)
                XCTAssertLessThan(m.fontSize, m.cellH, "h=\(h): glyph không tràn ô")
                if h >= 2 * spec.minPitchH {
                    XCTAssertGreaterThanOrEqual(m.cellH, spec.minPitchH, "h=\(h)")
                    XCTAssertEqual(m.fontSize, spec.font, "h=\(h): glyph cố định như stock")
                }
            }
        }
    }

    /// Plane thật: ô 46 × ≥38.5, glyph 32, ô tìm 40 cao; iPad không ô tìm trên cùng
    /// mà có nút 🔍 ở hàng dưới.
    @MainActor func testEmojiPlaneUsesStockGeometry() throws {
        let phone = EmojiPlane(dark: true, pad: false)
        phone.frame = CGRect(x: 0, y: 0, width: 402, height: 212)
        phone.layoutIfNeeded()
        XCTAssertEqual(phone.searchField.frame.height, 40)
        let grid = try XCTUnwrap(phone.subviews.compactMap { $0 as? UICollectionView }.first)
        grid.layoutIfNeeded()
        let cell = try XCTUnwrap(grid.visibleCells.first)
        XCTAssertEqual(cell.bounds.width, 50)
        XCTAssertGreaterThanOrEqual(cell.bounds.height, 40)

        let pad = EmojiPlane(dark: true, pad: true)
        pad.frame = CGRect(x: 0, y: 0, width: 834, height: 240)
        pad.layoutIfNeeded()
        XCTAssertGreaterThan(pad.convert(pad.searchField.bounds, from: pad.searchField).minY,
                             150, "iPad: 🔍 nằm ở hàng category dưới đáy")
        let pgrid = try XCTUnwrap(pad.subviews.compactMap { $0 as? UICollectionView }.first)
        pgrid.layoutIfNeeded()
        XCTAssertEqual(pgrid.visibleCells.first?.bounds.width, 70)
    }

    /// Thanh tìm luôn hiện trên cùng; chạm → onSearch (vào chế độ tìm với phím chữ).
    @MainActor func testEmojiPlaneHasSearchFieldOnTop() throws {
        let plane = EmojiPlane(dark: true, pad: false)
        plane.frame = CGRect(x: 0, y: 0, width: 390, height: 252)
        plane.layoutIfNeeded()
        let f = try XCTUnwrap(plane.searchField)
        XCTAssertLessThan(f.frame.minY, 10)
        XCTAssertGreaterThanOrEqual(f.frame.height, 30)
        XCTAssertGreaterThan(f.frame.width, 390 * 0.8, "thanh tìm gần đầy bề ngang như stock")
        var searched = false
        plane.onSearch = { searched = true }
        f.sendActions(for: .touchUpInside)
        XCTAssertTrue(searched)
    }

    /// Hàng category (Phil chốt 30/09/2026, giữ quy tắc 26/09): mở bằng phím emoji ⇒ ABC nằm
    /// ĐÚNG cột phím emoji (chạm lại chỗ cũ là về chữ), icon chia ĐỀU phần còn lại tới ⌫
    /// sát phải. Mở không qua phím (không biết chỗ) ⇒ ABC sát trái như stock.
    @MainActor func testEmojiCategoryRowABCAtEmojiKeyColumn() throws {
        let pad = UIDevice.current.userInterfaceIdiom == .pad
        let (kb, host) = makeKeyboard()
        _ = host
        let key = try XCTUnwrap(kb.debugEmojiKeyFrame)
        let emojiKey = try XCTUnwrap(kb.debugControl("Emoji"))
        emojiKey.sendActions(for: .touchDown)
        emojiKey.sendActions(for: .touchUpInside)
        kb.setNeedsLayout(); kb.layoutIfNeeded()
        func find(_ v: UIView) -> EmojiPlane? {
            if let p = v as? EmojiPlane { return p }
            for s in v.subviews { if let p = find(s) { return p } }
            return nil
        }
        let plane = try XCTUnwrap(find(kb))
        plane.layoutIfNeeded()
        let r = try XCTUnwrap(plane.debugCategoryRow)
        let abc = kb.convert(r.abc, from: plane)
        XCTAssertEqual(abc.minX, key.minX, accuracy: 0.5, "ABC đúng cột phím emoji")
        XCTAssertEqual(abc.maxX, key.maxX, accuracy: 0.5)
        // Chạm lại đúng chỗ phím emoji cũ (giữa phím) ⇒ trúng ABC.
        let tap = plane.convert(CGPoint(x: key.midX, y: key.midY), from: kb)
        XCTAssertTrue(plane.hitTest(tap, with: nil) === plane.abcButton, "chạm chỗ cũ = về chữ")
        let icons = r.icons
        XCTAssertEqual(icons.count, 10)
        XCTAssertGreaterThanOrEqual(icons[0].minX, abc.maxX - 0.5, "icon không chui dưới ABC")
        for f in icons { XCTAssertEqual(f.width, icons[0].width, accuracy: 0.5, "chia đều") }
        XCTAssertGreaterThanOrEqual(r.delete.maxX, kb.bounds.width - 8)
        XCTAssertLessThanOrEqual(r.delete.minX - (icons.last?.maxX ?? 0), 1, "icon trải tới sát ⌫")
        if !pad { XCTAssertGreaterThanOrEqual(icons[0].width, 24) }
    }

    @MainActor func testEmojiCategoryRowWithoutSlotIsStock() throws {
        for (pad, width, height) in [(false, CGFloat(402), CGFloat(246)), (true, CGFloat(834), CGFloat(274))] {
            let plane = EmojiPlane(dark: false, pad: pad)
            plane.frame = CGRect(x: 0, y: 0, width: width, height: height)
            plane.layoutIfNeeded()
            let r = try XCTUnwrap(plane.debugCategoryRow)
            XCTAssertLessThanOrEqual(r.abc.minX, 8, "pad \(pad)")
            XCTAssertGreaterThanOrEqual(r.delete.maxX, width - 8, "pad \(pad)")
            let icons = r.icons
            XCTAssertEqual(icons.count, 10)
            for f in icons { XCTAssertEqual(f.width, icons[0].width, accuracy: 0.5, "chia đều") }
        }
    }

    /// Host co plane emoji sau lượt layout đầu (300 → 274, như lúc host settle): lưới phải
    /// xếp lại theo ô MỚI. Trước: flow layout giữ ô cũ 81pt ⇒ 2 hàng cách nhau 137pt.
    @MainActor func testEmojiGridRelayoutsWhenPlaneShrinks() throws {
        for pad in [false, true] {
            let width: CGFloat = pad ? 834 : 402
            let plane = EmojiPlane(dark: false, pad: pad)
            let win = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 600))
            win.addSubview(plane); win.isHidden = false
            plane.frame = CGRect(x: 0, y: 0, width: width, height: 300)
            plane.layoutIfNeeded()
            plane.frame.size.height = 274
            plane.layoutIfNeeded()
            let grid = try XCTUnwrap(plane.subviews.compactMap { $0 as? UICollectionView }.first)
            let spec = plane.spec
            let m = EmojiGridMetrics.compute(
                gridHeight: EmojiGridMetrics.gridHeight(planeHeight: 274, spec: spec, pad: pad), spec: spec)
            // Lượt xếp lại chạy ở nhịp main kế (tối đa 1s khi máy test bận).
            let deadline = Date().addingTimeInterval(1)
            while Set(grid.visibleCells.map { $0.frame.minY.rounded() }).count != m.rows, Date() < deadline {
                RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            }
            XCTAssertEqual(grid.bounds.height, EmojiGridMetrics.gridHeight(planeHeight: 274, spec: spec, pad: pad),
                           accuracy: 0.5, "pad \(pad): gridHeight khớp constraint")
            let ys = Set(grid.visibleCells.map { $0.frame.minY.rounded() })
            XCTAssertEqual(ys.count, m.rows, "pad \(pad): đủ hàng sau khi co")
            for c in grid.visibleCells { XCTAssertEqual(c.frame.height, m.cellH, accuracy: 0.01) }
            win.isHidden = true
        }
    }

    // MARK: 2. dark mode

    /// Theme Hệ thống tối khớp stock iOS 27 (đo pixel simulator: nền #202020, phím
    /// #444444, chữ trắng) trong ±6/255 mỗi kênh, KHÔNG sáng hơn stock; chữ ≥ 7:1 trên
    /// phím và cả khi đè; phím tách khỏi nền; theme khác không đổi.
    func testSystemDarkMatchesStockAndContrast() {
        let p = KeyboardTheme.system.palette(systemDark: true)
        let stockKey = RGBA(hex: 0x444444), stockBg = RGBA(hex: 0x202020)
        for (a, b) in [(p.keyFill.r, stockKey.r), (p.keyFill.g, stockKey.g), (p.keyFill.b, stockKey.b)] {
            XCTAssertEqual(a, b, accuracy: 6.0 / 255)
        }
        XCTAssertLessThanOrEqual(p.keyFill.luminance, stockKey.luminance + 0.005, "không sáng hơn stock")
        XCTAssertGreaterThanOrEqual(RGBA.contrast(p.ink, p.keyFill), 7)
        XCTAssertGreaterThanOrEqual(RGBA.contrast(p.ink, p.specialFill), 7)
        XCTAssertGreaterThan(RGBA.contrast(p.keyFill, stockBg), 1.4, "phím phải nổi khỏi nền")
        XCTAssertGreaterThanOrEqual(RGBA.contrast(p.barInk, stockBg), 7)
        XCTAssertEqual(KeyboardTheme.oled.palette(systemDark: true).keyFill, RGBA(hex: 0x1C1C1E))
        XCTAssertEqual(KeyboardTheme.system.palette(systemDark: false).keyFill, .white)
    }

    // MARK: 3. thanh gợi ý

    private let sets: [KeyboardView.SuggestionSet] = [
        .init(nextWords: ["Đáp", "Được", "Đi"]),
        .init(nextWords: ["a", "nghiêng nghiêng", "ok"]),
        .init(literal: "đ", word: "đường", emojis: ["🛣️", "🚗"]),
        .init(literal: "xin", word: "xin chào các bạn", word2: "xinh"),
        .init(nextWords: ["và"]),
    ]

    /// Bố cục cố định: 3 ô bằng nhau, vạch ngăn đúng mép ô — không nhảy khi nội dung đổi.
    @MainActor func testSuggestionSlotsHaveFixedGeometry() {
        let (kb, host) = makeKeyboard()
        kb.showSuggestions(sets[0])
        let g0 = kb.debugSuggestionGeometry()
        XCTAssertEqual(g0.cells.count, 3)
        XCTAssertEqual(g0.dividers.count, 2)
        let cw = g0.cells[0].width
        XCTAssertGreaterThan(cw, 60)
        for c in g0.cells { XCTAssertEqual(c.width, cw, accuracy: 0.5) }
        XCTAssertEqual(g0.dividers[0].midX, g0.cells[0].maxX, accuracy: 0.5)
        XCTAssertEqual(g0.dividers[1].midX, g0.cells[1].maxX, accuracy: 0.5)
        for s in sets.dropFirst() {
            kb.showSuggestions(s)
            let g = kb.debugSuggestionGeometry()
            for i in 0..<3 { XCTAssertEqual(g.cells[i], g0.cells[i], "ô \(i) nhảy với \(s.nextWords)\(s.word ?? "")") }
            for i in 0..<2 { XCTAssertEqual(g.dividers[i].midX, g0.dividers[i].midX, accuracy: 0.01) }
            for t in g.visibleTitles {
                XCTAssertTrue(g0.cells.contains { $0.insetBy(dx: -1, dy: -40).contains(t) },
                              "chữ tràn khỏi ô: \(t)")
            }
        }
        withExtendedLifetime(host) {}
    }

    /// Issue #97 (bản phát hành): chạm ☰ khi đang có thẻ Dán ⇒ "Dán" vẽ ĐÈ lên slot giữa
    /// ("Anh"), vạch ngăn lệch. Mọi trạng thái: chữ không chồng nhau, không chồng thẻ Dán, ô
    /// bằng nhau — kể cả sau ☰ bật/tắt, chip số/emoji, chip "↩︎ từ cũ".
    @MainActor func testBarNeverOverlapsAcrossStates() {
        let (kb, host) = makeKeyboard()
        var paste = KeyboardView.SuggestionSet(nextWords: ["Em", "Anh", "Tôi"]); paste.paste = true
        var number = KeyboardView.SuggestionSet(literal: "12", word: "mười hai"); number.number = "12.000"
        var revise = KeyboardView.SuggestionSet(nextWords: ["có", "cơ"])
        revise.actionLabel = "\u{21A9}\u{FE0E} từ cũ"; revise.actionPayload = KeyboardView.undoReviseToken
        let states: [(String, KeyboardView.SuggestionSet)] = [
            ("paste", paste), ("words", sets[0]), ("paste", paste), ("emoji", sets[2]),
            ("number", number), ("revise", revise), ("long", sets[3]), ("paste", paste),
        ]
        func check(_ name: String) {
            let g = kb.debugSuggestionGeometry()
            let cw = g.cells[0].width
            for c in g.cells { XCTAssertEqual(c.width, cw, accuracy: 0.5, "\(name): ô lệch") }
            for (i, a) in g.visibleTitles.enumerated() {
                if let card = g.pasteCard { XCTAssertFalse(a.intersects(card), "\(name): chữ đè thẻ Dán") }
                for b in g.visibleTitles[(i + 1)...] { XCTAssertFalse(a.intersects(b), "\(name): chữ chồng chữ") }
            }
            if g.pasteCard != nil { XCTAssertTrue(g.visibleTitles.isEmpty, "\(name): thẻ Dán phải thay cả bar") }
        }
        for (name, s) in states {
            kb.showSuggestions(s); check(name)
            kb.debugTapBurger(); kb.showSuggestions(s); check(name + "+☰")
            kb.debugTapBurger(); kb.showSuggestions(s); check(name + "+☰☰")
        }
        withExtendedLifetime(host) {}
    }

    /// Regression: thẻ Dán hiện thì KHÔNG còn chữ gợi ý nào vẽ chung (kể cả sau
    /// rebuild/đổi plane — đường từng đặt lại alpha bar = 1 làm "Đáp" đè "Dán").
    @MainActor func testPasteCardHidesSlotsCompletely() throws {
        let (kb, host) = makeKeyboard()
        kb.showSuggestions(sets[0])
        XCTAssertFalse(kb.debugSuggestionGeometry().visibleTitles.isEmpty)
        var paste = sets[0]; paste.paste = true
        kb.showSuggestions(paste)
        var g = kb.debugSuggestionGeometry()
        let card = try XCTUnwrap(g.pasteCard)
        XCTAssertTrue(g.visibleTitles.isEmpty, "slot bị thẻ Dán thay phải ẩn hẳn")
        kb.debugRefreshChrome()                 // rebuild / xoay / đổi plane
        kb.debugCycleThroughNumbers()
        g = kb.debugSuggestionGeometry()
        if g.pasteCard != nil {
            XCTAssertTrue(g.visibleTitles.filter { $0.intersects(card) }.isEmpty,
                          "chữ gợi ý đè lên thẻ Dán sau rebuild")
        }
        // Gõ chữ → thẻ biến mất, gợi ý hiện lại bình thường.
        kb.hidePasteCard()
        kb.showSuggestions(sets[2])
        g = kb.debugSuggestionGeometry()
        XCTAssertNil(g.pasteCard)
        XCTAssertFalse(g.visibleTitles.isEmpty)
        withExtendedLifetime(host) {}
    }

    // MARK: 4. trackpad

    func testCoalescerMergesSameAxisAndKeepsOrder() {
        var c = TrackpadCoalescer()
        c.add(.init(axis: .horizontal, count: 2))
        c.add(.init(axis: .horizontal, count: 3))
        XCTAssertEqual(c.drain(), [.init(axis: .horizontal, count: 5)])
        XCTAssertTrue(c.isEmpty)
        c.add(.init(axis: .horizontal, count: 1))
        c.add(.init(axis: .vertical, count: -1))
        c.add(.init(axis: .vertical, count: -2))
        XCTAssertEqual(c.drain(), [.init(axis: .horizontal, count: 1), .init(axis: .vertical, count: -3)])
        c.add(.init(axis: .horizontal, count: 2))
        c.add(.init(axis: .horizontal, count: -2))       // triệt tiêu trong frame → không gửi gì
        XCTAssertEqual(c.drain(), [])
        c.add(.init(axis: .horizontal, count: 0))
        XCTAssertTrue(c.isEmpty)
    }

    /// Vệt kéo nhanh mẫu (touch 120Hz, màn 60Hz): cùng quãng dời con trỏ nhưng số lệnh
    /// adjustTextPosition (XPC) giảm; phím mờ ngay khi vào trackpad.
    @MainActor func testTrackpadDragSendsAtMostOneCommandPerFrame() {
        func trace() -> [(x: CGFloat, y: CGFloat, t: CFTimeInterval)] {
            // 0.25s chậm (40pt/s) → 0.5s nhanh (1200pt/s) → 0.5s về trái (800pt/s).
            var out: [(x: CGFloat, y: CGFloat, t: CFTimeInterval)] = []
            var x: CGFloat = 100, t: CFTimeInterval = 0
            let dt = 1.0 / 120
            for _ in 0..<30 { out.append((x, 250, t)); x += 40 * dt; t += dt }
            for _ in 0..<60 { out.append((x, 250, t)); x += 1200 * dt; t += dt }
            for _ in 0..<60 { out.append((x, 250, t)); x -= 800 * dt; t += dt }
            return out
        }
        func run(coalesce: Bool) -> (commands: Int, total: Int, ms: Double) {
            var commands = 0, total = 0
            let (kb, host) = makeKeyboard { key in
                if case .moveCursor(let n) = key { commands += 1; total += n }
            }
            var began: Bool?
            kb.onTrackpad = { on in if began == nil { began = on } }
            let t0 = CACurrentMediaTime()
            kb.debugTrackpadDrag(trace(), frameEvery: 2, coalesce: coalesce)
            let ms = (CACurrentMediaTime() - t0) * 1000
            XCTAssertEqual(began, true)
            XCTAssertFalse(kb.debugTrackpadDimmed, "nhả tay → hết mờ")
            withExtendedLifetime(host) {}
            return (commands, total, ms)
        }
        let before = run(coalesce: false), after = run(coalesce: true)
        print("TRACKPAD before: \(before.commands) lệnh, Σ=\(before.total), \(String(format: "%.2f", before.ms))ms"
              + " | after: \(after.commands) lệnh, Σ=\(after.total), \(String(format: "%.2f", after.ms))ms")
        XCTAssertEqual(after.total, before.total, "cùng quãng dời con trỏ")
        XCTAssertLessThanOrEqual(after.commands, 150 / 2 + 1, "≤ 1 lệnh / frame")
        XCTAssertLessThan(after.commands, before.commands)
    }

    // MARK: 5. ô phóng to chữ

    func testKeyPreviewSettingDefaultsOn() {
        let suite = "kp-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        defer { d.removePersistentDomain(forName: suite) }
        XCTAssertTrue(KeyboardView.keyPreviewSetting(nil))
        XCTAssertTrue(KeyboardView.keyPreviewSetting(d))
        d.set(false, forKey: KeyboardView.keyPreviewKey)
        XCTAssertFalse(KeyboardView.keyPreviewSetting(d))
        d.set(true, forKey: KeyboardView.keyPreviewKey)
        XCTAssertTrue(KeyboardView.keyPreviewSetting(d))
    }

    /// Tắt: bấm phím không tạo/vẽ balloon. Bật: như cũ.
    @MainActor func testKeyPreviewOffCreatesNoBalloon() throws {
        let (kb, host) = makeKeyboard()
        kb.debugSetKeyPreview(false)
        let q = try XCTUnwrap(kb.debugLetterFrame("q"))
        let p = CGPoint(x: q.midX, y: q.midY)
        kb.debugTouch(from: p, through: [p], start: 1)
        XCTAssertFalse(kb.debugBalloonMade)
        kb.debugSetKeyPreview(true)
        let routeT: TimeInterval = 5
        kb.debugTouch(from: p, through: [p], start: routeT)
        XCTAssertTrue(kb.debugBalloonMade)
        withExtendedLifetime(host) {}
    }

    // MARK: 6. mẫu câu mặc định

    /// Nhãn mặc định không dùng ❓ (đỏ — trông như lỗi hiển thị); nội dung câu giữ nguyên.
    func testDefaultTemplateLabelsHaveNoRedQuestionMark() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("ios-mau-cau.yml")
        let items = KeyboardView.parseTemplatesYAML(try String(contentsOf: url, encoding: .utf8))
        XCTAssertEqual(items.count, 23)
        for i in items { XCTAssertFalse(i.label.contains("❓"), i.label) }
        let texts = items.map(\.text)
        for t in ["Đang ở đâu vậy?", "Đang làm gì vậy", "Lúc nào gặp được nhỉ", "Bạn đang ở đâu?",
                  "https://api.ipify.org"] {
            XCTAssertTrue(texts.contains(t), t)
        }
    }
}

/// Hữu Đông 28/09/2026: "Thanh gợi ý bị ngắn 1 đoạn" sau khi dùng bảng clipboard 📋.
final class ClipboardBarRegressionTests: XCTestCase {

    /// Host như KeyboardViewController: bàn phím ghim 4 mép vào view gốc (khung do host cấp).
    @MainActor private func makeHosted(height: CGFloat = 290)
        -> (kb: KeyboardView, root: UIView, win: UIWindow, height: NSLayoutConstraint) {
        let win = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        win.isHidden = false
        let root = UIView()
        root.translatesAutoresizingMaskIntoConstraints = false
        win.addSubview(root)
        let h = root.heightAnchor.constraint(equalToConstant: height)
        NSLayoutConstraint.activate([
            root.leftAnchor.constraint(equalTo: win.leftAnchor),
            root.rightAnchor.constraint(equalTo: win.rightAnchor),
            root.bottomAnchor.constraint(equalTo: win.bottomAnchor), h,
        ])
        let kb = KeyboardView(needsGlobe: false, inputController: nil) { _ in }
        kb.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(kb)
        NSLayoutConstraint.activate([
            kb.leftAnchor.constraint(equalTo: root.leftAnchor),
            kb.rightAnchor.constraint(equalTo: root.rightAnchor),
            kb.topAnchor.constraint(equalTo: root.topAnchor),
            kb.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        kb.setSuggestionsEnabled(true)
        kb.setClipboardButton(visible: true)
        win.layoutIfNeeded()
        return (kb, root, win, h)
    }

    /// Mở như controller (toggleClipboardPanel): frame = vùng phím, overlayPanel.
    @MainActor private func openPanel(_ kb: KeyboardView) -> ClipboardPanel {
        let p = ClipboardPanel()
        p.frame = kb.keyAreaFrame
        kb.addSubview(p)
        kb.overlayPanel = p
        p.reload(items: [ClipItem(text: String(repeating: "nội dung rất dài ", count: 20), at: 0,
                                  pinned: false, sensitive: false),
                         ClipItem(text: "0912345678", at: 0, pinned: true, sensitive: false)],
                 dark: false, incognito: false)
        kb.setNeedsLayout()
        return p
    }

    /// Mở → gõ → đóng → gõ: bar/📋 và 3 ô giữ nguyên khung trước khi mở.
    @MainActor func testBarGeometryUnchangedAfterPanelOpenClose() {
        let (kb, root, win, _) = makeHosted()
        kb.showSuggestions(.init(nextWords: ["Em", "Anh", "Tôi"]))
        let g0 = kb.debugStripLayout()
        let clip0 = g0.clip
        XCTAssertNotNil(clip0)
        // Không còn ⌄: 📋 sát mép phải, bar sát trái 📋.
        XCTAssertEqual(clip0?.maxX ?? 0, kb.bounds.width, accuracy: 0.5)
        XCTAssertEqual(g0.bar.maxX, clip0?.minX ?? 0, accuracy: 0.5)
        XCTAssertEqual(g0.slots.count, 3)
        let p = openPanel(kb)
        root.layoutIfNeeded()
        kb.showSuggestions(.init(literal: "x", word: "xin"))
        let g1 = kb.debugStripLayout()
        XCTAssertEqual(g1.bar, g0.bar); XCTAssertEqual(g1.clip, g0.clip); XCTAssertEqual(g1.cells, g0.cells)
        XCTAssertGreaterThanOrEqual(p.frame.minY, g0.bar.maxY, "panel không đè bar")
        p.removeFromSuperview(); kb.overlayPanel = nil; kb.setNeedsLayout()
        kb.showSuggestions(.init(nextWords: ["Và", "Là", "Có"]))
        let g2 = kb.debugStripLayout()
        XCTAssertEqual(g2.bar, g0.bar); XCTAssertEqual(g2.clip, g0.clip)
        XCTAssertEqual(g2.slots, g0.slots)
        withExtendedLifetime(win) {}
    }

    /// Bàn phím đổi chiều cao khi panel đang mở (xoay / host cấp lại khung): panel phải bám
    /// vùng phím — trước đây cao cố định + neo đáy ⇒ trồi lên đè dải gợi ý.
    /// 18/10/2026 (bar mặc định Vừa 26pt): host cấp thiếu (240) ⇒ bar CO về chỗ còn lại (sàn 20),
    /// co hết mới dời lên VỪA đủ để không đè hàng đầu (không cao hơn đệm trên); cấp đủ lại thì về
    /// đúng khung cũ. Từ c02fbdb6 (29/10) bar canh giữa dải (đỉnh 9, không còn 4) ⇒ ở 240 bar phải
    /// dời lên — bất biến cũ "đỉnh bar đứng yên" chỉ đúng khi đỉnh đã ghim sát đệm trên.
    @MainActor func testPanelFollowsKeyAreaWhenKeyboardResizes() {
        let (kb, root, win, h) = makeHosted(height: 290)
        kb.showSuggestions(.init(nextWords: ["Em", "Anh", "Tôi"]))
        let bar = kb.debugStripLayout().bar
        let p = openPanel(kb)
        root.layoutIfNeeded()
        for height: CGFloat in [240, 320, 290] {
            h.constant = height
            win.layoutIfNeeded()
            XCTAssertEqual(p.frame, kb.keyAreaFrame, "cao \(height)")
            let now = kb.debugStripLayout().bar
            XCTAssertGreaterThanOrEqual(p.frame.minY, now.maxY, "cao \(height): panel đè bar")
            XCTAssertLessThanOrEqual(now.minY, bar.minY, "cao \(height): bar chỉ dời lên, không tụt xuống")
            XCTAssertGreaterThanOrEqual(now.minY, KeyboardView.barTopPad, "cao \(height): bar vượt đệm trên")
            if now.minY < bar.minY {   // đã dời ⇒ phải co hết trước, và dời vừa đủ (chạm hàng đầu)
                XCTAssertEqual(now.height, SuggestionBarHeight.baseRow, "cao \(height): dời trước khi co hết")
                XCTAssertEqual(now.maxY, kb.keyAreaFrame.minY, accuracy: 0.5, "cao \(height): dời quá tay")
            }
            XCTAssertEqual(now.width, bar.width)
            XCTAssertGreaterThanOrEqual(now.height, SuggestionBarHeight.baseRow, "cao \(height)")
            if height >= 290 { XCTAssertEqual(now, bar, "cao \(height)") }
        }
        withExtendedLifetime(win) {}
    }

    /// Chip clipboard [Dán SĐT…][Dán] CHIA ĐỀU bar (như Android) — không để ô 3 trống
    /// khiến bar trông ngắn đi một đoạn; gõ tiếp thì về 3 ô cố định.
    @MainActor func testClipChipsFillWholeBar() {
        let (kb, _, win, _) = makeHosted()
        kb.showSuggestions(.init(nextWords: ["Em", "Anh", "Tôi"]))
        let g0 = kb.debugStripLayout()
        var s = KeyboardView.SuggestionSet(nextWords: ["Em", "Anh", "Tôi"])
        s.paste = true
        s.clipChips = [("Dán SĐT 0912…", KeyboardView.clipTokenPrefix + "0912345678")]
        kb.showSuggestions(s)
        var g = kb.debugStripLayout()
        XCTAssertEqual(g.slots.count, 2)
        XCTAssertEqual(g.slots[0].minX, g0.bar.minX + 3, accuracy: 0.5)
        XCTAssertEqual(g.slots[1].maxX, g0.bar.maxX - 3, accuracy: 0.5, "chip cuối chạm mép phải bar")
        XCTAssertEqual(g.slots[0].width, g.slots[1].width, accuracy: 0.5)
        XCTAssertEqual(g.dividers.count, 1)
        XCTAssertEqual(g.dividers[0].midX, g0.bar.midX, accuracy: 0.5)
        s.paste = false   // nút Dán tắt: một chip = cả bar
        kb.showSuggestions(s)
        g = kb.debugStripLayout()
        XCTAssertEqual(g.slots.count, 1)
        XCTAssertEqual(g.slots[0].width, g0.bar.width - 6, accuracy: 0.5)
        XCTAssertTrue(g.dividers.isEmpty)
        kb.showSuggestions(.init(nextWords: ["Và", "Là", "Có"]))
        g = kb.debugStripLayout()
        XCTAssertEqual(g.slots, g0.slots)
        XCTAssertEqual(g.dividers, g0.dividers)
        withExtendedLifetime(win) {}
    }
}
