import UIKit

/// Bàn phím tối hay sáng. Host đa số truyền `.default` → theo trait của CONTROLLER
/// (host/hệ thống). Không dùng trait của KeyboardView: lúc viewWillAppear view chưa
/// vào window nên trait `.unspecified` ⇒ phím sáng trên nền tối (bug 26/09/2026).
enum AppearancePolicy {
    static func isDark(appearance: UIKeyboardAppearance, style: UIUserInterfaceStyle) -> Bool {
        switch appearance {
        case .dark: return true
        case .light: return false
        default: return style == .dark
        }
    }
}
