// Nhóm thu gọn "Gõ lẫn tiếng Anh" ngay dưới mục Kiểu gõ (tab Kiểu Gõ) — docs/ONBOARDING-SPEC.md §4,
// docs/SETTINGS-CLEANUP-SPEC.md §1: cấp 1 = bộ chọn hồ sơ + vuốt phím cách + Từ điển cá nhân + dòng
// "Nâng cao" (MixedAdvancedPage). Danh mục + key ở Shared/MixedTypingUI.swift. Các công tắc đọc/ghi CÙNG key App Group như chỗ
// cũ (Chính tả, Phím & cử chỉ, Gõ vuốt, Kiểu gõ) — không đổi hành vi, sao lưu giữ nguyên.
// Song sinh Android ui/MixedTyping.kt.
import SwiftUI
import Combine

private let mixedDefaults = UserDefaults(suiteName: AppFlavor.appGroup)

/// Trạng thái nhóm trong phiên chạy app (KHÔNG lưu): mở app là thu gọn. Ô tìm cài đặt (tab
/// Tính Năng) đặt `request` ⇒ RootView chuyển sang Kiểu Gõ, mở nhóm, cuộn + tô sáng dòng.
final class MixedTypingFocus: ObservableObject {
    static let shared = MixedTypingFocus()
    @Published var expanded = false
    @Published var request: MixedTypingItem?
    @Published var highlighted: MixedTypingItem?
    /// Tăng mỗi lần `open` — RootView đang ở sẵn tab Kiểu Gõ thì cuộn ngay (không dựng lại tab).
    @Published var scrollTick = 0
    /// Dòng chờ cuộn tới khi danh sách tab Kiểu Gõ vừa dựng xong (RootView đổi tab ⇒ dựng lại).
    var pendingScroll: MixedTypingItem?

    /// Ô tìm kiếm chọn `item` (cấp 1 của nhóm): mở nhóm, ghi nhớ dòng cần cuộn tới (RootView đã chuyển tab).
    func open(_ item: MixedTypingItem) {
        expanded = true
        pendingScroll = item
        scrollTick += 1
    }

    /// Gọi từ danh sách tab Kiểu Gõ: cuộn tới dòng đang chờ (đợi List dựng hàng) + tô sáng.
    func scrollIfPending(_ proxy: ScrollViewProxy) {
        guard let t = pendingScroll else { return }
        pendingScroll = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            withAnimation { proxy.scrollTo(t, anchor: .center) }
            self.highlighted = t
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                withAnimation { if self.highlighted == t { self.highlighted = nil } }
            }
        }
    }

    #if DEBUG
    /// `-mixedTypingExpanded 1`: mở sẵn nhóm (chụp màn hình tự động).
    init() { expanded = UserDefaults.standard.bool(forKey: "mixedTypingExpanded") }
    #endif
}

struct MixedTypingSection: View {
    @ObservedObject private var focus = MixedTypingFocus.shared
    @AppStorage("autoRestore", store: mixedDefaults) private var autoRestore = true
    @AppStorage("contextualEnglish", store: mixedDefaults) private var contextualEnglish = true
    @AppStorage(RetroEnglishUI.autoKey, store: mixedDefaults) private var retroEnglishAuto = false
    @AppStorage(RetroEnglishUI.frequencyKey, store: mixedDefaults) private var englishByFrequency = false
    @AppStorage("spaceSwipeLanguage", store: mixedDefaults) private var spaceSwipeLanguage = false
    /// VNI ⇒ ẩn bộ chọn hồ sơ + "Nâng cao", hiện một dòng ghi chú (MixedTypingUI.rows).
    @AppStorage("vniMode", store: mixedDefaults) private var vniMode = false
    /// Mặc định BẬT, xem KeyboardSettings.swipeEnglish. Công tắc ở trang Gõ vuốt; ở đây chỉ để
    /// so khớp hồ sơ (bộ chọn vẫn đặt giá trị của nó như cũ).
    @AppStorage("swipeEnglish", store: mixedDefaults) private var swipeEnglish = true
    /// Hồ sơ chọn gần nhất (onboarding / bộ chọn nhanh) — chỉ để phân biệt "Việt + Anh nhiều" với
    /// "Chủ yếu tiếng Anh" (cùng bộ công tắc), không điều khiển hành vi.
    @AppStorage(OnboardingFlow.profileKey, store: mixedDefaults) private var lastProfile = ""
    /// Hồ sơ chờ xác nhận (sẽ đổi công tắc người dùng tự chỉnh).
    @State private var confirming: OnboardingProfile?

    private var currentValues: [String: Bool] {
        ["autoRestore": autoRestore, "contextualEnglish": contextualEnglish, RetroEnglishUI.autoKey: retroEnglishAuto,
         RetroEnglishUI.frequencyKey: englishByFrequency, "spaceSwipeLanguage": spaceSwipeLanguage, "swipeEnglish": swipeEnglish]
    }

    /// Hồ sơ khớp đúng cài đặt hiện tại; nil = "Tuỳ chỉnh" (ONBOARDING-SPEC §4).
    private var matched: OnboardingProfile? {
        OnboardingSettings.match(currentValues, lastChosen: OnboardingProfile(rawValue: lastProfile))
    }

    private var summary: String {
        if MixedTypingUI.groupHidden(vniMode: vniMode) { return L(MixedTypingUI.vniNoteKey) }
        let on = [(autoRestore, L("Khôi phục tiếng Anh")), (contextualEnglish, L("Ngữ cảnh")),
                  (spaceSwipeLanguage, L("Vuốt phím cách"))]
            .filter(\.0).map(\.1)
        return on.isEmpty ? L("Đang tắt") : on.joined(separator: " · ")
    }

    var body: some View {
        Section {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { focus.expanded.toggle() }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "globe")
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 29, height: 29)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.teal))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L(MixedTypingUI.titleKey)).foregroundStyle(.primary)
                        Text(summary).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(focus.expanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(focus.expanded ? L("Mở rộng") : L("Thu gọn"))
            .id(MixedTypingItem.section)
            .listRowBackground(rowBackground(.section))

            if focus.expanded {
                ForEach(MixedTypingUI.rows(vniMode: vniMode), id: \.self) { r in
                    switch r {
                    case .profilePicker:
                        profilePicker
                    case .vniNote:
                        Text(L(MixedTypingUI.vniNoteKey))
                            .font(.footnote).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    case .spaceSwipeLanguage:
                        settingToggle(L(MixedTypingItem.spaceSwipeLanguage.viTitle), L(SettingCaption.spaceSwipeLanguage), isOn: $spaceSwipeLanguage)
                            .row(.spaceSwipeLanguage, rowBackground(.spaceSwipeLanguage))
                    case .userDictionary:
                        NavigationLink {
                            UserDictView()
                        } label: {
                            SubPageRow(title: L("Từ điển cá nhân"), subtitle: L(SettingCaption.userDictionary))
                        }
                        .row(.userDictionary, rowBackground(.userDictionary))
                    case .advanced:
                        NavigationLink {
                            MixedAdvancedPage()
                        } label: {
                            SubPageRow(title: L(MixedTypingUI.advancedTitleKey), subtitle: L(MixedTypingUI.advancedSubtitleKey))
                        }
                    }
                }
            }
        } footer: {
            if focus.expanded { Text(L("Cài đặt áp dụng ngay lần mở bàn phím kế tiếp.")) }
        }
    }

    /// Bộ chọn hồ sơ ở đầu nhóm: câu hỏi + ba nút radio (chọn MỘT). "Tuỳ chỉnh" chỉ hiện — đã chọn
    /// sẵn, không bấm được — khi công tắc bên dưới không khớp hồ sơ nào. Trước đây là dấu ✓ bên
    /// phải: người dùng không nhận ra là chọn một.
    @ViewBuilder private var profilePicker: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(L("Bạn thường gõ thế nào?")).font(.subheadline.weight(.semibold))
            Text(L(SettingCaption.profileHint)).font(.footnote).foregroundStyle(.secondary)
        }
        .padding(.top, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        let current = matched
        ForEach(OnboardingProfile.allCases, id: \.self) { p in
            Button { pick(p) } label: {
                profileRow(L(p.titleKey), "“\(p.example)”", selected: current == p)
            }
            .buttonStyle(.plain)
            .id(ProfileRowID.profile(p))
        }
        Group {
            if current == nil {
                profileRow(L("Tuỳ chỉnh"), L(SettingCaption.customProfile), selected: true)
            }
        }
        .alert(confirming.map { L("Áp dụng “%@”?", L($0.titleKey)) } ?? "",
               isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
               presenting: confirming) { p in
            Button(L("Áp dụng")) { apply(p) }
            Button(L("Huỷ"), role: .cancel) {}
        } message: { p in
            Text(changeList(p))
        }
    }

    private enum ProfileRowID: Hashable { case profile(OnboardingProfile) }

    /// Dòng radio: vòng tròn bên trái (đặc = đang chọn), tên + câu ví dụ.
    private func profileRow(_ title: String, _ caption: String, selected: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                .font(.title3).foregroundStyle(selected ? accentBlue : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(.primary).fontWeight(selected ? .semibold : .regular)
                Text(caption).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 4)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func pick(_ p: OnboardingProfile) {
        if OnboardingSettings.needsConfirmation(currentValues, applying: p,
                                                lastChosen: OnboardingProfile(rawValue: lastProfile)) {
            confirming = p
        } else {
            apply(p)
        }
    }

    private func apply(_ p: OnboardingProfile) {
        withAnimation { OnboardingSettings.apply(p, to: mixedDefaults) }
    }

    /// "Sẽ đổi: Tự sửa từ phía trước → bật, …" cho hộp xác nhận.
    private func changeList(_ p: OnboardingProfile) -> String {
        let lines = OnboardingSettings.changes(from: currentValues, to: p).map { k in
            "• " + L(OnboardingSettings.titleKey(k)) + ": " + (p.values[k] == true ? L("bật") : L("tắt"))
        }
        return L("Các công tắc bạn đã tự chỉnh sẽ đổi:") + "\n" + lines.joined(separator: "\n")
    }

    /// Dòng vừa được tìm tới: nền nhấn nhạt ~1.6 s; còn lại nền mặc định.
    private func rowBackground(_ item: MixedTypingItem) -> Color? {
        focus.highlighted == item ? accentBlue.opacity(0.18) : nil
    }
}

private extension View {
    func row(_ item: MixedTypingItem, _ background: Color?) -> some View {
        id(item).listRowBackground(background)
    }
}

/// Kiểu Gõ › Gõ lẫn tiếng Anh › "Nâng cao": các công tắc nhận diện tiếng Anh. Hai mục thử nghiệm
/// phụ thuộc "Quyết định theo ngữ cảnh" đặt ngay dưới nó, ẨN khi nó tắt (MixedTypingUI.advancedRows,
/// SETTINGS-CLEANUP-SPEC §0.4/§6). Ô tìm kiếm mở trang này kèm `highlight` (cuộn + tô sáng).
struct MixedAdvancedPage: View {
    var highlight: MixedTypingItem? = nil
    @AppStorage("autoRestore", store: mixedDefaults) private var autoRestore = true
    @AppStorage("contextualEnglish", store: mixedDefaults) private var contextualEnglish = true
    @AppStorage(RetroEnglishUI.autoKey, store: mixedDefaults) private var retroEnglishAuto = false
    @AppStorage(RetroEnglishUI.frequencyKey, store: mixedDefaults) private var englishByFrequency = false
    @AppStorage("vniMode", store: mixedDefaults) private var vniMode = false
    @State private var highlighted: MixedTypingItem?

    private var rows: [MixedTypingItem] {
        MixedTypingUI.advancedRows(contextualEnglish: contextualEnglish, vniMode: vniMode)
    }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                // Tới đây khi đang chọn VNI (lối vào cũ còn mở): chỉ dòng ghi chú, không công tắc.
                if MixedTypingUI.groupHidden(vniMode: vniMode) {
                    Section { Text(L(MixedTypingUI.vniNoteKey)).foregroundStyle(.secondary) }
                } else {
                Section {
                    settingToggle(L(MixedTypingItem.autoRestore.viTitle), L(SettingCaption.autoRestore), isOn: $autoRestore)
                        .row(.autoRestore, background(.autoRestore))
                    settingToggle(L(MixedTypingItem.contextualEnglish.viTitle), L(SettingCaption.contextualEnglish), isOn: $contextualEnglish)
                        .row(.contextualEnglish, background(.contextualEnglish))
                    if rows.contains(.retroEnglish) {
                        dependentToggle(L(MixedTypingItem.retroEnglish.viTitle), L(SettingCaption.retroEnglish),
                                        isOn: $retroEnglishAuto, reason: nil, experimental: true)
                            .padding(.leading, 12)
                            .row(.retroEnglish, background(.retroEnglish))
                    }
                    if rows.contains(.englishByFrequency) {
                        dependentToggle(L(MixedTypingItem.englishByFrequency.viTitle), L(SettingCaption.englishByFrequency),
                                        isOn: $englishByFrequency, reason: nil, experimental: true)
                            .padding(.leading, 12)
                            .row(.englishByFrequency, background(.englishByFrequency))
                    }
                } footer: {
                    Text(L("Cài đặt áp dụng ngay lần mở bàn phím kế tiếp."))
                }
                }
            }
            .navigationTitle(L(MixedTypingUI.advancedTitleKey))
            .navigationBarTitleDisplayMode(.inline)
            .bottomBarScrollMargin()
            .onAppear {
                guard let t = highlight else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    withAnimation { proxy.scrollTo(t, anchor: .center) }
                    highlighted = t
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                        withAnimation { if highlighted == t { highlighted = nil } }
                    }
                }
            }
        }
    }

    private func background(_ item: MixedTypingItem) -> Color? {
        highlighted == item ? accentBlue.opacity(0.18) : nil
    }
}
