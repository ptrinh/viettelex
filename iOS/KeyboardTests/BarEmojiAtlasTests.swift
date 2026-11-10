import XCTest
import UIKit

/// Emoji trên THANH GỢI Ý vẽ từ atlas (Keyboard/SuggestionEmojiTiles.swift, RAM-AUDIT.md §4d):
/// ảnh thay chữ khi atlas hợp lệ, rơi về chữ khi không có / thiếu emoji, kết quả nền cũ bị bỏ, ô không
/// đổi kích thước, bar không làm gì khi nội dung không đổi.
@MainActor
final class BarEmojiAtlasTests: XCTestCase {

    private var tmp: URL!
    private let w: CGFloat = 402

    override func setUp() {
        super.setUp()
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("bar-atlas-\(UUID().uuidString)")
        EmojiAtlasStore.release()
    }

    override func tearDown() {
        KeyboardView.barEmojiOpener = nil
        EmojiAtlasStore.release()
        try? FileManager.default.removeItem(at: tmp)
        super.tearDown()
    }

    private var phoneKey: EmojiAtlasManifest.Key {
        EmojiAtlas.expectedKey(scale: UIScreen.main.scale, pad: false)
    }

    final class Counter { var n = 0 }

    /// Atlas nhỏ trong thư mục tạm; bar mở bằng opener test (đếm số lần mở).
    private func useAtlas(_ emojis: [String], opens: Counter? = nil) throws {
        try EmojiAtlasBuilder.build(groups: [("smileys", emojis)], root: tmp, key: phoneKey)
        let root = tmp!, key = phoneKey
        KeyboardView.barEmojiOpener = {
            opens?.n += 1
            return EmojiAtlasStore(root: root, expected: key)
        }
    }

    private func makeKeyboard() -> (KeyboardView, UIView) {
        let kb = KeyboardView(needsGlobe: false, inputController: nil, onKey: { _ in })
        let host = UIView(frame: CGRect(x: 0, y: 0, width: w, height: 320))
        host.addSubview(kb)
        kb.frame = host.bounds
        kb.setSuggestionsEnabled(true)
        kb.setNeedsLayout(); kb.layoutIfNeeded()
        return (kb, host)
    }

    private func drain(_ kb: KeyboardView) { kb.debugBarEmojiTiles?.debugDrain() }

    private func set(_ emojis: [String], word: String = "đường") -> KeyboardView.SuggestionSet {
        .init(literal: "đ", word: word, emojis: emojis)
    }

    // MARK: ảnh thay chữ

    func testBarEmojiUsesAtlasImageNotTitle() throws {
        try useAtlas(["🛣️", "🚗", "😀"])
        let (kb, _) = makeKeyboard()
        kb.showSuggestions(set(["🛣️", "🚗"]))
        // Nhịp đầu: đang giải mã ⇒ ô TRỐNG (không chữ, không ảnh sai).
        for c in kb.debugBarEmojiCells() { XCTAssertNil(c.title); XCTAssertNil(c.image) }
        drain(kb)
        let cells = kb.debugBarEmojiCells()
        XCTAssertEqual(cells.count, 2)
        for c in cells {
            XCTAssertNotNil(c.image, "atlas hợp lệ ⇒ ảnh")
            XCTAssertNil(c.title, "không vẽ chữ emoji (không nạp font Apple Color Emoji)")
        }
        // Ảnh đúng cỡ bar (glyph 20 pt), không phải ô atlas 34 pt.
        let img = try XCTUnwrap(cells[0].image)
        XCTAssertEqual(img.size.width, 20, accuracy: 0.5)
        XCTAssertEqual(img.scale, UIScreen.main.scale)
        // Hai emoji khác nhau ⇒ hai ảnh khác nhau (không lệch ô).
        XCTAssertNotEqual(cells[0].image?.pngData(), cells[1].image?.pngData())
        // Trúng cache: hiện lại emoji đã có ⇒ ảnh NGAY, không việc nền mới.
        let jobs = kb.debugBarEmojiTiles?.debugJobs ?? -1
        kb.showSuggestions(set(["😀"], word: "a"))
        drain(kb)
        kb.showSuggestions(set(["🚗", "🛣️"], word: "b"))
        XCTAssertTrue(kb.debugBarEmojiCells().allSatisfy { $0.image != nil && $0.title == nil })
        XCTAssertEqual(kb.debugBarEmojiTiles?.debugJobs, jobs + 1, "chỉ 😀 cần giải mã")
        XCTAssertLessThanOrEqual(kb.debugBarEmojiTiles?.cachedTileCount ?? 99, SuggestionEmojiTiles.capacity)
    }

    func testFallsBackToTextWithoutAtlasOrMissingEmoji() throws {
        try useAtlas(["😀"])
        let (kb, _) = makeKeyboard()
        kb.showSuggestions(set(["😀", "🦖"]))
        drain(kb)
        let cells = kb.debugBarEmojiCells()
        XCTAssertNotNil(cells[0].image)
        XCTAssertNil(cells[1].image)
        XCTAssertEqual(cells[1].title, "🦖", "không có trong atlas ⇒ chữ")

        // Không atlas (chưa mở app lần nào / manifest cũ) ⇒ chữ như trước.
        let none = tmp.appendingPathComponent("none"), key = phoneKey
        KeyboardView.barEmojiOpener = { EmojiAtlasStore(root: none, expected: key) }
        let (kb2, _) = makeKeyboard()
        kb2.showSuggestions(set(["😀", "🚗"]))
        drain(kb2)
        XCTAssertEqual(kb2.debugBarEmojiCells().map(\.title), ["😀", "🚗"])
        XCTAssertTrue(kb2.debugBarEmojiCells().allSatisfy { $0.image == nil })
        // Đã biết không atlas ⇒ emoji sau vẽ chữ NGAY (không nhịp trống).
        kb2.showSuggestions(set(["🚕"], word: "x"))
        XCTAssertEqual(kb2.debugBarEmojiCells().map(\.title), ["🚕"])
    }

    // MARK: kết quả nền cũ

    func testStaleTileNeverShowsWrongEmoji() throws {
        try useAtlas(["😀", "🚗", "🐶"])
        let (kb, _) = makeKeyboard()
        kb.showSuggestions(set(["😀"]))
        // Đổi emoji TRƯỚC khi ảnh 😀 về: ô phải chờ 🚗, không bao giờ hiện 😀.
        kb.showSuggestions(set(["🚗"], word: "x"))
        drain(kb)
        let img = try XCTUnwrap(kb.debugBarEmojiCells().first?.image)
        let tiles = try XCTUnwrap(kb.debugBarEmojiTiles)
        guard case .image(let car) = tiles.lookup("🚗"), case .image(let smile) = tiles.lookup("😀") else {
            return XCTFail("cả hai đã vào LRU")
        }
        XCTAssertTrue(img === car)
        XCTAssertFalse(img === smile)

        // reset (ẩn bàn phím / thiếu RAM) trong lúc đang giải mã ⇒ kết quả đó bị bỏ.
        kb.showSuggestions(set(["🐶"], word: "y"))
        tiles.reset()
        drain(kb)
        XCTAssertGreaterThanOrEqual(tiles.debugDroppedStale, 1)
        XCTAssertNil(kb.debugBarEmojiCells().first?.image, "kết quả cũ không được áp")
        XCTAssertEqual(tiles.cachedTileCount, 0)
    }

    func testTileLRUIsBounded() throws {
        let many = ["😀", "😃", "😄", "😁", "😆", "😅", "😂", "🤣", "🥲", "😊", "😇", "🙂", "🙃", "😉", "😌", "😍"]
        try useAtlas(many)
        let (kb, _) = makeKeyboard()
        for (i, e) in many.enumerated() {
            kb.showSuggestions(set([e], word: "w\(i)"))
            drain(kb)
            XCTAssertNotNil(kb.debugBarEmojiCells().first?.image, e)
        }
        XCTAssertEqual(kb.debugBarEmojiTiles?.cachedTileCount, SuggestionEmojiTiles.capacity)
        // Emoji cũ nhất bị đẩy ra ⇒ hỏi lại thì phải giải mã (pending), mới nhất vẫn trúng.
        XCTAssertEqual(kb.debugBarEmojiTiles?.lookup(many.last!).isImage, true)
        XCTAssertEqual(kb.debugBarEmojiTiles?.lookup(many[0]), .pending)
    }

    // MARK: ô không đổi, bar không làm gì khi nội dung không đổi

    func testSlotGeometryStableAndNoWorkWhenUnchanged() throws {
        let opens = Counter()
        try useAtlas(["🛣️", "🚗"], opens: opens)
        let (kb, _) = makeKeyboard()
        kb.showSuggestions(set(["🛣️", "🚗"]))
        let before = kb.debugSuggestionGeometry().cells
        drain(kb)
        let g = kb.debugSuggestionGeometry()
        XCTAssertEqual(g.cells, before, "ảnh về không đổi khung ô")
        // Khung ảnh nằm trong ô cuối (theo chiều ngang), cỡ glyph, căn giữa theo chiều dọc.
        let last = try XCTUnwrap(g.cells.last)
        let imgs = g.visibleTitles.filter { $0.midX > last.minX && $0.midX < last.maxX }
        XCTAssertEqual(imgs.count, 2)
        for r in imgs {
            XCTAssertEqual(r.width, 20, accuracy: 0.5); XCTAssertEqual(r.height, 20, accuracy: 0.5)
            XCTAssertEqual(r.midY, last.midY, accuracy: 0.5)
        }
        // Cùng nội dung ⇒ bar không đụng gì (không lookup, không việc nền).
        let jobs = kb.debugBarEmojiTiles?.debugJobs
        kb.showSuggestions(set(["🛣️", "🚗"]))
        XCTAssertEqual(kb.debugBarEmojiTiles?.debugJobs, jobs)
        XCTAssertEqual(opens.n, 1, "atlas mở một lần mỗi KeyboardView")
    }

    /// Tắt gợi ý emoji / không emoji nào ⇒ không tạo bộ ô, không mở atlas.
    func testNoEmojiNoAtlasWork() throws {
        let opens = Counter()
        try useAtlas(["😀"], opens: opens)
        let (kb, _) = makeKeyboard()
        kb.showSuggestions(.init(nextWords: ["Đáp", "Được", "Đi"]))
        kb.showSuggestions(.init(literal: "xin", word: "xin", word2: "xinh"))
        XCTAssertNil(kb.debugBarEmojiTiles)
        Thread.sleep(forTimeInterval: 0.05)
        XCTAssertEqual(opens.n, 0)
    }

    // MARK: đo (bộ chậm) — mỗi biến thể một process (font / cache glyph CoreText không xả được):
    //   TEST_RUNNER_VT_SLOW_TESTS=1 xcodebuild … -only-testing:VietTelexKeyboardTests/BarEmojiAtlasTests/testBarMemoryText test
    //   TEST_RUNNER_VT_SLOW_TESTS=1 xcodebuild … -only-testing:VietTelexKeyboardTests/BarEmojiAtlasTests/testBarMemoryAtlas test

    func testBarMemoryText() throws { try barMemory(atlas: false) }
    func testBarMemoryAtlas() throws { try barMemory(atlas: true) }

    /// Bàn phím thật trong cửa sổ, 30 lượt gợi ý × 3 emoji KHÁC nhau (90 emoji) trên thanh gợi ý:
    /// phys_footprint trước / sau / đỉnh. Biến thể atlas dựng atlas trong process TRƯỚC f0 (dựng nạp
    /// font + cache glyph — thành nền, như bàn phím thật không phải tự dựng).
    private func barMemory(atlas: Bool) throws {
        try SlowTests.require()
        let ids = EmojiData.categories.first { $0.name == "smileys" }!.ids.prefix(90)
        let list = ids.map { EmojiData.emoji(Int($0)) }
        XCTAssertEqual(list.count, 90)
        if atlas {
            try useAtlas(list)
        } else {
            let none = tmp.appendingPathComponent("none"), key = phoneKey
            KeyboardView.barEmojiOpener = { EmojiAtlasStore(root: none, expected: key) }
        }
        EmojiData.dropCaches()
        let win = UIWindow(frame: CGRect(x: 0, y: 0, width: w, height: 874))
        win.isHidden = false
        let kb = KeyboardView(needsGlobe: false, inputController: nil, onKey: { _ in })
        kb.frame = CGRect(x: 0, y: 874 - 320, width: w, height: 320)
        win.addSubview(kb)
        kb.setSuggestionsEnabled(true)
        kb.showSuggestions(.init(literal: "a", word: "anh", word2: "ánh"))
        kb.layoutIfNeeded()
        RamBreakdownTests.spin(0.5)
        let f0 = KeyboardBenchTests.footprintMB()
        var peak = f0
        let t0 = Date()
        for k in 0..<30 {
            kb.showSuggestions(set(Array(list[(k * 3)..<(k * 3 + 3)]), word: "w\(k)"))
            kb.debugBarEmojiTiles?.debugDrain()
            kb.layoutIfNeeded()
            RamBreakdownTests.spin(0.03)      // CA vẽ chữ / ảnh
            peak = max(peak, KeyboardBenchTests.footprintMB())
        }
        let ms = Date().timeIntervalSince(t0) * 1000
        RamBreakdownTests.spin(0.5)
        let f1 = KeyboardBenchTests.footprintMB()
        let cells = kb.debugBarEmojiCells()
        XCTAssertEqual(cells.allSatisfy { $0.image != nil }, atlas)
        print(String(format: "BAREMOJI %@: 90 emoji trên thanh gợi ý %+.2f MB (đỉnh %+.2f) | ô LRU %d | %.0f ms",
                     atlas ? "atlas" : "text", f1 - f0, peak - f0, kb.debugBarEmojiTiles?.cachedTileCount ?? 0, ms))
        kb.removeFromSuperview()
        win.isHidden = true
    }

    /// tearDown / cảnh báo bộ nhớ nhả LRU.
    func testReleaseOnTearDownAndMemoryWarning() throws {
        try useAtlas(["😀"])
        let (kb, _) = makeKeyboard()
        kb.showSuggestions(set(["😀"]))
        drain(kb)
        XCTAssertEqual(kb.debugBarEmojiTiles?.cachedTileCount, 1)
        kb.dropCaches()
        XCTAssertEqual(kb.debugBarEmojiTiles?.cachedTileCount, 0)
        XCTAssertNotNil(kb.debugBarEmojiCells().first?.image, "ô đang hiện giữ ảnh của nó")
        kb.tearDown()
        XCTAssertNil(kb.debugBarEmojiTiles)
    }
}

private extension SuggestionEmojiTiles.Lookup {
    var isImage: Bool { if case .image = self { return true }; return false }
}
