// Viền phím cầu vồng — theme "Gaming RGB" (slot "borderFx":"rainbow", Phil 19/10/2026).
//
// MỘT lớp gradient (dải cầu vồng lặp 2 chu kỳ, rộng gấp đôi bàn phím) bị CHE bởi MỘT CAShapeLayer là hình viền
// của mọi phím (path dựng lại chỉ khi khung phím đổi — không mỗi phím). "Gợn sóng RGB": dịch dải gradient theo
// trục x (transform.translation.x) bằng animation Core Animation ⇒ render server / GPU chạy, main thread không làm
// gì mỗi khung. Không animation từng phím.
//
// PHỦ KÍN (bug "tắt đèn từ phía phải qua", Phil 19/10/2026 trên iPhone thật): một chu kỳ màu = một bề ngang W, dải
// rộng 2W = W + một chu kỳ. Độ lệch hiển thị LUÔN lấy dư theo chu kỳ (∈ [0, 1)) ⇒ dải luôn phủ [0, W]. Bản cũ chạy
// vòng lặp từ −phase·W tới −(phase+1)·W: sau lần nghỉ đầu (phase > 0) mép phải dải lùi vào (1−phase)·W < W ⇒ phần
// viền bên phải không còn màu, tối dần từ phải qua rồi bật lại khi vòng lặp quay về. Nay: vòng lặp luôn 0 → −W
// (timeOffset = vị trí bắt đầu), đoạn tăng/giảm tốc là keyframe đã lấy dư (chèn bước nhảy 1 → 0 liền mạch).
//
// Luật hiệu năng (feature-flags-perf-policy): chỉ chạy KHI ĐANG GÕ. Phím đầu: tăng tốc (~0,4 s) + sáng lên 100%
// (~0,2 s). Nghỉ `idleAfter` giây ⇒ GIẢM TỐC tới dừng (~1 s) + MỜ DẦN xuống ánh nghỉ (~58%) cùng lúc — tất cả là
// animation CA (GPU), xong thì gỡ sạch ⇒ 0 animation, 0 CPU khi nghỉ. Mỗi phím chỉ ghi một mốc thời gian (+ hẹn MỘT
// lượt kiểm nếu chưa hẹn). Theme khác ⇒ view không tồn tại (KeyboardView.rainbow == nil). Android
// RainbowBorderView y hệt (cùng hằng số / màu / đường chuyển động — RainbowMotion / RainbowFade).
import UIKit

/// Hằng số + hàm thuần dùng chung hai nền tảng (Android RainbowBorder cùng số — test chéo).
enum RainbowBorder {
    /// Một chu kỳ cầu vồng trượt hết một bề ngang bàn phím (giây) — ở tốc độ đầy.
    static let period = 4.0
    /// Nghỉ gõ chừng này ⇒ bắt đầu dừng (giây).
    static let idleAfter = 1.2
    /// Độ dày viền (pt / dp).
    static let lineWidth = 1.5
    /// Giảm tốc từ tốc độ đầy tới dừng (giây).
    static let decelTime = 1.0
    /// Tăng tốc từ đứng yên tới tốc độ đầy (giây).
    static let accelTime = 0.4
    /// Mờ dần xuống ánh nghỉ (giây) — cùng lúc giảm tốc.
    static let fadeOutTime = 1.0
    /// Sáng lại 100% khi gõ tiếp (giây).
    static let fadeInTime = 0.2
    /// Độ sáng (alpha) ánh nghỉ.
    static let restAlpha = 0.58
    /// Số chu kỳ màu trên dải (dải rộng = stripPeriods · W; cần ≥ W + một chu kỳ).
    static let stripPeriods = 2.0
    /// Một chu kỳ màu (đỏ → cam → vàng → lục → lam → chàm → tím → đỏ); dải gradient lặp HAI lần (0…1 = 2 chu kỳ)
    /// để dịch đúng một bề ngang là liền mạch.
    static let hues: [UInt32] = [0xFF3B30, 0xFF9500, 0xFFCC00, 0x34C759, 0x00C7BE, 0x007AFF, 0xAF52DE, 0xFF3B30]

    /// Màu + vị trí của dải 2 chu kỳ (bỏ điểm trùng ở giữa). `hues`: một chu kỳ, điểm cuối = điểm đầu.
    static func stops(_ hues: [UInt32] = RainbowBorder.hues) -> [(color: UInt32, location: Double)] {
        let n = hues.count - 1
        var out: [(color: UInt32, location: Double)] = []
        for cycle in 0..<2 {
            for i in 0..<n { out.append((hues[i], (Double(cycle) + Double(i) / Double(n)) / 2)) }
        }
        out.append((hues[n], 1))
        return out
    }

    /// Lấy dư theo chu kỳ: luôn trong [0, 1).
    static func wrap(_ x: Double) -> Double {
        let v = x - x.rounded(.down)
        return v >= 1 ? 0 : v
    }

    /// Độ lệch (0…1 bề ngang) sau `elapsed` giây chạy đầy tốc kể từ lệch `from` — tuần hoàn, luôn trong [0, 1).
    static func offset(from: Double, elapsed: Double) -> Double { wrap(from + elapsed / period) }

    /// Khoảng [đầu, cuối] (đơn vị bề ngang) dải phủ khi lệch `offset` (dải đặt ở x = −offset·W, rộng stripPeriods·W).
    static func coverage(offset: Double) -> ClosedRange<Double> { -offset...(stripPeriods - offset) }

    /// Keyframe cho đoạn tăng/giảm tốc của `m` từ `t` tới `end`: độ lệch ĐÃ LẤY DƯ (∈ [0, 1]) + keyTimes (0…1).
    /// Khi chạm biên chu kỳ: chèn 1 → 0 cùng một keyTime (hai vị trí trông y hệt ⇒ liền mạch, không bao giờ trượt quá).
    static func keyframes(_ m: RainbowMotion, from t: Double, to end: Double, fps: Double = 60) -> (values: [Double], times: [Double]) {
        let dur = end - t
        guard dur > 0 else { return ([m.offset(at: t)], [0]) }
        let n = max(1, Int((dur * fps).rounded(.up)))
        var values: [Double] = [], times: [Double] = []
        var prev = m.travelled(at: t)
        values.append(wrap(prev)); times.append(0)
        for i in 1...n {
            let k = Double(i) / Double(n)
            let u = m.travelled(at: t + dur * k)
            let boundary = prev.rounded(.down) + 1
            if u >= boundary, u > prev {
                let kb = (Double(i - 1) + (boundary - prev) / (u - prev)) / Double(n)
                values.append(1); times.append(kb)
                values.append(0); times.append(kb)
            }
            values.append(wrap(u)); times.append(k)
            prev = u
        }
        return (values, times)
    }
}

/// "borderFx":"aurora" (theme AI, 11/2026): viền phím gradient ĐỨNG YÊN (tím → lam ngọc → hồng theo bề ngang bàn phím,
/// cùng lớp mặt nạ hình viền với cầu vồng nhưng không animation, không poke) + dải cực quang tĩnh dọc mép trên (gradient
/// ngang, mờ dần xuống — MỘT CAGradientLayer có mặt nạ gradient dọc trong nền theme). Vẽ một lần lúc đổi theme / cỡ;
/// 0 chi phí mỗi phím, 0 hoạt ảnh. Android AuroraFx y hệt (test số chung).
enum AuroraFx {
    /// Viền phím: (màu, vị trí 0…1 bề ngang bàn phím).
    static let border: [(color: UInt32, location: Double)] = [(0x8B5CF6, 0), (0x22D3EE, 0.55), (0xF472B6, 1)]
    static let borderAlpha = 0.85
    static let lineWidth = 1.0
    /// Dải cực quang: cao (pt / dp) tính từ mép trên nội dung bàn phím; màu ngang; độ đậm ở mép trên → 0 ở đáy dải.
    static let bandHeight = 56.0
    static let band: [(color: UInt32, location: Double)] = [(0x7C3AED, 0), (0x22D3EE, 0.4), (0xA855F7, 0.7), (0x06B6D4, 1)]
    static let bandAlpha = 0.32
    /// Độ đậm dải theo độ sâu `y` (0 = mép trên) — giảm bậc hai (mềm ở đáy dải).
    static func bandOpacity(_ y: Double) -> Double {
        guard y >= 0, y < bandHeight else { return 0 }
        let f = 1 - y / bandHeight
        return bandAlpha * f * f
    }
}

/// "borderFx":"hueflow" (theme "Ảo giác", 11/2026): viền phím cầu vồng (cùng lớp mặt nạ với Gaming RGB nhưng CHẬM) + MỘT
/// lớp nền đổi sắc (dải gradient chàm / tím / lam ngọc cùng độ sáng, trượt ngang như cầu vồng — không mặt nạ, sau hàng
/// phím) — chỉ chạy KHI ĐANG GÕ, một vòng màu `period` giây ở tốc độ đầy (≥ `minCycle`), nghỉ `idleAfter` ⇒ giảm tốc tới
/// dừng rồi 0 hoạt ảnh. An toàn thị giác: sắc nền kề nhau lệch độ sáng tương đối ≤ ~0,02 (không nháy), số lần chuyển sắc
/// mỗi giây ≤ 3; độ đậm nền KHÔNG đổi khi gõ / nghỉ. Gõ dồn (ComboMeter ≥ `rippleLevel`, cách nhau ≥ `rippleGap`) ⇒ một
/// gợn sóng màu đồng tâm chậm (3 vòng cầu vồng mảnh) toả từ phím, trong lớp nền (sau phím). Android HueFlow y hệt.
enum HueFlow {
    static let period = 12.0
    /// Sàn an toàn: một vòng màu không bao giờ nhanh hơn (giây).
    static let minCycle = 8.0
    static let idleAfter = 1.5
    static let accelTime = 0.8
    static let decelTime = 1.5
    static let fadeInTime = 0.6
    static let fadeOutTime = 1.5
    /// Độ sáng viền lúc nghỉ / lúc gõ.
    static let borderRest = 0.55
    static let borderActive = 0.9
    /// Độ đậm lớp nền (cố định — không đổi khi gõ / nghỉ).
    static let fillAlpha = 0.5
    /// Một chu kỳ sắc nền (điểm cuối = điểm đầu): tím, chàm, lam ngọc sẫm, lam, mận — độ sáng gần nhau.
    static let fillHues: [UInt32] = [0x4C1D95, 0x312E81, 0x134E4A, 0x1E3A8A, 0x701A75, 0x4C1D95]
    static func fillStops() -> [(color: UInt32, location: Double)] { RainbowBorder.stops(fillHues) }

    /// Độ sáng tương đối (WCAG) của màu RGB.
    static func luminance(_ rgb: UInt32) -> Double {
        func lin(_ v: UInt32) -> Double {
            let c = Double(v & 0xFF) / 255
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * lin(rgb >> 16) + 0.7152 * lin(rgb >> 8) + 0.0722 * lin(rgb)
    }
    /// Chênh độ sáng lớn nhất giữa hai sắc nền kề nhau.
    static var maxLuminanceStep: Double {
        zip(fillHues, fillHues.dropFirst()).map { abs(luminance($0) - luminance($1)) }.max() ?? 0
    }
    /// Số lần chuyển sắc mỗi giây ở tốc độ đầy (một điểm trên nền đi qua cả chu kỳ trong `period` giây).
    static var transitionsPerSecond: Double { Double(fillHues.count - 1) / period }

    // Gợn sóng màu khi gõ dồn.
    static let rippleLevel = 2
    static let rippleGap = 0.9
    static let rippleRings = 3
    static let rippleStagger = 0.3
    static let rippleLife = 1.6
    static let rippleRadius = 110.0
    static let ripplePeak = 0.35
    static let rippleWidth = 2.0
    static let ripplePool = 2
    /// Bán kính vòng `ring` sau `dt` giây (ease-out bậc ba; 0 trước lượt vòng).
    static func rippleRadius(_ dt: Double, ring: Int) -> Double {
        let t = dt - Double(ring) * rippleStagger
        guard t > 0 else { return 0 }
        let u = min(1, t / rippleLife), v = 1 - u
        return rippleRadius * (1 - v * v * v)
    }
    /// Độ đậm vòng `ring` sau `dt` giây: hiện mềm 0,15 s rồi tắt (1 − u)².
    static func rippleAlpha(_ dt: Double, ring: Int) -> Double {
        let t = dt - Double(ring) * rippleStagger
        guard t > 0, t < rippleLife else { return 0 }
        let u = t / rippleLife
        return ripplePeak * min(1, t / 0.15) * (1 - u) * (1 - u)
    }
    static var rippleLifetime: Double { Double(rippleRings - 1) * rippleStagger + rippleLife }
    /// Màu vòng `ring` của lần gợn thứ `seed` (sắc cầu vồng, hai bậc mỗi vòng).
    static func rippleColor(ring: Int, seed: Int) -> UInt32 {
        let n = RainbowBorder.hues.count - 1
        return RainbowBorder.hues[((seed + ring) * 2 % n + n) % n]
    }
    /// Cổng gợn: chỉ ở mức combo ≥ `rippleLevel`, cách nhau ≥ `rippleGap`.
    struct RippleGate {
        private(set) var last = -Double.greatestFiniteMagnitude
        private(set) var fired = 0
        mutating func trigger(level: Int, at t: Double) -> Bool {
            guard level >= HueFlow.rippleLevel, t - last >= HueFlow.rippleGap else { return false }
            last = t; fired += 1
            return true
        }
    }
}

/// Bộ số chạy của một lớp dải (thuần; Android RainbowTuning y hệt): Gaming RGB, viền / nền "Ảo giác".
struct RainbowTuning: Equatable {
    var period: Double
    var idleAfter: Double
    var accelTime: Double
    var decelTime: Double
    var fadeInTime: Double
    var fadeOutTime: Double
    var restAlpha: Double
    var activeAlpha: Double
    var fullSpeed: Double { 1 / period }

    static let rainbow = RainbowTuning(period: RainbowBorder.period, idleAfter: RainbowBorder.idleAfter,
                                       accelTime: RainbowBorder.accelTime, decelTime: RainbowBorder.decelTime,
                                       fadeInTime: RainbowBorder.fadeInTime, fadeOutTime: RainbowBorder.fadeOutTime,
                                       restAlpha: RainbowBorder.restAlpha, activeAlpha: 1)
    static let hueflowBorder = RainbowTuning(period: HueFlow.period, idleAfter: HueFlow.idleAfter, accelTime: HueFlow.accelTime,
                                             decelTime: HueFlow.decelTime, fadeInTime: HueFlow.fadeInTime,
                                             fadeOutTime: HueFlow.fadeOutTime, restAlpha: HueFlow.borderRest,
                                             activeAlpha: HueFlow.borderActive)
    static let hueflowFill = RainbowTuning(period: HueFlow.period, idleAfter: HueFlow.idleAfter, accelTime: HueFlow.accelTime,
                                           decelTime: HueFlow.decelTime, fadeInTime: 0, fadeOutTime: 0,
                                           restAlpha: HueFlow.fillAlpha, activeAlpha: HueFlow.fillAlpha)
}

/// Đường chuyển động của dải (thuần — test được; Android RainbowMotion y hệt). Đơn vị: chu kỳ màu (= một bề
/// ngang); tốc độ đầy = 1/period chu kỳ/giây. Từ `t0` ở `x0`, tốc độ đổi tuyến tính `v0` → `v1` trong `ramp` giây
/// rồi giữ `v1`.
struct RainbowMotion: Equatable {
    var t0 = 0.0
    var x0 = 0.0
    var v0 = 0.0
    var v1 = 0.0
    var ramp = 0.0

    static let fullSpeed = 1 / RainbowBorder.period
    var rampEnd: Double { t0 + ramp }

    /// Quãng đã đi (chưa lấy dư).
    func travelled(at t: Double) -> Double {
        let tau = max(0, t - t0)
        if tau < ramp { return x0 + v0 * tau + (v1 - v0) * tau * tau / (2 * ramp) }
        return x0 + (v0 + v1) * ramp / 2 + v1 * (tau - ramp)
    }
    func velocity(at t: Double) -> Double {
        let tau = max(0, t - t0)
        return tau < ramp ? v0 + (v1 - v0) * tau / ramp : v1
    }
    /// Độ lệch hiển thị (đã lấy dư, ∈ [0, 1)).
    func offset(at t: Double) -> Double { RainbowBorder.wrap(travelled(at: t)) }

    static func rest(at x: Double) -> RainbowMotion { RainbowMotion(x0: RainbowBorder.wrap(x)) }

    /// Gõ tiếp lúc `t`: tăng tốc từ tốc độ hiện tại tới đầy (đang giảm tốc dở ⇒ ramp ngắn hơn, không giật).
    func resumed(at t: Double, _ k: RainbowTuning = .rainbow) -> RainbowMotion {
        let v = velocity(at: t)
        return RainbowMotion(t0: t, x0: offset(at: t), v0: v, v1: k.fullSpeed,
                             ramp: k.accelTime * max(0, 1 - v / k.fullSpeed))
    }
    /// Nghỉ lúc `t`: giảm tốc đều tới dừng (từ tốc độ đầy mất decelTime).
    func settled(at t: Double, _ k: RainbowTuning = .rainbow) -> RainbowMotion {
        let v = velocity(at: t)
        return RainbowMotion(t0: t, x0: offset(at: t), v0: v, v1: 0, ramp: k.decelTime * v / k.fullSpeed)
    }
}

/// Độ sáng dải theo thời gian (thuần; Android RainbowFade y hệt): `from` → `to` trong `duration` giây, ease in-out.
struct RainbowFade: Equatable {
    var t0 = 0.0
    var from = RainbowBorder.restAlpha
    var to = RainbowBorder.restAlpha
    var duration = 0.0

    var end: Double { t0 + duration }
    func alpha(at t: Double) -> Double {
        guard duration > 0, t < end else { return to }
        let u = max(0, (t - t0) / duration)
        return from + (to - from) * u * u * (3 - 2 * u)
    }
    func toward(_ a: Double, at t: Double, duration d: Double) -> RainbowFade {
        RainbowFade(t0: t, from: alpha(at: t), to: a, duration: d)
    }
}

/// Đồng hồ "chỉ chạy khi đang gõ" (thuần — test được; Android RainbowClock y hệt).
struct RainbowClock {
    var idleAfter = RainbowBorder.idleAfter
    private(set) var running = false
    private(set) var lastInput = -Double.infinity

    /// Một phím lúc `t`; true = vừa chuyển nghỉ → chạy (gắn animation).
    mutating func poke(at t: Double) -> Bool {
        lastInput = t
        if running { return false }
        running = true
        return true
    }
    /// Còn bao lâu nữa thì nghỉ (≤ 0 ⇒ nghỉ ngay).
    func idleRemaining(at t: Double) -> Double { idleAfter - (t - lastInput) }
    mutating func stop() { running = false }
}

/// Lớp viền cầu vồng phủ trên hàng phím (không nhận chạm). Chỉ tồn tại khi theme có "borderFx":"rainbow" / "aurora" /
/// "hueflow". "hueflow" dùng HAI view: viền (`hueflowBorder`) trên hàng phím + nền (`hueflowFill`, không mặt nạ, sau
/// hàng phím, có gợn sóng màu).
final class RainbowBorderView: UIView {
    enum Kind { case rainbow, aurora, hueflowBorder, hueflowFill }
    let kind: Kind
    /// true = viền gradient TĨNH của theme AI (AuroraFx): không animation, poke không làm gì.
    var isAurora: Bool { kind == .aurora }
    var isFill: Bool { kind == .hueflowFill }
    let tuning: RainbowTuning
    private let strip = CAGradientLayer()
    private let outline = CAShapeLayer()
    private var clock = RainbowClock()
    private var tickScheduled = false
    private var motion = RainbowMotion()
    private var fade = RainbowFade()
    private var laidOutWidth: CGFloat = -1
    private var outlines: [CGRect] = []
    private var radii: [CGFloat] = []
    private static let moveKey = "rgb.move", loopKey = "rgb.loop", fadeKey = "rgb.fade"

    /// Độ lệch đang hiện (0…1 bề ngang).
    var phase: Double { motion.offset(at: CACurrentMediaTime()) }

    // Gợn sóng màu (chỉ nền "hueflow"): pool gốc dựng lười, animation gắn MỘT lần, bấm chỉ đặt vị trí + màu + beginTime.
    private var combo = ComboMeter()
    private var rippleGate = HueFlow.RippleGate()
    private var ripples: [CALayer] = []
    private var rippleCursor = 0

    init(frame: CGRect = .zero, aurora: Bool = false, kind: Kind? = nil) {
        let k = kind ?? (aurora ? .aurora : .rainbow)
        self.kind = k
        tuning = k == .hueflowBorder ? .hueflowBorder : k == .hueflowFill ? .hueflowFill : .rainbow
        super.init(frame: frame)
        let aurora = k == .aurora
        clock.idleAfter = tuning.idleAfter
        fade = RainbowFade(from: tuning.restAlpha, to: tuning.restAlpha)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        backgroundColor = .clear
        isOpaque = false
        let st = aurora ? AuroraFx.border : isFill ? HueFlow.fillStops() : RainbowBorder.stops()
        strip.colors = st.map { UIColor(rgbHex: $0.color).cgColor }
        strip.locations = st.map { NSNumber(value: $0.location) }
        strip.startPoint = CGPoint(x: 0, y: 0.5)
        strip.endPoint = CGPoint(x: 1, y: 0.5)
        strip.anchorPoint = .zero
        strip.opacity = Float(aurora ? AuroraFx.borderAlpha : tuning.restAlpha)
        outline.fillColor = nil
        outline.strokeColor = UIColor.black.cgColor
        outline.lineWidth = CGFloat(aurora ? AuroraFx.lineWidth : RainbowBorder.lineWidth)
        layer.addSublayer(strip)
        if !isFill { layer.mask = outline }   // nền "hueflow": cả mặt, không mặt nạ
    }
    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool { false }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        outline.frame = bounds
        strip.bounds = CGRect(x: 0, y: 0, width: bounds.width * CGFloat(isAurora ? 1 : RainbowBorder.stripPeriods), height: bounds.height)
        strip.position = .zero
        if isAurora { CATransaction.commit(); return }   // tĩnh: không animation nào
        // Đổi bề ngang (xoay / iPad / chia đôi): dựng lại animation theo W mới, tiếp tục đúng chỗ đang hiện.
        if bounds.width != laidOutWidth {
            laidOutWidth = bounds.width
            installMotion(at: CACurrentMediaTime())
        }
        CATransaction.commit()
    }

    /// Khung phím (toạ độ view này) + bán kính bo — path chỉ dựng lại khi khác lần trước.
    func setKeys(_ frames: [CGRect], radii: [CGFloat]) {
        guard frames != outlines || radii != self.radii else { return }
        outlines = frames; self.radii = radii
        let p = CGMutablePath()
        let h = outline.lineWidth / 2
        for (f, r) in zip(frames, radii) where f.width > 2 * h && f.height > 2 * h {
            let rr = max(0, min(r - h, min(f.width, f.height) / 2 - h))
            p.addRoundedRect(in: f.insetBy(dx: h, dy: h), cornerWidth: rr, cornerHeight: rr)
        }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        outline.path = p
        CATransaction.commit()
    }

    /// Một phím vừa gõ (sau khi chữ đã chèn). Nghỉ → chạy: tăng tốc + sáng lên MỘT lần. Đang chạy: chỉ ghi giờ.
    func poke() {
        #if DEBUG
        let t0 = CACurrentMediaTime()
        defer { Self.debugCost += CACurrentMediaTime() - t0 }
        #endif
        if isAurora { return }
        let now = CACurrentMediaTime()
        if clock.poke(at: now) {
            motion = motion.resumed(at: now, tuning)
            CATransaction.begin(); CATransaction.setDisableActions(true)
            installMotion(at: now)
            fadeStrip(to: tuning.activeAlpha, duration: tuning.fadeInTime, at: now)
            CATransaction.commit()
        }
        scheduleTick(after: clock.idleRemaining(at: now))
    }

    /// Nền "hueflow": một phím vừa gõ ở `p` (toạ độ view này; nil = phím không có khung) — chạy dải như `poke` + gõ dồn
    /// thì MỘT gợn sóng màu (cổng RippleGate). Kiểu khác ⇒ như `poke`.
    func poke(at p: CGPoint?) {
        poke()
        guard isFill else { return }
        let now = CACurrentMediaTime()
        let level = combo.press(at: now)
        guard let p, rippleGate.trigger(level: level, at: now), window != nil || Self.drawsOffscreen else { return }
        fireRipple(at: p, now: now)
    }

    private func fireRipple(at p: CGPoint, now: CFTimeInterval) {
        let slot = rippleCursor % HueFlow.ripplePool
        rippleCursor += 1
        let root: CALayer
        if slot < ripples.count { root = ripples[slot] } else { root = makeRipple(); ripples.append(root) }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for (i, l) in (root.sublayers ?? []).enumerated() {
            (l as? CAShapeLayer)?.strokeColor = UIColor(rgbHex: HueFlow.rippleColor(ring: i, seed: rippleGate.fired)).cgColor
        }
        root.position = p
        root.beginTime = layer.convertTime(now, from: nil)
        root.isHidden = false
        CATransaction.commit()
    }

    /// Một gốc gợn: `rippleRings` vòng tròn mảnh (path bán kính đầy), animation cỡ + độ đậm + nét lấy mẫu hàm thuần, gắn
    /// MỘT lần (không gỡ; fillMode removed ⇒ xong là vô hình — model opacity 0).
    private func makeRipple() -> CALayer {
        let root = CALayer()
        root.bounds = .zero
        root.isHidden = true
        let r = CGFloat(HueFlow.rippleRadius)
        let path = CGPath(ellipseIn: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r), transform: nil)
        let steps = 16
        for ring in 0..<HueFlow.rippleRings {
            let l = CAShapeLayer()
            l.path = path
            l.fillColor = nil
            l.lineWidth = CGFloat(HueFlow.rippleWidth)
            l.opacity = 0
            let life = HueFlow.rippleLife, start = Double(ring) * HueFlow.rippleStagger
            func at(_ k: Int) -> Double { start + life * Double(k) / Double(steps) * 0.9999 }
            let times = (0...steps).map { NSNumber(value: Double($0) / Double(steps)) }
            let sc = CAKeyframeAnimation(keyPath: "transform.scale")
            sc.values = (0...steps).map { max(0.001, HueFlow.rippleRadius(at($0), ring: ring) / HueFlow.rippleRadius) }
            sc.keyTimes = times
            let op = CAKeyframeAnimation(keyPath: "opacity")
            op.values = (0...steps).map { HueFlow.rippleAlpha(at($0), ring: ring) }
            op.keyTimes = times
            // Nét giữ ~rippleWidth trên màn khi vòng phóng to (bù cỡ).
            let lw = CAKeyframeAnimation(keyPath: "lineWidth")
            lw.values = (0...steps).map { HueFlow.rippleWidth * HueFlow.rippleRadius / max(4, HueFlow.rippleRadius(at($0), ring: ring)) }
            lw.keyTimes = times
            let g = CAAnimationGroup()
            g.animations = [sc, op, lw]
            g.duration = life
            g.beginTime = 1e-3 + start
            g.fillMode = .removed
            g.isRemovedOnCompletion = false
            l.add(g, forKey: "fx")
            root.addSublayer(l)
        }
        layer.addSublayer(root)
        return root
    }

    /// Ẩn bàn phím / đổi theme: đứng yên ngay ở ánh nghỉ (không còn animation).
    func halt() {
        if isAurora { return }
        let now = CACurrentMediaTime()
        clock.stop()
        motion = .rest(at: motion.offset(at: now))
        fade = RainbowFade(from: tuning.restAlpha, to: tuning.restAlpha)
        combo.reset()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for r in ripples { r.isHidden = true }
        strip.removeAllAnimations()
        strip.opacity = Float(fade.to)
        applyOffset(motion.x0)
        CATransaction.commit()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { halt() }
    }

    /// MỘT hẹn giờ cho cả: kiểm nghỉ (khi đang gõ) và dọn animation đã xong (sau khi dừng/mờ). Không chạy mỗi khung.
    private func scheduleTick(after s: Double) {
        guard !tickScheduled else { return }
        tickScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0.05, s)) { [weak self] in
            guard let self else { return }
            self.tickScheduled = false
            self.tick(at: CACurrentMediaTime())
        }
    }

    private func tick(at now: Double) {
        if clock.running {
            let left = clock.idleRemaining(at: now)
            if left > 0 { dropFinished(at: now); scheduleTick(after: left); return }
            settle(at: now)
        }
        let done = max(motion.rampEnd, fade.end)
        if now < done { scheduleTick(after: done - now + 0.02); return }
        dropFinished(at: now)
    }

    /// Gỡ đoạn tăng/giảm tốc + mờ đã xong (model đã ở đúng giá trị cuối ⇒ không đổi gì trên màn).
    private func dropFinished(at now: Double) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        if now >= motion.rampEnd { strip.removeAnimation(forKey: Self.moveKey) }
        if now >= fade.end { strip.removeAnimation(forKey: Self.fadeKey) }
        CATransaction.commit()
    }

    /// Nghỉ: giảm tốc tới dừng + mờ xuống ánh nghỉ, cùng lúc (GPU); xong thì tick gỡ sạch.
    private func settle(at now: Double) {
        clock.stop()
        motion = motion.settled(at: now, tuning)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        installMotion(at: now)
        fadeStrip(to: tuning.restAlpha, duration: tuning.fadeOutTime, at: now)
        CATransaction.commit()
    }

    private func applyOffset(_ x: Double) {
        strip.setAffineTransform(CGAffineTransform(translationX: -CGFloat(x) * bounds.width, y: 0))
    }

    #if DEBUG
    nonisolated(unsafe) static var drawsOffscreen = false
    var debugRipples: [CALayer] { ripples }
    var debugRippleFired: Int { rippleGate.fired }
    #else
    static let drawsOffscreen = false
    #endif

    /// Dựng animation dịch dải theo `motion` từ `now`: đoạn tăng/giảm tốc (keyframe, đã lấy dư) rồi — nếu còn chạy —
    /// vòng lặp 0 → −W đúng một chu kỳ, lặp mãi (timeOffset = vị trí vào vòng). Model = vị trí cuối ⇒ khe giữa hai
    /// animation (nếu có) vẫn hiện đúng chỗ. Gọi trong CATransaction đã tắt actions.
    private func installMotion(at now: Double) {
        strip.removeAnimation(forKey: Self.moveKey)
        strip.removeAnimation(forKey: Self.loopKey)
        let end = motion.rampEnd
        let entry = motion.offset(at: max(now, end))
        applyOffset(entry)
        let w = Double(bounds.width)
        guard w > 0 else { return }
        if now < end {
            let (vals, times) = RainbowBorder.keyframes(motion, from: now, to: end)
            let a = CAKeyframeAnimation(keyPath: "transform.translation.x")
            a.values = vals.map { -$0 * w }
            a.keyTimes = times.map { NSNumber(value: $0) }
            a.calculationMode = .linear
            a.beginTime = strip.convertTime(now, from: nil)
            a.duration = end - now
            strip.add(a, forKey: Self.moveKey)
        }
        if motion.v1 > 0 {
            let a = CABasicAnimation(keyPath: "transform.translation.x")
            a.fromValue = 0.0
            a.toValue = -w
            a.duration = tuning.period
            a.repeatCount = .infinity
            a.timingFunction = CAMediaTimingFunction(name: .linear)
            a.timeOffset = entry * tuning.period
            if end > now { a.beginTime = strip.convertTime(end, from: nil) }
            a.isRemovedOnCompletion = false
            strip.add(a, forKey: Self.loopKey)
        }
    }

    /// Độ sáng dải → `a` trong `duration` giây (từ độ sáng đang hiện; animation opacity GPU). Trong CATransaction.
    private func fadeStrip(to a: Double, duration: Double, at now: Double) {
        guard duration > 0, abs(fade.alpha(at: now) - a) > 1e-9 else { return }   // nền "hueflow": độ đậm không đổi
        fade = fade.toward(a, at: now, duration: duration)
        strip.opacity = Float(a)
        let an = CABasicAnimation(keyPath: "opacity")
        an.fromValue = Float(fade.from)
        an.toValue = Float(a)
        an.duration = duration
        an.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        strip.add(an, forKey: Self.fadeKey)
    }

    #if DEBUG
    /// Đo: tổng thời gian main thread trong poke (giây).
    nonisolated(unsafe) static var debugCost: CFTimeInterval = 0
    var debugRunning: Bool { clock.running }
    var debugAnimationCount: Int { strip.animationKeys()?.count ?? 0 }
    var debugAnimationKeys: Set<String> { Set(strip.animationKeys() ?? []) }
    var debugMaskPath: CGPath? { outline.path }
    var debugStrip: CAGradientLayer { strip }
    var debugMotion: RainbowMotion { motion }
    var debugFade: RainbowFade { fade }
    func debugSetIdle(_ s: Double) { clock.idleAfter = s }
    /// Đặt độ lệch đứng yên (test phủ kín ở mọi vị trí).
    func debugSetPhase(_ x: Double) { halt(); motion = .rest(at: x); applyOffset(motion.x0) }
    /// Nghỉ ngay (không đợi idleAfter).
    func debugSettleNow() { if clock.running { settle(at: CACurrentMediaTime()) } }
    /// Mọi giá trị translation.x mà animation dịch dải có thể nhận (keyframe + đầu/cuối vòng lặp) + model.
    var debugTranslationValues: [Double] {
        var out = [Double(strip.affineTransform().tx)]
        if let a = strip.animation(forKey: Self.moveKey) as? CAKeyframeAnimation {
            out += (a.values ?? []).compactMap { ($0 as? NSNumber)?.doubleValue }
        }
        if let a = strip.animation(forKey: Self.loopKey) as? CABasicAnimation {
            out += [a.fromValue, a.toValue].compactMap { ($0 as? NSNumber)?.doubleValue }
        }
        return out
    }
    var debugLoopTimeOffset: Double? { strip.animation(forKey: Self.loopKey)?.timeOffset }
    /// Ảnh chụp (test không có window: layer.render bỏ qua mask) — vẽ tay: dải gradient ở độ lệch + độ sáng hiện
    /// tại, cắt theo nét viền. Toạ độ = toạ độ view này.
    func debugDraw(in c: CGContext) {
        guard let path = outline.path, bounds.width > 0 else { return }
        c.saveGState()
        c.setAlpha(CGFloat(isAurora ? AuroraFx.borderAlpha : fade.alpha(at: CACurrentMediaTime())))
        if !isFill {
            c.addPath(path.copy(strokingWithWidth: outline.lineWidth, lineCap: .butt, lineJoin: .miter, miterLimit: 10))
            c.clip()
        }
        let st = isAurora ? AuroraFx.border : isFill ? HueFlow.fillStops() : RainbowBorder.stops()
        let cols = st.map { UIColor(rgbHex: $0.color).cgColor } as CFArray
        let locs = st.map { CGFloat($0.location) }
        if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: cols, locations: locs) {
            let x0 = isAurora ? 0 : -CGFloat(phase) * bounds.width
            let span = isAurora ? 1 : CGFloat(RainbowBorder.stripPeriods)
            c.drawLinearGradient(g, start: CGPoint(x: x0, y: 0),
                                 end: CGPoint(x: x0 + span * bounds.width, y: 0), options: [])
        }
        c.restoreGState()
    }
    #endif
}

private extension UIColor {
    convenience init(rgbHex v: UInt32) {
        self.init(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                  blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
}
