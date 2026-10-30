package com.viettelex.android.ui

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import com.viettelex.android.ime.KeyEffectView
import com.viettelex.keyboard.ComboMeter
import com.viettelex.keyboard.KeyEffect
import com.viettelex.keyboard.KeyEffectBand
import com.viettelex.keyboard.KeyEffectGate
import com.viettelex.keyboard.Keys
import com.viettelex.keyboard.ThemePalette
import com.viettelex.keyboard.tr

/**
 * "Hiệu ứng khi bấm phím" (Plus): lưới 3 cột như "Chọn giao diện" — mỗi ô một phím thu nhỏ trên nền
 * theme đang dùng; chạm là chọn + xem thử ngay (cùng [KeyEffectView] của IME). Ô Plus bị khoá: mờ +
 * nhãn Plus, chạm mở VietTelex Plus. Lưu [Keys.KEY_EFFECT] — IME đọc lần hiện kế. iOS: KeyEffectPickerView.
 */
@Composable
internal fun KeyEffectPage(palette: ThemePalette, onOpenPlus: () -> Unit, onBack: () -> Unit) {
    val c = LocalVT.current
    BackHandler(onBack = onBack)
    var raw by rememberStringPref(Keys.KEY_EFFECT, KeyEffect.DEFAULT.id)
    val current = KeyEffect.of(raw)
    /** Số lần chạm từng ô — đổi ⇒ ô phát hiệu ứng một lượt. */
    val plays = remember { mutableStateMapOf<KeyEffect, Int>() }

    SubPageHeader(tr("Hiệu ứng khi bấm phím"), onBack)
    if (!KeyEffectGate.allows) {
        VTSection(footer = tr("Theme có nhãn Plus và ảnh nền thuộc VietTelex Plus (Giới Thiệu → VietTelex Plus). Hệ thống, Tối OLED, Tương phản cao và Xám trung tính luôn miễn phí.")) {
            VTRow(onClick = onOpenPlus) { Text("VietTelex Plus ›", color = c.accent) }
        }
    }
    VTSection(header = tr("Chạm một ô để chọn và xem thử."),
        footer = tr("Hình nhỏ bay ra từ phím vừa bấm, theo màu nhấn của giao diện. Vẽ sau khi chữ đã vào ô nên không làm chậm gõ; tự tắt khi bật Trình tiết kiệm pin.") +
            " " + tr("Matrix, Mực loang, Sóng nước chạy dưới phím; Matrix chỉ chạy khi đang gõ. Nháy sáng được giới hạn nhịp và độ sáng cho dịu mắt. Emoji theo chữ hiện khi vừa gõ xong từ như \"haha\", \"cảm ơn\", \"chúc mừng\".")) {
        KeyEffect.entries.chunked(3).forEach { row ->
            Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 6.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                row.forEach { e ->
                    val locked = !KeyEffectGate.allows(e)
                    val selected = current == e
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Box(Modifier.fillMaxWidth().height(84.dp).clip(RoundedCornerShape(10.dp))
                            .border(if (selected) 3.dp else 1.dp, if (selected) c.accent else c.separator, RoundedCornerShape(10.dp))
                            .alpha(if (locked) 0.5f else 1f)) {
                            val play = plays[e] ?: 0
                            AndroidView(factory = { KeyEffectPreviewView(it) }, modifier = Modifier.matchParentSize(),
                                update = { it.update(e, palette, play) })
                            // Lớp Compose phủ TRÊN AndroidView nhận chạm: View con nhận sự kiện trước nên
                            // clickable đặt ở Box cha không chắc tới được (iOS bị đúng lỗi này, 19/10/2026).
                            Box(Modifier.matchParentSize().clickable {
                                if (locked) onOpenPlus() else { raw = e.id; plays[e] = (plays[e] ?: 0) + 1 }
                            })
                            if (selected) Text("✓", style = VTType.body, color = c.accent,
                                modifier = Modifier.align(Alignment.TopEnd).padding(6.dp))
                        }
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(e.title, style = VTType.footnote, color = if (locked) c.secondary else c.label, maxLines = 1,
                                modifier = Modifier.weight(1f, fill = false))
                            if (locked) Text("Plus", style = VTType.caption2, color = Color.White,
                                modifier = Modifier.padding(start = 4.dp).background(Color(0xFFF5A623), RoundedCornerShape(50))
                                    .padding(horizontal = 5.dp, vertical = 1.dp))
                        }
                    }
                }
                repeat(3 - row.size) { Box(Modifier.weight(1f)) }
            }
        }
    }
}

/** Ô xem thử: nền theme + một phím "a" + overlay hiệu ứng thật (vẽ phím trước, hạt sau). */
@SuppressLint("ViewConstructor")
internal class KeyEffectPreviewView(context: Context) : KeyEffectView(context, context.resources.displayMetrics.density) {
    private val d = context.resources.displayMetrics.density
    private val keyPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { textAlign = Paint.Align.CENTER; textSize = 20 * d }
    private val keyRect = RectF()
    private var bg = 0
    private var lastPlay = 0

    fun update(e: KeyEffect, p: ThemePalette, play: Int) {
        bg = p.bg; keyPaint.color = p.keyFill; textPaint.color = p.ink
        configure(e, p.action, p.keyFill, p.isDark)
        invalidate()
        if (play != lastPlay) {
            lastPlay = play
            if (width > 0) playOnce() else post { playOnce() }
        }
    }

    /** Một lần xem thử: emoji như vừa gõ "haha" + dấu cách; combo = một tràng phím nhanh (mức lửa cao nhất). */
    private fun playOnce() {
        val x = width / 2f; val y = height - 8 * d - 21 * d
        when (effect) {
            KeyEffect.EMOJIWORD -> queueEmoji("😂")
            KeyEffect.COMBO -> repeat(ComboMeter.THRESHOLDS[2]) { burst(x, y, 34 * d, 42 * d); flush() }
            else -> {}
        }
        burst(x, y, 34 * d, 42 * d)
    }

    override fun onDraw(canvas: Canvas) {
        canvas.drawColor(bg)
        // Matrix / Mực loang / Sóng nước: dưới phím mẫu (như bàn phím thật); còn lại: trên.
        val below = effect.band == KeyEffectBand.BELOW_KEYS
        var running = below && drawEffects(canvas)
        val w = 34 * d; val h = 42 * d
        keyRect.set((width - w) / 2f, height - h - 8 * d, (width + w) / 2f, height - 8 * d)
        canvas.drawRoundRect(keyRect, 6 * d, 6 * d, keyPaint)
        canvas.drawText("a", keyRect.centerX(), keyRect.centerY() + textPaint.textSize / 3f, textPaint)
        if (!below) running = drawEffects(canvas)
        if (running) postInvalidateOnAnimation()
    }
}
