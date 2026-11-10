import XCTest
import UIKit

/// Hồi quy cho các sửa RAM (iOS/docs/RAM-AUDIT.md): bảng emoji dạng id, nhả cache khi rời
/// emoji / cảnh báo bộ nhớ, ảnh nền @2x cắt đúng view. Rò rỉ cây view: ViewTreeLeakTests.
final class RamFixTests: XCTestCase {

    // MARK: emoji

    func testEmojiCategoriesAreCompactIds() {
        // Font Apple Color Emoji của CoreText (kiểm glyph + vẽ lưới dùng chung, ~1,8 MB lần đầu
        // trong process) nạp TRƯỚC — thứ đo dưới đây chỉ là bảng của mình.
        let hf0 = RamBreakdownTests.heapBytes()
        _ = EmojiData.canRender("😀")
        let hf1 = RamBreakdownTests.heapBytes()
        EmojiData.dropCaches()
        let h0 = RamBreakdownTests.heapBytes()
        let cats = EmojiData.categories
        let h1 = RamBreakdownTests.heapBytes()
        let n = cats.reduce(0) { $0 + $1.ids.count }
        print("RAMFIX emoji font \(hf1 - hf0) B, categories(ids) \(h1 - h0) B, n=\(n)")
        XCTAssertGreaterThan(n, 1500)
        // [UInt16]: ~2 B/emoji (+ cache kiểm glyph).
        XCTAssertLessThan(h1 - h0, 100_000, "bảng category tốn \(h1 - h0) B heap")
        // Cùng nội dung + thứ tự như đọc thẳng từ blob (lọc glyph).
        for (cat, raw) in zip(cats, EmojiData.rawCategories) {
            XCTAssertEqual(cat.name, raw.name)
            let expect = (raw.start..<(raw.start + raw.count)).filter { EmojiData.isSupported($0) }
            XCTAssertEqual(cat.ids.map(Int.init), expect)
        }
        XCTAssertEqual(EmojiData.emoji(Int(cats.last!.ids.first!)), EmojiData.emoji(EmojiData.rawCategories.last!.start))
    }

    func testEmojiDropCachesRebuildsSame() {
        let a = EmojiData.categories.map { $0.ids }
        XCTAssertTrue(EmojiData.hasCachedCategories)
        EmojiData.dropCaches()
        XCTAssertFalse(EmojiData.hasCachedCategories)
        XCTAssertEqual(EmojiData.categories.map { $0.ids }, a)
    }

    func testEmojiSectionMixesIdsAndRecents() {
        let s = EmojiPlane.Section(name: "smileys", ids: [0, 1])
        XCTAssertEqual(s.count, 2)
        XCTAssertEqual(s[1], EmojiData.emoji(1))
        let r = EmojiPlane.Section(name: "recents", strings: ["👍🏽", "😀"])
        XCTAssertEqual(r.count, 2)
        XCTAssertEqual(r[0], "👍🏽")
    }

    /// Lưới: không prefetch cột ngoài màn hình, ô không co chữ; rời lưới ⇒ nhả bảng category.
    @MainActor func testEmojiPlaneGridSettingsAndLeaveDropsCache() {
        let r = autoreleasepool { KeyboardBenchTests.Rig() }
        let kb = r.vc.debugKeyboard
        kb.debugShowEmojiPlane()
        r.vc.view.layoutIfNeeded()
        XCTAssertTrue(EmojiData.hasCachedCategories)
        guard let cv = Self.find(UICollectionView.self, in: r.vc.view) else { return XCTFail("không thấy lưới emoji") }
        XCTAssertFalse(cv.isPrefetchingEnabled)
        cv.layoutIfNeeded()
        let cells = cv.visibleCells
        XCTAssertFalse(cells.isEmpty)
        // Ô vẽ ẢNH atlas (khi App Group đã có atlas — máy từng chạy app) hoặc CHỮ: cả hai đều
        // phải hiện đúng emoji. Trước đây test chỉ nhìn label ⇒ hỏng trên máy đã có atlas.
        for c in cells {
            guard let l = Self.find(UILabel.self, in: c) else { continue }
            XCTAssertFalse(l.adjustsFontSizeToFitWidth)
            let image = Self.find(UIImageView.self, in: c)
            let showsImage = image.map { !$0.isHidden && $0.image != nil } ?? false
            XCTAssertTrue(showsImage || !(l.text?.isEmpty ?? true), "ô emoji trống")
            XCTAssertFalse(c.accessibilityLabel?.isEmpty ?? true)
        }
        kb.debugSetPlane(numbers: false)
        XCTAssertEqual(kb.debugPlaneName, "letters")
        XCTAssertFalse(EmojiData.hasCachedCategories, "rời emoji phải nhả bảng category")
        // Mở lại vẫn đủ emoji
        kb.debugShowEmojiPlane(); r.vc.view.layoutIfNeeded()
        XCTAssertFalse(Self.find(UICollectionView.self, in: r.vc.view)!.visibleCells.isEmpty)
        kb.debugSetPlane(numbers: false)
        r.close()
    }

    // MARK: cảnh báo bộ nhớ

    @MainActor func testMemoryWarningDropsCaches() {
        let r = autoreleasepool { KeyboardBenchTests.Rig() }
        let kb = r.vc.debugKeyboard
        kb.debugCycleThroughNumbers()
        XCTAssertGreaterThan(kb.debugPlaneCacheCount, 0)
        _ = EmojiData.categories
        r.vc.didReceiveMemoryWarning()
        Wallpaper.queue.sync {}
        XCTAssertEqual(kb.debugPlaneCacheCount, 0)
        XCTAssertFalse(EmojiData.hasCachedCategories)
        XCTAssertFalse(Wallpaper.hasCache)
        // plane đang hiện vẫn nguyên, gõ tiếp được; sang số rồi về vẫn dựng lại đúng
        XCTAssertNotNil(kb.debugLetterFrame("a"))
        kb.debugCycleThroughNumbers()
        XCTAssertEqual(kb.debugPlaneName, "letters")
        XCTAssertNotNil(kb.debugLetterFrame("a"))
        r.close()
    }

    // MARK: cảnh báo bộ nhớ — cache thêm từ 10/2026 (RAM-AUDIT.md 10/11/2026)

    /// Nạp đủ các cache tĩnh: tệp theme (một mục), atlas Bạn đồng hành của 2 nhân vật, từ vựng vuốt cả 2 chế độ lọc.
    @MainActor private func fillLateCaches(themeDir: URL) -> ThemeAssetPlan {
        var plan = ThemeAssetPlan()
        plan.background = ThemeAssetRef(url: "https://example.invalid/bg.jpg", sha256: nil)
        XCTAssertNotNil(ThemeAssetLoader.load(plan, dir: themeDir))
        for c in [BuddyCharacter.cat, .chick] {
            BuddyView(character: c, bar: 0x222222, lowPower: true, artStyle: .sprite).halt()   // giải đồng bộ ⇒ vào cache
            XCTAssertTrue(BuddyView.atlasCached(c), "\(c)")
        }
        let saved = SwipeVocab.filterSensitive
        for f in [!saved, saved] { SwipeVocab.filterSensitive = f; _ = SwipeVocab.current }
        XCTAssertEqual(SwipeVocab.cachedModes, [true, false])
        return plan
    }

    #if DEBUG
    /// Ẩn: bỏ HẾT (tệp theme, mọi atlas Bạn đồng hành, cả hai từ vựng vuốt); dùng lại ⇒ nạp lại đúng.
    @MainActor func testMemoryWarningHiddenDropsLateCaches() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ramfix-theme-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir); ThemeAssetLoader.dropCache() }
        let plan = fillLateCaches(themeDir: dir)
        let active = SwipeVocab.filterSensitive
        let h0 = RamBreakdownTests.heapBytes(), f0 = KeyboardBenchTests.footprintMB()
        KeyboardViewController.purgeStaticCaches(visible: false, activeBuddy: .cat)   // ẩn: nhân vật bỏ qua
        KeySound.shared.debugDrain()
        print(String(format: "RAMFIX late-caches hidden purge: heap %+.2fMB footprint %+.2fMB",
                     Double(RamBreakdownTests.heapBytes() - h0) / 1_048_576, KeyboardBenchTests.footprintMB() - f0))
        XCTAssertFalse(BuddyView.atlasCached(.cat)); XCTAssertFalse(BuddyView.atlasCached(.chick))
        XCTAssertTrue(SwipeVocab.cachedModes.isEmpty)
        let loads = ThemeAssetLoader.loadCount
        XCTAssertNotNil(ThemeAssetLoader.load(plan, dir: dir))
        XCTAssertEqual(ThemeAssetLoader.loadCount, loads + 1, "tệp theme đã bỏ ⇒ giải lại")
        // Nạp lại lười, đúng.
        let v = BuddyView(character: .cat, bar: 0x222222, lowPower: true, artStyle: .sprite)
        XCTAssertTrue(v.atlasReady); XCTAssertTrue(BuddyView.atlasCached(.cat)); v.halt()
        let vocab = SwipeVocab.current
        XCTAssertEqual(vocab.filter, active)
        XCTAssertEqual(vocab.forms.count, SwipeVocab.build(filter: active, shortcuts: SwipeVocab.shortcuts).forms.count)
    }

    /// Đang hiện: GIỮ thứ đang trên màn (tệp theme đang dùng, atlas nhân vật đang hiện, từ vựng chế độ lọc đang dùng),
    /// chỉ bỏ phần không hiện (nhân vật khác, chế độ lọc kia).
    @MainActor func testMemoryWarningVisibleKeepsActiveAssets() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ramfix-theme-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir); ThemeAssetLoader.dropCache() }
        let plan = fillLateCaches(themeDir: dir)
        let active = SwipeVocab.filterSensitive
        let vocab = SwipeVocab.current
        KeyboardViewController.purgeStaticCaches(visible: true, activeBuddy: .cat)
        XCTAssertTrue(BuddyView.atlasCached(.cat), "nhân vật đang hiện giữ nguyên")
        XCTAssertFalse(BuddyView.atlasCached(.chick), "nhân vật khác bỏ")
        XCTAssertEqual(SwipeVocab.cachedModes, [active])
        XCTAssertTrue(SwipeVocab.current === vocab, "decoder đang giữ từ vựng này — không dựng lại")
        let loads = ThemeAssetLoader.loadCount
        XCTAssertNotNil(ThemeAssetLoader.load(plan, dir: dir))
        XCTAssertEqual(ThemeAssetLoader.loadCount, loads, "tệp theme đang dùng: không giải lại")
        // Bạn đồng hành ẩn (nil) khi bàn phím đang hiện ⇒ không còn nhân vật nào cần giữ.
        KeyboardViewController.purgeStaticCaches(visible: true, activeBuddy: nil)
        XCTAssertFalse(BuddyView.atlasCached(.cat))
    }

    /// Đường thật: controller trong cửa sổ (đang hiện) nhận cảnh báo ⇒ giữ tệp theme + từ vựng đang dùng; đóng (ẩn)
    /// rồi cảnh báo ⇒ bỏ hết.
    @MainActor func testMemoryWarningControllerVisibleVsHidden() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ramfix-theme-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir); ThemeAssetLoader.dropCache() }
        let r = autoreleasepool { KeyboardBenchTests.Rig() }
        let plan = fillLateCaches(themeDir: dir)
        let active = SwipeVocab.filterSensitive
        XCTAssertNotNil(r.vc.view.window)
        r.vc.didReceiveMemoryWarning()
        XCTAssertEqual(SwipeVocab.cachedModes, [active])
        let loads = ThemeAssetLoader.loadCount
        _ = ThemeAssetLoader.load(plan, dir: dir)
        XCTAssertEqual(ThemeAssetLoader.loadCount, loads)
        r.close()
        XCTAssertNil(r.vc.view.window)
        r.vc.didReceiveMemoryWarning()
        KeySound.shared.debugDrain()
        XCTAssertTrue(SwipeVocab.cachedModes.isEmpty)
        XCTAssertFalse(BuddyView.atlasCached(.cat)); XCTAssertFalse(BuddyView.atlasCached(.chick))
        _ = ThemeAssetLoader.load(plan, dir: dir)
        XCTAssertEqual(ThemeAssetLoader.loadCount, loads + 1)
    }
    #endif

    /// Người nhảy Night Club: ngoài cửa sổ ⇒ thả atlas; trong cửa sổ ⇒ giữ (đang hiện); gắn lại cửa sổ ⇒ giải lại.
    @MainActor func testNightDancerAtlasPurgeOnlyOffscreenAndReloads() throws {
        let v = SpotlightView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        v.layoutIfNeeded()
        v.setPhoto(nil)
        v.debugLoadAtlasNow(scale: 2)
        XCTAssertNotNil(v.debugAtlas)
        let win = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        win.isHidden = false
        win.addSubview(v)
        XCTAssertFalse(v.purgeAtlasIfOffscreen(), "đang hiện ⇒ giữ")
        XCTAssertNotNil(v.debugAtlas)
        XCTAssertTrue(v.debugDancerVisible)
        v.removeFromSuperview()
        XCTAssertTrue(v.purgeAtlasIfOffscreen())
        XCTAssertNil(v.debugAtlas)
        win.addSubview(v)
        let deadline = Date().addingTimeInterval(3)
        while v.debugAtlas == nil && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        XCTAssertNotNil(v.debugAtlas, "hiện lại ⇒ giải lại")
        XCTAssertTrue(v.debugDancerVisible)
        v.halt(); v.removeFromSuperview(); win.isHidden = true
    }

    // MARK: ảnh nền

    func testWallpaperDecodeScaleCapsAt2x() {
        XCTAssertEqual(Wallpaper.decodeScale(screenScale: 3), 2)
        XCTAssertEqual(Wallpaper.decodeScale(screenScale: 2), 2)
        XCTAssertEqual(Wallpaper.decodeScale(screenScale: 1), 1)
    }

    /// Ảnh dọc 810×1080 trên bàn phím iPhone 17 (402×290 @2x = 804×580): bitmap giữ lại đúng
    /// cỡ view (1,9 MB thay 3,5 MB), nội dung là phần GIỮA như aspect-fill của UIImageView.
    func testAspectFillCropKeepsVisibleCenter() {
        let src = Self.bands(width: 810, height: 1080)
        let view = CGSize(width: 402, height: 290)
        let scale = Wallpaper.decodeScale(screenScale: 3)
        let px = Wallpaper.displayMaxPixel(viewSize: view, scale: scale, imageAspect: 810.0 / 1080)
        XCTAssertLessThanOrEqual(px, Wallpaper.maxEdge)
        let out = Wallpaper.aspectFillCrop(src, to: CGSize(width: view.width * scale, height: view.height * scale))!
        XCTAssertEqual(out.width, 804)
        XCTAssertEqual(out.height, 580)
        XCTAssertLessThan(out.bytesPerRow * out.height, 2_000_000)
        // Ảnh gốc: dải trên đỏ / giữa xanh lá / dưới xanh dương — phần hiện phải là dải giữa.
        let c = Self.pixel(out, x: 402, y: 290)
        XCTAssertGreaterThan(c.g, 200); XCTAssertLessThan(c.r, 60); XCTAssertLessThan(c.b, 60)
        // Cùng cỡ ⇒ không vẽ lại
        XCTAssertNil(Wallpaper.aspectFillCrop(out, to: CGSize(width: 804, height: 580)))
    }

    /// Ảnh hẹp (497×1080, ảnh chụp màn hình dọc) trên view 804×580 px: không phóng to vào
    /// bitmap — cắt phần giữa ở độ phân giải gốc (497×359), cùng tỉ lệ view.
    func testAspectFillCropNeverUpscales() {
        let src = Self.bands(width: 497, height: 1080)
        let out = Wallpaper.aspectFillCrop(src, to: CGSize(width: 804, height: 580))!
        XCTAssertEqual(out.width, 497)
        XCTAssertEqual(out.height, 359)
        XCTAssertEqual(Double(out.width) / Double(out.height), 804.0 / 580, accuracy: 0.01)
        let c = Self.pixel(out, x: 248, y: 179)
        XCTAssertGreaterThan(c.g, 200); XCTAssertLessThan(c.r, 60)
    }

    // MARK: helpers

    static func find<T: UIView>(_ t: T.Type, in v: UIView) -> T? {
        if let x = v as? T { return x }
        for s in v.subviews { if let x = find(t, in: s) { return x } }
        return nil
    }

    /// Ba dải ngang: 0–40 % đỏ, 40–60 % xanh lá, 60–100 % xanh dương (toạ độ ảnh, gốc trên).
    static func bands(width: Int, height: Int) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        let h = CGFloat(height), w = CGFloat(width)
        // CGContext gốc dưới-trái: dải "trên" của ảnh nằm ở y cao.
        ctx.setFillColor(red: 0, green: 0, blue: 1, alpha: 1); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h * 0.4))
        ctx.setFillColor(red: 0, green: 1, blue: 0, alpha: 1); ctx.fill(CGRect(x: 0, y: h * 0.4, width: w, height: h * 0.2))
        ctx.setFillColor(red: 1, green: 0, blue: 0, alpha: 1); ctx.fill(CGRect(x: 0, y: h * 0.6, width: w, height: h * 0.4))
        return ctx.makeImage()!
    }

    static func pixel(_ img: CGImage, x: Int, y: Int) -> (r: Int, g: Int, b: Int) {
        var px = [UInt8](repeating: 0, count: 4)
        let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.draw(img, in: CGRect(x: -x, y: -(img.height - 1 - y), width: img.width, height: img.height))
        return (Int(px[0]), Int(px[1]), Int(px[2]))
    }
}
