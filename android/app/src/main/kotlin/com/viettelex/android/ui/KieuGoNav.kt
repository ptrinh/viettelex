package com.viettelex.android.ui

import androidx.compose.animation.animateColorAsState
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.relocation.BringIntoViewRequester
import androidx.compose.foundation.relocation.bringIntoViewRequester
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.viettelex.keyboard.Keys
import com.viettelex.keyboard.tr

// Điều hướng tab Kiểu Gõ (docs/SETTINGS-CLEANUP-SPEC.md §1, §3, §4): trang chính + hai trang con
// "Nâng cao" (kiểu gõ / nhóm gõ lẫn tiếng Anh), tối đa 2 tầng. Ô tìm cài đặt (tab Tính Năng) đặt
// [KieuGoNav.request] ⇒ RootScreen chuyển tab, KieuGoTab mở đúng trang, cuộn tới + tô sáng dòng.

/** Trang con của tab Kiểu Gõ. */
internal enum class KieuGoPage { TypingAdvanced, MixedAdvanced }

/** Đích tìm kiếm: [id] của dòng ([Highlightable]), [page] chứa nó (null = trang chính), mở nhóm mixed? */
internal data class KieuGoTarget(val id: String, val page: KieuGoPage?, val expandMixed: Boolean = false)

/** Trạng thái trong phiên (KHÔNG lưu): mở app là trang chính. */
@OptIn(ExperimentalFoundationApi::class)
internal object KieuGoNav {
    val page = mutableStateOf<KieuGoPage?>(null)
    val request = mutableStateOf<KieuGoTarget?>(null)
    val highlighted = mutableStateOf<String?>(null)
    /** Dòng đang dựng, theo id — để cuộn tới. Chỉ dùng trên main thread (composition). */
    val requesters = HashMap<String, BringIntoViewRequester>()
}

/**
 * Cài đặt kiểu gõ (không thuộc nhóm gõ lẫn tiếng Anh). [advanced] = nằm ở trang "Nâng cao";
 * [hiddenInVni] = chỉ-Telex, nằm cùng nhóm "Kiểu gõ" với bộ chọn Telex/VNI ⇒ ẨN khi chọn VNI
 * (SETTINGS-CLEANUP-SPEC §0.4, §6). Teencode chạy cả ở VNI ⇒ luôn hiện. Key lưu KHÔNG đổi.
 */
internal enum class TypingOption(val viTitle: String, val keywords: String, val prefKey: String,
                                 val advanced: Boolean, val hiddenInVni: Boolean) {
    InputMethod("Kiểu gõ", "telex vni input method kiểu gõ", Keys.VNI_MODE, false, false), // l10n-key
    AutoCapitalize("Tự động viết hoa đầu câu", "viết hoa capital shift đầu câu", Keys.AUTO_CAPITALIZE, false, false), // l10n-key
    SimpleTelex("Telex đơn giản", "simple telex w ư nâng cao advanced", Keys.SIMPLE_TELEX, true, true), // l10n-key
    FreeMarking("Bỏ dấu tự do", "free marking đặt dấu thứ tự nâng cao advanced", Keys.FREE_MARKING, true, true), // l10n-key
    QuickTelex("Gõ nhanh (Quick Telex)", "quick telex cc ch gg gi phụ âm nâng cao advanced", Keys.QUICK_TELEX, true, true), // l10n-key
    ModernTone("Bỏ dấu kiểu mới (oà, uý)", "modern tone hoà thuý dấu mới cũ nâng cao advanced", Keys.MODERN_TONE, true, false), // l10n-key
    Teencode("Chính tả teencode", "teencode chat wá zui kó nâng cao advanced", Keys.TEENCODE, true, false); // l10n-key

    val title: String get() = tr(viTitle)

    val target: KieuGoTarget get() = KieuGoTarget("typing:$name", if (advanced) KieuGoPage.TypingAdvanced else null)

    companion object {
        /** Mục bị ẩn (VNI ⇒ ẩn mục chỉ-Telex). Chỉ hiển thị: giá trị đã lưu giữ nguyên. */
        fun hidden(o: TypingOption, vniMode: Boolean): Boolean = vniMode && o.hiddenInVni

        /** Mục của trang "Nâng cao" đang hiện, theo thứ tự. */
        fun advancedRows(vniMode: Boolean): List<TypingOption> = entries.filter { it.advanced && !hidden(it, vniMode) }

        /** Dòng phụ (khoá dịch) của mục "Nâng cao": chỉ liệt kê mục đang hiện. */
        fun advancedSummary(vniMode: Boolean): String = if (vniMode) TYPING_ADVANCED_SUMMARY_VNI else TYPING_ADVANCED_SUMMARY

        /** Đích tìm kiếm thực sự: mục đang ẩn (VNI) ⇒ tô sáng bộ chọn Telex/VNI (nơi bật lại). */
        fun resolve(target: KieuGoTarget, vniMode: Boolean): KieuGoTarget =
            entries.firstOrNull { it.target.id == target.id }?.takeIf { hidden(it, vniMode) }?.let { InputMethod.target } ?: target
    }
}

/** Dòng phụ của mục "Nâng cao" trong mục Kiểu gõ — liệt kê những gì bên trong. */
internal const val TYPING_ADVANCED_SUMMARY = "Telex đơn giản, bỏ dấu tự do, gõ nhanh, bỏ dấu kiểu mới, teencode…" // l10n-key
/** Như trên khi chọn VNI (ba mục chỉ-Telex đã ẩn). */
internal const val TYPING_ADVANCED_SUMMARY_VNI = "Bỏ dấu kiểu mới, teencode" // l10n-key

/** Bọc một dòng để ô tìm kiếm cuộn tới + tô sáng (~1,6 s). */
@OptIn(ExperimentalFoundationApi::class)
@Composable
internal fun Highlightable(id: String, content: @Composable () -> Unit) {
    val c = LocalVT.current
    val r = remember { BringIntoViewRequester() }
    DisposableEffect(id) {
        KieuGoNav.requesters[id] = r
        onDispose { if (KieuGoNav.requesters[id] === r) KieuGoNav.requesters.remove(id) }
    }
    val bg by animateColorAsState(if (KieuGoNav.highlighted.value == id) c.accent.copy(alpha = 0.18f) else Color.Transparent, label = "hl")
    Box(Modifier.bringIntoViewRequester(r).background(bg)) { content() }
}

/** Dòng mở trang con: tiêu đề + dòng phụ (liệt kê nội dung) + "›". */
@Composable
internal fun NavRow(title: String, subtitle: String?, onClick: () -> Unit) {
    val c = LocalVT.current
    VTRow(onClick = onClick) {
        Column(Modifier.weight(1f).padding(end = 8.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, style = VTType.body, color = c.label)
            if (subtitle != null) Text(subtitle, style = VTType.footnote, color = c.secondary)
        }
        Text("›", style = VTType.title3, color = c.tertiary)
    }
}

/**
 * Công tắc phụ thuộc: [reason] != null ⇒ mờ, không bấm được, lý do ghi dưới chú thích (không ẩn —
 * SETTINGS-CLEANUP-SPEC §0.4). Giá trị đã lưu giữ nguyên.
 */
@Composable
internal fun DependentToggle(key: String, default: Boolean, title: String, caption: String, reason: String?,
                             experimental: Boolean = false, indent: Boolean = experimental) {
    val c = LocalVT.current
    var v by rememberBoolPref(key, default)
    val enabled = reason == null
    Box(Modifier.alpha(if (enabled) 1f else 0.45f).then(if (indent) Modifier.padding(start = 16.dp) else Modifier)) {
        VTRow(onClick = if (enabled) ({ v = !v }) else null) {
            Column(Modifier.weight(1f).padding(end = 12.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(title, style = VTType.body, color = c.label)
                    if (experimental) ExperimentalBadge()
                }
                Text(caption, style = VTType.footnote, color = c.secondary)
                if (reason != null) Text(reason, style = VTType.footnote, color = c.secondary)
            }
            IosSwitch(v) { if (enabled) v = it }
        }
    }
}

/** Trang "Nâng cao" của mục Kiểu gõ (SETTINGS-CLEANUP-SPEC §3, §6): mục chỉ-Telex ẨN khi chọn VNI. */
@Composable
internal fun TypingAdvancedPage(onBack: () -> Unit) {
    val vni by rememberBoolPref(Keys.VNI_MODE, Prefs.D.vniMode)
    SubPageHeader(tr("Nâng cao"), onBack, backTitle = "‹ " + AppTab.KieuGo.title)
    VTSection(header = tr("Kiểu gõ"), footer = APPLY_NOTE) {
        TypingOption.advancedRows(vni).forEachIndexed { i, o ->
            if (i > 0) RowDivider()
            val (default, caption) = when (o) {
                TypingOption.SimpleTelex -> Prefs.D.simpleTelex to SettingCaption.simpleTelex
                TypingOption.FreeMarking -> Prefs.D.freeMarking to SettingCaption.freeMarking
                TypingOption.QuickTelex -> Prefs.D.quickTelex to SettingCaption.quickTelex
                TypingOption.ModernTone -> Prefs.D.modernTone to SettingCaption.modernTone
                TypingOption.Teencode -> Prefs.D.teencode to SettingCaption.teencode
                TypingOption.InputMethod, TypingOption.AutoCapitalize -> return@forEachIndexed
            }
            Highlightable(o.target.id) { BoolToggle(o.prefKey, default, tr(o.viTitle), tr(caption)) }
        }
    }
}
