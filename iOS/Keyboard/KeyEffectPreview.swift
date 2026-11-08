// Ô xem thử "Hiệu ứng khi bấm phím" (trang chọn KeyEffectPickerView): nền theme + một phím "V" + overlay hiệu ứng
// THẬT (KeyEffectOverlay). File riêng (không nằm trong App/) để VietTelexKeyboardTests chạy được
// KeyEffectPreviewTests trên đúng view này. Android: KeyEffectPreviewView trong KeyEffectPage.kt.
//
// Lỗi 08/11/2026 (Phil, iPhone): chạm ô Laser / Glitch / Từ khoá / Chữ bay / Hạt cát / Biển / Token AI / Sàn nhảy LED
// không thấy gì. Gốc: SwiftUI gọi updateUIView TRƯỚC khi ô có kích thước ⇒ overlay gắn với khung 0×0 và không bao giờ
// được đặt lại khung (bàn phím thật gọi match mỗi lần layout, ô xem thử thì không). Các kiểu cắt theo khung
// (KeyEffectOverlay.clipped + dải dưới phím + Nháy sáng) bị cắt sạch; kiểu cũ (tim, cánh hoa…) không cắt nên vẫn thấy.
// Sửa: overlay theo khung ô ở MỌI lần layout + trước mỗi lần phát.
//
// Đầu vào giả (KeyEffectPreviewScript): bàn phím thật cấp chữ vừa ra, từ vừa chốt, khung phím cách, đích thanh gợi ý…
// Ô xem thử cấp TẤT CẢ mỗi lần chạm — mỗi hàm queue / closure tự bỏ qua khi không phải kiểu của nó, nên kiểu mới chỉ
// cần thêm đầu vào của mình vào kịch bản (hoặc không cần gì nếu chỉ dựa vào khung phím).
import UIKit

/// Kịch bản một lần chạm ô xem thử (`tap` = số lần đã chạm, từ 1). Hàm thuần — test và Android đọc cùng ý nghĩa.
enum KeyEffectPreviewScript {
    /// Emoji theo chữ: như vừa gõ "haha" + dấu cách.
    static let emoji = "😂"
    /// Chữ bay / Token AI: chữ vừa ra.
    static let glyph = "ế"
    /// Dấu thanh: như vừa bỏ dấu sắc.
    static let tone: ToneFx = .sac
    /// Từ khoá: lần lẻ "tết" (pháo + lì xì), lần chẵn "yêu" (tim) — chạm lại để thấy cả hai.
    static func keyword(tap: Int) -> KeywordKind { tap % 2 == 1 ? .tet : .love }
    /// Số phím của một "tràng gõ nhanh" (Lửa combo / Rung combo / Biển / Sàn nhảy LED: mức cao nhất).
    static func burst(_ e: KeyEffect) -> Int {
        switch e {
        case .combo, .shake, .sea, .dancefloor: return ComboMeter.thresholds[2]
        case .reps: return RepsFx.perSet      // Rep: đủ một hiệp ⇒ huy hiệu SET 1 ✓ + nhãn "+1 rep 💪" (gõ dồn)
        default: return 1
        }
    }
    /// Sàn nhảy LED: lần chạm chẵn = một nhịp phím cách (flash nền, cổng ≤ 3 lần / giây vẫn áp).
    static func beat(_ e: KeyEffect, tap: Int) -> Bool { e == .dancefloor && tap % 2 == 0 }
    /// Rep: lần chạm lẻ như vừa gõ "gym" + dấu cách ⇒ BEAST MODE.
    static func beastMode(tap: Int) -> Bool { tap % 2 == 1 }
    /// Phím giả quanh phím V (Sàn nhảy LED thắp phím hàng xóm).
    static func ghostKeys(_ e: KeyEffect) -> Bool { e == .dancefloor }
    /// "Phím cách" giả: dải thấp ở góc dưới trái ô (Laser bắn từ đây lên phím V).
    static func spaceBar(in b: CGRect) -> CGRect {
        CGRect(x: b.minX + 6, y: b.maxY - 10, width: max(b.width * 0.3 - 6, 1), height: 8)
    }
    /// "Thanh gợi ý" giả: giữa mép trên ô (Token AI bay vào đây).
    static func tokenTarget(in b: CGRect) -> CGPoint { CGPoint(x: b.midX, y: b.minY + 10) }
}

/// Ô xem thử: một phím "V" trên nền theme + overlay hiệu ứng thật.
final class KeyEffectPreviewView: UIView {
    static let keySize = CGSize(width: 34, height: 42)
    private let key = UIView()
    private let label = UILabel()
    /// Sàn nhảy LED: phím hàng xóm giả + lớp flash nền (như BeatFlashView của bàn phím).
    private var ghosts: [UIView] = []
    private var beat: BeatFlashView?
    private(set) var overlay: KeyEffectOverlay?
    private var effect: KeyEffect = .none
    private var lastPlay = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        key.layer.cornerRadius = 6
        key.isUserInteractionEnabled = false
        label.text = "V"
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 20)
        key.addSubview(label)
        addSubview(key)
        isUserInteractionEnabled = false
    }
    required init?(coder: NSCoder) { fatalError() }

    var keyFrame: CGRect { key.frame }

    func update(effect e: KeyEffect, palette: KeyboardPalette, play: Int) {
        effect = e
        backgroundColor = palette.background?.ui ?? (palette.isDark ? UIColor(white: 0.16, alpha: 1)
                                                                    : UIColor(red: 0.82, green: 0.84, blue: 0.87, alpha: 1))
        key.backgroundColor = palette.keyFill.ui
        label.textColor = palette.keyInk.ui
        configureGhosts(e, fill: palette.keyFill.ui)
        configureBeat(e)
        // Matrix / Mực loang / Sóng nước: dưới phím mẫu (như bàn phím thật).
        overlay = KeyEffectOverlay.install(e, color: palette.accent.alpha(1).ui, keyFill: palette.keyFill.ui,
                                           dark: palette.isDark, in: self, keys: key, existing: overlay)
        // Đầu vào giả — chỉ kiểu cần mới đọc (closure đọc khung lúc bắn ⇒ đúng cả khi ô đổi cỡ).
        overlay?.laserOrigin = { [weak self] in self.map { KeyEffectPreviewScript.spaceBar(in: $0.bounds) } }
        overlay?.tokenTarget = { [weak self] in self.map { KeyEffectPreviewScript.tokenTarget(in: $0.bounds) } }
        overlay?.flashGate = beat?.gate
        syncSpace()
        if play != lastPlay {
            lastPlay = play
            self.play(tap: play)
        }
    }

    /// Một lần xem thử: cấp mọi đầu vào giả rồi "bấm" phím V (vẽ ngay — ô xem thử không chèn chữ nên không cần đợi).
    func play(tap: Int) {
        layoutIfNeeded()
        syncSpace()
        guard let o = overlay, bounds.width > 0, bounds.height > 0 else { return }
        let k = key.frame
        if effect == .plasma {   // tia nối hai phím xa nhau
            o.emit(key: CGRect(x: bounds.width * 0.12, y: 12, width: 20, height: 20)); o.flush()
            o.emit(key: CGRect(x: bounds.width * 0.78, y: 18, width: 20, height: 20)); o.flush()
        }
        for _ in 1..<max(KeyEffectPreviewScript.burst(effect), 1) { o.emit(key: k); o.flush() }
        o.queueEmoji(KeyEffectPreviewScript.emoji)
        o.queueTone(KeyEffectPreviewScript.tone)
        o.queueKeyword(KeyEffectPreviewScript.keyword(tap: tap))
        o.queueLetter(KeyEffectPreviewScript.glyph)
        o.queueToken(KeyEffectPreviewScript.glyph)
        if KeyEffectPreviewScript.beastMode(tap: tap) { o.queueBeastMode() }
        o.emit(key: k)
        o.flush()
        if KeyEffectPreviewScript.beat(effect, tap: tap) { beat?.kick() }
    }

    /// Overlay + lớp flash trùng khung ô (gắn lúc ô còn 0×0 ⇒ phải đặt lại khi ô có cỡ).
    private func syncSpace() {
        if let o = overlay { KeyEffectOverlay.match(o, to: self) }
        beat?.shareCoordinateSpace(with: self)
    }

    private func configureGhosts(_ e: KeyEffect, fill: UIColor) {
        let on = KeyEffectPreviewScript.ghostKeys(e)
        if on && ghosts.isEmpty {
            ghosts = (0..<5).map { _ in
                let g = UIView()
                g.layer.cornerRadius = 6
                g.isUserInteractionEnabled = false
                insertSubview(g, belowSubview: key)
                return g
            }
            setNeedsLayout()
        }
        for g in ghosts { g.isHidden = !on; g.backgroundColor = fill.withAlphaComponent(0.55) }
    }

    private func configureBeat(_ e: KeyEffect) {
        guard e == .dancefloor else {
            beat?.halt(); beat?.removeFromSuperview(); beat = nil
            return
        }
        let v = beat ?? BeatFlashView()
        if v.superview !== self { insertSubview(v, at: 0) }
        beat = v
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = Self.keySize.width, h = Self.keySize.height
        key.frame = CGRect(x: (bounds.width - w) / 2, y: bounds.height - h - 8, width: w, height: h)
        label.frame = key.bounds
        // Phím hàng xóm theo đúng bước lưới của Sàn nhảy LED: trái / phải cùng hàng + ba phím hàng trên.
        let cells = [(-1, 0), (1, 0), (-1, -1), (0, -1), (1, -1)]
        let u = CGFloat(DanceFloor.unit(w: Double(w), h: Double(h)))
        for (g, (i, j)) in zip(ghosts, cells) {
            let c = DanceFloor.center(i, j, cx: Double(key.frame.midX), cy: Double(key.frame.midY), w: Double(w), h: Double(h))
            let gw = i == 0 ? w : u
            g.frame = CGRect(x: c.x - Double(gw) / 2, y: c.y - Double(h) / 2, width: Double(gw), height: Double(h))
        }
        syncSpace()
    }
}
