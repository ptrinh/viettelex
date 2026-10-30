// "Màu chữ gợi ý" (tester 30/10/2026: "chữ trên thanh gợi ý iOS mặc định màu xám, bản VietTelex
// trắng quá, phân tâm lúc gõ") — THUẦN, song sinh android/keyboard/.../SuggestionInk.kt.
// Khoá App Group `suggestionInk` (String): "muted" (Xám, giống bàn phím Apple — MẶC ĐỊNH) /
// "bright" (Sáng — chữ đậm màu như trước 30/10/2026). Giá trị lạ / thiếu ⇒ Xám.
// Cài đặt: Tính Năng → Giao diện → Bàn phím (cạnh "Chiều cao thanh gợi ý").
//
// Chỉ CHỮ ô gợi ý đổi; vạch ngăn, icon ☰/📋/😊, chip clipboard, thẻ Dán giữ `barInk` như cũ.
// Xám = màu `secondaryLabel` của UIKit (chữ phụ hệ thống, cùng tông ứng viên QuickType stock):
//   sáng  #3C3C43 @ 60%   (trên kính bàn phím sáng ≈ #7C7D82)
//   tối   #EBEBF5 @ 60%   (trên nền stock #202020 ≈ #9A9AA0)
// Theme màu riêng (chữ không phải đen/trắng thuần) giữ sắc chữ của theme, chỉ giảm độ đậm 60%.
// Không bao giờ nhạt quá: alpha tăng dần tới khi chữ đạt ≥ 3:1 trên nền thanh (như các nhãn
// khác — KeyboardTransparency.minLabelContrast); vẫn không đạt ⇒ dùng màu Sáng.
// Đọc lúc hiện bàn phím (applyAppearance → resolvePalette) — 0 chi phí mỗi phím.
import Foundation

enum SuggestionInk: String, CaseIterable {
    case muted, bright

    static let key = "suggestionInk"
    static let defaultValue: SuggestionInk = .muted

    static func parse(_ raw: Any?) -> SuggestionInk {
        (raw as? String).flatMap(SuggestionInk.init(rawValue:)) ?? defaultValue
    }
    static func load(_ d: UserDefaults?) -> SuggestionInk { parse(d?.object(forKey: key)) }

    /// Độ đậm chữ Xám (= alpha secondaryLabel của UIKit).
    static let mutedAlpha = 0.6
    /// Sắc secondaryLabel UIKit cho chữ đen (sáng) / trắng (tối).
    static let stockLight = RGBA(r: 60 / 255, g: 60 / 255, b: 67 / 255)
    static let stockDark = RGBA(r: 235 / 255, g: 235 / 255, b: 245 / 255)
    /// Sàn tương phản (chữ đã trộn lên nền thanh).
    static let minContrast = 3.0

    /// Màu chữ ô gợi ý. `barInk` = chữ thanh của palette (theme đã giải: sáng/tối, ảnh nền,
    /// độ trong suốt); `behind` = nền đục ước lượng sau thanh (`behindBar`).
    static func color(barInk: RGBA, behind: RGBA, mode: SuggestionInk) -> RGBA {
        guard mode == .muted else { return barInk }
        let tint = stockTint(for: barInk) ?? RGBA(r: barInk.r, g: barInk.g, b: barInk.b)
        var a = mutedAlpha
        while a < 1, RGBA.contrast(tint.alpha(a * barInk.a).over(behind), behind) < minContrast { a += 0.05 }
        let muted = tint.alpha(min(a, 1) * barInk.a)
        // Không đạt sàn kể cả đậm hết (barInk vốn kém tương phản) ⇒ giữ màu Sáng, không làm tệ hơn.
        return RGBA.contrast(muted.over(behind), behind) >= minContrast ? muted : barInk
    }

    /// Chữ đen / trắng thuần (theme Hệ thống, Kính, theme chữ trung tính) ⇒ sắc secondaryLabel stock.
    static func stockTint(for ink: RGBA) -> RGBA? {
        let eps = 0.002
        if abs(ink.r) < eps, abs(ink.g) < eps, abs(ink.b) < eps { return stockLight }
        if abs(ink.r - 1) < eps, abs(ink.g - 1) < eps, abs(ink.b - 1) < eps { return stockDark }
        return nil
    }

    /// Nền đục sau thanh gợi ý: nền theme (hoặc lớp phủ ảnh nền) trên kính bàn phím hệ thống.
    static func behindBar(_ p: KeyboardPalette, systemDark: Bool, wallpaper: Bool) -> RGBA {
        let sys = KeyboardTransparency.systemBackdrop(dark: systemDark)
        return (wallpaper ? p.wallpaperOverlay : p.background)?.over(sys) ?? sys
    }
}
