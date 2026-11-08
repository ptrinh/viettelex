package com.viettelex.android.ime

import android.os.SystemClock
import android.view.View
import androidx.test.core.app.ApplicationProvider
import com.viettelex.keyboard.KeyEffect
import com.viettelex.keyboard.RepsFx
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * Hiệu ứng Rep (theme Gym) phía View: đếm hiệp, nhãn có trần + đường bay trong khung view, huy hiệu / BEAST MODE, nghỉ 60 s
 * hoặc ẩn bàn phím ⇒ hiệp về 0. = iOS GymThemeTests.testRepOverlayInsideShiftedBoundsCappedAndResets.
 */
@RunWith(RobolectricTestRunner::class)
class GymRepsViewTest {
    private val ctx get() = ApplicationProvider.getApplicationContext<android.content.Context>()
    private val d = 3f

    private fun view(): KeyEffectView {
        val v = KeyEffectView(ctx, d)
        v.measure(View.MeasureSpec.makeMeasureSpec(1170, View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(900, View.MeasureSpec.EXACTLY))
        v.layout(0, 0, 1170, 900)
        v.configure(KeyEffect.REPS, 0xFFC6FF1A.toInt())
        return v
    }

    @Test fun repsCountSetsCapLabelsStayInside() {
        val v = view()
        assertFalse("chưa gõ ⇒ chưa vẽ thanh", v.repBarActive)
        // Gõ dồn sát mép trên trái (tâm phím y = 5 dp) ⇒ combo ⇒ nhãn.
        for (i in 0 until 23) { v.burst((i % 10) * 117f + 6f, 15f, 102f, 126f); v.flush() }
        assertEquals(2, v.repCounterState.sets); assertEquals(3, v.repFillShown)
        assertTrue(v.repBarActive)
        assertEquals("SET 2 ✓", v.repBadgeLabel)
        val now = SystemClock.uptimeMillis()
        assertTrue(v.repBadgeAlive(now))
        assertTrue("pool nhãn có trần", v.repLabelsAlive(now) <= RepsFx.LABEL_CAP)
        assertTrue(v.repLabelsAlive(now) > 0)
        val hw = (RepsFx.LABEL_HALF_WIDTH * d).toFloat(); val hh = (RepsFx.LABEL_HEIGHT / 2 * d).toFloat()
        for (i in 0 until RepsFx.LABEL_CAP) {
            val (x, y) = v.repLabelCenter(i)
            assertTrue("x $x", x - hw >= -1e-3f && x + hw <= v.width + 1e-3f)
            assertTrue("bay lên vẫn trong khung: $y", y - (RepsFx.LABEL_RISE * d).toFloat() - hh >= -1e-3f)
            assertTrue(y + hh <= v.height + 1e-3f)
        }
        // Từ khoá ⇒ BEAST MODE ở lượt vẽ kế.
        assertFalse(v.repSlamAlive(SystemClock.uptimeMillis()))
        v.queueBeastMode()
        v.burst(900f, 600f, 102f, 126f); v.flush()
        assertTrue(v.repSlamAlive(SystemClock.uptimeMillis()))
        assertEquals(4, v.repFillShown)
        // Nghỉ chưa đủ ⇒ giữ; đủ 60 s ⇒ về 0.
        v.debugSweepReps(10.0)
        assertEquals(4, v.repFillShown)
        v.debugSweepReps(RepsFx.IDLE_RESET + 1)
        assertEquals(0, v.repFillShown); assertEquals(0, v.repCounterState.sets)
        assertFalse(v.repBarActive)
        // Ẩn bàn phím ⇒ halt ⇒ về 0, không còn gì bay.
        for (i in 0 until 4) { v.burst(300f, 300f, 102f, 126f); v.flush() }
        v.halt()
        assertEquals(0, v.repFillShown); assertEquals(0, v.repCounterState.reps)
        assertEquals(0, v.repLabelsAlive(SystemClock.uptimeMillis()))
        assertFalse(v.repSlamAlive(SystemClock.uptimeMillis()))
    }

    @Test fun otherEffectsIgnoreBeastMode() {
        val v = KeyEffectView(ctx, d)
        v.configure(KeyEffect.HEART, 0xFFFF0000.toInt())
        v.queueBeastMode()
        v.burst(100f, 100f); v.flush()
        assertFalse(v.repSlamAlive(SystemClock.uptimeMillis()))
        assertFalse(v.repBarActive)
    }
}
