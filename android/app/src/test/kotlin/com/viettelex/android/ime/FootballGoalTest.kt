package com.viettelex.android.ime

import android.view.View
import androidx.test.core.app.ApplicationProvider
import com.viettelex.keyboard.CheerBurst
import com.viettelex.keyboard.GoalFx
import com.viettelex.keyboard.GrassTuft
import com.viettelex.keyboard.Key
import com.viettelex.keyboard.KeyEffect
import com.viettelex.keyboard.KeySoundSynth
import com.viettelex.keyboard.ThemeDecoration
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import android.os.SystemClock
import java.nio.file.Files

/**
 * Sút! (theme Bóng đá) phía IME: Enter sút bóng (cung trong view), phím khác nhú cỏ, cụm cổ vũ ⇒ pháo + cờ, tiếng hò reo chỉ
 * khi Âm thanh phím phát, cảnh sân cỏ vẽ trọn nền. = iOS FootballFxTests (overlay, công tắc âm).
 */
@RunWith(RobolectricTestRunner::class)
class FootballGoalTest {
    private val ctx get() = ApplicationProvider.getApplicationContext<android.content.Context>()

    @Test fun cheerRespectsKeySound() {
        val f = Feedback(ctx)
        f.setEventSound(Feedback.EventSound.CHEER)
        assertEquals(Feedback.EventSound.CHEER, f.eventSoundWanted)
        assertFalse("Âm thanh phím tắt ⇒ im", f.cheer())
        assertEquals(0, f.cheers)
        f.configureSound(true, 50, "wood") { }
        assertTrue(f.cheer())
        assertEquals(1, f.cheers)
        f.setEventSound(null)
        assertNull(f.eventSoundWanted)
        f.releaseSound()
    }

    @Test fun cheerWavCachedOnce() {
        val dir = Files.createTempDirectory("cheer").toFile()
        try {
            val w = Feedback.cheerFile(dir)!!
            val (s, rate) = KeySoundSynth.parseWav(w.readBytes())!!
            assertEquals(KeySoundSynth.SURF_SAMPLE_RATE.toDouble(), rate, 0.0)
            assertEquals(KeySoundSynth.cheerSamples().size, s.size)
            val stamp = w.lastModified()
            assertEquals(w, Feedback.cheerFile(dir)); assertEquals(stamp, w.lastModified())
        } finally { dir.deleteRecursively() }
    }

    @Test fun returnKeyDetection() {
        assertTrue(KeyboardView.isReturnKey(Key.Newline)); assertTrue(KeyboardView.isReturnKey(Key.LineBreak))
        assertFalse(KeyboardView.isReturnKey(Key.Space))
    }

    /** Enter ⇒ một cú sút (một tiếng), cung bay + lưới trong view; phím thường ⇒ cỏ; cụm cổ vũ ⇒ cờ trong view. */
    @Test fun shotTuftCheerInsideView() {
        val d = 3f
        val v = KeyEffectView(ctx, d)
        v.measure(View.MeasureSpec.makeMeasureSpec(1170, View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(780, View.MeasureSpec.EXACTLY))
        v.layout(0, 0, 1170, 780)
        v.configure(KeyEffect.GOAL, 0xFFC62828.toInt())
        var events = 0
        v.onThemeEvent = { events++ }
        v.burst(1050f, 700f, 240f, 126f, isReturn = true); v.flush()
        val now = SystemClock.uptimeMillis()
        assertEquals(1, v.shotsAlive(now)); assertEquals(1, events); assertEquals(1, v.shotsFired)
        val p = v.shotPoints(0)
        val r = (GoalFx.BALL_RADIUS * d).toFloat()
        for (i in 0..50) {
            val u = i / 50f; val m = 1 - u
            val x = m * m * p[0] + 2 * m * u * p[2] + u * u * p[4]
            val y = m * m * p[1] + 2 * m * u * p[3] + u * u * p[5]
            assertTrue("cung trong view", x - r >= 0 && x + r <= 1170 && y - r >= 0 && y + r <= 780)
        }
        val net = v.shotNetRect(0)
        assertEquals(167f * d, net.left, 1e-3f); assertEquals(4f * d, net.top, 1e-3f)
        v.burst(100f, 400f, 100f, 126f); v.flush()
        assertEquals(1, v.tuftsAlive(SystemClock.uptimeMillis())); assertEquals("phím thường không sút", 1, v.shotsFired)
        v.queueCheer()
        v.burst(100f, 500f, 100f, 126f); v.flush()
        assertTrue(v.cheerAlive(SystemClock.uptimeMillis()))
        for (i in 0 until CheerBurst.FLAG_COUNT) {
            val f = v.cheerFlag(i)
            assertTrue(f[0] > 0 && f[0] * d < 1170 && f[1] >= 0 && (f[1] + f[3]) * d <= 780)
        }
        repeat(50) { v.burst(1050f, 700f, 240f, 126f, isReturn = true); v.flush() }
        assertEquals("pool 2 cú sút", GoalFx.POOL, v.shotsAlive(SystemClock.uptimeMillis()))
        assertTrue(GrassTuft.POOL >= v.tuftsAlive(SystemClock.uptimeMillis()))
        v.halt()
        assertEquals(0, v.shotsAlive(SystemClock.uptimeMillis())); assertFalse(v.cheerAlive(SystemClock.uptimeMillis()))
    }

    /** Kiểu khác: queueCheer bỏ qua, Enter không sút. */
    @Test fun otherEffectIgnoresGoal() {
        val v = KeyEffectView(ctx, 3f)
        v.layout(0, 0, 1170, 780)
        v.configure(KeyEffect.HEART, 0xFFC62828.toInt())
        v.queueCheer()
        v.burst(1050f, 700f, 240f, 126f, isReturn = true); v.flush()
        assertEquals(0, v.shotsFired); assertFalse(v.cheerAlive(SystemClock.uptimeMillis()))
    }

    /** Cảnh sân cỏ: sọc + vạch + chấm giữa (3 lớp), dựng lại chỉ khi đổi khung. */
    @Test fun pitchScenePainter() {
        val sp = ThemeScenePainter(ThemeDecoration.PITCH, 0x4DFFFFFF, false)
        val bmp = android.graphics.Bitmap.createBitmap(390, 260, android.graphics.Bitmap.Config.ARGB_8888)
        sp.draw(android.graphics.Canvas(bmp), 0f, 0f, 390f, 260f, 1f)
        assertEquals(3, sp.layerCount)
        bmp.recycle()
    }
}
