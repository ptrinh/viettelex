package com.viettelex.android.ui

import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.viettelex.android.ime.KeyFeedbackPreview
import com.viettelex.android.ime.KeySoundImport
import com.viettelex.android.ime.SwipeSoundImport
import com.viettelex.keyboard.Keys
import com.viettelex.keyboard.SwipeSoundGate
import com.viettelex.keyboard.SwipeSoundStyle
import com.viettelex.keyboard.tr
import java.util.Locale

/**
 * "Âm thanh nét vuốt" (Gõ vuốt → Âm thanh nét vuốt): danh sách kiểu, chạm là chọn + nghe thử một nét vuốt mẫu
 * ([KeyFeedbackPreview.playSwipe], cùng mẫu + vỏ âm lượng + tiếng nhấc tay với IME). Kiểu Plus chưa có Plus: nhãn Plus,
 * chạm mở VietTelex Plus. Lưu [Keys.SWIPE_SOUND] — IME đọc lần hiện kế. "Âm của bạn": chọn file (bộ chọn file hệ thống)
 * → [SwipeSoundImport] (như âm phím tự chọn) + nghe thử + xoá. iOS: SwipeSoundPickerView.
 */
@Composable
internal fun SwipeSoundPage(onOpenPlus: () -> Unit, onBack: () -> Unit) {
    val c = LocalVT.current
    val ctx = LocalContext.current
    BackHandler(onBack = onBack)
    var raw by rememberStringPref(Keys.SWIPE_SOUND, SwipeSoundStyle.DEFAULT.id)
    val vol by rememberIntPref(Keys.KEY_SOUND_VOLUME, Prefs.D.keySoundVolume)
    val current = SwipeSoundStyle.displayed(raw)
    val preview = remember { KeyFeedbackPreview(ctx) }
    DisposableEffect(Unit) { onDispose { preview.release() } }
    var customDuration by remember { mutableStateOf(SwipeSoundImport.storedDuration(ctx)) }
    var notice by remember { mutableStateOf<String?>(null) }
    var styleBeforeImport by remember { mutableStateOf<String?>(null) }
    val audible = { maxOf(vol, 20) }

    val importer = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        val before = styleBeforeImport
        styleBeforeImport = null
        val customId = SwipeSoundStyle.CUSTOM.id
        if (uri == null) {
            if (customDuration == null && raw == customId) raw = before ?: SwipeSoundStyle.DEFAULT.id
            return@rememberLauncherForActivityResult
        }
        try {
            val o = SwipeSoundImport.importUri(ctx, uri)
            customDuration = o.duration
            raw = customId
            notice = if (o.truncated) tr("Âm dài hơn 3 giây nên chỉ dùng 3 giây đầu.") else null
            preview.playSwipe(SwipeSoundStyle.CUSTOM, audible())
        } catch (e: KeySoundImport.ImportException) {
            notice = when (e.failure) {
                KeySoundImport.Failure.SILENT -> tr("File không có tiếng (toàn im lặng).")
                KeySoundImport.Failure.TOO_LARGE -> tr("File quá lớn (tối đa 30 MB).")
                KeySoundImport.Failure.UNREADABLE -> tr("Không đọc được file âm thanh này.")
            }
            if (customDuration == null && raw == customId) raw = before ?: SwipeSoundStyle.DEFAULT.id
        }
    }

    SubPageHeader(tr("Âm thanh nét vuốt"), onBack)
    if (!SwipeSoundGate.allows) {
        VTSection {
            VTRow(onClick = onOpenPlus) { Text("VietTelex Plus ›", color = c.accent) }
        }
    }
    VTSection(header = tr("Chạm một kiểu để chọn và nghe thử."),
        footer = tr("Tiếng khẽ khi ngón đang vuốt một từ: to hơn khi vuốt nhanh, im khi ngón dừng. Nốt nhạc theo phím: mỗi phím ngón đi qua gảy một nốt, mỗi từ thành một giai điệu nhỏ (nhạc cụ theo Âm thanh phím nếu là Piano, Đàn tranh hay Ghi-ta mộc, không thì Đàn tranh). Sáo trúc: cao độ theo vị trí ngón. Roi vụt, Tia sét, Plasma, Đũa phép, Sóng biển, Mèo kêu và Chim hót thêm một tiếng ngắn lúc nhấc tay. Tắt: không phát gì. Bút chì miễn phí, các kiểu còn lại thuộc VietTelex Plus.") +
            " " + tr("Theo âm lượng của Âm thanh phím; im khi máy để Rung/Im lặng. Tự về Bút chì khi bật Trình tiết kiệm pin.")) {
        SwipeSoundStyle.entries.forEachIndexed { i, s ->
            if (i > 0) RowDivider()
            val locked = !SwipeSoundGate.allows(s)
            VTRow(onClick = {
                when {
                    locked -> onOpenPlus()
                    s == SwipeSoundStyle.CUSTOM && customDuration == null -> {
                        styleBeforeImport = raw; raw = s.id
                        importer.launch(arrayOf("audio/*"))
                    }
                    else -> { raw = s.id; preview.playSwipe(s, audible()) }
                }
            }) {
                Text(s.title, style = VTType.body, color = if (locked) c.secondary else c.label,
                    modifier = Modifier.weight(1f))
                if (locked) Text("Plus", style = VTType.caption2, color = Color.White,
                    modifier = Modifier.padding(end = 8.dp).background(Color(0xFFF5A623), RoundedCornerShape(50))
                        .padding(horizontal = 5.dp, vertical = 1.dp))
                if (current == s) GlyphIcon(Glyph.Check, c.accent, 18.dp)
            }
        }
    }
    if (SwipeSoundGate.allows && (current == SwipeSoundStyle.CUSTOM || customDuration != null)) {
        VTSection {
            Column(Modifier.padding(horizontal = 16.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                val d = customDuration
                Text(if (d != null) tr("Âm của bạn: %s giây", String.format(Locale.ROOT, "%.2f", d))
                     else tr("Chưa có âm — chọn một file âm thanh (mp3, m4a, ogg, wav…); dùng tối đa 3 giây đầu làm vòng lặp."),
                    style = VTType.footnote, color = if (d != null) c.label else c.secondary)
                Row(horizontalArrangement = Arrangement.spacedBy(20.dp)) {
                    Text(if (d == null) tr("Chọn âm thanh…") else tr("Chọn âm khác…"), style = VTType.body, color = c.accent,
                        modifier = Modifier.clickable { styleBeforeImport = raw; importer.launch(arrayOf("audio/*")) })
                    if (d != null) {
                        Text(tr("Nghe thử"), style = VTType.body, color = c.accent,
                            modifier = Modifier.clickable { preview.playSwipe(SwipeSoundStyle.CUSTOM, audible()) })
                        Text(tr("Xoá"), style = VTType.body, color = c.red,
                            modifier = Modifier.clickable {
                                SwipeSoundImport.remove(ctx); customDuration = null
                                if (raw == SwipeSoundStyle.CUSTOM.id) raw = SwipeSoundStyle.FALLBACK.id
                            })
                    }
                }
                Text(tr("Bỏ lặng đầu/cuối, nối đuôi vào đầu cho liền, chỉnh độ to như các kiểu khác. File chỉ trên máy này (không tải lên, không sao lưu); thiếu file ⇒ phát Bút chì."),
                    style = VTType.footnote, color = c.secondary)
            }
            notice?.let { VTRow { Text(it, style = VTType.footnote, color = c.secondary) } }
        }
    }
}
