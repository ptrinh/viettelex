package com.viettelex.android.ui

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.relocation.BringIntoViewRequester
import androidx.compose.foundation.relocation.bringIntoViewRequester
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.unit.dp
import com.viettelex.keyboard.Keys
import com.viettelex.keyboard.RetroEnglishUI
import com.viettelex.keyboard.tr
import kotlinx.coroutines.delay

// Nhóm thu gọn "Gõ mixed Việt/Anh" ngay dưới mục Kiểu gõ (tab Kiểu Gõ) — docs/ONBOARDING-SPEC.md §4.
// Gom mọi công tắc gõ trộn Việt–Anh (trước nằm ở Kiểu gõ, Chính tả, Phím & cử chỉ, Gõ vuốt). Key
// SharedPreferences KHÔNG đổi ⇒ hành vi + sao lưu/khôi phục giữ nguyên. Song sinh iOS
// Shared/MixedTypingUI.swift + App/MixedTypingSection.swift.

/** Mục của nhóm — [viTitle] = khoá dịch = chữ trên dòng; [prefKey] = key lưu (null: không phải công tắc). */
internal enum class MixedTypingItem(val viTitle: String, val keywords: String, val prefKey: String?, val group: Group?) {
    Section(MIXED_TITLE, "mixed trộn song ngữ bilingual tiếng anh english việt anh", null, null), // l10n-skip: từ khoá tìm kiếm
    AutoRestore("Tự khôi phục từ tiếng Anh", "english google restore khôi phục", Keys.AUTO_RESTORE, Group.Recognition), // l10n-key
    ContextualEnglish("Quyết định theo ngữ cảnh", "context ngữ cảnh english he is", Keys.CONTEXTUAL_ENGLISH, Group.Recognition), // l10n-key
    RetroEnglish("Tự sửa từ phía trước", "sửa ngược retro english thử nghiệm experimental", Keys.RETRO_ENGLISH_AUTO, Group.Recognition), // l10n-key
    EnglishByFrequency("Đoán từ trùng theo tần suất", "tần suất frequency his hí từ trùng collision thử nghiệm experimental", Keys.ENGLISH_BY_FREQUENCY, Group.Recognition), // l10n-key
    SpaceSwipeLanguage("Vuốt phím cách đổi Tiếng Việt / Tiếng Anh", "space ngôn ngữ english language vuốt phím cách", Keys.SPACE_SWIPE_LANGUAGE, Group.Language), // l10n-key
    SwipeEnglish("Vuốt từ tiếng Anh", "swipe english", Keys.SWIPE_ENGLISH, Group.Suggest), // l10n-key
    UserDictionary("Từ điển cá nhân", "dictionary tên riêng thuật ngữ từ tiếng anh", null, Group.Suggest); // l10n-key

    val title: String get() = tr(viTitle)

    enum class Group(val viTitle: String) {
        Recognition("Nhận diện tiếng Anh"), // l10n-key
        Language("Chuyển ngôn ngữ"), // l10n-key
        Suggest("Gợi ý & gõ vuốt tiếng Anh"); // l10n-key
    }
}

/** Tên nhóm — cùng tên/thứ tự trên iOS và Android. */
internal const val MIXED_TITLE = "Gõ mixed Việt/Anh" // l10n-key

internal object MixedTypingUI {
    /** "Tự sửa từ phía trước" + "Đoán từ trùng theo tần suất" chỉ hiện khi ngữ cảnh bật, không VNI. */
    fun isVisible(item: MixedTypingItem, contextualEnglish: Boolean, vniMode: Boolean): Boolean = when (item) {
        MixedTypingItem.RetroEnglish, MixedTypingItem.EnglishByFrequency -> RetroEnglishUI.switchVisible(contextualEnglish, vniMode)
        else -> true
    }

    /** Tìm tới mục con đang ẩn ⇒ cuộn về công tắc cha "Quyết định theo ngữ cảnh". */
    fun scrollTarget(item: MixedTypingItem, contextualEnglish: Boolean, vniMode: Boolean): MixedTypingItem =
        if (isVisible(item, contextualEnglish, vniMode)) item else MixedTypingItem.ContextualEnglish
}

/**
 * Trạng thái nhóm trong phiên chạy app (KHÔNG lưu): mở app là thu gọn. Ô tìm cài đặt (tab Tính
 * Năng) đặt [request] ⇒ RootScreen chuyển tab Kiểu Gõ; nhóm mở ra, cuộn tới + tô sáng dòng.
 */
internal object MixedTypingFocus {
    val expanded = mutableStateOf(false)
    val request = mutableStateOf<MixedTypingItem?>(null)
    val highlighted = mutableStateOf<MixedTypingItem?>(null)
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
internal fun MixedTypingSection() {
    val c = LocalVT.current
    val ctx = LocalContext.current
    var expanded by MixedTypingFocus.expanded
    val highlighted = MixedTypingFocus.highlighted.value
    val requesters = remember { MixedTypingItem.entries.associateWith { BringIntoViewRequester() } }

    val autoRestore by rememberBoolPref(Keys.AUTO_RESTORE, Prefs.D.autoRestore)
    val contextual by rememberBoolPref(Keys.CONTEXTUAL_ENGLISH, Prefs.D.contextualEnglish)
    val vni by rememberBoolPref(Keys.VNI_MODE, Prefs.D.vniMode)
    val spaceSwipe by rememberBoolPref(Keys.SPACE_SWIPE_LANGUAGE, Prefs.D.spaceSwipeLanguage)
    val swipeOn by rememberBoolPref(Keys.SWIPE_TYPING, Prefs.D.swipeTyping)
    var swipeEn by rememberBoolPref(Keys.SWIPE_ENGLISH, Prefs.D.swipeEnglish)

    // Ô tìm kiếm vừa chọn một mục: mở nhóm, đợi dựng hàng, cuộn tới + tô sáng ~1.6 s.
    val req = MixedTypingFocus.request.value
    LaunchedEffect(req) {
        if (req == null) return@LaunchedEffect
        MixedTypingFocus.request.value = null
        val p = Prefs.of(ctx)
        val target = MixedTypingUI.scrollTarget(req,
            p.getBoolean(Keys.CONTEXTUAL_ENGLISH, Prefs.D.contextualEnglish), p.getBoolean(Keys.VNI_MODE, Prefs.D.vniMode))
        expanded = true
        delay(350)
        runCatching { requesters.getValue(target).bringIntoView() }
        MixedTypingFocus.highlighted.value = target
        delay(1600)
        if (MixedTypingFocus.highlighted.value == target) MixedTypingFocus.highlighted.value = null
    }

    @Composable
    fun Item(item: MixedTypingItem, content: @Composable () -> Unit) {
        val bg by animateColorAsState(if (highlighted == item) c.accent.copy(alpha = 0.18f) else Color.Transparent, label = "hl")
        Box(Modifier.bringIntoViewRequester(requesters.getValue(item)).background(bg)) { content() }
    }

    @Composable
    fun GroupHeader(g: MixedTypingItem.Group) {
        RowDivider()
        Text(tr(g.viTitle).uppercase(), style = VTType.footnote, color = c.secondary,
            modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 12.dp, bottom = 6.dp).semantics { heading() })
    }

    val summary = listOf(autoRestore to tr("Khôi phục tiếng Anh"), contextual to tr("Ngữ cảnh"),
        spaceSwipe to tr("Vuốt phím cách"), (swipeOn && swipeEn) to tr("Vuốt từ tiếng Anh"))
        .filter { it.first }.joinToString(" · ") { it.second }.ifEmpty { tr("Đang tắt") }

    VTSection(footer = if (expanded) APPLY_NOTE else null) {
        Item(MixedTypingItem.Section) {
            val stateText = if (expanded) tr("Mở rộng") else tr("Thu gọn")
            VTRow(onClick = { expanded = !expanded }, modifier = Modifier.semantics { stateDescription = stateText }) {
                Box(Modifier.size(29.dp).background(Color(0xFF30B0C7), RoundedCornerShape(7.dp)), contentAlignment = Alignment.Center) {
                    GlyphIcon(Glyph.Globe, Color.White, 18.dp)
                }
                Column(Modifier.weight(1f).padding(start = 12.dp, end = 8.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(tr(MIXED_TITLE), style = VTType.body, color = c.label)
                    Text(summary, style = VTType.footnote, color = c.secondary, maxLines = 1)
                }
                val angle by animateFloatAsState(if (expanded) 90f else 0f, label = "chev")
                Text("›", style = VTType.title3, color = c.tertiary, modifier = Modifier.rotate(angle))
            }
        }
        if (!expanded) return@VTSection

        GroupHeader(MixedTypingItem.Group.Recognition)
        Item(MixedTypingItem.AutoRestore) {
            BoolToggle(Keys.AUTO_RESTORE, Prefs.D.autoRestore, tr("Tự khôi phục từ tiếng Anh"), tr("Từ không phải tiếng Việt trả về như đã gõ (google, github…)."))
        }
        RowDivider()
        Item(MixedTypingItem.ContextualEnglish) {
            BoolToggle(Keys.CONTEXTUAL_ENGLISH, Prefs.D.contextualEnglish, tr("Quyết định theo ngữ cảnh"), tr("Sau một từ tiếng Anh, từ nhập nhằng kế tiếp mà chuỗi phím tạo thành một từ tiếng Anh sẽ được giữ tiếng Anh thay vì tiếng Việt — “he is” → “he is”, không phải “he í”. Sau từ tiếng Việt hoặc không rõ thì để tiếng Việt — “sao í”."))
        }
        // "Tự sửa từ phía trước" + "Đoán từ trùng theo tần suất" (thử nghiệm): chỉ hiện khi ngữ cảnh bật — như iOS.
        if (RetroEnglishUI.switchVisible(contextual, vni)) {
            RowDivider()
            Item(MixedTypingItem.RetroEnglish) {
                ExperimentalToggle(Keys.RETRO_ENGLISH_AUTO, Prefs.D.retroEnglishAuto, tr("Tự sửa từ phía trước"),
                    tr("Khi bạn gõ tiếp một câu tiếng Anh, tự sửa các từ vừa bị bỏ dấu nhầm (vd. \"Hí cả í very fast\" → \"His car is very fast\")."))
            }
            RowDivider()
            Item(MixedTypingItem.EnglishByFrequency) {
                ExperimentalToggle(Keys.ENGLISH_BY_FREQUENCY, Prefs.D.englishByFrequency, tr("Đoán từ trùng theo tần suất"),
                    tr("Đầu câu, từ vừa là tiếng Anh phổ biến vừa là âm tiết Việt hiếm (his → hí) thì chọn tiếng Anh; từ kế cho thấy là tiếng Việt (hí hửng, hí hí) thì tự đổi lại. Cần bật Quyết định theo ngữ cảnh."))
            }
        }

        GroupHeader(MixedTypingItem.Group.Language)
        Item(MixedTypingItem.SpaceSwipeLanguage) {
            BoolToggle(Keys.SPACE_SWIPE_LANGUAGE, Prefs.D.spaceSwipeLanguage, tr("Vuốt phím cách đổi Tiếng Việt / Tiếng Anh"),
                tr("Vuốt nhanh phím cách sang trái/phải. Góc phím cách hiện VI / EN. Tiếng Anh gõ nguyên văn. Giữ rồi kéo vẫn là di con trỏ."))
        }

        GroupHeader(MixedTypingItem.Group.Suggest)
        Item(MixedTypingItem.SwipeEnglish) {
            // Chỉ có tác dụng khi bật Gõ vuốt ⇒ tắt Gõ vuốt thì hiện mờ, không bấm được.
            val caption = tr("check, mail, meeting… Nét vừa Việt vừa Anh (the/thế) ưu tiên tiếng Việt, phương án kia ở thanh gợi ý.") +
                if (swipeOn) "" else "\n" + tr("Cần bật Gõ vuốt (Tính Năng → Gõ vuốt).")
            Box(Modifier.alpha(if (swipeOn) 1f else 0.45f)) {
                SettingToggle(tr("Vuốt từ tiếng Anh"), caption, swipeEn) { if (swipeOn) swipeEn = it }
            }
        }
        RowDivider()
        Item(MixedTypingItem.UserDictionary) {
            var showDict by remember { mutableStateOf(false) }
            VTRow(onClick = { showDict = true }) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(tr("Từ điển cá nhân"), style = VTType.body, color = c.label)
                    Text(tr("Xem, tìm, xoá từ đã học; thêm tên riêng."), style = VTType.footnote, color = c.secondary)
                }
                Text("›", style = VTType.title3, color = c.tertiary)
            }
            if (showDict) UserDictDialog { showDict = false }
        }
    }
}
