package com.viettelex.android.ime

import android.graphics.Bitmap
import android.graphics.Canvas
import android.os.SystemClock
import android.view.View
import androidx.test.core.app.ApplicationProvider
import com.viettelex.keyboard.KeyEffect
import com.viettelex.keyboard.KeyEffectPool
import com.viettelex.keyboard.ThemeFx
import com.viettelex.keyboard.ThemeParticles
import com.viettelex.keyboard.ThemeSpecParser
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.GraphicsMode

/**
 * Theme JSON phía View: hạt "Theo giao diện" (trần pool, gốc theo "origin" trong view) + từ khoá theme nổ THÊM cùng mọi
 * hiệu ứng (kể cả "Không"), 0 việc khi theme không có. iOS ThemeFxTests (phần overlay).
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class ThemeFxViewTest {
    private val ctx get() = ApplicationProvider.getApplicationContext<android.content.Context>()
    private val base = """{"v":1,"name":{"vi":"x"},"light":{"key":"#FFFFFF","special":"#DDDDDD","ink":"#000000","accent":"#000000"}"""
    private fun fx(extra: String): ThemeFx = ThemeFx.make(ThemeSpecParser.parse("$base,$extra}").spec)!!

    private fun view(e: KeyEffect, f: ThemeFx?): KeyEffectView {
        val v = KeyEffectView(ctx, 3f)
        v.configure(e, 0xFFFF2D55.toInt())
        v.setThemeFx(f)
        v.measure(View.MeasureSpec.makeMeasureSpec(1170, View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(780, View.MeasureSpec.EXACTLY))
        v.layout(0, 0, 1170, 780)
        return v
    }

    private fun drawnPixels(v: View): Int {
        val b = Bitmap.createBitmap(v.width, v.height, Bitmap.Config.ARGB_8888)
        v.draw(Canvas(b))
        val px = IntArray(v.width * v.height)
        b.getPixels(px, 0, v.width, 0, 0, v.width, v.height)
        b.recycle()
        return px.count { it != 0 }
    }

    @Test fun themeParticlesCappedAndOriginInsideView() {
        val v = view(KeyEffect.THEME, fx(""""particles":{"shape":"star","count":12,"origin":"bottom","size":20}"""))
        assertEquals("12 hạt/chùm ⇒ 1 chùm", 1, v.themeSlotCount)
        repeat(200) { i -> v.burst((i % 12) * 100f, 300f, 100f, 126f); if (i % 3 == 0) v.flush() }
        v.flush()
        val now = SystemClock.uptimeMillis()
        assertTrue(v.themeAlive(now) <= KeyEffectPool.CAP)
        assertEquals(12, v.themeAlive(now))
        val o = v.themeOrigin(0)
        assertEquals("gốc = mép dưới − nửa cỡ", 780f - 30f, o[1], 0.5f)
        assertTrue(o[0] in 0f..1170f)
        assertTrue(drawnPixels(v) > 50)
        // Không "particles" ⇒ chùm sao mặc định.
        val d = view(KeyEffect.THEME, null)
        assertEquals(ThemeParticles.slots(ThemeParticles.FALLBACK.effCount), d.themeSlotCount)
        d.burst(500f, 300f); d.flush()
        assertTrue(drawnPixels(d) > 50)
    }

    @Test fun keywordsFireWithAnyEffectAndZeroCostWhenAbsent() {
        val f = fx(""""keywords":[{"words":["yêu"],"burst":{"glyphs":["❤️"],"count":10,"spread":360},"text":"Yêu"},{"words":["phở"]}]""")
        val v = view(KeyEffect.NONE, f)
        assertTrue(v.wantsBoundaryWord)
        v.burst(100f, 100f); assertEquals("phím thường không hẹn vẽ gì", 0, v.pendingCount)
        v.queueThemeKeyword(99); assertNull(v.pendingThemeKeywordForTest)
        v.queueThemeKeyword(0); v.burst(100f, 300f, 100f, 126f); v.flush()
        assertEquals(0, v.keywordEntry(0))
        assertTrue(drawnPixels(v) > 50)
        // Hiệu ứng khác + từ khoá: cả hai.
        val h = view(KeyEffect.HEART, f)
        h.queueThemeKeyword(1); h.burst(100f, 300f, 100f, 126f); h.flush()
        assertEquals(1, h.keywordEntry(0))
        assertTrue(h.aliveCount() > 0)
        // Không có gì ⇒ không tra từ.
        assertFalse(view(KeyEffect.HEART, null).wantsBoundaryWord)
        assertFalse(view(KeyEffect.HEART, fx(""""particles":{}""")).wantsBoundaryWord)
    }
}
