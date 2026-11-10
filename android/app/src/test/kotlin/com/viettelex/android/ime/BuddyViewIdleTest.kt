package com.viettelex.android.ime

import android.graphics.Bitmap
import android.graphics.Canvas
import android.os.Looper
import android.view.View
import android.widget.FrameLayout
import androidx.test.core.app.ApplicationProvider
import com.viettelex.keyboard.BuddyCharacter
import com.viettelex.keyboard.BuddyIdleMotion
import com.viettelex.keyboard.BuddySeason
import com.viettelex.keyboard.BuddySprites
import com.viettelex.keyboard.BuddyStyle
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf

/**
 * Audit 10/11/2026 — Bạn đồng hành lúc NGHỈ phía View: không vẽ lại mãi (koi ngủ / Tết Thiếu nhi / Hoạt hình lắc nghỉ),
 * atlas 512 px giải ngoài main, cache một bản, nhả được khi ẩn lâu rồi nạp lại. = iOS KeyboardBuddyTests (cùng luật).
 */
@RunWith(RobolectricTestRunner::class)
class BuddyViewIdleTest {
    private val ctx get() = ApplicationProvider.getApplicationContext<android.content.Context>()
    private var now = 1000.0
    private val canvas = Canvas(Bitmap.createBitmap(300, 300, Bitmap.Config.ARGB_8888))

    @After fun tearDown() { BuddyView.SpriteAssets.drain(); BuddyView.SpriteAssets.drop() }

    private fun view(c: BuddyCharacter, season: BuddySeason? = null, style: BuddyStyle = BuddyStyle.VECTOR, low: Boolean = false): BuddyView {
        val v = BuddyView(ctx, c, 3f, 0xFFFFFF, low, season, artStyle = style)
        v.clock = { now }
        v.measure(View.MeasureSpec.makeMeasureSpec(300, View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(300, View.MeasureSpec.EXACTLY))
        v.layout(0, 0, 300, 300)
        v.appear()
        return v
    }

    /** Vẽ từng khung [step] giây tới [until]; trả số khung còn đòi vẽ tiếp (animating). */
    private fun run(v: BuddyView, until: Double, step: Double = 0.5): Int {
        var n = 0
        while (now < until) { v.draw(canvas); if (v.animating(now)) n++; now += step }
        return n
    }

    @Test fun koiAsleepBeforeFirstKeyDrawsNothingMore() {
        val v = view(BuddyCharacter.KOI)
        assertEquals("mở bàn phím, koi ngủ, chưa gõ ⇒ 0 khung hình", 0, run(v, now + 120))
    }

    @Test fun koiBubblesRunFewCyclesThenStop() {
        val v = view(BuddyCharacter.KOI)
        v.keyPressed()
        // Thức → lắc nghỉ → ngủ (SLEEP_AFTER 8,6 s) → bong bóng 8,8 s → yên.
        var sleptAt = Double.NaN
        while (now < 1060 && sleptAt.isNaN()) {
            v.draw(canvas)
            if (v.driver.shown is com.viettelex.keyboard.BuddyPhase.Asleep) sleptAt = now
            now += 0.1
        }
        assertFalse("đã ngủ", sleptAt.isNaN())
        now = sleptAt + 3.0; v.draw(canvas)
        assertTrue("đang bong bóng (sau phím đầu)", v.animating(now))
        now = sleptAt + BuddyIdleMotion.BUBBLE_SPAN + 0.2
        assertEquals("hết ${BuddyIdleMotion.BUBBLE_CYCLES} nhịp ⇒ không còn khung nào", 0, run(v, now + 120))
        // Hiện lại (chưa gõ) ⇒ vẫn yên dù ngủ.
        v.appear()
        assertEquals(0, run(v, now + 30))
    }

    @Test fun childrensDayBalloonBobsFewTimesThenStops() {
        val v = view(BuddyCharacter.CAT, BuddySeason.CHILDRENS_DAY)
        assertTrue("vừa hiện ⇒ nhún", v.animating(now + 0.5))
        assertFalse("hết ${BuddyIdleMotion.BALLOON_BOBS} nhịp", v.animating(now + BuddyIdleMotion.BALLOON_SPAN + 0.01))
        now += BuddyIdleMotion.BALLOON_SPAN + 0.1
        assertEquals("cả ngày 1/6 không vẽ lại mỗi 80 ms nữa", 0, run(v, now + 120))
        v.appear()
        assertTrue("hiện lại ⇒ nhún lại vài nhịp", v.animating(now + 0.5))
        assertFalse("tiết kiệm pin ⇒ yên", view(BuddyCharacter.CAT, BuddySeason.CHILDRENS_DAY, low = true).animating(now + 0.5))
    }

    @Test fun companionLoadsPrescaled512AtlasOffMainAndCachesOne() {
        BuddyView.SpriteAssets.drop()
        val v = view(BuddyCharacter.GIRL, style = BuddyStyle.SPRITE)
        assertTrue("chưa có cache ⇒ giải nền, ô trống (không lóe vector)", v.atlasPending)
        assertFalse("đang chờ ảnh: không vẽ lại liên tục", v.animating(now))
        BuddyView.SpriteAssets.drain()
        v.loadAtlasNow()
        val a = v.atlasBitmap!!
        assertEquals(512, a.width); assertEquals(341, a.height)
        println("Companion RAM: girl ${a.width}×${a.height} = ${a.allocationByteCount} B (trước: 1536 px lấy mẫu 4 = 384×256 = 393216 B, giải trọn PNG 1536 px)")
        assertSame("cache giữ đúng bản đó", a, BuddyView.SpriteAssets.cached(BuddyCharacter.GIRL))
        assertSame("view mới cùng nhân vật ⇒ có ảnh ngay", a, view(BuddyCharacter.GIRL, style = BuddyStyle.SPRITE).atlasBitmap)
        // Đổi nhân vật ⇒ thay bản cũ (một bản duy nhất).
        val catView = view(BuddyCharacter.CAT, style = BuddyStyle.SPRITE)
        BuddyView.SpriteAssets.drain()
        val cat = catView.also { it.loadAtlasNow() }.atlasBitmap!!
        assertEquals(512, cat.width); assertEquals(256, cat.height)
        assertNull(BuddyView.SpriteAssets.cached(BuddyCharacter.GIRL))
        assertEquals(cat.allocationByteCount, BuddyView.SpriteAssets.cachedBytes)
    }

    @Test fun asyncDecodeAttachesWithoutVectorFlash() {
        BuddyView.SpriteAssets.drop()
        val v = view(BuddyCharacter.BOY, style = BuddyStyle.SPRITE)
        assertTrue(v.atlasPending)
        assertFalse("chờ ảnh ⇒ không dựng điệu vector", v.driver.vectorDance)
        val end = System.currentTimeMillis() + 10_000
        while (v.atlasPending && System.currentTimeMillis() < end) { Thread.sleep(5); shadowOf(Looper.getMainLooper()).idle() }
        assertNotNull("giải xong trên luồng vt-buddy", v.atlasBitmap)
        assertFalse(v.driver.vectorDance)
    }

    @Test fun releaseAndRewarmAtlas() {
        val parent = FrameLayout(ctx)
        val v = view(BuddyCharacter.GIRL, style = BuddyStyle.SPRITE).also { parent.addView(it); it.loadAtlasNow() }
        BuddyView.SpriteAssets.drain(); shadowOf(Looper.getMainLooper()).idle()
        assertTrue(v.releaseAtlas())
        BuddyView.SpriteAssets.drop()
        assertNull(v.atlasBitmap); assertTrue(v.atlasPending)
        assertEquals("ẩn lâu ⇒ cache rỗng", 0, BuddyView.SpriteAssets.cachedBytes)
        assertFalse("đã nhả ⇒ không nhả lần hai", v.releaseAtlas())
        val jobs = ArrayList<Runnable>()
        v.rewarmAtlas { jobs += it }
        assertEquals("một việc trên vt-rewarm", 1, jobs.size)
        jobs.forEach { it.run() }
        shadowOf(Looper.getMainLooper()).idle()
        assertNotNull(v.atlasBitmap); assertFalse(v.atlasPending)
        assertTrue(BuddyView.SpriteAssets.cachedBytes > 0)
        assertFalse("Vẽ nét: không có atlas để nhả", view(BuddyCharacter.GIRL).releaseAtlas())
    }

    @Test fun spriteIdleRedrawsOncePerFrameNotEveryFiftyMs() {
        val v = view(BuddyCharacter.GIRL, style = BuddyStyle.SPRITE).also { it.loadAtlasNow() }
        v.keyPressed()
        v.draw(canvas)
        assertTrue("đang nhảy ⇒ khung hình liên tục", v.animating(now))
        // Tới lắc nghỉ (sau TAIL 0,6 s).
        while (v.driver.shown != com.viettelex.keyboard.BuddyPhase.Idle && now < 1010) { now += 0.05; v.draw(canvas) }
        if (v.driver.shown != com.viettelex.keyboard.BuddyPhase.Idle) return   // đêm: ngáp chen vào — bỏ qua
        val start = v.driver.phaseStart
        now = start + 0.1
        assertFalse("lắc nghỉ không vẽ mỗi 50 ms", v.animating(now))
        assertEquals("hẹn đúng mốc đổi khung (0,8 s/khung)", start + 0.8,
            v.spriteFrameAt(now)!!, 1e-9)
        assertEquals(BuddySprites.IDLE_DURATION / BuddySprites.IDLE.size, 0.8, 1e-9)
    }
}
