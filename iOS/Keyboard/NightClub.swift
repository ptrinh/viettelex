// "Neon Night Club" (11/2026, Plus): ĐÈN RỌI trên ảnh nền ("photoFx":"spotlight" — ThemeSpec) + quả cầu disco nhỏ.
// Song sinh android/keyboard/.../Spotlight.kt (hàm thuần, CÙNG SỐ — test chung) + app/.../ime/SpotlightView.kt.
//
// Chỉ tồn tại khi theme đang dùng có "photoFx":"spotlight" (KeyboardView.spotlight == nil với mọi theme khác ⇒ 0 lớp,
// đường phím chỉ đọc một optional). Thứ tự lớp: nền theme / ảnh nền / lớp phủ ảnh · ĐÈN RỌI · hiệu ứng dải dưới phím ·
// phím. Không nhận chạm.
//
// • Có ảnh nền: lớp đen 90 % phủ ảnh; mỗi phím bấm "rọi" một quầng tròn mềm (bán kính ~1,6–2 bề rộng phím) — lớp
//   `lit` chứa CHÍNH CGImage của ảnh nền đang hiện (không giải mã / sao chép thêm) cắt bằng mặt nạ là vài
//   CAGradientLayer radial (lỗ sáng), cộng quầng tô màu neon hồng / tím / lục lam xoay vòng mỗi lần bấm. Tắt dần
//   ~0,7–0,9 s, tối đa 6 quầng (quầng cũ nhất bị thay); gõ nhanh (ComboMeter) ⇒ quầng to + sáng + lâu hơn chút.
// • Không có ảnh nền: phía sau phím là BÓNG ĐEN cô gái nhảy (DancerFigure — 8 tư thế vector, kiểu bóng đen quảng cáo máy
//   nghe nhạc, đầm kín): mỗi lần đèn nháy bóng đổi tư thế, đèn rọi viền neon theo màu đèn + phông tím đêm quanh bóng;
//   ngoài quầng sáng mọi thứ chìm trong tối. Có ảnh nền ⇒ không có bóng.
// • Hiệu năng: lớp + animation dựng MỘT lần (pool); bấm chỉ đặt vị trí / cỡ + gắn animation dựng sẵn (render server
//   chạy phần còn lại — không timer khung hình). Hết quầng ⇒ ẩn `lit` (không còn lượt vẽ mặt nạ) bằng MỘT asyncAfter
//   cho cả loạt gõ. Nghỉ = 0 animation.
import UIKit

/// Cổng chạy (thuần): theme có "photoFx":"spotlight" + Plus + không tiết kiệm pin. Giảm chuyển động KHÔNG tắt
/// (như hiệu ứng phím — Phil 19/10/2026). Android SpotlightPolicy y hệt.
enum SpotlightPolicy {
    static func active(photoFx: String?, plus: Bool, lowPower: Bool) -> Bool {
        photoFx == ThemeExtraIds.spotlight && plus && !lowPower
    }
}

/// Hàm thuần đèn rọi (giây, pt) — Android SpotlightFx cùng số (test chung).
enum SpotlightFx {
    /// Tối đa số quầng sống cùng lúc (quầng cũ nhất bị thay).
    static let cap = 6
    /// Lớp đen phủ ảnh nền (0…1).
    static let darkness = 0.9
    /// Neon xoay vòng mỗi lần bấm: hồng, tím, lục lam.
    static let colors: [UInt32] = [0xFF2FD0, 0x9B5CFF, 0x2FE6FF]
    /// Độ đậm quầng tô màu (nhân với độ sáng quầng).
    static let tint = 0.32
    static let attack = 0.06
    static let baseDuration = 0.72
    static let durationPerLevel = 0.05
    static let radiusFactor = 1.6
    static let radiusPerLevel = 0.15
    static let minRadius = 36.0
    static let maxRadius = 150.0
    static let peakBase = 0.78
    static let peakPerLevel = 0.07
    static let startScale = 0.8
    static let growScale = 0.3

    private static func lv(_ level: Int) -> Double { Double(min(max(level, 0), 3)) }

    /// Thời gian sống của quầng ở mức combo `level` (0…3): 0,72…0,87 s.
    static func duration(level: Int) -> Double { baseDuration + durationPerLevel * lv(level) }
    /// Bán kính quầng (pt) theo bề rộng phím + mức combo, kẹp [36, 150].
    static func radius(keyWidth w: Double, level: Int) -> Double {
        min(max(w * (radiusFactor + radiusPerLevel * lv(level)), minRadius), maxRadius)
    }
    /// Độ sáng đỉnh 0,78…0,99.
    static func peak(level: Int) -> Double { min(1, peakBase + peakPerLevel * lv(level)) }
    /// Độ sáng sau `dt` giây: lên tuyến tính trong `attack`, rồi tắt (1−u)².
    static func alpha(_ dt: Double, level: Int) -> Double {
        let d = duration(level: level), p = peak(level: level)
        guard dt >= 0, dt < d else { return 0 }
        if dt < attack { return p * dt / attack }
        let u = (dt - attack) / (d - attack)
        return p * (1 - u) * (1 - u)
    }
    /// Hệ số bán kính sau `dt` (0,8 → 1,1, chậm dần).
    static func scale(_ dt: Double, level: Int) -> Double {
        let x = min(max(dt / duration(level: level), 0), 1)
        return startScale + growScale * (1 - (1 - x) * (1 - x))
    }
    /// Màu neon của lần bấm thứ `press`.
    static func color(_ press: Int) -> UInt32 { colors[((press % colors.count) + colors.count) % colors.count] }
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
    /// Không ảnh nền: "phông" tím đêm (trong `lit` — chỉ lộ dưới đèn) + viền neon của bóng (trong `lit`) + bóng đen cô gái
    /// nhảy (NGOÀI `lit`, trên quầng tô ⇒ che nửa trong của viền: chỉ còn vành sáng quanh bóng). Dựng lười.
    private var texture: CAGradientLayer?
    private var rim: CAShapeLayer?
    private var dancer: CAShapeLayer?
    private var textureBuiltFor: CGSize = .zero
    private var dancerPaths: [Int: CGPath] = [:]
    private var flashes = 0
    private(set) var poseIndex = 0
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
    /// Màu tô (CGColor) dựng sẵn: [đậm, trong] mỗi màu.
    private let tintColors: [[CGColor]] = SpotlightFx.colors.map {
        [UIColor(neon: $0).cgColor, UIColor(neon: $0).withAlphaComponent(0).cgColor]
    }
    private static let holeAnims: [CAAnimationGroup] = (0...3).map { anim(level: $0, tint: false) }
    private static let tintAnims: [CAAnimationGroup] = (0...3).map { anim(level: $0, tint: true) }

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
            h.colors = [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0.55).cgColor, UIColor.white.withAlphaComponent(0).cgColor]
            h.locations = [0, 0.45, 1]
            holes.addSublayer(h); holeLayers.append(h)
            let t = Self.radial()
            t.colors = tintColors[0]
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

    /// Animation dựng MỘT lần mỗi mức combo: độ sáng + bán kính lấy mẫu từ SpotlightFx (8 bước).
    private static func anim(level: Int, tint: Bool) -> CAAnimationGroup {
        let d = SpotlightFx.duration(level: level), a = SpotlightFx.attack, steps = 7
        // Mốc: 0, hết attack (đỉnh), rồi 7 bước đều tới hết.
        let times = [0.0] + (0...steps).map { a + (d - a) * Double($0) / Double(steps) }
        let keyTimes = times.map { NSNumber(value: $0 / d) }
        let o = CAKeyframeAnimation(keyPath: "opacity")
        o.values = times.map { SpotlightFx.alpha(min($0, d * 0.9999), level: level) * (tint ? SpotlightFx.tint : 1) }
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
        for l in [texture, rim, dancer] as [CALayer?] { l?.isHidden = img != nil }
        CATransaction.commit()
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

    /// Không ảnh nền: phông gradient + viền + bóng cô gái nhảy — dựng lười, path theo cỡ (cache theo tư thế).
    private func ensureTexture() {
        let size = bounds.size
        guard size.width > 0, size.height > 0 else { return }
        if texture == nil {
            let g = CAGradientLayer()
            g.colors = SpotlightTexture.gradient.map { UIColor(neon: $0).cgColor }
            g.startPoint = CGPoint(x: 0, y: 0); g.endPoint = CGPoint(x: 1, y: 1)
            lit.insertSublayer(g, at: 0)
            let r = CAShapeLayer()
            r.fillColor = nil
            r.lineWidth = CGFloat(DancerFigure.rimWidth * 2)       // nửa trong bị bóng che ⇒ vành = rimWidth
            r.lineJoin = .round
            r.strokeColor = UIColor(neon: SpotlightFx.colors[0]).cgColor
            lit.addSublayer(r)
            let d = CAShapeLayer()
            d.fillColor = UIColor.black.cgColor
            layer.insertSublayer(d, below: ball)
            texture = g; rim = r; dancer = d
        }
        guard textureBuiltFor != size else { return }
        textureBuiltFor = size
        dancerPaths.removeAll()
        texture?.frame = lit.bounds
        rim?.frame = lit.bounds
        dancer?.frame = bounds
        applyPose()
    }

    /// Path tư thế hiện tại ở cỡ hiện tại (toạ độ cục bộ 0…w, 0…h — dùng chung cho viền lẫn bóng).
    private func applyPose() {
        let poses = DancerFigure.poses
        guard !poses.isEmpty, bounds.width > 0, bounds.height > 0 else { return }
        let i = poseIndex % poses.count
        let path: CGPath
        if let p = dancerPaths[i] { path = p } else {
            let m = CGMutablePath()
            for q in DancerFigure.fitted(poses[i], width: Double(bounds.width), height: Double(bounds.height)) where q.count >= 6 {
                m.move(to: CGPoint(x: q[0], y: q[1]))
                for k in stride(from: 2, to: q.count, by: 2) { m.addLine(to: CGPoint(x: q[k], y: q[k + 1])) }
                m.closeSubpath()
            }
            dancerPaths[i] = m; path = m
        }
        rim?.path = path
        dancer?.path = path
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
            dot.fillColor = tintColors[(press + i) % tintColors.count][0]
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
        if !hasPhoto, dancer != nil {
            // Mỗi lần đèn nháy: bóng đổi tư thế (xoay vòng, không lặp liền) + viền theo màu đèn vừa bật.
            flashes += 1
            poseIndex = DancerFigure.poseIndex(press: flashes, count: DancerFigure.poses.count)
            rim?.strokeColor = UIColor(neon: SpotlightFx.color(lights.presses - 1)).cgColor
            applyPose()
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
        h.add(Self.holeAnims[min(level, 3)], forKey: "fx")
        t.add(Self.tintAnims[min(level, 3)], forKey: "fx")
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
    var debugDancer: CAShapeLayer? { dancer }
    var debugRim: CAShapeLayer? { rim }
    var debugBallPosition: CGPoint { ball.position }
    var debugDots: [CAShapeLayer] { dots }
    func debugIdle() { idle() }

    /// Ảnh xem trước (test xuất ảnh — layer.render bỏ qua mask / animation): vẽ lại bằng Core Graphics theo CÙNG hàm thuần
    /// các quầng `lights` (tâm, bề rộng phím, mức combo, số giây đã trôi, chỉ số màu) + tư thế + ảnh nền (nếu có) + quả cầu.
    static func debugRender(in ctx: CGContext, size: CGSize, photo: CGImage?, pose: Int,
                            lights: [(center: CGPoint, keyWidth: Double, level: Int, dt: Double, color: Int)]) {
        let rect = CGRect(origin: .zero, size: size)
        let cs = CGColorSpaceCreateDeviceRGB()
        if let photo {
            ctx.saveGState(); ctx.translateBy(x: 0, y: size.height); ctx.scaleBy(x: 1, y: -1)
            ctx.draw(photo, in: rect); ctx.restoreGState()
            ctx.setFillColor(UIColor.black.withAlphaComponent(CGFloat(SpotlightFx.darkness)).cgColor); ctx.fill(rect)
        }
        let poses = DancerFigure.poses
        let path = CGMutablePath()
        if photo == nil, !poses.isEmpty {
            for q in DancerFigure.fitted(poses[pose % poses.count], width: Double(size.width), height: Double(size.height)) {
                path.move(to: CGPoint(x: q[0], y: q[1]))
                for k in stride(from: 2, to: q.count, by: 2) { path.addLine(to: CGPoint(x: q[k], y: q[k + 1])) }
                path.closeSubpath()
            }
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
                               colors: [CGColor(gray: a, alpha: 1), CGColor(gray: a * 0.55, alpha: 1), CGColor(gray: 0, alpha: 1)] as CFArray,
                               locations: [0, 0.45, 1])!
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
            if let last = lights.last {
                ctx.addPath(path)
                ctx.setStrokeColor(UIColor(neon: SpotlightFx.colors[last.color % 3]).cgColor)
                ctx.setLineWidth(CGFloat(DancerFigure.rimWidth * 2)); ctx.setLineJoin(.round)
                ctx.strokePath()
            }
        }
        ctx.restoreGState()
        // Quầng tô neon (screen).
        ctx.saveGState(); ctx.setBlendMode(.screen)
        for l in lights {
            let a = SpotlightFx.alpha(l.dt, level: l.level) * SpotlightFx.tint
            guard a > 0 else { continue }
            let r = CGFloat(SpotlightFx.radius(keyWidth: l.keyWidth, level: l.level) * SpotlightFx.scale(l.dt, level: l.level))
            let col = UIColor(neon: SpotlightFx.colors[l.color % 3])
            let g = CGGradient(colorsSpace: cs, colors: [col.withAlphaComponent(CGFloat(a)).cgColor, col.withAlphaComponent(0).cgColor] as CFArray,
                               locations: [0, 1])!
            ctx.drawRadialGradient(g, startCenter: l.center, startRadius: 0, endCenter: l.center, endRadius: r, options: [])
        }
        ctx.restoreGState()
        if photo == nil { ctx.addPath(path); ctx.setFillColor(UIColor.black.cgColor); ctx.fillPath() }
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

/// Phông tím đêm khi không có ảnh nền (chỉ lộ dưới đèn, sau bóng cô gái nhảy) — Android SpotlightTexture cùng số.
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

// MARK: - Bóng cô gái nhảy (không có ảnh nền)

/// Một tư thế (độ; hướng a ⇒ vector (sin a, cos a), y hướng xuống: 0 = xuống, 90 = phải, 180 = lên, −90 = trái).
/// l / r = tay, chân bên TRÁI / PHẢI màn hình; ua / fa = cánh tay / cẳng tay; th / sh = đùi / cẳng chân; flare = độ xoè váy 0…100.
struct DancerPose: Equatable {
    var id: String
    var torso = 180, lua = 0, lfa = 0, rua = 0, rfa = 0, lth = 0, lsh = 0, rth = 0, rsh = 0, hair = 0, flare = 0
}

/// Bóng đen cô gái nhảy (theme Neon Night Club, KHÔNG có ảnh nền): khối hình bo tròn (đầu, tóc đuôi ngựa, thân thon, váy
/// chữ A, tay chân) dựng từ 8 tư thế trong themes/dancer-poses.json (sinh vào BuiltinThemesData.dancerJson). Phong cách bóng
/// đen quảng cáo máy nghe nhạc: dáng nhảy năng động, đầm kín, không chi tiết cơ thể. Mỗi lần đèn rọi nháy ⇒ tư thế kế
/// (bước 3 mod 8: đủ vòng, không lặp liền). Đa giác cùng chiều quay ⇒ tô nonzero = hợp. Hình học thuần — Android
/// DancerFigure cùng số (checksum chung).
enum DancerFigure {
    static let torsoLen = 0.27, neck = 0.03, headR = 0.058, shoulder = 0.068, hipW = 0.034
    static let upperArm = 0.14, forearm = 0.13, thigh = 0.235, shin = 0.22, foot = 0.05, hair = 0.21
    static let seg = 6
    /// Bóng cao 86 % khung, giữa ngang, cách đáy 7 %.
    static let heightFraction = 0.86
    /// Bước xoay vòng tư thế (nguyên tố cùng nhau với số tư thế ⇒ đi đủ vòng, không lặp liền).
    static let step = 3
    /// Viền đèn rọi (pt) — nửa ngoài lộ ra quanh bóng.
    static let rimWidth = 3.0
    static let fields = ["torso", "lua", "lfa", "rua", "rfa", "lth", "lsh", "rth", "rsh", "hair", "flare"]

    /// Đọc CHẶT (StrictJSON): mục thiếu / sai kiểu / ngoài khoảng ⇒ bỏ mục; hỏng cả ⇒ [].
    static func parse(_ text: String) -> [DancerPose] {
        guard case .success(.object(let root)) = StrictJSON.parse(text),
              let arr = root.first(where: { $0.0 == "poses" })?.1, case .array(let items) = arr else { return [] }
        var out: [DancerPose] = []
        for it in items.prefix(12) {
            guard case .object(let m) = it else { continue }
            let d = Dictionary(m, uniquingKeysWith: { a, _ in a })
            guard case .string(let id)? = d["id"], !id.isEmpty else { continue }
            var vals: [Int] = []
            for f in fields {
                guard case .int(let v)? = d[f], abs(v) <= 360 else { break }
                vals.append(v)
            }
            guard vals.count == fields.count, vals[10] >= 0, vals[10] <= 100 else { continue }
            out.append(DancerPose(id: id, torso: vals[0], lua: vals[1], lfa: vals[2], rua: vals[3], rfa: vals[4],
                                  lth: vals[5], lsh: vals[6], rth: vals[7], rsh: vals[8], hair: vals[9], flare: vals[10]))
        }
        return out
    }
    /// Tư thế dựng sẵn — đọc LƯỜI (chỉ khi theme này đang dùng và không có ảnh nền).
    static let poses: [DancerPose] = parse(BuiltinThemesData.dancerJson)

    /// Tư thế của lần nháy thứ `press`.
    static func poseIndex(press: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return ((press % count + count) % count) * step % count
    }

    private static func vec(_ a: Int) -> (Double, Double) { let r = Double(a) * .pi / 180; return (sin(r), cos(r)) }
    private static func add(_ p: (Double, Double), _ v: (Double, Double), _ k: Double) -> (Double, Double) {
        (p.0 + v.0 * k, p.1 + v.1 * k)
    }
    private static func oriented(_ pts: [(Double, Double)]) -> [Double] {
        var a = 0.0
        for i in 0..<pts.count { let p = pts[i], q = pts[(i + 1) % pts.count]; a += p.0 * q.1 - q.0 * p.1 }
        let o = a >= 0 ? pts : Array(pts.reversed())
        return o.flatMap { [$0.0, $0.1] }
    }
    private static func capsule(_ p0: (Double, Double), _ p1: (Double, Double), _ r0: Double, _ r1: Double) -> [Double] {
        let dx = p1.0 - p0.0, dy = p1.1 - p0.1
        let a = hypot(dx, dy) > 1e-9 ? atan2(dy, dx) : 0
        var pts: [(Double, Double)] = []
        for k in 0...seg {
            let t = a - .pi / 2 + .pi * Double(k) / Double(seg)
            pts.append((p1.0 + r1 * cos(t), p1.1 + r1 * sin(t)))
        }
        for k in 0...seg {
            let t = a + .pi / 2 + .pi * Double(k) / Double(seg)
            pts.append((p0.0 + r0 * cos(t), p0.1 + r0 * sin(t)))
        }
        return oriented(pts)
    }
    private static func circle(_ c: (Double, Double), _ r: Double) -> [Double] {
        oriented((0..<(2 * seg)).map { k in
            let t = 2 * Double.pi * Double(k) / Double(2 * seg)
            return (c.0 + r * cos(t), c.1 + r * sin(t))
        })
    }

    /// Đa giác (mảng phẳng x0, y0, x1, y1 …) của tư thế, toạ độ đơn vị (hông = gốc). Thứ tự: thân, cổ, đầu, tóc, váy,
    /// tay trái (cánh, cẳng, bàn tay), tay phải, chân trái (đùi, cẳng, bàn chân), chân phải — 17 đa giác.
    static func polygons(_ p: DancerPose) -> [[Double]] {
        let hip = (0.0, 0.0), t = vec(p.torso), perp = (-t.1, t.0)
        let neckP = add(hip, t, torsoLen), head = add(neckP, t, neck + headR)
        func side(_ k: Double, _ w: Double) -> (Double, Double) { add(add(hip, t, k), perp, w) }
        var out: [[Double]] = []
        out.append(oriented([side(0, -0.05), side(0.12, -0.04), side(0.20, -0.052), side(torsoLen, -0.072),
                             side(torsoLen, 0.072), side(0.20, 0.052), side(0.12, 0.04), side(0, 0.05)]))
        out.append(capsule(neckP, add(neckP, t, neck + 0.01), 0.02, 0.02))
        out.append(circle(head, headR))
        out.append(capsule(add(head, t, -0.01), add(head, vec(p.hair), hair), headR, 0.03))
        let fl = Double(p.flare) / 100, down = (-t.0, -t.1)
        let w0 = add(hip, t, 0.12), hem = add(hip, down, 0.11), hw = 0.10 + 0.05 * fl
        out.append(oriented([add(w0, perp, -0.045), add(hem, perp, -hw), add(hem, perp, hw), add(w0, perp, 0.045)]))
        for (s, ua, fa) in [(-1.0, p.lua, p.lfa), (1.0, p.rua, p.rfa)] {
            let sh = add(add(hip, t, torsoLen - 0.015), perp, s * shoulder)
            let el = add(sh, vec(ua), upperArm), hd = add(el, vec(fa), forearm)
            out.append(capsule(sh, el, 0.027, 0.021))
            out.append(capsule(el, hd, 0.021, 0.016))
            out.append(circle(hd, 0.019))
        }
        for (s, th, sn) in [(-1, p.lth, p.lsh), (1, p.rth, p.rsh)] {
            let root = add(hip, perp, Double(s) * hipW)
            let kn = add(root, vec(th), thigh), an = add(kn, vec(sn), shin)
            out.append(capsule(root, kn, 0.04, 0.027))
            out.append(capsule(kn, an, 0.026, 0.015))
            out.append(capsule(an, add(an, vec(sn + s * 80), foot), 0.015, 0.011))
        }
        return out
    }

    /// Đặt vào khung w × h (gốc 0,0): cao `heightFraction`·h theo khung bao tư thế, giữa ngang, đáy cách 7 %.
    static func fitted(_ p: DancerPose, width w: Double, height h: Double) -> [[Double]] {
        let polys = polygons(p)
        var minX = Double.infinity, maxX = -Double.infinity, minY = Double.infinity, maxY = -Double.infinity
        for q in polys {
            for i in stride(from: 0, to: q.count, by: 2) {
                minX = min(minX, q[i]); maxX = max(maxX, q[i]); minY = min(minY, q[i + 1]); maxY = max(maxY, q[i + 1])
            }
        }
        guard maxY > minY, h > 0 else { return [] }
        let k = h * heightFraction / (maxY - minY), cx = (minX + maxX) / 2
        let bottom = h * (1 - (1 - heightFraction) / 2)
        return polys.map { q in
            var o = q
            for i in stride(from: 0, to: q.count, by: 2) {
                o[i] = w / 2 + (q[i] - cx) * k
                o[i + 1] = bottom - (maxY - q[i + 1]) * k
            }
            return o
        }
    }

    /// Tổng toạ độ (test chéo nền tảng).
    static func checksum(_ polys: [[Double]]) -> Double { polys.reduce(0) { $0 + $1.reduce(0, +) } }
}
