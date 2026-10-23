// "Tự sửa từ phía trước" (sửa ngược tiếng Anh — docs/DESIGN.md "Sửa ngược tiếng Anh"):
// phần dùng chung app ↔ bàn phím. Engine luôn quyết định khi "Quyết định theo ngữ cảnh"
// (contextualEnglish) bật; công tắc này (thử nghiệm, mặc định TẮT) chỉ chọn TỰ ÁP + chip
// "Khôi phục" thay vì MỜI qua chip trên thanh gợi ý. Song sinh Android Keys.RETRO_ENGLISH_AUTO.
import Foundation

enum RetroEnglishUI {
    /// Key App Group (Bool, mặc định false).
    static let autoKey = "retroactiveEnglish"

    /// Công tắc chỉ hiện khi "Quyết định theo ngữ cảnh" bật (engine chỉ sửa ngược khi đó),
    /// và không ở VNI (engine chỉ sửa ngược ở Telex — như teencode).
    static func switchVisible(contextualEnglish: Bool, vniMode: Bool = false) -> Bool {
        contextualEnglish && !vniMode
    }

    /// Nhãn chip "Khôi phục" sau khi tự sửa. Không qua L(): khoá "Khôi phục" đã dịch là
    /// "Reset" (nút đặt lại ở app) — chip này là "Undo".
    static var undoChipLabel: String {
        "\u{21A9}\u{FE0E} " + (L10n.isEnglish ? "Undo" : "Khôi phục")
    }
}
