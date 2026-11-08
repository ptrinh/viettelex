// Bộ vẽ hiệu ứng riêng của các theme đủ món 11/2026 (Bóng đá, …) + CẢNH nền vẽ thủ tục (motif cảnh trong "deco").
// KeyEffectOverlay chỉ chuyển tiếp: dựng bộ vẽ khi chọn đúng kiểu, gỡ sạch khi đổi kiểu ⇒ kiểu khác 0 chi phí.
// Song sinh android/keyboard/.../ThemeFxPack.kt (cảnh: cùng hình học, test số chung).
import UIKit

/// Một bộ vẽ hiệu ứng theme. Toạ độ = toạ độ overlay (chung hệ toạ độ KeyboardView — #151).
@MainActor protocol ThemeFxRenderer: AnyObject {
    var onEvent: (() -> Void)? { get set }
    /// Phím vừa bấm (khung phím); `isReturn` = phím Enter.
    func fire(_ r: CGRect, isReturn: Bool, now: CFTimeInterval, media: CFTimeInterval)
    /// Sự kiện controller xếp sẵn (Sút!: cụm cổ vũ) — bắn ở lượt vẽ kế.
    func fireQueued(now: CFTimeInterval, media: CFTimeInterval)
    /// Ẩn bàn phím: dừng mọi thứ đang chạy (ghi bộ đếm nếu có).
    func halt()
    /// Đổi kiểu: gỡ mọi layer.
    func detach()
    func layout()
    /// App Group (Bể cá lưu bộ đếm); bộ vẽ khác bỏ qua.
    func setDefaults(_ d: UserDefaults?)
}

extension ThemeFxRenderer {
    func setDefaults(_ d: UserDefaults?) {}
}

enum ThemeFxFactory {
    /// Kiểu có bộ vẽ riêng.
    static let effects: Set<KeyEffect> = [.goal, .fishfeed]
    static func handles(_ e: KeyEffect) -> Bool { effects.contains(e) }

    @MainActor static func make(_ e: KeyEffect, host: UIView, defaults: UserDefaults?) -> ThemeFxRenderer? {
        switch e {
        case .goal: return GoalRenderer(host: host)
        case .fishfeed: return FishFeedRenderer(host: host, defaults: defaults)
        default: return nil
        }
    }
}

// MARK: - Cảnh nền

/// Motif "cảnh": vẽ TRỌN nền theme một lần mỗi cỡ (không theo khe hàng phím như motif thường): gradient + hình vector.
/// Màu `deco.color` = màu nét / điểm sáng của cảnh; gradient theo bảng cố định (sáng / tối).
enum ThemeScene {
    static let motifs: Set<KeyboardDecoration.Motif> = [.pitch, .aquarium]
    static func isScene(_ m: KeyboardDecoration.Motif) -> Bool { motifs.contains(m) }
    /// Gradient trên → dưới (0xRRGGBB); rỗng = giữ màu nền theme.
    static func gradient(_ m: KeyboardDecoration.Motif, dark: Bool) -> [UInt32] {
        switch m {
        case .aquarium: return [0x0F4C7A, 0x0B3D66, 0x062847]   // nước sâu (sáng = tối)
        default: return []
        }
    }
}

extension KeyboardDecoration {
    /// Motif cảnh (ThemeScene) — không đặt motif nhỏ vào khe hàng.
    var isScene: Bool { ThemeScene.isScene(motif) }
}

/// Lớp cảnh: dựng lại chỉ khi cỡ / motif / màu đổi; rasterize một lần, 0 việc mỗi phím.
final class ThemeSceneLayer: CALayer {
    private var sig: (KeyboardDecoration.Motif, RGBA, Bool, CGSize)?

    func update(motif m: KeyboardDecoration.Motif, color: RGBA, dark: Bool, size: CGSize) {
        if let s = sig, s.0 == m, s.1 == color, s.2 == dark, s.3 == size { return }
        sig = (m, color, dark, size)
        sublayers?.forEach { $0.removeFromSuperlayer() }
        frame = CGRect(origin: .zero, size: size)
        guard size.width > 0, size.height > 0 else { return }
        let w = Double(size.width), h = Double(size.height)
        let stops = ThemeScene.gradient(m, dark: dark)
        if stops.count >= 2 {
            let g = CAGradientLayer()
            g.frame = bounds
            g.colors = stops.map { UIColor(fx: $0).cgColor }
            g.startPoint = CGPoint(x: 0.5, y: 0); g.endPoint = CGPoint(x: 0.5, y: 1)
            addSublayer(g)
        }
        switch m {
        case .pitch: buildPitch(w, h, color)
        case .aquarium: buildAquarium(w, h, color)
        default: break
        }
    }

    private func shape(_ p: CGPath, fill: UIColor?, stroke: UIColor? = nil, width: Double = 0) -> CAShapeLayer {
        let l = CAShapeLayer()
        l.frame = bounds
        l.path = p
        l.fillColor = fill?.cgColor
        l.strokeColor = stroke?.cgColor
        l.lineWidth = CGFloat(width)
        l.lineCap = .round
        l.lineJoin = .round
        addSublayer(l)
        return l
    }

    private func buildPitch(_ w: Double, _ h: Double, _ c: RGBA) {
        let st = CGMutablePath()
        for s in PitchScene.stripes(width: w, height: h) { st.addRect(CGRect(x: s.x, y: 0, width: s.w, height: h)) }
        _ = shape(st, fill: UIColor(white: 1, alpha: PitchScene.stripeAlpha))
        let ln = CGMutablePath()
        for p in PitchScene.lines(width: w, height: h) {
            switch p {
            case let .rect(x, y, rw, rh): ln.addRect(CGRect(x: x, y: y, width: rw, height: rh))
            case let .circle(cx, cy, r): ln.addEllipse(in: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r))
            case let .line(x0, y0, x1, y1): ln.move(to: CGPoint(x: x0, y: y0)); ln.addLine(to: CGPoint(x: x1, y: y1))
            }
        }
        _ = shape(ln, fill: nil, stroke: c.ui, width: PitchScene.lineWidth)
        let spot = PitchScene.spot
        _ = shape(CGPath(ellipseIn: CGRect(x: w / 2 - spot, y: h / 2 - spot, width: 2 * spot, height: 2 * spot), transform: nil),
                  fill: c.ui)
    }

    private func buildAquarium(_ w: Double, _ h: Double, _ c: RGBA) {
        let rays = CGMutablePath()
        for q in AquariumScene.rays(width: w, height: h) {
            for (i, p) in q.enumerated() {
                if i == 0 { rays.move(to: CGPoint(x: p.0, y: p.1)) } else { rays.addLine(to: CGPoint(x: p.0, y: p.1)) }
            }
            rays.closeSubpath()
        }
        _ = shape(rays, fill: c.ui)
        let sand = CGMutablePath()
        let top = AquariumScene.sandTop(width: w, height: h)
        sand.move(to: CGPoint(x: 0, y: h))
        for p in top { sand.addLine(to: CGPoint(x: p.0, y: p.1)) }
        sand.addLine(to: CGPoint(x: w, y: h)); sand.closeSubpath()
        _ = shape(sand, fill: UIColor(fx: AquariumScene.sandColor, alpha: AquariumScene.sandAlpha))
        let weeds = CGMutablePath()
        for s in AquariumScene.weeds(width: w, height: h) {
            weeds.move(to: CGPoint(x: s.x0, y: s.y0))
            weeds.addQuadCurve(to: CGPoint(x: s.x1, y: s.y1), control: CGPoint(x: s.cx, y: s.cy))
        }
        _ = shape(weeds, fill: nil, stroke: UIColor(fx: AquariumScene.weedColor, alpha: AquariumScene.weedAlpha),
                  width: AquariumScene.weedWidth)
    }

    #if DEBUG
    var debugLayerCount: Int { sublayers?.count ?? 0 }
    #endif
}
