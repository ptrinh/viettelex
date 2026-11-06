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
import androidx.lifecycle.lifecycleScope
import com.viettelex.android.plus.PlayPlusStore
import com.viettelex.android.plus.PlusController
import com.viettelex.android.plus.PlusPrefs
import com.viettelex.keyboard.Keys
import com.viettelex.keyboard.PlusGate
import kotlinx.coroutines.launch

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
    /** VietTelex Plus — Play Billing; ghi cờ [Keys.PLUS_UNLOCKED] cho IME. */
    private lateinit var plus: PlusController
    private lateinit var store: PlayPlusStore

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.auto(android.graphics.Color.TRANSPARENT, android.graphics.Color.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.auto(android.graphics.Color.TRANSPARENT, android.graphics.Color.TRANSPARENT),
        )
        super.onCreate(savedInstanceState)
        // Onboarding (ONBOARDING-SPEC §5): nhận diện người dùng cũ TRƯỚC mọi chuyển đổi ghi prefs.
        OnboardingStore.migrate(this)
        SettingsProcess.install(this)
        PlusPrefs.install(this)
        com.viettelex.android.shared.UiLang.install(this)   // ngôn ngữ giao diện (mặc định Tiếng Việt)
        migrateThemeSettings(this)   // Tuỳ chỉnh nâng cao chung cũ → theo theme; "Trắng hồng" → Hệ thống + nhấn hồng
        ThemeAssetFlow.gcAsync(this)  // tệp tải về không còn theme nào dùng (luồng nền)
        plus = PlusController(
            // Tham chiếu YẾU: coroutine/Billing có thể giữ store lâu hơn activity (đo: Message hẹn
            // giờ trên main looper → store → lambda → MainActivity sống mãi sau khi rời app).
            store = java.lang.ref.WeakReference(this).let { ref ->
                PlayPlusStore(this) { ref.get()?.takeUnless { it.isDestroyed } }
            }.also { store = it },
            writeFlag = applicationContext.let { app -> { on: Boolean -> PlusPrefs.writePurchased(app, on) } },
            initialPurchased = PlusGate.purchased,
            scope = lifecycleScope,
            onboarding = PlusPrefs.onboarding(this),
        )
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
                    plus = plus,
                )
            }
        }
    }

    override fun onDestroy() {
        // Billing (tự nối lại, hẹn giờ trên main looper) giữ store → activity: ngắt để activity
        // + cây Compose GC được sau khi rời app (RAM-AUDIT #5).
        if (::store.isInitialized) store.release()
        super.onDestroy()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleDeepLink(intent)
    }

    override fun onResume() {
        super.onResume()
        SettingsProcess.refresh(this)    // bàn phím (process khác) có thể vừa ghi prefs
        refreshIme()
        // Đồng bộ giao dịch (mua ở máy khác / hoàn tiền / pending vừa xong).
        lifecycleScope.launch { plus.refresh(loadProducts = false) }
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) refreshIme()
    }

    private fun handleDeepLink(i: Intent?) {
        if (com.viettelex.android.BuildConfig.DEBUG) debugOnboarding(i)
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

    /**
     * Bản Debug — chụp màn hình / thử tay: `am start … --es onboardingDemo choose|mixed|en|vi`
     * (choose = về màn 1; hồ sơ = áp rồi tới màn 2), `--ez mixedTipDemo true` (thẻ người dùng cũ).
     */
    private fun debugOnboarding(i: Intent?) {
        val p = Prefs.of(this)
        i?.getStringExtra("onboardingDemo")?.let { d ->
            p.edit().putBoolean(com.viettelex.keyboard.OnboardingFlow.DONE_KEY, false)
                .remove(com.viettelex.keyboard.OnboardingFlow.PROFILE_KEY).commit()
            com.viettelex.keyboard.OnboardingProfile.of(d)?.let { OnboardingStore.apply(this, it) }
        }
        if (i?.getBooleanExtra("mixedTipDemo", false) == true)
            p.edit().putBoolean(com.viettelex.keyboard.OnboardingFlow.TIP_KEY, true).apply()
    }

    // MARK: dọn RAM khi rời app (RAM-AUDIT #5)

    /**
     * Trước đây app cài đặt chạy CÙNG process với bàn phím — từ API 31 Back không finish activity
     * gốc nên Compose/HWUI (+16.7 MB) nằm lại mãi trong process IME. Giờ app ở process ":settings"
     * (hệ thống dọn được); vẫn finish ở onStop để process cache nhẹ, TRỪ khi chính app vừa mở
     * activity khác mà user sẽ quay về (chọn ảnh/file, Play Billing, Cài đặt bàn phím, chia sẻ,
     * link) — kết quả trả về cần activity còn sống.
     */
    private var launchedChild = false

    @Deprecated("ComponentActivity") @Suppress("DEPRECATION")
    override fun startActivityForResult(intent: Intent, requestCode: Int, options: Bundle?) {
        launchedChild = true
        super.startActivityForResult(intent, requestCode, options)
    }

    @Deprecated("ComponentActivity") @Suppress("DEPRECATION")
    override fun startIntentSenderForResult(intent: android.content.IntentSender, requestCode: Int, fillInIntent: Intent?,
                                            flagsMask: Int, flagsValues: Int, extraFlags: Int, options: Bundle?) {
        launchedChild = true
        super.startIntentSenderForResult(intent, requestCode, fillInIntent, flagsMask, flagsValues, extraFlags, options)
    }

    override fun onStart() {
        super.onStart()
        launchedChild = false
    }

    override fun onStop() {
        super.onStop()
        // context ỨNG DỤNG: PowerManager lấy từ activity giữ activity trong WeakHashMap tĩnh (rò)
        val interactive = applicationContext.getSystemService(android.os.PowerManager::class.java)?.isInteractive ?: true
        if (SettingsExit.shouldFinish(isChangingConfigurations, launchedChild, interactive, isFinishing)) finish()
    }

    private fun refreshIme() {
        val imm = getSystemService(InputMethodManager::class.java)
        val enabled = imm.enabledInputMethodList.any { it.packageName == packageName }
        val cur = Settings.Secure.getString(contentResolver, Settings.Secure.DEFAULT_INPUT_METHOD).orEmpty()
        val s = ImeStatus(enabled, enabled && cur.startsWith("$packageName/"))
        if (s != ime.value) ime.value = s
    }
}

/** Quyết định finish MainActivity ở onStop (tách hàm thuần để test). */
object SettingsExit {
    /**
     * [changingConfig] xoay/đổi theme ⇒ activity dựng lại, không finish; [launchedChild] app vừa
     * mở activity khác chờ kết quả / user quay về; ![interactive] tắt màn hình (mở lại thấy
     * nguyên chỗ cũ — lần rời app sau vẫn finish); [finishing] đã finish.
     */
    fun shouldFinish(changingConfig: Boolean, launchedChild: Boolean, interactive: Boolean, finishing: Boolean): Boolean =
        !changingConfig && !launchedChild && interactive && !finishing
}

/**
 * Process ":settings" (RAM-AUDIT #5): dữ liệu bàn phím dùng trong app (Luyện vuốt, từ điển…) cài
 * riêng ở đây; prefs đồng bộ hai chiều với process bàn phím qua [PrefSync].
 */
object SettingsProcess {
    private var installed = false

    fun install(ctx: android.content.Context) {
        if (installed) return
        installed = true
        val app = ctx.applicationContext
        // androidx.startup (InitializationProvider) nay khai process ":settings" (manifest) ⇒ đã tự chạy;
        // gọi lại là no-op — giữ phòng khi provider bị tắt (emoji màu mới cho UI Compose).
        runCatching {
            androidx.startup.AppInitializer.getInstance(app)
                .initializeComponent(androidx.emoji2.text.EmojiCompatInitializer::class.java)
        }
        if (!com.viettelex.keyboard.KeyboardData.installed)
            com.viettelex.keyboard.KeyboardData.install(com.viettelex.android.ime.AssetBlobs.provider(app.assets))
        com.viettelex.android.shared.PrefSync.forward(app)   // thay đổi trong app ⇒ bàn phím
        // Bàn phím ghi (thả nổi, một tay, thu gọn bar…) ⇒ đọc lại + cập nhật ô cài đặt đang hiện.
        com.viettelex.android.shared.PrefSync.listen(app) { keys -> PrefRefresh.dispatch(app, keys) }
    }

    /** Đọc lại prefs từ đĩa (lỡ broadcast lúc process bị đóng băng) rồi làm mới mọi ô đang hiện. */
    fun refresh(ctx: android.content.Context) {
        val app = ctx.applicationContext
        com.viettelex.android.shared.PrefSync.reload(app)
        PrefRefresh.dispatch(app, null)
    }
}
