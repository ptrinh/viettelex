// Theme "Bể cá" (11/2026, Plus): hiệu ứng "Cho cá ăn" (id fishfeed) + cảnh bể (motif "aquarium" — ThemeScene).
// Hàm thuần song sinh android/keyboard/.../AquariumFx.kt — CÙNG SỐ (test chéo hai nền tảng).
//
//  • 3…6 chú cá vector bơi chậm SAU hàng phím (dải dưới phím). Mỗi phím bấm thả một viên thức ăn tại phím, viên chìm dần
//    xuống cát; chú cá RẢNH gần nhất (hết rảnh ⇒ gần nhất) lái tới ăn (lái đơn giản: vận tốc mong muốn − vận tốc, kẹp lực).
//  • Tổng số viên đã ăn (bộ đếm theo máy, App Group "aquariumFood") ⇒ cá lớn dần chút (trần +30 %); mỗi 500 viên thêm một
//    chú (trần 6). Ghi tối đa mỗi 5 s + lúc ẩn bàn phím (PersistGate).
//  • Nhịp mô phỏng 30 khung/giây CHỈ khi đang gõ; nghỉ 3 s ⇒ dừng hẳn (CADisplayLink tạm dừng — 0 chi phí khi nghỉ), cá
//    đứng yên tại chỗ. Mảng cố định (≤ 6 cá, ≤ 8 viên) ⇒ không cấp phát mỗi khung.
import UIKit

enum AquariumFx {
    static let baseFish = 3, maxFish = 6, pelletsPerFish = 500
    static let growthCap = 1500.0, growthMax = 0.3
    static let fishLength = 20.0, fishHeight = 10.0
    /// Tốc độ tối đa khi đi ăn / khi lượn (pt/s), lực lái tối đa (pt/s²), bán kính chậm lại khi tới đích.
    static let maxSpeed = 46.0, wanderSpeed = 14.0, maxForce = 90.0, arriveRadius = 24.0
    static let eatRadius = 7.0
    static let sinkSpeed = 22.0, pelletRadius = 2.0, pelletLife = 6.0, maxPellets = 8, pelletSway = 1.5
    static let idleAfter = 3.0
    static let persistInterval = 5.0
    static let tick = 1.0 / 30
    static let sandHeight = 10.0
    static let margin = 12.0
    static let waypointReach = 6.0
    static let storageKey = "aquariumFood"
    /// Tỉ lệ cỡ riêng từng chú (thứ tự xuất hiện) + màu.
    static let sizeFactors: [Double] = [1.0, 0.85, 1.1, 0.9, 1.05, 0.95]
    static let colors: [UInt32] = [0xFF8C42, 0xFFD23F, 0x4FC3F7, 0xF06292, 0x9CCC65, 0xFFF3E0]
    static let pelletColor: UInt32 = 0xC8843A

    static func fishCount(eaten: Int) -> Int { min(maxFish, baseFish + max(eaten, 0) / pelletsPerFish) }
    static func growth(eaten: Int) -> Double { 1 + growthMax * min(Double(max(eaten, 0)), growthCap) / growthCap }

    struct Region: Equatable { var minX: Double, minY: Double, maxX: Double, maxY: Double }
    /// Vùng bơi: dưới 1/4 trên (thanh gợi ý), trên lớp cát, chừa lề.
    static func region(minX: Double, top: Double, width: Double, height: Double) -> Region {
        Region(minX: minX + margin, minY: top + height * 0.25, maxX: minX + width - margin,
               maxY: max(top + height * 0.25 + 1, top + height - sandHeight - 6))
    }
    /// Đáy viên thức ăn chìm tới = đáy vùng bơi (ngay trên cát — cá luôn với tới).
    static func floorY(_ r: Region) -> Double { r.maxY }

    struct Fish: Equatable {
        var x: Double, y: Double, vx = 0.0, vy = 0.0
        var target = -1           // chỉ số viên đang tới ăn (−1 = rảnh)
        var wx: Double, wy: Double
        var seed: Int
        var hop = 0               // số điểm lượn đã qua
    }
    struct Pellet: Equatable {
        var x0 = 0.0, x = 0.0, y = 0.0, age = 0.0, alive = false
    }

    /// Điểm lượn thứ `k` của cá `seed` trong vùng (tất định).
    static func waypoint(seed: Int, k: Int, region r: Region) -> (x: Double, y: Double) {
        let s = fxStep(fxStep(fxSeed(seed &* 977 &+ k &* 131 &+ 17)))
        let t = fxStep(fxStep(s))
        return (r.minX + (r.maxX - r.minX) * fxValue(s), r.minY + (r.maxY - r.minY) * fxValue(t))
    }

    /// Một bước lái tới (tx, ty): vận tốc mong muốn (chậm dần trong arriveRadius nếu `arrive`) − vận tốc, kẹp lực
    /// maxForce·dt, kẹp tốc độ `limit`, dời vị trí, kẹp trong vùng.
    static func steer(_ f: Fish, toward tx: Double, _ ty: Double, dt: Double, limit: Double, arrive: Bool, region r: Region) -> Fish {
        var o = f
        let dx = tx - f.x, dy = ty - f.y, d = hypot(dx, dy)
        let speed = arrive && d < arriveRadius ? limit * max(d / arriveRadius, 0.25) : limit
        let ex = d > 1e-6 ? dx / d * speed : 0, ey = d > 1e-6 ? dy / d * speed : 0
        var ax = ex - f.vx, ay = ey - f.vy
        let a = hypot(ax, ay), amax = maxForce * dt
        if a > amax { ax *= amax / a; ay *= amax / a }
        o.vx += ax; o.vy += ay
        let v = hypot(o.vx, o.vy)
        if v > limit { o.vx *= limit / v; o.vy *= limit / v }
        o.x = min(max(o.x + o.vx * dt, r.minX), r.maxX)
        o.y = min(max(o.y + o.vy * dt, r.minY), r.maxY)
        return o
    }

    /// Chú cá đi ăn viên ở (px, py): cá rảnh gần nhất; không ai rảnh ⇒ gần nhất. Rỗng ⇒ −1.
    static func nearestFish(_ fish: [Fish], count: Int, px: Double, py: Double) -> Int {
        var best = -1, bestD = Double.infinity, bestFree = -1, bestFreeD = Double.infinity
        for i in 0..<min(count, fish.count) {
            let d = hypot(fish[i].x - px, fish[i].y - py)
            if d < bestD { bestD = d; best = i }
            if fish[i].target < 0, d < bestFreeD { bestFreeD = d; bestFree = i }
        }
        return bestFree >= 0 ? bestFree : best
    }

    /// Viên thức ăn sau `dt`: chìm tới `floor`, lắc ngang nhẹ, già đi; quá `pelletLife` ⇒ tan.
    static func sink(_ p: Pellet, dt: Double, floor: Double) -> Pellet {
        var o = p
        guard p.alive else { return o }
        o.age += dt
        o.y = min(p.y + sinkSpeed * dt, floor)
        o.x = p.x0 + pelletSway * sin(2 * Double.pi * 0.8 * o.age)
        if o.age >= pelletLife { o.alive = false }
        return o
    }

    static func eats(_ f: Fish, _ p: Pellet, scale: Double) -> Bool { p.alive && hypot(f.x - p.x, f.y - p.y) <= eatRadius * scale }

    /// Ghi bộ đếm: tối đa mỗi `persistInterval` giây khi có thay đổi; `flush` (ẩn bàn phím) ghi ngay nếu còn bẩn.
    struct PersistGate {
        private(set) var lastSave = -Double.greatestFiniteMagnitude
        private(set) var dirty = false
        mutating func note() { dirty = true }
        mutating func shouldSave(now: Double) -> Bool {
            guard dirty, now - lastSave >= AquariumFx.persistInterval else { return false }
            lastSave = now; dirty = false
            return true
        }
        mutating func flush(now: Double) -> Bool {
            guard dirty else { return false }
            lastSave = now; dirty = false
            return true
        }
    }

    /// Thế giới bể cá (thuần, mảng cố định). `eaten` = tổng đã ăn (cả từ lần trước, nạp từ bộ nhớ).
    struct World {
        private(set) var fish: [Fish] = []
        private(set) var pellets = [Pellet](repeating: Pellet(), count: AquariumFx.maxPellets)
        private(set) var eaten: Int
        private(set) var region: Region
        private(set) var floor: Double
        private var cursor = 0

        init(eaten: Int, minX: Double, top: Double, width: Double, height: Double) {
            self.eaten = max(eaten, 0)
            region = AquariumFx.region(minX: minX, top: top, width: width, height: height)
            floor = AquariumFx.floorY(region)
            fish.reserveCapacity(AquariumFx.maxFish)
            ensureFish()
        }

        var count: Int { fish.count }
        var scale: Double { AquariumFx.growth(eaten: eaten) }
        func scale(of i: Int) -> Double { scale * AquariumFx.sizeFactors[i % AquariumFx.sizeFactors.count] }

        /// Thêm cá tới đủ fishCount(eaten): chú mới xuất phát ở điểm lượn 0 của mình.
        mutating func ensureFish() {
            while fish.count < AquariumFx.fishCount(eaten: eaten) {
                let i = fish.count
                let p = AquariumFx.waypoint(seed: i, k: 0, region: region)
                let w = AquariumFx.waypoint(seed: i, k: 1, region: region)
                fish.append(Fish(x: p.x, y: p.y, wx: w.x, wy: w.y, seed: i, hop: 1))
            }
        }

        /// Thả viên tại (x, y) — kẹp vào vùng ngang; giao cho chú cá gần nhất. Trả chỉ số viên.
        @discardableResult
        mutating func drop(x: Double, y: Double) -> Int {
            let k = cursor
            cursor = (cursor + 1) % pellets.count
            for i in fish.indices where fish[i].target == k { fish[i].target = -1 }   // viên cũ bị thay
            let px = min(max(x, region.minX), region.maxX)
            pellets[k] = Pellet(x0: px, x: px, y: min(y, floor), age: 0, alive: true)
            let f = AquariumFx.nearestFish(fish, count: fish.count, px: px, py: pellets[k].y)
            if f >= 0 { fish[f].target = k }
            return k
        }

        /// Một bước mô phỏng — trả số viên vừa ăn.
        mutating func step(dt: Double) -> Int {
            for k in pellets.indices where pellets[k].alive { pellets[k] = AquariumFx.sink(pellets[k], dt: dt, floor: floor) }
            var ate = 0
            for i in fish.indices {
                let t = fish[i].target
                if t >= 0, pellets[t].alive {
                    // Đuổi viên đang chìm: KHÔNG chậm lại khi tới gần (viên chìm 22 pt/s — chậm lại thì không bắt kịp).
                    fish[i] = AquariumFx.steer(fish[i], toward: pellets[t].x, pellets[t].y, dt: dt, limit: AquariumFx.maxSpeed,
                                               arrive: false, region: region)
                    if AquariumFx.eats(fish[i], pellets[t], scale: scale(of: i)) {
                        pellets[t].alive = false
                        fish[i].target = -1
                        ate += 1
                    }
                } else {
                    fish[i].target = -1
                    fish[i] = AquariumFx.steer(fish[i], toward: fish[i].wx, fish[i].wy, dt: dt, limit: AquariumFx.wanderSpeed,
                                               arrive: true, region: region)
                    if hypot(fish[i].wx - fish[i].x, fish[i].wy - fish[i].y) < AquariumFx.waypointReach {
                        fish[i].hop += 1
                        let w = AquariumFx.waypoint(seed: fish[i].seed, k: fish[i].hop, region: region)
                        fish[i].wx = w.x; fish[i].wy = w.y
                    }
                }
            }
            // Viên khác bị ăn ké (cá đi ngang qua) — cũng tính.
            for i in fish.indices {
                for k in pellets.indices where AquariumFx.eats(fish[i], pellets[k], scale: scale(of: i)) {
                    pellets[k].alive = false
                    ate += 1
                    for j in fish.indices where fish[j].target == k { fish[j].target = -1 }
                }
            }
            if ate > 0 { eaten += ate; ensureFish() }
            return ate
        }

        /// Cá quay mặt sang trái (lật hình) khi vận tốc ngang âm rõ rệt.
        func facesLeft(_ i: Int) -> Bool { fish[i].vx < -0.5 }
    }

    /// Hình cá (đơn vị: dài 1, tâm thân ở gốc, mặt hướng phải): thân elip + đuôi tam giác.
    static func bodyPath(length L: Double) -> CGPath {
        let p = CGMutablePath()
        let h = L * fishHeight / fishLength
        p.addEllipse(in: CGRect(x: -L * 0.38, y: -h / 2, width: L * 0.8, height: h))
        p.move(to: CGPoint(x: -L * 0.3, y: 0))
        p.addLine(to: CGPoint(x: -L * 0.55, y: -h * 0.45))
        p.addLine(to: CGPoint(x: -L * 0.55, y: h * 0.45))
        p.closeSubpath()
        return p
    }
}

// MARK: - Cảnh bể (motif "aquarium")

/// Bể cá: gradient nước sâu (ThemeScene.gradient), vài vệt nắng xiên mờ từ mặt nước, lớp cát lượn ở đáy, rong biển.
enum AquariumScene {
    static let rayCount = 4
    static let sandHeight = AquariumFx.sandHeight
    static let sandColor: UInt32 = 0xC9B07A, sandAlpha = 0.55
    static let weedColor: UInt32 = 0x2F8F5B, weedAlpha = 0.6, weedWidth = 3.0
    static let weedX: [Double] = [0.06, 0.19, 0.37, 0.58, 0.81, 0.94]
    static let weedH: [Double] = [30, 22, 36, 26, 38, 24]

    /// Vệt nắng: tứ giác (4 điểm) từ mép trên xiên xuống 75 % chiều cao.
    static func rays(width w: Double, height h: Double) -> [[(Double, Double)]] {
        (0..<rayCount).map { i in
            let x0 = w * (0.12 + 0.24 * Double(i)), rw = w * 0.07, skew = w * 0.1
            return [(x0, 0), (x0 + rw, 0), (min(x0 + rw + skew, w), h * 0.75), (min(x0 + skew, w), h * 0.75)]
        }
    }
    /// Mép trên lớp cát (điểm cách 8 pt) — lượn nhẹ.
    static func sandTop(width w: Double, height h: Double) -> [(Double, Double)] {
        var out: [(Double, Double)] = []
        var x = 0.0
        while x <= w { out.append((x, h - sandHeight + 2 * sin(x / 37))); x += 8 }
        if out.last?.0 != w { out.append((w, h - sandHeight + 2 * sin(w / 37))) }
        return out
    }
    /// Rong: gốc (x, đáy) → ngọn (x + lệch, đáy − cao), điểm điều khiển lệch ngược ⇒ cong chữ S nhẹ.
    static func weeds(width w: Double, height h: Double) -> [(x0: Double, y0: Double, cx: Double, cy: Double, x1: Double, y1: Double)] {
        weedX.enumerated().map { i, f in
            let x = w * f, y0 = h - 3, hh = min(weedH[i], h * 0.4)
            let lean = i % 2 == 0 ? 5.0 : -5.0
            return (x, y0, x - lean, y0 - hh * 0.5, x + lean * 0.6, y0 - hh)
        }
    }
}

// MARK: - Bộ vẽ

/// Đích CADisplayLink yếu (link giữ target mạnh).
private final class LinkProxy: NSObject {
    weak var owner: FishFeedRenderer?
    @MainActor @objc func tick(_ l: CADisplayLink) { owner?.tick(l) }
}

@MainActor final class FishFeedRenderer: ThemeFxRenderer {
    private weak var host: UIView?
    var onEvent: (() -> Void)?
    /// App Group — nil (ô xem thử) ⇒ không lưu, bắt đầu từ 0.
    private var defaults: UserDefaults?
    private var world: AquariumFx.World?
    private var builtFor: CGRect = .null
    private var fishLayers: [CAShapeLayer] = []
    private var pelletLayers: [CAShapeLayer] = []
    private var link: CADisplayLink?
    private var lastPress: CFTimeInterval = 0
    private var lastTick: CFTimeInterval = 0
    private var gate = AquariumFx.PersistGate()

    init(host: UIView, defaults: UserDefaults?) {
        self.host = host
        self.defaults = defaults
    }

    /// App Group đến sau khi dựng (KeyboardView đặt sau install) ⇒ nạp lại bộ đếm từ đó (không ghi đè bằng 0).
    func setDefaults(_ d: UserDefaults?) {
        guard d !== defaults else { return }
        defaults = d
        gate = AquariumFx.PersistGate()
        let had = world != nil
        world = nil; builtFor = .null
        if had { ensureWorld() }
    }

    private var stored: Int { defaults?.integer(forKey: AquariumFx.storageKey) ?? 0 }

    func layout() { ensureWorld() }

    private func ensureWorld() {
        guard let host, host.bounds.width > 0, host.bounds.height > 0 else { return }
        let b = host.bounds
        guard world == nil || builtFor != b else { return }
        let eaten = world?.eaten ?? stored
        world = AquariumFx.World(eaten: eaten, minX: Double(b.minX), top: Double(b.minY), width: Double(b.width), height: Double(b.height))
        builtFor = b
        syncLayers()
    }

    func fire(_ r: CGRect, isReturn: Bool, now: CFTimeInterval, media: CFTimeInterval) {
        ensureWorld()
        guard world != nil else { return }
        world?.drop(x: Double(r.midX), y: Double(r.midY))
        lastPress = media
        startLink(media)
        syncLayers()
    }

    func fireQueued(now: CFTimeInterval, media: CFTimeInterval) {}

    func halt() {
        stopLink()
        save(force: true)
    }

    func detach() {
        halt()
        for l in fishLayers + pelletLayers { l.removeFromSuperlayer() }
        fishLayers.removeAll(); pelletLayers.removeAll()
        world = nil; builtFor = .null
    }

    private func startLink(_ media: CFTimeInterval) {
        if link == nil {
            let p = LinkProxy(); p.owner = self
            let l = CADisplayLink(target: p, selector: #selector(LinkProxy.tick(_:)))
            l.preferredFrameRateRange = CAFrameRateRange(minimum: 20, maximum: 30, preferred: 30)
            l.add(to: .main, forMode: .common)
            link = l
        }
        if link?.isPaused ?? true { lastTick = media }
        link?.isPaused = false
    }

    private func stopLink() {
        link?.invalidate()
        link = nil
    }

    fileprivate func tick(_ l: CADisplayLink) {
        let t = l.timestamp
        if t - lastPress > AquariumFx.idleAfter {          // nghỉ ⇒ dừng hẳn, cá đứng yên
            link?.isPaused = true
            save(force: true)
            return
        }
        let dt = min(max(t - lastTick, 0), 0.1)
        lastTick = t
        guard dt > 0, world != nil else { return }
        let ate = world?.step(dt: dt) ?? 0
        if ate > 0 { gate.note() }
        save(force: false)
        syncLayers()
    }

    private func save(force: Bool) {
        guard let w = world, let d = defaults else { return }
        let now = CACurrentMediaTime()
        if force ? gate.flush(now: now) : gate.shouldSave(now: now) { d.set(w.eaten, forKey: AquariumFx.storageKey) }
    }

    /// Đặt vị trí / hướng / cỡ layer theo thế giới (không cấp phát trừ khi có cá / viên mới lần đầu).
    private func syncLayers() {
        guard let host, let w = world else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        while fishLayers.count < w.count { let l = makeFish(fishLayers.count); fishLayers.append(l); host.layer.addSublayer(l) }
        while pelletLayers.count < w.pellets.count { let l = makePellet(); pelletLayers.append(l); host.layer.addSublayer(l) }
        for i in 0..<w.count {
            let f = w.fish[i], s = CGFloat(w.scale(of: i))
            let l = fishLayers[i]
            l.position = CGPoint(x: f.x, y: f.y)
            l.transform = CATransform3DMakeScale(w.facesLeft(i) ? -s : s, s, 1)
        }
        for i in w.count..<fishLayers.count { fishLayers[i].isHidden = true }   // bộ đếm nạp lại ít cá hơn
        for i in 0..<w.count where fishLayers[i].isHidden { fishLayers[i].isHidden = false }
        for (k, p) in w.pellets.enumerated() {
            let l = pelletLayers[k]
            l.isHidden = !p.alive
            if p.alive { l.position = CGPoint(x: p.x, y: p.y) }
        }
        CATransaction.commit()
    }

    private func makeFish(_ i: Int) -> CAShapeLayer {
        let l = CAShapeLayer()
        l.path = AquariumFx.bodyPath(length: AquariumFx.fishLength)
        l.fillColor = UIColor(fx: AquariumFx.colors[i % AquariumFx.colors.count]).cgColor
        l.opacity = 0.9
        let eye = CAShapeLayer()
        eye.path = CGPath(ellipseIn: CGRect(x: AquariumFx.fishLength * 0.22, y: -2.2, width: 2.2, height: 2.2), transform: nil)
        eye.fillColor = UIColor(white: 0.1, alpha: 1).cgColor
        l.addSublayer(eye)
        return l
    }

    private func makePellet() -> CAShapeLayer {
        let l = CAShapeLayer()
        let r = AquariumFx.pelletRadius
        l.path = CGPath(ellipseIn: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r), transform: nil)
        l.fillColor = UIColor(fx: AquariumFx.pelletColor).cgColor
        l.isHidden = true
        return l
    }

    #if DEBUG
    var debugWorld: AquariumFx.World? { world }
    var debugLinkRunning: Bool { link.map { !$0.isPaused } ?? false }
    var debugFishLayers: [CAShapeLayer] { fishLayers }
    func debugStep(_ dt: Double) { _ = world?.step(dt: dt); syncLayers() }
    #endif
}
