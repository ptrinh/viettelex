package com.viettelex.android.ui

import android.app.Activity
import android.content.Intent
import android.net.Uri
import com.viettelex.android.translate.TranslateDownloadError
import android.content.Context
import android.content.ContextWrapper
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
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.google.android.play.core.splitinstall.SplitInstallException
import com.google.android.play.core.splitinstall.SplitInstallManagerFactory
import com.google.android.play.core.splitinstall.SplitInstallRequest
import com.google.android.play.core.splitinstall.SplitInstallStateUpdatedListener
import com.google.android.play.core.splitinstall.model.SplitInstallSessionStatus
import com.viettelex.android.translate.TranslateBackend
import com.viettelex.android.translate.TranslateFeature
import com.viettelex.keyboard.Keys
import com.viettelex.keyboard.L10n
import com.viettelex.keyboard.TranslateLangs
import com.viettelex.keyboard.tr

/**
 * Cài đặt "Dịch trên máy" (Plus) — Tính Năng → Gõ tắt & mẫu câu: chọn ngôn ngữ đích
 * (mọi ngôn ngữ ML Kit hỗ trợ), chỉ-Wi-Fi, rồi hai bước tải do người dùng bấm:
 *  1. module `:translate` (Play Feature Delivery, on-demand — ML Kit không có trong APK gốc);
 *  2. gói ngôn ngữ (~30 MB mỗi thứ tiếng).
 * Gọi chỉ khi [TranslateFeature.offered] (APK ngoài Play: ẩn hẳn).
 */
@Composable
fun TranslateSettings(leadingDivider: Boolean = true) {
    val c = LocalVT.current
    val ctx = LocalContext.current
    var targetRaw by rememberStringPref(Keys.TRANSLATE_TARGET, TranslateLangs.DEFAULT_TARGET)
    val target = TranslateLangs.normalizeTarget(targetRaw)
    var wifiOnly by rememberBoolPref(Keys.TRANSLATE_WIFI_ONLY, true)
    var backend by remember { mutableStateOf<TranslateBackend?>(null) }
    var moduleChecked by remember { mutableStateOf(false) }
    var moduleStatus by remember { mutableStateOf<String?>(null) }   // null = không đang tải
    var have by remember { mutableStateOf<Set<String>?>(null) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    /** Lỗi tải module cần cài/cập nhật qua Google Play (APP_NOT_OWNED…) ⇒ hiện nút "Mở Google Play". */
    var errorOpensPlay by remember { mutableStateOf(false) }
    var picking by remember { mutableStateOf(false) }
    var refresh by remember { mutableStateOf(0) }
    val ui = if (L10n.isEnglish) L10n.EN else L10n.VI     // đọc state ngôn ngữ ⇒ recompose khi đổi

    // Module đã cài sẵn ⇒ nạp backend (khởi tạo ML Kit) — chỉ khi trang này mở.
    LaunchedEffect(Unit) {
        if (TranslateFeature.isInstalled(ctx)) backend = TranslateFeature.load(ctx)
        moduleChecked = true
    }
    LaunchedEffect(backend, refresh) { backend?.downloadedModels { have = it ?: emptySet() } }

    // --- bước 1: module Play Feature Delivery ---
    val splits = remember { SplitInstallManagerFactory.create(ctx) }
    DisposableEffect(splits) {
        val l = SplitInstallStateUpdatedListener { st ->
            if (!st.moduleNames().contains(TranslateFeature.MODULE)) return@SplitInstallStateUpdatedListener
            when (st.status()) {
                SplitInstallSessionStatus.PENDING -> moduleStatus = tr("Đang chờ tải tính năng Dịch…")
                SplitInstallSessionStatus.DOWNLOADING -> {
                    val total = st.totalBytesToDownload()
                    moduleStatus = if (total > 0) tr("Đang tải tính năng Dịch… %d%%", (st.bytesDownloaded() * 100 / total).toInt())
                        else tr("Đang tải tính năng Dịch…")
                }
                SplitInstallSessionStatus.DOWNLOADED, SplitInstallSessionStatus.INSTALLING -> moduleStatus = tr("Đang cài tính năng Dịch…")
                SplitInstallSessionStatus.REQUIRES_USER_CONFIRMATION -> {
                    val act = ctx.findActivity()
                    if (act == null || !splits.startConfirmationDialogForResult(st, act, CONFIRM_REQUEST)) {
                        moduleStatus = null; error = tr("Chưa tải được — kiểm tra kết nối rồi thử lại.")
                    }
                }
                SplitInstallSessionStatus.INSTALLED -> {
                    moduleStatus = null
                    backend = TranslateFeature.load(ctx)
                    if (backend == null) error = tr("Đã tải tính năng Dịch — mở lại app để dùng.")
                }
                SplitInstallSessionStatus.FAILED -> {
                    moduleStatus = null
                    error = TranslateDownloadError.text(st.errorCode(), ::tr)
                    errorOpensPlay = TranslateDownloadError.of(st.errorCode()).openPlay
                }
                SplitInstallSessionStatus.CANCELED -> moduleStatus = null
                else -> {}
            }
        }
        splits.registerListener(l)
        onDispose { splits.unregisterListener(l) }
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

    val b = backend
    if (b == null) {
        // Bước 1: tải module (Play).
        val label = moduleStatus ?: if (moduleChecked) tr("Tải tính năng Dịch (~7 MB)") else "…"
        VTRow(onClick = if (moduleStatus != null || !moduleChecked) null else {
            {
                error = null; errorOpensPlay = false
                if (wifiOnly && !ctx.onUnmeteredNetwork()) {
                    error = tr("Chưa tải được — cần Wi-Fi (hoặc tắt “Chỉ tải qua Wi-Fi”).")
                } else {
                    moduleStatus = tr("Đang chờ tải tính năng Dịch…")
                    splits.startInstall(SplitInstallRequest.newBuilder().addModule(TranslateFeature.MODULE).build())
                        .addOnSuccessListener { id ->
                            if (id == 0) { moduleStatus = null; backend = TranslateFeature.load(ctx) }   // đã có sẵn
                        }
                        .addOnFailureListener { e ->
                            moduleStatus = null
                            val code = (e as? SplitInstallException)?.errorCode
                            error = TranslateDownloadError.text(code, ::tr)
                            errorOpensPlay = TranslateDownloadError.of(code).openPlay
                        }
                }
            }
        }) {
            Text(label, style = VTType.body, color = c.accent)
        }
    } else {
        // Bước 2: gói ngôn ngữ.
        val ready = have?.containsAll(listOf(TranslateLangs.VI, target)) == true
        val status = when {
            have == null -> "…"
            busy -> tr("Đang tải gói dịch…")
            ready -> tr("✓ Đã có gói: Tiếng Việt + %s", TranslateLangs.displayName(target, ui))
            else -> tr("Tải gói dịch (Tiếng Việt + %s, %s)", TranslateLangs.displayName(target, ui), tr("~30 MB mỗi ngôn ngữ"))
        }
        VTRow(onClick = if (ready || busy || have == null) null else {
            {
                busy = true; error = null
                // English kèm theo (ML Kit đi vòng qua English) — đã có thì ML Kit bỏ qua ngay.
                val missing = linkedSetOf(TranslateLangs.VI, target, "en").filter { it == "en" || have?.contains(it) != true }
                b.downloadModels(missing, wifiOnly) { e ->
                    busy = false
                    if (e != null) error = if (wifiOnly) tr("Chưa tải được — cần Wi-Fi (hoặc tắt “Chỉ tải qua Wi-Fi”).") else tr("Chưa tải được — kiểm tra kết nối rồi thử lại.")
                    refresh++
                }
            }
        }) {
            Text(status, style = VTType.body, color = if (ready) c.green else c.accent)
        }
        // Gói đã tải khác (đổi đích nhiều lần) — xoá để lấy lại chỗ. Không xoá tiếng Việt / đích hiện tại.
        val extra = have.orEmpty().filter { it != TranslateLangs.VI && it != target && it != "en" }
        if (extra.isNotEmpty()) {
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
    }
    error?.let { e ->
        VTRow { Text(e, style = VTType.footnote, color = c.secondary) }
        if (errorOpensPlay) VTRow(onClick = { ctx.openPlayListing() }) {
            Text(tr("Mở Google Play"), style = VTType.body, color = c.accent)
        }
    }
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

private const val CONFIRM_REQUEST = 7301

private tailrec fun Context.findActivity(): Activity? = when (this) {
    is Activity -> this
    is ContextWrapper -> baseContext.findActivity()
    else -> null
}

/** Mạng hiện tại không tính phí theo dung lượng (Wi-Fi / Ethernet) — cho "Chỉ tải qua Wi-Fi". */
private fun Context.onUnmeteredNetwork(): Boolean {
    val cm = getSystemService(ConnectivityManager::class.java) ?: return false
    val caps = cm.getNetworkCapabilities(cm.activeNetwork) ?: return false
    return caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED) ||
        caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)
}

/** Trang VietTelex trên Google Play (app Play, không có thì trình duyệt). */
private fun Context.openPlayListing() {
    val id = packageName
    val market = Intent(Intent.ACTION_VIEW, Uri.parse("market://details?id=$id")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    try { startActivity(market) } catch (_: Exception) {
        try {
            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://play.google.com/store/apps/details?id=$id"))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        } catch (_: Exception) {}
    }
}
