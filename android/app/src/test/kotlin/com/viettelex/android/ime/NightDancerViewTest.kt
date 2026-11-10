package com.viettelex.android.ime

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Matrix
import android.view.View
import androidx.test.core.app.ApplicationProvider
import com.viettelex.keyboard.BuddyCharacter
import com.viettelex.keyboard.NightDancer
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * Người nhảy hoạt hình (theme Neon Night Club, không ảnh nền) phía View: atlas Bạn đồng hành giải theo cỡ hiển thị,
 * mỗi lần đèn nháy đổi biến thể (không lặp liền), khung vẽ trong bàn phím, có ảnh nền ⇒ không giữ atlas. = iOS NightClubTests.
 */
@RunWith(RobolectricTestRunner::class)
class NightDancerViewTest {
    private val ctx get() = ApplicationProvider.getApplicationContext<android.content.Context>()

    private fun sized(v: SpotlightView, w: Int, h: Int): SpotlightView {
        v.measure(View.MeasureSpec.makeMeasureSpec(w, View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(h, View.MeasureSpec.EXACTLY))
        v.layout(0, 0, w, h)
        return v
    }

    @Test fun dancerAtlasVariantsAndFrame() {
        val v = sized(SpotlightView(ctx, 3f), 1080, 780)
        v.loadAtlasNow()
        val atlas = v.dancerAtlas
        assertNotNull("giải được atlas cô gái", atlas)
        // 780 px cao × 0,85 = 663 px mỗi ô (221 dp @3x) ⇒ trần @2x: cạnh dài 1326 (= iOS), không trọn 1536.
        assertEquals(1326, maxOf(atlas!!.width, atlas.height))
        assertEquals(884, minOf(atlas.width, atlas.height))
        println("NightDancer RAM: ${atlas.width}×${atlas.height} = ${atlas.allocationByteCount} B (trước: 1536×1024 = 6291456 B)")
        assertTrue("≤ ~4,7 MB (trước 6,3 MB)", atlas.allocationByteCount <= 4_688_736)
        var prev = v.variant
        for (i in 0 until 30) {
            v.light(540f, 400f, 96f); v.flush()
            assertNotEquals("không lặp liền", prev, v.variant)
            prev = v.variant
        }
        v.draw(Canvas(Bitmap.createBitmap(1080, 780, Bitmap.Config.ARGB_8888)))
        val r = v.dancerRect
        assertEquals(663f, r.height(), 1f)
        assertTrue("trong bàn phím", r.left >= 0f && r.right <= 1080f && r.top >= 0f && r.bottom <= 780.5f)
        v.halt()
    }

    @Test fun photoMeansNoDancerAndNoAtlas() {
        val v = sized(SpotlightView(ctx, 3f), 1080, 780)
        v.loadAtlasNow()
        assertNotNull(v.dancerAtlas)
        v.setPhoto(Bitmap.createBitmap(10, 10, Bitmap.Config.ARGB_8888), Matrix())
        assertNull("có ảnh nền ⇒ thả atlas", v.dancerAtlas)
        v.loadAtlasNow()
        assertNull("có ảnh nền ⇒ không giải", v.dancerAtlas)
        val before = v.variant
        v.light(540f, 400f, 96f); v.flush()
        assertEquals("có ảnh nền ⇒ không đổi biến thể", before, v.variant)
        v.halt()
    }

    /**
     * Audit 10/11/2026: hẹn giờ ẩn (ImeRootView.dropWallpaper) từng gọi setPhoto(null) ⇒ GIẢI người nhảy ~6 MB đúng lúc
     * bàn phím ẩn (và lúc onDestroy). Nay release() bỏ atlas, không giải; đổi cỡ lúc ẩn cũng không giải; resume() (vt-rewarm)
     * giải lại trên luồng được giao.
     */
    @Test fun releaseFreesWithoutDecodingAndResumeReloads() {
        val v = sized(SpotlightView(ctx, 3f), 1080, 780)
        v.loadAtlasNow()
        assertNotNull(v.dancerAtlas)
        v.release()
        assertNull("nhả atlas", v.dancerAtlas)
        assertFalse("không bắt đầu giải lại", v.dancerLoading)
        sized(v, 1080, 760)                                   // onSizeChanged lúc ẩn
        assertFalse("đổi cỡ lúc ẩn không giải", v.dancerLoading)
        val jobs = ArrayList<Runnable>()
        v.resume { jobs += it }
        assertTrue(v.dancerLoading)
        assertEquals("một việc giải trên luồng được giao (vt-rewarm)", 1, jobs.size)
        jobs.forEach { it.run() }
        org.robolectric.Shadows.shadowOf(android.os.Looper.getMainLooper()).idle()
        assertNotNull("hiện lại ⇒ có người nhảy", v.dancerAtlas)
        v.resume { error("đã chạy — không giải lần hai") }
    }

    /** Có ảnh nền thì sau release, setPhoto(ảnh) đánh thức mà không giải người nhảy. */
    @Test fun releaseThenPhotoNeverDecodesDancer() {
        val v = sized(SpotlightView(ctx, 3f), 1080, 780)
        v.release()
        v.setPhoto(Bitmap.createBitmap(10, 10, Bitmap.Config.ARGB_8888), Matrix())
        assertFalse(v.dancerLoading); assertNull(v.dancerAtlas)
    }

    @Test fun boyWhenChosenElseGirl() {
        val v = sized(SpotlightView(ctx, 3f), 1080, 780)
        v.dancer = NightDancer.character(BuddyCharacter.BOY)
        assertEquals(BuddyCharacter.BOY, v.dancer)
        v.loadAtlasNow()
        assertNotNull("giải được atlas chàng trai", v.dancerAtlas)
        v.dancer = NightDancer.character(BuddyCharacter.CAT)
        assertEquals(BuddyCharacter.GIRL, v.dancer)
        assertNull("đổi nhân vật ⇒ thả atlas cũ", v.dancerAtlas)
    }
}
