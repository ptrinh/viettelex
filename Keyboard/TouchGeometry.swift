// TouchGeometry — điểm chọn phím từ điểm chạm (pure, test được, 25/09/2026).
import CoreGraphics

enum TouchGeometry {
    /// Tâm vùng da chạm nằm THẤP hơn điểm mắt nhắm → gõ nhanh hay trượt xuống hàng
    /// dưới (h→b, i→j — screenshot 25/09/2026). Như stock, dời điểm chọn phím lên.
    static let yOffset: CGFloat = 4
    static func keySelectionPoint(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x, y: p.y - yOffset)
    }
}
