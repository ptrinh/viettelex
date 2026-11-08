package com.viettelex.keyboard

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * Theme JSON tương tác: "particles" (hạt tự tạo — "Theo giao diện") + "keywords" (từ khoá tự tạo). Đọc / kiểm / kẹp ở
 * fixture chung (ThemeSpecTests.sharedCasesWithIOS); ở đây: số phát hạt CHUNG iOS (ThemeFxTests.swift), bảng từ khoá,
 * trần, gốc lệch, khứ hồi "Chép JSON" / kho / sao lưu, 0 chi phí khi không có, fuzz.
 */
class ThemeFxTests {
    private var savedPaywall = false
    @Before fun setUp() { savedPaywall = PlusGate.paywallEnabled; PlusGate.paywallEnabled = false }
    @After fun tearDown() { PlusGate.paywallEnabled = savedPaywall }

    private val base = """{"v":1,"name":{"vi":"x"},"light":{"key":"#FFFFFF","special":"#DDDDDD","ink":"#000000","accent":"#000000"}"""
    private fun spec(extra: String): ThemeSpec? = ThemeSpecParser.parse("$base,$extra}").spec

    companion object {
        const val NOODLES = """"effect":"theme","particles":{"glyphs":["🍜","🥢"],"count":6,"spread":360,"speed":90,"gravity":260,"lifeMs":1400,"size":22,"sizeJitter":30,"spin":120}"""
        const val HEARTS = """"keywords":[{"words":["yêu","love","năm mới"],"burst":{"glyphs":["❤️","💖"],"count":10,"spread":360,"speed":130,"gravity":-60},"text":"Yêu ❤️"},{"words":["phở","yêu"]}]"""
    }

    @Test fun sharedEmissionNumbers() {
        val p0 = ThemeParticles.FALLBACK.particle(0, 1)
        assertEquals(-95.516210961, p0.vx, 1e-6)
        assertEquals(-67.493628301, p0.vy, 1e-6)
        assertEquals(12.479176013, p0.size, 1e-6)
        val p4 = ThemeParticles.FALLBACK.particle(4, 3)
        assertEquals(105.642016591, p4.vx, 1e-6)
        assertEquals(-56.722040466, p4.vy, 1e-6)
        assertEquals(13.783712520, p4.size, 1e-6)
        assertEquals(0.8, p4.life, 1e-12)
        assertEquals(Math.PI * 0.8, p4.rotation, 1e-9)
    }

    @Test fun emissionDirectionAndPhysics() {
        for ((dir, sx, sy) in listOf(Triple(0, 0.0, -1.0), Triple(90, 1.0, 0.0), Triple(180, 0.0, 1.0), Triple(-90, -1.0, 0.0))) {
            val p = ThemeParticles(count = 1, spread = 0, direction = dir, speed = 100).particle(0, 7)
            val sp = Math.hypot(p.vx, p.vy)
            assertEquals("$dir", sx, p.vx / sp, 1e-9)
            assertEquals("$dir", sy, p.vy / sp, 1e-9)
            assertTrue(sp in 80.0..120.0)
        }
        val g = ThemeParticle(0.0, 0.0, 200.0, 1.0, 10.0, 0.0, false, 0, 0)
        assertEquals(25.0, g.offsetY(0.5), 1e-9)
        assertEquals(100.0, g.offsetY(5.0), 1e-9)
        assertEquals(1.0, g.alpha(0.2), 0.0); assertEquals(0.5, g.alpha(0.75), 1e-9); assertEquals(0.0, g.alpha(1.0), 0.0)
        val fi = g.copy(fadeIn = true)
        assertEquals(0.0, fi.alpha(0.0), 0.0); assertEquals(0.5, fi.alpha(0.075), 1e-9)
    }

    @Test fun emissionBoundedForExtremeSpecs() {
        val r = FxRandom(42)
        repeat(300) {
            var t = ThemeParticles(colors = listOf(0xFF000000.toInt(), -1, 0x80FF0000.toInt()), glyphs = listOf("🍜"))
            for ((k, rg) in ThemeParticles.RANGES) t = t.withInt(k, rg.first + (r.next() * (rg.last - rg.first)).toInt())
            for (i in 0 until t.effCount) {
                val p = t.particle(i, (r.next() * 1e6).toInt())
                for (v in listOf(p.vx, p.vy, p.size, p.rotation, p.life)) assertTrue(v.isFinite())
                assertTrue(Math.hypot(p.vx, p.vy) <= 600 * 1.2 + 1e-9)
                assertTrue(p.size in 4.0..96.0)
                assertTrue(p.life in 0.2..2.5)
                assertTrue(p.colorIndex < 3); assertEquals(0, p.glyphIndex)
            }
            assertTrue(t.effCount * ThemeParticles.slots(t.effCount) <= KeyEffectPool.CAP)
        }
        assertEquals(1, ThemeParticles.slots(12)); assertEquals(5, ThemeParticles.slots(4)); assertEquals(8, ThemeParticles.slots(1))
    }

    @Test fun originWithShiftedBounds() {
        assertEquals(100.0, ThemeFxOrigin.y("bottom", -20.0, 20.0, -180.0, 110.0), 0.0)
        assertEquals(-170.0, ThemeFxOrigin.y("top", 0.0, 20.0, -180.0, 110.0), 0.0)
        assertEquals(-180.0, ThemeFxOrigin.y("key", -400.0, 20.0, -180.0, 110.0), 0.0)
        assertEquals(390.0, ThemeFxOrigin.x(500.0, 0.0, 390.0), 0.0)
        assertEquals(0.0, ThemeFxOrigin.x(-5.0, 0.0, 390.0), 0.0)
    }

    @Test fun glyphAndWordRules() {
        for (g in listOf("🍜", "❤️", "👨‍👩‍👧", "🇻🇳", "👍🏽", "1️⃣", "ế", "é", "★", "A")) assertTrue(g, ThemeGlyph.isSingle(g))
        for (g in listOf("", "ab", "🍜🌸", " ", "́", "👨‍", "‍👨", "🇻", "🇻🇳🇺🇸", "a b", " ", "́".repeat(20)))
            assertFalse(g, ThemeGlyph.isSingle(g))
        for (w in listOf("yêu", "năm mới", "love", "phở")) assertTrue(w, ThemeKeywordTable.isValidWord(w))
        for (w in listOf("", " yêu", "yêu ", "a  b", "a b c", "abc1", "c++", "yêu!")) assertFalse(w, ThemeKeywordTable.isValidWord(w))
    }

    @Test fun keywordMatchingRules() {
        val t = ThemeKeywordTable(spec(HEARTS)!!.keywords!!)
        assertEquals(0, t.lookup("yêu", null))
        assertEquals(0, t.lookup("YÊU", null))
        assertEquals(0, t.lookup("Love,", null))
        assertNull("dấu có nghĩa", t.lookup("yeu", null))
        assertEquals(1, t.lookup("phở", null))
        assertNull(t.lookup("pho", null))
        assertEquals(0, t.lookup("mới", "năm"))
        assertNull(t.lookup("mới", "nam"))
        assertNull(t.lookup("mới", null))
        assertEquals("NFD ⇒ NFC", 0, t.lookup("yêu", null))
        assertNull(t.lookup("", null))
        assertNull(t.lookup("a".repeat(200), null))
        assertEquals(0, t.lookup("yêu", "anh"))
        SensitiveWords.set.firstOrNull { ThemeKeywordTable.isValidWord(it) }?.let { bad ->
            assertNull(bad, ThemeKeywordTable(listOf(ThemeKeyword(listOf(bad)))).lookup(bad, null))
        }
        assertEquals(ThemeKeyword.MAX_ENTRIES, ThemeKeywordTable(List(30) { ThemeKeyword(listOf("từ")) }).entries.size)
    }

    @Test fun themeFxMakeIsNullWithoutFields() {
        assertNull(ThemeFx.make(null))
        assertNull(ThemeFx.make(spec(""""effect":"heart"""")))
        assertNull(ThemeFx.make(spec(""""keywords":[]""")))
        val fx = ThemeFx.make(spec(HEARTS))!!
        assertNull(fx.particles)
        assertEquals(10, fx.burst(0).effCount)
        assertEquals(ThemeParticles.KEYWORD_FALLBACK, fx.burst(1))
        assertEquals(1, fx.keywordSlots)
        val both = ThemeFx.make(spec("$NOODLES,\"keywords\":[{\"words\":[\"phở\"]}]"))!!
        assertEquals(both.particles, both.burst(0))
        assertEquals(2, both.keywordSlots)
        assertNull(ThemeFxPolicy.active(both, plus = false, powerSave = false))
        assertNull(ThemeFxPolicy.active(both, plus = true, powerSave = true))
        assertEquals(both, ThemeFxPolicy.active(both, plus = true, powerSave = false))
        assertTrue(ThemeExtraIds.EFFECTS.contains("theme"))
    }

    @Test fun roundTripCopyStoreBackup() {
        val s = spec("$NOODLES,$HEARTS")!!
        assertEquals(s, ThemeSpecParser.parse(s.canonical).spec)
        assertEquals(s, ThemeSpecParser.parse(s.json.pretty).spec)
        val custom = s.copy(id = "mi")
        val raw = CustomThemeStore.serialize(mapOf("mi" to custom))
        assertEquals(s.particles, CustomThemeStore.parse(raw)["mi"]?.particles)
        assertEquals(s.keywords, CustomThemeStore.parse(raw)["mi"]?.keywords)
        assertEquals(raw, CustomThemeStore.normalize(raw))
        val back = ThemeSpecParser.parse(ThemeSettings().exportSpec(custom).canonical).spec!!
        assertEquals(s.particles, back.particles)
        assertEquals(s.keywords, back.keywords)
        assertEquals("theme", back.effect)
    }

    @Test fun fuzzNeverCrashes() {
        val seeds = listOf("$base,$NOODLES}", "$base,$HEARTS}", "$base,$NOODLES,$HEARTS}")
        val junk = listOf("{", "}", "[", "]", "\"", ":", ",", "null", "-", "9", "1.5", "\\u0301", "\\u200d", "🍜", "\"glyphs\"",
            "\"words\"", "[[[[", "999999999", "\"#FF00FF\"", "\"count\":", "\"burst\":{")
        val r = java.util.Random(0x5EED)
        var oks = 0
        for (i in 0 until 3000) {
            var b = seeds[r.nextInt(seeds.size)].toByteArray(Charsets.UTF_8)
            when (i % 5) {
                0 -> b = b.copyOf(r.nextInt(b.size + 1))
                1 -> repeat(3) { val k = r.nextInt(b.size); b[k] = (b[k].toInt() xor (1 shl r.nextInt(7))).toByte() }
                2 -> { val k = r.nextInt(b.size + 1); b = b.copyOfRange(0, k) + junk[r.nextInt(junk.size)].toByteArray() + b.copyOfRange(k, b.size) }
                3 -> b += "[".repeat(r.nextInt(500)).toByteArray()
                else -> b = String(b, Charsets.UTF_8).replace("\"count\":6", "\"count\":${r.nextInt(2_000_000) - 1_000_000}")
                    .replace("\"speed\":90", "\"speed\":-999999999").toByteArray()
            }
            val out = ThemeSpecParser.parse(b)
            val s = out.spec
            if (s != null) {
                oks++
                assertTrue(out.errors.isEmpty())
                assertEquals(s.canonical, ThemeSpecParser.parse(s.canonical).spec?.canonical)
                s.particles?.let { assertTrue(it.effCount in 1..12); assertTrue(it.effSpeed in 20..600) }
                s.keywords?.let { assertTrue(it.size <= ThemeKeyword.MAX_ENTRIES) }
                ThemeFx.make(s)?.keywords?.lookup("yêu", "năm")
            } else assertFalse(out.errors.isEmpty())
        }
        assertTrue(oks > 0)
        assertNotNull(spec(NOODLES))
    }
}
