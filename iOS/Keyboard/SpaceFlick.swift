// SpaceFlick — vuốt nhanh phím cách sang trái/phải để đổi Tiếng Việt ↔ Tiếng Anh (kiểu
// Gboard/HeliBoard "Swipe to switch languages"). Phần THUẦN, bản Kotlin song sinh:
// android/keyboard/src/main/kotlin/com/viettelex/keyboard/SpaceFlick.kt — sửa ở đây thì
// sửa y hệt bên kia (SpaceFlickTests hai bên cùng số liệu).
//
// Không đụng trackpad: flick phải NHẤC TAY trước ngưỡng giữ trackpad (0,3 s — iOS
// UILongPressGestureRecognizer trên space, Android SPACE_HOLD_MS). Giữ rồi mới kéo vẫn là
// trackpad; chạm thường vẫn ra dấu cách.
import CoreGraphics
import Foundation

enum KeyboardLanguage: String, Equatable {
    case vi, en

    var toggled: KeyboardLanguage { self == .vi ? .en : .vi }
    /// Nhãn thoáng trên phím cách lúc đổi.
    var displayName: String { self == .vi ? "Tiếng Việt" : "English" }

    /// Mã nhỏ góc dưới-phải phím cách khi bật vuốt đổi ngôn ngữ (như stock iOS nhiều ngôn ngữ).
    var shortCode: String { self == .vi ? "VI" : "EN" }

    /// Lưu ở UserDefaults riêng của bàn phím (ghi được cả khi không có Toàn quyền).
    static let storageKey = "keyboardLanguage"

    /// Công tắc tắt ⇒ luôn Tiếng Việt (không với tới EN); giá trị lạ ⇒ Tiếng Việt. App không gõ tiếng
    /// Việt (`AppFlavor.vietnameseInput`) ⇒ luôn Tiếng Anh.
    static func effective(stored: String?, flickEnabled: Bool) -> KeyboardLanguage {
        guard AppFlavor.vietnameseInput else { return .en }
        guard flickEnabled, let s = stored, let l = KeyboardLanguage(rawValue: s) else { return .vi }
        return l
    }
}

enum SpaceFlick {
    enum Direction: Int, Equatable { case left = -1, right = 1 }

    struct Params: Equatable {
        /// Quãng ngang tối thiểu, tính theo bề rộng phím — như ngưỡng vuốt của GestureClassifier.
        var minDistanceKeys: CGFloat = GestureClassifier.Params().minDistanceKeys
        /// Sàn tuyệt đối (pt) khi phím quá hẹp.
        var minDistance: CGFloat = 24
        /// pt/ms trung bình từ lúc chạm — như GestureClassifier.
        var minSpeed: CGFloat = GestureClassifier.Params().minSpeed
        /// Phải nhấc TRƯỚC ngưỡng giữ trackpad.
        var maxDuration: TimeInterval = 0.3
        /// |dy| ≤ maxSlope·|dx| (chủ yếu ngang).
        var maxSlope: CGFloat = 0.5
        /// Kéo quá ngưỡng này mới bắt đầu vẽ nhãn trượt theo ngón.
        var previewSlop: CGFloat = 8
    }

    /// Nhấc tay: có phải flick đổi ngôn ngữ không (nil = chạm/kéo thường).
    static func classify(dx: CGFloat, dy: CGFloat, duration: TimeInterval, keyWidth: CGFloat,
                         _ p: Params = Params()) -> Direction? {
        let ax = abs(dx)
        guard duration >= 0, duration < p.maxDuration,
              ax >= max(p.minDistance, keyWidth * p.minDistanceKeys),
              abs(dy) <= ax * p.maxSlope else { return nil }
        let ms = max(duration * 1000, 1)
        guard ax / CGFloat(ms) >= p.minSpeed else { return nil }
        return dx < 0 ? .left : .right
    }

    /// Đang kéo (chưa nhấc): tiến độ trượt nhãn -1…1 (±1 ở quãng `span`), 0 = chưa đủ slop /
    /// quá giờ (sắp thành trackpad) / kéo dọc.
    static func progress(dx: CGFloat, dy: CGFloat, elapsed: TimeInterval, span: CGFloat,
                         _ p: Params = Params()) -> CGFloat {
        let ax = abs(dx)
        guard span > 0, elapsed < p.maxDuration, ax >= p.previewSlop,
              abs(dy) <= ax * p.maxSlope * 2 else { return 0 }
        return max(-1, min(1, dx / span))
    }

    /// Quãng kéo mà nhãn trượt trọn (= 2 × ngưỡng flick): tới ngưỡng thì nhãn mới đã hiện nửa.
    static func previewSpan(keyWidth: CGFloat, _ p: Params = Params()) -> CGFloat {
        2 * max(p.minDistance, keyWidth * p.minDistanceKeys)
    }
}

/// Dấu hiệu trên phím cách: bật vuốt đổi ngôn ngữ ⇒ mã "VI"/"EN" nhỏ góc dưới-phải (như stock
/// iOS khi bật nhiều ngôn ngữ); tắt ⇒ logo Vᴛ (công tắc showSpaceLogo) như cũ.
enum SpaceMark: Equatable {
    case none
    case logo(KeyboardLanguage)
    case code(String)

    static func choose(flickEnabled: Bool, showLogo: Bool, language: KeyboardLanguage) -> SpaceMark {
        if flickEnabled { return .code(language.shortCode) }
        return showLogo ? .logo(language) : .none
    }
}
