// "Giao diện JSON" — tệp tải về (phông / ảnh nền / tiền cảnh / skin phím): toán 9-slice, thứ tự giải skin,
// kho + dọn, đường tải (transport giả + URLProtocol giả: cỡ, loại, sha, chuyển hướng http, hết giờ, 404,
// mất mạng), thu nhỏ ảnh, phông (CoreText + cảnh báo thiếu tiếng Việt), câu hỏi trước khi tải, dự phòng, bàn
// phím thật với theme NẶNG (nền + tiền cảnh + 14 skin + phông — đo RAM), 0 chi phí khi theme không có tệp.
// Schema + kế hoạch dùng chung Android nằm ở ThemeJSONTests (fixture theme-json-cases.txt, dòng CASE / PLAN).
import XCTest
import ImageIO
import CoreText
import UniformTypeIdentifiers

final class ThemeAssetTests: XCTestCase {
    private var tmp: URL!
    private var savedDefaults: UserDefaults?
    private var savedPlus: UserDefaults!
    private var savedPaywall = false
    private var suite = ""
    private var plusSuite = ""

    override func setUp() {
        super.setUp()
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("themeassets-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        ThemeAssetStore.dirOverride = tmp
        ThemeAssetLoader.dropCache()
        savedDefaults = UserDefaultsProvider.shared
        suite = "themeassets-\(UUID().uuidString)"
        UserDefaultsProvider.shared = UserDefaults(suiteName: suite)
        savedPlus = PlusGate.defaults
        savedPaywall = PlusGate.paywallEnabled
        plusSuite = "themeassets-plus-\(UUID().uuidString)"
        PlusGate.defaults = UserDefaults(suiteName: plusSuite)!
        PlusGate.paywallEnabled = false
    }

    override func tearDown() {
        ThemeAssetStore.dirOverride = nil
        ThemeAssetLoader.dropCache()
        try? FileManager.default.removeItem(at: tmp)
        UserDefaultsProvider.shared?.removePersistentDomain(forName: suite)
        UserDefaultsProvider.shared = savedDefaults
        PlusGate.defaults.removePersistentDomain(forName: plusSuite)
        PlusGate.defaults = savedPlus
        PlusGate.paywallEnabled = savedPaywall
        super.tearDown()
    }

    private static var repo: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    // MARK: ảnh mẫu

    static func png(_ w: Int, _ h: Int, alpha: Bool, color: UIColor = .systemTeal, inset: CGFloat = 4) -> Data {
        let f = UIGraphicsImageRendererFormat()
        f.scale = 1
        f.opaque = !alpha
        return UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: f).pngData { c in
            if !alpha { UIColor.white.setFill(); c.fill(CGRect(x: 0, y: 0, width: w, height: h)) }
            color.setFill()
            UIBezierPath(roundedRect: CGRect(x: inset, y: inset, width: CGFloat(w) - 2 * inset, height: CGFloat(h) - 2 * inset),
                         cornerRadius: 20).fill()
        }
    }

    /// JPEG có GPS + EXIF (kiểm lưu lại không còn metadata).
    static func jpegWithGPS(_ w: Int, _ h: Int) -> Data {
        let img = UIImage(data: png(w, h, alpha: false))!.cgImage!
        let d = NSMutableData()
        let dst = CGImageDestinationCreateWithData(d, UTType.jpeg.identifier as CFString, 1, nil)!
        let props: [CFString: Any] = [kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 21.0, kCGImagePropertyGPSLongitude: 105.8],
                                      kCGImagePropertyExifDictionary: [kCGImagePropertyExifUserComment: "secret"]]
        CGImageDestinationAddImage(dst, img, props as CFDictionary)
        CGImageDestinationFinalize(dst)
        return d as Data
    }

    struct FakeTransport: ThemeAssetTransport {
        var files: [String: Result<Data, Error>]
        func get(_ url: URL, maxBytes: Int) async throws -> Data {
            guard let r = files[url.absoluteString] else { throw ThemeAssetError.httpStatus }
            let d = try r.get()
            if d.count > maxBytes { throw ThemeAssetError.tooLarge }
            return d
        }
    }

    private func file(_ cls: ThemeAssetClass, _ url: String, sha: String? = nil) -> ThemeAssetFile {
        ThemeAssetFile(cls: cls, ref: ThemeAssetRef(url: url, sha256: sha))
    }

    // MARK: 9-slice (Android cùng số)

    func testNineSliceMath() {
        XCTAssertEqual(NineSlice.scale([30, 30, 34, 30], fromW: 120, fromH: 140, toW: 60, toH: 70), [15, 15, 17, 15])
        // Góc lớn hơn ảnh ⇒ thu cả hai, phần giữa còn ≥ 1 px.
        XCTAssertEqual(NineSlice.scale([100, 0, 100, 0], fromW: 100, fromH: 150, toW: 100, toH: 150), [74, 0, 74, 0])
        XCTAssertEqual(NineSlice.scale([1, 2, 3], fromW: 1, fromH: 1, toW: 1, toH: 1), [0, 0, 0, 0])
        // Đích: ảnh gốc cao 140 px phủ phím cao 46 ⇒ ×46/140.
        let d = NineSlice.destInsets([30, 30, 34, 30], srcH: 140, width: 40, height: 46)
        for (a, b) in zip(d, [30, 30, 34, 30].map { Double($0) * 46 / 140 }) { XCTAssertEqual(a, b, accuracy: 1e-9) }
        XCTAssertEqual(NineSlice.shrink([30, 30, 34, 30], srcH: 140, width: 40, height: 46), 1)
        // Phím hẹp hơn hai góc ⇒ thu đều cả bốn: 60 px × 46/140 = 19,71 > 30/2 ⇒ còn 15.
        let s = NineSlice.destInsets([60, 60, 60, 60], srcH: 140, width: 30, height: 46)
        for v in s { XCTAssertEqual(v, 15, accuracy: 1e-9) }
        XCTAssertEqual(NineSlice.shrink([60, 60, 60, 60], srcH: 140, width: 30, height: 46), 30.0 / (120.0 * 46 / 140), accuracy: 1e-9)
        // 9 mảnh phủ kín đích, không chồng.
        let p = NineSlice.patches(imageW: 120, imageH: 140, insets: [30, 30, 34, 30], width: 200, height: 46, dest: d)
        XCTAssertEqual(p.count, 9)
        XCTAssertEqual(p.reduce(0) { $0 + $1.dst.width * $1.dst.height }, 200 * 46, accuracy: 1e-6)
        XCTAssertEqual(p.reduce(0) { $0 + $1.src.width * $1.src.height }, 120 * 140, accuracy: 1e-6)
        XCTAssertEqual(p[0].src, CGRect(x: 0, y: 0, width: 30, height: 30))
        XCTAssertEqual(p[4].src, CGRect(x: 30, y: 30, width: 60, height: 76))
        XCTAssertEqual(NineSlice.contentsCenter([30, 30, 34, 30], w: 120, h: 140),
                       CGRect(x: 0.25, y: 30.0 / 140, width: 0.5, height: 76.0 / 140))
        // Không slice ⇒ một mảnh (cả ảnh căng).
        XCTAssertEqual(NineSlice.patches(imageW: 10, imageH: 10, insets: [0, 0, 0, 0], width: 50, height: 40,
                                         dest: [0, 0, 0, 0]).count, 1)
    }

    // MARK: thứ tự giải skin: từng phím → nhóm → màu theme

    func testResolutionOrder() {
        var a = ThemeAssetSpec()
        let k = { (u: String) in ThemeKeySkin(image: ThemeAssetRef(url: "https://e.com/\(u).png")) }
        a.keys = ["default": k("d"), "special": k("s"), "space": k("sp"), "a": k("a")]
        let p = ThemeAssetPlan.make(a)
        XCTAssertEqual(p.skin("a")?.image.url, "https://e.com/a.png", "từng phím thắng nhóm")
        XCTAssertEqual(p.skin("b")?.image.url, "https://e.com/d.png", "chữ ⇒ default")
        XCTAssertEqual(p.skin("space")?.image.url, "https://e.com/sp.png")
        XCTAssertEqual(p.skin("return")?.image.url, "https://e.com/s.png", "phím đặt tên ⇒ special")
        XCTAssertEqual(p.skin("shift")?.image.url, "https://e.com/s.png")
        // Không nhóm ⇒ màu theme.
        a.keys = ["a": k("a")]
        let q = ThemeAssetPlan.make(a)
        XCTAssertNil(q.skin("b")); XCTAssertNil(q.skin("return")); XCTAssertNil(q.skin("default"))
        XCTAssertEqual(q.files.count, 1)
        XCTAssertTrue(ThemeAssetPlan.make(ThemeAssetSpec()).isEmpty)
        // Ảnh nền theme: ảnh nền tự đặt của người dùng thắng.
        XCTAssertTrue(ThemeAssetPlan.showsThemeBackground(userWallpaperActive: false, themeBackgroundReady: true))
        XCTAssertFalse(ThemeAssetPlan.showsThemeBackground(userWallpaperActive: true, themeBackgroundReady: true))
        XCTAssertFalse(ThemeAssetPlan.showsThemeBackground(userWallpaperActive: false, themeBackgroundReady: false))
    }

    // MARK: URL / bản vá / gộp

    func testURLValidator() {
        XCTAssertTrue(ThemeAssetURL.isValid("https://viettelex.com/fonts/A.ttf", font: true))
        XCTAssertTrue(ThemeAssetURL.isValid("https://a.b/c.OTF#x", font: true))
        XCTAssertFalse(ThemeAssetURL.isValid("https://a.b/c.ttf.png", font: true))
        XCTAssertTrue(ThemeAssetURL.isValid("https://a.b/c", font: false))
        for bad in ["http://a.b/c", "HTTPS://a.b/c", "https://a.b", "https://a.b?x", "https://.ab/c", "https://ab./c",
                    "https://-a.b/c", "https://a:b@c.d/e", "https://a.b:443/c", "https://1.2.3.4/c", "https://ab/c",
                    "https://a.b/c d", "https://a.b/\u{1F600}", "https://a.b/c\\d", "ftp://a.b/c"] {
            XCTAssertFalse(ThemeAssetURL.isValid(bad, font: false), bad)
        }
        XCTAssertFalse(ThemeAssetURL.isValid("https://a.b/" + String(repeating: "x", count: 200), font: false))
        XCTAssertEqual(ThemeAssetURL.host("https://cdn.example.com/a/b.png?q"), "cdn.example.com")
        XCTAssertEqual(ThemeAssetURL.sha256(String(repeating: "AB", count: 32)), String(repeating: "ab", count: 32))
        XCTAssertNil(ThemeAssetURL.sha256(String(repeating: "g", count: 64)))
    }

    /// Phông tải về đi qua bản vá theme có sẵn (KeyStyleStore) khứ hồi; phông người dùng chọn thắng theme.
    func testKeyStyleAssetsRoundTripAndPrecedence() throws {
        let f = try XCTUnwrap(BuiltinFonts.list.first)
        var st = KeyStyle()
        st.assets.font = f.asset
        st.assets.background = ThemeAssetRef(url: "https://e.com/bg.jpg", sha256: nil)
        let raw = KeyStyleStore.serialize(["mint": st])
        XCTAssertTrue(raw.contains(#""font":{"name":"\#(f.name)","sha256":"\#(f.ref.sha256!)","url":"\#(f.ref.url)"}"#), raw)
        XCTAssertEqual(KeyStyleStore.parse(raw)["mint"], st)
        // Theme tự tạo có phông tải về; người dùng chọn phông hệ thống ⇒ phông hệ thống thắng.
        var spec = try XCTUnwrap(ThemeSpecParser.parse(##"{"v":1,"id":"t","name":{"vi":"t"},"light":{"key":"#FFFFFF","special":"#DDDDDD","ink":"#000000","accent":"#000000"},"font":{"name":"N","url":"https://e.com/n.ttf"},"keys":{"default":{"url":"https://e.com/k.png"}}}"##).spec)
        var s = ThemeSettings()
        s.select(custom: spec)
        XCTAssertEqual(s.effectiveKeyStyle.assets.font?.name, "N")
        s.keyStyles["t"] = KeyStyle(font: .serif)
        XCTAssertNil(s.effectiveKeyStyle.assets.font)
        XCTAssertEqual(s.effectiveKeyStyle.font, .serif)
        XCTAssertEqual(s.effectiveKeyStyle.assets.keys.count, 1, "skin theme vẫn còn")
        // Người dùng chọn phông tải về khác ⇒ thắng.
        var mine = KeyStyle(); mine.assets.font = f.asset
        s.keyStyles["t"] = mine
        XCTAssertEqual(s.effectiveKeyStyle.assets.font, f.asset)
        // "Chép JSON" theme tự tạo giữ tệp tải về; dán lại ra cùng đặc tả tệp.
        let copied = try XCTUnwrap(ThemeJSONActions.copyText(.custom("t"), settings: s, store: ["t": spec]))
        let back = try XCTUnwrap(ThemeSpecParser.parse(copied).spec)
        XCTAssertEqual(back.assets.font, f.asset)
        XCTAssertEqual(back.assets.keys, spec.assets.keys)
        // Sửa JSON theme có sẵn kèm ảnh ⇒ bản vá mang ảnh.
        spec.id = nil
        var store: [String: ThemeSpec] = [:]
        var s2 = ThemeSettings(theme: .mint)
        let r = ThemeJSONActions.save(back.canonical, to: .builtin(.mint), settings: &s2, store: &store)
        XCTAssertTrue(r.ok, "\(r.issues)")
        XCTAssertEqual(s2.style(for: .mint).assets.keys.count, 1)
        // Hết Plus ⇒ không tệp tải về nào (bàn phím vẽ màu / phông mặc định).
        PlusGate.paywallEnabled = true
        PlusGate.setPurchased(false)
        PlusGate.debugOverride = false
        XCTAssertTrue(s2.effectiveKeyStyle.assets.isEmpty)
    }

    func testBuiltinFontsList() throws {
        XCTAssertEqual(BuiltinFonts.list.count, 13)
        for e in BuiltinFonts.list {
            XCTAssertTrue(e.ref.url.hasPrefix("https://viettelex.com/fonts/"), e.id)
            XCTAssertNotNil(e.ref.sha256)
            XCTAssertLessThan(e.bytes, ThemeAssetLimits.fontMaxBytes)
            // Tệp host nằm trong docs/fonts và đúng sha256 (GitHub Pages phục vụ docs/ ở viettelex.com).
            let local = Self.repo.appendingPathComponent("docs/fonts/" + URL(string: e.ref.url)!.lastPathComponent)
            let data = try? Data(contentsOf: local)
            XCTAssertEqual(data.map(ThemeAssetDownloader.sha256Hex), e.ref.sha256, e.id)
            XCTAssertEqual(data?.count, e.bytes, e.id)
            // Bản đầy đủ có đủ tiếng Việt.
            if let data { XCTAssertNil(try ThemeAssetDownloader.validateFont(data), e.id) }
        }
        XCTAssertEqual(ThemeAssetPrompt.text([file(.font, BuiltinFonts.list[0].ref.url, sha: BuiltinFonts.list[0].ref.sha256)]),
                       L("Giao diện này cần tải %@ tệp (≈ %@ KB) từ %@. Tải?", 1, (BuiltinFonts.list[0].bytes + 1023) / 1024, "viettelex.com"))
    }

    /// Theme mẫu (docs/themes/demo/bien-dem.json): hợp lệ, đủ mọi loại tệp, sha khớp tệp host.
    func testDemoThemeIsValidAndHashesMatch() throws {
        let text = try String(contentsOf: Self.repo.appendingPathComponent("docs/themes/demo/bien-dem.json"), encoding: .utf8)
        let out = ThemeSpecParser.parse(text)
        let s = try XCTUnwrap(out.spec, "\(out.issues)")
        XCTAssertTrue(out.issues.isEmpty, "\(out.issues)")
        XCTAssertNotNil(s.assets.font); XCTAssertNotNil(s.assets.background); XCTAssertNotNil(s.assets.foreground)
        XCTAssertGreaterThanOrEqual(s.assets.keys.count, 8)
        for f in ThemeAssetPlan.make(s.assets).files {
            let path = f.ref.url.replacingOccurrences(of: "https://viettelex.com/", with: "docs/")
            let data = try Data(contentsOf: Self.repo.appendingPathComponent(path))
            XCTAssertEqual(ThemeAssetDownloader.sha256Hex(data), f.ref.sha256, path)
            // Xử lý như app (không mạng): mọi tệp hợp lệ.
            XCTAssertNoThrow(try ThemeAssetDownloader.process(data, file: f, screenEdge: 1600), path)
        }
    }

    // MARK: kho + dọn

    func testStoreIndexAndGC() throws {
        let sha = String(repeating: "a", count: 64), sha2 = String(repeating: "b", count: 64)
        XCTAssertTrue(ThemeAssetStore.validFileName("\(sha).key.png"))
        XCTAssertTrue(ThemeAssetStore.validFileName("\(sha).font.otf"))
        for bad in ["\(sha).key.ttf", "\(sha).font.png", "../\(sha).key.png", "\(sha).key", "x.key.png",
                    "\(sha.uppercased()).key.png", "\(sha).screen.png.png"] {
            XCTAssertFalse(ThemeAssetStore.validFileName(bad), bad)
        }
        let a = ThemeAssetStore.Entry(file: "\(sha).key.png", w: 10, h: 10, sw: 20, sh: 20, warn: nil)
        let b = ThemeAssetStore.Entry(file: "\(sha2).screen.jpg", w: 10, h: 10, sw: 20, sh: 20, warn: nil)
        let evil = ThemeAssetStore.Entry(file: "../../etc/passwd", w: 1, h: 1, sw: 1, sh: 1, warn: nil)
        try ThemeAssetStore.writeIndex(["key|https://e.com/a.png|-": a, "screen|https://e.com/b.jpg|-": b, "x": evil], tmp)
        let idx = ThemeAssetStore.readIndex(tmp)
        XCTAssertEqual(Set(idx.keys), ["key|https://e.com/a.png|-", "screen|https://e.com/b.jpg|-"], "tên tệp lạ bị bỏ")
        for n in [a.file, b.file, "stray.tmp"] { try Data([1]).write(to: tmp.appendingPathComponent(n)) }
        // Thuần.
        let p = ThemeAssetStore.gcPlan(index: idx, referenced: ["key|https://e.com/a.png|-"],
                                       files: [a.file, b.file, "stray.tmp", ThemeAssetStore.indexName])
        XCTAssertEqual(Array(p.index.keys), ["key|https://e.com/a.png|-"])
        XCTAssertEqual(p.delete, [b.file, "stray.tmp"].sorted())
        // Thật: theme còn tham chiếu skin a; ảnh nền b không ai dùng ⇒ xoá.
        var spec = ThemeAssetSpec()
        spec.keys = ["default": ThemeKeySkin(image: ThemeAssetRef(url: "https://e.com/a.png"))]
        let refs = ThemeAssetStore.referencedKeys(specs: [], styles: [KeyStyle(assets: spec)])
        XCTAssertEqual(refs, ["key|https://e.com/a.png|-"])
        let deleted = ThemeAssetStore.collectGarbage(dir: tmp, referenced: refs)
        XCTAssertEqual(Set(deleted), [b.file, "stray.tmp"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: tmp.appendingPathComponent(a.file).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: tmp.appendingPathComponent(b.file).path))
        XCTAssertEqual(Array(ThemeAssetStore.readIndex(tmp).keys), ["key|https://e.com/a.png|-"])
        // Không theme nào dùng ⇒ sạch.
        ThemeAssetStore.collectGarbage(dir: tmp, referenced: [])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: tmp.path), [ThemeAssetStore.indexName])
        // Mục lục hỏng ⇒ rỗng, không crash.
        try Data("{oops".utf8).write(to: tmp.appendingPathComponent(ThemeAssetStore.indexName))
        XCTAssertTrue(ThemeAssetStore.readIndex(tmp).isEmpty)
    }

    /// GC qua kho thật (theme tự tạo + bản vá): xoá theme ⇒ tệp của nó bị dọn; sau khôi phục ⇒ tệp thiếu được liệt kê.
    @MainActor func testGCAndRestoreThroughStores() async throws {
        let d = try XCTUnwrap(UserDefaultsProvider.shared)
        let data = Self.png(120, 140, alpha: true)
        let url = "https://e.com/k.png"
        let spec = try XCTUnwrap(ThemeSpecParser.parse(##"{"v":1,"id":"t","name":{"vi":"t"},"light":{"key":"#FFFFFF","special":"#DDDDDD","ink":"#000000","accent":"#000000"},"keys":{"default":{"url":"\##(url)"}}}"##).spec)
        CustomThemeStore.save(["t": spec], d)
        XCTAssertEqual(ThemeAssetCenter.allMissing(d).map(\.ref.url), [url], "sau khôi phục: thiếu tệp ⇒ đề nghị tải lại")
        let dl = ThemeAssetDownloader(transport: FakeTransport(files: [url: .success(data)]), dir: tmp, screenLongSidePx: 1000)
        let out = await dl.download(ThemeAssetCenter.allMissing(d))
        XCTAssertEqual(out.done.count, 1)
        XCTAssertTrue(ThemeAssetCenter.allMissing(d).isEmpty)
        XCTAssertTrue(ThemeAssetCenter.collectGarbage(d).isEmpty, "còn dùng ⇒ giữ")
        CustomThemeStore.save([:], d)
        XCTAssertEqual(ThemeAssetCenter.collectGarbage(d).count, 1, "xoá theme ⇒ dọn tệp")
        // Sao lưu không mang tệp: thư mục đánh dấu loại khỏi bản sao lưu.
        XCTAssertEqual(try tmp.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
    }

    // MARK: tải + xử lý (transport giả)

    func testDownloadPipelineFakeTransport() async throws {
        let good = Self.png(300, 200, alpha: true)
        let sha = ThemeAssetDownloader.sha256Hex(good)
        let files: [String: Result<Data, Error>] = [
            "https://e.com/good.png": .success(good),
            "https://e.com/text.png": .success(Data("<html>not an image</html>".utf8)),
            "https://e.com/big.png": .success(Data(count: ThemeAssetLimits.imageMaxBytes + 1)),
            "https://e.com/font.ttf": .success(Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0])),
            "https://e.com/junk.ttf": .success(Data([0x00, 0x01, 0x00, 0x00]) + Data(repeating: 7, count: 200)),
            "https://e.com/slow.png": .failure(ThemeAssetError.timeout),
            "https://e.com/off.png": .failure(ThemeAssetError.offline),
        ]
        let dl = ThemeAssetDownloader(transport: FakeTransport(files: files), dir: tmp, screenLongSidePx: 1000)
        let want: [ThemeAssetFile: ThemeAssetError] = [
            file(.key, "https://e.com/good.png", sha: String(repeating: "0", count: 64)): .shaMismatch,
            file(.key, "https://e.com/text.png"): .wrongType,
            file(.key, "https://e.com/big.png"): .tooLarge,
            file(.font, "https://e.com/font.ttf"): .wrongType,
            file(.font, "https://e.com/junk.ttf"): .fontInvalid,
            file(.key, "https://e.com/slow.png"): .timeout,
            file(.key, "https://e.com/off.png"): .offline,
            file(.key, "https://e.com/missing.png"): .httpStatus,
        ]
        let ok = file(.key, "https://e.com/good.png", sha: sha)
        let out = await dl.download(Array(want.keys) + [ok])
        XCTAssertEqual(out.failed, want)
        XCTAssertEqual(out.done, [ok])
        let idx = ThemeAssetStore.readIndex(tmp)
        let e = try XCTUnwrap(idx[ok.key])
        XCTAssertEqual(e.file, "\(sha).key.png")
        XCTAssertEqual([e.w, e.h, e.sw, e.sh], [300, 200, 300, 200])
        XCTAssertEqual(idx.count, 1, "lỗi không ghi mục lục")
        // Một ảnh dùng cho nhiều theme: cùng sha ⇒ cùng tệp (định địa chỉ theo nội dung).
        let again = await dl.download([file(.key, "https://e.com/good.png")])
        XCTAssertEqual(ThemeAssetStore.readIndex(tmp)[again.done[0].key]?.file, e.file)
        // Dán JSON không bao giờ gửi yêu cầu: preview chỉ đọc.
        XCTAssertNotNil(ThemeJSONActions.preview(##"{"v":1,"name":{"vi":"x"},"light":{"key":"#FFFFFF","special":"#DDDDDD","ink":"#000000","accent":"#000000"},"background":{"url":"https://e.com/good.png"}}"##).spec)
    }

    func testSniff() {
        XCTAssertEqual(ThemeAssetDownloader.sniff(Self.png(4, 4, alpha: true)), .png)
        XCTAssertEqual(ThemeAssetDownloader.sniff(Self.jpegWithGPS(8, 8)), .jpeg)
        XCTAssertEqual(ThemeAssetDownloader.sniff(Data("RIFF\0\0\0\0WEBPVP8 ".utf8)), .webp)
        XCTAssertEqual(ThemeAssetDownloader.sniff(Data([0, 0, 0, 24]) + Data("ftypheic".utf8)), .heic)
        XCTAssertEqual(ThemeAssetDownloader.sniff(Data("OTTO".utf8)), .otf)
        XCTAssertNil(ThemeAssetDownloader.sniff(Data("ttcf".utf8)))
        XCTAssertNil(ThemeAssetDownloader.sniff(Data("wOF2".utf8)))
        XCTAssertNil(ThemeAssetDownloader.sniff(Data("GIF89a".utf8)))
        XCTAssertNil(ThemeAssetDownloader.sniff(Data()))
    }

    /// Thu nhỏ: skin ≤ 512, ảnh nền ≤ cỡ bàn phím (≤ 1600), không phóng to; JPEG đục / PNG alpha; không metadata;
    /// ảnh quá nhiều điểm ảnh bị chặn TRƯỚC khi giải.
    func testImageDownsampleBoundsAndMetadata() throws {
        let big = Self.png(3000, 2000, alpha: true)
        let sha = ThemeAssetDownloader.sha256Hex(big)
        let k = try ThemeAssetDownloader.process(big, file: file(.key, "https://e.com/a.png"), screenEdge: 1600)
        XCTAssertEqual([k.entry.w, k.entry.h], [512, 341])
        XCTAssertEqual([k.entry.sw, k.entry.sh], [3000, 2000])
        XCTAssertEqual(k.entry.file, "\(sha).key.png")
        let s = try ThemeAssetDownloader.process(big, file: file(.screen, "https://e.com/a.png"), screenEdge: 1290)
        XCTAssertEqual(max(s.entry.w, s.entry.h), 1290)
        XCTAssertEqual(ThemeAssetLimits.screenEdge(screenLongSidePx: 5000), 1600)
        let small = try ThemeAssetDownloader.process(Self.png(100, 50, alpha: true), file: file(.key, "https://e.com/s.png"),
                                                     screenEdge: 1600)
        XCTAssertEqual([small.entry.w, small.entry.h], [100, 50], "không phóng to")
        // JPEG có GPS/EXIF ⇒ JPEG đục, sạch metadata.
        let j = try ThemeAssetDownloader.process(Self.jpegWithGPS(800, 600), file: file(.screen, "https://e.com/p.jpg"),
                                                 screenEdge: 400)
        XCTAssertTrue(j.entry.file.hasSuffix(".screen.jpg"))
        XCTAssertEqual(max(j.entry.w, j.entry.h), 400)
        let src = try XCTUnwrap(CGImageSourceCreateWithData(j.data as CFData, nil))
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] ?? [:]
        XCTAssertNil(props[kCGImagePropertyGPSDictionary])
        XCTAssertNil((props[kCGImagePropertyExifDictionary] as? [CFString: Any])?[kCGImagePropertyExifUserComment])
        // PNG đục (không pixel trong) ⇒ JPEG.
        let opaque = try ThemeAssetDownloader.process(Self.png(64, 64, alpha: false), file: file(.key, "https://e.com/o.png"),
                                                      screenEdge: 1600)
        XCTAssertTrue(opaque.entry.file.hasSuffix(".jpg"))
        // Bom: cạnh 13000 ⇒ chặn trước khi giải.
        XCTAssertThrowsError(try ThemeAssetDownloader.process(Self.png(13_000, 4, alpha: false),
                                                              file: file(.key, "https://e.com/bomb.png"), screenEdge: 1600)) {
            XCTAssertEqual($0 as? ThemeAssetError, .tooManyPixels)
        }
        // Tiền cảnh phủ kín ⇒ cảnh báo; khung mảnh ở mép ⇒ không.
        let heavy = try ThemeAssetDownloader.process(Self.png(400, 300, alpha: true, inset: 2),
                                                     file: file(.screen, "https://e.com/fg.png"), screenEdge: 1600)
        XCTAssertEqual(heavy.entry.warn, ThemeAssetWarning.foregroundCoverage.rawValue)
        let light = try ThemeAssetDownloader.process(Self.png(400, 300, alpha: true, inset: 140),
                                                     file: file(.screen, "https://e.com/fg2.png"), screenEdge: 1600)
        XCTAssertNil(light.entry.warn)
    }

    /// Phông: bản đầy đủ hợp lệ; bản xem trước (chỉ V, t) ⇒ cảnh báo thiếu tiếng Việt; rác ⇒ từ chối.
    func testFontValidation() throws {
        let full = try Data(contentsOf: Self.repo.appendingPathComponent("docs/fonts/BeVietnamPro-Medium.ttf"))
        XCTAssertNil(try ThemeAssetDownloader.validateFont(full))
        let preview = try Data(contentsOf: Self.repo.appendingPathComponent("iOS/App/FontPreviews/be-vietnam-pro.ttf"))
        XCTAssertEqual(try ThemeAssetDownloader.validateFont(preview), .missingVietnamese)
        let p = try ThemeAssetDownloader.process(preview, file: file(.font, "https://e.com/v.ttf"), screenEdge: 1600)
        XCTAssertEqual(p.entry.warn, "missingVietnamese")
        XCTAssertTrue(p.entry.file.hasSuffix(".font.ttf"))
        XCTAssertThrowsError(try ThemeAssetDownloader.validateFont(Data("true".utf8) + Data(count: 64)))
    }

    func testPromptText() {
        let f = [file(.key, "https://b.com/a.png"), file(.screen, "https://a.com/b.jpg"), file(.key, "https://b.com/c.png")]
        XCTAssertEqual(ThemeAssetPrompt.text(f), L("Giao diện này cần tải %@ tệp (tối đa %@ MB) từ %@. Tải?", 3, 15, "a.com, b.com"))
    }

    // MARK: URLSession thật + URLProtocol giả: chuyển hướng http, 404, cỡ không khai báo, hết giờ, mất mạng

    final class Stub: URLProtocol {
        nonisolated(unsafe) static var routes: [String: (Int, [String: String], Data)] = [:]
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            let u = request.url!.absoluteString
            if u.contains("hang") { return }                                 // không trả lời ⇒ hết giờ
            if u.contains("offline") { client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)); return }
            guard let (code, headers, body) = Self.routes[u] else {
                client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil,
                                                                       headerFields: nil)!, cacheStoragePolicy: .notAllowed)
                client?.urlProtocolDidFinishLoading(self); return
            }
            let resp = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: "HTTP/1.1", headerFields: headers)!
            if (300..<400).contains(code), let loc = headers["Location"], let to = URL(string: loc) {
                client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: to), redirectResponse: resp)
                client?.urlProtocolDidFinishLoading(self)
                return
            }
            client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
            // Gửi từng mẩu (giả luồng) — không có Content-Length.
            var i = 0
            while i < body.count { client?.urlProtocol(self, didLoad: body.subdata(in: i..<min(body.count, i + 65536))); i += 65536 }
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    func testURLSessionTransportPolicies() async throws {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [Stub.self]
        let t = URLSessionAssetTransport(configuration: cfg, timeout: 1)
        let img = Self.png(16, 16, alpha: true)
        Stub.routes = [
            "https://e.com/ok.png": (200, [:], img),
            "https://e.com/r-https": (302, ["Location": "https://e.com/ok.png"], Data()),
            "https://e.com/r-http": (302, ["Location": "http://e.com/ok.png"], Data()),
            "https://e.com/huge": (200, [:], Data(count: 300_000)),
            "https://e.com/declared": (200, ["Content-Length": "999999999"], Data(count: 10)),
        ]
        defer { Stub.routes = [:] }
        let ok = try await t.get(URL(string: "https://e.com/ok.png")!, maxBytes: 1_000_000)
        XCTAssertEqual(ok, img)
        let redirected = try await t.get(URL(string: "https://e.com/r-https")!, maxBytes: 1_000_000)
        XCTAssertEqual(redirected, img, "chuyển hướng https ⇒ được")
        func expect(_ u: String, _ max: Int = 1_000_000, _ e: ThemeAssetError) async {
            do { _ = try await t.get(URL(string: u)!, maxBytes: max); XCTFail("\(u) phải lỗi") }
            catch { XCTAssertEqual(error as? ThemeAssetError, e, u) }
        }
        await expect("https://e.com/r-http", 1_000_000, .redirectInsecure)
        await expect("https://e.com/none", 1_000_000, .httpStatus)
        await expect("https://e.com/huge", 100_000, .tooLarge)
        await expect("https://e.com/declared", 100_000, .tooLarge)
        await expect("http://e.com/ok.png", 1_000_000, .notHttps)
        await expect("https://e.com/hang", 1_000_000, .timeout)
        await expect("https://e.com/offline", 1_000_000, .offline)
    }

    // MARK: bàn phím thật

    /// Tải (transport giả) một theme đủ loại tệp rồi trả đặc tả + dữ liệu đã ghi vào `tmp`.
    private func installHeavyTheme(skins: Int = 14, writeFiles: Bool = true) async throws -> ThemeSpec {
        let base = "https://e.com/"
        var data: [String: Result<Data, Error>] = [:]
        var keys: [String] = []
        data[base + "bg.jpg"] = .success(Self.jpegWithGPS(1600, 1000))
        data[base + "fg.png"] = .success(Self.png(1600, 1000, alpha: true, inset: 300))
        // default (+ đè) + special + (skins − 3) chữ riêng — cùng nền + tiền cảnh = 16 ảnh khác nhau.
        let colors: [UIColor] = [.systemRed, .systemBlue, .systemGreen, .systemPink, .systemPurple, .systemOrange]
        func add(_ name: String, _ i: Int) -> String {
            data[base + name + ".png"] = .success(Self.png(512, 512, alpha: true, color: colors[i % colors.count]))
            return base + name + ".png"
        }
        keys.append(#""default":{"url":"\#(add("d", 0))","slice":[60,60,60,60],"pressed":{"url":"\#(add("dp", 1))"}}"#)
        keys.append(#""special":{"url":"\#(add("s", 2))","slice":[60,60,60,60]}"#)
        for (i, l) in ThemeAssetSpec.letterKeys.prefix(skins - 3).enumerated() {
            keys.append(#""\#(l)":{"url":"\#(add("l" + l, i + 3))"}"#)
        }
        let full = try Data(contentsOf: Self.repo.appendingPathComponent("docs/fonts/BeVietnamPro-Medium.ttf"))
        data[base + "f.ttf"] = .success(full)
        let json = ##"{"v":1,"id":"heavy","name":{"vi":"Nặng"},"light":{"bg":"#102040","key":"#203050","special":"#304060","ink":"#FFFFFF","accent":"#FFAA00"},"font":{"name":"Be","url":"\##(base)f.ttf"},"background":{"url":"\##(base)bg.jpg"},"foreground":{"url":"\##(base)fg.png"},"keys":{\##(keys.joined(separator: ","))}}"##
        let out = ThemeSpecParser.parse(json)
        let spec = try XCTUnwrap(out.spec, "\(out.issues)")
        XCTAssertEqual(ThemeAssetPlan.imageURLs(spec.assets).count, 16)
        if writeFiles {
            let dl = ThemeAssetDownloader(transport: FakeTransport(files: data), dir: tmp, screenLongSidePx: 1600)
            let r = await dl.download(ThemeAssetPlan.make(spec.assets).files)
            XCTAssertTrue(r.failed.isEmpty, "\(r.failed)")
        }
        var s = ThemeSettings()
        s.select(custom: spec)
        s.save(UserDefaultsProvider.shared)
        return spec
    }

    private func letterButton(_ kb: KeyboardView, _ l: String) -> KeyboardView.KeyButton? {
        kb.debugAllKeyButtons().first { $0.currentTitle == l || $0.currentTitle == l.uppercased() }
    }

    @MainActor private func makeKB() -> KeyboardView {
        let kb = KeyboardView(needsGlobe: false, inputController: nil) { _ in }
        kb.frame = CGRect(x: 0, y: 0, width: 430, height: 300)
        kb.applyAppearance(.light, style: .light)
        kb.layoutIfNeeded()
        return kb
    }

    /// Theme nặng: nền + tiền cảnh + 14 skin (16 ảnh) + phông. Giải MỘT lần, skin nhóm dùng chung CGImage,
    /// đè = đổi con trỏ ảnh, ô phóng to cùng skin + phông, thứ tự lớp đúng, RAM trong ngân sách.
    @MainActor func testHeavyThemeOnRealKeyboard() async throws {
        _ = try await installHeavyTheme()
        let before = KeyboardBenchTests.footprintMB()
        #if DEBUG
        let loads0 = ThemeAssetLoader.loadCount
        #endif
        let kb = makeKB()
        let a = try XCTUnwrap(kb.debugThemeAssets)
        XCTAssertEqual(a.skins.count, ThemeAssetPlan.roles.count, "mọi vai có skin (chữ ⇒ default, phím tên ⇒ special)")
        XCTAssertNotNil(a.font)
        XCTAssertNotNil(KeyboardView.labelFonts.custom, "nhãn phím vẽ bằng phông tải về")
        // Skin nhóm dùng chung một CGImage; skin riêng khác.
        let o = try XCTUnwrap(letterButton(kb, "o")), p = try XCTUnwrap(letterButton(kb, "p"))
        let aKey = try XCTUnwrap(letterButton(kb, "a"))
        let def = try XCTUnwrap(a.skins["default"]?.normal)
        XCTAssertTrue(kb.debugSkinContents(o) === def)
        XCTAssertTrue(kb.debugSkinContents(p) === def)
        XCTAssertTrue(kb.debugSkinContents(aKey) === a.skins["a"]?.normal)
        XCTAssertFalse(kb.debugSkinContents(aKey) === def)
        XCTAssertTrue(a.skins["shift"]?.normal === a.skins["special"]?.normal)
        XCTAssertLessThanOrEqual(def.width, 192, "skin phím thường giải ≤ 192 px")
        XCTAssertLessThanOrEqual(try XCTUnwrap(a.skins["space"]?.normal).width, 512)
        // Đè = đổi con trỏ sang ảnh đè dùng chung; nhả = về ảnh thường.
        kb.debugPress(o, true)
        XCTAssertTrue(kb.debugSkinContents(o) === a.skins["default"]?.pressed)
        kb.debugPress(o, false)
        XCTAssertTrue(kb.debugSkinContents(o) === def)
        // Nền màu phím trong khi có skin.
        XCTAssertEqual(o.backgroundColor, .clear)
        // Ô phóng to: cùng skin.
        kb.debugShowBalloon(over: o, text: "o")
        XCTAssertTrue(kb.debugBalloonSkin === def)
        // Thứ tự lớp: hàng phím < tiền cảnh < ô phóng to; tiền cảnh không nhận chạm.
        let z = kb.debugZOrder
        XCTAssertLessThan(try XCTUnwrap(z.rows), try XCTUnwrap(z.foreground))
        XCTAssertLessThan(try XCTUnwrap(z.foreground), try XCTUnwrap(z.balloon))
        XCTAssertFalse(kb.debugForegroundView.isUserInteractionEnabled)
        let pt = o.convert(CGPoint(x: o.bounds.midX, y: o.bounds.midY), to: kb)
        XCTAssertFalse(kb.hitTest(pt, with: nil) === kb.debugForegroundView)
        // Ảnh nền + tiền cảnh: giải ngoài main, ≤ cỡ view × 2.
        kb.layoutIfNeeded()
        Wallpaper.queue.sync {}
        try await Task.sleep(nanoseconds: 50_000_000)
        let bg = try XCTUnwrap(kb.debugThemeImageView.image?.cgImage)
        let fg = try XCTUnwrap(kb.debugForegroundView.image?.cgImage)
        XCTAssertFalse(kb.debugThemeImageView.isHidden)
        for img in [bg, fg] {
            XCTAssertLessThanOrEqual(max(img.width, img.height), 430 * 2)
        }
        let screenBytes = bg.bytesPerRow * bg.height + fg.bytesPerRow * fg.height
        let after = KeyboardBenchTests.footprintMB()
        print(String(format: "THEME ASSETS RAM iOS: skin %.2f MB (%d ảnh khác nhau) + nền/tiền cảnh %.2f MB; phys_footprint +%.1f MB",
                     Double(a.skinBytes) / 1_048_576, Set(a.skins.values.map { ObjectIdentifier($0.normal) }).count,
                     Double(screenBytes) / 1_048_576, after - before))
        XCTAssertLessThan(a.skinBytes, 4 * 1_048_576, "skin ≤ 4 MB")
        XCTAssertLessThan(a.skinBytes + screenBytes, 8 * 1_048_576, "bitmap theme ≤ 8 MB")
        XCTAssertLessThan(after - before, 20, "RAM tăng ≪ giới hạn extension (~48–60 MB tổng)")
        // Hiện lại (controller mới mỗi lần hiện) ⇒ không giải lại.
        _ = makeKB()
        #if DEBUG
        XCTAssertEqual(ThemeAssetLoader.loadCount - loads0, 1, "giải một lần mỗi theme")
        #endif
    }

    /// Thiếu tệp (offline / lỗi) ⇒ màu theme + phông mặc định, không crash.
    @MainActor func testMissingFilesFallBack() async throws {
        _ = try await installHeavyTheme(writeFiles: false)
        let kb = makeKB()
        let a = try XCTUnwrap(kb.debugThemeAssets)
        XCTAssertTrue(a.skins.isEmpty)
        XCTAssertNil(a.font)
        XCTAssertNil(KeyboardView.labelFonts.custom)
        let o = try XCTUnwrap(letterButton(kb, "o"))
        XCTAssertNil(kb.debugSkinLayer(o))
        XCTAssertEqual(kb.debugKeyColors(o).normal, kb.debugPalette.keyFill.ui, "màu theme")
        XCTAssertTrue(kb.debugForegroundView.isHidden)
        XCTAssertTrue(kb.debugThemeImageView.isHidden)
        // Tệp hỏng trên đĩa (bị sửa) ⇒ cũng dự phòng.
        _ = try await installHeavyTheme()
        for f in try FileManager.default.contentsOfDirectory(atPath: tmp.path) where f.hasSuffix(".png") || f.hasSuffix(".ttf") {
            try Data("rác".utf8).write(to: tmp.appendingPathComponent(f))
        }
        ThemeAssetLoader.dropCache()
        let kb2 = makeKB()
        XCTAssertTrue(kb2.debugThemeAssets?.skins.isEmpty ?? true)
        XCTAssertNil(KeyboardView.labelFonts.custom)
    }

    /// Theme không có tệp tải về: không đọc mục lục, không giải, không thêm view (0 chi phí như trước).
    @MainActor func testNoAssetsZeroCost() {
        var s = ThemeSettings(theme: .mint)
        s.save(UserDefaultsProvider.shared)
        #if DEBUG
        let loads0 = ThemeAssetLoader.loadCount
        #endif
        let kb = makeKB()
        XCTAssertNil(kb.debugThemeAssets)
        XCTAssertNil(kb.debugForegroundView.superview)
        XCTAssertNil(kb.debugThemeImageView.image)
        XCTAssertTrue(kb.debugAllKeyButtons().allSatisfy { kb.debugSkinLayer($0) == nil })
        XCTAssertNil(KeyboardView.labelFonts.custom)
        #if DEBUG
        XCTAssertEqual(ThemeAssetLoader.loadCount, loads0)
        #endif
    }

    // MARK: Bug 19/10/2026 — chọn phông "Vt" tải về, tải xong ô xem trước trong app vẫn phông hệ thống

    /// Phil (iPhone 13 mini, Debug): Tuỳ chỉnh nâng cao → Phông chữ → chọn phông tải về → đồng ý tải ⇒ ô xem trước
    /// KHÔNG đổi phông. Gốc: ThemePreview chỉ đọc `keyStyle.font` (= .standard khi chọn phông tải về) và không quan
    /// sát lượt tải. Khoá: tải xong (transport giả) ⇒ center báo kho đổi, phông xem trước = đúng tệp vừa tải; bàn phím
    /// hiện lần kế cũng dùng phông đó (trước khi tải: dự phòng phông hệ thống).
    @MainActor func testDownloadCompletionUpdatesPreviewAndKeyboardFont() async throws {
        let e = try XCTUnwrap(BuiltinFonts.list.first { $0.id == "lobster" }, "phông đã đổi tên VT …")
        let data = try Data(contentsOf: Self.repo.appendingPathComponent("docs/fonts/" + URL(string: e.ref.url)!.lastPathComponent))
        let center = ThemeAssetCenter.shared
        let savedTransport = center.transport
        defer { center.transport = savedTransport; center.storeChanged() }
        center.transport = FakeTransport(files: [e.ref.url: .success(data)])
        center.storeChanged()

        var style = KeyStyle()
        style.assets.font = e.asset
        var s = ThemeSettings(theme: .mint)
        s.keyStyle = style
        s.save(UserDefaultsProvider.shared)

        // Trước khi tải: chưa có tệp ⇒ phông hệ thống (ô xem trước + bàn phím).
        XCTAssertNil(center.previewFont(e.asset))
        let before = try XCTUnwrap(KeyLabelFonts.previewFont(style, custom: center.previewFont(e.asset), size: 15))
        XCTAssertNotEqual(before.familyName, e.name)
        _ = makeKB()
        XCTAssertNil(KeyboardView.labelFonts.custom)

        // Chọn ⇒ hỏi ⇒ đồng ý ⇒ tải xong.
        center.offer(style.assets, context: "test")
        let req = try XCTUnwrap(center.pending, "phông chưa tải ⇒ hỏi trước khi tải")
        let v0 = center.storeVersion
        await center.accept(req)?.value
        XCTAssertFalse(center.busy)
        XCTAssertEqual(center.storeVersion, v0 + 1, "ô xem trước (quan sát storeVersion) vẽ lại")
        XCTAssertTrue(center.missing(style.assets).isEmpty)

        let custom = try XCTUnwrap(center.previewFont(e.asset), "tải xong ⇒ phông xem trước có tệp")
        let after = try XCTUnwrap(KeyLabelFonts.previewFont(style, custom: custom, size: 15))
        XCTAssertEqual(after.familyName, e.name)
        XCTAssertEqual(after.fontName, "VTLobster-Regular")

        // Bàn phím hiện lần kế: phông tải về.
        _ = makeKB()
        let kbCustom = try XCTUnwrap(KeyboardView.labelFonts.custom)
        XCTAssertEqual(CTFontCopyPostScriptName(CTFontCreateWithFontDescriptor(kbCustom, 20, nil)) as String, "VTLobster-Regular")
        XCTAssertEqual(KeyboardView.keyFont(20).fontName, "VTLobster-Regular")
    }

    /// Cả 13 phông có sẵn: tên trong builtin-fonts.json = họ phông trong tệp (bản đầy đủ docs/fonts + bản xem trước
    /// "Vt" trong app), tên PostScript = tên bỏ dấu cách + "-Regular"/"-Medium"; 4 phông đổi tên (RFN) mang "VT ".
    func testBuiltinFontNamesMatchFiles() throws {
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: Self.repo.appendingPathComponent("docs/fonts/manifest.json"))) as? [String: Any]
        let renamed = Dictionary(uniqueKeysWithValues: ((manifest?["fonts"] as? [[String: Any]]) ?? []).compactMap { d -> (String, Bool)? in
            guard let id = d["id"] as? String, let r = d["renamed"] as? Bool else { return nil }
            return (id, r)
        })
        XCTAssertEqual(BuiltinFonts.list.count, 13)
        XCTAssertEqual(renamed.values.filter { $0 }.count, 4)
        for e in BuiltinFonts.list {
            XCTAssertEqual(e.name.hasPrefix("VT "), renamed[e.id], e.id)
            let full = Self.repo.appendingPathComponent("docs/fonts/" + URL(string: e.ref.url)!.lastPathComponent)
            let preview = Self.repo.appendingPathComponent("iOS/App/FontPreviews/\(e.id).ttf")
            for u in [full, preview] {
                let d = try XCTUnwrap(ThemeAssetLoader.fontDescriptor(at: u), u.lastPathComponent)
                let f = CTFontCreateWithFontDescriptor(d, 20, nil)
                XCTAssertEqual(CTFontCopyFamilyName(f) as String, e.name, u.lastPathComponent)
                let ps = CTFontCopyPostScriptName(f) as String
                let stem = e.name.replacingOccurrences(of: " ", with: "")
                XCTAssertTrue(ps == stem + "-Regular" || ps == stem + "-Medium", "\(u.lastPathComponent): \(ps)")
                XCTAssertEqual(KeyLabelFonts.previewFont({ var st = KeyStyle(); st.assets.font = e.asset; return st }(),
                                                         custom: d, size: 15)?.fontName, ps)
            }
        }
    }
}
