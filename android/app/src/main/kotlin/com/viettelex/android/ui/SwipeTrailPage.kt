package com.viettelex.android.ui

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.os.SystemClock
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
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import com.viettelex.android.ime.ImeTheme
import com.viettelex.android.ime.SwipeTrailView
import com.viettelex.keyboard.Keys
import com.viettelex.keyboard.SwipeTrailGate
import com.viettelex.keyboard.SwipeTrailPolicy
import com.viettelex.keyboard.SwipeTrailStyle
import com.viettelex.keyboard.tr
import kotlin.math.sin

/**
 * "Hiệu ứng nét vuốt" (Gõ vuốt → Hiệu ứng nét vuốt): lưới 2 cột — mỗi ô một nét vuốt mẫu vẽ bằng CHÍNH
 * [SwipeTrailView] của IME trên nền theme đang dùng; chạm là chọn + xem thử. Ô Plus bị khoá: mờ + nhãn Plus,
 * chạm mở VietTelex Plus. Lưu [Keys.SWIPE_TRAIL] — IME đọc lần hiện kế. iOS: SwipeTrailPickerView.
 */
@Composable
internal fun SwipeTrailPage(onOpenPlus: () -> Unit, onBack: () -> Unit) {
    val c = LocalVT.current
    val ctx = LocalContext.current
    BackHandler(onBack = onBack)
    var raw by rememberStringPref(Keys.SWIPE_TRAIL, SwipeTrailStyle.DEFAULT.id)
    val current = SwipeTrailStyle.displayed(raw)
    val theme = remember { ImeTheme(ctx, loadThemeSettings(ctx)) }
    val themeSwipe = theme.settings.effectiveKeyStyle.swipe
    /** Số lần chạm từng ô — đổi ⇒ ô vẽ lại nét mẫu một lượt. */
    val plays = remember { mutableStateMapOf<SwipeTrailStyle, Int>() }

    SubPageHeader(tr("Hiệu ứng nét vuốt"), onBack)
    if (!SwipeTrailGate.allows) {
        VTSection {
            VTRow(onClick = onOpenPlus) { Text("VietTelex Plus ›", color = c.accent) }
        }
    }
    VTSection(header = tr("Chạm một ô để chọn và xem thử."),
        footer = tr("Nét vẽ theo ngón tay khi gõ vuốt. Tắt: không vẽ gì. Tắt và Đơn giản miễn phí, mọi kiểu khác (kể cả Theo giao diện) thuộc VietTelex Plus. Theo giao diện: dùng nét vuốt của giao diện đang chọn (Đơn giản nếu giao diện không có).") +
            " " + tr("Vẽ trên lớp riêng, không làm chậm nhận diện nét vuốt; tự về Đơn giản khi bật Trình tiết kiệm pin.")) {
        SwipeTrailStyle.entries.chunked(2).forEach { row ->
            Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 6.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                row.forEach { s ->
                    val locked = !SwipeTrailGate.allows(s)
                    val selected = current == s
                    // Xem thử luôn vẽ đúng kiểu (kể cả khi khoá); "Theo giao diện" ⇒ nét của theme đang dùng.
                    val drawn = SwipeTrailPolicy.active(s, plus = true, themeSwipe = themeSwipe, powerSave = false)
                    LaunchedEffect(s) { if (plays[s] == null) plays[s] = 1 }   // vẽ mẫu một lượt khi mở trang
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Box(Modifier.fillMaxWidth().height(76.dp).clip(RoundedCornerShape(10.dp))
                            .border(if (selected) 3.dp else 1.dp, if (selected) c.accent else c.separator, RoundedCornerShape(10.dp))
                            .alpha(if (locked) 0.5f else 1f)) {
                            val play = plays[s] ?: 0
                            AndroidView(factory = { SwipeTrailPreviewView(it, theme) }, modifier = Modifier.matchParentSize(),
                                update = { it.update(drawn, play) })
                            // Lớp Compose phủ TRÊN AndroidView nhận chạm (như KeyEffectPage).
                            Box(Modifier.matchParentSize().clickable {
                                if (locked) onOpenPlus() else { raw = s.id; plays[s] = (plays[s] ?: 0) + 1 }
                            })
                            if (selected) Text("✓", style = VTType.body, color = c.accent,
                                modifier = Modifier.align(Alignment.TopEnd).padding(6.dp))
                        }
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(s.title, style = VTType.footnote, color = if (locked) c.secondary else c.label, maxLines = 1,
                                modifier = Modifier.weight(1f, fill = false))
                            if (locked) Text("Plus", style = VTType.caption2, color = Color.White,
                                modifier = Modifier.padding(start = 4.dp).background(Color(0xFFF5A623), RoundedCornerShape(50))
                                    .padding(horizontal = 5.dp, vertical = 1.dp))
                        }
                    }
                }
                repeat(2 - row.size) { Box(Modifier.weight(1f)) }
            }
        }
    }
}

/** Ô xem thử: nền theme + một nét vuốt mẫu (sóng ngang) vẽ dần ~0,55 s rồi nhấc tay — cùng renderer IME. */
@SuppressLint("ViewConstructor")
internal class SwipeTrailPreviewView(context: Context, private val th: ImeTheme) : SwipeTrailView(context, th) {
    private var lastPlay = 0
    private var start = 0L
    private var running = false
    private var drawStyle = SwipeTrailStyle.NONE

    fun update(s: SwipeTrailStyle, play: Int) {
        drawStyle = s
        if (s != SwipeTrailStyle.NONE) configure(s)
        invalidate()
        if (play != lastPlay) {
            lastPlay = play
            if (width > 0) run() else post { run() }
        }
    }

    private fun run() {
        if (drawStyle == SwipeTrailStyle.NONE || width == 0) return
        clear()
        setSampleKeys()   // Phím sáng theo đường / Ma trận: lưới QWERTY mẫu (kiểu khác: 0 việc)
        begin()
        start = SystemClock.uptimeMillis()
        running = true
        postOnAnimation(step)
    }

    private val step = object : Runnable {
        override fun run() {
            if (!running) return
            val now = SystemClock.uptimeMillis()
            val f = ((now - start) / DURATION_MS.toFloat()).coerceAtMost(1f)
            add(width * (0.1f + 0.8f * f), height * (0.5f + 0.25f * sin(f * 2 * Math.PI).toFloat()), now)
            if (f >= 1f) { running = false; end(fade = true); commitBurst() } else postOnAnimation(this)
        }
    }

    override fun onDetachedFromWindow() { running = false; removeCallbacks(step); clear(); super.onDetachedFromWindow() }

    override fun onDraw(canvas: Canvas) {
        canvas.drawColor(th.bg)
        if (drawStyle != SwipeTrailStyle.NONE) drawTrail(canvas, SystemClock.uptimeMillis())
    }

    companion object { private const val DURATION_MS = 550L }
}
