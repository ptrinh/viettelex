import XCTest
import UIKit

/// Hồi quy đợt 10/11/2026 (KEYBOARD-STARTUP.md §7): ảnh nền / ảnh theme không giải lại theo từng khung
/// tạm của host (mới nhất thắng), iPad không dựng lại cả plane ở didAppear vì phím 🌐, nét vuốt vẽ một
/// lần mỗi lượt touchesMoved (không mỗi điểm gộp).
final class OpenPathPerfTests: XCTestCase {

    @MainActor private static func spin(_ s: TimeInterval) { RunLoop.main.run(until: Date(timeIntervalSinceNow: s)) }

    // MARK: SizedDecodeGate (thuần)

    @MainActor func testGateLatestWinsAcrossInterimSizes() {
        let gate = SizedDecodeGate()
        let sizes = [CGSize(width: 414, height: 896), CGSize(width: 414, height: 452),
                     CGSize(width: 414, height: 268), CGSize(width: 414, height: 291)]
        let tickets = sizes.map { _ in gate.next() }
        let final = sizes.last!
        // Việc đã xếp hàng của khung tạm: bỏ ngay đầu khối.
        for t in tickets.dropLast() { XCTAssertFalse(gate.isCurrent(t)) }
        XCTAssertTrue(gate.isCurrent(tickets.last!))
        // Kết quả về main: chỉ đúng một lần gán, của cỡ cuối; kết quả cũ về muộn không đè.
        var applied: [CGSize] = []
        func land(_ i: Int) {
            if gate.verdict(tickets[i], requested: sizes[i], current: final) == .apply { applied.append(sizes[i]) }
        }
        land(3); land(0); land(2); land(1)   // thứ tự về bất kỳ, cũ về SAU mới
        XCTAssertEqual(applied, [final])
        // Vé mới nhất nhưng view đã đổi cỡ ⇒ xin lại, không gán.
        XCTAssertEqual(gate.verdict(tickets[3], requested: final, current: sizes[0]), .resized)
        gate.cancel()
        XCTAssertEqual(gate.verdict(tickets[3], requested: final, current: final), .stale)
    }

    @MainActor func testInterimSizeClassification() {
        XCTAssertFalse(SizedDecodeGate.isInterim(viewHeight: 291, expected: 291))
        XCTAssertFalse(SizedDecodeGate.isInterim(viewHeight: 291.5, expected: 291), "lệch làm tròn ≤ 1 pt")
        XCTAssertTrue(SizedDecodeGate.isInterim(viewHeight: 896, expected: 291))
        XCTAssertTrue(SizedDecodeGate.isInterim(viewHeight: 268, expected: 291))
        XCTAssertFalse(SizedDecodeGate.isInterim(viewHeight: 0, expected: 0), "chưa xin gì ⇒ không hoãn")
    }

    // MARK: ảnh nền — cache

    private var wallpaperFile: URL!

    @MainActor private func installWallpaperFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("vt-wall-\(UUID().uuidString).jpg")
        let ctx = try XCTUnwrap(CGContext(data: nil, width: 810, height: 1080, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue))
        ctx.setFillColor(UIColor.systemTeal.cgColor); ctx.fill(CGRect(x: 0, y: 0, width: 810, height: 1080))
        ctx.setFillColor(UIColor.systemPink.cgColor); ctx.fill(CGRect(x: 100, y: 100, width: 400, height: 600))
        let data = try XCTUnwrap(Wallpaper.encodeJPEG(try XCTUnwrap(ctx.makeImage())))
        try data.write(to: url)
        wallpaperFile = url
        Wallpaper.debugURLOverride = url
        Wallpaper.queue.sync { Wallpaper.dropCache() }
    }

    override func tearDown() {
        Wallpaper.debugURLOverride = nil
        Wallpaper.queue.sync { Wallpaper.dropCache() }
        if let f = wallpaperFile { try? FileManager.default.removeItem(at: f) }
        wallpaperFile = nil
        GlobeMemory.debugEnabled = nil
        GlobeMemory.debugReset()
        UserDefaults.standard.removeObject(forKey: GlobeMemory.key)
        KeyboardViewController.debugIdiom = nil
        KeyboardViewController.debugNeedsSwitchKey = nil
        super.tearDown()
    }

    @MainActor func testSupersededRequestNeverEvictsCache() throws {
        try installWallpaperFile()
        let a = CGSize(width: 414, height: 291), b = CGSize(width: 414, height: 896)
        Wallpaper.queue.sync {
            let d0 = Wallpaper.debugDecodes
            XCTAssertNotNil(Wallpaper.loadForKeyboard(version: 1, viewSize: a, scale: 2))
            XCTAssertEqual(Wallpaper.debugDecodes - d0, 1)
            // Yêu cầu đã bị thay (khung tạm) ⇒ không giải, không đuổi ảnh cỡ cuối.
            XCTAssertNil(Wallpaper.loadForKeyboard(version: 1, viewSize: b, scale: 2, stillWanted: { false }))
            XCTAssertEqual(Wallpaper.debugDecodes - d0, 1)
            XCTAssertTrue(Wallpaper.hasCache)
            // Hiện lại cùng cỡ ⇒ dùng cache, 0 lần giải.
            XCTAssertNotNil(Wallpaper.loadForKeyboard(version: 1, viewSize: a, scale: 2))
            XCTAssertEqual(Wallpaper.debugDecodes - d0, 1)
        }
    }

    // MARK: ảnh nền — trên controller thật, chuỗi khung host

    private let suite = "openpath-\(UUID().uuidString)"

    @MainActor private func useWallpaperDefaults() -> () -> Void {
        let saved = UserDefaultsProvider.shared
        let savedPaywall = PlusGate.paywallEnabled
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        PlusGate.paywallEnabled = false
        d.set(true, forKey: ThemeSettings.wallpaperKey)
        d.set(1.0, forKey: ThemeSettings.versionKey)
        UserDefaultsProvider.shared = d
        return { [suite] in
            UserDefaultsProvider.shared = saved
            PlusGate.paywallEnabled = savedPaywall
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        }
    }

    /// Host: khung 0 → 896 → 452 → 268 → chiều cao xin, liền nhau (không quay runloop giữa các khung).
    @MainActor private func walkHostSizes(_ r: KeyboardStartupTests.Rig) -> CGSize {
        let kb = r.vc.debugKeyboard
        let finalH = kb.constraintHeight
        for h: CGFloat in [0, 896, 452, 268, finalH] {
            r.vc.view.frame = CGRect(x: 0, y: 896 - h, width: 414, height: h)
            r.vc.view.layoutIfNeeded()
            CATransaction.flush()
        }
        return kb.bounds.size
    }

    @MainActor private func settle() {
        for _ in 0..<4 {
            Wallpaper.queue.sync {}
            Self.spin(SizedDecodeGate.settleDelay / 2 + 0.05)
        }
    }

    @MainActor func testHostSizeSequenceDecodesWallpaperOnceAtFinalSize() throws {
        try installWallpaperFile()
        let restore = useWallpaperDefaults()
        defer { restore() }

        // Lần hiện đầu (cache trống): đúng MỘT lần giải, đúng MỘT lần gán, ở cỡ cuối.
        let d0 = Wallpaper.debugDecodes
        let r = KeyboardStartupTests.Rig(fullAccess: false)
        let final = walkHostSizes(r)
        settle()
        let kb = r.vc.debugKeyboard
        XCTAssertEqual(final.height, kb.constraintHeight, accuracy: 1, "khung cuối = chiều cao xin")
        XCTAssertEqual(Wallpaper.debugDecodes - d0, 1, "khung tạm không giải ảnh")
        XCTAssertEqual(kb.debugWallpaperApplies, [final], "chỉ gán ảnh cỡ cuối, ảnh cũ không đè")
        let img = try XCTUnwrap(kb.debugWallpaperImage)
        // Ảnh cắt theo tỉ lệ cỡ CUỐI (nguồn hẹp hơn view ⇒ giữ độ phân giải gốc, cùng tỉ lệ — aspectFillCrop).
        XCTAssertEqual(img.size.width / img.size.height, final.width / final.height, accuracy: 0.02)
        XCTAssertNotEqual(final.height, 896)
        r.close()

        // Hiện lại cùng cỡ (controller mới): khung tạm không đuổi cache ⇒ 0 lần giải.
        let d1 = Wallpaper.debugDecodes
        let r2 = KeyboardStartupTests.Rig(fullAccess: false)
        let final2 = walkHostSizes(r2)
        settle()
        XCTAssertEqual(final2, final)
        XCTAssertEqual(Wallpaper.debugDecodes - d1, 0, "hiện lại cùng cỡ dùng ảnh đã cache")
        XCTAssertEqual(r2.vc.debugKeyboard.debugWallpaperApplies, [final])
        XCTAssertNotNil(r2.vc.debugKeyboard.debugWallpaperImage)
        r2.close()
    }

    @MainActor func testHostHoldingOtherHeightStillGetsWallpaper() throws {
        // Host giữ một chiều cao khác chiều cao xin (không bao giờ khớp): vẫn phải có ảnh nền.
        try installWallpaperFile()
        let restore = useWallpaperDefaults()
        defer { restore() }
        let r = KeyboardStartupTests.Rig(fullAccess: false)
        defer { r.close() }
        let kb = r.vc.debugKeyboard
        let odd = kb.constraintHeight + 120
        r.vc.view.frame = CGRect(x: 0, y: 896 - odd, width: 414, height: odd)
        r.vc.view.layoutIfNeeded()
        XCTAssertTrue(SizedDecodeGate.isInterim(viewHeight: kb.bounds.height, expected: kb.constraintHeight))
        settle()
        XCTAssertEqual(kb.debugWallpaperApplies.last, kb.bounds.size)
        XCTAssertNotNil(kb.debugWallpaperImage)
    }

    // MARK: phím 🌐 trước khung đầu

    @MainActor func testPreFrameGlobeGuess() {
        let se = CGSize(width: 375, height: 667), x = CGSize(width: 402, height: 874)
        XCTAssertEqual(KeyLayout.preFrameGlobeGuess(remembered: nil, phone: true, screen: se), true)
        XCTAssertEqual(KeyLayout.preFrameGlobeGuess(remembered: nil, phone: true, screen: x), false)
        XCTAssertNil(KeyLayout.preFrameGlobeGuess(remembered: nil, phone: false, screen: x), "iPad chưa nhớ ⇒ không đoán")
        XCTAssertEqual(KeyLayout.preFrameGlobeGuess(remembered: true, phone: false, screen: nil), true)
        XCTAssertEqual(KeyLayout.preFrameGlobeGuess(remembered: false, phone: true, screen: se), false, "giá trị thật thắng nút Home")
    }

    @MainActor func testGlobeMemoryPersistsAcrossProcess() {
        GlobeMemory.debugEnabled = true
        let d = UserDefaults(suiteName: suite)!
        defer { d.removePersistentDomain(forName: suite) }
        GlobeMemory.debugReset()
        XCTAssertNil(GlobeMemory.remembered(d))
        GlobeMemory.record(true, d)
        GlobeMemory.debugReset()                 // "tiến trình mới"
        XCTAssertEqual(GlobeMemory.remembered(d), true)
        GlobeMemory.debugEnabled = false
        XCTAssertNil(GlobeMemory.remembered(d), "tắt (mặc định trong XCTest) ⇒ không đoán")
    }

    /// Mở trên iPad (loại máy giả) tới khung đầu, rồi didAppear; trả số lần dựng cả plane ở didAppear.
    @MainActor private func padDidAppearBuilds() -> (builds: Int, rows: [[String]]) {
        KeyboardViewController.debugIdiom = .pad
        KeyboardViewController.debugNeedsSwitchKey = true
        let r = KeyboardStartupTests.Rig(fullAccess: false, appear: false)
        defer { r.close() }
        Self.spin(KeyboardStartupTests.Rig.slideIn)
        let b0 = KeyboardView.perfFullBuilds
        r.vc.endAppearanceTransition()
        return (KeyboardView.perfFullBuilds - b0, r.vc.debugKeyboard.debugRowLabels())
    }

    @MainActor func testPadWithRememberedGlobeDoesNotRebuildAtDidAppear() {
        UserDefaults.standard.removeObject(forKey: GlobeMemory.key)
        GlobeMemory.debugEnabled = true
        GlobeMemory.debugReset()
        // Chưa nhớ (lần đầu): hàng đáy dựng không 🌐 rồi didAppear dựng lại — hành vi cũ, chỉ một lần.
        let first = padDidAppearBuilds()
        XCTAssertEqual(first.builds, 1)
        XCTAssertEqual(GlobeMemory.remembered(), true, "didAppear ghi giá trị thật")
        // Từ lần sau (kể cả tiến trình mới — đọc lại defaults): đoán đúng ⇒ 0 lần dựng ở didAppear.
        GlobeMemory.debugReset()
        let next = padDidAppearBuilds()
        XCTAssertEqual(next.builds, 0, "iPad nhớ phím 🌐 ⇒ didAppear không dựng lại")
        XCTAssertEqual(next.rows, first.rows, "hàng phím y như sau khi sửa ở didAppear")
    }

    // MARK: nét vuốt — một lần vẽ mỗi lượt touchesMoved

    @MainActor private func swipeRun(coalesced: Int) throws -> (redraws: Int, events: Int, xs: [Float], ys: [Float], ts: [Double]) {
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        let saved = UserDefaultsProvider.shared
        UserDefaultsProvider.shared = d
        defer { UserDefaultsProvider.shared = saved; d.removePersistentDomain(forName: suite) }
        let win = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 300))
        win.isHidden = false
        defer { win.isHidden = true }
        let kb = KeyboardView(needsGlobe: false, inputController: nil) { _ in }
        kb.frame = win.bounds
        win.addSubview(kb)
        kb.applyAppearance(.light, style: .light)
        kb.layoutIfNeeded()
        kb.swipeEnabled = true
        var got: SwipePath?
        kb.onSwipeEnded = { p, _ in got = p }
        let keys = try "viet".map { c -> CGPoint in
            let f = try XCTUnwrap(kb.debugLetterFrame(String(c)))
            return CGPoint(x: f.midX, y: f.midY + TouchGeometry.yOffset)
        }
        var pts: [CGPoint] = []
        for i in 1..<keys.count {
            for j in 1...16 {
                let u = CGFloat(j) / 16
                pts.append(CGPoint(x: keys[i - 1].x + (keys[i].x - keys[i - 1].x) * u,
                                   y: keys[i - 1].y + (keys[i].y - keys[i - 1].y) * u))
            }
        }
        XCTAssertTrue(kb.debugTouch(from: keys[0], through: pts, dt: 0.008, start: 100, coalesced: coalesced))
        let path = try XCTUnwrap(got)
        let redraws = try XCTUnwrap(kb.debugTrail).debugRedraws
        let events = (pts.count + coalesced - 1) / coalesced
        return (redraws, events, Array(path.xs.prefix(path.count)), Array(path.ys.prefix(path.count)),
                Array(path.ts.prefix(path.count)))
    }

    @MainActor func testTrailRedrawsOncePerMoveEventDecoderInputUnchanged() throws {
        let one = try swipeRun(coalesced: 1)
        let two = try swipeRun(coalesced: 2)
        let four = try swipeRun(coalesced: 4)
        print("TRAIL redraws coalesced1=\(one.redraws)/\(one.events) 2=\(two.redraws)/\(two.events) 4=\(four.redraws)/\(four.events)")
        for r in [one, two, four] {
            XCTAssertGreaterThan(r.redraws, 0)
            XCTAssertLessThanOrEqual(r.redraws, r.events, "tối đa MỘT lần vẽ mỗi lượt touchesMoved")
        }
        XCTAssertLessThan(four.redraws, one.redraws)
        // Decoder nhận đúng từng điểm gộp như trước, bất kể gộp bao nhiêu.
        XCTAssertGreaterThan(one.xs.count, 8)
        for r in [two, four] {
            XCTAssertEqual(r.xs, one.xs); XCTAssertEqual(r.ys, one.ys); XCTAssertEqual(r.ts, one.ts)
        }
    }
}
