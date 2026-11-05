// Nhóm thu gọn "Gõ lẫn tiếng Anh" (Shared/MixedTypingUI.swift, docs/ONBOARDING-SPEC.md §4,
// docs/SETTINGS-CLEANUP-SPEC.md §1): key lưu không đổi (sao lưu giữ nguyên), chỗ đặt cấp 1 / Nâng
// cao, tìm kiếm Việt/Anh ra đúng mục, mục phụ thuộc "Quyết định theo ngữ cảnh" mờ + lý do.
import XCTest

final class MixedTypingUITests: XCTestCase {
    override func tearDown() {
        L10n.apply("vi")
        super.tearDown()
    }

    private func hits(_ q: String) -> Set<MixedTypingItem> {
        let w = SettingsSearch.words(q)
        return Set(MixedTypingItem.allCases.filter {
            SettingsSearch.matches(viTitle: $0.viTitle, keywords: $0.keywords, words: w)
        })
    }

    func testStorageKeysUnchangedAndBackedUp() {
        let expected: [MixedTypingItem: String] = [
            .autoRestore: "autoRestore", .contextualEnglish: "contextualEnglish",
            .retroEnglish: "retroactiveEnglish", .englishByFrequency: "englishByFrequency",
            .spaceSwipeLanguage: "spaceSwipeLanguage",
        ]
        for item in MixedTypingItem.allCases {
            XCTAssertEqual(item.storageKey, expected[item], "\(item)")
            if let k = item.storageKey {
                XCTAssertNotNil(BackupSettings.byKey[k], "key \(k) phải còn trong sao lưu")
            }
        }
    }

    /// SETTINGS-CLEANUP-SPEC §1: cấp 1 = tiêu đề, vuốt phím cách, Từ điển cá nhân; "Nâng cao" = bốn
    /// công tắc nhận diện tiếng Anh, hai mục thử nghiệm ngay dưới "Quyết định theo ngữ cảnh".
    func testPlacementFollowsSpec() {
        XCTAssertEqual(MixedTypingItem.allCases.filter { $0.placement == .top }, [.section, .spaceSwipeLanguage, .userDictionary])
        XCTAssertEqual(MixedTypingUI.advancedItems, [.autoRestore, .contextualEnglish, .retroEnglish, .englishByFrequency])
        XCTAssertEqual(MixedTypingUI.advancedSubtitleKey, "Khôi phục từ tiếng Anh, ngữ cảnh, khi trùng từ, sửa từ phía trước…")
        XCTAssertEqual(MixedTypingUI.titleKey, "Gõ lẫn tiếng Anh")
        XCTAssertEqual(MixedTypingItem.spaceSwipeLanguage.viTitle, "Vuốt phím cách đổi Tiếng Việt / Tiếng Anh")
    }

    func testSearchFindsItemsInBothLanguages() {
        for lang in ["vi", "en"] {
            L10n.apply(lang)
            XCTAssertTrue(hits("go lan tieng anh").contains(.section), lang)
            XCTAssertTrue(hits("go mixed").contains(.section), lang)
            XCTAssertTrue(hits("mixed vietnamese").contains(.section), lang)
            XCTAssertTrue(hits("tan suat").contains(.englishByFrequency), lang)
            XCTAssertTrue(hits("frequency").contains(.englishByFrequency), lang)
            XCTAssertTrue(hits("vuot phim cach").contains(.spaceSwipeLanguage), lang)
            XCTAssertTrue(hits("space").contains(.spaceSwipeLanguage), lang)
            XCTAssertTrue(hits("ngu canh").contains(.contextualEnglish), lang)
            XCTAssertTrue(hits("context").contains(.contextualEnglish), lang)
            XCTAssertTrue(hits("khoi phuc tieng anh").contains(.autoRestore), lang)
            XCTAssertTrue(hits("fix earlier").contains(.retroEnglish), lang)
            XCTAssertTrue(hits("nang cao").contains(.retroEnglish), lang)
        }
        XCTAssertTrue(hits("").isEmpty)
    }

    func testTitlesTranslated() {
        L10n.apply("en")
        XCTAssertEqual(L(MixedTypingUI.titleKey), "Mixed Vietnamese/English typing")
        XCTAssertEqual(L(MixedTypingUI.advancedTitleKey), "Advanced")
        XCTAssertNotEqual(L(MixedTypingUI.advancedSubtitleKey), MixedTypingUI.advancedSubtitleKey)
        for item in MixedTypingItem.allCases {
            XCTAssertNotNil(L10n.en[item.viTitle], item.viTitle)
        }
    }

    /// Mục phụ thuộc KHÔNG ẩn mà mờ + lý do (§0.4): VNI ⇒ "Chỉ áp dụng cho Telex" (thắng), ngữ cảnh
    /// tắt ⇒ "Cần bật Quyết định theo ngữ cảnh"; cùng điều kiện với RetroEnglishUI.switchVisible.
    func testDependentItemsDimmedWithReason() {
        for item in [MixedTypingItem.retroEnglish, .englishByFrequency] {
            XCTAssertNil(MixedTypingUI.disabledReason(item, contextualEnglish: true, vniMode: false))
            XCTAssertEqual(MixedTypingUI.disabledReason(item, contextualEnglish: false, vniMode: false), "Cần bật Quyết định theo ngữ cảnh")
            XCTAssertEqual(MixedTypingUI.disabledReason(item, contextualEnglish: true, vniMode: true), "Chỉ áp dụng cho Telex")
            XCTAssertEqual(MixedTypingUI.disabledReason(item, contextualEnglish: false, vniMode: true), "Chỉ áp dụng cho Telex")
            for c in [false, true] { for v in [false, true] {
                XCTAssertEqual(MixedTypingUI.disabledReason(item, contextualEnglish: c, vniMode: v) == nil,
                               RetroEnglishUI.switchVisible(contextualEnglish: c, vniMode: v))
            } }
        }
        for item in MixedTypingItem.allCases where item != .retroEnglish && item != .englishByFrequency {
            XCTAssertNil(MixedTypingUI.disabledReason(item, contextualEnglish: false, vniMode: true), "\(item)")
        }
    }
}
