package com.viettelex.android.ime

import android.os.Looper
import android.os.SystemClock
import android.text.InputType
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.inputmethod.EditorInfo
import com.viettelex.keyboard.BeatFlash
import com.viettelex.keyboard.Keys
import com.viettelex.keyboard.PlusGate
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

/**
 * "Sàn nhảy LED" — flash nền ở phím cách, IME thật: lớp flash ngay DƯỚI KeyboardView, phủ strip + phím; phím chữ không
 * flash, phím cách flash; 10 phím cách trong 1 s ⇒ ≤ 3 flash; kiểu khác ⇒ không có lớp. = iOS testBeatFlashOnSpaceOnlyBehindKeys.
 */
@RunWith(RobolectricTestRunner::class)
@Config(qualifiers = "w411dp-h891dp-port-xxhdpi")
class BeatFlashTest {
    private var ctrl: ServiceController<VietTelexIME>? = null
    private val savedPaywall = PlusGate.paywallEnabled

    @Before fun setUp() { PlusGate.paywallEnabled = false }
    @After fun tearDown() {
        ctrl?.destroy()
        RuntimeEnvironment.getApplication().getSharedPreferences(Keys.PREFS, android.content.Context.MODE_PRIVATE)
            .edit().clear().commit()
        PlusGate.paywallEnabled = savedPaywall
    }

    private fun start(effect: String): VietTelexIME {
        ctrl?.destroy()
        RuntimeEnvironment.getApplication().getSharedPreferences(Keys.PREFS, android.content.Context.MODE_PRIVATE).edit()
            .putString(Keys.KEY_EFFECT, effect).commit()
        val c = Robolectric.buildService(VietTelexIME::class.java).create()
        ctrl = c
        return c.get()
    }

    private fun show(ime: VietTelexIME): ImeRootView {
        val v = ime.onCreateInputView()
        ime.setInputView(v)
        val frame = v.parent as ViewGroup
        ime.onStartInputView(EditorInfo().apply { inputType = InputType.TYPE_CLASS_TEXT; packageName = "com.example.chat" }, false)
        val r = frame.getChildAt(0)
        val dm = ime.resources.displayMetrics
        r.measure(View.MeasureSpec.makeMeasureSpec(dm.widthPixels, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(dm.heightPixels, View.MeasureSpec.AT_MOST))
        r.layout(0, 0, r.measuredWidth, r.measuredHeight)
        return find(r, ImeRootView::class.java)!!
    }

    private fun <T : View> find(v: View, type: Class<T>): T? {
        if (type.isInstance(v)) return type.cast(v)
        if (v is ViewGroup) for (i in 0 until v.childCount) find(v.getChildAt(i), type)?.let { return it }
        return null
    }

    private fun tap(kb: KeyboardView, x: Float, y: Float) {
        val t = SystemClock.uptimeMillis()
        val down = MotionEvent.obtain(t, t, MotionEvent.ACTION_DOWN, x, y, 0)
        val up = MotionEvent.obtain(t, t + 40, MotionEvent.ACTION_UP, x, y, 0)
        kb.dispatchTouchEvent(down); kb.dispatchTouchEvent(up)
        down.recycle(); up.recycle()
        shadowOf(Looper.getMainLooper()).idle()
    }

    @Test fun flashOnSpaceOnlyBehindKeysCapped() {
        val r = show(start("dancefloor"))
        val kb = r.keyboard
        val f = r.beatFlash
        assertNotNull("Sàn nhảy LED ⇒ có lớp flash", f); f!!
        assertEquals("ngay DƯỚI hàng phím", r.indexOfChild(kb) - 1, r.indexOfChild(f))
        assertEquals(0, f.top); assertEquals(r.width, f.width)
        assertEquals("phủ strip + phím, không tràn xuống phần đệm dưới", kb.bottom, f.bottom)
        assertFalse(f.dispatchTouchEvent(MotionEvent.obtain(0, 0, MotionEvent.ACTION_DOWN, 10f, 10f, 0)))

        for (s in listOf("t", "e", "t")) kb.keyCenter(s)!!.let { tap(kb, it.x, it.y) }
        assertEquals("phím chữ: không flash", 0, f.gate.fired)

        val sp = kb.spaceCenter()!!
        tap(kb, sp.x, sp.y)
        assertEquals("phím cách: flash", 1, f.gate.fired)
        assertTrue(f.alphaAt(SystemClock.uptimeMillis() + 20) > 0.5)
        repeat(9) { tap(kb, sp.x, sp.y) }
        assertEquals("10 phím cách trong 1 s ⇒ ≤ 3 flash", BeatFlash.MAX_PER_SECOND, f.gate.fired)
    }

    @Test fun otherEffectHasNoFlashLayer() {
        val r = show(start("heart"))
        assertNull(r.beatFlash)
        assertNull(find(r, BeatFlashView::class.java))
    }
}
