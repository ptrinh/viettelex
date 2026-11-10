package com.viettelex.android.ime

import android.os.Looper
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf

/**
 * Âm phím riêng (10/11/2026): SoundPool GIỮ qua các lần ẩn ([Feedback.onHidden] chỉ dừng tiếng đang
 * kêu) — hiện lại cùng kiểu ⇒ 0 lần nạp mẫu (trước: dựng lại pool + nạp 3–30 mẫu mỗi lần hiện, phím
 * đầu im). Nhả hẳn ([Feedback.releaseSound]) ở hẹn giờ ẩn / thiếu RAM (VietTelexIME.releaseIdle), đổi
 * kiểu, tắt âm.
 */
@RunWith(RobolectricTestRunner::class)
class FeedbackPoolLifecycleTest {
    private val ctx get() = ApplicationProvider.getApplicationContext<android.content.Context>()
    private val sync: (Runnable) -> Unit = { it.run() }
    private fun drain() = shadowOf(Looper.getMainLooper()).idle()

    private fun show(f: Feedback, style: String, enabled: Boolean = true) {
        f.configureSound(enabled, 50, style, sync); drain()
    }

    @Test fun hideThenShowSameStyleReusesPool() {
        for (style in listOf("wood", "piano")) {
            val f = Feedback(ctx)
            show(f, style)
            assertTrue(f.hasPool)
            val loads = f.sampleLoads
            assertTrue("$style: nạp mẫu lần đầu ($loads)", loads >= 3)
            repeat(5) {
                f.onHidden()                         // ẩn bàn phím
                assertTrue("$style: ẩn vẫn giữ pool", f.hasPool)
                show(f, style)                       // hiện lại
            }
            assertEquals("$style: một pool duy nhất", 1, f.poolBuilds)
            assertEquals("$style: hiện lại không nạp mẫu nào", loads, f.sampleLoads)
            f.releaseSound()
        }
    }

    /** Hẹn giờ ẩn / onTrimMemory / onLowMemory gọi releaseIdle ⇒ releaseSound: nhả, hiện sau dựng lại. */
    @Test fun idleOrTrimReleaseFreesPool() {
        val f = Feedback(ctx)
        show(f, "wood")
        f.onHidden()
        f.releaseSound()
        assertFalse(f.hasPool)
        show(f, "wood")
        assertTrue(f.hasPool)
        assertEquals(2, f.poolBuilds)
        f.releaseSound()
    }

    @Test fun styleChangeOrSoundOffReleasesImmediately() {
        val f = Feedback(ctx)
        show(f, "wood")
        val first = f.sampleLoads
        show(f, "subtle")
        assertEquals("đổi kiểu ⇒ pool mới", 2, f.poolBuilds)
        assertTrue(f.sampleLoads > first)
        show(f, "subtle", enabled = false)
        assertFalse("tắt âm ⇒ nhả ngay", f.hasPool)
        show(f, "subtle")
        show(f, "system")
        assertFalse("kiểu Hệ thống ⇒ không pool", f.hasPool)
    }
}
