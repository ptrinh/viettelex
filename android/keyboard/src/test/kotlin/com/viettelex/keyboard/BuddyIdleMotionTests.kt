package com.viettelex.keyboard

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Audit 10/11/2026 (RAM/CPU nghỉ): bong bóng koi và bóng bay Tết Thiếu nhi từng vẽ lại mãi (6–12 khung/giây) suốt lúc
 * bàn phím mở mà không gõ; Hoạt hình lắc nghỉ vẽ lại mỗi 50–80 ms dù khung chỉ đổi mỗi 0,8 s. = iOS
 * testKoiBubblesFiniteAndNotBeforeFirstKey / testChildrensDayBalloonBobIsFinite (cùng số).
 */
class BuddyIdleMotionTests {
    @Test fun koiBubblesOnlyAfterFirstKeyWhileAsleep() {
        assertTrue(BuddyIdleMotion.bubbles(BuddyCharacter.KOI, asleep = true, lowPower = false, typedSinceShown = true))
        assertFalse("mở bàn phím, chưa gõ ⇒ koi ngủ yên", BuddyIdleMotion.bubbles(BuddyCharacter.KOI, true, false, false))
        assertFalse(BuddyIdleMotion.bubbles(BuddyCharacter.KOI, asleep = false, lowPower = false, typedSinceShown = true))
        assertFalse(BuddyIdleMotion.bubbles(BuddyCharacter.KOI, asleep = true, lowPower = true, typedSinceShown = true))
        for (c in BuddyCharacter.entries.filter { it != BuddyCharacter.KOI })
            assertFalse(c.id, BuddyIdleMotion.bubbles(c, true, false, true))
    }

    @Test fun koiBubblesAreFinite() {
        // Cùng số iOS: 3 bong bóng, mỗi cái 3 nhịp × 2,4 s, lệch 0,8 s ⇒ tan hết sau 8,8 s.
        assertEquals(8.8, BuddyIdleMotion.BUBBLE_SPAN, 1e-9)
        assertTrue(BuddyIdleMotion.bubblesMoving(0.0))
        assertTrue(BuddyIdleMotion.bubblesMoving(8.79))
        assertFalse(BuddyIdleMotion.bubblesMoving(8.8))
        assertFalse(BuddyIdleMotion.bubblesMoving(3600.0))
        assertFalse("trước lúc ngủ", BuddyIdleMotion.bubblesMoving(-0.1))
        assertEquals(0.0, BuddyIdleMotion.bubblePhase(0.0, 0)!!, 1e-9)
        assertEquals(0.5, BuddyIdleMotion.bubblePhase(1.2, 0)!!, 1e-9)
        assertNull("bong bóng 3 chưa tới lượt", BuddyIdleMotion.bubblePhase(1.0, 2))
        assertNotNull(BuddyIdleMotion.bubblePhase(1.7, 2))
        assertNull("bong bóng 1 hết 3 nhịp", BuddyIdleMotion.bubblePhase(7.2, 0))
        var t = 0.0
        var visible = 0
        while (t < 60.0) {
            for (i in 0 until BuddyIdleMotion.BUBBLES) {
                val p = BuddyIdleMotion.bubblePhase(t, i)
                if (p != null) { visible++; assertTrue(p in 0.0..1.0); assertTrue("$t", BuddyIdleMotion.bubblesMoving(t)) }
                if (t >= BuddyIdleMotion.BUBBLE_SPAN) assertNull("$t hết nhịp ⇒ không vẽ", p)
            }
            t += 0.05
        }
        assertTrue(visible > 0)
    }

    @Test fun childrensDayBalloonBobIsFinite() {
        assertEquals(6.0, BuddyIdleMotion.BALLOON_SPAN, 1e-9)
        assertTrue(BuddyIdleMotion.balloonMoving(0.0))
        assertTrue(BuddyIdleMotion.balloonMoving(5.99))
        assertFalse(BuddyIdleMotion.balloonMoving(6.0))
        assertFalse(BuddyIdleMotion.balloonMoving(-1.0))
        assertEquals(1.0, BuddyIdleMotion.balloonBob(0.5), 1e-9)       // = sin(t·π) cũ, chu kỳ 2 s
        assertEquals(0.0, BuddyIdleMotion.balloonBob(6.0), 1e-9)
        assertEquals(0.0, BuddyIdleMotion.balloonBob(1000.0), 1e-9)
        assertEquals("dừng liền mạch (không giật)", 0.0, BuddyIdleMotion.balloonBob(5.9999), 1e-3)
    }

    @Test fun spriteNextInvalidateIsNextFrameBoundary() {
        // Lắc nghỉ: 2 khung trong 1,6 s ⇒ mỗi khung 0,8 s.
        assertEquals(0.7, BuddySprites.nextFrameDelay(0.1, BuddySprites.IDLE_DURATION, BuddySprites.IDLE.size), 1e-9)
        assertEquals("đúng mốc ⇒ cả một khung", 0.8, BuddySprites.nextFrameDelay(0.8, 1.6, 2), 1e-9)
        assertEquals(0.6, BuddySprites.nextFrameDelay(1.0, 1.6, 2), 1e-9)
        assertEquals(0.7, BuddySprites.nextFrameDelay(2.5, 1.6, 2), 1e-9)
        assertEquals(Double.POSITIVE_INFINITY, BuddySprites.nextFrameDelay(1.0, 1.6, 0), 0.0)
        // Thuộc tính: khung không đổi trong [e, e + delay) và đổi ngay sau mốc.
        val rnd = java.util.Random(7)
        repeat(2000) {
            val e = rnd.nextDouble() * 20
            for ((dur, n) in listOf(BuddySprites.IDLE_DURATION to BuddySprites.IDLE.size, BuddyBrain.CHEER to BuddySprites.CHEER.size)) {
                val d = BuddySprites.nextFrameDelay(e, dur, n)
                assertTrue(d >= 0 && d <= dur / n + 1e-9)
                val now = BuddySprites.frameIndex(e / dur, n)
                assertEquals("e=$e", now, BuddySprites.frameIndex((e + d * 0.999) / dur, n))
                assertEquals("e=$e", (now + 1) % n, BuddySprites.frameIndex((e + d + 1e-6) / dur, n))
            }
        }
    }

    @Test fun companionUsesPrescaled512Atlas() {
        assertEquals("buddy-cat-v2-512.png", BuddySprites.atlasAsset(BuddyCharacter.CAT))
        assertEquals("buddy-girl-v2-512.png", BuddySprites.atlasAsset(BuddyCharacter.GIRL))
        assertEquals("bản 512 giải thẳng (không lấy mẫu)", 1, BuddySprites.sampleSize(512, 341))
        assertEquals(1, BuddySprites.sampleSize(512, 256))
    }
}
