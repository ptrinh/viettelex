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

    /**
     * Một lần: thêm mẫu động có sẵn (tỷ giá/vàng/BTC) vào danh sách đã tự chỉnh. Đã chạy ⇒
     * chỉ một lần đọc bool. Gọi từ cả IME lẫn app (idempotent, so theo text).
     * [sync] = ghi đồng bộ (commit) — IME gọi lúc onCreate để lần ghi một lần này xong TRƯỚC
     * mốc file prefs đầu tiên, không bị coi là "prefs đổi" ở lần mở bàn phím sau.
     */
    fun migrateDynamicSnippets(p: SharedPreferences, sync: Boolean = false) {
        if (p.getBoolean(Keys.DYNAMIC_SNIPPETS_MIGRATED, false)) return
        val json = p.getString(Keys.USER_TEMPLATES, null)
        if (!Templates.shouldMarkDynamicMigrated(json)) return
        val e = p.edit()
        Templates.migrateDynamicBuiltins(json, alreadyRan = false)?.let { e.putString(Keys.USER_TEMPLATES, it) }
        e.putBoolean(Keys.DYNAMIC_SNIPPETS_MIGRATED, true)
        if (sync) e.commit() else e.apply()
    }

    /** Mẫu câu hiện hành: pref JSON, không thì assets/ios-mau-cau.yml. */
    fun templates(ctx: Context, p: SharedPreferences = of(ctx)): List<TemplateItem> =
        Templates.load(migrateDynamicSnippets(p).let { p.getString(Keys.USER_TEMPLATES, null) }) {
            try {
                ctx.assets.open(Keys.ASSET_TEMPLATES_YAML).use { String(it.readBytes(), Charsets.UTF_8) }
            } catch (_: Exception) { null }
        }
}
