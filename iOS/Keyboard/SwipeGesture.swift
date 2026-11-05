// SwipeGesture.swift — phần THUẦN của gõ vuốt ở tầng touch (test được, không UIKit
// view): phân loại chạm/vuốt, khi nào được bật, dấu cách treo, viết hoa.
// Lõi giải mã: SwipeDecoder.swift; glue với engine: SwipeTyping.swift;
// router touch + vệt vuốt: KeyboardView (MARK gõ vuốt).
import CoreGraphics
import Foundation

/// Phân loại một touch phím chữ: CHẠM hay VUỐT. Chữ đã chèn ngay lúc chạm xuống
/// (không thêm độ trễ); chỉ khi thành vuốt thì chữ đó mới bị huỷ.
///
/// Chuyển sang vuốt khi (cùng lúc): chỉ 1 touch được route, điểm hiện tại đã RA
/// KHỎI phím xuất phát, cách điểm chạm ≥ ngưỡng quãng đường, và tốc độ trung bình
/// từ lúc chạm ≥ `minSpeed`. Nếu phím chữ trước vừa chạm trong `recentWindow` thì CẢ
/// HAI ngưỡng nhân `recentFactor` (×3) ngay sau phím trước, giảm tuyến tính về ×1 ở
/// cuối cửa sổ (kiểu AOSP) — gõ nhanh hay "kéo lê" ngón sang phím kế, không được
/// thành vuốt. Hằng số GIỐNG bản Android (GestureClassifier.kt). Ngón thứ hai chạm, hoặc
/// quá `tapLock` mà chưa đạt ngưỡng ⇒ khoá là chạm (không bao giờ thành vuốt nữa).
struct GestureClassifier {
    enum Decision: Equatable { case undecided, tap, swipe }

    struct Params: Equatable {
        var minDistanceKeys: CGFloat = 1.0
        /// pt/ms, trung bình từ lúc chạm (0.1 pt/ms = 100 pt/s).
        var minSpeed: CGFloat = 0.1
        var tapLock: TimeInterval = 0.5
        var recentWindow: TimeInterval = 0.35
        var recentFactor: CGFloat = 3.0
    }

    let params: Params
    let start: CGPoint
    let startTime: TimeInterval
    let startKey: CGRect
    /// Ngưỡng quãng đường (pt) và tốc độ (pt/ms) đã nhân hệ số "vừa gõ".
    let distanceThreshold: CGFloat
    let speedThreshold: CGFloat
    private(set) var decision: Decision = .undecided

    /// `sinceLastLetter`: giây từ lúc phím chữ TRƯỚC chạm xuống (nil = lâu rồi / không có).
    init(start: CGPoint, time: TimeInterval, startKey: CGRect, keyWidth: CGFloat,
         sinceLastLetter: TimeInterval?, params: Params = Params()) {
        self.params = params
        self.start = start
        self.startTime = time
        self.startKey = startKey
        let f = Self.recentMultiplier(sinceLastLetter: sinceLastLetter, params)
        distanceThreshold = keyWidth * params.minDistanceKeys * f
        speedThreshold = params.minSpeed * f
    }

    /// Hệ số nhân ngưỡng theo thời gian từ phím chữ trước: ×recentFactor lúc 0ms, giảm
    /// tuyến tính về ×1 ở `recentWindow`.
    static func recentMultiplier(sinceLastLetter: TimeInterval?, _ p: Params = Params()) -> CGFloat {
        guard let s = sinceLastLetter, s >= 0, s < p.recentWindow, p.recentWindow > 0 else {
            return 1
        }
        return p.recentFactor - (p.recentFactor - 1) * CGFloat(s / p.recentWindow)
    }

    /// Ngón khác chạm xuống trong lúc chưa quyết ⇒ khoá chạm.
    mutating func secondTouch() {
        if decision == .undecided { decision = .tap }
    }

    @discardableResult
    mutating func move(to p: CGPoint, time: TimeInterval) -> Decision {
        guard decision == .undecided else { return decision }
        let elapsed = time - startTime
        if elapsed > params.tapLock { decision = .tap; return decision }
        guard !startKey.contains(p) else { return decision }
        let d = hypot(p.x - start.x, p.y - start.y)
        guard d >= distanceThreshold else { return decision }
        let ms = max(elapsed * 1000, 1)
        if d / CGFloat(ms) >= speedThreshold { decision = .swipe }
        return decision
    }
}

/// Khi nào gõ vuốt được bật (ngoài công tắc trong app).
enum SwipePolicy {
    /// iPad full-size KHÔNG bật (như QuickPath; iPad có vuốt xuống ký tự phụ). Ô literal
    /// (passthrough: email/URL/username/OTP/mật khẩu), ô bảo mật, layout số/email/URL:
    /// tắt. VoiceOver: tắt (cử chỉ kéo là của VoiceOver).
    static func enabled(setting: Bool, isPad: Bool, traits: FieldTraits?, voiceOver: Bool) -> Bool {
        guard setting, !isPad, !voiceOver, let t = traits else { return false }
        return !t.passthrough && !t.secure && t.inputKind.isFreeText
    }
}

/// Chữ hoa của từ vuốt theo trạng thái shift lúc bắt đầu vuốt.
enum SwipeCase: Equatable {
    case lower, capitalized, upper

    /// Chỉ Shift (không tên riêng) — giữ cho công cụ/test cũ.
    func apply(_ w: String) -> String {
        apply(w, proper: { $0 })
    }

    /// Dạng chèn của từ vuốt (chữ thường từ decoder): trước hết dạng tên riêng `proper`
    /// (hoa/thường đã học ⊕ DisplayCase như thanh gợi ý — "iphone" → "iPhone", "nam" sau "việt"
    /// → "Nam"), rồi Shift: Caps Lock ⇒ HOA HẾT; Shift một-lần / đầu câu ⇒ hoa chữ đầu, NHƯNG từ
    /// đã có chữ hoa giữ nguyên ("iPhone" đầu câu vẫn "iPhone", như SuggestionCase); không bao
    /// giờ hạ chữ hoa của dạng tên riêng. = Android SwipeSuggest.applyCase.
    func apply(_ w: String, proper: (String) -> String) -> String {
        let base = proper(w)
        switch self {
        case .lower: return base
        case .capitalized:
            if base.contains(where: { $0.isUppercase }) { return base }
            return base.prefix(1).uppercased() + base.dropFirst()
        case .upper: return base.uppercased()
        }
    }
}

/// "Dấu cách treo": từ vuốt chèn KHÔNG kèm dấu cách sau; từ kế tiếp (vuốt) tự thêm
/// dấu cách trước nếu ngay trước con trỏ là CHỮ (chữ cái/số) hoặc DẤU CÂU ĐÓNG. Đầu ô,
/// sau khoảng trắng/xuống dòng, ngoặc/nháy mở hay ký hiệu khác (/ @ # -) ⇒ không.
/// Context nil (host không cho biết) ⇒ không thêm (thiếu một dấu cách rẻ hơn chèn
/// thừa). Cùng quy tắc bản Android.
enum SwipeSpacing {
    static let closers: Set<Character> = [
        ".", ",", ";", ":", "!", "?", ")", "]", "}", "\u{2026}",
        "\u{201D}", "\u{2019}", "\u{00BB}",       // nháy thẳng " ' mơ hồ đóng/mở ⇒ không
    ]

    static func needsLeadingSpace(before ctx: String?) -> Bool {
        guard let last = ctx?.last else { return false }
        return last.isLetter || last.isNumber || closers.contains(last)
    }

    /// Dấu cách treo cho phím KÝ HIỆU (số, emoji, ngoặc…) ngay sau từ vuốt — chưa phím nào
    /// xen vào. Số / emoji / ký hiệu tiền tệ / ngoặc-nháy MỞ (mở "từ" mới) cần " " trước:
    /// vuốt "mua" + 2 → "mua 2", không "mua2". Dấu câu đóng, nháy thẳng, ký hiệu nối
    /// (- / @ # _ % …) vẫn dính từ. Chữ cái không qua đây (phím chữ sau từ vuốt có luật
    /// riêng). `before` đọc được ⇒ theo `needsLeadingSpace`; nil ⇒ tin trạng thái (đuôi là
    /// từ vuốt). = Android SwipeSpacing.spaceBefore.
    static let openers: Set<Character> = ["(", "[", "{", "\u{201C}", "\u{2018}", "\u{00AB}"]

    static func spaceBefore(_ text: String, afterSwipe: Bool, before: String?) -> Bool {
        guard afterSwipe, startsWord(text) else { return false }
        guard let before else { return true }
        return needsLeadingSpace(before: before)
    }

    /// Ký tự đầu `text` mở một "từ" mới (cần tách khỏi từ trước bằng dấu cách).
    static func startsWord(_ text: String) -> Bool {
        guard let c = text.first, let s = c.unicodeScalars.first else { return false }
        if c.isASCII { return c.isNumber || openers.contains(c) || c == "$" }
        if openers.contains(c) || s.properties.generalCategory == .currencySymbol { return true }
        // emoji: ký hiệu ngoài BMP (😀 👍) hoặc ký hiệu kèm VS16 (❤️)
        return s.properties.generalCategory == .otherSymbol
            && (s.value >= 0x10000 || c.unicodeScalars.contains("\u{FE0F}"))
    }
}
