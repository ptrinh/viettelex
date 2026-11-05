// Onboarding.swift
// Onboarding người dùng mới (docs/ONBOARDING-SPEC.md §2/§3/§5), bản macOS.
//
//  • Màn 1 "Bạn thường gõ thế nào?" — 3 hồ sơ vi / mixed / en. Chọn = GHI THẲNG giá trị
//    vào từng công tắc (OnboardingLogic.values) rồi thôi; chỉ lưu thêm onboardingDone +
//    onboardingProfile (hiển thị, không điều khiển gì). macOS không có "chế độ tiếng Anh"
//    trong VietTelex (tiếng Anh = đổi nguồn nhập của macOS) ⇒ `en` ghi y như `mixed`.
//  • Màn 2 "Gõ thử" — ô gõ thử (gõ bằng chính VietTelex như mọi app khác) + câu mẫu + công
//    tắc của những gì vừa bật để tắt ngay.
//  • "Bỏ qua" ở mọi màn: màn 1 = giữ nguyên mặc định; màn 2 = giữ hồ sơ vừa chọn.
//  • Người dùng cũ (suite đã có dữ liệu khi process khởi động, AppState.hadPriorSettingsAtLaunch):
//    không bao giờ thấy onboarding; đặt onboardingDone + bật thẻ một lần trong Cài đặt → Gõ phím
//    chỉ tới nhóm "Gõ mixed Việt/Anh". Không đổi bất kỳ giá trị nào.
//  • Không telemetry: lựa chọn chỉ nằm trong suite cài đặt của máy này.
// macOS chưa từng có màn chào riêng: cửa sổ này là màn chào, hiện lần đầu VietTelex được chọn
// làm nguồn nhập (process IME chỉ chạy khi đó). Không bao giờ hiện trong XCTest host.

import AppKit
import SwiftUI

/// Hồ sơ gõ (spec §3). rawValue = giá trị lưu ở `onboardingProfile`.
enum TypingProfile: String, CaseIterable {
    case vi, mixed, en
}

/// Phần thuần (test được với suite riêng) — không UI, không AppState.shared.
enum OnboardingLogic {
    static let doneKey = "onboardingDone"
    static let profileKey = "onboardingProfile"
    /// Thẻ "Bạn hay gõ trộn Anh/Việt?" cho người dùng cũ: true = còn chờ hiện; đóng ⇒ false.
    static let cardKey = "mixedTypingCardPending"

    /// Công tắc nhóm "Gõ mixed Việt/Anh" mà macOS có, theo thứ tự hiện ở màn Gõ thử.
    static let mixedKeys = ["autoRestore", "contextualEnglish", "retroactiveEnglish",
                            "englishByFrequency", "collisionPrefersVietnamese"]

    /// Bảng §3 (+ §10: englishByFrequency BẬT cho mixed và en). `vi` = mặc định hiện tại.
    static func values(for p: TypingProfile) -> [(key: String, value: Bool)] {
        let mixed = p != .vi
        return [
            ("autoRestore", true),
            ("contextualEnglish", true),        // vi: "mặc định hiện tại" = BẬT (từ 15/08/2026)
            ("retroactiveEnglish", mixed),
            ("englishByFrequency", mixed),
            ("collisionPrefersVietnamese", true),
        ]
    }

    static func dict(_ p: TypingProfile) -> [String: Bool] {
        Dictionary(uniqueKeysWithValues: values(for: p).map { ($0.key, $0.value) })
    }

    /// Tên hồ sơ (khoá Localizable.strings) + câu ví dụ — màn 1 và bộ chọn nhanh dùng chung.
    static func title(_ p: TypingProfile) -> String {
        switch p {
        case .vi: return "Mostly Vietnamese"
        case .mixed: return "Lots of Vietnamese + English"
        case .en: return "Mostly English"
        }
    }

    static func example(_ p: TypingProfile) -> String {
        switch p {
        case .vi: return "Chiều nay mình đi cà phê nhé"
        case .mixed: return "Chiều nay họp team, nhớ check mail nha"
        case .en: return "See you at the meeting, nhớ mang laptop nhé"
        }
    }

    // MARK: Bộ chọn nhanh ở đầu nhóm "Gõ mixed Việt/Anh" (spec §4) — như iOS/Android
    // (iOS Shared/OnboardingProfile.swift OnboardingSettings, Android ui/MixedTyping.kt).

    /// Hồ sơ khớp ĐÚNG cài đặt hiện tại (`current`: đủ `mixedKeys`); nil = "Tuỳ chỉnh". macOS:
    /// `mixed` ≡ `en` (cùng bộ công tắc) ⇒ tô `en` khi lần chọn gần nhất là `en`, còn lại `mixed`.
    static func match(_ current: [String: Bool], lastChosen: TypingProfile?) -> TypingProfile? {
        let hits = TypingProfile.allCases.filter { dict($0) == current }
        guard let first = hits.first else { return nil }
        if let last = lastChosen, hits.contains(last) { return last }
        return first
    }

    /// Key sẽ đổi nếu áp `p` (theo thứ tự `mixedKeys`).
    static func changes(from current: [String: Bool], to p: TypingProfile) -> [String] {
        let target = dict(p)
        return mixedKeys.filter { current[$0] != target[$0] }
    }

    /// Hỏi xác nhận khi cài đặt đang "Tuỳ chỉnh" (người dùng đã tự chỉnh) và áp sẽ đổi ≥ 1 công
    /// tắc; đang khớp một hồ sơ thì đổi thẳng.
    static func needsConfirmation(_ current: [String: Bool], applying p: TypingProfile,
                                  lastChosen: TypingProfile?) -> Bool {
        match(current, lastChosen: lastChosen) == nil && !changes(from: current, to: p).isEmpty
    }

    /// Những công tắc hồ sơ vừa BẬT — danh sách ở màn Gõ thử.
    static func turnedOn(by p: TypingProfile) -> [String] {
        values(for: p).filter(\.value).map(\.key)
    }

    /// Suite có dữ liệu từ trước (bản cũ) — xem AppState.hadPriorSettingsAtLaunch.
    static func hasPriorSettings(_ domain: [String: Any]?) -> Bool {
        !(domain ?? [:]).isEmpty
    }

    enum LaunchDecision: Equatable {
        case showOnboarding   // người mới (hoặc người mới chưa đi hết onboarding lần trước)
        case upgrade          // người dùng cũ: đánh dấu xong + thẻ một lần
        case nothing
    }

    /// `onboardingDone`: nil = chưa có key. Người mới được ghi `false` NGAY lần đầu
    /// (`recordLaunch`) ⇒ lần chạy sau suite đã có dữ liệu nhưng vẫn nhận ra là người mới.
    static func decide(onboardingDone: Bool?, hadPriorSettings: Bool) -> LaunchDecision {
        switch onboardingDone {
        case true?: return .nothing
        case false?: return .showOnboarding
        case nil: return hadPriorSettings ? .upgrade : .showOnboarding
        }
    }

    /// Quyết định + ghi sổ lúc khởi động. Chỉ đụng doneKey / cardKey — không bao giờ đụng
    /// cài đặt gõ (người dùng cũ giữ nguyên mọi giá trị).
    @discardableResult
    static func recordLaunch(_ defaults: UserDefaults, hadPriorSettings: Bool) -> LaunchDecision {
        let done = defaults.object(forKey: doneKey) as? Bool
        let d = decide(onboardingDone: done, hadPriorSettings: hadPriorSettings)
        switch d {
        case .upgrade:
            defaults.set(true, forKey: doneKey)
            defaults.set(true, forKey: cardKey)
        case .showOnboarding:
            if done == nil { defaults.set(false, forKey: doneKey) }
        case .nothing:
            break
        }
        return d
    }

    /// Chọn hồ sơ: ghi từng công tắc qua `set` + hồ sơ (chỉ để hiển thị).
    static func apply(_ p: TypingProfile, defaults: UserDefaults, set: (String, Bool) -> Void) {
        for (k, v) in values(for: p) { set(k, v) }
        defaults.set(p.rawValue, forKey: profileKey)
    }

    /// Xong / Bỏ qua / đóng cửa sổ.
    static func finish(_ defaults: UserDefaults) {
        defaults.set(true, forKey: doneKey)
    }

    static func cardPending(_ defaults: UserDefaults) -> Bool {
        defaults.bool(forKey: cardKey)
    }

    static func dismissCard(_ defaults: UserDefaults) {
        defaults.set(false, forKey: cardKey)
    }

    /// Câu mẫu màn Gõ thử (spec §2).
    static func samples(for p: TypingProfile) -> [String] {
        switch p {
        case .vi: return ["Chiều nay mình đi cà phê nhé", "Cảm ơn bạn đã giúp đỡ hôm qua"]
        case .mixed: return ["Mai họp team lúc 9h, nhớ confirm nhé", "Chiều nay họp team, nhớ check mail nha",
                             "File design gửi qua email rồi đó"]
        case .en: return ["See you at the meeting, nhớ mang laptop nhé", "Please review the report trước thứ Sáu",
                          "Mai họp team lúc 9h, nhớ confirm nhé"]
        }
    }
}

// MARK: - Launch hook

enum Onboarding {
    /// Gọi một lần lúc khởi động (main.swift, ngoài XCTest host).
    static func launch() {
        let state = AppState.shared
        let d = OnboardingLogic.recordLaunch(state.defaults, hadPriorSettings: state.hadPriorSettingsAtLaunch)
        DebugLog.log("onboarding: launch decision \(d) (prior settings: \(state.hadPriorSettingsAtLaunch))")
        guard d == .showOnboarding else { return }
        pending = true
        // Một nhịp cho IMKServer/tap khởi động xong rồi mới mở cửa sổ.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { showIfReady() }
    }

    /// Chờ tới khi VietTelex THẬT SỰ là nguồn nhập đang chọn (ô gõ thử cần nó). main.swift
    /// gọi lại mỗi khi macOS đổi nguồn nhập.
    private(set) static var pending = false

    static func showIfReady() {
        guard pending, TelexInputController.isVietTelexSelected() else { return }
        pending = false
        OnboardingWindowController.shared.show()
    }
}

// MARK: - Window

final class OnboardingWindowController: NSObject, NSWindowDelegate {
    nonisolated(unsafe) static let shared = OnboardingWindowController()
    private var window: NSWindow?

    var isOpen: Bool { window != nil }

    func show() {
        NSApp.setActivationPolicy(.regular)
        if window == nil {
            let model = OnboardingModel { [weak self] in self?.window?.close() }
            let hosting = NSHostingController(rootView: OnboardingView().environmentObject(model))
            let win = NSWindow(contentViewController: hosting)
            win.title = VTLocalized("Welcome to VietTelex")
            win.styleMask = [.titled, .closable]
            win.setContentSize(NSSize(width: 560, height: 560))
            win.delegate = self
            win.isReleasedWhenClosed = false
            win.center()
            window = win
        }
        // Cùng lý do với SettingsWindowController.show: kích hoạt sau một nhịp.
        DispatchQueue.main.async { [weak self] in
            NSApp.activate(ignoringOtherApps: true)
            self?.window?.makeKeyAndOrderFront(nil)
        }
    }

    func windowWillClose(_ notification: Notification) {
        // Đóng ở bất kỳ màn nào = xong (spec: bỏ qua = giữ mặc định / giữ hồ sơ đã chọn).
        OnboardingLogic.finish(AppState.shared.defaults)
        if let win = notification.object as? NSWindow {
            win.delegate = nil
            win.contentViewController = nil
        }
        window = nil
        if SettingsWindowController.shared.currentWindow == nil {
            NSApp.setActivationPolicy(.accessory)
        }
        MemoryFootprint.relieveAfterTransientPeak()
    }
}

final class OnboardingModel: ObservableObject {
    enum Step { case question, tryIt }
    @Published var step: Step = .question
    @Published var profile: TypingProfile?
    @Published var trial = ""
    /// Giá trị công tắc đang hiện ở màn Gõ thử (key → bật/tắt); ghi thẳng vào AppState.
    @Published var toggles: [String: Bool] = [:]
    let close: () -> Void

    init(close: @escaping () -> Void) { self.close = close }

    func loc(_ key: String) -> String { VTLocalized(key) }

    func choose(_ p: TypingProfile) {
        let state = AppState.shared
        OnboardingLogic.apply(p, defaults: state.defaults) { state.setMixedSetting($0, $1) }
        profile = p
        toggles = Dictionary(uniqueKeysWithValues:
            OnboardingLogic.mixedKeys.map { ($0, state.mixedSetting($0) ?? false) })
        step = .tryIt
    }

    func binding(_ key: String) -> Binding<Bool> {
        Binding(get: { self.toggles[key] ?? false },
                set: { v in
                    self.toggles[key] = v
                    AppState.shared.setMixedSetting(key, v)
                })
    }

    /// Nhãn công tắc — cùng chuỗi với Cài đặt.
    static func title(_ key: String) -> String {
        switch key {
        case "autoRestore": return "Auto-restore invalid words"
        case "contextualEnglish": return "Context-based decision"
        case "retroactiveEnglish": return "Fix earlier words (experimental)"
        case "englishByFrequency": return "Guess colliding words by frequency (experimental)"
        case "collisionPrefersVietnamese": return "Prefer Vietnamese when a word is both English and Vietnamese"
        default: return key
        }
    }
}

struct OnboardingView: View {
    @EnvironmentObject var model: OnboardingModel

    var body: some View {
        Group {
            switch model.step {
            case .question: question
            case .tryIt: tryIt
            }
        }
        .padding(24)
        .frame(width: 560)
    }

    private var question: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(model.loc("How do you usually type?")).font(.title2.weight(.semibold))
            Text(model.loc("Pick the closest one — it only sets a few switches, which you can change any time in Settings → Typing → Mixed Vietnamese/English typing."))
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(TypingProfile.allCases, id: \.self) { p in
                card(p, title: OnboardingLogic.title(p), example: OnboardingLogic.example(p))
            }
            HStack {
                Spacer()
                Button(model.loc("Skip")) { model.close() }
                    .keyboardShortcut(.cancelAction)
            }
        }
    }

    private func card(_ p: TypingProfile, title: String, example: String) -> some View {
        Button { model.choose(p) } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.loc(title)).font(.headline)
                Text("“\(example)”").font(.callout).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.12)))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// Như Cài đặt: hai công tắc thử nghiệm chỉ có tác dụng (và chỉ hiện) khi bật ngữ cảnh.
    private var visibleKeys: [String] {
        let contextual = model.toggles["contextualEnglish"] ?? true
        return OnboardingLogic.turnedOn(by: model.profile ?? .vi).filter {
            contextual || ($0 != "retroactiveEnglish" && $0 != "englishByFrequency")
        }
    }

    private var tryIt: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.loc("Try typing")).font(.title2.weight(.semibold))
            Text(model.loc("Type one of these sentences below, using VietTelex as you would in any app:"))
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(OnboardingLogic.samples(for: model.profile ?? .vi), id: \.self) { s in
                    Text("• " + s).font(.callout)
                }
            }
            TextField(model.loc("Type here…"), text: $model.trial)
                .textFieldStyle(.roundedBorder)
            if !Accessibility.isTrusted {
                Text("⚠️ " + model.loc("No {PANE} permission — typing will be underlined"))
                    .font(.caption).foregroundStyle(.orange)
            }
            Divider()
            Text(model.loc("Turned on for you — switch off anything you don’t want:"))
                .font(.callout.weight(.medium))
            ForEach(visibleKeys, id: \.self) { key in
                Toggle(model.loc(OnboardingModel.title(key)), isOn: model.binding(key))
            }
            HStack {
                Button(model.loc("Skip")) { model.close() }
                Spacer()
                // Không gắn phím Return: Enter trong ô gõ thử không được đóng cửa sổ.
                Button(model.loc("Done")) { model.close() }
                    .prominentGlass()
            }
            .padding(.top, 4)
        }
    }
}
