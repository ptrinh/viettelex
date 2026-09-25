package com.viettelex.android.ui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.animation.expandVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.onPlaced
import androidx.compose.ui.layout.positionInParent
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

enum class AppTab(val title: String, val glyph: Glyph) {
    KieuGo("Kiểu Gõ", Glyph.Keyboard),
    TinhNang("Tính Năng", Glyph.Sliders),
    MauCau("Mẫu Câu", Glyph.Quote),
    GioiThieu("Giới Thiệu", Glyph.Info),
}

/**
 * Thanh tab nổi dạng viên thuốc (FloatingTabBar của iOS): icon trên chữ, thu về
 * icon-only khi cuộn xuống, pill chọn trượt bằng spring.
 */
@Composable
fun FloatingTabBar(selected: AppTab, tabs: List<AppTab>, collapsed: Boolean, onSelect: (AppTab) -> Unit) {
    val c = LocalVT.current
    val density = LocalDensity.current
    // Vị trí/bề ngang từng nút (px) để pill trượt giữa chúng.
    val bounds = remember { mutableStateMapOf<AppTab, Triple<Int, Int, Int>>() }
    val sel = bounds[selected]
    val spec = spring<androidx.compose.ui.unit.Dp>(dampingRatio = 0.75f, stiffness = Spring.StiffnessMediumLow)
    val pillX by animateDpAsState(with(density) { (sel?.first ?: 0).toDp() }, spec, label = "px")
    val pillW by animateDpAsState(with(density) { (sel?.second ?: 0).toDp() }, spec, label = "pw")
    val pillH by animateDpAsState(with(density) { (sel?.third ?: 0).toDp() }, spec, label = "ph")

    val shape = CircleShape
    Box(
        Modifier
            .shadow(10.dp, shape, ambientColor = Color.Black.copy(0.5f), spotColor = Color.Black.copy(0.5f))
            .background(c.barFill, shape)
            .border(1.dp, Brush.verticalGradient(listOf(Color.White.copy(0.55f), Color.White.copy(0.06f))), shape)
            .padding(5.dp),
    ) {
        if (sel != null) {
            Box(Modifier.offset(x = pillX).size(pillW, pillH).background(c.accent, shape))
        }
        Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
            tabs.forEach { t ->
                val on = t == selected
                val fg = if (on) Color.White else c.label
                Column(
                    Modifier
                        .onPlaced { bounds[t] = Triple(it.positionInParent().x.toInt(), it.size.width, it.size.height) }
                        .clickable(remember { MutableInteractionSource() }, null) { onSelect(t) }
                        .padding(horizontal = if (collapsed) 11.dp else 12.dp, vertical = if (collapsed) 9.dp else 6.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(2.dp),
                ) {
                    GlyphIcon(t.glyph, fg, 20.dp)
                    AnimatedVisibility(!collapsed, enter = fadeIn() + expandVertically(), exit = fadeOut() + shrinkVertically()) {
                        Text(t.title, fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = fg, maxLines = 1, softWrap = false)
                    }
                }
            }
        }
    }
}
