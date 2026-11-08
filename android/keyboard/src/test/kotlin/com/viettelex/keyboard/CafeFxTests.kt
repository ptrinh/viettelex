package com.viettelex.keyboard

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs
import kotlin.math.hypot

/**
 * Theme Cà phê sữa đá: viên đá lắc, giọt nước đọng, phin nhỏ giọt, sữa xoáy, cảnh ly, âm "clink". Số tham chiếu CHUNG iOS
 * (iOS/KeyboardTests/CafeFxTests.swift) — đổi một bên phải đổi cả hai.
 */
class CafeFxTests {

    @Test fun iceJiggleAndDroplet() {
        assertEquals(0.0, CafeFx.jiggle(0.0), 0.0)
        assertEquals(0.048000, CafeFx.jiggle(0.05), 1e-6)
        assertEquals(0.009992, CafeFx.jiggle(0.2), 1e-6)
        assertEquals("đứng yên sau 0,4 s", 0.0, CafeFx.jiggle(0.4), 0.0)
        for (i in 0..40) assertTrue(abs(CafeFx.jiggle(i / 100.0)) <= CafeFx.JIGGLE_AMP)
        assertEquals(0.45, CafeFx.cubeAlpha(0.2), 1e-12)
        val d = CafeFx.droplet(0.3)
        assertEquals(3.0, d.first, 1e-12); assertEquals(0.45, d.second, 1e-12)
        assertEquals(0.0, CafeFx.droplet(0.6).second, 0.0)
        val o = CafeFx.dropletOrigin(100.0, 50.0)
        assertEquals(94.0, o.first, 0.0); assertEquals(47.0, o.second, 0.0)
    }

    @Test fun dripTiming() {
        val c = CafeFx.DripCounter()
        assertEquals(listOf(false, false, false, true, false, false, false, true, false, false, false, true), (0 until 12).map { c.press() })
        c.reset(); assertEquals(0, c.n)
        assertEquals(2.0, CafeFx.dropY(0.15), 1e-12)
        assertEquals(CafeFx.DROP_FALL, CafeFx.dropY(1.0), 0.0)
        val b = CafeFx.phinBox(0.0, 0.0)
        assertEquals(listOf(8.0, 3.0, 16.0, 29.0), b.toList())
        // Phin nằm gọn trong thanh gợi ý (cao ≥ 36) kể cả khi gốc dời.
        val s = CafeFx.phinBox(0.0, 40.0)
        assertTrue(s[1] >= 40); assertTrue(s[1] + s[3] <= 40 + 36)
    }

    @Test fun swirlGateAndSpiral() {
        val g = CafeFx.SwirlGate()
        assertFalse(g.shouldSwirl(1, 0, 0.0))
        assertTrue(g.shouldSwirl(2, 1, 1.0))
        assertFalse("chỉ lúc VỪA lên mức 2", g.shouldSwirl(3, 2, 1.5))
        assertFalse("hồi 2,5 s", g.shouldSwirl(2, 1, 3.4))
        assertTrue(g.shouldSwirl(2, 0, 3.5))
        val sp = CafeFx.spiral()
        assertEquals(41, sp.size)
        assertEquals(0.0, sp[0].first, 0.0); assertEquals(0.0, sp[0].second, 0.0)
        assertEquals(0.0, sp[40].first, 1e-9); assertEquals(-22.0, sp[40].second, 1e-9)
        for (p in sp) assertTrue(hypot(p.first, p.second) <= CafeFx.SWIRL_RADIUS + 1e-9)
        val c = CafeFx.swirlCenter(195.0, 260.0)
        assertEquals(195.0, c.first, 0.0); assertEquals(232.0, c.second, 0.0)
        assertTrue("xoáy trong bàn phím", c.second + CafeFx.SWIRL_RADIUS + CafeFx.SWIRL_WIDTH <= 260)
        assertEquals(0.425, CafeFx.swirlAlpha(1.0), 1e-9)
        assertEquals(0.85, CafeFx.swirlAlpha(0.5), 0.0)
    }

    @Test fun cafeScene() {
        assertTrue(ThemeScene.isScene(ThemeDecoration.CAFE))
        assertEquals(listOf(0xEAD7B8, 0xC9A27E, 0x6B4430), ThemeScene.gradient(ThemeDecoration.CAFE, false).toList())
        assertEquals(listOf(0x1A0F09, 0x3A271C, 0x4A3426), ThemeScene.gradient(ThemeDecoration.CAFE, true).toList())
        val dots = CafeScene.dots(390.0, 260.0)
        assertEquals(24, dots.size)
        assertEquals(219.95663, dots[0][0], 1e-4); assertEquals(103.28112, dots[0][1], 1e-4)
        assertEquals(7238.7733, dots.sumOf { it[0] + it[1] + it[2] }, 1e-2)
        for (d in dots) assertTrue(d[0] - d[2] >= 0 && d[0] + d[2] <= 390 && d[1] - d[2] >= 0 && d[1] + d[2] <= 260)
    }

    @Test fun clinkSound() {
        assertTrue(KeySoundStyle.CLINK in KeySoundStyle.PRESETS)
        assertEquals(0x636C696E xor 0x85EBCA6B.toInt(), KeySoundSynth.seed(KeySoundStyle.CLINK, KeySoundSynth.Kind.LETTER))
        val golden = listOf(KeySoundSynth.Kind.LETTER to 102.6325, KeySoundSynth.Kind.DELETE to 114.7269, KeySoundSynth.Kind.MODIFIER to 124.6305)
        for ((k, want) in golden) {
            assertEquals("$k", want, KeySoundSynth.samples(KeySoundStyle.CLINK, k).sumOf { abs(it.toDouble()) }, 0.01)
        }
        val c = KeySoundSynth.samples(KeySoundStyle.CLINK, KeySoundSynth.Kind.LETTER)
        val wood = KeySoundSynth.samples(KeySoundStyle.WOOD, KeySoundSynth.Kind.LETTER)
        assertTrue(c.maxOf { abs(it) } < wood.maxOf { abs(it) })
        assertEquals("Ice clink", L10nTable.EN["Đá lanh canh"])
    }

    @Test fun cafeTheme() {
        val t = KeyboardTheme.CAFE
        val spec = t.spec
        assertNotNull(spec)
        assertTrue(t.isPlus); assertTrue(t.isInteractive)
        assertEquals("Cà phê sữa đá", spec!!.nameVi); assertEquals("Iced Coffee", spec.nameEn)
        assertEquals("Iced Coffee", L10nTable.EN[t.viTitle])
        assertEquals("clink", spec.sound); assertEquals("ice", spec.effect)
        assertTrue(ThemeSpecParser.contrastIssues(spec).isEmpty())
        assertEquals(listOf("football", "aquarium", "cafe"), ThemePicker.INTERACTIVE_ORDER.let { o -> val i = o.indexOf("football"); o.subList(i, minOf(i + 3, o.size)) })
        assertEquals(KeyEffectBand.ABOVE_KEYS, KeyEffect.ICE.band)
        assertTrue(KeyEffect.ICE in ThemeFxFactory.EFFECTS)
        for (dark in listOf(false, true)) {
            val p = t.palette(dark)!!
            assertEquals(ThemeDecoration.CAFE, p.decoration?.motif)
            // Phím đá trong mờ: chữ ≥ 4.5 trên mọi điểm gradient cà phê → sữa.
            for (s in ThemeScene.gradient(ThemeDecoration.CAFE, dark)) {
                val stop = ThemeColor.rgb(s)
                assertTrue("$dark ${Integer.toHexString(s)}", ThemeColor.contrast(p.ink, ThemeColor.over(p.keyFill, stop)) >= 4.5)
                assertTrue(ThemeColor.contrast(p.fnInk, ThemeColor.over(p.fnFill, stop)) >= 4.5)
            }
            assertTrue(ThemeColor.contrast(p.actionInk, ThemeColor.over(p.action, p.bg)) >= 4.5)
        }
    }
}
