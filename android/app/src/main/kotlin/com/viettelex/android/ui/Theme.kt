package com.viettelex.android.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.LocalTextStyle
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.sp

/** Bảng màu iOS (systemGroupedBackground, label, separator…) — không dùng Material. */
@Immutable
data class VTColors(
    val dark: Boolean,
    val groupedBg: Color,      // systemGroupedBackground
    val card: Color,           // secondarySystemGroupedBackground
    val label: Color,
    val secondary: Color,      // secondaryLabel
    val tertiary: Color,       // tertiaryLabel
    val separator: Color,
    val fill: Color,           // tertiarySystemFill (stepper, ô nhập)
    val accent: Color,         // accentBlue của app iOS
    val green: Color,          // systemGreen (toggle, tick)
    val red: Color,            // systemRed (destructive)
    val barFill: Color,        // nền thanh tab nổi (≈ ultraThinMaterial)
)

private val Light = VTColors(
    dark = false,
    groupedBg = Color(0xFFF2F2F7), card = Color.White,
    label = Color.Black, secondary = Color(0x993C3C43), tertiary = Color(0x4D3C3C43),
    separator = Color(0x4A3C3C43), fill = Color(0x1F767680),
    accent = Color(0.02f, 0.32f, 0.84f), green = Color(0xFF34C759), red = Color(0xFFFF3B30),
    barFill = Color(0xF0F7F7F8),
)
private val Dark = VTColors(
    dark = true,
    groupedBg = Color.Black, card = Color(0xFF1C1C1E),
    label = Color.White, secondary = Color(0x99EBEBF5), tertiary = Color(0x4DEBEBF5),
    separator = Color(0xA6545458), fill = Color(0x3D767680),
    accent = Color(0.30f, 0.52f, 1.00f), green = Color(0xFF30D158), red = Color(0xFFFF453A),
    barFill = Color(0xF02C2C2E),
)

val LocalVT = staticCompositionLocalOf { Light }

/** Cỡ chữ theo Dynamic Type mặc định của iOS (pt → sp). */
object VTType {
    val largeTitle = TextStyle(fontSize = 34.sp, lineHeight = 41.sp, fontWeight = androidx.compose.ui.text.font.FontWeight.Bold)
    val title2 = TextStyle(fontSize = 22.sp, lineHeight = 28.sp, fontWeight = androidx.compose.ui.text.font.FontWeight.Bold)
    val title3 = TextStyle(fontSize = 20.sp, lineHeight = 25.sp, fontWeight = androidx.compose.ui.text.font.FontWeight.Bold)
    val headline = TextStyle(fontSize = 17.sp, lineHeight = 22.sp, fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold)
    val body = TextStyle(fontSize = 17.sp, lineHeight = 22.sp)
    val subheadline = TextStyle(fontSize = 15.sp, lineHeight = 20.sp)
    val footnote = TextStyle(fontSize = 13.sp, lineHeight = 18.sp)
    val caption2 = TextStyle(fontSize = 11.sp, lineHeight = 13.sp)
}

@Composable
fun VTTheme(content: @Composable () -> Unit) {
    val c = if (isSystemInDarkTheme()) Dark else Light
    CompositionLocalProvider(
        LocalVT provides c,
        LocalContentColor provides c.label,
        LocalTextStyle provides VTType.body.copy(color = c.label),
        content = content,
    )
}
