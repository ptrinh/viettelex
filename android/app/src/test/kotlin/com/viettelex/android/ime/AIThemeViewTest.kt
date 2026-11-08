package com.viettelex.android.ime

import android.view.View
import androidx.test.core.app.ApplicationProvider
import com.viettelex.keyboard.AIEye
import com.viettelex.keyboard.KeyEffect
import com.viettelex.keyboard.TokenStream
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import kotlin.math.hypot

/**
 * Theme AI phía View: Mắt AI (đồng tử kẹp trong mống mắt, thở có hạn rồi lim dim = 0 khung hình / 0 hẹn giờ) và Token AI
 * (chip theo chữ, đường bay trong khung view, vệt sáng chỉ khi gợi ý đổi). iOS AIThemeTests (phần overlay / view).
 */
@RunWith(RobolectricTestRunner::class)
class AIThemeViewTest {
    private val ctx get() = ApplicationProvider.getApplicationContext<android.content.Context>()

    private fun <T : View> sized(v: T, w: Int, h: Int): T {
        v.measure(View.MeasureSpec.makeMeasureSpec(w, View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(h, View.MeasureSpec.EXACTLY))
        v.layout(0, 0, w, h)
        return v
    }

    @Test fun eyePupilClampedAndIdleBounded() {
        val e = sized(AIEyeView(ctx, 3f, lowPower = false), 132, 132)
        assertEquals(AIEye.Phase.RESTING, e.phase)
        assertFalse("chưa gõ ⇒ không hẹn gì", e.tickScheduled)
        e.keyPressed(5000f, 66f)                    // phím xa bên phải
        val p = e.pupilNow()
        assertTrue(p[0] > 0f)
        assertEquals(0f, p[1], 1f)
        assertTrue(hypot(p[0].toDouble(), p[1].toDouble()) <= e.maxOffsetPx() + 1e-6)
        assertEquals(AIEye.Phase.ACTIVE, e.phase)
        assertTrue(e.tickScheduled)
        // Thở: đúng lúc nghỉ 2 s ⇒ chuyển động có hạn (≤ 3 nhịp), rồi lim dim = hết chuyển động, không hẹn giờ.
        e.backdate(2.5)
        e.tickAt(android.os.SystemClock.uptimeMillis() / 1000.0)
        assertEquals(AIEye.Phase.BREATHING, e.phase)
        assertTrue(e.isMoving())
        e.backdate(7.0)
        e.tickAt(android.os.SystemClock.uptimeMillis() / 1000.0)
        assertEquals(AIEye.Phase.RESTING, e.phase)
        e.halt()
        assertFalse(e.isMoving())
        assertFalse(e.tickScheduled)
        assertEquals(AIEye.REST_GLOW.toFloat(), e.glowNow(), 1e-6f)
        assertEquals(AIEye.REST_LID.toFloat(), e.lidNow(), 1e-6f)
    }

    @Test fun eyeLowPowerHasNoMotion() {
        val e = sized(AIEyeView(ctx, 3f, lowPower = true), 132, 132)
        e.keyPressed(0f, 0f)
        assertFalse("tiết kiệm pin ⇒ không hoạt ảnh", e.isMoving())
        e.tickle()
        assertFalse(e.isMoving())
    }

    @Test fun tokensChipsPathsAndShimmer() {
        val v = sized(KeyEffectView(ctx, 3f), 1170, 780)
        v.configure(KeyEffect.TOKENS, 0xFF8B5CF6.toInt())
        v.tokenTarget = { out -> out[0] = 585f; out[1] = 60f; true }
        v.burst(300f, 450f, 100f, 126f); v.flush()
        assertEquals("chưa có chữ ⇒ không bắn", 0, v.tokenChipCount(0))
        v.queueToken("ế"); v.burst(300f, 450f, 100f, 126f); v.flush()
        assertEquals(6, v.tokenChipCount(0))
        assertEquals("ế", v.tokenGlyphs[0])
        for (i in 0 until 6) {
            val pts = v.tokenPath(0, i)
            for (k in 0 until 3) {
                assertTrue(pts[2 * k] in 0.0..1170.0); assertTrue(pts[2 * k + 1] in 0.0..780.0)
            }
            assertEquals("đích = Mắt AI / dải gợi ý", 585.0, pts[4], 1e-9); assertEquals(60.0, pts[5], 1e-9)
        }
        // Đích ngoài khung ⇒ kẹp vào trong.
        v.tokenTarget = { out -> out[0] = -500f; out[1] = -500f; true }
        v.queueToken("b"); v.burst(1160f, 770f, 100f, 126f); v.flush()
        assertEquals(TokenStream.chipCount("b"), v.tokenChipCount(1))
        val q = v.tokenPath(1, 0)
        assertEquals(TokenStream.INSET * 3, q[4], 1e-9); assertEquals(TokenStream.INSET * 3, q[5], 1e-9)
        // Vệt sáng: chỉ khi gợi ý đổi thật.
        v.suggestionsChanged(listOf("xin", "chào"), 100f, 0f, 1000f, 120f)
        assertTrue(v.shimmerActive)
        assertEquals(100f, v.shimmerRect.left, 0f)
        v.halt()
        assertFalse(v.shimmerActive)
        v.suggestionsChanged(emptyList(), 100f, 0f, 1000f, 120f)
        assertFalse("rỗng ⇒ không quét", v.shimmerActive)
        // Kiểu khác ⇒ bỏ qua hẳn.
        v.configure(KeyEffect.HEART, 0xFF8B5CF6.toInt())
        v.suggestionsChanged(listOf("cảm", "ơn"), 100f, 0f, 1000f, 120f)
        assertFalse(v.shimmerActive)
    }
}
