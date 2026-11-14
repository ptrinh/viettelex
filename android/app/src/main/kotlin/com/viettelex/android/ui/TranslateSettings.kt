package com.viettelex.android.ui

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.viettelex.android.translate.MlKitBackend
import com.viettelex.android.translate.TranslateDownloadError
import com.viettelex.android.translate.TranslateFeature
import com.viettelex.keyboard.Keys
import com.viettelex.keyboard.L10n
import com.viettelex.keyboard.TranslateLangs
import com.viettelex.keyboard.tr

/**
 * Cài đặt "Dịch trên máy" (Plus) — Tính Năng → Gõ tắt & mẫu câu: chọn ngôn ngữ đích
 * (mọi ngôn ngữ ML Kit hỗ trợ), chỉ-Wi-Fi, rồi tải gói ngôn ngữ (~30 MB mỗi thứ tiếng) khi người
 * dùng bấm. ML Kit nằm sẵn trong app (#162: bỏ module Play Feature Delivery).
 */
@Composable
fun TranslateSettings(leadingDivider: Boolean = true) {
    val c = LocalVT.current
    val ctx = LocalContext.current
    var targetRaw by rememberStringPref(Keys.TRANSLATE_TARGET, TranslateLangs.DEFAULT_TARGET)
    val target = TranslateLangs.normalizeTarget(targetRaw)
    var wifiOnly by rememberBoolPref(Keys.TRANSLATE_WIFI_ONLY, true)
    var backend by remember { mutableStateOf<MlKitBackend?>(null) }
    var have by remember { mutableStateOf<Set<String>?>(null) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var picking by remember { mutableStateOf(false) }
    var refresh by remember { mutableStateOf(0) }
    var aiOn by rememberBoolPref(Keys.TRANSLATE_AI, false)
    var nanoReady by remember { mutableStateOf(false) }
    val ui = if (L10n.isEnglish) L10n.EN else L10n.VI     // đọc state ngôn ngữ ⇒ recompose khi đổi

    // Khởi tạo ML Kit chỉ khi trang này mở (không lúc khởi động process).
    LaunchedEffect(Unit) { backend = TranslateFeature.load(ctx) }
    LaunchedEffect(backend, refresh) { backend?.downloadedModels { have = it ?: emptySet() } }
    // Gemini Nano dùng được trên máy này? (AICore; máy không hỗ trợ ⇒ không hiện công tắc AI)
    LaunchedEffect(Unit) {
        val main = android.os.Handler(android.os.Looper.getMainLooper())
        com.viettelex.android.ai.GeminiNanoBridge.status(com.viettelex.android.ai.GeminiNano.executor) { ok -> main.post { nanoReady = ok } }
    }

    if (leadingDivider) RowDivider()
    VTRow(onClick = { picking = true }) {
        Text(tr("Dịch sang"), style = VTType.body, color = c.label, modifier = Modifier.weight(1f))
        Text(TranslateLangs.displayName(target, ui) + " ›", style = VTType.body, color = c.secondary)
    }
    RowDivider()
    VTRow {
        Text(tr("Chiều ngược lại: đoạn đã là %s sẽ dịch sang tiếng Việt.", TranslateLangs.displayName(target, ui)),
            style = VTType.footnote, color = c.secondary)
    }
    RowDivider()
    SettingToggle(tr("Chỉ tải qua Wi-Fi"), null, wifiOnly) { wifiOnly = it }
    RowDivider()
    if (nanoReady || aiOn) {
        SettingToggle(tr("Dịch bằng AI trên máy (thử nghiệm)"),
            tr("Gemini Nano dịch tự nhiên hơn, hiểu ngữ cảnh và thành ngữ nhưng chậm hơn; lỗi hoặc quá lâu thì dùng ML Kit. Vẫn chạy hoàn toàn trên máy."),
            aiOn) { aiOn = it }
        RowDivider()
    }

    val b = backend
    val ready = have?.containsAll(listOf(TranslateLangs.VI, target)) == true
    val status = when {
        b == null || have == null -> "…"
        busy -> tr("Đang tải gói dịch…")
        ready -> tr("✓ Đã có gói: Tiếng Việt + %s", TranslateLangs.displayName(target, ui))
        else -> tr("Tải gói dịch (Tiếng Việt + %s, %s)", TranslateLangs.displayName(target, ui), tr("~30 MB mỗi ngôn ngữ"))
    }
    VTRow(onClick = if (b == null || ready || busy || have == null) null else {
        {
            error = null
            // ML Kit chờ tới khi có Wi-Fi (không báo lỗi) ⇒ kiểm tra trước, khỏi treo "Đang tải…".
            if (wifiOnly && !ctx.onUnmeteredNetwork()) error = tr(TranslateDownloadError.NEED_WIFI)
            else {
                busy = true
                // English kèm theo (ML Kit đi vòng qua English) — đã có thì ML Kit bỏ qua ngay.
                val missing = linkedSetOf(TranslateLangs.VI, target, "en").filter { it == "en" || have?.contains(it) != true }
                b.downloadModels(missing, wifiOnly) { code ->
                    busy = false
                    if (code != null) error = TranslateDownloadError.text(code, wifiOnly, ::tr)
                    refresh++
                }
            }
        }
    }) {
        Text(status, style = VTType.body, color = if (ready) c.green else c.accent)
    }
    // Gói đã tải khác (đổi đích nhiều lần) — xoá để lấy lại chỗ. Không xoá tiếng Việt / đích hiện tại.
    val extra = have.orEmpty().filter { it != TranslateLangs.VI && it != target && it != "en" }
    if (b != null && extra.isNotEmpty()) {
        RowDivider()
        VTRow(onClick = {
            busy = true
            var left = extra.size
            for (l in extra) b.deleteModel(l) { if (--left == 0) { busy = false; refresh++ } }
        }) {
            Text(tr("Xoá gói không dùng (%s)", extra.joinToString { TranslateLangs.displayName(it, ui) }),
                style = VTType.body, color = c.accent)
        }
    }
    error?.let { e -> VTRow { Text(e, style = VTType.footnote, color = c.secondary) } }
    VTRow {
        Text(tr("Dịch chạy ngay trên máy bằng Google ML Kit — chữ bạn gõ không bao giờ được gửi đi. Mạng chỉ dùng khi bạn bấm tải gói."),
            style = VTType.footnote, color = c.secondary)
    }

    if (picking) AlertDialog(
        onDismissRequest = { picking = false },
        title = { Text(tr("Dịch sang")) },
        text = {
            LazyColumn(Modifier.heightIn(max = 420.dp)) {
                items(TranslateLangs.pickerOrder(ui)) { code ->
                    VTRow(onClick = { targetRaw = code; picking = false; error = null }) {
                        Column(Modifier.weight(1f)) {
                            Text(TranslateLangs.displayName(code, ui), style = VTType.body, color = c.label)
                        }
                        if (code == target) Text("✓", style = VTType.body, color = c.accent, modifier = Modifier.padding(start = 8.dp))
                        else if (have?.contains(code) == true) Text("↓", style = VTType.footnote, color = c.secondary)
                    }
                }
            }
        },
        confirmButton = { TextButton(onClick = { picking = false }) { Text(tr("Đóng"), color = c.accent) } },
    )
}

/** Mạng hiện tại không tính phí theo dung lượng (Wi-Fi / Ethernet) — cho "Chỉ tải qua Wi-Fi". */
private fun Context.onUnmeteredNetwork(): Boolean {
    val cm = getSystemService(ConnectivityManager::class.java) ?: return false
    val caps = cm.getNetworkCapabilities(cm.activeNetwork) ?: return false
    return caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED) ||
        caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)
}
