import XCTest
@testable import VietTelex

/// Onboarding người dùng mới (docs/ONBOARDING-SPEC.md §2/§3/§5): hồ sơ → giá trị, nhận ra
/// người dùng cũ khi nâng cấp, bỏ qua giữ mặc định, thẻ một lần. Suite riêng cho mỗi test —
/// không đụng cài đặt thật (XCTest host đã dùng com.viettelex.settings.tests).
final class OnboardingTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "com.viettelex.settings.onboarding-tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    private func dict(_ p: TypingProfile) -> [String: Bool] {
        Dictionary(uniqueKeysWithValues: OnboardingLogic.values(for: p).map { ($0.key, $0.value) })
    }

    // MARK: hồ sơ (§3, §10)

    func testViProfileIsCurrentDefaults() {
        XCTAssertEqual(dict(.vi), ["autoRestore": true, "contextualEnglish": true, "retroactiveEnglish": false,
                                   "englishByFrequency": false, "collisionPrefersVietnamese": true])
    }

    func testMixedProfileTurnsEverythingOn() {
        XCTAssertEqual(dict(.mixed), ["autoRestore": true, "contextualEnglish": true, "retroactiveEnglish": true,
                                      "englishByFrequency": true, "collisionPrefersVietnamese": true])
    }

    /// macOS không có chế độ tiếng Anh trong VietTelex ⇒ `en` = `mixed`.
    func testEnglishProfileEqualsMixedOnMac() {
        XCTAssertEqual(dict(.en), dict(.mixed))
    }

    /// Mọi key hồ sơ ghi đều là công tắc AppState thật (không có key "chế độ" nào).
    func testProfileKeysAreRealSettings() {
        for p in TypingProfile.allCases {
            for (k, _) in OnboardingLogic.values(for: p) {
                XCTAssertNotNil(AppState.shared.mixedSetting(k), k)
                XCTAssertTrue(OnboardingLogic.mixedKeys.contains(k), k)
            }
        }
    }

    func testTurnedOnListsOnlyEnabledSwitches() {
        XCTAssertEqual(OnboardingLogic.turnedOn(by: .vi), ["autoRestore", "contextualEnglish", "collisionPrefersVietnamese"])
        XCTAssertEqual(OnboardingLogic.turnedOn(by: .mixed), OnboardingLogic.mixedKeys)
    }

    func testApplyWritesValuesAndProfileOnly() {
        var written: [String: Bool] = [:]
        OnboardingLogic.apply(.mixed, defaults: defaults) { written[$0] = $1 }
        XCTAssertEqual(written, dict(.mixed))
        XCTAssertEqual(defaults.string(forKey: OnboardingLogic.profileKey), "mixed")
        XCTAssertEqual(Set((defaults.persistentDomain(forName: suiteName) ?? [:]).keys),
                       [OnboardingLogic.profileKey])
    }

    /// Áp hồ sơ qua AppState thật (suite test) rồi trả lại như cũ.
    func testApplyThroughAppStateSetsEngineToggles() {
        let s = AppState.shared
        let saved = OnboardingLogic.mixedKeys.map { ($0, s.mixedSetting($0)!) }
        defer { for (k, v) in saved { s.setMixedSetting(k, v) } }
        OnboardingLogic.apply(.vi, defaults: defaults) { s.setMixedSetting($0, $1) }
        XCTAssertFalse(s.retroactiveEnglish)
        XCTAssertFalse(s.englishByFrequency)
        OnboardingLogic.apply(.en, defaults: defaults) { s.setMixedSetting($0, $1) }
        XCTAssertTrue(s.autoRestore)
        XCTAssertTrue(s.contextualEnglish)
        XCTAssertTrue(s.retroactiveEnglish)
        XCTAssertTrue(s.englishByFrequency)
        XCTAssertTrue(s.collisionPrefersVietnamese)
        XCTAssertEqual(s.defaults.object(forKey: "englishByFrequency") as? Bool, true)
    }

    // MARK: người mới / người dùng cũ (§5)

    func testDecideMatrix() {
        XCTAssertEqual(OnboardingLogic.decide(onboardingDone: nil, hadPriorSettings: false), .showOnboarding)
        XCTAssertEqual(OnboardingLogic.decide(onboardingDone: nil, hadPriorSettings: true), .upgrade)
        XCTAssertEqual(OnboardingLogic.decide(onboardingDone: false, hadPriorSettings: true), .showOnboarding)
        XCTAssertEqual(OnboardingLogic.decide(onboardingDone: true, hadPriorSettings: false), .nothing)
        XCTAssertEqual(OnboardingLogic.decide(onboardingDone: true, hadPriorSettings: true), .nothing)
    }

    func testPriorSettingsDetection() {
        XCTAssertFalse(OnboardingLogic.hasPriorSettings(nil))
        XCTAssertFalse(OnboardingLogic.hasPriorSettings([:]))
        // Mọi bản cũ ghi ít nhất probeV2Reset ở lần chạy đầu (AppState.init).
        XCTAssertTrue(OnboardingLogic.hasPriorSettings(["probeV2Reset": true]))
    }

    /// Bản nâng cấp: không onboarding, thẻ một lần, KHÔNG đổi giá trị nào của người dùng.
    func testUpgradeKeepsEveryValueAndQueuesCard() {
        let user: [String: Any] = ["probeV2Reset": true, "contextualEnglish": false, "autoRestore": false,
                                   "retroactiveEnglish": false, "collisionPrefersVietnamese": false,
                                   "switchHotkey": "ctrl-shift", "shortcuts": ["vn": "Việt Nam"]]
        for (k, v) in user { defaults.set(v, forKey: k) }
        let prior = OnboardingLogic.hasPriorSettings(defaults.persistentDomain(forName: suiteName))
        XCTAssertTrue(prior)
        XCTAssertEqual(OnboardingLogic.recordLaunch(defaults, hadPriorSettings: prior), .upgrade)

        let after = defaults.persistentDomain(forName: suiteName) ?? [:]
        for (k, v) in user {
            XCTAssertEqual(after[k] as? NSObject, v as? NSObject, k)
        }
        XCTAssertEqual(Set(after.keys).subtracting(user.keys), [OnboardingLogic.doneKey, OnboardingLogic.cardKey])
        XCTAssertEqual(defaults.object(forKey: OnboardingLogic.doneKey) as? Bool, true)
        XCTAssertTrue(OnboardingLogic.cardPending(defaults))
        XCTAssertNil(defaults.object(forKey: OnboardingLogic.profileKey))
        // Lần chạy sau: không làm gì nữa.
        XCTAssertEqual(OnboardingLogic.recordLaunch(defaults, hadPriorSettings: true), .nothing)
    }

    /// Người mới đóng app giữa chừng: lần sau suite đã có dữ liệu nhưng vẫn là người mới.
    func testFreshInstallStaysNewUntilFinished() {
        XCTAssertFalse(OnboardingLogic.hasPriorSettings(defaults.persistentDomain(forName: suiteName)))
        XCTAssertEqual(OnboardingLogic.recordLaunch(defaults, hadPriorSettings: false), .showOnboarding)
        XCTAssertEqual(defaults.object(forKey: OnboardingLogic.doneKey) as? Bool, false)
        defaults.set(true, forKey: "probeV2Reset")   // AppState.init của lần chạy đầu
        XCTAssertEqual(OnboardingLogic.recordLaunch(defaults, hadPriorSettings: true), .showOnboarding)
        XCTAssertFalse(OnboardingLogic.cardPending(defaults))
        OnboardingLogic.finish(defaults)
        XCTAssertEqual(OnboardingLogic.recordLaunch(defaults, hadPriorSettings: true), .nothing)
    }

    /// "Bỏ qua" ở màn 1 = giữ mặc định: chỉ onboardingDone được ghi, không công tắc nào.
    func testSkipKeepsDefaults() {
        OnboardingLogic.recordLaunch(defaults, hadPriorSettings: false)
        OnboardingLogic.finish(defaults)
        let keys = Set((defaults.persistentDomain(forName: suiteName) ?? [:]).keys)
        XCTAssertEqual(keys, [OnboardingLogic.doneKey])
        for k in OnboardingLogic.mixedKeys { XCTAssertNil(defaults.object(forKey: k), k) }
    }

    func testCardDismissIsPermanent() {
        XCTAssertEqual(OnboardingLogic.recordLaunch(defaults, hadPriorSettings: true), .upgrade)
        XCTAssertTrue(OnboardingLogic.cardPending(defaults))
        OnboardingLogic.dismissCard(defaults)
        XCTAssertFalse(OnboardingLogic.cardPending(defaults))
        XCTAssertEqual(OnboardingLogic.recordLaunch(defaults, hadPriorSettings: true), .nothing)
        XCTAssertFalse(OnboardingLogic.cardPending(defaults))
    }

    /// Thẻ trong Cài đặt đọc/ghi đúng key (suite test của AppState).
    func testSettingsModelCard() {
        let d = AppState.shared.defaults
        let saved = d.object(forKey: OnboardingLogic.cardKey)
        defer { d.set(saved, forKey: OnboardingLogic.cardKey) }
        d.set(true, forKey: OnboardingLogic.cardKey)
        let model = SettingsModel(selected: .typing)
        XCTAssertTrue(model.mixedCardPending)
        model.dismissMixedCard(reveal: true)
        XCTAssertFalse(model.mixedCardPending)
        XCTAssertTrue(model.revealMixed)
        XCTAssertFalse(SettingsModel(selected: .typing).mixedCardPending)
    }

    // MARK: bộ chọn nhanh (§4): khớp đúng / Tuỳ chỉnh / xác nhận / áp

    func testPickerExactMatch() {
        XCTAssertEqual(OnboardingLogic.match(dict(.vi), lastChosen: nil), .vi)
        XCTAssertEqual(OnboardingLogic.match(dict(.vi), lastChosen: .en), .vi)
        // macOS: mixed ≡ en ⇒ en chỉ khi en là lần chọn gần nhất.
        XCTAssertEqual(OnboardingLogic.match(dict(.mixed), lastChosen: nil), .mixed)
        XCTAssertEqual(OnboardingLogic.match(dict(.mixed), lastChosen: .vi), .mixed)
        XCTAssertEqual(OnboardingLogic.match(dict(.mixed), lastChosen: .mixed), .mixed)
        XCTAssertEqual(OnboardingLogic.match(dict(.en), lastChosen: .en), .en)
    }

    func testPickerCustomWhenAnySwitchDiffers() {
        for p in TypingProfile.allCases {
            for k in OnboardingLogic.mixedKeys {
                var cur = dict(p)
                cur[k]!.toggle()
                // vi ↔ mixed khác nhau 2 công tắc ⇒ lật 1 công tắc không bao giờ ra hồ sơ khác.
                XCTAssertNil(OnboardingLogic.match(cur, lastChosen: p), "\(p) \(k)")
            }
        }
    }

    func testPickerConfirmation() {
        // Đang khớp hồ sơ ⇒ đổi thẳng.
        XCTAssertEqual(OnboardingLogic.changes(from: dict(.vi), to: .mixed), ["retroactiveEnglish", "englishByFrequency"])
        XCTAssertFalse(OnboardingLogic.needsConfirmation(dict(.vi), applying: .mixed, lastChosen: nil))
        XCTAssertFalse(OnboardingLogic.needsConfirmation(dict(.mixed), applying: .en, lastChosen: .mixed))
        // Tuỳ chỉnh ⇒ hỏi, liệt kê đúng công tắc đổi.
        var custom = dict(.vi)
        custom["autoRestore"] = false
        XCTAssertTrue(OnboardingLogic.needsConfirmation(custom, applying: .mixed, lastChosen: .vi))
        XCTAssertEqual(OnboardingLogic.changes(from: custom, to: .mixed),
                       ["autoRestore", "retroactiveEnglish", "englishByFrequency"])
        XCTAssertEqual(OnboardingLogic.changes(from: dict(.en), to: .mixed), [])
    }

    /// Bộ chọn trong Cài đặt: áp qua model (AppState suite test), xác nhận khi Tuỳ chỉnh.
    func testSettingsModelPicker() {
        let s = AppState.shared
        let saved = OnboardingLogic.mixedKeys.map { ($0, s.mixedSetting($0)!) }
        let savedProfile = s.defaults.object(forKey: OnboardingLogic.profileKey)
        defer {
            for (k, v) in saved { s.setMixedSetting(k, v) }
            s.defaults.set(savedProfile, forKey: OnboardingLogic.profileKey)
        }
        OnboardingLogic.apply(.vi, defaults: s.defaults) { s.setMixedSetting($0, $1) }
        let model = SettingsModel(selected: .typing)
        XCTAssertEqual(model.matchedProfile, .vi)
        model.pickProfile(.en)                       // khớp vi ⇒ áp ngay
        XCTAssertNil(model.confirmingProfile)
        XCTAssertEqual(model.matchedProfile, .en)
        XCTAssertTrue(s.retroactiveEnglish && s.englishByFrequency)
        XCTAssertEqual(s.defaults.string(forKey: OnboardingLogic.profileKey), "en")
        model.pickProfile(.mixed)                    // mixed ≡ en ⇒ chỉ đổi lần chọn
        XCTAssertEqual(model.matchedProfile, .mixed)
        model.autoRestore = false                    // tự chỉnh ⇒ Tuỳ chỉnh
        XCTAssertNil(model.matchedProfile)
        model.pickProfile(.vi)
        XCTAssertEqual(model.confirmingProfile, .vi)
        XCTAssertFalse(s.autoRestore)                // chưa áp khi chưa xác nhận
        XCTAssertTrue(model.profileChangeList(.vi).contains("•"))
        model.applyProfile(.vi)
        XCTAssertNil(model.confirmingProfile)
        XCTAssertEqual(model.matchedProfile, .vi)
        XCTAssertTrue(s.autoRestore)
        XCTAssertFalse(s.retroactiveEnglish)
    }

    func testSamplesPerProfile() {
        for p in TypingProfile.allCases { XCTAssertGreaterThanOrEqual(OnboardingLogic.samples(for: p).count, 2) }
        XCTAssertTrue(OnboardingLogic.samples(for: .mixed).contains("Mai họp team lúc 9h, nhớ confirm nhé"))
    }

    func testVietnameseStringsExist() throws {
        let path = try XCTUnwrap(Bundle.main.path(forResource: "vi", ofType: "lproj"))
        let vi = try XCTUnwrap(Bundle(path: path))
        let expect = ["How do you usually type?": "Bạn thường gõ thế nào?",
                      "Mostly Vietnamese": "Chủ yếu tiếng Việt",
                      "Lots of Vietnamese + English": "Việt + Anh nhiều",
                      "Mostly English": "Chủ yếu tiếng Anh",
                      "Try typing": "Gõ thử",
                      "Skip": "Bỏ qua",
                      "Mixed Vietnamese/English typing": "Gõ mixed Việt/Anh",
                      "Quick choice": "Chọn nhanh",
                      "Custom": "Tuỳ chỉnh",
                      "Apply “%@”?": "Áp dụng “%@”?",
                      "Switches you changed yourself will change:": "Các công tắc bạn đã tự chỉnh sẽ đổi:"]
        for (k, v) in expect { XCTAssertEqual(vi.localizedString(forKey: k, value: nil, table: nil), v) }
        for key in OnboardingLogic.mixedKeys {
            let en = OnboardingModel.title(key)
            XCTAssertNotEqual(vi.localizedString(forKey: en, value: nil, table: nil), en, key)
        }
    }
}
