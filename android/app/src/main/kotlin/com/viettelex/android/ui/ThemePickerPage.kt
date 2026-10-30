package com.viettelex.android.ui

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.viettelex.keyboard.CustomThemeStore
import com.viettelex.keyboard.KeyStyle
import com.viettelex.keyboard.KeyboardTheme
import com.viettelex.keyboard.Keys
import com.viettelex.keyboard.ThemeEditTarget
import com.viettelex.keyboard.ThemeExtras
import com.viettelex.keyboard.ThemeGate
import com.viettelex.keyboard.ThemeIssue
import com.viettelex.keyboard.ThemeJsonActions
import com.viettelex.keyboard.ThemePalette
import com.viettelex.keyboard.ThemePicker
import com.viettelex.keyboard.ThemeSettings
import com.viettelex.keyboard.ThemeSpec
import com.viettelex.keyboard.ThemeSpecParser
import com.viettelex.keyboard.tr

/** Palette gốc cho "Chép JSON" / sửa: Hệ thống = màu xem trước (resource Material You). */
private val appBase = ThemeJsonActions.Base { t, dark -> previewPalette(t, dark) }

private fun loadCustomStore(ctx: Context): Map<String, ThemeSpec> = CustomThemeStore.parse(Prefs.of(ctx).getString(Keys.CUSTOM_THEMES, null))
private fun saveCustomStore(ctx: Context, m: Map<String, ThemeSpec>) =
    Prefs.of(ctx).edit().putString(Keys.CUSTOM_THEMES, CustomThemeStore.serialize(m)).apply()

/**
 * "Chọn giao diện": lưới 2 cột thẻ xem trước (vẽ bằng token theme, không ảnh), chia "Miễn phí" / "Plus" /
 * "Giao diện của bạn". Chạm là chọn ngay và ở lại trang (thẻ đang chọn viền + ✓). Theme Plus bị khoá: mờ
 * + nhãn Plus, chạm mở VietTelex Plus. Mỗi thẻ có menu ⋯ ("Giao diện JSON"): Chép JSON (miễn phí) · Sửa ·
 * Đặt lại mặc định (theme có sẵn đã chỉnh) · Xoá (theme tự tạo) — trừ Chép, mọi mục cần Plus. "Dán giao
 * diện" chỉ đọc clipboard khi bấm, xem trước rồi mới thêm. Y hệt iOS ThemePickerView.
 */
@Composable
internal fun ThemePickerPage(s: ThemeSettings, dark: Boolean, onSelect: (ThemeSettings) -> Unit,
                             onOpenPlus: () -> Unit, onBack: () -> Unit) {
    val c = LocalVT.current
    val ctx = LocalContext.current
    var store by remember { mutableStateOf(loadCustomStore(ctx)) }
    var editing by remember { mutableStateOf<Triple<ThemeEditTarget, String, String>?>(null) }
    var pasteText by remember { mutableStateOf<String?>(null) }
    var confirmDelete by remember { mutableStateOf<String?>(null) }
    var toast by remember { mutableStateOf<String?>(null) }
    /** Theme vừa chọn có âm riêng mà Âm thanh phím đang tắt ⇒ gợi ý (không chặn) + nút "Bật". */
    var soundHint by remember { mutableStateOf(false) }
    /** Hỏi trước khi tải tệp của theme (phông / ảnh) còn thiếu — dán JSON không tự tải. */
    val prompt = rememberAssetPrompt()
    BackHandler(onBack = onBack)

    fun persist(ns: ThemeSettings, nstore: Map<String, ThemeSpec>) {
        store = nstore
        saveCustomStore(ctx, nstore)
        onSelect(ns)
        ThemeAssetFlow.gcAsync(ctx)        // tệp không còn theme nào dùng ⇒ xoá
    }
    /** Âm / hiệu ứng đi kèm theme vừa chọn (chỉ lúc chọn — [ThemeExtras]); không bao giờ bật âm thanh phím. */
    fun applyExtras(ns: ThemeSettings) {
        val sp = Prefs.of(ctx)
        val r = ThemeExtras.applyOnSelect(ns.effectiveKeyStyle, sp.getBoolean(Keys.KEY_SOUND, Prefs.D.keySound)) { k, v ->
            sp.edit().putString(k, v).apply()
        }
        soundHint = r.soundHint
    }
    fun choose(ns: ThemeSettings) { onSelect(ns); applyExtras(ns); prompt.offer(ctx, ns.effectiveKeyStyle.assets) }
    fun copy(t: ThemeEditTarget) {
        val text = ThemeJsonActions.copyText(t, s, store, appBase) ?: return
        (ctx.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager)?.setPrimaryClip(ClipData.newPlainText("VietTelex theme", text))
        toast = tr("Đã chép JSON giao diện.")
    }
    fun edit(t: ThemeEditTarget, title: String) {
        if (!ThemeGate.allowsCustom) { onOpenPlus(); return }
        val text = ThemeJsonActions.copyText(t, s, store, appBase) ?: return
        editing = Triple(t, title, text)
    }
    fun paste() {
        if (!ThemeGate.allowsCustom) { onOpenPlus(); return }
        // Chỉ đọc clipboard ở đây (người dùng vừa bấm "Dán giao diện").
        val cm = ctx.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
        val text = cm?.primaryClip?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.coerceToText(ctx)?.toString()
        if (text.isNullOrEmpty()) toast = tr("Clipboard không có văn bản.") else pasteText = text
    }

    SubPageHeader(tr("Chọn giao diện"), onBack)
    if (!ThemeGate.allowsWallpaper) {
        VTSection(footer = tr("Theme có nhãn Plus và ảnh nền thuộc VietTelex Plus (Giới Thiệu → VietTelex Plus). Hệ thống, Tối OLED, Tương phản cao và Xám trung tính luôn miễn phí.")) {}
    }
    for (section in ThemePicker.sections) {
        VTSection(header = tr(section.title)) {
            Grid(section.themes) { t ->
                val locked = !ThemeGate.allows(t)
                ThemeCard(s.styled(t, t.palette(dark) ?: systemPreviewPalette(ctx, s, dark), dark), s.effectiveStyleFor(t), t.title,
                    selected = s.custom == null && s.theme == t, locked = locked, showPlus = t.isPlus && locked,
                    onTap = { ThemePicker.select(t, s)?.let(::choose) ?: onOpenPlus() },
                    menu = { close ->
                        MenuItems(ThemeEditTarget.Builtin(t), t.title, hasOverride = s.keyStyles[t.id] != null, close = close,
                            onCopy = ::copy, onEdit = ::edit,
                            onReset = { if (ThemeGate.allowsAdvanced) onSelect(ThemeJsonActions.reset(t, s)) else onOpenPlus() },
                            onDelete = {})
                    })
            }
        }
    }
    val customs = store.values.sortedWith(compareBy({ it.name }, { it.id ?: "" }))
    VTSection(header = tr("Giao diện của bạn"),
        footer = tr("Dán JSON giao diện đã chép (Plus). Chỉ đọc clipboard khi bạn bấm, xem trước rồi mới thêm.")) {
        if (customs.isNotEmpty()) {
            Grid(customs) { spec ->
                val id = spec.id ?: ""
                val locked = !ThemeGate.allowsCustom
                ThemeCard(s.styledCustom(spec, dark), s.effectiveStyleFor(id, spec.typography), spec.name,
                    selected = s.custom?.id == id, locked = locked, showPlus = locked,
                    onTap = { ThemePicker.select(spec, s)?.let(::choose) ?: onOpenPlus() },
                    menu = { close ->
                        MenuItems(ThemeEditTarget.Custom(id), spec.name, hasOverride = false, close = close,
                            onCopy = ::copy, onEdit = ::edit, onReset = {},
                            onDelete = { if (ThemeGate.allowsCustom) confirmDelete = id else onOpenPlus() })
                    })
            }
            RowDivider()
        }
        VTRow(onClick = { paste() }) {
            Text(tr("Dán giao diện"), style = VTType.body, color = c.accent)
            if (!ThemeGate.allowsCustom) PlusBadge()
        }
    }
    // Tệp tải về của theme đang chọn: trạng thái + lỗi / cảnh báo (thiếu chữ Việt, tiền cảnh phủ nhiều).
    val current = s.effectiveKeyStyle.assets
    if (!current.isEmpty) VTSection { ThemeAssetStatusList(current) { prompt.offer(ctx, current) } }
    if (soundHint) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(tr(ThemeExtras.HINT), style = VTType.footnote, color = c.secondary, modifier = Modifier.weight(1f))
            TextButton(onClick = { Prefs.of(ctx).edit().putBoolean(Keys.KEY_SOUND, true).apply(); soundHint = false }) {
                Text(tr("Bật"), color = c.accent)
            }
        }
    }
    toast?.let { msg ->
        Text(msg, style = VTType.footnote, color = c.secondary, modifier = Modifier.fillMaxWidth().padding(16.dp))
    }
    ThemeAssetPromptHost(prompt, onOpenPlus)

    editing?.let { (target, title, text) ->
        ThemeJsonEditor(title, text, onCancel = { editing = null }) { edited ->
            val r = ThemeJsonActions.save(edited, target, s, store, appBase)
            if (r.ok) {
                persist(r.settings, r.store); editing = null
                val assets = when (target) {
                    is ThemeEditTarget.Builtin -> r.settings.effectiveStyleFor(target.theme).assets
                    is ThemeEditTarget.Custom -> r.store[target.id]?.let { r.settings.effectiveStyleFor(target.id, it.typography).assets }
                }
                assets?.let { prompt.offer(ctx, it) }
            }
            r.issues
        }
    }
    pasteText?.let { text ->
        ThemePastePreview(text, onCancel = { pasteText = null }) { spec ->
            when (val r = ThemeJsonActions.commitPaste(spec, store)) {
                is CustomThemeStore.Added.Err -> r.issue
                is CustomThemeStore.Added.Ok -> {
                    val added = r.store[r.id]
                    val ns = added?.let { ThemePicker.select(it, s) } ?: s
                    persist(ns, r.store)
                    if (added != null && ns !== s) applyExtras(ns)
                    pasteText = null
                    // Chỉ HỎI (người dùng vừa bấm Thêm) — dán / xem trước không gửi yêu cầu nào.
                    added?.let { prompt.offer(ctx, ns.effectiveStyleFor(r.id, it.typography).assets) }
                    null
                }
            }
        }
    }
    confirmDelete?.let { id ->
        AlertDialog(onDismissRequest = { confirmDelete = null },
            title = { Text(tr("Xoá giao diện này?")) },
            confirmButton = { TextButton(onClick = {
                val (ns, nstore) = ThemeJsonActions.delete(id, s, store)
                persist(ns, nstore); confirmDelete = null
            }) { Text(tr("Xoá"), color = c.red) } },
            dismissButton = { TextButton(onClick = { confirmDelete = null }) { Text(tr("Huỷ")) } })
    }
}

@Composable
private fun <T> Grid(items: List<T>, cell: @Composable (T) -> Unit) {
    items.chunked(2).forEach { row ->
        Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 6.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            row.forEach { Box(Modifier.weight(1f)) { cell(it) } }
            repeat(2 - row.size) { Box(Modifier.weight(1f)) }
        }
    }
}

@Composable
private fun PlusBadge() {
    Text("Plus", style = VTType.caption2, color = Color.White,
        modifier = Modifier.padding(start = 8.dp).background(Color(0xFFF5A623), RoundedCornerShape(50))
            .padding(horizontal = 6.dp, vertical = 1.dp))
}

@Composable
private fun ThemeCard(palette: ThemePalette, style: KeyStyle, title: String, selected: Boolean, locked: Boolean, showPlus: Boolean,
                      onTap: () -> Unit, menu: @Composable (close: () -> Unit) -> Unit) {
    val c = LocalVT.current
    var open by remember { mutableStateOf(false) }
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Box(Modifier.clickable(onClick = onTap)) {
            // Thẻ phản ánh tuỳ chỉnh riêng của theme đó (rẻ: vài phép màu, không ảnh).
            KeyboardPreview(palette, null, 0, large = false, keyStyle = style,
                modifier = Modifier.fillMaxWidth().height(72.dp).clip(RoundedCornerShape(10.dp))
                    .border(if (selected) 3.dp else 1.dp, if (selected) c.accent else c.separator, RoundedCornerShape(10.dp)))
            if (selected) Text("✓", style = VTType.body, color = c.accent, modifier = Modifier.align(Alignment.TopEnd).padding(6.dp))
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(title + if (showPlus) " · Plus" else "", style = VTType.footnote,
                color = if (locked) c.secondary else c.label, maxLines = 1, modifier = Modifier.weight(1f))
            Box {
                Text("⋯", style = VTType.body, color = c.secondary,
                    modifier = Modifier.clickable { open = true }.padding(horizontal = 8.dp))
                DropdownMenu(expanded = open, onDismissRequest = { open = false }) { menu { open = false } }
            }
        }
    }
}

@Composable
private fun MenuItems(t: ThemeEditTarget, title: String, hasOverride: Boolean, close: () -> Unit,
                      onCopy: (ThemeEditTarget) -> Unit, onEdit: (ThemeEditTarget, String) -> Unit,
                      onReset: () -> Unit, onDelete: () -> Unit) {
    val plus = if (ThemeGate.allowsCustom) "" else " · Plus"
    DropdownMenuItem(text = { Text(tr("Chép JSON")) }, onClick = { close(); onCopy(t) })
    DropdownMenuItem(text = { Text(tr("Sửa") + plus) }, onClick = { close(); onEdit(t, title) })
    when (t) {
        is ThemeEditTarget.Builtin -> if (hasOverride)
            DropdownMenuItem(text = { Text(tr("Đặt lại mặc định") + plus) }, onClick = { close(); onReset() })
        is ThemeEditTarget.Custom -> DropdownMenuItem(text = { Text(tr("Xoá") + plus) }, onClick = { close(); onDelete() })
    }
}

/** Danh sách lỗi / cảnh báo (tiếng Việt hoặc tiếng Anh theo ngôn ngữ giao diện). */
@Composable
private fun IssueList(issues: List<ThemeIssue>) {
    val c = LocalVT.current
    if (issues.isEmpty()) { Text("✓ " + tr("JSON hợp lệ."), style = VTType.footnote, color = c.green); return }
    Column {
        issues.take(8).forEach { i ->
            Text((if (i.isError) "✕ " else "⚠ ") + i.message, style = VTType.footnote, color = if (i.isError) c.red else Color(0xFFE08600))
        }
        if (issues.size > 8) Text(tr("… và %s mục khác.", issues.size - 8), style = VTType.footnote, color = c.secondary)
    }
}

@Composable
private fun SpecPreview(spec: ThemeSpec) {
    Row(Modifier.fillMaxWidth().height(70.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        for (d in listOf(false, true)) KeyboardPreview(spec.palette(d), null, 0, large = false, keyStyle = spec.typography,
            modifier = Modifier.weight(1f).height(70.dp).clip(RoundedCornerShape(8.dp)))
    }
}

/** Trình sửa JSON (chữ đơn cách, kiểm trực tiếp). Lưu chỉ bật khi không còn lỗi; cảnh báo vẫn lưu được. */
@Composable
private fun ThemeJsonEditor(title: String, initial: String, onCancel: () -> Unit, onSave: (String) -> List<ThemeIssue>) {
    val c = LocalVT.current
    var text by remember { mutableStateOf(initial) }
    var saveIssues by remember { mutableStateOf<List<ThemeIssue>>(emptyList()) }
    val outcome = remember(text) { ThemeSpecParser.parse(text) }
    Dialog(onDismissRequest = onCancel, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Column(Modifier.fillMaxSize().background(c.groupedBg).padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                TextButton(onClick = onCancel) { Text(tr("Huỷ")) }
                Text(title, style = VTType.headline, color = c.label, maxLines = 1, modifier = Modifier.weight(1f))
                TextButton(enabled = outcome.errors.isEmpty(), onClick = {
                    val r = onSave(text)
                    if (r.any { it.isError }) saveIssues = r
                }) { Text(tr("Lưu")) }
            }
            outcome.spec?.let { SpecPreview(it) }
            BasicTextField(value = text, onValueChange = { text = it; saveIssues = emptyList() },
                textStyle = TextStyle(fontFamily = FontFamily.Monospace, fontSize = 13.sp, color = c.label),
                cursorBrush = SolidColor(c.accent),
                modifier = Modifier.weight(1f).fillMaxWidth().clip(RoundedCornerShape(8.dp)).background(c.card)
                    .padding(8.dp).verticalScroll(rememberScrollState()))
            IssueList(if (saveIssues.isEmpty()) outcome.issues else saveIssues)
            outcome.spec?.assets?.let { ThemeAssetStatusList(it, onRetry = null) }
        }
    }
}

/** "Dán giao diện": xem trước theme đọc từ clipboard — Thêm mới ghi. */
@Composable
private fun ThemePastePreview(text: String, onCancel: () -> Unit, onAdd: (ThemeSpec) -> ThemeIssue?) {
    val c = LocalVT.current
    val outcome = remember(text) { ThemeJsonActions.preview(text) }
    var addError by remember { mutableStateOf<ThemeIssue?>(null) }
    AlertDialog(onDismissRequest = onCancel,
        title = { Text(outcome.spec?.name ?: tr("Dán giao diện")) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                outcome.spec?.let { SpecPreview(it); Text(tr("Sáng · Tối"), style = VTType.footnote, color = c.secondary) }
                IssueList(addError?.let { listOf(it) } ?: outcome.issues)
            }
        },
        confirmButton = { TextButton(enabled = outcome.spec != null, onClick = {
            outcome.spec?.let { addError = onAdd(it) }
        }) { Text(tr("Thêm")) } },
        dismissButton = { TextButton(onClick = onCancel) { Text(tr("Huỷ")) } })
}
