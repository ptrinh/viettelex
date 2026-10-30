// Cấu hình VietTelex Plus — ID sản phẩm + danh sách tính năng Plus. Đổi ID ở
// ĐÂY (và trong StoreKit/VietTelex.storekit) cho khớp App Store Connect.
// Dùng chung app + bàn phím (chỉ Foundation, không StoreKit).
import Foundation

enum PlusConfig {
    /// CÔNG TẮC THANH TOÁN. `false` = chưa bán: PlusGate mở MỌI tính năng Plus
    /// cho mọi người. Chỉ bật `true` sau khi đã tạo sản phẩm trên App Store
    /// Connect (xem iOS/store-drafts/PRODUCTS.md). BẬT 27/09/2026 (Phil): 4 sản phẩm
    /// đã tạo trên App Store Connect (Ready to Submit, gửi duyệt cùng bản 1.2).
    static let paywallEnabled = true

    /// Giá gợi ý (chỉ để hiển thị khi StoreKit chưa tải được giá thật).
    static let plusPriceHint = AppFlavor.plusPriceHint

    /// Non-consumable: mở khoá VietTelex Plus vĩnh viễn.
    static let plusProductID = AppFlavor.plusProductID

    /// Consumable: ủng hộ (tip), không mở khoá gì — 25.000đ / 49.000đ / 99.000đ.
    static let tipProductIDs = AppFlavor.tipProductIDs

    static var allProductIDs: [String] { [plusProductID] + tipProductIDs }

    /// App Group chung app ↔ bàn phím.
    static let appGroup = AppFlavor.appGroup

    /// Key trong App Group. App ghi, bàn phím chỉ đọc.
    static let unlockedKey = "plusUnlocked"
    /// Công tắc giả lập đã mua — CHỈ có tác dụng ở bản Debug.
    static let debugOverrideKey = "plusDebugOverride"

    /// Giới hạn bản miễn phí cho tính năng có "mức" (clipboard ghim).
    static let freePinnedClipLimit = 5
}

/// Tính năng thuộc gói Plus. LUÔN MIỄN PHÍ (không bao giờ thêm vào đây): toàn
/// bộ phần gõ (Telex/VNI, bỏ dấu tự do, khôi phục tiếng Anh, sửa dấu từ đã gõ),
/// gợi ý/emoji/bigram, gõ vuốt, gõ tắt cơ bản, mẫu câu, hàng số, một tay, vuốt
/// ⌫, trackpad, theme hệ thống + sáng/tối + tương phản cao, sao lưu/nhập file.
/// Nguyên tắc: không khoá gì làm việc gõ tệ đi.
enum PlusFeature: String, CaseIterable, Identifiable {
    /// Theme cao cấp + ảnh nền tự chọn.
    case premiumThemes
    /// Thêm dấu cho cả câu gõ không dấu.
    case sentenceDiacritics
    /// Clipboard nâng cao: ghim không giới hạn + chip tách STK/SĐT/OTP.
    /// (Miễn phí vẫn có lịch sử ngắn + ghim tối đa `freePinnedClipLimit`.)
    case advancedClipboard
    /// Đồng bộ cài đặt/gõ tắt/từ đã học qua iCloud.
    case iCloudSync
    /// Công cụ văn bản: HOA/thường/Hoa Đầu Từ/Hoa đầu câu, xoá dấu (Keyboard/TextTools.swift).
    case textTools
    /// Dịch trên máy (Apple Translation, iOS 26+): Việt ↔ ngôn ngữ chọn trong app
    /// (Shared/TranslatePrefs.swift, Keyboard/Translate.swift).
    case translate
    /// Sửa lỗi bằng Apple Intelligence (FoundationModels trên máy, iOS 26+): chọn đoạn ⇒ chip
    /// "✨ Sửa lỗi"; chọn một từ ⇒ từ thay thế (Keyboard/AIAssist.swift). Mặc định TẮT.
    case aiProofread
    /// Huy hiệu cảm ơn người ủng hộ.
    case thanksBadge

    var id: String { rawValue }

    var title: String {
        switch self {
        case .premiumThemes: return L("Theme cao cấp & ảnh nền")
        case .sentenceDiacritics: return L("Thêm dấu cả câu")
        case .advancedClipboard: return L("Clipboard nâng cao")
        case .iCloudSync: return L("Đồng bộ iCloud")
        case .textTools: return L("Công cụ văn bản")
        case .translate: return L("Dịch trên máy")
        case .aiProofread: return L("Sửa lỗi bằng Apple Intelligence")
        case .thanksBadge: return L("Huy hiệu cảm ơn")
        }
    }

    var detail: String {
        switch self {
        case .premiumThemes: return L("Thêm bộ màu bàn phím và đặt ảnh riêng làm nền.")
        case .sentenceDiacritics: return L("Gõ không dấu cả câu, một chạm thêm dấu.")
        case .advancedClipboard: return L("Ghim không giới hạn, chip tách số tài khoản, số điện thoại, mã OTP.")
        case .iCloudSync: return L("Cài đặt, gõ tắt và từ đã học theo bạn sang máy khác.")
        case .textTools: return L("Đổi HOA/thường, hoa đầu từ/đầu câu, xoá dấu tiếng Việt.")
        case .translate: return L("Dịch giữa tiếng Việt và ngôn ngữ bạn chọn ngay trên máy — chữ không gửi đi đâu.")
        case .aiProofread: return L("Sửa chính tả, dấu tiếng Việt, ngữ pháp cho đoạn đang chọn; gợi ý từ thay thế — chạy ngay trên máy, chữ không gửi đi đâu.")
        case .thanksBadge: return L("Dấu ★ nhỏ trong app — lời cảm ơn vì đã ủng hộ.")
        }
    }

    /// "Cách dùng" một dòng trên màn Plus — chỉ ĐÚNG chỗ bật / lối vào (góp ý Hữu Đông
    /// 28/09/2026: mua Plus xong không biết "Thêm dấu cả câu" nằm đâu).
    var howTo: String {
        switch self {
        case .premiumThemes: return L("Cách dùng: Tính Năng → Giao diện → chọn theme hoặc ảnh nền.")
        case .sentenceDiacritics: return L("Cách dùng: gõ không dấu cả câu (hom nay troi dep), gõ dấu cách rồi chạm chip “Thêm dấu” ở đầu thanh gợi ý. Cần bật chip bên dưới.")
        case .advancedClipboard: return L("Cách dùng: bật Lịch sử clipboard (Tính Năng → Riêng tư & clipboard), chạm nút clipboard trên thanh gợi ý. Copy STK/SĐT/OTP → chip “Dán …” hiện trên thanh gợi ý.")
        case .iCloudSync: return L("Cách dùng: Tính Năng → Sao lưu & đồng bộ → bật Đồng bộ iCloud.")
        case .textTools: return L("Cách dùng: chạm ☰ trên thanh gợi ý → chip “⚒️ Công cụ” đầu lưới mẫu câu. Áp lên đoạn đang chọn hoặc câu trước con trỏ.")
        case .translate: return L("Cách dùng: chạm ☰ trên thanh gợi ý → “⚒️ Công cụ” → “Dịch ↔ …”. Chọn ngôn ngữ và tải gói dịch ngay bên dưới (cần iOS 26).")
        case .aiProofread: return L("Cách dùng: bật công tắc bên dưới, rồi chọn vài từ trong ô gõ → chip “✨ Sửa lỗi” trên thanh gợi ý. Chọn một từ → gợi ý từ thay thế.")
        case .thanksBadge: return L("Tự hiện sau khi mua.")
        }
    }

    /// Công tắc App Group bật/tắt tính năng — màn Plus đặt công tắc ngay dưới (khi đã mở khoá).
    /// Chip "Thêm dấu" mặc định TẮT; Công cụ văn bản mặc định BẬT (`settingDefault`).
    var settingKey: String? {
        switch self {
        case .sentenceDiacritics: return PlusOnboarding.addTonesKey
        case .textTools: return Self.textToolsKey
        case .aiProofread: return Self.aiProofreadKey
        default: return nil
        }
    }
    /// Key App Group công tắc "Công cụ văn bản" (KeyboardSettings.textToolsEnabled).
    static let textToolsKey = "textToolsEnabled"
    /// Key App Group công tắc "Sửa lỗi bằng Apple Intelligence" (KeyboardSettings.aiProofread).
    static let aiProofreadKey = "aiProofread"

    /// Giá trị khi chưa từng đặt — phải khớp mặc định KeyboardSettings.
    var settingDefault: Bool { self == .textTools }

    /// Nhãn + một dòng mô tả của công tắc trên màn Plus.
    var settingTitle: String {
        switch self {
        case .textTools: return L("Công cụ văn bản")
        case .aiProofread: return L("Sửa lỗi bằng Apple Intelligence")
        default: return L("Bật chip “Thêm dấu”")
        }
    }
    var settingSubtitle: String? {
        switch self {
        case .textTools: return L("Chip ⚒️ Công cụ trong lưới mẫu câu: đổi HOA/thường, bỏ dấu, dịch…")
        case .aiProofread: return L("Tắt mặc định. Chỉ chạy khi bạn chọn chữ.")
        default: return nil
        }
    }

    /// Máy dùng được tính năng này (màn Plus ẩn dòng không dùng được).
    var isAvailableOnDevice: Bool {
        if self == .translate {
            if #available(iOS 26.0, *) { return true }
            return false
        }
        if self == .aiProofread { return AISettingUI.current.isShown }
        return true
    }

    var systemImage: String {
        switch self {
        case .premiumThemes: return "paintpalette"
        case .sentenceDiacritics: return "textformat.abc"
        case .advancedClipboard: return "doc.on.clipboard"
        case .iCloudSync: return "icloud"
        case .textTools: return "wand.and.stars"
        case .translate: return "character.bubble"
        case .aiProofread: return "apple.intelligence"
        case .thanksBadge: return "star"
        }
    }
}

/// Mua / khôi phục Plus xong: mời bật chip "Thêm dấu" (tắt mặc định cho nhẹ máy) — MỘT lần,
/// chỉ hỏi, không tự đổi cài đặt. Hàm thuần + UserDefaults tiêm được để test.
struct PlusOnboarding {
    static let addTonesKey = "addTonesChip"
    static let offeredKey = "plusAddTonesOffered"
    let defaults: UserDefaults?

    /// Chưa hỏi lần nào và chip đang tắt.
    var shouldOfferAddTones: Bool {
        guard let d = defaults else { return false }
        return !d.bool(forKey: Self.addTonesKey) && !d.bool(forKey: Self.offeredKey)
    }
    func markOffered() { defaults?.set(true, forKey: Self.offeredKey) }
    func enableAddTones() { defaults?.set(true, forKey: Self.addTonesKey) }
}

/// Trạng thái model Apple Intelligence — mã khớp `IntelligenceStatus` (VTIntelligence/
/// IntelligenceEngine.swift) và `vt_ai_status` mà bàn phím đọc qua dlopen.
enum AIModelState: Int32, Equatable {
    case available = 0, deviceNotEligible = 1, notEnabled = 2, notReady = 3, unsupportedOS = 4
}

/// Apple Intelligence (FoundationModels) dùng được trên máy không. Shared không link
/// FoundationModels (bàn phím không được nạp nó lúc khởi động): app chủ gắn `probe`
/// (VTIntelligence/IntelligenceEngine.swift) lúc chạy; chưa gắn ⇒ unsupportedOS (ẩn tính năng).
enum AIAvailability {
    nonisolated(unsafe) static var probe: (() -> Int32)?
    static var state: AIModelState {
        guard #available(iOS 26.0, *), let raw = probe?() else { return .unsupportedOS }
        return AIModelState(rawValue: raw) ?? .notReady
    }
    static var isAvailable: Bool { state == .available }
}

/// Công tắc "Sửa lỗi bằng Apple Intelligence" trong app theo trạng thái model — hàm THUẦN:
/// máy không hỗ trợ / OS cũ ⇒ ẩn hẳn; chưa bật Apple Intelligence / mô hình đang tải ⇒ hiện
/// nhưng khoá, kèm một dòng hướng dẫn; dùng được ⇒ bật/tắt bình thường.
enum AISettingUI: Equatable {
    case hidden
    case enabled
    case disabled(hint: String)

    static func of(_ s: AIModelState) -> AISettingUI {
        switch s {
        case .available: return .enabled
        case .notEnabled: return .disabled(hint: L("Bật Apple Intelligence trong Cài đặt → Apple Intelligence & Siri"))
        case .notReady: return .disabled(hint: L("Mô hình đang tải, thử lại sau"))
        case .deviceNotEligible, .unsupportedOS: return .hidden
        }
    }

    static var current: AISettingUI { of(AIAvailability.state) }
    var isShown: Bool { self != .hidden }
    var isEnabled: Bool { self == .enabled }
    var hint: String? { if case .disabled(let h) = self { return h }; return nil }
}
