package com.viettelex.android.ui

import android.content.Context
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.relocation.BringIntoViewRequester
import androidx.compose.foundation.relocation.bringIntoViewRequester
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Text
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import com.viettelex.keyboard.Keys
import com.viettelex.keyboard.ShortcutFile
import com.viettelex.keyboard.ShortcutOrder
import com.viettelex.keyboard.ShortcutTable
import com.viettelex.keyboard.tr

/**
 * Gõ tắt — bảng lưu pref [Keys.SHORTCUTS] dạng CHÍNH file YAML macOS ([ShortcutFile]); IME
 * đọc qua KeyboardSettings.load (đổi lúc bàn phím đang mở ⇒ áp ngay, [Keys.ENGINE_KEYS]).
 */
object ShortcutsStore {
    fun load(ctx: Context): Map<String, String> = ShortcutFile.parse(Prefs.of(ctx).getString(Keys.SHORTCUTS, null))
    /** Mốc thêm/sửa ([ShortcutOrder]) — danh sách "mới nhất trước". */
    fun loadTimes(ctx: Context): Map<String, Long> = ShortcutOrder.fromPref(Prefs.of(ctx).getString(Keys.SHORTCUTS_ADDED, null))

    /** Ghi bảng + mốc: khoá mới / đổi nội dung so với bảng đang lưu ⇒ lên đầu; khoá đã xoá ⇒ bỏ mốc. */
    fun save(ctx: Context, t: Map<String, String>): Map<String, Long> {
        val times = ShortcutOrder.updated(loadTimes(ctx), load(ctx), t, System.currentTimeMillis())
        Prefs.of(ctx).edit().putString(Keys.SHORTCUTS, ShortcutFile.exportYAML(t))
            .putString(Keys.SHORTCUTS_ADDED, ShortcutOrder.toPref(times)).apply()
        return times
    }
}

/** Section trong Tính Năng: bật/tắt + mở trang quản lý. */
@Composable
fun ShortcutsSection(onOpen: () -> Unit) {
    val c = LocalVT.current
    val ctx = LocalContext.current
    var enabled by rememberBoolPref(Keys.SHORTCUTS_ENABLED, Prefs.D.shortcutsEnabled)
    val count = remember { ShortcutsStore.load(ctx).size }
    VTSection(header = tr("Gõ tắt")) {
        SettingToggle(tr("Gõ tắt"), tr(SettingCaption.shortcuts), enabled) { enabled = it }
        RowDivider()
        VTRow(onClick = onOpen) {
            Text(tr("Bảng gõ tắt"), style = VTType.body, color = c.label, modifier = Modifier.weight(1f))
            Text(if (count == 0) tr("Trống  ›") else tr("%s mục  ›", count), style = VTType.body, color = c.secondary)
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun ShortcutsPage(onBack: () -> Unit) {
    val c = LocalVT.current
    val ctx = LocalContext.current
    BackHandler(onBack = onBack)
    var table by remember { mutableStateOf(ShortcutsStore.load(ctx)) }
    var times by remember { mutableStateOf(ShortcutsStore.loadTimes(ctx)) }
    /** Mục vừa thêm/sửa: cuộn tới + tô nền một lúc. */
    var highlight by remember { mutableStateOf<String?>(null) }
    var query by rememberSaveable { mutableStateOf("") }
    var newKey by rememberSaveable { mutableStateOf("") }
    var newValue by rememberSaveable { mutableStateOf("") }
    var editing by remember { mutableStateOf<String?>(null) }
    var editKey by remember { mutableStateOf("") }
    var editValue by remember { mutableStateOf("") }
    var notice by remember { mutableStateOf<String?>(null) }
    fun persist(t: Map<String, String>) { times = ShortcutsStore.save(ctx, t); table = t }

    VTRow(onClick = onBack) { Text(tr("‹ Tính Năng"), style = VTType.body, color = c.accent) }

    val q = query.trim().lowercase()
    val rows = ShortcutOrder.sorted(table.keys, times).filter { q.isEmpty() || it.lowercase().contains(q) || table.getValue(it).lowercase().contains(q) }
    VTSection(header = tr("Bảng gõ tắt (%s)", table.size), footer = tr("Mới thêm hoặc vừa sửa ở đầu danh sách. Chạm một dòng để sửa hoặc xoá.")) {
        VTRow { VTTextField(query, { query = it }, tr("Tìm chữ tắt hoặc nội dung…"), capitalization = KeyboardCapitalization.None) }
        rows.forEach { k ->
            key(k) {
                RowDivider()
                if (editing == k) {
                    Column(Modifier.padding(horizontal = 16.dp, vertical = 11.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        VTTextField(editKey, { editKey = it }, tr("Chữ tắt"), capitalization = KeyboardCapitalization.None)
                        VTTextField(editValue, { editValue = it }, tr("Nội dung"), maxLines = 6)
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(tr("Lưu"), style = VTType.body, color = c.accent, modifier = Modifier.clickable {
                                val nk = editKey.trim(); val nv = editValue.trim()
                                when {
                                    !ShortcutTable.isValidKey(nk) -> notice = tr("Chữ tắt không được chứa khoảng trắng.")
                                    nv.isEmpty() -> {}
                                    nk != k && table.containsKey(nk) -> notice = tr("“%s” đã có.", nk)
                                    else -> { persist(table - k + (nk to nv)); editing = null; notice = null; highlight = nk }
                                }
                            })
                            Text(tr("Xoá"), style = VTType.body, color = c.red, modifier = Modifier.padding(start = 24.dp).clickable {
                                persist(table - k); editing = null
                            })
                            Box(Modifier.weight(1f))
                            Text(tr("Huỷ"), style = VTType.body, color = c.secondary, modifier = Modifier.clickable { editing = null })
                        }
                    }
                } else {
                    val req = remember { BringIntoViewRequester() }
                    if (highlight == k) LaunchedEffect(k) {
                        req.bringIntoView()
                        kotlinx.coroutines.delay(1600)
                        if (highlight == k) highlight = null
                    }
                    VTRow(onClick = { editKey = k; editValue = table.getValue(k); editing = k },
                        modifier = Modifier.bringIntoViewRequester(req)
                            .then(if (highlight == k) Modifier.background(c.accent.copy(alpha = 0.18f)) else Modifier)) {
                        Text(k, style = VTType.body.copy(fontFamily = FontFamily.Monospace), color = c.label)
                        Text("→", style = VTType.footnote, color = c.secondary, modifier = Modifier.padding(horizontal = 8.dp))
                        Text(table.getValue(k), style = VTType.body, color = c.label, maxLines = 3, modifier = Modifier.weight(1f))
                    }
                }
            }
        }
        if (table.isEmpty()) {
            RowDivider()
            VTRow { Text(tr("Chưa có gõ tắt nào. Thêm bên dưới, hoặc bấm “Thêm bộ gợi ý”."), style = VTType.body, color = c.secondary) }
        } else if (rows.isEmpty()) {
            RowDivider()
            VTRow { Text(tr("Không tìm thấy."), style = VTType.body, color = c.secondary) }
        }
    }

    VTSection(header = tr("Thêm mới"),
        footer = tr("Bung khi gõ dấu cách, Enter hoặc dấu câu ngay sau chữ tắt. Viết chữ tắt thường để tự theo hoa/thường khi gõ. Chữ tắt có ký hiệu hoặc số (->, k2) bung khi gõ dấu cách. Không bung khi dính liền sau số hoặc / # @ (5h, /h3), trong ô mật khẩu, email, địa chỉ web.")) {
        VTRow { VTTextField(newKey, { newKey = it }, tr("Chữ tắt (vd: ko, cty, ->)"), capitalization = KeyboardCapitalization.None) }
        RowDivider()
        VTRow { VTTextField(newValue, { newValue = it }, tr("Nội dung đầy đủ (được nhiều dòng)"), maxLines = 6) }
        RowDivider()
        val canAdd = newKey.isNotBlank() && newValue.isNotBlank()
        VTRow(onClick = if (canAdd) ({
            val k = newKey.trim(); val v = newValue.trim()
            when {
                !ShortcutTable.isValidKey(k) -> notice = tr("Chữ tắt không được chứa khoảng trắng.")
                table.containsKey(k) -> notice = tr("“%s” đã có — chạm dòng đó để sửa.", k)
                else -> { persist(table + (k to v)); newKey = ""; newValue = ""; notice = null; query = ""; highlight = k }
            }
        }) else null) {
            GlyphIcon(Glyph.Plus, if (canAdd) c.accent else c.tertiary, 20.dp)
            Text(tr("Thêm"), style = VTType.body, color = if (canAdd) c.accent else c.tertiary, modifier = Modifier.padding(start = 16.dp))
        }
        notice?.let {
            RowDivider()
            VTRow { Text(it, style = VTType.footnote, color = c.secondary) }
        }
    }

    val importer = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        val text = runCatching { ctx.contentResolver.openInputStream(uri)?.use { it.bufferedReader().readText() } }.getOrNull()
        if (text == null) { notice = tr("Không đọc được file."); return@rememberLauncherForActivityResult }
        val imported = ShortcutFile.parse(text)
        if (imported.isEmpty()) { notice = tr("File không có gõ tắt nào."); return@rememberLauncherForActivityResult }
        val (merged, added, replaced) = ShortcutFile.merge(table, imported)
        persist(merged)
        notice = tr("Đã nhập %s mục: %s mới, %s ghi đè.", imported.size, added, replaced)
    }
    val exporter = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/x-yaml")) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        val ok = runCatching {
            ctx.contentResolver.openOutputStream(uri, "wt")!!.use { it.write(ShortcutFile.exportYAML(table).toByteArray()) }
        }.isSuccess
        notice = if (ok) tr("Đã xuất %s gõ tắt.", table.size) else tr("Không ghi được file.")
    }
    VTSection(footer = tr("Bộ gợi ý: %s. File YAML “chữ tắt: nội dung” dùng chung với VietTelex trên Mac và iPhone; nhập sẽ gộp (mục trùng lấy theo file).", ShortcutFile.SUGGESTED.keys.sorted().joinToString(", "))) {
        VTRow(onClick = {
            val missing = ShortcutFile.SUGGESTED.filterKeys { it !in table }
            persist(table + missing)
            notice = if (missing.isEmpty()) tr("Bộ gợi ý đã có đủ.") else tr("Đã thêm %s gõ tắt gợi ý.", missing.size)
        }) {
            Text("✦", color = c.accent, modifier = Modifier.size(20.dp))
            Text(tr("Thêm bộ gợi ý"), style = VTType.body, color = c.accent, modifier = Modifier.padding(start = 16.dp))
        }
        RowDivider(52.dp)
        VTRow(onClick = { importer.launch(arrayOf("*/*")) }) {
            GlyphIcon(Glyph.Import, c.accent, 20.dp)
            Text(tr("Nhập từ file…"), style = VTType.body, color = c.accent, modifier = Modifier.padding(start = 16.dp))
        }
        RowDivider(52.dp)
        VTRow(onClick = if (table.isEmpty()) null else ({ exporter.launch("viettelex-go-tat.yml") })) {
            GlyphIcon(Glyph.Export, if (table.isEmpty()) c.tertiary else c.accent, 20.dp)
            Text(tr("Xuất ra YAML…"), style = VTType.body, color = if (table.isEmpty()) c.tertiary else c.accent,
                modifier = Modifier.padding(start = 16.dp))
        }
    }
}
