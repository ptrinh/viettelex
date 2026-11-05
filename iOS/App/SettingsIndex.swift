// Cấu trúc cài đặt (docs/SETTINGS-CLEANUP-SPEC.md §3–§4) — phần THUẦN (không SwiftUI) để test:
// các trang của tab Tính Năng, nhãn chung (bảng §3), chỉ mục ô tìm cài đặt và chỗ mỗi mục nằm.
// Giao diện ở FeaturePages.swift (icon, màu, trang đích). KHÔNG đổi key/mặc định: chỉ đổi chỗ
// hiển thị. Song sinh Android ui/FeaturePages.kt.
import Foundation

/// Các trang của tab Tính Năng — cùng thứ tự/tên với Android.
enum FeaturePage: String, CaseIterable, Identifiable {
    case suaLoi, goVuot, goTat, phim, giaoDien, riengTu, nangCao
    var id: String { rawValue }

    var title: String { L(viTitle) }
    /// Tên gốc tiếng Việt — khoá tra L10n và so khớp tìm kiếm.
    var viTitle: String {
        switch self {
        case .suaLoi: return LK("Sửa lỗi & gợi ý")
        case .goVuot: return LK("Gõ vuốt")
        case .goTat: return LK("Gõ tắt & mẫu câu")
        case .phim: return LK("Phím & cử chỉ")
        case .giaoDien: return LK("Giao diện")
        case .riengTu: return LK("Riêng tư & sao lưu")
        case .nangCao: return LK("Nâng cao / Gỡ lỗi")
        }
    }
    /// Cả nhóm đang thử nghiệm → nhãn nhỏ ngay trên dòng.
    var experimental: Bool { self == .goVuot }
    /// Mục tương ứng trong Hướng dẫn sử dụng (docs/hdsd/index.html); nil = không có mục riêng.
    var guideAnchor: String? {
        switch self {
        case .suaLoi: return "goi-y"
        case .goVuot: return "go-vuot"
        case .goTat: return "go-tat"
        case .phim: return "cu-chi"
        case .giaoDien: return "giao-dien"
        case .riengTu: return "sao-luu"
        case .nangCao: return nil
        }
    }

    /// Các nhóm hiển thị theo khối như app Cài đặt; "Nâng cao / Gỡ lỗi" cuối danh sách.
    static let groups: [[FeaturePage]] = [[.suaLoi, .goVuot, .goTat], [.phim, .giaoDien], [.riengTu], [.nangCao]]
}

/// Nhãn dùng chung mọi nền tảng (SETTINGS-CLEANUP-SPEC §3) — giao diện + chỉ mục tìm kiếm đọc từ đây.
enum SettingLabel {
    static let freeMarking = LK("Bỏ dấu tự do")
    static let modernTone = LK("Bỏ dấu kiểu mới (oà, uý)")
    static let reEditWord = LK("Sửa dấu từ đã gõ")
    static let numberChips = LK("Gợi ý số tiền")
    static let autoRestore = LK("Tự khôi phục từ tiếng Anh")
    static let simpleTelex = LK("Telex đơn giản")
    static let quickTelex = LK("Gõ nhanh (Quick Telex)")
    static let teencode = LK("Chính tả teencode")
    static let autoCapitalize = LK("Tự động viết hoa đầu câu")
    /// Một tên cho mọi cách thêm dấu cả câu (§4).
    static let addTones = LK("Thêm dấu")
    static let swipeEnglish = LK("Vuốt từ tiếng Anh")
    static let feedbackPage = LK("Phản hồi khi chạm")
    /// Trang con "Nâng cao" của mục Kiểu gõ + dòng phụ liệt kê bên trong.
    static let typingAdvanced = LK("Nâng cao")
    static let typingAdvancedSubtitle = LK("Telex đơn giản, bỏ dấu tự do, gõ nhanh, bỏ dấu kiểu mới, teencode…")
}

/// Nơi một mục cài đặt nằm — ô tìm kiếm mở đúng chỗ này.
enum SettingsLocation: Hashable {
    /// Trang Tính Năng.
    case page(FeaturePage)
    /// Tính Năng › Phím & cử chỉ › Phản hồi khi chạm.
    case feedback
    /// Kiểu Gõ › Kiểu gõ › Nâng cao.
    case typingAdvanced
    /// Kiểu Gõ › Gõ lẫn tiếng Anh (cấp 1 của nhóm): đổi tab, mở nhóm, cuộn tới dòng.
    case mixed(MixedTypingItem)
    /// Kiểu Gõ › Gõ lẫn tiếng Anh › Nâng cao.
    case mixedAdvanced(MixedTypingItem)

    /// Khoá L10n của đường dẫn hiện dưới kết quả tìm kiếm (nối bằng " › ").
    var pathKeys: [String] {
        let typing = LK("Kiểu Gõ")
        switch self {
        case .page(let p): return [p.viTitle]
        case .feedback: return [FeaturePage.phim.viTitle, SettingLabel.feedbackPage]
        case .typingAdvanced: return [typing, SettingLabel.typingAdvanced]
        case .mixed: return [typing, MixedTypingUI.titleKey]
        case .mixedAdvanced: return [typing, MixedTypingUI.titleKey, MixedTypingUI.advancedTitleKey]
        }
    }
}

/// Một dòng của chỉ mục tìm kiếm.
struct SettingsIndexEntry: Hashable {
    /// Điều kiện hiện (tính năng Plus / chỉ iPhone…) — app đánh giá lúc tìm.
    enum Condition: Hashable { case always, phoneOnly, addTones, aiProofread, textTools, translate, iCloud }

    let viTitle: String
    let keywords: String
    let location: SettingsLocation
    /// Key App Group của công tắc (nil = không phải công tắc / nhiều key).
    var key: String? = nil
    var condition: Condition = .always

    var title: String { L(viTitle) }
    /// Dòng tên trang (kết quả tìm khớp tên trang).
    var isPage: Bool { if case .page(let p) = location { return p.viTitle == viTitle }; return false }
}

enum SettingsIndex {
    static let all: [SettingsIndexEntry] = {
        typealias E = SettingsIndexEntry
        var e: [E] = [
            // Kiểu Gõ › Nâng cao
            E(viTitle: SettingLabel.simpleTelex, keywords: "w ư simple telex nâng cao advanced", location: .typingAdvanced, key: "simpleTelex"),
            E(viTitle: SettingLabel.freeMarking, keywords: "free marking đặt dấu thứ tự nâng cao advanced", location: .typingAdvanced, key: "freeMarking"),
            E(viTitle: SettingLabel.quickTelex, keywords: "quick telex gõ nhanh cc ch gg gi nn ng phụ âm nâng cao advanced", location: .typingAdvanced, key: "quickTelex"),
            E(viTitle: SettingLabel.modernTone, keywords: "hoà hòa thuý thúy kiểu mới kiểu cũ modern tone nâng cao advanced", location: .typingAdvanced, key: "modernTone"),
            E(viTitle: SettingLabel.teencode, keywords: "teencode chat wá zui nâng cao advanced", location: .typingAdvanced, key: "teencode"),
            // Sửa lỗi & gợi ý
            E(viTitle: LK("Kiểm tra chính tả khi gõ"), keywords: "spell check", location: .page(.suaLoi), key: "liveSpellCheck"),
            E(viTitle: SettingLabel.reEditWord, keywords: "sửa dấu con trỏ backspace", location: .page(.suaLoi), key: "reEditWord"),
            E(viTitle: LK("Chọn phím thông minh"), keywords: "chạm trượt smart touch thử nghiệm", location: .page(.suaLoi), key: "smartTouch"),
            E(viTitle: LK("Tự sửa từ gõ sai"), keywords: "autocorrect sửa lỗi chạm trượt thử nghiệm", location: .page(.suaLoi), key: "autoCorrect"),
            E(viTitle: LK("Gợi ý sửa lỗi chạm trượt"), keywords: "chạm trượt phím bên cạnh adjacent typo gợi ý", location: .page(.suaLoi), key: "autoFixAdjacent"),
            E(viTitle: LK("Thanh gợi ý"), keywords: "suggestion học từ", location: .page(.suaLoi), key: "showSuggestions"),
            E(viTitle: LK("Gợi ý emoji"), keywords: "emoji biểu tượng", location: .page(.suaLoi), key: "emojiSuggest"),
            E(viTitle: SettingLabel.numberChips, keywords: "chip số tiền đọc số number money", location: .page(.suaLoi), key: "numberChips"),
            E(viTitle: LK("Hiện kết quả phép tính"), keywords: "tính toán máy tính bằng math calculator", location: .page(.suaLoi), key: "mathResults"),
            E(viTitle: LK("Nút Dán"), keywords: "paste dán clipboard", location: .page(.suaLoi), key: "pasteButton"),
            E(viTitle: LK("Lọc từ nhạy cảm"), keywords: "tục chửi filter", location: .page(.suaLoi), key: "filterSensitive"),
            E(viTitle: LK("Từ điển cá nhân"), keywords: "dictionary tên riêng thuật ngữ", location: .page(.suaLoi)),
            E(viTitle: LK("Xoá từ đã học"), keywords: "xoá học reset", location: .page(.suaLoi)),
            E(viTitle: SettingLabel.addTones, keywords: "chip thêm dấu câu không dấu add tones plus", location: .page(.suaLoi), key: "addTonesChip", condition: .addTones),
            E(viTitle: LK("Sửa lỗi bằng Apple Intelligence"), keywords: "apple intelligence ai trí tuệ nhân tạo sửa lỗi chính tả ngữ pháp proofread grammar spelling từ thay thế đồng nghĩa synonym plus", location: .page(.suaLoi), key: "aiProofread", condition: .aiProofread),
            // Gõ vuốt
            E(viTitle: LK("Gõ vuốt"), keywords: "swipe vuốt thử nghiệm", location: .page(.goVuot), key: "swipeTyping"),
            E(viTitle: SettingLabel.swipeEnglish, keywords: "swipe english check mail meeting", location: .page(.goVuot), key: "swipeEnglish"),
            E(viTitle: LK("Hiệu ứng nét vuốt"), keywords: "swipe trail nét vuốt vệt hiệu ứng lửa fire điện electric lightning bút lông brush mực ink cầu vồng rainbow neon bụi sao stardust sparkle pháo hoa firework theo giao diện theme plus", location: .page(.goVuot)),
            E(viTitle: LK("Mô hình neural gõ vuốt"), keywords: "futo neural swipe", location: .page(.goVuot), key: "swipeFuto"),
            E(viTitle: LK("Luyện vuốt"), keywords: "practice swipe", location: .page(.goVuot)),
            // Gõ tắt & mẫu câu
            E(viTitle: LK("Gõ tắt"), keywords: "shortcut viết tắt", location: .page(.goTat)),
            E(viTitle: LK("Bảng gõ tắt"), keywords: "shortcut yaml import export", location: .page(.goTat)),
            E(viTitle: LK("Mẫu câu"), keywords: "template câu soạn sẵn snippets tắt ẩn tab ☰", location: .page(.goTat), key: "templatesEnabled"),
            E(viTitle: LK("Công cụ văn bản"), keywords: "text tools hoa thường bỏ dấu dịch translate plus", location: .page(.goTat), condition: .textTools),
            E(viTitle: LK("Dịch trên máy"), keywords: "translate dịch ngôn ngữ language gói dịch plus", location: .page(.goTat), condition: .translate),
            // Phím & cử chỉ
            E(viTitle: LK("Hàng phím số"), keywords: "number row số", location: .page(.phim), key: "numberRow"),
            E(viTitle: LK("Hàng số cao bằng hàng chữ"), keywords: "number row height cao số", location: .page(.phim)),
            E(viTitle: LK("Phím cạnh dấu cách"), keywords: "dấu phẩy dấu chấm comma period key next to space", location: .page(.phim)),
            E(viTitle: LK("Phím to"), keywords: "larger keys phím lớn dấu phẩy dấu chấm shift xoá comma period backspace bấm nhầm", location: .page(.phim)),
            E(viTitle: LK("Giữ phím ra ký tự đặc biệt"), keywords: "ký hiệu symbol @ # giữ lâu", location: .page(.phim)),
            E(viTitle: LK("Giữ phím hàng trên để ra số"), keywords: "số giữ lâu number", location: .page(.phim), condition: .phoneOnly),
            E(viTitle: LK("Giữ Shift để gõ số và ký hiệu"), keywords: "shift giữ hold số number ký hiệu symbol 123", location: .page(.phim), condition: .phoneOnly),
            E(viTitle: LK("Chế độ một tay"), keywords: "one hand một tay", location: .page(.phim), condition: .phoneOnly),
            E(viTitle: LK("Độ nhạy con trỏ"), keywords: "trackpad con trỏ cursor phím cách space kéo tốc độ nhạy sensitivity speed", location: .page(.phim)),
            E(viTitle: LK("Vuốt phím để sao chép/dán"), keywords: "copy paste cut sao chép dán cắt clipboard vuốt lên swipe", location: .page(.phim)),
            // Phím & cử chỉ › Phản hồi khi chạm
            E(viTitle: SettingLabel.feedbackPage, keywords: "feedback rung âm thanh haptic sound", location: .feedback),
            E(viTitle: LK("Phóng to chữ khi bấm"), keywords: "key preview popup phóng to phím", location: .feedback, key: "keyPreviewEnabled"),
            E(viTitle: LK("Phím sẫm khi bấm"), keywords: "pressed key highlight", location: .feedback, key: "keyPressHighlight"),
            E(viTitle: LK("Rung phím"), keywords: "haptic rung vibrate", location: .feedback, key: "hapticFeedback"),
            E(viTitle: LK("Âm thanh phím"), keywords: "sound click tiếng âm lượng volume kiểu style gỗ cơ máy chữ bong bóng custom", location: .feedback, key: "keySound"),
            E(viTitle: LK("Âm thanh gõ"), keywords: "typing sound key sound style kiểu âm iOS system click hệ thống gỗ wood đá rock pop nước water cổ điển vintage pháo firecracker tết chuông jingle bell giáng sinh piano nốt nhạc đàn tranh dan tranh zither việt nam viet nam bàn phím cơ mechanical máy chữ typewriter bong bóng bubble ding sci-fi scifi bíp beep vũ trụ space trống lân lion drum trung thu mid autumn ma quái spooky boo halloween guitar ghi ta ghi-ta đàn ghi-ta acoustic hợp âm chord búa gỗ mallet bop", location: .feedback),
            // Giao diện
            E(viTitle: LK("Theme & ảnh nền"), keywords: "theme màu chủ đề wallpaper hình nền tết tet năm mới lunar new year mai đào giáng sinh noel christmas xmas tuyết snow piano đàn dương cầm sen lotus hoa sen sen việt đàn tranh dan tranh zither việt nam viet nam máy chữ cổ typewriter vintage gaming rgb cầu vồng rainbow vũ trụ space sao star outer space trung thu mid autumn đèn lồng lantern trăng moon valentine tình yêu love tim heart halloween bí ngô pumpkin dơi bat guitar ghi ta ghi-ta đàn ghi-ta acoustic dây đàn strings đập chuột whack a mole xám trung tính neutral grey gray xám ghi gboard", location: .page(.giaoDien)),
            E(viTitle: LK("Độ trong suốt phím"), keywords: "trong suốt transparent", location: .page(.giaoDien)),
            E(viTitle: LK("Độ trong suốt ký tự"), keywords: "trong suốt transparent chữ", location: .page(.giaoDien)),
            E(viTitle: LK("Tuỳ chỉnh nâng cao"), keywords: "màu chữ màu phím màu nhấn accent color colour bo góc tròn vuông corner radius cỡ chữ size phông font độ đậm weight bold đặt lại reset mặc định giao diện theme", location: .page(.giaoDien)),
            E(viTitle: LK("Dán giao diện"), keywords: "json theme giao diện chép copy paste dán sửa edit nhập import tự tạo custom chia sẻ share", location: .page(.giaoDien)),
            E(viTitle: LK("Bạn đồng hành"), keywords: "bạn đồng hành nhân vật thú cưng mèo gà con cô gái chàng trai buddy keyboard buddy pet character mascot cat chick girl boy nhảy dance ngủ sleep plus", location: .page(.giaoDien)),
            E(viTitle: LK("Hiệu ứng khi bấm phím"), keywords: "key press effect animation hoạt ảnh trái tim heart bong bóng bubble gợn sóng ripple cánh hoa petal pháo hoa firework nháy sáng flash matrix tia sét lightning emoji theo chữ emoji words hoa đào mai tết blossom lửa combo fire mực loang ink sóng nước water wave tuyết rơi snow giáng sinh christmas sao băng shooting star meteor vũ trụ space plus đèn lồng lantern glow trung thu mid autumn sương ma khói smoke spooky mist halloween rung dây string vibration guitar ghi ta đàn ghi-ta", location: .page(.giaoDien)),
            E(viTitle: LK("Đập chuột"), keywords: "đập chuột trò chơi game whack a mole chuột mouse theme giao diện vui fun plus", location: .page(.giaoDien)),
            E(viTitle: LK("Màu nhấn"), keywords: "accent color colour nhập enter return shift tuỳ chỉnh nâng cao", location: .page(.giaoDien)),
            E(viTitle: LK("Khôi phục giao diện gốc"), keywords: "reset mặc định", location: .page(.giaoDien)),
            E(viTitle: LK("Chiều cao hàng phím"), keywords: "height cao thấp stock gốc apple cỡ phím size như bàn phím iphone", location: .page(.giaoDien)),
            E(viTitle: LK("Nâng bàn phím"), keywords: "raise nâng cao đẩy lên khoảng trống dưới padding bottom", location: .page(.giaoDien)),
            E(viTitle: LK("Màu chữ gợi ý"), keywords: "suggestion text color colour xám grey gray sáng bright thanh gợi ý chữ mờ dịu apple stock", location: .page(.giaoDien)),
            E(viTitle: LK("Hiện logo Vᴛ"), keywords: "logo phím cách", location: .page(.giaoDien)),
            E(viTitle: LK("Bàn phím tách đôi"), keywords: "split tách chia hai nửa gập ngang", location: .page(.giaoDien)),
            // Riêng tư & sao lưu
            E(viTitle: LK("Lịch sử clipboard"), keywords: "copy dán clipboard giữ lịch sử 24 giờ 7 ngày keep history", location: .page(.riengTu), key: "clipboardHistory"),
            E(viTitle: LK("Chế độ ẩn danh"), keywords: "incognito riêng tư", location: .page(.riengTu), key: "incognitoMode"),
            E(viTitle: LK("Xuất / nhập file sao lưu"), keywords: "backup export import restore sao lưu", location: .page(.riengTu)),
            E(viTitle: LK("Đồng bộ iCloud"), keywords: "sync icloud đồng bộ", location: .page(.riengTu), condition: .iCloud),
            // Nâng cao / Gỡ lỗi
            E(viTitle: LK("Debug mode — ghi log chạm phím"), keywords: "debug log gỡ lỗi nhật ký tester", location: .page(.nangCao), key: "debugTouchLog"),
        ]
        // Nhóm "Gõ lẫn tiếng Anh" (tab Kiểu Gõ) — tên + từ khoá ở Shared/MixedTypingUI.swift.
        e += MixedTypingItem.allCases.map { m in
            E(viTitle: m.viTitle, keywords: m.keywords,
              location: m.placement == .top ? .mixed(m) : .mixedAdvanced(m), key: m.storageKey)
        }
        return e
    }()

    /// Dòng tên các trang Tính Năng (gõ tên trang cũng ra).
    static let pages: [SettingsIndexEntry] = FeaturePage.allCases.map {
        SettingsIndexEntry(viTitle: $0.viTitle, keywords: "", location: .page($0))
    }

    /// So khớp không phân biệt hoa/thường và dấu ("trong suot" vẫn ra) — SettingsSearch (Shared).
    static func search(_ query: String, allows: (SettingsIndexEntry.Condition) -> Bool) -> [SettingsIndexEntry] {
        let words = SettingsSearch.words(query)
        guard !words.isEmpty else { return [] }
        return (pages + all).filter {
            allows($0.condition) && SettingsSearch.matches(viTitle: $0.viTitle, keywords: $0.keywords, words: words)
        }
    }

    /// Mục có key `k` (test: bộ chọn hồ sơ trỏ đúng chỗ mới).
    static func entry(forKey k: String) -> SettingsIndexEntry? { all.first { $0.key == k } }
}
