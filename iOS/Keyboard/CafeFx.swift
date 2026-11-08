// Theme "Cà phê sữa đá" (11/2026, Plus): hiệu ứng "Đá lanh canh" (id ice) + cảnh ly cà phê (motif "cafe" — ThemeScene).
// Hàm thuần song sinh android/keyboard/.../CafeFx.kt — CÙNG SỐ (test chéo hai nền tảng).
//
//  • Bấm phím ⇒ "viên đá" (khung kính sáng ôm phím) lắc lư tắt dần + một giọt nước đọng trượt xuống từ góc dưới phím.
//  • Phin nhỏ (vector) ở góc trái thanh gợi ý: mỗi 4 phím nhỏ một giọt cà phê xuống ly. Phin tĩnh (0 hoạt ảnh khi nghỉ).
//  • Gõ nhanh (ComboMeter lên mức 2) ⇒ một vòng sữa xoáy vào cà phê ở đáy (hồi 2,5 s).
import UIKit

enum CafeFx {
    // Viên đá lắc
    static let jiggleAmp = 0.09, jiggleTau = 0.12, jiggleFreq = 7.0, jiggleDuration = 0.4
    static let cubeInset = 1.0, cubeCorner = 6.0
    static let pool = 6
    /// Góc lắc (radian) `t` giây sau khi bấm: dao động tắt dần, 0 sau jiggleDuration.
    static func jiggle(_ t: Double) -> Double {
        guard t > 0, t < jiggleDuration else { return 0 }
        return jiggleAmp * exp(-t / jiggleTau) * sin(2 * Double.pi * jiggleFreq * t)
    }
    static func cubeAlpha(_ t: Double) -> Double {
        if t <= 0 || t >= jiggleDuration { return 0 }
        return 0.9 * (1 - t / jiggleDuration)
    }

    // Giọt nước đọng
    static let dropletRadius = 2.2, dropletSlide = 12.0, dropletDuration = 0.6
    static func dropletOrigin(keyMaxX: Double, keyMaxY: Double) -> (x: Double, y: Double) { (keyMaxX - 6, keyMaxY - 3) }
    /// (lệch y, độ đậm) — trượt nhanh dần, mờ dần.
    static func droplet(_ t: Double) -> (dy: Double, alpha: Double) {
        let u = min(max(t / dropletDuration, 0), 1)
        return (dropletSlide * u * u, t <= 0 || t >= dropletDuration ? 0 : 0.9 * (1 - u))
    }

    // Phin + giọt cà phê
    static let dripEvery = 4
    static let phinWidth = 16.0, phinHeight = 10.0, cupWidth = 14.0, cupHeight = 10.0, cupGap = 9.0
    static let dropFall = 8.0, dropDuration = 0.3, dropRadius = 1.6
    /// Góc phin (trên-trái của phin) — góc trái thanh gợi ý.
    static func phinOrigin(minX: Double, top: Double) -> (x: Double, y: Double) { (minX + 8, top + 3) }
    /// Toàn khung phin + ly (để kiểm trong khung).
    static func phinBox(minX: Double, top: Double) -> (x: Double, y: Double, w: Double, h: Double) {
        let o = phinOrigin(minX: minX, top: top)
        return (o.x, o.y, phinWidth, phinHeight + cupGap + cupHeight)
    }
    /// Giọt rơi `t` giây: lệch y (rơi nhanh dần) — 0…dropFall.
    static func dropY(_ t: Double) -> Double {
        let u = min(max(t / dropDuration, 0), 1)
        return dropFall * u * u
    }
    struct DripCounter {
        private(set) var n = 0
        /// Một phím — true khi tới lượt nhỏ giọt (mỗi `dripEvery` phím).
        mutating func press() -> Bool {
            n += 1
            if n >= CafeFx.dripEvery { n = 0; return true }
            return false
        }
        mutating func reset() { n = 0 }
    }

    // Sữa xoáy
    static let swirlLevel = 2, swirlCooldown = 2.5, swirlDuration = 1.2, swirlDraw = 0.6
    static let swirlRadius = 22.0, swirlTurns = 1.75, swirlPoints = 40, swirlLift = 28.0, swirlWidth = 2.5
    static let milk: UInt32 = 0xF3E5CC
    struct SwirlGate {
        private(set) var last = -Double.greatestFiniteMagnitude
        /// Mức combo VỪA lên tới swirlLevel và đã hồi ≥ swirlCooldown.
        mutating func shouldSwirl(level: Int, previous: Int, now: Double) -> Bool {
            guard level >= CafeFx.swirlLevel, previous < CafeFx.swirlLevel, now - last >= CafeFx.swirlCooldown else { return false }
            last = now
            return true
        }
    }
    static func swirlCenter(midX: Double, bottom: Double) -> (x: Double, y: Double) { (midX, bottom - swirlLift) }
    /// Xoắn ốc Archimedes r = a·θ quanh tâm (0, 0), θ 0 … turns·2π, bán kính cuối = swirlRadius.
    static func spiral() -> [(Double, Double)] {
        let tMax = swirlTurns * 2 * Double.pi, a = swirlRadius / tMax
        return (0...swirlPoints).map { i in
            let th = tMax * Double(i) / Double(swirlPoints)
            return (a * th * cos(th), a * th * sin(th))
        }
    }
    static func swirlAlpha(_ t: Double) -> Double {
        if t <= 0 || t >= swirlDuration { return 0 }
        if t > swirlDuration - 0.4 { return 0.85 * (swirlDuration - t) / 0.4 }
        return 0.85
    }
}

// MARK: - Cảnh ly cà phê (motif "cafe")

/// Nền: gradient cà phê → sữa (ThemeScene.gradient) + vài giọt nước đọng li ti (màu deco).
enum CafeScene {
    static let dotCount = 24
    static func dots(width w: Double, height h: Double) -> [(x: Double, y: Double, r: Double)] {
        (0..<dotCount).map { i in
            let a = fxStep(fxSeed(i &* 211 &+ 3)), b = fxStep(a), c = fxStep(b)
            return (4 + (w - 8) * fxValue(a), 4 + (h - 8) * fxValue(b), 1 + 1.2 * fxValue(c))
        }
    }
}

// MARK: - Bộ vẽ

@MainActor final class IceRenderer: ThemeFxRenderer {
    private weak var host: UIView?
    var onEvent: (() -> Void)?
    private var cubes: [CAShapeLayer] = []
    private var drops: [CAShapeLayer] = []
    private var cubePool = KeyEffectPool(capacity: CafeFx.pool)
    private var cubeAnim: CAAnimationGroup?
    private var dropAnim: CAAnimationGroup?
    private var phin: CALayer?
    private var coffeeDrop: CAShapeLayer?
    private var phinBuiltFor: CGRect = .null
    private var drip = CafeFx.DripCounter()
    private var combo = ComboMeter()
    private var level = 0
    private var swirlGate = CafeFx.SwirlGate()
    private var swirl: CAShapeLayer?

    init(host: UIView) { self.host = host }

    func layout() { buildPhin() }

    func fire(_ r: CGRect, isReturn: Bool, now: CFTimeInterval, media: CFTimeInterval) {
        guard let host else { return }
        buildPhin()
        let slot = cubePool.next()
        let c: CAShapeLayer, d: CAShapeLayer
        if slot < cubes.count { c = cubes[slot]; d = drops[slot] } else {
            c = makeCube(); d = makeDrop()
            cubes.append(c); drops.append(d)
            host.layer.addSublayer(c); host.layer.addSublayer(d)
        }
        // Chỉ có điểm (emit(at:)) ⇒ phím cỡ mặc định quanh điểm.
        let d0 = KeyEffectOverlay.defaultKeySize
        let kr = r.width >= 4 && r.height >= 4 ? r
            : CGRect(x: r.midX - d0.width / 2, y: r.midY - d0.height / 2, width: d0.width, height: d0.height)
        let box = kr.insetBy(dx: CGFloat(CafeFx.cubeInset), dy: CGFloat(CafeFx.cubeInset))
        if c.bounds.size != box.size {
            c.bounds = CGRect(origin: .zero, size: box.size)
            let rr = max(0, min(CGFloat(CafeFx.cubeCorner), box.width / 2, box.height / 2))   // CGPath đòi bo ≤ nửa cạnh
            c.path = CGPath(roundedRect: c.bounds, cornerWidth: rr, cornerHeight: rr, transform: nil)
        }
        c.position = CGPoint(x: box.midX, y: box.midY)
        let g = cubeAnimation(); g.beginTime = now
        c.removeAnimation(forKey: "fx"); c.add(g, forKey: "fx")
        let o = CafeFx.dropletOrigin(keyMaxX: Double(kr.maxX), keyMaxY: Double(kr.maxY))
        d.position = CGPoint(x: o.x, y: o.y)
        let dg = dropAnimation(); dg.beginTime = now
        d.removeAnimation(forKey: "fx"); d.add(dg, forKey: "fx")
        if drip.press() { fireDrip(now: now) }
        let prev = level
        level = combo.press(at: media)
        if swirlGate.shouldSwirl(level: level, previous: prev, now: media) { fireSwirl(now: now) }
    }

    func fireQueued(now: CFTimeInterval, media: CFTimeInterval) {}

    func halt() {
        for l in cubes + drops { l.removeAllAnimations() }
        coffeeDrop?.removeAllAnimations()
        swirl?.removeAllAnimations()
        combo.reset(); level = 0
    }

    func detach() {
        halt()
        for l in cubes + drops { l.removeFromSuperlayer() }
        cubes.removeAll(); drops.removeAll()
        phin?.removeFromSuperlayer(); phin = nil; coffeeDrop = nil; phinBuiltFor = .null
        swirl?.removeFromSuperlayer(); swirl = nil
    }

    private func keyframes(_ path: String, _ values: [Double], duration: Double) -> CAKeyframeAnimation {
        let a = CAKeyframeAnimation(keyPath: path)
        a.values = values.map { NSNumber(value: $0) }
        a.duration = duration
        return a
    }
    private func group(_ parts: [CAAnimation], duration: Double) -> CAAnimationGroup {
        let g = CAAnimationGroup()
        g.animations = parts; g.duration = duration
        g.fillMode = .backwards; g.isRemovedOnCompletion = true
        return g
    }

    private func cubeAnimation() -> CAAnimationGroup {
        if let a = cubeAnim { return a }
        let n = 16, d = CafeFx.jiggleDuration
        let rot = keyframes("transform.rotation.z", (0...n).map { CafeFx.jiggle(d * Double($0) / Double(n)) }, duration: d)
        let al = keyframes("opacity", (0...n).map { CafeFx.cubeAlpha(d * Double($0) / Double(n)) }, duration: d)
        let g = group([rot, al], duration: d); cubeAnim = g
        return g
    }

    private func dropAnimation() -> CAAnimationGroup {
        if let a = dropAnim { return a }
        let n = 12, d = CafeFx.dropletDuration
        let ty = keyframes("transform.translation.y", (0...n).map { CafeFx.droplet(d * Double($0) / Double(n)).dy }, duration: d)
        let al = keyframes("opacity", (0...n).map { CafeFx.droplet(d * Double($0) / Double(n)).alpha }, duration: d)
        let g = group([ty, al], duration: d); dropAnim = g
        return g
    }

    private func makeCube() -> CAShapeLayer {
        let l = CAShapeLayer()
        l.fillColor = UIColor(white: 1, alpha: 0.18).cgColor
        l.strokeColor = UIColor(white: 1, alpha: 0.75).cgColor
        l.lineWidth = 1.2
        l.opacity = 0
        let glint = CAShapeLayer()       // vệt sáng chéo góc trên-trái
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 4, y: 9)); p.addLine(to: CGPoint(x: 9, y: 4))
        glint.path = p
        glint.strokeColor = UIColor(white: 1, alpha: 0.9).cgColor
        glint.lineWidth = 1.4
        glint.lineCap = .round
        l.addSublayer(glint)
        return l
    }

    private func makeDrop() -> CAShapeLayer {
        let l = CAShapeLayer()
        let r = CGFloat(CafeFx.dropletRadius)
        let p = CGMutablePath()   // giọt: đầu nhọn trên, đáy tròn
        p.move(to: CGPoint(x: 0, y: -r * 2))
        p.addQuadCurve(to: CGPoint(x: r, y: 0), control: CGPoint(x: r * 0.9, y: -r))
        p.addArc(center: .zero, radius: r, startAngle: 0, endAngle: .pi, clockwise: false)
        p.addQuadCurve(to: CGPoint(x: 0, y: -r * 2), control: CGPoint(x: -r * 0.9, y: -r))
        l.path = p
        l.fillColor = UIColor(white: 1, alpha: 0.8).cgColor
        l.strokeColor = UIColor(white: 1, alpha: 0.95).cgColor
        l.lineWidth = 0.5
        l.opacity = 0
        return l
    }

    /// Phin (nắp + thân thép + đế) trên ly thuỷ tinh có cà phê — vẽ một lần mỗi cỡ, tĩnh.
    private func buildPhin() {
        guard let host, host.bounds.width > 0 else { return }
        let b = host.bounds
        guard phin == nil || phinBuiltFor != b else { return }
        phin?.removeFromSuperlayer()
        let o = CafeFx.phinOrigin(minX: Double(b.minX), top: Double(b.minY))
        let root = CALayer()
        root.frame = CGRect(x: o.x, y: o.y, width: CafeFx.phinWidth, height: CafeFx.phinHeight + CafeFx.cupGap + CafeFx.cupHeight)
        let steel = UIColor(white: 0.74, alpha: 0.95).cgColor
        let body = CAShapeLayer()
        let p = CGMutablePath()
        let w = CafeFx.phinWidth, h = CafeFx.phinHeight
        p.addRect(CGRect(x: 3, y: 0, width: w - 6, height: 2))                 // nắp
        p.move(to: CGPoint(x: 2, y: 2.5)); p.addLine(to: CGPoint(x: w - 2, y: 2.5))   // thân thuôn
        p.addLine(to: CGPoint(x: w - 4, y: h - 2)); p.addLine(to: CGPoint(x: 4, y: h - 2)); p.closeSubpath()
        p.addRect(CGRect(x: 0, y: h - 1.5, width: w, height: 1.5))             // đế
        body.path = p
        body.fillColor = steel
        let cup = CAShapeLayer()
        let cx = (w - CafeFx.cupWidth) / 2, cy = h + CafeFx.cupGap
        cup.path = CGPath(roundedRect: CGRect(x: cx, y: cy, width: CafeFx.cupWidth, height: CafeFx.cupHeight),
                          cornerWidth: 2, cornerHeight: 2, transform: nil)
        cup.fillColor = UIColor(white: 1, alpha: 0.22).cgColor
        cup.strokeColor = UIColor(white: 1, alpha: 0.7).cgColor
        cup.lineWidth = 0.8
        let coffee = CAShapeLayer()
        coffee.path = CGPath(rect: CGRect(x: cx + 1, y: cy + CafeFx.cupHeight * 0.45, width: CafeFx.cupWidth - 2,
                                          height: CafeFx.cupHeight * 0.55 - 1), transform: nil)
        coffee.fillColor = UIColor(fx: 0x3B2416, alpha: 0.95).cgColor
        let drop = CAShapeLayer()
        let r = CafeFx.dropRadius
        drop.path = CGPath(ellipseIn: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r), transform: nil)
        drop.fillColor = UIColor(fx: 0x3B2416).cgColor
        drop.position = CGPoint(x: w / 2, y: h)
        drop.opacity = 0
        for l in [cup, coffee, body, drop] { root.addSublayer(l) }
        host.layer.addSublayer(root)
        phin = root
        coffeeDrop = drop
        phinBuiltFor = b
    }

    private func fireDrip(now: CFTimeInterval) {
        guard let d = coffeeDrop else { return }
        let n = 8, dur = CafeFx.dropDuration
        let ty = keyframes("transform.translation.y", (0...n).map { CafeFx.dropY(dur * Double($0) / Double(n)) }, duration: dur)
        let al = keyframes("opacity", [1, 1, 0], duration: dur)
        let g = group([ty, al], duration: dur); g.beginTime = now
        d.removeAnimation(forKey: "fx"); d.add(g, forKey: "fx")
    }

    private func fireSwirl(now: CFTimeInterval) {
        guard let host, host.bounds.width > 0 else { return }
        let l: CAShapeLayer
        if let s = swirl { l = s } else {
            l = CAShapeLayer()
            let p = CGMutablePath()
            for (i, q) in CafeFx.spiral().enumerated() {
                if i == 0 { p.move(to: CGPoint(x: q.0, y: q.1)) } else { p.addLine(to: CGPoint(x: q.0, y: q.1)) }
            }
            l.path = p
            l.fillColor = nil
            l.strokeColor = UIColor(fx: CafeFx.milk).cgColor
            l.lineWidth = CGFloat(CafeFx.swirlWidth)
            l.lineCap = .round
            l.opacity = 0
            host.layer.addSublayer(l)
            swirl = l
        }
        let b = host.bounds
        let c = CafeFx.swirlCenter(midX: Double(b.midX), bottom: Double(b.maxY))
        l.position = CGPoint(x: c.x, y: c.y)
        let d = CafeFx.swirlDuration
        let draw = CABasicAnimation(keyPath: "strokeEnd")
        draw.fromValue = 0; draw.toValue = 1; draw.duration = CafeFx.swirlDraw
        draw.fillMode = .forwards
        let rot = CABasicAnimation(keyPath: "transform.rotation.z")
        rot.fromValue = 0; rot.toValue = Double.pi; rot.duration = d
        let n = 12
        let al = keyframes("opacity", (0...n).map { CafeFx.swirlAlpha(d * Double($0) / Double(n)) }, duration: d)
        let g = group([draw, rot, al], duration: d); g.beginTime = now
        l.removeAnimation(forKey: "fx"); l.add(g, forKey: "fx")
    }

    #if DEBUG
    var debugCubes: [CAShapeLayer] { cubes }
    var debugPhin: CALayer? { phin }
    var debugSwirl: CAShapeLayer? { swirl }
    var debugCoffeeDropAnimating: Bool { coffeeDrop?.animation(forKey: "fx") != nil }
    #endif
}
