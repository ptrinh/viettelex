package com.viettelex.android.shared

import android.content.Context
import com.viettelex.android.BuildConfig
import com.viettelex.keyboard.Keys
import com.viettelex.keyboard.TouchLog
import java.io.File

/**
 * Nối TouchLog (module :keyboard) vào filesDir/touchlog.txt. Bản Release KHÔNG
 * bao giờ ghi ký tự gõ (recordsCharacters = BuildConfig.DEBUG). App settings dùng
 * [tail] / [clear] cho "Hiện log" / "Xoá log".
 */
object DebugLog {
    fun file(ctx: Context) = File(ctx.applicationContext.filesDir, Keys.TOUCHLOG_FILE)

    fun configure(ctx: Context, enabled: Boolean) {
        TouchLog.configure(file(ctx), recordsCharacters = BuildConfig.DEBUG)
        TouchLog.enabled = enabled
    }

    fun tail(ctx: Context, lines: Int = 80): String = TouchLog.tail(lines, file(ctx))

    fun clear(ctx: Context) = TouchLog.clear(file(ctx))
}
