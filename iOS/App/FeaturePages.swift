// Tab Tính Năng (27/09/2026): trang chính là 8 nhóm (icon + tên + tóm tắt trạng thái),
// mỗi nhóm mở một trang con — thay cho danh sách dài mọi công tắc. Ô tìm kiếm trên đầu
// lọc theo tên/từ khoá rồi mở đúng trang. KHÔNG đổi key/mặc định/cổng Plus: các trang con
// đọc/ghi cùng key App Group như trước. Android dùng cùng cấu trúc (ui/FeaturePages.kt).
import SwiftUI
import UIKit
import UniformTypeIdentifiers

private let featureDefaults = UserDefaults(suiteName: AppFlavor.appGroup)

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
            .init(viTitle: LK("Gợi ý sửa lỗi chạm trượt"), keywords: "chạm trượt phím bên cạnh adjacent typo gợi ý", page: .chinhTa),
            .init(viTitle: LK("Thanh gợi ý"), keywords: "suggestion học từ", page: .goiY),
            .init(viTitle: LK("Gợi ý emoji"), keywords: "emoji biểu tượng", page: .goiY),
            .init(viTitle: LK("Chip số"), keywords: "số tiền đọc số number", page: .goiY),
            .init(viTitle: LK("Hiện kết quả phép tính"), keywords: "tính toán máy tính bằng math calculator", page: .goiY),
            .init(viTitle: LK("Nút Dán"), keywords: "paste dán clipboard", page: .goiY),
            .init(viTitle: LK("Lọc từ nhạy cảm"), keywords: "tục chửi filter", page: .goiY),
            .init(viTitle: LK("Từ điển cá nhân"), keywords: "dictionary tên riêng thuật ngữ", page: .goiY),
            .init(viTitle: LK("Xoá từ đã học"), keywords: "xoá học reset", page: .goiY),
            .init(viTitle: LK("Gõ vuốt"), keywords: "swipe vuốt thử nghiệm", page: .goVuot),
            .init(viTitle: LK("Hiệu ứng nét vuốt"), keywords: "swipe trail nét vuốt vệt hiệu ứng lửa fire điện electric lightning bút lông brush mực ink cầu vồng rainbow neon bụi sao stardust sparkle pháo hoa firework theo giao diện theme plus", page: .goVuot),
            .init(viTitle: LK("Vuốt từ tiếng Anh"), keywords: "swipe english", page: .goVuot),
            .init(viTitle: LK("Mô hình neural gõ vuốt"), keywords: "futo neural swipe", page: .goVuot),
            .init(viTitle: LK("Luyện vuốt"), keywords: "practice swipe", page: .goVuot),
            .init(viTitle: LK("Gõ tắt"), keywords: "shortcut viết tắt", page: .goTat),
            .init(viTitle: LK("Bảng gõ tắt"), keywords: "shortcut yaml import export", page: .goTat),
            .init(viTitle: LK("Mẫu câu"), keywords: "template câu soạn sẵn snippets tắt ẩn tab ☰", page: .goTat),
            .init(viTitle: LK("Hàng phím số"), keywords: "number row số", page: .phim),
            .init(viTitle: LK("Hàng số cao bằng hàng chữ"), keywords: "number row height cao số", page: .phim),
            .init(viTitle: LK("Phím cạnh dấu cách"), keywords: "dấu phẩy dấu chấm comma period key next to space", page: .phim),
            .init(viTitle: LK("Giữ phím ra ký tự đặc biệt"), keywords: "ký hiệu symbol @ # giữ lâu", page: .phim),
            .init(viTitle: LK("Vuốt phím cách đổi Tiếng Việt / Tiếng Anh"), keywords: "space ngôn ngữ english language", page: .phim),
            .init(viTitle: LK("Độ nhạy con trỏ"), keywords: "trackpad con trỏ cursor phím cách space kéo tốc độ nhạy sensitivity speed", page: .phim),
            .init(viTitle: LK("Vuốt phím để sao chép/dán"), keywords: "copy paste cut sao chép dán cắt clipboard vuốt lên swipe", page: .phim),
            .init(viTitle: LK("Phóng to chữ khi bấm"), keywords: "key preview popup", page: .phim),
            .init(viTitle: LK("Phím sẫm khi bấm"), keywords: "pressed key highlight", page: .phim),
            .init(viTitle: LK("Rung phím"), keywords: "haptic rung vibrate", page: .phim),
            .init(viTitle: LK("Âm thanh phím"), keywords: "sound click tiếng âm lượng volume kiểu style gỗ cơ máy chữ bong bóng custom", page: .phim),
            .init(viTitle: LK("Âm thanh gõ"), keywords: "typing sound key sound style kiểu âm iOS system click hệ thống gỗ wood đá rock pop nước water cổ điển vintage pháo firecracker tết chuông jingle bell giáng sinh piano nốt nhạc đàn tranh dan tranh zither việt nam viet nam bàn phím cơ mechanical máy chữ typewriter bong bóng bubble ding sci-fi scifi bíp beep vũ trụ space trống lân lion drum trung thu mid autumn ma quái spooky boo halloween guitar ghi ta ghi-ta đàn ghi-ta acoustic hợp âm chord búa gỗ mallet bop", page: .phim),
            .init(viTitle: LK("Theme & ảnh nền"), keywords: "theme màu chủ đề wallpaper hình nền tết tet năm mới lunar new year mai đào giáng sinh noel christmas xmas tuyết snow piano đàn dương cầm sen lotus hoa sen sen việt đàn tranh dan tranh zither việt nam viet nam máy chữ cổ typewriter vintage gaming rgb cầu vồng rainbow vũ trụ space sao star outer space trung thu mid autumn đèn lồng lantern trăng moon valentine tình yêu love tim heart halloween bí ngô pumpkin dơi bat guitar ghi ta ghi-ta đàn ghi-ta acoustic dây đàn strings đập chuột whack a mole", page: .giaoDien),
            .init(viTitle: LK("Độ trong suốt phím"), keywords: "trong suốt transparent", page: .giaoDien),
            .init(viTitle: LK("Độ trong suốt ký tự"), keywords: "trong suốt transparent chữ", page: .giaoDien),
            .init(viTitle: LK("Tuỳ chỉnh nâng cao"), keywords: "màu chữ màu phím màu nhấn accent color colour bo góc tròn vuông corner radius cỡ chữ size phông font độ đậm weight bold đặt lại reset mặc định giao diện theme", page: .giaoDien),
            .init(viTitle: LK("Dán giao diện"), keywords: "json theme giao diện chép copy paste dán sửa edit nhập import tự tạo custom chia sẻ share", page: .giaoDien),
            .init(viTitle: LK("Bạn đồng hành"), keywords: "bạn đồng hành nhân vật thú cưng mèo gà con cô gái chàng trai buddy keyboard buddy pet character mascot cat chick girl boy nhảy dance ngủ sleep plus", page: .giaoDien),
            .init(viTitle: LK("Hiệu ứng khi bấm phím"), keywords: "key press effect animation hoạt ảnh trái tim heart bong bóng bubble gợn sóng ripple cánh hoa petal pháo hoa firework nháy sáng flash matrix tia sét lightning emoji theo chữ emoji words hoa đào mai tết blossom lửa combo fire mực loang ink sóng nước water wave tuyết rơi snow giáng sinh christmas sao băng shooting star meteor vũ trụ space plus đèn lồng lantern glow trung thu mid autumn sương ma khói smoke spooky mist halloween rung dây string vibration guitar ghi ta đàn ghi-ta", page: .giaoDien),
            .init(viTitle: LK("Đập chuột"), keywords: "đập chuột trò chơi game whack a mole chuột mouse theme giao diện vui fun plus", page: .giaoDien),
            .init(viTitle: LK("Màu nhấn"), keywords: "accent color colour nhập enter return shift tuỳ chỉnh nâng cao", page: .giaoDien),
            .init(viTitle: LK("Khôi phục giao diện gốc"), keywords: "reset mặc định", page: .giaoDien),
            .init(viTitle: LK("Chiều cao hàng phím"), keywords: "height cao thấp stock gốc apple cỡ phím size như bàn phím iphone", page: .giaoDien),
            .init(viTitle: LK("Nâng bàn phím"), keywords: "raise nâng cao đẩy lên khoảng trống dưới padding bottom", page: .giaoDien),
            .init(viTitle: LK("Hiện logo Vᴛ"), keywords: "logo phím cách", page: .giaoDien),
            .init(viTitle: LK("Bàn phím tách đôi"), keywords: "split tách chia hai nửa gập ngang", page: .giaoDien),
            .init(viTitle: LK("Lịch sử clipboard"), keywords: "copy dán clipboard giữ lịch sử 24 giờ 7 ngày keep history", page: .riengTu),
            .init(viTitle: LK("Chế độ ẩn danh"), keywords: "incognito riêng tư", page: .riengTu),
            .init(viTitle: LK("Xuất / nhập file sao lưu"), keywords: "backup export import restore", page: .saoLuu),
        ]
        if UIDevice.current.userInterfaceIdiom == .phone {
            e.append(.init(viTitle: LK("Giữ phím hàng trên để ra số"), keywords: "số giữ lâu number", page: .phim))
            e.append(.init(viTitle: LK("Giữ Shift để gõ số và ký hiệu"), keywords: "shift giữ hold số number ký hiệu symbol 123", page: .phim))
            e.append(.init(viTitle: LK("Chế độ một tay"), keywords: "one hand một tay", page: .phim))
        }
        if PlusGate.isUnlocked(.sentenceDiacritics) {
            e.append(.init(viTitle: LK("Chip “Thêm dấu”"), keywords: "thêm dấu câu không dấu plus", page: .goiY))
        }
        if PlusGate.isUnlocked(.textTools) {
            e.append(.init(viTitle: LK("Công cụ văn bản"), keywords: "text tools hoa thường bỏ dấu dịch translate plus", page: .goTat))
        }
        if PlusFeature.translate.isAvailableOnDevice, PlusGate.isUnlocked(.translate) {
            e.append(.init(viTitle: LK("Dịch trên máy"), keywords: "translate dịch ngôn ngữ language gói dịch plus", page: .goTat))
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
    @AppStorage(KeyGeometry.numberRowFullHeightKey, store: featureDefaults) private var numberRowFullHeight = false
    @AppStorage("spaceSwipeLanguage", store: featureDefaults) private var spaceSwipeLanguage = false
    @AppStorage("swipeKeyCommands", store: featureDefaults) private var swipeKeyCommands = false
    @AppStorage("autoSpaceAfterPunct", store: featureDefaults) private var autoSpaceAfterPunct = false
    @AppStorage("hapticFeedback", store: featureDefaults) private var hapticFeedback = false
    @AppStorage("keySound", store: featureDefaults) private var keySound = false
    @AppStorage(PlusFeature.textToolsKey, store: featureDefaults) private var textToolsEnabled = true
    @AppStorage("oneHandMode", store: featureDefaults) private var oneHandMode = "off"
    @AppStorage(SpaceSideKey.key, store: featureDefaults) private var spaceSideKey = SpaceSideKey.defaultValue.rawValue
    @AppStorage(EmojiKeyPlacement.key, store: featureDefaults) private var emojiKeyPlacement = EmojiKeyPlacement.defaultValue.rawValue
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
            let tools = textToolsEnabled && PlusGate.isUnlocked(.textTools)
            return st + " · " + (templatesEnabled ? L("Mẫu câu bật") : L("Mẫu câu tắt"))
                + (tools ? " · " + L("Công cụ văn bản") : "")
        case .phim:
            return Self.join([(numberRow, numberRowFullHeight ? L("Hàng số cao") : L("Hàng số")),
                              (SpaceSideKey.parse(spaceSideKey) != .defaultValue, L("Phím cạnh dấu cách")),
                              (EmojiKeyPlacement.parse(emojiKeyPlacement) != .defaultValue, L("Nút emoji")),
                              (spaceSwipeLanguage, L("Vuốt phím cách")),
                              (swipeKeyCommands, L("Vuốt sao chép/dán")),
                              (autoSpaceAfterPunct, L("Cách sau dấu câu")),
                              (hapticFeedback, L("Rung")), (keySound, L("Âm phím")),
                              (oneHandMode != "off", L("Một tay"))], none: L("Mặc định"))
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
    /// Mặc định BẬT (KeyboardSettings.autoFixAdjacent) — trước nằm ở tab Kiểu Gõ, chuyển về đây
    /// cạnh hai công tắc chạm trượt anh em (14/10/2026).
    @AppStorage("autoFixAdjacent", store: featureDefaults) private var autoFixAdjacent = true

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
                settingToggle(L("Gợi ý sửa lỗi chạm trượt"), L("Khi từ đang gõ không phải tiếng Việt, gợi ý từ đúng nếu bạn lỡ chạm phím bên cạnh: nbjeeuf → nhiều, ohims → phím, cahcs → cách. Chạm gợi ý để thay."), isOn: $autoFixAdjacent)
            } header: { Text(L("Chạm trượt")) } footer: {
                Text(L("Gợi ý sửa lỗi hiện trên thanh gợi ý (cần bật Thanh gợi ý)."))
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
    @State private var confirmErase = false
    @State private var erased = false

    var body: some View {
        FeaturePageList(page: .goiY) {
            Section {
                // Thanh gợi ý bật = tự học từ hay dùng (learnWords đi theo — quyết định 2026-07-24).
                settingToggle(L("Thanh gợi ý"), L("Gợi ý từ + emoji, tự học từ bạn hay dùng (chỉ trên máy)."), isOn: $showSuggestions)
                if showSuggestions {
                    SuggestionCountRow()
                    settingToggle(L("Gợi ý cả khi ứng dụng tắt gợi ý"), L("Ô mà ứng dụng tắt gợi ý (vd ô chat, thanh địa chỉ) vẫn gợi ý từ — không tự sửa, không học từ gõ ở đó. Mật khẩu, ẩn danh, ô số không bị ảnh hưởng."), isOn: $suggestInNoSuggestFields)
                    settingToggle(L("Gợi ý emoji"), L("Emoji hợp với từ đang gõ (yêu → ❤️)."), isOn: $emojiSuggest)
                    settingToggle(L("Chip số"), L("Đọc số thành chữ, định dạng tiền (1tr2 → 1.200.000 ₫)."), isOn: $numberChips)
                    settingToggle(L("Hiện kết quả phép tính"), L("Gõ phép tính (12*3, không cần dấu =) → kết quả “= 36” hiện ở đầu thanh gợi ý, chạm để chèn. Dấu = ở bàn 123: giữ phím /."), isOn: $mathResults)
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
                // Không hoàn tác được ⇒ hỏi lại trước khi xoá, xoá xong báo ngay dưới nút.
                Button(L("Xoá từ đã học"), role: .destructive) { confirmErase = true }
                    .confirmationDialog(L("Xoá mọi từ bàn phím đã học?"), isPresented: $confirmErase,
                                        titleVisibility: .visible) {
                        Button(L("Xoá từ đã học"), role: .destructive) {
                            // Xoá file + đổi mốc userlmResetAt ⇒ bàn phím bỏ bảng trong RAM lần hiện kế tiếp.
                            UserDictStore.eraseAll()
                            erased = true
                        }
                        Button(L("Huỷ"), role: .cancel) {}
                    } message: {
                        Text(L("Gợi ý sẽ học lại từ đầu. Từ bạn thêm tay trong Từ điển cá nhân cũng bị xoá. Không hoàn tác được."))
                    }
                if erased {
                    Label(L("Đã xoá từ đã học."), systemImage: "checkmark.circle.fill")
                        .font(.footnote).foregroundStyle(.green)
                }
            } header: { Text(L("Từ đã học")) }
        }
    }
}

/// "Số từ gợi ý" (SuggestionCount): một hàng gọn − [giá trị] +, Tự động → 1 → … → 5
/// (− ở 1 về Tự động). VoiceOver: một phần tử chỉnh được (vuốt lên/xuống).
struct SuggestionCountRow: View {
    @AppStorage(SuggestionCount.key, store: featureDefaults) private var count = SuggestionCount.auto

    private var valueText: String { count <= SuggestionCount.auto ? L("Tự động") : "\(count)" }

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Số từ gợi ý"))
                Text(L("Tự động: 3 từ. Máy hẹp có thể hiện ít hơn để ô đủ rộng cho dễ chạm."))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            HStack(spacing: 0) {
                Button { count = SuggestionCount.step(count, by: -1) } label: {
                    Image(systemName: "minus").frame(width: 36, height: 32)
                }
                .disabled(count <= SuggestionCount.auto)
                Text(valueText)
                    .monospacedDigit()
                    .frame(minWidth: 64)
                Button { count = SuggestionCount.step(count, by: 1) } label: {
                    Image(systemName: "plus").frame(width: 36, height: 32)
                }
                .disabled(count >= SuggestionCount.max)
            }
            .buttonStyle(.borderless)   // trong List: hai nút bấm riêng, không ăn cả hàng
            .background(Color(.tertiarySystemFill), in: Capsule())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("Số từ gợi ý"))
        .accessibilityValue(valueText)
        .accessibilityAdjustableAction { dir in
            switch dir {
            case .increment: count = SuggestionCount.step(count, by: 1)
            case .decrement: count = SuggestionCount.step(count, by: -1)
            @unknown default: break
            }
        }
    }
}

struct GoVuotPage: View {
    @AppStorage("swipeTyping", store: featureDefaults) private var swipeTyping = false
    /// Công tắc con — mặc định BẬT, xem KeyboardSettings.swipeEnglish.
    @AppStorage("swipeEnglish", store: featureDefaults) private var swipeEnglish = true
    /// Decoder FUTO Swipe — mặc định TẮT, xem KeyboardSettings.swipeFuto.
    @AppStorage("swipeFuto", store: featureDefaults) private var swipeFuto = false
    /// "Hiệu ứng nét vuốt" (SwipeTrailStyle) — trang con SwipeTrailPickerView.
    @AppStorage(SwipeTrailStyle.key, store: featureDefaults) private var swipeTrailRaw = SwipeTrailStyle.defaultValue.rawValue

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
            Section {
                NavigationLink {
                    SwipeTrailPickerView()
                } label: {
                    HStack(spacing: 6) {
                        Text(L("Hiệu ứng nét vuốt"))
                        if !SwipeTrailGate.allows { SwipeTrailPlusBadge() }
                        Spacer()
                        Text(SwipeTrailStyle.displayed(swipeTrailRaw).title)
                            .foregroundStyle(.secondary).lineLimit(1)
                    }
                }
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
    @AppStorage(PlusFeature.textToolsKey, store: featureDefaults) private var textToolsEnabled = true

    var body: some View {
        FeaturePageList(page: .goTat) {
            ShortcutsSection()
            Section {
                settingToggle(L("Mẫu câu"), L("Nút ☰ trên bàn phím chèn câu soạn sẵn — quản lý ở tab Mẫu Câu. Tắt: ẩn tab Mẫu Câu; nút ☰ chỉ còn mở Công cụ văn bản (nếu bật)."), isOn: $templatesEnabled)
                if PlusGate.isUnlocked(.textTools) {
                    // Mẫu câu tắt ⇒ ☰ vẫn hiện và mở thẳng Công cụ (KeyboardView.LeftZone.tools).
                    settingToggle(L("Công cụ văn bản"), L("Chip ⚒️ Công cụ trong lưới mẫu câu (Mẫu câu tắt: chạm ☰ mở thẳng): đổi HOA/thường, bỏ dấu, dịch…"), isOn: $textToolsEnabled)
                }
                if PlusFeature.translate.isAvailableOnDevice, PlusGate.isUnlocked(.translate), #available(iOS 26.0, *) {
                    NavigationLink { TranslateSettingsView() } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("Dịch trên máy"))
                            Text(L("Chọn ngôn ngữ dịch + tải gói dịch cho chip “Dịch ↔ …” trong Công cụ."))
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            } header: { Text(L("Mẫu câu")) }
        }
    }
}

struct PhimPage: View {
    @AppStorage("numberRow", store: featureDefaults) private var numberRow = false
    /// Hàng số cao bằng hàng chữ — mặc định TẮT (phím số 0.8×, KeyGeometry.numberRowFullHeightKey).
    @AppStorage(KeyGeometry.numberRowFullHeightKey, store: featureDefaults) private var numberRowFullHeight = false
    /// Giữ phím chữ ra ký tự phụ (KeyAlternates) — số mặc định BẬT, ký hiệu TẮT.
    @AppStorage("longPressNumbers", store: featureDefaults) private var longPressNumbers = true
    @AppStorage("longPressSymbols", store: featureDefaults) private var longPressSymbols = false
    /// Giữ ⇧ + phím chữ ra ký tự phụ (ShiftHold) — mặc định BẬT.
    @AppStorage("holdShiftSymbols", store: featureDefaults) private var holdShiftSymbols = true
    /// Vuốt phím cách đổi Tiếng Việt ↔ Tiếng Anh — mặc định TẮT (KeyboardSettings.spaceSwipeLanguage).
    @AppStorage("spaceSwipeLanguage", store: featureDefaults) private var spaceSwipeLanguage = false
    /// Vuốt phím C / X / V lên ra lệnh sao chép / cắt / dán — mặc định TẮT (KeyCommandGesture).
    @AppStorage("swipeKeyCommands", store: featureDefaults) private var swipeKeyCommands = false
    /// "Độ nhạy con trỏ" khi giữ phím cách: "slow" | "medium" (mặc định) | "fast" (TrackpadSpeed).
    @AppStorage(TrackpadSpeed.key, store: featureDefaults) private var trackpadSpeed = TrackpadSpeed.defaultValue.rawValue
    /// Tự thêm dấu cách sau . , ? ! ; : — mặc định TẮT (KeyboardSettings.autoSpaceAfterPunct).
    @AppStorage("autoSpaceAfterPunct", store: featureDefaults) private var autoSpaceAfterPunct = false
    /// "off" | "left" | "right" — bàn phím đọc lúc hiện (OneHand.resolve).
    @AppStorage("oneHandMode", store: featureDefaults) private var oneHandMode = "off"
    /// "Phím cạnh dấu cách": "comma" (mặc định) | "period" | "both" | "off" — bàn phím đọc lúc hiện (SpaceSideKey).
    @AppStorage(SpaceSideKey.key, store: featureDefaults) private var spaceSideKey = SpaceSideKey.defaultValue.rawValue
    /// "Nút emoji": "bottom" (mặc định) | "top" — bàn phím đọc lúc hiện (EmojiKeyPlacement).
    @AppStorage(EmojiKeyPlacement.key, store: featureDefaults) private var emojiKeyPlacement = EmojiKeyPlacement.defaultValue.rawValue
    /// Ô phóng to chữ khi bấm phím — mặc định BẬT (KeyboardView.keyPreviewKey).
    @AppStorage("keyPreviewEnabled", store: featureDefaults) private var keyPreview = true
    /// Phím sẫm khi bấm (KeyboardView.keyPressHighlightKey) — mặc định = keyPressHighlightDefault.
    @AppStorage("keyPressHighlight", store: featureDefaults) private var keyPressHighlight = true
    @AppStorage("hapticFeedback", store: featureDefaults) private var hapticFeedback = false
    @AppStorage("hapticStrength", store: featureDefaults) private var hapticStrength = 45
    @AppStorage("keySound", store: featureDefaults) private var keySound = false
    @AppStorage("keySoundStyle", store: featureDefaults) private var keySoundStyle = KeySoundStyle.defaultStyle.rawValue
    /// Rung thử khi kéo thanh trượt: ≤ 1 lần / 120 ms + lúc thả.
    @State private var hapticThrottle = PreviewThrottle()

    private var isPhone: Bool { UIDevice.current.userInterfaceIdiom == .phone }

    var body: some View {
        FeaturePageList(page: .phim) {
            Section {
                settingToggle(L("Hàng phím số"), L("Thêm hàng 1 … 0 trên hàng chữ (bàn phím cao thêm gần một hàng)."), isOn: $numberRow)
                if numberRow {
                    settingToggle(L("Hàng số cao bằng hàng chữ"), L("Phím số to bằng phím chữ (mặc định thấp hơn một chút). Bàn phím cao thêm đúng một hàng."), isOn: $numberRowFullHeight)
                }
                // iPad có ký tự phụ vuốt xuống riêng ⇒ chỉ iPhone.
                if isPhone {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L("Phím cạnh dấu cách"))
                        Picker(L("Phím cạnh dấu cách"), selection: Binding(
                            get: { SpaceSideKey.parse(spaceSideKey).rawValue },
                            set: { spaceSideKey = $0 })) {
                            Text(L("Dấu phẩy")).tag(SpaceSideKey.comma.rawValue)
                            Text(L("Dấu chấm")).tag(SpaceSideKey.period.rawValue)
                            Text(L("Cả hai")).tag(SpaceSideKey.both.rawValue)
                            Text(L("Tắt")).tag(SpaceSideKey.off.rawValue)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        Text(L("Phím hẹp bên phải phím cách trên bàn chữ (ô email, đường dẫn giữ nguyên). Dấu chấm: giữ phím ra dấu phẩy (khi bật giữ phím ra ký tự đặc biệt). Cả hai: dấu phẩy bên trái, dấu chấm bên phải phím cách. Tắt: phím cách rộng hơn; chạm phím cách hai lần vẫn ra dấu chấm."))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L("Nút emoji"))
                        Picker(L("Nút emoji"), selection: Binding(
                            get: { EmojiKeyPlacement.parse(emojiKeyPlacement).rawValue },
                            set: { emojiKeyPlacement = $0 })) {
                            Text(L("Hàng dưới")).tag(EmojiKeyPlacement.bottom.rawValue)
                            Text(L("Thanh trên")).tag(EmojiKeyPlacement.top.rawValue)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        Text(L("Thanh trên: nút 😊 lên thanh gợi ý (sát mép phải), phím cách rộng hơn. Khi thanh gợi ý tắt hoặc không hiện ở ô đang gõ, nút 😊 vẫn ở hàng dưới."))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if !numberRow {
                        settingToggle(L("Giữ phím hàng trên để ra số"), L("Giữ q … p để gõ 1 … 0 (số nhỏ ở góc phím)."), isOn: $longPressNumbers)
                    }
                    settingToggle(L("Giữ phím hàng 2, 3 để ra ký tự đặc biệt"), L("Giữ a … l, z … m để gõ @ # $ _ & - + ( ) … Giữ , để ra dấu chấm."), isOn: $longPressSymbols)
                    settingToggle(L("Giữ Shift để gõ số và ký hiệu"), L("Giữ ⇧ rồi chạm phím chữ để gõ ký tự nhỏ ở góc phím (q w e → 1 2 3) thay vì chữ hoa. Chạm ⇧ vẫn viết hoa một chữ, chạm đôi để khoá."), isOn: $holdShiftSymbols)
                }
                settingToggle(L("Tự thêm dấu cách sau dấu câu"), L("Gõ . , ? ! ; : tự có dấu cách phía sau. Không thêm trong số (3.5, 1,000), email, đường dẫn. Gõ dấu cách ngay sau không thành hai dấu cách; ⌫ ngay sau chỉ xoá dấu cách đó."), isOn: $autoSpaceAfterPunct)
            } header: { Text(L("Phím")) }
            Section {
                settingToggle(L("Vuốt phím cách đổi Tiếng Việt / Tiếng Anh"), L("Vuốt nhanh phím cách sang trái/phải. Góc phím cách hiện VI / EN. Tiếng Anh gõ nguyên văn. Giữ rồi kéo vẫn là di con trỏ."), isOn: $spaceSwipeLanguage)
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("Độ nhạy con trỏ"))
                    Picker(L("Độ nhạy con trỏ"), selection: Binding(
                        get: { TrackpadSpeed.parse(trackpadSpeed).rawValue },
                        set: { trackpadSpeed = $0 })) {
                        Text(L("Chậm")).tag(TrackpadSpeed.slow.rawValue)
                        Text(L("Vừa")).tag(TrackpadSpeed.medium.rawValue)
                        Text(L("Nhanh")).tag(TrackpadSpeed.fast.rawValue)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Text(L("Giữ phím cách rồi kéo để di con trỏ. Kéo chậm luôn đi từng ký tự; mức này chỉnh độ tăng tốc khi kéo nhanh."))
                        .font(.footnote).foregroundStyle(.secondary)
                }
                settingToggle(L("Vuốt phím để sao chép/dán"), L("Chạm C, X hoặc V rồi vuốt thẳng lên quá hàng phím trên cùng và nhấc tay: C sao chép, X cắt, V dán. Kéo ngón trở xuống để huỷ. iOS không cho bàn phím chọn chữ, chọn hết hay hoàn tác/làm lại; sao chép, cắt và dán cần bật Truy cập đầy đủ."), isOn: $swipeKeyCommands)
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
                        Text(L("Thu hẹp bàn phím về một bên. Giữ lâu nút ☰ trên thanh gợi ý để bật/tắt nhanh; khi tắt Mẫu câu, nút đó thành nút một tay (chạm để bật/tắt)."))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            } header: { Text(L("Cử chỉ")) }
            Section {
                settingToggle(L("Phóng to chữ khi bấm"), L("Ô chữ lớn nổi trên phím vừa chạm. Tắt cho gọn, nhẹ máy."), isOn: $keyPreview)
                settingToggle(L("Phím sẫm khi bấm"), L("Phím đổi màu trong lúc chạm như bàn phím iPhone, kể cả khi tắt phóng to chữ."), isOn: $keyPressHighlight)
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
                    // "Âm thanh gõ" (Phil 19/10/2026): trang con chọn kiểu + âm lượng + âm tự chọn.
                    NavigationLink { KeySoundStylePage() } label: {
                        HStack {
                            Text(L("Âm thanh gõ"))
                            Spacer()
                            Text(L(KeySoundStyle.resolve(keySoundStyle, customAvailable: true).viTitle))
                                .foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    if KeySoundStyle.needsEngine(keySoundStyle) {
                        FullAccessNotice(reason: L("Âm thanh phím"))
                    }
                }
            } header: { Text(L("Phản hồi khi chạm")) }
        }
    }

    private func previewHaptic(final: Bool) {
        guard hapticThrottle.shouldFire(value: hapticStrength, now: CACurrentMediaTime(), final: final) else { return }
        KeyFeedbackPreview.shared.playHaptic(strength: hapticStrength)
    }
}

/// "Âm thanh gõ" (Phil 19/10/2026): chọn kiểu âm phím — "iOS" (click hệ thống) đầu, 11 kiểu tổng hợp + Piano,
/// "Âm của bạn" cuối. Chạm một kiểu = chọn + nghe thử chữ → xoá → phím chức năng. Âm lượng + nhập âm
/// tự chọn ở đây (Android: KeySoundPage, cùng bố cục). Mọi kiểu miễn phí.
struct KeySoundStylePage: View {
    @AppStorage("keySoundVolume", store: featureDefaults) private var keySoundVolume = 50
    @AppStorage("keySoundStyle", store: featureDefaults) private var keySoundStyle = KeySoundStyle.defaultStyle.rawValue
    @State private var volumeThrottle = PreviewThrottle()
    @State private var importing = false
    @State private var styleBeforeImport: String?
    @State private var customDuration: Double?
    @State private var importMessage: String?

    private var current: KeySoundStyle { KeySoundStyle.resolve(keySoundStyle, customAvailable: true) }

    var body: some View {
        List {
            Section {
                ForEach(KeySoundStyle.menuOrder, id: \.rawValue) { st in
                    Button { pickStyle(st.rawValue) } label: {
                        HStack {
                            Text(L(st.viTitle)).foregroundStyle(Color.primary)
                            Spacer()
                            if current == st {
                                Image(systemName: "checkmark").foregroundStyle(Color.accentColor).font(.body.weight(.semibold))
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .accessibilityAddTraits(current == st ? .isSelected : [])
                }
            } header: {
                Text(L("Chạm một kiểu để chọn và nghe thử."))
            } footer: {
                Text(L("iOS: tiếng bấm bàn phím của hệ thống — theo Cài đặt → Âm thanh & Cảm ứng → Phản hồi bàn phím, không cần Toàn quyền Truy cập. Các kiểu khác là tiếng riêng của VietTelex (cần Toàn quyền Truy cập)."))
            }
            if current == .custom || customDuration != nil {
                Section { customSoundRow }
            }
            if current.usesEngine {
                Section {
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
            }
        }
        .bottomBarScrollMargin()
        .navigationTitle(L("Âm thanh gõ"))
        .navigationBarTitleDisplayMode(.inline)
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
        KeyFeedbackPreview.shared.playStyle(raw, volume: max(keySoundVolume, 20))
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            do {
                let o = try KeySoundImport.importFile(url)
                customDuration = o.duration
                keySoundStyle = KeySoundStyle.custom.rawValue
                if o.truncated { importMessage = L("Âm dài hơn 0,3 giây nên đã được cắt ngắn.") }
                KeyFeedbackPreview.shared.playStyle(keySoundStyle, volume: max(keySoundVolume, 20))
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
}
