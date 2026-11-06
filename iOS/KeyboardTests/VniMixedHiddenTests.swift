// SETTINGS-CLEANUP-SPEC §1 (06/11/2026): chọn VNI ⇒ ẩn nhóm "Gõ lẫn tiếng Anh" (bộ chọn hồ sơ +
// Nâng cao), thay bằng MỘT dòng ghi chú. Chỉ đổi hiển thị: key/giá trị giữ nguyên; tìm kiếm vẫn
// thấy mục bị ẩn và mở ra nhóm có dòng ghi chú; onboarding bỏ qua câu hỏi hồ sơ.
import XCTest

final class VniMixedHiddenTests: XCTestCase {
    override func tearDown() {
        L10n.apply("vi")
        super.tearDown()
    }

    func testGroupHiddenOnlyForVni() {
        XCTAssertTrue(MixedTypingUI.groupHidden(vniMode: true))
        XCTAssertFalse(MixedTypingUI.groupHidden(vniMode: false))
    }

    func testRows() {
        XCTAssertEqual(MixedTypingUI.rows(vniMode: false),
                       [.profilePicker, .spaceSwipeLanguage, .userDictionary, .advanced])
        // VNI: dòng ghi chú thay bộ chọn + Nâng cao; vuốt phím cách + từ điển cá nhân vẫn hiện.
        XCTAssertEqual(MixedTypingUI.rows(vniMode: true), [.vniNote, .spaceSwipeLanguage, .userDictionary])
    }

    func testItemVisibility() {
        for item in MixedTypingItem.allCases {
            XCTAssertTrue(MixedTypingUI.isVisible(item, vniMode: false), item.rawValue)
            XCTAssertEqual(MixedTypingUI.isVisible(item, vniMode: true), item.placement == .top, item.rawValue)
        }
        XCTAssertTrue(MixedTypingUI.isVisible(.spaceSwipeLanguage, vniMode: true))
        XCTAssertTrue(MixedTypingUI.isVisible(.userDictionary, vniMode: true))
        XCTAssertFalse(MixedTypingUI.isVisible(.autoRestore, vniMode: true))
    }

    func testNoteText() {
        XCTAssertEqual(MixedTypingUI.vniNoteKey, "Gõ VNI không làm đổi từ tiếng Anh nên không cần chỉnh phần này.")
        XCTAssertEqual(L10n.en[MixedTypingUI.vniNoteKey], "VNI leaves English words as typed, so there is nothing to set here.")
        XCTAssertTrue(SettingCaption.all.contains(MixedTypingUI.vniNoteKey), "đo độ dài cùng bảng chú thích")
    }

    /// Mục bị ẩn vẫn tìm thấy; mở ra nhóm (đang hiện dòng ghi chú). Telex: như cũ.
    func testSearchStillFindsHiddenItems() {
        for lang in ["vi", "en"] {
            L10n.apply(lang)
            for (q, item) in [("tu khoi phuc", MixedTypingItem.autoRestore), ("tan suat", .englishByFrequency),
                              ("ngu canh", .contextualEnglish), ("sua tu phia truoc", .retroEnglish)] {
                let hits = SettingsIndex.search(q) { _ in true }.map(\.location)
                XCTAssertTrue(hits.contains(.mixedAdvanced(item)), "\(lang) \(q)")
                XCTAssertEqual(SettingsLocation.mixedAdvanced(item).resolved(vniMode: true), .mixed(.section))
                XCTAssertEqual(SettingsLocation.mixedAdvanced(item).resolved(vniMode: false), .mixedAdvanced(item))
            }
        }
        // Mục vẫn hiện khi VNI: giữ nguyên chỗ.
        for l: SettingsLocation in [.mixed(.spaceSwipeLanguage), .mixed(.userDictionary), .page(.goVuot), .typingAdvanced] {
            XCTAssertEqual(l.resolved(vniMode: true), l)
        }
    }

    /// Không đổi key: mỗi mục ẩn vẫn trỏ đúng key lưu cũ.
    func testKeysUnchanged() {
        XCTAssertEqual(MixedTypingItem.autoRestore.storageKey, "autoRestore")
        XCTAssertEqual(MixedTypingItem.contextualEnglish.storageKey, "contextualEnglish")
        XCTAssertEqual(MixedTypingItem.retroEnglish.storageKey, RetroEnglishUI.autoKey)
        XCTAssertEqual(MixedTypingItem.englishByFrequency.storageKey, RetroEnglishUI.frequencyKey)
    }

    func testOnboardingSkippedForVni() {
        XCTAssertNil(OnboardingFlow.screen(done: false, profile: nil, keyboardEnabled: true, vniMode: true))
        XCTAssertNil(OnboardingFlow.screen(done: false, profile: .mixed, keyboardEnabled: true, vniMode: true))
        XCTAssertEqual(OnboardingFlow.screen(done: false, profile: nil, keyboardEnabled: true, vniMode: false), .choose)

        let name = "vt-test-vni-onboarding"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        defer { d.removePersistentDomain(forName: name) }
        d.set(false, forKey: OnboardingFlow.doneKey)
        d.set(true, forKey: "vniMode")
        XCTAssertNil(OnboardingFlow.screen(d, keyboardEnabled: true))
        XCTAssertEqual(d.object(forKey: OnboardingFlow.doneKey) as? Bool, false, "không ghi gì")
        // Đổi lại Telex: câu hỏi hiện như thường.
        d.set(false, forKey: "vniMode")
        XCTAssertEqual(OnboardingFlow.screen(d, keyboardEnabled: true), .choose)
    }
}
