package com.viettelex.keyboard

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs
import kotlin.math.hypot

/**
 * Theme Bể cá: lái cá, thả / chìm / ăn thức ăn, lớn dần, thêm cá + trần, ghi bộ đếm thưa, cảnh bể, âm "bloop". Số tham
 * chiếu CHUNG iOS (iOS/KeyboardTests/AquariumFxTests.swift) — đổi một bên phải đổi cả hai.
 */
class AquariumFxTests {

    @Test fun countsAndGrowth() {
        assertEquals(3, AquariumFx.fishCount(0))
        assertEquals(3, AquariumFx.fishCount(499))
        assertEquals(4, AquariumFx.fishCount(500))
        assertEquals(5, AquariumFx.fishCount(1499))
        assertEquals(6, AquariumFx.fishCount(1500))
        assertEquals("trần 6", 6, AquariumFx.fishCount(100_000))
        assertEquals(3, AquariumFx.fishCount(-5))
        assertEquals(1.0, AquariumFx.growth(0), 0.0)
        assertEquals(1.15, AquariumFx.growth(750), 1e-12)
        assertEquals(1.2998, AquariumFx.growth(1499), 1e-12)
        assertEquals("trần +30 %", 1.3, AquariumFx.growth(9999), 1e-12)
    }

    @Test fun regionWaypointSteerSink() {
        val r = AquariumFx.region(0.0, 0.0, 390.0, 260.0)
        assertEquals(AquariumFx.Region(12.0, 65.0, 378.0, 244.0), r)
        assertEquals(244.0, AquariumFx.floorY(r), 0.0)
        val w0 = AquariumFx.waypoint(0, 0, r)
        assertEquals(349.847013, w0.first, 1e-5); assertEquals(220.040467, w0.second, 1e-5)
        val w1 = AquariumFx.waypoint(1, 1, r)
        assertEquals(251.297597, w1.first, 1e-5); assertEquals(145.744610, w1.second, 1e-5)
        for (s in 0 until 6) for (k in 0 until 20) {
            val w = AquariumFx.waypoint(s, k, r)
            assertTrue(w.first >= r.minX && w.first <= r.maxX && w.second >= r.minY && w.second <= r.maxY)
        }
        // Một bước lái từ đứng yên: lực kẹp 90 × (1/30) = 3 dp/s.
        val f = AquariumFx.Fish(x = 100.0, y = 100.0, wx = 0.0, wy = 0.0, seed = 0)
        val o = AquariumFx.steer(f, 200.0, 100.0, 1.0 / 30, AquariumFx.MAX_SPEED, true, r)
        assertEquals(3.0, o.vx, 1e-12); assertEquals(0.0, o.vy, 0.0); assertEquals(100.1, o.x, 1e-12)
        assertEquals("steer trả bản sao", 0.0, f.vx, 0.0)
        // Tốc độ không vượt trần, vị trí kẹp trong vùng.
        var g = AquariumFx.Fish(x = 370.0, y = 240.0, wx = 0.0, wy = 0.0, seed = 0)
        repeat(300) {
            g = AquariumFx.steer(g, 1000.0, 1000.0, 1.0 / 30, AquariumFx.MAX_SPEED, false, r)
            assertTrue(hypot(g.vx, g.vy) <= AquariumFx.MAX_SPEED + 1e-9)
            assertTrue(g.x <= r.maxX && g.y <= r.maxY)
        }
        val p = AquariumFx.sink(AquariumFx.Pellet(50.0, 50.0, 100.0, 0.0, true), 0.5, 250.0)
        assertEquals(111.0, p.y, 1e-12); assertEquals(50.881678, p.x, 1e-5)
        val q = AquariumFx.sink(AquariumFx.Pellet(50.0, 50.0, 249.0, 5.9, true), 0.2, 250.0)
        assertEquals("dừng ở đáy", 250.0, q.y, 0.0); assertFalse("quá 6 s ⇒ tan", q.alive)
    }

    @Test fun nearestFishPrefersFree() {
        val a = AquariumFx.Fish(x = 0.0, y = 0.0, target = 3, wx = 0.0, wy = 0.0, seed = 0)
        val b = AquariumFx.Fish(x = 50.0, y = 0.0, wx = 0.0, wy = 0.0, seed = 1)
        val c = AquariumFx.Fish(x = 100.0, y = 0.0, wx = 0.0, wy = 0.0, seed = 2)
        assertEquals("cá bận bị bỏ qua", 1, AquariumFx.nearestFish(listOf(a, b, c), 3, 1.0, 0.0))
        val busy = listOf(a.copy(), b.copy(target = 0), c.copy(target = 1))
        assertEquals("không ai rảnh ⇒ gần nhất", 0, AquariumFx.nearestFish(busy, 3, 1.0, 0.0))
        assertEquals(-1, AquariumFx.nearestFish(emptyList(), 0, 0.0, 0.0))
    }

    @Test fun worldFeedingDeterministic() {
        val w = AquariumFx.World(0, 0.0, 0.0, 390.0, 260.0)
        assertEquals(3, w.count)
        assertEquals(349.847013, w.fish[0].x, 1e-5); assertEquals(34.026459, w.fish[1].x, 1e-5)
        assertEquals(84.217075, w.fish[2].x, 1e-5)
        w.drop(200.0, 120.0)
        assertEquals("cá gần nhất đi ăn", listOf(-1, -1, 0), w.fish.map { it.target })
        var ate = 0
        repeat(120) { ate += w.step(1.0 / 30) }
        assertEquals(1, ate); assertEquals(1, w.eaten)
        assertEquals(301.2957, w.fish[0].x, 1e-3); assertEquals(193.9167, w.fish[0].y, 1e-3)
        assertFalse(w.pellets.any { it.alive })
        // 40 viên dồn dập: ring 8 viên, tất định.
        val v = AquariumFx.World(0, 0.0, 0.0, 390.0, 260.0)
        var tot = 0
        for (j in 0 until 40) {
            v.drop((20 + (j * 37) % 350).toDouble(), (80 + (j * 53) % 150).toDouble())
            repeat(6) { tot += v.step(1.0 / 30) }
        }
        repeat(300) { tot += v.step(1.0 / 30) }
        assertEquals(11, tot); assertEquals(11, v.eaten)
        assertEquals(1060.5885, v.fish.sumOf { it.x + it.y }, 1e-2)
        assertTrue(v.pellets.size <= AquariumFx.MAX_PELLETS)
    }

    @Test fun newFishThresholdAndCap() {
        val w = AquariumFx.World(1499, 0.0, 0.0, 390.0, 260.0)
        assertEquals(5, w.count)
        w.drop(195.0, 150.0)
        var n = 0
        while (n < 200 && w.step(1.0 / 30) == 0) n++
        assertEquals(1500, w.eaten); assertEquals("mỗi 500 viên thêm một chú", 6, w.count)
        assertEquals(1.3, w.scale(0), 1e-12)
        assertEquals(1.3 * 0.85, w.scale(1), 1e-12)
        assertEquals(AquariumFx.MAX_FISH, AquariumFx.World(50_000, 0.0, 0.0, 390.0, 260.0).count)
    }

    @Test fun persistThrottle() {
        val g = AquariumFx.PersistGate()
        assertFalse("chưa bẩn", g.shouldSave(0.0))
        g.note()
        assertTrue(g.shouldSave(0.0))
        g.note()
        assertFalse("≤ một lần mỗi 5 s", g.shouldSave(4.9))
        assertTrue(g.shouldSave(5.0))
        assertFalse("không đổi ⇒ không ghi", g.shouldSave(20.0))
        g.note()
        assertTrue("ẩn bàn phím ⇒ ghi ngay", g.flush(21.0))
        assertFalse(g.flush(21.5))
        val h = AquariumFx.PersistGate(); var writes = 0
        for (i in 0 until 1800) { h.note(); if (h.shouldSave(i / 30.0)) writes++ }
        assertEquals(12, writes)
    }

    @Test fun aquariumScene() {
        assertTrue(ThemeScene.isScene(ThemeDecoration.AQUARIUM))
        assertEquals(listOf(0x0F4C7A, 0x0B3D66, 0x062847), ThemeScene.gradient(ThemeDecoration.AQUARIUM, false).toList())
        assertEquals(listOf(0x0F4C7A, 0x0B3D66, 0x062847), ThemeScene.gradient(ThemeDecoration.AQUARIUM, true).toList())
        val rays = AquariumScene.rays(390.0, 260.0)
        assertEquals(4, rays.size)
        assertEquals(46.8, rays[0][0].first, 1e-9); assertEquals(195.0, rays[0][2].second, 0.0)
        for (q in rays) for (p in q) assertTrue(p.first in 0.0..390.0 && p.second in 0.0..260.0)
        val sand = AquariumScene.sandTop(390.0, 260.0)
        assertEquals(50, sand.size); assertEquals(390.0, sand.last().first, 0.0)
        for (p in sand) assertTrue(p.second >= 260 - AquariumScene.SAND_HEIGHT - 2 && p.second <= 260)
        val weeds = AquariumScene.weeds(390.0, 260.0)
        assertEquals(6, weeds.size)
        for (w in weeds) assertTrue(w[5] >= 0 && w[5] < w[1] && w[4] >= 0 && w[4] <= 390)
    }

    @Test fun bloopSound() {
        assertTrue(KeySoundStyle.BLOOP in KeySoundStyle.PRESETS)
        assertEquals(0x626C6F6F xor 0x85EBCA6B.toInt(), KeySoundSynth.seed(KeySoundStyle.BLOOP, KeySoundSynth.Kind.LETTER))
        val golden = listOf(KeySoundSynth.Kind.LETTER to 178.8050, KeySoundSynth.Kind.DELETE to 180.1272, KeySoundSynth.Kind.MODIFIER to 213.0168)
        for ((k, want) in golden) {
            assertEquals("$k", want, KeySoundSynth.samples(KeySoundStyle.BLOOP, k).sumOf { abs(it.toDouble()) }, 0.01)
        }
        val wood = KeySoundSynth.samples(KeySoundStyle.WOOD, KeySoundSynth.Kind.LETTER)
        val b = KeySoundSynth.samples(KeySoundStyle.BLOOP, KeySoundSynth.Kind.LETTER)
        assertTrue("không to hơn Gõ gỗ", b.maxOf { abs(it) } < wood.maxOf { abs(it) })
        assertEquals("Fish bloop", L10nTable.EN["Bọt cá"])
    }

    @Test fun aquariumTheme() {
        val t = KeyboardTheme.AQUARIUM
        val spec = t.spec
        assertNotNull(spec)
        assertTrue(t.isPlus); assertTrue(t.isInteractive)
        assertEquals("Bể cá", spec!!.nameVi); assertEquals("Aquarium", spec.nameEn)
        assertEquals("Aquarium", L10nTable.EN[t.viTitle])
        assertEquals("bloop", spec.sound); assertEquals("fishfeed", spec.effect)
        assertNull("dark = same", spec.dark)
        assertTrue(ThemeSpecParser.contrastIssues(spec).isEmpty())
        assertEquals("Feed the fish", L10nTable.EN[KeyEffect.FISHFEED.viTitle])
        assertEquals(KeyEffectBand.BELOW_KEYS, KeyEffect.FISHFEED.band)
        assertTrue(KeyEffect.FISHFEED in ThemeFxFactory.EFFECTS)
        val p = t.palette(false)!!
        assertEquals(ThemeDecoration.AQUARIUM, p.decoration?.motif)
        // Phím trong mờ: chữ ≥ 4.5 trên mọi điểm gradient của cảnh (kể cả dưới vệt nắng ở đỉnh).
        val ray = p.decoration!!.color
        for (s in ThemeScene.gradient(ThemeDecoration.AQUARIUM, false)) {
            val stop = ThemeColor.rgb(s)
            for (base in listOf(stop, ThemeColor.over(ray, stop))) {
                assertTrue(Integer.toHexString(s), ThemeColor.contrast(p.ink, ThemeColor.over(p.keyFill, base)) >= 4.5)
                assertTrue(ThemeColor.contrast(p.fnInk, ThemeColor.over(p.fnFill, base)) >= 4.5)
            }
        }
    }
}
