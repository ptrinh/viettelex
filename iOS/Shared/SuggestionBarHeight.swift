// "Chiều cao thanh gợi ý" (Phil 18/10/2026: bar 30pt thấp quá, chạm nhầm) — THUẦN, song sinh
// android/keyboard/.../SuggestionBarHeight.kt. Khoá App Group `suggestionBarHeight` (String):
// "low" (Thấp, 30 — bố cục cũ trước 18/10/2026) / "medium" (Vừa, 36 — MẶC ĐỊNH) / "high" (Cao, 44).
// Giá trị lạ / thiếu ⇒ Vừa. Cài đặt: Tính Năng → Giao diện → Bàn phím (cạnh "Chiều cao hàng phím").
//
// Số danh nghĩa 30/36/44 = dải thanh gợi ý người dùng thấy (đỉnh bàn phím → mép hàng phím đầu,
// tính cả khe) ở mức Thấp = bố cục cũ. Bàn phím chỉ CỘNG `delta` (0/6/14) vào strip mở:
//  • tổng chiều cao bàn phím tăng ĐÚNG `delta`; hàng phím, tắt (0) giữ nguyên;
//  • hàng nội dung bar (chữ gợi ý, chip, icon ☰/📋/😊) cao `rowHeight` = 20 + delta ⇒ vùng chạm
//    mỗi ô phủ trọn chiều cao bar (cộng phần hit nở xuống như cũ);
//  • iPhone NGANG: delta kẹp ở mức Vừa (+6) — màn ngang thấp, Cao (+14) làm bàn phím chiếm quá nhiều;
//  • cỡ chữ gợi ý nhích nhẹ theo mức (17/18/19, chip 14/15/15) — có trần;
//  • hàng nội dung canh giữa dải đỉnh bàn phím → đỉnh phím hàng đầu (`rowTop`, 29/10/2026).
// Đọc lúc hiện bàn phím (applyAppearance) — 0 chi phí mỗi phím.
import CoreGraphics
import Foundation

enum SuggestionBarHeight: String, CaseIterable {
    case low, medium, high

    static let key = "suggestionBarHeight"
    static let defaultValue: SuggestionBarHeight = .medium

    /// Chiều cao danh nghĩa (pt) — nhãn cài đặt.
    var nominal: CGFloat {
        switch self { case .low: return 30; case .medium: return 36; case .high: return 44 }
    }
    /// pt cộng thêm vào strip mở so với Thấp (bố cục cũ).
    var delta: CGFloat { nominal - SuggestionBarHeight.low.nominal }
    /// Trần delta khi iPhone xoay ngang (= mức Vừa).
    static let landscapeMaxDelta: CGFloat = 6
    func delta(landscape: Bool) -> CGFloat {
        landscape ? min(delta, Self.landscapeMaxDelta) : delta
    }

    /// Hàng nội dung bar ở mức Thấp (bố cục cũ: tâm chữ y = 10).
    static let baseRow: CGFloat = 20
    /// Hàng nội dung bar (chữ / chip / icon canh giữa hàng này).
    func rowHeight(landscape: Bool) -> CGFloat { Self.baseRow + delta(landscape: landscape) }

    /// Đỉnh (y, toạ độ bàn phím) của hàng nội dung bar — chữ gợi ý, vạch ngăn, ☰ / 📋 / 😊 đều
    /// canh giữa hàng này, nên chỉ một con số quyết định chúng thẳng hàng.
    ///
    /// Dải người dùng THẤY là thanh gợi ý chạy từ đỉnh bàn phím tới ĐỈNH PHÍM hàng đầu =
    /// `strip` + `capGap` (khe trên phím hàng đầu, RowSpec.gap ≈ 11), không phải tới mép strip.
    /// Bản cũ ghim hàng ở `topPad` (4) ⇒ tâm chữ/icon cao hơn tâm dải ~6pt (tester 29/10/2026:
    /// "chữ hơi cao lên phía trên, cả icon clipboard nữa"; đo ảnh: Vừa + hàng số, tâm nội dung
    /// y≈16.5, tâm dải 23). Giờ: canh giữa dải, nhưng không thò xuống dưới strip (vùng chạm ô
    /// gợi ý không lấn phím) và không cao hơn `topPad` (host không vẽ khung — Telegram).
    static func rowTop(strip: CGFloat, capGap: CGFloat, row: CGFloat, topPad: CGFloat) -> CGFloat {
        let centered = ((strip + max(capGap, 0) - row) / 2).rounded()
        return max(topPad, min(centered, strip - row))
    }

    /// Cỡ chữ ô gợi ý / chip theo mức (trần 19 / 15).
    func slotFontSize(landscape: Bool) -> CGFloat {
        switch delta(landscape: landscape) { case ..<1: return 17; case ..<10: return 18; default: return 19 }
    }
    func chipFontSize(landscape: Bool) -> CGFloat { delta(landscape: landscape) < 1 ? 14 : 15 }

    /// Giá trị lạ / thiếu ⇒ mặc định (Vừa).
    static func parse(_ raw: Any?) -> SuggestionBarHeight {
        (raw as? String).flatMap(SuggestionBarHeight.init(rawValue:)) ?? defaultValue
    }
    static func load(_ d: UserDefaults?) -> SuggestionBarHeight { parse(d?.object(forKey: key)) }
}
