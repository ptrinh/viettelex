package com.viettelex.android.ui

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.viettelex.android.BuildConfig
import com.viettelex.android.R
import com.viettelex.keyboard.Keys
import com.viettelex.keyboard.TemplateItem
import com.viettelex.keyboard.Templates
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

private const val APPLY_NOTE = "Cài đặt áp dụng ngay lần mở bàn phím kế tiếp."

private fun openUrl(ctx: Context, url: String) {
    runCatching { ctx.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))) }
}

@Composable
private fun AppLogo(size: Dp, radius: Dp, shadow: Boolean = false) {
    Image(
        painterResource(R.drawable.vt_logo), contentDescription = null,
        modifier = Modifier.size(size)
            .then(if (shadow) Modifier.shadow(6.dp, RoundedCornerShape(radius), ambientColor = Color.Black.copy(0.15f), spotColor = Color.Black.copy(0.15f)) else Modifier)
            .clip(RoundedCornerShape(radius)),
    )
}

// ============================================================== Kiểu Gõ

@Composable
fun KieuGoTab(ime: ImeStatus, onOpenImeSettings: () -> Unit, onPickIme: () -> Unit) {
    val c = LocalVT.current
    VTSection(plain = true) { OnboardingCard(ime, onOpenImeSettings, onPickIme) }
    VTSection(
        header = "Thử gõ",
        footer = "Chọn Tiếng Việt (VietTelex) — bấm biểu tượng bàn phím ở thanh điều hướng — rồi gõ thử: vieejt → việt.",
    ) {
        var text by rememberSaveable { mutableStateOf("") }
        // KHÔNG tắt autoCorrect: bàn phím coi ô "không gợi ý/không sửa" là passthrough (như iOS).
        VTTextField(text, { text = it }, "Thử gõ tại đây…", minLines = 1, maxLines = 4,
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 11.dp))
    }
    KieuGoSection()
}

/** Ô nhập kiểu iOS (không gạch chân Material). */
@Composable
fun VTTextField(
    value: String, onChange: (String) -> Unit, placeholder: String,
    minLines: Int = 1, maxLines: Int = 1, center: Boolean = false, modifier: Modifier = Modifier,
) {
    val c = LocalVT.current
    val style = VTType.body.copy(color = c.label, textAlign = if (center) TextAlign.Center else TextAlign.Start)
    BasicTextField(
        value, onChange, modifier.fillMaxWidth(),
        textStyle = style, minLines = minLines, maxLines = maxLines, singleLine = maxLines == 1,
        cursorBrush = SolidColor(c.accent),
        keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences),
        decorationBox = { inner ->
            Box {
                if (value.isEmpty()) Text(placeholder, style = style.copy(color = c.tertiary), modifier = Modifier.fillMaxWidth())
                inner()
            }
        },
    )
}

@Composable
private fun OnboardingCard(ime: ImeStatus, onOpenImeSettings: () -> Unit, onPickIme: () -> Unit) {
    val c = LocalVT.current
    Column(
        Modifier.padding(vertical = 6.dp).fillMaxWidth().glassCard(c)
            .padding(if (ime.selected) 14.dp else 20.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        if (ime.selected) {
            // Đã bật + đang chọn — thu gọn, chỉ xác nhận + nhắc thử gõ.
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                GlyphIcon(Glyph.Check, c.green, 26.dp)
                Column(Modifier.padding(start = 10.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text("Bàn phím đã bật", style = VTType.headline, color = c.label)
                    Text("Thử gõ ngay bên dưới.", style = VTType.subheadline, color = c.secondary)
                }
            }
            return@Column
        }
        AppLogo(64.dp, 14.dp)
        Text("Bật bàn phím VietTelex", style = VTType.title3, color = c.label)
        Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Step(1, "Bật bàn phím trong Cài đặt", ime.enabled)
            if (!ime.enabled) {
                Column(Modifier.padding(start = 30.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Note("Cài đặt → Hệ thống → Ngôn ngữ & nhập liệu")
                    Note("Bàn phím trên màn hình → Quản lý → bật VietTelex")
                    Note("Khi bật, Android hiện cảnh báo bàn phím “có thể thu thập mọi văn bản bạn nhập”.", c.tertiary)
                    Note("Cảnh báo này hiện với mọi bàn phím bên thứ ba — VietTelex chạy hoàn toàn trên máy, không gửi gì đi.", c.tertiary)
                }
            }
            Step(2, "Chọn VietTelex làm bàn phím", ime.selected)
            if (ime.enabled) {
                Note("Khi gõ, bấm biểu tượng bàn phím ở thanh điều hướng để chuyển sang VietTelex", modifier = Modifier.padding(start = 30.dp))
            }
            Step(3, "Thử gõ ngay bên dưới", false)
        }
        if (!ime.enabled) ProminentButton("Mở Cài đặt", onOpenImeSettings)
        else ProminentButton("Chọn VietTelex", onPickIme)
    }
}

@Composable
private fun Step(n: Int, title: String, done: Boolean) {
    val c = LocalVT.current
    Row(verticalAlignment = Alignment.CenterVertically) {
        if (done) GlyphIcon(Glyph.Check, c.green, 20.dp) else NumberCircle(n, c.secondary)
        Text(title, style = VTType.subheadline, color = c.label, modifier = Modifier.padding(start = 10.dp))
    }
}

@Composable
private fun Note(text: String, color: Color? = null, modifier: Modifier = Modifier) {
    Text(text, style = VTType.footnote, color = color ?: LocalVT.current.secondary, modifier = modifier)
}

@Composable
private fun BoolToggle(key: String, default: Boolean, title: String, caption: String) {
    var v by rememberBoolPref(key, default)
    SettingToggle(title, caption, v) { v = it }
}

@Composable
private fun KieuGoSection() {
    VTSection(header = "Kiểu gõ", footer = APPLY_NOTE) {
        BoolToggle(Keys.SIMPLE_TELEX, Prefs.D.simpleTelex, "Telex đơn giản", "Phím w đứng lẻ giữ nguyên là w, không thành ư.")
        RowDivider()
        BoolToggle(Keys.FREE_MARKING, Prefs.D.freeMarking, "Bỏ dấu tự do", "Phím dấu đặt đâu cũng được, không cần đúng thứ tự.")
        RowDivider()
        BoolToggle(Keys.QUICK_TELEX, Prefs.D.quickTelex, "Gõ nhanh (Quick Telex)", "Phụ âm đôi đầu từ thành phụ âm ghép: cc → ch, nn → ng, tt → th…")
        RowDivider()
        BoolToggle(Keys.MODERN_TONE, Prefs.D.modernTone, "Bỏ dấu kiểu mới", "hoà, thuý thay vì hòa, thúy.")
        RowDivider()
        BoolToggle(Keys.CONTEXTUAL_ENGLISH, Prefs.D.contextualEnglish, "Quyết định theo ngữ cảnh", "Sau một từ tiếng Anh, từ mơ hồ kế tiếp giữ nguyên tiếng Anh — \"he is\" → he is, không phải \"he í\". Sau từ tiếng Việt thì vẫn là tiếng Việt — \"sao í\".")
        RowDivider()
        BoolToggle(Keys.AUTO_FIX_ADJACENT, Prefs.D.autoFixAdjacent, "Gợi ý sửa lỗi chạm trượt", "Khi từ đang gõ không phải tiếng Việt, gợi ý từ đúng nếu bạn lỡ chạm phím bên cạnh: nbjeeuf → nhiều, ohims → phím, cahcs → cách. Chạm gợi ý để thay.")
        RowDivider()
        BoolToggle(Keys.TEENCODE, Prefs.D.teencode, "Chính tả teencode", "Chấp nhận cách viết khi chat: w/z/k thay cho qu/d/c (wá, zui zẻ, kó) và bíe, thík, gòy, ừk. Tắt = chỉ chính tả chuẩn, từ tiếng Anh như was, war, zoo giữ nguyên.")
    }
}

// ============================================================== Tính Năng

@Composable
fun TinhNangTab() {
    val c = LocalVT.current
    val ctx = LocalContext.current
    VTSection(header = "Chính tả") {
        BoolToggle(Keys.AUTO_RESTORE, Prefs.D.autoRestore, "Tự khôi phục từ tiếng Anh", "Từ không phải tiếng Việt tự trả về như đã gõ (google, github…).")
        RowDivider()
        BoolToggle(Keys.LIVE_SPELL_CHECK, Prefs.D.liveSpellCheck, "Kiểm tra chính tả khi gõ", "Ngừng bỏ dấu ngay khi từ không thể là tiếng Việt.")
    }
    VTSection(header = "Gợi ý") {
        BoolToggle(Keys.SHOW_SUGGESTIONS, Prefs.D.showSuggestions, "Thanh gợi ý", "Gợi ý từ + emoji, tự học từ bạn hay dùng (chỉ trên máy).")
        RowDivider()
        BoolToggle(Keys.FILTER_SENSITIVE, Prefs.D.filterSensitive, "Lọc từ nhạy cảm khỏi gợi ý", "Không chủ động gợi ý từ tục — gõ tay và học vẫn bình thường.")
        RowDivider()
        BoolToggle(Keys.TEMPLATES_ENABLED, Prefs.D.templatesEnabled, "Mẫu câu", "Nút ☰ trên bàn phím chèn nhanh câu soạn sẵn — quản lý ở tab Mẫu Câu.")
        RowDivider()
        VTRow(onClick = {
            java.io.File(ctx.filesDir, Keys.USERLM_FILE).delete()
            // IME (cùng process) thấy mốc đổi ⇒ bỏ model trong RAM, seed lại, không ghi đè.
            Prefs.of(ctx).edit().putLong(Keys.USERLM_RESET_AT, System.currentTimeMillis()).apply()
        }) { Text("Xóa từ đã học", style = VTType.body, color = c.red) }
    }
    VTSection(header = "Giao diện", footer = APPLY_NOTE) {
        BoolToggle(Keys.SHOW_SPACE_LOGO, Prefs.D.showSpaceLogo, "Hiện logo Vᴛ", "Logo mờ ở góc phải phím space.")
        RowDivider()
        BoolToggle(Keys.HAPTIC_FEEDBACK, Prefs.D.hapticFeedback, "Rung phím", "Rung nhẹ mỗi lần chạm phím.")
        RowDivider()
        var adj by rememberIntPref(Keys.ROW_HEIGHT_ADJUST, Prefs.D.rowHeightAdjust)
        VTRow {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text("Chiều cao hàng phím", style = VTType.body, color = c.label)
                Text(
                    if (adj == 0) "Chuẩn" else String.format(Locale.ROOT, "%+d dp mỗi hàng (%+d dp cả bàn phím)", adj, adj * 4),
                    style = VTType.footnote, color = c.secondary,
                )
            }
            IosStepper(adj, -10..10) { adj = it }
        }
    }
}

// ============================================================== Mẫu Câu

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MauCauTab() {
    val c = LocalVT.current
    val ctx = LocalContext.current
    var templates by remember { mutableStateOf(TemplatesStore.load(ctx)) }
    var newLabel by rememberSaveable { mutableStateOf("") }
    var newText by rememberSaveable { mutableStateOf("") }
    var notice by remember { mutableStateOf<String?>(null) }
    var editing by remember { mutableStateOf<Int?>(null) }
    var editLabel by remember { mutableStateOf("") }
    var editText by remember { mutableStateOf("") }
    fun persist(list: List<TemplateItem>) { templates = list; TemplatesStore.save(ctx, list) }

    VTSection(
        header = "Mẫu câu (${templates.size})",
        footer = "Bấm ☰ trên bàn phím để chèn nhanh. Chạm một dòng để sửa, vuốt trái để xoá. Label (emoji/chữ ngắn) giúp bubble trên bàn phím gọn hơn.",
    ) {
        templates.forEachIndexed { i, t ->
            key(t.label + "\u0001" + t.text) {
                if (i > 0) RowDivider()
                val state = rememberSwipeToDismissBoxState(confirmValueChange = {
                    if (it == SwipeToDismissBoxValue.EndToStart) { persist(templates - t); true } else false
                })
                SwipeToDismissBox(
                    state, enableDismissFromStartToEnd = false,
                    backgroundContent = {
                        Box(Modifier.fillMaxWidth().height(44.dp).background(c.red).padding(end = 20.dp), contentAlignment = Alignment.CenterEnd) {
                            GlyphIcon(Glyph.Trash, Color.White, 20.dp)
                        }
                    },
                ) {
                    if (editing == i) {
                        val canSave = editText.trim().isNotEmpty()
                        VTRow(modifier = Modifier.background(c.card)) {
                            VTTextField(editLabel, { editLabel = it }, "👋", center = true, modifier = Modifier.width(44.dp))
                            Box(Modifier.padding(horizontal = 10.dp).width(0.5.dp).height(28.dp).background(c.separator))
                            VTTextField(editText, { editText = it }, "Mẫu câu", maxLines = 4, modifier = Modifier.weight(1f))
                            Box(
                                Modifier.padding(start = 8.dp).size(28.dp).clickable(enabled = canSave) {
                                    val r = Templates.edit(templates, i, editLabel, editText)
                                    if (r != null) { persist(r); editing = null } else notice = "Mẫu câu này đã có."
                                },
                                contentAlignment = Alignment.Center,
                            ) { GlyphIcon(Glyph.Check, if (canSave) c.accent else c.tertiary, 24.dp) }
                            Text("✕", color = c.secondary, modifier = Modifier.padding(start = 8.dp).clickable { editing = null })
                        }
                    } else {
                        VTRow(modifier = Modifier.background(c.card).clickable {
                            editLabel = t.label; editText = t.text; editing = i
                        }) {
                            Text(t.label.ifEmpty { "💬" }, style = VTType.body, modifier = Modifier.widthIn(min = 30.dp))
                            Text(t.text, style = VTType.body, color = c.label, modifier = Modifier.padding(start = 8.dp))
                        }
                    }
                }
            }
        }
        if (templates.isEmpty()) VTRow { Text("Chưa có mẫu câu nào.", style = VTType.body, color = c.secondary) }
    }

    VTSection(header = "Thêm mới", footer = "Ô nhỏ bên trái là label (không bắt buộc).") {
        val trimmed = newText.trim()
        val canAdd = trimmed.isNotEmpty()
        VTRow {
            VTTextField(newLabel, { newLabel = it }, "👋", center = true, modifier = Modifier.width(44.dp))
            Box(Modifier.padding(horizontal = 10.dp).width(0.5.dp).height(28.dp).background(c.separator))
            VTTextField(newText, { newText = it }, "Thêm mẫu câu…", maxLines = 3, modifier = Modifier.weight(1f))
            Box(
                Modifier.padding(start = 8.dp).size(28.dp).clickable(enabled = canAdd) {
                    Templates.add(templates, newLabel, newText)?.let {
                        persist(it)
                        newLabel = ""; newText = ""
                    }
                },
                contentAlignment = Alignment.Center,
            ) { GlyphIcon(Glyph.Plus, if (canAdd) c.accent else c.tertiary, 24.dp) }
        }
    }

    VTSection(
        header = "Mẫu câu động (https://)",
        footer = "Mẫu có nội dung bắt đầu bằng https:// sẽ fetch dữ liệu NGAY LÚC BẤM và chèn kết quả (tối đa 1000 bytes) — ví dụ IP❓ chèn địa chỉ IP hiện tại. Không có mạng thì bấm sẽ chèn chính URL.",
        plain = true,
    ) {}

    val importer = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        val text = runCatching { ctx.contentResolver.openInputStream(uri)?.use { it.bufferedReader().readText() } }.getOrNull()
        if (text == null) { notice = "Không đọc được file."; return@rememberLauncherForActivityResult }
        val (merged, msg) = Templates.merge(templates, Templates.parseYAML(text))
        persist(merged)
        notice = msg
    }
    val exporter = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/x-yaml")) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        val ok = runCatching {
            ctx.contentResolver.openOutputStream(uri, "wt")!!.use { it.write(Templates.exportYAML(templates).toByteArray()) }
        }.isSuccess
        notice = if (ok) "Đã export ${templates.size} mẫu." else "Không ghi được file."
    }
    VTSection(footer = "YAML phẳng, mỗi dòng “- \"👋 | Chào buổi sáng\"” (label | câu) hoặc “- \"câu\"”. Import gộp thêm, không thay thế.") {
        LinkRow(Glyph.Import, "Import…") { importer.launch(arrayOf("*/*")) }
        RowDivider(52.dp)
        LinkRow(Glyph.Export, "Export ra YAML…") { exporter.launch("viettelex-mau-cau.yaml") }
        notice?.let {
            RowDivider()
            VTRow { Text(it, style = VTType.footnote, color = c.secondary) }
        }
    }
}

@Composable
private fun LinkRow(g: Glyph, title: String, onClick: () -> Unit) {
    val c = LocalVT.current
    VTRow(onClick = onClick) {
        GlyphIcon(g, c.accent, 20.dp)
        Text(title, style = VTType.body, color = c.accent, modifier = Modifier.padding(start = 16.dp))
    }
}

// ============================================================== Giới Thiệu

@Composable
fun GioiThieuTab() {
    val c = LocalVT.current
    val ctx = LocalContext.current
    DebugSection()
    VTSection(plain = true) {
        Column(Modifier.fillMaxWidth().padding(vertical = 8.dp), horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(10.dp)) {
            AppLogo(88.dp, 20.dp, shadow = true)
            Text("VietTelex", style = VTType.title2, color = c.label)
            Text("Bàn phím Telex tiếng Việt", style = VTType.subheadline, color = c.secondary)
        }
    }
    VTSection(header = "Tài nguyên") {
        LinkRow(Glyph.Globe, "Website") { openUrl(ctx, "https://ptrinh.github.io/viettelex/") }
        RowDivider(52.dp)
        LinkRow(Glyph.Cap, "Học gõ Telex") { openUrl(ctx, "https://ptrinh.github.io/viettelex/learn/") }
        RowDivider(52.dp)
        LinkRow(Glyph.Code, "Mã nguồn trên GitHub") { openUrl(ctx, "https://github.com/ptrinh/viettelex") }
    }
    VTSection(header = "Giới thiệu") {
        VTRow {
            Text("Phiên bản", style = VTType.body, color = c.label, modifier = Modifier.weight(1f))
            Text(remember { versionLine(ctx) }, style = VTType.body, color = c.secondary)
        }
        RowDivider()
        VTRow {
            Text("© Phil Trinh ${Calendar.getInstance().get(Calendar.YEAR)}", style = VTType.footnote, color = c.secondary, modifier = Modifier.weight(1f))
            Text("vt@trinh.uk", style = VTType.footnote, color = c.accent,
                modifier = Modifier.clickable { openUrl(ctx, "mailto:vt@trinh.uk") })
        }
        RowDivider()
        VTRow { Text("Không thu thập dữ liệu · Không theo dõi · Mã nguồn mở", style = VTType.footnote, color = c.secondary) }
        RowDivider()
        VTRow {
            Text("Android hiện cảnh báo \"có thể thu thập mọi văn bản bạn nhập\" khi bật bất kỳ bàn phím bên thứ ba nào. VietTelex chạy hoàn toàn trên máy, không gửi gì đi — quyền mạng chỉ dùng cho Mẫu câu động (https://) do bạn tạo.",
                style = VTType.footnote, color = c.secondary)
        }
    }
}

/** "1.1 · build dd/MM/yyyy" — Android không có mtime binary ⇒ dùng lần cài/cập nhật. */
private fun versionLine(ctx: Context): String {
    val t = runCatching { ctx.packageManager.getPackageInfo(ctx.packageName, 0).lastUpdateTime }.getOrDefault(System.currentTimeMillis())
    return "${BuildConfig.VERSION_NAME} · build ${SimpleDateFormat("dd/MM/yyyy", Locale.ROOT).format(Date(t))}"
}

/** Gỡ lỗi: log hiện NGAY trong section qua toggle (như iOS). */
@Composable
private fun DebugSection() {
    val c = LocalVT.current
    val ctx = LocalContext.current
    var debug by rememberBoolPref(Keys.DEBUG_TOUCH_LOG, Prefs.D.debugTouchLog)
    var showLog by remember { mutableStateOf(false) }
    var logText by remember { mutableStateOf("") }
    val logFile = remember { java.io.File(ctx.filesDir, Keys.TOUCHLOG_FILE) }
    VTSection(header = "Gỡ lỗi") {
        SettingToggle("Debug mode — ghi log chạm phím",
            "Ghi thời điểm chạm, độ trễ và số phím vào log trong app — KHÔNG ghi nội dung bạn gõ. Tắt + Xoá log khi xong.", debug) { debug = it }
        if (debug) {
            RowDivider()
            SettingToggle("Hiện log (tự copy vào clipboard)",
                "Bật để xem log bên dưới và copy toàn bộ — tắt rồi bật lại để tải log mới.", showLog) { on ->
                showLog = on
                if (on) {
                    logText = runCatching { logFile.readText() }.getOrDefault("")
                    if (logText.isNotEmpty()) {
                        ctx.getSystemService(ClipboardManager::class.java)
                            .setPrimaryClip(ClipData.newPlainText("VietTelex log", logText))
                    }
                }
            }
            RowDivider()
            SettingToggle("Xoá log", "Bật để xoá log cũ trước khi thử lại.", false) { on ->
                if (on) { logFile.delete(); logText = "" }
            }
            if (showLog) {
                RowDivider()
                val lines = logText.split('\n').filter { it.isNotEmpty() }
                SelectionContainer(Modifier.padding(horizontal = 16.dp, vertical = 11.dp)) {
                    Text(
                        if (logText.isEmpty()) "Chưa có log. Chọn bàn phím VietTelex rồi gõ thử ở app bất kỳ."
                        else "${lines.size} dòng — đã copy vào clipboard.\n\n" + lines.takeLast(80).joinToString("\n"),
                        style = TextStyle(fontFamily = FontFamily.Monospace, fontSize = 11.sp, lineHeight = 14.sp, color = c.label),
                    )
                }
            }
        }
    }
}
