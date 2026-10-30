package com.viettelex.keyboard

/**
 * "Màu chữ gợi ý" (tester 30/10/2026: chữ thanh gợi ý sáng quá, phân tâm lúc gõ) — THUẦN, song sinh
 * iOS/Shared/SuggestionInk.swift. Khoá [Keys.SUGGESTION_INK] (String, cùng iOS): "muted" (Xám — MẶC ĐỊNH)
 * / "bright" (Sáng — như trước 30/10/2026); giá trị lạ / thiếu ⇒ Xám. Cài đặt: Giao diện → Bàn phím
 * (cạnh "Chiều cao thanh gợi ý").
 *
 * Chỉ CHỮ ô gợi ý đổi; icon, chip, thẻ Dán giữ `barInk`. Xám = sắc chữ thanh ở 60% (alpha chữ phụ
 * secondaryLabel / Material "medium emphasis"); chữ đen/trắng thuần ⇒ sắc secondaryLabel iOS
 * (#3C3C43 / #EBEBF5) như iOS. Không bao giờ nhạt quá: alpha tăng dần tới khi chữ ≥ 3:1 trên nền
 * thanh; vẫn không đạt ⇒ dùng màu Sáng. Đọc lúc hiện bàn phím (StripView.configure) — 0 chi phí mỗi phím.
 */
enum class SuggestionInk(val id: String) {
    MUTED("muted"), BRIGHT("bright");

    companion object {
        val DEFAULT = MUTED
        val IDS: Set<String> = entries.map { it.id }.toSet()
        /** Giá trị lạ / thiếu ⇒ [DEFAULT]. */
        fun of(raw: Any?): SuggestionInk = entries.firstOrNull { it.id == raw } ?: DEFAULT

        const val MUTED_ALPHA = 0.6f
        const val MIN_CONTRAST = 3.0
        val STOCK_LIGHT = ThemeColor.rgb(0x3C3C43)
        val STOCK_DARK = ThemeColor.rgb(0xEBEBF5)

        /** Màu chữ ô gợi ý từ `barInk` (đã giải theo theme/ảnh nền/độ trong suốt) trên nền đục [behind]. */
        fun color(barInk: Int, behind: Int, mode: SuggestionInk): Int {
            if (mode != MUTED) return barInk
            val c = ThemeColor
            val tint = stockTint(barInk) ?: (barInk or (0xFF shl 24))
            val baseA = c.alpha(barInk) / 255f
            var a = MUTED_ALPHA
            while (a < 1f && c.contrast(c.over(c.withAlpha(tint, a * baseA), behind), behind) < MIN_CONTRAST) a += 0.05f
            val muted = c.withAlpha(tint, a.coerceAtMost(1f) * baseA)
            return if (c.contrast(c.over(muted, behind), behind) >= MIN_CONTRAST) muted else barInk
        }

        /** Chữ đen / trắng thuần ⇒ sắc secondaryLabel (như iOS); chữ khác giữ sắc theme. */
        fun stockTint(ink: Int): Int? {
            val rgb = ink and 0xFFFFFF
            return when (rgb) { 0x000000 -> STOCK_LIGHT; 0xFFFFFF -> STOCK_DARK; else -> null }
        }

        /** Nền đục sau thanh gợi ý: nền theme (ảnh nền ⇒ tông lớp phủ) trên nền sau IME. */
        fun behindBar(p: ThemePalette, systemDark: Boolean): Int {
            val sys = KeyboardTransparency.systemBackdrop(systemDark)
            return if (p.wallpaper) p.wallpaperOverlay else ThemeColor.over(p.bg, sys)
        }
    }
}
