// Nhóm "Gõ mixed Việt/Anh" (docs/ONBOARDING-SPEC.md §4): gom mọi công tắc gõ trộn Việt–Anh
// vào MỘT nhóm thu gọn được trong tab Kiểu Gõ (mặc định thu gọn). Phần thuần (không SwiftUI)
// để test được: danh mục mục, key lưu (KHÔNG đổi — sao lưu/khôi phục giữ nguyên), từ khoá tìm
// kiếm, mục đích để cuộn tới khi mục con đang ẩn. Song sinh Android ui/MixedTyping.kt.
import Foundation

enum MixedTypingItem: String, CaseIterable, Hashable {
    /// Dòng tiêu đề nhóm (bấm để mở/thu gọn).
    case section
    // 1. Nhận diện tiếng Anh
    case autoRestore, contextualEnglish, retroEnglish, englishByFrequency
    // 2. Chuyển ngôn ngữ
    case spaceSwipeLanguage
    // 3. Gợi ý & gõ vuốt tiếng Anh
    case swipeEnglish, userDictionary

    enum Group: CaseIterable { case recognition, language, suggest }

    var group: Group? {
        switch self {
        case .section: return nil
        case .autoRestore, .contextualEnglish, .retroEnglish, .englishByFrequency: return .recognition
        case .spaceSwipeLanguage: return .language
        case .swipeEnglish, .userDictionary: return .suggest
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
        case .swipeEnglish: return LK("Vuốt từ tiếng Anh")
        case .userDictionary: return LK("Từ điển cá nhân")
        }
    }

    /// Từ khoá tìm kiếm thêm (Việt + Anh) ngoài tên.
    var keywords: String {
        switch self {
        case .section: return "mixed trộn song ngữ bilingual tiếng anh english việt anh"
        case .autoRestore: return "english google restore khôi phục"
        case .contextualEnglish: return "context ngữ cảnh english he is"
        case .retroEnglish: return "sửa ngược retro english thử nghiệm experimental"
        case .englishByFrequency: return "tần suất frequency his hí từ trùng collision thử nghiệm experimental"
        case .spaceSwipeLanguage: return "space ngôn ngữ english language vuốt phím cách"
        case .swipeEnglish: return "swipe english"
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
        case .swipeEnglish: return "swipeEnglish"
        }
    }
}

enum MixedTypingUI {
    /// Tên nhóm — cùng tên/thứ tự trên iOS và Android.
    static let titleKey = LK("Gõ mixed Việt/Anh")

    static func groupTitle(_ g: MixedTypingItem.Group) -> String {
        switch g {
        case .recognition: return LK("Nhận diện tiếng Anh")
        case .language: return LK("Chuyển ngôn ngữ")
        case .suggest: return LK("Gợi ý & gõ vuốt tiếng Anh")
        }
    }

    /// Mục có đang hiện không: "Tự sửa từ phía trước" + "Đoán từ trùng theo tần suất" chỉ hiện
    /// khi "Quyết định theo ngữ cảnh" bật và không ở VNI (RetroEnglishUI.switchVisible).
    static func isVisible(_ item: MixedTypingItem, contextualEnglish: Bool, vniMode: Bool) -> Bool {
        switch item {
        case .retroEnglish, .englishByFrequency:
            return RetroEnglishUI.switchVisible(contextualEnglish: contextualEnglish, vniMode: vniMode)
        default: return true
        }
    }

    /// Ô tìm kiếm chọn một mục: dòng để cuộn tới + tô sáng. Mục con đang ẩn ⇒ cuộn tới công tắc
    /// cha "Quyết định theo ngữ cảnh" (bật nó lên thì mục con hiện ngay bên dưới).
    static func scrollTarget(_ item: MixedTypingItem, contextualEnglish: Bool, vniMode: Bool) -> MixedTypingItem {
        isVisible(item, contextualEnglish: contextualEnglish, vniMode: vniMode) ? item : .contextualEnglish
    }
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
