package com.viettelex.android.shared

import android.content.Context
import android.os.Build
import android.os.LocaleList
import com.viettelex.android.BuildConfig
import com.viettelex.keyboard.Keys
import com.viettelex.keyboard.TouchLog
import com.viettelex.keyboard.TouchLogFormat
import java.io.File

/**
 * Nối TouchLog (module :keyboard) vào filesDir/touchlog.txt. Bản Release KHÔNG
 * bao giờ ghi ký tự gõ (recordsCharacters = BuildConfig.DEBUG). App settings dùng
 * [tail] / [clear] cho "Hiện log" / "Xoá log". Header đầu log ([header]): phiên bản, máy,
 * Android, ABI, locale, nguồn cài, theme — CHỈ dựng khi Debug mode bật.
 */
object DebugLog {
    fun file(ctx: Context) = File(ctx.applicationContext.filesDir, Keys.TOUCHLOG_FILE)

    fun configure(ctx: Context, enabled: Boolean) {
        TouchLog.configure(file(ctx), recordsCharacters = BuildConfig.DEBUG)
        TouchLog.enabled = enabled
        val app = ctx.applicationContext
        TouchLog.headerProvider = if (enabled) ({ header(app) }) else null
    }

    fun tail(ctx: Context, lines: Int = 80): String = TouchLog.tail(lines, file(ctx))

    fun clear(ctx: Context) = TouchLog.clear(file(ctx))

    private fun header(ctx: Context): List<String> {
        val prefs = VTPrefs.of(ctx)
        val custom = !prefs.getString(Keys.ACTIVE_THEME_SPEC, null).isNullOrEmpty()
        return TouchLogFormat.contextLines(TouchLogFormat.Context(
            version = BuildConfig.VERSION_NAME,
            build = BuildConfig.VERSION_CODE.toString(),
            android = "${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT})",
            device = "${Build.MANUFACTURER} ${Build.MODEL}",
            abi = Build.SUPPORTED_ABIS.firstOrNull() ?: "?",
            install = installSource(ctx),
            locales = LocaleList.getDefault().toLanguageTags(),
            uiLanguage = prefs.getString(Keys.UI_LANGUAGE, null) ?: "default",
            // Theme tự tạo: chỉ "custom" (JSON có thể mang tên người dùng đặt).
            theme = if (custom) "custom" else (prefs.getString(Keys.KEYBOARD_THEME, null) ?: "default"),
            debugBuild = BuildConfig.DEBUG,
        ))
    }

    private fun installSource(ctx: Context): String = try {
        val pm = ctx.packageManager
        val installer = if (Build.VERSION.SDK_INT >= 30) {
            pm.getInstallSourceInfo(ctx.packageName).installingPackageName
        } else {
            @Suppress("DEPRECATION") pm.getInstallerPackageName(ctx.packageName)
        }
        when (installer) {
            null -> "sideload"
            "com.android.vending" -> "play"
            else -> installer
        }
    } catch (_: Exception) { "?" }
}
