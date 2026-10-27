import UIKit
import ImageIO
import UniformTypeIdentifiers
import CoreImage

/// Ảnh nền bàn phím. App chọn ảnh (PhotosPicker) → giữ bản gốc ≤2048px (chưa mờ,
/// container RIÊNG của app) + khung cắt `WallpaperCrop` (ThemeSettings) → "nướng" sẵn
/// đúng VÙNG CẮT, thu ≤1080px cạnh dài, áp mờ, nén JPEG ~200–400KB → `wallpaper.jpg`
/// trong App Group. Extension CHỈ đọc file đã cắt: giải bằng ImageIO thumbnail ở đúng
/// cỡ hiển thị (không bao giờ giải bản gốc — RAM extension ~48–60MB). ImageIO không giải
/// được một vùng, nên cắt ở app là cách để extension chỉ giải đúng phần hiện.
enum Wallpaper {
    static let fileName = "wallpaper.jpg"
    static let maxEdge = 1080
    static let maxBytes = 400_000
    /// Bản gốc giữ để chỉnh khung (kéo/zoom) về sau — cạnh dài ≤ chừng này.
    static let sourceMaxEdge = 2048

    static var url: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppFlavor.appGroup)?
            .appendingPathComponent(fileName)
    }

    /// Thu nhỏ bằng ImageIO (không giải ảnh gốc vào RAM). Cạnh dài ≤ maxPixel.
    static func downsample(source: CGImageSource, maxPixel: Int) -> CGImage? {
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,   // xoay theo EXIF
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, opts as CFDictionary)
    }

    static func downsample(data: Data, maxPixel: Int) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData,
                [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        return downsample(source: src, maxPixel: maxPixel)
    }

    static func downsample(url: URL, maxPixel: Int) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL,
                [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        return downsample(source: src, maxPixel: maxPixel)
    }

    /// Mờ Gauss (app, lúc lưu) — bàn phím chỉ hiện ảnh đã mờ sẵn, không tốn gì.
    static func blurred(_ img: CGImage, radius: Int) -> CGImage {
        guard radius > 0 else { return img }
        let ci = CIImage(cgImage: img).clampedToExtent()
            .applyingGaussianBlur(sigma: Double(radius))
            .cropped(to: CGRect(x: 0, y: 0, width: img.width, height: img.height))
        return CIContext(options: [.useSoftwareRenderer: false])
            .createCGImage(ci, from: ci.extent) ?? img
    }

    /// JPEG ≤ maxBytes: hạ chất lượng dần 0.8 → 0.4.
    static func encodeJPEG(_ img: CGImage, maxBytes: Int = maxBytes) -> Data? {
        var out: Data?
        for q in stride(from: 0.8, through: 0.4, by: -0.1) {
            let data = NSMutableData()
            guard let dst = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)
            else { return nil }
            CGImageDestinationAddImage(dst, img, [kCGImageDestinationLossyCompressionQuality: q] as CFDictionary)
            guard CGImageDestinationFinalize(dst) else { return nil }
            out = data as Data
            if data.length <= maxBytes { break }
        }
        return out
    }

    /// Toàn bộ pipeline của app: ảnh gốc → JPEG nhỏ sẵn cho bàn phím.
    static func prepare(original: Data, blur: Int) -> Data? {
        guard let small = downsample(data: original, maxPixel: maxEdge) else { return nil }
        return encodeJPEG(blurred(small, radius: blur))
    }

    /// Bản gốc để lưu (≤ sourceMaxEdge, đã xoay EXIF, chưa mờ) — JPEG chất lượng cao.
    static func encodeSource(_ img: CGImage) -> Data? {
        encodeJPEG(img, maxBytes: 1_500_000)
    }

    /// Ảnh cho bàn phím từ bản gốc + khung cắt: cắt vùng `crop` (nil = cả ảnh — ảnh cũ
    /// chưa có khung, bàn phím tự cắt giữa như trước), thu ≤ maxEdge, mờ. Bitmap MỚI
    /// (không chia bộ nhớ với bản gốc).
    static func render(source: CGImage, crop: WallpaperCrop?, blur: Int) -> CGImage? {
        var rect = CGRect(x: 0, y: 0, width: source.width, height: source.height)
        if let crop { rect = crop.pixelRect(imageWidth: source.width, imageHeight: source.height) }
        let k = min(1, CGFloat(maxEdge) / max(rect.width, rect.height))
        let w = max(Int((rect.width * k).rounded()), 1), h = max(Int((rect.height * k).rounded()), 1)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
                                      | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        ctx.interpolationQuality = .high
        // CGContext gốc dưới-trái; rect tính từ trên-trái của ảnh. Scale theo từng trục
        // để khớp đúng w×h nguyên (làm tròn không kéo lệch tỉ lệ thấy được).
        let kx = CGFloat(w) / rect.width, ky = CGFloat(h) / rect.height
        ctx.draw(source, in: CGRect(x: -rect.minX * kx, y: -(CGFloat(source.height) - rect.maxY) * ky,
                                    width: CGFloat(source.width) * kx, height: CGFloat(source.height) * ky))
        guard let cut = ctx.makeImage() else { return nil }
        return blurred(cut, radius: blur)
    }

    /// render + nén: JPEG sẵn cho App Group.
    static func prepare(source: CGImage, crop: WallpaperCrop?, blur: Int) -> Data? {
        render(source: source, crop: crop, blur: blur).flatMap { encodeJPEG($0) }
    }

    /// Strip gợi ý mở ở mức Thấp (KeyboardView.openStrip).
    static let suggestionStrip: CGFloat = 34

    /// Strip gợi ý mở như KeyboardView.openStripNow: iPhone theo bàn phím gốc (stock), cộng
    /// "Chiều cao thanh gợi ý" (SuggestionBarHeight.delta; iPhone ngang kẹp ở Vừa).
    static func openStrip(width: CGFloat, pad: Bool, landscape: Bool, stock: Bool,
                          barHeight: SuggestionBarHeight = .defaultValue) -> CGFloat {
        let base = stock
            ? (KeyGeometry.StockSize.openStrip(width: width, landscape: landscape) ?? suggestionStrip)
            : suggestionStrip
        return base + barHeight.delta(landscape: !pad && landscape)
    }

    /// Cỡ (pt) vùng bàn phím mà ảnh nền phủ — cùng công thức KeyboardView.keyAreaHeight
    /// + strip gợi ý (mở; trạng thái thu gọn nằm trong container riêng của extension, app
    /// không đọc được) + "Nâng bàn phím" (đệm dưới hàng đáy, ảnh nền phủ luôn phần đó).
    /// Bề ngang: dọc = cạnh ngắn màn hình, ngang = cạnh dài. iPhone: bước hàng/khe/strip theo
    /// số đo bàn phím gốc + chỉnh tay (KeyGeometry.rowSpec).
    static func keyboardSize(screenSize: CGSize, pad: Bool, landscape: Bool, rowHeightAdjust: Int,
                             numberRow: Bool, suggestions: Bool, raise: Int = 0,
                             numberRowFullHeight: Bool = false,
                             barHeight: SuggestionBarHeight = .defaultValue) -> CGSize {
        let width = landscape ? max(screenSize.width, screenSize.height) : min(screenSize.width, screenSize.height)
        let base: CGFloat = pad ? (landscape ? 300 : 240) : (landscape ? 162 : KeyGeometry.phonePortraitBase)
        let spec = KeyGeometry.rowSpec(pad: pad, landscape: landscape, unfolded: false, width: width,
                                       base: base, adjust: CGFloat(rowHeightAdjust))
        let strip = openStrip(width: width, pad: pad, landscape: landscape, stock: spec.stock, barHeight: barHeight)
        return CGSize(width: width, height: spec.keyArea(numberRow: numberRow, fullHeight: numberRowFullHeight) + (suggestions ? strip : 0)
                          + CGFloat(KeyGeometry.RowAdjust.clampRaise(raise)))
    }

    static func aspect(_ size: CGSize) -> Double {
        size.width > 0 && size.height > 0 ? Double(size.width / size.height) : 1.4
    }

    /// Cạnh dài cần giải cho view w×h pt (aspect-fill): ảnh phải phủ kín view,
    /// không lớn hơn bản đã lưu (maxEdge).
    static func displayMaxPixel(viewSize: CGSize, scale: CGFloat, imageAspect: CGFloat) -> Int {
        guard viewSize.width > 0, viewSize.height > 0, imageAspect > 0 else { return maxEdge }
        let w = viewSize.width * scale, h = viewSize.height * scale
        // aspect-fill: cạnh ngắn của ảnh ≥ cạnh tương ứng của view.
        let needW = max(w, h * imageAspect)          // bề ngang ảnh cần
        let needH = needW / imageAspect
        return min(maxEdge, Int(ceil(max(needW, needH))))
    }

    // MARK: extension — cache một ảnh đã giải (controller dựng lại mỗi lần hiện)

    /// Mọi lần giải/cache chạy tuần tự trên queue này (cache không cần khoá).
    static let queue = DispatchQueue(label: "viettelex.wallpaper", qos: .userInitiated)
    nonisolated(unsafe) private static var cache: (key: String, image: UIImage)?

    /// Ảnh cho bàn phím; nil nếu không có file. Cache theo version + cỡ.
    static func loadForKeyboard(version: Double, viewSize: CGSize, scale: CGFloat) -> UIImage? {
        guard let url, FileManager.default.fileExists(atPath: url.path) else { cache = nil; return nil }
        guard let src = CGImageSourceCreateWithURL(url as CFURL,
                [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        var aspect: CGFloat = 1
        if let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
           let pw = props[kCGImagePropertyPixelWidth] as? CGFloat,
           let ph = props[kCGImagePropertyPixelHeight] as? CGFloat, ph > 0 {
            aspect = pw / ph
        }
        let px = displayMaxPixel(viewSize: viewSize, scale: scale, imageAspect: aspect)
        let target = CGSize(width: (viewSize.width * scale).rounded(), height: (viewSize.height * scale).rounded())
        let key = "\(version)|\(px)|\(Int(target.width))x\(Int(target.height))"
        if let c = cache, c.key == key { return c.image }
        cache = nil                     // nhả ảnh cũ TRƯỚC khi giải ảnh mới
        guard let full = downsample(source: src, maxPixel: px) else { return nil }
        // Chỉ giữ phần HIỆN (aspect-fill cắt giữa): ảnh dọc 3:4 trên bàn phím ngang chỉ lộ
        // ~55 % — bitmap giữ lại cỡ đúng view thay vì cả ảnh.
        let cg = aspectFillCrop(full, to: target) ?? full
        let img = UIImage(cgImage: cg, scale: scale, orientation: .up)
        cache = (key, img)
        return img
    }

    /// Vẽ `img` kiểu aspect-fill (căn giữa, cắt phần thừa) vào bitmap MỚI đúng `size` px —
    /// bitmap gốc nhả được ngay (CGImage.cropping chia chung bộ nhớ gốc nên không dùng).
    /// Ảnh gốc hẹp hơn view (phải phóng to mới phủ kín) ⇒ cắt ở ĐỘ PHÂN GIẢI GỐC (bitmap nhỏ
    /// hơn `size`, cùng tỉ lệ; UIImageView aspect-fill tự phóng — không phóng hai lần).
    /// Đúng cỡ sẵn ⇒ trả nil (dùng thẳng ảnh gốc).
    static func aspectFillCrop(_ img: CGImage, to size: CGSize) -> CGImage? {
        guard size.width >= 1, size.height >= 1, img.width > 0, img.height > 0 else { return nil }
        var k = max(size.width / CGFloat(img.width), size.height / CGFloat(img.height))
        var target = size
        if k > 1 { target = CGSize(width: size.width / k, height: size.height / k); k = 1 }
        let w = max(Int(target.width.rounded()), 1), h = max(Int(target.height.rounded()), 1)
        if img.width == w, img.height == h { return nil }
        let dw = CGFloat(img.width) * k, dh = CGFloat(img.height) * k
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
                                      | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(img, in: CGRect(x: (CGFloat(w) - dw) / 2, y: (CGFloat(h) - dh) / 2, width: dw, height: dh))
        return ctx.makeImage()
    }

    static func dropCache() { cache = nil }
    static var hasCache: Bool { cache != nil }

    /// Scale giải ảnh nền cho bàn phím: tối đa @2x (máy @3x giải ở @2x rồi phóng). Nền đã
    /// mờ + phủ tối + thường trong suốt một phần ⇒ mắt không phân biệt, mà bitmap 810×1080
    /// @3x (3,4 MB) còn ~1,5 MB (RAM-AUDIT.md §6).
    static func decodeScale(screenScale: CGFloat) -> CGFloat { min(screenScale, 2) }
}

/// Khung cắt ảnh nền, CHUẨN HOÁ 0…1 theo ảnh gốc đã lưu (đã xoay EXIF): x, y = góc trên-trái.
/// Tỉ lệ (theo px) = tỉ lệ vùng bàn phím DỌC (gồm thanh gợi ý) lúc chỉnh. Không phụ thuộc
/// độ phân giải ⇒ bản gốc thu nhỏ/lưu lại vẫn đúng.
///
/// Bàn phím NGANG: dùng cùng khung, cắt theo tỉ lệ ngang QUANH TÂM khung (`landscape`) —
/// ngang rộng hơn dọc ⇒ giữ nguyên bề ngang, lấy dải giữa; luôn nằm trong khung dọc nên
/// chỉ cần file đã cắt theo khung dọc (bàn phím tự cắt giữa = đúng phép này).
/// Đổi chiều cao bàn phím sau khi chỉnh (hàng số, ±hàng) cũng cắt giữa như vậy.
/// Không có khung (ảnh chọn trước bản này) ⇒ cắt giữa như cũ.
/// Cùng công thức với android/keyboard WallpaperCrop (test hai bên cùng số).
struct WallpaperCrop: Equatable {
    var x: Double, y: Double, w: Double, h: Double
    static let maxZoom: Double = 5

    init(x: Double, y: Double, w: Double, h: Double) { self.x = x; self.y = y; self.w = w; self.h = h }

    init(pixelRect r: CGRect, imageWidth iw: Int, imageHeight ih: Int) {
        let W = Double(max(iw, 1)), H = Double(max(ih, 1))
        self.init(x: Double(r.minX) / W, y: Double(r.minY) / H, w: Double(r.width) / W, h: Double(r.height) / H)
    }

    /// Khung phủ kín (zoom 1) ở giữa ảnh — cũng là mặc định cho ảnh cũ chưa có khung.
    static func cover(imageWidth iw: Int, imageHeight ih: Int, frameAspect a: Double) -> WallpaperCrop {
        make(imageWidth: iw, imageHeight: ih, frameAspect: a, zoom: 1, centerX: 0.5, centerY: 0.5)
    }

    /// Khung tỉ lệ `a` (rộng/cao px), zoom 1…maxZoom (1 = vừa phủ — không bao giờ lộ viền),
    /// tâm (chuẩn hoá) kẹp để khung luôn nằm trong ảnh.
    static func make(imageWidth iw: Int, imageHeight ih: Int, frameAspect a: Double,
                     zoom: Double, centerX: Double, centerY: Double) -> WallpaperCrop {
        let W = Double(max(iw, 1)), H = Double(max(ih, 1))
        let aspect = a > 0 && a.isFinite ? a : 1
        var cw = W, ch = W / aspect           // phủ: chạm hai mép trái-phải…
        if ch > H { ch = H; cw = H * aspect } // …hoặc trên-dưới
        let z = min(max(zoom.isFinite ? zoom : 1, 1), maxZoom)
        let w = cw / z / W, h = ch / z / H
        let cx = min(max(centerX.isFinite ? centerX : 0.5, w / 2), 1 - w / 2)
        let cy = min(max(centerY.isFinite ? centerY : 0.5, h / 2), 1 - h / 2)
        return WallpaperCrop(x: cx - w / 2, y: cy - h / 2, w: w, h: h)
    }

    var centerX: Double { x + w / 2 }
    var centerY: Double { y + h / 2 }

    /// Tỉ lệ px (rộng/cao) của khung trên ảnh iw×ih.
    func aspect(imageWidth iw: Int, imageHeight ih: Int) -> Double {
        (w * Double(iw)) / max(h * Double(ih), 1e-9)
    }

    /// Zoom so với khung phủ cùng tỉ lệ (≥1).
    func zoom(imageWidth iw: Int, imageHeight ih: Int) -> Double {
        let c = Self.cover(imageWidth: iw, imageHeight: ih, frameAspect: aspect(imageWidth: iw, imageHeight: ih))
        return w > 0 ? max(1, c.w / w) : 1
    }

    /// Cùng tâm + zoom, tỉ lệ mới (bàn phím đổi chiều cao rồi mở lại trình chỉnh).
    func refit(imageWidth iw: Int, imageHeight ih: Int, frameAspect a: Double) -> WallpaperCrop {
        Self.make(imageWidth: iw, imageHeight: ih, frameAspect: a, zoom: zoom(imageWidth: iw, imageHeight: ih),
                  centerX: centerX, centerY: centerY)
    }

    /// Khung cho bàn phím NGANG (tỉ lệ `a`): quanh tâm khung dọc, nằm TRONG khung dọc.
    func landscape(imageWidth iw: Int, imageHeight ih: Int, aspect a: Double) -> WallpaperCrop {
        let pw = w * Double(iw), ph = h * Double(ih)
        guard pw > 0, ph > 0, a > 0, iw > 0, ih > 0 else { return self }
        var lw = pw, lh = pw / a
        if lh > ph { lh = ph; lw = ph * a }
        let nw = lw / Double(iw), nh = lh / Double(ih)
        return WallpaperCrop(x: centerX - nw / 2, y: centerY - nh / 2, w: nw, h: nh)
    }

    /// Hình chữ nhật px nguyên trong ảnh iw×ih (kẹp biên, ≥1px).
    func pixelRect(imageWidth iw: Int, imageHeight ih: Int) -> CGRect {
        let W = Double(iw), H = Double(ih)
        let l = min(max(Int((x * W).rounded()), 0), max(iw - 1, 0))
        let t = min(max(Int((y * H).rounded()), 0), max(ih - 1, 0))
        let r = min(max(Int(((x + w) * W).rounded()), l + 1), iw)
        let b = min(max(Int(((y + h) * H).rounded()), t + 1), ih)
        return CGRect(x: l, y: t, width: r - l, height: b - t)
    }

    /// "x,y,w,h" (dấu chấm, 5 số lẻ) — cùng định dạng Android.
    var serialized: String {
        [x, y, w, h].map { String(format: "%.5f", locale: Locale(identifier: "en_US_POSIX"), $0) }
            .joined(separator: ",")
    }

    /// Sai định dạng / ngoài biên ⇒ nil (= cắt giữa như cũ).
    init?(serialized s: String?) {
        guard let s else { return nil }
        let v = s.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard v.count == 4, v.allSatisfy({ $0.isFinite }) else { return nil }
        let eps = 1e-3
        guard v[2] > 0, v[3] > 0, v[0] >= -eps, v[1] >= -eps,
              v[0] + v[2] <= 1 + eps, v[1] + v[3] <= 1 + eps else { return nil }
        let x = max(0, v[0]), y = max(0, v[1])
        self.init(x: x, y: y, w: min(v[2], 1 - x), h: min(v[3], 1 - y))
    }
}
