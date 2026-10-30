package com.viettelex.android.ui

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.widget.FrameLayout
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
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
import com.viettelex.android.ime.BuddyView
import com.viettelex.keyboard.BuddyCharacter
import com.viettelex.keyboard.BuddyBirthday
import com.viettelex.keyboard.BuddyName
import com.viettelex.keyboard.BuddyFraming
import com.viettelex.keyboard.BuddyGate
import com.viettelex.keyboard.BuddyPlacement
import com.viettelex.keyboard.BuddySeason
import com.viettelex.keyboard.BuddyStyle
import com.viettelex.keyboard.Keys
import com.viettelex.keyboard.ThemePalette
import com.viettelex.keyboard.tr

/**
 * "Bạn đồng hành" (Plus): lưới Tắt / Cô gái / Chàng trai / Mèo / Gà con — mỗi ô là [BuddyView] thật (cả người)
 * trên nền theme. Mở trang: mọi nhân vật nhảy một tràng như đang gõ rồi ngủ; chạm ô là chọn + diễn lại. Ô Plus bị
 * khoá: mờ + nhãn Plus, chạm mở VietTelex Plus. Lưu [Keys.KEYBOARD_BUDDY] — IME đọc lần hiện kế. Dưới lưới: "Kiểu vẽ"
 * Hoạt hình | Vẽ nét của nhân vật đang chọn ([BuddyStyle], khoá `buddyStyle.<id>`); mỗi ô vẽ theo kiểu của nhân vật đó.
 * "Vị trí & cỡ" ([BuddyPlacement]: cỡ 1…20, lề phải / lề trên −100…100 dp, nấc 5) chung mọi nhân vật. iOS: BuddyPickerView.
 */
@Composable
internal fun BuddyPage(palette: ThemePalette, themeId: String, onOpenPlus: () -> Unit, onBack: () -> Unit) {
    val c = LocalVT.current
    BackHandler(onBack = onBack)
    var raw by rememberStringPref(Keys.KEYBOARD_BUDDY, BuddyCharacter.DEFAULT.id)
    val current = BuddyCharacter.of(raw)
    val plays = remember { mutableStateMapOf<BuddyCharacter, Int>() }
    // Kiểu vẽ từng nhân vật: MỘT bảng state (đọc prefs một lần) — ô xem thử và nút chọn cùng nguồn, đổi là vẽ lại
    // ngay (không dựa vào listener prefs giữa nhiều state rời).
    val ctx = androidx.compose.ui.platform.LocalContext.current
    val styles = remember {
        val sp = Prefs.of(ctx)
        mutableStateMapOf<BuddyCharacter, BuddyStyle>().apply {
            BuddyCharacter.entries.forEach { put(it, BuddyStyle.of(sp.getString(BuddyStyle.key(it), null))) }
        }
    }
    var size by rememberIntPref(Keys.BUDDY_SIZE, BuddyPlacement.DEFAULT_SIZE)
    var padRight by rememberIntPref(Keys.BUDDY_PAD_RIGHT, 0)
    var padTop by rememberIntPref(Keys.BUDDY_PAD_TOP, 0)
    var birthdayMonth by rememberIntPref(BuddyBirthday.MONTH_KEY, 0)
    var birthdayDay by rememberIntPref(BuddyBirthday.DAY_KEY, 0)
    // Vẽ nét xem thử mặc trang phục mùa lễ như trên bàn phím (theme lễ / ngày).
    val season = remember(themeId) {
        val cal = java.util.Calendar.getInstance()
        BuddySeason.resolve(themeId, cal.get(java.util.Calendar.YEAR), cal.get(java.util.Calendar.MONTH) + 1,
            cal.get(java.util.Calendar.DAY_OF_MONTH))
    }

    SubPageHeader(tr("Bạn đồng hành"), onBack)
    if (!BuddyGate.allows) {
        VTSection(footer = tr("Theme có nhãn Plus và ảnh nền thuộc VietTelex Plus (Giới Thiệu → VietTelex Plus). Hệ thống, Tối OLED, Tương phản cao và Xám trung tính luôn miễn phí.")) {
            VTRow(onClick = onOpenPlus) { Text("VietTelex Plus ›", color = c.accent) }
        }
    }
    VTSection(header = tr("Chạm một ô để chọn và xem thử."),
        footer = tr("Nhân vật nhỏ ở góc phải thanh gợi ý: gõ thì nhảy — gõ càng nhanh nhảy càng sung — ngừng gõ thì cuộn tròn ngủ. Chỉ chuyển động khi đang gõ; Trình tiết kiệm pin chỉ hiện dáng đứng yên.")) {
        BuddyCharacter.entries.chunked(3).forEach { row ->
            Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 6.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                row.forEach { ch ->
                    val name by rememberStringPref(BuddyName.key(ch), "")
                    val locked = !BuddyGate.allows(ch)
                    val selected = current == ch
                    val style = (styles[ch] ?: BuddyStyle.DEFAULT).resolved(ch)
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Box(Modifier.fillMaxWidth().height(96.dp).clip(RoundedCornerShape(10.dp))
                            .border(if (selected) 3.dp else 1.dp, if (selected) c.accent else c.separator, RoundedCornerShape(10.dp))
                            .alpha(if (locked) 0.5f else 1f)) {
                            val play = plays[ch] ?: 0
                            AndroidView(factory = { BuddyPreviewView(it) }, modifier = Modifier.matchParentSize(),
                                update = { it.update(ch, style, season, palette, play) })
                            Box(Modifier.matchParentSize().clickable {
                                if (locked) onOpenPlus() else { raw = ch.id; plays[ch] = (plays[ch] ?: 0) + 1 }
                            })
                            if (selected) Text("✓", style = VTType.body, color = c.accent,
                                modifier = Modifier.align(Alignment.TopEnd).padding(6.dp))
                        }
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(name.ifEmpty { ch.title }, style = VTType.footnote, color = if (locked) c.secondary else c.label, maxLines = 1,
                                modifier = Modifier.weight(1f, fill = false))
                            if (locked && ch.isPlus) Text("Plus", style = VTType.caption2, color = Color.White,
                                modifier = Modifier.padding(start = 4.dp).background(Color(0xFFF5A623), RoundedCornerShape(50))
                                    .padding(horizontal = 5.dp, vertical = 1.dp))
                        }
                    }
                }
                repeat(3 - row.size) { Box(Modifier.weight(1f)) }
            }
        }
    }
    if (current != BuddyCharacter.OFF && BuddyGate.allows(current)) {
        var name by rememberStringPref(BuddyName.key(current), "")
        VTSection(header = tr("Đặt tên") + " · " + current.title) {
            VTRow { VTTextField(name, { name = BuddyName.clean(it) }, tr("Đặt tên"), maxLines = 1) }
        }
        val style = styles[current] ?: BuddyStyle.DEFAULT
        if (BuddyStyle.hasAtlas(current)) VTSection(header = tr("Kiểu vẽ") + " · " + current.title,
            footer = tr("Hoạt hình: hình vẽ sẵn, giữ nguyên quanh năm. Vẽ nét: mặc trang phục mùa lễ (Tết, Trung Thu, Halloween, Giáng sinh) và có thêm điệu nhảy.")) {
            VTRow {
                // Segmented như "Ngôn ngữ / Language" (LanguagePickerRow); đổi ⇒ ô xem thử diễn lại theo kiểu mới.
                Row(Modifier.weight(1f).clip(RoundedCornerShape(9.dp)).background(c.fill).padding(2.dp)) {
                    for (s in BuddyStyle.entries) {
                        val sel = style == s
                        Box(
                            Modifier.weight(1f).clip(RoundedCornerShape(7.dp))
                                .background(if (sel) c.card else Color.Transparent)
                                .clickable {
                                    if (!sel) {
                                        styles[current] = s
                                        Prefs.of(ctx).edit().putString(BuddyStyle.key(current), s.id).apply()
                                        plays[current] = (plays[current] ?: 0) + 1
                                    }
                                }
                                .padding(vertical = 6.dp),
                            contentAlignment = Alignment.Center,
                        ) { Text(s.title, style = VTType.subheadline, color = c.label) }
                    }
                }
            }
        } else {
            VTSection { VTRow { Text(tr("Chỉ có kiểu Vẽ nét"), style = VTType.footnote, color = c.secondary) } }
        }
        VTSection(header = tr("Vị trí & cỡ"),
            footer = tr("Chung cho mọi nhân vật. Lề phải dương: dời sang trái; lề trên dương: dời xuống. Bàn phím áp dụng lần hiện kế.")) {
            PlacementRow(tr("Cỡ"), "$size", size, BuddyPlacement.SIZE_RANGE) { size = it }
            RowDivider()
            PlacementRow(tr("Lề phải"), "$padRight dp", padRight, BuddyPlacement.PAD_RANGE, BuddyPlacement.PAD_STEP) { padRight = it }
            RowDivider()
            PlacementRow(tr("Lề trên"), "$padTop dp", padTop, BuddyPlacement.PAD_RANGE, BuddyPlacement.PAD_STEP) { padTop = it }
            RowDivider()
            val standard = size == BuddyPlacement.DEFAULT_SIZE && padRight == 0 && padTop == 0
            VTRow(onClick = if (standard) null else ({ size = BuddyPlacement.DEFAULT_SIZE; padRight = 0; padTop = 0 })) {
                Text(tr("Mặc định"), style = VTType.body, color = if (standard) c.tertiary else c.accent)
            }
        }
    }
    VTSection(header = tr("Sinh nhật của bạn"), footer = tr("Chỉ lưu trên thiết bị và trong bản sao lưu.")) {
        VTRow(onClick = { if (birthdayMonth == 0) { birthdayMonth = 1; birthdayDay = 1 } else { birthdayMonth = 0; birthdayDay = 0 } }) {
            Text(tr("Sinh nhật của bạn"), style = VTType.body, color = c.label)
            Spacer(Modifier.weight(1f))
            Text(if (birthdayMonth == 0) tr("Tắt") else "$birthdayDay/$birthdayMonth", style = VTType.body, color = c.secondary)
        }
        if (birthdayMonth > 0) {
            PlacementRow(tr("Tháng"), "$birthdayMonth", birthdayMonth, 1..12) {
                birthdayMonth = it; birthdayDay = minOf(birthdayDay, intArrayOf(31,29,31,30,31,30,31,31,30,31,30,31)[it - 1])
            }
            PlacementRow(tr("Ngày"), "$birthdayDay", birthdayDay,
                1..intArrayOf(31,29,31,30,31,30,31,31,30,31,30,31)[birthdayMonth - 1]) { birthdayDay = it }
        }
    }
}

/** Một dòng "Vị trí & cỡ": tên · giá trị · stepper − | +. */
@Composable
private fun PlacementRow(title: String, value: String, v: Int, range: IntRange, step: Int = 1, onChange: (Int) -> Unit) {
    val c = LocalVT.current
    VTRow {
        Text(title, style = VTType.body, color = c.label, modifier = Modifier.weight(1f))
        Text(value, style = VTType.body, color = c.secondary, modifier = Modifier.padding(end = 12.dp))
        IosStepper(v, range, step) { onChange(it) }
    }
}

/** Ô xem thử: nền theme + [BuddyView] cả người; "—" cho Tắt. Diễn: một tràng phím nhanh dần ~2,6 s rồi ngủ. */
@SuppressLint("ViewConstructor")
internal class BuddyPreviewView(context: Context) : FrameLayout(context) {
    private val d = context.resources.displayMetrics.density
    private var buddy: BuddyView? = null
    private var bg = 0
    private val dash = Paint(Paint.ANTI_ALIAS_FLAG).apply { textAlign = Paint.Align.CENTER; textSize = 28 * d }
    private var off = true
    private var lastPlay = -1
    private var presses = 0
    private val demo = object : Runnable {
        override fun run() {
            val b = buddy ?: return
            b.keyPressed()
            if (++presses < 24) postDelayed(this, 110)
        }
    }

    init { setWillNotDraw(false) }

    fun update(ch: BuddyCharacter, style: BuddyStyle, season: BuddySeason?, p: ThemePalette, play: Int) {
        bg = p.bg; dash.color = (p.ink and 0xFFFFFF) or 0x80000000.toInt()
        off = ch == BuddyCharacter.OFF
        if (off) { buddy?.let { it.halt(); removeView(it) }; buddy = null; invalidate(); return }
        if (buddy?.character != ch || buddy?.artStyle != style || buddy?.season != season) {
            buddy?.let { it.halt(); removeView(it) }
            val b = BuddyView(context, ch, d, com.viettelex.keyboard.BuddyHalo.opaque(p.bg, p.isDark), false, season, BuddyFraming.FULL,
                style).apply { maxFigureDp = 88f }
            val m = (4 * d).toInt()
            addView(b, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT).apply { setMargins(m, m, m, m) })
            buddy = b
        }
        buddy?.setBar(com.viettelex.keyboard.BuddyHalo.opaque(p.bg, p.isDark))
        if (play != lastPlay) { lastPlay = play; removeCallbacks(demo); presses = 0; post(demo) }
        invalidate()
    }

    override fun onDetachedFromWindow() { removeCallbacks(demo); buddy?.halt(); super.onDetachedFromWindow() }

    override fun onDraw(canvas: Canvas) {
        canvas.drawColor(bg)
        if (off) canvas.drawText("—", width / 2f, height / 2f + dash.textSize / 3f, dash)
    }
}
