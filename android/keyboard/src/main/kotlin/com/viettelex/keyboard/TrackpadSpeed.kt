package com.viettelex.keyboard

/**
 * "Độ nhạy con trỏ" (giữ phím cách = trackpad) — THUẦN, song sinh iOS/Shared/TrackpadSpeed.swift.
 * Khoá [Keys.TRACKPAD_SPEED] (String, cùng iOS): "slow" (Chậm) / "medium" (Vừa, MẶC ĐỊNH) /
 * "fast" (Nhanh); giá trị lạ / thiếu ⇒ Vừa.
 *
 * Tester 29/10/2026 (sau tăng tốc theo QUÃNG kéo, ngưỡng 120): "Nên có cài đặt mức độ nhạy của
 * con trỏ, bạn chỉnh nó nhạy quá có vẻ hơi bị lag".
 * - Nhanh = đường cong cũ (ngang 120→900 dp/s ×1→×5, dọc 120→700 ×1→×3).
 * - Chậm ≈ cảm giác trước đó (gần như không tăng tốc ở cú kéo thường): ngang 300→1500 ×3, dọc
 *   250→1000 ×2.
 * - Vừa (mặc định) ≈ nửa đường: ngang 210→1200 ×4, dọc 180→850 ×2,5.
 * Dưới ngưỡng chậm luôn ×1 (6dp/ký tự, 24dp/dòng) ở MỌI mức. IME đọc lúc dựng bàn phím
 * ([KeyboardSettings.load]) — 0 chi phí mỗi chạm.
 */
enum class TrackpadSpeed(val id: String, val curve: Curve) {
    SLOW("slow", Curve(300.0, 1500.0, 3.0, 250.0, 1000.0, 2.0)),
    MEDIUM("medium", Curve(210.0, 1200.0, 4.0, 180.0, 850.0, 2.5)),
    FAST("fast", Curve(120.0, 900.0, 5.0, 120.0, 700.0, 3.0));

    /** Tốc độ (dp/s) ≤ slow ⇒ ×1, ≥ fast ⇒ ×max, giữa tuyến tính — ngang (h) / dọc (v). */
    data class Curve(val hSlow: Double, val hFast: Double, val hMax: Double,
                     val vSlow: Double, val vFast: Double, val vMax: Double)

    companion object {
        val DEFAULT = MEDIUM
        val IDS: Set<String> = entries.map { it.id }.toSet()
        /** Giá trị lạ / thiếu ⇒ [DEFAULT]. */
        fun of(raw: Any?): TrackpadSpeed = entries.firstOrNull { it.id == raw } ?: DEFAULT
    }
}
