package com.viettelex.android.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.viettelex.android.ime.KeyFeedbackPreview
import com.viettelex.keyboard.Keys
import com.viettelex.keyboard.SwipeSoundGate
import com.viettelex.keyboard.SwipeSoundStyle
import com.viettelex.keyboard.tr

/**
 * "Âm thanh nét vuốt" (Gõ vuốt → Âm thanh nét vuốt): danh sách kiểu, chạm là chọn + nghe thử một nét vuốt mẫu
 * ([KeyFeedbackPreview.playSwipe], cùng mẫu + vỏ âm lượng với IME). Kiểu Plus chưa có Plus: nhãn Plus, chạm mở
 * VietTelex Plus. Lưu [Keys.SWIPE_SOUND] — IME đọc lần hiện kế. iOS: SwipeSoundPickerView.
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

    SubPageHeader(tr("Âm thanh nét vuốt"), onBack)
    if (!SwipeSoundGate.allows) {
        VTSection {
            VTRow(onClick = onOpenPlus) { Text("VietTelex Plus ›", color = c.accent) }
        }
    }
    VTSection(header = tr("Chạm một kiểu để chọn và nghe thử."),
        footer = tr("Tiếng khẽ khi ngón đang vuốt một từ, như bút lướt trên giấy: to hơn khi vuốt nhanh, im khi ngón dừng. Tắt: không phát gì. Chổi lông, Phấn bảng và Bút dạ thuộc VietTelex Plus.") +
            " " + tr("Theo âm lượng của Âm thanh phím; im khi máy để Rung/Im lặng. Tự về Bút chì khi bật Trình tiết kiệm pin.")) {
        SwipeSoundStyle.entries.forEachIndexed { i, s ->
            if (i > 0) RowDivider()
            val locked = !SwipeSoundGate.allows(s)
            VTRow(onClick = {
                if (locked) onOpenPlus() else { raw = s.id; preview.playSwipe(s, maxOf(vol, 20)) }
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
}
