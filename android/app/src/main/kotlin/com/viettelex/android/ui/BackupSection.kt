package com.viettelex.android.ui

import android.content.Context
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.viettelex.keyboard.BackupCodec
import com.viettelex.keyboard.BackupException
import com.viettelex.keyboard.BackupPrefs
import com.viettelex.keyboard.Keys
import com.viettelex.keyboard.UserLangModel
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import com.viettelex.keyboard.tr

/**
 * Xuất/nhập file sao lưu một tệp (JSON, cùng định dạng iOS — [BackupCodec]) qua SAF.
 * Logic thuần ở module :keyboard ([BackupPrefs]); đây chỉ nối SharedPreferences + file.
 */
object BackupIO {
    private fun learnedFile(ctx: Context) = File(ctx.filesDir, Keys.USERLM_FILE)

    fun export(ctx: Context, includeLearned: Boolean): String {
        val all = Prefs.of(ctx).all
        val learned = if (includeLearned) UserLangModel.readLearned(learnedFile(ctx)) ?: com.viettelex.keyboard.LearnedWords() else null
        return BackupCodec.encode(BackupPrefs.snapshot({ all[it] }, TemplatesStore.load(ctx), learned))
    }

    /** Trả câu tóm tắt; ném [BackupException] nếu file không hợp lệ. */
    fun import(ctx: Context, text: String): String {
        val p = BackupCodec.decode(text)
        val sp = Prefs.of(ctx)
        val all = sp.all
        val plan = BackupPrefs.plan(p, { all[it] }, TemplatesStore.load(ctx))
        plan.learnedWords?.let { UserLangModel.mergeLearnedIntoFile(it, learnedFile(ctx)) }
        val e = sp.edit()
        for ((k, v) in plan.writes) when (v) {
            is Boolean -> e.putBoolean(k, v)
            is Int -> e.putInt(k, v)
            is String -> e.putString(k, v)
        }
        // IME (cùng process) thấy mốc đổi ⇒ nạp lại userlm.bin vừa gộp, không ghi đè bằng bảng cũ.
        if (plan.learnedWords != null) e.putLong(Keys.USERLM_RESET_AT, System.currentTimeMillis())
        e.apply()
        plan.templates?.let { TemplatesStore.save(ctx, it) }
        return plan.summary
    }
}

@Composable
fun SaoLuuSection(onOpenPlus: () -> Unit = {}) {
    val c = LocalVT.current
    val ctx = LocalContext.current
    /** Sao lưu chỉ mang JSON theme (không mang tệp tải về) ⇒ khôi phục xong HỎI tải lại tệp còn thiếu. */
    val assetPrompt = rememberAssetPrompt()
    var includeLearned by rememberBoolPref(BackupPrefs.INCLUDE_LEARNED_KEY, false)
    var notice by remember { mutableStateOf<String?>(null) }

    val exporter = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/json")) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        val ok = runCatching {
            val json = BackupIO.export(ctx, includeLearned)
            ctx.contentResolver.openOutputStream(uri, "wt")!!.use { it.write(json.toByteArray()) }
        }.isSuccess
        notice = if (ok) tr("Đã xuất file sao lưu.") else tr("Không ghi được file.")
    }
    val importer = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        val text = runCatching { ctx.contentResolver.openInputStream(uri)?.use { it.bufferedReader().readText() } }.getOrNull()
        notice = when {
            text == null -> tr("Không đọc được file.")
            else -> try {
                BackupIO.import(ctx, text).also {
                    ThemeAssetFlow.gcAsync(ctx)
                    assetPrompt.offer(ctx, loadThemeSettings(ctx).effectiveKeyStyle.assets)
                }
            } catch (e: BackupException) { e.userMessage }
        }
    }

    VTSection(header = tr("File sao lưu"),
        footer = tr(SettingCaption.backupFile)) {
        SettingToggle(tr("Kèm từ đã học khi xuất file"),
            tr(SettingCaption.includeLearned), includeLearned) { includeLearned = it }
        RowDivider()
        LinkRow(Glyph.Export, tr("Xuất file sao lưu…")) {
            val day = SimpleDateFormat("yyyy-MM-dd", Locale.ROOT).format(Date())
            exporter.launch("viettelex-sao-luu-$day.json")
        }
        RowDivider(52.dp)
        LinkRow(Glyph.Import, tr("Nhập file sao lưu…")) { importer.launch(arrayOf("application/json", "text/*", "application/octet-stream")) }
        notice?.let {
            RowDivider()
            VTRow { Text(it, style = VTType.footnote, color = c.secondary) }
        }
    }
    ThemeAssetPromptHost(assetPrompt, onOpenPlus)
}
