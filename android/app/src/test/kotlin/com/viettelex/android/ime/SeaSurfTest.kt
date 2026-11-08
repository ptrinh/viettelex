package com.viettelex.android.ime

import android.view.View
import androidx.test.core.app.ApplicationProvider
import com.viettelex.keyboard.KeyEffect
import com.viettelex.keyboard.KeySoundSynth
import com.viettelex.keyboard.SeaFx
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.shadows.ShadowSystemClock
import java.nio.file.Files
import java.time.Duration

/**
 * Tiếng sóng vỗ của hiệu ứng Biển phía IME: chỉ khi Âm thanh phím (đường âm riêng) phát, MỖI CON SÓNG MỚI một tiếng
 * (gõ dồn trong [SeaFx.LAUNCH_GAP] không thêm tiếng), WAV ghi một lần. = iOS KeyEffectTests (testSeaSurf…, overlay Biển).
 */
@RunWith(RobolectricTestRunner::class)
class SeaSurfTest {
    private val ctx get() = ApplicationProvider.getApplicationContext<android.content.Context>()

    /** Tắt Âm thanh phím / kiểu Hệ thống / âm lượng 0 / máy im ⇒ không có tiếng sóng. */
    @Test fun surfRespectsKeySound() {
        assertTrue(Feedback.surfAllowed(KeySoundSynth.route(true, 50, true, "wood")))
        assertFalse(Feedback.surfAllowed(KeySoundSynth.route(false, 50, true, "wood")))
        assertFalse(Feedback.surfAllowed(KeySoundSynth.route(true, 50, true, "system")))
        assertFalse(Feedback.surfAllowed(KeySoundSynth.route(true, 0, true, "wood")))
        assertFalse(Feedback.surfAllowed(KeySoundSynth.route(true, 50, false, "wood")))
        val f = Feedback(ctx)
        f.setSurfEnabled(true)
        assertFalse("Âm thanh phím tắt ⇒ im", f.surf(1.65))
        assertEquals(0, f.surfs)
        f.configureSound(true, 50, "wood") { }
        assertTrue(f.surf(1.0))
        assertEquals(1, f.surfs)
        f.releaseSound()
    }

    @Test fun surfWavCachedOnce() {
        val dir = Files.createTempDirectory("surf").toFile()
        try {
            val f = Feedback.surfFile(dir)!!
            val (s, rate) = KeySoundSynth.parseWav(f.readBytes())!!
            assertEquals(KeySoundSynth.SURF_SAMPLE_RATE.toDouble(), rate, 0.0)
            assertEquals(KeySoundSynth.surfSamples().size, s.size)
            val stamp = f.lastModified()
            assertEquals(f, Feedback.surfFile(dir)); assertEquals(stamp, f.lastModified())
        } finally { dir.deleteRecursively() }
    }

    /** Gõ dồn ⇒ MỘT tiếng; nhịp đều qua nhiều chu kỳ sóng ⇒ đúng một tiếng mỗi sóng, sóng to (combo) ⇒ cỡ lớn. */
    @Test fun onlyNewWavesTriggerSurf() {
        val v = KeyEffectView(ctx, 3f)
        v.measure(View.MeasureSpec.makeMeasureSpec(1170, View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(780, View.MeasureSpec.EXACTLY))
        v.layout(0, 0, 1170, 780)
        v.configure(KeyEffect.SEA, 0xFF0EA5E9.toInt())
        val sizes = mutableListOf<Double>()
        v.onSeaWave = { sizes += it }
        repeat(30) { v.burst(300f, 400f, 100f, 120f); v.flush() }
        assertEquals("gõ dồn: một sóng, một tiếng", listOf(1.0), sizes)
        val half = Duration.ofMillis(((SeaFx.LAUNCH_GAP * 1000 + 20) / 2).toLong())
        repeat(5) {
            ShadowSystemClock.advanceBy(half)
            repeat(7) { v.burst(300f, 400f, 100f, 120f); v.flush() }
            ShadowSystemClock.advanceBy(half)
            v.burst(300f, 400f, 100f, 120f); v.flush()
        }
        assertEquals("mỗi con sóng mới đúng một tiếng", 6, sizes.size)
        assertEquals("gõ nhanh ⇒ sóng to ⇒ tiếng to hơn", 1.65, sizes.last(), 0.0)
        v.halt()
    }
}
