package com.viettelex.android.ime

import android.view.View
import androidx.test.core.app.ApplicationProvider
import com.viettelex.keyboard.KeyEffect
import com.viettelex.keyboard.ZodiacSign
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * Hiệu ứng "Chòm sao" phía View: mỗi phím thắp một sao, chòm xoay vòng trong pool, mọi sao nằm trong khung view (bàn
 * phím), ẩn ⇒ hết sao. iOS ZodiacThemeTests.testConstellationOverlayInsideKeyboardAndCapped (cùng kịch bản 25 phím).
 */
@RunWith(RobolectricTestRunner::class)
class ZodiacViewTest {
    private val ctx get() = ApplicationProvider.getApplicationContext<android.content.Context>()

    @Test fun constellationStarsInsideViewAndPooled() {
        val v = KeyEffectView(ctx, 3f)
        v.measure(View.MeasureSpec.makeMeasureSpec(1170, View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(870, View.MeasureSpec.EXACTLY))
        v.layout(0, 0, 1170, 870)
        v.configure(KeyEffect.CONSTELLATION, 0xFFFF7A2F.toInt())
        v.zodiacSign = ZodiacSign.SCORPIO
        for (i in 0 until 25) {
            v.burst((i % 10) * 117f + 51f, (i % 4) * 180f + 63f, 102f, 126f)
            v.flush()
        }
        // 25 phím, chòm 9 sao: 9 + 9 + 7 ⇒ ô 0 (chòm thứ ba) đang có 7 sao.
        assertEquals(7, v.starsLit(0))
        for (s in 0 until 2) for (i in 0 until v.starsLit(s)) {
            assertTrue(v.starX(s, i) in 0f..1170f && v.starY(s, i) in 0f..870f)
        }
        v.halt()
        assertEquals(0, v.starsLit(0)); assertEquals(0, v.starsLit(1))
    }
}
