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
import androidx.compose.runtime.LaunchedEffect
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
import com.viettelex.keyboard.KeyAlternates
import com.viettelex.keyboard.Keys
import com.viettelex.keyboard.RetroEnglishUI
import com.viettelex.keyboard.TemplateItem
import com.viettelex.keyboard.Templates
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import com.viettelex.keyboard.tr
import com.viettelex.keyboard.L10n


internal fun openUrl(ctx: Context, url: String) {
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
        header = tr("Thử gõ"),
        footer = tr("Chọn Tiếng Việt (VietTelex) — bấm biểu tượng bàn phím ở thanh điều hướng — rồi gõ thử: vieejt → việt."),
    ) {
        var text by rememberSaveable { mutableStateOf("") }
        // KHÔNG tắt autoCorrect: bàn phím coi ô "không gợi ý/không sửa" là passthrough (như iOS).
        VTTextField(text, { text = it }, tr("Thử gõ tại đây…"), minLines = 1, maxLines = 4,
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 11.dp))
    }
    KieuGoSection()
}

/** Ô nhập kiểu iOS (không gạch chân Material). */
@Composable
fun VTTextField(
    value: String, onChange: (String) -> Unit, placeholder: String,
    minLines: Int = 1, maxLines: Int = 1, center: Boolean = false, modifier: Modifier = Modifier,
    capitalization: KeyboardCapitalization = KeyboardCapitalization.Sentences,
) {
    val c = LocalVT.current
    val style = VTType.body.copy(color = c.label, textAlign = if (center) TextAlign.Center else TextAlign.Start)
    BasicTextField(
        value, onChange, modifier.fillMaxWidth(),
        textStyle = style, minLines = minLines, maxLines = maxLines, singleLine = maxLines == 1,
        cursorBrush = SolidColor(c.accent),
        keyboardOptions = KeyboardOptions(capitalization = capitalization),
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
                    Text(tr("Bàn phím đã bật"), style = VTType.headline, color = c.label)
                    Text(tr("Thử gõ ngay bên dưới."), style = VTType.subheadline, color = c.secondary)
                }
            }
            return@Column
        }
        AppLogo(64.dp, 14.dp)
        Text(tr("Bật bàn phím VietTelex"), style = VTType.title3, color = c.label)
        Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Step(1, tr("Bật bàn phím trong Cài đặt"), ime.enabled)
            if (!ime.enabled) {
                Column(Modifier.padding(start = 30.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Note(tr("Cài đặt → Hệ thống → Ngôn ngữ & nhập liệu"))
                    Note(tr("Bàn phím trên màn hình → Quản lý → bật VietTelex"))
                    Note(tr("Khi bật, Android hiện cảnh báo bàn phím “có thể thu thập mọi văn bản bạn nhập”."), c.tertiary)
                    Note(tr("Cảnh báo này hiện với mọi bàn phím bên thứ ba — VietTelex chạy hoàn toàn trên máy, không gửi gì đi."), c.tertiary)
                }
            }
            Step(2, tr("Chọn VietTelex làm bàn phím"), ime.selected)
            if (ime.enabled) {
                Note(tr("Khi gõ, bấm biểu tượng bàn phím ở thanh điều hướng để chuyển sang VietTelex"), modifier = Modifier.padding(start = 30.dp))
            }
            Step(3, tr("Thử gõ ngay bên dưới"), false)
        }
        if (!ime.enabled) ProminentButton(tr("Mở Cài đặt"), onOpenImeSettings)
        else ProminentButton(tr("Chọn VietTelex"), onPickIme)
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
internal fun BoolToggle(key: String, default: Boolean, title: String, caption: String) {
    var v by rememberBoolPref(key, default)
    SettingToggle(title, caption, v) { v = it }
}

/**
 * Telex / VNI — hai kiểu gõ loại trừ nhau ⇒ segmented (như radio macOS / Picker iOS). Chọn
 * VNI TỰ BẬT hàng phím số (số là phím dấu; không có hàng số thì mỗi dấu phải chuyển ?123),
 * tắt lại được ở Tính năng → Phím & cử chỉ.
 */
@Composable
private fun InputMethodPicker(vni: Boolean, onChange: (Boolean) -> Unit) {
    val c = LocalVT.current
    VTRow {
        Text(tr("Kiểu gõ"), style = VTType.body, color = c.label, modifier = Modifier.weight(1f))
        Row(Modifier.clip(RoundedCornerShape(9.dp)).background(c.fill).padding(2.dp)) {
            for ((label, isVni) in listOf("Telex" to false, "VNI" to true)) {
                val sel = vni == isVni
                Box(
                    Modifier.clip(RoundedCornerShape(7.dp))
                        .background(if (sel) c.card else Color.Transparent)
                        .clickable { onChange(isVni) }
                        .padding(horizontal = 18.dp, vertical = 6.dp),
                ) { Text(label, style = VTType.body, color = c.label) }
            }
        }
    }
}

@Composable
private fun KieuGoSection() {
    var vni by rememberBoolPref(Keys.VNI_MODE, Prefs.D.vniMode)
    var numberRow by rememberBoolPref(Keys.NUMBER_ROW, Prefs.D.numberRow)
    VTSection(header = tr("Kiểu gõ"), footer = APPLY_NOTE) {
        InputMethodPicker(vni) { v ->
            if (v && !vni) numberRow = true
            vni = v
        }
        RowDivider()
        if (vni) {
            VTRow {
                Note(tr("Gõ dấu bằng số khi đang gõ một từ: 1 sắc, 2 huyền, 3 hỏi, 4 ngã, 5 nặng, 6 mũ (â ê ô), 7 móc (ơ ư), 8 trăng (ă), 9 đ, 0 xoá dấu — tie6ng1 vie6t5 → tiếng việt. Ngoài từ, phím số vẫn gõ ra số (cả bàn phím cứng). Chọn VNI tự bật Hàng phím số (tắt được ở Tính năng → Phím & cử chỉ)."))
            }
            RowDivider()
        } else {
            BoolToggle(Keys.SIMPLE_TELEX, Prefs.D.simpleTelex, tr("Telex đơn giản"), tr("Phím w đứng lẻ giữ nguyên là w, không thành ư."))
            RowDivider()
            BoolToggle(Keys.FREE_MARKING, Prefs.D.freeMarking, tr("Bỏ dấu tự do"), tr("Phím dấu đặt đâu cũng được, không cần đúng thứ tự."))
            RowDivider()
            BoolToggle(Keys.QUICK_TELEX, Prefs.D.quickTelex, tr("Gõ nhanh (Quick Telex)"), tr("Phụ âm đôi đầu từ thành phụ âm ghép: cc → ch, nn → ng, tt → th…"))
            RowDivider()
        }
        BoolToggle(Keys.MODERN_TONE, Prefs.D.modernTone, tr("Bỏ dấu kiểu mới"), tr("hoà, thuý thay vì hòa, thúy."))
        RowDivider()
        BoolToggle(Keys.AUTO_CAPITALIZE, Prefs.D.autoCapitalize, tr("Tự động viết hoa đầu câu"), tr("Bật shift ở đầu ô, sau . ! ? và khi xuống dòng."))
        RowDivider()
        BoolToggle(Keys.CONTEXTUAL_ENGLISH, Prefs.D.contextualEnglish, tr("Quyết định theo ngữ cảnh"), tr("Sau một từ tiếng Anh, từ nhập nhằng kế tiếp mà chuỗi phím tạo thành một từ tiếng Anh sẽ được giữ tiếng Anh thay vì tiếng Việt — “he is” → “he is”, không phải “he í”. Sau từ tiếng Việt hoặc không rõ thì để tiếng Việt — “sao í”."))
        // "Tự sửa từ phía trước" (thử nghiệm): chỉ hiện khi "Quyết định theo ngữ cảnh" bật — như iOS.
        val contextual by rememberBoolPref(Keys.CONTEXTUAL_ENGLISH, Prefs.D.contextualEnglish)
        if (RetroEnglishUI.switchVisible(contextual, vni)) {
            RowDivider()
            ExperimentalToggle(Keys.RETRO_ENGLISH_AUTO, Prefs.D.retroEnglishAuto, tr("Tự sửa từ phía trước"),
                tr("Khi bạn gõ tiếp một câu tiếng Anh, tự sửa các từ vừa bị bỏ dấu nhầm (vd. \"Hí cả í very fast\" → \"His car is very fast\")."))
        }

        // Sửa dấu từ đã gõ chuyển sang Tính Năng → Chính tả & sửa lỗi (giống iOS, 27/09/2026).
        RowDivider()
        BoolToggle(Keys.AUTO_FIX_ADJACENT, Prefs.D.autoFixAdjacent, tr("Gợi ý sửa lỗi chạm trượt"), tr("Khi từ đang gõ không phải tiếng Việt, gợi ý từ đúng nếu bạn lỡ chạm phím bên cạnh: nbjeeuf → nhiều, ohims → phím, cahcs → cách. Chạm gợi ý để thay."))
        if (!vni) {
            RowDivider()
            BoolToggle(Keys.TEENCODE, Prefs.D.teencode, tr("Chính tả teencode"), tr("Chấp nhận cách viết khi chat: w/z/k thay cho qu/d/c (wá, zui zẻ, kó) và bíe, thík, gòy, ừk. Tắt = chỉ chính tả chuẩn, từ tiếng Anh như was, war, zoo giữ nguyên."))
        }
    }
}

// ============================================================== Tính Năng
// TinhNangTab + các trang con ở FeaturePages.kt.

/** Chế độ một tay: Tắt / Trái / Phải (điện thoại; tablet bàn phím bỏ qua). */
@Composable
internal fun OneHandRow() {
    val c = LocalVT.current
    val ctx = LocalContext.current
    var mode by rememberStringPref(Keys.ONE_HAND_MODE, Prefs.D.oneHandMode)
    VTRow {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(tr("Chế độ một tay"), style = VTType.body, color = c.label)
            Text(tr("Thu hẹp bàn phím về một bên cho dễ gõ bằng một tay (chỉ điện thoại). Trên bàn phím: giữ lâu icon con trỏ trên thanh gợi ý để bật/tắt; nút ở dải trống để đổi bên hoặc thoát."),
                style = VTType.footnote, color = c.secondary)
        }
    }
    Row(Modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, bottom = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        for ((v, t) in listOf("off" to tr("Tắt"), "left" to tr("Trái"), "right" to tr("Phải"))) {
            val on = mode == v
            Box(Modifier.weight(1f)
                .background(if (on) c.accent else c.secondary.copy(alpha = 0.12f), RoundedCornerShape(10.dp))
                .clickable {
                    mode = v
                    if (v != "off") Prefs.of(ctx).edit().putString(Keys.ONE_HAND_LAST, v).apply()
                }
                .padding(vertical = 8.dp), contentAlignment = Alignment.Center) {
                Text(t, style = VTType.body, color = if (on) Color.White else c.label)
            }
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
    /** Kết quả bấm ⊕ ở "Thêm mới" — hiện ngay dưới ô nhập. */
    var addNotice by remember { mutableStateOf<String?>(null) }
    var editing by remember { mutableStateOf<Int?>(null) }
    var editLabel by remember { mutableStateOf("") }
    var editText by remember { mutableStateOf("") }
    fun persist(list: List<TemplateItem>) { templates = list; TemplatesStore.save(ctx, list) }
    fun importText(text: String?) {
        val items = Templates.parseImport(text)
        if (items.isEmpty()) { notice = tr("Không tìm thấy mẫu câu nào để thêm."); return }
        val (merged, msg) = Templates.merge(templates, items)
        persist(merged)
        notice = msg
    }
    // Chữ chia sẻ từ app khác (MainActivity nhận ACTION_SEND) ⇒ gộp thêm như Import.
    val shared = SharedImport.pending.value
    LaunchedEffect(shared) {
        if (shared != null) { SharedImport.pending.value = null; importText(shared) }
    }

    VTSection(
        header = tr("Mẫu câu (%s)", templates.size),
        footer = tr("Bấm ☰ trên bàn phím để chèn nhanh. Chạm một dòng để sửa, vuốt trái để xoá. Label (emoji/chữ ngắn) giúp bubble trên bàn phím gọn hơn."),
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
                            VTTextField(editText, { editText = it }, tr("Mẫu câu"), maxLines = 4, modifier = Modifier.weight(1f))
                            Box(
                                Modifier.padding(start = 8.dp).size(28.dp).clickable(enabled = canSave) {
                                    val r = Templates.edit(templates, i, editLabel, editText)
                                    if (r != null) { persist(r); editing = null } else addNotice = tr("Không lưu được: mẫu câu này trùng một dòng khác.")
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
        if (templates.isEmpty()) VTRow { Text(tr("Chưa có mẫu câu nào."), style = VTType.body, color = c.secondary) }
    }

    VTSection(header = tr("Thêm mới"), footer = tr("Ô nhỏ bên trái là label (không bắt buộc).")) {
        val trimmed = newText.trim()
        val canAdd = trimmed.isNotEmpty()
        VTRow {
            VTTextField(newLabel, { newLabel = it; addNotice = null }, "👋", center = true, modifier = Modifier.width(44.dp))
            Box(Modifier.padding(horizontal = 10.dp).width(0.5.dp).height(28.dp).background(c.separator))
            VTTextField(newText, { newText = it; addNotice = null }, tr("Thêm mẫu câu…"), maxLines = 3, modifier = Modifier.weight(1f))
            Box(
                // Luôn bấm được: không thêm ⇒ báo lý do (không im lặng — lỗi iOS 27/09/2026).
                Modifier.padding(start = 8.dp).size(28.dp).clickable {
                    when (val r = Templates.tryAdd(templates, newLabel, newText)) {
                        is Templates.AddResult.Added -> {
                            persist(r.list)
                            newLabel = ""; newText = ""
                            addNotice = tr("Đã thêm mẫu câu (dòng %s).", r.list.size)
                        }
                        else -> addNotice = Templates.addNotice(r)
                    }
                },
                contentAlignment = Alignment.Center,
            ) { GlyphIcon(Glyph.Plus, if (canAdd) c.accent else c.tertiary, 24.dp) }
        }
        addNotice?.let {
            RowDivider()
            VTRow { Text(it, style = VTType.footnote, color = c.secondary) }
        }
    }

    VTSection(
        header = tr("Mẫu câu động (https://)"),
        footer = tr("Mẫu có nội dung bắt đầu bằng https:// sẽ fetch dữ liệu NGAY LÚC BẤM và chèn kết quả (tối đa 1000 bytes) — ví dụ 🌐 IP chèn địa chỉ IP hiện tại. Không có mạng thì bấm sẽ chèn chính URL."),
        plain = true,
    ) {}

    val importer = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        val text = runCatching { ctx.contentResolver.openInputStream(uri)?.use { it.bufferedReader().readText() } }.getOrNull()
        if (text == null) { notice = tr("Không đọc được file."); return@rememberLauncherForActivityResult }
        importText(text)
    }
    val exporter = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/x-yaml")) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        val ok = runCatching {
            ctx.contentResolver.openOutputStream(uri, "wt")!!.use { it.write(Templates.exportYAML(templates).toByteArray()) }
        }.isSuccess
        notice = if (ok) tr("Đã export %s mẫu.", templates.size) else tr("Không ghi được file.")
    }
    VTSection(footer = tr("YAML phẳng, mỗi dòng “- \"👋 | Chào buổi sáng\"” (label | câu) hoặc “- \"câu\"”. Import gộp thêm, không thay thế. Cũng có thể chia sẻ chữ từ app khác vào VietTelex để thêm thành mẫu câu.")) {
        LinkRow(Glyph.Import, "Import…") { importer.launch(arrayOf("*/*")) }
        RowDivider(52.dp)
        LinkRow(Glyph.Export, tr("Export ra YAML…")) { exporter.launch("viettelex-mau-cau.yaml") }
        notice?.let {
            RowDivider()
            VTRow { Text(it, style = VTType.footnote, color = c.secondary) }
        }
    }
}

@Composable
internal fun LinkRow(g: Glyph, title: String, onClick: () -> Unit) {
    val c = LocalVT.current
    VTRow(onClick = onClick) {
        GlyphIcon(g, c.accent, 20.dp)
        Text(title, style = VTType.body, color = c.accent, modifier = Modifier.padding(start = 16.dp))
    }
}

// ============================================================== Giới Thiệu

@Composable
fun GioiThieuTab(plus: com.viettelex.android.plus.PlusController, onOpenPlus: () -> Unit) {
    val c = LocalVT.current
    val ctx = LocalContext.current
    // Sao lưu & đồng bộ chuyển sang Tính Năng (27/09/2026).
    VTSection(plain = true) {
        Column(Modifier.fillMaxWidth().padding(vertical = 8.dp), horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(10.dp)) {
            AppLogo(88.dp, 20.dp, shadow = true)
            Text("VietTelex", style = VTType.title2, color = c.label)
            Text(tr("Bàn phím Telex tiếng Việt"), style = VTType.subheadline, color = c.secondary)
        }
    }
    PlusEntryRow(plus, onOpenPlus)
    VTSection(header = tr("Tài nguyên")) {
        LinkRow(Glyph.Info, tr("Hướng dẫn sử dụng")) { openUrl(ctx, L10n.guideUrl("android")) }
        RowDivider(52.dp)
        LinkRow(Glyph.Globe, "Website") { openUrl(ctx, "https://ptrinh.github.io/viettelex/") }
        RowDivider(52.dp)
        LinkRow(Glyph.Cap, tr("Học gõ Telex")) { openUrl(ctx, "https://ptrinh.github.io/viettelex/learn/") }
        RowDivider(52.dp)
        LinkRow(Glyph.Code, tr("Mã nguồn trên GitHub")) { openUrl(ctx, "https://github.com/ptrinh/viettelex") }
    }
    VTSection(header = tr("Giới thiệu")) {
        VTRow {
            Text(tr("Phiên bản"), style = VTType.body, color = c.label, modifier = Modifier.weight(1f))
            Text(remember { versionLine(ctx) }, style = VTType.body, color = c.secondary)
        }
        RowDivider()
        VTRow {
            Text("© Phil Trinh ${Calendar.getInstance().get(Calendar.YEAR)}", style = VTType.footnote, color = c.secondary, modifier = Modifier.weight(1f))
            Text("vt@trinh.uk", style = VTType.footnote, color = c.accent,
                modifier = Modifier.clickable { openUrl(ctx, "mailto:vt@trinh.uk") })
        }
        RowDivider()
        VTRow { Text(tr("Không thu thập dữ liệu · Không theo dõi · Mã nguồn mở"), style = VTType.footnote, color = c.secondary) }
        RowDivider()
        // Ghi công theo giấy phép dữ liệu bigram gõ vuốt (vnlm.bin) — docs/DATA-SOURCES.md
        VTRow(onClick = { openUrl(ctx, "https://github.com/ptrinh/viettelex/blob/main/docs/DATA-SOURCES.md") }) {
            Text(tr("Dữ liệu gõ vuốt: thống kê từ Wikipedia, Wikisource… tiếng Việt (CC BY-SA 4.0) và Tatoeba (CC BY 2.0 FR)"),
                style = VTType.footnote, color = c.secondary)
        }
        RowDivider()
        VTRow {
            Text(tr("Android hiện cảnh báo \"có thể thu thập mọi văn bản bạn nhập\" khi bật bất kỳ bàn phím bên thứ ba nào. VietTelex chạy hoàn toàn trên máy, không gửi gì đi — quyền mạng chỉ dùng cho Mẫu câu động (https://) do bạn tạo."),
                style = VTType.footnote, color = c.secondary)
        }
    }
    // Gỡ lỗi ở CUỐI tab (maintainer 14/10/2026) — công cụ cho tester.
    DebugSection()
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
    VTSection(header = tr("Gỡ lỗi")) {
        SettingToggle(tr("Debug mode — ghi log chạm phím"),
            tr("Ghi thời điểm chạm, độ trễ và số phím vào log trong app — KHÔNG ghi nội dung bạn gõ. Tắt + Xoá log khi xong."), debug) { debug = it }
        if (debug) {
            RowDivider()
            SettingToggle(tr("Hiện log (tự copy vào clipboard)"),
                tr("Bật để xem log bên dưới và copy toàn bộ — tắt rồi bật lại để tải log mới."), showLog) { on ->
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
            SettingToggle(tr("Xoá log"), tr("Bật để xoá log cũ trước khi thử lại."), false) { on ->
                if (on) { logFile.delete(); logText = "" }
            }
            if (showLog) {
                RowDivider()
                val lines = logText.split('\n').filter { it.isNotEmpty() }
                SelectionContainer(Modifier.padding(horizontal = 16.dp, vertical = 11.dp)) {
                    Text(
                        if (logText.isEmpty()) tr("Chưa có log. Chọn bàn phím VietTelex rồi gõ thử ở app bất kỳ.")
                        else tr("%s dòng — đã copy vào clipboard.\n\n", lines.size) + lines.takeLast(80).joinToString("\n"),
                        style = TextStyle(fontFamily = FontFamily.Monospace, fontSize = 11.sp, lineHeight = 14.sp, color = c.label),
                    )
                }
            }
        }
    }
}
