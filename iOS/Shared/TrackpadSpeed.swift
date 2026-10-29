// "Độ nhạy con trỏ" (giữ phím cách = trackpad) — THUẦN, song sinh
// android/keyboard/.../TrackpadSpeed.kt. Khoá App Group `trackpadSpeed` (String):
// "slow" (Chậm) / "medium" (Vừa, MẶC ĐỊNH) / "fast" (Nhanh). Giá trị lạ / thiếu ⇒ Vừa.
//
// Tester 29/10/2026 (sau 15bed4b2 — tăng tốc theo QUÃNG kéo, ngưỡng 120 pt/s): "Nên có cài
// đặt mức độ nhạy của con trỏ, bạn chỉnh nó nhạy quá có vẻ hơi bị lag".
//  • Nhanh = đường cong 15bed4b2 (ngang 120→900 pt/s ×1→×5, dọc 120→700 ×1→×3).
//  • Chậm  ≈ cảm giác trước 15bed4b2 (gần như không tăng tốc ở cú kéo thường): ngang
//    300→1500 ×3, dọc 250→1000 ×2.
//  • Vừa (mặc định) ≈ nửa đường giữa hai bản: ngang 210→1200 ×4, dọc 180→850 ×2,5.
// Dưới ngưỡng chậm luôn ×1 (6pt/ký tự, 24pt/dòng) ở MỌI mức — chỉnh chính xác không đổi.
// Bàn phím đọc một lần lúc hiện (KeyboardSettings.load) — 0 chi phí mỗi chạm.
import Foundation

enum TrackpadSpeed: String, CaseIterable {
    case slow, medium, fast

    static let key = "trackpadSpeed"
    static let defaultValue: TrackpadSpeed = .medium

    /// Đường cong tăng tốc: tốc độ (pt/s) ≤ slow ⇒ ×1, ≥ fast ⇒ ×max, giữa tuyến tính.
    struct Curve: Equatable {
        let hSlow: Double, hFast: Double, hMax: Double
        let vSlow: Double, vFast: Double, vMax: Double
    }

    var curve: Curve {
        switch self {
        case .slow: return Curve(hSlow: 300, hFast: 1500, hMax: 3, vSlow: 250, vFast: 1000, vMax: 2)
        case .medium: return Curve(hSlow: 210, hFast: 1200, hMax: 4, vSlow: 180, vFast: 850, vMax: 2.5)
        case .fast: return Curve(hSlow: 120, hFast: 900, hMax: 5, vSlow: 120, vFast: 700, vMax: 3)
        }
    }

    /// Giá trị lạ / thiếu ⇒ mặc định (Vừa).
    static func parse(_ raw: Any?) -> TrackpadSpeed {
        (raw as? String).flatMap(TrackpadSpeed.init(rawValue:)) ?? defaultValue
    }
    static func load(_ d: UserDefaults?) -> TrackpadSpeed { parse(d?.object(forKey: key)) }
}
