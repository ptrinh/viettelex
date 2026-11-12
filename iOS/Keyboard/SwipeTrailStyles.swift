// "Hiệu ứng nét vuốt" (Gõ vuốt → Hiệu ứng nét vuốt): Tắt, Đơn giản (mặc định, vệt cũ), Lửa, Điện, Bút lông,
// Cầu vồng, Neon, Bụi sao, Pháo hoa cuối nét, Plasma, Ảo ảnh, Tan chảy, Vệt lặp, Phím sáng theo đường, Thư pháp,
// Sao chổi, Đom đóm, Ma trận, Cánh hoa, Theo giao diện. "Tắt" + "Đơn giản" miễn phí; còn lại Plus —
// chưa có Plus ⇒ vẽ "Đơn giản" (giá trị lưu giữ nguyên). Song sinh android/keyboard/.../SwipeTrailStyle.kt
// (cùng khoá `swipeTrail`, cùng id, cùng hàm thuần: nhiễu tia điện, độ dày bút lông, quỹ đạo hạt).
//
// Luật hiệu năng (gõ vuốt KHÔNG được chậm đi):
//  • Tắt ⇒ KeyboardView không dựng renderer (trail == nil) — đường vuốt chỉ đọc một optional.
//  • Vệt = MỘT path dựng lại mỗi lần chạm di chuyển (như trước). Kiểu chỉ đổi các lớp nét / gradient / quầng
//    — dựng MỘT lần lúc cấu hình (configure), mọi lớp nét dùng chung path đó.
//  • Hạt (Lửa, Bụi sao, Pháo hoa): pool ≤ 24 layer dựng lúc cấu hình, sinh tối đa mỗi N điểm; bắn = đổi
//    position + beginTime (render server chạy animation) — không cấp phát mỗi lần di chuyển.
//  • Vệt tắt hẳn ⇒ settle(): gỡ mọi animation (nhấp nháy điện, mờ dần, hạt) — 0 animation chạy khi nghỉ.
//  • Ảo ảnh / Tan chảy / Vệt lặp (nặng nhất): vẫn MỘT path. Ảo ảnh = 5 bản xoay của CÙNG path qua
//    CAReplicatorLayer (không dựng 6 path), màu = MỘT gradient nón xoay trên render server; Tan chảy = đổi màu
//    + "thở" bằng animation CA (strokeColor / lineWidth); Vệt lặp = 3 lớp bóng dùng chung path, dời bằng
//    transform. Mọi animation lặp gắn lúc begin, gỡ lúc settle.
//  • Phím sáng theo đường: pool ≤ 12 layer sáng dựng lúc cấu hình; khung phím nhận MỘT lần đầu cú vuốt
//    (setKeys); mỗi điểm chỉ dò ≤ ~33 khung (không cấp phát). Đổi phím ⇒ đổi frame + beginTime của layer
//    (animation mờ gắn sẵn, như hạt) — 0 animation mới mỗi lần di chuyển.
//  • Thư pháp: dải kín như Bút lông (MỘT path); dấu triện đỏ dựng một lần, nhấc tay chỉ đổi position + beginTime.
//  • Sao chổi: MỘT path, 4 đoạn (strokeStart/End như Tan chảy) + đầu sáng = 2 layer tròn dựng sẵn, chỉ dời position.
//  • Đom đóm / Ma trận / Cánh hoa: pool hạt như Lửa; chữ Ma trận = path glyph dựng MỘT lần (static), bắn chỉ đổi path.
import UIKit
import CoreText

/// Kiểu nét vuốt (giá trị lưu App Group / sao lưu = rawValue).
enum SwipeTrailStyle: String, CaseIterable {
    case none, simple, fire, electric, brush, rainbow, neon, stardust, firework, plasma, kaleidoscope, melt, chroma,
         keys, calligraphy, comet, firefly, matrix, petals, theme

    static let key = "swipeTrail"
    static let defaultValue: SwipeTrailStyle = .simple

    /// Giá trị lạ / thiếu ⇒ Đơn giản.
    static func parse(_ raw: Any?) -> SwipeTrailStyle {
        (raw as? String).flatMap(SwipeTrailStyle.init(rawValue:)) ?? defaultValue
    }
    static func load(_ d: UserDefaults?) -> SwipeTrailStyle { parse(d?.object(forKey: key)) }
    /// Kiểu hiện ở dòng cài đặt: kiểu Plus khi chưa có Plus ⇒ Đơn giản (giá trị lưu giữ nguyên).
    static func displayed(_ raw: Any?, plus: Bool = SwipeTrailGate.allows) -> SwipeTrailStyle {
        let s = parse(raw)
        return s.isPlus && !plus ? .simple : s
    }

    /// Id hợp lệ cho "swipe" của theme JSON: mọi kiểu cụ thể (không có "theme").
    static let themeIds: [String] = allCases.filter { $0 != .theme }.map(\.rawValue)

    var title: String {
        switch self {
        case .none: return L("Tắt")
        case .simple: return L("Đơn giản")
        case .fire: return L("Lửa")
        case .electric: return L("Điện")
        case .brush: return L("Bút lông")
        case .rainbow: return L("Cầu vồng")
        case .neon: return L("Neon")
        case .stardust: return L("Bụi sao")
        case .firework: return L("Pháo hoa cuối nét")
        case .plasma: return L("Plasma")
        case .kaleidoscope: return L("Ảo ảnh")
        case .melt: return L("Tan chảy")
        case .chroma: return L("Vệt lặp")
        case .keys: return L("Phím sáng theo đường")
        case .calligraphy: return L("Thư pháp")
        case .comet: return L("Sao chổi")
        case .firefly: return L("Đom đóm")
        case .matrix: return L("Ma trận")
        case .petals: return L("Cánh hoa")
        case .theme: return L("Theo giao diện")
        }
    }

    /// Tắt + Đơn giản miễn phí; còn lại (cả "Theo giao diện") thuộc Plus.
    var isPlus: Bool { self != .none && self != .simple }

    /// Sinh hạt mỗi N điểm của đường vuốt (0 = không hạt dọc đường).
    var spawnEvery: Int {
        switch self {
        case .fire: return 3
        case .stardust: return 4
        case .plasma: return 5
        case .melt: return 4
        case .firefly: return 3
        case .matrix: return 3
        case .petals: return 4
        default: return 0
        }
    }
    /// Có pool hạt (dọc đường hoặc chùm pháo hoa lúc nhấc tay).
    var usesParticles: Bool { spawnEvery > 0 || self == .firework }
    /// Cần khung phím chữ (setKeys lúc bắt đầu vuốt): Phím sáng theo đường (sáng phím), Ma trận (chữ của phím).
    var usesKeys: Bool { self == .keys || self == .matrix }

    /// Các lớp nét (dưới → trên) — hàm thuần, Android cùng số. `base` = bề rộng vệt Đơn giản của nền tảng
    /// (iOS 6pt, Android 5dp); `trail` = màu vệt theme (ARGB); `accent` = màu nhấn (RGB).
    func strokes(base w: Double, trail: UInt32, accent: UInt32, dark: Bool) -> [SwipeTrailStroke] {
        let a = accent & 0xFFFFFF
        func alpha(_ rgb: UInt32, _ x: Double) -> UInt32 { (UInt32((x * 255).rounded()) << 24) | (rgb & 0xFFFFFF) }
        switch self {
        case .none, .theme: return []
        case .simple, .firework: return [SwipeTrailStroke(width: w, argb: trail)]
        case .fire:
            return [SwipeTrailStroke(width: w * 2.2, argb: 0x73FF_3B1F),
                    SwipeTrailStroke(width: w * 1.1, argb: 0xE6FF_8A1A),
                    SwipeTrailStroke(width: w * 0.45, argb: 0xFFFF_E08A)]
        case .electric:
            return [SwipeTrailStroke(width: w * 1.9, argb: 0x5939_D8FF),
                    SwipeTrailStroke(width: w * 0.9, argb: 0xB37F_E8FF),
                    SwipeTrailStroke(width: w * 0.35, argb: 0xFFFF_FFFF)]
        case .neon:
            return [SwipeTrailStroke(width: w * 2.8, argb: alpha(a, 0.18)),
                    SwipeTrailStroke(width: w * 1.6, argb: alpha(a, 0.40)),
                    SwipeTrailStroke(width: w * 0.6, argb: 0xFF00_0000 | SwipeTrailFx.mix(a, 0xFFFFFF, 0.65))]
        case .rainbow: return [SwipeTrailStroke(width: w, argb: 0xFFFF_FFFF, kind: .gradient)]
        case .brush: return [SwipeTrailStroke(width: 0, argb: dark ? 0xE6F2_F2F2 : 0xE61A_1A1A, kind: .fill)]
        case .stardust: return [SwipeTrailStroke(width: w * 0.45, argb: alpha(a, 0.55))]
        case .plasma:   // = hiệu ứng phím Plasma (PlasmaArc): quầng tím, thân tím nhạt, lõi gần trắng
            return [SwipeTrailStroke(width: w * 2.4, argb: 0x59B4_4CFF),
                    SwipeTrailStroke(width: w * 1.1, argb: 0xBFC7_7DFF),
                    SwipeTrailStroke(width: w * 0.4, argb: 0xFFF3_E0FF)]
        case .kaleidoscope:
            // Nhánh xoay (mảnh, mờ — nét thật vẫn dễ đọc) dưới nét thật tô bánh xe màu, lõi trắng trên cùng.
            return [SwipeTrailStroke(width: w * 0.6, argb: 0x73FF_FFFF, kind: .mirror),
                    SwipeTrailStroke(width: w * 1.3, argb: 0xFFFF_FFFF, kind: .conic),
                    SwipeTrailStroke(width: w * 0.35, argb: 0xD9FF_FFFF)]
        case .melt:
            // 3 đoạn cũ → mới (SwipeTrailFx.meltSegments): đoạn cũ mờ hơn. Màu + bề rộng đổi theo thời gian.
            return [0.45, 0.75, 1.0].map {
                SwipeTrailStroke(width: w * 1.5, argb: alpha(SwipeTrailFx.hueWheel[0], $0), kind: .melt)
            }
        case .chroma:
            // 3 bóng đỏ / lục / lam lệch nhau (SwipeTrailFx.chromaShift) dưới nét chính màu vệt theme.
            return [SwipeTrailStroke(width: w * 1.1, argb: 0x99FF_2D55, kind: .ghost),
                    SwipeTrailStroke(width: w * 1.1, argb: 0x9930_D158, kind: .ghost),
                    SwipeTrailStroke(width: w * 1.1, argb: 0x990A_84FF, kind: .ghost),
                    SwipeTrailStroke(width: w * 0.6, argb: trail)]
        case .keys:     // nét rất mờ — phím sáng (SwipeTrailFx.keyGlow*) mới là chính
            return [SwipeTrailStroke(width: w * 0.35, argb: alpha(a, 0.3))]
        case .calligraphy:  // mực đậm nền sáng / mực sáng nền tối; bề rộng theo tốc độ × ngòi xiên (calliWidth)
            return [SwipeTrailStroke(width: 0, argb: dark ? 0xF0EE_E8DC : 0xF014_1210, kind: .fill)]
        case .comet:
            // 4 đoạn cũ → mới (cometSegments): mảnh + màu nhấn mờ ở đuôi → dày + trắng ở đầu; rồi quầng + lõi đầu.
            let segs = (0..<4).map { i in
                SwipeTrailStroke(width: w * SwipeTrailFx.cometWidths[i],
                                 argb: alpha(SwipeTrailFx.mix(a, 0xFFFFFF, SwipeTrailFx.cometWhite[i]), SwipeTrailFx.cometAlpha[i]),
                                 kind: .segment)
            }
            return segs + [SwipeTrailStroke(width: w * 4.4, argb: alpha(a, 0.28), kind: .head),
                           SwipeTrailStroke(width: w * 1.5, argb: 0xFFFF_FFFF, kind: .head)]
        case .firefly: return [SwipeTrailStroke(width: w * 0.3, argb: 0x40D8_FF5A)]
        case .matrix:
            return [SwipeTrailStroke(width: w * 1.2, argb: 0x2600_FF66),
                    SwipeTrailStroke(width: w * 0.35, argb: 0xD900_E05A)]
        case .petals: return [SwipeTrailStroke(width: w * 0.5, argb: 0x59F5_8FB1)]
        }
    }

    /// Màu hạt (RGB) — hạt i dùng màu i % count.
    func particleColors(accent: UInt32) -> [UInt32] {
        switch self {
        case .fire: return [0xFFC21A, 0xFF7A1A, 0xFF3B30]
        case .stardust: return [0xFFC93C, accent & 0xFFFFFF, 0xFFE7A0]
        case .firework: return [accent & 0xFFFFFF, 0xFFC93C, 0xFF5E7E, 0x4FC3F7]
        case .plasma: return [0xB44CFF, 0xE0B0FF, 0xF3E0FF]
        case .melt: return [SwipeTrailFx.hueWheel[0], SwipeTrailFx.hueWheel[2], SwipeTrailFx.hueWheel[4]]
        case .firefly: return [0xD8FF5A, 0xF2FF8A, 0xB6F23A]
        case .matrix: return [0x3DFF6E, 0x00E05A, 0xB6FFC8]
        case .petals: return [0xF58FB1, 0xFFC8DA, 0xF7A8C4]   // hồng sen + hồng nhạt
        default: return []
        }
    }
}

struct SwipeTrailStroke: Equatable {
    /// conic = nét tô bánh xe màu (Ảo ảnh), mirror = nhánh xoay quanh tâm vùng phím (Ảo ảnh), melt = một đoạn
    /// của nét Tan chảy (thứ tự = đoạn trong meltSegments), ghost = bóng lệch màu (Vệt lặp, thứ tự = chromaAngles),
    /// segment = một đoạn Sao chổi (thứ tự = đoạn trong cometSegments), head = chấm tròn ở đầu ngón (Sao chổi,
    /// width = đường kính; không dùng path chung).
    enum Kind { case stroke, fill, gradient, conic, mirror, melt, ghost, segment, head }
    /// pt (iOS) / dp (Android). Bút lông (fill) = 0: bề rộng theo tốc độ (SwipeTrailFx.brushWidth).
    var width: Double
    var argb: UInt32
    var kind: Kind = .stroke
}

/// Cổng Plus: đi cùng quyền theme cao cấp (như Hiệu ứng khi bấm phím).
enum SwipeTrailGate {
    static var allows: Bool { PlusGate.isUnlocked(.premiumThemes) }
    static func allows(_ s: SwipeTrailStyle) -> Bool { !s.isPlus || allows }
}

/// Kiểu thực vẽ — hàm thuần (test). Không bao giờ trả `.theme`.
enum SwipeTrailPolicy {
    /// - Tắt ⇒ Tắt (0 chi phí). Chưa có Plus / nguồn điện thấp ⇒ kiểu Plus về Đơn giản (giá trị lưu giữ nguyên).
    /// - "Theo giao diện" ⇒ "swipe" của theme đang dùng (thiếu / lạ ⇒ Đơn giản).
    static func active(setting: SwipeTrailStyle, plus: Bool, themeSwipe: String?, lowPower: Bool) -> SwipeTrailStyle {
        switch setting {
        case .none, .simple: return setting
        default: break
        }
        guard plus, !lowPower else { return .simple }
        guard setting == .theme else { return setting }
        guard let t = themeSwipe.flatMap(SwipeTrailStyle.init(rawValue:)), t != .theme else { return .simple }
        return t
    }

    /// Đọc lúc hiện bàn phím (applyAppearance) — không mỗi lần chạm.
    static func current(_ d: UserDefaults?, themeSwipe: String?) -> SwipeTrailStyle {
        let s = SwipeTrailStyle.load(d)
        guard s.isPlus else { return s }
        return active(setting: s, plus: SwipeTrailGate.allows(s), themeSwipe: themeSwipe,
                      lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled)
    }
}

// MARK: - Hàm thuần dùng chung hai nền tảng (Android SwipeTrailFx cùng số)

enum SwipeTrailFx {
    /// Trần hạt (pool cố định).
    static let particleCap = 24
    /// Số hạt chùm pháo hoa lúc nhấc tay.
    static let fireworkCount = 12
    /// Biên độ nhiễu tia điện (pt / dp).
    static let electricAmplitude = 4.5
    /// Tia plasma lượn rộng hơn tia điện (pt / dp).
    static let plasmaAmplitude = 6.0
    /// Bút lông: dày nhất (chậm) / mảnh nhất (nhanh), tốc độ coi là "nhanh" (pt/ms), hệ số làm mượt, số điểm vuốt nhọn.
    static let brushMax = 10.0, brushMin = 2.5, brushFast = 1.6, brushSmoothing = 0.35, brushTaper = 6
    /// Cầu vồng: các mốc màu (RGB) của gradient — lặp 2 vòng để nét ngắn vẫn đổi màu.
    static let rainbow: [UInt32] = [0xFF3B30, 0xFF9500, 0xFFCC00, 0x34C759, 0x00C7BE, 0x007AFF, 0xAF52DE,
                                    0xFF3B30, 0xFF9500, 0xFFCC00, 0x34C759, 0x00C7BE, 0x007AFF, 0xAF52DE]
    /// Sống lâu nhất của hạt (giây) — sau mờ dần + khoảng này thì settle (Đom đóm sống tới 1,2 s).
    static let maxParticleLife = 1.25
    /// Mờ dần lúc nhấc tay (giây).
    static let fade = 0.2

    /// Bánh xe màu (RGB) — Ảo ảnh (gradient nón quanh tâm) + Tan chảy (đổi màu theo thời gian). Mốc cuối = mốc
    /// đầu (khép vòng), các mốc cách đều.
    static let hueWheel: [UInt32] = [0xFF4D6D, 0xFFB84D, 0xE8FF4D, 0x4DFF88, 0x4DD8FF, 0x6B5BFF, 0xE04DFF, 0xFF4D6D]
    /// Ảo ảnh: số nhánh đối xứng xoay (gồm nét thật) quanh TÂM VÙNG PHÍM; một vòng xoay bánh xe màu (giây).
    static let kaleidoBranches = 6
    static let kaleidoHuePeriod = 4.0
    /// Tan chảy: một vòng màu (giây, chậm); chu kỳ "thở" (giây) + biên độ (× bề rộng); đuôi chảy xuống tối đa
    /// (pt / dp); mốc chia 3 đoạn cũ → mới theo chiều dài nét (đoạn cũ mờ hơn).
    static let meltHuePeriod = 6.0
    static let meltBreathPeriod = 1.2
    static let meltBreathAmp = 0.3
    static let meltDrip = 7.0
    static let meltSegments: [Double] = [0, 0.35, 0.7, 1]
    /// Vệt lặp: độ lệch bóng lúc vuốt / lúc tan hẳn (pt / dp), thời gian bóng trôi + mờ sau nhấc tay (giây),
    /// hướng lệch từng bóng (độ; đỏ lên trên, lục dưới phải, lam dưới trái — cách đều 120°).
    static let chromaOffset = 2.5
    static let chromaDrift = 8.0
    static let chromaFade = 0.45
    static let chromaAngles: [Double] = [-90, 30, 150]

    /// Đuôi nét (giây): Sao chổi dài gấp đôi, kiểu khác 0,3 s như vệt cũ.
    static let cometTail = 0.6
    static func tail(_ s: SwipeTrailStyle) -> Double { s == .comet ? cometTail : 0.3 }
    /// Sao chổi: mốc 4 đoạn theo chiều dài (cũ → mới; đoạn đầu ngắn, sáng nhất), bề rộng (× base), độ pha trắng,
    /// độ đậm từng đoạn.
    static let cometSegments: [Double] = [0, 0.4, 0.7, 0.88, 1]
    static let cometWidths: [Double] = [0.45, 0.8, 1.15, 1.5]
    static let cometWhite: [Double] = [0, 0.25, 0.6, 1]
    static let cometAlpha: [Double] = [0.3, 0.55, 0.8, 1]

    /// Phím sáng theo đường: tắt dần sau khi ngón rời phím (giây), số layer sáng tối đa, nới khung phím khi dò
    /// (pt / dp — khoảng nửa khe giữa hai phím), bo góc ô sáng.
    static let keyGlowFade = 0.35
    static let keyGlowCap = 12
    static let keyGlowSlop = 2.0
    static let keyGlowCorner = 6.0
    /// Độ sáng của phím đã rời được `s` giây (≤ 0 = ngón còn trong phím): tắt tuyến tính trong keyGlowFade.
    static func keyGlowAlpha(sinceLeave s: Double) -> Double { s <= 0 ? 1 : max(0, 1 - s / keyGlowFade) }
    /// Phím dưới điểm (x, y) (đã trừ độ dời điểm chọn phím): khung nới keyGlowSlop chứa điểm; nhiều khung ⇒ tâm
    /// gần nhất. −1 = không phím nào. Không cấp phát (Android cùng luật).
    static func keyHit(x: Double, y: Double, minX: [Double], minY: [Double], maxX: [Double], maxY: [Double]) -> Int {
        var best = -1, bestD = Double.infinity
        let s = keyGlowSlop
        for i in 0..<min(minX.count, minY.count, maxX.count, maxY.count) {
            guard x >= minX[i] - s, x <= maxX[i] + s, y >= minY[i] - s, y <= maxY[i] + s else { continue }
            let cx = (minX[i] + maxX[i]) / 2 - x, cy = (minY[i] + maxY[i]) / 2 - y
            let d = cx * cx + cy * cy
            if d < bestD { bestD = d; best = i }
        }
        return best
    }

    /// Thư pháp: góc ngòi (độ), bề rộng tối thiểu khi vuốt dọc theo ngòi (× bề rộng), hệ số dày so với Bút lông,
    /// mực đọng ở chỗ chậm: cộng tối đa (pt / dp) khi gần đứng yên, hết đọng từ tốc độ này (pt/ms).
    static let nibAngle = 35.0
    static let nibMin = 0.3
    static let calliScale = 1.25
    static let calliPoolMax = 4.0
    static let calliPoolSpeed = 0.25
    /// Ngòi xiên: nét vuông góc với ngòi dày nhất, dọc theo ngòi mảnh nhất (nibMin). Hướng (0, 0) ⇒ 1.
    static func nibFactor(dx: Double, dy: Double) -> Double {
        guard dx != 0 || dy != 0 else { return 1 }
        return nibMin + (1 - nibMin) * abs(sin(atan2(dy, dx) - nibAngle * .pi / 180))
    }
    /// Mực đọng (pt / dp cộng thêm) theo tốc độ (pt/ms).
    static func calliPool(speed: Double) -> Double { calliPoolMax * max(0, 1 - max(0, speed) / calliPoolSpeed) }
    /// Bề rộng nét thư pháp: Bút lông × calliScale × ngòi + mực đọng (không theo hướng — đọng thành vũng tròn).
    static func calliWidth(speed: Double, dx: Double, dy: Double) -> Double {
        brushWidth(speed: speed) * calliScale * nibFactor(dx: dx, dy: dy) + calliPool(speed: speed)
    }
    /// Dấu triện đỏ lúc nhấc tay: cạnh (pt / dp), bo góc, đời (giây), màu son (RGB), nghiêng (độ).
    static let sealSize = 15.0
    static let sealCorner = 3.5
    static let sealLife = 0.9
    static let sealColor: UInt32 = 0xD1352B
    static let sealTilt = -8.0
    /// Khung hình đóng dấu: phóng → 1 (ấn xuống) rồi giữ; hiện nhanh, giữ, mờ dần. Keyframes CA = Android.
    static let sealScaleT: [Double] = [0, 0.15, 1], sealScaleV: [Double] = [1.35, 1, 1]
    static let sealAlphaT: [Double] = [0, 0.08, 0.6, 1], sealAlphaV: [Double] = [0, 1, 1, 0]
    /// Nét khắc trắng trong dấu (đơn vị = cạnh dấu, tâm 0): khung trong (nửa cạnh sealInset) + 3 vạch ngang +
    /// vạch đứng + nét hất. Mỗi mục = (x0, y0, x1, y1).
    static let sealInset = 0.36
    static let sealMarks: [(Double, Double, Double, Double)] = [
        (-0.24, -0.2, -0.02, -0.2), (-0.24, 0, -0.02, 0), (-0.24, 0.2, -0.02, 0.2),
        (0.13, -0.24, 0.13, 0.24), (0.13, -0.02, 0.26, 0.12),
    ]
    /// Nội suy tuyến tính theo mốc (= CAKeyframeAnimation calculationMode linear). f ngoài 0…1 ⇒ mốc biên.
    static func keyframe(_ f: Double, _ t: [Double], _ v: [Double]) -> Double {
        guard let first = v.first, let last = v.last else { return 0 }
        if f <= t[0] { return first }
        for k in 1..<t.count where f <= t[k] {
            let u = (f - t[k - 1]) / max(1e-9, t[k] - t[k - 1])
            return v[k - 1] + (v[k] - v[k - 1]) * u
        }
        return last
    }

    /// Đom đóm: nhịp sáng (opacity keyframes) — chậm hơn Bụi sao.
    static let fireflyPulseT: [Double] = [0, 0.15, 0.35, 0.5, 0.7, 0.85, 1]
    static let fireflyPulseV: [Double] = [0, 1, 0.35, 0.95, 0.3, 0.7, 0]

    /// Ma trận: bảng chữ rơi (chữ thường a–z rồi 0–9).
    static let matrixGlyphs: [Character] = Array("abcdefghijklmnopqrstuvwxyz0123456789")
    /// Chữ thứ `n` (đếm hạt đã bắn trong cú vuốt): cứ 3 chữ có 1 chữ số; còn lại = chữ của phím đang đi qua
    /// (không có / không phải a–z ⇒ chữ số). Trả chỉ số trong matrixGlyphs. Không cấp phát.
    static func matrixGlyph(spawn n: Int, key: Character?) -> Int {
        let digit = 26 + ((n * 7) % 10 + 10) % 10
        guard n % 3 != 2, var c = key?.asciiValue else { return digit }
        if c >= 65, c <= 90 { c += 32 }
        guard c >= 97, c <= 122 else { return digit }
        return Int(c) - 97
    }

    /// Màu bánh xe ở tỉ lệ f (vòng tròn: f lấy phần lẻ) — nội suy tuyến tính giữa các mốc (= keyframes CA).
    static func cycleColor(_ f: Double) -> UInt32 {
        let n = hueWheel.count - 1
        var u = f - f.rounded(.down)
        if u < 0 { u += 1 }
        let x = u * Double(n)
        let k = min(n - 1, Int(x))
        return mix(hueWheel[k], hueWheel[k + 1], x - Double(k))
    }
    /// Hệ số bề rộng Tan chảy ở pha (số chu kỳ thở đã qua): 1 ± meltBreathAmp, hình sin.
    static func meltBreath(_ phase: Double) -> Double { 1 + meltBreathAmp * sin(2 * .pi * phase) }
    /// Độ chảy xuống (pt / dp) của điểm có tuổi u = tuổi / đuôi (0 = mới nhất, 1 = sắp hết): bậc hai.
    static func meltSag(_ u: Double) -> Double {
        let x = min(1, max(0, u))
        return meltDrip * x * x
    }
    /// Độ lệch bóng i ở tiến độ trôi e (0 = đang vuốt, 1 = tan hẳn; đã qua easeOut).
    static func chromaShift(_ i: Int, _ e: Double) -> (dx: Double, dy: Double) {
        let d = chromaOffset + (chromaDrift - chromaOffset) * min(1, max(0, e))
        let a = chromaAngles[i % chromaAngles.count] * .pi / 180
        return (cos(a) * d, sin(a) * d)
    }

    /// Nhiễu tia điện cho điểm `index` với `seed` (mỗi lần vẽ một seed ⇒ nhấp nháy) — −1…1, tất định.
    /// LCG 32-bit như FxRandom; Kotlin Int tràn số y hệt.
    static func jitter(seed: Int, index: Int) -> Double {
        var s = UInt32(truncatingIfNeeded: seed &* 31 &+ index) &* 2_654_435_761 &+ 1
        s = s &* 1_103_515_245 &+ 12345
        return Double((s >> 8) & 0xFFFF) / 65535 * 2 - 1
    }

    /// Bề rộng bút lông theo tốc độ (pt/ms): chậm = dày, nhanh = mảnh.
    static func brushWidth(speed: Double) -> Double {
        let f = min(1, max(0, speed) / brushFast)
        return brushMax - (brushMax - brushMin) * f
    }
    /// Làm mượt bề rộng giữa hai điểm liên tiếp.
    static func brushSmooth(_ prev: Double, _ target: Double) -> Double { prev + (target - prev) * brushSmoothing }
    /// Hệ số vuốt nhọn hai đầu (0…1) cho điểm i trong n điểm.
    static func brushTaperFactor(_ i: Int, _ n: Int) -> Double {
        let k = Double(brushTaper)
        return max(0.12, min(1, Double(i + 1) / k, Double(n - i) / k))
    }

    /// Trộn hai màu RGB (t = 0 ⇒ a, 1 ⇒ b).
    static func mix(_ a: UInt32, _ b: UInt32, _ t: Double) -> UInt32 {
        func ch(_ s: UInt32) -> UInt32 {
            let x = Double((a >> s) & 0xFF), y = Double((b >> s) & 0xFF)
            return UInt32((x + (y - x) * t).rounded()) << s
        }
        return ch(16) | ch(8) | ch(0)
    }

    /// Số quỹ đạo dựng sẵn của kiểu (hạt pool thứ i dùng quỹ đạo i % variants).
    static func variants(_ s: SwipeTrailStyle) -> Int {
        switch s {
        case .fire: return 8
        case .stardust: return 6
        case .firework: return fireworkCount
        case .plasma: return 6
        case .melt: return 6
        case .firefly: return 6
        case .matrix: return 6
        case .petals: return 8
        default: return 0
        }
    }

    /// Quỹ đạo hạt `v` (pt, giây, radian) — hàm thuần, Android y hệt.
    static func trajectory(_ s: SwipeTrailStyle, _ v: Int) -> KeyEffectTrajectory {
        let n = max(variants(s), 1)
        let t = n > 1 ? (Double(v) - Double(n - 1) / 2) / (Double(n - 1) / 2) : 0   // −1…1
        switch s {
        case .fire:     // tàn lửa bốc lên, lắc nhẹ
            return KeyEffectTrajectory(dx: t * 8, dy: -(22 + Double(v % 3) * 6), scaleFrom: 1, scaleTo: 0.25,
                                       rotation: 0, duration: 0.55 + Double(v % 3) * 0.06, sway: 2)
        case .stardust: // đứng gần chỗ cũ, xoay + nhấp nháy (opacity keyframes trong renderer)
            return KeyEffectTrajectory(dx: t * 3, dy: -3, scaleFrom: 0.4, scaleTo: 1.0,
                                       rotation: t * 0.8, duration: 0.9 + Double(v % 3) * 0.1)
        case .firework: // toả tròn đều
            let ang = Double(v) * 2 * .pi / Double(fireworkCount)
            let d = 30 + Double(v % 2) * 6
            return KeyEffectTrajectory(dx: cos(ang) * d, dy: sin(ang) * d, scaleFrom: 1, scaleTo: 0.35,
                                       rotation: 0, duration: 0.6)
        case .plasma:   // tia lửa tím bắn ngắn ra hai bên nét, tắt nhanh
            let up = v % 2 == 0 ? -1.0 : 1.0
            return KeyEffectTrajectory(dx: t * 10, dy: up * (6 + Double(v % 3) * 3), scaleFrom: 1, scaleTo: 0.2,
                                       rotation: 0, duration: 0.32 + Double(v % 3) * 0.05)
        case .melt:     // giọt nhỏ khỏi nét, rơi xuống rồi tan
            return KeyEffectTrajectory(dx: t * 2, dy: 10 + Double(v % 3) * 4, scaleFrom: 1, scaleTo: 0.3,
                                       rotation: 0, duration: 0.6 + Double(v % 3) * 0.08)
        case .firefly:  // trôi chậm lên, lượn nhẹ, nhịp sáng (opacity keyframes) rồi tắt
            return KeyEffectTrajectory(dx: t * 6, dy: -(4 + Double(v % 3) * 3), scaleFrom: 0.7, scaleTo: 1,
                                       rotation: 0, duration: 1.0 + Double(v % 3) * 0.1, sway: 2.5)
        case .matrix:   // chữ rơi thẳng xuống một đoạn ngắn rồi tắt
            return KeyEffectTrajectory(dx: 0, dy: 14 + Double(v % 3) * 5, scaleFrom: 1, scaleTo: 1,
                                       rotation: 0, duration: 0.7 + Double(v % 3) * 0.08)
        case .petals:   // cánh hoa rơi chậm, đung đưa, xoay
            return KeyEffectTrajectory(dx: t * 10, dy: 18 + Double(v % 3) * 6, scaleFrom: 1, scaleTo: 0.75,
                                       rotation: t * 2.4, duration: 0.95 + Double(v % 3) * 0.08, sway: 5)
        default:
            return KeyEffectTrajectory(dx: 0, dy: 0, scaleFrom: 1, scaleTo: 1, rotation: 0, duration: 0)
        }
    }

    /// Đếm điểm để sinh hạt: true mỗi `every` điểm.
    struct Spawner {
        let every: Int
        private(set) var count = 0
        init(every: Int) { self.every = every }
        mutating func tick() -> Bool {
            guard every > 0 else { return false }
            count += 1
            if count >= every { count = 0; return true }
            return false
        }
        mutating func reset() { count = 0 }
    }
}

extension RGBA {
    /// ARGB 32-bit (làm tròn từng kênh).
    var argb32: UInt32 {
        func c(_ x: Double) -> UInt32 { UInt32((min(1, max(0, x)) * 255).rounded()) }
        return c(a) << 24 | c(r) << 16 | c(g) << 8 | c(b)
    }
}

private extension UIColor {
    convenience init(argb: UInt32) {
        self.init(red: CGFloat((argb >> 16) & 0xFF) / 255, green: CGFloat((argb >> 8) & 0xFF) / 255,
                  blue: CGFloat(argb & 0xFF) / 255, alpha: CGFloat(argb >> 24) / 255)
    }
}

// MARK: - Renderer (Core Animation)

/// Vệt vuốt: container (lớp `layer`) = nhóm nét (mờ dần / nhấp nháy) + nhóm hạt. Đuôi ~300ms, không
/// animation ngầm khi vẽ; nhấc tay nét mờ dần ~200ms (huỷ: tắt ngay; Giảm chuyển động vẫn mờ dần), hạt bay nốt.
final class SwipeTrailRenderer {
    let layer = CALayer()
    private(set) var style: SwipeTrailStyle = .none
    static let tail: TimeInterval = 0.3
    private static let cap = 128
    private var xs = [CGFloat](repeating: 0, count: cap)
    private var ys = [CGFloat](repeating: 0, count: cap)
    private var ts = [TimeInterval](repeating: 0, count: cap)
    private var head = 0, count = 0
    // Nháp cấp sẵn (bút lông): bề rộng nửa nét mỗi điểm.
    private var hw = [CGFloat](repeating: 0, count: cap)

    private let strokeRoot = CALayer()
    private let particleRoot = CALayer()
    private var strokeLayers: [CAShapeLayer] = []
    private var gradient: CAGradientLayer?
    private var particles: [CAShapeLayer] = []
    private var particleAnims: [CAAnimation] = []
    private var pool = KeyEffectPool(capacity: 1)
    private var spawner = SwipeTrailFx.Spawner(every: 0)
    /// Animation lặp (nhấp nháy Điện/Plasma, xoay màu Ảo ảnh, đổi màu + thở Tan chảy): dựng ở configure, gắn
    /// lúc begin, gỡ lúc huỷ / settle — chạy trên render server, main thread không làm gì mỗi khung.
    private var loops: [(layer: CALayer, key: String, anim: CAAnimation)] = []
    // Ảo ảnh: kaleidoRoot (mask = kaleidoMask) chứa bánh xe màu `hue`; mask = nét thật + replicator nhánh.
    private var kaleidoRoot: CALayer?
    private var kaleidoMask: CALayer?
    private var hue: CAGradientLayer?
    private var mirror: CAReplicatorLayer?
    private var mirrorShape: CAShapeLayer?
    // Vệt lặp: bóng nằm DƯỚI nhóm nét, mờ chậm hơn (chromaFade) nên tách nhóm riêng (chỉ gắn khi dùng).
    private let ghostRoot = CALayer()
    private var ghosts: [CAShapeLayer] = []
    /// Đuôi của kiểu (Sao chổi 0,6 s; kiểu khác = `tail`).
    private var tailSec: TimeInterval = SwipeTrailRenderer.tail
    /// Lớp dùng path chung (mọi lớp nét trừ đầu sao chổi) + chấm đầu sao chổi (path tròn cố định, chỉ dời).
    private var pathLayers: [CAShapeLayer] = []
    private var heads: [CAShapeLayer] = []
    // Phím sáng theo đường / Ma trận: khung phím chữ (toạ độ host) nhận lúc bắt đầu vuốt; pool ô sáng dưới nét.
    private var usesKeys = false
    private var keyRects: [CGRect] = []
    private var keyChars: [Character] = []
    private var keyMinX: [Double] = [], keyMinY: [Double] = [], keyMaxX: [Double] = [], keyMaxY: [Double] = []
    private var keyPaths: [CGPath] = []
    private var hitDy: CGFloat = 0
    private var curKey = -1, curGlow = -1
    private let glowRoot = CALayer()
    private var glows: [CALayer] = []
    private var glowKey: [Int] = []
    private var glowAnim: CAAnimation?
    private var glowPool = KeyEffectPool(capacity: 1)
    // Thư pháp: dấu triện (dựng một lần), animation gắn sẵn — nhấc tay chỉ đổi position + beginTime.
    private var seal: CAShapeLayer?
    private var sealAnim: CAAnimation?
    /// Ma trận: số chữ đã bắn trong cú vuốt (chọn chữ / chữ số).
    private var spawned = 0
    /// beginTime "chưa tới" (ô đang sáng: animation mờ chưa chạy, fill lùi giữ độ đậm 1).
    private static let pending: CFTimeInterval = 1e7
    private var seed = 0
    private var lastPoint: CGPoint?
    private var settleGen = 0
    private var configured: (SwipeTrailStyle, UInt32, UInt32, Bool)?
    /// beginTime cục bộ (> 0: CA không tự gán "bây giờ").
    private static let animBegin: CFTimeInterval = 1e-3

    init() {
        layer.addSublayer(strokeRoot)
        layer.addSublayer(particleRoot)
        for l in [layer, strokeRoot, particleRoot, ghostRoot, glowRoot] { l.actions = Self.noActions }
    }

    private static let noActions: [String: CAAction] = ["position": NSNull(), "bounds": NSNull(), "path": NSNull(),
                                                        "opacity": NSNull(), "hidden": NSNull(), "frame": NSNull(),
                                                        "beginTime": NSNull(), "sublayers": NSNull(),
                                                        "shadowPath": NSNull(), "transform": NSNull()]

    /// Dựng lớp nét / gradient / pool hạt MỘT lần cho kiểu + màu (gọi lúc hiện bàn phím / đổi sáng-tối).
    func configure(style: SwipeTrailStyle, trail: RGBA, accent: RGBA, dark: Bool, base: Double = 6) {
        let key = (style, trail.argb32, accent.argb32, dark)
        if let c = configured, c.0 == key.0, c.1 == key.1, c.2 == key.2, c.3 == key.3 { return }
        configured = key
        self.style = style
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        settleNow()
        strokeLayers.forEach { $0.removeFromSuperlayer() }
        strokeLayers.removeAll()
        gradient?.removeFromSuperlayer(); gradient = nil
        particles.forEach { $0.removeFromSuperlayer() }
        particles.removeAll(); particleAnims.removeAll()
        loops.removeAll()
        kaleidoRoot?.removeFromSuperlayer()
        kaleidoRoot = nil; kaleidoMask = nil; hue = nil; mirror = nil; mirrorShape = nil
        ghosts.forEach { $0.removeFromSuperlayer() }
        ghosts.removeAll()
        if style == .chroma { layer.insertSublayer(ghostRoot, at: 0) } else { ghostRoot.removeFromSuperlayer() }
        heads.removeAll(); pathLayers.removeAll()
        glows.forEach { $0.removeFromSuperlayer() }
        glows.removeAll(); glowKey.removeAll(); glowAnim = nil
        glowRoot.removeFromSuperlayer()
        seal?.removeFromSuperlayer(); seal = nil; sealAnim = nil
        tailSec = SwipeTrailFx.tail(style)
        usesKeys = style.usesKeys
        curKey = -1; curGlow = -1
        if !usesKeys { keyRects = []; keyChars = []; keyMinX = []; keyMinY = []; keyMaxX = []; keyMaxY = []; keyPaths = [] }
        var meltIndex = 0, segIndex = 0
        for s in style.strokes(base: base, trail: trail.argb32, accent: accent.argb32 & 0xFFFFFF, dark: dark) {
            let l = CAShapeLayer()
            l.actions = Self.noActions
            l.lineCap = .round
            l.lineJoin = .round
            l.shadowOpacity = 0
            switch s.kind {
            case .stroke:
                l.fillColor = nil
                l.lineWidth = CGFloat(s.width)
                l.strokeColor = UIColor(argb: s.argb).cgColor
                strokeRoot.addSublayer(l)
            case .fill:
                l.fillColor = UIColor(argb: s.argb).cgColor
                l.strokeColor = nil
                strokeRoot.addSublayer(l)
            case .gradient:
                l.fillColor = nil
                l.lineWidth = CGFloat(s.width)
                l.strokeColor = UIColor.white.cgColor
                let g = CAGradientLayer()
                g.actions = Self.noActions
                g.colors = SwipeTrailFx.rainbow.map { UIColor(argb: 0xFF00_0000 | $0).cgColor }
                g.startPoint = CGPoint(x: 0, y: 0.2)
                g.endPoint = CGPoint(x: 1, y: 0.8)
                g.mask = l
                strokeRoot.addSublayer(g)
                gradient = g
            case .conic, .mirror:
                // Mask chỉ dùng kênh alpha: nét trắng có alpha của kiểu, màu lấy từ bánh xe `hue` bên dưới.
                l.fillColor = nil
                l.lineWidth = CGFloat(s.width)
                l.strokeColor = UIColor(argb: s.argb).cgColor
                buildKaleido()
                if s.kind == .conic {
                    kaleidoMask?.addSublayer(l)
                } else {
                    // Nhánh đầu xoay sẵn 60°, replicator nhân thêm bản, mỗi bản xoay tiếp 60° (cùng path).
                    l.transform = Self.branchTurn
                    mirror?.addSublayer(l)
                    mirrorShape = l
                }
            case .melt:
                l.fillColor = nil
                l.lineWidth = CGFloat(s.width)
                l.strokeColor = UIColor(argb: s.argb).cgColor
                let seg = SwipeTrailFx.meltSegments
                l.strokeStart = CGFloat(seg[min(meltIndex, seg.count - 2)])
                l.strokeEnd = CGFloat(seg[min(meltIndex + 1, seg.count - 1)])
                l.lineCap = .butt     // đầu tròn chồng nhau ⇒ cục sáng ở chỗ nối đoạn
                meltIndex += 1
                strokeRoot.addSublayer(l)
                let breath = CAKeyframeAnimation(keyPath: "lineWidth")
                breath.values = (0...8).map { s.width * SwipeTrailFx.meltBreath(Double($0) / 8) }
                breath.calculationMode = .cubic
                breath.duration = SwipeTrailFx.meltBreathPeriod
                breath.repeatCount = .infinity
                let tint = CAKeyframeAnimation(keyPath: "strokeColor")
                tint.values = SwipeTrailFx.hueWheel.map { UIColor(argb: (s.argb & 0xFF00_0000) | $0).cgColor }
                tint.duration = SwipeTrailFx.meltHuePeriod
                tint.repeatCount = .infinity
                loops.append((l, "breath", breath))
                loops.append((l, "tint", tint))
            case .ghost:
                l.fillColor = nil
                l.lineWidth = CGFloat(s.width)
                l.strokeColor = UIColor(argb: s.argb).cgColor
                l.transform = Self.ghostTransform(ghosts.count, 0)
                ghostRoot.addSublayer(l)
                ghosts.append(l)
            case .segment:
                l.fillColor = nil
                l.lineWidth = CGFloat(s.width)
                l.strokeColor = UIColor(argb: s.argb).cgColor
                let seg = SwipeTrailFx.cometSegments
                l.strokeStart = CGFloat(seg[min(segIndex, seg.count - 2)])
                l.strokeEnd = CGFloat(seg[min(segIndex + 1, seg.count - 1)])
                l.lineCap = .butt     // đầu tròn chồng nhau ⇒ cục sáng ở chỗ nối đoạn (như Tan chảy)
                segIndex += 1
                strokeRoot.addSublayer(l)
            case .head:
                // Chấm tròn tâm (0, 0), bounds rỗng: redraw chỉ dời position tới đầu ngón (không dựng path).
                let r = CGFloat(s.width) / 2
                l.path = CGPath(ellipseIn: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r), transform: nil)
                l.fillColor = UIColor(argb: s.argb).cgColor
                l.strokeColor = nil
                l.bounds = .zero
                l.isHidden = true
                strokeRoot.addSublayer(l)
                heads.append(l)
            }
            strokeLayers.append(l)
            if s.kind != .head { pathLayers.append(l) }
        }
        if style == .keys { buildGlows(accent: accent.argb32 & 0xFFFFFF) }
        if style == .calligraphy { buildSeal() }
        if style == .electric || style == .plasma {
            let f = CAKeyframeAnimation(keyPath: "opacity")
            f.values = [1, 0.55, 1, 0.8, 0.45, 1]
            f.duration = 0.22
            f.repeatCount = .infinity
            loops.append((strokeRoot, "flicker", f))
        }
        if style.usesParticles { buildParticles(accent: accent.argb32 & 0xFFFFFF) }
        pool = KeyEffectPool(capacity: max(1, particles.count))
        spawner = SwipeTrailFx.Spawner(every: style.spawnEvery)
        CATransaction.commit()
    }

    private static let branchTurn = CATransform3DMakeRotation(2 * .pi / CGFloat(SwipeTrailFx.kaleidoBranches), 0, 0, 1)

    private static func ghostTransform(_ i: Int, _ e: Double) -> CATransform3D {
        let d = SwipeTrailFx.chromaShift(i, e)
        return CATransform3DMakeTranslation(CGFloat(d.dx), CGFloat(d.dy), 0)
    }

    /// Ảo ảnh: dựng MỘT lần — bánh xe màu (gradient nón) + mask chứa nét thật và replicator nhánh.
    private func buildKaleido() {
        guard kaleidoRoot == nil else { return }
        let root = CALayer(), mask = CALayer(), rep = CAReplicatorLayer(), g = CAGradientLayer()
        for l in [root, mask, rep, g] as [CALayer] { l.actions = Self.noActions }
        g.type = .conic
        g.colors = SwipeTrailFx.hueWheel.map { UIColor(argb: 0xFF00_0000 | $0).cgColor }
        g.startPoint = CGPoint(x: 0.5, y: 0.5)
        g.endPoint = CGPoint(x: 1, y: 0.5)
        rep.instanceCount = SwipeTrailFx.kaleidoBranches - 1
        rep.instanceTransform = Self.branchTurn      // quanh tâm replicator = tâm vùng phím
        mask.addSublayer(rep)
        root.addSublayer(g)
        root.mask = mask
        strokeRoot.addSublayer(root)
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0
        spin.toValue = 2 * Double.pi
        spin.duration = SwipeTrailFx.kaleidoHuePeriod
        spin.repeatCount = .infinity
        loops.append((g, "spin", spin))
        kaleidoRoot = root; kaleidoMask = mask; mirror = rep; hue = g
    }

    /// Phím sáng theo đường: pool ô sáng (màu nhấn) DƯỚI nét; animation mờ dựng MỘT lần, gắn khi dùng lần đầu.
    private func buildGlows(accent: UInt32) {
        layer.insertSublayer(glowRoot, at: 0)
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1; fade.toValue = 0
        fade.duration = SwipeTrailFx.keyGlowFade
        fade.beginTime = Self.animBegin
        fade.fillMode = .both
        fade.isRemovedOnCompletion = false
        glowAnim = fade
        let corner = CGFloat(SwipeTrailFx.keyGlowCorner)
        for _ in 0..<SwipeTrailFx.keyGlowCap {
            let l = CALayer()
            l.actions = Self.noActions
            l.backgroundColor = UIColor(argb: 0x5200_0000 | accent).cgColor
            l.borderColor = UIColor(argb: 0xE600_0000 | accent).cgColor
            l.borderWidth = 1.5
            l.cornerRadius = corner
            // Quầng: shadowPath đặt sẵn theo khung phím ⇒ không tốn lượt vẽ ngoài màn hình.
            l.shadowColor = UIColor(argb: 0xFF00_0000 | accent).cgColor
            l.shadowOpacity = 0.85
            l.shadowRadius = 6
            l.shadowOffset = .zero
            l.isHidden = true
            glowRoot.addSublayer(l)
            glows.append(l)
            glowKey.append(-1)
        }
        glowPool = KeyEffectPool(capacity: glows.count)
    }

    /// Thư pháp: dấu triện son (vuông bo góc, nghiêng nhẹ) + nét khắc trắng; animation đóng dấu dựng một lần.
    private func buildSeal() {
        let s = CGFloat(SwipeTrailFx.sealSize), c = CGFloat(SwipeTrailFx.sealCorner)
        var tilt = CGAffineTransform(rotationAngle: CGFloat(SwipeTrailFx.sealTilt * .pi / 180))
        let l = CAShapeLayer()
        l.actions = Self.noActions
        l.path = CGPath(roundedRect: CGRect(x: -s / 2, y: -s / 2, width: s, height: s),
                        cornerWidth: c, cornerHeight: c, transform: &tilt)
        l.fillColor = UIColor(argb: 0xFF00_0000 | SwipeTrailFx.sealColor).cgColor
        l.strokeColor = nil
        l.bounds = .zero
        l.isHidden = true
        let mark = CAShapeLayer()
        mark.actions = Self.noActions
        let m = CGMutablePath()
        let i = CGFloat(SwipeTrailFx.sealInset) * s
        m.addRect(CGRect(x: -i, y: -i, width: 2 * i, height: 2 * i), transform: tilt)
        for (x0, y0, x1, y1) in SwipeTrailFx.sealMarks {
            m.move(to: CGPoint(x: x0 * s, y: y0 * s), transform: tilt)
            m.addLine(to: CGPoint(x: x1 * s, y: y1 * s), transform: tilt)
        }
        mark.path = m
        mark.fillColor = nil
        mark.strokeColor = UIColor(white: 1, alpha: 0.9).cgColor
        mark.lineWidth = 1.1
        mark.lineCap = .round
        mark.bounds = .zero
        l.addSublayer(mark)
        particleRoot.addSublayer(l)
        let scale = CAKeyframeAnimation(keyPath: "transform.scale")
        scale.values = SwipeTrailFx.sealScaleV
        scale.keyTimes = SwipeTrailFx.sealScaleT.map { NSNumber(value: $0) }
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = SwipeTrailFx.sealAlphaV
        fade.keyTimes = SwipeTrailFx.sealAlphaT.map { NSNumber(value: $0) }
        let g = CAAnimationGroup()
        g.animations = [scale, fade]
        for a in [scale, fade, g] as [CAAnimation] { a.duration = SwipeTrailFx.sealLife }
        g.beginTime = Self.animBegin
        g.fillMode = .both
        g.isRemovedOnCompletion = false
        seal = l; sealAnim = g
    }

    /// Khung phím chữ (toạ độ host) cho Phím sáng theo đường / Ma trận — gọi lúc BẮT ĐẦU cú vuốt (không mỗi lần
    /// di chuyển); cùng khung ⇒ 0 việc. `hitDy` = độ dời điểm chọn phím (dò phím ở y − hitDy như bộ giải mã).
    func setKeys(_ rects: [CGRect], _ chars: [Character], hitDy: CGFloat) {
        guard usesKeys else { return }
        self.hitDy = hitDy
        if rects == keyRects, chars == keyChars { return }
        keyRects = rects; keyChars = chars
        keyMinX = rects.map { Double($0.minX) }; keyMinY = rects.map { Double($0.minY) }
        keyMaxX = rects.map { Double($0.maxX) }; keyMaxY = rects.map { Double($0.maxY) }
        let c = CGFloat(SwipeTrailFx.keyGlowCorner)
        keyPaths = rects.map { r -> CGPath in
            let k = max(0, min(c, r.width / 2, r.height / 2))   // bo góc > nửa cạnh ⇒ CGPath crash
            return CGPath(roundedRect: CGRect(origin: .zero, size: r.size), cornerWidth: k, cornerHeight: k, transform: nil)
        }
        curKey = -1
    }

    /// Đường mẫu của ô xem thử (không có phím thật): lưới 3 hàng QWERTY phủ `b`.
    static func sampleKeys(in b: CGRect) -> (rects: [CGRect], chars: [Character]) {
        let rows: [[Character]] = [Array("qwertyuiop"), Array("asdfghjkl"), Array("zxcvbnm")]
        let w = b.width / 10, h = b.height / 3
        var rects: [CGRect] = [], chars: [Character] = []
        for (r, row) in rows.enumerated() {
            let x0 = b.minX + (b.width - w * CGFloat(row.count)) / 2
            for (k, ch) in row.enumerated() {
                rects.append(CGRect(x: x0 + w * CGFloat(k), y: b.minY + h * CGFloat(r), width: w, height: h).insetBy(dx: 2, dy: 3))
                chars.append(ch)
            }
        }
        return (rects, chars)
    }

    private static let petal: CGPath = {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 0, y: -5))
        p.addQuadCurve(to: CGPoint(x: 0, y: 5), control: CGPoint(x: 5, y: -1))
        p.addQuadCurve(to: CGPoint(x: 0, y: -5), control: CGPoint(x: -5, y: -1))
        p.closeSubpath()
        return p
    }()

    /// Ma trận: path glyph a–z, 0–9 (Menlo đậm 12pt — phông hệ thống), tâm (0, 0); dựng MỘT lần cho cả tiến trình.
    static let glyphPaths: [CGPath] = {
        let font = CTFontCreateWithName("Menlo-Bold" as CFString, 12, nil)
        return SwipeTrailFx.matrixGlyphs.map { ch -> CGPath in
            var u = Array(String(ch).utf16)
            var g = [CGGlyph](repeating: 0, count: u.count)
            guard CTFontGetGlyphsForCharacters(font, &u, &g, u.count) else { return CGMutablePath() }
            let box = CTFontGetBoundingRectsForGlyphs(font, .default, &g, nil, 1)
            // Lật trục y (CoreText hướng lên) + đưa tâm hộp chữ về (0, 0).
            var t = CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: -box.midX, y: -box.midY)
            return CTFontCreatePathForGlyph(font, g[0], &t) ?? CGMutablePath()
        }
    }()

    private func buildParticles(accent: UInt32) {
        let colors = style.particleColors(accent: accent)
        let star: CGPath = {
            let p = CGMutablePath()
            for k in 0..<8 {
                let r: CGFloat = k % 2 == 0 ? 4.5 : 1.5
                let a = CGFloat(k) * .pi / 4 - .pi / 2
                let pt = CGPoint(x: cos(a) * r, y: sin(a) * r)
                if k == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            p.closeSubpath()
            return p
        }()
        let r: CGFloat = style == .fire ? 2.6 : style == .firefly ? 2.0 : 2.2
        let dot = CGPath(ellipseIn: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r), transform: nil)
        let n = SwipeTrailFx.variants(style)
        for i in 0..<SwipeTrailFx.particleCap {
            let l = CAShapeLayer()
            l.actions = Self.noActions
            switch style {
            case .stardust: l.path = star
            case .petals: l.path = Self.petal
            case .matrix: l.path = Self.glyphPaths[26 + i % 10]   // chữ thật đặt lúc bắn
            default: l.path = dot
            }
            let rgb = colors[i % colors.count]
            l.fillColor = UIColor(argb: 0xFF00_0000 | rgb).cgColor
            if style == .firefly {
                // Quầng đom đóm: bóng cùng màu theo shadowPath cố định (không lượt vẽ ngoài màn hình).
                l.shadowColor = UIColor(argb: 0xFF00_0000 | rgb).cgColor
                l.shadowOpacity = 0.9
                l.shadowRadius = 3.5
                l.shadowOffset = .zero
                l.shadowPath = dot
            } else {
                l.shadowOpacity = 0
            }
            l.strokeColor = nil
            l.bounds = .zero
            l.isHidden = true
            l.opacity = 0
            particleRoot.addSublayer(l)
            particles.append(l)
            particleAnims.append(Self.animation(style, SwipeTrailFx.trajectory(style, i % max(n, 1))))
        }
    }

    private static func animation(_ s: SwipeTrailStyle, _ t: KeyEffectTrajectory) -> CAAnimation {
        let move = CABasicAnimation(keyPath: "position")
        move.isAdditive = true
        move.fromValue = NSValue(cgPoint: .zero)
        move.toValue = NSValue(cgPoint: CGPoint(x: t.dx, y: t.dy))
        move.timingFunction = CAMediaTimingFunction(name: .easeOut)
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = t.scaleFrom
        scale.toValue = t.scaleTo
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        if s == .stardust {        // lấp lánh: sáng – mờ – sáng – tắt
            fade.values = [0, 1, 0.3, 1, 0.2, 0.8, 0]
            fade.keyTimes = [0, 0.12, 0.3, 0.45, 0.62, 0.78, 1]
        } else if s == .firefly {  // nhịp sáng chậm (= Android particleAlpha)
            fade.values = SwipeTrailFx.fireflyPulseV
            fade.keyTimes = SwipeTrailFx.fireflyPulseT.map { NSNumber(value: $0) }
        } else {
            fade.values = [1, 1, 0]
            fade.keyTimes = [0, 0.4, 1]
        }
        var parts: [CAAnimation] = [move, scale, fade]
        if t.rotation != 0 {
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = 0; spin.toValue = t.rotation
            parts.append(spin)
        }
        if t.sway != 0 {
            let sway = CAKeyframeAnimation(keyPath: "position.x")
            sway.isAdditive = true
            sway.values = (0...6).map { t.sway * sin(Double($0) / 6 * 2 * .pi) }
            parts.append(sway)
        }
        for p in parts { p.duration = t.duration }
        let g = CAAnimationGroup()
        g.animations = parts
        g.duration = t.duration
        g.beginTime = animBegin
        g.fillMode = .both
        g.isRemovedOnCompletion = false
        return g
    }

    /// Bắt đầu cú vuốt mới (container phủ `bounds` của host).
    func begin(bounds: CGRect) {
        settleGen &+= 1
        head = 0; count = 0
        lastPoint = nil
        spawner.reset()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // CÙNG hệ toạ độ với host (khung = bounds, gốc bounds = gốc bounds host): điểm chạm tính theo
        // toạ độ KeyboardView dùng thẳng được cả khi host dời gốc bounds (#151, khung host cao tạm).
        // Trước đây frame = bounds nhưng gốc bounds 0 ⇒ vệt vẽ lệch lên đúng phần dư.
        Self.share(layer, bounds); Self.share(strokeRoot, bounds); Self.share(particleRoot, bounds)
        if let g = gradient { Self.share(g, bounds) }   // gradient dựng lại (đổi kiểu) sau lần begin trước
        // Ảo ảnh: mọi lớp phủ vùng phím ⇒ nhánh / replicator xoay quanh TÂM VÙNG PHÍM; bánh xe màu là hình
        // vuông cạnh = đường chéo (xoay không lộ góc trống).
        for l in [kaleidoRoot, kaleidoMask, mirror, mirrorShape] as [CALayer?] { if let l { Self.share(l, bounds) } }
        if let g = hue {
            let d = (bounds.width * bounds.width + bounds.height * bounds.height).squareRoot()
            g.bounds = CGRect(x: 0, y: 0, width: d, height: d)
            g.position = CGPoint(x: bounds.midX, y: bounds.midY)
        }
        if !ghosts.isEmpty {
            Self.share(ghostRoot, bounds)
            ghostRoot.removeAnimation(forKey: "fade")
            ghostRoot.opacity = 1
            for (i, g) in ghosts.enumerated() { g.removeAnimation(forKey: "drift"); g.transform = Self.ghostTransform(i, 0) }
        }
        if !glows.isEmpty { Self.share(glowRoot, bounds) }
        curKey = -1; curGlow = -1; spawned = 0
        strokeRoot.removeAnimation(forKey: "fade")
        strokeRoot.opacity = 1
        for l in pathLayers { l.path = nil }
        for h in heads { h.isHidden = true }
        for x in loops { x.layer.add(x.anim, forKey: x.key) }
        CATransaction.commit()
    }

    /// Layer phủ `b` VÀ dùng toạ độ của `b` (layer gốc: toạ độ host; layer con: toạ độ layer gốc — cùng một hệ).
    private static func share(_ l: CALayer, _ b: CGRect) {
        let p = CGPoint(x: b.midX, y: b.midY)
        if l.bounds != b { l.bounds = b }
        if l.position != p { l.position = p }
    }

    func add(_ p: CGPoint, _ t: TimeInterval) {
        if count == Self.cap { head = (head + 1) % Self.cap; count -= 1 }
        let i = (head + count) % Self.cap
        xs[i] = p.x; ys[i] = p.y; ts[i] = t
        count += 1
        while count > 2, ts[head] < t - tailSec { head = (head + 1) % Self.cap; count -= 1 }
        lastPoint = p
        if usesKeys, !keyMinX.isEmpty { trackKey(p) }
        if spawner.every > 0, spawner.tick() { spawn(at: p) }
    }

    /// Phím dưới ngón (dò ≤ ~33 khung, không cấp phát). Đổi phím: ô cũ bắt đầu mờ (beginTime = bây giờ), ô mới
    /// sáng (beginTime "chưa tới" ⇒ fill lùi = đậm 1). Ma trận chỉ cần biết phím (chữ rơi).
    private func trackKey(_ p: CGPoint) {
        let k = SwipeTrailFx.keyHit(x: Double(p.x), y: Double(p.y - hitDy),
                                    minX: keyMinX, minY: keyMinY, maxX: keyMaxX, maxY: keyMaxY)
        guard k != curKey else { return }
        curKey = k
        guard !glows.isEmpty, let anim = glowAnim else { return }
        let now = glowRoot.convertTime(CACurrentMediaTime(), from: nil)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        releaseGlow(now)
        if k >= 0, k < keyRects.count {
            let i = glowPool.next(), l = glows[i], r = keyRects[k]
            if l.animation(forKey: "fade") == nil { l.add(anim, forKey: "fade") }
            l.bounds = CGRect(origin: .zero, size: r.size)
            l.position = CGPoint(x: r.midX, y: r.midY)
            l.shadowPath = keyPaths[k]
            l.beginTime = now + Self.pending
            l.isHidden = false
            glowKey[i] = k
            curGlow = i
        }
        CATransaction.commit()
    }

    /// Ô đang sáng bắt đầu mờ (ngón rời phím / nhấc tay).
    private func releaseGlow(_ now: CFTimeInterval) {
        guard curGlow >= 0 else { return }
        glows[curGlow].beginTime = now
        curGlow = -1
    }

    private func spawn(at p: CGPoint) {
        guard !particles.isEmpty else { return }
        let now = particleRoot.convertTime(CACurrentMediaTime(), from: nil)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let i = pool.next()
        if style == .matrix {
            let g = SwipeTrailFx.matrixGlyph(spawn: spawned, key: curKey >= 0 && curKey < keyChars.count ? keyChars[curKey] : nil)
            particles[i].path = Self.glyphPaths[g]
            spawned &+= 1
        }
        fire(i, at: p, now: now)
        CATransaction.commit()
    }

    private func fire(_ i: Int, at p: CGPoint, now: CFTimeInterval) {
        let l = particles[i]
        // Animation gắn một lần (cho tới settle); bắn lại = đổi beginTime.
        if l.animation(forKey: "p") == nil { l.add(particleAnims[i], forKey: "p") }
        l.position = p
        l.beginTime = now
        l.isHidden = false
    }

    #if DEBUG
    /// Test: số lần dựng path + commit (KeyboardView vẽ MỘT lần mỗi lượt touchesMoved, không mỗi điểm gộp).
    var debugRedraws = 0
    #endif

    func redraw() {
        guard count > 0, !strokeLayers.isEmpty else { return }
        #if DEBUG
        debugRedraws += 1
        #endif
        let path = CGMutablePath()
        if style == .brush || style == .calligraphy {
            buildBrush(path, calligraphy: style == .calligraphy)
        } else {
            let jag = style == .electric || style == .plasma
            if jag { seed &+= 1 }
            let amp = CGFloat(style == .plasma ? SwipeTrailFx.plasmaAmplitude : SwipeTrailFx.electricAmplitude)
            // Tan chảy: điểm càng cũ (so với điểm mới nhất) càng chảy xuống.
            let melt = style == .melt
            let newest = ts[(head + count - 1) % Self.cap]
            for k in 0..<count {
                let i = (head + k) % Self.cap
                var p = CGPoint(x: xs[i], y: ys[i])
                if melt { p.y += CGFloat(SwipeTrailFx.meltSag((newest - ts[i]) / tailSec)) }
                if jag, k > 0, k < count - 1 {
                    let a = (head + k - 1) % Self.cap, b = (head + k + 1) % Self.cap
                    let dx = xs[b] - xs[a], dy = ys[b] - ys[a]
                    let len = max(0.001, (dx * dx + dy * dy).squareRoot())
                    let o = CGFloat(SwipeTrailFx.jitter(seed: seed, index: k)) * amp
                    p.x += -dy / len * o; p.y += dx / len * o
                }
                if k == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for l in pathLayers { l.path = path }
        if !heads.isEmpty {   // Sao chổi: đầu sáng theo ngón — chỉ dời
            let i = (head + count - 1) % Self.cap
            let p = CGPoint(x: xs[i], y: ys[i])
            for h in heads { h.position = p; h.isHidden = false }
        }
        CATransaction.commit()
    }

    /// Bút lông / Thư pháp: dải kín, nửa bề rộng theo tốc độ (mượt) × vuốt nhọn hai đầu. Thư pháp: bề rộng còn
    /// theo hướng nét (ngòi xiên) + mực đọng ở chỗ chậm (SwipeTrailFx.calliWidth).
    private func buildBrush(_ path: CGMutablePath, calligraphy: Bool) {
        let n = count
        guard n >= 2 else { return }
        var w = SwipeTrailFx.brushMax
        for k in 0..<n {
            let i = (head + k) % Self.cap
            if k > 0 {
                let j = (head + k - 1) % Self.cap
                let dx = Double(xs[i] - xs[j]), dy = Double(ys[i] - ys[j])
                let dt = max(0.001, (ts[i] - ts[j]) * 1000)
                let v = (dx * dx + dy * dy).squareRoot() / dt
                w = SwipeTrailFx.brushSmooth(w, calligraphy ? SwipeTrailFx.calliWidth(speed: v, dx: dx, dy: dy)
                                                            : SwipeTrailFx.brushWidth(speed: v))
            }
            hw[k] = CGFloat(w * SwipeTrailFx.brushTaperFactor(k, n) / 2)
        }
        func normal(_ k: Int) -> CGPoint {
            let a = (head + max(0, k - 1)) % Self.cap, b = (head + min(n - 1, k + 1)) % Self.cap
            let dx = xs[b] - xs[a], dy = ys[b] - ys[a]
            let len = max(0.001, (dx * dx + dy * dy).squareRoot())
            return CGPoint(x: -dy / len, y: dx / len)
        }
        for k in 0..<n {
            let i = (head + k) % Self.cap, nm = normal(k)
            let p = CGPoint(x: xs[i] + nm.x * hw[k], y: ys[i] + nm.y * hw[k])
            if k == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        for k in stride(from: n - 1, through: 0, by: -1) {
            let i = (head + k) % Self.cap, nm = normal(k)
            path.addLine(to: CGPoint(x: xs[i] - nm.x * hw[k], y: ys[i] - nm.y * hw[k]))
        }
        path.closeSubpath()
    }

    /// Nhấc tay / huỷ: nét mờ dần (`reduceMotion` = true: tắt ngay — chỉ dùng khi huỷ), hạt bay nốt; rồi settle.
    func fadeOut(reduceMotion: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if reduceMotion {
            for l in pathLayers { l.path = nil }
            for h in heads { h.isHidden = true }
            for x in loops { x.layer.removeAnimation(forKey: x.key) }
            for g in glows { g.isHidden = true }
            curGlow = -1
        } else {
            let a = CABasicAnimation(keyPath: "opacity")
            a.fromValue = 1; a.toValue = 0; a.duration = SwipeTrailFx.fade
            strokeRoot.add(a, forKey: "fade")
            strokeRoot.opacity = 0
            if !glows.isEmpty { releaseGlow(glowRoot.convertTime(CACurrentMediaTime(), from: nil)) }
            if let s = seal, let anim = sealAnim, let p = lastPoint {
                // Thư pháp: đóng dấu son ở chỗ nhấc tay (animation gắn sẵn, chỉ đổi position + beginTime).
                if s.animation(forKey: "stamp") == nil { s.add(anim, forKey: "stamp") }
                s.position = p
                s.beginTime = particleRoot.convertTime(CACurrentMediaTime(), from: nil)
                s.isHidden = false
            }
            if !ghosts.isEmpty {
                // Vệt lặp: bóng trôi xa nhau rồi tan, chậm hơn nét chính.
                let g = CABasicAnimation(keyPath: "opacity")
                g.fromValue = 1; g.toValue = 0; g.duration = SwipeTrailFx.chromaFade
                ghostRoot.add(g, forKey: "fade")
                ghostRoot.opacity = 0
                for (i, l) in ghosts.enumerated() {
                    let d = CABasicAnimation(keyPath: "transform")
                    d.fromValue = NSValue(caTransform3D: Self.ghostTransform(i, 0))
                    d.toValue = NSValue(caTransform3D: Self.ghostTransform(i, 1))
                    d.duration = SwipeTrailFx.chromaFade
                    d.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    l.add(d, forKey: "drift")
                    l.transform = Self.ghostTransform(i, 1)
                }
            }
        }
        CATransaction.commit()
        scheduleSettle()
    }

    /// Đã chốt từ vuốt: "Pháo hoa cuối nét" bắn một chùm ở chỗ nhấc tay.
    func commitBurst() {
        guard style == .firework, let p = lastPoint, !particles.isEmpty else { return }
        let now = particleRoot.convertTime(CACurrentMediaTime(), from: nil)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for _ in 0..<SwipeTrailFx.fireworkCount { fire(pool.next(), at: p, now: now) }
        CATransaction.commit()
        scheduleSettle()
    }

    private func scheduleSettle() {
        settleGen &+= 1
        let g = settleGen
        DispatchQueue.main.asyncAfter(deadline: .now() + SwipeTrailFx.fade + SwipeTrailFx.maxParticleLife) { [weak self] in
            guard let self, self.settleGen == g else { return }
            self.settleNow()
        }
    }

    /// Vệt đã tắt hẳn: gỡ mọi animation (mờ dần, nhấp nháy, hạt), xoá path — 0 animation còn chạy.
    func settleNow() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Gỡ animation cả cây (mờ dần, nhấp nháy, xoay màu, đổi màu / thở, bóng trôi, hạt).
        func strip(_ l: CALayer) { l.removeAllAnimations(); l.sublayers?.forEach(strip) }
        strip(layer)
        for l in pathLayers { l.path = nil }
        for h in heads { h.isHidden = true }
        for l in particles { l.isHidden = true }
        for g in glows { g.isHidden = true }
        seal?.isHidden = true
        curGlow = -1; curKey = -1
        CATransaction.commit()
    }

    #if DEBUG
    var debugStrokeLayers: [CAShapeLayer] { strokeLayers }
    var debugGradient: CAGradientLayer? { gradient }
    var debugHue: CAGradientLayer? { hue }
    var debugMirror: CAReplicatorLayer? { mirror }
    var debugGhosts: [CAShapeLayer] { ghosts }
    var debugLoopCount: Int { loops.count }
    var debugParticles: [CAShapeLayer] { particles }
    var debugVisibleParticles: Int { particles.filter { !$0.isHidden }.count }
    /// Mọi animation còn gắn trong cây vệt (0 sau settle).
    var debugAnimationCount: Int {
        func n(_ l: CALayer) -> Int { (l.animationKeys()?.count ?? 0) + (l.sublayers ?? []).reduce(0) { $0 + n($1) } }
        return n(layer)
    }
    var debugSublayerCount: Int {
        func n(_ l: CALayer) -> Int { (l.sublayers ?? []).reduce(0) { $0 + 1 + n($1) } }
        return n(layer)
    }
    var debugPointCount: Int { count }
    var debugSeed: Int { seed }
    var debugTail: TimeInterval { tailSec }
    var debugHeads: [CAShapeLayer] { heads }
    var debugGlows: [CALayer] { glows }
    /// Phím (chỉ số trong setKeys) của từng ô sáng đang hiện, theo thứ tự ô trong pool.
    var debugLitKeys: [Int] { glows.indices.filter { !glows[$0].isHidden }.map { glowKey[$0] } }
    /// Ô đang sáng (ngón còn trong phím): beginTime "chưa tới".
    var debugLitNow: Int? { curGlow >= 0 ? glowKey[curGlow] : nil }
    var debugCurrentKey: Int { curKey }
    var debugSeal: CAShapeLayer? { seal }
    #endif
}
