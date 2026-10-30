package com.viettelex.android.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.viettelex.keyboard.HapticStrength
import com.viettelex.keyboard.KeySoundStyle
import com.viettelex.keyboard.PreviewThrottle
import com.viettelex.android.ime.KeyFeedbackPreview
import com.viettelex.android.ime.KeySoundImport
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.DisposableEffect
import android.os.SystemClock
import com.viettelex.keyboard.KeyAlternates
import com.viettelex.keyboard.Keys
import com.viettelex.keyboard.SpaceSideKey
import com.viettelex.keyboard.EmojiKeyPlacement
import com.viettelex.keyboard.KeyLabelSize
import com.viettelex.keyboard.PlusFeature
import com.viettelex.keyboard.PlusGate
import java.text.Normalizer
import java.util.Locale
import com.viettelex.keyboard.tr
import com.viettelex.keyboard.L10n
import com.viettelex.keyboard.L10nTable
import com.viettelex.android.shared.UiLang
import androidx.compose.ui.draw.clip
import androidx.compose.foundation.layout.widthIn
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import com.viettelex.keyboard.SuggestionCount

// Tab Tính Năng (27/09/2026): trang chính là 8 nhóm (icon + tên + tóm tắt trạng thái), mỗi
// nhóm mở một trang con — thay cho danh sách dài mọi công tắc. Ô tìm kiếm lọc theo tên/từ
// khoá rồi mở đúng trang. KHÔNG đổi key/mặc định: trang con đọc/ghi cùng SharedPreferences.
// Cùng cấu trúc với iOS (App/FeaturePages.swift).

internal val APPLY_NOTE get() = tr("Cài đặt áp dụng ngay lần mở bàn phím kế tiếp.")

/** [viTitle] = khoá dịch; hiển thị qua [title] (theo ngôn ngữ giao diện). */
enum class FeaturePage(val viTitle: String, val glyph: Glyph, val color: Color, val anchor: String, val enAnchor: String, val experimental: Boolean = false) {
    ChinhTa("Chính tả & sửa lỗi", Glyph.Spell, Color(0xFF34C759), "sua-dau", "fix-tones"), // l10n-key
    GoiY("Gợi ý & từ điển", Glyph.Bulb, Color(0xFFFF9500), "goi-y", "suggestions"), // l10n-key
    GoVuot("Gõ vuốt", Glyph.Swipe, Color(0xFFAF52DE), "go-vuot", "swipe", experimental = true), // l10n-key
    GoTat("Gõ tắt & mẫu câu", Glyph.Quote, Color(0xFF30B0C7), "go-tat", "shortcuts"), // l10n-key
    Phim("Phím & cử chỉ", Glyph.Keyboard, Color(0xFF8E8E93), "cu-chi", "gestures"), // l10n-key
    GiaoDien("Giao diện", Glyph.Palette, Color(0xFFFF2D55), "giao-dien", "look"), // l10n-key
    RiengTu("Riêng tư & clipboard", Glyph.Lock, Color(0xFF5856D6), "clipboard", "clipboard"), // l10n-key
    SaoLuu("Sao lưu & đồng bộ", Glyph.Cloud, Color(0xFF007AFF), "sao-luu", "backup"); // l10n-key

    val title: String get() = tr(viTitle)
    /** Hướng dẫn đúng ngôn ngữ: /hdsd/#… hoặc /en/guide/#… (anchor tiếng Anh khác). */
    val guideUrl: String get() = L10n.guideUrl("android", if (L10n.isEnglish) enAnchor else anchor)

    companion object {
        /** 3 khối như app Cài đặt. */
        val groups = listOf(listOf(ChinhTa, GoiY, GoVuot, GoTat), listOf(Phim, GiaoDien), listOf(RiengTu, SaoLuu))
    }
}

/**
 * Chỉ mục ô tìm kiếm: tên cài đặt ([viTitle] = khoá dịch) + từ khoá → trang chứa nó. Tìm khớp
 * CẢ tên tiếng Việt lẫn tên tiếng Anh (bất kể đang chọn ngôn ngữ nào) + từ khoá (Việt/Anh).
 */
internal data class FeatureSearchEntry(val viTitle: String, val keywords: String, val page: FeaturePage) {
    val title: String get() = tr(viTitle)
    val isPage: Boolean get() = viTitle == page.viTitle

    companion object {
        val all = listOf(
            FeatureSearchEntry("Tự khôi phục từ tiếng Anh", "english google restore", FeaturePage.ChinhTa), // l10n-key
            FeatureSearchEntry("Kiểm tra chính tả khi gõ", "spell check", FeaturePage.ChinhTa), // l10n-key
            FeatureSearchEntry("Sửa dấu từ đã gõ", "sửa dấu con trỏ backspace", FeaturePage.ChinhTa), // l10n-key
            FeatureSearchEntry("Chọn phím thông minh", "chạm trượt smart touch thử nghiệm experimental", FeaturePage.ChinhTa), // l10n-key
            FeatureSearchEntry("Tự sửa từ gõ sai", "autocorrect sửa lỗi thử nghiệm experimental", FeaturePage.ChinhTa), // l10n-key
            FeatureSearchEntry("Thanh gợi ý", "suggestion học từ", FeaturePage.GoiY), // l10n-key
            FeatureSearchEntry("Chip số", "số tiền đọc số number", FeaturePage.GoiY), // l10n-key
            FeatureSearchEntry("Hiện kết quả phép tính", "tính toán máy tính bằng math calculator", FeaturePage.GoiY), // l10n-key
            FeatureSearchEntry("Chip “Thêm dấu”", "thêm dấu câu không dấu plus", FeaturePage.GoiY), // l10n-key
            FeatureSearchEntry("Lọc từ nhạy cảm", "tục chửi filter", FeaturePage.GoiY), // l10n-key
            FeatureSearchEntry("Từ điển cá nhân", "dictionary tên riêng thuật ngữ", FeaturePage.GoiY), // l10n-key
            FeatureSearchEntry("Xóa từ đã học", "xoá học reset", FeaturePage.GoiY), // l10n-key
            FeatureSearchEntry("Gõ vuốt", "swipe vuốt thử nghiệm experimental", FeaturePage.GoVuot), // l10n-key
            FeatureSearchEntry("Hiệu ứng nét vuốt", "swipe trail nét vuốt vệt hiệu ứng lửa fire điện electric lightning bút lông brush mực ink cầu vồng rainbow neon bụi sao stardust sparkle pháo hoa firework theo giao diện theme plus", FeaturePage.GoVuot), // l10n-key
            FeatureSearchEntry("Vuốt từ tiếng Anh", "swipe english", FeaturePage.GoVuot), // l10n-key
            FeatureSearchEntry("Mô hình neural gõ vuốt", "futo neural swipe", FeaturePage.GoVuot), // l10n-key
            FeatureSearchEntry("Luyện vuốt", "practice swipe", FeaturePage.GoVuot), // l10n-key
            FeatureSearchEntry("Gõ tắt", "shortcut viết tắt", FeaturePage.GoTat), // l10n-key
            FeatureSearchEntry("Bảng gõ tắt", "shortcut yaml import export", FeaturePage.GoTat), // l10n-key
            FeatureSearchEntry("Mẫu câu", "template câu soạn sẵn", FeaturePage.GoTat), // l10n-key
            FeatureSearchEntry("Công cụ văn bản", "text tools hoa thường bỏ dấu dịch translate plus", FeaturePage.GoTat), // l10n-key
            FeatureSearchEntry("Dịch trên máy", "translate dịch ngôn ngữ language ml kit plus", FeaturePage.GoTat), // l10n-key
            FeatureSearchEntry("Hàng phím số", "number row số", FeaturePage.Phim), // l10n-key
            FeatureSearchEntry("Hàng số cao bằng hàng chữ", "number row tall height cao số", FeaturePage.Phim), // l10n-key
            FeatureSearchEntry("Phím cạnh dấu cách", "dấu phẩy dấu chấm cả hai comma period both key next to space", FeaturePage.Phim), // l10n-key
            FeatureSearchEntry("Nút emoji", "emoji biểu tượng cảm xúc thanh trên top bar toolbar", FeaturePage.Phim), // l10n-key
            FeatureSearchEntry("Cỡ chữ trên phím", "cỡ chữ to lớn font size label large key", FeaturePage.Phim), // l10n-key
            FeatureSearchEntry("Giữ phím hàng trên để ra số", "số giữ lâu number long press", FeaturePage.Phim), // l10n-key
            FeatureSearchEntry("Giữ phím hàng 2, 3 để ra ký tự đặc biệt", "ký hiệu symbol @ # giữ lâu long press", FeaturePage.Phim), // l10n-key
            FeatureSearchEntry("Giữ Shift để gõ số và ký hiệu", "shift giữ hold số number ký hiệu symbol 123", FeaturePage.Phim), // l10n-key
            FeatureSearchEntry("Vuốt phím cách đổi Tiếng Việt / Tiếng Anh", "space ngôn ngữ english language", FeaturePage.Phim), // l10n-key
            FeatureSearchEntry("Độ nhạy con trỏ", "trackpad con trỏ cursor phím cách space kéo tốc độ nhạy sensitivity speed", FeaturePage.Phim), // l10n-key
            FeatureSearchEntry("Vuốt phím để sao chép/dán", "copy paste cut undo redo select sao chép dán cắt hoàn tác chọn hết clipboard vuốt lên swipe", FeaturePage.Phim), // l10n-key
            FeatureSearchEntry("Chế độ một tay", "one hand một tay", FeaturePage.Phim), // l10n-key
            FeatureSearchEntry("Bàn phím thả nổi", "floating nổi kéo di chuyển float", FeaturePage.Phim), // l10n-key
            FeatureSearchEntry("Phóng to chữ khi bấm", "key preview popup", FeaturePage.Phim), // l10n-key
            FeatureSearchEntry("Phím sẫm khi bấm", "pressed key highlight darken", FeaturePage.Phim), // l10n-key
            FeatureSearchEntry("Rung phím", "haptic rung vibrate", FeaturePage.Phim), // l10n-key
            FeatureSearchEntry("Âm thanh phím", "sound click tiếng âm lượng volume kiểu style gỗ cơ máy chữ bong bóng custom", FeaturePage.Phim), // l10n-key
            FeatureSearchEntry("Âm thanh gõ", "typing sound key sound style kiểu âm hệ thống system click gỗ wood đá rock pop nước water cổ điển vintage pháo firecracker tết chuông jingle bell giáng sinh piano nốt nhạc đàn tranh dan tranh zither việt nam viet nam bàn phím cơ mechanical máy chữ typewriter bong bóng bubble ding sci-fi scifi bíp beep vũ trụ space trống lân lion drum trung thu mid autumn ma quái spooky boo halloween guitar ghi ta ghi-ta đàn ghi-ta acoustic hợp âm chord búa gỗ mallet bop", FeaturePage.Phim), // l10n-key
            FeatureSearchEntry("Telex cho bàn phím cứng", "bluetooth usb dex chromebook hardware", FeaturePage.Phim), // l10n-key
            FeatureSearchEntry("Theme & ảnh nền", "theme màu chủ đề wallpaper hình nền color tết tet năm mới lunar new year mai đào giáng sinh noel christmas xmas tuyết snow piano đàn dương cầm sen lotus hoa sen sen việt đàn tranh dan tranh zither việt nam viet nam máy chữ cổ typewriter vintage gaming rgb cầu vồng rainbow vũ trụ space sao star outer space trung thu mid autumn đèn lồng lantern trăng moon valentine tình yêu love tim heart halloween bí ngô pumpkin dơi bat guitar ghi ta ghi-ta đàn ghi-ta acoustic dây đàn strings đập chuột whack a mole", FeaturePage.GiaoDien), // l10n-key
            FeatureSearchEntry("Độ trong suốt phím", "trong suốt transparent", FeaturePage.GiaoDien), // l10n-key
            FeatureSearchEntry("Độ trong suốt ký tự", "trong suốt transparent chữ", FeaturePage.GiaoDien), // l10n-key
            FeatureSearchEntry("Tuỳ chỉnh nâng cao", "màu chữ màu phím màu nhấn accent color colour bo góc tròn vuông corner radius cỡ chữ size phông font độ đậm weight bold đặt lại reset mặc định giao diện theme", FeaturePage.GiaoDien), // l10n-key
            FeatureSearchEntry("Dán giao diện", "json theme giao diện chép copy paste dán sửa edit nhập import tự tạo custom chia sẻ share", FeaturePage.GiaoDien), // l10n-key
            FeatureSearchEntry("Bạn đồng hành", "bạn đồng hành nhân vật thú cưng mèo gà con cô gái chàng trai buddy keyboard buddy pet character mascot cat chick girl boy nhảy dance ngủ sleep plus", FeaturePage.GiaoDien), // l10n-key
            FeatureSearchEntry("Hiệu ứng khi bấm phím", "key press effect animation hoạt ảnh trái tim heart bong bóng bubble gợn sóng ripple cánh hoa petal pháo hoa firework nháy sáng flash matrix tia sét lightning emoji theo chữ emoji words hoa đào mai tết blossom lửa combo fire mực loang ink sóng nước water wave tuyết rơi snow giáng sinh christmas sao băng shooting star meteor vũ trụ space plus đèn lồng lantern glow trung thu mid autumn sương ma khói smoke spooky mist halloween rung dây string vibration guitar ghi ta đàn ghi-ta", FeaturePage.GiaoDien), // l10n-key
            FeatureSearchEntry("Đập chuột", "đập chuột trò chơi game whack a mole chuột mouse theme giao diện vui fun plus", FeaturePage.GiaoDien), // l10n-key
            FeatureSearchEntry("Màu nhấn", "accent color colour nhập enter return shift tuỳ chỉnh nâng cao", FeaturePage.GiaoDien), // l10n-key
            FeatureSearchEntry("Khôi phục giao diện gốc", "reset mặc định default", FeaturePage.GiaoDien), // l10n-key
            FeatureSearchEntry("Chiều cao hàng phím", "height cao thấp", FeaturePage.GiaoDien), // l10n-key
            FeatureSearchEntry("Màu chữ gợi ý", "suggestion text color colour xám grey gray sáng bright thanh gợi ý chữ mờ dịu", FeaturePage.GiaoDien), // l10n-key
            FeatureSearchEntry("Hiện logo Vᴛ", "logo phím cách space", FeaturePage.GiaoDien), // l10n-key
            FeatureSearchEntry("Bàn phím tách đôi", "split tách chia hai nửa gập ngang fold foldable tablet máy tính bảng", FeaturePage.GiaoDien), // l10n-key
            FeatureSearchEntry("Lịch sử clipboard", "copy dán clipboard paste giữ lịch sử 24 giờ 7 ngày keep history", FeaturePage.RiengTu), // l10n-key
            FeatureSearchEntry("Chế độ ẩn danh", "incognito riêng tư privacy", FeaturePage.RiengTu), // l10n-key
            FeatureSearchEntry("Xuất / nhập file sao lưu", "backup export import restore", FeaturePage.SaoLuu), // l10n-key
        )

        /** Bỏ dấu + chữ thường ("trong suot" khớp "trong suốt"). */
        fun fold(s: String): String =
            Normalizer.normalize(s.replace('đ', 'd').replace('Đ', 'D'), Normalizer.Form.NFD)
                .replace(Regex("\\p{Mn}+"), "").lowercase(Locale.ROOT)

        /** Chữ để khớp: tên Việt + tên Anh + từ khoá — tìm được bằng cả hai ngôn ngữ. */
        private fun haystack(e: FeatureSearchEntry): String =
            fold(e.viTitle + " " + (L10nTable.EN[e.viTitle] ?: "") + " " + e.keywords)

        fun search(query: String): List<FeatureSearchEntry> {
            val words = fold(query).split(' ').filter { it.isNotBlank() }
            if (words.isEmpty()) return emptyList()
            val pages = FeaturePage.entries.map { FeatureSearchEntry(it.viTitle, "", it) }
            return (pages + all).filter { e -> haystack(e).let { h -> words.all { h.contains(it) } } }
        }
    }
}

/** Nhãn picker ngôn ngữ — giống hệt ở hai ngôn ngữ (người không đọc được tiếng Việt vẫn thấy). */
internal const val LANGUAGE_TITLE = "Ngôn ngữ / Language" // l10n-skip: song ngữ sẵn

// ---------------------------------------------------------------- khối dùng chung

@Composable
internal fun ExperimentalBadge() {
    Text(tr("Thử nghiệm"), style = VTType.caption2.copy(fontWeight = FontWeight.SemiBold), color = Color(0xFFAF52DE),
        modifier = Modifier.background(Color(0xFFAF52DE).copy(alpha = 0.15f), RoundedCornerShape(50))
            .padding(horizontal = 6.dp, vertical = 1.dp))
}

/** "Ngôn ngữ / Language": Tiếng Việt | English (segmented, như picker Kiểu gõ). */
@Composable
internal fun LanguagePickerRow() {
    val c = LocalVT.current
    val ctx = LocalContext.current
    val lang = UiLang.state.value
    VTRow {
        GlyphIcon(Glyph.Globe, c.accent, 20.dp)
        Text(LANGUAGE_TITLE, style = VTType.body, color = c.label,
            modifier = Modifier.weight(1f).padding(start = 12.dp, end = 8.dp))
        Row(Modifier.clip(RoundedCornerShape(9.dp)).background(c.fill).padding(2.dp)) {
            for ((code, label) in listOf(L10n.VI to "Tiếng Việt", L10n.EN to "English")) { // l10n-skip: tên ngôn ngữ giữ nguyên
                val sel = lang == code
                Box(
                    Modifier.clip(RoundedCornerShape(7.dp))
                        .background(if (sel) c.card else Color.Transparent)
                        .clickable { if (!sel) UiLang.select(ctx, code) }
                        .padding(horizontal = 12.dp, vertical = 6.dp),
                ) { Text(label, style = VTType.subheadline, color = c.label) }
            }
        }
    }
}

/** Toggle có nhãn "Thử nghiệm". */
@Composable
internal fun ExperimentalToggle(key: String, default: Boolean, title: String, caption: String) {
    val c = LocalVT.current
    var v by rememberBoolPref(key, default)
    VTRow(onClick = { v = !v }) {
        Column(Modifier.weight(1f).padding(end = 12.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(title, style = VTType.body, color = c.label)
                ExperimentalBadge()
            }
            Text(caption, style = VTType.footnote, color = c.secondary)
        }
        IosSwitch(v) { v = it }
    }
}

@Composable
private fun FeatureIcon(p: FeaturePage) {
    Box(Modifier.size(29.dp).background(p.color, RoundedCornerShape(7.dp)), contentAlignment = Alignment.Center) {
        GlyphIcon(p.glyph, Color.White, 18.dp)
    }
}

@Composable
private fun FeatureRow(p: FeaturePage, title: String, subtitle: String, badge: Boolean, onClick: () -> Unit) {
    val c = LocalVT.current
    VTRow(onClick = onClick) {
        FeatureIcon(p)
        Column(Modifier.weight(1f).padding(start = 12.dp, end = 8.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(title, style = VTType.body, color = c.label)
                if (badge) ExperimentalBadge()
            }
            Text(subtitle, style = VTType.footnote, color = c.secondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        Text("›", style = VTType.title3, color = c.tertiary)
    }
}

/** Đầu trang con: "‹ Tính Năng" + tên nhóm. */
@Composable
internal fun SubPageHeader(title: String, onBack: () -> Unit) {
    val c = LocalVT.current
    BackHandler(onBack = onBack)
    VTRow(onClick = onBack) { Text(tr("‹ Tính Năng"), style = VTType.body, color = c.accent) }
    Text(title, style = VTType.title2, color = c.label, modifier = Modifier.padding(start = 20.dp, top = 2.dp, bottom = 12.dp))
}

/** Link "Tìm hiểu thêm" cuối mỗi trang con. */
@Composable
internal fun GuideLinkSection(p: FeaturePage) {
    val ctx = LocalContext.current
    VTSection(footer = APPLY_NOTE) {
        LinkRow(Glyph.Info, tr("Tìm hiểu thêm trong Hướng dẫn")) { openUrl(ctx, p.guideUrl) }
    }
}

// ---------------------------------------------------------------- trang chính

@Composable
fun TinhNangTab(openRequest: FeaturePage? = null, onOpened: () -> Unit = {}, onOpenPlus: () -> Unit = {}) {
    var open by rememberSaveable { mutableStateOf<String?>(null) }
    // Màn Plus chạm một quyền lợi ⇒ mở thẳng trang chứa cài đặt của nó.
    androidx.compose.runtime.LaunchedEffect(openRequest) { if (openRequest != null) { open = openRequest.name; onOpened() } }
    val page = open?.let { n -> FeaturePage.entries.firstOrNull { it.name == n } }
    if (page != null) {
        val back = { open = null }
        when (page) {
            FeaturePage.ChinhTa -> ChinhTaPage(back)
            FeaturePage.GoiY -> GoiYPage(back)
            FeaturePage.GoVuot -> GoVuotPage(back, onOpenPlus)
            FeaturePage.GoTat -> GoTatPage(back)
            FeaturePage.Phim -> PhimPage(back)
            FeaturePage.GiaoDien -> ThemePage(back, onOpenPlus)
            FeaturePage.RiengTu -> { SubPageHeader(page.title, back); PrivacySection(); GuideLinkSection(page) }
            FeaturePage.SaoLuu -> { SubPageHeader(page.title, back); SaoLuuSection(onOpenPlus); GuideLinkSection(page) }
        }
        return
    }
    FeatureHome { open = it.name }
}

@Composable
private fun FeatureHome(onOpen: (FeaturePage) -> Unit) {
    val c = LocalVT.current
    val ctx = LocalContext.current
    var query by rememberSaveable { mutableStateOf("") }

    val autoRestore by rememberBoolPref(Keys.AUTO_RESTORE, Prefs.D.autoRestore)
    val liveSpell by rememberBoolPref(Keys.LIVE_SPELL_CHECK, Prefs.D.liveSpellCheck)
    val reEdit by rememberBoolPref(Keys.RE_EDIT_WORDS, Prefs.D.reEditWords)
    val autoCorrect by rememberBoolPref(Keys.AUTO_CORRECT, Prefs.D.autoCorrect)
    val suggestions by rememberBoolPref(Keys.SHOW_SUGGESTIONS, Prefs.D.showSuggestions)
    val numberChips by rememberBoolPref(Keys.NUMBER_CHIPS, Prefs.D.numberChips)
    val addTones by rememberBoolPref(Keys.ADD_TONES_CHIP, Prefs.D.addTonesChip)
    val swipe by rememberBoolPref(Keys.SWIPE_TYPING, Prefs.D.swipeTyping)
    val swipeEn by rememberBoolPref(Keys.SWIPE_ENGLISH, Prefs.D.swipeEnglish)
    val swipeFuto by rememberBoolPref(Keys.SWIPE_FUTO, Prefs.D.swipeFuto)
    val shortcutsOn by rememberBoolPref(Keys.SHORTCUTS_ENABLED, Prefs.D.shortcutsEnabled)
    val templatesOn by rememberBoolPref(Keys.TEMPLATES_ENABLED, Prefs.D.templatesEnabled)
    val numberRow by rememberBoolPref(Keys.NUMBER_ROW, Prefs.D.numberRow)
    val spaceSwipe by rememberBoolPref(Keys.SPACE_SWIPE_LANGUAGE, Prefs.D.spaceSwipeLanguage)
    val keyCmds by rememberBoolPref(Keys.SWIPE_KEY_COMMANDS, Prefs.D.swipeKeyCommands)
    val autoSpace by rememberBoolPref(Keys.AUTO_SPACE_AFTER_PUNCT, Prefs.D.autoSpaceAfterPunct)
    val haptic by rememberBoolPref(Keys.HAPTIC_FEEDBACK, Prefs.D.hapticFeedback)
    val keySound by rememberBoolPref(Keys.KEY_SOUND, Prefs.D.keySound)
    val oneHand by rememberStringPref(Keys.ONE_HAND_MODE, Prefs.D.oneHandMode)
    val sideKey by rememberStringPref(Keys.SPACE_SIDE_KEY, Prefs.D.spaceSideKey.id)
    val emojiPlace by rememberStringPref(Keys.EMOJI_KEY_PLACEMENT, Prefs.D.emojiKeyPlacement.id)
    val labelSize by rememberStringPref(Keys.KEY_LABEL_SIZE, Prefs.D.keyLabelSize.id)
    val floating by rememberBoolPref(Keys.FLOATING_KEYBOARD, Prefs.D.floatingKeyboard)
    val hardware by rememberBoolPref(Keys.HARDWARE_TELEX, Prefs.D.hardwareTelex)
    val clipHistory by rememberBoolPref(Keys.CLIPBOARD_HISTORY, Prefs.D.clipboardHistory)
    val incognito by rememberBoolPref(Keys.INCOGNITO, Prefs.D.incognito)
    val shortcutCount = remember { ShortcutsStore.load(ctx).size }
    val theme = remember { loadThemeSettings(ctx) }
    val wallpaperOn = remember { theme.wallpaperActive(WallpaperStore.file(ctx).exists()) }

    fun join(vararg parts: Pair<Boolean, String>, none: String) =
        parts.filter { it.first }.joinToString(" · ") { it.second }.ifEmpty { none }

    fun summary(p: FeaturePage): String = when (p) {
        FeaturePage.ChinhTa -> join(autoRestore to tr("Khôi phục tiếng Anh"), liveSpell to tr("Kiểm tra chính tả"),
            reEdit to tr("Sửa dấu"), autoCorrect to tr("Tự sửa"), none = tr("Đang tắt"))
        FeaturePage.GoiY -> if (!suggestions) tr("Tắt thanh gợi ý")
            else join(true to tr("Thanh gợi ý"), numberChips to tr("Chip số"), addTones to tr("Thêm dấu"), none = "")
        FeaturePage.GoVuot -> if (!swipe) tr("Đang tắt") else join(true to tr("Bật"), swipeEn to tr("Tiếng Anh"), swipeFuto to "Neural", none = "")
        FeaturePage.GoTat -> (if (!shortcutsOn) tr("Gõ tắt tắt") else if (shortcutCount == 0) tr("Gõ tắt bật") else tr("Gõ tắt: %d mục", shortcutCount)) +
            " · " + if (templatesOn) tr("Mẫu câu bật") else tr("Mẫu câu tắt")
        FeaturePage.Phim -> join(numberRow to tr("Hàng số"),
            (SpaceSideKey.of(sideKey) != SpaceSideKey.DEFAULT) to tr("Phím cạnh dấu cách"),
            (EmojiKeyPlacement.of(emojiPlace) != EmojiKeyPlacement.DEFAULT) to tr("Nút emoji"),
            (KeyLabelSize.of(labelSize) != KeyLabelSize.DEFAULT) to tr("Cỡ chữ trên phím"), spaceSwipe to tr("Vuốt phím cách"),
            keyCmds to tr("Vuốt sao chép/dán"),
            autoSpace to tr("Cách sau dấu câu"), haptic to tr("Rung"), keySound to tr("Âm"),
            (oneHand != "off") to tr("Một tay"), floating to tr("Thả nổi"), hardware to tr("Bàn phím cứng"), none = tr("Mặc định"))
        FeaturePage.GiaoDien -> theme.effectiveTheme.title + (if (wallpaperOn) " · " + tr("Ảnh nền") else "") +
            if (theme.keyboardTransparency > 0 || theme.labelTransparency > 0) " · " + tr("Trong suốt") else ""
        FeaturePage.RiengTu -> (if (clipHistory) tr("Lịch sử clipboard bật") else tr("Lịch sử clipboard tắt")) +
            if (incognito) " · " + tr("Ẩn danh") else ""
        FeaturePage.SaoLuu -> tr("Xuất / nhập file")
    }

    // Ngôn ngữ giao diện — mục ĐẦU TIÊN của Tính Năng, nhãn song ngữ (ai không đọc được tiếng
    // Việt vẫn tìm ra). Đổi là áp dụng ngay cho cả app (L10n → recompose), bàn phím lần hiện kế.
    VTSection { LanguagePickerRow() }

    VTSection {
        VTRow {
            GlyphIcon(Glyph.Search, c.secondary, 18.dp)
            Box(Modifier.weight(1f).padding(start = 10.dp)) {
                VTTextField(query, { query = it }, tr("Tìm cài đặt…"), capitalization = KeyboardCapitalization.None)
            }
            if (query.isNotEmpty()) {
                Text("✕", style = VTType.body, color = c.tertiary,
                    modifier = Modifier.clickable { query = "" }.padding(start = 8.dp))
            }
        }
    }

    if (query.isBlank()) {
        FeaturePage.groups.forEach { group ->
            VTSection {
                group.forEachIndexed { i, p ->
                    if (i > 0) RowDivider(57.dp)
                    FeatureRow(p, p.title, summary(p), p.experimental) { onOpen(p) }
                }
            }
        }
    } else {
        val hits = FeatureSearchEntry.search(query)
        VTSection(header = tr("Kết quả")) {
            if (hits.isEmpty()) VTRow { Text(tr("Không tìm thấy cài đặt nào."), style = VTType.body, color = c.secondary) }
            hits.forEachIndexed { i, e ->
                if (i > 0) RowDivider(57.dp)
                val isPage = e.isPage
                FeatureRow(e.page, e.title, if (isPage) summary(e.page) else e.page.title, isPage && e.page.experimental) { onOpen(e.page) }
            }
        }
    }
}

// ---------------------------------------------------------------- trang con

@Composable
private fun ChinhTaPage(onBack: () -> Unit) {
    SubPageHeader(FeaturePage.ChinhTa.title, onBack)
    VTSection(header = tr("Chính tả")) {
        BoolToggle(Keys.AUTO_RESTORE, Prefs.D.autoRestore, tr("Tự khôi phục từ tiếng Anh"), tr("Từ không phải tiếng Việt trả về như đã gõ (google, github…)."))
        RowDivider()
        BoolToggle(Keys.LIVE_SPELL_CHECK, Prefs.D.liveSpellCheck, tr("Kiểm tra chính tả khi gõ"), tr("Ngừng bỏ dấu khi từ không thể là tiếng Việt."))
        RowDivider()
        BoolToggle(Keys.RE_EDIT_WORDS, Prefs.D.reEditWords, tr("Sửa dấu từ đã gõ"), tr("⌫ ngay sau dấu cách để sửa tiếp từ vừa gõ (tháy ␣ ⌫ a → thấy), hoặc đặt con trỏ sau từ rồi gõ phím dấu: chao + f → chào."))
    }
    VTSection(header = tr("Chạm trượt"), footer = tr("Gợi ý sửa lỗi chạm trượt (hiện trên thanh gợi ý) nằm ở tab Kiểu Gõ.")) {
        ExperimentalToggle(Keys.SMART_TOUCH, Prefs.D.smartTouch, tr("Chọn phím thông minh"),
            tr("Chạm sát mép giữa hai phím thì chọn phím hợp với chữ đang gõ. Chạm giữa phím luôn ra đúng phím đó."))
        RowDivider()
        ExperimentalToggle(Keys.AUTO_CORRECT, Prefs.D.autoCorrect, tr("Tự sửa từ gõ sai"),
            tr("Khi gõ dấu cách, sửa từ lỡ chạm phím kề (tpoi → tôi) nếu chắc chắn. ⌫ ngay sau đó để trả lại chữ gốc."))
    }
    GuideLinkSection(FeaturePage.ChinhTa)
}

@Composable
private fun GoiYPage(onBack: () -> Unit) {
    val c = LocalVT.current
    val ctx = LocalContext.current
    SubPageHeader(FeaturePage.GoiY.title, onBack)
    VTSection(header = tr("Thanh gợi ý")) {
        BoolToggle(Keys.SHOW_SUGGESTIONS, Prefs.D.showSuggestions, tr("Thanh gợi ý"), tr("Gợi ý từ + emoji, tự học từ bạn hay dùng (chỉ trên máy)."))
        RowDivider()
        SuggestionCountRow()
        RowDivider()
        BoolToggle(Keys.SUGGEST_IN_NO_SUGGEST_FIELDS, Prefs.D.suggestInNoSuggestFields, tr("Gợi ý cả khi ứng dụng tắt gợi ý"),
            tr("Ô mà ứng dụng tắt gợi ý (vd ô chat, thanh địa chỉ) vẫn gợi ý từ — không tự sửa, không học từ gõ ở đó. Mật khẩu, ẩn danh, ô số không bị ảnh hưởng."))
        RowDivider()
        BoolToggle(Keys.NUMBER_CHIPS, Prefs.D.numberChips, tr("Chip số"), tr("Đọc số thành chữ, định dạng tiền (1tr2 → 1.200.000 ₫)."))
        RowDivider()
        BoolToggle(Keys.MATH_RESULTS, Prefs.D.mathResults, tr("Hiện kết quả phép tính"), tr("Gõ phép tính (12*3, không cần dấu =) → kết quả “= 36” hiện ở đầu thanh gợi ý, chạm để chèn. Dấu = ở bàn 123: giữ phím /."))
        RowDivider()
        BoolToggle(Keys.ADD_TONES_CHIP, Prefs.D.addTonesChip, tr("Chip “Thêm dấu”"),
            tr("Gõ không dấu cả câu (hom nay troi dep), gõ dấu cách → chip “Thêm dấu” hiện ở đầu thanh gợi ý, chạm để thành “hôm nay trời đẹp”; chạm “Hoàn tác” để trả lại. Tắt mặc định cho nhẹ máy."))
        RowDivider()
        BoolToggle(Keys.FILTER_SENSITIVE, Prefs.D.filterSensitive, tr("Lọc từ nhạy cảm"), tr("Không chủ động gợi ý từ tục — gõ tay vẫn bình thường."))
    }
    VTSection(header = tr("Từ đã học")) {
        var showDict by remember { mutableStateOf(false) }
        VTRow(onClick = { showDict = true }) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(tr("Từ điển cá nhân"), style = VTType.body, color = c.label)
                Text(tr("Xem, tìm, xoá từ đã học; thêm tên riêng."), style = VTType.footnote, color = c.secondary)
            }
            Text("›", style = VTType.title3, color = c.tertiary)
        }
        if (showDict) UserDictDialog { showDict = false }
        RowDivider()
        // Xoá không hoàn tác được ⇒ hỏi lại; xong thì báo ngay tại dòng.
        var confirmErase by remember { mutableStateOf(false) }
        var erased by remember { mutableStateOf(false) }
        VTRow(onClick = { confirmErase = true }) {
            Text(tr("Xóa từ đã học"), style = VTType.body, color = c.red, modifier = Modifier.weight(1f))
            if (erased) Text(tr("Đã xoá"), style = VTType.footnote, color = c.secondary)
        }
        if (confirmErase) androidx.compose.material3.AlertDialog(
            onDismissRequest = { confirmErase = false },
            title = { Text(tr("Xóa từ đã học?")) },
            text = { Text(tr("Bàn phím quên mọi từ đã học trên máy này, kể cả từ thêm tay trong từ điển cá nhân. Không hoàn tác được.")) },
            confirmButton = {
                androidx.compose.material3.TextButton(onClick = {
                    confirmErase = false
                    java.io.File(ctx.filesDir, Keys.USERLM_FILE).delete()
                    // IME (process khác) nhận mốc đổi qua PrefSync ⇒ bỏ model trong RAM, seed lại, không ghi đè.
                    Prefs.of(ctx).edit().putLong(Keys.USERLM_RESET_AT, System.currentTimeMillis()).apply()
                    erased = true
                }) { Text(tr("Xoá"), color = c.red) }
            },
            dismissButton = { androidx.compose.material3.TextButton(onClick = { confirmErase = false }) { Text(tr("Huỷ"), color = c.accent) } },
        )
    }
    GuideLinkSection(FeaturePage.GoiY)
}

@Composable
private fun GoVuotPage(onBack: () -> Unit, onOpenPlus: () -> Unit = {}) {
    val c = LocalVT.current
    val ctx = LocalContext.current
    /** Trang con "Hiệu ứng nét vuốt" đang mở. */
    var pickingTrail by remember { mutableStateOf(false) }
    if (pickingTrail) { SwipeTrailPage(onOpenPlus = onOpenPlus, onBack = { pickingTrail = false }); return }
    val trailRaw by rememberStringPref(Keys.SWIPE_TRAIL, com.viettelex.keyboard.SwipeTrailStyle.DEFAULT.id)
    SubPageHeader(FeaturePage.GoVuot.title, onBack)
    val swipeOn by rememberBoolPref(Keys.SWIPE_TYPING, Prefs.D.swipeTyping)
    VTSection(footer = tr("Tự tắt khi bật TalkBack và ở ô mật khẩu, email, địa chỉ web.")) {
        ExperimentalToggle(Keys.SWIPE_TYPING, Prefs.D.swipeTyping, tr("Gõ vuốt"),
            tr("Lướt qua các chữ không dấu rồi nhấc tay: viet → việt. Gõ phím dấu ngay sau để đổi dấu, ⌫ xoá cả từ."))
        if (swipeOn) {
            RowDivider()
            BoolToggle(Keys.SWIPE_ENGLISH, Prefs.D.swipeEnglish, tr("Vuốt từ tiếng Anh"),
                tr("check, mail, meeting… Nét vừa Việt vừa Anh (the/thế) ưu tiên tiếng Việt, phương án kia ở thanh gợi ý."))
            RowDivider()
            BoolToggle(Keys.SWIPE_FUTO, Prefs.D.swipeFuto, tr("Mô hình neural gõ vuốt"),
                tr("Mạng neural chạy hoàn toàn trên máy, chấm cùng bộ giải mã. Tốn thêm ~3 MB bộ nhớ."))
            // Ghi công BẮT BUỘC theo FUTO Model Weights License 1.0 ("visible notice … within
            // the product's settings") — Phil 27/09/2026: chỉ hiện ở đây (dưới công tắc, khi đã
            // bật Gõ vuốt), chữ nhỏ mờ. KHÔNG xoá. Xem docs/DATA-SOURCES.md.
            VTRow(onClick = { openUrl(ctx, "https://github.com/ptrinh/viettelex/blob/main/docs/DATA-SOURCES.md#futo-swipe") }) {
                Text("powered by FUTO Swipe", style = VTType.caption2, color = c.tertiary)
            }
        }
    }
    VTSection {
        VTRow(onClick = { pickingTrail = true }) {
            val plus = com.viettelex.keyboard.SwipeTrailGate.allows
            Text(tr("Hiệu ứng nét vuốt") + if (plus) "" else " · Plus", style = VTType.body, color = c.label,
                modifier = Modifier.weight(1f))
            Text("${com.viettelex.keyboard.SwipeTrailStyle.displayed(trailRaw).title} ›", style = VTType.body,
                color = c.secondary, maxLines = 1)
        }
    }
    if (swipeOn) {
        VTSection {
            var showPractice by remember { mutableStateOf(false) }
            VTRow(onClick = { showPractice = true }) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(tr("Luyện vuốt"), style = VTType.body, color = c.label)
                    Text(tr("Vuốt thử từng từ, xem bàn phím đọc đúng bao nhiêu."), style = VTType.footnote, color = c.secondary)
                }
                Text("›", style = VTType.title3, color = c.tertiary)
            }
            if (showPractice) SwipePracticeDialog { showPractice = false }
        }
    }
    GuideLinkSection(FeaturePage.GoVuot)
}

@Composable
private fun GoTatPage(onBack: () -> Unit) {
    // Trang con "Bảng gõ tắt" (như NavigationLink iOS) — ⟵ hệ thống quay lại.
    var showShortcuts by rememberSaveable { mutableStateOf(false) }
    if (showShortcuts) { ShortcutsPage { showShortcuts = false }; return }
    SubPageHeader(FeaturePage.GoTat.title, onBack)
    ShortcutsSection { showShortcuts = true }
    VTSection(header = tr("Mẫu câu")) {
        BoolToggle(Keys.TEMPLATES_ENABLED, Prefs.D.templatesEnabled, tr("Mẫu câu"), tr("Nút ☰ trên bàn phím chèn câu soạn sẵn — quản lý ở tab Mẫu Câu. Tắt: ẩn tab Mẫu Câu; nút ☰ chỉ còn mở Công cụ văn bản (nếu bật)."))
        RowDivider()
        // Luôn hiện (tìm "Công cụ văn bản" phải tới được đây); chưa có Plus ⇒ dòng khoá.
        if (PlusGate.isUnlocked(PlusFeature.TEXT_TOOLS)) {
            BoolToggle(Keys.TEXT_TOOLS_ENABLED, Prefs.D.textToolsEnabled, tr("Công cụ văn bản"),
                tr("Chip ⚒️ Công cụ trong lưới mẫu câu (Mẫu câu tắt: chạm ☰ mở thẳng): đổi HOA/thường, bỏ dấu, dịch…"))
        } else PlusLockedRow(tr("Công cụ văn bản"), tr("Chip ⚒️ Công cụ trong lưới mẫu câu: đổi HOA/thường, bỏ dấu, dịch…"))
    }
    // Dịch trên máy (Plus): cài đặt ở đây (cạnh Công cụ) — APK ngoài Play không tải được module ⇒ ẩn.
    if (com.viettelex.android.translate.TranslateFeature.offered(LocalContext.current)) {
        VTSection(header = PlusFeature.TRANSLATE.title) {
            if (PlusGate.isUnlocked(PlusFeature.TRANSLATE)) TranslateSettings(leadingDivider = false)
            else PlusLockedRow(PlusFeature.TRANSLATE.title, PlusFeature.TRANSLATE.detail)
        }
    }
    GuideLinkSection(FeaturePage.GoTat)
}

/** Tính năng Plus chưa mở khoá: vẫn hiện (tìm kiếm tới được) với nhãn khoá, không công tắc. */
@Composable
private fun PlusLockedRow(title: String, caption: String) {
    val c = LocalVT.current
    VTRow {
        Column(Modifier.weight(1f).padding(end = 12.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, style = VTType.body, color = c.secondary)
            Text(caption, style = VTType.footnote, color = c.secondary)
        }
        Text(tr("🔒 Plus"), style = VTType.footnote, color = c.accent)
    }
}

/** Hàng chọn một trong vài giá trị chuỗi (nút bấm chia đều): tiêu đề + chú thích + các ô. */
@Composable
internal fun ChoiceRow(key: String, default: String, title: String, caption: String,
                      options: List<Pair<String, String>>, normalize: (String) -> String = { it }) {
    val c = LocalVT.current
    var mode by rememberStringPref(key, default)
    VTRow {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, style = VTType.body, color = c.label)
            Text(caption, style = VTType.footnote, color = c.secondary)
        }
    }
    Row(Modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, bottom = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        for ((v, t) in options) {
            val on = normalize(mode) == v
            Box(Modifier.weight(1f)
                .background(if (on) c.accent else c.secondary.copy(alpha = 0.12f), RoundedCornerShape(10.dp))
                .clickable { mode = v }
                .padding(vertical = 8.dp), contentAlignment = Alignment.Center) {
                // 4 ô trên điện thoại hẹp ⇒ chữ nhỏ hơn một bậc cho vừa một dòng.
                Text(t, style = if (options.size > 3) VTType.subheadline else VTType.body, maxLines = 1,
                    color = if (on) Color.White else c.label)
            }
        }
    }
}

/**
 * "Phím cạnh dấu cách": Dấu phẩy (mặc định) / Dấu chấm / Cả hai / Tắt — bàn chữ ô thường
 * (điện thoại: phím hẹp, Cả hai = "," trái + "." phải; tablet: "," "." hai bên space hoặc không).
 */
@Composable
private fun SpaceSideKeyRow() = ChoiceRow(Keys.SPACE_SIDE_KEY, Prefs.D.spaceSideKey.id, tr("Phím cạnh dấu cách"),
    tr("Điện thoại: phím hẹp cạnh phím cách trên bàn chữ; Cả hai: dấu phẩy bên trái, dấu chấm bên phải phím cách. Máy tính bảng: Dấu phẩy, Dấu chấm hay Cả hai đều giữ hai phím , và . hai bên phím cách; Tắt bỏ cả hai. Ô email, đường dẫn giữ nguyên. Giữ dấu phẩy để chọn dấu câu khác. Tắt: phím cách rộng hơn; chạm phím cách hai lần vẫn ra dấu chấm."),
    listOf(SpaceSideKey.COMMA.id to tr("Dấu phẩy"), SpaceSideKey.PERIOD.id to tr("Dấu chấm"),
        SpaceSideKey.BOTH.id to tr("Cả hai"), SpaceSideKey.OFF.id to tr("Tắt"))) { SpaceSideKey.of(it).id }

/**
 * "Số từ gợi ý" ([SuggestionCount]): một hàng gọn − [giá trị] +, Tự động → 1 → … → 5 (− ở 1 về
 * Tự động; hai đầu thì nút mờ). Cùng khoá + giá trị iOS.
 */
@Composable
private fun SuggestionCountRow() {
    val c = LocalVT.current
    var v by rememberIntPref(Keys.SUGGESTION_COUNT, Prefs.D.suggestionCount)
    val n = SuggestionCount.parse(v)
    val value = if (n <= SuggestionCount.AUTO) tr("Tự động") else n.toString()
    VTRow {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(tr("Số từ gợi ý"), style = VTType.body, color = c.label)
            Text(tr("Tự động: 3 từ. Máy hẹp có thể hiện ít hơn để ô đủ rộng cho dễ chạm."),
                style = VTType.footnote, color = c.secondary)
        }
        Row(Modifier.padding(start = 8.dp).clip(RoundedCornerShape(9.dp)).background(c.fill),
            verticalAlignment = Alignment.CenterVertically) {
            StepButton("−", tr("Bớt một từ gợi ý"), n > SuggestionCount.AUTO) { v = SuggestionCount.step(n, -1) }
            Text(value, style = VTType.body, color = c.label, textAlign = TextAlign.Center, maxLines = 1,
                modifier = Modifier.widthIn(min = 64.dp).semantics { contentDescription = tr("Số từ gợi ý") + ": " + value })
            StepButton("+", tr("Thêm một từ gợi ý"), n < SuggestionCount.MAX) { v = SuggestionCount.step(n, 1) }
        }
    }
}

@Composable
private fun StepButton(symbol: String, description: String, enabled: Boolean, onClick: () -> Unit) {
    val c = LocalVT.current
    Box(Modifier.size(44.dp).clickable(enabled = enabled, onClick = onClick).semantics { contentDescription = description },
        contentAlignment = Alignment.Center) {
        Text(symbol, style = VTType.title3, color = if (enabled) c.accent else c.tertiary)
    }
}

/** "Nút emoji": Hàng dưới (mặc định) / Thanh trên — [EmojiKeyPlacement]. */
@Composable
private fun EmojiPlacementRow() = ChoiceRow(Keys.EMOJI_KEY_PLACEMENT, Prefs.D.emojiKeyPlacement.id, tr("Nút emoji"),
    tr("Thanh trên: nút emoji lên thanh gợi ý (sát mép phải), phím cách rộng hơn. Giữ nút để đổi bàn phím, gõ giọng nói, một tay… Khi thanh gợi ý không hiện, nút vẫn ở hàng dưới."),
    listOf(EmojiKeyPlacement.BOTTOM.id to tr("Hàng dưới"), EmojiKeyPlacement.TOP.id to tr("Thanh trên"))) { EmojiKeyPlacement.of(it).id }

/** "Cỡ chữ trên phím": Vừa (mặc định) / Lớn — [KeyLabelSize]. */
@Composable
private fun KeyLabelSizeRow() = ChoiceRow(Keys.KEY_LABEL_SIZE, Prefs.D.keyLabelSize.id, tr("Cỡ chữ trên phím"),
    tr("Lớn: chữ, ký hiệu và biểu tượng trên phím to hơn khoảng 20%. Có Plus: thanh “Cỡ chữ trên phím” ở Giao diện → Tuỳ chỉnh nâng cao, khi đã đặt, thay cho lựa chọn này."),
    listOf(KeyLabelSize.MEDIUM.id to tr("Vừa"), KeyLabelSize.LARGE.id to tr("Lớn"))) { KeyLabelSize.of(it).id }

@Composable
private fun PhimPage(onBack: () -> Unit) {
    var pickingSound by remember { mutableStateOf(false) }
    if (pickingSound) { KeySoundPage(onBack = { pickingSound = false }); return }
    SubPageHeader(FeaturePage.Phim.title, onBack)
    val numberRow by rememberBoolPref(Keys.NUMBER_ROW, Prefs.D.numberRow)
    VTSection(header = tr("Phím")) {
        BoolToggle(Keys.NUMBER_ROW, Prefs.D.numberRow, tr("Hàng phím số"), tr("Thêm hàng 1 … 0 trên hàng chữ (bàn phím cao thêm gần một hàng)."))
        RowDivider()
        // Chỉ hiện khi hàng số bật (tắt hàng số thì công tắc này vô nghĩa, giá trị vẫn giữ).
        if (numberRow) {
            BoolToggle(Keys.NUMBER_ROW_FULL_HEIGHT, Prefs.D.numberRowFullHeight, tr("Hàng số cao bằng hàng chữ"),
                tr("Phím số to bằng phím chữ (bàn phím cao thêm đúng một hàng)."))
            RowDivider()
        }
        SpaceSideKeyRow()
        RowDivider()
        EmojiPlacementRow()
        RowDivider()
        KeyLabelSizeRow()
        RowDivider()
        // Hàng số bật ⇒ giữ q…p ra số vô nghĩa (KeyAlternates.numbersSettingVisible).
        if (KeyAlternates.numbersSettingVisible(numberRow)) {
            BoolToggle(Keys.LONG_PRESS_NUMBERS, Prefs.D.longPressNumbers, tr("Giữ phím hàng trên để ra số"), tr("Giữ q … p để gõ 1 … 0 (số nhỏ ở góc phím)."))
            RowDivider()
        }
        BoolToggle(Keys.LONG_PRESS_SYMBOLS, Prefs.D.longPressSymbols, tr("Giữ phím hàng 2, 3 để ra ký tự đặc biệt"),
            tr("Giữ a … l, z … m để gõ @ # \$ _ & - + ( ) … Giữ , để chọn dấu câu (. ? ! : ; …); giữ 😊 để đổi bàn phím, gõ giọng nói, một tay, thả nổi."))
        RowDivider()
        BoolToggle(Keys.HOLD_SHIFT_SYMBOLS, Prefs.D.holdShiftSymbols, tr("Giữ Shift để gõ số và ký hiệu"),
            tr("Giữ ⇧ rồi chạm phím chữ để gõ ký tự nhỏ ở góc phím (q w e → 1 2 3) thay vì chữ hoa. Chạm ⇧ vẫn viết hoa một chữ, chạm đôi để khoá."))
        RowDivider()
        BoolToggle(Keys.AUTO_SPACE_AFTER_PUNCT, Prefs.D.autoSpaceAfterPunct, tr("Tự thêm dấu cách sau dấu câu"),
            tr("Gõ . , ? ! ; : tự có dấu cách phía sau. Không thêm trong số (3.5, 1,000), email, đường dẫn. Gõ dấu cách ngay sau không thành hai dấu cách; ⌫ ngay sau chỉ xoá dấu cách đó."))
    }
    VTSection(header = tr("Cử chỉ")) {
        BoolToggle(Keys.SPACE_SWIPE_LANGUAGE, Prefs.D.spaceSwipeLanguage, tr("Vuốt phím cách đổi Tiếng Việt / Tiếng Anh"),
            tr("Vuốt nhanh phím cách sang trái/phải. Góc phím cách hiện VI / EN. Tiếng Anh gõ nguyên văn. Giữ rồi kéo vẫn là di con trỏ."))
        RowDivider()
        // "Độ nhạy con trỏ" Chậm / Vừa (mặc định) / Nhanh — TrackpadSpeed, cùng khoá iOS.
        ChoiceRow(Keys.TRACKPAD_SPEED, Prefs.D.trackpadSpeed.id, tr("Độ nhạy con trỏ"),
            tr("Giữ phím cách rồi kéo để di con trỏ. Kéo chậm luôn đi từng ký tự; mức này chỉnh độ tăng tốc khi kéo nhanh."),
            listOf(com.viettelex.keyboard.TrackpadSpeed.SLOW.id to tr("Chậm"),
                com.viettelex.keyboard.TrackpadSpeed.MEDIUM.id to tr("Vừa"),
                com.viettelex.keyboard.TrackpadSpeed.FAST.id to tr("Nhanh"))) {
            com.viettelex.keyboard.TrackpadSpeed.of(it).id
        }
        RowDivider()
        BoolToggle(Keys.SWIPE_KEY_COMMANDS, Prefs.D.swipeKeyCommands, tr("Vuốt phím để sao chép/dán"),
            tr("Chạm phím rồi vuốt thẳng lên quá hàng phím trên cùng và nhấc tay: C sao chép, X cắt, V dán, A chọn hết, Z hoàn tác, Y làm lại. Kéo ngón trở xuống để huỷ. Giữ ⇧ rồi kéo phím cách để chọn chữ."))
        RowDivider()
        OneHandRow()
        RowDivider()
        BoolToggle(Keys.FLOATING_KEYBOARD, Prefs.D.floatingKeyboard, tr("Bàn phím thả nổi"),
            tr("Tách bàn phím khỏi đáy màn hình thành khung nhỏ, kéo thanh dưới cùng để đặt đâu cũng được — app bên dưới vẫn chạm được, không bị che hay co lại. Bật/tắt nhanh: giữ 😊 → 🪟; nút ⤓ trên thanh kéo để gắn lại. Khi thả nổi, chế độ một tay và Nâng bàn phím tạm bỏ qua. Vị trí nhớ riêng cho màn hình dọc và ngang."))
    }
    VTSection(header = tr("Phản hồi khi chạm")) {
        BoolToggle(Keys.KEY_PREVIEW, Prefs.D.keyPreview, tr("Phóng to chữ khi bấm"), tr("Ô chữ lớn nổi trên phím vừa chạm. Tắt nếu thấy rối mắt."))
        RowDivider()
        BoolToggle(Keys.KEY_PRESS_HIGHLIGHT, Prefs.D.keyPressHighlight, tr("Phím sẫm khi bấm"),
            tr("Phím đổi màu trong lúc chạm, kể cả khi tắt phóng to chữ."))
        RowDivider()
        BoolToggle(Keys.HAPTIC_FEEDBACK, Prefs.D.hapticFeedback, tr("Rung phím"), tr("Rung nhẹ mỗi lần chạm phím."))
        HapticStrengthRow()
        RowDivider()
        KeySoundRows(onOpenStyles = { pickingSound = true })
    }
    VTSection(header = tr("Bàn phím cứng")) {
        BoolToggle(Keys.HARDWARE_TELEX, Prefs.D.hardwareTelex, tr("Telex cho bàn phím cứng"),
            tr("Gõ Telex/VNI bằng bàn phím Bluetooth/USB, Samsung DeX, Chromebook. Phím tắt Ctrl/Alt vẫn tới app. Bàn phím ảo tự ẩn khi có bàn phím cứng (bật lại: Cài đặt hệ thống → Bàn phím vật lý → Hiện bàn phím ảo)."))
    }
    GuideLinkSection(FeaturePage.Phim)
}

/** Nghe/rung thử dùng chung cho trang Phím (nhả AudioTrack khi rời trang). */
@Composable
private fun rememberPreview(): KeyFeedbackPreview {
    val ctx = LocalContext.current
    val p = remember { KeyFeedbackPreview(ctx) }
    DisposableEffect(Unit) { onDispose { p.release() } }
    return p
}

/** Thanh trượt "Độ mạnh rung" 10…100 % dưới công tắc Rung phím (chỉ hiện khi bật) — giống iOS.
 *  Kéo ⇒ rung thử đúng độ mạnh (≤ 1 lần / 120 ms + lúc thả). */
@Composable
private fun HapticStrengthRow() {
    val on by rememberBoolPref(Keys.HAPTIC_FEEDBACK, Prefs.D.hapticFeedback)
    if (!on) return
    val c = LocalVT.current
    var pct by rememberIntPref(Keys.HAPTIC_STRENGTH, Prefs.D.hapticStrength)
    val preview = rememberPreview()
    val throttle = remember { PreviewThrottle() }
    fun fire(final: Boolean) {
        if (throttle.shouldFire(pct, SystemClock.uptimeMillis(), final)) preview.playHaptic(pct)
    }
    RowDivider()
    Column(Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(tr("Độ mạnh rung"), style = VTType.body, color = c.label, modifier = Modifier.weight(1f))
            Text("${HapticStrength.clamp(pct)}%", style = VTType.body, color = c.secondary)
        }
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(tr("Nhẹ"), style = VTType.footnote, color = c.secondary)
            Slider(value = HapticStrength.clamp(pct).toFloat(), valueRange = 10f..100f, steps = 17,
                onValueChange = { v -> val n = HapticStrength.clamp(Math.round(v / 5) * 5); if (n != pct) { pct = n; fire(false) } },
                onValueChangeFinished = { fire(true) },
                modifier = Modifier.weight(1f))
            Text(tr("Mạnh"), style = VTType.footnote, color = c.secondary)
        }
    }
}

/** Âm thanh phím riêng: công tắc + hàng "Âm thanh gõ" (kiểu đang chọn ›) mở [KeySoundPage] — chỉ
 *  hiện khi bật. [com.viettelex.keyboard.KeySoundSynth]. */
@Composable
private fun KeySoundRows(onOpenStyles: () -> Unit) {
    val c = LocalVT.current
    val on by rememberBoolPref(Keys.KEY_SOUND, Prefs.D.keySound)
    BoolToggle(Keys.KEY_SOUND, Prefs.D.keySound, tr("Âm thanh phím"),
        tr("Tiếng phím riêng của VietTelex: chọn kiểu, chỉnh âm lượng. Tắt: dùng âm thanh khi chạm của hệ thống. Im khi máy để Rung hoặc Im lặng."))
    if (!on) return
    val style by rememberStringPref(Keys.KEY_SOUND_STYLE, Prefs.D.keySoundStyle)
    RowDivider()
    VTRow(onClick = onOpenStyles) {
        Text(tr("Âm thanh gõ"), style = VTType.body, color = c.label, modifier = Modifier.weight(1f))
        Text("${tr(KeySoundStyle.resolve(style, true).viTitle)} ›", style = VTType.body, color = c.secondary, maxLines = 1)
    }
}

/**
 * "Âm thanh gõ" (Phil 19/10/2026): chọn kiểu âm phím — "Hệ thống" đầu, 11 kiểu tổng hợp + Piano, "Âm của
 * bạn" cuối. Chạm một kiểu = chọn + nghe thử chữ → xoá → phím chức năng. Âm lượng + nhập âm tự
 * chọn ở đây (iOS: KeySoundStylePage, cùng bố cục). Mọi kiểu miễn phí.
 */
@Composable
private fun KeySoundPage(onBack: () -> Unit) {
    val c = LocalVT.current
    val ctx = LocalContext.current
    var vol by rememberIntPref(Keys.KEY_SOUND_VOLUME, Prefs.D.keySoundVolume)
    var style by rememberStringPref(Keys.KEY_SOUND_STYLE, Prefs.D.keySoundStyle)
    var customDuration by remember { mutableStateOf(KeySoundImport.storedDuration(ctx)) }
    var notice by remember { mutableStateOf<String?>(null) }
    var styleBeforeImport by remember { mutableStateOf<String?>(null) }
    val preview = rememberPreview()
    val throttle = remember { PreviewThrottle() }
    val audible = { maxOf(vol, 20) }
    val current = KeySoundStyle.resolve(style, true)

    val importer = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        val before = styleBeforeImport
        styleBeforeImport = null
        if (uri == null) {
            if (customDuration == null && style == KeySoundStyle.CUSTOM.id) style = before ?: KeySoundStyle.DEFAULT.id
            return@rememberLauncherForActivityResult
        }
        try {
            val o = KeySoundImport.importUri(ctx, uri)
            customDuration = o.duration
            style = KeySoundStyle.CUSTOM.id
            notice = if (o.truncated) tr("Âm dài hơn 0,3 giây nên đã được cắt ngắn.") else null
            preview.playStyle(style, audible())
        } catch (e: KeySoundImport.ImportException) {
            notice = when (e.failure) {
                KeySoundImport.Failure.SILENT -> tr("File không có tiếng (toàn im lặng).")
                KeySoundImport.Failure.TOO_LARGE -> tr("File quá lớn (tối đa 30 MB).")
                KeySoundImport.Failure.UNREADABLE -> tr("Không đọc được file âm thanh này.")
            }
            if (customDuration == null && style == KeySoundStyle.CUSTOM.id) style = before ?: KeySoundStyle.DEFAULT.id
        }
    }
    fun pick(id: String) {
        if (id == KeySoundStyle.CUSTOM.id && customDuration == null) {
            styleBeforeImport = style; style = id
            importer.launch(arrayOf("audio/*"))
            return
        }
        style = id
        preview.playStyle(id, audible())
    }

    SubPageHeader(tr("Âm thanh gõ"), onBack)
    VTSection(header = tr("Chạm một kiểu để chọn và nghe thử."),
        footer = tr("Hệ thống: âm thanh khi chạm của Android — theo Cài đặt → Âm thanh → Âm thanh khi chạm, âm lượng theo hệ thống. Các kiểu khác là tiếng riêng của VietTelex.")) {
        KeySoundStyle.MENU_ORDER.forEachIndexed { i, st ->
            if (i > 0) RowDivider()
            VTRow(onClick = { pick(st.id) }) {
                Text(tr(st.viTitle), style = VTType.body, color = c.label, modifier = Modifier.weight(1f))
                if (current == st) GlyphIcon(Glyph.Check, c.accent, 18.dp)
            }
        }
    }
    if (current == KeySoundStyle.CUSTOM || customDuration != null) {
        VTSection {
            Column(Modifier.padding(horizontal = 16.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                val d = customDuration
                Text(if (d != null) tr("Âm của bạn: %s giây", String.format(Locale.ROOT, "%.2f", d))
                     else tr("Chưa có âm — chọn một file âm thanh ngắn (mp3, m4a, ogg, wav…)."),
                    style = VTType.footnote, color = if (d != null) c.label else c.secondary)
                Row(horizontalArrangement = Arrangement.spacedBy(20.dp)) {
                    Text(if (d == null) tr("Chọn file âm thanh…") else tr("Chọn âm khác…"), style = VTType.body, color = c.accent,
                        modifier = Modifier.clickable { styleBeforeImport = style; importer.launch(arrayOf("audio/*")) })
                    if (d != null) Text(tr("Xoá"), style = VTType.body, color = c.red,
                        modifier = Modifier.clickable {
                            KeySoundImport.remove(ctx); customDuration = null
                            if (style == KeySoundStyle.CUSTOM.id) style = KeySoundStyle.DEFAULT.id
                        })
                }
                Text(tr("Âm được cắt lặng đầu, giữ tối đa 0,3 giây và chỉnh độ to an toàn. File chỉ nằm trên máy này (không có trong sao lưu)."),
                    style = VTType.footnote, color = c.secondary)
            }
            notice?.let { VTRow { Text(it, style = VTType.footnote, color = c.secondary) } }
        }
    }
    if (current.usesPool) {
        fun fire(final: Boolean) {
            if (throttle.shouldFire(vol, SystemClock.uptimeMillis(), final)) preview.playSound(style, vol)
        }
        VTSection {
            Column(Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) {
                Text(tr("Âm lượng: %s%%", vol), style = VTType.body, color = c.label)
                Slider(value = vol.toFloat(), valueRange = 0f..100f, steps = 19,
                    onValueChange = { v -> val n = Math.round(v / 5) * 5; if (n != vol) { vol = n; fire(false) } },
                    onValueChangeFinished = { fire(true) })
                Text(tr("Kéo thanh trượt hoặc chọn kiểu để nghe thử. Không nghe thấy? Tắt chế độ Rung/Im lặng (bàn phím cũng im khi đó)."),
                    style = VTType.footnote, color = c.secondary)
            }
        }
    }
}
