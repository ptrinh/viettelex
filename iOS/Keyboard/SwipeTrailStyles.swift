// "Hiệu ứng nét vuốt" (Gõ vuốt → Hiệu ứng nét vuốt): Tắt, Đơn giản (mặc định, vệt cũ), Lửa, Điện, Bút lông,
// Cầu vồng, Neon, Bụi sao, Pháo hoa cuối nét, Theo giao diện. "Tắt" + "Đơn giản" miễn phí; còn lại Plus —
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
import UIKit

/// Kiểu nét vuốt (giá trị lưu App Group / sao lưu = rawValue).
enum SwipeTrailStyle: String, CaseIterable {
    case none, simple, fire, electric, brush, rainbow, neon, stardust, firework, theme

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
        default: return 0
        }
    }
    /// Có pool hạt (dọc đường hoặc chùm pháo hoa lúc nhấc tay).
    var usesParticles: Bool { spawnEvery > 0 || self == .firework }

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
        }
    }

    /// Màu hạt (RGB) — hạt i dùng màu i % count.
    func particleColors(accent: UInt32) -> [UInt32] {
        switch self {
        case .fire: return [0xFFC21A, 0xFF7A1A, 0xFF3B30]
        case .stardust: return [0xFFC93C, accent & 0xFFFFFF, 0xFFE7A0]
        case .firework: return [accent & 0xFFFFFF, 0xFFC93C, 0xFF5E7E, 0x4FC3F7]
        default: return []
        }
    }
}

struct SwipeTrailStroke: Equatable {
    enum Kind { case stroke, fill, gradient }
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
    /// Bút lông: dày nhất (chậm) / mảnh nhất (nhanh), tốc độ coi là "nhanh" (pt/ms), hệ số làm mượt, số điểm vuốt nhọn.
    static let brushMax = 10.0, brushMin = 2.5, brushFast = 1.6, brushSmoothing = 0.35, brushTaper = 6
    /// Cầu vồng: các mốc màu (RGB) của gradient — lặp 2 vòng để nét ngắn vẫn đổi màu.
    static let rainbow: [UInt32] = [0xFF3B30, 0xFF9500, 0xFFCC00, 0x34C759, 0x00C7BE, 0x007AFF, 0xAF52DE,
                                    0xFF3B30, 0xFF9500, 0xFFCC00, 0x34C759, 0x00C7BE, 0x007AFF, 0xAF52DE]
    /// Sống lâu nhất của hạt (giây) — sau mờ dần + khoảng này thì settle.
    static let maxParticleLife = 1.1
    /// Mờ dần lúc nhấc tay (giây).
    static let fade = 0.2

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
    private var flicker: CAAnimation?
    private var seed = 0
    private var lastPoint: CGPoint?
    private var settleGen = 0
    private var configured: (SwipeTrailStyle, UInt32, UInt32, Bool)?
    /// beginTime cục bộ (> 0: CA không tự gán "bây giờ").
    private static let animBegin: CFTimeInterval = 1e-3

    init() {
        layer.addSublayer(strokeRoot)
        layer.addSublayer(particleRoot)
        for l in [layer, strokeRoot, particleRoot] { l.actions = Self.noActions }
    }

    private static let noActions: [String: CAAction] = ["position": NSNull(), "bounds": NSNull(), "path": NSNull(),
                                                        "opacity": NSNull(), "hidden": NSNull(), "frame": NSNull(),
                                                        "beginTime": NSNull(), "sublayers": NSNull()]

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
        flicker = nil
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
            }
            strokeLayers.append(l)
        }
        if style == .electric {
            let f = CAKeyframeAnimation(keyPath: "opacity")
            f.values = [1, 0.55, 1, 0.8, 0.45, 1]
            f.duration = 0.22
            f.repeatCount = .infinity
            flicker = f
        }
        if style.usesParticles { buildParticles(accent: accent.argb32 & 0xFFFFFF) }
        pool = KeyEffectPool(capacity: max(1, particles.count))
        spawner = SwipeTrailFx.Spawner(every: style.spawnEvery)
        CATransaction.commit()
    }

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
        let r: CGFloat = style == .fire ? 2.6 : 2.2
        let dot = CGPath(ellipseIn: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r), transform: nil)
        let n = SwipeTrailFx.variants(style)
        for i in 0..<SwipeTrailFx.particleCap {
            let l = CAShapeLayer()
            l.actions = Self.noActions
            l.path = style == .stardust ? star : dot
            l.fillColor = UIColor(argb: 0xFF00_0000 | colors[i % colors.count]).cgColor
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
        strokeRoot.removeAnimation(forKey: "fade")
        strokeRoot.opacity = 1
        for l in strokeLayers { l.path = nil }
        if let f = flicker { strokeRoot.add(f, forKey: "flicker") }
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
        while count > 2, ts[head] < t - Self.tail { head = (head + 1) % Self.cap; count -= 1 }
        lastPoint = p
        if spawner.every > 0, spawner.tick() { spawn(at: p) }
    }

    private func spawn(at p: CGPoint) {
        guard !particles.isEmpty else { return }
        let now = particleRoot.convertTime(CACurrentMediaTime(), from: nil)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fire(pool.next(), at: p, now: now)
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
        if style == .brush {
            buildBrush(path)
        } else {
            let jag = style == .electric
            if jag { seed &+= 1 }
            let amp = CGFloat(SwipeTrailFx.electricAmplitude)
            for k in 0..<count {
                let i = (head + k) % Self.cap
                var p = CGPoint(x: xs[i], y: ys[i])
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
        for l in strokeLayers { l.path = path }
        CATransaction.commit()
    }

    /// Bút lông: dải kín, nửa bề rộng theo tốc độ (mượt) × vuốt nhọn hai đầu.
    private func buildBrush(_ path: CGMutablePath) {
        let n = count
        guard n >= 2 else { return }
        var w = SwipeTrailFx.brushMax
        for k in 0..<n {
            let i = (head + k) % Self.cap
            if k > 0 {
                let j = (head + k - 1) % Self.cap
                let dx = Double(xs[i] - xs[j]), dy = Double(ys[i] - ys[j])
                let dt = max(0.001, (ts[i] - ts[j]) * 1000)
                w = SwipeTrailFx.brushSmooth(w, SwipeTrailFx.brushWidth(speed: (dx * dx + dy * dy).squareRoot() / dt))
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
            for l in strokeLayers { l.path = nil }
            strokeRoot.removeAnimation(forKey: "flicker")
        } else {
            let a = CABasicAnimation(keyPath: "opacity")
            a.fromValue = 1; a.toValue = 0; a.duration = SwipeTrailFx.fade
            strokeRoot.add(a, forKey: "fade")
            strokeRoot.opacity = 0
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
        strokeRoot.removeAllAnimations()
        for l in strokeLayers { l.path = nil }
        for l in particles { l.removeAllAnimations(); l.isHidden = true }
        CATransaction.commit()
    }

    #if DEBUG
    var debugStrokeLayers: [CAShapeLayer] { strokeLayers }
    var debugGradient: CAGradientLayer? { gradient }
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
    #endif
}
