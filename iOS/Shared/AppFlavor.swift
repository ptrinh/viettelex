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
}
