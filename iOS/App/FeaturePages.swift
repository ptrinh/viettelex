// Tab Tính Năng (27/09/2026): trang chính là 8 nhóm (icon + tên + tóm tắt trạng thái),
// mỗi nhóm mở một trang con — thay cho danh sách dài mọi công tắc. Ô tìm kiếm trên đầu
// lọc theo tên/từ khoá rồi mở đúng trang. KHÔNG đổi key/mặc định/cổng Plus: các trang con
// đọc/ghi cùng key App Group như trước. Android dùng cùng cấu trúc (ui/FeaturePages.kt).
import SwiftUI
import UIKit
import UniformTypeIdentifiers

private let featureDefaults = UserDefaults(suiteName: "group.com.viettelex")

/// Các nhóm của tab Tính Năng — cùng thứ tự/tên với Android (FeaturePage.kt).
enum FeaturePage: String, CaseIterable, Identifiable {
    case chinhTa, goiY, goVuot, goTat, phim, giaoDien, riengTu, saoLuu
    var id: String { rawValue }

    var title: String { L(viTitle) }
    /// Tên gốc tiếng Việt — khoá tra L10n và so khớp tìm kiếm.
    var viTitle: String {
        switch self {
        case .chinhTa: return LK("Chính tả & sửa lỗi")
        case .goiY: return LK("Gợi ý & từ điển")
        case .goVuot: return LK("Gõ vuốt")
        case .goTat: return LK("Gõ tắt & mẫu câu")
        case .phim: return LK("Phím & cử chỉ")
        case .giaoDien: return LK("Giao diện")
        case .riengTu: return LK("Riêng tư & clipboard")
        case .saoLuu: return LK("Sao lưu & đồng bộ")
        }
    }
    var icon: String {
        switch self {
        case .chinhTa: return "checkmark.seal"
        case .goiY: return "lightbulb"
        case .goVuot: return "hand.draw"
        case .goTat: return "text.quote"
        case .phim: return "keyboard"
        case .giaoDien: return "paintpalette"
        case .riengTu: return "lock"
        case .saoLuu: return "icloud"
        }
    }
    var color: Color {
        switch self {
        case .chinhTa: return .green
        case .goiY: return .orange
        case .goVuot: return .purple
        case .goTat: return .teal
        case .phim: return .gray
        case .giaoDien: return .pink
        case .riengTu: return .indigo
        case .saoLuu: return .blue
        }
    }
    /// Cả nhóm đang thử nghiệm → nhãn nhỏ ngay trên dòng.
    var experimental: Bool { self == .goVuot }
    /// Mục tương ứng trong Hướng dẫn sử dụng (docs/hdsd/index.html).
    var guideAnchor: String {
        switch self {
        case .chinhTa: return "sua-dau"
        case .goiY: return "goi-y"
        case .goVuot: return "go-vuot"
        case .goTat: return "go-tat"
        case .phim: return "cu-chi"
        case .giaoDien: return "giao-dien"
        case .riengTu: return "clipboard"
        case .saoLuu: return "sao-luu"
        }
    }
    var guideURL: URL { L10n.guideURL(os: "ios", anchor: guideAnchor) }

    @ViewBuilder var destination: some View {
        switch self {
        case .chinhTa: ChinhTaPage()
        case .goiY: GoiYPage()
        case .goVuot: GoVuotPage()
        case .goTat: GoTatPage()
        case .phim: PhimPage()
        case .giaoDien: ThemeSettingsView()
        case .riengTu: FeaturePageList(page: .riengTu) { RiengTuSection() }
        case .saoLuu: FeaturePageList(page: .saoLuu) { SaoLuuSection() }
        }
    }

    /// Các nhóm hiển thị theo 3 khối như app Cài đặt.
    static let groups: [[FeaturePage]] = [[.chinhTa, .goiY, .goVuot, .goTat], [.phim, .giaoDien], [.riengTu, .saoLuu]]
}

/// Chỉ mục cho ô tìm kiếm: tên cài đặt + từ khoá → trang chứa nó. `viTitle` là tên
/// gốc tiếng Việt (khoá L10n); tìm khớp cả tên tiếng Việt lẫn tiếng Anh.
struct FeatureSearchEntry: Identifiable {
    let viTitle: String
    var title: String { L(viTitle) }
    let keywords: String
    let page: FeaturePage
    var id: String { page.rawValue + viTitle }

    static var all: [FeatureSearchEntry] {
        var e: [FeatureSearchEntry] = [
            .init(viTitle: LK("Tự khôi phục từ tiếng Anh"), keywords: "english google restore", page: .chinhTa),
            .init(viTitle: LK("Kiểm tra chính tả khi gõ"), keywords: "spell check", page: .chinhTa),
            .init(viTitle: LK("Sửa dấu từ đã gõ"), keywords: "sửa dấu con trỏ backspace", page: .chinhTa),
            .init(viTitle: LK("Chọn phím thông minh"), keywords: "chạm trượt smart touch thử nghiệm", page: .chinhTa),
            .init(viTitle: LK("Tự sửa từ gõ sai"), keywords: "autocorrect sửa lỗi thử nghiệm", page: .chinhTa),
            .init(viTitle: LK("Thanh gợi ý"), keywords: "suggestion học từ", page: .goiY),
            .init(viTitle: LK("Gợi ý emoji"), keywords: "emoji biểu tượng", page: .goiY),
            .init(viTitle: LK("Chip số"), keywords: "số tiền đọc số number", page: .goiY),
            .init(viTitle: LK("Hiện kết quả phép tính"), keywords: "tính toán máy tính bằng math calculator", page: .goiY),
            .init(viTitle: LK("Nút Dán"), keywords: "paste dán clipboard", page: .goiY),
            .init(viTitle: LK("Lọc từ nhạy cảm"), keywords: "tục chửi filter", page: .goiY),
            .init(viTitle: LK("Từ điển cá nhân"), keywords: "dictionary tên riêng thuật ngữ", page: .goiY),
            .init(viTitle: LK("Xóa từ đã học"), keywords: "xoá học reset", page: .goiY),
            .init(viTitle: LK("Gõ vuốt"), keywords: "swipe vuốt thử nghiệm", page: .goVuot),
            .init(viTitle: LK("Vuốt từ tiếng Anh"), keywords: "swipe english", page: .goVuot),
            .init(viTitle: LK("Mô hình neural gõ vuốt"), keywords: "futo neural swipe", page: .goVuot),
            .init(viTitle: LK("Luyện vuốt"), keywords: "practice swipe", page: .goVuot),
            .init(viTitle: LK("Gõ tắt"), keywords: "shortcut viết tắt", page: .goTat),
            .init(viTitle: LK("Bảng gõ tắt"), keywords: "shortcut yaml import export", page: .goTat),
            .init(viTitle: LK("Mẫu câu"), keywords: "template câu soạn sẵn snippets tắt ẩn tab ☰", page: .goTat),
            .init(viTitle: LK("Hàng phím số"), keywords: "number row số", page: .phim),
            .init(viTitle: LK("Giữ phím ra ký tự đặc biệt"), keywords: "ký hiệu symbol @ # giữ lâu", page: .phim),
            .init(viTitle: LK("Vuốt phím cách đổi Tiếng Việt / Tiếng Anh"), keywords: "space ngôn ngữ english language", page: .phim),
            .init(viTitle: LK("Phóng to chữ khi bấm"), keywords: "key preview popup", page: .phim),
            .init(viTitle: LK("Rung phím"), keywords: "haptic rung vibrate", page: .phim),
            .init(viTitle: LK("Âm thanh phím"), keywords: "sound click tiếng âm lượng volume kiểu style gỗ cơ máy chữ bong bóng custom", page: .phim),
            .init(viTitle: LK("Theme & ảnh nền"), keywords: "theme màu chủ đề wallpaper hình nền", page: .giaoDien),
            .init(viTitle: LK("Độ trong suốt phím"), keywords: "trong suốt transparent", page: .giaoDien),
            .init(viTitle: LK("Độ trong suốt ký tự"), keywords: "trong suốt transparent chữ", page: .giaoDien),
            .init(viTitle: LK("Khôi phục giao diện gốc"), keywords: "reset mặc định", page: .giaoDien),
            .init(viTitle: LK("Chiều cao hàng phím"), keywords: "height cao thấp", page: .giaoDien),
            .init(viTitle: LK("Hiện logo Vᴛ"), keywords: "logo phím cách", page: .giaoDien),
            .init(viTitle: LK("Bàn phím tách đôi"), keywords: "split tách chia hai nửa gập ngang", page: .giaoDien),
            .init(viTitle: LK("Lịch sử clipboard"), keywords: "copy dán clipboard", page: .riengTu),
            .init(viTitle: LK("Chế độ ẩn danh"), keywords: "incognito riêng tư", page: .riengTu),
            .init(viTitle: LK("Xuất / nhập file sao lưu"), keywords: "backup export import restore", page: .saoLuu),
        ]
        if UIDevice.current.userInterfaceIdiom == .phone {
            e.append(.init(viTitle: LK("Giữ phím hàng trên để ra số"), keywords: "số giữ lâu number", page: .phim))
            e.append(.init(viTitle: LK("Chế độ một tay"), keywords: "one hand một tay", page: .phim))
        }
        if PlusGate.isUnlocked(.sentenceDiacritics) {
            e.append(.init(viTitle: LK("Chip “Thêm dấu”"), keywords: "thêm dấu câu không dấu plus", page: .goiY))
        }
        if ICloudSync.isUnlocked() {
            e.append(.init(viTitle: LK("Đồng bộ iCloud"), keywords: "sync icloud đồng bộ", page: .saoLuu))
        }
        return e
    }

    /// So khớp không phân biệt hoa/thường và dấu (gõ "trong suot" vẫn ra).
    static func fold(_ s: String) -> String {
        s.replacingOccurrences(of: "đ", with: "d").replacingOccurrences(of: "Đ", with: "D")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    static func search(_ query: String) -> [FeatureSearchEntry] {
        let words = fold(query).split(separator: " ").map(String.init)
        guard !words.isEmpty else { return [] }
        let pageHits = FeaturePage.allCases.map {
            FeatureSearchEntry(viTitle: $0.viTitle, keywords: "", page: $0)
        }
        return (pageHits + all).filter { e in
            let hay = fold(e.viTitle + " " + (L10n.en[e.viTitle] ?? "") + " " + e.keywords)
            return words.allSatisfy { hay.contains($0) }
        }
    }
}

/// Nhãn nhỏ "Thử nghiệm" cạnh tên cài đặt.
struct ExperimentalBadge: View {
    var body: some View {
        Text(L("Thử nghiệm"))
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(Capsule().fill(Color.purple.opacity(0.15)))
            .foregroundStyle(.purple)
    }
}

/// Toggle có nhãn "Thử nghiệm" (cùng kiểu settingToggle).
func experimentalToggle(_ title: String, _ caption: String, isOn: Binding<Bool>) -> some View {
    Toggle(isOn: isOn) {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) { Text(title); ExperimentalBadge() }
            Text(caption).font(.footnote).foregroundStyle(.secondary)
        }
    }
    .tint(.green)
}

/// Ô icon màu kiểu app Cài đặt.
struct FeatureIcon: View {
    let page: FeaturePage
    var body: some View {
        Image(systemName: page.icon)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 29, height: 29)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(page.color))
    }
}

/// Dòng "Tìm hiểu thêm" cuối mỗi trang con.
struct GuideLinkSection: View {
    let page: FeaturePage
    var body: some View {
        Section {
            Link(destination: page.guideURL) {
                Label(L("Tìm hiểu thêm trong Hướng dẫn"), systemImage: "book")
            }
        } footer: {
            Text(L("Cài đặt áp dụng ngay lần mở bàn phím kế tiếp."))
        }
    }
}

/// Khung trang con: List + tiêu đề inline + link Hướng dẫn + chừa lối cho bar nổi.
struct FeaturePageList<Content: View>: View {
    let page: FeaturePage
    @ViewBuilder var content: Content
    var body: some View {
        List {
            content
            GuideLinkSection(page: page)
        }
        .navigationTitle(page.title)
        .navigationBarTitleDisplayMode(.inline)
        .bottomBarScrollMargin()
    }
}

// ============================================================== Trang chính

/// Tab Tính Năng — ô tìm kiếm + các nhóm kèm tóm tắt trạng thái hiện tại.
struct TinhNangSections: View {
    @State private var query = ""
    @State private var shortcutCount = ShortcutStore.load().count
    @State private var theme = ThemeSettings.load(featureDefaults)

    // Chỉ để dựng dòng tóm tắt — trang con ghi, @AppStorage tự cập nhật.
    @AppStorage("autoRestore", store: featureDefaults) private var autoRestore = true
    @AppStorage("liveSpellCheck", store: featureDefaults) private var liveSpellCheck = true
    @AppStorage("reEditWord", store: featureDefaults) private var reEditWord = true
    @AppStorage("autoCorrect", store: featureDefaults) private var autoCorrect = false
    @AppStorage("showSuggestions", store: featureDefaults) private var showSuggestions = true
    @AppStorage("emojiSuggest", store: featureDefaults) private var emojiSuggest = true
    @AppStorage("numberChips", store: featureDefaults) private var numberChips = true
    @AppStorage("swipeTyping", store: featureDefaults) private var swipeTyping = false
    @AppStorage("swipeEnglish", store: featureDefaults) private var swipeEnglish = true
    @AppStorage("swipeFuto", store: featureDefaults) private var swipeFuto = false
    @AppStorage(ShortcutFile.enabledKey, store: featureDefaults) private var shortcutsEnabled = true
    @AppStorage("templatesEnabled", store: featureDefaults) private var templatesEnabled = true
    @AppStorage("numberRow", store: featureDefaults) private var numberRow = false
    @AppStorage("spaceSwipeLanguage", store: featureDefaults) private var spaceSwipeLanguage = false
    @AppStorage("autoSpaceAfterPunct", store: featureDefaults) private var autoSpaceAfterPunct = false
    @AppStorage("hapticFeedback", store: featureDefaults) private var hapticFeedback = false
    @AppStorage("oneHandMode", store: featureDefaults) private var oneHandMode = "off"
    @AppStorage("clipboardHistory", store: featureDefaults) private var clipboardHistory = false
    @AppStorage("incognitoMode", store: featureDefaults) private var incognitoMode = false
    @AppStorage(ICloudSync.enabledKey, store: featureDefaults) private var iCloudSync = false
    @AppStorage(L10n.defaultsKey, store: featureDefaults) private var uiLanguage = "vi"

    private static func join(_ parts: [(Bool, String)], none: String) -> String {
        let on = parts.filter(\.0).map(\.1)
        return on.isEmpty ? none : on.joined(separator: " · ")
    }

    private func summary(_ p: FeaturePage) -> String {
        switch p {
        case .chinhTa:
            return Self.join([(autoRestore, L("Khôi phục tiếng Anh")), (liveSpellCheck, L("Kiểm tra chính tả")),
                              (reEditWord, L("Sửa dấu")), (autoCorrect, L("Tự sửa"))], none: L("Đang tắt"))
        case .goiY:
            guard showSuggestions else { return L("Tắt thanh gợi ý") }
            return Self.join([(true, L("Thanh gợi ý")), (emojiSuggest, "Emoji"), (numberChips, L("Chip số"))], none: "")
        case .goVuot:
            guard swipeTyping else { return L("Đang tắt") }
            return Self.join([(true, L("Bật")), (swipeEnglish, L("Tiếng Anh")), (swipeFuto, "Neural")], none: "")
        case .goTat:
            let st = shortcutsEnabled ? (shortcutCount == 0 ? L("Gõ tắt bật") : L("Gõ tắt: %@ mục", shortcutCount)) : L("Gõ tắt tắt")
            return st + " · " + (templatesEnabled ? L("Mẫu câu bật") : L("Mẫu câu tắt"))
        case .phim:
            return Self.join([(numberRow, L("Hàng số")), (spaceSwipeLanguage, L("Vuốt phím cách")),
                              (autoSpaceAfterPunct, L("Cách sau dấu câu")),
                              (hapticFeedback, L("Rung")), (oneHandMode != "off", L("Một tay"))], none: L("Mặc định"))
        case .giaoDien:
            let wp = theme.wallpaperActive(fileExists: Wallpaper.url.map { FileManager.default.fileExists(atPath: $0.path) } ?? false)
            return theme.effectiveTheme.title + (wp ? " · " + L("Ảnh nền") : "")
                + (theme.keyboardTransparency > 0 || theme.labelTransparency > 0 ? " · " + L("Trong suốt") : "")
        case .riengTu:
            return (clipboardHistory ? L("Lịch sử clipboard bật") : L("Lịch sử clipboard tắt")) + (incognitoMode ? " · " + L("Ẩn danh") : "")
        case .saoLuu:
            return iCloudSync && ICloudSync.isUnlocked() ? L("Đồng bộ iCloud bật") : L("Xuất / nhập file")
        }
    }

    var body: some View {
        // Ngôn ngữ giao diện — mục ĐẦU TIÊN của Tính Năng, nhãn song ngữ để ai cũng tìm thấy.
        Section {
            Picker(selection: Binding(get: { uiLanguage == "en" ? "en" : "vi" },
                                      set: { L10n.apply($0); uiLanguage = $0 })) {
                Text(verbatim: "Tiếng Việt").tag("vi")
                Text(verbatim: "English").tag("en")
            } label: {
                Label { Text(verbatim: "Ngôn ngữ / Language") } icon: {
                    Image(systemName: "globe").foregroundStyle(accentBlue)
                }
            }
        }
        Section {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                // KHÔNG .autocorrectionDisabled(): bàn phím VietTelex coi ô đó là ô mã → tắt Telex.
                TextField(L("Tìm cài đặt…"), text: $query)
                    .textInputAutocapitalization(.never)
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(L("Xoá tìm kiếm"))
                }
            }
            .onAppear {
                // Quay về từ trang con → làm mới các giá trị không phải @AppStorage.
                shortcutCount = ShortcutStore.load().count
                theme = ThemeSettings.load(featureDefaults)
            }
        }

        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            ForEach(Array(FeaturePage.groups.enumerated()), id: \.offset) { _, group in
                Section {
                    ForEach(group) { p in
                        NavigationLink { p.destination } label: { row(p, subtitle: summary(p)) }
                    }
                }
            }
        } else {
            let hits = FeatureSearchEntry.search(query)
            Section {
                if hits.isEmpty {
                    Text(L("Không tìm thấy cài đặt nào.")).foregroundStyle(.secondary)
                }
                ForEach(hits) { e in
                    NavigationLink { e.page.destination } label: {
                        row(e.page, title: e.title, subtitle: e.viTitle == e.page.viTitle ? summary(e.page) : e.page.title)
                    }
                }
            } header: { Text(L("Kết quả")) }
        }
    }

    private func row(_ p: FeaturePage, title: String? = nil, subtitle: String) -> some View {
        HStack(spacing: 12) {
            FeatureIcon(page: p)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title ?? p.title)
                    if p.experimental && title == nil { ExperimentalBadge() }
                }
                Text(subtitle).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}

// ============================================================== Trang con

struct ChinhTaPage: View {
    @AppStorage("autoRestore", store: featureDefaults) private var autoRestore = true
    @AppStorage("liveSpellCheck", store: featureDefaults) private var liveSpellCheck = true
    @AppStorage("reEditWord", store: featureDefaults) private var reEditWord = true
    /// Thử nghiệm — mặc định BẬT, xem KeyboardSettings.smartTouch.
    @AppStorage("smartTouch", store: featureDefaults) private var smartTouch = true
    /// Thử nghiệm — mặc định TẮT, xem KeyboardSettings.autoCorrect.
    @AppStorage("autoCorrect", store: featureDefaults) private var autoCorrect = false

    var body: some View {
        FeaturePageList(page: .chinhTa) {
            Section {
                settingToggle(L("Tự khôi phục từ tiếng Anh"), L("Từ không phải tiếng Việt trả về như đã gõ (google, github…)."), isOn: $autoRestore)
                settingToggle(L("Kiểm tra chính tả khi gõ"), L("Ngừng bỏ dấu khi từ không thể là tiếng Việt."), isOn: $liveSpellCheck)
                settingToggle(L("Sửa dấu từ đã gõ"), L("⌫ ngay sau dấu cách để sửa tiếp từ vừa gõ (tháy ␣ ⌫ a → thấy), hoặc đặt con trỏ sau từ rồi gõ phím dấu: viêt + j → việt."), isOn: $reEditWord)
            } header: { Text(L("Chính tả")) }
            Section {
                experimentalToggle(L("Chọn phím thông minh"), L("Chạm sát mép giữa hai phím thì chọn phím hợp với chữ đang gõ. Chạm giữa phím luôn ra đúng phím đó."), isOn: $smartTouch)
                experimentalToggle(L("Tự sửa từ gõ sai"), L("Khi gõ dấu cách, sửa từ lỡ chạm phím kề (tpoi → tôi) nếu chắc chắn. ⌫ ngay sau đó để trả lại chữ gốc."), isOn: $autoCorrect)
            } header: { Text(L("Chạm trượt")) } footer: {
                Text(L("Gợi ý sửa lỗi chạm trượt (hiện trên thanh gợi ý) nằm ở tab Kiểu Gõ."))
            }
        }
    }
}

struct GoiYPage: View {
    @AppStorage("showSuggestions", store: featureDefaults) private var showSuggestions = true
    @AppStorage("filterSensitive", store: featureDefaults) private var filterSensitive = true
    @AppStorage("emojiSuggest", store: featureDefaults) private var emojiSuggest = true
    @AppStorage("numberChips", store: featureDefaults) private var numberChips = true
    @AppStorage("mathResults", store: featureDefaults) private var mathResults = true
    @AppStorage("suggestInNoSuggestFields", store: featureDefaults) private var suggestInNoSuggestFields = true
    @AppStorage("pasteButton", store: featureDefaults) private var pasteButton = true
    @AppStorage("addTonesChip", store: featureDefaults) private var addTonesChip = false

    var body: some View {
        FeaturePageList(page: .goiY) {
            Section {
                // Thanh gợi ý bật = tự học từ hay dùng (learnWords đi theo — quyết định 2026-07-24).
                settingToggle(L("Thanh gợi ý"), L("Gợi ý từ + emoji, tự học từ bạn hay dùng (chỉ trên máy)."), isOn: $showSuggestions)
                if showSuggestions {
                    settingToggle(L("Gợi ý cả khi ứng dụng tắt gợi ý"), L("Ô mà ứng dụng tắt gợi ý (vd ô chat, thanh địa chỉ) vẫn gợi ý từ — không tự sửa, không học từ gõ ở đó. Mật khẩu, ẩn danh, ô số không bị ảnh hưởng."), isOn: $suggestInNoSuggestFields)
                    settingToggle(L("Gợi ý emoji"), L("Emoji hợp với từ đang gõ (yêu → ❤️)."), isOn: $emojiSuggest)
                    settingToggle(L("Chip số"), L("Đọc số thành chữ, định dạng tiền (1tr2 → 1.200.000 ₫)."), isOn: $numberChips)
                    settingToggle(L("Hiện kết quả phép tính"), L("Gõ phép tính rồi dấu = (12*3=) → kết quả hiện ở đầu thanh gợi ý, chạm để chèn."), isOn: $mathResults)
                    settingToggle(L("Nút Dán"), L("Vừa copy xong thì hiện nút Dán (cần Toàn quyền)."), isOn: $pasteButton)
                    if PlusGate.isUnlocked(.sentenceDiacritics) {
                        settingToggle(L("Chip “Thêm dấu”"), L("Gõ không dấu cả câu (hom nay troi dep), gõ dấu cách → chip “Thêm dấu” hiện ở đầu thanh gợi ý, chạm để thành “hôm nay trời đẹp”; chạm “Hoàn tác” để trả lại. Tắt mặc định cho nhẹ máy."), isOn: $addTonesChip)
                    }
                }
                settingToggle(L("Lọc từ nhạy cảm"), L("Không chủ động gợi ý từ tục — gõ tay vẫn bình thường."), isOn: $filterSensitive)
            } header: { Text(L("Thanh gợi ý")) }
            Section {
                NavigationLink {
                    UserDictView()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Từ điển cá nhân"))
                        Text(L("Xem, tìm, xoá từ đã học; thêm tên riêng."))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Button(L("Xóa từ đã học"), role: .destructive) {
                    // Xoá file + đổi mốc userlmResetAt ⇒ bàn phím bỏ bảng trong RAM lần hiện kế tiếp.
                    UserDictStore.eraseAll()
                }
            } header: { Text(L("Từ đã học")) }
        }
    }
}

struct GoVuotPage: View {
    @AppStorage("swipeTyping", store: featureDefaults) private var swipeTyping = false
    /// Công tắc con — mặc định BẬT, xem KeyboardSettings.swipeEnglish.
    @AppStorage("swipeEnglish", store: featureDefaults) private var swipeEnglish = true
    /// Decoder FUTO Swipe — mặc định TẮT, xem KeyboardSettings.swipeFuto.
    @AppStorage("swipeFuto", store: featureDefaults) private var swipeFuto = false

    var body: some View {
        FeaturePageList(page: .goVuot) {
            Section {
                experimentalToggle(L("Gõ vuốt"), L("Vuốt qua các chữ không dấu rồi nhấc tay: v→i→e→t ra “việt”. Gõ phím dấu ngay sau để đổi dấu, ⌫ xoá cả từ. Chỉ trên iPhone."), isOn: $swipeTyping)
                if swipeTyping {
                    settingToggle(L("Vuốt từ tiếng Anh"), L("check, mail, meeting… Nét vừa Việt vừa Anh (the/thế) ưu tiên tiếng Việt, phương án kia ở thanh gợi ý."), isOn: $swipeEnglish)
                    settingToggle(L("Mô hình neural gõ vuốt"), L("Mạng neural chạy hoàn toàn trên máy, chấm cùng bộ giải mã. Tốn thêm ~3 MB bộ nhớ."), isOn: $swipeFuto)
                    // Ghi công BẮT BUỘC theo FUTO Model Weights License 1.0 ("visible notice …
                    // within the product's settings") — Phil 27/09/2026: chỉ hiện ở đây (dưới công
                    // tắc, khi đã bật Gõ vuốt), chữ nhỏ mờ. KHÔNG xoá. Xem docs/DATA-SOURCES.md.
                    Link(destination: URL(string: "https://github.com/ptrinh/viettelex/blob/main/docs/DATA-SOURCES.md#futo-swipe")!) {
                        Text("powered by FUTO Swipe")
                    }
                    .font(.caption2).foregroundStyle(.tertiary)
                }
            } footer: {
                Text(L("Tự tắt khi dùng VoiceOver và ở ô email/mật khẩu/URL."))
            }
            if swipeTyping {
                Section {
                    NavigationLink {
                        SwipePracticeView()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("Luyện vuốt"))
                            Text(L("Vuốt thử từng từ, xem bàn phím đọc đúng bao nhiêu."))
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}

struct GoTatPage: View {
    @AppStorage("templatesEnabled", store: featureDefaults) private var templatesEnabled = true

    var body: some View {
        FeaturePageList(page: .goTat) {
            ShortcutsSection()
            Section {
                settingToggle(L("Mẫu câu"), L("Nút ☰ trên bàn phím chèn câu soạn sẵn — quản lý ở tab Mẫu Câu. Tắt: ẩn nút ☰ và tab Mẫu Câu."), isOn: $templatesEnabled)
            } header: { Text(L("Mẫu câu")) }
        }
    }
}

struct PhimPage: View {
    @AppStorage("numberRow", store: featureDefaults) private var numberRow = false
    /// Giữ phím chữ ra ký tự phụ (KeyAlternates) — số mặc định BẬT, ký hiệu TẮT.
    @AppStorage("longPressNumbers", store: featureDefaults) private var longPressNumbers = true
    @AppStorage("longPressSymbols", store: featureDefaults) private var longPressSymbols = false
    /// Vuốt phím cách đổi Tiếng Việt ↔ Tiếng Anh — mặc định TẮT (KeyboardSettings.spaceSwipeLanguage).
    @AppStorage("spaceSwipeLanguage", store: featureDefaults) private var spaceSwipeLanguage = false
    /// Tự thêm dấu cách sau . , ? ! ; : — mặc định TẮT (KeyboardSettings.autoSpaceAfterPunct).
    @AppStorage("autoSpaceAfterPunct", store: featureDefaults) private var autoSpaceAfterPunct = false
    /// "off" | "left" | "right" — bàn phím đọc lúc hiện (OneHand.resolve).
    @AppStorage("oneHandMode", store: featureDefaults) private var oneHandMode = "off"
    /// Ô phóng to chữ khi bấm phím — mặc định BẬT (KeyboardView.keyPreviewKey).
    @AppStorage("keyPreviewEnabled", store: featureDefaults) private var keyPreview = true
    @AppStorage("hapticFeedback", store: featureDefaults) private var hapticFeedback = false
    @AppStorage("hapticStrength", store: featureDefaults) private var hapticStrength = 45
    @AppStorage("keySound", store: featureDefaults) private var keySound = false
    @AppStorage("keySoundVolume", store: featureDefaults) private var keySoundVolume = 50
    @AppStorage("keySoundStyle", store: featureDefaults) private var keySoundStyle = KeySoundStyle.defaultStyle.rawValue
    /// Nghe/rung thử khi kéo thanh trượt: ≤ 1 lần / 120 ms + lúc thả.
    @State private var hapticThrottle = PreviewThrottle()
    @State private var volumeThrottle = PreviewThrottle()
    @State private var importing = false
    @State private var styleBeforeImport: String?
    @State private var customDuration: Double?
    @State private var importMessage: String?

    private var isPhone: Bool { UIDevice.current.userInterfaceIdiom == .phone }

    var body: some View {
        FeaturePageList(page: .phim) {
            Section {
                settingToggle(L("Hàng phím số"), L("Thêm hàng 1 … 0 trên hàng chữ (bàn phím cao thêm ~¾ hàng)."), isOn: $numberRow)
                // iPad có ký tự phụ vuốt xuống riêng ⇒ chỉ iPhone.
                if isPhone {
                    if !numberRow {
                        settingToggle(L("Giữ phím hàng trên để ra số"), L("Giữ q … p để gõ 1 … 0 (số nhỏ ở góc phím)."), isOn: $longPressNumbers)
                    }
                    settingToggle(L("Giữ phím hàng 2, 3 để ra ký tự đặc biệt"), L("Giữ a … l, z … m để gõ @ # $ _ & - + ( ) … Giữ , để ra dấu chấm."), isOn: $longPressSymbols)
                }
                settingToggle(L("Tự thêm dấu cách sau dấu câu"), L("Gõ . , ? ! ; : tự có dấu cách phía sau. Không thêm trong số (3.5, 1,000), email, đường dẫn. Gõ dấu cách ngay sau không thành hai dấu cách; ⌫ ngay sau chỉ xoá dấu cách đó."), isOn: $autoSpaceAfterPunct)
            } header: { Text(L("Phím")) }
            Section {
                settingToggle(L("Vuốt phím cách đổi Tiếng Việt / Tiếng Anh"), L("Vuốt nhanh phím cách sang trái/phải. Góc phím cách hiện VI / EN. Tiếng Anh gõ nguyên văn. Giữ rồi kéo vẫn là di con trỏ."), isOn: $spaceSwipeLanguage)
                if isPhone {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L("Chế độ một tay"))
                        Picker(L("Chế độ một tay"), selection: $oneHandMode) {
                            Text(L("Tắt")).tag("off")
                            Text(L("Trái")).tag("left")
                            Text(L("Phải")).tag("right")
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        Text(L("Thu hẹp bàn phím về một bên. Giữ lâu nút ☰ trên thanh gợi ý để bật/tắt nhanh."))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            } header: { Text(L("Cử chỉ")) }
            Section {
                settingToggle(L("Phóng to chữ khi bấm"), L("Ô chữ lớn nổi trên phím vừa chạm. Tắt cho gọn, nhẹ máy."), isOn: $keyPreview)
                settingToggle(L("Rung phím"), L("Rung nhẹ mỗi lần chạm phím."), isOn: $hapticFeedback)
                if hapticFeedback {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(L("Độ mạnh rung"))
                            Spacer()
                            Text("\(hapticStrength)%").foregroundStyle(.secondary).monospacedDigit()
                        }
                        Slider(value: Binding(get: { Double(hapticStrength) },
                                              set: { hapticStrength = Int($0.rounded()); previewHaptic(final: false) }),
                               in: 10...100, step: 5,
                               label: { Text(L("Độ mạnh rung")) },
                               minimumValueLabel: { Text(L("Nhẹ")).font(.caption) },
                               maximumValueLabel: { Text(L("Mạnh")).font(.caption) },
                               onEditingChanged: { editing in if !editing { previewHaptic(final: true) } })
                    }
                    FullAccessNotice(reason: L("Rung phím"))
                }
                settingToggle(L("Âm thanh phím"), L("Tiếng phím riêng của VietTelex: chọn kiểu, chỉnh âm lượng. Tắt: dùng tiếng bấm bàn phím của iOS (Cài đặt → Âm thanh). Im khi gạt chế độ im lặng."), isOn: $keySound)
                if keySound {
                    Picker(L("Kiểu âm"), selection: Binding(get: { keySoundStyle }, set: { pickStyle($0) })) {
                        ForEach(KeySoundStyle.allCases, id: \.rawValue) { st in
                            Text(L(st.viTitle)).tag(st.rawValue)
                        }
                    }
                    if keySoundStyle == KeySoundStyle.custom.rawValue || customDuration != nil {
                        customSoundRow
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(L("Âm lượng"))
                            Spacer()
                            Text("\(keySoundVolume)%").foregroundStyle(.secondary).monospacedDigit()
                        }
                        Slider(value: Binding(get: { Double(keySoundVolume) },
                                              set: { keySoundVolume = Int($0.rounded()); previewSound(final: false) }),
                               in: 0...100, step: 5,
                               label: { Text(L("Âm lượng")) },
                               minimumValueLabel: { Image(systemName: "speaker.fill").font(.caption) },
                               maximumValueLabel: { Image(systemName: "speaker.wave.3.fill").font(.caption) },
                               onEditingChanged: { editing in if !editing { previewSound(final: true) } })
                        Text(L("Kéo thanh trượt hoặc chọn kiểu để nghe thử. Không nghe thấy? Tắt gạt im lặng (bàn phím cũng im khi gạt)."))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    FullAccessNotice(reason: L("Âm thanh phím"))
                }
            } header: { Text(L("Phản hồi khi chạm")) }
        }
        .onAppear { customDuration = KeySoundImport.storedDuration() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio]) { result in
            handleImport(result)
        }
        .alert(L("Âm của bạn"), isPresented: Binding(get: { importMessage != nil }, set: { if !$0 { importMessage = nil } })) {
            Button(L("OK"), role: .cancel) { importMessage = nil }
        } message: { Text(importMessage ?? "") }
    }

    /// Hàng "Âm của bạn": độ dài + chọn file khác + xoá.
    private var customSoundRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let d = customDuration {
                Text(L("Âm của bạn: %@ giây", String(format: "%.2f", d))).font(.subheadline)
            } else {
                Text(L("Chưa có âm — chọn một file âm thanh ngắn (m4a, mp3, wav, caf, aiff).")).font(.subheadline).foregroundStyle(.secondary)
            }
            HStack(spacing: 16) {
                Button(customDuration == nil ? L("Chọn file âm thanh…") : L("Chọn âm khác…")) {
                    styleBeforeImport = keySoundStyle; importing = true
                }
                if customDuration != nil {
                    Button(L("Xoá"), role: .destructive) {
                        KeySoundImport.remove()
                        customDuration = nil
                        if keySoundStyle == KeySoundStyle.custom.rawValue { keySoundStyle = KeySoundStyle.defaultStyle.rawValue }
                    }
                }
            }
            .buttonStyle(.borderless)
            Text(L("Âm được cắt lặng đầu, giữ tối đa 0,3 giây và chỉnh độ to an toàn. File chỉ nằm trên máy này (không có trong sao lưu)."))
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func pickStyle(_ raw: String) {
        if raw == KeySoundStyle.custom.rawValue && customDuration == nil {
            styleBeforeImport = keySoundStyle
            keySoundStyle = raw
            importing = true
            return
        }
        keySoundStyle = raw
        KeyFeedbackPreview.shared.playSound(style: raw, volume: max(keySoundVolume, 20))
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            do {
                let o = try KeySoundImport.importFile(url)
                customDuration = o.duration
                keySoundStyle = KeySoundStyle.custom.rawValue
                if o.truncated { importMessage = L("Âm dài hơn 0,3 giây nên đã được cắt ngắn.") }
                KeyFeedbackPreview.shared.playSound(style: keySoundStyle, volume: max(keySoundVolume, 20))
            } catch {
                importMessage = error.localizedDescription
                revertAfterFailedImport()
            }
        case .failure:
            revertAfterFailedImport()
        }
        styleBeforeImport = nil
    }

    /// Huỷ/lỗi khi đang chọn "Âm của bạn" mà chưa có file ⇒ quay lại kiểu trước.
    private func revertAfterFailedImport() {
        if customDuration == nil, keySoundStyle == KeySoundStyle.custom.rawValue {
            keySoundStyle = styleBeforeImport ?? KeySoundStyle.defaultStyle.rawValue
        }
    }

    private func previewSound(final: Bool) {
        guard volumeThrottle.shouldFire(value: keySoundVolume, now: CACurrentMediaTime(), final: final) else { return }
        KeyFeedbackPreview.shared.playSound(style: keySoundStyle, volume: keySoundVolume)
    }

    private func previewHaptic(final: Bool) {
        guard hapticThrottle.shouldFire(value: hapticStrength, now: CACurrentMediaTime(), final: final) else { return }
        KeyFeedbackPreview.shared.playHaptic(strength: hapticStrength)
    }
}
