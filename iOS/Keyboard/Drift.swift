// Theme "Lạc trôi" (11/2026, Plus): hiệu ứng "Đường hầm" (tunnel) + phím "Lơ lửng" (float).
// Song sinh android/keyboard/.../Drift.kt (CÙNG SỐ, test chung) — vẽ Android ở app/.../ime/DriftPainters.kt.
//
// • Đường hầm: mỗi phím bấm vài VÒNG mảnh (tím neon dịu / lục lam) hiện ở mép bàn phím rồi co về điểm tụ là phím vừa
//   bấm (không có cỡ phím ⇒ tâm bàn phím), co NHANH DẦN như rơi vào đường hầm vô tận. Vòng = viền bàn phím thu nhỏ
//   quanh điểm tụ V (phối cảnh đúng: tâm vòng = V + (C − V)·s). Gõ dồn (mức ComboMeter) ⇒ nhiều vòng hơn + rơi nhanh
//   hơn. Trần `TunnelFx.pool` vòng; vector; animation gắn lúc bắn rồi TỰ GỠ ⇒ nghỉ = 0 animation.
// • Lơ lửng: khi đang gõ, từng phím trôi khỏi hàng + nhấp nhô chậm (lệch ≤ 4 pt, xoay ≤ 2°, chu kỳ 3–5 s, mỗi phím
//   một nhịp riêng); nghỉ gõ 2 s ⇒ về chỗ êm trong 0,8 s rồi DỪNG HẲN (0 animation). CHỈ HÌNH: animation cộng dồn trên
//   layer phím (như Rung combo) — khung phím / vùng nhận chạm không đổi. Giảm chuyển động vẫn trôi.
//   Bật bằng hiệu ứng "float" HOẶC theme có "keyMotion":"float" (ThemeSpec) — FloatPolicy.
import UIKit

// MARK: - Hàm thuần (Android Drift.kt y hệt)

/// "Đường hầm": hình học + nhịp (giây, pt). Android TunnelFx y hệt.
enum TunnelFx {
    /// Trần số vòng đang dựng (pool xoay vòng — gõ dồn thì vòng cũ nhất bị bắn lại).
    static let pool = 16
    /// Số vòng mỗi phím theo mức combo 0…3.
    static let ringsPerLevel = [2, 3, 4, 5]
    /// Thời gian một vòng (mép → điểm tụ) theo mức combo — gõ dồn ⇒ rơi nhanh hơn.
    static let durations = [1.15, 1.05, 0.97, 0.9]
    /// Vòng sau của cùng một phím trễ hơn vòng trước.
    static let stagger = 0.12
    static let lineWidth = 1.2
    static let glowWidth = 4.0
    static let glowAlpha = 0.22
    static let peakAlpha = 0.85
    /// Tỉ lệ thời gian hiện dần / mờ dần ở đầu / cuối.
    static let fadeIn = 0.12
    static let fadeOut = 0.3
    /// Vòng lớn nhất thụt vào trong mép bàn phím (pt).
    static let inset = 2.0
    static let maxCorner = 22.0
    /// Tím neon dịu, lục lam — xen kẽ theo thứ tự vòng.
    static let colors: [UInt32] = [0xB48CFF, 0x5EEAD4]

    static func level(_ l: Int) -> Int { Swift.min(Swift.max(l, 0), 3) }
    static func rings(level l: Int) -> Int { ringsPerLevel[level(l)] }
    static func duration(level l: Int) -> Double { durations[level(l)] }
    static func delay(ring i: Int) -> Double { Double(Swift.max(i, 0)) * stagger }
    /// Tỉ lệ cỡ vòng (1 = mép bàn phím, 0 = điểm tụ) ở tỉ lệ thời gian `u`: 1 − u² — co NHANH DẦN.
    static func scale(_ u: Double) -> Double {
        let k = Swift.min(Swift.max(u, 0), 1)
        return 1 - k * k
    }
    /// Độ đậm ở `u`: hiện dần `fadeIn`, mờ dần `fadeOut` cuối; ngoài [0, 1) ⇒ 0.
    static func alpha(_ u: Double) -> Double {
        guard u >= 0, u < 1 else { return 0 }
        return peakAlpha * Swift.min(1, u / fadeIn, (1 - u) / fadeOut)
    }
    /// Điểm tụ: tâm phím vừa bấm; không có cỡ phím (emit(at:) / phím rỗng) ⇒ tâm bàn phím.
    static func vanish(key: (x: Double, y: Double, w: Double, h: Double)?,
                       bounds b: (x: Double, y: Double, w: Double, h: Double)) -> (x: Double, y: Double) {
        if let k = key, k.w > 0, k.h > 0 { return (k.x + k.w / 2, k.y + k.h / 2) }
        return (b.x + b.w / 2, b.y + b.h / 2)
    }
    /// Tâm vòng ở `u`: V + (C − V)·scale(u) — co đều về điểm tụ như phối cảnh.
    static func center(_ c: (x: Double, y: Double), vanish v: (x: Double, y: Double), _ u: Double) -> (x: Double, y: Double) {
        let s = scale(u)
        return (v.x + (c.x - v.x) * s, v.y + (c.y - v.y) * s)
    }
    /// Bo góc vòng lớn nhất theo cỡ bàn phím.
    static func corner(width w: Double, height h: Double) -> Double { Swift.min(maxCorner, Swift.min(w, h) * 0.12) }
    /// Số mẫu keyframe (iOS) — Android tính thẳng mỗi khung hình.
    static let samples = 12
    static func uiColor(_ rgb: UInt32) -> UIColor {
        UIColor(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}

/// "Lơ lửng": tham số + đường đi của từng phím (giây, pt, radian). Android FloatFx y hệt.
enum FloatFx {
    /// Lệch tâm tối đa (pt) và xoay tối đa (radian, 2°) — chậm + nhỏ cho dịu mắt.
    static let maxOffset = 4.0
    static let maxRotation = 2.0 * Double.pi / 180
    /// Nghỉ gõ bao lâu thì về chỗ; thời gian về chỗ.
    static let idle = 2.0
    static let settle = 0.8

    struct Params: Equatable {
        /// Biên độ (có dấu) x / y (pt), xoay (radian) + chu kỳ (giây) từng trục.
        var ax: Double, ay: Double, rot: Double
        var px: Double, py: Double, pr: Double
    }

    /// Tham số phím thứ `i` (thứ tự phím trong bàn phím) — hạt giống cố định ⇒ mỗi phím một nhịp, không đổi giữa lần.
    /// |(ax, ay)| ≤ √(2.2² + 2.8²) ≈ 3.56 pt (≤ 4); ngang nhỏ hơn dọc vì khe giữa hai phím cạnh nhau hẹp hơn khe hàng
    /// (hai phím kề lệch ngược chiều vẫn không chồng lên nhau); |rot| ≤ 1.6°.
    static func params(_ i: Int) -> Params {
        var st = mix(i &* 131 &+ 17)
        func next() -> Double { st = fxStep(st); return fxValue(st) }
        let a = next(), b = next(), c = next(), d = next(), e = next(), f = next(), g = next()
        let sx: Double = g < 0.5 ? -1 : 1
        let sy: Double = (Int(g * 1000) % 2 == 0) ? 1 : -1
        let sr: Double = (Int(g * 1000) / 2 % 2 == 0) ? -1 : 1
        return Params(ax: sx * (1.4 + 0.8 * a), ay: sy * (1.8 + 1.0 * b),
                      rot: sr * (0.8 + 0.8 * c) * Double.pi / 180,
                      px: 3.2 + 1.6 * d, py: 3.0 + 1.6 * e, pr: 3.6 + 1.4 * f)
    }

    /// Trộn chỉ số phím (murmur3 finalizer) — phím kề nhau ra nhịp KHÁC hẳn nhau (fxSeed tuyến tính ⇒ phím kề giống nhau).
    static func mix(_ i: Int) -> UInt32 {
        var h = UInt32(truncatingIfNeeded: i) &* 0x9E37_79B9
        h ^= h >> 16; h = h &* 0x85EB_CA6B; h ^= h >> 13; h = h &* 0xC2B2_AE35; h ^= h >> 16
        return h
    }

    /// Độ lệch (x, y, xoay) của phím `i` sau `t` giây trôi: sin bắt đầu từ 0 ⇒ rời hàng êm, không giật.
    static func bob(_ i: Int, _ t: Double) -> (x: Double, y: Double, rot: Double) {
        let p = params(i), w = 2 * Double.pi
        return (p.ax * sin(w * t / p.px), p.ay * sin(w * t / p.py), p.rot * sin(w * t / p.pr))
    }
    /// Smoothstep 0…1.
    static func smooth(_ f: Double) -> Double { let k = Swift.min(Swift.max(f, 0), 1); return k * k * (3 - 2 * k) }
    /// Hệ số còn lại khi về chỗ, `dt` giây sau khi bắt đầu về: 1 → 0 (êm cả hai đầu).
    static func settleFactor(_ dt: Double) -> Double { 1 - smooth(dt / settle) }
    /// Số mẫu keyframe một chu kỳ (iOS).
    static let samples = 24
}

/// Đồng hồ "Lơ lửng" (thuần): gõ ⇒ trôi; nghỉ `FloatFx.idle` ⇒ về chỗ `FloatFx.settle` rồi dừng. Gõ lại lúc đang về
/// chỗ ⇒ nhịp trôi mới bắt đầu từ 0 CỘNG với phần về chỗ còn lại (liền mạch — đúng như animation cộng dồn iOS).
/// Android FloatClock y hệt.
struct FloatClock {
    /// Mốc bắt đầu nhịp trôi đang chạy (nil = không trôi).
    private(set) var start: Double?
    private(set) var last = -Double.greatestFiniteMagnitude
    /// Mốc bắt đầu về chỗ (nil = không về chỗ) + tuổi nhịp trôi lúc đóng băng.
    private(set) var settleStart: Double?
    private(set) var frozen = 0.0

    var bobbing: Bool { start != nil }
    var active: Bool { start != nil || settleStart != nil }

    /// Một phím lúc `t` — true khi nhịp trôi VỪA bắt đầu (gắn animation).
    @discardableResult
    mutating func poke(at t: Double) -> Bool {
        last = t
        guard start == nil else { return false }
        start = t
        return true
    }
    /// Cập nhật lúc `t` — true khi VỪA chuyển sang về chỗ.
    @discardableResult
    mutating func update(at t: Double) -> Bool {
        var began = false
        if let s = start, t - last >= FloatFx.idle {
            settleStart = t; frozen = t - s; start = nil; began = true
        }
        if let ss = settleStart, t - ss >= FloatFx.settle { settleStart = nil }
        return began
    }
    /// Độ lệch phím `i` lúc `t` (pt, radian).
    func offset(_ i: Int, at t: Double) -> (x: Double, y: Double, rot: Double) {
        var o = (x: 0.0, y: 0.0, rot: 0.0)
        if let s = start { let b = FloatFx.bob(i, t - s); o = b }
        if let ss = settleStart {
            let k = FloatFx.settleFactor(t - ss), f = FloatFx.bob(i, frozen)
            o.x += f.x * k; o.y += f.y * k; o.rot += f.rot * k
        }
        return o
    }
    mutating func stop() { start = nil; settleStart = nil }
}

/// Cổng chạy "Lơ lửng" (thuần): hiệu ứng thực dùng là `float` HOẶC theme có "keyMotion":"float"; cần Plus, không tiết
/// kiệm pin. Giảm chuyển động KHÔNG tắt (Phil 11/2026: mọi hiệu ứng / hoạt ảnh theme vẫn chạy). Android FloatPolicy y hệt.
enum FloatPolicy {
    static func active(effect: KeyEffect, keyMotion: String?, plus: Bool, lowPower: Bool) -> Bool {
        guard plus, !lowPower else { return false }
        return effect == .float || keyMotion == ThemeExtraIds.floatMotion
    }
}

// MARK: - Đường hầm (iOS: pool vòng trên layer của overlay)

/// Pool vòng "Đường hầm" — KeyEffectOverlay giữ MỘT bản khi kiểu là `tunnel` (kiểu khác ⇒ nil, 0 lớp). Mỗi vòng: gốc ở
/// điểm tụ (bounds rỗng) + hai CAShapeLayer (quầng mờ + nét) hình viền bàn phím đặt ở (C − V); bắn = đặt vị trí + gắn
/// MỘT nhóm animation (scale gốc + độ đậm, lấy mẫu TunnelFx) tự gỡ khi xong. Path dựng lại chỉ khi cỡ bàn phím đổi.
final class TunnelRings {
    private final class Ring {
        let root = CALayer()
        let glow = CAShapeLayer()
        let core = CAShapeLayer()
    }
    private weak var host: CALayer?
    private var rings: [Ring] = []
    private var pool = KeyEffectPool(capacity: TunnelFx.pool)
    private var builtFor: CGSize = .zero
    private var outline: CGPath?
    private var seq = 0
    /// Nhóm animation dựng sẵn theo mức combo (scale + độ đậm) — gắn bản sao mỗi lần bắn.
    private var groups: [CAAnimationGroup] = []
    static let animKey = "fx.tunnel"

    init(host: CALayer) {
        self.host = host
        groups = (0...3).map(Self.makeGroup)
    }

    private static func makeGroup(_ level: Int) -> CAAnimationGroup {
        let n = TunnelFx.samples
        let us = (0...n).map { Double($0) / Double(n) }
        let scale = CAKeyframeAnimation(keyPath: "transform.scale")
        scale.values = us.map { max(TunnelFx.scale($0), 0.001) }
        scale.keyTimes = us.map { NSNumber(value: $0) }
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        // Mẫu dày ở đầu (hiện dần) + cuối (mờ dần) đúng TunnelFx.alpha.
        let fu = [0, TunnelFx.fadeIn, 1 - TunnelFx.fadeOut, 0.85, 0.999]
        fade.values = fu.map { TunnelFx.alpha($0) }
        fade.keyTimes = fu.map { NSNumber(value: $0) }
        let g = CAAnimationGroup()
        g.animations = [scale, fade]
        g.duration = TunnelFx.duration(level: level)
        scale.duration = g.duration; fade.duration = g.duration
        g.fillMode = .backwards           // trễ (vòng sau) ⇒ đứng ở mép, vô hình
        g.isRemovedOnCompletion = true    // xong ⇒ gỡ: nghỉ gõ = 0 animation
        return g
    }

    /// Bắn: `r` = khung phím (toạ độ overlay), `b` = bounds overlay (gốc có thể dời — #151), `level` = mức combo,
    /// `media` = CACurrentMediaTime().
    func fire(key r: CGRect, bounds b: CGRect, level: Int, media: CFTimeInterval) {
        guard let host, b.width > 1, b.height > 1 else { return }
        if b.size != builtFor { rebuildOutline(b.size) }
        let v = TunnelFx.vanish(key: (Double(r.minX), Double(r.minY), Double(r.width), Double(r.height)),
                                bounds: (Double(b.minX), Double(b.minY), Double(b.width), Double(b.height)))
        let vp = CGPoint(x: v.x, y: v.y)
        let rel = CGPoint(x: b.midX - vp.x, y: b.midY - vp.y)
        let lv = TunnelFx.level(level)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for i in 0..<TunnelFx.rings(level: lv) {
            let slot = pool.next()
            let ring: Ring
            if slot < rings.count { ring = rings[slot] } else { ring = makeRing(host); rings.append(ring) }
            seq += 1
            let col = TunnelFx.uiColor(TunnelFx.colors[seq % TunnelFx.colors.count])
            ring.core.strokeColor = col.cgColor
            ring.glow.strokeColor = col.withAlphaComponent(CGFloat(TunnelFx.glowAlpha)).cgColor
            ring.root.position = vp
            ring.core.position = rel
            ring.glow.position = rel
            ring.root.removeAnimation(forKey: Self.animKey)
            let g = groups[lv]
            g.beginTime = ring.root.convertTime(media, from: nil) + TunnelFx.delay(ring: i)
            ring.root.add(g, forKey: Self.animKey)
            ring.root.isHidden = false
        }
        CATransaction.commit()
    }

    private func makeRing(_ host: CALayer) -> Ring {
        let r = Ring()
        r.root.bounds = .zero
        r.root.opacity = 0            // model vô hình — chỉ animation làm hiện
        r.root.isHidden = true
        for (l, w) in [(r.glow, TunnelFx.glowWidth), (r.core, TunnelFx.lineWidth)] {
            l.fillColor = nil
            l.lineWidth = CGFloat(w)
            l.path = outline
            l.bounds = .zero
            r.root.addSublayer(l)
        }
        host.addSublayer(r.root)
        return r
    }

    private func rebuildOutline(_ s: CGSize) {
        builtFor = s
        let w = Double(s.width) - 2 * TunnelFx.inset, h = Double(s.height) - 2 * TunnelFx.inset
        let c = TunnelFx.corner(width: w, height: h)
        outline = CGPath(roundedRect: CGRect(x: -w / 2, y: -h / 2, width: w, height: h),
                         cornerWidth: CGFloat(c), cornerHeight: CGFloat(c), transform: nil)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for r in rings { r.glow.path = outline; r.core.path = outline }
        CATransaction.commit()
    }

    /// Ẩn bàn phím / đổi kiểu: gỡ mọi animation (0 lớp chạy).
    func halt() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for r in rings { r.root.removeAnimation(forKey: Self.animKey); r.root.isHidden = true }
        CATransaction.commit()
    }
    func remove() {
        halt()
        for r in rings { r.root.removeFromSuperlayer() }
        rings.removeAll()
    }

    #if DEBUG
    var debugRoots: [CALayer] { rings.map(\.root) }
    var debugCores: [CAShapeLayer] { rings.map(\.core) }
    var debugAnimationCount: Int { rings.reduce(0) { $0 + ($1.root.animationKeys()?.count ?? 0) } }
    #endif
}

// MARK: - Lơ lửng (iOS: animation cộng dồn trên layer từng phím)

/// "Lơ lửng" — KeyboardView giữ MỘT bản khi FloatPolicy cho phép (khác ⇒ nil, đường phím chỉ đọc optional). Gõ: nhịp
/// trôi VỪA bắt đầu ⇒ mỗi phím gắn 3 animation lặp (x / y / xoay, cộng dồn — model + khung nhận chạm KHÔNG đổi), lấy mẫu
/// FloatFx một chu kỳ; render server chạy tiếp, không timer / display link. Nghỉ: MỘT asyncAfter kiểm nghỉ ⇒ gỡ nhịp trôi,
/// gắn animation về chỗ (lấy mẫu FloatClock) tự gỡ khi xong ⇒ 0 animation.
final class KeyFloat {
    private weak var target: UIView?
    private(set) var clock = FloatClock()
    private var idleScheduled = false
    /// Đồng hồ (giây) — test thay.
    var now: () -> CFTimeInterval = { CACurrentMediaTime() }
    static let bobKeys = ["fx.float.x", "fx.float.y", "fx.float.r"]
    static let settleKey = "fx.float.settle"
    /// Lọc view phím: KeyboardView đặt (KeyButton) — test có thể thay.
    private let isKey: (UIView) -> Bool

    init(target: UIView, isKey: @escaping (UIView) -> Bool) {
        self.target = target
        self.isKey = isKey
    }

    /// Các view phím đang hiện, theo thứ tự (chỉ số = tham số FloatFx của phím).
    func keyViews() -> [UIView] {
        var out: [UIView] = []
        func walk(_ v: UIView) {
            if isKey(v) { if !v.isHidden { out.append(v) } } else { v.subviews.forEach(walk) }
        }
        if let target { walk(target) }
        return out
    }

    /// Một phím vừa bấm (sau khi chữ đã chèn).
    func poke() {
        let t = now()
        let began = clock.poke(at: t)
        guard let start = clock.start else { return }
        // Phím mới hiện giữa chừng (đổi bảng chữ / số) cũng trôi theo cùng nhịp; phím đang trôi giữ nguyên.
        for (i, v) in keyViews().enumerated() where began || v.layer.animation(forKey: Self.bobKeys[0]) == nil {
            attachBob(v.layer, index: i, start: start)
        }
        scheduleIdle()
    }

    private func attachBob(_ l: CALayer, index i: Int, start: CFTimeInterval) {
        let p = FloatFx.params(i)
        let n = FloatFx.samples
        func anim(_ path: String, _ amp: Double, _ period: Double) -> CAKeyframeAnimation {
            let a = CAKeyframeAnimation(keyPath: path)
            a.isAdditive = true
            a.values = (0...n).map { amp * sin(2 * Double.pi * Double($0) / Double(n)) }
            a.keyTimes = (0...n).map { NSNumber(value: Double($0) / Double(n)) }
            a.calculationMode = .cubic
            a.duration = period
            a.repeatCount = .infinity
            a.beginTime = l.convertTime(start, from: nil)
            a.isRemovedOnCompletion = false
            return a
        }
        l.add(anim("position.x", p.ax, p.px), forKey: Self.bobKeys[0])
        l.add(anim("position.y", p.ay, p.py), forKey: Self.bobKeys[1])
        l.add(anim("transform.rotation.z", p.rot, p.pr), forKey: Self.bobKeys[2])
    }

    private func scheduleIdle() {
        guard !idleScheduled else { return }
        idleScheduled = true
        let wait = Swift.max(0.05, FloatFx.idle - (now() - clock.last))
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in self?.idleCheck() }
    }

    /// Kiểm nghỉ (asyncAfter; test gọi thẳng sau khi đổi `now`).
    func idleCheck() {
        idleScheduled = false
        let t = now()
        if clock.update(at: t) { settle(at: t) } else if clock.bobbing { scheduleIdle() }
    }

    private func settle(at t: CFTimeInterval) {
        let n = 8
        for (i, v) in keyViews().enumerated() {
            let l = v.layer
            guard l.animation(forKey: Self.bobKeys[0]) != nil else { continue }
            for k in Self.bobKeys { l.removeAnimation(forKey: k) }
            let f = FloatFx.bob(i, clock.frozen)
            let ks = (0...n).map { Double($0) / Double(n) }
            func anim(_ path: String, _ v0: Double) -> CAKeyframeAnimation {
                let a = CAKeyframeAnimation(keyPath: path)
                a.isAdditive = true
                a.values = ks.map { v0 * FloatFx.settleFactor($0 * FloatFx.settle) }
                a.keyTimes = ks.map { NSNumber(value: $0) }
                return a
            }
            let g = CAAnimationGroup()
            g.animations = [anim("position.x", f.x), anim("position.y", f.y), anim("transform.rotation.z", f.rot)]
            g.duration = FloatFx.settle
            g.animations?.forEach { $0.duration = FloatFx.settle }
            g.beginTime = l.convertTime(t, from: nil)
            g.isRemovedOnCompletion = true
            l.add(g, forKey: Self.settleKey)
        }
    }

    /// Ẩn bàn phím / tắt: gỡ sạch (phím về đúng chỗ ngay).
    func halt() {
        clock.stop()
        for v in keyViews() {
            for k in Self.bobKeys { v.layer.removeAnimation(forKey: k) }
            v.layer.removeAnimation(forKey: Self.settleKey)
        }
    }

    #if DEBUG
    /// Tổng animation "Lơ lửng" còn gắn trên các phím.
    var debugAnimationCount: Int {
        keyViews().reduce(0) { n, v in
            n + (Self.bobKeys + [Self.settleKey]).filter { v.layer.animation(forKey: $0) != nil }.count
        }
    }
    var debugIdleScheduled: Bool { idleScheduled }
    #endif
}
