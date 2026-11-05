package com.viettelex.android.ui

import android.content.Context
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.viettelex.keyboard.Keys
import com.viettelex.keyboard.OnboardingFlow
import com.viettelex.keyboard.OnboardingProfile
import com.viettelex.keyboard.OnboardingSettings
import com.viettelex.keyboard.RetroEnglishUI
import com.viettelex.keyboard.tr

// Onboarding người dùng mới (docs/ONBOARDING-SPEC.md §2): màn 1 "Bạn thường gõ thế nào?" (3 thẻ hồ
// sơ), màn 2 "Gõ thử" (ô gõ + câu mẫu + danh sách vừa bật, mỗi dòng một công tắc). "Bỏ qua" ở mọi
// màn = giữ nguyên cài đặt. Phần thuần ở :keyboard Onboarding.kt. Song sinh iOS App/OnboardingView.swift.

/** Đọc/ghi trạng thái onboarding trên prefs chung (đồng bộ IME qua PrefSync). */
internal object OnboardingStore {
    /** Gọi ĐẦU TIÊN ở MainActivity.onCreate — trước mọi chuyển đổi ghi key vào prefs. */
    fun migrate(ctx: Context) {
        val p = Prefs.of(ctx)
        val w = OnboardingFlow.upgradeWrites(p.all.keys) ?: return
        p.edit().apply { w.forEach { (k, v) -> putBoolean(k, v) } }.commit()
    }

    fun apply(ctx: Context, profile: OnboardingProfile) {
        Prefs.of(ctx).edit().apply {
            for ((k, v) in OnboardingSettings.writes(profile, System.currentTimeMillis())) when (v) {
                is Boolean -> putBoolean(k, v)
                is String -> putString(k, v)
            }
        }.apply()
    }

    fun current(ctx: Context): Map<String, Boolean> {
        val p = Prefs.of(ctx)
        return OnboardingSettings.current { k -> if (p.contains(k)) p.getBoolean(k, false) else null }
    }

    /** "Bỏ qua" / "Xong": chỉ ghi xong — giữ nguyên mọi cài đặt. */
    fun finish(ctx: Context) { Prefs.of(ctx).edit().putBoolean(OnboardingFlow.DONE_KEY, true).apply() }

    fun dismissTip(ctx: Context) { Prefs.of(ctx).edit().putBoolean(OnboardingFlow.TIP_KEY, false).apply() }
}

/** Phủ toàn màn hình khi [screen] khác null. */
@Composable
internal fun OnboardingOverlay(screen: OnboardingFlow.Screen, ime: ImeStatus, onPickIme: () -> Unit) {
    val c = LocalVT.current
    val ctx = LocalContext.current
    val profileId by rememberStringPref(OnboardingFlow.PROFILE_KEY, "")
    val profile = OnboardingProfile.of(profileId)
    // Màn 2 mở ngay sau màn 1 trong phiên ⇒ "Chọn lại" quay về màn 1.
    var rechoose by rememberSaveable { mutableStateOf(false) }
    var cameFromChoose by rememberSaveable { mutableStateOf(screen == OnboardingFlow.Screen.CHOOSE) }
    val shown = if (rechoose) OnboardingFlow.Screen.CHOOSE else screen
    BackHandler(shown == OnboardingFlow.Screen.TRY_IT && cameFromChoose) { rechoose = true }

    Box(Modifier.fillMaxSize().background(c.groupedBg)) {
        Column(Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding().imePadding()) {
            Row(Modifier.fillMaxWidth().height(48.dp).padding(horizontal = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                if (shown == OnboardingFlow.Screen.TRY_IT && cameFromChoose) {
                    TextAction("‹ " + tr("Chọn lại")) { rechoose = true }
                }
                Spacer(Modifier.weight(1f))
                TextAction(tr("Bỏ qua")) { OnboardingStore.finish(ctx) }
            }
            when (shown) {
                OnboardingFlow.Screen.CHOOSE -> OnboardingChoose(profile.takeIf { rechoose }) { p ->
                    OnboardingStore.apply(ctx, p)
                    rechoose = false
                    cameFromChoose = true
                }
                OnboardingFlow.Screen.TRY_IT -> OnboardingTry(profile ?: OnboardingProfile.VI, ime, onPickIme) {
                    OnboardingStore.finish(ctx)
                }
            }
        }
    }
}

@Composable
private fun TextAction(text: String, onClick: () -> Unit) {
    val c = LocalVT.current
    Text(text, style = VTType.body, color = c.accent,
        modifier = Modifier.clip(RoundedCornerShape(8.dp)).clickable(onClick = onClick).padding(horizontal = 10.dp, vertical = 8.dp))
}

@Composable
private fun OnboardingChoose(selected: OnboardingProfile?, onPick: (OnboardingProfile) -> Unit) {
    val c = LocalVT.current
    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Text(tr("Bạn thường gõ thế nào?"), style = VTType.largeTitle, color = c.label)
        Text(tr("Chọn một — VietTelex bật sẵn những gì hợp với bạn. Đổi lại lúc nào cũng được ở Kiểu Gõ → Gõ lẫn tiếng Anh."),
            style = VTType.subheadline, color = c.secondary, modifier = Modifier.padding(bottom = 6.dp))
        for (p in OnboardingProfile.entries) {
            val sel = selected == p
            Row(
                Modifier.fillMaxWidth().widthIn(max = 560.dp).clip(RoundedCornerShape(16.dp)).background(c.card)
                    .border(if (sel) 2.dp else 0.5.dp, if (sel) c.accent else c.separator.copy(alpha = 0.3f), RoundedCornerShape(16.dp))
                    .clickable { onPick(p) }
                    .semantics { role = Role.Button; this.selected = sel }
                    .padding(16.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                ProfileBadge(p)
                Column(Modifier.weight(1f).padding(start = 14.dp, end = 8.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(p.title, style = VTType.headline, color = c.label)
                    Text("“${p.example}”", style = VTType.subheadline.copy(fontStyle = FontStyle.Italic), color = c.secondary)
                }
                if (sel) GlyphIcon(Glyph.Check, c.accent, 20.dp) else Text("›", style = VTType.title3, color = c.tertiary)
            }
        }
        Spacer(Modifier.height(24.dp))
    }
}

/** Nhãn VI / VI+EN / EN — cùng màu iOS. */
@Composable
internal fun ProfileBadge(p: OnboardingProfile) {
    val bg = when (p) {
        OnboardingProfile.VI -> Color(0xD9FF3B30)
        OnboardingProfile.MIXED -> Color(0xFF30B0C7)
        OnboardingProfile.EN -> LocalVT.current.accent
    }
    Box(Modifier.size(46.dp).background(bg, RoundedCornerShape(11.dp)), contentAlignment = Alignment.Center) {
        Text(when (p) { OnboardingProfile.VI -> "VI"; OnboardingProfile.MIXED -> "VI+EN"; OnboardingProfile.EN -> "EN" },
            color = Color.White, fontWeight = FontWeight.Bold, fontSize = if (p == OnboardingProfile.MIXED) 11.sp else 15.sp)
    }
}

@Composable
private fun OnboardingTry(profile: OnboardingProfile, ime: ImeStatus, onPickIme: () -> Unit, onDone: () -> Unit) {
    val c = LocalVT.current
    val contextual by rememberBoolPref(Keys.CONTEXTUAL_ENGLISH, Prefs.D.contextualEnglish)
    val vni by rememberBoolPref(Keys.VNI_MODE, Prefs.D.vniMode)
    val swipeOn by rememberBoolPref(Keys.SWIPE_TYPING, Prefs.D.swipeTyping)
    // Công tắc hồ sơ này BẬT; mục phụ thuộc theo đúng điều kiện hiện như nhóm Gõ mixed.
    val shown = OnboardingSettings.KEYS.filter { k ->
        profile.values[k] == true && when (k) {
            Keys.RETRO_ENGLISH_AUTO, Keys.ENGLISH_BY_FREQUENCY -> RetroEnglishUI.switchVisible(contextual, vni)
            Keys.SWIPE_ENGLISH -> swipeOn
            else -> true
        }
    }
    val hint = when (profile) {
        OnboardingProfile.EN -> tr("Bàn phím bắt đầu ở Tiếng Anh — vuốt nhanh phím cách sang trái/phải để gõ tiếng Việt.")
        OnboardingProfile.MIXED -> tr("Cứ gõ lẫn Anh và Việt: check, mail, team giữ nguyên. Vuốt nhanh phím cách để đổi hẳn sang Tiếng Anh.")
        OnboardingProfile.VI -> tr("Telex: vieejt → việt. Từ tiếng Anh như google, github vẫn giữ nguyên.")
    }
    Column(Modifier.fillMaxSize()) {
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState())) {
            Text(tr("Gõ thử"), style = VTType.largeTitle, color = c.label,
                modifier = Modifier.padding(start = 20.dp, bottom = 10.dp))
            VTSection {
                VTRow {
                    ProfileBadge(profile)
                    Column(Modifier.padding(start = 12.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text(profile.title, style = VTType.headline, color = c.label)
                        Text("“${profile.example}”", style = VTType.footnote.copy(fontStyle = FontStyle.Italic), color = c.secondary)
                    }
                }
            }
            VTSection(header = tr("Gõ thử"), footer = hint) {
                var text by rememberSaveable { mutableStateOf("") }
                VTTextField(text, { text = it }, tr("Thử gõ tại đây…"), minLines = 2, maxLines = 5,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 11.dp))
                if (!ime.selected) {
                    RowDivider()
                    VTRow(onClick = onPickIme) {
                        Text(tr("Chọn VietTelex để gõ thử bằng chính bàn phím này."), style = VTType.subheadline, color = c.accent)
                    }
                }
            }
            VTSection(header = tr("Câu mẫu")) {
                profile.samples.forEachIndexed { i, s ->
                    if (i > 0) RowDivider()
                    VTRow { Text(s, style = VTType.body, color = c.secondary) }
                }
            }
            if (shown.isNotEmpty()) VTSection(header = tr("Vừa bật"),
                footer = tr("Tắt ngay ở đây nếu không cần. Chỉnh thêm ở Kiểu Gõ → Gõ lẫn tiếng Anh.")) {
                shown.forEachIndexed { i, k ->
                    if (i > 0) RowDivider()
                    var v by rememberBoolPref(k, OnboardingSettings.DEFAULTS.getValue(k))
                    SettingToggle(tr(OnboardingSettings.viTitle(k)), null, v) { v = it }
                }
            }
        }
        Box(Modifier.padding(horizontal = 20.dp, vertical = 8.dp)) { ProminentButton(tr("Xong"), onDone) }
    }
}

/** Thẻ một lần cho người dùng cũ (§5): chạm = mở nhóm "Gõ lẫn tiếng Anh"; đóng/xem ⇒ không hiện lại. */
@Composable
internal fun MixedTypingTipCard(onOpen: () -> Unit, onDismiss: () -> Unit) {
    val c = LocalVT.current
    VTSection {
        Row(Modifier.fillMaxWidth().padding(start = 16.dp, top = 11.dp, bottom = 11.dp, end = 4.dp), verticalAlignment = Alignment.Top) {
            Box(Modifier.size(29.dp).background(Color(0xFF30B0C7), RoundedCornerShape(7.dp)), contentAlignment = Alignment.Center) {
                GlyphIcon(Glyph.Globe, Color.White, 18.dp)
            }
            Column(Modifier.weight(1f).clickable(onClick = onOpen).padding(start = 12.dp, end = 8.dp),
                verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(tr("Bạn hay gõ trộn Anh/Việt?"), style = VTType.subheadline.copy(fontWeight = FontWeight.SemiBold), color = c.label)
                Text(tr("Xem nhóm Gõ lẫn tiếng Anh mới") + " ›", style = VTType.footnote, color = c.accent)
            }
            Text("✕", style = VTType.body, color = c.secondary,
                modifier = Modifier.clip(RoundedCornerShape(8.dp)).clickable(onClick = onDismiss).padding(10.dp)
                    .semantics { role = Role.Button; contentDescription = tr("Đóng") })
        }
    }
}
