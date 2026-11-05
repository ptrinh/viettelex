// Nhóm thu gọn "Gõ mixed Việt/Anh" ngay dưới mục Kiểu gõ (tab Kiểu Gõ) — docs/ONBOARDING-SPEC.md §4.
// Danh mục + key ở Shared/MixedTypingUI.swift. Các công tắc đọc/ghi CÙNG key App Group như chỗ
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
    /// Dòng chờ cuộn tới khi danh sách tab Kiểu Gõ vừa dựng xong (RootView đổi tab ⇒ dựng lại).
    var pendingScroll: MixedTypingItem?

    /// Ô tìm kiếm chọn `item`: mở nhóm, ghi nhớ dòng cần cuộn tới (RootView đã chuyển tab).
    func open(_ item: MixedTypingItem) {
        expanded = true
        pendingScroll = target(for: item)
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

    /// Dòng thực sự để cuộn tới (mục con đang ẩn ⇒ công tắc cha).
    func target(for item: MixedTypingItem) -> MixedTypingItem {
        let d = mixedDefaults
        let contextual = d?.object(forKey: "contextualEnglish") as? Bool ?? true
        return MixedTypingUI.scrollTarget(item, contextualEnglish: contextual, vniMode: d?.bool(forKey: "vniMode") ?? false)
    }
}

struct MixedTypingSection: View {
    @ObservedObject private var focus = MixedTypingFocus.shared
    @AppStorage("autoRestore", store: mixedDefaults) private var autoRestore = true
    @AppStorage("contextualEnglish", store: mixedDefaults) private var contextualEnglish = true
    @AppStorage(RetroEnglishUI.autoKey, store: mixedDefaults) private var retroEnglishAuto = false
    @AppStorage(RetroEnglishUI.frequencyKey, store: mixedDefaults) private var englishByFrequency = false
    @AppStorage("vniMode", store: mixedDefaults) private var vniMode = false
    @AppStorage("spaceSwipeLanguage", store: mixedDefaults) private var spaceSwipeLanguage = false
    @AppStorage("swipeTyping", store: mixedDefaults) private var swipeTyping = false
    /// Mặc định BẬT, xem KeyboardSettings.swipeEnglish — chỉ có tác dụng khi bật Gõ vuốt.
    @AppStorage("swipeEnglish", store: mixedDefaults) private var swipeEnglish = true

    private var summary: String {
        let on = [(autoRestore, L("Khôi phục tiếng Anh")), (contextualEnglish, L("Ngữ cảnh")),
                  (spaceSwipeLanguage, L("Vuốt phím cách")), (swipeTyping && swipeEnglish, L("Vuốt từ tiếng Anh"))]
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
                groupHeader(.recognition)
                settingToggle(L("Tự khôi phục từ tiếng Anh"), L("Từ không phải tiếng Việt trả về như đã gõ (google, github…)."), isOn: $autoRestore)
                    .row(.autoRestore, rowBackground(.autoRestore))
                settingToggle(L("Quyết định theo ngữ cảnh"), L("Sau một từ tiếng Anh, từ nhập nhằng kế tiếp mà chuỗi phím tạo thành một từ tiếng Anh sẽ được giữ tiếng Anh thay vì tiếng Việt — “he is” → “he is”, không phải “he í”. Sau từ tiếng Việt hoặc không rõ thì để tiếng Việt — “sao í”."), isOn: $contextualEnglish)
                    .row(.contextualEnglish, rowBackground(.contextualEnglish))
                if RetroEnglishUI.switchVisible(contextualEnglish: contextualEnglish, vniMode: vniMode) {
                    experimentalToggle(L("Tự sửa từ phía trước"), L("Khi bạn gõ tiếp một câu tiếng Anh, tự sửa các từ vừa bị bỏ dấu nhầm (vd. \"Hí cả í very fast\" → \"His car is very fast\")."), isOn: $retroEnglishAuto)
                        .row(.retroEnglish, rowBackground(.retroEnglish))
                    experimentalToggle(L("Đoán từ trùng theo tần suất"), L("Đầu câu, từ vừa là tiếng Anh phổ biến vừa là âm tiết Việt hiếm (his → hí) thì chọn tiếng Anh; từ kế cho thấy là tiếng Việt (hí hửng, hí hí) thì tự đổi lại."), isOn: $englishByFrequency)
                        .row(.englishByFrequency, rowBackground(.englishByFrequency))
                }

                groupHeader(.language)
                settingToggle(L("Vuốt phím cách đổi Tiếng Việt / Tiếng Anh"), L("Vuốt nhanh phím cách sang trái/phải. Góc phím cách hiện VI / EN. Tiếng Anh gõ nguyên văn. Giữ rồi kéo vẫn là di con trỏ."), isOn: $spaceSwipeLanguage)
                    .row(.spaceSwipeLanguage, rowBackground(.spaceSwipeLanguage))

                groupHeader(.suggest)
                settingToggle(L("Vuốt từ tiếng Anh"),
                              L("check, mail, meeting… Nét vừa Việt vừa Anh (the/thế) ưu tiên tiếng Việt, phương án kia ở thanh gợi ý.")
                                + (swipeTyping ? "" : "\n" + L("Cần bật Gõ vuốt (Tính Năng → Gõ vuốt).")),
                              isOn: $swipeEnglish)
                    .disabled(!swipeTyping)
                    .row(.swipeEnglish, rowBackground(.swipeEnglish))
                NavigationLink {
                    UserDictView()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Từ điển cá nhân"))
                        Text(L("Xem, tìm, xoá từ đã học; thêm tên riêng."))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .row(.userDictionary, rowBackground(.userDictionary))
            }
        } footer: {
            if focus.expanded { Text(L("Cài đặt áp dụng ngay lần mở bàn phím kế tiếp.")) }
        }
    }

    private func groupHeader(_ g: MixedTypingItem.Group) -> some View {
        Text(L(MixedTypingUI.groupTitle(g)).uppercased())
            .font(.footnote).foregroundStyle(.secondary)
            .padding(.top, 4)
            .accessibilityAddTraits(.isHeader)
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
