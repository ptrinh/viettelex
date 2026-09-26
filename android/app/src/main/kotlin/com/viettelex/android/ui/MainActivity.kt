package com.viettelex.android.ui

import android.content.Intent
import android.os.Bundle
import android.provider.Settings
import android.view.inputmethod.InputMethodManager
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.mutableStateOf
import com.viettelex.keyboard.Keys

/** Trạng thái IME trong hệ thống — làm mới mỗi onResume / khi lấy lại focus (sau picker). */
data class ImeStatus(val enabled: Boolean, val selected: Boolean)

/** Chữ chia sẻ (ACTION_SEND text/plain) đang chờ tab Mẫu Câu gộp vào — xem [MauCauTab]. */
object SharedImport {
    val pending = mutableStateOf<String?>(null)
}

class MainActivity : ComponentActivity() {
    private val ime = mutableStateOf(ImeStatus(false, false))
    /** Tăng mỗi lần có deep link viettelex://maucau. */
    private val openMauCau = mutableStateOf(0)

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.auto(android.graphics.Color.TRANSPARENT, android.graphics.Color.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.auto(android.graphics.Color.TRANSPARENT, android.graphics.Color.TRANSPARENT),
        )
        super.onCreate(savedInstanceState)
        handleDeepLink(intent)
        setContent {
            VTTheme {
                RootScreen(
                    ime = ime.value,
                    openMauCau = openMauCau.value,
                    onOpenImeSettings = {
                        runCatching { startActivity(Intent(Settings.ACTION_INPUT_METHOD_SETTINGS)) }
                    },
                    onPickIme = {
                        getSystemService(InputMethodManager::class.java).showInputMethodPicker()
                    },
                )
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleDeepLink(intent)
    }

    override fun onResume() {
        super.onResume()
        refreshIme()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) refreshIme()
    }

    private fun handleDeepLink(i: Intent?) {
        if (i?.action == Intent.ACTION_SEND && i.type == "text/plain") {
            val text = i.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString() ?: return
            Prefs.of(this).edit().putBoolean(Keys.TEMPLATES_ENABLED, true).apply()
            SharedImport.pending.value = text
            openMauCau.value++
            return
        }
        val d = i?.data ?: return
        if (d.scheme == "viettelex" && d.host == "maucau") {
            // User chủ động mở từ bàn phím ⇒ bật tính năng + nhảy tab.
            Prefs.of(this).edit().putBoolean(Keys.TEMPLATES_ENABLED, true).apply()
            openMauCau.value++
        }
    }

    private fun refreshIme() {
        val imm = getSystemService(InputMethodManager::class.java)
        val enabled = imm.enabledInputMethodList.any { it.packageName == packageName }
        val cur = Settings.Secure.getString(contentResolver, Settings.Secure.DEFAULT_INPUT_METHOD).orEmpty()
        val s = ImeStatus(enabled, enabled && cur.startsWith("$packageName/"))
        if (s != ime.value) ime.value = s
    }
}
