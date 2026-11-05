// Onboarding người dùng mới (docs/ONBOARDING-SPEC.md §2): màn 1 "Bạn thường gõ thế nào?" (3 thẻ
// hồ sơ), màn 2 "Gõ thử" (ô gõ + câu mẫu + danh sách vừa bật, mỗi dòng một công tắc). "Bỏ qua" ở
// mọi màn = giữ nguyên cài đặt. Phần thuần ở Shared/OnboardingProfile.swift. Song sinh Android
// ui/Onboarding.kt. Thẻ một lần cho người dùng cũ (§5): MixedTypingTipCard.
import SwiftUI

private let onboardingDefaults = UserDefaults(suiteName: AppFlavor.appGroup)

struct OnboardingView: View {
    let keyboardEnabled: Bool
    let onClose: () -> Void

    @State private var step: OnboardingFlow.Screen
    @State private var profile: OnboardingProfile?
    /// Màn 2 mở ngay sau màn 1 (cùng phiên) ⇒ có nút "Chọn lại".
    @State private var cameFromChoose = false

    init(start: OnboardingFlow.Screen, keyboardEnabled: Bool, onClose: @escaping () -> Void) {
        self.keyboardEnabled = keyboardEnabled
        self.onClose = onClose
        _step = State(initialValue: start)
        _profile = State(initialValue: onboardingDefaults?.string(forKey: OnboardingFlow.profileKey)
            .flatMap(OnboardingProfile.init(rawValue:)))
    }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .choose: OnboardingChooseScreen(selected: profile, onPick: pick)
                case .tryIt: OnboardingTryScreen(profile: profile ?? .vi, onDone: finish)
                }
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .toolbar {
                if step == .tryIt && cameFromChoose {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { withAnimation { step = .choose } } label: {
                            Label(L("Chọn lại"), systemImage: "chevron.left").labelStyle(.titleAndIcon)
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("Bỏ qua")) { finish() }
                }
            }
            .tint(accentBlue)
        }
        .interactiveDismissDisabled()
    }

    /// Chọn hồ sơ: ghi giá trị ngay (§3). Bàn phím chưa bật ⇒ đóng, màn 2 chờ tới khi bật.
    private func pick(_ p: OnboardingProfile) {
        OnboardingSettings.apply(p, to: onboardingDefaults)
        profile = p
        if keyboardEnabled {
            cameFromChoose = true
            withAnimation { step = .tryIt }
        } else {
            onClose()
        }
    }

    private func finish() {
        OnboardingFlow.finish(onboardingDefaults)
        onClose()
    }
}

/// Màn 1 — ba thẻ lớn, mỗi thẻ một câu ví dụ.
struct OnboardingChooseScreen: View {
    var selected: OnboardingProfile?
    let onPick: (OnboardingProfile) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(L("Bạn thường gõ thế nào?"))
                    .font(.largeTitle.bold())
                    .fixedSize(horizontal: false, vertical: true)
                Text(L("Chọn một — VietTelex bật sẵn những gì hợp với bạn. Đổi lại lúc nào cũng được ở Kiểu Gõ → Gõ lẫn tiếng Anh."))
                    .font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 6)
                ForEach(OnboardingProfile.allCases, id: \.self) { p in
                    Button { onPick(p) } label: { card(p) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
    }

    private func card(_ p: OnboardingProfile) -> some View {
        HStack(alignment: .center, spacing: 14) {
            ProfileBadge(profile: p)
            VStack(alignment: .leading, spacing: 4) {
                Text(L(p.titleKey)).font(.headline).foregroundStyle(.primary)
                Text("“\(p.example)”").font(.subheadline).italic().foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Image(systemName: selected == p ? "checkmark.circle.fill" : "chevron.right")
                .font(selected == p ? .title3 : .footnote.weight(.semibold))
                .foregroundStyle(selected == p ? AnyShapeStyle(accentBlue) : AnyShapeStyle(.tertiary))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(selected == p ? accentBlue : Color.primary.opacity(0.06), lineWidth: selected == p ? 2 : 0.5))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected == p ? [.isButton, .isSelected] : .isButton)
    }
}

/// Nhãn VI / VI+EN / EN trên thẻ hồ sơ.
struct ProfileBadge: View {
    let profile: OnboardingProfile
    var body: some View {
        Text(profile == .vi ? "VI" : profile == .mixed ? "VI+EN" : "EN")
            .font(.system(size: profile == .mixed ? 11 : 15, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 46, height: 46)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(profile == .vi ? Color.red.opacity(0.85) : profile == .mixed ? Color.teal : accentBlue))
            .accessibilityHidden(true)
    }
}

/// Màn 2 — gõ thử bằng chính bàn phím VietTelex + những gì vừa bật (tắt ngay được).
struct OnboardingTryScreen: View {
    let profile: OnboardingProfile
    let onDone: () -> Void

    @State private var text = ""
    @FocusState private var focused: Bool
    @AppStorage("autoRestore", store: onboardingDefaults) private var autoRestore = true
    @AppStorage("contextualEnglish", store: onboardingDefaults) private var contextualEnglish = true
    @AppStorage(RetroEnglishUI.autoKey, store: onboardingDefaults) private var retroEnglish = false
    @AppStorage(RetroEnglishUI.frequencyKey, store: onboardingDefaults) private var englishByFrequency = false
    @AppStorage("spaceSwipeLanguage", store: onboardingDefaults) private var spaceSwipeLanguage = false
    @AppStorage("swipeEnglish", store: onboardingDefaults) private var swipeEnglish = true
    @AppStorage("swipeTyping", store: onboardingDefaults) private var swipeTyping = false
    @AppStorage("vniMode", store: onboardingDefaults) private var vniMode = false

    /// Công tắc hồ sơ này BẬT (§2 "danh sách ngắn những gì vừa bật"); mục phụ thuộc theo đúng điều
    /// kiện hiện như nhóm Gõ lẫn tiếng Anh; "Vuốt từ tiếng Anh" chỉ khi Gõ vuốt đang bật.
    private var shownKeys: [String] {
        OnboardingSettings.keys.filter { k in
            guard profile.values[k] == true else { return false }
            switch k {
            case RetroEnglishUI.autoKey, RetroEnglishUI.frequencyKey:
                return RetroEnglishUI.switchVisible(contextualEnglish: contextualEnglish, vniMode: vniMode)
            case "swipeEnglish": return swipeTyping
            default: return true
            }
        }
    }

    private func binding(_ k: String) -> Binding<Bool> {
        switch k {
        case "autoRestore": return $autoRestore
        case "contextualEnglish": return $contextualEnglish
        case RetroEnglishUI.autoKey: return $retroEnglish
        case RetroEnglishUI.frequencyKey: return $englishByFrequency
        case "spaceSwipeLanguage": return $spaceSwipeLanguage
        default: return $swipeEnglish
        }
    }

    private var keyboardHint: String {
        switch profile {
        case .en: return L("Bàn phím bắt đầu ở Tiếng Anh — vuốt nhanh phím cách sang trái/phải để gõ tiếng Việt.")
        case .mixed: return L("Cứ gõ lẫn Anh và Việt: check, mail, team giữ nguyên. Vuốt nhanh phím cách để đổi hẳn sang Tiếng Anh.")
        case .vi: return L("Telex: vieejt → việt. Từ tiếng Anh như google, github vẫn giữ nguyên.")
        }
    }

    var body: some View {
        List {
            Section {
                ProfileSummaryRow(profile: profile)
            }
            Section {
                TextField(L("Thử gõ tại đây…"), text: $text, axis: .vertical)
                    .lineLimit(2...5)
                    .textInputAutocapitalization(.sentences)
                    .focused($focused)
            } header: { Text(L("Gõ thử")) } footer: { Text(keyboardHint) }
            Section(L("Câu mẫu")) {
                ForEach(profile.samples, id: \.self) { s in
                    Text(s).foregroundStyle(.secondary)
                }
            }
            if !shownKeys.isEmpty {
                Section {
                    ForEach(shownKeys, id: \.self) { k in
                        Toggle(L(OnboardingSettings.titleKey(k)), isOn: binding(k)).tint(.green)
                    }
                } header: { Text(L("Vừa bật")) } footer: {
                    Text(L("Tắt ngay ở đây nếu không cần. Chỉnh thêm ở Kiểu Gõ → Gõ lẫn tiếng Anh."))
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(L("Gõ thử"))
        .navigationBarTitleDisplayMode(.large)
        .safeAreaInset(edge: .bottom) {
            Button(action: onDone) {
                Text(L("Xong")).font(.headline).frame(maxWidth: .infinity)
            }
            .prominentGlassButton()
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { focused = true }
        }
    }
}

private struct ProfileSummaryRow: View {
    let profile: OnboardingProfile
    var body: some View {
        HStack(spacing: 12) {
            ProfileBadge(profile: profile)
            VStack(alignment: .leading, spacing: 2) {
                Text(L(profile.titleKey)).font(.headline)
                Text("“\(profile.example)”").font(.footnote).italic().foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

/// Thẻ một lần cho người dùng cũ (§5): chạm = mở nhóm "Gõ lẫn tiếng Anh" ngay trong tab Kiểu Gõ;
/// đóng hay xem đều không hiện lại.
struct MixedTypingTipCard: View {
    let onOpen: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "globe")
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 29, height: 29)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.teal))
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L("Bạn hay gõ trộn Anh/Việt?")).font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(L("Xem nhóm Gõ lẫn tiếng Anh mới") + " ›").font(.footnote)
                        .foregroundStyle(accentBlue)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button(action: onDismiss) {
                Image(systemName: "xmark").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(L("Đóng"))
        }
        .padding(.vertical, 4)
    }
}
