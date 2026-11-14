// Dịch trên máy (Plus, PlusGate .translate) — phần THUẦN dùng chung app + bàn phím:
// ngôn ngữ đích đã chọn (App Group `translateTarget`, có trong sao lưu) và luật chọn
// chiều dịch. Bản dịch chạy bằng Apple Translation NGAY TRÊN MÁY (Keyboard/Translate.swift)
// — chữ không bao giờ rời máy.
import Foundation

enum TranslatePrefs {
    static let targetKey = "translateTarget"
    /// Mặc định dịch sang tiếng Anh.
    static let defaultTarget = "en"
    static let vietnamese = "vi"

    /// Ngôn ngữ Apple Translation hỗ trợ (LanguageAvailability.supportedLanguages trên SDK
    /// iOS 27.1, đo 13/10/2026), trừ tiếng Việt. Dùng làm tập giá trị hợp lệ khi nhập sao
    /// lưu và danh sách dự phòng; màn cài đặt trong app đọc danh sách THẬT của máy.
    static let knownTargets = [
        "ar-AE", "ar-SA", "da", "de", "de-AT", "de-CH", "en", "en-AU", "en-CA", "en-GB",
        "en-IE", "en-IN", "en-NZ", "en-SG", "en-ZA", "es", "es-CL", "es-MX", "es-US", "fi",
        "fr", "fr-BE", "fr-CA", "fr-CH", "he", "hi", "id", "it", "it-CH", "ja", "ko", "ms",
        "nb", "nl", "nl-BE", "pl", "pt", "pt-PT", "ru", "sv", "th", "tr", "uk", "zh",
        "zh-HK", "zh-TW",
    ]

    /// Mã ngôn ngữ gốc: "zh-TW" / "pt_PT" → "zh" / "pt".
    static func base(_ id: String) -> String {
        String(id.split(whereSeparator: { $0 == "-" || $0 == "_" }).first ?? Substring(id)).lowercased()
    }

    /// Giá trị lưu hợp lệ; thiếu / rỗng / tiếng Việt ⇒ mặc định (đích không thể là tiếng Việt:
    /// tiếng Việt là đầu kia của mọi cặp).
    static func normalized(_ v: String?) -> String {
        guard let v, !v.isEmpty, base(v) != vietnamese else { return defaultTarget }
        return v
    }

    static func target(_ d: UserDefaults?) -> String { normalized(d?.string(forKey: targetKey)) }

    /// "Dịch bằng Apple Intelligence" (thử nghiệm, mặc định TẮT): model trên máy dịch trước,
    /// lỗi / quá hạn / kết quả bất thường ⇒ Apple Translation. Không sao lưu (tuỳ máy) — song
    /// sinh Android Keys.TRANSLATE_AI.
    static let aiKey = "translateAI"
    static func useAI(_ d: UserDefaults?) -> Bool { d?.bool(forKey: aiKey) ?? false }

    static func setTarget(_ v: String, _ d: UserDefaults?) { d?.set(normalized(v), forKey: targetKey) }

    /// Tên ngôn ngữ theo ngôn ngữ giao diện ("Tiếng Nhật" / "Japanese"), viết hoa chữ đầu.
    static func displayName(_ id: String, uiLanguage: String = L10n.lang) -> String {
        let name = Locale(identifier: uiLanguage).localizedString(forIdentifier: id) ?? id
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    /// Danh sách cho bộ chọn: bỏ tiếng Việt + trùng, xếp theo tên hiển thị (so sánh theo
    /// ngôn ngữ giao diện).
    static func pickerTargets(_ ids: [String], uiLanguage: String = L10n.lang) -> [String] {
        let loc = Locale(identifier: uiLanguage)
        var seen = Set<String>()
        let ok = ids.filter { base($0) != vietnamese && seen.insert($0).inserted }
        return ok.map { ($0, displayName($0, uiLanguage: uiLanguage)) }
            .sorted { $0.1.compare($1.1, locale: loc) == .orderedAscending }
            .map(\.0)
    }
}

/// Luật chọn chiều dịch: dịch SANG ngôn ngữ đích đã chọn; chữ vốn ĐÃ là ngôn ngữ đích thì
/// dịch về tiếng Việt (khứ hồi Việt ↔ đích bằng cùng một nút).
enum TranslateDirection {
    struct Pair: Equatable {
        let source: String
        let target: String
    }

    /// `detected`: ngôn ngữ nhận ra của đoạn chữ (nil = không nhận ra ⇒ không dịch).
    static func resolve(detected: String?, target: String) -> Pair? {
        guard let d = detected, !d.isEmpty else { return nil }
        let t = TranslatePrefs.normalized(target)
        if TranslatePrefs.base(d) == TranslatePrefs.base(t) {
            return Pair(source: t, target: TranslatePrefs.vietnamese)
        }
        return Pair(source: d, target: t)
    }
}
