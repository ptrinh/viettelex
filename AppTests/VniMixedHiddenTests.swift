import XCTest
@testable import VietTelex

/// SETTINGS-CLEANUP-SPEC §1 (06/11/2026): chọn VNI ⇒ ẩn nhóm "Gõ lẫn tiếng Anh" (bộ chọn hồ sơ +
/// Nâng cao), thay bằng MỘT dòng ghi chú. Chỉ đổi hiển thị: key/giá trị giữ nguyên.
final class VniMixedHiddenTests: XCTestCase {

    func testGroupHiddenOnlyForVni() {
        XCTAssertTrue(OnboardingLogic.mixedGroupHidden(vniMode: true))
        XCTAssertFalse(OnboardingLogic.mixedGroupHidden(vniMode: false))
    }

    func testRows() {
        XCTAssertEqual(OnboardingLogic.mixedRows(vniMode: false), [.profilePicker, .advanced])
        XCTAssertEqual(OnboardingLogic.mixedRows(vniMode: true), [.vniNote])
    }

    func testNoteTextAndTranslation() throws {
        XCTAssertEqual(TypingTab.C.vniMixedNote, "VNI leaves English words as typed, so there is nothing to set here.")
        XCTAssertTrue(TypingTab.C.all.contains(TypingTab.C.vniMixedNote), "đo độ dài cùng bảng chú thích")
        let path = try XCTUnwrap(Bundle.main.path(forResource: "vi", ofType: "lproj"))
        let vi = try XCTUnwrap(Bundle(path: path))
        XCTAssertEqual(vi.localizedString(forKey: TypingTab.C.vniMixedNote, value: "∅", table: nil),
                       "Gõ VNI không làm đổi từ tiếng Anh nên không cần chỉnh phần này.")
    }

    /// Đổi qua lại VNI ↔ Telex không đụng giá trị công tắc nào của nhóm.
    func testTogglingVniKeepsMixedValues() {
        let s = AppState.shared
        let savedVni = s.vniMode
        let saved = OnboardingLogic.mixedKeys.map { ($0, s.mixedSetting($0)!) }
        defer {
            for (k, v) in saved { s.setMixedSetting(k, v) }
            s.vniMode = savedVni
        }
        let model = SettingsModel(selected: .typing)
        model.vniMode = false
        let before = model.mixedValues
        model.vniMode = true
        XCTAssertEqual(model.mixedValues, before)
        model.vniMode = false
        XCTAssertEqual(model.mixedValues, before)
        XCTAssertEqual(OnboardingLogic.mixedRows(vniMode: model.vniMode), [.profilePicker, .advanced])
    }
}
