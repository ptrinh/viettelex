package com.viettelex.android.ime

import android.graphics.Bitmap
import android.graphics.Canvas
import android.os.SystemClock
import android.view.View
import androidx.test.core.app.ApplicationProvider
import com.viettelex.keyboard.KeyEffect
import com.viettelex.keyboard.RainFx
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.shadows.ShadowSystemClock
import java.time.Duration

/**
 * Hiệu ứng "Mưa" phía IME (KeyEffectView): đếm phím → mưa thưa + đèn ấm, trần hạt, trong khung bàn phím, nghỉ = hết
 * khung hình, ẩn bàn phím ⇒ về đầu, ô xem thử có hình. = iOS RainOverlayTests.
 */
@RunWith(RobolectricTestRunner::class)
class RainEffectViewTest {
    private val ctx get() = ApplicationProvider.getApplicationContext<android.content.Context>()

    private fun view(): KeyEffectView {
        val v = KeyEffectView(ctx, 3f)
        v.measure(View.MeasureSpec.makeMeasureSpec(1170, View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(780, View.MeasureSpec.EXACTLY))
        v.layout(0, 0, 1170, 780)
        v.configure(KeyEffect.RAIN, 0xFFE9A84E.toInt(), dark = true)
        return v
    }

    private fun draw(v: KeyEffectView): Boolean {
        val bmp = Bitmap.createBitmap(1170, 780, Bitmap.Config.ARGB_8888)
        val m = KeyEffectView::class.java.getDeclaredMethod("drawEffects", Canvas::class.java).apply { isAccessible = true }
        return m.invoke(v, Canvas(bmp)) as Boolean
    }

    @Test fun clearingArcAndResetOnHide() {
        val v = view()
        assertEquals(1.0, v.rainIntensity, 0.0)
        repeat(85) { v.burst(300f, 400f, 100f, 120f); v.flush() }
        assertEquals(85, v.rainKeyCount)
        assertEquals(0.8, v.rainIntensity, 1e-12)
        assertEquals(RainFx.glow(85), v.rainGlowTarget, 1e-12)
        repeat(400) { v.burst(300f, 400f, 100f, 120f); v.flush() }
        assertEquals(RainFx.FLOOR_INTENSITY, v.rainIntensity, 1e-12)
        assertEquals(RainFx.GLOW_MAX, v.rainGlowTarget, 1e-12)
        v.halt()   // ẩn bàn phím (onFinishInputView)
        assertEquals(0, v.rainKeyCount)
        assertEquals(1.0, v.rainIntensity, 0.0)
        assertEquals(0.0, v.rainGlowAt(SystemClock.uptimeMillis()), 0.0)
        assertEquals(0, v.rainDropsAlive(SystemClock.uptimeMillis()))
    }

    @Test fun capsInsideBoundsAndIdleStop() {
        val v = view()
        val keys = listOf(floatArrayOf(0f, 0f), floatArrayOf(1170f, 780f), floatArrayOf(600f, 300f))
        repeat(200) { n ->
            val k = keys[n % keys.size]
            v.burst(k[0], k[1], 100f, 120f); v.flush()
            ShadowSystemClock.advanceBy(Duration.ofMillis(60))
            val now = SystemClock.uptimeMillis()
            assertTrue(v.rainDropsAlive(now) <= RainFx.MAX_DROPS)
            assertTrue(v.rainTapsAlive(now) <= RainFx.TAP_SLOTS)
        }
        for (i in 0 until RainFx.MAX_DROPS) { val x = v.rainDropX(i); assertTrue("$x", x == 0f || x in 0f..1170f) }
        for (i in 0 until RainFx.TAP_SLOTS) { val (x, y) = v.rainTapPos(i); assertTrue(x in 0f..1170f && y in 0f..780f) }
        assertTrue("đang gõ ⇒ còn khung hình", draw(v))
        // Ngừng gõ: hết đời hạt (3 s) + đèn chuyển xong ⇒ không còn khung hình nào (nghỉ = 0).
        ShadowSystemClock.advanceBy(Duration.ofMillis((RainFx.IDLE_AFTER * 1000).toLong() + 10))
        val now = SystemClock.uptimeMillis()
        assertEquals(0, v.rainDropsAlive(now)); assertEquals(0, v.rainTapsAlive(now))
        assertFalse("nghỉ ⇒ thôi hẹn khung hình", draw(v))
        assertTrue("đèn ấm vẫn giữ (vẽ tĩnh)", v.rainGlowAt(now) > 0.0)
        v.halt()
    }

    @Test fun previewShowsSomething() {
        val v = view()
        v.previewRain(200)
        v.burst(200f, 70f); v.flush()
        assertEquals(200, v.rainKeyCount)
        assertEquals(0.5, v.rainIntensity, 1e-12)
        assertEquals(RainFx.glow(200), v.rainGlowTarget, 1e-12)
        val now = SystemClock.uptimeMillis()
        assertEquals(1, v.rainDropsAlive(now)); assertEquals(1, v.rainTapsAlive(now))
        assertTrue(draw(v))
        v.halt()
    }
}
