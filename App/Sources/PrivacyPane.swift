import AppKit

/// Tên + đường dẫn của mục quyền mà VietTelex cần (TCC kTCCServiceAccessibility),
/// theo phiên bản macOS. MỘT chỗ duy nhất cho mọi alert / menu / Cài đặt / sửa quyền.
///
/// macOS 27 đổi tên mục này trong Quyền riêng tư & Bảo mật: "Accessibility / Trợ năng"
/// → "Device Control and Data Access / Điều khiển thiết bị và truy cập dữ liệu". Mục
/// "Trợ năng" ở thanh bên vẫn còn nhưng là cài đặt hỗ trợ thị giác/thính giác — KHÔNG
/// phải chỗ cấp quyền, nên user 27 đọc hướng dẫn cũ sẽ lạc (field report 25/10/2026).
///
/// Tên lấy NGUYÊN VĂN từ chuỗi hệ thống (macOS 27.0.1, 26A434):
///   SecurityPrivacyExtension.appex/Contents/Resources/Localizable.loctable, khoá
///   "ACCESSIBILITY": en "Device Control and Data Access",
///                    vi "Điều khiển thiết bị và truy cập dữ liệu".
///   Tên cũ (≤ 26) = tên khung Trợ năng: "Accessibility" / "Trợ năng".
///   Khung cha: "Privacy & Security" / "Quyền riêng tư & Bảo mật" (InfoPlist.loctable).
///
/// Chuỗi giao diện chứa token `{PANE}`; `VTLocalized` thay token bằng tên mục đã dịch
/// theo ngôn ngữ giao diện (`nameKey` là khoá tiếng Anh, vi.lproj dịch sang tiếng Việt).
enum PrivacyPane {
    static let token = "{PANE}"

    static let legacyNameEN = "Accessibility"
    static let legacyNameVI = "Trợ năng"
    static let modernNameEN = "Device Control and Data Access"
    static let modernNameVI = "Điều khiển thiết bị và truy cập dữ liệu"

    /// macOS 27 trở lên dùng tên mới.
    static func isRenamed(major: Int) -> Bool { major >= 27 }

    static var currentMajor: Int { ProcessInfo.processInfo.operatingSystemVersion.majorVersion }

    /// Tên mục quyền theo phiên bản + ngôn ngữ. Pure — pinned by PrivacyPaneTests.
    static func name(major: Int, vietnamese: Bool) -> String {
        switch (isRenamed(major: major), vietnamese) {
        case (true, true): return modernNameVI
        case (true, false): return modernNameEN
        case (false, true): return legacyNameVI
        case (false, false): return legacyNameEN
        }
    }

    /// Khoá Localizable (= tên tiếng Anh) của tên mục; vi.lproj dịch sang tiếng Việt.
    static func nameKey(major: Int) -> String { name(major: major, vietnamese: false) }

    /// Chọn khoá chuỗi cho câu hướng dẫn có nội dung khác nhau giữa hai đời macOS
    /// (vd 27: "xoá rồi thêm lại" thay cho "tắt rồi bật lại").
    static func pick(legacy: String, modern: String, major: Int = currentMajor) -> String {
        isRenamed(major: major) ? modern : legacy
    }

    /// Thay `{PANE}` bằng `paneName`. Pure — chuỗi không chứa token trả nguyên.
    static func fill(_ text: String, paneName: String) -> String {
        text.contains(token) ? text.replacingOccurrences(of: token, with: paneName) : text
    }

    /// Deep link mở đúng danh sách quyền. Kiểm tra trên bundle macOS 27.0.1:
    /// SecurityPrivacyExtension vẫn khai `legacyBundleIdentifier =
    /// com.apple.preference.security` + `allowsXAppleSystemPreferencesURLScheme`, và
    /// anchor `Privacy_Accessibility` vẫn có trong binary + PrivacySecurity.searchTerms
    /// (mục đổi tên, anchor KHÔNG đổi; không có anchor mới) ⇒ cùng URL cho mọi đời.
    /// Phần tử sau = dự phòng (mở khung Quyền riêng tư & Bảo mật) nếu URL đầu bị từ chối.
    static let settingsURLStrings = [
        "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
        "x-apple.systempreferences:com.apple.preference.security",
    ]

    /// Mở Cài đặt hệ thống → Quyền riêng tư & Bảo mật → mục quyền này.
    /// Kèm: poll quyền nhanh (2s) vài phút — user sắp bật VietTelex ở đó, và macOS 27
    /// có thể không phát com.apple.accessibility.api (TrustPollSchedule).
    static func openSettings() {
        TerminalTapController.shared.recheckTrust(reason: "open-settings clicked", boost: true)
        for s in settingsURLStrings {
            if let url = URL(string: s), NSWorkspace.shared.open(url) { return }
        }
    }
}
