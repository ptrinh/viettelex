// "Mắt AI" — nhân vật Bạn đồng hành thứ 13 (BuddyCharacter.ai, Plus, 11/2026): quả cầu năng lượng có mống mắt +
// đồng tử nằm ở ô nhân vật của thanh gợi ý (cùng công tắc / "Vị trí & cỡ" với mọi nhân vật). Song sinh android
// AIEye.kt (pure, cùng số) + app/.../ime/AIEyeView.kt.
//
//  • Đồng tử NHÌN về phím vừa bấm (hướng tâm mắt → tâm phím, kẹp trong mống mắt — `AIEye.pupilOffset`).
//  • Gõ nhanh (mức ComboMeter, chung Lửa combo) ⇒ đồng tử co lại + quầng sáng mạnh lên.
//  • Nghỉ `idleAfter` (2 s) ⇒ "thở" chậm (quầng sáng phập phồng) đúng `breathCycles` nhịp rồi lim dim (mí khép nửa) và
//    ĐỨNG YÊN — không hoạt ảnh vô hạn, không hẹn giờ lặp: nghỉ lâu = 0 animation, 0 timer.
//  • Chớp mắt chỉ khi đang gõ (mỗi `blinkEvery` phím của chuỗi gõ hiện tại) — không có đồng hồ chớp tự chạy.
//  • Token AI (KeyEffects.swift TokenStream) bay vào tâm mắt khi cả hai cùng bật.
//
// Luật hiệu năng: không chọn ⇒ KeyboardView không tạo view (aiEye == nil). Chọn: mỗi phím chỉ đổi vài thuộc tính layer
// (Core Animation chạy trên render server) + hẹn TỐI ĐA một lượt kiểm nghỉ. Chỉ vector + gradient (không ảnh).
// Nguồn điện thấp ⇒ chỉ đồng tử nhìn theo (không thở / không chớp / không hoạt ảnh).
import UIKit

/// Hằng số + hàm thuần dùng chung Android (AIEye.kt — test số chung).
enum AIEye {
    /// Bán kính (tỉ lệ cạnh ngắn của khung vẽ): quả cầu, mống mắt, đồng tử; lề an toàn đồng tử ↔ mép mống mắt.
    static let orb = 0.42, iris = 0.25, pupil = 0.10, margin = 0.02
    /// Khoảng cách (pt / dp) tới phím mà đồng tử chạm mép mống mắt — gần hơn thì lệch ít hơn (mắt "nhìn gần").
    static let gaze = 120.0
    /// Gõ nhanh: đồng tử co (tỉ lệ) + quầng sáng (độ đậm) theo mức combo 0…3.
    static let pupilScales: [Double] = [1.0, 0.86, 0.74, 0.62]
    static let glows: [Double] = [0.6, 0.75, 0.88, 1.0]
    /// Nghỉ: quầng sáng nền + biên độ thở.
    static let restGlow = 0.5, breathAmp = 0.35
    /// Nghỉ chừng này (giây) ⇒ thở `breathCycles` nhịp, mỗi nhịp `breathPeriod` giây, rồi lim dim.
    static let idleAfter = 2.0, breathPeriod = 1.6, breathCycles = 3
    static var breathEnd: Double { idleAfter + breathPeriod * Double(breathCycles) }
    /// Độ mở mí: mở / lim dim / chớp.
    static let openLid = 1.0, restLid = 0.5, blinkLid = 0.08
    static let blinkTime = 0.16
    /// Chớp mỗi chừng này phím của chuỗi gõ hiện tại.
    static let blinkEvery = 9
    /// Thời gian đồng tử / quầng sáng / mí chuyển (giây).
    static let lookTime = 0.12, lidTime = 0.35
    /// Màu (RGB): quầng (tím → lam), cầu (tâm → mép), mống mắt (sáng → mép), đồng tử, vành, mí.
    static let haloInner: UInt32 = 0xA855F7, haloOuter: UInt32 = 0x22D3EE
    static let orbColors: [UInt32] = [0x3B2A7A, 0x151A3A, 0x070A18]
    static let irisColors: [UInt32] = [0xA5F3FC, 0x22D3EE, 0x7C3AED]
    static let pupilColor: UInt32 = 0x0B1020, ringColor: UInt32 = 0x67E8F9, lidColor: UInt32 = 0x0A0E22

    /// Cạnh khung vẽ cỡ gốc = cao strip × `slotSize` (Phil 08/11: mắt cạnh = strip sát mép trên bàn phím ⇒ thu ~14 %
    /// cho quầng sáng có khoảng thở trên / dưới).
    static let slotSize = 0.86

    /// Khung cỡ gốc (TRƯỚC "Vị trí & cỡ") trong strip cao `strip`, dòng chữ gợi ý có tâm dọc `rowMid` (gốc = đỉnh
    /// strip): cạnh = round(strip × slotSize) nhưng không quá 2 × khoảng từ tâm chữ tới mép gần nhất (strip bị host bóp ⇒
    /// mắt nhỏ lại thay vì lệch tâm), tối thiểu nửa strip; TÂM DỌC = rowMid (thẳng hàng chữ gợi ý); kẹp trong [0, strip]
    /// ⇒ quầng sáng (cả khung) không vượt mép trên, không đè phím. Android AIEye.slot cùng số.
    static func slot(strip: Double, rowMid: Double) -> (top: Double, side: Double) {
        let fit = (2 * Swift.min(rowMid, strip - rowMid)).rounded(.down)
        let s = Swift.max((strip * minSlot).rounded(), Swift.min((strip * slotSize).rounded(), fit))
        return (Swift.max(0, Swift.min(rowMid - s / 2, strip - s)), s)
    }
    /// Cạnh tối thiểu (tỉ lệ strip) khi dòng chữ sát mép.
    static let minSlot = 0.5

    enum Phase: Equatable { case active, breathing, resting }

    /// Đồng tử lệch tối đa (cùng đơn vị với `side`): mép đồng tử luôn trong mống mắt, chừa `margin`.
    static func maxOffset(side: Double) -> Double { Swift.max(0, (iris - pupil - margin) * side) }

    /// Lệch của đồng tử khi mắt ở `eye` nhìn `target` (cùng hệ toạ độ): đúng HƯỚNG tới phím, độ dài =
    /// `radius` × min(1, khoảng cách / gaze) ⇒ không bao giờ quá `radius`. Trùng tâm ⇒ (0, 0).
    static func pupilOffset(eye: (x: Double, y: Double), target: (x: Double, y: Double), radius: Double,
                            gaze: Double = gaze) -> (dx: Double, dy: Double) {
        let dx = target.x - eye.x, dy = target.y - eye.y
        let d = hypot(dx, dy)
        guard d > 1e-9, radius > 0 else { return (0, 0) }
        let k = radius * Swift.min(1, d / Swift.max(gaze, 1e-9)) / d
        return (dx * k, dy * k)
    }

    static func level(_ lv: Int) -> Int { Swift.min(Swift.max(lv, 0), pupilScales.count - 1) }
    static func pupilScale(level lv: Int) -> Double { pupilScales[level(lv)] }
    static func glow(level lv: Int) -> Double { glows[level(lv)] }

    /// Trạng thái sau `dt` giây kể từ phím cuối (chưa gõ = vô cùng ⇒ lim dim).
    static func phase(sinceLastPress dt: Double) -> Phase {
        if dt < idleAfter { return .active }
        return dt < breathEnd ? .breathing : .resting
    }
    /// Còn bao lâu (giây) tới lần đổi trạng thái kế; lim dim ⇒ nil (không hẹn gì nữa).
    static func nextDeadline(sinceLastPress dt: Double) -> Double? {
        switch phase(sinceLastPress: dt) {
        case .active: return idleAfter - dt
        case .breathing: return breathEnd - dt
        case .resting: return nil
        }
    }
    /// Độ đậm quầng khi đang thở, `s` giây kể từ lúc bắt đầu thở: rest → rest + amp → rest mỗi nhịp; ngoài khoảng ⇒ rest.
    static func breathGlow(_ s: Double) -> Double {
        guard s > 0, s < breathPeriod * Double(breathCycles) else { return restGlow }
        return restGlow + breathAmp * (1 - cos(2 * .pi * s / breathPeriod)) / 2
    }
    static func openness(_ p: Phase) -> Double { p == .resting ? restLid : openLid }
    /// Mép dưới mí (tính từ đỉnh quả cầu, cùng đơn vị bán kính `r`) với độ mở `o`: mở hẳn = 0 (mí khuất trên), lim dim =
    /// r (che nửa trên), khép = 2r.
    static func lidEdge(openness o: Double, radius r: Double) -> Double { (1 - Swift.min(Swift.max(o, 0), 1)) * 2 * r }
    static func blinks(press n: Int) -> Bool { n > 0 && n % blinkEvery == 0 }
}

/// Đồng hồ thuần của mắt: phím cuối + số phím của chuỗi gõ hiện tại (lim dim ⇒ chuỗi mới). Android AIEyeClock y hệt.
struct AIEyeClock {
    private(set) var lastPress = -Double.greatestFiniteMagnitude
    private(set) var streak = 0

    func phase(at t: Double) -> AIEye.Phase { AIEye.phase(sinceLastPress: t - lastPress) }
    /// Giờ tuyệt đối của lần đổi trạng thái kế (nil = đã lim dim, không hẹn gì).
    func nextDeadline(at t: Double) -> Double? { AIEye.nextDeadline(sinceLastPress: t - lastPress).map { t + $0 } }
    /// Một phím lúc `t` — trả số thứ tự phím trong chuỗi gõ.
    mutating func press(at t: Double) -> Int {
        if phase(at: t) == .resting { streak = 0 }
        lastPress = t
        streak += 1
        return streak
    }
    mutating func reset() { lastPress = -.greatestFiniteMagnitude; streak = 0 }
}

/// View Mắt AI (không nhận chạm — chạm ô nhân vật do KeyboardView bắt, như Bạn đồng hành).
final class AIEyeView: UIView {
    var lowPower: Bool { didSet { if lowPower && !oldValue { halt() } } }
    private let halo = CAGradientLayer()
    private let orb = CAGradientLayer()
    private let irisLayer = CAGradientLayer()
    private let pupilGroup = CALayer()
    private let pupilDot = CAShapeLayer()
    private let shine = CAShapeLayer()
    private let lid = CAShapeLayer()
    private let lidLine = CAShapeLayer()
    private let ring = CAShapeLayer()
    private var clock = AIEyeClock()
    private var combo = ComboMeter()
    private var tickScheduled = false
    private var gen = 0
    private var breathing = false
    private var laidOut: CGSize = .zero
    private var side: CGFloat = 0
    private var radius: CGFloat = 0
    private static let breathKey = "ai.breath", blinkKey = "ai.blink"

    init(lowPower: Bool) {
        self.lowPower = lowPower
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        backgroundColor = .clear
        isOpaque = false
        let c = { (v: UInt32, a: CGFloat) in UIColor(eyeRGB: v).withAlphaComponent(a).cgColor }
        halo.type = .radial
        halo.colors = [c(AIEye.haloInner, 0.85), c(AIEye.haloOuter, 0.35), c(AIEye.haloOuter, 0)]
        halo.locations = [0, 0.55, 1]
        halo.startPoint = CGPoint(x: 0.5, y: 0.5)
        halo.endPoint = CGPoint(x: 1, y: 1)
        orb.type = .radial
        orb.colors = AIEye.orbColors.map { c($0, 1) }
        orb.locations = [0, 0.6, 1]
        orb.startPoint = CGPoint(x: 0.42, y: 0.38)
        orb.endPoint = CGPoint(x: 1, y: 1)
        orb.masksToBounds = true
        irisLayer.type = .radial
        irisLayer.colors = AIEye.irisColors.map { c($0, 1) }
        irisLayer.locations = [0, 0.45, 1]
        irisLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        irisLayer.endPoint = CGPoint(x: 1, y: 1)
        irisLayer.masksToBounds = true
        pupilDot.fillColor = c(AIEye.pupilColor, 1)
        shine.fillColor = UIColor.white.withAlphaComponent(0.9).cgColor
        lid.fillColor = c(AIEye.lidColor, 0.97)
        lid.anchorPoint = CGPoint(x: 0.5, y: 1)
        lidLine.strokeColor = c(AIEye.ringColor, 0.75)
        lidLine.fillColor = nil
        lidLine.lineWidth = 1
        ring.fillColor = nil
        ring.strokeColor = c(AIEye.ringColor, 0.85)
        ring.lineWidth = 1.2
        pupilGroup.addSublayer(pupilDot)
        pupilGroup.addSublayer(shine)
        lid.addSublayer(lidLine)
        orb.addSublayer(irisLayer)
        orb.addSublayer(pupilGroup)
        orb.addSublayer(lid)
        layer.addSublayer(halo)
        layer.addSublayer(orb)
        layer.addSublayer(ring)
        halo.opacity = Float(AIEye.restGlow)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }

    /// Tâm quả cầu theo toạ độ view cha (KeyboardView) — đích bay của Token AI.
    var eyeCenter: CGPoint { CGPoint(x: frame.midX, y: frame.midY) }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != laidOut, bounds.width > 0, bounds.height > 0 else { return }
        laidOut = bounds.size
        side = min(bounds.width, bounds.height)
        radius = side * CGFloat(AIEye.orb)
        let s = side, r = radius
        CATransaction.begin(); CATransaction.setDisableActions(true)
        halo.frame = CGRect(x: bounds.midX - s / 2, y: bounds.midY - s / 2, width: s, height: s)
        orb.frame = CGRect(x: bounds.midX - r, y: bounds.midY - r, width: 2 * r, height: 2 * r)
        orb.cornerRadius = r
        let ri = s * CGFloat(AIEye.iris)
        irisLayer.frame = CGRect(x: r - ri, y: r - ri, width: 2 * ri, height: 2 * ri)
        irisLayer.cornerRadius = ri
        let rp = s * CGFloat(AIEye.pupil)
        pupilGroup.bounds = CGRect(x: -rp, y: -rp, width: 2 * rp, height: 2 * rp)
        pupilGroup.position = CGPoint(x: r, y: r)
        pupilDot.path = CGPath(ellipseIn: CGRect(x: -rp, y: -rp, width: 2 * rp, height: 2 * rp), transform: nil)
        let hr = rp * 0.32
        shine.path = CGPath(ellipseIn: CGRect(x: -rp * 0.42 - hr, y: -rp * 0.42 - hr, width: 2 * hr, height: 2 * hr), transform: nil)
        lid.bounds = CGRect(x: 0, y: 0, width: 2 * r, height: 2 * r)
        lid.path = CGPath(rect: lid.bounds, transform: nil)
        let line = CGMutablePath()
        line.move(to: CGPoint(x: 0, y: 2 * r)); line.addLine(to: CGPoint(x: 2 * r, y: 2 * r))
        lidLine.path = line
        ring.path = CGPath(ellipseIn: CGRect(x: bounds.midX - r + 0.6, y: bounds.midY - r + 0.6, width: 2 * r - 1.2, height: 2 * r - 1.2),
                           transform: nil)
        applyLid(AIEye.openness(clock.phase(at: CACurrentMediaTime())))
        CATransaction.commit()
    }

    private func applyLid(_ o: Double) {
        lid.position = CGPoint(x: radius, y: CGFloat(AIEye.lidEdge(openness: o, radius: Double(radius))))
    }

    /// Phím vừa bấm, tâm phím `p` theo toạ độ view CHA (KeyboardView). Chỉ đổi vài thuộc tính layer + hẹn một lượt kiểm.
    func keyPressed(at p: CGPoint) {
        let now = CACurrentMediaTime()
        let wasResting = clock.phase(at: now) == .resting
        let n = clock.press(at: now)
        let lv = combo.press(at: now)
        guard side > 0 else { return }
        let q = superview.map { convert(p, from: $0) } ?? p
        let c = CGPoint(x: bounds.midX, y: bounds.midY)
        let off = AIEye.pupilOffset(eye: (Double(c.x), Double(c.y)), target: (Double(q.x), Double(q.y)),
                                    radius: AIEye.maxOffset(side: Double(side)))
        CATransaction.begin()
        CATransaction.setDisableActions(lowPower)
        CATransaction.setAnimationDuration(AIEye.lookTime)
        pupilGroup.position = CGPoint(x: radius + CGFloat(off.dx), y: radius + CGFloat(off.dy))
        let k = CGFloat(AIEye.pupilScale(level: lv))
        pupilGroup.setAffineTransform(CGAffineTransform(scaleX: k, y: k))
        if breathing { halo.removeAnimation(forKey: Self.breathKey); breathing = false }
        halo.opacity = Float(AIEye.glow(level: lv))
        if wasResting {
            CATransaction.setAnimationDuration(lowPower ? 0 : AIEye.lookTime)
            applyLid(AIEye.openLid)
        }
        CATransaction.commit()
        if !lowPower && AIEye.blinks(press: n) { blink() }
        if !lowPower { scheduleTick(after: AIEye.idleAfter) } else { scheduleTick(after: AIEye.breathEnd) }
    }

    /// ⌫: nhìn xuống phím xoá như mọi phím (KeyboardView gửi tâm phím ⌫).
    func deletePressed(at p: CGPoint) { keyPressed(at: p) }

    /// Chạm ô nhân vật: chớp mắt một cái (mở mắt nếu đang lim dim).
    func tickle() {
        guard !lowPower else { return }
        keyPressed(at: superview.map { $0.convert(CGPoint(x: bounds.midX, y: bounds.midY), from: self) } ?? .zero)
        blink()
    }

    private func blink() {
        guard radius > 0 else { return }
        let open = CGFloat(AIEye.lidEdge(openness: AIEye.openLid, radius: Double(radius)))
        let shut = CGFloat(AIEye.lidEdge(openness: AIEye.blinkLid, radius: Double(radius)))
        let a = CAKeyframeAnimation(keyPath: "position.y")
        a.values = [open, shut, open]
        a.keyTimes = [0, 0.45, 1]
        a.duration = AIEye.blinkTime
        lid.add(a, forKey: Self.blinkKey)   // tự gỡ khi xong
    }

    /// MỘT hẹn giờ (không lặp): khi tới mốc, xem trạng thái thuần rồi hẹn mốc kế — lim dim thì thôi hẳn.
    private func scheduleTick(after s: Double) {
        guard !tickScheduled else { return }
        tickScheduled = true
        let g = gen
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0.05, s)) { [weak self] in
            guard let self, self.gen == g else { return }
            self.tickScheduled = false
            self.tick(at: CACurrentMediaTime())
        }
    }

    private func tick(at now: Double) {
        switch clock.phase(at: now) {
        case .active:
            if let d = clock.nextDeadline(at: now) { scheduleTick(after: d - now) }
        case .breathing:
            if !breathing && !lowPower { startBreathing(at: now) }
            if let d = clock.nextDeadline(at: now) { scheduleTick(after: d - now) }
        case .resting:
            settle(animated: !lowPower)
        }
    }

    /// Thở: quầng sáng phập phồng ĐÚNG `breathCycles` nhịp (animation tự gỡ), đồng tử về giữa, nở lại.
    private func startBreathing(at now: Double) {
        breathing = true
        let left = max(0, AIEye.breathEnd - (now - clock.lastPress))
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.6)
        pupilGroup.position = CGPoint(x: radius, y: radius)
        pupilGroup.setAffineTransform(.identity)
        halo.opacity = Float(AIEye.restGlow)
        CATransaction.commit()
        let a = CAKeyframeAnimation(keyPath: "opacity")
        let steps = 16
        a.values = (0...steps).map { AIEye.breathGlow(AIEye.breathPeriod * Double($0) / Double(steps)) }
        a.keyTimes = (0...steps).map { NSNumber(value: Double($0) / Double(steps)) }
        a.duration = AIEye.breathPeriod
        // Số nhịp còn lại (tick có thể trễ vài ms ⇒ làm tròn, trần breathCycles): luôn hữu hạn.
        a.repeatCount = Float(min(Double(AIEye.breathCycles), max(1, (left / AIEye.breathPeriod).rounded())))
        halo.add(a, forKey: Self.breathKey)
    }

    /// Lim dim: mí khép nửa, quầng nền, đồng tử giữa — xong là ĐỨNG YÊN (0 animation, 0 hẹn giờ).
    private func settle(animated: Bool) {
        breathing = false
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        CATransaction.setAnimationDuration(AIEye.lidTime)
        halo.removeAnimation(forKey: Self.breathKey)
        halo.opacity = Float(AIEye.restGlow)
        pupilGroup.position = CGPoint(x: radius, y: radius)
        pupilGroup.setAffineTransform(.identity)
        applyLid(AIEye.restLid)
        CATransaction.commit()
    }

    /// Ẩn bàn phím / đổi nhân vật: dừng hẳn ở dáng lim dim, huỷ hẹn giờ.
    func halt() {
        gen += 1
        tickScheduled = false
        clock.reset()
        combo.reset()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for l in [halo, pupilGroup, lid] as [CALayer] { l.removeAllAnimations() }
        CATransaction.commit()
        settle(animated: false)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { halt() }
    }

    #if DEBUG
    var debugPhase: AIEye.Phase { clock.phase(at: CACurrentMediaTime()) }
    var debugPupilOffset: CGPoint { CGPoint(x: pupilGroup.position.x - radius, y: pupilGroup.position.y - radius) }
    var debugPupilScale: CGFloat { pupilGroup.affineTransform().a }
    var debugGlow: Float { halo.opacity }
    var debugLidEdge: CGFloat { lid.position.y }
    var debugRadius: CGFloat { radius }
    var debugMaxOffset: CGFloat { CGFloat(AIEye.maxOffset(side: Double(side))) }
    var debugTickScheduled: Bool { tickScheduled }
    var debugAnimationCount: Int {
        [halo, orb, irisLayer, pupilGroup, lid, ring].reduce(0) { $0 + ($1.animationKeys()?.count ?? 0) }
    }
    var debugBreathRepeat: Float? { (halo.animation(forKey: Self.breathKey) as? CAKeyframeAnimation)?.repeatCount }
    func debugTick(at t: Double) { tickScheduled = false; tick(at: t) }
    /// Như vừa gõ phím cuối `ago` giây trước (test thở / lim dim mà không chờ thật).
    func debugBackdate(_ ago: Double) {
        let now = CACurrentMediaTime()
        var c = AIEyeClock()
        _ = c.press(at: now - ago)
        clock = c
    }
    #endif
}

private extension UIColor {
    convenience init(eyeRGB v: UInt32) {
        self.init(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                  blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
}
