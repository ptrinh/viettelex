// Onboarding người dùng mới + bộ chọn hồ sơ nhanh — docs/ONBOARDING-SPEC.md §2/§3/§5.
// Phần THUẦN (không SwiftUI) để test được: giá trị từng hồ sơ, nhận diện hồ sơ đang khớp
// ("Tuỳ chỉnh" khi không khớp), màn onboarding nào cần hiện, nhận diện người dùng cũ khi nâng
// cấp, yêu cầu ngôn ngữ khởi đầu cho bàn phím. Song sinh Android
// keyboard/…/Onboarding.kt — sửa ở đây thì sửa y hệt bên kia (OnboardingTests hai bên).
//
// Hồ sơ = bộ cài đặt cụ thể: chọn hồ sơ GHI THẲNG giá trị vào từng key hiện có rồi thôi —
// không lưu "chế độ" nào chi phối về sau. Chỉ lưu thêm `onboardingDone` + `onboardingProfile`
// (hiển thị/hỗ trợ), cờ một lần của thẻ người dùng cũ, và yêu cầu ngôn ngữ cho bàn phím.
// Không key nào ở đây nằm trong sao lưu / đồng bộ iCloud (BackupSettings) — không gửi đi đâu.
import Foundation

enum OnboardingProfile: String, CaseIterable, Hashable {
    case vi, mixed, en

    /// Tên trên thẻ / bộ chọn — cùng tên + thứ tự trên iOS và Android.
    var titleKey: String {
        switch self {
        case .vi: return LK("Chủ yếu tiếng Việt")
        case .mixed: return LK("Việt + Anh nhiều")
        case .en: return LK("Chủ yếu tiếng Anh")
        }
    }

    /// Câu ví dụ trên thẻ (§2) — là chữ mẫu, không dịch.
    var example: String {
        switch self {
        case .vi: return "Chiều nay mình đi cà phê nhé"
        case .mixed: return "Chiều nay họp team, nhớ check mail nha"
        case .en: return "See you at the meeting, nhớ mang laptop nhé"
        }
    }

    /// Câu mẫu ở màn "Gõ thử" — không dịch.
    var samples: [String] {
        switch self {
        case .vi: return ["Chiều nay mình đi cà phê nhé", "Cảm ơn bạn nhiều lắm"]
        case .mixed: return ["Mai họp team lúc 9h, nhớ confirm nhé", "Gửi mình file slide trước deadline nha",
                             "His car is very fast"]
        case .en: return ["See you at the meeting, nhớ mang laptop nhé", "Thanks, I will check my email tonight"]
        }
    }

    /// Ngôn ngữ khởi đầu của bàn phím ("vi" | "en", §3: hồ sơ `en` bắt đầu ở Tiếng Anh).
    var keyboardLanguage: String { self == .en ? "en" : "vi" }

    /// Giá trị ghi vào từng key (bảng §3; `en` = như `mixed`). Thứ tự = thứ tự danh sách ở màn
    /// Gõ thử. `vi` = mặc định hiện tại (ngữ cảnh, vuốt từ tiếng Anh giữ mặc định).
    var values: [String: Bool] {
        switch self {
        case .vi: return OnboardingSettings.defaults
        case .mixed, .en:
            return Dictionary(uniqueKeysWithValues: OnboardingSettings.keys.map { ($0, true) })
        }
    }
}

enum OnboardingSettings {
    /// Key hiện có (KHÔNG đổi tên) mà hồ sơ ghi vào — thứ tự như nhóm "Gõ lẫn tiếng Anh".
    /// `collisionPrefersVietnamese` chỉ có trên macOS.
    static let keys = ["autoRestore", "contextualEnglish", RetroEnglishUI.autoKey, RetroEnglishUI.frequencyKey,
                       "spaceSwipeLanguage", "swipeEnglish"]

    /// Mặc định khi chưa ghi (khớp KeyboardSettings / @AppStorage các màn cài đặt).
    static let defaults: [String: Bool] = [
        "autoRestore": true, "contextualEnglish": true, RetroEnglishUI.autoKey: false,
        RetroEnglishUI.frequencyKey: false, "spaceSwipeLanguage": false, "swipeEnglish": true,
    ]

    /// Giá trị đang có (thiếu ⇒ mặc định).
    static func current(_ read: (String) -> Bool?) -> [String: Bool] {
        Dictionary(uniqueKeysWithValues: keys.map { ($0, read($0) ?? defaults[$0]!) })
    }

    static func current(_ d: UserDefaults?) -> [String: Bool] {
        current { d?.object(forKey: $0) as? Bool }
    }

    /// Hồ sơ khớp ĐÚNG cài đặt hiện tại; nil = "Tuỳ chỉnh". `mixed` và `en` cùng bộ công tắc (chỉ
    /// khác ngôn ngữ khởi đầu — trạng thái bàn phím, đổi bằng vuốt phím cách) ⇒ tô `en` khi lần
    /// chọn gần nhất là `en`, còn lại `mixed`.
    static func match(_ current: [String: Bool], lastChosen: OnboardingProfile?) -> OnboardingProfile? {
        if current == OnboardingProfile.vi.values { return .vi }
        if current == OnboardingProfile.mixed.values { return lastChosen == .en ? .en : .mixed }
        return nil
    }

    /// Key sẽ bị đổi nếu áp `profile` (theo thứ tự `keys`).
    static func changes(from current: [String: Bool], to profile: OnboardingProfile) -> [String] {
        let target = profile.values
        return keys.filter { current[$0] != target[$0] }
    }

    /// Hỏi xác nhận khi áp sẽ đổi công tắc người dùng đã tự chỉnh: cài đặt đang "Tuỳ chỉnh"
    /// (không khớp hồ sơ nào) và có ít nhất một công tắc đổi.
    static func needsConfirmation(_ current: [String: Bool], applying profile: OnboardingProfile,
                                  lastChosen: OnboardingProfile?) -> Bool {
        match(current, lastChosen: lastChosen) == nil && !changes(from: current, to: profile).isEmpty
    }

    /// Ghi hồ sơ: giá trị §3 + `onboardingProfile` + yêu cầu ngôn ngữ khởi đầu cho bàn phím.
    static func apply(_ profile: OnboardingProfile, to d: UserDefaults?, now: Date = Date()) {
        guard let d else { return }
        for k in keys { d.set(profile.values[k]!, forKey: k) }
        d.set(profile.rawValue, forKey: OnboardingFlow.profileKey)
        d.set(KeyboardLanguageRequest.encode(profile.keyboardLanguage, stamp: now.timeIntervalSince1970),
              forKey: KeyboardLanguageRequest.key)
    }

    /// Tên hiển thị của một key (dòng trong hộp xác nhận / danh sách Gõ thử).
    static func titleKey(_ key: String) -> String {
        switch key {
        case "autoRestore": return LK("Tự khôi phục từ tiếng Anh")
        case "contextualEnglish": return LK("Quyết định theo ngữ cảnh")
        case RetroEnglishUI.autoKey: return LK("Tự sửa từ phía trước")
        case RetroEnglishUI.frequencyKey: return LK("Đoán từ trùng theo tần suất")
        case "spaceSwipeLanguage": return LK("Vuốt phím cách đổi Tiếng Việt / Tiếng Anh")
        case "swipeEnglish": return LK("Vuốt từ tiếng Anh")
        default: return key
        }
    }
}

enum OnboardingFlow {
    static let doneKey = "onboardingDone"
    static let profileKey = "onboardingProfile"
    /// Thẻ một lần cho người dùng cũ (§5): true = còn chờ hiện; đóng/xem ⇒ false.
    static let tipKey = "mixedTypingTip"

    enum Screen: Equatable { case choose, tryIt }

    /// Màn cần hiện: xong rồi ⇒ không gì; chưa chọn hồ sơ ⇒ màn 1; đã chọn ⇒ màn 2 khi bàn phím
    /// đã bật (chưa bật thì chờ — hiện một lần sau khi bật).
    static func screen(done: Bool, profile: OnboardingProfile?, keyboardEnabled: Bool) -> Screen? {
        if done { return nil }
        guard profile != nil else { return .choose }
        return keyboardEnabled ? .tryIt : nil
    }

    static func screen(_ d: UserDefaults?, keyboardEnabled: Bool) -> Screen? {
        screen(done: d?.bool(forKey: doneKey) ?? true,
               profile: d?.string(forKey: profileKey).flatMap(OnboardingProfile.init(rawValue:)),
               keyboardEnabled: keyboardEnabled)
    }

    /// Key chỉ bàn phím tự ghi khi chạy (không phải người dùng chỉnh) — KHÔNG tính là "đã có cài
    /// đặt": người mới bật bàn phím trước khi mở app vẫn được onboarding.
    static let keyboardRuntimeKeys: Set<String> = ["kbLastSeen", "kbFullAccess", "pasteNoPrompt"]
    /// Cờ do app bản cũ ghi mỗi lần mở (từ 12/10/2026, KeyGeometry.RowAdjust) ⇒ đã từng mở app.
    static let appLaunchMarkers: Set<String> = ["rowAdjustStockBase", "rowAdjustDefaultFix"]

    /// Lần đầu bản này chạy (chưa có `doneKey`): đã có cài đặt cũ ⇒ người dùng cũ: xong onboarding
    /// + thẻ một lần; chưa có ⇒ người mới: ghi `doneKey = false` (tường minh, để lần sau không
    /// đoán lại khi app/bàn phím đã ghi thêm key). Có `doneKey` rồi ⇒ nil (không đổi gì).
    /// `settingKeys`: key cài đặt người dùng (BackupSettings…).
    static func upgradeWrites(existingKeys: Set<String>, settingKeys: Set<String>) -> [String: Bool]? {
        guard !existingKeys.contains(doneKey) else { return nil }
        let markers = settingKeys.union(appLaunchMarkers).subtracting(keyboardRuntimeKeys)
        return existingKeys.isDisjoint(with: markers) ? [doneKey: false] : [doneKey: true, tipKey: true]
    }

    /// Gọi ĐẦU TIÊN lúc app khởi động — trước mọi chuyển đổi khác ghi key vào App Group.
    @discardableResult
    static func migrate(_ d: UserDefaults?, settingKeys: Set<String>) -> [String: Bool]? {
        guard let d, let w = upgradeWrites(existingKeys: Set(d.dictionaryRepresentation().keys),
                                           settingKeys: settingKeys) else { return nil }
        for (k, v) in w { d.set(v, forKey: k) }
        return w
    }

    /// Màn 1 "Bỏ qua" / màn 2 "Xong": chỉ ghi `doneKey` — giữ nguyên mọi cài đặt.
    static func finish(_ d: UserDefaults?) { d?.set(true, forKey: doneKey) }

    static func dismissTip(_ d: UserDefaults?) { d?.set(false, forKey: tipKey) }
}

/// Yêu cầu ngôn ngữ khởi đầu app → bàn phím. Ngôn ngữ đang gõ là trạng thái RIÊNG của bàn phím
/// (iOS: UserDefaults của extension, app không ghi được; Android: prefs riêng của IME) ⇒ app ghi
/// "en@<mốc>" vào App Group; bàn phím lần hiện kế tiếp thấy yêu cầu MỚI (khác yêu cầu đã áp) thì
/// đặt ngôn ngữ một lần, rồi người dùng vuốt phím cách đổi như thường.
enum KeyboardLanguageRequest {
    static let key = "keyboardLanguageRequest"
    /// Bàn phím (UserDefaults riêng) nhớ yêu cầu đã áp.
    static let appliedKey = "keyboardLanguageRequestApplied"

    static func encode(_ language: String, stamp: TimeInterval) -> String {
        "\(language)@\(Int64(stamp * 1000))"
    }

    /// Ngôn ngữ cần đặt ("vi" | "en") nếu có yêu cầu chưa áp; nil = không làm gì.
    static func pending(request: String?, applied: String?) -> String? {
        guard let request, request != applied,
              let lang = request.split(separator: "@").first.map(String.init),
              lang == "vi" || lang == "en" else { return nil }
        return lang
    }
}
