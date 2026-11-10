import XCTest
@testable import VietTelex

// SettingsModel's mode-table logic: rows, labels, filter, sort, add/delete, and
// — per an explicit field requirement — IMPORT IDEMPOTENCY: applying the same
// plist any number of times must converge to one identical state, never crash,
// never duplicate. Same snapshot/restore discipline as AppStateRoutingTests.
final class SettingsModelTests: XCTestCase {

    private let s = AppState.shared
    private var savedManual: [String: String] = [:]

    override func setUp() {
        super.setUp()
        savedManual = s.manualModes
        Accessibility.testTrustOverride = true
    }

    override func tearDown() {
        Accessibility.testTrustOverride = nil
        let current = s.manualModes
        for id in current.keys where savedManual[id] == nil { s.setManualMode(.auto, for: id) }
        for (id, raw) in savedManual {
            if let m = AppState.AppMode(rawValue: raw) { s.setManualMode(m, for: id) }
        }
        super.tearDown()
    }

    /// 5 tab ngang, đúng thứ tự, luôn hiện (không còn "Ẩn tính năng nâng cao"); nhãn
    /// có tiếng Việt; icon không trùng nhau.
    func testSettingsTabsOrderAndLabels() throws {
        XCTAssertEqual(SettingsTab.allCases, [.typing, .tools, .shortcuts, .apps, .general])
        let path = try XCTUnwrap(Bundle.main.path(forResource: "vi", ofType: "lproj"))
        let vi = try XCTUnwrap(Bundle(path: path))
        let expected: [SettingsTab: String] = [
            .typing: "Gõ phím", .tools: "Gợi ý & công cụ", .shortcuts: "Gõ tắt",
            .apps: "Ứng dụng", .general: "Chung",
        ]
        for tab in SettingsTab.allCases {
            XCTAssertEqual(vi.localizedString(forKey: tab.titleKey, value: nil, table: nil), expected[tab])
        }
        XCTAssertEqual(Set(SettingsTab.allCases.map(\.icon)).count, SettingsTab.allCases.count)
    }

    /// Sau khi gộp tab (Giới thiệu/Thử nghiệm/Công cụ văn bản → Chung/Công cụ & gợi ý),
    /// thông báo cập nhật hằng tuần và toast "chưa tải gói dịch" từng chỉ người dùng tới
    /// tab không còn tồn tại (PR #125). Mọi chuỗi "Settings → X" (trừ System Settings)
    /// phải chỉ tới một tab có thật, ở cả khoá tiếng Anh lẫn bản dịch tiếng Việt.
    /// Phil 18/10/2026: giữ tên "Chính tả teencode" (dễ hiểu hơn "Chính tả khi nhắn tin").
    /// Phil 18/10/2026: nút mở cài đặt nguồn nhập liệu macOS phải có tiêu đề + tên rõ ràng (người dùng
    /// không biết viết hoa / gợi ý chữ / dấu chấm khi gõ hai dấu cách chỉnh ở đó).
    func testInputSourceSettingsButtonIsDescriptive() throws {
        let path = try XCTUnwrap(Bundle.main.path(forResource: "vi", ofType: "lproj"))
        let vi = try XCTUnwrap(Bundle(path: path))
        XCTAssertEqual(vi.localizedString(forKey: "Open Input Sources settings…", value: nil, table: nil),
                       "Mở cài đặt nguồn nhập liệu…")
        // Từ 05/11/2026 (spec cleanup §4) mục này chỉ còn một dòng link + chú thích một dòng.
        let title = vi.localizedString(forKey: TypingTab.systemSettingsCaption, value: nil, table: nil)
        XCTAssertTrue(title.contains("Viết hoa") && title.contains("gợi ý"))
    }

    /// Phil 10/11/2026: tự đổi nguồn nhập theo ứng dụng / tài liệu là cài đặt của macOS — dòng riêng ở
    /// cấp 1 của mục Chuyển Việt/Anh, gọi đúng tên công tắc macOS (bản tiếng Việt của macOS).
    func testPerDocumentInputSourceRowNamesTheMacOSSwitch() throws {
        let path = try XCTUnwrap(Bundle.main.path(forResource: "vi", ofType: "lproj"))
        let vi = try XCTUnwrap(Bundle(path: path))
        let title = vi.localizedString(forKey: TypingTab.perDocumentTitle, value: nil, table: nil)
        XCTAssertTrue(title.contains("ứng dụng") && title.contains("tài liệu"), title)
        let cap = vi.localizedString(forKey: TypingTab.perDocumentCaption, value: nil, table: nil)
        XCTAssertTrue(cap.contains("Tự động chuyển sang nguồn đầu vào của tài liệu"), cap)
        XCTAssertTrue(TypingTab.perDocumentCaption.contains("Automatically switch to a document’s input source"))
    }

    func testTeencodeToggleKeepsItsName() throws {
        let path = try XCTUnwrap(Bundle.main.path(forResource: "vi", ofType: "lproj"))
        let vi = try XCTUnwrap(Bundle(path: path))
        XCTAssertEqual(vi.localizedString(forKey: "Teencode spelling", value: nil, table: nil), "Chính tả teencode")
    }

    func testSettingsPathStringsNameCurrentTabs() throws {
        let path = try XCTUnwrap(Bundle.main.path(forResource: "vi", ofType: "lproj"))
        let vi = try XCTUnwrap(Bundle(path: path))
        let table = try XCTUnwrap(vi.path(forResource: "Localizable", ofType: "strings"))
        let dict = try XCTUnwrap(NSDictionary(contentsOfFile: table) as? [String: String])
        let enTabs = SettingsTab.allCases.map(\.titleKey)
        let viTabs = SettingsTab.allCases.map { vi.localizedString(forKey: $0.titleKey, value: nil, table: nil) }

        let update = "Open Settings → General to install it."
        let translate = "Translation pack not downloaded — open VietTelex Settings → Suggestions & tools."
        XCTAssertEqual(dict[update], "Mở Cài đặt → Chung để cài bản mới.")
        XCTAssertEqual(dict[translate], "Chưa có gói dịch này. Mở Cài đặt VietTelex → Gợi ý & công cụ để tải về.")

        func tab(after marker: String, in s: String) -> Substring? {
            s.range(of: marker).map { s[$0.upperBound...] }
        }
        var checked = 0
        for (key, value) in dict where key.contains("Settings → ") && !key.contains("System Settings") {
            checked += 1
            let enRest = try XCTUnwrap(tab(after: "Settings → ", in: key), key)
            XCTAssertTrue(enTabs.contains { enRest.hasPrefix($0) }, "stale tab in key: \(key)")
            let viRest = try XCTUnwrap(tab(after: "Cài đặt VietTelex → ", in: value)
                                       ?? tab(after: "Cài đặt → ", in: value), value)
            XCTAssertTrue(viTabs.contains { viRest.hasPrefix($0) }, "stale tab in vi: \(value)")
        }
        XCTAssertGreaterThanOrEqual(checked, 2)
        for stale in ["Giới thiệu để", "→ Công cụ văn bản", "tab Thử nghiệm", "tab Giới thiệu"] {
            XCTAssertFalse(dict.values.contains { $0.contains(stale) }, stale)
        }
    }

    /// Mở thẳng vào bất kỳ tab nào (không còn rơi về tab đầu khi "nâng cao" tắt).
    func testModelOpensRequestedTab() {
        for tab in SettingsTab.allCases {
            XCTAssertEqual(SettingsModel(selected: tab).selectedTab, tab)
        }
    }

    /// Chú thích Công cụ văn bản theo đúng số dòng của bảng (7 khi có Dịch), có tiếng Việt.
    func testTextToolsCaptionMatchesPanelRows() throws {
        let path = try XCTUnwrap(Bundle.main.path(forResource: "vi", ofType: "lproj"))
        let vi = try XCTUnwrap(Bundle(path: path))
        XCTAssertTrue(SettingsModel.textToolsCaptionKey(toolCount: 6).contains("1–6"))
        XCTAssertTrue(SettingsModel.textToolsCaptionKey(toolCount: 7).contains("1–7"))
        let n = TextToolsPanelLogic.tools.count
        XCTAssertTrue(SettingsModel.textToolsCaptionKey(toolCount: n).contains("1–\(n)"))
        for k in [6, 7].map(SettingsModel.textToolsCaptionKey(toolCount:)) {
            XCTAssertNotEqual(vi.localizedString(forKey: k, value: "∅", table: nil), "∅")
        }
        XCTAssertNotEqual(vi.localizedString(forKey: "Keep VietTelex when macOS auto-switches the input source",
                                             value: "∅", table: nil), "∅")
    }

    func testImportIsIdempotentAndValidates() {
        let model = SettingsModel(selected: .apps)
        let dict = [
            "test.viettelex.import.a": "tap",
            "test.viettelex.import.b": "inPlace",
            "test.viettelex.import.bad": "notAMode",   // must be skipped, not crash
            "": "tap",                                  // empty id skipped
        ]
        let first = model.importManualModes(dict)
        XCTAssertEqual(first, 2, "two valid entries applied, junk skipped")
        let stateAfterFirst = s.manualModes
        // Same file, five more times: identical state every time.
        for _ in 0..<5 {
            XCTAssertEqual(model.importManualModes(dict), 2)
            XCTAssertEqual(s.manualModes, stateAfterFirst)
        }
        s.setManualMode(.auto, for: "test.viettelex.import.a")
        s.setManualMode(.auto, for: "test.viettelex.import.b")
    }

    func testImportingTheShippedRulesFileIsSafe() {
        // The typing-modes.yml attached to releases is importable as manual pins
        // — twice, without drift (the user-facing "Nhập…" path).
        guard let url = Bundle(for: TelexInputController.self)
                .url(forResource: "typing-modes", withExtension: "yml"),
              let data = try? Data(contentsOf: url),
              let dict = ShortcutImporter.parse(data)
        else { return XCTFail("bundled typing-modes.yml unreadable") }
        let model = SettingsModel(selected: .apps)
        let n1 = model.importManualModes(dict)
        let snapshot = s.manualModes
        let n2 = model.importManualModes(dict)
        XCTAssertEqual(n1, n2)
        XCTAssertEqual(s.manualModes, snapshot)
        for id in dict.keys { s.setManualMode(.auto, for: id) }   // clean up pins
    }

    func testRowsFilterSortAndLabels() {
        let model = SettingsModel(selected: .apps)
        model.reloadModeTable()
        // Terminal row exists with a truthful detected label under both trusts.
        Accessibility.testTrustOverride = true
        model.reloadModeTable()
        guard let term = model.visibleModeRows.first(where: { $0.id == "com.apple.Terminal" })
        else { return XCTFail("Terminal row missing") }
        XCTAssertFalse(term.missingPermission)
        Accessibility.testTrustOverride = false
        model.reloadModeTable()
        let term2 = model.visibleModeRows.first(where: { $0.id == "com.apple.Terminal" })!
        XCTAssertTrue(term2.missingPermission)

        // Filter matches name, id, and labels; is case-insensitive.
        model.modeFilter = "com.apple.terminal"
        XCTAssertTrue(model.visibleModeRows.contains { $0.id == "com.apple.Terminal" })
        model.modeFilter = "zzz-no-such-app-zzz"
        XCTAssertTrue(model.visibleModeRows.isEmpty)
        model.modeFilter = ""

        // Header sort: descending by name reverses the default.
        let asc = model.visibleModeRows.map(\.name)
        model.modeSortOrder = [KeyPathComparator(\AppModeRow.name, order: .reverse)]
        XCTAssertEqual(model.visibleModeRows.map(\.name), asc.reversed())
        model.modeSortOrder = [KeyPathComparator(\AppModeRow.name)]
    }

    func testAddAndDeleteRow() {
        let model = SettingsModel(selected: .apps)
        model.newModeAppID = "test.viettelex.added"
        model.addApp()
        XCTAssertTrue(model.visibleModeRows.contains { $0.id == "test.viettelex.added" })
        XCTAssertEqual(model.newModeAppID, "")
        model.deleteRow("test.viettelex.added")
        XCTAssertFalse(model.visibleModeRows.contains { $0.id == "test.viettelex.added" })
        // Deleting a built-in row forgets user data but the row itself stays.
        model.deleteRow("com.apple.Terminal")
        XCTAssertTrue(model.visibleModeRows.contains { $0.id == "com.apple.Terminal" })
    }

    func testAppNameResolution() {
        XCTAssertEqual(SettingsModel.appName(for: SettingsModel.spotlightRowID), "Spotlight")
        // Unknown bundle id falls back to the id itself.
        XCTAssertEqual(SettingsModel.appName(for: "test.viettelex.ghost"), "test.viettelex.ghost")
    }
}
