package com.viettelex.android.ime

import android.graphics.Bitmap
import android.graphics.Canvas
import android.text.InputType
import android.view.View
import android.view.ViewGroup
import android.view.inputmethod.EditorInfo
import com.viettelex.keyboard.KeyEffect
import com.viettelex.keyboard.Keys
import com.viettelex.keyboard.PlusGate
import com.viettelex.keyboard.TunnelFx
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
import org.robolectric.android.controller.ServiceController
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import org.robolectric.shadows.ShadowSystemClock
import java.io.File
import java.time.Duration

/**
 * Theme "Lạc trôi" phía IME: Đường hầm trên [KeyEffectView] (trần vòng, hết thì thôi khung hình) + "Lơ lửng" trên
 * [KeyboardView] (CHỈ HÌNH — khung phím / điểm chạm không đổi; nghỉ ⇒ về chỗ rồi dừng). = iOS DriftTests (phần view).
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w411dp-h891dp-port-xxhdpi")
class DriftThemeTest {
    private var ctrl: ServiceController<VietTelexIME>? = null
    private val savedPaywall = PlusGate.paywallEnabled

    @Before fun setUp() { PlusGate.paywallEnabled = false }
    @After fun tearDown() {
        ctrl?.destroy()
        RuntimeEnvironment.getApplication().getSharedPreferences(Keys.PREFS, android.content.Context.MODE_PRIVATE).edit().clear().commit()
        PlusGate.paywallEnabled = savedPaywall
    }

    private fun start(theme: String, effect: String? = null): VietTelexIME {
        ctrl?.destroy()
        val ctx = RuntimeEnvironment.getApplication()
        ctx.getSharedPreferences(Keys.PREFS, android.content.Context.MODE_PRIVATE).edit()
            .putString(Keys.KEYBOARD_THEME, theme).apply { effect?.let { putString(Keys.KEY_EFFECT, it) } }.commit()
        val c = Robolectric.buildService(VietTelexIME::class.java).create()
        ctrl = c
        return c.get()
    }

    private fun show(ime: VietTelexIME): View {
        val v = ime.onCreateInputView()
        ime.setInputView(v)
        val frame = v.parent as ViewGroup
        ime.onStartInputView(EditorInfo().apply { inputType = InputType.TYPE_CLASS_TEXT; packageName = "com.example.chat" }, false)
        val r = frame.getChildAt(0)
        val dm = ime.resources.displayMetrics
        r.measure(View.MeasureSpec.makeMeasureSpec(dm.widthPixels, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(dm.heightPixels, View.MeasureSpec.AT_MOST))
        r.layout(0, 0, r.measuredWidth, r.measuredHeight)
        return r
    }

    private fun <T : View> find(v: View, type: Class<T>): T? {
        if (type.isInstance(v)) return type.cast(v)
        if (v is ViewGroup) for (i in 0 until v.childCount) find(v.getChildAt(i), type)?.let { return it }
        return null
    }

    private fun tap(kb: KeyboardView, label: String) {
        val p = kb.keyCenter(label)!!
        val t = android.os.SystemClock.uptimeMillis()
        kb.dispatchTouchEvent(android.view.MotionEvent.obtain(t, t, android.view.MotionEvent.ACTION_DOWN, p.x, p.y, 0))
        kb.dispatchTouchEvent(android.view.MotionEvent.obtain(t, t + 20, android.view.MotionEvent.ACTION_UP, p.x, p.y, 0))
    }

    /** Theme Lạc trôi: Lơ lửng bật theo "keyMotion" (dù hiệu ứng là Đường hầm); khung phím không đổi khi trôi; nghỉ ⇒ dừng. */
    @Test fun floatIsVisualOnlyAndStops() {
        val ime = start("drift", "tunnel")
        val r = show(ime)
        val kb = find(r, KeyboardView::class.java)!!
        val f = kb.keyFloat
        assertNotNull("theme Lạc trôi ⇒ phím Lơ lửng", f)
        val labels = listOf("q", "g", "m", "a")
        val before = labels.map { kb.keyCenter(it)!! }
        tap(kb, "g")
        assertTrue(f!!.clock.bobbing)
        ShadowSystemClock.advanceBy(Duration.ofMillis(1200))
        val bmp = Bitmap.createBitmap(kb.width, kb.height, Bitmap.Config.ARGB_8888)
        kb.draw(Canvas(bmp))                                   // vẽ có dời hình
        assertEquals("khung phím (vùng chạm) không đổi khi trôi", before, labels.map { kb.keyCenter(it)!! })
        // Nghỉ 2 s ⇒ về chỗ 0,8 s ⇒ dừng hẳn (không còn hẹn khung hình).
        ShadowSystemClock.advanceBy(Duration.ofMillis(2100)); kb.draw(Canvas(bmp))
        assertTrue(f.clock.active && !f.clock.bobbing)
        ShadowSystemClock.advanceBy(Duration.ofMillis(900)); kb.draw(Canvas(bmp))
        assertFalse(f.clock.active)
        assertEquals(before, labels.map { kb.keyCenter(it)!! })
    }

    /** Theme khác / hiệu ứng khác ⇒ không có Lơ lửng (0 chi phí); hiệu ứng "float" ở theme thường ⇒ có. */
    @Test fun floatOnlyWhenChosen() {
        assertNull(find(show(start("nightclub")), KeyboardView::class.java)!!.keyFloat)
        assertNull(find(show(start("mint", "tunnel")), KeyboardView::class.java)!!.keyFloat)
        assertNotNull(find(show(start("mint", "float")), KeyboardView::class.java)!!.keyFloat)
    }

    /** Đường hầm: vòng theo mức combo, trần pool, trong bàn phím; hết thì thôi (nghỉ = 0 khung hình). */
    @Test fun tunnelRingsCappedAndStop() {
        val ctx = RuntimeEnvironment.getApplication()
        val v = KeyEffectView(ctx, 3f)
        v.measure(View.MeasureSpec.makeMeasureSpec(1170, View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(780, View.MeasureSpec.EXACTLY))
        v.layout(0, 0, 1170, 780)
        v.configure(KeyEffect.TUNNEL, 0xFF9B7BFF.toInt())
        val t0 = android.os.SystemClock.uptimeMillis()
        v.burst(300f, 500f, 100f, 130f); v.flush()
        assertEquals("mức 0: vòng đầu hiện ngay, vòng sau trễ", 1, v.tunnelAlive(android.os.SystemClock.uptimeMillis()))
        ShadowSystemClock.advanceBy(Duration.ofMillis(130))
        assertEquals(TunnelFx.rings(0), v.tunnelAlive(android.os.SystemClock.uptimeMillis()))
        repeat(40) { v.burst(300f, 500f, 100f, 130f); v.flush() }
        ShadowSystemClock.advanceBy(Duration.ofMillis(700))
        assertTrue(v.tunnelAlive(android.os.SystemClock.uptimeMillis()) <= TunnelFx.POOL)
        val bmp = Bitmap.createBitmap(1170, 780, Bitmap.Config.ARGB_8888)
        ShadowSystemClock.advanceBy(Duration.ofMillis(2000))
        assertEquals(0, v.tunnelAlive(android.os.SystemClock.uptimeMillis()))
        assertFalse("hết vòng ⇒ không hẹn khung hình", v.run { draw(Canvas(bmp)); tunnelAlive(android.os.SystemClock.uptimeMillis()) > 0 })
        assertTrue(t0 > 0)
    }

    /** Ảnh cho chủ dự án (chỉ khi có thư mục). */
    @Test fun snapshotForOwner() {
        val dir = File("/Users/ptrinh/Downloads/Temp")
        if (!dir.isDirectory) return
        val ime = start("drift", "tunnel")
        val r = show(ime)
        val kb = find(r, KeyboardView::class.java)!!
        val fx = find(r, KeyEffectView::class.java)!!          // view chưa gắn cửa sổ ⇒ post() không chạy: bắn tay
        tap(kb, "h"); fx.flush()
        ShadowSystemClock.advanceBy(Duration.ofMillis(900)); tap(kb, "j"); fx.flush()
        ShadowSystemClock.advanceBy(Duration.ofMillis(300))
        val bmp = Bitmap.createBitmap(r.width, r.height, Bitmap.Config.ARGB_8888)
        r.draw(Canvas(bmp))
        File(dir, "drift-theme-android.png").outputStream().use { bmp.compress(Bitmap.CompressFormat.PNG, 100, it) }
    }
}
