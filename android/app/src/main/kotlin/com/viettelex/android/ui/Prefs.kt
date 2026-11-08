package com.viettelex.android.ui

import android.content.Context
import android.content.SharedPreferences
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import com.viettelex.keyboard.KeyboardSettings
import com.viettelex.keyboard.Keys
import com.viettelex.keyboard.TemplateItem
import com.viettelex.keyboard.Templates

/** SharedPreferences dùng chung với IME (process khác — đồng bộ qua PrefSync) — key/tên file ở [Keys] (module :keyboard). */
object Prefs {
    fun of(ctx: Context): SharedPreferences = ctx.getSharedPreferences(Keys.PREFS, Context.MODE_PRIVATE)
    /** Mặc định y iOS — lấy từ KeyboardSettings để app và IME không lệch nhau. */
    val D = KeyboardSettings()
}

/** State Compose gắn 1 key Boolean; ghi apply() ngay, nghe thay đổi từ IME. */
@Composable
fun rememberBoolPref(key: String, default: Boolean): MutableState<Boolean> =
    rememberPref(key, { getBoolean(key, default) }, { putBoolean(key, it) })

@Composable
fun rememberIntPref(key: String, default: Int): MutableState<Int> =
    rememberPref(key, { getInt(key, default) }, { putInt(key, it) })

@Composable
fun rememberStringPref(key: String, default: String): MutableState<String> =
    rememberPref(key, { getString(key, default) ?: default }, { putString(key, it) })

@Composable
private fun <T> rememberPref(
    key: String,
    read: SharedPreferences.() -> T,
    write: SharedPreferences.Editor.(T) -> Unit,
): MutableState<T> {
    val sp = Prefs.of(LocalContext.current)
    val backing = remember(key) { mutableStateOf(sp.read()) }
    DisposableEffect(key) {
        val l = SharedPreferences.OnSharedPreferenceChangeListener { p, k ->
            if (k == key) backing.value = p.read()
        }
        sp.registerOnSharedPreferenceChangeListener(l)
        // Bàn phím (process khác) ghi key này ⇒ PrefSync đọc lại file ⇒ cập nhật ô.
        val r: (Set<String>?) -> Unit = { keys -> if (keys == null || key in keys) { val v = sp.read(); if (v != backing.value) backing.value = v } }
        PrefRefresh.add(r)
        onDispose { sp.unregisterOnSharedPreferenceChangeListener(l); PrefRefresh.remove(r) }
    }
    return remember(key) {
        object : MutableState<T> {
            override var value: T
                get() = backing.value
                set(v) { backing.value = v; sp.edit().apply { write(v) }.apply() }
            override fun component1() = value
            override fun component2(): (T) -> Unit = { value = it }
        }
    }
}

/**
 * Ô cài đặt đang hiện cần đọc lại khi process bàn phím ghi prefs (reload không kích listener
 * SharedPreferences). keys null = có thể đổi bất kỳ (onResume).
 */
object PrefRefresh {
    private val listeners = LinkedHashSet<(Set<String>?) -> Unit>()
    fun add(l: (Set<String>?) -> Unit) { listeners.add(l) }
    fun remove(l: (Set<String>?) -> Unit) { listeners.remove(l) }
    fun dispatch(ctx: Context, keys: Set<String>?) {
        listeners.toList().forEach { it(keys) }
        if (keys == null || Keys.UI_LANGUAGE in keys) com.viettelex.android.shared.UiLang.refreshFromPrefs(Prefs.of(ctx))
    }
}

/** userTemplates (JSON) ⇄ list — định dạng/parse do module :keyboard ([Templates]) giữ. */
object TemplatesStore {
    fun load(ctx: Context): List<TemplateItem> {
        val p = Prefs.of(ctx)
        com.viettelex.android.shared.VTPrefs.migrateDynamicSnippets(p)
        return loadRaw(ctx, p)
    }

    private fun loadRaw(ctx: Context, p: android.content.SharedPreferences): List<TemplateItem> =
        Templates.load(p.getString(Keys.USER_TEMPLATES, null)) {
        runCatching { ctx.assets.open(Keys.ASSET_TEMPLATES_YAML).bufferedReader().use { it.readText() } }.getOrNull()
    }

    fun save(ctx: Context, items: List<TemplateItem>) {
        Prefs.of(ctx).edit().putString(Keys.USER_TEMPLATES, Templates.toJson(items)).apply()
    }
}
