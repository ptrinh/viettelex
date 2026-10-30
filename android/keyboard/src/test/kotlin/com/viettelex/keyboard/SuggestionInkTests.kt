package com.viettelex.keyboard

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** "Màu chữ gợi ý" ([SuggestionInk]) — song sinh iOS SuggestionInkTests.swift: theme × cài đặt × sáng/tối. */
class SuggestionInkTests {
    private val c = ThemeColor
    private fun contrast(ink: Int, bg: Int) = c.contrast(c.over(ink, bg), bg)

    /** Hệ thống Android = màu resource Material (không có palette) — mô phỏng ink/bg của values(-night)/ime_colors.xml. */
    private fun systemPalette(dark: Boolean) = ThemePalette(
        bg = c.rgb(if (dark) 0x1F1F1F else 0xEEF0F4), keyFill = c.WHITE, specialFill = c.WHITE,
        ink = c.rgb(if (dark) 0xE3E3E3 else 0x1F1F1F), trail = c.WHITE, balloon = c.WHITE, popup = c.WHITE,
        action = c.WHITE, actionInk = c.BLACK, chip = c.WHITE, isDark = dark)

    private fun palettes(): List<Pair<String, ThemePalette>> =
        listOf(false, true).flatMap { d ->
            listOf("system dark=$d" to systemPalette(d)) +
                KeyboardTheme.entries.mapNotNull { t -> t.palette(d)?.let { "${t.id} dark=$d" to it } }
        }

    @Test fun parseAndDefault() {
        assertEquals(SuggestionInk.MUTED, SuggestionInk.DEFAULT)
        assertEquals(SuggestionInk.MUTED, SuggestionInk.of(null))
        assertEquals(SuggestionInk.MUTED, SuggestionInk.of("neon"))
        assertEquals(SuggestionInk.BRIGHT, SuggestionInk.of("bright"))
        assertEquals(setOf("muted", "bright"), SuggestionInk.IDS)   // cùng chuỗi iOS
        assertEquals(SuggestionInk.MUTED, KeyboardSettings.load { null }.suggestionInk)
        assertEquals(SuggestionInk.BRIGHT,
            KeyboardSettings.load { if (it == Keys.SUGGESTION_INK) "bright" else null }.suggestionInk)
    }

    @Test fun brightKeepsBarInk() {
        for ((name, p) in palettes()) {
            val bar = p.barInk ?: p.keyInk
            assertEquals(name, bar, SuggestionInk.color(bar, SuggestionInk.behindBar(p, p.isDark), SuggestionInk.BRIGHT))
        }
    }

    /** Xám: dịu hơn Sáng nhưng ≥ 3:1, giữ sắc chữ theme (đen/trắng thuần ⇒ sắc secondaryLabel). */
    @Test fun mutedAcrossThemes() {
        for ((name, p) in palettes()) {
            val bar = p.barInk ?: p.keyInk
            val behind = SuggestionInk.behindBar(p, p.isDark)
            val m = SuggestionInk.color(bar, behind, SuggestionInk.MUTED)
            assertTrue(name, contrast(m, behind) >= SuggestionInk.MIN_CONTRAST)
            assertTrue(name, contrast(m, behind) <= contrast(bar, behind) + 1e-9)
            if (m != bar) {
                val tint = SuggestionInk.stockTint(bar) ?: (bar or (0xFF shl 24))
                assertEquals(name, tint and 0xFFFFFF, m and 0xFFFFFF)
                assertTrue(name, c.alpha(m) < c.alpha(bar))
            }
        }
    }

    /** Hệ thống tối (chữ #E3E3E3 gần trắng — góp ý "trắng quá"): Xám = 60%. */
    @Test fun systemDarkMutedIsSixtyPercent() {
        val p = systemPalette(true)
        val m = SuggestionInk.color(p.ink, SuggestionInk.behindBar(p, true), SuggestionInk.MUTED)
        assertEquals(p.ink and 0xFFFFFF, m and 0xFFFFFF)
        assertEquals((255 * 0.6f).toInt(), c.alpha(m))
    }

    @Test fun pureWhiteUsesStockTint() {
        val m = SuggestionInk.color(c.WHITE, c.rgb(0x202020), SuggestionInk.MUTED)
        assertEquals(SuggestionInk.STOCK_DARK and 0xFFFFFF, m and 0xFFFFFF)
    }

    @Test fun lowContrastFallsBackToBright() {
        val ink = c.rgb(0xB0B0B0)
        assertEquals(ink, SuggestionInk.color(ink, c.rgb(0xC8C8C8), SuggestionInk.MUTED))
    }

    @Test fun behindBarUsesWallpaperOverlay() {
        val p = systemPalette(true).copy(wallpaper = true)
        assertEquals(c.BLACK, SuggestionInk.behindBar(p, true))
    }
}
