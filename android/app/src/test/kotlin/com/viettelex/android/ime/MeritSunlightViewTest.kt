package com.viettelex.android.ime

import android.graphics.RectF
import android.view.View
import androidx.test.core.app.ApplicationProvider
import com.viettelex.keyboard.KeyEffect
import com.viettelex.keyboard.MeritCounter
import com.viettelex.keyboard.MeritFx
import com.viettelex.keyboard.SunlightFx
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/** Công đức / Nắng qua kính phía View (iOS MeritGlassTests phần overlay): trần nhãn, trong khung view, bộ đếm + ghi thưa. */
@RunWith(RobolectricTestRunner::class)
class MeritSunlightViewTest {
    private val ctx get() = ApplicationProvider.getApplicationContext<android.content.Context>()

    private fun view(e: KeyEffect, w: Int = 390, h: Int = 260): KeyEffectView {
        val v = KeyEffectView(ctx, 1f)
        v.measure(View.MeasureSpec.makeMeasureSpec(w, View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(h, View.MeasureSpec.EXACTLY))
        v.layout(0, 0, w, h)
        v.configure(e, 0xFFE8A317.toInt())
        return v
    }

    @Test fun meritCapsLabelsInsideViewAndCounts() {
        val v = view(KeyEffect.MERIT)
        assertNull("chưa bấm ⇒ chưa dựng gì", v.merit)
        val keys = listOf(17f to 21f, 372f to 21f, 187f to 250f)
        for (i in 0 until 12) { val (x, y) = keys[i % 3]; v.burst(x, y, 35f, 42f); v.flush() }
        val m = v.merit!!
        assertEquals(12, m.counter.count)
        assertEquals(12, m.seq)
        for (i in 0 until MeritFx.CAP) {
            assertTrue(m.labelX(i) - MeritFx.LABEL_WIDTH / 2 >= 0)
            assertTrue(m.labelX(i) + MeritFx.LABEL_WIDTH / 2 <= 390)
            assertTrue("cả đường bay trong view", m.labelY(i) - MeritFx.RISE - MeritFx.LABEL_HEIGHT / 2 >= 0)
        }
    }

    @Test fun meritCounterPersistsThrottledAndResetsAtMidnight() {
        val v = view(KeyEffect.MERIT)
        val off = java.util.TimeZone.getDefault().getOffset(System.currentTimeMillis()) / 1000
        var epoch = 86_400.0 * 20_000 - off - 5
        v.meritEpoch = { epoch }
        val today = MeritCounter.dayIndex(epoch, off)
        val space = RectF(100f, 210f, 290f, 252f)
        v.spaceFrame = { out -> out.set(space); true }
        val saved = ArrayList<Pair<Int, Int>>()
        v.attachMeritStore(load = { today to 41 }, save = { d, c -> saved.add(d to c) })
        assertEquals(41, v.merit!!.counter.count)
        assertNotNull("nhãn đếm trên phím cách", v.merit!!.counterLabel)
        assertTrue(space.contains(v.merit!!.counterFrame.left, v.merit!!.counterFrame.top))
        v.burst(20f, 60f, 35f, 42f); v.flush()
        assertEquals(42, saved.last().second)
        v.burst(20f, 60f, 35f, 42f); v.flush()
        assertEquals("ghi thưa", 1, saved.size)
        epoch += 10
        v.burst(20f, 60f, 35f, 42f); v.flush()
        assertEquals(1, v.merit!!.counter.count)
        v.halt()
        assertEquals(today + 1 to 1, saved.last())
    }

    @Test fun sunlightPoolAndBeamsFromTop() {
        val v = view(KeyEffect.SUNLIGHT)
        for (i in 0 until 12) { v.burst(137f, 171f, 35f, 42f); v.flush() }
        val s = v.sunlight!!
        val now = android.os.SystemClock.uptimeMillis()
        assertTrue(s.alive(now) <= SunlightFx.POOL)
        val b = s.beam(0)
        assertEquals(0f, b[1], 0f); assertEquals(150f, b[5], 0.001f)
        assertTrue("gõ dồn ⇒ ánh nến", s.candle.changes >= 1)
    }

    /** Xem thử: một lần bấm ⇒ có hình. */
    @Test fun previewShowsSomething() {
        for (e in listOf(KeyEffect.MERIT, KeyEffect.SUNLIGHT)) {
            val v = view(e, 120, 84)
            v.burst(60f, 55f, 34f, 42f); v.flush()
            val now = android.os.SystemClock.uptimeMillis()
            val n = if (e == KeyEffect.MERIT) v.merit!!.alive(now) else v.sunlight!!.alive(now)
            assertEquals(e.id, 1, n)
        }
    }
}
