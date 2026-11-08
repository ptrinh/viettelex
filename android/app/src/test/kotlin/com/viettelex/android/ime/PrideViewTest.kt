package com.viettelex.android.ime

import android.os.SystemClock
import android.view.View
import androidx.test.core.app.ApplicationProvider
import com.viettelex.keyboard.KeyEffect
import com.viettelex.keyboard.PrideFlag
import com.viettelex.keyboard.PrideFlagWave
import com.viettelex.keyboard.RainbowBurst
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * Hiệu ứng "Cầu vồng" phía View: vòng cung xoay vòng trong pool, từ khoá ⇒ cờ (vị trí kẹp trong view, kể cả phím sát
 * mép), ẩn ⇒ hết. iOS PrideThemeTests.testOverlayInsideKeyboardAndCapped.
 */
@RunWith(RobolectricTestRunner::class)
class PrideViewTest {
    private val ctx get() = ApplicationProvider.getApplicationContext<android.content.Context>()

    @Test fun rainbowArcsPooledAndFlagInsideView() {
        val d = 3f
        val v = KeyEffectView(ctx, d)
        v.measure(View.MeasureSpec.makeMeasureSpec(1170, View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(870, View.MeasureSpec.EXACTLY))
        v.layout(0, 0, 1170, 870)
        v.configure(KeyEffect.RAINBOWBURST, 0xFFFF8C00.toInt())
        v.prideFlag = PrideFlag.TRANS
        for (i in 0 until 10) { v.burst((i % 10) * 117f + 51f, (i % 3) * 270f + 63f, 102f, 126f); v.flush() }
        val now = SystemClock.uptimeMillis()
        assertEquals(RainbowBurst.POOL, v.rainbowsAlive(now))
        assertFalse("chưa gõ từ khoá ⇒ không có cờ", v.flagFlying(now))
        v.queuePride()
        v.burst(51f, 63f, 102f, 126f); v.flush()          // phím sát mép trái + mép trên
        assertTrue(v.flagFlying(SystemClock.uptimeMillis()))
        val (fx, fy) = v.flagPos.let { it[0] to it[1] }
        assertTrue(fx - PrideFlagWave.WIDTH / 2 * d >= 0)
        assertTrue(fy - (PrideFlagWave.GAP + PrideFlagWave.HEIGHT + PrideFlagWave.RISE) * d >= 0)
        v.halt()
        assertEquals(0, v.rainbowsAlive(SystemClock.uptimeMillis()))
        assertFalse(v.flagFlying(SystemClock.uptimeMillis()))
    }
}
