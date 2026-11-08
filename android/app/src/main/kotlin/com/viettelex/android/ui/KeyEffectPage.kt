package com.viettelex.android.ui

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
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
import com.viettelex.keyboard.BeatFlash
import com.viettelex.android.ime.KeyFloatDriver
import com.viettelex.keyboard.ComboMeter
import com.viettelex.keyboard.DanceFloor
import com.viettelex.keyboard.KeyEffect
import com.viettelex.keyboard.KeyEffectBand
import com.viettelex.keyboard.KeyEffectGate
import com.viettelex.keyboard.Keys
import com.viettelex.keyboard.KeywordKind
import com.viettelex.keyboard.ToneFx
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
        VTSection(footer = tr(SettingCaption.plusThemes)) {
            VTRow(onClick = onOpenPlus) { Text("VietTelex Plus ›", color = c.accent) }
        }
    }
    VTSection(header = tr("Chạm một ô để chọn và xem thử."),
        footer = tr("Hình nhỏ bay ra từ phím vừa bấm, theo màu nhấn của giao diện. Vẽ sau khi chữ đã vào ô nên không làm chậm gõ; tự tắt khi bật Trình tiết kiệm pin.") +
            " " + tr("Matrix, Mực loang, Sóng nước chạy dưới phím; Matrix chỉ chạy khi đang gõ. Nháy sáng được giới hạn nhịp và độ sáng cho dịu mắt. Emoji theo chữ hiện khi vừa gõ xong từ như \"haha\", \"cảm ơn\", \"chúc mừng\".") +
            " " + tr("Rung combo không rung khi bật Giảm chuyển động. Dấu thanh phản ứng theo dấu vừa bỏ; Từ khoá nổ pháo đỏ và lì xì khi gõ \"tết\", thả tim khi gõ \"yêu\"; Chữ bay thả đúng chữ vừa ra; Hạt cát đọng thành đống thấp ở đáy rồi tự tan.") +
            " " + tr("Biển: mỗi đợt gõ một con sóng vỗ vào bờ dưới đáy bàn phím, gõ càng nhanh sóng càng lớn; thỉnh thoảng có cá bơi ngang.") +
            " " + tr("Sàn nhảy LED thắp phím vừa bấm và các phím quanh thành vòng neon lan ra; gõ thật nhanh, cả bàn phím nháy một nhịp.") +
            " " + tr("Kính vạn hoa nở một bông đối xứng sắc cầu vồng từ phím vừa bấm, xoay chậm rồi tan.") +
            " " + tr("Đường hầm: vòng sáng co về phím vừa bấm như rơi vào đường hầm, gõ nhanh thì rơi nhanh hơn. Lơ lửng: phím trôi nhẹ khỏi hàng khi đang gõ rồi về chỗ khi nghỉ; chỉ là hình — chạm vẫn đúng phím; tắt khi bật Giảm chuyển động.") +
            " " + tr("Công đức thả \"+1 công đức\" bay lên từ phím vừa bấm và đếm số phím trong ngày (về 0 lúc nửa đêm, chỉ lưu trên máy). Nắng qua kính làm ô vừa bấm sáng lên như nắng xuyên qua kính màu; gõ nhanh có ánh nến ấm bập bùng chậm ở mép dưới.") +
            " " + tr("Mưa: mưa đêm êm trên ô kính — giọt rơi xuống phím vừa bấm rồi lăn nhẹ; gõ một lúc mưa thưa dần và ánh đèn ấm ở góc sáng lên.")) {
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

/**
 * Kịch bản một lần chạm ô xem thử ([tap] = số lần đã chạm, từ 1) — = iOS KeyEffectPreviewScript. IME thật cấp chữ vừa
 * ra, từ vừa chốt, khung phím cách, đích thanh gợi ý…; ô xem thử cấp TẤT CẢ mỗi lần chạm (mỗi hàm queue / lambda tự bỏ
 * qua khi không phải kiểu của nó) ⇒ kiểu mới chỉ cần thêm đầu vào của mình vào đây (hoặc không cần gì).
 */
internal object KeyEffectPreviewScript {
    const val EMOJI = "😂"                 // như vừa gõ "haha" + dấu cách
    const val GLYPH = "ế"                  // l10n-skip (chữ mẫu: Chữ bay / Token AI)
    val TONE = ToneFx.SAC
    /** Từ khoá: lần lẻ "tết" (pháo + lì xì), lần chẵn "yêu" (tim). */
    fun keyword(tap: Int): KeywordKind = if (tap % 2 == 1) KeywordKind.TET else KeywordKind.LOVE
    /** Số phím của một "tràng gõ nhanh" (mức combo cao nhất). */
    fun burst(e: KeyEffect): Int = when (e) {
        KeyEffect.COMBO, KeyEffect.SHAKE, KeyEffect.SEA, KeyEffect.DANCEFLOOR -> ComboMeter.THRESHOLDS[2]
        else -> 1
    }
    /** Sàn nhảy LED: lần chạm chẵn = một nhịp phím cách (flash nền, cổng ≤ 3 lần / giây vẫn áp). */
    fun beat(e: KeyEffect, tap: Int): Boolean = e == KeyEffect.DANCEFLOOR && tap % 2 == 0
    /** Phím hàng xóm giả quanh phím V (Sàn nhảy LED). */
    fun ghostKeys(e: KeyEffect): Boolean = e == KeyEffect.DANCEFLOOR
    /** Ô hàng xóm (i, j) theo lưới DanceFloor: trái / phải cùng hàng + ba phím hàng trên. */
    val GHOST_CELLS = arrayOf(intArrayOf(-1, 0), intArrayOf(1, 0), intArrayOf(-1, -1), intArrayOf(0, -1), intArrayOf(1, -1))
}

/**
 * Ô xem thử: nền theme + một phím "V" + overlay hiệu ứng thật (vẽ phím trước, hạt sau). Đầu vào giả theo
 * [KeyEffectPreviewScript]; bắn NGAY (không đợi lượt kế như IME — ô xem thử không chèn chữ).
 */
@SuppressLint("ViewConstructor")
internal class KeyEffectPreviewView(context: Context) : KeyEffectView(context, context.resources.displayMetrics.density) {
    private val d = context.resources.displayMetrics.density
    private val keyPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val ghostPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { textAlign = Paint.Align.CENTER; textSize = 20 * d }
    private val keyRect = RectF()
    private val ghostRect = RectF()
    private var bg = 0
    private var lastPlay = 0
    /** Sàn nhảy LED: flash nền (= BeatFlashView của IME) — cổng dùng chung với nhịp nháy cả bàn phím. */
    private val beatGate = BeatFlash.Gate()
    private var beatStart = Long.MIN_VALUE / 2
    private var beatColor = 0
    private var beatN = 0
    /** "Lơ lửng": phím mẫu trôi rồi về chỗ (đồng hồ thật [KeyFloatDriver]). */
    private var floater: KeyFloatDriver? = null

    fun update(e: KeyEffect, p: ThemePalette, play: Int) {
        bg = p.bg; keyPaint.color = p.keyFill; textPaint.color = p.ink
        ghostPaint.color = (p.keyFill and 0x00FFFFFF) or (0x8C shl 24)
        configure(e, p.action, p.keyFill, p.isDark)
        // Rung combo: rung cả ô xem thử (như hàng phím); Laser: "phím cách" giả ở góc dưới trái ô.
        shakeTarget = if (e == KeyEffect.SHAKE) this else null
        spaceFrame = { out -> out.set(6 * d, height - 10 * d, maxOf(width * 0.3f, 7 * d), height - 2 * d); true }
        floater = if (e == KeyEffect.FLOAT) floater ?: KeyFloatDriver() else null
        // Token AI: "thanh gợi ý" = mép trên ô xem thử.
        tokenTarget = { out -> out[0] = width / 2f; out[1] = 10 * d; true }
        flashGate = if (e == KeyEffect.DANCEFLOOR) beatGate else null
        invalidate()
        if (play != lastPlay) {
            lastPlay = play
            if (width > 0) playTap(play) else post { playTap(play) }
        }
    }

    private fun keyCx() = width / 2f
    private fun keyCy() = height - 8 * d - 21 * d

    /** Một lần xem thử: cấp mọi đầu vào giả rồi "bấm" phím V. */
    fun playTap(tap: Int) {
        if (width <= 0 || height <= 0) return
        val e = effect
        val x = keyCx(); val y = keyCy(); val w = 34 * d; val h = 42 * d
        if (e == KeyEffect.PLASMA) { burst(width * 0.15f, 18 * d); flush(); burst(width * 0.85f, 26 * d); flush() }
        repeat(KeyEffectPreviewScript.burst(e) - 1) { burst(x, y, w, h); flush() }
        queueEmoji(KeyEffectPreviewScript.EMOJI)
        queueTone(KeyEffectPreviewScript.TONE)
        queueKeyword(KeyEffectPreviewScript.keyword(tap))
        queueLetter(KeyEffectPreviewScript.GLYPH)
        queueToken(KeyEffectPreviewScript.GLYPH)
        burst(x, y, w, h)
        flush()
        if (KeyEffectPreviewScript.beat(e, tap)) kickBeat()
        // Mưa: như đã gõ một lúc (mưa thưa bớt, đèn ấm sáng lên) + vài giọt rơi quanh ô — = iOS.
        if (e == KeyEffect.RAIN) { previewRain(200); burst(width * 0.18f, 24 * d); flush(); burst(width * 0.8f, 32 * d); flush() }
        floater?.let { it.poke(); invalidate() }
    }

    private fun kickBeat() {
        val now = SystemClock.uptimeMillis()
        if (!beatGate.trigger(now / 1000.0)) return
        beatColor = BeatFlash.tint(beatN++); beatStart = now
        postInvalidateOnAnimation()
    }

    /** Test: độ đục flash nền lúc [now]. */
    internal fun beatAlpha(now: Long): Double = BeatFlash.alpha((now - beatStart) / 1000.0)

    override fun onDraw(canvas: Canvas) {
        canvas.drawColor(bg)
        val now = SystemClock.uptimeMillis()
        val ba = beatAlpha(now)
        if (ba > 0) canvas.drawColor(((ba * 255).toInt().coerceIn(0, 255) shl 24) or (beatColor and 0xFFFFFF))
        // Matrix / Mực loang / Sóng nước: dưới phím mẫu (như bàn phím thật); còn lại: trên.
        val below = effect.band == KeyEffectBand.BELOW_KEYS
        var running = below && drawEffects(canvas)
        val w = 34 * d; val h = 42 * d
        keyRect.set((width - w) / 2f, height - h - 8 * d, (width + w) / 2f, height - 8 * d)
        if (KeyEffectPreviewScript.ghostKeys(effect)) {
            val u = DanceFloor.unit(w.toDouble(), h.toDouble()).toFloat()
            for (c in KeyEffectPreviewScript.GHOST_CELLS) {
                val p = DanceFloor.center(c[0], c[1], keyRect.centerX().toDouble(), keyRect.centerY().toDouble(), w.toDouble(), h.toDouble())
                val gw = if (c[0] == 0) w else u
                ghostRect.set(p[0].toFloat() - gw / 2, p[1].toFloat() - h / 2, p[0].toFloat() + gw / 2, p[1].toFloat() + h / 2)
                canvas.drawRoundRect(ghostRect, 6 * d, 6 * d, ghostPaint)
            }
        }
        val f = floater
        val t = f?.now?.invoke() ?: 0.0
        val floating = f != null && f.frame(t)
        canvas.save()
        if (floating) f!!.apply(canvas, 0, t, keyRect.centerX(), keyRect.centerY(), d)
        canvas.drawRoundRect(keyRect, 6 * d, 6 * d, keyPaint)
        canvas.drawText("V", keyRect.centerX(), keyRect.centerY() + textPaint.textSize / 3f, textPaint)
        canvas.restore()
        if (!below) running = drawEffects(canvas) || running
        if (floating) running = true
        if (running || ba > 0 || now - beatStart < (BeatFlash.DURATION * 1000).toLong()) postInvalidateOnAnimation()
    }
}
