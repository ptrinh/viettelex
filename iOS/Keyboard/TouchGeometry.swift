// TouchGeometry — điểm chọn phím từ điểm chạm (pure, test được, 25/09/2026).
import CoreGraphics

enum TouchGeometry {
    /// Tâm vùng da chạm nằm THẤP hơn điểm mắt nhắm → gõ nhanh hay trượt xuống hàng
    /// dưới (h→b, i→j — screenshot 25/09/2026). Như stock, dời điểm chọn phím lên.
    static let yOffset: CGFloat = 4
    static func keySelectionPoint(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x, y: p.y - yOffset)
    }
    /// Như trên nhưng không đẩy điểm lên QUÁ đỉnh vùng phím `top`: chạm sát mép trên hàng
    /// đầu (khe trên q…p) trước đây bị dời ra ngoài vùng phím → router bỏ → mất phím.
    static func keySelectionPoint(_ p: CGPoint, top: CGFloat) -> CGPoint {
        CGPoint(x: p.x, y: max(p.y - yOffset, min(p.y, top)))
    }
}

/// Ưu tiên phím ở MÉP CHUNG (pure, Phil 06/10/2026 — song sinh Android HitBias.kt, sửa
/// cả hai). Hình phím KHÔNG đổi; chỉ đường chia vùng chạm giữa space và "," / "." kề dời
/// vào phía phím dấu câu một dải = `band` × bề rộng phím dấu câu — như stock iOS (hàng đáy
/// [123][😊][space][,][↵] hay chạm nhầm ","). Gõ cuộn (chạm ngay sau một chữ) ⇒ dải rộng
/// hơn. Dải luôn < 0.5 ⇒ TÂM "," vẫn là của nó.
///
/// ĐÃ BỎ (10/10/2026, bug tester 1.2.6/1.2.7 "bấm ⌫ hay thành chữ m hoặc l"): nhánh "phím
/// chữ thắng mép ⇧ / ⌫" — m lấn 20 % (gõ nhanh 35 %) mép trái ⌫, l lấn 20–35 % ĐỈNH ⌫ và
/// trọn khe giữa hai hàng. Phím chức năng giờ có vùng chạm ổn định (SpecialKeyGutter).
enum KeyHitBias {
    /// Phần "," / "." thuộc về space (tỉ lệ bề rộng phím dấu câu).
    static let spaceBand: CGFloat = 0.30
    /// … khi "," chạm trong `spaceRollWindow` sau một chữ (đang gõ dở từ ⇒ hay là space).
    static let spaceBandRolling: CGFloat = 0.40
    static let spaceRollWindow: TimeInterval = 0.15
    /// Hai phím coi là KỀ khi khe giữa chúng ≤ chừng này (pt/dp).
    static let maxGap: CGFloat = 16

    /// `sinceLetter` = giây từ lần chạm chữ gần nhất (nil = chưa có).
    static func spaceBand(sinceLetter: TimeInterval?) -> CGFloat {
        if let t = sinceLetter, t >= 0, t < spaceRollWindow { return spaceBandRolling }
        return spaceBand
    }

    /// `p` (đang thuộc phím thua `loser`, hoặc nằm trong khe) có rơi vào dải của phím thắng
    /// `winner` kề bên CÙNG HÀNG không — dải tính từ mép `loser` phía `winner`. Không kề ⇒ false.
    static func intrudes(_ p: CGPoint, loser l: CGRect, winner w: CGRect, band: CGFloat,
                         maxGap: CGFloat = maxGap) -> Bool {
        let vOverlap = min(l.maxY, w.maxY) - max(l.minY, w.minY)
        guard vOverlap > 0.5 * min(l.height, w.height) else { return false }
        if w.maxX <= l.minX + 0.5 {                            // winner bên trái
            guard l.minX - w.maxX <= maxGap else { return false }
            return p.x >= w.maxX && p.x < l.minX + band * l.width
        }
        if w.minX >= l.maxX - 0.5 {                            // winner bên phải
            guard w.minX - l.maxX <= maxGap else { return false }
            return p.x <= w.minX && p.x > l.maxX - band * l.width
        }
        return false
    }
}

/// Phím chức năng (⇧, ⌫, return, space…) ở plane chữ có vùng chạm ỔN ĐỊNH (pure, 10/10/2026 —
/// song sinh Android KeyLayout.gutterOwner). Bug tester 1.2.6/1.2.7: "bấm ⌫ hay thành m / l".
/// Quy tắc (như stock iOS):
///  • chạm trong hình phím chức năng ⇒ chính nó, KHÔNG phím chữ nào lấn (không dải ưu tiên,
///    không gõ cuộn, không mô hình ngôn ngữ — TouchTarget chỉ chọn giữa các phím chữ);
///  • khe CÙNG HÀNG cạnh phím chức năng (khe m↔⌫ rộng 12, z↔⇧, mép màn hình) thuộc phím
///    chức năng, trừ `letterReach` (= nửa khe 6pt giữa hai phím chữ) sát mép phím chữ;
///  • khe giữa hai hàng (l trên ⌫): phím chức năng giữ `rowReach` (5.5pt ≈ nửa khe 10, như
///    vùng nở UIButton trước 1.2.6) — tính ở đây vì bàn tách đôi vùng nở bị stack nửa hàng
///    cắt mất (hit-test UIKit không xuống tới nút) ⇒ l ăn trọn khe trên ⌫.
enum SpecialKeyGutter {
    /// Phím chữ giữ chừng này ngoài mép nó trong khe cùng hàng (nửa khe chữ↔chữ).
    static let letterReach: CGFloat = 3
    /// Khe xa hơn chừng này (pt) tính từ phím chức năng ⇒ không thuộc nó.
    static let maxGap: CGFloat = 16
    /// Phần khe trên / dưới (giữa hai hàng) thuộc phím chức năng, trong khoảng x của nó.
    static let rowReach: CGFloat = 5.5

    /// Chỉ số phím chức năng trong `specials` sở hữu `p` (nil = không phím nào — để router
    /// gần-nhất quyết). `letters`: hình phím chữ (cùng hệ toạ độ). `p` = điểm chạm THÔ.
    static func owner(_ p: CGPoint, specials: [CGRect], letters: [CGRect]) -> Int? {
        if letters.contains(where: { $0.contains(p) }) { return nil }      // lõi phím chữ
        var best: (Int, CGFloat)?
        for (i, s) in specials.enumerated() {
            let d: CGFloat
            if s.contains(p) {
                d = 0
            } else if p.x >= s.minX, p.x <= s.maxX {                       // khe trên / dưới
                d = max(s.minY - p.y, p.y - s.maxY)
                guard d <= rowReach else { continue }
            } else {
                guard p.y >= s.minY, p.y <= s.maxY else { continue }      // khe cùng hàng
                d = max(s.minX - p.x, p.x - s.maxX)
                guard d > 0, d <= maxGap else { continue }
                // Sát mép một phím chữ cùng hàng (≤ letterReach) ⇒ phần của phím chữ.
                if letters.contains(where: {
                    p.y >= $0.minY && p.y <= $0.maxY && $0.insetBy(dx: -letterReach, dy: 0).contains(p)
                }) { return nil }
            }
            if best == nil || d < best!.1 { best = (i, d) }
        }
        return best?.0
    }
}

import UIKit

extension UIScrollView {
    /// iOS 26+ tự vẽ "scroll edge effect" (dải mờ + vạch cứng) ở mép view cuộn nằm
    /// dưới một "bar" — trong bàn phím nó coi thanh gợi ý là bar và phủ dải ~30pt lên
    /// hàng emoji / mẫu câu đầu (Telegram, 25/09/2026). Bàn phím không cần hiệu ứng này.
    func disableKeyboardEdgeEffects() {
        if #available(iOS 26.0, *) {
            topEdgeEffect.isHidden = true
            bottomEdgeEffect.isHidden = true
            leftEdgeEffect.isHidden = true
            rightEdgeEffect.isHidden = true
        }
    }
}
