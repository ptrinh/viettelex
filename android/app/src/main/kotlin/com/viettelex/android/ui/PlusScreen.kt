package com.viettelex.android.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.viettelex.android.BuildConfig
import com.viettelex.android.plus.PlusController
import com.viettelex.android.translate.TranslateFeature
import androidx.compose.ui.platform.LocalContext
import com.viettelex.keyboard.Keys
import com.viettelex.keyboard.PlusConfig
import com.viettelex.keyboard.PlusFeature
import com.viettelex.keyboard.PlusGate
import kotlinx.coroutines.launch
import com.viettelex.keyboard.tr

/** Dòng mở màn Plus (tab Giới Thiệu). */
@Composable
fun PlusEntryRow(plus: PlusController, onOpen: () -> Unit) {
    val c = LocalVT.current
    val s by plus.state.collectAsState()
    VTSection {
        VTRow(onClick = onOpen) {
            Text("★", style = VTType.body, color = c.accent)
            Text("VietTelex Plus", style = VTType.body, color = c.accent,
                modifier = Modifier.padding(start = 16.dp).weight(1f))
            if (s.purchased) Text(tr("Đã mở khoá"), style = VTType.footnote, color = c.secondary)
        }
    }
}

/** Màn "VietTelex Plus": quyền lợi, mua, khôi phục, trạng thái, ủng hộ. */
@Composable
fun PlusScreen(plus: PlusController, onBack: () -> Unit, onOpenFeature: (FeaturePage) -> Unit = {}) {
    val c = LocalVT.current
    val s by plus.state.collectAsState()
    val scope = rememberCoroutineScope()
    var debugOverride by rememberBoolPref(Keys.PLUS_DEBUG_OVERRIDE, false)
    val isPlus = PlusGate.resolve(s.purchased, debugOverride, BuildConfig.DEBUG)

    LaunchedEffect(Unit) { plus.refresh() }

    VTSection(plain = true) {
        VTRow(onClick = onBack) { Text(tr("‹ Giới Thiệu"), style = VTType.body, color = c.accent) }
    }
    VTSection(plain = true) {
        Column(Modifier.fillMaxWidth().padding(vertical = 8.dp), horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(if (isPlus) "★" else "☆", style = VTType.largeTitle, color = c.accent)
            Text(if (isPlus) tr("Cảm ơn bạn đã ủng hộ VietTelex ★") else tr("Mua một lần, dùng mãi mãi. Không thuê bao, không quảng cáo."),
                style = VTType.subheadline, color = c.secondary)
        }
    }
    if (!PlusGate.paywallEnabled) {
        VTSection { VTRow { Text(tr("Trong giai đoạn này mọi tính năng Plus đang mở miễn phí cho tất cả mọi người."),
            style = VTType.footnote, color = c.secondary) } }
    }
    VTSection(header = tr("Quyền lợi Plus"),
        footer = tr("Toàn bộ phần gõ — Telex/VNI, sửa dấu từ đã gõ, gợi ý, gõ vuốt, gõ tắt, mẫu câu, theme sáng/tối — luôn miễn phí.")) {
        // APK ngoài Play không tải được module Dịch ⇒ ẩn hẳn dòng này.
        val translateOffered = TranslateFeature.offered(LocalContext.current)
        PlusFeature.entries.filter { it != PlusFeature.TRANSLATE || translateOffered }.forEachIndexed { i, f ->
            if (i > 0) RowDivider()
            // Màn Plus chỉ là trang mua: công tắc/cài đặt nằm ở trang tính năng — chạm để mở.
            val page = plusFeaturePage(f)
            VTRow(onClick = page?.let { p -> { onOpenFeature(p) } }) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(f.title, style = VTType.body, color = c.label)
                    Text(f.detail, style = VTType.footnote, color = c.secondary)
                    Text(f.howTo, style = VTType.footnote, color = c.accent)
                }
                if (page != null) Text("›", style = VTType.title3, color = c.tertiary)
            }
        }
    }
    VTSection(header = tr("Mua"),footer = tr("Thanh toán qua Google Play. Đã mua trên máy khác cùng tài khoản Google thì bấm Khôi phục.")) {
        if (isPlus) {
            VTRow { Text(tr("✓ Bạn đã có VietTelex Plus"), style = VTType.body, color = c.green) }
        } else {
            VTRow(onClick = { plus.buy(PlusConfig.PLUS_PRODUCT_ID) }) {
                Text(tr("Mở khoá Plus"), style = VTType.headline, color = c.accent, modifier = Modifier.weight(1f))
                Text(if (s.busyProductId == PlusConfig.PLUS_PRODUCT_ID) "…" else s.plus?.price ?: PlusConfig.PLUS_PRICE_HINT,
                    style = VTType.body, color = c.secondary)
            }
        }
        RowDivider()
        VTRow(onClick = { if (!s.restoring) scope.launch { plus.restore() } }) {
            Text(if (s.restoring) tr("Đang khôi phục…") else tr("Khôi phục giao dịch"), style = VTType.body, color = c.accent)
        }
    }
    VTSection(header = tr("Ủng hộ tác giả"), footer = tr("Tuỳ tâm, không mở khoá thêm gì — giúp VietTelex tiếp tục miễn phí và mã nguồn mở.")) {
        if (s.tips.isEmpty()) {
            VTRow { Text(tr("Chưa tải được các mức ủng hộ."), style = VTType.footnote, color = c.secondary) }
        }
        s.tips.forEachIndexed { i, t ->
            if (i > 0) RowDivider()
            VTRow(onClick = { plus.buy(t.id) }) {
                Text(t.title, style = VTType.body, color = c.label, modifier = Modifier.weight(1f))
                Text(if (s.busyProductId == t.id) "…" else t.price, style = VTType.body, color = c.secondary)
            }
        }
    }
    if (s.offerAddTones) AlertDialog(
        onDismissRequest = { plus.dismissAddTonesOffer() },
        title = { Text(tr("Bật chip “Thêm dấu”?")) },
        text = { Text(tr("Gõ không dấu cả câu, gõ dấu cách rồi chạm chip “Thêm dấu” ở đầu thanh gợi ý. Chip đang tắt — bật ngay? (Đổi lại ở Tính Năng → Sửa lỗi & gợi ý.)")) },
        confirmButton = { TextButton(onClick = { plus.acceptAddTonesOffer() }) { Text(tr("Bật ngay"), color = c.accent) } },
        dismissButton = { TextButton(onClick = { plus.dismissAddTonesOffer() }) { Text(tr("Để sau"), color = c.secondary) } },
    )
    s.message?.let { m ->
        VTSection { VTRow(onClick = { plus.dismissMessage() }) { Text(m, style = VTType.footnote, color = c.label) } }
    }
    if (BuildConfig.DEBUG) {
        VTSection(header = "Debug", footer = tr("Chỉ có trong bản Debug. Bàn phím đọc cùng cờ.")) {
            SettingToggle(tr("Giả lập đã mua Plus"), null, debugOverride) { debugOverride = it }
        }
    }
}

/** Trang Tính Năng chứa cài đặt / lối vào của quyền lợi Plus (null = không có trang riêng). */
internal fun plusFeaturePage(f: PlusFeature): FeaturePage? = when (f) {
    PlusFeature.PREMIUM_THEMES -> FeaturePage.GiaoDien
    PlusFeature.SENTENCE_DIACRITICS -> FeaturePage.SuaLoi
    PlusFeature.ADVANCED_CLIPBOARD -> FeaturePage.RiengTu
    PlusFeature.CLOUD_SYNC -> FeaturePage.RiengTu
    PlusFeature.TEXT_TOOLS, PlusFeature.TRANSLATE -> FeaturePage.GoTat
    PlusFeature.THANKS_BADGE -> null
}
