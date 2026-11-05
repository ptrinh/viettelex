package com.viettelex.android.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import com.viettelex.keyboard.ClipboardTTL
import com.viettelex.keyboard.Keys
import com.viettelex.keyboard.tr

/** Tính Năng → "Riêng tư & clipboard": lịch sử clipboard + chế độ ẩn danh. */
@Composable
fun PrivacySection() {
    val ctx = LocalContext.current
    VTSection(header = "Clipboard",
        footer = tr(SettingCaption.clipboardFooterAndroid)) {
        var history by rememberBoolPref(Keys.CLIPBOARD_HISTORY, Prefs.D.clipboardHistory)
        SettingToggle(tr("Lịch sử clipboard"),
            tr(SettingCaption.clipboardHistory), history) {
            history = it
            // Tắt ⇒ xoá luôn dữ liệu đã lưu (IME cùng process cũng bỏ bản trong RAM).
            if (!it) java.io.File(ctx.filesDir, Keys.CLIPBOARD_FILE).delete()
        }
        // "Giữ lịch sử clipboard" — IME đọc khi hiện / khi pref đổi (PrefSync), áp ở lần prune kế tiếp.
        if (history) ChoiceRow(Keys.CLIPBOARD_TTL, Prefs.D.clipboardTtl.id, tr("Giữ lịch sử clipboard"),
            tr(SettingCaption.clipboardTTL),
            listOf(ClipboardTTL.HOUR_1.id to tr("1 giờ"), ClipboardTTL.HOURS_24.id to tr("24 giờ"),
                ClipboardTTL.DAYS_7.id to tr("7 ngày"))) { ClipboardTTL.of(it).id }
    }
    VTSection(header = tr("Riêng tư")) {
        var incognito by rememberBoolPref(Keys.INCOGNITO, Prefs.D.incognito)
        SettingToggle(tr("Chế độ ẩn danh"),
            tr(SettingCaption.incognitoAndroid), incognito) { incognito = it }
    }
}
