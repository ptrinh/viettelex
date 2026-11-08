package com.viettelex.android.ime

import android.graphics.Bitmap
import android.graphics.Canvas
import android.os.SystemClock
import android.view.View
import androidx.test.core.app.ApplicationProvider
import com.viettelex.keyboard.HueFlow
import com.viettelex.keyboard.KaleidoBloom
import com.viettelex.keyboard.KeyEffect
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * Theme "Ảo giác" phía View: Kính vạn hoa (≤ 4 bông, tâm luôn để cả bông trong khung, ẩn ⇒ hết) và nền "hueflow" (gợn
 * sóng chỉ khi gõ dồn, có trần nhịp, ẩn ⇒ hết; viền / nền đúng bộ số). iOS PsychedelicThemeTests (phần overlay / view).
 */
@RunWith(RobolectricTestRunner::class)
class PsychedelicViewTest {
    private val ctx get() = ApplicationProvider.getApplicationContext<android.content.Context>()

    private fun <T : View> sized(v: T, w: Int, h: Int): T {
        v.measure(View.MeasureSpec.makeMeasureSpec(w, View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(h, View.MeasureSpec.EXACTLY))
        v.layout(0, 0, w, h)
        return v
    }

    @Test fun kaleidoCappedAndInsideView() {
        val d = 3f
        val v = sized(KeyEffectView(ctx, d), 1170, 780)
        v.configure(KeyEffect.KALEIDO, 0xFFC084FC.toInt())
        val keys = listOf(0f to 0f, 1170f to 780f, 585f to 390f, 20f to 700f)
        repeat(30) { i -> val (x, y) = keys[i % keys.size]; v.burst(x, y, 100f, 126f); v.flush() }
        val now = SystemClock.uptimeMillis()
        assertEquals("trần 4 bông", KaleidoBloom.POOL, v.kaleidoAlive(now))
        val r = (KaleidoBloom.EXTENT * d).toFloat()
        for (i in 0 until KaleidoBloom.POOL) {
            val (cx, cy) = v.kaleidoCenter(i)!!
            assertTrue("bông $i trong khung", cx - r >= -0.5f && cx + r <= 1170.5f && cy - r >= -0.5f && cy + r <= 780.5f)
        }
        // Vẽ được (không ném), còn chạy ⇒ hẹn khung.
        val bmp = Bitmap.createBitmap(1170, 780, Bitmap.Config.ARGB_8888)
        v.draw(Canvas(bmp))
        v.halt()
        assertEquals(0, v.kaleidoAlive(SystemClock.uptimeMillis()))
        // Đổi kiểu ⇒ không còn bông.
        v.configure(KeyEffect.HEART, 0xFFC084FC.toInt())
        assertEquals(0, v.kaleidoAlive(SystemClock.uptimeMillis()))
    }

    @Test fun hueFillRipplesOnlyOnFastTypingAndStops() {
        val fill = sized(RainbowBorderView(ctx, 3f, kind = RainbowBorderView.Kind.HUEFLOW_FILL), 1170, 900)
        assertTrue(fill.isFill)
        assertEquals(12.0, fill.tuning.period, 0.0)
        assertEquals(HueFlow.FILL_ALPHA, fill.tuning.restAlpha, 0.0)
        fill.poke(300f, 400f)
        assertEquals("gõ chậm ⇒ không gợn", 0, fill.ripplesFired)
        assertTrue(fill.running)
        repeat(20) { fill.poke(300f, 400f) }       // dồn trong cùng lúc ⇒ mức combo ≥ 2 ⇒ MỘT gợn (trần nhịp 0,9 s)
        assertEquals(1, fill.ripplesFired)
        val (x, y) = fill.rippleCenter(0)
        assertEquals(300f, x, 0f); assertEquals(400f, y, 0f)
        fill.poke(Float.NaN, Float.NaN)             // phím không có khung: chạy dải, không gợn
        assertEquals(1, fill.ripplesFired)
        val bmp = Bitmap.createBitmap(1170, 900, Bitmap.Config.ARGB_8888)
        fill.draw(Canvas(bmp))
        fill.halt()
        assertFalse(fill.running)
        // Viền "hueflow": chậm như nền, sáng lúc gõ / dịu lúc nghỉ; không gợn.
        val border = RainbowBorderView(ctx, 3f, kind = RainbowBorderView.Kind.HUEFLOW_BORDER)
        assertFalse(border.isFill)
        assertEquals(HueFlow.BORDER_REST, border.tuning.restAlpha, 0.0)
        repeat(20) { border.poke(10f, 10f) }
        assertEquals(0, border.ripplesFired)
        border.halt()
    }
}
