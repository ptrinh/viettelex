// Onboarding + hồ sơ (Shared/OnboardingProfile.swift, docs/ONBOARDING-SPEC.md §2–§5): giá trị
// từng hồ sơ đúng bảng §3, nhận diện hồ sơ khớp / "Tuỳ chỉnh", người dùng cũ khi nâng cấp không
// chạy onboarding (thẻ một lần), "Bỏ qua" giữ mặc định, sao lưu/khôi phục không đụng key onboarding.
// Song sinh Android OnboardingTest.kt — cùng số liệu.
import XCTest

final class OnboardingTests: XCTestCase {
    private var suites: [String] = []

    private func freshDefaults() -> UserDefaults {
        let name = "onboarding-test-\(UUID().uuidString)"
        suites.append(name)
        return UserDefaults(suiteName: name)!
    }

    override func tearDown() {
        for s in suites { UserDefaults().removePersistentDomain(forName: s) }
        suites = []
        L10n.apply("vi")
        super.tearDown()
    }

    private let retro = "retroactiveEnglish", freq = "englishByFrequency"

    // MARK: §3 bảng hồ sơ

    func testProfileValuesFollowSpecTable() {
        XCTAssertEqual(OnboardingSettings.keys,
                       ["autoRestore", "contextualEnglish", retro, freq, "spaceSwipeLanguage", "swipeEnglish"])
        XCTAssertEqual(OnboardingProfile.vi.values, [
            "autoRestore": true, "contextualEnglish": true, retro: false, freq: false,
            "spaceSwipeLanguage": false, "swipeEnglish": true,
        ])
        let allOn = Dictionary(uniqueKeysWithValues: OnboardingSettings.keys.map { ($0, true) })
        XCTAssertEqual(OnboardingProfile.mixed.values, allOn)
        XCTAssertEqual(OnboardingProfile.en.values, OnboardingProfile.mixed.values, "en = như mixed (§3)")
        XCTAssertEqual(OnboardingProfile.en.keyboardLanguage, "en")
        XCTAssertEqual(OnboardingProfile.mixed.keyboardLanguage, "vi")
        XCTAssertEqual(OnboardingProfile.vi.keyboardLanguage, "vi")
        XCTAssertEqual(OnboardingProfile.allCases, [.vi, .mixed, .en], "thứ tự thẻ như Android")
    }

    /// Hồ sơ `vi` = mặc định hiện tại; mặc định ở đây khớp mặc định sao lưu (cùng nguồn sự thật).
    func testDefaultsMatchBackupDefaultsAndKeysAreBackedUp() {
        for k in OnboardingSettings.keys {
            guard case .bool(let def)? = BackupSettings.byKey[k]?.kind else { return XCTFail("\(k) không trong sao lưu") }
            XCTAssertEqual(OnboardingSettings.defaults[k], def, k)
        }
        XCTAssertEqual(OnboardingProfile.vi.values, OnboardingSettings.defaults)
    }

    func testApplyWritesConcreteValuesAndLanguageRequest() {
        let d = freshDefaults()
        OnboardingSettings.apply(.en, to: d, now: Date(timeIntervalSince1970: 1000))
        XCTAssertEqual(OnboardingSettings.current(d), OnboardingProfile.en.values)
        XCTAssertEqual(d.string(forKey: OnboardingFlow.profileKey), "en")
        XCTAssertEqual(d.string(forKey: KeyboardLanguageRequest.key), "en@1000000")
        XCTAssertNil(d.object(forKey: OnboardingFlow.doneKey), "áp hồ sơ không tự đánh dấu xong")
        // Không lưu "chế độ": sửa một công tắc sau đó thì giữ nguyên, không bị ghi đè.
        d.set(false, forKey: "spaceSwipeLanguage")
        XCTAssertEqual(OnboardingSettings.current(d)["spaceSwipeLanguage"], false)
        OnboardingSettings.apply(.vi, to: d, now: Date(timeIntervalSince1970: 2000))
        XCTAssertEqual(OnboardingSettings.current(d), OnboardingSettings.defaults)
        XCTAssertEqual(d.string(forKey: KeyboardLanguageRequest.key), "vi@2000000")
    }

    // MARK: §4 khớp đúng / Tuỳ chỉnh

    func testExactMatchAndCustom() {
        for p in OnboardingProfile.allCases {
            XCTAssertEqual(OnboardingSettings.match(p.values, lastChosen: p), p)
        }
        XCTAssertEqual(OnboardingSettings.match(OnboardingSettings.defaults, lastChosen: nil), .vi)
        // mixed ≡ en về công tắc ⇒ tô theo lần chọn gần nhất.
        XCTAssertEqual(OnboardingSettings.match(OnboardingProfile.mixed.values, lastChosen: nil), .mixed)
        XCTAssertEqual(OnboardingSettings.match(OnboardingProfile.mixed.values, lastChosen: .vi), .mixed)
        XCTAssertEqual(OnboardingSettings.match(OnboardingProfile.mixed.values, lastChosen: .en), .en)
        // Lệch một công tắc bất kỳ ⇒ Tuỳ chỉnh.
        for p in OnboardingProfile.allCases {
            for k in OnboardingSettings.keys {
                var v = p.values; v[k]?.toggle()
                XCTAssertNil(OnboardingSettings.match(v, lastChosen: p), "\(p) lệch \(k)")
            }
        }
        // "en" đã chọn nhưng công tắc là của vi ⇒ vi.
        XCTAssertEqual(OnboardingSettings.match(OnboardingSettings.defaults, lastChosen: .en), .vi)
    }

    func testChangesAndConfirmation() {
        XCTAssertEqual(OnboardingSettings.changes(from: OnboardingSettings.defaults, to: .mixed),
                       [retro, freq, "spaceSwipeLanguage"])
        XCTAssertEqual(OnboardingSettings.changes(from: OnboardingProfile.mixed.values, to: .en), [])
        // Đang khớp hồ sơ ⇒ đổi hồ sơ không hỏi.
        XCTAssertFalse(OnboardingSettings.needsConfirmation(OnboardingSettings.defaults, applying: .mixed, lastChosen: nil))
        // Đang Tuỳ chỉnh và áp sẽ đổi công tắc ⇒ hỏi.
        var custom = OnboardingSettings.defaults; custom["autoRestore"] = false
        XCTAssertTrue(OnboardingSettings.needsConfirmation(custom, applying: .mixed, lastChosen: nil))
        XCTAssertTrue(OnboardingSettings.needsConfirmation(custom, applying: .vi, lastChosen: nil))
    }

    // MARK: §2 luồng

    func testScreenFlow() {
        XCTAssertEqual(OnboardingFlow.screen(done: false, profile: nil, keyboardEnabled: false), .choose)
        XCTAssertEqual(OnboardingFlow.screen(done: false, profile: nil, keyboardEnabled: true), .choose)
        // Đã chọn, bàn phím chưa bật ⇒ ẩn màn 2; bật rồi ⇒ hiện.
        XCTAssertNil(OnboardingFlow.screen(done: false, profile: .mixed, keyboardEnabled: false))
        XCTAssertEqual(OnboardingFlow.screen(done: false, profile: .mixed, keyboardEnabled: true), .tryIt)
        XCTAssertNil(OnboardingFlow.screen(done: true, profile: nil, keyboardEnabled: true))
        XCTAssertNil(OnboardingFlow.screen(done: true, profile: .en, keyboardEnabled: true))
    }

    /// Người mới: onboarding hiện; "Bỏ qua" ⇒ chỉ ghi xong, mọi cài đặt giữ mặc định.
    func testNewUserSkipKeepsDefaults() {
        let d = freshDefaults()
        XCTAssertEqual(OnboardingFlow.migrate(d, settingKeys: ["autoRestore"]), [OnboardingFlow.doneKey: false])
        XCTAssertEqual(OnboardingFlow.screen(d, keyboardEnabled: false), .choose)
        let before = Set(d.dictionaryRepresentation().keys)
        OnboardingFlow.finish(d)
        XCTAssertEqual(Set(d.dictionaryRepresentation().keys).subtracting(before), [])
        XCTAssertEqual(d.object(forKey: OnboardingFlow.doneKey) as? Bool, true)
        for k in OnboardingSettings.keys { XCTAssertNil(d.object(forKey: k), "\(k) không được ghi") }
        XCTAssertEqual(OnboardingSettings.current(d), OnboardingSettings.defaults)
        XCTAssertNil(OnboardingFlow.screen(d, keyboardEnabled: true))
        XCTAssertNotEqual(d.object(forKey: OnboardingFlow.tipKey) as? Bool, true, "người mới không có thẻ")
    }

    /// Người mới chọn hồ sơ khi chưa bật bàn phím ⇒ màn 2 chờ; app/bàn phím ghi thêm key sau đó
    /// cũng không biến họ thành "người dùng cũ".
    func testNewUserChoosesBeforeKeyboardEnabled() {
        let d = freshDefaults()
        OnboardingFlow.migrate(d, settingKeys: ["autoRestore", "numberRow"])
        OnboardingSettings.apply(.mixed, to: d)
        d.set(true, forKey: "rowAdjustStockBase")
        d.set(true, forKey: "numberRow")
        XCTAssertNil(OnboardingFlow.migrate(d, settingKeys: ["autoRestore", "numberRow"]), "đã quyết định một lần")
        XCTAssertNil(OnboardingFlow.screen(d, keyboardEnabled: false))
        XCTAssertEqual(OnboardingFlow.screen(d, keyboardEnabled: true), .tryIt)
        OnboardingFlow.finish(d)
        XCTAssertNil(OnboardingFlow.screen(d, keyboardEnabled: true), "màn 2 chỉ hiện một lần")
    }

    // MARK: §5 người dùng cũ

    func testUpgradeDetection() {
        let settings: Set<String> = ["autoRestore", "numberRow", "kbLastSeen"]
        // Không có gì / chỉ key bàn phím tự ghi ⇒ người mới.
        XCTAssertEqual(OnboardingFlow.upgradeWrites(existingKeys: [], settingKeys: settings), [OnboardingFlow.doneKey: false])
        XCTAssertEqual(OnboardingFlow.upgradeWrites(existingKeys: ["kbLastSeen", "kbFullAccess", "pasteNoPrompt", "uiLanguageX"],
                                                    settingKeys: settings), [OnboardingFlow.doneKey: false])
        // Có một cài đặt / cờ app bản cũ ⇒ người dùng cũ: xong + thẻ một lần.
        let old = [OnboardingFlow.doneKey: true, OnboardingFlow.tipKey: true]
        XCTAssertEqual(OnboardingFlow.upgradeWrites(existingKeys: ["numberRow"], settingKeys: settings), old)
        XCTAssertEqual(OnboardingFlow.upgradeWrites(existingKeys: ["rowAdjustStockBase"], settingKeys: settings), old)
        // Đã quyết định rồi ⇒ không đổi gì.
        XCTAssertNil(OnboardingFlow.upgradeWrites(existingKeys: [OnboardingFlow.doneKey, "numberRow"], settingKeys: settings))
    }

    /// Bản nâng cấp: không onboarding, thẻ một lần, KHÔNG đổi giá trị nào của người dùng.
    func testExistingUserNeverOnboardedAndValuesUntouched() {
        let d = freshDefaults()
        d.set(false, forKey: "autoRestore")
        d.set(true, forKey: "spaceSwipeLanguage")
        d.set("en", forKey: "uiLanguage")
        let before = d.dictionaryRepresentation().filter { !$0.key.hasPrefix("onboarding") && $0.key != OnboardingFlow.tipKey }
        let keys = Set(BackupSettings.all.map(\.key))
        XCTAssertEqual(OnboardingFlow.migrate(d, settingKeys: keys), [OnboardingFlow.doneKey: true, OnboardingFlow.tipKey: true])
        XCTAssertNil(OnboardingFlow.screen(d, keyboardEnabled: true))
        XCTAssertNil(OnboardingFlow.screen(d, keyboardEnabled: false))
        XCTAssertEqual(d.bool(forKey: OnboardingFlow.tipKey), true)
        let after = d.dictionaryRepresentation().filter { !$0.key.hasPrefix("onboarding") && $0.key != OnboardingFlow.tipKey }
        XCTAssertEqual(NSDictionary(dictionary: before), NSDictionary(dictionary: after))
        // Thẻ: đóng là không hiện lại, lần mở sau không bật lại.
        OnboardingFlow.dismissTip(d)
        XCTAssertNil(OnboardingFlow.migrate(d, settingKeys: keys))
        XCTAssertEqual(d.bool(forKey: OnboardingFlow.tipKey), false)
    }

    // MARK: sao lưu / khôi phục

    func testBackupRestoreUnaffected() {
        let ownKeys = [OnboardingFlow.doneKey, OnboardingFlow.profileKey, OnboardingFlow.tipKey,
                       KeyboardLanguageRequest.key, KeyboardLanguageRequest.appliedKey]
        for k in ownKeys { XCTAssertNil(BackupSettings.byKey[k], "\(k) không được vào sao lưu") }
        // Xuất từ máy đã onboarding ⇒ không mang key onboarding; nhập vào máy khác ⇒ không đụng chúng.
        let src = freshDefaults()
        OnboardingFlow.migrate(src, settingKeys: [])
        OnboardingSettings.apply(.en, to: src)
        OnboardingFlow.finish(src)
        let exported = BackupStore(defaults: src, containerURL: nil).settings()
        for k in ownKeys { XCTAssertNil(exported[k]) }
        XCTAssertEqual(exported["spaceSwipeLanguage"], .bool(true), "giá trị hồ sơ là cài đặt thường ⇒ vẫn sao lưu")

        let dst = freshDefaults()
        d_setOld(dst)
        BackupStore(defaults: dst, containerURL: nil).setSettings(exported)
        XCTAssertEqual(dst.object(forKey: OnboardingFlow.doneKey) as? Bool, true)
        XCTAssertEqual(dst.object(forKey: OnboardingFlow.tipKey) as? Bool, false)
        XCTAssertNil(dst.object(forKey: OnboardingFlow.profileKey))
        XCTAssertEqual(OnboardingSettings.current(dst), OnboardingProfile.en.values)
    }

    private func d_setOld(_ d: UserDefaults) {
        d.set(true, forKey: OnboardingFlow.doneKey)
        d.set(false, forKey: OnboardingFlow.tipKey)
    }

    // MARK: ngôn ngữ khởi đầu (bàn phím)

    func testKeyboardLanguageRequest() {
        XCTAssertEqual(KeyboardLanguageRequest.encode("en", stamp: 1.5), "en@1500")
        XCTAssertNil(KeyboardLanguageRequest.pending(request: nil, applied: nil))
        XCTAssertEqual(KeyboardLanguageRequest.pending(request: "en@1500", applied: nil), "en")
        XCTAssertNil(KeyboardLanguageRequest.pending(request: "en@1500", applied: "en@1500"), "áp một lần")
        XCTAssertEqual(KeyboardLanguageRequest.pending(request: "en@1600", applied: "en@1500"), "en", "chọn lại ⇒ áp lại")
        XCTAssertEqual(KeyboardLanguageRequest.pending(request: "vi@1700", applied: "en@1600"), "vi")
        XCTAssertNil(KeyboardLanguageRequest.pending(request: "xx@1", applied: nil))
        XCTAssertNil(KeyboardLanguageRequest.pending(request: "", applied: nil))
        // Bàn phím: ngôn ngữ chỉ là EN khi bật vuốt phím cách — hồ sơ en bật sẵn công tắc đó.
        XCTAssertEqual(OnboardingProfile.en.values["spaceSwipeLanguage"], true)
        XCTAssertEqual(KeyboardLanguage.effective(stored: "en", flickEnabled: true), .en)
    }

    func testTitlesTranslated() {
        L10n.apply("en")
        XCTAssertEqual(L(OnboardingProfile.vi.titleKey), "Mostly Vietnamese")
        XCTAssertEqual(L(OnboardingProfile.mixed.titleKey), "Vietnamese + lots of English")
        XCTAssertEqual(L(OnboardingProfile.en.titleKey), "Mostly English")
        for k in OnboardingSettings.keys { XCTAssertNotEqual(L(OnboardingSettings.titleKey(k)), OnboardingSettings.titleKey(k)) }
    }
}
