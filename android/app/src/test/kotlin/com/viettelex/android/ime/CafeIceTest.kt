package com.viettelex.android.ime

import android.content.Context
import android.os.SystemClock
import android.view.View
import androidx.test.core.app.ApplicationProvider
import com.viettelex.keyboard.CafeFx
import com.viettelex.keyboard.ComboMeter
import com.viettelex.keyboard.KeyEffect
import com.viettelex.keyboard.ThemeDecoration
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * Đá lanh canh (theme Cà phê sữa đá) phía IME: viên đá ôm phím (pool 6), giọt cà phê mỗi 4 phím, phin trong view, gõ dồn ⇒
 * sữa xoáy, ẩn ⇒ dừng; cảnh ly 2 lớp. = iOS CafeFxTests (bộ vẽ).
 */
@RunWith(RobolectricTestRunner::class)
class CafeIceTest {
    private val ctx get() = ApplicationProvider.getApplicationContext<Context>()

    @Test fun iceDripSwirlInsideView() {
        val d = 3f
        val v = KeyEffectView(ctx, d)
        v.measure(View.MeasureSpec.makeMeasureSpec(1170, View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(780, View.MeasureSpec.EXACTLY))
        v.layout(0, 0, 1170, 780)
        v.configure(KeyEffect.ICE, 0xFF6F4E37.toInt())
        val phin = v.phinRect()
        assertTrue("phin trong view", phin.left >= 0 && phin.top >= 0 && phin.right <= 1170 && phin.bottom <= 780)
        for (i in 0 until 4) {
            v.burst(300f, 400f, 105f, 126f); v.flush()
            assertEquals("mỗi 4 phím một giọt", i == 3, v.dripping(SystemClock.uptimeMillis()))
        }
        val r = v.iceRectAt(0)
        assertEquals(300f, r.centerX(), 1e-3f); assertEquals(400f, r.centerY(), 1e-3f)
        repeat(ComboMeter.THRESHOLDS[2]) { v.burst(300f, 400f, 105f, 126f); v.flush() }
        assertTrue("gõ dồn ⇒ sữa xoáy", v.swirling(SystemClock.uptimeMillis()))
        assertTrue(v.icesAlive(SystemClock.uptimeMillis()) <= CafeFx.POOL)
        v.halt()
        assertFalse(v.swirling(SystemClock.uptimeMillis())); assertEquals(0, v.icesAlive(SystemClock.uptimeMillis()))
    }

    @Test fun cafeScenePainter() {
        val sp = ThemeScenePainter(ThemeDecoration.CAFE, 0x40FFFFFF, false)
        val bmp = android.graphics.Bitmap.createBitmap(390, 260, android.graphics.Bitmap.Config.ARGB_8888)
        sp.draw(android.graphics.Canvas(bmp), 0f, 0f, 390f, 260f, 1f)
        assertEquals("gradient + giọt đọng", 2, sp.layerCount)
        bmp.recycle()
    }
}
