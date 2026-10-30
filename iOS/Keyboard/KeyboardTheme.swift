import UIKit
import CoreText

// Theme bàn phím — MỌI token màu ở một chỗ (dùng chung Keyboard + App + test).
// Android giữ bảng y hệt ở android/keyboard/.../KeyboardTheme.kt — sửa màu thì
// sửa cả hai. Vẽ phím vẫn phẳng: không bóng, không blur runtime, không offscreen
// pass (xem lịch sử bỏ shadow trong KeyboardView). Kính = để lộ backdrop mờ SẴN
// CÓ của hệ thống + phím bán trong suốt, không tự blur.

/// Màu RGBA thuần (0…1) — tách khỏi UIColor để test tính tương phản.
struct RGBA: Equatable {
    var r: Double, g: Double, b: Double, a: Double = 1
    init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }
    init(hex: UInt32, alpha: Double = 1) {
        r = Double((hex >> 16) & 0xFF) / 255
        g = Double((hex >> 8) & 0xFF) / 255
        b = Double(hex & 0xFF) / 255
        a = alpha
    }
    static let white = RGBA(hex: 0xFFFFFF), black = RGBA(hex: 0x000000)
    func alpha(_ x: Double) -> RGBA { RGBA(r: r, g: g, b: b, a: a * x) }
    var ui: UIColor { UIColor(red: r, green: g, blue: b, alpha: a) }

    /// Trộn màu này (có alpha) lên nền đục.
    func over(_ bg: RGBA) -> RGBA {
        RGBA(r: r * a + bg.r * (1 - a), g: g * a + bg.g * (1 - a), b: b * a + bg.b * (1 - a))
    }
    /// Độ chói tương đối WCAG 2.x.
    var luminance: Double {
        func ch(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * ch(r) + 0.7152 * ch(g) + 0.0722 * ch(b)
    }
    /// Tỉ lệ tương phản WCAG (1…21), cả hai màu coi như đục.
    static func contrast(_ x: RGBA, _ y: RGBA) -> Double {
        let a = x.luminance, b = y.luminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}

/// Bộ token một theme đã giải (theo sáng/tối hệ thống + ảnh nền).
struct KeyboardPalette: Equatable {
    /// nil = nền trong suốt (backdrop hệ thống lộ ra: theme Hệ thống, Kính).
    var background: RGBA?
    var keyFill: RGBA
    /// Phím chức năng khi ĐÈ (iOS 26+: mọi phím cùng nền, đè thì sẫm lại).
    var specialFill: RGBA
    var ink: RGBA
    var trail: RGBA
    /// Chữ/icon thanh gợi ý.
    var barInk: RGBA
    var balloon: RGBA
    /// Phím return dạng hành động (go/search/send…).
    var accent: RGBA
    var accentInk: RGBA
    /// Viền phím 1pt (chỉ theme tương phản cao) — borderWidth không gây offscreen.
    var keyBorder: RGBA?
    /// Chữ sáng trên nền tối → icon hệ thống, emoji plane, … đi theo nhánh tối.
    var isDark: Bool
    /// Chữ/icon TRÊN PHÍM sau hai thanh trượt độ trong suốt; nil = `ink`.
    /// `ink` giữ nguyên cho balloon/popup — phản hồi khi gõ luôn rõ.
    var keyLabel: RGBA? = nil
    /// Hệ số alpha của bề mặt PHÍM (nền phím, viền, phím shift bật) theo độ trong suốt phím
    /// (1 = như cũ). KHÔNG áp cho ảnh nền — ảnh nền có độ tối/mờ riêng (wallpaperLayer).
    var surfaceAlpha: Double = 1
    /// Chữ trên phím do người dùng chọn (Tuỳ chỉnh nâng cao) — độ trong suốt không đổi
    /// nó sang đen/trắng.
    var keyLabelPinned = false

    /// Nền phía sau phần KHÔNG phải phím (thanh gợi ý, bảng emoji, ô tìm emoji) tối hay sáng;
    /// nil = `isDark`. Khác `isDark` khi theme tự vẽ phím nhưng nền theo hệ thống.
    var surfaceDark: Bool? = nil

    /// Nền phím CHỨC NĂNG + phím cách (⇧ ⌫ 123 🌐 😊 return thường) — nil = `keyFill` (iOS 26+:
    /// mọi phím cùng nền). Chỉ theme tô phím chức năng riêng (Xanh lá) đặt. Android cùng ý nghĩa.
    var functionFill: RGBA? = nil
    /// Chữ/icon trên phím chức năng (đã áp độ trong suốt ký tự) — nil = `keyInk`. Trắng hồng.
    var functionInk: RGBA? = nil
    /// Hoạ tiết vẽ MỘT lần vào lớp nền (tim / hoa) — nil = nền phẳng. Không vẽ gì mỗi phím.
    var decoration: KeyboardDecoration? = nil
    /// Viền phím cầu vồng (Gaming RGB, slot "borderFx":"rainbow"): MỘT lớp gradient che bằng hình viền mọi phím
    /// (RainbowBorder) — chỉ xoay màu khi đang gõ, nghỉ thì đứng yên. Android `rainbowBorder` cùng ý nghĩa.
    var rainbowBorder = false
    /// Lỗ thoát âm trên phím cách (Ghi-ta, slot "spaceDeco":"soundhole"): hình tròn tối + vành hoa văn vẽ MỘT lần
    /// (CAShapeLayer trong phím cách / Canvas Android), 0 chi phí mỗi phím. Android `spaceSoundhole` cùng ý nghĩa.
    var spaceSoundhole = false
    /// Người dùng chọn "Màu nhấn" (KeyStyle.accentColor) ⇒ phím ⇧ bật / Caps tô `accent` + `accentInk`
    /// (mặc định: nền trắng glyph đen như stock). Android cùng ý nghĩa (`accentShift`).
    var accentShift = false

    var keyInk: RGBA { keyLabel ?? ink }
    var fnFill: RGBA { functionFill ?? keyFill }
    var fnInk: RGBA { functionInk ?? keyInk }

    /// "Nền theo hệ thống": bỏ nền theme (vật liệu bàn phím hệ thống lộ ra, cùng màu dải
    /// 🌐/🎤), GIỮ màu phím. Chữ thanh gợi ý đổi đen/trắng nếu không đọc được trên nền đó.
    func onSystemBackdrop(systemDark: Bool) -> KeyboardPalette {
        var p = self
        p.background = nil
        p.decoration = nil
        p.barInk = KeyboardTransparency.readable(barInk, on: KeyboardTransparency.systemBackdrop(dark: systemDark))
        p.surfaceDark = systemDark
        return p
    }

    /// Có ảnh nền: phím hơi trong để ảnh lộ ra; lớp phủ (dim) do view vẽ riêng.
    /// Độ trong được chọn sao cho chữ vẫn ≥ 4.5:1 (WCAG AA) kể cả trên ảnh TỆ NHẤT
    /// (trắng tuyền dưới theme tối, đen tuyền dưới theme sáng) và lớp phủ 0%.
    static let wallpaperKeyAlpha = 0.8
    func overWallpaper() -> KeyboardPalette {
        let worst: RGBA = isDark ? .white : .black
        func legible(_ base: RGBA, _ label: RGBA) -> RGBA {
            // Theme phím vốn trong (Kính): đổi sang phím phủ đen/trắng bán trong.
            let translucent = base.a < 1
            let solid = translucent ? (isDark ? RGBA.black : RGBA.white) : base
            var a = translucent ? 0.5 : Self.wallpaperKeyAlpha
            while a < 1, RGBA.contrast(label, solid.alpha(a).over(worst)) < 4.5 { a += 0.05 }
            return solid.alpha(min(a, 1))
        }
        var p = self
        p.keyFill = legible(keyFill, ink)
        p.specialFill = legible(specialFill, ink)
        // Phím chức năng đo theo CHỮ phím chức năng (Giáng sinh: glyph vàng, Piano: glyph trắng trên phím đen).
        p.functionFill = functionFill.map { legible($0, functionInk ?? ink) }
        p.background = nil
        p.decoration = nil
        // Thanh gợi ý nằm trên lớp phủ ảnh (tông theo isDark) ⇒ chữ riêng của thanh (Piano) đổi cho đọc được.
        // Theme khác: barInk = ink vốn đọc được trên lớp phủ cùng tông ⇒ không đổi.
        let bar = KeyboardTransparency.readable(barInk, on: wallpaperOverlay)
        if bar != barInk { p.barInk = bar; p.surfaceDark = isDark }
        return p
    }
    /// Màu lớp phủ ảnh nền: tối cho theme tối, sáng cho theme sáng.
    var wallpaperOverlay: RGBA { isDark ? .black : .white }

    /// Cách vẽ ảnh nền (mô hình vẽ thuần — KeyboardView + bản xem trước dùng chung): ảnh luôn
    /// ĐỤC, lớp phủ theo "Độ tối lớp phủ". Độ trong suốt phím KHÔNG làm mất ảnh nền (bug 100%
    /// trước đây: ảnh + lớp phủ nhân surfaceAlpha ⇒ 0 ⇒ ảnh biến mất).
    func wallpaperLayer(dim: Int) -> (imageAlpha: Double, overlay: RGBA) {
        (1, wallpaperOverlay.alpha(Double(max(0, min(80, dim))) / 100))
    }
}

/// Độ trong suốt (Cài đặt → Giao diện), hai thanh độc lập 0…100%:
/// - phím: nền phím + viền (+ nền theme khi KHÔNG có ảnh nền); 100% = phím vô hình, chỉ còn
///   chữ. Ảnh nền luôn giữ nguyên (đã có độ tối/mờ riêng).
/// - ký tự: chữ/icon/nhãn phụ trên phím; 100% = phím trơn không chữ.
/// Áp bằng alpha của MÀU lúc dựng palette — không alpha nhóm (không offscreen pass,
/// không làm mờ chữ theo), 0 chi phí mỗi phím. Balloon/popup không đổi.
/// Android giữ y hệt ở android/keyboard/.../KeyboardTheme.kt.
enum KeyboardTransparency {
    static let keyboardKey = "keyboardTransparency"
    static let labelKey = "keyLabelTransparency"
    /// Chữ trên phím ≥ 18pt = "chữ lớn" WCAG → ngưỡng 3:1. Dưới ngưỡng (vì nền đã
    /// trong suốt, lộ nền khác tông) mới đổi sang đen/trắng.
    static let minLabelContrast = 3.0

    static func clamp(_ v: Int) -> Int { max(0, min(100, v)) }
    /// 0% → 1 (như cũ), 100% → 0.
    static func alpha(_ pct: Int) -> Double { 1 - Double(clamp(pct)) / 100 }

    /// Nền hệ thống sau input view: iOS luôn có lớp kính bàn phím (không gỡ được) —
    /// tối đo từ stock iOS 27 (#202020), sáng xấp xỉ kính sáng.
    static func systemBackdrop(dark: Bool) -> RGBA { dark ? RGBA(hex: 0x202020) : RGBA(hex: 0xD4D6DC) }

    /// Giữ `ink` nếu còn đọc được trên `bg`; không thì đen/trắng (cái tương phản hơn).
    static func readable(_ ink: RGBA, on bg: RGBA) -> RGBA {
        guard RGBA.contrast(ink, bg) < minLabelContrast else { return ink }
        let alt: RGBA = RGBA.contrast(.white, bg) >= RGBA.contrast(.black, bg) ? .white : .black
        return RGBA.contrast(alt, bg) > RGBA.contrast(ink, bg) ? alt : ink
    }
}

/// Kiểu ô phóng to khi bấm + popup ký tự phụ / đuôi tên miền / pill: GIỐNG PHÍM của theme đang dùng
/// (nền phím đã ghép lên nền bàn phím — gồm độ trong suốt + sáng/tối, viền, bo góc, màu chữ, phông /
/// độ đậm / cỡ). Ô đang chọn trong popup ký tự phụ dùng màu nhấn. Giải MỘT lần mỗi lần dựng palette
/// (KeyboardView.resolvePalette) — không tính gì thêm mỗi lần bấm. Android y hệt (KeyPopupStyle.kt).
struct KeyPopupStyle: Equatable {
    /// Nền ĐỤC (ô phóng to luôn đọc được kể cả khi phím trong suốt hẳn).
    var fill: RGBA
    var ink: RGBA
    /// Viền như phím (Hoa xanh, Neon, Tương phản cao); nil = không viền.
    var border: RGBA?
    var borderWidth: Double
    /// Bo góc như phím (% KeyStyle.corner); nil = bo mặc định của ô phóng to.
    var cornerPercent: Int?
    /// Hệ số cỡ chữ (KeyStyle.fontScale) — kẹp vừa ô lúc vẽ.
    var labelScale: Double
    /// Ô đang chọn (popup ký tự phụ / tên miền): nền nhấn + chữ đọc được trên nhấn.
    var selectedFill: RGBA
    var selectedInk: RGBA

    static func make(_ p: KeyboardPalette, style: KeyStyle, systemDark: Bool, wallpaper: Bool) -> KeyPopupStyle {
        let sys = KeyboardTransparency.systemBackdrop(dark: systemDark)
        let behind = (wallpaper ? p.wallpaperOverlay : p.background)?.over(sys) ?? sys
        let fill = p.keyFill.over(behind)
        let ink = KeyboardTransparency.readable(RGBA(r: p.ink.r, g: p.ink.g, b: p.ink.b), on: fill)
        let selected = p.accent.over(behind)
        let selInk = KeyboardTransparency.readable(RGBA(r: p.accentInk.r, g: p.accentInk.g, b: p.accentInk.b), on: selected)
        return KeyPopupStyle(fill: fill, ink: ink, border: p.keyBorder.map { $0.over(fill) },
                             borderWidth: p.keyBorder == nil ? 0 : 1, cornerPercent: style.corner,
                             labelScale: Double(style.labelScale), selectedFill: selected, selectedInk: selInk)
    }

    /// Bán kính bo góc ô cỡ `size` (bo theo % như phím; mặc định `fallback`), kẹp nửa cạnh ngắn.
    func radius(size: CGSize, fallback: CGFloat) -> CGFloat {
        KeyStyle.cornerRadius(percent: cornerPercent, size: size, fallback: fallback)
    }
}

extension KeyboardPalette {
    func withTransparency(keyboard: Int, labels: Int, systemDark: Bool,
                          wallpaper: Bool) -> KeyboardPalette {
        typealias T = KeyboardTransparency
        let k = T.clamp(keyboard), l = T.clamp(labels)
        guard k > 0 || l > 0 else { return self }
        var p = self
        var label = ink
        if k > 0 {
            let s = T.alpha(k)
            p.surfaceAlpha = s
            p.background = background?.alpha(s)
            p.keyFill = keyFill.alpha(s)
            p.specialFill = specialFill.alpha(s)
            p.accent = accent.alpha(s)
            p.keyBorder = keyBorder?.alpha(s)
            p.functionFill = functionFill?.alpha(s)
            if let d = decoration { p.decoration?.color = d.color.alpha(s) }
            // Nền thật sau chữ ≈ lớp nền mới trên backdrop hệ thống. Ảnh nền vẫn hiện nguyên
            // ⇒ ước lượng bằng tông lớp phủ (tối cho theme tối, sáng cho theme sáng).
            let sys = T.systemBackdrop(dark: systemDark)
            let behind = (wallpaper ? wallpaperOverlay : p.background)?.over(sys) ?? sys
            if !keyLabelPinned {
                label = T.readable(ink, on: p.keyFill.over(behind))
                p.functionInk = functionInk.map { T.readable($0, on: p.fnFill.over(behind)) }
            }
            p.barInk = T.readable(barInk, on: behind)
            p.accentInk = T.readable(accentInk, on: p.accent.over(behind))
            if label != ink { p.isDark = label.luminance > 0.5 }
        }
        let la = T.alpha(l)
        p.keyLabel = label.alpha(la)
        p.functionInk = p.functionInk?.alpha(la)
        p.accentInk = p.accentInk.alpha(la)
        return p
    }
}

enum KeyboardTheme: String, CaseIterable {
    case system, oled, contrast, peach, mint, sky, lavender, glass
    // Bộ 10/2026 (gợi ý từ các theme cộng đồng được thích nhất — thiết kế riêng, không dùng tài
    // sản của ai, không nhân vật có thương hiệu). rawValue = giá trị lưu, trùng id Android.
    case blackHeart, greenFloral, sage, neon, pink
    // Lễ / mùa (10/2026, hình vẽ vector tự thiết kế): Tết, Tết mai vàng, Giáng sinh, Giáng sinh tuyết, Piano.
    case tet, tetMai, xmas, xmasSnow, piano
    // Sen Việt (19/10/2026): hồng sen + xanh lá sen, motif hoa sen, âm đàn tranh.
    case sen
    // Bộ đủ món 10/2026 (màu + trang trí + hiệu ứng + âm): Máy chữ cổ, Gaming RGB, Vũ trụ.
    case typewriter, rgb, space
    // Bộ đủ món 10/2026 (màu + hoạ tiết + hiệu ứng + âm): Trung Thu, Valentine, Halloween.
    case trungthu, valentine, halloween
    // Bộ đủ món 10/2026: Ghi-ta (mặt đàn gỗ thích mật ong, phím gỗ hồng sắc, dây đàn + khảm xà cừ, lỗ thoát âm trên
    // phím cách, âm ghi-ta mộc + hiệu ứng rung dây).
    case guitar
    // Trò chơi khi gõ 10/2026: Đập chuột (bãi cỏ + phím hang đất; "game":"mole" — MoleGame).
    case mole
    // Xám trung tính (issue #137, 30/10/2026): miễn phí, kiểu Gboard xám, theo sáng/tối hệ thống. Id trùng Android;
    // THÊM CUỐI (rawValue lưu, không đổi thứ tự).
    case neutral
    // "Trắng hồng" (pureWhite, 1.5.12) đã bỏ 10/2026: chỉ là Hệ thống + màu nhấn hồng ⇒ chuyển sang
    // Hệ thống + Màu nhấn D6336C (KeyStyleStore.migrate). Id lạ / đã bỏ luôn về Hệ thống.

    var title: String {
        switch self {
        case .system: return L("Hệ thống")
        case .oled: return L("Tối OLED")
        case .contrast: return L("Tương phản cao")
        case .peach: return L("Hồng đào")
        case .mint: return L("Bạc hà")
        case .sky: return L("Trời xanh")
        case .lavender: return L("Oải hương")
        case .glass: return L("Kính")
        case .blackHeart: return L("Tim đen")
        case .greenFloral: return L("Hoa xanh")
        case .sage: return L("Xanh lá")
        case .neon: return L("Neon")
        case .pink: return L("Hồng")
        case .tet: return L("Tết")
        case .tetMai: return L("Tết mai vàng")
        case .xmas: return L("Giáng sinh")
        case .xmasSnow: return L("Giáng sinh tuyết")
        case .piano: return L("Piano")
        case .sen: return L("Sen Việt")
        case .typewriter: return L("Máy chữ cổ")
        case .rgb: return L("Gaming RGB")
        case .space: return L("Vũ trụ")
        case .trungthu: return L("Trung Thu")
        case .valentine: return L("Valentine")
        case .halloween: return L("Halloween")
        case .guitar: return L("Ghi-ta")
        case .mole: return L("Đập chuột")
        case .neutral: return L("Xám trung tính")
        }
    }

    /// Bo góc mặc định của theme (% như KeyStyle.corner) khi người dùng chưa chỉnh — nil = bo stock.
    /// "Hồng": phím tròn trịa (corner 70 trong builtin-themes.json). Android cùng giá trị.
    var defaultCorner: Int? { spec?.corner }

    /// Theme tự vẽ nền (OLED, tương phản cao, pastel) — có tuỳ chọn "Nền theo hệ thống".
    /// Hệ thống / Kính vốn trong suốt.
    var hasOwnBackground: Bool { palette(systemDark: false).background != nil }

    /// Key App Group + sao lưu của "Nền theo hệ thống" cho theme này ("systemBackdropOled"…);
    /// nil = theme vốn trong suốt (không có tuỳ chọn).
    var systemBackdropKey: String? {
        guard hasOwnBackground else { return nil }
        return "systemBackdrop" + rawValue.prefix(1).uppercased() + rawValue.dropFirst()
    }

    /// Theme cao cấp thuộc gói Plus. Tương phản cao là trợ năng → luôn miễn phí.
    var isPlus: Bool {
        switch self {
        case .system, .oled, .contrast, .neutral: return false
        case .peach, .mint, .sky, .lavender, .glass,
             .blackHeart, .greenFloral, .sage, .neon, .pink,
             .tet, .tetMai, .xmas, .xmasSnow, .piano,
             .sen,
             .typewriter, .rgb, .space,
             .trungthu, .valentine, .halloween,
             .guitar,
             .mole: return true
        }
    }

    func palette(systemDark: Bool) -> KeyboardPalette {
        let blue = RGBA(r: 0, g: 0.478, b: 1)   // ≈ systemBlue
        switch self {
        case .system:
            // Sáng: giá trị cũ của KeyboardView. Tối: theo bàn phím STOCK iOS 27 (đo pixel
            // ảnh chụp simulator iPhone 17, English US, dark, 27/09/2026): nền #202020, MỌI
            // phím (chữ, shift, ⌫, 123, space, return) #444444, chữ trắng. Trước đây
            // #6B6B6B (phím chữ iOS ≤ 18, KeyboardKit standardButtonBackground dark) — sáng
            // hơn hẳn stock iOS 26/27 (góp ý user). Đè phím: sẫm lại về phía nền.
            return systemDark
                ? KeyboardPalette(background: nil, keyFill: RGBA(hex: 0x444444),
                                  specialFill: RGBA(hex: 0x2E2E2E), ink: .white,
                                  trail: RGBA.white.alpha(0.55), barInk: .white,
                                  balloon: RGBA(r: 0.35, g: 0.35, b: 0.35),
                                  accent: blue, accentInk: .white, keyBorder: nil, isDark: true)
                : KeyboardPalette(background: nil, keyFill: .white,
                                  specialFill: RGBA(r: 0.68, g: 0.70, b: 0.74), ink: .black,
                                  trail: blue.alpha(0.55), barInk: .black, balloon: .white,
                                  accent: blue, accentInk: .white, keyBorder: nil, isDark: false)
        case .glass:
            // Nền trong suốt: backdrop mờ của hệ thống lộ ra (miễn phí, không
            // blur tự vẽ); phím trắng bán trong kiểu Liquid Glass.
            return systemDark
                ? KeyboardPalette(background: nil, keyFill: RGBA.white.alpha(0.16),
                                  specialFill: RGBA.white.alpha(0.32), ink: .white,
                                  trail: RGBA.white.alpha(0.6), barInk: .white,
                                  balloon: RGBA(hex: 0x4A4A4E),
                                  accent: blue, accentInk: .white, keyBorder: RGBA.white.alpha(0.18),
                                  isDark: true)
                : KeyboardPalette(background: nil, keyFill: RGBA.white.alpha(0.55),
                                  specialFill: RGBA.white.alpha(0.3), ink: .black,
                                  trail: blue.alpha(0.55), barInk: .black, balloon: .white,
                                  accent: blue, accentInk: .white, keyBorder: RGBA.white.alpha(0.6),
                                  isDark: false)
        default:
            // Theme có sẵn khác: dữ liệu JSON (themes/builtin-themes.json → BuiltinThemes, đọc MỘT lần).
            // Thiếu (không xảy ra — test khoá) ⇒ vẽ như Hệ thống, không crash.
            guard let spec = BuiltinThemes.specs[rawValue] else { return Self.system.palette(systemDark: systemDark) }
            return spec.palette(dark: systemDark)
        }
    }

    /// Đặc tả JSON của theme có sẵn (nil = Hệ thống / Kính — vẽ theo nền tảng).
    var spec: ThemeSpec? { BuiltinThemes.specs[rawValue] }
}

/// Hoạ tiết nền theme (Tim đen: tim; Hoa xanh: hoa) — MỘT path vẽ một lần vào lớp nền
/// (CAShapeLayer iOS / Drawable Android), dựng lại chỉ khi cỡ / hàng phím đổi. 0 chi phí mỗi phím,
/// không ảnh. Motif CHỈ nằm trong khe GIỮA các hàng phím (không ở thanh gợi ý, không dưới nhãn phím
/// kể cả khi phím trong suốt). Hình học thuần (test được); Android giữ y hệt (ThemeDecoration).
struct KeyboardDecoration: Equatable {
    /// Danh sách trắng (theme JSON chỉ nhận các id này — Android ThemeDeco.MOTIFS y hệt). Tim / hoa vẽ riêng;
    /// mai / đào / bông tuyết / sao / nốt nhạc là dữ liệu hình (`shape`) chung Android.
    enum Motif: String, CaseIterable {
        case hearts, flowers, mai, dao, snowflake, star, notes
        // Sen Việt (19/10/2026).
        case lotus
        // Vũ trụ (bộ đủ món 10/2026).
        case starfield
        // Trung Thu / Halloween (10/2026, vector tự vẽ): đèn lồng, trăng khuyết, bí ngô, dơi.
        case lantern, moon, pumpkin, bat
        // Ghi-ta (10/2026): "strings" = dây đàn kim loại kéo NGANG HẾT khe hàng (vẽ một lần mỗi khe, dày dần ở khe
        // dưới như dây trầm — không theo vị trí motif); "inlay" = chấm khảm xà cừ nhỏ (thường dùng làm deco.alt).
        case strings, inlay
    }
    var motif: Motif
    var color: RGBA
    /// Mật độ % ("Giao diện JSON" deco.density, 50…200): bước ngang = stepX × 100 / density.
    var density: Int = 100
    /// Motif thứ hai (deco.alt) — xen kẽ với `motif` (motif lẻ dùng alt): Trung Thu đèn lồng + trăng,
    /// Halloween bí ngô + dơi. nil = một motif như cũ. Android ThemeDecoration.alt y hệt.
    var alt: Motif? = nil

    init(motif: Motif, color: RGBA, density: Int = 100, alt: Motif? = nil) {
        self.motif = motif; self.color = color; self.density = density; self.alt = alt
    }

    /// Motif của vị trí thứ `k` (theo thứ tự `placements`).
    func motif(at k: Int) -> Motif { k % 2 == 1 ? (alt ?? motif) : motif }

    /// Có dây đàn (motif chính hoặc alt = strings) ⇒ path thêm mỗi khe một dây ngang.
    var hasStrings: Bool { motif == .strings || alt == .strings }

    /// Độ dày dây ở khe thứ `i` (0 = khe trên cùng; pt / dp) — dây dưới dày hơn như dây trầm của đàn.
    static func stringThickness(_ i: Int) -> Double { min(0.6 + 0.3 * Double(i), 1.5) }
    /// Lề hai đầu dây (pt / dp).
    static let stringInset = 6.0

    /// Dây đàn: mỗi khe có motif (tâm `y` khác nhau của `placements`, theo thứ tự) một hình chữ nhật mảnh kéo từ
    /// `stringInset` tới `width − stringInset` (nil ⇒ tới motif xa nhất + `inset`). Chiều quay như `shape` (nonzero
    /// hợp với chấm khảm đè lên). Android ThemeDecoration.strings y hệt.
    static func strings(_ placements: [Placement], width: Double?) -> [(x0: Double, x1: Double, y: Double, h: Double)] {
        var ys: [Double] = []
        for p in placements where !ys.contains(p.y) { ys.append(p.y) }
        guard !ys.isEmpty else { return [] }
        let right = width ?? ((placements.map { $0.x + $0.size / 2 }.max() ?? 0) + inset)
        let x0 = stringInset, x1 = right - stringInset
        guard x1 > x0 else { return [] }
        return ys.sorted().enumerated().map { (x0: x0, x1: x1, y: $0.element, h: stringThickness($0.offset)) }
    }

    /// Bước ngang (pt / dp), cỡ motif tối đa, lề hai bên, cỡ nhỏ nhất còn vẽ.
    static let stepX = 64.0, motifSize = 8.0, inset = 14.0, minMotifSize = 5.0
    /// Cách mép phím tối thiểu (motif không chạm phím).
    static let clearance = 1.0
    /// Trần số motif — bàn phím rộng (iPad) giãn bước thay vì vẽ thêm.
    static let maxMotifs = 120

    struct Gap: Equatable { var center: Double; var height: Double }
    struct Placement: Equatable { var x: Double; var y: Double; var size: Double }

    /// Khe giữa các HÀNG phím từ khung phím (top, bottom): gộp phím cùng hàng (chồng dọc), khe =
    /// từ đáy hàng trên tới đỉnh hàng dưới. Không tính phía trên hàng đầu (thanh gợi ý).
    static func rowGaps(_ spans: [(top: Double, bottom: Double)]) -> [Gap] {
        var rows: [(top: Double, bottom: Double)] = []
        for s in spans.sorted(by: { $0.top < $1.top }) where s.bottom > s.top {
            if let last = rows.last, s.top < last.bottom { rows[rows.count - 1].bottom = max(last.bottom, s.bottom) }
            else { rows.append(s) }
        }
        guard rows.count > 1 else { return [] }
        return (1..<rows.count).compactMap { i in
            let h = rows[i].top - rows[i - 1].bottom
            return h > 0 ? Gap(center: rows[i - 1].bottom + h / 2, height: h) : nil
        }
    }

    /// Motif dọc từng khe (so le giữa các khe), cỡ vừa khe (chừa `clearance` mỗi bên); khe quá hẹp bỏ.
    static func placements(width w: Double, gaps: [Gap], density: Int = 100) -> [Placement] {
        guard w > 2 * inset else { return [] }
        func layout(_ step: Double) -> [Placement] {
            var out: [Placement] = []
            for (i, g) in gaps.enumerated() {
                let size = min(motifSize, g.height - 2 * clearance)
                guard size >= minMotifSize else { continue }
                var x = inset + size / 2 + (i % 2 == 1 ? step / 2 : 0)
                while x + size / 2 <= w - inset { out.append(Placement(x: x, y: g.center, size: size)); x += step }
            }
            return out
        }
        var step = stepX * 100 / Double(min(max(density, 50), 200))   // kẹp lại: bước luôn > 0
        var pts = layout(step)
        while pts.count > maxMotifs { step *= 1.15; pts = layout(step) }
        return pts
    }

    /// Path mọi motif (gốc trên-trái, y xuống). `width` = bề ngang vùng vẽ (dây đàn kéo hết khe); nil ⇒ suy từ motif.
    func path(_ placements: [Placement], width: Double? = nil) -> CGPath {
        let path = CGMutablePath()
        if hasStrings {
            for s in Self.strings(placements, width: width) {
                let t = s.y - s.h / 2, b = s.y + s.h / 2
                path.move(to: CGPoint(x: s.x1, y: t))
                path.addLine(to: CGPoint(x: s.x1, y: b))
                path.addLine(to: CGPoint(x: s.x0, y: b))
                path.addLine(to: CGPoint(x: s.x0, y: t))
                path.closeSubpath()
            }
        }
        // Dữ liệu hình tính MỘT lần mỗi lần dựng path (không mỗi motif).
        let shapes = [motif, alt ?? motif].map(Self.shape)
        for (k, c) in placements.enumerated() {
            let s = CGFloat(c.size)
            let o = CGPoint(x: c.x, y: c.y)
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: o.x + x * s, y: o.y + y * s) }
            switch motif(at: k) {
            case .hearts:
                path.move(to: p(0, 0.45))
                path.addCurve(to: p(-0.5, -0.18), control1: p(-0.35, 0.2), control2: p(-0.5, 0))
                path.addCurve(to: p(-0.22, -0.5), control1: p(-0.5, -0.38), control2: p(-0.36, -0.5))
                path.addCurve(to: p(0, -0.33), control1: p(-0.1, -0.5), control2: p(-0.03, -0.43))
                path.addCurve(to: p(0.22, -0.5), control1: p(0.03, -0.43), control2: p(0.1, -0.5))
                path.addCurve(to: p(0.5, -0.18), control1: p(0.36, -0.5), control2: p(0.5, -0.38))
                path.addCurve(to: p(0, 0.45), control1: p(0.5, 0), control2: p(0.35, 0.2))
                path.closeSubpath()
            case .flowers:
                // 5 cánh tròn không chồng nhau + nhuỵ — tô nonzero, không cần lớp thứ hai.
                for i in 0..<5 {
                    let a = Double(i) * 2 * .pi / 5 - .pi / 2
                    let r: CGFloat = 0.18
                    let cx = CGFloat(0.32 * cos(a)), cy = CGFloat(0.32 * sin(a))
                    path.addEllipse(in: CGRect(origin: p(cx - r, cy - r), size: CGSize(width: 2 * r * s, height: 2 * r * s)))
                }
                path.addEllipse(in: CGRect(origin: p(-0.12, -0.12), size: CGSize(width: 0.24 * s, height: 0.24 * s)))
            default:
                for sub in shapes[k % 2] {
                    path.move(to: p(CGFloat(sub.start.0), CGFloat(sub.start.1)))
                    for g in sub.segs {
                        if g.count == 2 { path.addLine(to: p(CGFloat(g[0]), CGFloat(g[1]))) }
                        else { path.addCurve(to: p(CGFloat(g[4]), CGFloat(g[5])), control1: p(CGFloat(g[0]), CGFloat(g[1])),
                                             control2: p(CGFloat(g[2]), CGFloat(g[3]))) }
                    }
                    path.closeSubpath()
                }
            }
        }
        return path
    }

    /// Chấm sao nhỏ của motif "starfield": (x, y, bán kính) theo đơn vị motif — Android STAR_DOTS y hệt.
    static let starDots: [(Double, Double, Double)] = [(-2.6, -0.3, 0.1), (-1.4, 0.34, 0.07), (1.5, -0.24, 0.08),
                                                        (2.7, 0.3, 0.11), (0.8, 0.4, 0.05)]

    /// Một đường con khép kín: điểm đầu + các đoạn ([x, y] thẳng / [c1x, c1y, c2x, c2y, x, y] cubic).
    struct Sub: Equatable { var start: (Double, Double); var segs: [[Double]]
        static func == (a: Sub, b: Sub) -> Bool { a.start == b.start && a.segs == b.segs }
    }

    /// Hình motif dạng dữ liệu (đơn vị motif: tâm 0,0, nằm trong ô ±0.5, y xuống). MỌI đường con cùng chiều quay ⇒
    /// tô nonzero = hợp các mảnh, không thủng. Android ThemeDecoration.shape y hệt (test mốc chung).
    /// Tim / hoa vẽ riêng ở `path` ⇒ rỗng.
    static func shape(_ m: Motif) -> [Sub] {
        func pol(_ r: Double, _ a: Double) -> [Double] { [r * cos(a), r * sin(a)] }
        func rect(_ bx: Double, _ by: Double, _ ang: Double, _ len: Double, _ w: Double) -> Sub {
            let dx = cos(ang), dy = sin(ang), nx = -dy, ny = dx
            return Sub(start: (bx - nx * w, by - ny * w),
                       segs: [[bx + dx * len - nx * w, by + dy * len - ny * w], [bx + dx * len + nx * w, by + dy * len + ny * w],
                              [bx + nx * w, by + ny * w]])
        }
        func ell(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double) -> Sub {
            let k = 0.5523
            return Sub(start: (cx + rx, cy), segs: [
                [cx + rx, cy + k * ry, cx + k * rx, cy + ry, cx, cy + ry],
                [cx - k * rx, cy + ry, cx - rx, cy + k * ry, cx - rx, cy],
                [cx - rx, cy - k * ry, cx - k * rx, cy - ry, cx, cy - ry],
                [cx + k * rx, cy - ry, cx + rx, cy - k * ry, cx + rx, cy]])
        }
        func poly(_ q: [[Double]]) -> Sub { Sub(start: (q[0][0], q[0][1]), segs: Array(q.dropFirst())) }
        switch m {
        case .hearts, .flowers, .strings: return []
        case .inlay:
            // Chấm khảm xà cừ (tròn nhỏ) — trên cần đàn thật nằm giữa hai phím đàn.
            return [ell(0, 0, 0.22, 0.22)]
        case .starfield:
            // Vũ trụ: một sao lấp lánh 4 cánh (to) + vài chấm sao nhỏ trải NGANG trong khe (dọc vẫn ±0.45 —
            // không chạm phím). Chấm = hình thoi nhỏ, cùng chiều quay với sao.
            let pts = (0..<8).map { k in pol(k % 2 == 0 ? 0.5 : 0.13, Double(k) * .pi / 4 - .pi / 2) }
            var out = [Sub(start: (pts[0][0], pts[0][1]), segs: Array(pts.dropFirst()))]
            for d in Self.starDots {
                out.append(Sub(start: (d.0 + d.2, d.1), segs: [[d.0, d.1 + d.2], [d.0 - d.2, d.1], [d.0, d.1 - d.2]]))
            }
            return out
        case .mai:
            // Mai: 5 cánh tròn đầy (mỗi cánh một vòng cubic từ tâm).
            return (0..<5).map { i in
                let a = Double(i) * 2 * .pi / 5 - .pi / 2
                return Sub(start: (0, 0), segs: [pol(0.74, a - 0.6) + pol(0.74, a + 0.6) + [0, 0]])
            }
        case .dao:
            // Đào: 5 cánh có khía ở đầu cánh.
            return (0..<5).map { i in
                let a = Double(i) * 2 * .pi / 5 - .pi / 2
                return Sub(start: (0, 0), segs: [pol(0.5, a - 0.62) + pol(0.58, a - 0.28) + pol(0.4, a),
                                                 pol(0.58, a + 0.28) + pol(0.5, a + 0.62) + [0, 0]])
            }
        case .snowflake:
            // 6 nhánh + mỗi nhánh 2 nhánh con chữ V.
            var out: [Sub] = []
            for i in 0..<6 {
                let a = Double(i) * .pi / 3 - .pi / 2
                out.append(rect(0, 0, a, 0.48, 0.055))
                let b = pol(0.27, a)
                for sgn in [-1.0, 1.0] { out.append(rect(b[0], b[1], a + sgn * .pi / 3, 0.17, 0.045)) }
            }
            return out
        case .star:
            let pts = (0..<10).map { k in pol(k % 2 == 0 ? 0.5 : 0.21, Double(k) * .pi / 5 - .pi / 2) }
            return [Sub(start: (pts[0][0], pts[0][1]), segs: Array(pts.dropFirst()))]
        case .notes:
            // Nốt móc đơn ♪: đầu nốt (elip 4 cubic) + thân + móc.
            let k = 0.5523, cx = -0.14, cy = 0.3, rx = 0.19, ry = 0.14
            let head = Sub(start: (cx + rx, cy), segs: [
                [cx + rx, cy + k * ry, cx + k * rx, cy + ry, cx, cy + ry],
                [cx - k * rx, cy + ry, cx - rx, cy + k * ry, cx - rx, cy],
                [cx - rx, cy - k * ry, cx - k * rx, cy - ry, cx, cy - ry],
                [cx + k * rx, cy - ry, cx + rx, cy - k * ry, cx + rx, cy]])
            let stem = Sub(start: (0.01, 0.3), segs: [[0.01, -0.48], [0.07, -0.48], [0.07, 0.3]])
            let flag = Sub(start: (0.07, -0.48), segs: [[0.1, -0.3, 0.38, -0.3, 0.3, -0.02], [0.3, -0.2, 0.18, -0.26, 0.07, -0.28]])
            return [head, stem, flag]
        case .lotus:
            // Hoa sen (tự vẽ): 5 cánh nhọn toả từ gốc — cánh giữa cao nhất, hai cặp nghiêng thấp dần (mỗi cánh một
            // vòng cubic, cùng chiều quay) — ngồi trên đài / mặt nước hình thấu kính.
            let by = 0.28, up = -Double.pi / 2
            func petal(_ a: Double, _ r: Double, _ d: Double) -> Sub {
                Sub(start: (0, by), segs: [[r * cos(a - d), by + r * sin(a - d), r * cos(a + d), by + r * sin(a + d), 0, by]])
            }
            return [petal(up, 0.95, 0.3), petal(up - 0.5, 0.8, 0.3), petal(up + 0.5, 0.8, 0.3),
                    petal(up - 1.1, 0.6, 0.32), petal(up + 1.1, 0.6, 0.32),
                    Sub(start: (-0.38, by), segs: [[-0.15, by - 0.1, 0.15, by - 0.1, 0.38, by],
                                                   [0.15, by + 0.16, -0.15, by + 0.16, -0.38, by]])]
        case .lantern:
            // Đèn lồng giấy: dây treo + nắp + thân tròn dẹt + đáy + tua.
            return [poly([[-0.015, -0.5], [0.015, -0.5], [0.015, -0.36], [-0.015, -0.36]]),
                    poly([[-0.13, -0.38], [0.13, -0.38], [0.13, -0.27], [-0.13, -0.27]]),
                    ell(0, 0, 0.37, 0.3),
                    poly([[-0.13, 0.26], [0.13, 0.26], [0.13, 0.36], [-0.13, 0.36]]),
                    poly([[-0.03, 0.35], [0.03, 0.35], [0.07, 0.5], [-0.07, 0.5]])]
        case .moon:
            // Trăng khuyết: cung ngoài (tròn R quanh tâm) đi vòng xa, cung trong (tròn r lệch lên-phải) quay về.
            let rr = 0.44, r = 0.37, cx = 0.17, cy = -0.12
            let d = (cx * cx + cy * cy).squareRoot(), dir = atan2(cy, cx)
            let a = (rr * rr - r * r + d * d) / (2 * d)
            let al = acos(a / rr), ga = acos((d - a) / r)
            var q: [[Double]] = (0...24).map { pol(rr, dir + al + Double($0) / 24 * (2 * .pi - 2 * al)) }
            for i in 1..<16 {
                let t = dir + .pi + ga - Double(i) / 16 * 2 * ga
                q.append([cx + r * cos(t), cy + r * sin(t)])
            }
            return [poly(q)]
        case .pumpkin:
            // Bí ngô hiền: 3 múi + cuống + lá (không mặt).
            return [ell(-0.2, 0.07, 0.22, 0.29), ell(0.2, 0.07, 0.22, 0.29), ell(0, 0.05, 0.23, 0.33),
                    poly([[-0.01, -0.45], [0.07, -0.42], [0.04, -0.24], [-0.04, -0.24]]),
                    Sub(start: (0.03, -0.31), segs: [[0.1, -0.45, 0.24, -0.44, 0.29, -0.36],
                                                     [0.21, -0.35, 0.11, -0.31, 0.03, -0.31]])]
        case .bat:
            // Dơi tròn trịa: thân + đầu + 2 tai + 2 cánh mép dưới lượn sóng.
            return [ell(0, 0.04, 0.11, 0.17), ell(0, -0.14, 0.1, 0.1),
                    poly([[-0.09, -0.18], [-0.08, -0.3], [-0.02, -0.22]]),
                    poly([[0.02, -0.22], [0.08, -0.3], [0.09, -0.18]]),
                    Sub(start: (0.06, -0.08), segs: [[0.18, -0.22, 0.36, -0.24, 0.48, -0.12],
                                                     [0.44, -0.04, 0.4, -0.04, 0.36, 0.02],
                                                     [0.32, -0.04, 0.26, -0.02, 0.22, 0.06],
                                                     [0.18, 0, 0.12, 0.02, 0.08, 0.1]]),
                    Sub(start: (-0.08, 0.1), segs: [[-0.12, 0.02, -0.18, 0, -0.22, 0.06],
                                                    [-0.26, -0.02, -0.32, -0.04, -0.36, 0.02],
                                                    [-0.4, -0.04, -0.44, -0.04, -0.48, -0.12],
                                                    [-0.36, -0.24, -0.18, -0.22, -0.06, -0.08]])]
        }
    }
}

/// Lỗ thoát âm trên phím cách (theme Ghi-ta, slot "spaceDeco":"soundhole") — hình học thuần, Android Soundhole y hệt.
/// Tâm = tâm phím; bán kính lỗ R = min(0.34 × cao, 0.18 × rộng); hai vành hoa văn (rosette) đồng tâm vẽ nét:
/// (bán kính, độ dày) theo bội của R. Vành ngoài cùng ≤ 0.46 × cao ⇒ không chạm mép phím.
enum Soundhole {
    static let holeRatio = 0.34
    static let maxWidthRatio = 0.18
    static let holeAlpha = 0.55
    static let rings: [(radius: Double, width: Double)] = [(1.28, 0.12), (1.13, 0.06)]
    static func radius(width: Double, height: Double) -> Double { max(0, min(holeRatio * height, maxWidthRatio * width)) }
    /// Bán kính ngoài cùng (mép vành ngoài) — test: nằm trong phím.
    static func outerExtent(width: Double, height: Double) -> Double {
        let r = radius(width: width, height: height)
        return rings.map { ($0.radius + $0.width / 2) * r }.max() ?? r
    }
}

/// "sound" / "effect" đi kèm theme (Tết: pháo + hoa mai rơi, Giáng sinh: chuông + tuyết, Piano: tiếng đàn): áp MỘT
/// lần ĐÚNG LÚC người dùng chọn theme (chạm thẻ "Chọn giao diện", hoặc dán rồi áp theme tự tạo). Sau đó người dùng đổi
/// tay thì giữ tới lần chọn theme kế; theme không khai báo ⇒ không đổi gì. KHÔNG BAO GIỜ bật âm thanh phím: tắt thì
/// chỉ lưu kiểu âm + trả `soundHint` để app gợi ý "Bật". Id máy chưa có / bị khoá Plus ⇒ bỏ qua (không lưu giá trị
/// khoá). Android ThemeExtras y hệt.
enum ThemeExtras {
    static let soundOnKey = "keySound"
    static let soundStyleKey = "keySoundStyle"

    struct Outcome: Equatable {
        var effect: String?
        var sound: String?
        /// Âm thanh phím đang TẮT mà theme vừa đặt kiểu âm ⇒ app hiện gợi ý (không chặn) kèm nút "Bật".
        var soundHint: Bool
    }

    /// Logic thuần: `st` = kiểu thực dùng của theme vừa chọn (ThemeSettings.effectiveKeyStyle).
    static func plan(_ st: KeyStyle, soundOn: Bool, effectAllowed: (String) -> Bool,
                     soundAllowed: (String) -> Bool) -> Outcome {
        let e = st.effect.flatMap { effectAllowed($0) ? $0 : nil }
        let snd = st.sound.flatMap { soundAllowed($0) ? $0 : nil }
        return Outcome(effect: e, sound: snd, soundHint: snd != nil && !soundOn)
    }

    /// Hiệu ứng có trên máy + được phép (Plus) — id chưa có (hiệu ứng mới chưa vào bản này) ⇒ bỏ qua.
    static func effectAllowed(_ id: String) -> Bool { KeyEffect(rawValue: id).map(KeyEffectGate.allows) ?? false }
    /// Kiểu âm dựng sẵn (kiểu âm không thuộc Plus — trang Âm thanh gõ chọn tự do).
    static func soundAllowed(_ id: String) -> Bool { KeySoundStyle.presetIDs.contains(id) }

    /// Gọi NGAY sau khi lưu theme vừa chọn. Ghi App Group (cùng khoá trang Âm thanh / Hiệu ứng).
    @discardableResult
    static func applyOnSelect(_ st: KeyStyle, to d: UserDefaults?) -> Outcome {
        let r = plan(st, soundOn: d?.bool(forKey: soundOnKey) ?? false, effectAllowed: effectAllowed, soundAllowed: soundAllowed)
        if let e = r.effect { d?.set(e, forKey: KeyEffect.key) }
        if let s = r.sound { d?.set(s, forKey: soundStyleKey) }
        return r
    }

    static var hintText: String { L("Giao diện này có âm thanh riêng — bật Âm thanh phím để nghe.") }
}

/// Trang "Chọn giao diện" (logic thuần — test được; Android: ThemePicker trong KeyboardTheme.kt).
enum ThemePicker {
    struct Section { let title: String; let themes: [KeyboardTheme] }
    /// "Miễn phí" (Hệ thống, OLED, Tương phản cao, Xám trung tính) rồi "Plus" (còn lại), giữ thứ tự khai báo.
    static var sections: [Section] {
        [Section(title: LK("Miễn phí"), themes: KeyboardTheme.allCases.filter { !$0.isPlus }),
         Section(title: "Plus", themes: KeyboardTheme.allCases.filter(\.isPlus))]
    }
    /// Chạm thẻ: chọn ngay nếu được phép; theme Plus bị khoá ⇒ nil (không đổi gì).
    static func select(_ t: KeyboardTheme, in s: ThemeSettings) -> ThemeSettings? {
        guard ThemeGate.allows(t) else { return nil }
        var n = s
        n.select(t)
        return n
    }
    /// Chạm thẻ theme tự tạo: cần Plus ⇒ không có thì nil (mở màn Plus).
    static func select(custom spec: ThemeSpec, in s: ThemeSettings) -> ThemeSettings? {
        guard ThemeGate.allowsCustom else { return nil }
        var n = s
        n.select(custom: spec)
        return n
    }

    enum Tap: Equatable { case select(ThemeSettings), openPlus }
    /// Chạm thẻ: chọn ngay; theme Plus bị khoá ⇒ mở màn VietTelex Plus (như Android).
    static func tap(_ t: KeyboardTheme, in s: ThemeSettings) -> Tap {
        select(t, in: s).map(Tap.select) ?? .openPlus
    }
}

/// Cổng Plus cho theme: dùng PlusGate thật (iOS/Shared) — `.premiumThemes` gồm
/// theme cao cấp + ảnh nền. Hệ thống/OLED/tương phản cao luôn miễn phí.
enum ThemeGate {
    static func allows(_ theme: KeyboardTheme) -> Bool {
        !theme.isPlus || PlusGate.isUnlocked(.premiumThemes)
    }
    static var allowsWallpaper: Bool { PlusGate.isUnlocked(.premiumThemes) }
}

/// Cài đặt giao diện (App Group) — app ghi, bàn phím đọc mỗi lần hiện.
struct ThemeSettings: Equatable {
    static let themeKey = "keyboardTheme"
    static let wallpaperKey = "wallpaperEnabled"
    static let dimKey = "wallpaperDim"        // % lớp phủ 0…80
    static let blurKey = "wallpaperBlur"      // bán kính mờ 0…20 (app áp khi lưu ảnh)
    static let versionKey = "wallpaperVersion" // đổi mỗi lần lưu ảnh → vứt cache
    static let cropKey = "wallpaperCrop"      // "x,y,w,h" chuẩn hoá theo ảnh gốc; thiếu = cắt giữa

    var theme: KeyboardTheme = .system
    /// Theme tự tạo ĐANG CHỌN ("Giao diện JSON", Plus) — có thì thay `theme` (khi đó `theme` = .system
    /// làm dự phòng). Bàn phím chỉ đọc theme này (CustomThemeStore.activeKey), không đọc cả kho.
    var custom: ThemeSpec?
    var wallpaper = false
    var dim = 30
    var blur = 0
    var version: Double = 0
    /// Khung cắt đã chỉnh (nil = ảnh cũ / chưa chỉnh → cắt giữa). Thuộc về ẢNH (như file),
    /// nên "Khôi phục giao diện gốc" giữ nguyên.
    var crop: WallpaperCrop?
    /// Độ trong suốt phím / ký tự 0…100 (miễn phí, mọi theme).
    var keyboardTransparency = 0
    var labelTransparency = 0
    /// Theme bật "Nền theo hệ thống" (tuỳ chọn RIÊNG từng theme có nền; mặc định không theme nào).
    var systemBackdropThemes: Set<KeyboardTheme> = []
    /// "Tuỳ chỉnh nâng cao" (Plus) RIÊNG từng theme: id theme (rawValue) → KeyStyle; theme chưa chỉnh
    /// không có mục. Lưu nguyên kể cả khi hết quyền; áp qua `effectiveKeyStyle`. Id lạ (bản mới hơn)
    /// giữ nguyên để khứ hồi.
    var keyStyles: [String: KeyStyle] = [:]

    /// Id theme đang chọn (có sẵn hoặc tự tạo) — khoá của `keyStyles`.
    var themeId: String { custom?.id ?? theme.rawValue }

    /// Tuỳ chỉnh của theme ĐANG CHỌN (màn Giao diện đọc/ghi qua đây). Gán mặc định ⇒ xoá mục.
    var keyStyle: KeyStyle {
        get { keyStyles[themeId] ?? .default }
        set { keyStyles[themeId] = newValue.isDefault ? nil : newValue }
    }
    func style(for t: KeyboardTheme) -> KeyStyle { keyStyles[t.rawValue] ?? .default }
    mutating func setStyle(_ st: KeyStyle, for t: KeyboardTheme) {
        keyStyles[t.rawValue] = st.isDefault ? nil : st
    }

    /// Chọn theme có sẵn (bỏ theme tự tạo).
    mutating func select(_ t: KeyboardTheme) { theme = t; custom = nil }
    /// Chọn theme tự tạo.
    mutating func select(custom spec: ThemeSpec) { theme = .system; custom = spec }

    /// "Khôi phục giao diện gốc": mọi chỉnh ở màn Giao diện về mặc định. Ảnh nền chỉ
    /// bỏ chọn (file giữ nguyên để bật lại); version giữ nguyên (không vứt cache vô cớ).
    func resetToDefaults() -> ThemeSettings {
        var s = ThemeSettings()
        s.version = version
        s.crop = crop
        return s
    }
    var isDefault: Bool { self == resetToDefaults() }

    /// Đọc + chuyển đổi trong bộ nhớ (KeyStyleStore.migrate — thuần, không ghi; bàn phím gọi mỗi lần
    /// hiện). App ghi bản đã chuyển một lần lúc khởi động (`migrateStored`).
    static func load(_ d: UserDefaults?) -> ThemeSettings {
        var s = ThemeSettings()
        guard let d else { return s }
        let m = KeyStyleStore.migrate(theme: d.string(forKey: themeKey),
                                      styles: KeyStyleStore.parse(d.string(forKey: KeyStyleStore.key)),
                                      legacy: KeyStyleStore.loadLegacy(d))
        // Id có sẵn ⇒ theme đó; id theme tự tạo ⇒ đọc (và kiểm lại) bản app đã chuẩn hoá; id lạ / đã bỏ /
        // dữ liệu hỏng ⇒ Hệ thống (mặc định), không crash.
        if let raw = m.theme {
            if let t = KeyboardTheme(rawValue: raw) { s.theme = t }
            else if KeyStyleStore.validId(raw) {
                s.custom = CustomThemeStore.active(d.string(forKey: CustomThemeStore.activeKey), id: raw)
            }
        }
        s.keyStyles = m.styles
        s.wallpaper = d.bool(forKey: wallpaperKey)
        if d.object(forKey: dimKey) != nil { s.dim = max(0, min(80, d.integer(forKey: dimKey))) }
        s.blur = max(0, min(20, d.integer(forKey: blurKey)))
        s.version = d.double(forKey: versionKey)
        s.crop = WallpaperCrop(serialized: d.string(forKey: cropKey))
        s.keyboardTransparency = KeyboardTransparency.clamp(d.integer(forKey: KeyboardTransparency.keyboardKey))
        s.labelTransparency = KeyboardTransparency.clamp(d.integer(forKey: KeyboardTransparency.labelKey))
        for t in KeyboardTheme.allCases {
            if let k = t.systemBackdropKey, d.bool(forKey: k) { s.systemBackdropThemes.insert(t) }
        }
        return s
    }

    /// Chuyển đổi đã lưu MỘT lần (app, lúc khởi động): khoá KeyStyle chung cũ → theme đang chọn,
    /// "Trắng hồng" → Hệ thống + Màu nhấn hồng. Không có gì cũ ⇒ không ghi gì. Lặp lại vô hại.
    @discardableResult
    static func migrateStored(_ d: UserDefaults?) -> Bool {
        guard let d, KeyStyleStore.needsMigration(theme: d.string(forKey: themeKey),
                                                  hasLegacy: KeyStyleStore.hasLegacy(d)) else { return false }
        load(d).save(d)
        return true
    }

    func save(_ d: UserDefaults?) {
        d?.set(themeId, forKey: Self.themeKey)
        // Bàn phím chỉ đọc theme tự tạo đang chọn — bản chuẩn hoá (đã kiểm) ở khoá riêng.
        if let custom { d?.set(custom.canonical, forKey: CustomThemeStore.activeKey) }
        else { d?.removeObject(forKey: CustomThemeStore.activeKey) }
        d?.set(wallpaper, forKey: Self.wallpaperKey)
        d?.set(dim, forKey: Self.dimKey)
        d?.set(blur, forKey: Self.blurKey)
        d?.set(version, forKey: Self.versionKey)
        if let crop { d?.set(crop.serialized, forKey: Self.cropKey) } else { d?.removeObject(forKey: Self.cropKey) }
        d?.set(keyboardTransparency, forKey: KeyboardTransparency.keyboardKey)
        d?.set(labelTransparency, forKey: KeyboardTransparency.labelKey)
        for t in KeyboardTheme.allCases {
            if let k = t.systemBackdropKey { d?.set(systemBackdropThemes.contains(t), forKey: k) }
        }
        // Chưa từng chỉnh: không tạo khoá (0 chi phí đọc). Đã có khoá thì ghi (kể cả "{}" sau đặt lại).
        let styles = KeyStyleStore.serialize(keyStyles)
        if styles != KeyStyleStore.empty || d?.object(forKey: KeyStyleStore.key) != nil {
            d?.set(styles, forKey: KeyStyleStore.key)
        }
        KeyStyleStore.removeLegacy(d)
    }

    /// Theme thực dùng sau cổng Plus (hết quyền → về Hệ thống, không crash/không trắng).
    var effectiveTheme: KeyboardTheme { ThemeGate.allows(theme) ? theme : .system }
    /// Theme tự tạo thực dùng: hết Plus ⇒ nil (vẽ Hệ thống; dữ liệu giữ nguyên để mua lại là có lại).
    var effectiveCustom: ThemeSpec? { ThemeGate.allowsCustom ? custom : nil }
    /// Tuỳ chỉnh nâng cao thực dùng: hết quyền Plus ⇒ mặc định (giá trị lưu giữ nguyên để
    /// mua lại là có lại).
    /// Bo góc / phông chưa chỉnh ⇒ của theme (Hồng: tròn trịa).
    var effectiveKeyStyle: KeyStyle {
        if let c = effectiveCustom { return effectiveStyle(id: c.id ?? "", typography: c.typography) }
        return effectiveStyle(for: effectiveTheme)
    }
    /// Như `effectiveKeyStyle` cho theme `t` bất kỳ (thẻ "Chọn giao diện" xem trước tuỳ chỉnh riêng).
    func effectiveStyle(for t: KeyboardTheme) -> KeyStyle {
        effectiveStyle(id: t.rawValue, typography: t.spec?.typography)
    }
    func effectiveStyle(id: String, typography: KeyStyle?) -> KeyStyle {
        var s = ThemeGate.allowsAdvanced ? (keyStyles[id] ?? .default) : .default
        if let t = typography {
            // Phông người dùng chọn (hệ thống hoặc tải về) thắng phông của theme.
            let userSystemFont = s.font != .standard && s.assets.font == nil
            if s.corner == nil { s.corner = t.corner }
            if s.fontScale == nil { s.fontScale = t.fontScale }
            if s.font == .standard { s.font = t.font }
            if s.weight == .regular { s.weight = t.weight }
            if s.sound == nil { s.sound = t.sound }
            if s.effect == nil { s.effect = t.effect }
            if s.swipe == nil { s.swipe = t.swipe }
            if s.game == nil { s.game = t.game }
            s.assets = s.assets.merged(over: t.assets)
            if userSystemFont { s.assets.font = nil }
            if s.assets.font != nil { s.font = .standard }
        }
        return s
    }

    /// Palette đã áp tuỳ chỉnh (vá chế độ → nền hệ thống → màu chữ/phím → màu nhấn), TRƯỚC ảnh nền /
    /// độ trong suốt. Dùng cho bàn phím, thẻ "Chọn giao diện" và "Chép JSON".
    static func styled(_ base: KeyboardPalette, style st: KeyStyle, systemDark: Bool, backdrop: Bool) -> KeyboardPalette {
        var p = st.applyPatch(to: base, dark: systemDark)
        if backdrop { p = p.onSystemBackdrop(systemDark: systemDark) }
        p = st.applyColors(to: p)
        p.keyLabelPinned = st.labelColor != nil || p.keyLabelPinned
        return st.applyAccent(to: p)
    }

    /// Thẻ "Chọn giao diện": palette gốc của `t` + màu tuỳ chỉnh RIÊNG của nó (không ảnh nền / độ trong
    /// suốt / nền hệ thống — thẻ chỉ để nhận ra theme). Chưa chỉnh ⇒ đúng palette gốc.
    func cardPalette(for t: KeyboardTheme, systemDark: Bool) -> KeyboardPalette {
        Self.styled(t.palette(systemDark: systemDark), style: effectiveStyle(for: t), systemDark: systemDark, backdrop: false)
    }
    func cardPalette(custom c: ThemeSpec, systemDark: Bool) -> KeyboardPalette {
        Self.styled(c.palette(dark: systemDark), style: effectiveStyle(id: c.id ?? "", typography: c.typography),
                    systemDark: systemDark, backdrop: false)
    }

    /// "Chép JSON": theme thực thấy (gồm tuỳ chỉnh) dạng đặc tả đầy đủ — miễn phí.
    func exportSpec(for t: KeyboardTheme) -> ThemeSpec {
        let st = effectiveStyle(for: t)
        // Hệ thống / Kính (vẽ theo nền tảng, không có JSON gốc): xuất màu đã giải trên máy này.
        return ThemeSpec.export(id: t.rawValue, nameVi: t.spec?.nameVi ?? (t == .glass ? "Kính" : "Hệ thống"),
                                nameEn: t.spec?.nameEn ?? (t == .glass ? "Glass" : "System"),
                                light: cardPalette(for: t, systemDark: false), dark: cardPalette(for: t, systemDark: true),
                                style: st)
    }
    func exportSpec(custom c: ThemeSpec) -> ThemeSpec {
        let st = effectiveStyle(id: c.id ?? "", typography: c.typography)
        return ThemeSpec.export(id: c.id, nameVi: c.nameVi, nameEn: c.nameEn,
                                light: cardPalette(custom: c, systemDark: false), dark: cardPalette(custom: c, systemDark: true),
                                style: st)
    }
    /// Ảnh nền chỉ bật khi có quyền Plus VÀ file tồn tại.
    func wallpaperActive(fileExists: Bool) -> Bool {
        wallpaper && fileExists && ThemeGate.allowsWallpaper
    }

    /// Nền bàn phím để TRONG — lộ vật liệu bàn phím hệ thống, cùng màu dải 🌐/🎤 iOS vẽ bên
    /// dưới (kính iOS 26/27, sáng lẫn tối). Chỉ theme nền trong suốt (Hệ thống, Kính) không
    /// ảnh nền; theme có nền riêng (Tối OLED / Tương phản cao = đen tuyền, pastel) và ảnh nền
    /// tự vẽ nền ⇒ chấp nhận lệch màu với dải hệ thống. Độ trong suốt phím không đổi quyết
    /// định này (theme trong suốt vẫn trong suốt).
    func clearBackground(systemDark: Bool, wallpaperActive: Bool) -> Bool {
        !wallpaperActive && palette(systemDark: systemDark, wallpaperActive: false).background == nil
    }

    /// "Nền theo hệ thống" đang áp: theme có nền riêng + người dùng bật cho theme đó.
    /// Mặc định TẮT ⇒ 0 chi phí, như trước.
    var usesSystemBackdrop: Bool {
        effectiveCustom == nil && effectiveTheme.hasOwnBackground && systemBackdropThemes.contains(effectiveTheme)
    }

    func palette(systemDark: Bool, wallpaperActive: Bool) -> KeyboardPalette {
        let base = effectiveCustom?.palette(dark: systemDark) ?? effectiveTheme.palette(systemDark: systemDark)
        let p = Self.styled(base, style: effectiveKeyStyle, systemDark: systemDark,
                            backdrop: usesSystemBackdrop && !wallpaperActive)
        return (wallpaperActive ? p.overWallpaper() : p)
            .withTransparency(keyboard: keyboardTransparency, labels: labelTransparency,
                              systemDark: systemDark, wallpaper: wallpaperActive)
    }
}

// MARK: - Tuỳ chỉnh nâng cao (Plus): màu chữ/nền phím, bo góc, cỡ chữ, phông, độ đậm

/// Phông nhãn phím — CHỈ phông hệ thống (không nhúng phông: giữ nhẹ app). Id dùng chung
/// Android (Keys.KEY_LABEL_FONT); máy không có kiểu đó (Android không có "rounded") ⇒ mặc định.
enum KeyLabelFont: String, CaseIterable {
    /// SF Compact như stock (SF Pro nếu máy không có Compact).
    case standard = "default"
    case rounded, serif, mono, condensed

    var title: String {
        switch self {
        case .standard: return L("Mặc định")
        case .rounded: return L("Tròn")
        case .serif: return L("Có chân")
        case .mono: return L("Đơn cách")
        case .condensed: return L("Hẹp")
        }
    }
}

/// "Độ đậm" nhãn phím → độ đậm hệ thống.
enum KeyLabelWeight: String, CaseIterable {
    case light, regular, medium, bold, heavy

    var title: String {
        switch self {
        case .light: return L("Mỏng")
        case .regular: return L("Thường")
        case .medium: return L("Vừa")
        case .bold: return L("Đậm")
        case .heavy: return L("Rất đậm")
        }
    }
    var uiWeight: UIFont.Weight {
        switch self {
        case .light: return .light
        case .regular: return .regular
        case .medium: return .medium
        case .bold: return .bold
        case .heavy: return .heavy
        }
    }
}

/// "Tuỳ chỉnh nâng cao" ở Cài đặt → Giao diện (Plus), RIÊNG từng theme (ThemeSettings.keyStyles,
/// lưu bằng KeyStyleStore). Mọi giá trị nil/mặc định = như cũ.
/// Màu: MỘT màu dùng cho cả sáng lẫn tối (đơn giản, đoán được); "Theo theme" = nil.
/// Android giữ y hệt (android/keyboard/.../KeyStyle.kt). Áp lúc dựng palette / plane (0 chi phí mỗi phím).
struct KeyStyle: Equatable {
    // Khoá App Group CŨ (≤ 1.5.12 / iOS 1.2.17: một bộ chung cho mọi theme) — chỉ còn để chuyển đổi
    // (KeyStyleStore.loadLegacy); app xoá sau khi chuyển. Giá trị canh: -1 / 0 = mặc định.
    static let labelColorKey = "keyLabelColor"     // 0xRRGGBB; -1 = theo theme
    static let fillColorKey = "keyFillColor"       // 0xRRGGBB; -1 = theo theme
    static let cornerKey = "keyCornerRadius"       // 0…100 (% nửa cạnh ngắn); -1 = mặc định
    static let fontScaleKey = "keyFontScale"       // 80…150 (%); 0 = mặc định
    static let fontKey = "keyLabelFont"            // KeyLabelFont.rawValue
    static let weightKey = "keyLabelWeight"        // KeyLabelWeight.rawValue
    static let fontScaleMin = 80, fontScaleMax = 150

    var labelColor: UInt32? = nil
    var fillColor: UInt32? = nil
    /// "Màu nhấn": phím Nhập/hành động, ⇧ bật, vệt gõ vuốt, glyph màu nhấn; nil = theo theme.
    var accentColor: UInt32? = nil
    /// 0 = chữ nhật, 100 = tròn/viên thuốc (bán kính = nửa cạnh ngắn của phím); nil = mặc định.
    var corner: Int?
    /// 80…150 (% cỡ mặc định); nil = mặc định.
    var fontScale: Int?
    var font: KeyLabelFont = .standard
    var weight: KeyLabelWeight = .regular
    /// Vá từng chế độ ("Giao diện JSON" → Sửa): màu nào có thì thay màu theme đúng chế độ đó.
    var light = ThemeSlots()
    var dark = ThemeSlots()
    /// Tệp tải về (phông / ảnh nền / tiền cảnh / skin phím — ThemeAssets.swift). Rỗng = như cũ.
    var assets = ThemeAssetSpec()
    /// Âm phím / hiệu ứng đi kèm theme ("sound" / "effect", ThemeExtraIds) — CHỈ áp lúc chọn theme (ThemeExtras).
    var sound: String? = nil
    var effect: String? = nil
    /// Nét vuốt theme ("swipe", ThemeExtraIds.swipes) — chỉ dùng khi chọn "Theo giao diện" (SwipeTrailPolicy).
    var swipe: String? = nil
    /// Trò chơi khi gõ của theme ("game", ThemeExtraIds.games) — bàn phím đọc từ kiểu thực dùng (MolePolicy).
    var game: String? = nil

    static let `default` = KeyStyle()
    var isDefault: Bool { self == .default }
    /// Có đổi chữ (phông / độ đậm / cỡ / phông tải về) — bật đường đo + kẹp chữ.
    var customizesLabels: Bool { font != .standard || weight != .regular || fontScale != nil || assets.font != nil }
    var labelScale: CGFloat { CGFloat(fontScale ?? 100) / 100 }

    static func parseColor(_ v: Int?) -> UInt32? {
        guard let v, v >= 0, v <= 0xFFFFFF else { return nil }
        return UInt32(v)
    }
    static func parseCorner(_ v: Int?) -> Int? {
        guard let v, v >= 0 else { return nil }
        return min(v, 100)
    }
    static func parseFontScale(_ v: Int?) -> Int? {
        guard let v, v > 0 else { return nil }
        return min(max(v, fontScaleMin), fontScaleMax)
    }

    /// Bán kính bo góc phím cỡ `size`: 0% = chữ nhật, 100% = nửa cạnh ngắn (phím vuông ⇒
    /// tròn, phím dài ⇒ viên thuốc). nil ⇒ `fallback` (bo mặc định).
    static func cornerRadius(percent: Int?, size: CGSize, fallback: CGFloat) -> CGFloat {
        guard let p = percent else { return fallback }
        let half = max(0, min(size.width, size.height)) / 2
        return half * CGFloat(min(max(p, 0), 100)) / 100
    }

    /// Màu phím theo lựa chọn (trước ảnh nền / độ trong suốt). Màu chữ do người dùng chọn
    /// được giữ nguyên; chỉ đổi nền ⇒ chữ theme đổi đen/trắng nếu không đọc được trên nền mới.
    /// Ô phóng to / popup đi theo để chữ trong đó luôn đọc được.
    func applyColors(to p: KeyboardPalette) -> KeyboardPalette {
        guard labelColor != nil || fillColor != nil else { return p }
        var q = p
        q.surfaceDark = p.surfaceDark ?? p.isDark   // thanh gợi ý / emoji giữ tông nền cũ
        if let f = fillColor {
            let c = RGBA(hex: f)
            q.keyFill = c
            // Phím khi đè: sẫm (nền sáng) / sáng (nền tối) hơn một chút.
            let toward: RGBA = c.luminance > 0.4 ? .black : .white
            q.specialFill = toward.alpha(0.18).over(c)
            q.balloon = c
            q.functionFill = nil      // màu người dùng chọn phủ MỌI phím
        }
        if let l = labelColor {
            q.ink = RGBA(hex: l)
            q.functionInk = nil       // chữ người dùng chọn: mọi phím cùng màu
        } else {
            let sys = KeyboardTransparency.systemBackdrop(dark: p.isDark)
            let behind = p.background?.over(sys) ?? sys
            q.ink = KeyboardTransparency.readable(p.ink, on: q.keyFill.over(behind))
            q.functionInk = p.functionInk.map { KeyboardTransparency.readable($0, on: q.fnFill.over(behind)) }
        }
        if RGBA.contrast(q.ink, q.balloon.over(.white)) < KeyboardTransparency.minLabelContrast {
            q.balloon = q.ink.luminance > 0.5 ? RGBA(hex: 0x3A3A3C) : .white
        }
        q.isDark = q.ink.luminance > 0.5
        return q
    }

    /// "Màu nhấn" thay màu nhấn của theme ở MỌI chỗ dùng: phím Nhập/hành động, ⇧ bật (accentShift),
    /// vệt gõ vuốt, glyph màu nhấn trên phím chức năng (theme có functionInk). Chữ trên nền nhấn giữ
    /// màu theme nếu còn đọc được (≥ 3:1), không thì đen/trắng (KeyboardTransparency.readable).
    /// Áp SAU applyColors (glyph đọc được trên nền phím mới). nil ⇒ y như cũ (0 chi phí).
    func applyAccent(to p: KeyboardPalette) -> KeyboardPalette {
        guard let a = accentColor else { return p }
        let c = RGBA(hex: a)
        var q = p
        q.accent = c
        q.accentInk = Self.accentInk(p.accentInk, on: c)
        q.trail = c.alpha(0.6)
        q.accentShift = true
        if p.functionInk != nil {
            let sys = KeyboardTransparency.systemBackdrop(dark: p.surfaceDark ?? p.isDark)
            let behind = p.background?.over(sys) ?? sys
            q.functionInk = KeyboardTransparency.readable(c, on: p.fnFill.over(behind))
        }
        return q
    }

    /// Chữ/icon trên nền nhấn `accent`: giữ `themeInk` nếu ≥ 3:1, không thì đen/trắng tương phản hơn.
    static func accentInk(_ themeInk: RGBA, on accent: RGBA) -> RGBA {
        KeyboardTransparency.readable(themeInk, on: accent)
    }

    /// Bản vá theo chế độ (light / dark) — áp TRƯỚC applyColors / applyAccent. Mặc định tự tính như theme
    /// JSON: balloon theo key, trail = nhấn 60%, accentInk tự tính. Viền trong suốt = bỏ viền; motif
    /// "none" = bỏ hoạ tiết. Không vá ⇒ y như cũ (0 chi phí).
    func applyPatch(to p: KeyboardPalette, dark d: Bool) -> KeyboardPalette {
        let s = d ? dark : light
        guard !s.isEmpty else { return p }
        let c = ThemeColorCode.rgba
        var q = p
        if let v = s.bg { q.background = c(v) }
        if let v = s.key { q.keyFill = c(v); q.balloon = c(v) }
        if let v = s.special { q.specialFill = c(v) }
        if let v = s.ink { q.ink = c(v); q.barInk = c(v); q.isDark = c(v).luminance > 0.5 }
        if let v = s.accent {
            q.accent = c(v)
            q.trail = c(v).alpha(0.6)
            q.accentInk = ThemeSpec.autoAccentInk(c(v))
            q.accentShift = true
        }
        if let v = s.accentInk { q.accentInk = c(v) }
        if let v = s.border { q.keyBorder = v >> 24 == 0 ? nil : c(v) }
        if let v = s.fn { q.functionFill = c(v) }
        if let v = s.fnInk { q.functionInk = c(v) }
        if let v = s.balloon { q.balloon = c(v) }
        if let v = s.trail { q.trail = c(v) }
        if let dc = s.deco {
            q.decoration = dc.motif.map { KeyboardDecoration(motif: $0, color: c(dc.color), density: dc.density, alt: dc.alt) }
        }
        if let fx = s.borderFx { q.rainbowBorder = fx == ThemeSlots.rainbow }
        if let sd = s.spaceDeco { q.spaceSoundhole = sd == ThemeSlots.soundhole }
        return q
    }

    /// Theme đầy đủ người dùng sửa (trình sửa JSON) → bản vá so với `base` (màu theme có sẵn từng chế độ)
    /// + kiểu chữ. Bỏ label / fill / accent dạng chung (màu đã nằm trong bản vá). `lostBg` = người dùng bỏ
    /// nền của theme có nền (không biểu diễn được — giữ nền).
    static func fromEdited(_ edited: ThemeSpec, baseLight: ThemeSlots, baseDark: ThemeSlots) -> (style: KeyStyle, lostBg: Bool) {
        let l = edited.slots(dark: false).patch(from: baseLight)
        let d = edited.slots(dark: true).patch(from: baseDark)
        var st = KeyStyle()
        st.light = l.patch
        st.dark = d.patch
        st.corner = edited.corner
        st.fontScale = edited.fontScale
        st.font = edited.font ?? .standard
        st.weight = edited.weight ?? .regular
        st.assets = edited.assets
        st.sound = edited.sound
        st.effect = edited.effect
        st.swipe = edited.swipe
        st.game = edited.game
        return (st, l.lostBg || d.lostBg)
    }
}

/// Lưu "Tuỳ chỉnh nâng cao" (= bản vá "Giao diện JSON") theo theme: MỘT khoá App Group `keyStyles` =
/// chuỗi JSON chuẩn (y hệt Android KeyStyleStore — sao lưu / iCloud chuyển nguyên chuỗi):
///   {"pink":{"accent":"#D6336C","corner":70},"system":{"dark":{"key":"#202020"},"fill":"#102030"}}
/// Trường (đều tuỳ chọn): label / fill / accent = "#RRGGBB" (áp cả sáng lẫn tối, chữ tự đọc được),
/// corner 0…100, fontScale 80…150, font, weight, light / dark = vá màu từng chế độ (khoá như theme JSON).
/// Theme không chỉnh gì thì không có mục; trống = "{}".
enum KeyStyleStore {
    static let key = "keyStyles"
    static let empty = "{}"
    /// Màu nhấn của "Trắng hồng" (đã bỏ) — người dùng theme đó chuyển sang Hệ thống + màu này.
    static let pureWhiteAccent: UInt32 = 0xD6336C
    static let removedPureWhite = "pureWhite"
    static let legacyKeys = [KeyStyle.labelColorKey, KeyStyle.fillColorKey, KeyStyle.cornerKey,
                             KeyStyle.fontScaleKey, KeyStyle.fontKey, KeyStyle.weightKey]
    /// "Nền theo hệ thống" của Trắng hồng — xoá cùng lúc chuyển.
    static let removedBackdropKey = "systemBackdropPureWhite"

    /// Id theme hợp lệ để lưu: ASCII chữ/số/_/-, ≤ 40 ký tự (Android cùng luật).
    static func validId(_ s: String) -> Bool {
        !s.isEmpty && s.utf8.count <= 40 && s.utf8.allSatisfy {
            ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x41 && $0 <= 0x5A) || ($0 >= 0x61 && $0 <= 0x7A) || $0 == 0x5F || $0 == 0x2D
        }
    }

    /// Cả kho bản vá: tối đa ~ (50 theme tự tạo + 13 có sẵn) × vài KB.
    static let limits: StrictJSON.Limits = {
        var l = StrictJSON.Limits()
        l.maxBytes = 512 * 1024
        l.maxMembers = 128
        return l
    }()

    /// Đọc CHẶT (ThemeSpecParser.override): mục nào có khoá lạ / màu sai ⇒ bỏ cả mục (theme đó vẽ như
    /// chưa chỉnh); chuỗi hỏng ⇒ rỗng. Không bao giờ crash.
    static func parse(_ raw: String?) -> [String: KeyStyle] {
        guard let raw, raw != empty, case .success(.object(let m)) = StrictJSON.parse(raw, limits: limits) else { return [:] }
        var out: [String: KeyStyle] = [:]
        for (id, v) in m where validId(id) {
            if let st = ThemeSpecParser.override(from: v), !st.isDefault { out[id] = st }
        }
        return out
    }

    static func json(_ st: KeyStyle) -> StrictJSON {
        var f: [(String, StrictJSON)] = []
        func rgb(_ v: UInt32) -> StrictJSON { .string(ThemeColorCode.format(0xFF00_0000 | (v & 0xFFFFFF))) }
        if let v = st.labelColor { f.append(("label", rgb(v))) }
        if let v = st.fillColor { f.append(("fill", rgb(v))) }
        if let v = st.accentColor { f.append(("accent", rgb(v))) }
        if let v = st.corner { f.append(("corner", .int(v))) }
        if let v = st.fontScale { f.append(("fontScale", .int(v))) }
        if st.font != .standard, st.assets.font == nil { f.append(("font", .string(st.font.rawValue))) }
        if let fa = st.assets.font { f.append(("font", ThemeSpec.json(fa))) }
        if st.weight != .regular { f.append(("weight", .string(st.weight.rawValue))) }
        ThemeSpec.appendImages(st.assets, to: &f)
        if let v = st.sound { f.append(("sound", .string(v))) }
        if let v = st.effect { f.append(("effect", .string(v))) }
        if let v = st.swipe { f.append(("swipe", .string(v))) }
        if let v = st.game { f.append(("game", .string(v))) }
        if !st.light.isEmpty { f.append(("light", ThemeSpec.json(st.light))) }
        if !st.dark.isEmpty { f.append(("dark", ThemeSpec.json(st.dark))) }
        return .object(f)
    }

    /// Chuỗi CHUẨN (StrictJSON.canonical: khoá sắp xếp, không khoảng trắng, màu "#RRGGBB") — trùng Android.
    static func serialize(_ m: [String: KeyStyle]) -> String {
        StrictJSON.object(m.compactMap { id, st in validId(id) && !st.isDefault ? (id, json(st)) : nil }).canonical
    }

    /// Chuẩn hoá chuỗi từ file sao lưu / iCloud; nil = không phải object JSON (bỏ qua).
    static func normalize(_ raw: String) -> String? {
        guard case .success(.object) = StrictJSON.parse(raw, limits: limits) else { return nil }
        return serialize(parse(raw))
    }

    static func hasLegacy(_ d: UserDefaults) -> Bool { legacyKeys.contains { d.object(forKey: $0) != nil } }

    /// Bộ chung cũ; nil = không có khoá cũ nào.
    static func loadLegacy(_ d: UserDefaults) -> KeyStyle? {
        guard hasLegacy(d) else { return nil }
        func int(_ k: String) -> Int? { (d.object(forKey: k) as? NSNumber)?.intValue }
        var s = KeyStyle()
        s.labelColor = KeyStyle.parseColor(int(KeyStyle.labelColorKey))
        s.fillColor = KeyStyle.parseColor(int(KeyStyle.fillColorKey))
        s.corner = KeyStyle.parseCorner(int(KeyStyle.cornerKey))
        s.fontScale = KeyStyle.parseFontScale(int(KeyStyle.fontScaleKey))
        s.font = d.string(forKey: KeyStyle.fontKey).flatMap(KeyLabelFont.init(rawValue:)) ?? .standard
        s.weight = d.string(forKey: KeyStyle.weightKey).flatMap(KeyLabelWeight.init(rawValue:)) ?? .regular
        return s
    }

    static func removeLegacy(_ d: UserDefaults?) {
        for k in legacyKeys { d?.removeObject(forKey: k) }
        d?.removeObject(forKey: removedBackdropKey)
    }

    static func needsMigration(theme: String?, hasLegacy: Bool) -> Bool {
        hasLegacy || theme == removedPureWhite
    }

    /// Chuyển đổi THUẦN (Android cùng quy tắc), áp lại lên kết quả của chính nó không đổi gì:
    /// 1. theme "pureWhite" (đã bỏ) ⇒ "system"; "system" chưa có màu nhấn ⇒ màu nhấn D6336C;
    /// 2. bộ chung cũ (khác mặc định) ⇒ theme ĐANG CHỌN (sau bước 1; id lạ ⇒ "system"), chỉ khi
    ///    theme đó chưa có mục riêng — không ghi đè thứ người dùng chỉnh sau này;
    /// 3. mục "pureWhite" (nếu có) bỏ.
    static func migrate(theme: String?, styles: [String: KeyStyle], legacy: KeyStyle?)
        -> (theme: String?, styles: [String: KeyStyle]) {
        let sys = KeyboardTheme.system.rawValue
        var t = theme, m = styles
        let fromPureWhite = t == removedPureWhite
        if fromPureWhite { t = sys }
        if let legacy, !legacy.isDefault {
            let id = t.flatMap(KeyboardTheme.init(rawValue:))?.rawValue ?? sys
            if m[id] == nil { m[id] = legacy }
        }
        if fromPureWhite {
            var st = m[sys] ?? .default
            if st.accentColor == nil { st.accentColor = pureWhiteAccent; m[sys] = st }
        }
        m[removedPureWhite] = nil
        return (t, m)
    }
}

/// Số đo mực chữ theo em (đo một lần mỗi phông + độ đậm, CTLine — có thay phông dự phòng như
/// lúc vẽ thật). Dùng để kẹp cỡ chữ: chữ rộng nhất vừa bề ngang phím, dấu chồng (Ễ, Ỗ) và
/// phần dưới dòng (g, ỵ) nằm trọn trong phím / ô phóng to.
struct KeyLabelEm: Equatable {
    /// Bề ngang glyph rộng nhất / em.
    var width: CGFloat
    /// Mực trên baseline / dưới baseline (đều dương) theo em.
    var ascent: CGFloat
    var descent: CGFloat
    /// Hộp dòng của phông (UIFont.ascender, −descender) theo em — UILabel căn giữa hộp này.
    var lineAscender: CGFloat
    var lineDescender: CGFloat
    var inkHeight: CGFloat { ascent + descent }

    /// Mẫu chữ có thể hiện TRÊN phím (chữ hoa có dấu mũ/móc, không dấu thanh).
    static let keySample = "WMĐÂĂÊÔƠƯgjpqy"
    /// Mẫu chữ ô phóng to / popup ký tự phụ (dấu chồng).
    static let stackedSample = "ỄẪỖẰẲỮỂgjpqyỵỹ"

    static func measure(_ font: UIFont, sample: String) -> KeyLabelEm {
        let s = font.pointSize
        guard s > 0 else { return KeyLabelEm(width: 0, ascent: 0, descent: 0, lineAscender: 0, lineDescender: 0) }
        var maxW: CGFloat = 0, top: CGFloat = 0, bottom: CGFloat = 0
        for ch in sample {
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: String(ch), attributes: [.font: font]))
            let ink = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
            maxW = max(maxW, ink.maxX, CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)))
            top = max(top, ink.maxY)
            bottom = max(bottom, -ink.minY)
        }
        return KeyLabelEm(width: maxW / s, ascent: top / s, descent: bottom / s,
                          lineAscender: font.ascender / s, lineDescender: -font.descender / s)
    }
}

/// Kẹp cỡ + baseline nhãn phím (thuần — test được).
enum KeyLabelFit {
    static let sidePad: CGFloat = 3
    static let vPad: CGFloat = 1

    /// Cỡ lớn nhất ≤ `want` để glyph rộng nhất vừa bề ngang và mực (trên + dưới baseline)
    /// vừa chiều cao phím.
    static func size(want: CGFloat, em: KeyLabelEm, keyWidth: CGFloat, keyHeight: CGFloat) -> CGFloat {
        var s = want
        // ×0.98: chừa sai số cỡ quang học (đo một cỡ, vẽ cỡ khác).
        if em.width > 0, keyWidth > 0 { s = min(s, (keyWidth - 2 * sidePad) / em.width * 0.98) }
        if em.inkHeight > 0, keyHeight > 0 { s = min(s, (keyHeight - 2 * vPad) / em.inkHeight) }
        return max(s, 1)
    }

    /// Baseline (pt dưới đỉnh phím): giữ `preferred` (baseline stock) nếu mực vẫn trong phím,
    /// không thì dời vừa đủ.
    static func baseline(preferred: CGFloat, size: CGFloat, em: KeyLabelEm, keyHeight: CGFloat) -> CGFloat {
        let lo = vPad + em.ascent * size, hi = keyHeight - vPad - em.descent * size
        guard lo <= hi else { return (lo + hi) / 2 }
        return min(max(preferred, lo), hi)
    }

    /// Cỡ lớn nhất ≤ `want` để chữ trong UILabel CĂN GIỮA hộp dòng (ô phóng to, popup) cao
    /// `height` không bị cắt mực trên/dưới (UILabel cắt nội dung theo bounds).
    static func centeredSize(want: CGFloat, em: KeyLabelEm, height: CGFloat) -> CGFloat {
        let line = em.lineAscender + em.lineDescender
        let over = max(0, em.ascent - em.lineAscender, em.descent - em.lineDescender)
        let need = line + 2 * over
        guard need > 0, height > 0 else { return want }
        return max(1, min(want, height / need))
    }
}

/// Phông nhãn phím đã giải (phông + độ đậm + hệ số cỡ) — KeyboardView giữ một bản tĩnh,
/// đặt lại mỗi lần hiện; UIFont cache theo cỡ trong bản này.
final class KeyLabelFonts {
    let font: KeyLabelFont
    let weight: KeyLabelWeight
    let scale: CGFloat
    /// Có tuỳ chỉnh chữ — false ⇒ đường cũ y nguyên (không đo, không kẹp).
    let active: Bool
    private let compact: UIFontDescriptor?
    /// Phông tải về (theme JSON "font": {…}) đã nạp từ App Group; nil = phông hệ thống (`font`).
    let custom: CTFontDescriptor?
    private var cache: [CGFloat: UIFont] = [:]
    private var emCache: [String: KeyLabelEm] = [:]

    init(style: KeyStyle, compact: UIFontDescriptor?, custom: CTFontDescriptor? = nil) {
        font = style.font; weight = style.weight; scale = style.labelScale
        active = style.customizesLabels
        self.compact = compact
        self.custom = custom
    }

    /// Cùng phông tải về (đối tượng mô tả) — đổi theme ⇒ dựng lại.
    func sameCustom(_ d: CTFontDescriptor?) -> Bool {
        switch (custom, d) {
        case (nil, nil): return true
        case let (a?, b?): return a === b
        default: return false
        }
    }

    private func makeFont(size: CGFloat) -> UIFont {
        if let custom { return CTFontCreateWithFontDescriptor(custom, size, nil) as UIFont }
        return Self.make(font, weight, size: size, compact: compact)
    }

    /// Phông ở đúng cỡ `size` (nơi gọi tự nhân `scale` nếu cần).
    func font(size: CGFloat) -> UIFont {
        if let f = cache[size] { return f }
        let f = makeFont(size: size)
        if cache.count > 64 { cache.removeAll() }
        cache[size] = f
        return f
    }

    static func make(_ design: KeyLabelFont, _ weight: KeyLabelWeight, size: CGFloat,
                     compact: UIFontDescriptor?) -> UIFont {
        let w = weight.uiWeight
        switch design {
        case .standard:
            guard let c = compact else { return .systemFont(ofSize: size, weight: w) }
            if weight == .regular { return UIFont(descriptor: c, size: size) }
            let d = c.addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: w]])
            return UIFont(descriptor: d, size: size)
        case .rounded, .serif, .mono:
            let sd: UIFontDescriptor.SystemDesign = design == .rounded ? .rounded : design == .serif ? .serif : .monospaced
            let base = UIFont.systemFont(ofSize: size, weight: w)
            return base.fontDescriptor.withDesign(sd).map { UIFont(descriptor: $0, size: size) } ?? base
        case .condensed:
            return .systemFont(ofSize: size, weight: w, width: .condensed)
        }
    }

    /// Phông nhãn của ô xem trước trong APP (ThemePreview) — CÙNG luật với bàn phím (`makeFont`): phông tải về đã
    /// có trong kho (`custom`) ⇒ chính nó (bỏ độ đậm như bàn phím); chưa tải ⇒ phông hệ thống của kiểu (bàn phím
    /// cũng dự phòng như vậy). nil = không tuỳ chỉnh chữ (ô xem trước giữ `.system`).
    /// Bug 19/10/2026 (iPhone 13 mini): ô xem trước chỉ đọc `style.font` (= .standard khi chọn phông tải về) ⇒ chọn
    /// phông "Vt" tải về xong ô xem trước vẫn phông hệ thống.
    static func previewFont(_ style: KeyStyle, custom: CTFontDescriptor?, size: CGFloat) -> UIFont? {
        guard style.customizesLabels else { return nil }
        if style.assets.font != nil, let custom { return CTFontCreateWithFontDescriptor(custom, size, nil) as UIFont }
        return make(style.font, style.weight, size: size, compact: nil)
    }

    /// Số đo em (đo ở cỡ thật của nhãn phím ~24pt — SF / New York đổi nét theo cỡ quang học,
    /// đo ở cỡ khác lệch bề ngang; một lần cho mỗi mẫu).
    func em(_ sample: String) -> KeyLabelEm {
        if let e = emCache[sample] { return e }
        let e = KeyLabelEm.measure(makeFont(size: 24), sample: sample)
        emCache[sample] = e
        return e
    }
}

extension ThemeGate {
    /// "Tuỳ chỉnh nâng cao" đi cùng quyền theme cao cấp (Plus).
    static var allowsAdvanced: Bool { PlusGate.isUnlocked(.premiumThemes) }
    /// Theme tự tạo / dán / sửa JSON (Plus). "Chép JSON" luôn miễn phí.
    static var allowsCustom: Bool { PlusGate.isUnlocked(.premiumThemes) }
}
