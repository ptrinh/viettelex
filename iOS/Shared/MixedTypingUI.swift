// Nhóm "Gõ lẫn tiếng Anh" (docs/ONBOARDING-SPEC.md §4, docs/SETTINGS-CLEANUP-SPEC.md §1): nhóm
// thu gọn được trong tab Kiểu Gõ (mặc định thu gọn). Cấp 1 chỉ có bộ chọn hồ sơ, vuốt phím cách
// và Từ điển cá nhân; các công tắc nhận diện tiếng Anh nằm ở trang con "Nâng cao". "Vuốt từ tiếng
// Anh" đã về trang Gõ vuốt (tìm kiếm: SettingsIndex). Phần thuần (không SwiftUI) để test được:
// danh mục mục, key lưu (KHÔNG đổi — sao lưu/khôi phục giữ nguyên), từ khoá tìm kiếm, chỗ đặt, lý
// do làm mờ mục phụ thuộc. Song sinh Android ui/MixedTyping.kt.
import Foundation

enum MixedTypingItem: String, CaseIterable, Hashable {
    /// Dòng tiêu đề nhóm (bấm để mở/thu gọn).
    case section
    // Cấp 1 của nhóm
    case spaceSwipeLanguage, userDictionary
    // Trang con "Nâng cao"
    case autoRestore, contextualEnglish, retroEnglish, englishByFrequency

    /// Mục nằm ở cấp 1 của nhóm hay trong trang con "Nâng cao".
    enum Placement: CaseIterable { case top, advanced }

    var placement: Placement {
        switch self {
        case .section, .spaceSwipeLanguage, .userDictionary: return .top
        case .autoRestore, .contextualEnglish, .retroEnglish, .englishByFrequency: return .advanced
        }
    }

    /// Tên gốc tiếng Việt = khoá L10n = chữ trên dòng cài đặt.
    var viTitle: String {
        switch self {
        case .section: return MixedTypingUI.titleKey
        case .autoRestore: return LK("Tự khôi phục từ tiếng Anh")
        case .contextualEnglish: return LK("Quyết định theo ngữ cảnh")
        case .retroEnglish: return LK("Tự sửa từ phía trước")
        case .englishByFrequency: return LK("Đoán từ trùng theo tần suất")
        case .spaceSwipeLanguage: return LK("Vuốt phím cách đổi Tiếng Việt / Tiếng Anh")
        case .userDictionary: return LK("Từ điển cá nhân")
        }
    }

    /// Từ khoá tìm kiếm thêm (Việt + Anh) ngoài tên.
    var keywords: String {
        switch self {
        case .section: return "mixed trộn song ngữ bilingual tiếng anh english việt anh"
        case .autoRestore: return "english google restore khôi phục nâng cao advanced"
        case .contextualEnglish: return "context ngữ cảnh english he is nâng cao advanced"
        case .retroEnglish: return "sửa ngược retro english thử nghiệm experimental nâng cao advanced"
        case .englishByFrequency: return "tần suất frequency his hí từ trùng collision thử nghiệm experimental nâng cao advanced"
        case .spaceSwipeLanguage: return "space ngôn ngữ english language vuốt phím cách tiếng việt tiếng anh"
        case .userDictionary: return "dictionary tên riêng thuật ngữ từ tiếng anh"
        }
    }

    /// Key App Group (KHÔNG đổi khi chuyển chỗ) — nil với dòng không phải công tắc.
    var storageKey: String? {
        switch self {
        case .section, .userDictionary: return nil
        case .autoRestore: return "autoRestore"
        case .contextualEnglish: return "contextualEnglish"
        case .retroEnglish: return RetroEnglishUI.autoKey
        case .englishByFrequency: return RetroEnglishUI.frequencyKey
        case .spaceSwipeLanguage: return "spaceSwipeLanguage"
        }
    }
}

enum MixedTypingUI {
    /// Tên nhóm — cùng tên/thứ tự trên iOS và Android.
    static let titleKey = LK("Gõ lẫn tiếng Anh")
    /// Dòng "Nâng cao" của nhóm + dòng phụ liệt kê những gì bên trong (SETTINGS-CLEANUP-SPEC §1).
    static let advancedTitleKey = LK("Nâng cao")
    static let advancedSubtitleKey = LK("Khôi phục từ tiếng Anh, ngữ cảnh, khi trùng từ, sửa từ phía trước…")

    /// Thứ tự dòng ở trang con "Nâng cao".
    static let advancedItems: [MixedTypingItem] = MixedTypingItem.allCases.filter { $0.placement == .advanced }

    /// Mục phụ thuộc "Quyết định theo ngữ cảnh": KHÔNG ẩn — làm mờ + lý do (SETTINGS-CLEANUP-SPEC
    /// §0.4). VNI ⇒ "Chỉ áp dụng cho Telex" (engine chỉ sửa ngược ở Telex); ngữ cảnh tắt ⇒ "Cần
    /// bật Quyết định theo ngữ cảnh". nil = dùng được. Cùng điều kiện với RetroEnglishUI.switchVisible.
    static func disabledReason(_ item: MixedTypingItem, contextualEnglish: Bool, vniMode: Bool) -> String? {
        switch item {
        case .retroEnglish, .englishByFrequency:
            if vniMode { return TelexOnly.reasonKey }
            if !contextualEnglish { return LK("Cần bật Quyết định theo ngữ cảnh") }
            return nil
        default: return nil
        }
    }
}

/// Tuỳ chọn chỉ có tác dụng ở Telex: khi chọn VNI thì làm mờ kèm lý do này (không ẩn).
enum TelexOnly {
    static let reasonKey = LK("Chỉ áp dụng cho Telex")
}

/// So khớp ô tìm cài đặt: không phân biệt hoa/thường và dấu ("tan suat" khớp "tần suất"), mọi
/// từ của câu tìm phải có trong tên Việt + tên Anh + từ khoá.
enum SettingsSearch {
    static func fold(_ s: String) -> String {
        s.replacingOccurrences(of: "đ", with: "d").replacingOccurrences(of: "Đ", with: "D")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    static func words(_ query: String) -> [String] {
        fold(query).split(separator: " ").map(String.init)
    }

    static func matches(viTitle: String, keywords: String, words: [String]) -> Bool {
        let hay = fold(viTitle + " " + (L10n.en[viTitle] ?? "") + " " + keywords)
        return !words.isEmpty && words.allSatisfy { hay.contains($0) }
    }
}
