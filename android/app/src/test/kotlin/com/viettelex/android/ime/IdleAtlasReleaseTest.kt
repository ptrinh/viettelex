package com.viettelex.android.ime

import android.os.Looper
import android.text.InputType
import android.view.View
import android.view.ViewGroup
import android.view.inputmethod.EditorInfo
import com.viettelex.keyboard.Keys
import com.viettelex.keyboard.PlusGate
import com.viettelex.keyboard.ThemeAssetPlan
import com.viettelex.keyboard.ThemeAssetRef
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.android.controller.ServiceController
import org.robolectric.annotation.Config
import java.time.Duration

/**
 * Audit 10/11/2026, IME thật: tắt Bạn đồng hành / ẩn lâu ⇒ không giữ atlas; hẹn giờ ẩn KHÔNG giải người nhảy Night Club
 * (lỗi cũ: dropWallpaper → setPhoto(null) giải ~6 MB lúc đang ẩn); hiện lại ⇒ nạp lại nền (vt-rewarm), không chặn khung
 * đầu; theme không tệp ⇒ bỏ skin của theme trước; ảnh dựng sẵn của hiệu ứng phím nhả rồi dựng lại.
 */
@RunWith(RobolectricTestRunner::class)
@Config(qualifiers = "w411dp-h891dp-port-xxhdpi")
class IdleAtlasReleaseTest {
    private var ctrl: ServiceController<VietTelexIME>? = null
    private val savedPaywall = PlusGate.paywallEnabled
    private val prefs get() = RuntimeEnvironment.getApplication().getSharedPreferences(Keys.PREFS, android.content.Context.MODE_PRIVATE)

    @Before fun setUp() { PlusGate.paywallEnabled = false; BuddyView.SpriteAssets.drop() }
    @After fun tearDown() {
        ctrl?.destroy()
        prefs.edit().clear().commit()
        PlusGate.paywallEnabled = savedPaywall
        BuddyView.SpriteAssets.drain(); BuddyView.SpriteAssets.drop()
    }

    private fun start(vararg p: Pair<String, String>): VietTelexIME {
        ctrl?.destroy()
        prefs.edit().apply { p.forEach { (k, v) -> putString(k, v) } }.commit()
        val c = Robolectric.buildService(VietTelexIME::class.java).create()
        ctrl = c
        return c.get()
    }

    private var frame: ViewGroup? = null
    private fun show(ime: VietTelexIME): ImeRootView {
        if (frame == null) { val v = ime.onCreateInputView(); ime.setInputView(v); frame = v.parent as ViewGroup }
        ime.onStartInputView(EditorInfo().apply { inputType = InputType.TYPE_CLASS_TEXT; packageName = "com.example.chat" }, false)
        val r = frame!!.getChildAt(0)
        val dm = ime.resources.displayMetrics
        r.measure(View.MeasureSpec.makeMeasureSpec(dm.widthPixels, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(dm.heightPixels, View.MeasureSpec.AT_MOST))
        r.layout(0, 0, r.measuredWidth, r.measuredHeight)
        return find(r, ImeRootView::class.java)!!
    }

    private fun hideLong(ime: VietTelexIME) {
        ime.onFinishInputView(true)
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(VietTelexIME.IDLE_RELEASE_MS + 1_000))
    }

    private fun <T : View> find(v: View, type: Class<T>): T? {
        if (type.isInstance(v)) return type.cast(v)
        if (v is ViewGroup) for (i in 0 until v.childCount) find(v.getChildAt(i), type)?.let { return it }
        return null
    }

    private fun waitFor(what: String, cond: () -> Boolean) {
        val end = System.currentTimeMillis() + 10_000
        while (!cond()) {
            assertTrue("chờ quá lâu: $what", System.currentTimeMillis() < end)
            Thread.sleep(5)
            shadowOf(Looper.getMainLooper()).idle()
        }
    }

    @Test fun companionOffEmptiesAtlasCache() {
        val ime = start(Keys.KEYBOARD_BUDDY to "cat")            // mèo: miễn phí, Hoạt hình mặc định
        val r = show(ime)
        val b = r.buddy!!
        waitFor("atlas mèo") { b.atlasBitmap != null }
        assertEquals("bản 512 px", 512, b.atlasBitmap!!.width)
        assertTrue(BuddyView.SpriteAssets.cachedBytes > 0)
        ime.onFinishInputView(true)
        prefs.edit().putString(Keys.KEYBOARD_BUDDY, "off").commit()
        val r2 = show(ime)
        assertNull(r2.buddy)
        BuddyView.SpriteAssets.drain()
        assertEquals("tắt ⇒ cache rỗng", 0, BuddyView.SpriteAssets.cachedBytes)
    }

    @Test fun idleReleaseDropsCompanionAtlasAndShowReloads() {
        val ime = start(Keys.KEYBOARD_BUDDY to "cat")
        val b = show(ime).buddy!!
        waitFor("atlas mèo") { b.atlasBitmap != null }
        BuddyView.SpriteAssets.drain()
        hideLong(ime)
        assertNull("ẩn lâu ⇒ view nhả atlas", b.atlasBitmap)
        assertEquals("ẩn lâu ⇒ cache rỗng", 0, BuddyView.SpriteAssets.cachedBytes)
        val again = show(ime).buddy!!
        assertTrue(again === b)
        waitFor("nạp lại nền (vt-rewarm)") { b.atlasBitmap != null }
        assertEquals(512, b.atlasBitmap!!.width)
    }

    @Test fun nightClubIdleReleaseDoesNotDecodeDancer() {
        val ime = start(Keys.KEYBOARD_THEME to "nightclub")
        val sp = show(ime).spotlight
        assertNotNull("Night Club + Plus ⇒ Đèn rọi", sp); sp!!
        waitFor("người nhảy") { sp.dancerAtlas != null }
        hideLong(ime)
        assertNull("ẩn lâu ⇒ nhả người nhảy", sp.dancerAtlas)
        assertFalse("và KHÔNG giải lại lúc đang ẩn (lỗi cũ: setPhoto(null) ⇒ giải ~6 MB)", sp.dancerLoading)
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(30))
        assertNull(sp.dancerAtlas); assertFalse(sp.dancerLoading)
        show(ime)
        waitFor("hiện lại ⇒ giải lại nền") { sp.dancerAtlas != null }
    }

    @Test fun destroyDoesNotDecodeDancer() {
        val ime = start(Keys.KEYBOARD_THEME to "nightclub")
        val sp = show(ime).spotlight!!
        waitFor("người nhảy") { sp.dancerAtlas != null }
        ime.onFinishInputView(true)
        ctrl!!.destroy(); ctrl = null
        assertNull(sp.dancerAtlas)
        assertFalse("onDestroy không giải người nhảy", sp.dancerLoading)
    }

    /** Hiệu ứng phím (Matrix): ảnh dựng sẵn nhả khi ẩn lâu, [KeyEffectView.rewarm] dựng lại ngoài main. */
    @Test fun keyEffectPrerenderedBitmapsReleasedAndRebuilt() {
        val ac = Robolectric.buildActivity(android.app.Activity::class.java).setup()
        val act = ac.get()
        val fx = KeyEffectView(act, 3f)
        act.setContentView(fx)                                   // gắn cửa sổ: kết quả luồng nền về qua View.post
        fx.configure(com.viettelex.keyboard.KeyEffect.MATRIX, 0xFF00FF00.toInt())
        waitFor("dải Matrix") { fx.prerenderedCount > 0 }
        fx.halt()
        assertTrue(fx.releaseIdle())
        assertEquals("ẩn lâu ⇒ nhả ảnh dựng sẵn", 0, fx.prerenderedCount)
        assertFalse("không còn gì để nhả", fx.releaseIdle())
        fx.rewarm()
        waitFor("hiện lại ⇒ dựng lại nền") { fx.prerenderedCount > 0 }
        fx.halt(); ac.pause().stop().destroy()
    }

    @Test fun themeWithoutAssetsDropsSkinCache() {
        val dir = java.nio.file.Files.createTempDirectory("vt-assets").toFile()
        try {
            ThemeAssetLoader.load(ThemeAssetPlan(font = ThemeAssetRef("https://example.invalid/f.ttf")), dir, 0L)
            assertNotNull("theme có tệp ⇒ cache", ThemeAssetLoader.cached)
            val th = ImeTheme(RuntimeEnvironment.getApplication())
            assertNull(th.assets)
            assertNull("theme không tệp ⇒ bỏ skin / phông theme trước", ThemeAssetLoader.cached)
        } finally { dir.deleteRecursively() }
    }
}
