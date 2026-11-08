// Hiệu ứng bấm phím "Kính vạn hoa" (id `kaleido`, Plus, 11/2026 — mặc định của theme "Ảo giác").
//
// Mỗi phím một bông kính vạn hoa đối xứng 8 nhánh nở ra từ chỗ chạm: 8 mảnh kính hình diều (dài / ngắn xen kẽ, mỗi mảnh
// đối xứng qua trục của nó) + 8 viên đá nhỏ nằm giữa hai nhánh, tô 8 sắc cầu vồng; cả bông xoay chậm 45° trong khi nở rồi
// tan trong `duration` (0,9 s). Tối đa `pool` (4) bông cùng lúc — bông thứ 5 tái dùng bông cũ nhất.
//
// Hiệu năng: chỉ vector, path dựng MỘT lần (dùng chung mọi bông), mỗi bông = gốc + lớp xoay + 8 CAShapeLayer (mỗi sắc một
// layer, path = mảnh + đá cùng sắc) — animation (cỡ / góc / độ mờ lấy mẫu hàm thuần) gắn MỘT lần lúc dựng; bấm chỉ đặt
// vị trí + beginTime. Kiểu khác ⇒ không có đối tượng nào (0 chi phí). Tâm bông kẹp trong khung bàn phím (cả khi host dời
// gốc bounds — #151) ⇒ cả bông luôn nằm trong bàn phím; overlay cũng cắt theo khung. Android KaleidoBloom y hệt (số chung).
import UIKit

/// Hình học + thời gian thuần (test được; Android KaleidoBloom cùng số).
enum KaleidoBloom {
    static let folds = 8
    static let duration = 0.9
    /// Góc xoay cả bông trong suốt đời (rad) — 45°, chậm.
    static let spin = Double.pi / 4
    /// Bán kính tới đầu mảnh dài khi nở hết (pt / dp).
    static let radius = 38.0
    static let scaleFrom = 0.25
    static let peak = 0.9
    /// Trần số bông cùng lúc.
    static let pool = 4
    /// 8 sắc cầu vồng (mảnh k dùng sắc k, đá giữa nhánh k và k+1 dùng sắc k+4).
    static let colors: [UInt32] = [0xFF5E8A, 0xFFA94D, 0xFFE066, 0x6EE7B7, 0x5EEAD4, 0x60A5FA, 0xA78BFA, 0xF472B6]

    /// Mảnh kính nhánh `k` ở dạng đơn vị (trục = −y, đầu nhọn hướng lên), đối xứng qua x = 0: nhánh chẵn dài mảnh, lẻ ngắn rộng.
    static func shardUnit(_ k: Int) -> [(x: Double, y: Double)] {
        k % 2 == 0 ? [(0, -1), (0.17, -0.55), (0, -0.16), (-0.17, -0.55)]
                   : [(0, -0.74), (0.24, -0.46), (0, -0.2), (-0.24, -0.46)]
    }
    /// Viên đá nhỏ (hình thoi, đơn vị) trên trục của nó.
    static let gemUnit: [(x: Double, y: Double)] = [(0, -0.5), (0.07, -0.38), (0, -0.26), (-0.07, -0.38)]

    /// Xoay điểm `p` góc `a` (y xuống; a > 0 theo chiều kim đồng hồ trên màn).
    static func rotate(_ p: (x: Double, y: Double), _ a: Double) -> (x: Double, y: Double) {
        (p.x * cos(a) - p.y * sin(a), p.x * sin(a) + p.y * cos(a))
    }
    /// Góc trục nhánh `k`.
    static func axis(_ k: Int) -> Double { Double(k) * 2 * .pi / Double(folds) }
    /// Mảnh nhánh `k` (pt, quanh tâm 0,0, bán kính `radius`).
    static func shard(_ k: Int) -> [(x: Double, y: Double)] {
        shardUnit(k).map { rotate(($0.x * radius, $0.y * radius), axis(k)) }
    }
    /// Đá giữa nhánh `k` và `k + 1`.
    static func gem(_ k: Int) -> [(x: Double, y: Double)] {
        gemUnit.map { rotate(($0.x * radius, $0.y * radius), axis(k) + .pi / Double(folds)) }
    }
    /// Sắc của mảnh `k` / của đá `k`.
    static func shardColor(_ k: Int) -> Int { k % colors.count }
    static func gemColor(_ k: Int) -> Int { (k + folds / 2) % colors.count }

    /// Tiến trình 0…1.
    static func progress(_ t: Double) -> Double { max(0, min(1, t / duration)) }
    /// Cỡ theo thời gian: nở ease-out bậc ba từ `scaleFrom` tới 1.
    static func scale(_ t: Double) -> Double {
        let v = 1 - progress(t)
        return scaleFrom + (1 - scaleFrom) * (1 - v * v * v)
    }
    /// Góc xoay theo thời gian (đều — chậm, không giật).
    static func angle(_ t: Double) -> Double { spin * progress(t) }
    /// Độ mờ: hiện trong 12 % đầu rồi tan (1 − u)²; 0 ở cuối.
    static func alpha(_ t: Double) -> Double {
        guard t >= 0, t < duration else { return 0 }
        let u = progress(t)
        return peak * min(1, u / 0.12) * (1 - u) * (1 - u)
    }
    /// Bán kính lớn nhất của cả bông (mảnh dài khi nở hết).
    static var extent: Double { radius }

    /// Tâm bông từ điểm chạm (x, y), kẹp để CẢ bông nằm trong khung (x0, y0, w, h) — khung hẹp hơn bông ⇒ giữa khung.
    static func center(x: Double, y: Double, bounds b: (x: Double, y: Double, w: Double, h: Double)) -> (x: Double, y: Double) {
        let r = extent
        func clamp(_ v: Double, _ lo: Double, _ len: Double) -> Double {
            len <= 2 * r ? lo + len / 2 : min(max(v, lo + r), lo + len - r)
        }
        return (clamp(x, b.x, b.w), clamp(y, b.y, b.h))
    }
}

/// Lớp vẽ của "Kính vạn hoa" trong KeyEffectOverlay (dựng lười ở phím đầu; pool `KaleidoBloom.pool` bông).
final class KaleidoFx {
    private weak var host: CALayer?
    private(set) var roots: [CALayer] = []
    private var cursor = 0
    /// Path mỗi sắc (mảnh + đá cùng sắc) — dựng MỘT lần, dùng chung mọi bông.
    private static let colorPaths: [CGPath] = {
        let n = KaleidoBloom.colors.count
        let paths = (0..<n).map { _ in CGMutablePath() }
        func add(_ pts: [(x: Double, y: Double)], to p: CGMutablePath) {
            p.move(to: CGPoint(x: pts[0].x, y: pts[0].y))
            for q in pts.dropFirst() { p.addLine(to: CGPoint(x: q.x, y: q.y)) }
            p.closeSubpath()
        }
        for k in 0..<KaleidoBloom.folds {
            add(KaleidoBloom.shard(k), to: paths[KaleidoBloom.shardColor(k)])
            add(KaleidoBloom.gem(k), to: paths[KaleidoBloom.gemColor(k)])
        }
        return paths
    }()

    init(host: CALayer) { self.host = host }

    /// Một bông tại điểm chạm `p` (toạ độ host), kẹp trong `bounds` (host.bounds — có thể dời gốc). `now`: giờ cục bộ host.
    func fire(at p: CGPoint, bounds: CGRect, now: CFTimeInterval) {
        guard let host else { return }
        let slot = cursor % KaleidoBloom.pool
        cursor += 1
        let root: CALayer
        if slot < roots.count { root = roots[slot] } else { root = make(); host.addSublayer(root); roots.append(root) }
        let c = KaleidoBloom.center(x: Double(p.x), y: Double(p.y),
                                    bounds: (Double(bounds.minX), Double(bounds.minY), Double(bounds.width), Double(bounds.height)))
        root.position = CGPoint(x: c.x, y: c.y)
        root.beginTime = now
        root.isHidden = false
    }

    /// Ẩn bàn phím: ẩn mọi bông (animation vẫn gắn — lần bấm kế chạy lại từ đầu).
    func halt() { for r in roots { r.isHidden = true } }
    func remove() { for r in roots { r.removeFromSuperlayer() }; roots.removeAll(); cursor = 0 }

    private func make() -> CALayer {
        let root = CALayer()
        root.bounds = .zero
        root.isHidden = true
        let spinner = CALayer()
        spinner.bounds = .zero
        spinner.opacity = 0
        for (i, path) in Self.colorPaths.enumerated() {
            let l = CAShapeLayer()
            l.path = path
            let c = KaleidoBloom.colors[i]
            l.fillColor = UIColor(red: CGFloat((c >> 16) & 0xFF) / 255, green: CGFloat((c >> 8) & 0xFF) / 255,
                                  blue: CGFloat(c & 0xFF) / 255, alpha: 0.85).cgColor
            l.strokeColor = UIColor(white: 1, alpha: 0.55).cgColor
            l.lineWidth = 0.6
            spinner.addSublayer(l)
        }
        let steps = 12
        let times = (0...steps).map { NSNumber(value: Double($0) / Double(steps)) }
        func at(_ k: Int) -> Double { KaleidoBloom.duration * Double(k) / Double(steps) * 0.9999 }
        let sc = CAKeyframeAnimation(keyPath: "transform.scale")
        sc.values = (0...steps).map { KaleidoBloom.scale(at($0)) }
        sc.keyTimes = times
        let rot = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        rot.values = (0...steps).map { KaleidoBloom.angle(at($0)) }
        rot.keyTimes = times
        let op = CAKeyframeAnimation(keyPath: "opacity")
        op.values = (0...steps).map { KaleidoBloom.alpha(at($0)) }
        op.keyTimes = times
        let g = CAAnimationGroup()
        g.animations = [sc, rot, op]
        g.duration = KaleidoBloom.duration
        g.beginTime = 1e-3
        g.fillMode = .removed
        g.isRemovedOnCompletion = false
        spinner.add(g, forKey: "fx")
        root.addSublayer(spinner)
        return root
    }
}
