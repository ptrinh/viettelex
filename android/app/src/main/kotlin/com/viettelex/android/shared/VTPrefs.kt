package com.viettelex.android.shared

import android.content.Context
import android.content.SharedPreferences
import com.viettelex.keyboard.KeyboardSettings
import com.viettelex.keyboard.Keys
import com.viettelex.keyboard.TemplateItem
import com.viettelex.keyboard.Templates

/**
 * Adapter mỏng trên MỘT SharedPreferences [Keys.PREFS] (thay App Group iOS), dùng
 * chung IME + app settings. Key/mặc định là của module :keyboard ([Keys],
 * [KeyboardSettings]) — ở đây chỉ nối Android vào.
 */
object VTPrefs {
    fun of(ctx: Context): SharedPreferences =
        ctx.applicationContext.getSharedPreferences(Keys.PREFS, Context.MODE_PRIVATE)

    /** Ảnh chụp settings (một lần copy map, không đọc lẻ từng key). */
    fun settings(p: SharedPreferences): KeyboardSettings {
        val all = p.all
        return KeyboardSettings.load { all[it] }
    }

    fun settings(ctx: Context): KeyboardSettings = settings(of(ctx))

    /** Mẫu câu hiện hành: pref JSON, không thì assets/ios-mau-cau.yml. */
    fun templates(ctx: Context, p: SharedPreferences = of(ctx)): List<TemplateItem> =
        Templates.load(p.getString(Keys.USER_TEMPLATES, null)) {
            try {
                ctx.assets.open(Keys.ASSET_TEMPLATES_YAML).use { String(it.readBytes(), Charsets.UTF_8) }
            } catch (_: Exception) { null }
        }
}
