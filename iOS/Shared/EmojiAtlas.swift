// EmojiAtlas — emoji vẽ sẵn thành ảnh (RAM-AUDIT.md §4b, 14/10/2026).
//
// Vấn đề: mỗi emoji KHÁC NHAU bàn phím vẽ bằng chữ để lại ~8,5 KB trong cache glyph Apple Color
// Emoji của CoreText, suốt đời process, không API nào xả ⇒ bảng emoji 51–65 MB, sát trần jetsam.
// Cách sửa: APP CHỦ (không giới hạn RAM như extension) vẽ mọi emoji một lần thành trang ảnh PNG
// trong App Group; bàn phím chỉ giải mã ảnh (ImageIO) — bitmap nhả được khi rời bảng emoji.
//
// Bố cục trong App Group:
//   EmojiAtlas/current            tên thư mục bản dựng đang dùng (ghi SAU CÙNG, đổi nguyên tử)
//   EmojiAtlas/b<uuid>/manifest.json   EmojiAtlasManifest (iOS build, scale, cỡ chữ, hash dữ liệu)
//   EmojiAtlas/b<uuid>/index.bin       chuỗi emoji → (trang, ô) — mmap, tra nhị phân, 0 heap
//   EmojiAtlas/b<uuid>/<nhóm>-<n>.png  trang `cols` × ≤`rowsPerPage` ô vuông `slotPx` px
// Mỗi bản dựng một thư mục riêng ⇒ bàn phím đang giữ bản cũ không bao giờ đọc nhầm trang của
// bản mới (trang bị xoá thì trả nil ⇒ ô đó vẽ chữ như cũ).
//
// index.bin (little-endian): "VTA1" | u32 n | u32 off[n+1] | n × (u16 page, u16 slot) | utf8 —
// sort theo byte UTF-8 (so sánh từ điển, ngắn hơn đứng trước khi là tiền tố).
//
// Khoá là CHUỖI emoji (không phải id trong emoji.bin): id đổi khi dữ liệu sinh lại; chuỗi thì
// không — Recents / tông da / kết quả tìm đều tra được.
import CoreGraphics
import Foundation
import ImageIO
import UIKit

enum EmojiAtlas {
    static let appGroup = AppFlavor.appGroup
    static let format = 1
    /// Ô vuông / trang: 8 × 4 = 32 emoji/trang — trang nhỏ ⇒ giải mã một trang ~1 ms và Recents
    /// (rải nhiều trang) không phải giữ nhiều trang to.
    static let cols = 8
    static let rowsPerPage = 4

    /// Test: thư mục atlas thay App Group.
    nonisolated(unsafe) static var rootOverride: URL?

    static var defaultRoot: URL? {
        if let rootOverride { return rootOverride }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent("EmojiAtlas", isDirectory: true)
    }

    /// Cỡ chữ (pt) vẽ atlas = glyph LỚN NHẤT lưới dùng trên loại máy này (EmojiGridMetrics:
    /// iPhone 34 dọc / 32 ngang, iPad 52). Cỡ nhỏ hơn (ngang, popup tông 26, kết quả tìm 28) thu
    /// nhỏ ảnh — nét vẫn sắc. Test khoá: EmojiAtlasTests.testPointSizeMatchesGridMetrics.
    static func pointSize(pad: Bool) -> CGFloat { pad ? 52 : 34 }

    /// Cạnh ô (px) cho cỡ chữ + scale: glyph Apple Color Emoji bbox ≈ 0,917 × cỡ chữ ⇒ ô = cỡ chữ.
    static func slotPx(pointSize: CGFloat, scale: CGFloat) -> Int { Int((pointSize * scale).rounded(.up)) }

    /// iOS build (đổi font emoji có thể đi kèm bản vá) — "Version 27.0 (Build 24A…)".
    static var osBuild: String { ProcessInfo.processInfo.operatingSystemVersionString }

    /// Khoá mà bàn phím / app mong đợi trên máy này.
    static func expectedKey(scale: CGFloat, pad: Bool) -> EmojiAtlasManifest.Key {
        EmojiAtlasManifest.Key(format: format, os: osBuild, scale: Double(scale),
                               pointSize: Double(pointSize(pad: pad)), dataHash: EmojiData.dataHash)
    }

    /// Bàn phím: mở atlas hợp lệ (nil ⇒ vẽ chữ như cũ). Chỉ gọi từ UI emoji — không bao giờ
    /// trên đường gõ.
    static func loadForKeyboard(scale: CGFloat, pad: Bool) -> EmojiAtlasStore? {
        guard let root = defaultRoot else { return nil }
        return EmojiAtlasStore.load(root: root, expected: expectedKey(scale: scale, pad: pad))
    }
}

struct EmojiAtlasManifest: Codable, Equatable {
    struct Key: Equatable {
        var format: Int
        var os: String
        var scale: Double
        var pointSize: Double
        var dataHash: String
    }

    var format: Int
    var os: String
    var scale: Double
    var pointSize: Double
    var dataHash: String
    var slotPx: Int
    var cols: Int
    var pageFiles: [String]
    var pageRows: [Int]
    var count: Int

    var key: Key { Key(format: format, os: os, scale: scale, pointSize: pointSize, dataHash: dataHash) }

    /// nil = dùng được; khác = lý do phải dựng lại (app) / bỏ qua (bàn phím).
    static func staleReason(_ m: EmojiAtlasManifest?, expected k: Key) -> String? {
        guard let m else { return "missing" }
        if m.format != k.format { return "format" }
        if m.os != k.os { return "os" }
        if m.scale != k.scale { return "scale" }
        if m.pointSize != k.pointSize { return "size" }
        if m.dataHash != k.dataHash { return "data" }
        if m.pageFiles.count != m.pageRows.count || m.slotPx <= 0 || m.cols <= 0 { return "corrupt" }
        return nil
    }

    static func read(buildDir: URL) -> EmojiAtlasManifest? {
        guard let d = try? Data(contentsOf: buildDir.appendingPathComponent("manifest.json")) else { return nil }
        return try? JSONDecoder().decode(EmojiAtlasManifest.self, from: d)
    }

    /// Thư mục bản dựng hiện hành (theo con trỏ `current`).
    static func currentBuildDir(root: URL) -> URL? {
        guard let s = try? String(contentsOf: root.appendingPathComponent("current"), encoding: .utf8)
        else { return nil }
        let name = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.contains("/"), !name.hasPrefix(".") else { return nil }
        return root.appendingPathComponent(name, isDirectory: true)
    }
}

/// index.bin: ghi (app) + tra (bàn phím, mmap).
struct EmojiAtlasIndex {
    struct Entry { let emoji: String; let page: Int; let slot: Int }

    static func encode(_ entries: [Entry]) -> Data {
        // Trùng chuỗi: giữ mục đầu (một chuỗi chỉ một chỗ).
        var seen = Set<String>()
        let uniq = entries.filter { seen.insert($0.emoji).inserted }
        let sorted = uniq.map { (Array($0.emoji.utf8), $0.page, $0.slot) }
            .sorted { $0.0.lexicographicallyPrecedes($1.0) }
        var d = Data("VTA1".utf8)
        func u32(_ v: Int) { var x = UInt32(v).littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
        func u16(_ v: Int) { var x = UInt16(v).littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
        u32(sorted.count)
        var off = 0
        for e in sorted { u32(off); off += e.0.count }
        u32(off)
        for e in sorted { u16(e.1); u16(e.2) }
        for e in sorted { d.append(contentsOf: e.0) }
        return d
    }

    let data: Data
    let count: Int
    private let offBase = 8
    private var locBase: Int { offBase + (count + 1) * 4 }
    private var strBase: Int { locBase + count * 4 }

    init?(data: Data) {
        guard data.count >= 12, data.prefix(4).elementsEqual("VTA1".utf8) else { return nil }
        self.data = data
        count = Int(UInt32(littleEndian: data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: UInt32.self) }))
        let need = 8 + (count + 1) * 4 + count * 4
        guard data.count >= need else { return nil }
        let strLen = Int(UInt32(littleEndian: data.withUnsafeBytes {
            $0.loadUnaligned(fromByteOffset: 8 + count * 4, as: UInt32.self) }))
        guard data.count == need + strLen else { return nil }
    }

    func locate(_ emoji: String) -> (page: Int, slot: Int)? {
        var key = emoji
        return key.withUTF8 { q -> (Int, Int)? in
            data.withUnsafeBytes { raw -> (Int, Int)? in
                func u32(_ o: Int) -> Int { Int(UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: o, as: UInt32.self))) }
                func u16(_ o: Int) -> Int { Int(UInt16(littleEndian: raw.loadUnaligned(fromByteOffset: o, as: UInt16.self))) }
                let sb = strBase
                var lo = 0, hi = count - 1
                while lo <= hi {
                    let mid = (lo + hi) / 2
                    let s = sb + u32(offBase + mid * 4), e = sb + u32(offBase + mid * 4 + 4)
                    let n = min(e - s, q.count)
                    var c = n > 0 ? memcmp(raw.baseAddress! + s, q.baseAddress!, n) : 0
                    if c == 0 { c = Int32(clamping: (e - s) - q.count) }
                    if c == 0 { return (u16(locBase + mid * 4), u16(locBase + mid * 4 + 2)) }
                    if c < 0 { lo = mid + 1 } else { hi = mid - 1 }
                }
                return nil
            }
        }
    }
}

/// Atlas đã kiểm hợp lệ, chỉ dùng trên main thread (UI bàn phím). Trang giải mã lười, giữ tối
/// đa `maxPages` (LRU); mỗi ô nhận BẢN SAO riêng (~cạnh² × 4 B, 102 px ≈ 41 KB) chứ không giữ
/// cả trang — Recents rải 30 trang cũng chỉ tốn 30 ô. Rời bảng emoji / cảnh báo bộ nhớ:
/// `EmojiData.dropCaches()` → `release()`.
final class EmojiAtlasStore {
    nonisolated(unsafe) private(set) static var current: EmojiAtlasStore?

    /// Mở (hoặc dùng lại) atlas hợp lệ cho `expected`; nil nếu chưa có / cũ / hỏng.
    static func load(root: URL, expected: EmojiAtlasManifest.Key) -> EmojiAtlasStore? {
        if let c = current, c.manifest.key == expected, c.root == root { return c }
        current = EmojiAtlasStore(root: root, expected: expected)
        return current
    }

    /// Nhả trang đã giải mã + bỏ tham chiếu tĩnh (ô đang hiện vẫn giữ ảnh của nó).
    static func release() {
        current?.dropPages()
        current = nil
    }

    let root: URL
    let dir: URL
    let manifest: EmojiAtlasManifest
    private let index: EmojiAtlasIndex
    /// Trang đang xem + trang kề hai bên (đã giải mã trước ở nền) + một trang dự phòng.
    static let maxPages = 4
    /// Giải mã trước trang kề (lướt ngang theo thứ tự trang) ở nền — main thread hầu như chỉ trúng
    /// cache. Tắt trong test cần đếm trang đồng bộ.
    var prefetchAdjacent = true
    private var inflight = Set<Int>()
    private var pages: [(page: Int, image: CGImage)] = []
    private(set) var pageDecodes = 0

    init?(root: URL, expected: EmojiAtlasManifest.Key) {
        guard let dir = EmojiAtlasManifest.currentBuildDir(root: root),
              let m = EmojiAtlasManifest.read(buildDir: dir),
              EmojiAtlasManifest.staleReason(m, expected: expected) == nil,
              let d = try? Data(contentsOf: dir.appendingPathComponent("index.bin"), options: .alwaysMapped),
              let idx = EmojiAtlasIndex(data: d)
        else { return nil }
        self.root = root
        self.dir = dir
        manifest = m
        index = idx
    }

    var scale: CGFloat { CGFloat(manifest.scale) }
    var pointSize: CGFloat { CGFloat(manifest.pointSize) }
    /// Cạnh ô (pt) khi vẽ ở `pointSize`; vẽ ở cỡ `f` thì cạnh = sidePoints × f / pointSize.
    var sidePoints: CGFloat { CGFloat(manifest.slotPx) / scale }
    func side(forFont f: CGFloat) -> CGFloat { sidePoints * f / pointSize }

    func contains(_ e: String) -> Bool { index.locate(e) != nil }

    /// Ảnh riêng của một emoji (bản sao, không dính trang) — nil ⇒ vẽ chữ.
    func tile(_ e: String) -> CGImage? {
        guard let loc = index.locate(e), let page = pageImage(loc.page) else { return nil }
        let s = manifest.slotPx
        let r = CGRect(x: (loc.slot % manifest.cols) * s, y: (loc.slot / manifest.cols) * s, width: s, height: s)
        guard let crop = page.cropping(to: r),
              let ctx = CGContext(data: nil, width: s, height: s, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: page.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.draw(crop, in: CGRect(x: 0, y: 0, width: s, height: s))
        return ctx.makeImage()
    }

    func tileImage(_ e: String) -> UIImage? {
        tile(e).map { UIImage(cgImage: $0, scale: scale, orientation: .up) }
    }

    func pageImage(_ p: Int) -> CGImage? {
        if let i = pages.firstIndex(where: { $0.page == p }) {
            let hit = pages.remove(at: i)
            pages.append(hit)
            return hit.image
        }
        guard p >= 0, p < manifest.pageFiles.count,
              let img = Self.decode(dir.appendingPathComponent(manifest.pageFiles[p])) else { return nil }
        pageDecodes += 1
        insert(p, img)
        if prefetchAdjacent { prefetch(p + 1); prefetch(p - 1) }
        return img
    }

    private func insert(_ p: Int, _ img: CGImage) {
        pages.removeAll { $0.page == p }
        pages.append((p, img))
        if pages.count > Self.maxPages { pages.removeFirst(pages.count - Self.maxPages) }
    }

    private func prefetch(_ p: Int) {
        guard p >= 0, p < manifest.pageFiles.count, !inflight.contains(p),
              !pages.contains(where: { $0.page == p }) else { return }
        inflight.insert(p)
        let url = dir.appendingPathComponent(manifest.pageFiles[p])
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let img = Self.decode(url)
            DispatchQueue.main.async {
                guard let self, self.inflight.remove(p) != nil, let img else { return }
                self.pageDecodes += 1
                // Chèn ở ĐẦU (cũ nhất): trang đang xem không bị đẩy ra trước trang đoán trước.
                if !self.pages.contains(where: { $0.page == p }), self.pages.count < Self.maxPages {
                    self.pages.insert((p, img), at: 0)
                } else if !self.pages.contains(where: { $0.page == p }) {
                    self.pages[0] = (p, img)
                }
            }
        }
    }

    static func decode(_ url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        // Giải mã NGAY, buffer thuộc CGImage (nhả cùng CGImage) — không giải mã lại lúc vẽ.
        return CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }

    /// Nhả trang; giải mã nền đang bay sẽ bị bỏ khi về.
    func dropPages() { pages.removeAll(); inflight.removeAll() }
    var cachedPageCount: Int { pages.count }
}
