package com.viettelex.android.ui

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

// ---------------------------------------------------------------- grouped list

/** Một section kiểu `List(.insetGrouped)`: header HOA nhỏ, card bo góc, footer xám. */
@Composable
fun VTSection(
    header: String? = null,
    footer: String? = null,
    plain: Boolean = false,        // true = không vẽ card (listRowBackground(.clear))
    content: @Composable ColumnScope.() -> Unit,
) {
    val c = LocalVT.current
    Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp)) {
        if (header != null) {
            Text(header.uppercase(), style = VTType.footnote, color = c.secondary,
                modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 6.dp, bottom = 7.dp))
        }
        Column(
            if (plain) Modifier else Modifier.clip(RoundedCornerShape(12.dp)).background(c.card),
            content = content,
        )
        if (footer != null) {
            Text(footer, style = VTType.footnote, color = c.secondary,
                modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 7.dp))
        }
        Spacer(Modifier.height(if (footer != null) 24.dp else 20.dp))
    }
}

/** Đường kẻ giữa 2 dòng (thụt trái như iOS). */
@Composable
fun RowDivider(inset: Dp = 16.dp) {
    val c = LocalVT.current
    Box(Modifier.padding(start = inset).fillMaxWidth().height(0.5.dp).background(c.separator))
}

/** Khung dòng chuẩn: min 44dp, padding 16/11. */
@Composable
fun VTRow(
    onClick: (() -> Unit)? = null,
    modifier: Modifier = Modifier,
    content: @Composable RowScope.() -> Unit,
) {
    val c = LocalVT.current
    val src = remember { MutableInteractionSource() }
    val pressed by src.collectIsPressedAsState()
    Row(
        modifier
            .fillMaxWidth()
            .then(if (pressed) Modifier.background(c.fill) else Modifier)
            .then(if (onClick != null) Modifier.clickable(src, null, onClick = onClick) else Modifier)
            .heightIn(min = 44.dp)
            .padding(horizontal = 16.dp, vertical = 11.dp),
        verticalAlignment = Alignment.CenterVertically,
        content = content,
    )
}

/** Toggle kèm chú giải nhỏ dưới tiêu đề (settingToggle của iOS). */
@Composable
fun SettingToggle(title: String, caption: String?, checked: Boolean, onChange: (Boolean) -> Unit) {
    val c = LocalVT.current
    VTRow(onClick = { onChange(!checked) }) {
        Column(Modifier.weight(1f).padding(end = 12.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, style = VTType.body, color = c.label)
            if (caption != null) Text(caption, style = VTType.footnote, color = c.secondary)
        }
        IosSwitch(checked, onChange)
    }
}

/** UISwitch 51×31, màu xanh lá hệ thống. */
@Composable
fun IosSwitch(checked: Boolean, onChange: (Boolean) -> Unit) {
    val c = LocalVT.current
    val track by animateColorAsState(if (checked) c.green else if (c.dark) Color(0xFF39393D) else Color(0xFFE9E9EA), label = "t")
    val x by animateDpAsState(if (checked) 22.dp else 2.dp, spring(dampingRatio = 0.7f, stiffness = 600f), label = "x")
    Box(
        Modifier.size(51.dp, 31.dp).clip(CircleShape).background(track)
            .clickable(remember { MutableInteractionSource() }, null, role = Role.Switch) { onChange(!checked) },
    ) {
        Box(
            Modifier.offset(x = x, y = 2.dp).size(27.dp)
                .shadow(2.dp, CircleShape, ambientColor = Color.Black.copy(0.3f), spotColor = Color.Black.copy(0.3f))
                .background(Color.White, CircleShape),
        )
    }
}

/** UIStepper: viên thuốc "− | +". */
@Composable
fun IosStepper(value: Int, range: IntRange, onChange: (Int) -> Unit) {
    val c = LocalVT.current
    Row(
        Modifier.size(94.dp, 32.dp).clip(RoundedCornerShape(8.dp)).background(c.fill),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        StepperHalf("−", value > range.first) { onChange(value - 1) }
        Box(Modifier.width(1.dp).height(18.dp).background(c.separator))
        StepperHalf("+", value < range.last) { onChange(value + 1) }
    }
}

@Composable
private fun RowScope.StepperHalf(sym: String, enabled: Boolean, onClick: () -> Unit) {
    val c = LocalVT.current
    Box(
        Modifier.weight(1f).height(32.dp).clickable(enabled = enabled, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Text(sym, fontSize = 22.sp, fontWeight = FontWeight.Light, color = if (enabled) c.label else c.tertiary)
    }
}

/** Nút chính: capsule tô accentBlue (glassProminent / borderedProminent). */
@Composable
fun ProminentButton(text: String, onClick: () -> Unit) {
    val c = LocalVT.current
    val src = remember { MutableInteractionSource() }
    val pressed by src.collectIsPressedAsState()
    Box(
        Modifier.fillMaxWidth().height(50.dp).clip(CircleShape)
            .background(if (pressed) c.accent.copy(alpha = 0.75f) else c.accent)
            .clickable(src, null, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) { Text(text, style = VTType.headline, color = Color.White) }
}

/** Card nền "glass" (surface + viền nhẹ) như glassCard() của iOS. */
fun Modifier.glassCard(c: VTColors, radius: Dp = 18.dp): Modifier =
    clip(RoundedCornerShape(radius))
        .background(c.card)
        .border(0.5.dp, if (c.dark) Color.White.copy(0.10f) else Color.Black.copy(0.06f), RoundedCornerShape(radius))

// ---------------------------------------------------------------- glyphs
// Icon vẽ tay bằng Canvas (thay SF Symbols) — không kéo material-icons-extended.

enum class Glyph { Keyboard, Sliders, Quote, Info, Globe, Cap, Code, Import, Export, Plus, Check, Trash }

@Composable
fun GlyphIcon(g: Glyph, color: Color, size: Dp = 20.dp, modifier: Modifier = Modifier) {
    Canvas(modifier.size(size)) { drawGlyph(g, color) }
}

private fun DrawScope.drawGlyph(g: Glyph, col: Color) {
    val s = size.minDimension
    val w = s * 0.085f
    val st = Stroke(width = w, cap = StrokeCap.Round)
    fun p(x: Float, y: Float) = Offset(x * s, y * s)
    fun line(x1: Float, y1: Float, x2: Float, y2: Float) =
        drawLine(col, p(x1, y1), p(x2, y2), w, StrokeCap.Round)
    when (g) {
        Glyph.Keyboard -> {
            drawRoundRect(col, p(0.05f, 0.2f), Size(s * 0.9f, s * 0.6f), CornerRadius(s * 0.1f), style = st)
            val d = s * 0.1f
            for (r in 0..1) for (i in 0..4) drawRect(col, p(0.2f + i * 0.14f - 0.045f, 0.33f + r * 0.14f - 0.045f), Size(d * 0.9f, d * 0.9f))
            line(0.33f, 0.66f, 0.67f, 0.66f)
        }
        Glyph.Sliders -> {
            for ((i, k) in listOf(0.7f, 0.3f, 0.6f).withIndex()) {
                val y = 0.22f + i * 0.28f
                line(0.08f, y, 0.92f, y)
                drawCircle(col, s * 0.1f, p(k, y))
            }
        }
        Glyph.Quote -> {
            line(0.12f, 0.3f, 0.88f, 0.3f); line(0.12f, 0.5f, 0.88f, 0.5f); line(0.12f, 0.7f, 0.6f, 0.7f)
            drawCircle(col, s * 0.07f, p(0.78f, 0.72f))
        }
        Glyph.Info -> {
            drawCircle(col, s * 0.42f, p(0.5f, 0.5f), style = st)
            drawCircle(col, s * 0.055f, p(0.5f, 0.3f))
            line(0.5f, 0.45f, 0.5f, 0.72f)
        }
        Glyph.Globe -> {
            drawCircle(col, s * 0.42f, p(0.5f, 0.5f), style = Stroke(w * 0.8f))
            drawOval(col, p(0.32f, 0.08f), Size(s * 0.36f, s * 0.84f), style = Stroke(w * 0.8f))
            line(0.1f, 0.5f, 0.9f, 0.5f)
        }
        Glyph.Cap -> {
            val path = Path().apply { moveTo(0.5f * s, 0.2f * s); lineTo(0.95f * s, 0.4f * s); lineTo(0.5f * s, 0.6f * s); lineTo(0.05f * s, 0.4f * s); close() }
            drawPath(path, col)
            drawArc(col, 0f, 180f, false, p(0.25f, 0.35f), Size(s * 0.5f, s * 0.4f), style = st)
            line(0.88f, 0.44f, 0.88f, 0.72f)
        }
        Glyph.Code -> {
            line(0.3f, 0.3f, 0.1f, 0.5f); line(0.1f, 0.5f, 0.3f, 0.7f)
            line(0.7f, 0.3f, 0.9f, 0.5f); line(0.9f, 0.5f, 0.7f, 0.7f)
            line(0.58f, 0.22f, 0.42f, 0.78f)
        }
        Glyph.Import, Glyph.Export -> {
            val box = Path().apply { moveTo(0.3f * s, 0.42f * s); lineTo(0.15f * s, 0.42f * s); lineTo(0.15f * s, 0.92f * s); lineTo(0.85f * s, 0.92f * s); lineTo(0.85f * s, 0.42f * s); lineTo(0.7f * s, 0.42f * s) }
            drawPath(box, col, style = Stroke(w, cap = StrokeCap.Round))
            if (g == Glyph.Import) { line(0.5f, 0.06f, 0.5f, 0.66f); line(0.33f, 0.5f, 0.5f, 0.67f); line(0.67f, 0.5f, 0.5f, 0.67f) }
            else { line(0.5f, 0.08f, 0.5f, 0.64f); line(0.33f, 0.24f, 0.5f, 0.07f); line(0.67f, 0.24f, 0.5f, 0.07f) }
        }
        Glyph.Plus, Glyph.Check -> {
            drawCircle(col, s * 0.48f, p(0.5f, 0.5f))
            val on = Color.White
            if (g == Glyph.Plus) {
                drawLine(on, p(0.5f, 0.27f), p(0.5f, 0.73f), w, StrokeCap.Round)
                drawLine(on, p(0.27f, 0.5f), p(0.73f, 0.5f), w, StrokeCap.Round)
            } else {
                drawLine(on, p(0.28f, 0.52f), p(0.44f, 0.68f), w, StrokeCap.Round)
                drawLine(on, p(0.44f, 0.68f), p(0.73f, 0.36f), w, StrokeCap.Round)
            }
        }
        Glyph.Trash -> {
            line(0.15f, 0.25f, 0.85f, 0.25f); line(0.4f, 0.12f, 0.6f, 0.12f)
            val b = Path().apply { moveTo(0.23f * s, 0.3f * s); lineTo(0.3f * s, 0.9f * s); lineTo(0.7f * s, 0.9f * s); lineTo(0.77f * s, 0.3f * s) }
            drawPath(b, col, style = st)
        }
    }
}

/** Số trong vòng tròn (`n.circle.fill`) cho checklist onboarding. */
@Composable
fun NumberCircle(n: Int, color: Color, size: Dp = 20.dp) {
    Box(Modifier.size(size).background(color, CircleShape), contentAlignment = Alignment.Center) {
        Text("$n", fontSize = 12.sp, fontWeight = FontWeight.Bold, color = Color.White)
    }
}
