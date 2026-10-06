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
/// cả hai). Hình phím KHÔNG đổi; chỉ đường chia vùng chạm giữa 2 phím kề dời vào phía
/// phím "thua" một dải = `band` × bề rộng (cao) phím thua — như stock iOS:
///  • space thắng "," / "." kề bên (hàng đáy [123][😊][space][,][↵] hay chạm nhầm ",");
///  • phím chữ thắng ⇧ / ⌫ kề bên (z/a cạnh ⇧, m cạnh ⌫) — gõ nhanh hay quẹt mép ⇧.
/// Gõ cuộn (phím này chạm ngay sau một chữ) ⇒ dải rộng hơn. Dải luôn < 0.5 ⇒ TÂM phím
/// thua vẫn là của nó (chạm ⇧ / "," cố ý ở giữa phím không bao giờ bị cướp).
enum KeyHitBias {
    /// Phần "," / "." thuộc về space (tỉ lệ bề rộng phím dấu câu).
    static let spaceBand: CGFloat = 0.30
    /// … khi "," chạm trong `spaceRollWindow` sau một chữ (đang gõ dở từ ⇒ hay là space).
    static let spaceBandRolling: CGFloat = 0.40
    static let spaceRollWindow: TimeInterval = 0.15
    /// Phần ⇧ / ⌫ thuộc về phím chữ kề (tỉ lệ bề rộng — hay bề cao với hàng trên — của ⇧/⌫).
    static let letterBand: CGFloat = 0.20
    /// … khi ⇧ / ⌫ chạm trong `letterRollWindow` sau một chữ (gõ nhanh).
    static let letterBandRolling: CGFloat = 0.35
    static let letterRollWindow: TimeInterval = 0.20
    /// Hai phím coi là KỀ khi khe giữa chúng ≤ chừng này (pt/dp).
    static let maxGap: CGFloat = 16

    /// `sinceLetter` = giây từ lần chạm chữ gần nhất (nil = chưa có).
    static func spaceBand(sinceLetter: TimeInterval?) -> CGFloat {
        if let t = sinceLetter, t >= 0, t < spaceRollWindow { return spaceBandRolling }
        return spaceBand
    }
    static func letterBand(sinceLetter: TimeInterval?) -> CGFloat {
        if let t = sinceLetter, t >= 0, t < letterRollWindow { return letterBandRolling }
        return letterBand
    }

    /// `p` (đang thuộc phím thua `loser`, hoặc nằm trong khe) có rơi vào dải của phím thắng
    /// `winner` kề bên không. Kề ngang (cùng hàng): dải tính từ mép `loser` phía `winner`.
    /// `winner` ở hàng TRÊN `loser` (a trên ⇧): dải tính từ mép trên `loser`, chỉ trong
    /// khoảng x của `winner`. Không kề ⇒ false.
    static func intrudes(_ p: CGPoint, loser l: CGRect, winner w: CGRect, band: CGFloat,
                         maxGap: CGFloat = maxGap) -> Bool {
        let vOverlap = min(l.maxY, w.maxY) - max(l.minY, w.minY)
        if vOverlap > 0.5 * min(l.height, w.height) {             // cùng hàng
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
        if w.maxY <= l.minY + 0.5 {                                // winner ở hàng trên
            guard l.minY - w.maxY <= maxGap, p.x >= w.minX, p.x <= w.maxX else { return false }
            return p.y >= w.maxY && p.y < l.minY + band * l.height
        }
        return false
    }

    /// Chỉ số phím thắng đầu tiên trong `winners` mà `p` lấn vào (nil = giữ phím thua).
    static func stealer(_ p: CGPoint, loser: CGRect, winners: [CGRect], band: CGFloat) -> Int? {
        var best: (Int, CGFloat)?
        for (i, w) in winners.enumerated() where intrudes(p, loser: loser, winner: w, band: band) {
            let dx = max(w.minX - p.x, 0, p.x - w.maxX), dy = max(w.minY - p.y, 0, p.y - w.maxY)
            let d = dx * dx + dy * dy
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
