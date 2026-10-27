// Giá trị riêng của từng app dựng từ mã này. Đây là bản của VietTelex. Một app khác dùng chung mã bàn phím
// bỏ file này khỏi target và đưa bản của mình vào (cùng tên kiểu, cùng thành viên) — mã chung chỉ đọc các
// giá trị này qua `AppFlavor`, không viết cứng định danh của VietTelex.
import Foundation

enum AppFlavor {
    /// Tên hiện cho người dùng ("Mở app VietTelex…", "VietTelex Plus").
    static let displayName = "VietTelex"
    /// App Group chung app ↔ bàn phím.
    static let appGroup = "group.com.viettelex"
    /// URL scheme của app chủ (bàn phím mở app: `<scheme>://maucau`).
    static let urlScheme = "viettelex"
    /// Bundle id của bàn phím — app dò trong danh sách bàn phím đang bật.
    static let keyboardBundleID = "com.viettelex.ios.keyboard"

    /// Non-consumable: mở khoá Plus vĩnh viễn.
    static let plusProductID = "com.viettelex.ios.plus"
    /// Consumable: ủng hộ, không mở khoá gì. Rỗng = app không có mục ủng hộ.
    static let tipProductIDs = [
        "com.viettelex.ios.tip.small",
        "com.viettelex.ios.tip.medium",
        "com.viettelex.ios.tip.large",
    ]
    /// Giá gợi ý khi StoreKit chưa tải được giá thật.
    static let plusPriceHint = "69.000đ"

    /// Ngôn ngữ giao diện khi người dùng chưa chọn ("vi" | "en").
    static let defaultUILanguage = "vi"
    /// Có gõ tiếng Việt không. `false`: bàn phím luôn ở chế độ Tiếng Anh, không vuốt phím cách đổi ngôn ngữ,
    /// không nạp dữ liệu tiếng Việt cho gõ vuốt (vnlexicon / vnlm) — app đó có thể không đóng gói chúng.
    static let vietnameseInput = true
    /// Bàn phím đếm số phím đã gõ vào App Group (`KeystrokeCounter`) — chỉ con số, không nội dung.
    static let countsKeystrokes = false

    // Bạn đồng hành (KeyboardBuddy.swift). Id = BuddyCharacter.rawValue.
    /// Nhân vật khi người dùng chưa chọn ("off" = tắt).
    static let defaultBuddy = "off"
    /// Nhân vật cho chọn, theo thứ tự (gồm "off" nếu cho tắt). nil = tất cả.
    static let buddyCharacters: [String]? = nil
    /// Nhân vật không cần Plus.
    static let freeBuddies = ["cat"]
    /// Hình + tên riêng của app cho nhân vật có sẵn: id → (tên hiển thị, tên file atlas PNG không đuôi, bố cục
    /// 4 × 2 như atlas có sẵn, xoay theo ô 2…6). Rỗng = hình của mã chung.
    static let buddySkins: [String: (title: String, atlas: String)] = [:]
}
