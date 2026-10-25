import XCTest
@testable import VietTelex

/// macOS 27 đổi tên mục quyền "Trợ năng / Accessibility" thành "Điều khiển thiết bị và
/// truy cập dữ liệu / Device Control and Data Access" (field report 25/10/2026: user
/// không tìm thấy "Trợ năng"). Pin bảng phiên bản → tên + bản dịch trong vi.lproj.
final class PrivacyPaneTests: XCTestCase {

    func testNamesByVersion() {
        for major in [11, 13, 14, 15, 26] {
            XCTAssertFalse(PrivacyPane.isRenamed(major: major))
            XCTAssertEqual(PrivacyPane.name(major: major, vietnamese: true), "Trợ năng")
            XCTAssertEqual(PrivacyPane.name(major: major, vietnamese: false), "Accessibility")
        }
        for major in [27, 28, 30] {
            XCTAssertTrue(PrivacyPane.isRenamed(major: major))
            XCTAssertEqual(PrivacyPane.name(major: major, vietnamese: true),
                           "Điều khiển thiết bị và truy cập dữ liệu")
            XCTAssertEqual(PrivacyPane.name(major: major, vietnamese: false),
                           "Device Control and Data Access")
        }
        XCTAssertEqual(PrivacyPane.nameKey(major: 26), "Accessibility")
        XCTAssertEqual(PrivacyPane.nameKey(major: 27), "Device Control and Data Access")
    }

    func testPickAndFill() {
        XCTAssertEqual(PrivacyPane.pick(legacy: "a", modern: "b", major: 26), "a")
        XCTAssertEqual(PrivacyPane.pick(legacy: "a", modern: "b", major: 27), "b")
        XCTAssertEqual(PrivacyPane.fill("Mở … → {PANE} rồi bật; cần quyền {PANE}.", paneName: "X"),
                       "Mở … → X rồi bật; cần quyền X.")
        XCTAssertEqual(PrivacyPane.fill("no token", paneName: "X"), "no token")
    }

    /// Deep link: anchor không đổi trên 27 (đã kiểm bundle hệ thống), có dự phòng.
    func testSettingsURLs() {
        XCTAssertEqual(PrivacyPane.settingsURLStrings.first,
                       "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        XCTAssertGreaterThanOrEqual(PrivacyPane.settingsURLStrings.count, 2)
        for s in PrivacyPane.settingsURLStrings { XCTAssertNotNil(URL(string: s)) }
    }

    /// vi.lproj dịch đúng cả hai tên, và mọi chuỗi mang token đều giữ token ở bản dịch
    /// (không còn "Trợ năng" cứng — trên 27 nó chỉ sai chỗ).
    func testVietnameseTableUsesToken() throws {
        let path = try XCTUnwrap(Bundle.main.path(forResource: "vi", ofType: "lproj"))
        let vi = try XCTUnwrap(Bundle(path: path))
        XCTAssertEqual(vi.localizedString(forKey: PrivacyPane.nameKey(major: 26), value: nil, table: nil),
                       PrivacyPane.legacyNameVI)
        XCTAssertEqual(vi.localizedString(forKey: PrivacyPane.nameKey(major: 27), value: nil, table: nil),
                       PrivacyPane.modernNameVI)
        let table = try XCTUnwrap(vi.path(forResource: "Localizable", ofType: "strings"))
        let dict = try XCTUnwrap(NSDictionary(contentsOfFile: table) as? [String: String])
        var checked = 0
        for (key, value) in dict where key.contains(PrivacyPane.token) {
            checked += 1
            XCTAssertTrue(value.contains(PrivacyPane.token), key)
            XCTAssertFalse(value.contains("Trợ năng"), key)
        }
        XCTAssertGreaterThanOrEqual(checked, 8)
        for key in ["Stale permission title", "Status: Permission stale — click to fix",
                    "Repair started body", "Repair failed body", "Permission alert body (macOS 27)"] {
            XCTAssertTrue(dict[key]?.contains(PrivacyPane.token) == true, key)
        }
        let body27 = try XCTUnwrap(dict["Permission alert body (macOS 27)"])
        XCTAssertTrue(body27.contains("Quyền riêng tư & Bảo mật → {PANE}"))
        XCTAssertTrue(body27.contains("bấm − để xoá"))
    }
}
