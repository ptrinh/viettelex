package com.viettelex.android.ui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.ime
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.ScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.unit.dp
import com.viettelex.keyboard.Keys

@Composable
fun RootScreen(
    ime: ImeStatus,
    openMauCau: Int,
    onOpenImeSettings: () -> Unit,
    onPickIme: () -> Unit,
) {
    val c = LocalVT.current
    val density = LocalDensity.current
    val focus = LocalFocusManager.current
    var tab by rememberSaveable { mutableStateOf(AppTab.KieuGo) }
    var templatesEnabled by rememberBoolPref(Keys.TEMPLATES_ENABLED, Prefs.D.templatesEnabled)
    val tabs = if (templatesEnabled) AppTab.entries else AppTab.entries.filter { it != AppTab.MauCau }

    LaunchedEffect(openMauCau) { if (openMauCau > 0) tab = AppTab.MauCau }
    LaunchedEffect(templatesEnabled) { if (!templatesEnabled && tab == AppTab.MauCau) tab = AppTab.TinhNang }

    // Mỗi tab một vị trí cuộn riêng; bar thu gọn khi cuộn xuống > 40dp.
    val scroll = remember(tab) { ScrollState(0) }
    var barCollapsed by remember { mutableStateOf(false) }
    LaunchedEffect(scroll) {
        var last = scroll.value
        val thresh = with(density) { 3.dp.toPx() }
        val top = with(density) { 40.dp.toPx() }
        snapshotFlow { scroll.value }.collect { v ->
            if (kotlin.math.abs(v - last) > thresh) {
                barCollapsed = v > last && v > top
                last = v
            }
        }
    }
    // Cuộn tay ⇒ đóng bàn phím (scrollDismissesKeyboard(.immediately)).
    val dismissOnScroll = remember(focus) {
        object : NestedScrollConnection {
            override fun onPreScroll(available: Offset, source: NestedScrollSource): Offset {
                if (source == NestedScrollSource.UserInput) focus.clearFocus()
                return Offset.Zero
            }
        }
    }
    val keyboardShown = WindowInsets.ime.getBottom(density) > 0
    val title = if (tab == AppTab.KieuGo) "VietTelex" else tab.title
    val titlePx = with(density) { 52.dp.toPx() }

    Box(Modifier.fillMaxSize().background(c.groupedBg).imePadding()) {
        Column(
            Modifier.fillMaxSize()
                .pointerInput(Unit) { detectTapGestures { focus.clearFocus() } }
                .nestedScroll(dismissOnScroll)
                .verticalScroll(scroll)
                .statusBarsPadding(),
        ) {
            Text(title, style = VTType.largeTitle, color = c.label,
                modifier = Modifier.padding(start = 20.dp, top = 8.dp, bottom = 10.dp))
            when (tab) {
                AppTab.KieuGo -> KieuGoTab(ime, onOpenImeSettings, onPickIme)
                AppTab.TinhNang -> TinhNangTab()
                AppTab.MauCau -> MauCauTab()
                AppTab.GioiThieu -> GioiThieuTab()
            }
            // Chừa lối cuộn cho bar nổi (contentMargins 72).
            Spacer(Modifier.navigationBarsPadding().height(72.dp))
        }

        // Tiêu đề inline hiện khi large title cuộn khuất (như navigation bar iOS).
        val showInline = scroll.value > titlePx
        AnimatedVisibility(showInline, enter = fadeIn(), exit = fadeOut(), modifier = Modifier.align(Alignment.TopCenter)) {
            Column(Modifier.fillMaxWidth().background(c.groupedBg.copy(alpha = 0.94f)).statusBarsPadding()) {
                Box(Modifier.fillMaxWidth().height(44.dp), contentAlignment = Alignment.Center) {
                    Text(title, style = VTType.headline, color = c.label)
                }
                Box(Modifier.fillMaxWidth().height(0.5.dp).background(c.separator))
            }
        }

        if (!keyboardShown) {
            Box(Modifier.align(Alignment.BottomCenter).navigationBarsPadding().padding(bottom = 8.dp)) {
                FloatingTabBar(tab, tabs, barCollapsed) { tab = it }
            }
        }
    }
}
