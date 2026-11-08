// Theme "Bóng đá" (11/2026, Plus): hiệu ứng "Sút!" (id goal) + cụm cổ vũ (pháo sáng đỏ + cờ đỏ sao vàng) + cảnh sân cỏ
// (motif "pitch" — ThemeScene). Hàm thuần song sinh android/keyboard/.../FootballFx.kt — CÙNG SỐ (test chéo hai nền tảng).
//
//  • Enter ⇒ quả bóng (vector) bay theo cung Bézier bậc 2 từ phím Enter vào khung thành nhỏ ở mép trên; lưới gợn; chữ
//    "VÀOOO!" bật lên rồi tắt. Điểm điều khiển kẹp trong khung ⇒ cả cung nằm trong bàn phím (bao lồi, #151).
//  • Phím khác ⇒ một túm cỏ nhỏ nhú lên ở mép dưới phím rồi tắt (rất nhẹ).
//  • Cụm cổ vũ ("việt nam vô địch", "vnvđ", "vn #1", "vào", "goal", "gooool"…) ⇒ pháo sáng đỏ hai góc dưới + cờ đỏ sao
//    vàng rơi ~1,2 s. So khớp ở ranh giới từ, chỉ khi hiệu ứng Sút! đang chọn (CheerWords.Matcher, ≤ 6 token gần nhất).
//  • Tiếng hò reo (KeySoundSynth.cheerSamples) mỗi cú sút — chỉ khi Âm thanh phím bật.
import UIKit

// MARK: - Cụm cổ vũ

/// Cụm cổ vũ của theme Bóng đá. Chuẩn hoá: NFC, chữ thường, bỏ ký tự đầu/cuối không phải chữ/số/#, chữ lặp ≥ 3 lần (cùng
/// chữ gốc, bỏ dấu) gộp còn một ("vàoooo" ⇒ "vào", "gooool" ⇒ "gol"); "việt nam" ⇒ "vn"; "# 1" / "number one" / "số 1"
/// ⇒ "#1"; "vnvd" ⇒ "vnvđ". Chỉ so NGUYÊN token ("vàobờ" ≠ "vào"); từ Việt phải đúng dấu ("vao" không khớp). Bảng là dữ
/// liệu — Android CheerWords y hệt.
enum CheerWords {
    static let phrases: [String] = ["việt nam vô địch", "vô địch", "vnvđ", "vn #1", "vào", "goal", "gol"]
    /// Số token gần nhất giữ lại (đủ cho "việt nam number one").
    static let maxTokens = 6
    static let table: [[String]] = phrases.map { canonical(tokens($0)) }

    static func tokens(_ text: String) -> [String] {
        text.split(whereSeparator: { $0 == " " }).map { token(String($0)) }.filter { !$0.isEmpty }
    }

    /// Chữ gốc (bỏ dấu, giữ đ): scalar đầu của dạng tách NFD.
    static func base(_ c: Character) -> Character {
        guard let s = String(c).decomposedStringWithCanonicalMapping.unicodeScalars.first else { return c }
        return Character(s)
    }

    private static func keep(_ c: Character) -> Bool { c.isLetter || c.isNumber || c == "#" }

    /// Một từ ⇒ token chuẩn hoá (rỗng = bỏ qua).
    static func token(_ word: String) -> String {
        var cs = Array(word.precomposedStringWithCanonicalMapping.lowercased())
        while let f = cs.first, !keep(f) { cs.removeFirst() }
        while let l = cs.last, !keep(l) { cs.removeLast() }
        return collapse(cs)
    }

    /// Gộp chuỗi ≥ 3 ký tự cùng chữ gốc: cùng một ký tự ⇒ ký tự đó; lẫn dấu ⇒ chữ gốc không dấu.
    static func collapse(_ cs: [Character]) -> String {
        var out = ""
        var i = 0
        while i < cs.count {
            let b = base(cs[i])
            var j = i + 1
            while j < cs.count && base(cs[j]) == b { j += 1 }
            if j - i >= 3 {
                let same = cs[i..<j].allSatisfy { $0 == cs[i] }
                out.append(same ? cs[i] : b)
            } else {
                out.append(contentsOf: cs[i..<j])
            }
            i = j
        }
        return out
    }

    static let numberWords: Set<String> = ["#", "number", "số"]
    static let oneWords: Set<String> = ["1", "one", "một"]

    /// Gộp cụm nhiều token thành dạng chuẩn ("việt nam" ⇒ "vn", "số 1" ⇒ "#1", "vnvd" ⇒ "vnvđ").
    static func canonical(_ t: [String]) -> [String] {
        var out: [String] = []
        var i = 0
        while i < t.count {
            let a = t[i]
            let b: String? = i + 1 < t.count ? t[i + 1] : nil
            if a == "việt", b == "nam" { out.append("vn"); i += 2; continue }
            if numberWords.contains(a), let b, oneWords.contains(b) { out.append("#1"); i += 2; continue }
            out.append(a == "vnvd" ? "vnvđ" : a)
            i += 1
        }
        return out
    }

    /// Dãy token (cũ → mới) có KẾT THÚC bằng một cụm trong bảng không.
    static func matches(_ t: [String]) -> Bool {
        let c = canonical(t)
        return table.contains { p in p.count <= c.count && Array(c.suffix(p.count)) == p }
    }

    /// Bộ so khớp chạy theo phím: controller đưa từ vừa chốt + ký hiệu vừa gõ; "#" và chữ số dồn thành một token ("#1").
    /// Chỉ so ở ranh giới (cách / Enter / dấu câu); khớp ⇒ xoá bộ nhớ (một cụm bắn một lần).
    struct Matcher {
        private(set) var tokens: [String] = []
        private var glue = ""

        static func isGlue(_ s: String) -> Bool { !s.isEmpty && s.allSatisfy { $0 == "#" || ("0"..."9").contains($0) } }

        private mutating func push(_ t: String) {
            guard !t.isEmpty else { return }
            tokens.append(t)
            if tokens.count > CheerWords.maxTokens { tokens.removeFirst(tokens.count - CheerWords.maxTokens) }
        }
        private mutating func closeGlue() {
            if !glue.isEmpty { push(glue); glue = "" }
        }

        /// `word`: từ vừa chốt (rỗng = không có); `symbol`: ký hiệu / chữ số vừa gõ; `end`: ranh giới (cách / Enter).
        /// Trả true khi vừa gõ xong một cụm cổ vũ.
        mutating func feed(word: String, symbol: String? = nil, end: Bool = false) -> Bool {
            if !word.isEmpty { closeGlue(); push(CheerWords.token(word)) }
            if let s = symbol {
                if Self.isGlue(s) { glue += s; if glue.count > 8 { glue = String(glue.suffix(8)) }; return false }
                closeGlue()
                return evaluate()
            }
            guard end else { return false }
            closeGlue()
            return evaluate()
        }

        private mutating func evaluate() -> Bool {
            guard !tokens.isEmpty, CheerWords.matches(tokens) else { return false }
            tokens.removeAll(keepingCapacity: true)
            return true
        }

        mutating func reset() { tokens.removeAll(keepingCapacity: true); glue = "" }
    }
}

// MARK: - Sút! (Enter)

/// Cú sút: khung thành nhỏ canh giữa mép trên, bóng bay cung Bézier bậc 2 từ tâm phím Enter vào giữa lưới.
enum GoalFx {
    static let netWidth = 56.0, netHeight = 24.0, netTop = 4.0, mesh = 6.0, postWidth = 2.0
    static let ballRadius = 7.0
    /// Bay / nằm trong lưới / mờ (giây).
    static let flight = 0.6, hold = 0.35, fade = 0.4
    static var life: Double { flight + hold + fade + 0.15 }
    /// Cung bay: nhô lên trên điểm cao hơn `lift` + `liftPerDx` × khoảng ngang.
    static let lift = 34.0, liftPerDx = 0.3
    static let pool = 2
    static let text = "VÀOOO!"
    static let textSize = 16.0, textGap = 12.0, textWidth = 96.0, textHeight = 22.0
    static let ballScaleEnd = 0.72
    static let spinTurns = 2.0
    static let keyframes = 24

    struct Rect: Equatable { var x: Double, y: Double, w: Double, h: Double
        var midX: Double { x + w / 2 }; var maxY: Double { y + h }
    }
    struct Pt: Equatable { var x: Double, y: Double }

    static func net(minX: Double, width: Double, top: Double) -> Rect {
        Rect(x: minX + (width - netWidth) / 2, y: top + netTop, w: netWidth, h: netHeight)
    }
    /// Đích: giữa lưới, hơi thấp (bóng "nằm" trong lưới).
    static func target(_ n: Rect) -> Pt { Pt(x: n.midX, y: n.y + n.h * 0.55) }
    /// Điểm điều khiển: giữa hai đầu theo ngang, cao hơn điểm cao hơn; kẹp ≥ top + bán kính bóng + 1.
    static func control(start s: Pt, end e: Pt, top: Double) -> Pt {
        let cy = min(s.y, e.y) - lift - liftPerDx * abs(s.x - e.x)
        return Pt(x: (s.x + e.x) / 2, y: max(cy, top + ballRadius + 1))
    }
    /// Vị trí bóng ở tỉ lệ u (0…1) của cung.
    static func ball(_ u: Double, start s: Pt, control c: Pt, end e: Pt) -> Pt {
        let k = min(max(u, 0), 1), m = 1 - k
        return Pt(x: m * m * s.x + 2 * m * k * c.x + k * k * e.x, y: m * m * s.y + 2 * m * k * c.y + k * k * e.y)
    }
    static func ballScale(_ u: Double) -> Double { 1 - (1 - ballScaleEnd) * min(max(u, 0), 1) }
    static func ballSpin(_ u: Double) -> Double { 2 * Double.pi * spinTurns * min(max(u, 0), 1) }
    /// Gợn lưới (tỉ lệ phồng) `t` giây sau khi bóng chạm lưới — dao động tắt dần, hết sau 0,6 s.
    static func netRipple(_ t: Double) -> Double {
        guard t > 0, t < 0.6 else { return 0 }
        return 0.16 * sin(2 * Double.pi * 2.6 * t) * exp(-t / 0.2)
    }
    /// Độ đậm khung thành theo thời gian cú sút: hiện 0,12 s, giữ, mờ 0,3 s cuối.
    static func netAlpha(_ t: Double) -> Double {
        if t <= 0 || t >= life { return 0 }
        if t < 0.12 { return t / 0.12 }
        if t > life - 0.3 { return (life - t) / 0.3 }
        return 1
    }
    /// Chữ "VÀOOO!" `t` giây sau khi chạm lưới: bật 0,4 → 1,2 → 1.
    static func textScale(_ t: Double) -> Double {
        if t <= 0 { return 0.4 }
        if t < 0.12 { return 0.4 + 0.8 * t / 0.12 }
        if t < 0.22 { return 1.2 - 0.2 * (t - 0.12) / 0.1 }
        return 1
    }
    static func textAlpha(_ t: Double) -> Double {
        if t <= 0 { return 0 }
        let end = hold + fade + 0.15
        if t > end - 0.25 { return max(0, (end - t) / 0.25) }
        return 1
    }
    static func textCenter(_ n: Rect) -> Pt { Pt(x: n.midX, y: n.maxY + textGap) }
    /// Vạch lưới dọc + ngang (toạ độ trong khung lưới) — bước `mesh`.
    static func meshLines(_ n: Rect) -> (xs: [Double], ys: [Double]) {
        var xs: [Double] = [], ys: [Double] = []
        var x = mesh; while x < n.w - 0.5 { xs.append(x); x += mesh }
        var y = mesh; while y < n.h - 0.5 { ys.append(y); y += mesh }
        return (xs, ys)
    }
}

/// Túm cỏ nhú ở mép dưới phím (phím không phải Enter): 3 lá (lệch ngang, cao, nghiêng ngọn).
enum GrassTuft {
    static let blades: [(dx: Double, h: Double, lean: Double)] = [(-4, 7, -2), (0, 9, 0.5), (4, 6.5, 2)]
    static let bladeWidth = 1.6
    static let grow = 0.12, duration = 0.32
    static let pool = 6
    static let inset = 2.0
    static let color: UInt32 = 0x8BD36A
    static func origin(keyMidX: Double, keyMaxY: Double) -> GoalFx.Pt { GoalFx.Pt(x: keyMidX, y: keyMaxY - inset) }
    static func scaleY(_ t: Double) -> Double { t <= 0 ? 0 : t < grow ? t / grow : 1 }
    static func alpha(_ t: Double) -> Double {
        if t <= 0 || t >= duration { return 0 }
        return t < grow ? 0.9 : 0.9 * (duration - t) / (duration - grow)
    }
}

// MARK: - Cụm cổ vũ: pháo sáng đỏ + cờ đỏ sao vàng

enum CheerBurst {
    static let duration = 1.2
    static let flagCount = 14
    static let flagW = 11.0, flagH = 7.5, starR = 2.6
    /// Tỉ lệ bán kính trong của sao 5 cánh (ngôi sao cờ: r trong ≈ 0,382 r ngoài).
    static let starInner = 0.382
    /// Sao vàng 5 cánh (10 đỉnh xen ngoài / trong, đỉnh đầu chĩa lên) quanh gốc — Android CheerBurst.star y hệt.
    static func star(_ r: Double = starR) -> [(x: Double, y: Double)] {
        (0..<10).map { k in
            let a = Double(k) * Double.pi / 5 - Double.pi / 2
            let rr = k % 2 == 0 ? r : r * starInner
            return (rr * cos(a), rr * sin(a))
        }
    }
    static let red: UInt32 = 0xDA251D, yellow: UInt32 = 0xFFFF00
    static let flareRed: UInt32 = 0xFF3B30
    static let flareRadius = 5.0
    static let sparksPerFlare = 5
    static let sparkDuration = 0.8
    static let margin = 8.0

    struct Flag: Equatable { var x0: Double, y0: Double, dx: Double, dy: Double, rot: Double, delay: Double, dur: Double }

    /// Cờ rơi: trải đều bề ngang (lệch nhẹ), xuất phát gần mép trên, rơi tối đa tới cách đáy `margin`.
    static func flags(minX: Double, top: Double, width: Double, height: Double) -> [Flag] {
        (0..<flagCount).map { i in
            var st = fxSeed(i &* 131 &+ 7)
            func next() -> Double { st = fxStep(st); return fxValue(st) }
            let slot = (Double(i) + 0.5) / Double(flagCount)
            let x0 = minX + margin + (width - 2 * margin) * slot + (next() - 0.5) * 6
            let y0 = top + 6 + 10 * next()
            let fall = (height - 20) * (0.45 + 0.4 * next())
            let dy = max(0, min(fall, top + height - margin - y0))
            let dx = (next() - 0.5) * 24
            let rot = (next() - 0.5) * 6
            let delay = 0.25 * next()
            return Flag(x0: x0, y0: y0, dx: dx, dy: dy, rot: rot, delay: delay, dur: duration - delay)
        }
    }
    /// Hai pháo sáng ở hai góc dưới.
    static func flares(minX: Double, top: Double, width: Double, height: Double) -> [GoalFx.Pt] {
        let y = top + height - 10
        return [GoalFx.Pt(x: minX + width * 0.1, y: y), GoalFx.Pt(x: minX + width * 0.9, y: y)]
    }
    /// Độ sáng pháo: mở 0,1 s, bập bùng NHẸ (0,75…1, 3 Hz — không chớp), tắt 0,3 s cuối.
    static func flareAlpha(_ t: Double) -> Double {
        if t <= 0 || t >= duration { return 0 }
        if t < 0.1 { return t / 0.1 }
        if t > duration - 0.3 { return (duration - t) / 0.3 * 0.875 }
        return 0.875 + 0.125 * sin(2 * Double.pi * 3 * t)
    }
    /// Tia lửa thứ k của pháo: bay lên toả quạt.
    static func spark(_ k: Int) -> (dx: Double, dy: Double, delay: Double) {
        (Double(k - 2) * 7, -(26 + 6 * Double(k % 3)), Double(k) * 0.07)
    }
}

// MARK: - Cảnh sân cỏ (motif "pitch")

/// Sân cỏ: sọc cắt cỏ dọc (sọc lẻ sáng hơn) + vạch vôi mờ: đường biên, vạch giữa, vòng tròn giữa + chấm, vòng cấm +
/// khu cầu môn hai bên. Toạ độ trong khung w×h (gốc trên-trái).
enum PitchScene {
    static let inset = 5.0, lineWidth = 1.2, spot = 1.6
    static let stripeAlpha = 0.07
    static func stripeWidth(_ w: Double) -> Double { max(28, w / 10) }
    /// Sọc sáng (x, bề rộng) — sọc lẻ.
    static func stripes(width w: Double, height h: Double) -> [(x: Double, w: Double)] {
        let sw = stripeWidth(w)
        var out: [(x: Double, w: Double)] = []
        var x = sw
        while x < w { out.append((x, min(sw, w - x))); x += 2 * sw }
        return out
    }
    enum Prim: Equatable {
        case rect(x: Double, y: Double, w: Double, h: Double)
        case circle(cx: Double, cy: Double, r: Double)
        case line(x0: Double, y0: Double, x1: Double, y1: Double)
    }
    static func lines(width w: Double, height h: Double) -> [Prim] {
        guard w > 4 * inset, h > 4 * inset else { return [] }
        let r = min(h * 0.22, 40)
        let bw = w * 0.12, bh = h * 0.5, gw = w * 0.05, gh = h * 0.26
        return [
            .rect(x: inset, y: inset, w: w - 2 * inset, h: h - 2 * inset),
            .line(x0: w / 2, y0: inset, x1: w / 2, y1: h - inset),
            .circle(cx: w / 2, cy: h / 2, r: r),
            .rect(x: inset, y: (h - bh) / 2, w: bw, h: bh),
            .rect(x: w - inset - bw, y: (h - bh) / 2, w: bw, h: bh),
            .rect(x: inset, y: (h - gh) / 2, w: gw, h: gh),
            .rect(x: w - inset - gw, y: (h - gh) / 2, w: gw, h: gh),
        ]
    }
}

// MARK: - Bộ vẽ

/// Bộ vẽ hiệu ứng Sút! — layer dựng lười, animation gắn mỗi lần bắn và TỰ GỠ khi xong (model mờ 0) ⇒ nghỉ = 0 animation.
@MainActor final class GoalRenderer: ThemeFxRenderer {
    private weak var host: UIView?
    var onEvent: (() -> Void)?

    private final class Shot {
        let root = CALayer()
        let net = CAShapeLayer()
        let mesh = CAShapeLayer()
        let ball = CALayer()
        let text = CATextLayer()
    }
    private var shots: [Shot] = []
    private var shotPool = KeyEffectPool(capacity: GoalFx.pool)
    private var tufts: [CAShapeLayer] = []
    private var tuftPool = KeyEffectPool(capacity: GrassTuft.pool)
    private var tuftAnim: CAAnimationGroup?
    private var cheerRoot: CALayer?
    private var cheerFlags: [CALayer] = []
    private var cheerFlares: [CALayer] = []
    private var cheerSparks: [CALayer] = []
    private var cheerBuiltFor: CGRect = .null

    init(host: UIView) { self.host = host }

    func fire(_ r: CGRect, isReturn: Bool, now: CFTimeInterval, media: CFTimeInterval) {
        if isReturn { shoot(from: r, now: now) } else { tuft(r, now: now) }
    }

    func fireQueued(now: CFTimeInterval, media: CFTimeInterval) { cheer(now: now) }

    func halt() {
        for s in shots { s.root.isHidden = true }
        cheerRoot?.isHidden = true
        for t in tufts { t.removeAllAnimations() }
    }

    func detach() {
        for s in shots { s.root.removeFromSuperlayer() }
        for t in tufts { t.removeFromSuperlayer() }
        cheerRoot?.removeFromSuperlayer()
        shots.removeAll(); tufts.removeAll(); cheerRoot = nil
        cheerFlags.removeAll(); cheerFlares.removeAll(); cheerSparks.removeAll()
    }

    func layout() {}

    // MARK: sút

    private func shoot(from r: CGRect, now: CFTimeInterval) {
        guard let host, host.bounds.width > 0, host.bounds.height > 0 else { return }
        let b = host.bounds
        let slot = shotPool.next()
        let s: Shot
        if slot < shots.count { s = shots[slot] } else { s = makeShot(); shots.append(s); host.layer.addSublayer(s.root) }
        let n = GoalFx.net(minX: Double(b.minX), width: Double(b.width), top: Double(b.minY))
        let start = GoalFx.Pt(x: Double(min(max(r.midX, b.minX + 8), b.maxX - 8)), y: Double(min(max(r.midY, b.minY + 8), b.maxY - 8)))
        let end = GoalFx.target(n)
        let ctrl = GoalFx.control(start: start, end: end, top: Double(b.minY))
        s.root.frame = b
        s.root.bounds = b
        s.root.isHidden = false
        // Khung thành: cột + xà (đậm) + lưới (mảnh).
        let nr = CGRect(x: n.x, y: n.y, width: n.w, height: n.h)
        s.net.frame = nr
        s.mesh.frame = CGRect(origin: .zero, size: nr.size)
        let frame = CGMutablePath()
        frame.move(to: CGPoint(x: 0, y: nr.height)); frame.addLine(to: .zero)
        frame.addLine(to: CGPoint(x: nr.width, y: 0)); frame.addLine(to: CGPoint(x: nr.width, y: nr.height))
        s.net.path = frame
        let mesh = CGMutablePath()
        let m = GoalFx.meshLines(n)
        for x in m.xs { mesh.move(to: CGPoint(x: x, y: 0)); mesh.addLine(to: CGPoint(x: x, y: n.h)) }
        for y in m.ys { mesh.move(to: CGPoint(x: 0, y: y)); mesh.addLine(to: CGPoint(x: n.w, y: y)) }
        s.mesh.path = mesh
        // Cung bay
        let arc = CGMutablePath()
        arc.move(to: CGPoint(x: start.x, y: start.y))
        arc.addQuadCurve(to: CGPoint(x: end.x, y: end.y), control: CGPoint(x: ctrl.x, y: ctrl.y))
        s.ball.position = CGPoint(x: end.x, y: end.y)
        let tc = GoalFx.textCenter(n)
        s.text.position = CGPoint(x: tc.x, y: tc.y)

        let life = GoalFx.life, fl = GoalFx.flight
        let steps = GoalFx.keyframes
        // Khung thành: hiện / gợn / mờ
        let netA = keyframes("opacity", (0...steps).map { GoalFx.netAlpha(life * Double($0) / Double(steps)) }, duration: life)
        let rip = keyframes("transform.scale.y", (0...steps).map { 1 + GoalFx.netRipple(0.6 * Double($0) / Double(steps)) },
                            duration: 0.6, delay: fl)
        let ripX = keyframes("transform.scale.x", (0...steps).map { 1 + 0.4 * GoalFx.netRipple(0.6 * Double($0) / Double(steps)) },
                             duration: 0.6, delay: fl)
        add(s.net, [netA], now: now)
        add(s.mesh, [rip, ripX], now: now)
        // Bóng
        let pos = CAKeyframeAnimation(keyPath: "position")
        pos.path = arc
        pos.duration = fl
        pos.calculationMode = .paced
        let spin = keyframes("transform.rotation.z", (0...steps).map { GoalFx.ballSpin(Double($0) / Double(steps)) }, duration: fl)
        let sc = keyframes("transform.scale", (0...steps).map { GoalFx.ballScale(Double($0) / Double(steps)) }, duration: fl)
        let ballA = keyframes("opacity", [1, 1, 0], times: [0, (fl + GoalFx.hold) / life, (fl + GoalFx.hold + GoalFx.fade) / life],
                              duration: life)
        s.ball.transform = CATransform3DMakeScale(CGFloat(GoalFx.ballScaleEnd), CGFloat(GoalFx.ballScaleEnd), 1)
        add(s.ball, [pos, spin, sc, ballA], now: now)
        // Chữ
        let tl = life - fl
        let tS = keyframes("transform.scale", (0...steps).map { GoalFx.textScale(tl * Double($0) / Double(steps)) }, duration: tl, delay: fl)
        let tA = keyframes("opacity", (0...steps).map { GoalFx.textAlpha(tl * Double($0) / Double(steps)) }, duration: tl, delay: fl)
        add(s.text, [tS, tA], now: now)
        onEvent?()
    }

    private func keyframes(_ path: String, _ values: [Double], times: [Double]? = nil, duration: Double, delay: Double = 0) -> CAKeyframeAnimation {
        let a = CAKeyframeAnimation(keyPath: path)
        a.values = values.map { NSNumber(value: $0) }
        if let times { a.keyTimes = times.map { NSNumber(value: $0) } }
        a.duration = duration
        a.beginTime = delay
        return a
    }

    /// Gắn nhóm animation (bắt đầu `now`, tự gỡ khi xong; model = trạng thái cuối mờ 0 ⇒ nghỉ không còn gì).
    private func add(_ l: CALayer, _ parts: [CAAnimation], now: CFTimeInterval) {
        let g = CAAnimationGroup()
        g.animations = parts
        g.duration = GoalFx.life
        g.beginTime = now
        g.fillMode = .backwards
        g.isRemovedOnCompletion = true
        l.removeAnimation(forKey: "fx")
        l.add(g, forKey: "fx")
    }

    private func makeShot() -> Shot {
        let s = Shot()
        s.root.anchorPoint = .zero
        s.net.fillColor = nil
        s.net.strokeColor = UIColor.white.cgColor
        s.net.lineWidth = CGFloat(GoalFx.postWidth)
        s.net.lineJoin = .round
        s.net.opacity = 0
        s.mesh.fillColor = nil
        s.mesh.strokeColor = UIColor.white.withAlphaComponent(0.55).cgColor
        s.mesh.lineWidth = 0.7
        s.mesh.anchorPoint = CGPoint(x: 0.5, y: 0)
        s.net.addSublayer(s.mesh)
        // Bóng vector: nền trắng viền sẫm + ngũ giác giữa + 5 mảng sẫm quanh mép.
        let r = CGFloat(GoalFx.ballRadius)
        s.ball.bounds = CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r)
        let disc = CAShapeLayer()
        disc.path = CGPath(ellipseIn: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r), transform: nil)
        disc.fillColor = UIColor.white.cgColor
        disc.strokeColor = UIColor(white: 0.13, alpha: 1).cgColor
        disc.lineWidth = 0.8
        let patches = CAShapeLayer()
        patches.path = Self.ballPatches(r)
        patches.fillColor = UIColor(white: 0.13, alpha: 1).cgColor
        s.ball.addSublayer(disc); s.ball.addSublayer(patches)
        s.ball.opacity = 0
        s.text.string = GoalFx.text
        s.text.font = UIFont.systemFont(ofSize: CGFloat(GoalFx.textSize), weight: .heavy)
        s.text.fontSize = CGFloat(GoalFx.textSize)
        s.text.alignmentMode = .center
        s.text.foregroundColor = UIColor.white.cgColor
        s.text.shadowColor = UIColor(red: 0.85, green: 0.1, blue: 0.1, alpha: 1).cgColor
        s.text.shadowOpacity = 1
        s.text.shadowRadius = 1.5
        s.text.shadowOffset = .zero
        s.text.contentsScale = UIScreen.main.scale
        s.text.bounds = CGRect(x: 0, y: 0, width: GoalFx.textWidth, height: GoalFx.textHeight)
        s.text.opacity = 0
        for l in [s.net, s.ball, s.text] as [CALayer] { s.root.addSublayer(l) }
        return s
    }

    /// Ngũ giác giữa + 5 chấm sẫm quanh mép (bán kính bóng r).
    static func ballPatches(_ r: CGFloat) -> CGPath {
        let p = CGMutablePath()
        func pent(_ cx: CGFloat, _ cy: CGFloat, _ rr: CGFloat, _ rot: CGFloat) {
            for i in 0..<5 {
                let a = rot + CGFloat(i) * 2 * .pi / 5
                let pt = CGPoint(x: cx + rr * cos(a), y: cy + rr * sin(a))
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            p.closeSubpath()
        }
        pent(0, 0, r * 0.37, -.pi / 2)
        for k in 0..<5 {
            let a = -.pi / 2 + CGFloat(k) * 2 * .pi / 5 + .pi / 5
            pent(r * 0.78 * cos(a), r * 0.78 * sin(a), r * 0.22, a)
        }
        return p
    }

    // MARK: cỏ

    private func tuft(_ r: CGRect, now: CFTimeInterval) {
        guard let host else { return }
        let slot = tuftPool.next()
        let l: CAShapeLayer
        if slot < tufts.count { l = tufts[slot] } else { l = makeTuft(); tufts.append(l); host.layer.addSublayer(l) }
        let o = GrassTuft.origin(keyMidX: Double(r.midX), keyMaxY: Double(r.maxY))
        l.position = CGPoint(x: o.x, y: o.y)
        let g = tuftAnimation()
        g.beginTime = now
        l.removeAnimation(forKey: "fx")
        l.add(g, forKey: "fx")
    }

    private func tuftAnimation() -> CAAnimationGroup {
        if let a = tuftAnim { return a }
        let n = 12, d = GrassTuft.duration
        let sy = keyframes("transform.scale.y", (0...n).map { GrassTuft.scaleY(d * Double($0) / Double(n)) }, duration: d)
        let al = keyframes("opacity", (0...n).map { GrassTuft.alpha(d * Double($0) / Double(n)) }, duration: d)
        let g = CAAnimationGroup()
        g.animations = [sy, al]
        g.duration = d
        g.fillMode = .backwards
        g.isRemovedOnCompletion = true
        tuftAnim = g
        return g
    }

    private func makeTuft() -> CAShapeLayer {
        let l = CAShapeLayer()
        let p = CGMutablePath()
        let w = CGFloat(GrassTuft.bladeWidth) / 2
        for b in GrassTuft.blades {
            p.move(to: CGPoint(x: b.dx - w, y: 0))
            p.addQuadCurve(to: CGPoint(x: b.dx + b.lean, y: -b.h), control: CGPoint(x: b.dx - w, y: -b.h * 0.6))
            p.addQuadCurve(to: CGPoint(x: b.dx + w, y: 0), control: CGPoint(x: b.dx + w, y: -b.h * 0.6))
            p.closeSubpath()
        }
        l.path = p
        l.fillColor = UIColor(fx: GrassTuft.color).cgColor
        l.bounds = CGRect(x: -8, y: -10, width: 16, height: 10)
        l.anchorPoint = CGPoint(x: 0.5, y: 1)
        l.opacity = 0
        return l
    }

    // MARK: cổ vũ

    private func cheer(now: CFTimeInterval) {
        guard let host, host.bounds.width > 0, host.bounds.height > 0 else { return }
        let b = host.bounds
        if cheerRoot == nil || cheerBuiltFor != b { buildCheer(b) }
        guard let root = cheerRoot else { return }
        root.isHidden = false
        let d = CheerBurst.duration
        let flags = CheerBurst.flags(minX: Double(b.minX), top: Double(b.minY), width: Double(b.width), height: Double(b.height))
        for (l, f) in zip(cheerFlags, flags) {
            let n = 10
            let pos = keyframes("position.y", (0...n).map { k -> Double in
                let u = Double(k) / Double(n)
                return f.y0 + f.dy * u * u * (3 - 2 * u)
            }, duration: f.dur, delay: f.delay)
            let px = keyframes("position.x", (0...n).map { k -> Double in
                let u = Double(k) / Double(n)
                return f.x0 + f.dx * u + 4 * sin(2 * Double.pi * 1.5 * u)
            }, duration: f.dur, delay: f.delay)
            let rot = keyframes("transform.rotation.z", [0, f.rot], duration: f.dur, delay: f.delay)
            let al = keyframes("opacity", [1, 1, 0], times: [0, 0.75, 1], duration: f.dur, delay: f.delay)
            group(l, [pos, px, rot, al], duration: d, now: now)
        }
        for l in cheerFlares {
            let n = 24
            let al = keyframes("opacity", (0...n).map { CheerBurst.flareAlpha(d * Double($0) / Double(n)) }, duration: d)
            group(l, [al], duration: d, now: now)
        }
        for (i, l) in cheerSparks.enumerated() {
            let sp = CheerBurst.spark(i % CheerBurst.sparksPerFlare)
            let mv = CABasicAnimation(keyPath: "transform.translation")
            mv.fromValue = NSValue(cgSize: .zero)
            mv.toValue = NSValue(cgSize: CGSize(width: sp.dx, height: sp.dy))
            mv.duration = CheerBurst.sparkDuration
            mv.beginTime = sp.delay
            let al = keyframes("opacity", [1, 0.8, 0], duration: CheerBurst.sparkDuration, delay: sp.delay)
            group(l, [mv, al], duration: d, now: now)
        }
    }

    private func group(_ l: CALayer, _ parts: [CAAnimation], duration: Double, now: CFTimeInterval) {
        let g = CAAnimationGroup()
        g.animations = parts
        g.duration = duration
        g.beginTime = now
        g.fillMode = .backwards
        g.isRemovedOnCompletion = true
        l.removeAnimation(forKey: "fx")
        l.add(g, forKey: "fx")
    }

    private func buildCheer(_ b: CGRect) {
        cheerRoot?.removeFromSuperlayer()
        cheerFlags.removeAll(); cheerFlares.removeAll(); cheerSparks.removeAll()
        let root = CALayer()
        root.frame = b
        root.bounds = b
        let flagPath = CGPath(rect: CGRect(x: -CheerBurst.flagW / 2, y: -CheerBurst.flagH / 2,
                                           width: CheerBurst.flagW, height: CheerBurst.flagH), transform: nil)
        let star = CGMutablePath()
        for (k, p) in CheerBurst.star().enumerated() {
            if k == 0 { star.move(to: CGPoint(x: p.x, y: p.y)) } else { star.addLine(to: CGPoint(x: p.x, y: p.y)) }
        }
        star.closeSubpath()
        let flags = CheerBurst.flags(minX: Double(b.minX), top: Double(b.minY), width: Double(b.width), height: Double(b.height))
        for f in flags {
            let l = CAShapeLayer()
            l.path = flagPath
            l.fillColor = UIColor(fx: CheerBurst.red).cgColor
            let s = CAShapeLayer()
            s.path = star
            s.fillColor = UIColor(fx: CheerBurst.yellow).cgColor
            l.addSublayer(s)
            l.position = CGPoint(x: f.x0, y: f.y0 + f.dy)
            l.opacity = 0
            root.addSublayer(l)
            cheerFlags.append(l)
        }
        let fr = CGFloat(CheerBurst.flareRadius)
        for p in CheerBurst.flares(minX: Double(b.minX), top: Double(b.minY), width: Double(b.width), height: Double(b.height)) {
            let l = CAShapeLayer()
            l.path = CGPath(ellipseIn: CGRect(x: -fr, y: -fr, width: 2 * fr, height: 2 * fr), transform: nil)
            l.fillColor = UIColor(fx: CheerBurst.flareRed).cgColor
            l.shadowColor = UIColor(fx: CheerBurst.flareRed).cgColor
            l.shadowOpacity = 1
            l.shadowRadius = 7
            l.shadowOffset = .zero
            l.shadowPath = CGPath(ellipseIn: CGRect(x: -fr * 2, y: -fr * 2, width: 4 * fr, height: 4 * fr), transform: nil)
            l.position = CGPoint(x: p.x, y: p.y)
            l.opacity = 0
            root.addSublayer(l)
            cheerFlares.append(l)
            for _ in 0..<CheerBurst.sparksPerFlare {
                let s = CAShapeLayer()
                s.path = CGPath(ellipseIn: CGRect(x: -1.4, y: -1.4, width: 2.8, height: 2.8), transform: nil)
                s.fillColor = UIColor(fx: 0xFFB199).cgColor
                s.position = CGPoint(x: p.x, y: p.y)
                s.opacity = 0
                root.addSublayer(s)
                cheerSparks.append(s)
            }
        }
        host?.layer.addSublayer(root)
        cheerRoot = root
        cheerBuiltFor = b
    }

    #if DEBUG
    var debugShotRoots: [CALayer] { shots.map(\.root) }
    var debugBallPaths: [CGPath] { shots.compactMap { s in
        ((s.ball.animation(forKey: "fx") as? CAAnimationGroup)?.animations?.first as? CAKeyframeAnimation)?.path } }
    var debugTufts: [CAShapeLayer] { tufts }
    var debugCheerRoot: CALayer? { cheerRoot }
    var debugCheerFlags: [CALayer] { cheerFlags }
    #endif
}

extension UIColor {
    /// Màu từ 0xRRGGBB.
    convenience init(fx rgb: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255, alpha: alpha)
    }
}
