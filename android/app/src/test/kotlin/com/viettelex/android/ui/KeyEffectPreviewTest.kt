package com.viettelex.android.ui

import android.app.Activity
import android.graphics.Bitmap
import android.graphics.Canvas
import android.os.Looper
import android.os.SystemClock
import android.view.View
import android.widget.FrameLayout
import androidx.test.core.app.ApplicationProvider
import com.viettelex.keyboard.KeyEffect
import com.viettelex.keyboard.KeywordKind
import com.viettelex.keyboard.ThemePalette
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import org.robolectric.shadows.ShadowSystemClock
import java.time.Duration

/**
 * Ô xem thử trang "Hiệu ứng khi bấm phím": MỌI kiểu ([KeyEffect.entries] — kiểu mới tự vào) chạm ô phải vẽ ra điểm ảnh
 * khác hẳn ô lúc nghỉ (hoặc rung ô, với Rung combo). Ô dựng như Compose: update trước khi có cỡ / gắn window.
 * = iOS KeyEffectPreviewTests.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "xxhdpi")
class KeyEffectPreviewTest {
    private val ctx get() = ApplicationProvider.getApplicationContext<android.content.Context>()
    private val palette = ThemePalette(bg = 0xFFD1D5DB.toInt(), keyFill = 0xFFFFFFFF.toInt(), specialFill = 0xFFAAB0B8.toInt(),
        ink = 0xFF000000.toInt(), trail = 0xFF007AFF.toInt(), balloon = 0xFFFFFFFF.toInt(), popup = 0xFFFFFFFF.toInt(),
        action = 0xFF007AFF.toInt(), actionInk = 0xFFFFFFFF.toInt(), chip = 0xFFFFFFFF.toInt(), isDark = false)

    /** Ô 110 × 84 dp (xxhdpi) gắn vào Activity thật — post / khung hình chạy như trong app. */
    private fun tile(e: KeyEffect): KeyEffectPreviewView {
        val a = Robolectric.buildActivity(Activity::class.java).setup().get()
        val v = KeyEffectPreviewView(a)
        v.update(e, palette, 0)                       // Compose: update trước khi có cỡ
        val root = FrameLayout(a)
        root.addView(v, FrameLayout.LayoutParams(330, 252))
        a.setContentView(root)
        shadowOf(Looper.getMainLooper()).idle()
        v.measure(View.MeasureSpec.makeMeasureSpec(330, View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(252, View.MeasureSpec.EXACTLY))
        v.layout(0, 0, 330, 252)
        return v
    }

    private fun snap(v: View): IntArray {
        val b = Bitmap.createBitmap(v.width, v.height, Bitmap.Config.ARGB_8888)
        v.draw(Canvas(b))
        val px = IntArray(v.width * v.height)
        b.getPixels(px, 0, v.width, 0, 0, v.width, v.height)
        b.recycle()
        return px
    }

    @Test fun everyEffectPreviewDrawsSomething() {
        val blank = mutableListOf<String>()
        for (e in KeyEffect.entries) {
            if (e == KeyEffect.NONE) continue
            val v = tile(e)
            val base = snap(v)
            v.update(e, palette, 1)
            Thread.sleep(60)                          // Matrix dựng dải chữ ở luồng nền rồi post về
            shadowOf(Looper.getMainLooper()).idle()
            var best = 0
            var moved = false
            for (ms in longArrayOf(8, 20, 40, 75, 150, 300, 500)) {
                ShadowSystemClock.advanceBy(Duration.ofMillis(ms))
                val px = snap(v)
                best = maxOf(best, px.indices.count { px[it] != base[it] })
                if (v.translationX != 0f || v.translationY != 0f) moved = true
            }
            if (best < 50 && !moved) blank += "${e.id}($best)"
            v.halt()
        }
        assertTrue("chạm ô xem thử mà không thấy gì: $blank", blank.isEmpty())
    }

    @Test fun scriptInputs() {
        assertEquals(KeywordKind.TET, KeyEffectPreviewScript.keyword(1))
        assertEquals(KeywordKind.LOVE, KeyEffectPreviewScript.keyword(2))
        assertFalse(KeyEffectPreviewScript.beat(KeyEffect.DANCEFLOOR, 1))
        assertTrue(KeyEffectPreviewScript.beat(KeyEffect.DANCEFLOOR, 2))
        assertFalse(KeyEffectPreviewScript.beat(KeyEffect.HEART, 2))
    }

    /** Sàn nhảy LED: lần chạm chẵn = nhịp phím cách ⇒ flash nền; lần lẻ thì không. */
    @Test fun dancefloorBeatOnEverySecondTap() {
        val v = tile(KeyEffect.DANCEFLOOR)
        v.update(KeyEffect.DANCEFLOOR, palette, 1)
        assertEquals(0.0, v.beatAlpha(SystemClock.uptimeMillis() + 20), 1e-9)
        ShadowSystemClock.advanceBy(Duration.ofMillis(500))
        v.update(KeyEffect.DANCEFLOOR, palette, 2)
        assertTrue(v.beatAlpha(SystemClock.uptimeMillis() + 20) > 0.3)
    }
}
