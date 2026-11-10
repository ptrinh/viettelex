package com.viettelex.keyboard

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Theme Neon Night Club — Đèn rọi, quả cầu disco, Sàn nhảy LED, người nhảy hoạt hình (NightDancer). Số CHUNG iOS NightClubTests.swift. */
class SpotlightTests {
    @Test fun spotlightRadiusAlphaScale() {
        assertEquals(129.2, SpotlightFx.radius(34.0, 0), 1e-9)
        assertEquals(164.9, SpotlightFx.radius(34.0, 3), 1e-9)
        assertEquals(72.0, SpotlightFx.radius(10.0, 0), 0.0)
        assertEquals(210.0, SpotlightFx.radius(100.0, 3), 0.0)
        // Chớp đèn sân khấu: ≥ 3,5 bề rộng phím; 3 quầng mức cao nhất phủ hết bề rộng bàn phím 402.
        assertTrue(SpotlightFx.radius(34.0, 0) >= 3.5 * 34)
        assertTrue(3 * 2 * SpotlightFx.radius(34.0, 3) >= 402)
        assertEquals(1.11, SpotlightFx.duration(0), 1e-12)
        assertEquals(1.29, SpotlightFx.duration(3), 1e-12)
        assertEquals(1.29, SpotlightFx.duration(9), 1e-12)
        assertEquals(0.88, SpotlightFx.peak(0), 1e-12)
        assertEquals(1.0, SpotlightFx.peak(3), 1e-12)
        assertEquals(0.0, SpotlightFx.alpha(-0.01, 0), 0.0)
        assertEquals(0.44, SpotlightFx.alpha(0.03, 0), 1e-12)
        assertEquals(0.88, SpotlightFx.alpha(0.06, 0), 1e-12)
        assertEquals(0.88, SpotlightFx.alpha(0.2, 0), 1e-12)
        assertEquals(0.22, SpotlightFx.alpha(0.66, 0), 1e-12)
        assertEquals(0.0, SpotlightFx.alpha(1.11, 0), 0.0)
        assertEquals(0.006944444444444469, SpotlightFx.alpha(1.2, 3), 1e-12)
        assertEquals(0.8, SpotlightFx.scale(0.0, 0), 1e-12)
        assertEquals(1.025, SpotlightFx.scale(0.555, 0), 1e-12)
        assertEquals(1.1, SpotlightFx.scale(5.0, 0), 1e-12)
        assertEquals(listOf(0xFF2FD0, 0x9B5CFF, 0x2FE6FF, 0xFF2FD0), (0 until 4).map { SpotlightFx.color(it) })
        for (lv in 0..3) {
            assertTrue(SpotlightFx.duration(lv) in 1.0..1.4)
            val fade = SpotlightFx.duration(lv) - SpotlightFx.ATTACK - SpotlightFx.HOLD
            assertTrue("tắt 0,9–1,1 s", fade in 0.9 - 1e-9..1.1)
        }
    }

    /** Hình quầng: lõi lộ ảnh 100 %, quầng 50–70 %; tô lõi gần trắng, vành sáng mờ ở rìa. = iOS testSpotlightProfile. */
    @Test fun spotlightProfile() {
        assertEquals(SpotlightFx.MASK_STOPS.size, SpotlightFx.MASK_LEVELS.size)
        assertEquals(SpotlightFx.GLOW_STOPS.size, SpotlightFx.GLOW_ALPHA.size)
        assertEquals(SpotlightFx.GLOW_STOPS.size, SpotlightFx.GLOW_WHITE.size)
        assertEquals(1.0, SpotlightFx.MASK_LEVELS[1], 0.0)
        assertTrue(SpotlightFx.MASK_LEVELS[2] in 0.5..0.7)
        assertEquals(0.0, SpotlightFx.MASK_LEVELS.last(), 0.0)
        for (i in 1 until SpotlightFx.MASK_STOPS.size) assertTrue(SpotlightFx.MASK_STOPS[i] > SpotlightFx.MASK_STOPS[i - 1])
        for (i in 1 until SpotlightFx.GLOW_STOPS.size) assertTrue(SpotlightFx.GLOW_STOPS[i] > SpotlightFx.GLOW_STOPS[i - 1])
        assertTrue("vành sáng mờ: bướu ở rìa", SpotlightFx.GLOW_ALPHA[4] > SpotlightFx.GLOW_ALPHA[3])
        assertEquals(0xD9FFACEC.toInt(), SpotlightFx.glowColor(0xFF2FD0, 0))
        assertEquals(0xB8B485FF.toInt(), SpotlightFx.glowColor(0x9B5CFF, 1))
        assertEquals(0x572FE6FF, SpotlightFx.glowColor(0x2FE6FF, 2))
        assertEquals(0x00FF2FD0, SpotlightFx.glowColor(0xFF2FD0, 5))
    }

    @Test fun spotlightLightsCap() {
        val l = SpotlightLights()
        assertEquals(0, l.live(0.0))
        assertEquals(Double.NEGATIVE_INFINITY, l.lastEnd, 0.0)
        for (k in 0 until 7) l.press(k * 0.1, 0)
        assertEquals(7, l.presses)
        assertEquals(1, l.cursor)
        assertEquals(0.6, l.starts[0], 1e-12)
        assertEquals(SpotlightFx.CAP, l.live(0.65))
        assertEquals(1.71, l.lastEnd, 1e-12)
        assertEquals(3, l.live(1.5))
        assertEquals(0, l.live(1.8))
        l.reset()
        assertEquals(0, l.live(0.65))
    }

    @Test fun discoBall() {
        val c = DiscoBall.center(0.0, 0.0, 400.0)
        assertEquals(386.0, c[0], 1e-12); assertEquals(13.0, c[1], 1e-12)
        val d = DiscoBall.direction(0, 0)
        assertEquals(-0.15643446504023104, d[0], 1e-12); assertEquals(0.9876883405951377, d[1], 1e-12)
        for (p in 0 until 6) for (i in 0 until DiscoBall.DOTS_PER_PRESS) {
            val v = DiscoBall.direction(p, i); assertTrue(v[0] < 0.01); assertTrue(v[1] >= -0.1)
        }
        assertEquals(0.25, DiscoBall.dotAlpha(0.225), 1e-12)
        assertEquals(0.0, DiscoBall.dotAlpha(0.45), 0.0)
        assertEquals(22.5, DiscoBall.dotTravel(0.225), 1e-12)
        assertEquals(30.0, DiscoBall.dotTravel(9.0), 1e-12)
    }

    @Test fun danceFloorTiming() {
        assertEquals(0.55, DanceFloor.alpha(0.0, 0), 1e-12)
        assertEquals(0.0, DanceFloor.alpha(0.05, 1), 0.0)
        assertEquals(0.55, DanceFloor.alpha(0.06, 1), 1e-12)
        assertEquals(0.1375, DanceFloor.alpha(0.13, 0), 1e-12)
        assertEquals(0.0, DanceFloor.alpha(0.26, 0), 0.0)
        assertEquals(0.38, DanceFloor.LIFETIME, 1e-12)
        assertEquals(0.22, DanceFloor.flickerAlpha(0.03), 1e-12)
        assertEquals(0.0, DanceFloor.flickerAlpha(0.08), 0.0)
        assertEquals(0.11, DanceFloor.flickerAlpha(0.15), 1e-12)
        assertEquals(0.0, DanceFloor.flickerAlpha(0.2), 0.0)
        val g = DanceFloor.FlickerGate()
        assertFalse(g.trigger(2, 0.0))
        assertTrue(g.trigger(3, 1.0))
        assertFalse(g.trigger(3, 2.1))
        assertTrue(g.trigger(3, 2.2))
        assertEquals(2, g.fired)
    }

    @Test fun danceFloorTiles() {
        val t = DanceFloor.tiles(100.0, 50.0, 30.0, 40.0, 0)
        assertEquals(25, t.size)
        assertEquals(listOf(1, 8, 16), (0 until 3).map { r -> t.count { it.ring == r } })
        assertEquals(DanceFloor.Tile(0, 0, 100.0, 50.0, 30.0, 40.0), t[12])
        assertEquals(135.4, t[13].x, 1e-9)
        assertEquals(50 - 51.2, t[7].y, 1e-9)
        assertEquals(1, DanceFloor.colorIndex(1, -1, 2))
        val sp = DanceFloor.tiles(100.0, 50.0, 200.0, 40.0, 2)
        assertEquals(223.12, sp[13].x, 1e-9)
        assertEquals(34.0, sp[13].w, 1e-9)
        assertEquals(6075.88, sp.sumOf { it.x * (it.color + 1) + it.w }, 1e-6)
        val grid = DanceFloor.grid(0.0, 0.0, 400.0, 300.0, 100.0, 50.0, 30.0, 40.0, 0)
        assertEquals(55, grid.size)
        assertTrue(grid.all { it.x in 0.0..400.0 && it.y in 0.0..300.0 })
        assertTrue(DanceFloor.grid(0.0, 0.0, 4000.0, 3000.0, 0.0, 0.0, 30.0, 40.0, 0).size <= DanceFloor.MAX_GRID)
    }

    /** Người nhảy hoạt hình: biến thể (khung × lật) tất định, không lặp liền, đủ 14 biến thể. = iOS testDancerVariants. */
    @Test fun dancerVariants() {
        assertEquals(listOf(0, 1, 0, 1, 2, 3, 4, 5, 6), NightDancer.SEQUENCE.toList())
        assertEquals(14, NightDancer.VARIANTS)
        assertEquals(3, NightDancer.frame(3)); assertFalse(NightDancer.mirrored(3))
        assertEquals(3, NightDancer.frame(10)); assertTrue(NightDancer.mirrored(10))
        val golden = listOf(1, 7, 1, 9, 3, 4, 5, 4, 7, 8, 0, 8, 2, 3, 4, 12, 13, 0, 12, 0, 1, 2, 3, 11, 12, 6, 11, 1, 0, 1, 9,
            10, 3, 12, 6, 0, 1, 6, 8, 9)
        var p = -1
        val seq = (1..400).map { n -> NightDancer.next(p, n).also { p = it } }
        assertEquals(golden, seq.take(40))
        assertTrue(seq.all { it in 0 until NightDancer.VARIANTS })
        for (i in 1 until seq.size) assertNotEquals("lần $i", seq[i - 1], seq[i])
        assertEquals("đủ 14 biến thể trong 40 lần nháy", 14, seq.take(40).toSet().size)
        val mirrors = seq.count { NightDancer.mirrored(it) }
        val twice = (1 until seq.size).count { NightDancer.mirrored(seq[it]) && NightDancer.mirrored(seq[it - 1]) }
        assertTrue("lật ~1/3 số lần", mirrors in 100..200)
        assertTrue("lật hai lần liền ít hơn hẳn", twice * 2 < mirrors)
        assertTrue("theo chuỗi nhảy là chính",
            seq.withIndex().count { (i, v) -> NightDancer.frame(v) == NightDancer.SEQUENCE[(i + 1) % 9] } > 240)
        // Không trùng biến thể trước kể cả khi chuỗi rơi đúng nó.
        for (n in 1..200) for (prev in 0 until NightDancer.VARIANTS) assertNotEquals(prev, NightDancer.next(prev, n))
    }

    @Test fun dancerCharacterCellsAndDecodeSize() {
        assertEquals(BuddyCharacter.GIRL, NightDancer.character(BuddyCharacter.OFF))
        assertEquals(BuddyCharacter.GIRL, NightDancer.character(BuddyCharacter.GIRL))
        assertEquals(BuddyCharacter.BOY, NightDancer.character(BuddyCharacter.BOY))
        for (c in listOf(BuddyCharacter.CAT, BuddyCharacter.CHICK, BuddyCharacter.AI)) assertEquals(BuddyCharacter.GIRL, NightDancer.character(c))
        assertEquals(listOf(0.0, 0.0, 0.25, 0.5), NightDancer.cell(0).toList())
        assertEquals(listOf(0.75, 0.0, 0.25, 0.5), NightDancer.cell(3).toList())
        assertEquals(listOf(0.5, 0.5, 0.25, 0.5), NightDancer.cell(6).toList())
        // Khung vẽ: cao 85 %, đứng đáy, giữa ngang, trong bàn phím.
        val r = NightDancer.rect(400.0, 260.0, 0.75)
        assertEquals(221.0, r[3], 1e-9); assertEquals(165.75, r[2], 1e-9)
        assertEquals(117.125, r[0], 1e-9); assertEquals(39.0, r[1], 1e-9)
        assertTrue(r[0] >= 0 && r[0] + r[2] <= 400 && r[1] >= 0 && r[1] + r[3] <= 260)
        // Cỡ giải theo cỡ hiển thị (atlas 1536 × 1024), trần @2x; cỡ nhỏ thì nhỏ nữa; trần 2048.
        // Audit 10/11/2026: @3x từng giải trọn 1536 px (6,3 MB) để hiện một ô ⇒ nay trần @2x (= iOS NightClubTests).
        assertEquals(1326, NightDancer.decodeLongEdge(221.0, 3.0, 1536, 1024))
        assertEquals("cao hơn ⇒ tới cỡ gốc", 1536, NightDancer.decodeLongEdge(300.0, 3.0, 1536, 1024))
        assertEquals(663, NightDancer.decodeLongEdge(221.0, 1.0, 1536, 1024))
        assertEquals(1326, NightDancer.decodeLongEdge(221.0, 2.0, 1536, 1024))
        assertEquals("@2,625 (420 dpi) ⇒ cũng @2x", 1326, NightDancer.decodeLongEdge(221.0, 2.625, 1536, 1024))
        assertEquals(510, NightDancer.decodeLongEdge(85.0, 2.0, 1536, 1024))
        assertEquals(2048, NightDancer.decodeLongEdge(400.0, 3.0, 4096, 2731))
        assertEquals(0, NightDancer.decodeLongEdge(221.0, 3.0, 0, 0))
        assertEquals(6_291_456L, NightDancer.decodedBytes(1536, 1536, 1024))
        assertEquals(4_688_736L, NightDancer.decodedBytes(1326, 1536, 1024))
        assertTrue("≤ ~11 MB ở trần", NightDancer.decodedBytes(2048, 2048, 1365) < 11_200_000L)
        // Android inSampleSize: không bao giờ mờ hơn cỡ cần.
        assertEquals(1, NightDancer.sampleSize(1536, 1536)); assertEquals(1, NightDancer.sampleSize(1536, 1326))
        assertEquals(2, NightDancer.sampleSize(1536, 510)); assertEquals(4, NightDancer.sampleSize(1536, 300))
        assertEquals(1, NightDancer.sampleSize(1536, 0))
        // Kế hoạch giải: lấy mẫu (chia đôi) rồi thu ĐÚNG cạnh cần — không lấy mẫu 2 (768 px, nhoè dưới đèn rọi).
        assertEquals(listOf(1, 1536, 1326), NightDancer.decodePlan(1536, 1326).toList())
        assertEquals("đúng cỡ gốc ⇒ không thu", listOf(1, 0, 0), NightDancer.decodePlan(1536, 1536).toList())
        assertEquals(listOf(2, 768, 510), NightDancer.decodePlan(1536, 510).toList())
        assertEquals(listOf(2, 0, 0), NightDancer.decodePlan(1536, 768).toList())
        assertEquals(listOf(1, 0, 0), NightDancer.decodePlan(1536, 0).toList())
        for (target in listOf(300, 510, 663, 769, 1000, 1326, 1535)) {
            val p = NightDancer.decodePlan(1536, target)
            val out = if (p[1] > 0) p[2] else 1536 / p[0]
            assertEquals("cạnh sau giải = cạnh cần ($target)", target, out)
        }
        assertTrue("RAM @2x < bản gốc", NightDancer.decodedBytes(1326, 1536, 1024) < NightDancer.decodedBytes(1536, 1536, 1024))
    }
}
