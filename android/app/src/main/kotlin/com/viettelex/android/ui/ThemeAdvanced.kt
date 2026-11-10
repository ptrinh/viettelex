package com.viettelex.android.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.sp
import com.viettelex.keyboard.BuiltinFonts
import com.viettelex.keyboard.KeyLabelFont
import com.viettelex.keyboard.KeyLabelWeight
import com.viettelex.keyboard.KeyStyle
import com.viettelex.keyboard.ThemeGate
import com.viettelex.keyboard.ThemePalette
import com.viettelex.keyboard.tr

/** Bo mặc định (7dp trên phím ~44dp) ≈ 30% nửa cạnh ngắn — vị trí thanh trượt khi chưa chỉnh. */
private const val DEFAULT_CORNER_PERCENT = 30

/**
 * "Tuỳ chỉnh nâng cao" (Plus) ở trang Giao diện — thu gọn mặc định. Chưa có Plus: chạm mở màn
 * VietTelex Plus ([onOpenPlus]); giá trị đã lưu chỉ áp khi có Plus ([com.viettelex.keyboard.ThemeSettings.effectiveKeyStyle]).
 * [palette] = palette đang xem trước (màu "theo theme" hiện ở ô màu). [borderLocked] = theme có viền hiệu ứng / skin
 * ảnh ([KeyStyle.borderLocked]) ⇒ ô "Màu viền phím" mờ + giải thích.
 */
@Composable
internal fun AdvancedStyleSection(style: KeyStyle, palette: ThemePalette, onChange: (KeyStyle) -> Unit, onOpenPlus: () -> Unit,
                                  onFontAsset: (KeyStyle) -> Unit = onChange, borderLocked: Boolean = false) {
    val c = LocalVT.current
    val allowed = ThemeGate.allowsAdvanced
    var open by rememberSaveable { mutableStateOf(false) }
    VTSection(footer = tr(SettingCaption.advancedStyle)) {
        VTRow(onClick = { if (allowed) open = !open else onOpenPlus() }) {
            Text(tr("Tuỳ chỉnh nâng cao"), style = VTType.body, color = c.label)
            Text("Plus", style = VTType.footnote, color = Color.White,
                modifier = Modifier.padding(start = 8.dp).background(Color(0xFFF5A623), RoundedCornerShape(50))
                    .padding(horizontal = 6.dp, vertical = 1.dp))
            Box(Modifier.weight(1f))
            Text(if (!allowed) "›" else if (open) "▾" else "▸", style = VTType.body, color = c.secondary)
        }
        if (!allowed || !open) return@VTSection
        RowDivider()
        ColorRow(tr("Màu chữ trên phím"), style.labelColor, palette.keyInk) { onChange(style.copy(labelColor = it)) }
        RowDivider()
        ColorRow(tr("Màu nền phím"), style.fillColor, palette.keyFill) { onChange(style.copy(fillColor = it)) }
        RowDivider()
        // Nhập/hành động, ⇧ bật, vệt gõ vuốt — chữ trên nó tự đổi đen/trắng nếu cần.
        ColorRow(tr("Màu nhấn"), style.accentColor, palette.action) { onChange(style.copy(accentColor = it)) }
        RowDivider()
        // Viền mọi phím (+ ô phóng to); theme không viền ⇒ viền mảnh. Viền hiệu ứng / skin ảnh ⇒ mờ + giải thích.
        ColorRow(tr("Màu viền phím"), style.borderColor, palette.keyBorder ?: palette.keyInk, enabled = !borderLocked) {
            onChange(style.withBorderColor(it))
        }
        if (borderLocked) Text(tr("Giao diện này dùng viền hiệu ứng riêng."), style = VTType.footnote, color = c.secondary,
            modifier = Modifier.padding(start = 16.dp, end = 16.dp, bottom = 8.dp))
        RowDivider()
        Column(Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(style.corner?.let { tr("Độ bo góc phím: %s%%", it) } ?: tr("Độ bo góc phím: mặc định"),
                    style = VTType.body, color = c.label, modifier = Modifier.weight(1f))
                if (style.corner != null) TextButton(onClick = { onChange(style.copy(corner = null)) }) { Text(tr("Mặc định")) }
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(14.dp).border(1.5.dp, c.secondary))
                Slider(value = (style.corner ?: DEFAULT_CORNER_PERCENT).toFloat(), valueRange = 0f..100f, steps = 19,
                    onValueChange = { onChange(style.copy(corner = Math.round(it / 5) * 5)) },
                    modifier = Modifier.weight(1f).padding(horizontal = 8.dp))
                Box(Modifier.size(14.dp).border(1.5.dp, c.secondary, CircleShape))
            }
        }
        RowDivider()
        Column(Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(tr("Cỡ chữ trên phím: %s%%", style.fontScale ?: 100), style = VTType.body, color = c.label,
                    modifier = Modifier.weight(1f))
                if (style.fontScale != null) TextButton(onClick = { onChange(style.copy(fontScale = null)) }) { Text(tr("Mặc định")) }
            }
            Slider(value = (style.fontScale ?: 100).toFloat(),
                valueRange = KeyStyle.FONT_SCALE_MIN.toFloat()..KeyStyle.FONT_SCALE_MAX.toFloat(),
                steps = (KeyStyle.FONT_SCALE_MAX - KeyStyle.FONT_SCALE_MIN) / 5 - 1,
                onValueChange = { onChange(style.copy(fontScale = KeyStyle.parseFontScale(Math.round(it / 5) * 5))) })
            Text(tr(SettingCaption.fontScaleAndroid),
                style = VTType.footnote, color = c.secondary)
        }
        RowDivider()
        // Lưới phông: mỗi ô chữ "Vt" bằng chính phông đó — phông hệ thống + phông tải về có sẵn (Plus).
        FontGrid(style, onSystem = { onChange(style.copy(font = it, assets = style.assets.copy(font = null))) },
            onAsset = { onFontAsset(style.copy(font = KeyLabelFont.DEFAULT, assets = style.assets.copy(font = it.asset))) })
        RowDivider()
        OptionChips(tr("Độ đậm"), KeyLabelWeight.entries, style.weight, { it.title }, { null },
            weight = { FontWeight(it.weight) }) { onChange(style.copy(weight = it)) }
        RowDivider()
        VTRow(onClick = if (style.isDefault) null else { { onChange(KeyStyle.DEFAULT) } }) {
            Text(tr("Đặt lại về mặc định của giao diện"), style = VTType.body, color = if (style.isDefault) c.secondary else c.red)
        }
    }
}

/** Một ô lưới phông: "Vt" bằng phông đó + tên; đang chọn tô màu nhấn. */
@Composable
private fun FontTile(name: String, family: FontFamily, on: Boolean, modifier: Modifier, onPick: () -> Unit) {
    val c = LocalVT.current
    Column(modifier
        .background(if (on) c.accent else c.secondary.copy(alpha = 0.12f), RoundedCornerShape(10.dp))
        .clickable(onClick = onPick)
        .padding(vertical = 8.dp, horizontal = 4.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Text("Vt", fontFamily = family, fontSize = 26.sp, maxLines = 1, color = if (on) Color.White else c.label)
        Text(name, style = VTType.caption2, maxLines = 1, color = if (on) Color.White else c.secondary)
    }
}

/**
 * Phông chữ: phông hệ thống (có trên Android) + 12 phông tải về có sẵn ([BuiltinFonts]). Phông tải về chưa tải
 * vẽ "Vt" bằng phông xem trước tí hon trong assets (fontpreview/…); đã tải ⇒ phông thật trong kho.
 */
@Composable
private fun FontGrid(style: KeyStyle, onSystem: (KeyLabelFont) -> Unit, onAsset: (BuiltinFonts.Entry) -> Unit) {
    val c = LocalVT.current
    val ctx = LocalContext.current
    val version = ThemeAssetFlow.storeVersion
    val systems = KeyLabelFont.entries.filter { it.onAndroid }
    val families = remember(version) {
        val dir = ThemeAssetFlow.dir(ctx)
        val index = com.viettelex.keyboard.ThemeAssetStore.readIndex(dir)
        BuiltinFonts.list.associate { e ->
            val key = com.viettelex.keyboard.ThemeAssetFile(com.viettelex.keyboard.ThemeAssetClass.font, e.ref).key
            val tf = index[key]?.let { runCatching { android.graphics.Typeface.createFromFile(java.io.File(dir, it.file)) }.getOrNull() }
                ?: runCatching { android.graphics.Typeface.createFromAsset(ctx.assets, e.previewAsset) }.getOrNull()
            e.id to (tf?.let { FontFamily(it) } ?: FontFamily.Default)
        }
    }
    VTRow { Text(tr("Phông chữ"), style = VTType.body, color = c.label) }
    val selectedAsset = style.assets.font
    val tiles: List<Pair<String, @Composable (Modifier) -> Unit>> = systems.map { f ->
        f.id to @Composable { m: Modifier ->
            FontTile(f.title, systemFamily(f, ctx), selectedAsset == null && (if (style.font.onAndroid) style.font else KeyLabelFont.DEFAULT) == f, m) { onSystem(f) }
        }
    } + BuiltinFonts.list.map { e ->
        e.id to @Composable { m: Modifier ->
            FontTile(e.name, families[e.id] ?: FontFamily.Default, selectedAsset?.ref == e.ref, m) { onAsset(e) }
        }
    }
    tiles.chunked(4).forEach { row ->
        Row(Modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, bottom = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            for ((_, tile) in row) tile(Modifier.weight(1f))
            repeat(4 - row.size) { Box(Modifier.weight(1f)) }
        }
    }
    Text(tr("Phông tải về (Plus): chữ “Vt” xem trước; chọn rồi app hỏi trước khi tải từ viettelex.com."),
        style = VTType.footnote, color = c.secondary, modifier = Modifier.padding(start = 16.dp, end = 16.dp, bottom = 8.dp))
}

private fun systemFamily(f: KeyLabelFont, ctx: android.content.Context): FontFamily = when (f) {
    KeyLabelFont.PIXEL -> com.viettelex.android.ime.PixelFont.typeface(ctx.assets)?.let { FontFamily(it) } ?: FontFamily.Monospace
    KeyLabelFont.SERIF -> FontFamily.Serif
    KeyLabelFont.MONO -> FontFamily.Monospace
    KeyLabelFont.CONDENSED -> FontFamily(android.graphics.Typeface.create("sans-serif-condensed", android.graphics.Typeface.NORMAL))
    else -> FontFamily.Default
}

@Composable
private fun <T> OptionChips(title: String, options: List<T>, selected: T, label: (T) -> String,
                            family: (T) -> FontFamily?, weight: (T) -> FontWeight? = { null }, onPick: (T) -> Unit) {
    val c = LocalVT.current
    VTRow { Text(title, style = VTType.body, color = c.label) }
    // Hai hàng khi nhiều lựa chọn (5 ô độ đậm vừa một hàng điện thoại hẹp nếu chữ nhỏ).
    options.chunked(if (options.size > 4) 3 else options.size).forEach { row ->
        Row(Modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, bottom = 8.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            for (o in row) {
                val on = o == selected
                Box(Modifier.weight(1f)
                    .background(if (on) c.accent else c.secondary.copy(alpha = 0.12f), RoundedCornerShape(10.dp))
                    .clickable { onPick(o) }
                    .padding(vertical = 8.dp), contentAlignment = Alignment.Center) {
                    Text(label(o), style = VTType.subheadline, maxLines = 1, fontFamily = family(o), fontWeight = weight(o),
                        color = if (on) Color.White else c.label)
                }
            }
            repeat((if (options.size > 4) 3 else options.size) - row.size) { Box(Modifier.weight(1f)) }
        }
    }
}

/** Dòng màu: ô màu hiện tại (theo theme khi chưa chọn) — chạm mở bảng chọn; "Theo theme" về mặc định. */
@Composable
private fun ColorRow(title: String, value: Int?, themeColor: Int, enabled: Boolean = true, onPick: (Int?) -> Unit) {
    val c = LocalVT.current
    var picking by remember { mutableStateOf(false) }
    val shown = value?.let { 0xFF000000.toInt() or it } ?: (themeColor or 0xFF000000.toInt())
    VTRow(onClick = if (enabled) { { picking = true } } else null) {
        Text(title, style = VTType.body, color = if (enabled) c.label else c.secondary, modifier = Modifier.weight(1f))
        if (value != null) TextButton(onClick = { onPick(null) }) { Text(tr("Theo theme")) }
        Box(Modifier.size(28.dp).background(Color(shown), CircleShape).border(1.dp, c.separator, CircleShape))
    }
    if (picking) ColorPickerDialog(title, shown, onDismiss = { picking = false }) { picking = false; onPick(it and 0xFFFFFF) }
}

/** Bảng chọn màu nhẹ (không thư viện ngoài): dải màu gợi ý + 3 thanh Sắc độ / Độ bão hoà / Độ sáng (HSV). */
@Composable
private fun ColorPickerDialog(title: String, initial: Int, onDismiss: () -> Unit, onPick: (Int) -> Unit) {
    val c = LocalVT.current
    val hsv0 = remember { FloatArray(3).also { android.graphics.Color.colorToHSV(initial, it) } }
    var h by remember { mutableStateOf(hsv0[0]) }
    var s by remember { mutableStateOf(hsv0[1]) }
    var v by remember { mutableStateOf(hsv0[2]) }
    fun color(hh: Float = h, ss: Float = s, vv: Float = v) = android.graphics.Color.HSVToColor(floatArrayOf(hh, ss, vv))
    val presets = listOf(0x000000, 0xFFFFFF, 0x1C1C1E, 0x8E8E93, 0xFF3B30, 0xFF9500, 0xFFCC00, 0x34C759,
        0x00C7BE, 0x007AFF, 0x5856D6, 0xAF52DE, 0xFF2D55, 0xA2845E, 0xFBE3E1, 0xD9F2E7)
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Box(Modifier.fillMaxWidth().height(40.dp).background(Color(color()), RoundedCornerShape(10.dp))
                    .border(1.dp, c.separator, RoundedCornerShape(10.dp)))
                presets.chunked(8).forEach { row ->
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        for (p in row) {
                            Box(Modifier.weight(1f).height(26.dp).background(Color(0xFF000000.toInt() or p), CircleShape)
                                .border(1.dp, c.separator, CircleShape)
                                .clickable {
                                    val a = FloatArray(3); android.graphics.Color.colorToHSV(0xFF000000.toInt() or p, a)
                                    h = a[0]; s = a[1]; v = a[2]
                                })
                        }
                    }
                }
                Text(tr("Sắc độ"), style = VTType.footnote, color = c.secondary)
                Box(Modifier.fillMaxWidth().height(8.dp).background(
                    Brush.horizontalGradient((0..6).map { Color(color(hh = it * 60f, ss = 1f, vv = 1f)) }), RoundedCornerShape(4.dp)))
                Slider(value = h, valueRange = 0f..360f, onValueChange = { h = it })
                Text(tr("Độ bão hoà"), style = VTType.footnote, color = c.secondary)
                Slider(value = s, valueRange = 0f..1f, onValueChange = { s = it })
                Text(tr("Độ sáng"), style = VTType.footnote, color = c.secondary)
                Slider(value = v, valueRange = 0f..1f, onValueChange = { v = it })
            }
        },
        confirmButton = { TextButton(onClick = { onPick(color()) }) { Text(tr("Chọn")) } },
        dismissButton = { TextButton(onClick = onDismiss) { Text(tr("Huỷ")) } },
    )
}
