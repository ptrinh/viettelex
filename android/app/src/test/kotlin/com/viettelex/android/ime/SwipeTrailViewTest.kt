package com.viettelex.android.ime

import android.graphics.Bitmap
import android.graphics.Canvas
import android.view.View
import androidx.test.core.app.ApplicationProvider
import com.viettelex.keyboard.SwipeTrailFx
import com.viettelex.keyboard.SwipeTrailStyle
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * Vệt vuốt phía View: mọi kiểu (cả Ảo ảnh / Tan chảy / Vệt lặp) vẽ được qua Canvas thật — đang vuốt hẹn khung,
 * mờ xong ⇒ ngừng hẹn khung (0 animation khi nghỉ). iOS SwipeTrailStyleTests (settle ⇒ 0 animation).
 */
@RunWith(RobolectricTestRunner::class)
class SwipeTrailViewTest {
    private val ctx get() = ApplicationProvider.getApplicationContext<android.content.Context>()

    private class Probe(ctx: android.content.Context) : SwipeTrailView(ctx, ImeTheme(ctx)) {
        fun frame(c: Canvas, now: Long) = drawTrail(c, now)
        fun sampleKeys() = setSampleKeys()
        fun lit(now: Long) = state.litGlows(now)
        val keyCount get() = state.keyCount
    }

    /** Phím sáng theo đường: lưới phím mẫu ⇒ ô sáng vẽ được, mờ hết ⇒ ngừng hẹn khung; kiểu khác bỏ qua phím. */
    @Test fun keyGlowDrawsThenStops() {
        val c = Canvas(Bitmap.createBitmap(400, 300, Bitmap.Config.ARGB_8888))
        val v = Probe(ctx)
        v.measure(View.MeasureSpec.makeMeasureSpec(400, View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(300, View.MeasureSpec.EXACTLY))
        v.layout(0, 0, 400, 300)
        v.configure(SwipeTrailStyle.SIMPLE)
        v.sampleKeys()
        assertTrue("Đơn giản: không nhận phím", v.keyCount == 0)
        v.configure(SwipeTrailStyle.KEYS)
        v.sampleKeys()
        assertTrue(v.keyCount == 26)
        v.begin()
        val t0 = android.os.SystemClock.uptimeMillis() - 2_000L
        for (i in 0 until 40) { v.add(20f + i * 9, 150f, t0 + i * 8); assertTrue(v.frame(c, t0 + i * 8)) }
        assertTrue(v.lit(t0 + 312) >= 3)
        v.end(fade = true)
        val lift = android.os.SystemClock.uptimeMillis()
        assertTrue(v.frame(c, lift))
        assertFalse("mờ hết ⇒ ngừng hẹn khung", v.frame(c, lift + 400))
        assertTrue(v.lit(lift + 400) == 0)
    }

    @Test fun everyStyleDrawsThenStopsWhenSettled() {
        val bmp = Bitmap.createBitmap(400, 300, Bitmap.Config.ARGB_8888)
        val c = Canvas(bmp)
        for (s in SwipeTrailStyle.entries) {
            if (s == SwipeTrailStyle.NONE || s == SwipeTrailStyle.THEME) continue
            val v = Probe(ctx)
            v.measure(View.MeasureSpec.makeMeasureSpec(400, View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(300, View.MeasureSpec.EXACTLY))
            v.layout(0, 0, 400, 300)
            v.configure(s)
            v.begin()
            // Cùng đồng hồ với end() (SystemClock của Robolectric đứng yên): cú vuốt xảy ra trước lúc nhấc tay.
            val t0 = android.os.SystemClock.uptimeMillis() - 2_000L
            var now = t0
            for (i in 0 until 40) {
                now = t0 + i * 8
                v.add(20f + i * 9, 150f + (i % 7) * 4, now)
                assertTrue(s.id, v.frame(c, now))
            }
            // Ngón đứng yên: Ảo ảnh / Tan chảy vẫn đổi màu theo thời gian ⇒ vẫn vẽ khung (nét còn hiện).
            assertTrue(s.id, v.frame(c, now + 100))
            v.end(fade = true)
            val lift = android.os.SystemClock.uptimeMillis()
            val gone = lift + SwipeTrailFx.CHROMA_FADE.times(1000).toLong() + (SwipeTrailFx.MAX_PARTICLE_LIFE * 1000).toLong() + 50
            assertFalse("${s.id}: nghỉ ⇒ ngừng hẹn khung", v.frame(c, gone))
        }
    }
}
