// "Neon Night Club" (11/2026, Plus): ĐÈN RỌI trên ảnh nền ("photoFx":"spotlight" — ThemeSpec) + quả cầu disco nhỏ.
// Song sinh android/keyboard/.../Spotlight.kt (hàm thuần, CÙNG SỐ — test chung) + app/.../ime/SpotlightView.kt.
//
// Chỉ tồn tại khi theme đang dùng có "photoFx":"spotlight" (KeyboardView.spotlight == nil với mọi theme khác ⇒ 0 lớp,
// đường phím chỉ đọc một optional). Thứ tự lớp: nền theme / ảnh nền / lớp phủ ảnh · ĐÈN RỌI · hiệu ứng dải dưới phím ·
// phím. Không nhận chạm.
//
// • Có ảnh nền: lớp đen 90 % phủ ảnh; mỗi phím bấm "chớp" một quầng đèn sân khấu (bán kính ~3,8–4,9 bề rộng phím;
//   lõi lộ ảnh 100 % + cộng sáng gần trắng, quầng ~60 %, vành sáng mờ màu neon ở rìa) — lớp
//   `lit` chứa CHÍNH CGImage của ảnh nền đang hiện (không giải mã / sao chép thêm) cắt bằng mặt nạ là vài
//   CAGradientLayer radial (lỗ sáng), cộng quầng tô màu neon hồng / tím / lục lam xoay vòng mỗi lần bấm. Giữ 0,15 s rồi
//   tắt dần ~0,9–1,1 s, tối đa 6 quầng (quầng cũ nhất bị thay); gõ nhanh (ComboMeter) ⇒ quầng to + sáng + lâu hơn chút.
// • Không có ảnh nền: phía sau phím là NGƯỜI NHẢY HOẠT HÌNH (NightDancer — atlas 4 × 2 của Bạn đồng hành, cô gái /
//   chàng trai) cao 85 % bàn phím, chìm trong tối (~12 % sáng); đèn rọi mới thấy màu thật + viền neon theo màu đèn + phông
//   tím đêm. Mỗi lần đèn nháy ⇒ biến thể kế (7 khung × lật ngang, không lặp liền) — chỉ đổi contentsRect / transform.
//   Atlas giải MỘT lần trên luồng nền theo cỡ hiển thị (NightDancer.decodeLongEdge); có ảnh nền ⇒ không giải / thả ra.
// • Hiệu năng: lớp + animation dựng MỘT lần (pool); bấm chỉ đặt vị trí / cỡ + gắn animation dựng sẵn (render server
//   chạy phần còn lại — không timer khung hình). Hết quầng ⇒ ẩn `lit` (không còn lượt vẽ mặt nạ) bằng MỘT asyncAfter
//   cho cả loạt gõ. Nghỉ = 0 animation.
import UIKit
import ImageIO

/// Cổng chạy (thuần): theme có "photoFx":"spotlight" + Plus + không tiết kiệm pin. Giảm chuyển động KHÔNG tắt
/// (như hiệu ứng phím — Phil 19/10/2026). Android SpotlightPolicy y hệt.
enum SpotlightPolicy {
    static func active(photoFx: String?, plus: Bool, lowPower: Bool) -> Bool {
        photoFx == ThemeExtraIds.spotlight && plus && !lowPower
    }
}

/// Hàm thuần đèn rọi (giây, pt) — Android SpotlightFx cùng số (test chung). Mỗi lần bấm là một "chớp đèn sân khấu"
/// (11/2026 — Phil: "sáng lóa, rộng hơn"): quầng ~3,8–4,9 bề rộng phím (≈ 30–45 % bề rộng bàn phím; 2–3 quầng phủ gần
/// hết), lõi nóng gần trắng (tô nhẹ màu neon) → quầng màu → vành sáng mờ màu neon ở rìa ngoài. Ảnh nền / người nhảy lộ
/// ~100 % trong lõi, ~60 % ở quầng. Sáng giữ `hold` rồi tắt dần 0,9–1,08 s.
enum SpotlightFx {
    /// Tối đa số quầng sống cùng lúc (quầng cũ nhất bị thay).
    static let cap = 6
    /// Lớp đen phủ ảnh nền (0…1).
    static let darkness = 0.9
    /// Neon xoay vòng mỗi lần bấm: hồng, tím, lục lam.
    static let colors: [UInt32] = [0xFF2FD0, 0x9B5CFF, 0x2FE6FF]
    static let attack = 0.06
    /// Giữ đỉnh sáng sau `attack` trước khi tắt.
    static let hold = 0.15
    /// = attack + hold + tắt 0,9 s (mức 0); mỗi mức combo tắt lâu thêm `durationPerLevel`.
    static let baseDuration = 1.11
    static let durationPerLevel = 0.06
    static let radiusFactor = 3.8
    static let radiusPerLevel = 0.35
    static let minRadius = 72.0
    static let maxRadius = 210.0
    static let peakBase = 0.88
    static let peakPerLevel = 0.04
    static let startScale = 0.8
    static let growScale = 0.3

    /// Mặt nạ "lộ ảnh" theo bán kính (0 = tâm, 1 = rìa): lõi 100 %, quầng ~60 %, rìa tắt. Nhân với `alpha`.
    static let maskStops: [Double] = [0, 0.24, 0.55, 0.8, 1]
    static let maskLevels: [Double] = [1, 1, 0.62, 0.2, 0]
    /// Quầng tô màu (cộng sáng — screen) theo bán kính: lõi nóng gần trắng (`glowWhite` = tỉ lệ pha trắng) → màu neon →
    /// vành sáng mờ (bướu ở 0,86) → trong suốt. `glowAlpha` = độ đậm mỗi mốc; cả quầng nhân với `alpha`.
    static let glowStops: [Double] = [0, 0.16, 0.42, 0.68, 0.86, 1]
    static let glowAlpha: [Double] = [0.85, 0.72, 0.34, 0.08, 0.16, 0]
    static let glowWhite: [Double] = [0.6, 0.25, 0, 0, 0, 0]

    private static func lv(_ level: Int) -> Double { Double(min(max(level, 0), 3)) }

    /// Thời gian sống của quầng ở mức combo `level` (0…3): 1,11…1,29 s.
    static func duration(level: Int) -> Double { baseDuration + durationPerLevel * lv(level) }
    /// Bán kính quầng (pt) theo bề rộng phím + mức combo, kẹp [72, 210].
    static func radius(keyWidth w: Double, level: Int) -> Double {
        min(max(w * (radiusFactor + radiusPerLevel * lv(level)), minRadius), maxRadius)
    }
    /// Độ sáng đỉnh 0,88…1.
    static func peak(level: Int) -> Double { min(1, peakBase + peakPerLevel * lv(level)) }
    /// Độ sáng sau `dt` giây: lên tuyến tính trong `attack`, giữ `hold`, rồi tắt (1−u)².
    static func alpha(_ dt: Double, level: Int) -> Double {
        let d = duration(level: level), p = peak(level: level)
        guard dt >= 0, dt < d else { return 0 }
        if dt < attack { return p * dt / attack }
        if dt < attack + hold { return p }
        let u = (dt - attack - hold) / (d - attack - hold)
        return p * (1 - u) * (1 - u)
    }
    /// Hệ số bán kính sau `dt` (0,8 → 1,1, chậm dần).
    static func scale(_ dt: Double, level: Int) -> Double {
        let x = min(max(dt / duration(level: level), 0), 1)
        return startScale + growScale * (1 - (1 - x) * (1 - x))
    }
    /// Màu neon của lần bấm thứ `press`.
    static func color(_ press: Int) -> UInt32 { colors[((press % colors.count) + colors.count) % colors.count] }
    /// Màu ARGB mốc `stop` của quầng tô màu neon `rgb`: pha trắng `glowWhite`, alpha `glowAlpha` (làm tròn kênh).
    static func glowColor(_ rgb: UInt32, stop: Int) -> UInt32 {
        let w = glowWhite[stop]
        func ch(_ c: UInt32) -> UInt32 { UInt32(min(max((Double(c) + (255 - Double(c)) * w).rounded(), 0), 255)) }
        let a = UInt32(min(max((glowAlpha[stop] * 255).rounded(), 0), 255))
        return a << 24 | ch(rgb >> 16 & 0xFF) << 16 | ch(rgb >> 8 & 0xFF) << 8 | ch(rgb & 0xFF)
    }
    /// CGColor (sRGB) của màu ARGB `glowColor` — dựng sẵn một lần (không mỗi lần bấm).
    static func cgColor(argb v: UInt32) -> CGColor {
        UIColor(red: CGFloat(v >> 16 & 0xFF) / 255, green: CGFloat(v >> 8 & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255,
                alpha: CGFloat(v >> 24 & 0xFF) / 255).cgColor
    }
}

/// Vòng quầng sáng (thuần, mảng cấp sẵn): lần bấm ⇒ ô kế tiếp (quầng cũ nhất bị thay khi đủ `cap`).
struct SpotlightLights {
    private(set) var starts = [Double](repeating: -.greatestFiniteMagnitude, count: SpotlightFx.cap)
    private(set) var levels = [Int](repeating: 0, count: SpotlightFx.cap)
    private(set) var cursor = 0
    private(set) var presses = 0

    /// Bấm lúc `t` ở mức combo `level` ⇒ chỉ số ô dùng.
    mutating func press(at t: Double, level: Int) -> Int {
        let i = cursor
        starts[i] = t; levels[i] = level
        cursor = (cursor + 1) % SpotlightFx.cap
        presses += 1
        return i
    }
    /// Số quầng còn sáng lúc `t`.
    func live(at t: Double) -> Int {
        var n = 0
        for i in 0..<SpotlightFx.cap where t >= starts[i] && t - starts[i] < SpotlightFx.duration(level: levels[i]) { n += 1 }
        return n
    }
    /// Thời điểm quầng cuối cùng tắt hẳn (−∞ khi chưa bấm).
    var lastEnd: Double {
        var e = -Double.greatestFiniteMagnitude
        for i in 0..<SpotlightFx.cap where starts[i] > -.greatestFiniteMagnitude {
            e = max(e, starts[i] + SpotlightFx.duration(level: levels[i]))
        }
        return e
    }
    mutating func reset() {
        for i in 0..<SpotlightFx.cap { starts[i] = -.greatestFiniteMagnitude; levels[i] = 0 }
        cursor = 0
    }
}

/// Quả cầu disco nhỏ ở góc trên phải (pt) — Android DiscoBall cùng số.
enum DiscoBall {
    static let diameter = 16.0
    static let inset = 6.0
    /// Dây treo (từ mép trên xuống đỉnh quả cầu).
    static let cord = 5.0
    /// Mỗi lần bấm xoay thêm (rad) trong `spinDuration`.
    static let spin = 0.35
    static let spinDuration = 0.25
    /// Chấm sáng toả ra mỗi lần bấm / pool / quãng bay / thời gian / trần nhịp.
    static let dotsPerPress = 3
    static let dotPool = 6
    static let dotRadius = 2.0
    static let dotDistance = 30.0
    static let dotDuration = 0.45
    static let minInterval = 0.12

    /// Tâm quả cầu trong khung (minX, minY, width) — góc trên phải.
    static func center(minX: Double, minY: Double, width: Double) -> (x: Double, y: Double) {
        (minX + width - inset - diameter / 2, minY + cord + diameter / 2)
    }
    /// Hướng bay chấm `i` của lần bấm `press` (đơn vị, y xuống): toả xuống-trái 0,55π…1,03π.
    static func direction(press: Int, dot i: Int) -> (x: Double, y: Double) {
        let a = Double.pi * (0.55 + 0.16 * Double(i) + 0.04 * Double(((press % 3) + 3) % 3))
        return (cos(a), sin(a))
    }
    /// Độ mờ chấm sau `dt`: (1−u)².
    static func dotAlpha(_ dt: Double) -> Double {
        guard dt >= 0, dt < dotDuration else { return 0 }
        let u = dt / dotDuration
        return (1 - u) * (1 - u)
    }
    /// Quãng đã bay sau `dt` (chậm dần): d·(1−(1−u)²).
    static func dotTravel(_ dt: Double) -> Double {
        let u = min(max(dt / dotDuration, 0), 1)
        return dotDistance * (1 - (1 - u) * (1 - u))
    }
}

/// Lớp đèn rọi + quả cầu disco. Dùng CHUNG hệ toạ độ với KeyboardView (shareCoordinateSpace — #151).
final class SpotlightView: UIView {
    private let dark = CALayer()
    private let lit = CALayer()
    private let holes = CALayer()
    private var holeLayers: [CAGradientLayer] = []
    private var tintLayers: [CAGradientLayer] = []
    /// Không ảnh nền: "phông" tím đêm (trong `lit` — chỉ lộ dưới đèn) + người nhảy: bản tối (NGOÀI `lit`: ảnh + lớp đen
    /// 88 % cắt theo alpha ảnh) và bản màu thật có bóng neon (TRONG `lit` ⇒ chỉ lộ dưới đèn). Dựng lười; atlas giải nền.
    private var texture: CAGradientLayer?
    private var textureBuiltFor: CGSize = .zero
    private let dimBox = CALayer(), dimArt = CALayer(), dimShade = CALayer(), dimMask = CALayer()
    private let litBox = CALayer(), litArt = CALayer()
    private var dancerBuilt = false
    private var atlas: CGImage?
    private var atlasGen = 0
    private var atlasLoading = false
    private var flashes = 0
    /// Biến thể đang hiện (khung × lật — NightDancer.next); 0 = đứng thẳng trước lần nháy đầu.
    private(set) var variant = 0
    /// Nhân vật nhảy (NightDancer.character) — đổi ⇒ thả atlas cũ, giải lại.
    var dancer: BuddyCharacter = .girl {
        didSet {
            guard dancer != oldValue else { return }
            dropAtlas()
            ensureAtlas()
        }
    }
    private static let atlasQueue = DispatchQueue(label: "com.viettelex.nightclub.atlas", qos: .userInitiated)
    private let ball = CALayer()
    private let ballFacets = CAShapeLayer()
    private let ballCord = CAShapeLayer()
    private var dots: [CAShapeLayer] = []
    private var dotCursor = 0
    private var lastDots = -Double.greatestFiniteMagnitude
    private var spinAngle: CGFloat = 0
    private var lights = SpotlightLights()
    private var combo = ComboMeter()
    private var pending: [CGRect] = []
    private var scheduled = false
    private var hideScheduled = false
    private(set) var hasPhoto = false
    private static let maxPending = 4
    /// Màu tô (CGColor) dựng sẵn mỗi màu neon: các mốc SpotlightFx.glowColor (lõi gần trắng → màu → vành mờ).
    private let tintColors: [[CGColor]] = SpotlightFx.colors.map { c in
        SpotlightFx.glowStops.indices.map { SpotlightFx.cgColor(argb: SpotlightFx.glowColor(c, stop: $0)) }
    }
    /// Màu chấm sáng quả cầu disco (neon đặc) — dựng sẵn.
    private let dotColors: [CGColor] = SpotlightFx.colors.map { UIColor(neon: $0).cgColor }
    /// Mặt nạ + quầng tô chung MỘT animation mỗi mức (cùng độ sáng — màu / độ đậm nằm trong gradient).
    private static let anims: [CAAnimationGroup] = (0...3).map { anim(level: $0) }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        backgroundColor = .clear
        isOpaque = false
        clipsToBounds = true                     // quầng / chấm sáng không bao giờ ra ngoài bàn phím (#151)
        pending.reserveCapacity(Self.maxPending)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        dark.backgroundColor = UIColor.black.withAlphaComponent(CGFloat(SpotlightFx.darkness)).cgColor
        dark.isHidden = true
        layer.addSublayer(dark)
        lit.contentsGravity = .resizeAspectFill
        lit.masksToBounds = true
        lit.mask = holes
        lit.isHidden = true
        layer.addSublayer(lit)
        for _ in 0..<SpotlightFx.cap {
            let h = Self.radial()
            h.colors = SpotlightFx.maskLevels.map { UIColor.white.withAlphaComponent(CGFloat($0)).cgColor }
            h.locations = SpotlightFx.maskStops.map { NSNumber(value: $0) }
            holes.addSublayer(h); holeLayers.append(h)
            let t = Self.radial()
            t.colors = tintColors[0]
            t.locations = SpotlightFx.glowStops.map { NSNumber(value: $0) }
            t.compositingFilter = "screenBlendMode"
            t.isHidden = true
            layer.addSublayer(t); tintLayers.append(t)
        }
        buildBall()
        CATransaction.commit()
    }
    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool { false }

    private static func radial() -> CAGradientLayer {
        let g = CAGradientLayer()
        g.type = .radial
        g.startPoint = CGPoint(x: 0.5, y: 0.5)
        g.endPoint = CGPoint(x: 1, y: 1)
        g.opacity = 0
        return g
    }

    /// Animation dựng MỘT lần mỗi mức combo: độ sáng + bán kính lấy mẫu từ SpotlightFx (đỉnh, giữ, 7 bước tắt).
    private static func anim(level: Int) -> CAAnimationGroup {
        let d = SpotlightFx.duration(level: level), a = SpotlightFx.attack + SpotlightFx.hold, steps = 7
        // Mốc: 0, hết attack (đỉnh), hết giữ, rồi 7 bước đều tới hết.
        let times = [0.0, SpotlightFx.attack] + (0...steps).map { a + (d - a) * Double($0) / Double(steps) }
        let keyTimes = times.map { NSNumber(value: $0 / d) }
        let o = CAKeyframeAnimation(keyPath: "opacity")
        o.values = times.map { SpotlightFx.alpha(min($0, d * 0.9999), level: level) }
        o.keyTimes = keyTimes
        let s = CAKeyframeAnimation(keyPath: "transform.scale")
        s.values = times.map { SpotlightFx.scale($0, level: level) }
        s.keyTimes = keyTimes
        let g = CAAnimationGroup()
        g.animations = [o, s]
        g.duration = d
        g.isRemovedOnCompletion = true
        return g
    }

    private static let dotFade: CAKeyframeAnimation = {
        let steps = 6, dd = DiscoBall.dotDuration
        let o = CAKeyframeAnimation(keyPath: "opacity")
        o.values = (0...steps).map { DiscoBall.dotAlpha(dd * Double($0) / Double(steps) * 0.9999) }
        o.keyTimes = (0...steps).map { NSNumber(value: Double($0) / Double(steps)) }
        o.duration = dd
        o.isRemovedOnCompletion = true
        return o
    }()

    // MARK: ảnh

    /// Ảnh nền đang hiện (CHÍNH CGImage của view ảnh nền — không sao chép) hoặc nil = hoạ tiết neon.
    func setPhoto(_ img: CGImage?) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        hasPhoto = img != nil
        lit.contents = img
        dark.isHidden = img == nil
        if img == nil { ensureTexture() }
        texture?.isHidden = img != nil
        if img != nil { dropAtlas() }   // có ảnh nền ⇒ không người nhảy, thả atlas (0 byte)
        CATransaction.commit()
        if img == nil { ensureAtlas() }
    }

    /// Bo góc theo nền bàn phím (2 góc trên).
    func setCornerRadius(_ r: CGFloat) {
        guard layer.cornerRadius != r else { return }
        layer.cornerRadius = r
        layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        layer.cornerCurve = .circular
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        if dark.frame != bounds { dark.frame = bounds }
        if lit.frame != bounds { lit.frame = bounds }
        holes.frame = lit.bounds
        if !hasPhoto { ensureTexture() }
        let c = DiscoBall.center(minX: Double(bounds.minX), minY: Double(bounds.minY), width: Double(bounds.width))
        ball.position = CGPoint(x: c.x, y: c.y)
        ballCord.path = {
            let p = CGMutablePath()
            p.move(to: CGPoint(x: 0, y: -DiscoBall.cord - DiscoBall.diameter / 2))
            p.addLine(to: CGPoint(x: 0, y: -DiscoBall.diameter / 2))
            return p
        }()
        CATransaction.commit()
    }

    /// Không ảnh nền: phông gradient + khung người nhảy — dựng lười theo cỡ.
    private func ensureTexture() {
        let size = bounds.size
        guard size.width > 0, size.height > 0 else { return }
        if texture == nil {
            let g = CAGradientLayer()
            g.colors = SpotlightTexture.gradient.map { UIColor(neon: $0).cgColor }
            g.startPoint = CGPoint(x: 0, y: 0); g.endPoint = CGPoint(x: 1, y: 1)
            lit.insertSublayer(g, at: 0)
            texture = g
        }
        if !dancerBuilt {
            dancerBuilt = true
            for l in [dimArt, dimMask, litArt] { l.contentsGravity = .resize; l.minificationFilter = .trilinear }
            dimShade.backgroundColor = UIColor.black.withAlphaComponent(CGFloat(1 - NightDancer.shade)).cgColor
            dimShade.mask = dimMask
            dimBox.addSublayer(dimArt); dimBox.addSublayer(dimShade)
            layer.insertSublayer(dimBox, below: lit)
            litArt.shadowOffset = .zero
            litArt.shadowOpacity = 1
            litArt.shadowRadius = CGFloat(NightDancer.rim)
            litArt.shadowColor = UIColor(neon: SpotlightFx.colors[0]).cgColor
            litArt.shouldRasterize = true   // bóng neon tính MỘT lần mỗi biến thể; mặt nạ đèn chạy không vẽ lại bóng
            litBox.addSublayer(litArt)
            lit.addSublayer(litBox)
            dimBox.isHidden = true; litBox.isHidden = true
        }
        guard textureBuiltFor != size else { return }
        textureBuiltFor = size
        texture?.frame = lit.bounds
        layoutDancer()
        ensureAtlas()
    }

    /// Giải atlas MỘT lần trên luồng nền (chỉ khi không có ảnh nền + đã biết cỡ). Xong ⇒ gắn vào 3 lớp (cùng CGImage).
    private func ensureAtlas() {
        guard !hasPhoto, atlas == nil, !atlasLoading, bounds.height > 0 else { return }
        atlasLoading = true
        let gen = atlasGen, c = dancer
        let h = Double(bounds.height) * NightDancer.heightFraction
        let scale = Double(window?.screen.scale ?? traitCollection.displayScale)
        Self.atlasQueue.async { [weak self] in
            let img = NightDancer.decodeAtlas(c, displayHeight: h, scale: max(scale, 1))
            DispatchQueue.main.async {
                guard let self, gen == self.atlasGen else { return }
                self.atlasLoading = false
                if !self.hasPhoto, let img { self.attachAtlas(img) }
            }
        }
    }

    private func attachAtlas(_ img: CGImage) {
        atlas = img
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for l in [dimArt, dimMask, litArt] { l.contents = img }
        litArt.rasterizationScale = window?.screen.scale ?? traitCollection.displayScale
        dimBox.isHidden = false; litBox.isHidden = false
        layoutDancer()
        CATransaction.commit()
    }

    private func dropAtlas() {
        atlasGen += 1; atlasLoading = false; atlas = nil
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for l in [dimArt, dimMask, litArt] { l.contents = nil }
        dimBox.isHidden = true; litBox.isHidden = true
        CATransaction.commit()
    }

    /// Khung + ô + lật theo biến thể hiện tại (chỉ đặt thuộc tính — không giải / vẽ lại ảnh).
    private func layoutDancer() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let aspect: Double = atlas.map { Double($0.width) / Double(NightDancer.columns) / (Double($0.height) / Double(NightDancer.rows)) } ?? 0.75
        // Gốc bounds có thể dời (chung hệ toạ độ với bàn phím — #151) ⇒ khung theo bounds, không theo (0, 0).
        let r = NightDancer.rect(width: Double(bounds.width), height: Double(bounds.height), cellAspect: aspect)
            .offsetBy(dx: bounds.minX, dy: bounds.minY)
        let cell = NightDancer.cell(NightDancer.frame(variant))
        let flip = NightDancer.mirrored(variant) ? CATransform3DMakeScale(-1, 1, 1) : CATransform3DIdentity
        for box in [dimBox, litBox] {
            box.transform = CATransform3DIdentity
            box.frame = box === litBox ? layer.convert(r, to: lit) : r
            box.transform = flip
        }
        for l in [dimArt, dimShade, dimMask, litArt] { l.frame = CGRect(origin: .zero, size: r.size) }
        for l in [dimArt, dimMask, litArt] { l.contentsRect = cell }
    }

    // MARK: quả cầu disco

    private func buildBall() {
        let d = CGFloat(DiscoBall.diameter)
        ballCord.strokeColor = UIColor(white: 0.75, alpha: 0.7).cgColor
        ballCord.lineWidth = 0.8
        ballCord.fillColor = nil
        ball.addSublayer(ballCord)
        let body = CAShapeLayer()
        body.path = CGPath(ellipseIn: CGRect(x: -d / 2, y: -d / 2, width: d, height: d), transform: nil)
        body.fillColor = UIColor(neon: 0xB9BCC8).cgColor
        body.strokeColor = UIColor(neon: 0xE6E8F0).cgColor
        body.lineWidth = 0.6
        ball.addSublayer(body)
        // Mặt gương: lưới ô (xoay khi bấm) cắt trong hình tròn.
        let clip = CALayer()
        clip.frame = CGRect(x: -d / 2, y: -d / 2, width: d, height: d)
        clip.cornerRadius = d / 2
        clip.masksToBounds = true
        ballFacets.frame = clip.bounds
        let p = CGMutablePath(), step = d / 4
        for k in 1..<4 {
            p.move(to: CGPoint(x: CGFloat(k) * step, y: 0)); p.addLine(to: CGPoint(x: CGFloat(k) * step, y: d))
            p.move(to: CGPoint(x: 0, y: CGFloat(k) * step)); p.addLine(to: CGPoint(x: d, y: CGFloat(k) * step))
        }
        ballFacets.path = p
        ballFacets.strokeColor = UIColor(neon: 0x5A5E6E).cgColor
        ballFacets.lineWidth = 0.7
        ballFacets.fillColor = nil
        clip.addSublayer(ballFacets)
        ball.addSublayer(clip)
        let glint = CAShapeLayer()
        glint.path = CGPath(ellipseIn: CGRect(x: -d * 0.28, y: -d * 0.32, width: d * 0.22, height: d * 0.22), transform: nil)
        glint.fillColor = UIColor.white.withAlphaComponent(0.9).cgColor
        ball.addSublayer(glint)
        layer.addSublayer(ball)
    }

    private func makeDot() -> CAShapeLayer {
        let l = CAShapeLayer()
        let r = CGFloat(DiscoBall.dotRadius)
        l.path = CGPath(ellipseIn: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r), transform: nil)
        l.opacity = 0
        layer.addSublayer(l)
        return l
    }

    private func spinBall(media: CFTimeInterval) {
        let from = spinAngle
        spinAngle += CGFloat(DiscoBall.spin)
        ballFacets.transform = CATransform3DMakeRotation(spinAngle, 0, 0, 1)
        let a = CABasicAnimation(keyPath: "transform.rotation.z")
        a.fromValue = from; a.toValue = spinAngle
        a.duration = DiscoBall.spinDuration
        a.timingFunction = CAMediaTimingFunction(name: .easeOut)
        ballFacets.add(a, forKey: "spin")
        guard media - lastDots >= DiscoBall.minInterval else { return }
        lastDots = media
        let c = ball.position, press = lights.presses
        for i in 0..<DiscoBall.dotsPerPress {
            let slot = dotCursor
            dotCursor = (dotCursor + 1) % DiscoBall.dotPool
            let dot = slot < dots.count ? dots[slot] : { let d = makeDot(); dots.append(d); return d }()
            dot.fillColor = dotColors[(press + i) % dotColors.count]
            let dir = DiscoBall.direction(press: press, dot: i)
            let end = CGPoint(x: c.x + CGFloat(dir.x * DiscoBall.dotDistance), y: c.y + CGFloat(dir.y * DiscoBall.dotDistance))
            dot.position = end
            let m = CABasicAnimation(keyPath: "position")
            m.fromValue = c; m.toValue = end
            m.duration = DiscoBall.dotDuration
            m.timingFunction = CAMediaTimingFunction(name: .easeOut)
            m.isRemovedOnCompletion = true
            dot.add(m, forKey: "move")
            dot.add(Self.dotFade, forKey: "fade")
        }
    }

    // MARK: bấm

    /// Khung phím vừa bấm (toạ độ view) — vẽ ở lượt runloop kế, SAU khi phím đã chèn chữ.
    func light(key r: CGRect) {
        if pending.count >= Self.maxPending { pending.removeFirst() }
        pending.append(r)
        guard !scheduled else { return }
        scheduled = true
        DispatchQueue.main.async { [weak self] in self?.flush() }
    }

    /// Bật các quầng đang chờ (test gọi thẳng).
    func flush() {
        scheduled = false
        guard !pending.isEmpty, window != nil || Self.drawsOffscreen else { pending.removeAll(keepingCapacity: true); return }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        let media = CACurrentMediaTime()
        lit.isHidden = false
        for r in pending { fire(r, media: media) }
        if !hasPhoto {
            // Mỗi lần đèn nháy: người nhảy sang biến thể kế (không lặp liền) + viền neon theo màu đèn vừa bật.
            flashes += 1
            variant = NightDancer.next(prev: variant, flash: flashes)
            litArt.shadowColor = UIColor(neon: SpotlightFx.color(lights.presses - 1)).cgColor
            layoutDancer()
        }
        spinBall(media: media)
        CATransaction.commit()
        pending.removeAll(keepingCapacity: true)
        scheduleHide()
    }

    private func fire(_ r: CGRect, media: CFTimeInterval) {
        let level = combo.press(at: media)
        let press = lights.presses
        let slot = lights.press(at: media, level: level)
        let w = r.width > 0 ? Double(r.width) : 34
        let rad = CGFloat(SpotlightFx.radius(keyWidth: w, level: level))
        let box = CGRect(x: -rad, y: -rad, width: 2 * rad, height: 2 * rad)
        let c = CGPoint(x: r.midX, y: r.midY)
        let h = holeLayers[slot], t = tintLayers[slot]
        h.bounds = box; h.position = CGPoint(x: c.x - lit.frame.minX, y: c.y - lit.frame.minY)   // toạ độ của `lit`
        t.bounds = box; t.position = c
        t.colors = tintColors[((press % tintColors.count) + tintColors.count) % tintColors.count]   // = SpotlightFx.color(press)
        t.isHidden = false
        h.add(Self.anims[min(level, 3)], forKey: "fx")
        t.add(Self.anims[min(level, 3)], forKey: "fx")
    }

    /// MỘT asyncAfter cho cả loạt gõ: tới lúc quầng cuối tắt ⇒ ẩn `lit` (không còn lượt vẽ mặt nạ).
    private func scheduleHide() {
        guard !hideScheduled else { return }
        hideScheduled = true
        let wait = max(0.05, lights.lastEnd - CACurrentMediaTime()) + 0.05
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
            guard let self else { return }
            self.hideScheduled = false
            if CACurrentMediaTime() < self.lights.lastEnd { self.scheduleHide(); return }
            self.idle()
        }
    }

    private func idle() {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        lit.isHidden = true
        for t in tintLayers { t.isHidden = true }
        CATransaction.commit()
    }

    /// Ẩn bàn phím / gỡ: tắt mọi quầng + chấm (không còn animation nào).
    func halt() {
        pending.removeAll(keepingCapacity: true)
        for l in holeLayers { l.removeAllAnimations() }
        for l in tintLayers { l.removeAllAnimations() }
        for d in dots { d.removeAllAnimations() }
        ballFacets.removeAllAnimations()
        lights.reset()
        combo.reset()
        idle()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { halt() }
    }

    #if DEBUG
    nonisolated(unsafe) static var drawsOffscreen = false
    var debugLitHidden: Bool { lit.isHidden }
    var debugDarkHidden: Bool { dark.isHidden }
    var debugLights: SpotlightLights { lights }
    var debugHoleLayers: [CAGradientLayer] { holeLayers }
    var debugTintLayers: [CAGradientLayer] { tintLayers }
    var debugLitContents: Any? { lit.contents }
    var debugTextureVisible: Bool { texture.map { !$0.isHidden } ?? false }
    var debugAtlas: CGImage? { atlas }
    var debugDancerFrame: CGRect { dimBox.frame }
    var debugDancerVisible: Bool { !dimBox.isHidden && !litBox.isHidden }
    var debugDancerCell: CGRect { dimArt.contentsRect }
    var debugDancerMirrored: Bool { dimBox.transform.m11 < 0 }
    var debugRimColor: CGColor? { litArt.shadowColor }
    /// Test: giải + gắn atlas ĐỒNG BỘ (đo RAM / ảnh xuất).
    func debugLoadAtlasNow(scale: Double) {
        guard !hasPhoto, let img = NightDancer.decodeAtlas(dancer, displayHeight: Double(bounds.height) * NightDancer.heightFraction,
                                                           scale: scale) else { return }
        atlasGen += 1; atlasLoading = false
        attachAtlas(img)
    }
    var debugBallPosition: CGPoint { ball.position }
    var debugDots: [CAShapeLayer] { dots }
    func debugIdle() { idle() }

    /// Ảnh xem trước (test xuất ảnh — layer.render bỏ qua mask / animation): vẽ lại bằng Core Graphics theo CÙNG hàm thuần
    /// các quầng `lights` (tâm, bề rộng phím, mức combo, số giây đã trôi, chỉ số màu) + tư thế + ảnh nền (nếu có) + quả cầu.
    static func debugRender(in ctx: CGContext, size: CGSize, photo: CGImage?, atlas: CGImage?, variant: Int,
                            lights: [(center: CGPoint, keyWidth: Double, level: Int, dt: Double, color: Int)]) {
        let rect = CGRect(origin: .zero, size: size)
        let cs = CGColorSpaceCreateDeviceRGB()
        if let photo {
            ctx.saveGState(); ctx.translateBy(x: 0, y: size.height); ctx.scaleBy(x: 1, y: -1)
            ctx.draw(photo, in: rect); ctx.restoreGState()
            ctx.setFillColor(UIColor.black.withAlphaComponent(CGFloat(SpotlightFx.darkness)).cgColor); ctx.fill(rect)
        }
        // Người nhảy: ô của biến thể (cắt từ atlas) + khung 85 % + lật.
        var cellImg: CGImage?, dRect = CGRect.zero
        if photo == nil, let atlas {
            let c = NightDancer.cell(NightDancer.frame(variant))
            let px = CGRect(x: c.minX * CGFloat(atlas.width), y: c.minY * CGFloat(atlas.height),
                            width: c.width * CGFloat(atlas.width), height: c.height * CGFloat(atlas.height)).integral
            cellImg = atlas.cropping(to: px)
            dRect = NightDancer.rect(width: Double(size.width), height: Double(size.height), cellAspect: Double(px.width / px.height))
        }
        let mirrored = NightDancer.mirrored(variant)
        func drawDancer(_ img: CGImage) {
            ctx.saveGState()
            if mirrored { ctx.translateBy(x: dRect.midX, y: 0); ctx.scaleBy(x: -1, y: 1); ctx.translateBy(x: -dRect.midX, y: 0) }
            UIImage(cgImage: img).draw(in: dRect)
            ctx.restoreGState()
        }
        if let cellImg {
            // Bản tối (ngoài đèn): ảnh rồi phủ đen 88 % chỉ trên phần có hình.
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
            drawDancer(cellImg)
            ctx.setBlendMode(.sourceAtop)
            ctx.setFillColor(UIColor.black.withAlphaComponent(CGFloat(1 - NightDancer.shade)).cgColor); ctx.fill(dRect)
            ctx.endTransparencyLayer()
        }
        // Mặt nạ quầng sáng (xám) → lớp `lit` (ảnh / phông + viền).
        let w = Int(size.width), h = Int(size.height)
        guard let mctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(),
                                   bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return }
        mctx.setFillColor(gray: 0, alpha: 1); mctx.fill(rect)
        mctx.setBlendMode(.lighten)
        for l in lights {
            let a = SpotlightFx.alpha(l.dt, level: l.level)
            guard a > 0 else { continue }
            let r = CGFloat(SpotlightFx.radius(keyWidth: l.keyWidth, level: l.level) * SpotlightFx.scale(l.dt, level: l.level))
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceGray(),
                               colors: SpotlightFx.maskLevels.map { CGColor(gray: CGFloat(a * $0), alpha: 1) } as CFArray,
                               locations: SpotlightFx.maskStops.map { CGFloat($0) })!
            let c = CGPoint(x: l.center.x, y: size.height - l.center.y)
            mctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: r, options: [])
        }
        guard let mask = mctx.makeImage() else { return }
        ctx.saveGState()
        ctx.clip(to: rect, mask: mask)
        if let photo {
            ctx.saveGState(); ctx.translateBy(x: 0, y: size.height); ctx.scaleBy(x: 1, y: -1)
            ctx.draw(photo, in: rect); ctx.restoreGState()
        } else {
            let g = CGGradient(colorsSpace: cs, colors: SpotlightTexture.gradient.map { UIColor(neon: $0).cgColor } as CFArray, locations: nil)!
            ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
            if let cellImg {
                // Màu thật + viền neon (bóng) theo màu đèn cuối — chỉ trong mặt nạ đèn.
                let rim = UIColor(neon: SpotlightFx.colors[(lights.last?.color ?? 0) % 3]).cgColor
                ctx.saveGState(); ctx.setShadow(offset: .zero, blur: CGFloat(NightDancer.rim * 2), color: rim)
                drawDancer(cellImg); drawDancer(cellImg)
                ctx.restoreGState()
                drawDancer(cellImg)
            }
        }
        ctx.restoreGState()
        // Quầng tô neon (screen): lõi gần trắng → màu → vành sáng mờ.
        ctx.saveGState(); ctx.setBlendMode(.screen)
        for l in lights {
            let a = SpotlightFx.alpha(l.dt, level: l.level)
            guard a > 0 else { continue }
            let r = CGFloat(SpotlightFx.radius(keyWidth: l.keyWidth, level: l.level) * SpotlightFx.scale(l.dt, level: l.level))
            let neon = SpotlightFx.colors[l.color % 3]
            let cols = SpotlightFx.glowStops.indices.map { i -> CGColor in
                let c = SpotlightFx.cgColor(argb: SpotlightFx.glowColor(neon, stop: i))
                return c.copy(alpha: c.alpha * CGFloat(a)) ?? c
            }
            let g = CGGradient(colorsSpace: cs, colors: cols as CFArray, locations: SpotlightFx.glowStops.map { CGFloat($0) })!
            ctx.drawRadialGradient(g, startCenter: l.center, startRadius: 0, endCenter: l.center, endRadius: r, options: [])
        }
        ctx.restoreGState()
        // Quả cầu disco.
        let bc = DiscoBall.center(minX: 0, minY: 0, width: Double(size.width)), d = CGFloat(DiscoBall.diameter)
        let b = CGRect(x: CGFloat(bc.x) - d / 2, y: CGFloat(bc.y) - d / 2, width: d, height: d)
        ctx.setStrokeColor(UIColor(white: 0.75, alpha: 0.7).cgColor); ctx.setLineWidth(0.8)
        ctx.move(to: CGPoint(x: b.midX, y: b.minY - CGFloat(DiscoBall.cord))); ctx.addLine(to: CGPoint(x: b.midX, y: b.minY)); ctx.strokePath()
        ctx.setFillColor(UIColor(neon: 0xB9BCC8).cgColor); ctx.fillEllipse(in: b)
        ctx.saveGState(); ctx.addEllipse(in: b); ctx.clip()
        ctx.setStrokeColor(UIColor(neon: 0x5A5E6E).cgColor); ctx.setLineWidth(0.7)
        for k in 1..<4 {
            ctx.move(to: CGPoint(x: b.minX + CGFloat(k) * d / 4, y: b.minY)); ctx.addLine(to: CGPoint(x: b.minX + CGFloat(k) * d / 4, y: b.maxY))
            ctx.move(to: CGPoint(x: b.minX, y: b.minY + CGFloat(k) * d / 4)); ctx.addLine(to: CGPoint(x: b.maxX, y: b.minY + CGFloat(k) * d / 4))
        }
        ctx.strokePath(); ctx.restoreGState()
        ctx.setFillColor(UIColor.white.withAlphaComponent(0.9).cgColor)
        ctx.fillEllipse(in: CGRect(x: b.midX - d * 0.28, y: b.midY - d * 0.32, width: d * 0.22, height: d * 0.22))
        for i in 0..<DiscoBall.dotsPerPress {
            let v = DiscoBall.direction(press: lights.count, dot: i), t = DiscoBall.dotTravel(0.15)
            ctx.setFillColor(UIColor(neon: SpotlightFx.colors[(lights.count + i) % 3]).withAlphaComponent(CGFloat(DiscoBall.dotAlpha(0.15))).cgColor)
            let p = CGPoint(x: b.midX + CGFloat(v.x * t), y: b.midY + CGFloat(v.y * t)), r = CGFloat(DiscoBall.dotRadius)
            ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
        }
    }
    #else
    static let drawsOffscreen = false
    #endif
}

/// Phông tím đêm khi không có ảnh nền (chỉ lộ dưới đèn, quanh người nhảy) — Android SpotlightTexture cùng số.
enum SpotlightTexture {
    /// Gradient chéo: tím đậm → tím đêm → xanh đêm.
    static let gradient: [UInt32] = [0x3A0A5E, 0x16073A, 0x06284A]
}

private extension UIColor {
    /// 0xRRGGBB ⇒ màu đục.
    convenience init(neon v: UInt32) {
        self.init(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                  blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
}

// MARK: - Người nhảy hoạt hình (không có ảnh nền)

/// Người nhảy (KHÔNG có ảnh nền): nhân vật HOẠT HÌNH của Bạn đồng hành (atlas 4 × 2 buddy-<id>-v2.png — khung 0 đứng,
/// 1 nhảy, 2 xoay ¾, 3 nghiêng phải, 4 sau lưng, 5 nghiêng trái, 6 xoay về; 7 ngủ không dùng) cỡ lớn phía sau phím, chìm
/// trong tối (~12 % sáng); chỉ vùng đèn rọi thấy màu thật + viền neon theo màu đèn. Mỗi lần đèn nháy ⇒ biến thể kế: 7 khung
/// × {thường, lật ngang} = 14 biến thể. Hàm THUẦN — Android NightDancer cùng số (test chung).
enum NightDancer {
    /// Chuỗi nhảy nhanh (khung atlas) — trọng số chọn khung; bỏ khung 7 (ngủ).
    static let sequence = [0, 1, 0, 1, 2, 3, 4, 5, 6]
    static let frames = 7
    static let variants = frames * 2
    /// Xác suất theo đúng chuỗi nhảy (còn lại: khung ngẫu nhiên 0…6).
    static let follow = 0.7
    /// Lật ngang: sau biến thể thường / sau biến thể đã lật (thấp hơn ⇒ ít khi lật hai lần liền).
    static let mirror = 0.5, mirrorAgain = 0.25
    /// Cao nhân vật = tỉ lệ cao bàn phím (cả dải gợi ý), đứng sát đáy, giữa ngang.
    static let heightFraction = 0.85
    /// Độ sáng phần ngoài đèn.
    static let shade = 0.12
    /// Viền neon quanh nhân vật dưới đèn (pt).
    static let rim = 2.5
    static let columns = 4, rows = 2
    /// Trần cạnh dài atlas khi giải (px) — ≤ 2048 × 1365 × 4 B ≈ 11 MB; atlas hiện 1536 × 1024 ⇒ 6,3 MB.
    static let maxLongEdge = 2048

    static func frame(_ variant: Int) -> Int { ((variant % variants) + variants) % variants % frames }
    static func mirrored(_ variant: Int) -> Bool { ((variant % variants) + variants) % variants >= frames }

    /// Nhân vật nhảy: chàng trai nếu Bạn đồng hành đang chọn là chàng trai; còn lại ⇒ cô gái.
    static func character(_ buddy: BuddyCharacter) -> BuddyCharacter { buddy == .boy ? .boy : .girl }

    /// Biến thể của lần nháy thứ `flash` sau biến thể `prev` (−1 = chưa có): theo chuỗi nhảy với xác suất `follow`,
    /// không thì khung ngẫu nhiên; lật ngang `mirror` / `mirrorAgain`; KHÔNG BAO GIỜ trùng `prev`. Tất định theo `flash`.
    static func next(prev: Int, flash: Int) -> Int {
        var st = fxStep(fxSeed(flash &* 7919 &+ 17))   // bỏ một bước: số đầu của seed liền nhau tương quan
        st = fxStep(st); let a = fxValue(st)
        st = fxStep(st); let b = fxValue(st)
        st = fxStep(st); let c = fxValue(st)
        var f = a < follow ? sequence[((flash % sequence.count) + sequence.count) % sequence.count]
                           : Swift.min(frames - 1, Int(b * Double(frames)))
        let m = c < (prev >= 0 && mirrored(prev) ? mirrorAgain : mirror)
        var v = f + (m ? frames : 0)
        if v == prev { f = (f + 1) % frames; v = f + (m ? frames : 0) }
        return v
    }

    /// Ô `frame` trong atlas (contentsRect, tỉ lệ 0…1).
    static func cell(_ frame: Int) -> CGRect {
        let i = ((frame % (columns * rows)) + columns * rows) % (columns * rows)
        return CGRect(x: Double(i % columns) / Double(columns), y: Double(i / columns) / Double(rows),
                      width: 1 / Double(columns), height: 1 / Double(rows))
    }

    /// Khung vẽ trong bàn phím w × h với ô tỉ lệ rộng/cao `cellAspect`: cao 85 %, đứng đáy, giữa ngang.
    static func rect(width w: Double, height h: Double, cellAspect: Double) -> CGRect {
        let fh = h * heightFraction, fw = fh * cellAspect
        return CGRect(x: (w - fw) / 2, y: h - fh, width: fw, height: fh)
    }

    /// Cạnh dài (px) cần giải atlas để ô cao đúng `displayHeight` pt × `scale` — không quá ảnh gốc, không quá trần.
    static func decodeLongEdge(displayHeight: Double, scale: Double, atlasW: Int, atlasH: Int) -> Int {
        guard atlasW > 0, atlasH > 0 else { return 0 }
        let native = Swift.max(atlasW, atlasH)
        let need = Int((displayHeight * scale * Double(rows) * Double(native) / Double(atlasH)).rounded(.up))
        return Swift.min(need, native, maxLongEdge)
    }

    /// RAM ảnh đã giải (byte, RGBA 8-bit) khi cạnh dài = `longEdge`.
    static func decodedBytes(longEdge: Int, atlasW: Int, atlasH: Int) -> Int {
        guard atlasW > 0, atlasH > 0, longEdge > 0 else { return 0 }
        let native = Double(Swift.max(atlasW, atlasH))
        let w = (Double(atlasW) * Double(longEdge) / native).rounded(), h = (Double(atlasH) * Double(longEdge) / native).rounded()
        return Int(w * h * 4)
    }

    /// Giải atlas nhân vật `c` (cạnh dài theo cỡ hiển thị) — gọi trên luồng nền. Không có ảnh / lỗi ⇒ nil.
    static func decodeAtlas(_ c: BuddyCharacter, displayHeight: Double, scale: Double) -> CGImage? {
        guard let url = VTBundleResource.url("buddy-\(c.rawValue)-v2", "png", anchor: SpotlightView.self),
              let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        let edge = decodeLongEdge(displayHeight: displayHeight, scale: scale, atlasW: w, atlasH: h)
        guard edge > 0 else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(src, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: edge,
            kCGImageSourceShouldCacheImmediately: true,
        ] as CFDictionary)
    }
}
