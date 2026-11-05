// Nhóm thu gọn "Gõ mixed Việt/Anh" (Shared/MixedTypingUI.swift, docs/ONBOARDING-SPEC.md §4):
// key lưu không đổi (sao lưu giữ nguyên), tìm kiếm Việt/Anh ra đúng mục, mục con phụ thuộc
// "Quyết định theo ngữ cảnh" vẫn ẩn/hiện như cũ và tìm tới nó khi ẩn thì cuộn về công tắc cha.
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
            .spaceSwipeLanguage: "spaceSwipeLanguage", .swipeEnglish: "swipeEnglish",
        ]
        for item in MixedTypingItem.allCases {
            XCTAssertEqual(item.storageKey, expected[item], "\(item)")
            if let k = item.storageKey {
                XCTAssertNotNil(BackupSettings.byKey[k], "key \(k) phải còn trong sao lưu")
            }
        }
    }

    func testGroupsFollowSpecOrder() {
        let recognition = MixedTypingItem.allCases.filter { $0.group == .recognition }
        XCTAssertEqual(recognition, [.autoRestore, .contextualEnglish, .retroEnglish, .englishByFrequency])
        XCTAssertEqual(MixedTypingItem.allCases.filter { $0.group == .language }, [.spaceSwipeLanguage])
        XCTAssertEqual(MixedTypingItem.allCases.filter { $0.group == .suggest }, [.swipeEnglish, .userDictionary])
        XCTAssertNil(MixedTypingItem.section.group)
    }

    func testSearchFindsItemsInBothLanguages() {
        for lang in ["vi", "en"] {
            L10n.apply(lang)
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
            XCTAssertTrue(hits("swipe english").contains(.swipeEnglish), lang)
        }
        XCTAssertTrue(hits("").isEmpty)
    }

    func testTitlesTranslated() {
        L10n.apply("en")
        XCTAssertEqual(L(MixedTypingUI.titleKey), "Mixed Vietnamese/English typing")
        for g in MixedTypingItem.Group.allCases {
            XCTAssertNotEqual(L(MixedTypingUI.groupTitle(g)), MixedTypingUI.groupTitle(g))
        }
        for item in MixedTypingItem.allCases {
            XCTAssertNotNil(L10n.en[item.viTitle], item.viTitle)
        }
    }

    /// Phụ thuộc cũ giữ nguyên: "Tự sửa từ phía trước" + "Đoán từ trùng theo tần suất" chỉ hiện
    /// khi ngữ cảnh bật và không VNI; tìm tới khi đang ẩn ⇒ cuộn tới "Quyết định theo ngữ cảnh".
    func testDependentItemsVisibilityAndScrollTarget() {
        for item in [MixedTypingItem.retroEnglish, .englishByFrequency] {
            XCTAssertTrue(MixedTypingUI.isVisible(item, contextualEnglish: true, vniMode: false))
            XCTAssertFalse(MixedTypingUI.isVisible(item, contextualEnglish: false, vniMode: false))
            XCTAssertFalse(MixedTypingUI.isVisible(item, contextualEnglish: true, vniMode: true))
            XCTAssertEqual(MixedTypingUI.scrollTarget(item, contextualEnglish: true, vniMode: false), item)
            XCTAssertEqual(MixedTypingUI.scrollTarget(item, contextualEnglish: false, vniMode: false), .contextualEnglish)
            XCTAssertEqual(MixedTypingUI.scrollTarget(item, contextualEnglish: true, vniMode: true), .contextualEnglish)
        }
        for item in MixedTypingItem.allCases where item != .retroEnglish && item != .englishByFrequency {
            XCTAssertEqual(MixedTypingUI.scrollTarget(item, contextualEnglish: false, vniMode: true), item)
        }
    }
}
