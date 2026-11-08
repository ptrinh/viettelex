// Theme "Pixel 8-bit": dáng phím điểm ảnh ("keyShape":"pixel" — hình học CHUNG Android qua
// Fixtures/pixel-key-cases.txt), ảnh 9-slice tí hon, phông điểm ảnh NHÚNG (KeyLabelFont.pixel — đủ mọi chữ Việt),
// bàn phím thật (skin điểm ảnh chỉ khi theme dùng, đè = lún 1 khối + nhãn dời theo) + ảnh chụp cho chủ repo xem.
import XCTest
import CoreText

final class PixelKeysTests: XCTestCase {
    private var savedDefaults: UserDefaults?
    private var savedPlus: UserDefaults!
    private var savedPaywall = false
    private var suite = ""
    private var plusSuite = ""

    override func setUp() {
        super.setUp()
        ThemeAssetLoader.dropCache()
        savedDefaults = UserDefaultsProvider.shared
        suite = "pixelkeys-\(UUID().uuidString)"
        UserDefaultsProvider.shared = UserDefaults(suiteName: suite)
        savedPlus = PlusGate.defaults
        savedPaywall = PlusGate.paywallEnabled
        plusSuite = "pixelkeys-plus-\(UUID().uuidString)"
        PlusGate.defaults = UserDefaults(suiteName: plusSuite)!
        PlusGate.paywallEnabled = false
    }

    override func tearDown() {
        UserDefaultsProvider.shared?.removePersistentDomain(forName: suite)
        UserDefaultsProvider.shared = savedDefaults
        PlusGate.defaults.removePersistentDomain(forName: plusSuite)
        PlusGate.defaults = savedPlus
        PlusGate.paywallEnabled = savedPaywall
        super.tearDown()
    }

    // MARK: hình học chung Android

    private static func rects(_ s: String) -> [PixelKeys.Rect] {
        s == "-" ? [] : s.split(separator: ";").map {
            let v = $0.split(separator: ",").map { Double($0)! }
            return PixelKeys.Rect(l: v[0], t: v[1], r: v[2], b: v[3])
        }
    }
    private func assertRects(_ a: [PixelKeys.Rect], _ b: [PixelKeys.Rect], _ msg: String) {
        XCTAssertEqual(a.count, b.count, msg)
        for (x, y) in zip(a, b) {
            for (p, q) in [(x.l, y.l), (x.t, y.t), (x.r, y.r), (x.b, y.b)] { XCTAssertEqual(p, q, accuracy: 1e-6, msg) }
        }
    }

    func testSharedGeometryWithAndroid() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "pixel-key-cases", withExtension: "txt"))
        var n = 0
        for line in try String(contentsOf: url, encoding: .utf8).split(separator: "\n") where !line.hasPrefix("#") {
            let c = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            switch c[0] {
            case "KEY":
                let f = c[1].split(separator: " ").map { Double($0)! }
                let ly = PixelKeys.layers(l: f[0], t: f[1], r: f[2], b: f[3], block: Double(c[2])!, pressed: c[3] == "1")
                assertRects(ly.ink, Self.rects(c[4]), line + " viền+bóng")
                assertRects(ly.fill, Self.rects(c[5]), line + " lõi")
            case "BLOCK":
                XCTAssertEqual(PixelKeys.block(keyHeight: Double(c[1])!), Double(c[2])!, accuracy: 1e-4, String(line))
            case "SHIFT":
                XCTAssertEqual(PixelKeys.labelShift(block: Double(c[1])!, pressed: c[2] == "1"), Double(c[3])!, accuracy: 1e-6)
            default: XCTFail("dòng lạ: \(line)")
            }
            n += 1
        }
        XCTAssertGreaterThanOrEqual(n, 16)
    }

    // MARK: ảnh 9-slice

    private static func pixel(_ img: CGImage, _ x: Int, _ y: Int) -> UInt32 {
        var px: UInt32 = 0
        let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
        ctx.interpolationQuality = .none
        ctx.draw(img, in: CGRect(x: -x, y: y - img.height + 1, width: img.width, height: img.height))
        return UInt32(bigEndian: px)   // byte R G B A ⇒ 0xRRGGBBAA
    }

    func testImagesAreCrispBlocks() throws {
        let c = PixelKeys.Colors(fill: RGBA(r: 1, g: 1, b: 1), outline: RGBA(r: 0, g: 0, b: 0))
        let n = try XCTUnwrap(PixelKeys.image(c, pressed: false))
        let p = try XCTUnwrap(PixelKeys.image(c, pressed: true))
        XCTAssertEqual([n.width, n.height, p.width, p.height], [16, 16, 16, 16])
        let clear: UInt32 = 0, black: UInt32 = 0x0000_00FF, white: UInt32 = 0xFFFF_FFFF
        // Thường: góc cắt bậc (trong suốt), viền trên, lõi, bóng dưới/phải; KHÔNG có điểm ảnh pha trộn.
        XCTAssertEqual(Self.pixel(n, 0, 0), clear)
        XCTAssertEqual(Self.pixel(n, 1, 0), clear)
        XCTAssertEqual(Self.pixel(n, 2, 0), black)
        XCTAssertEqual(Self.pixel(n, 1, 1), black)
        XCTAssertEqual(Self.pixel(n, 6, 6), white)
        XCTAssertEqual(Self.pixel(n, 6, 15), black, "bóng dưới")
        XCTAssertEqual(Self.pixel(n, 15, 6), black, "bóng phải")
        XCTAssertEqual(Self.pixel(n, 15, 15), clear)
        // Lún: mặt dời 1 khối xuống-phải, không bóng ⇒ hàng/cột 0 trống.
        for i in 0..<16 { XCTAssertEqual(Self.pixel(p, i, 0), clear); XCTAssertEqual(Self.pixel(p, 0, i), clear) }
        XCTAssertEqual(Self.pixel(p, 3, 1), black)
        XCTAssertEqual(Self.pixel(p, 7, 7), white)
        for y in 0..<16 { for x in 0..<16 {
            XCTAssertTrue([clear, black, white].contains(Self.pixel(n, x, y)), "(\(x),\(y)) pha trộn")
        } }
        // Cùng màu ⇒ cùng ảnh (cache, dùng chung mọi phím cùng vai).
        XCTAssertTrue(PixelKeys.skin(c)?.normal === PixelKeys.skin(c)?.normal)
        XCTAssertEqual(PixelKeys.skin(c)?.insets, PixelKeys.slice)
        XCTAssertEqual(PixelKeys.skin(c)?.pixelated, true)
    }

    // MARK: phông điểm ảnh nhúng

    /// Mọi chữ cái tiếng Việt (a–z, ă â đ ê ô ơ ư; nguyên âm × 5 thanh; hoa + thường) có glyph trong phông nhúng —
    /// popup ký tự phụ / gợi ý không bao giờ rơi về phông khác giữa chừng.
    static var vietnameseLetters: [String] {
        let vowels = ["a", "ă", "â", "e", "ê", "i", "o", "ô", "ơ", "u", "ư", "y"]
        let tones = ["", "\u{301}", "\u{300}", "\u{309}", "\u{303}", "\u{323}"]
        var out = (UInt8(ascii: "a")...UInt8(ascii: "z")).map { String(UnicodeScalar($0)) } + ["đ"]
        for v in vowels { for t in tones { out.append((v + t).precomposedStringWithCanonicalMapping) } }
        return Array(Set(out + out.map { $0.uppercased() })).sorted()
    }

    func testPixelFontCoversVietnamese() throws {
        let d = try XCTUnwrap(PixelFont.descriptor, "Tiny5-Regular.ttf phải có trong bundle")
        let font = CTFontCreateWithFontDescriptor(d, 24, nil)
        XCTAssertEqual(CTFontCopyFamilyName(font) as String, "Tiny5")
        let letters = Self.vietnameseLetters
        XCTAssertEqual(letters.count, 2 * (26 + 1 + 12 * 6 - 6), "a–z + đ + 12 nguyên âm × 6 thanh (a e i o u y không dấu đã đếm)")
        for s in letters {
            let u = Array(s.utf16)
            XCTAssertEqual(u.count, 1, "\(s) phải là một ký tự dựng sẵn")
            var g = [CGGlyph](repeating: 0, count: u.count)
            XCTAssertTrue(CTFontGetGlyphsForCharacters(font, u, &g, u.count), "thiếu glyph \(s)")
            XCTAssertNotEqual(g[0], 0, s)
        }
        // Tệp nhỏ (nạp lười trong extension ~50–70 MB).
        let size = try XCTUnwrap(PixelFont.url.flatMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize })
        XCTAssertLessThan(size, 60 * 1024)
        // KeyLabelFont "pixel" ⇒ đúng phông này (bỏ qua độ đậm).
        let ui = KeyLabelFonts.make(.pixel, .heavy, size: 20, compact: nil)
        XCTAssertEqual(ui.familyName, "Tiny5")
        XCTAssertEqual(ui.pointSize, 20)
    }

    // MARK: bàn phím thật

    @MainActor private func makeKB(_ t: KeyboardTheme) -> KeyboardView {
        var s = ThemeSettings(theme: t)
        s.save(UserDefaultsProvider.shared)
        let kb = KeyboardView(needsGlobe: false, inputController: nil) { _ in }
        kb.frame = CGRect(x: 0, y: 0, width: 430, height: 300)
        kb.applyAppearance(.light, style: .light)
        kb.layoutIfNeeded()
        return kb
    }

    @MainActor func testPixelThemeOnRealKeyboard() throws {
        let kb = makeKB(.pixel)
        let a = try XCTUnwrap(kb.debugThemeAssets, "theme Pixel ⇒ skin điểm ảnh")
        XCTAssertTrue(a.skins.values.allSatisfy(\.pixelated))
        XCTAssertLessThan(a.skinBytes, 16 * 1024, "vài ảnh 16×16")
        XCTAssertEqual(KeyboardView.labelFonts.font, .pixel)
        let keys = kb.debugAllKeyButtons()
        let o = try XCTUnwrap(keys.first { $0.currentTitle == "o" || $0.currentTitle == "O" })
        let sl = try XCTUnwrap(kb.debugSkinLayer(o))
        XCTAssertEqual(sl.magnificationFilter, .nearest)
        XCTAssertEqual(o.titleLabel?.font.familyName, "Tiny5")
        // Đè: đổi con trỏ ảnh (lún) + nhãn dời đúng 1 khối xuống-phải, không lượt layout; nhả: về chỗ cũ.
        let normal = sl.contents as AnyObject?
        let c0 = try XCTUnwrap(o.titleLabel?.center)
        let k = o.bounds.height / CGFloat(PixelKeys.cells)
        o.showPressed(true)
        XCTAssertFalse((sl.contents as AnyObject?) === normal)
        let c1 = try XCTUnwrap(o.titleLabel?.center)
        XCTAssertEqual(c1.x - c0.x, k, accuracy: 0.01); XCTAssertEqual(c1.y - c0.y, k, accuracy: 0.01)
        o.layoutIfNeeded()   // layout giữa chừng không làm mất độ dời
        XCTAssertEqual(o.titleLabel!.center.y - c0.y, k, accuracy: 0.6)
        o.showPressed(false)
        XCTAssertTrue((sl.contents as AnyObject?) === normal)
        XCTAssertEqual(o.titleLabel!.center.y, c0.y, accuracy: 0.6)
        // ⇧ đang bật lúc dựng (đầu câu): lún + glyph màu chức năng đọc được (không đen như shiftOnInk).
        if let sh = keys.first(where: { $0.accessibilityLabel == "Shift" }), kb.debugSkinLayer(sh) != nil {
            XCTAssertEqual(sh.tintColor, kb.debugPalette.fnInk.ui)
        }
        // Theme khác: không skin, không phông điểm ảnh (0 chi phí).
        let mint = makeKB(.mint)
        XCTAssertNil(mint.debugThemeAssets)
        XCTAssertNotEqual(KeyboardView.labelFonts.font, .pixel)
        XCTAssertTrue(mint.debugAllKeyButtons().allSatisfy { mint.debugSkinLayer($0) == nil })
    }

    /// Ảnh chụp bàn phím theme Pixel (sáng + tối) cho chủ repo xem: /Users/ptrinh/Downloads/Temp/pixel-theme-ios.png
    /// (chỉ ghi khi thư mục tồn tại — máy dev; CI bỏ qua).
    @MainActor func testSnapshotForOwner() throws {
        let dir = URL(fileURLWithPath: "/Users/ptrinh/Downloads/Temp")
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else {
            throw XCTSkip("không có thư mục ảnh tạm")
        }
        var shots: [UIImage] = []
        for style in [UIUserInterfaceStyle.light, .dark] {
            var s = ThemeSettings(theme: .pixel)
            s.save(UserDefaultsProvider.shared)
            let kb = KeyboardView(needsGlobe: false, inputController: nil) { _ in }
            kb.frame = CGRect(x: 0, y: 0, width: 402, height: 320)
            kb.applyAppearance(style == .dark ? .dark : .light, style: style)
            kb.layoutIfNeeded()
            // Một phím đang đè (lún) để thấy trạng thái bấm.
            kb.debugAllKeyButtons().first { $0.currentTitle == "g" || $0.currentTitle == "G" }?.showPressed(true)
            let r = UIGraphicsImageRenderer(bounds: kb.bounds, format: { let f = UIGraphicsImageRendererFormat(); f.scale = 3; return f }())
            shots.append(r.image { ctx in kb.layer.render(in: ctx.cgContext) })
        }
        let w = shots[0].size.width, h = shots.map(\.size.height).reduce(0, +)
        let out = UIGraphicsImageRenderer(size: CGSize(width: w, height: h + 8),
                                          format: { let f = UIGraphicsImageRendererFormat(); f.scale = 3; return f }()).image { _ in
            var y: CGFloat = 0
            for s in shots { s.draw(at: CGPoint(x: 0, y: y)); y += s.size.height + 8 }
        }
        try XCTUnwrap(out.pngData()).write(to: dir.appendingPathComponent("pixel-theme-ios.png"))
    }
}
