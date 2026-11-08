package com.viettelex.keyboard

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Theme Neon Night Club — Đèn rọi, quả cầu disco, Sàn nhảy LED, bóng cô gái nhảy. Số CHUNG iOS NightClubTests.swift. */
class SpotlightTests {
    @Test fun spotlightRadiusAlphaScale() {
        assertEquals(54.4, SpotlightFx.radius(34.0, 0), 1e-9)
        assertEquals(69.7, SpotlightFx.radius(34.0, 3), 1e-9)
        assertEquals(36.0, SpotlightFx.radius(10.0, 0), 0.0)
        assertEquals(150.0, SpotlightFx.radius(100.0, 3), 0.0)
        assertEquals(0.72, SpotlightFx.duration(0), 1e-12)
        assertEquals(0.87, SpotlightFx.duration(3), 1e-12)
        assertEquals(0.87, SpotlightFx.duration(9), 1e-12)
        assertEquals(0.78, SpotlightFx.peak(0), 1e-12)
        assertEquals(0.99, SpotlightFx.peak(3), 1e-12)
        assertEquals(0.0, SpotlightFx.alpha(-0.01, 0), 0.0)
        assertEquals(0.39, SpotlightFx.alpha(0.03, 0), 1e-12)
        assertEquals(0.78, SpotlightFx.alpha(0.06, 0), 1e-12)
        assertEquals(0.195, SpotlightFx.alpha(0.39, 0), 1e-12)
        assertEquals(0.0, SpotlightFx.alpha(0.72, 0), 0.0)
        assertEquals(0.007393689986282588, SpotlightFx.alpha(0.8, 3), 1e-12)
        assertEquals(0.8, SpotlightFx.scale(0.0, 0), 1e-12)
        assertEquals(1.025, SpotlightFx.scale(0.36, 0), 1e-12)
        assertEquals(1.1, SpotlightFx.scale(5.0, 0), 1e-12)
        assertEquals(listOf(0xFF2FD0, 0x9B5CFF, 0x2FE6FF, 0xFF2FD0), (0 until 4).map { SpotlightFx.color(it) })
        for (lv in 0..3) assertTrue(SpotlightFx.duration(lv) in 0.6..0.9)
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
        assertEquals(1.32, l.lastEnd, 1e-12)
        assertEquals(4, l.live(1.0))
        assertEquals(0, l.live(1.4))
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

    @Test fun dancerPosesParseAndRotate() {
        val poses = DancerFigure.POSES
        assertEquals(listOf("vArms", "point", "jump", "spin", "disco", "clap", "groove", "hips"), poses.map { it.id })
        val seq = (1..16).map { DancerFigure.poseIndex(it, poses.size) }
        assertEquals(listOf(3, 6, 1, 4, 7, 2, 5, 0), seq.take(8))
        assertEquals(8, seq.take(8).toSet().size)
        for (i in 1 until seq.size) assertNotEquals(seq[i], seq[i - 1])
        assertEquals(emptyList<DancerPose>(), DancerFigure.parse("{"))
        assertEquals(emptyList<DancerPose>(), DancerFigure.parse("""{"poses":[{"id":"a","torso":180}]}"""))
        assertEquals(emptyList<DancerPose>(), DancerFigure.parse("""{"poses":[{"id":"a","torso":999,"lua":0,"lfa":0,"rua":0,"rfa":0,"lth":0,"lsh":0,"rth":0,"rsh":0,"hair":0,"flare":0}]}"""))
        assertEquals(1, DancerFigure.parse("""{"poses":[{"id":"a","torso":180,"lua":0,"lfa":0,"rua":0,"rfa":0,"lth":0,"lsh":0,"rth":0,"rsh":0,"hair":0,"flare":50}]}""").size)
        assertTrue(BuiltinThemesData.DANCER_JSON.toByteArray().size < 30 * 1024)
        // Chuỗi nhúng trùng nguồn (Scripts/gen-builtin-themes.py).
        val src = java.io.File("../../themes/dancer-poses.json").takeIf { it.exists() }?.readText()?.trimEnd('\n')
        if (src != null) assertEquals(src, BuiltinThemesData.DANCER_JSON.trim())
    }

    @Test fun dancerGeometry() {
        val golden = doubleArrayOf(71623.601231, 67304.161350, 70302.961617, 73226.334031, 75023.606427, 72363.604897,
            71621.713071, 74609.106699)
        for ((i, p) in DancerFigure.POSES.withIndex()) {
            val polys = DancerFigure.fitted(p, 400.0, 300.0)
            assertEquals(p.id, 17, polys.size)
            assertEquals(p.id, 216, polys.sumOf { it.size / 2 })
            var minY = Double.POSITIVE_INFINITY; var maxY = Double.NEGATIVE_INFINITY
            for (q in polys) {
                var a = 0.0
                for (k in q.indices step 2) {
                    val n = (k + 2) % q.size
                    a += q[k] * q[n + 1] - q[n] * q[k + 1]
                    assertTrue(p.id, q[k] > 0 && q[k] < 400)
                    minY = minOf(minY, q[k + 1]); maxY = maxOf(maxY, q[k + 1])
                }
                assertTrue("${p.id} cùng chiều quay", a > 0)
            }
            assertEquals(21.0, minY, 1e-9); assertEquals(279.0, maxY, 1e-9)
            assertEquals(p.id, golden[i], DancerFigure.checksum(polys), 1e-5)
        }
    }
}
