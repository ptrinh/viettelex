package com.viettelex.android.ime

import android.content.Context
import android.os.SystemClock
import android.view.View
import androidx.test.core.app.ApplicationProvider
import com.viettelex.keyboard.AquariumFx
import com.viettelex.keyboard.KeyEffect
import com.viettelex.keyboard.ThemeDecoration
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * Cho cá ăn (theme Bể cá) phía IME: bộ đếm nạp từ nơi lưu (≥ 500 ⇒ 4 chú), cá trong view, phím thả viên + mô phỏng chạy,
 * ẩn ⇒ dừng + ghi, ô xem thử không lưu, cảnh bể 4 lớp. = iOS AquariumFxTests (bộ vẽ).
 */
@RunWith(RobolectricTestRunner::class)
class AquariumFeedTest {
    private val ctx get() = ApplicationProvider.getApplicationContext<Context>()

    private fun view(d: Float): KeyEffectView {
        val v = KeyEffectView(ctx, d)
        v.measure(View.MeasureSpec.makeMeasureSpec(1170, View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(780, View.MeasureSpec.EXACTLY))
        v.layout(0, 0, 1170, 780)
        return v
    }

    @Test fun dropsPelletsAndPersistsOnHide() {
        val prefs = ctx.getSharedPreferences("aquarium-test", Context.MODE_PRIVATE)
        prefs.edit().clear().putInt(AquariumFx.STORAGE_KEY, 500).commit()
        val d = 3f
        val v = view(d)
        v.configure(KeyEffect.FISHFEED, 0xFF0B3D66.toInt())
        v.fishPrefs = prefs
        val w = v.fishWorldForTest
        assertNotNull(w)
        assertEquals("500 viên đã ăn ⇒ 4 chú", 4, w!!.count)
        for (f in w.fish) assertTrue("cá trong view", f.x * d in 0.0..1170.0 && f.y * d in 0.0..780.0)
        v.burst(540f, 300f, 100f, 126f); v.flush()
        assertTrue("đang gõ ⇒ mô phỏng chạy", v.fishRunning(SystemClock.uptimeMillis()))
        assertEquals(1, v.fishWorldForTest!!.pellets.count { it.alive })
        v.halt()
        assertFalse("ẩn ⇒ dừng hẳn", v.fishRunning(SystemClock.uptimeMillis()))
        assertTrue(prefs.getInt(AquariumFx.STORAGE_KEY, 0) >= 500)
        assertEquals(com.viettelex.keyboard.KeyEffectBand.BELOW_KEYS, v.effect.band)
    }

    @Test fun previewWithoutPrefsStartsAtZero() {
        val v = view(3f)
        v.configure(KeyEffect.FISHFEED, 0xFF0B3D66.toInt())
        assertEquals(0, v.fishWorldForTest!!.eaten)
        assertEquals(AquariumFx.BASE_FISH, v.fishWorldForTest!!.count)
    }

    @Test fun aquariumScenePainter() {
        val sp = ThemeScenePainter(ThemeDecoration.AQUARIUM, 0x12FFFFFF, true)
        val bmp = android.graphics.Bitmap.createBitmap(390, 260, android.graphics.Bitmap.Config.ARGB_8888)
        sp.draw(android.graphics.Canvas(bmp), 0f, 0f, 390f, 260f, 1f)
        assertEquals("gradient + vệt nắng + cát + rong", 4, sp.layerCount)
        bmp.recycle()
    }
}
