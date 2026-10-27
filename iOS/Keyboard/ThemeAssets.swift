import UIKit
import ImageIO
import CoreText

// "Giao diện JSON" — tệp tải về (phông / ảnh nền / tiền cảnh / skin phím). Android y hệt
// (android/keyboard/.../ThemeAssets.kt): cùng kế hoạch (ThemeAssetPlan — chuỗi mô tả trùng từng ký tự, fixture
// chung theme-json-cases.txt dòng PLAN), cùng giới hạn, cùng toán 9-slice, cùng tên tệp / mục lục.
//
// Luồng: JSON chỉ là chỉ dẫn. APP (App/ThemeAssetDownloader.swift) hỏi người dùng rồi mới tải, kiểm (https,
// cỡ, loại, sha256), giải mã có thu nhỏ, lưu lại bản NHỎ không metadata vào App Group `ThemeAssets/`
// (tên = sha256 của tệp tải về ⇒ trùng nội dung dùng chung) + mục lục `index.json`. Bàn phím KHÔNG BAO GIỜ
// dùng mạng: chỉ đọc mục lục + tệp đã xử lý, giải mỗi ảnh MỘT lần mỗi lần nạp theme, dùng chung CGImage cho
// mọi phím cùng nhóm; thiếu tệp / hỏng ⇒ màu theme / phông mặc định (không crash).

// MARK: - Giới hạn (chung hai nền tảng)

enum ThemeAssetClass: String, CaseIterable {
    /// Phông .ttf/.otf (lưu nguyên).
    case font
    /// Ảnh nền / tiền cảnh: thu ≤ cỡ bàn phím.
    case screen
    /// Skin phím: thu ≤ 512 px.
    case key
}

enum ThemeAssetLimits {
    static let fontMaxBytes = 2 * 1024 * 1024
    static let imageMaxBytes = 5 * 1024 * 1024
    /// Cạnh dài tối đa đã lưu.
    static let keyMaxEdge = 512
    static let screenMaxEdge = 1600
    /// Chặn "bom giải nén": đọc kích thước từ header TRƯỚC khi giải.
    static let maxSourcePixels = 40_000_000
    static let maxSourceEdge = 12_000
    static let timeout: TimeInterval = 20
    /// Tiền cảnh phủ (alpha ≥ 50 %) quá tỉ lệ này ⇒ cảnh báo khó đọc chữ.
    static let foregroundCoverageWarn = 0.35

    /// Cạnh dài lưu cho ảnh nền / tiền cảnh: ≤ cỡ bàn phím (px, cạnh dài màn hình ở scale giải ≤ 2) và ≤ 1600.
    static func screenEdge(screenLongSidePx: Int) -> Int { max(64, min(screenMaxEdge, screenLongSidePx)) }

    static func maxBytes(_ c: ThemeAssetClass) -> Int { c == .font ? fontMaxBytes : imageMaxBytes }

    /// Cạnh dài khi BÀN PHÍM giải skin: phím rộng (space / return) 512, phím thường 192 — đủ nét ở @3x,
    /// 16 skin × 192² × 4 B ≈ 2,4 MB thay vì 16 MB.
    static func keyDecodeEdge(roles: Set<String>) -> Int {
        roles.contains("space") || roles.contains("return") ? keyMaxEdge : 192
    }
}

// MARK: - Kế hoạch (thuần — chuỗi mô tả trùng Android)

/// Tệp cần có: lớp + URL + sha256. Khoá mục lục = "lớp|url|sha256 hoặc -".
struct ThemeAssetFile: Hashable, Comparable {
    var cls: ThemeAssetClass
    var ref: ThemeAssetRef
    var key: String { "\(cls.rawValue)|\(ref.url)|\(ref.sha256 ?? "-")" }
    static func < (a: Self, b: Self) -> Bool { a.key < b.key }
}

struct ThemeAssetPlan: Equatable {
    struct Skin: Equatable {
        var image: ThemeAssetRef
        var pressed: ThemeAssetRef?
        var slice: [Int]?
    }
    var fontName: String?
    var font: ThemeAssetRef?
    var background: ThemeAssetRef?
    var foreground: ThemeAssetRef?
    /// Vai phím → skin ĐÃ GIẢI (từng phím → nhóm). Không có ⇒ màu theme.
    var skins: [String: Skin] = [:]

    /// Thứ tự vai (chuỗi mô tả + vòng lặp).
    static let roles: [String] = ThemeAssetSpec.groupKeys + ThemeAssetSpec.namedKeys + ThemeAssetSpec.letterKeys

    /// Thứ tự giải: chữ a–z ⇒ "a" → "default"; space / return / shift / delete ⇒ chính nó → "special";
    /// "default" / "special" ⇒ chính nó (phím số / ký hiệu dùng "default", 123 / 🌐 / emoji dùng "special").
    static func resolve(_ role: String, in keys: [String: ThemeKeySkin]) -> ThemeKeySkin? {
        if let k = keys[role] { return k }
        if ThemeAssetSpec.namedKeys.contains(role) { return keys["special"] }
        if ThemeAssetSpec.letterKeys.contains(role) { return keys["default"] }
        return nil
    }

    static func make(_ a: ThemeAssetSpec) -> ThemeAssetPlan {
        var p = ThemeAssetPlan()
        p.fontName = a.font?.name
        p.font = a.font?.ref
        p.background = a.background
        p.foreground = a.foreground
        for r in roles {
            if let k = resolve(r, in: a.keys) { p.skins[r] = Skin(image: k.image, pressed: k.pressed, slice: k.slice) }
        }
        return p
    }

    var isEmpty: Bool { font == nil && background == nil && foreground == nil && skins.isEmpty }

    /// Skin cho vai `role` (vai lạ ⇒ nhóm: chữ ⇒ default).
    func skin(_ role: String) -> Skin? { skins[role] }

    /// Mọi tệp khác nhau cần có (sắp xếp theo khoá).
    var files: [ThemeAssetFile] {
        var s = Set<ThemeAssetFile>()
        if let f = font { s.insert(ThemeAssetFile(cls: .font, ref: f)) }
        if let b = background { s.insert(ThemeAssetFile(cls: .screen, ref: b)) }
        if let f = foreground { s.insert(ThemeAssetFile(cls: .screen, ref: f)) }
        for k in skins.values {
            s.insert(ThemeAssetFile(cls: .key, ref: k.image))
            if let pr = k.pressed { s.insert(ThemeAssetFile(cls: .key, ref: pr)) }
        }
        return s.sorted()
    }

    /// URL ảnh khác nhau (giới hạn 16) — tính trên đặc tả (cả skin không vai nào dùng).
    static func imageURLs(_ a: ThemeAssetSpec) -> Set<String> {
        var s = Set<String>()
        if let b = a.background { s.insert(b.url) }
        if let f = a.foreground { s.insert(f.url) }
        for k in a.keys.values {
            s.insert(k.image.url)
            if let p = k.pressed { s.insert(p.url) }
        }
        return s
    }

    /// Chuỗi mô tả CHUẨN (fixture PLAN, Android trùng từng ký tự).
    var description: String {
        func r(_ x: ThemeAssetRef) -> String { x.url + "#" + (x.sha256 ?? "-") }
        var parts: [String] = []
        if let f = font { parts.append("font=" + r(f)) }
        if let b = background { parts.append("bg=" + r(b)) }
        if let f = foreground { parts.append("fg=" + r(f)) }
        for role in Self.roles {
            guard let k = skins[role] else { continue }
            var s = "key." + role + "=" + r(k.image)
            if let p = k.pressed { s += ">" + r(p) }
            if let sl = k.slice { s += "@" + sl.map(String.init).joined(separator: ",") }
            parts.append(s)
        }
        let images = Set(files.filter { $0.cls != .font }.map(\.ref.url)).count
        parts.append("files=\(files.count)")
        parts.append("images=\(images)")
        return parts.joined(separator: "|")
    }

    /// Ảnh nền theme chỉ hiện khi đã tải xong VÀ ảnh nền tự đặt của người dùng không bật (ảnh người dùng thắng).
    static func showsThemeBackground(userWallpaperActive: Bool, themeBackgroundReady: Bool) -> Bool {
        themeBackgroundReady && !userWallpaperActive
    }

    /// Chữ ký để cache (đổi URL / sha / slice ⇒ nạp lại).
    var signature: String { description }
}

// MARK: - 9-slice (thuần — Android cùng công thức)

enum NineSlice {
    /// Đổi insets [t,l,b,r] từ px ảnh `from` sang px ảnh `to` (theo từng trục, làm tròn), kẹp để phần giữa
    /// còn ≥ 1 px: t+b ≤ h−1, l+r ≤ w−1 (vượt ⇒ thu cả hai theo tỉ lệ).
    static func scale(_ s: [Int], fromW: Int, fromH: Int, toW: Int, toH: Int) -> [Int] {
        guard s.count == 4, fromW > 0, fromH > 0, toW > 0, toH > 0 else { return [0, 0, 0, 0] }
        let ky = Double(toH) / Double(fromH), kx = Double(toW) / Double(fromW)
        var t = Int((Double(s[0]) * ky).rounded()), b = Int((Double(s[2]) * ky).rounded())
        var l = Int((Double(s[1]) * kx).rounded()), r = Int((Double(s[3]) * kx).rounded())
        (t, b) = fit(t, b, toH - 1)
        (l, r) = fit(l, r, toW - 1)
        return [t, l, b, r]
    }

    private static func fit(_ a: Int, _ b: Int, _ room: Int) -> (Int, Int) {
        let room = max(room, 0)
        guard a + b > room, a + b > 0 else { return (a, b) }
        let k = Double(room) / Double(a + b)
        let na = Int((Double(a) * k).rounded(.down)), nb = Int((Double(b) * k).rounded(.down))
        return (na, nb)
    }

    /// Insets ĐÍCH (pt / dp) trên phím W×H: ảnh gốc cao `srcH` px phủ đúng chiều cao phím ⇒ hệ số H/srcH;
    /// góc rộng hơn phím (l+r > W hoặc t+b > H) ⇒ thu ĐỀU cả bốn (giữ hình góc).
    static func destInsets(_ slice: [Int], srcH: Int, width W: Double, height H: Double) -> [Double] {
        guard slice.count == 4, srcH > 0, W > 0, H > 0 else { return [0, 0, 0, 0] }
        let f = H / Double(srcH)
        var d = slice.map { Double($0) * f }
        let k = min(1, W / max(d[1] + d[3], 1e-9), H / max(d[0] + d[2], 1e-9))
        if k < 1 { d = d.map { $0 * k } }
        return d
    }

    /// Hệ số thu đều (≤ 1) của destInsets — iOS dùng cho contentsScale.
    static func shrink(_ slice: [Int], srcH: Int, width W: Double, height H: Double) -> Double {
        guard slice.count == 4, srcH > 0, W > 0, H > 0 else { return 1 }
        let f = H / Double(srcH)
        return min(1, W / max(Double(slice[1] + slice[3]) * f, 1e-9), H / max(Double(slice[0] + slice[2]) * f, 1e-9))
    }

    struct Patch: Equatable { var src: CGRect; var dst: CGRect }

    /// 9 mảnh (ảnh w×h px, insets px) → khung đích W×H với insets đích. Mảnh rỗng bỏ. Android vẽ đúng các mảnh này.
    static func patches(imageW w: Int, imageH h: Int, insets s: [Int], width W: Double, height H: Double,
                        dest d: [Double]) -> [Patch] {
        guard s.count == 4, d.count == 4 else { return [] }
        let xs = [0, Double(s[1]), Double(w - s[3]), Double(w)], ys = [0, Double(s[0]), Double(h - s[2]), Double(h)]
        let dx = [0, d[1], W - d[3], W], dy = [0, d[0], H - d[2], H]
        var out: [Patch] = []
        for j in 0..<3 {
            for i in 0..<3 {
                let src = CGRect(x: xs[i], y: ys[j], width: xs[i + 1] - xs[i], height: ys[j + 1] - ys[j])
                let dst = CGRect(x: dx[i], y: dy[j], width: dx[i + 1] - dx[i], height: dy[j + 1] - dy[j])
                if src.width > 0, src.height > 0, dst.width > 0, dst.height > 0 { out.append(Patch(src: src, dst: dst)) }
            }
        }
        return out
    }

    /// CALayer.contentsCenter (đơn vị 0…1) cho insets px trên ảnh w×h.
    static func contentsCenter(_ s: [Int], w: Int, h: Int) -> CGRect {
        guard s.count == 4, w > 0, h > 0 else { return CGRect(x: 0, y: 0, width: 1, height: 1) }
        let W = CGFloat(w), H = CGFloat(h)
        let cw = max(W - CGFloat(s[1] + s[3]), 1), ch = max(H - CGFloat(s[0] + s[2]), 1)
        return CGRect(x: CGFloat(s[1]) / W, y: CGFloat(s[0]) / H, width: cw / W, height: ch / H)
    }
}

// MARK: - Kho (App Group ThemeAssets/ + index.json)

enum ThemeAssetStore {
    static let dirName = "ThemeAssets"
    static let indexName = "index.json"
    static let indexMaxBytes = 256 * 1024

    struct Entry: Codable, Equatable {
        /// Tên tệp đã xử lý: "<sha256 tệp tải về>.<lớp>.<đuôi>".
        var file: String
        /// Cỡ đã lưu (px; phông = 0).
        var w: Int
        var h: Int
        /// Cỡ ảnh gốc (px) — slice tính theo cỡ này.
        var sw: Int
        var sh: Int
        /// Cảnh báo lưu kèm ("missingVietnamese", "foregroundCoverage") — trình sửa hiện.
        var warn: String?
    }
    private struct IndexFile: Codable { var v: Int; var entries: [String: Entry] }

    /// Test: thư mục tạm thay App Group.
    nonisolated(unsafe) static var dirOverride: URL?

    static var defaultDir: URL? {
        if let dirOverride { return dirOverride }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppFlavor.appGroup)?
            .appendingPathComponent(dirName, isDirectory: true)
    }

    static let fileExts: [ThemeAssetClass: Set<String>] = [.font: ["ttf", "otf"], .screen: ["jpg", "png"], .key: ["jpg", "png"]]

    static func fileName(sha256: String, cls: ThemeAssetClass, ext: String) -> String { "\(sha256).\(cls.rawValue).\(ext)" }

    /// Chỉ tên do app đặt (64 hex . lớp . đuôi) — mục lục hỏng / bị sửa không trỏ ra ngoài thư mục được.
    static func validFileName(_ n: String) -> Bool {
        let p = n.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard p.count == 3, ThemeAssetURL.sha256(p[0]) == p[0], let c = ThemeAssetClass(rawValue: p[1]),
              fileExts[c]?.contains(p[2]) == true else { return false }
        return true
    }

    static func readIndex(_ dir: URL?) -> [String: Entry] {
        guard let dir else { return [:] }
        let url = dir.appendingPathComponent(indexName)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int, size <= indexMaxBytes,
              let data = try? Data(contentsOf: url),
              let f = try? JSONDecoder().decode(IndexFile.self, from: data), f.v == 1 else { return [:] }
        return f.entries.filter { validFileName($0.value.file) && $0.value.w >= 0 && $0.value.h >= 0 }
    }

    static func writeIndex(_ m: [String: Entry], _ dir: URL) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        try enc.encode(IndexFile(v: 1, entries: m)).write(to: dir.appendingPathComponent(indexName), options: .atomic)
    }

    /// Tệp kế hoạch cần mà chưa có (mục lục thiếu hoặc tệp mất).
    static func missing(_ plan: ThemeAssetPlan, index: [String: Entry], dir: URL?) -> [ThemeAssetFile] {
        plan.files.filter { f in
            guard let e = index[f.key], let dir else { return true }
            return !FileManager.default.fileExists(atPath: dir.appendingPathComponent(e.file).path)
        }
    }

    /// Khoá mục lục mọi theme còn tham chiếu (kho theme tự tạo + bản vá theme có sẵn — kể cả theme không chọn).
    static func referencedKeys(specs: [ThemeSpec], styles: [KeyStyle]) -> Set<String> {
        var s = Set<String>()
        for a in specs.map(\.assets) + styles.map(\.assets) where !a.isEmpty {
            for f in ThemeAssetPlan.make(a).files { s.insert(f.key) }
            // Skin không vai nào dùng (không xảy ra với bộ khoá hiện tại) vẫn giữ — kế hoạch đã phủ.
        }
        return s
    }

    /// Dọn (thuần): bỏ mục lục không còn tham chiếu; xoá tệp không mục nào trỏ tới (kể cả tệp lạ).
    static func gcPlan(index: [String: Entry], referenced: Set<String>, files: [String])
        -> (index: [String: Entry], delete: [String]) {
        let keep = index.filter { referenced.contains($0.key) }
        let live = Set(keep.values.map(\.file))
        let del = files.filter { $0 != indexName && !live.contains($0) }.sorted()
        return (keep, del)
    }

    /// Dọn thật (APP gọi sau lưu / xoá / dán / khôi phục, và lúc khởi động).
    @discardableResult
    static func collectGarbage(dir: URL?, referenced: Set<String>) -> [String] {
        guard let dir, let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return [] }
        let idx = readIndex(dir)
        let p = gcPlan(index: idx, referenced: referenced, files: files)
        if p.index != idx { try? writeIndex(p.index, dir) }
        for f in p.delete { try? FileManager.default.removeItem(at: dir.appendingPathComponent(f)) }
        return p.delete
    }
}

// MARK: - Bàn phím: nạp (giải MỘT lần mỗi theme, dùng chung ảnh)

/// Ảnh / phông đã giải cho theme đang hiện. Skin cùng ảnh ⇒ CÙNG đối tượng CGImage.
final class LoadedThemeAssets {
    struct Skin {
        let normal: CGImage
        let pressed: CGImage?
        /// Insets theo px ẢNH GIẢI (normal), [t,l,b,r]; nil = căng cả ảnh.
        let insets: [Int]?
        /// Chiều cao ảnh gốc (px) — hệ số đích = chiều cao phím / srcH.
        let srcH: Int
    }
    let signature: String
    let font: CTFontDescriptor?
    let skins: [String: Skin]
    /// Ảnh nền / tiền cảnh (file đã xử lý) — giải theo cỡ view, ngoài main (loadScreen).
    let backgroundURL: URL?
    let foregroundURL: URL?

    init(signature: String, font: CTFontDescriptor?, skins: [String: Skin], backgroundURL: URL?, foregroundURL: URL?) {
        self.signature = signature; self.font = font; self.skins = skins
        self.backgroundURL = backgroundURL; self.foregroundURL = foregroundURL
    }

    /// Byte bitmap skin (mỗi CGImage đếm một lần).
    var skinBytes: Int {
        var seen = Set<ObjectIdentifier>(), n = 0
        for s in skins.values {
            for img in [s.normal, s.pressed].compactMap({ $0 }) where seen.insert(ObjectIdentifier(img)).inserted {
                n += img.bytesPerRow * img.height
            }
        }
        return n
    }
}

enum ThemeAssetLoader {
    nonisolated(unsafe) private static var cache: LoadedThemeAssets?
    #if DEBUG
    /// Test: số lần giải thật (cache trúng không tăng).
    nonisolated(unsafe) static var loadCount = 0
    #endif

    /// Theme không có tệp tải về ⇒ nil, 0 việc (không đọc mục lục). Cùng chữ ký ⇒ bản cache.
    static func load(_ plan: ThemeAssetPlan, dir: URL? = ThemeAssetStore.defaultDir) -> LoadedThemeAssets? {
        guard !plan.isEmpty else { cache = nil; return nil }
        // mtime mục lục: app vừa tải xong ⇒ lần hiện kế nạp lại (một stat, chỉ theme có tệp).
        let stamp = dir.flatMap { try? FileManager.default.attributesOfItem(atPath: $0.appendingPathComponent(ThemeAssetStore.indexName).path)[.modificationDate] as? Date }?.timeIntervalSince1970 ?? 0
        let sig = plan.signature + "|" + (dir?.path ?? "") + "|\(stamp)"
        if let c = cache, c.signature == sig { return c }
        cache = nil                                   // nhả bộ cũ TRƯỚC khi giải bộ mới
        #if DEBUG
        loadCount += 1
        #endif
        let index = ThemeAssetStore.readIndex(dir)
        func file(_ cls: ThemeAssetClass, _ r: ThemeAssetRef?) -> (URL, ThemeAssetStore.Entry)? {
            guard let r, let dir, let e = index[ThemeAssetFile(cls: cls, ref: r).key] else { return nil }
            let u = dir.appendingPathComponent(e.file)
            return FileManager.default.fileExists(atPath: u.path) ? (u, e) : nil
        }
        // Phông: mô tả từ tệp (không đăng ký toàn hệ thống).
        let font = file(.font, plan.font).flatMap { fontDescriptor(at: $0.0) }
        // Skin: gom vai theo ảnh ⇒ cạnh giải = lớn nhất các vai cần; mỗi ảnh giải một lần.
        var roles: [ThemeAssetRef: Set<String>] = [:]
        for (role, s) in plan.skins {
            roles[s.image, default: []].insert(role)
            if let p = s.pressed { roles[p, default: []].insert(role) }
        }
        var decoded: [ThemeAssetRef: (CGImage, ThemeAssetStore.Entry)] = [:]
        for (ref, rs) in roles {
            guard let (u, e) = file(.key, ref),
                  let img = Wallpaper.downsample(url: u, maxPixel: ThemeAssetLimits.keyDecodeEdge(roles: rs)) else { continue }
            decoded[ref] = (img, e)
        }
        var skins: [String: LoadedThemeAssets.Skin] = [:]
        for (role, s) in plan.skins {
            guard let (img, e) = decoded[s.image] else { continue }   // thiếu ảnh ⇒ màu theme
            let ins = s.slice.map { NineSlice.scale($0, fromW: e.sw, fromH: e.sh, toW: img.width, toH: img.height) }
            skins[role] = .init(normal: img, pressed: s.pressed.flatMap { decoded[$0]?.0 }, insets: ins, srcH: max(e.sh, 1))
        }
        let out = LoadedThemeAssets(signature: sig, font: font, skins: skins,
                                    backgroundURL: file(.screen, plan.background)?.0,
                                    foregroundURL: file(.screen, plan.foreground)?.0)
        cache = out
        return out
    }

    static func dropCache() { cache = nil }

    /// Mô tả CoreText từ tệp phông (KHÔNG đăng ký toàn hệ thống — không tra theo tên PostScript; CTFont tạo từ
    /// mô tả này dùng đúng tệp). Tệp hỏng ⇒ nil.
    static func fontDescriptor(at url: URL) -> CTFontDescriptor? {
        (CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor])?.first
    }

    /// Phông tải về `font` đã có trong kho (mục lục + tệp) ⇒ mô tả; chưa tải / thiếu tệp / hỏng ⇒ nil.
    /// Ô xem trước trong APP dùng (cùng tệp với bàn phím) — bàn phím đi đường `load` (cache theo chữ ký).
    static func fontDescriptor(_ font: ThemeFontAsset?, dir: URL? = ThemeAssetStore.defaultDir) -> CTFontDescriptor? {
        guard let font, let dir, let e = ThemeAssetStore.readIndex(dir)[ThemeAssetFile(cls: .font, ref: font.ref).key]
        else { return nil }
        let u = dir.appendingPathComponent(e.file)
        guard FileManager.default.fileExists(atPath: u.path) else { return nil }
        return fontDescriptor(at: u)
    }

    /// Ảnh nền theme (aspect-fill, cắt đúng cỡ view) / tiền cảnh (căng — giải ở cỡ view) — gọi trên
    /// Wallpaper.queue. Bitmap ≤ cỡ view × scale giải (≤ 2).
    static func loadScreen(_ url: URL, viewSize: CGSize, scale: CGFloat, fill: Bool) -> UIImage? {
        let target = CGSize(width: (viewSize.width * scale).rounded(), height: (viewSize.height * scale).rounded())
        guard target.width >= 1, target.height >= 1 else { return nil }
        let px = Int(max(target.width, target.height))
        guard let img = Wallpaper.downsample(url: url, maxPixel: px) else { return nil }
        let cg = fill ? (Wallpaper.aspectFillCrop(img, to: target) ?? img) : img
        return UIImage(cgImage: cg, scale: scale, orientation: .up)
    }
}

// MARK: - Phông tải về có sẵn (themes/builtin-fonts.json → BuiltinFonts.swift)

/// ~12 phông OFL có đủ tiếng Việt, host viettelex.com/fonts kèm sha256 (lưới chọn phông). Đọc một lần.
enum BuiltinFonts {
    struct Entry: Equatable {
        let id: String
        let name: String
        let ref: ThemeAssetRef
        let bytes: Int
        var asset: ThemeFontAsset { ThemeFontAsset(name: name, ref: ref) }
    }

    static let list: [Entry] = parse(BuiltinFontsData.json)

    static func parse(_ text: String) -> [Entry] {
        guard let root = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              let arr = root["fonts"] as? [[String: Any]] else { return [] }
        return arr.compactMap { d in
            guard let id = d["id"] as? String, let name = d["name"] as? String, let url = d["url"] as? String,
                  ThemeAssetURL.isValid(url, font: true), let sha = (d["sha256"] as? String).flatMap(ThemeAssetURL.sha256),
                  let bytes = d["bytes"] as? Int else { return nil }
            return Entry(id: id, name: name, ref: ThemeAssetRef(url: url, sha256: sha), bytes: bytes)
        }
    }

    /// Cỡ đã biết của tệp (phông có sẵn) — câu hỏi trước khi tải ước lượng KB.
    static func knownBytes(_ r: ThemeAssetRef) -> Int? { list.first { $0.ref == r }?.bytes }
}
