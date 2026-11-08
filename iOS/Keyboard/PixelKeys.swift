import UIKit

/// Dáng phím "pixel" (theme JSON "keyShape":"pixel" — theme Pixel 8-bit): góc cắt 2 bậc theo KHỐI, viền 1 khối đậm,
/// bóng khối cứng dưới/phải (không mờ, không khử răng cưa); bấm = mặt phím lún 1 khối xuống-phải, mất bóng.
///
/// Hình học THUẦN (`layers` — các dải RỜI NHAU theo hàng khối) giống hệt Android (android/keyboard/.../PixelKeys.kt) — fixture chung
/// KeyboardTests/Fixtures/pixel-key-cases.txt. iOS vẽ bằng ảnh 9-slice TÍ HON (16×16 px, 1 px = 1 khối) dựng MỘT lần
/// mỗi bảng màu rồi dùng chung cho mọi phím cùng vai (skin của KeyButton: đè = đổi con trỏ CGImage, phóng to bằng
/// lọc "nearest" ⇒ khối vuông sắc). Theme khác không chạm tới (0 chi phí).
enum PixelKeys {
    static let shape = "pixel"
    /// Phím cao `cells` khối (mặt 15 + bóng 1) ⇒ khối = chiều cao phím / 16 (≈ 2,7 pt trên iPhone) — góc 2 bậc vẫn
    /// đọc rõ là điểm ảnh mà phím chữ hẹp (~33 pt) không thành viên thuốc.
    static let cells = 16
    /// Vùng giữ nguyên của ảnh 9-slice [t, l, b, r] (khối): phủ trọn bậc góc + bóng ở cả hai trạng thái.
    static let slice = [3, 3, 4, 4]

    struct Rect: Equatable { var l, t, r, b: Double }
    /// Hai vùng RỜI NHAU (không chồng ⇒ màu trong suốt một phần không cộng dồn alpha, khỏi chế độ hoà trộn đặc biệt):
    /// `ink` = viền + bóng (màu viền), `fill` = lõi.
    struct Layers: Equatable {
        var ink: [Rect]
        var fill: [Rect]
    }

    static func block(keyHeight h: Double) -> Double { h / Double(cells) }

    /// Phím điểm ảnh trong khung (l, t, r, b), khối `k`, cắt theo HÀNG khối. Mặt (fl, ft, fr, fb) = khung bớt 1 khối
    /// phải + dưới; bấm: mặt dời 1 khối xuống-phải, không bóng. Hình = mặt cắt góc 2 bậc (∪ chính nó dời (k, k) = bóng);
    /// lõi = hình lõm 1 khối. Mỗi hàng: vùng hình [ul, ur) trừ lõi [xl, xr) ⇒ 1 hoặc 2 dải `ink`. Thứ tự ổn định (fixture).
    static func layers(l: Double, t: Double, r: Double, b: Double, block k: Double, pressed: Bool) -> Layers {
        let d = pressed ? k : 0
        let fl = l + d, ft = t + d, fr = r - k + d, fb = b - k + d
        // (y0, y1, ul, ur, xl?, xr?) — hàng từ trên xuống.
        typealias Row = (Double, Double, Double, Double, Double?, Double?)
        let rows: [Row] = pressed ? [
            (ft, ft + k, fl + 2 * k, fr - 2 * k, nil, nil),
            (ft + k, ft + 2 * k, fl + k, fr - k, fl + 2 * k, fr - 2 * k),
            (ft + 2 * k, fb - 2 * k, fl, fr, fl + k, fr - k),
            (fb - 2 * k, fb - k, fl + k, fr - k, fl + 2 * k, fr - 2 * k),
            (fb - k, fb, fl + 2 * k, fr - 2 * k, nil, nil),
        ] : [
            (ft, ft + k, fl + 2 * k, fr - 2 * k, nil, nil),
            (ft + k, ft + 2 * k, fl + k, fr - k, fl + 2 * k, fr - 2 * k),
            (ft + 2 * k, ft + 3 * k, fl, fr, fl + k, fr - k),
            (ft + 3 * k, fb - 2 * k, fl, fr + k, fl + k, fr - k),
            (fb - 2 * k, fb - k, fl + k, fr + k, fl + 2 * k, fr - 2 * k),
            (fb - k, fb, fl + 2 * k, fr, nil, nil),
            (fb, fb + k, fl + 3 * k, fr - k, nil, nil),
        ]
        var ink: [Rect] = [], fill: [Rect] = []
        for (y0, y1, ul, ur, xl, xr) in rows {
            if let xl, let xr {
                ink.append(Rect(l: ul, t: y0, r: xl, b: y1))
                ink.append(Rect(l: xr, t: y0, r: ur, b: y1))
                fill.append(Rect(l: xl, t: y0, r: xr, b: y1))
            } else {
                ink.append(Rect(l: ul, t: y0, r: ur, b: y1))
            }
        }
        return Layers(ink: ink, fill: fill)
    }

    /// Dời nhãn / icon cho khớp tâm MẶT phím: thường −k/2 (mặt lệch trái-trên vì bóng), lún +k/2.
    static func labelShift(block k: Double, pressed: Bool) -> Double { pressed ? k / 2 : -k / 2 }

    /// Màu một vai: lõi, viền (bóng cùng màu viền — khối đậm kiểu 8-bit).
    struct Colors: Hashable {
        var fill: RGBA, outline: RGBA
        func hash(into h: inout Hasher) {
            for c in [fill, outline] { h.combine(c.r); h.combine(c.g); h.combine(c.b); h.combine(c.a) }
        }
    }

    /// Ảnh 16×16 px (sRGB, không khử răng cưa) của một trạng thái.
    static func image(_ c: Colors, pressed: Bool) -> CGImage? {
        let n = cells
        guard let ctx = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setShouldAntialias(false)
        ctx.interpolationQuality = .none
        // Gốc toạ độ ảnh ở TRÊN-trái như hình học (CGContext gốc dưới-trái).
        ctx.translateBy(x: 0, y: CGFloat(n))
        ctx.scaleBy(x: 1, y: -1)
        let ly = layers(l: 0, t: 0, r: Double(n), b: Double(n), block: 1, pressed: pressed)
        func paint(_ rs: [Rect], _ col: RGBA) {
            ctx.setFillColor(col.ui.cgColor)
            for r in rs where r.r > r.l && r.b > r.t {
                ctx.fill(CGRect(x: r.l, y: r.t, width: r.r - r.l, height: r.b - r.t))
            }
        }
        paint(ly.ink, c.outline)
        paint(ly.fill, c.fill)
        return ctx.makeImage()
    }

    /// Skin (thường + lún) cho bảng màu — cache theo màu (vài vai × 2 ảnh 16×16 ≈ 1 KB mỗi ảnh).
    nonisolated(unsafe) private static var cache: [Colors: LoadedThemeAssets.Skin] = [:]
    static func skin(_ c: Colors) -> LoadedThemeAssets.Skin? {
        if let s = cache[c] { return s }
        guard let n = image(c, pressed: false), let p = image(c, pressed: true) else { return nil }
        if cache.count > 16 { cache.removeAll() }
        let s = LoadedThemeAssets.Skin(normal: n, pressed: p, insets: slice, srcH: cells, pixelated: true)
        cache[c] = s
        return s
    }

    /// Vai phím → màu (bảng màu đã giải: trong suốt / ảnh nền đã áp). Chữ a–z, số, ký hiệu: mặt phím; phím chức năng
    /// (⇧ ⌫ 123 🌐 cách, return thường): màu chức năng; return hành động (go/search/send…): màu nhấn.
    static let actionReturnRole = "returnAction"
    static func skins(_ p: KeyboardPalette) -> [String: LoadedThemeAssets.Skin] {
        let outline = p.keyBorder.map { $0.a > 0 ? $0 : p.keyInk } ?? p.keyInk
        guard let key = skin(Colors(fill: p.keyFill, outline: outline)),
              let fn = skin(Colors(fill: p.fnFill, outline: outline)),
              let act = skin(Colors(fill: p.accent, outline: outline)) else { return [:] }
        var out: [String: LoadedThemeAssets.Skin] = [:]
        for r in ThemeAssetPlan.roles {
            out[r] = ThemeAssetSpec.letterKeys.contains(r) || r == "default" ? key : fn
        }
        out[actionReturnRole] = act
        return out
    }

    /// Bộ "tệp đã nạp" có skin điểm ảnh, giữ phông / ảnh nền / tiền cảnh của bộ tải về (nếu có). Chữ ký đổi theo màu ⇒
    /// plane dựng lại khi đổi sáng/tối.
    static func assets(over base: LoadedThemeAssets?, palette p: KeyboardPalette) -> LoadedThemeAssets {
        let sig = "pixel|" + [p.keyFill, p.fnFill, p.accent, p.keyBorder ?? p.keyInk].map {
            String(format: "%.4f,%.4f,%.4f,%.4f", $0.r, $0.g, $0.b, $0.a)
        }.joined(separator: ";")
        return LoadedThemeAssets(signature: (base?.signature ?? "") + "|" + sig, font: base?.font, skins: skins(p),
                                 backgroundURL: base?.backgroundURL, foregroundURL: base?.foregroundURL)
    }
}
