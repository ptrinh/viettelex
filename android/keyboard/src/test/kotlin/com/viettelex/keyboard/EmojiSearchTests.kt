package com.viettelex.keyboard

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/** emoji.bin (Scripts/gen-emoji-data.py): dữ liệu, lọc glyph, tìm tiếng Việt, kaomoji. */
class EmojiBinTests {
    @Before fun setUp() = TestAssets.install()
    @After fun tearDown() { EmojiData.glyphCheck = null; EmojiData.trusted = 170 }

    @Test fun testCompleteAndUnique() {
        val cats = EmojiData.rawCategories
        var next = 0
        for (c in cats) { assertEquals(next, c.start); next += c.count }
        assertEquals(EmojiData.count, next)
        assertTrue(EmojiData.count > 1800)
        val all = (0 until EmojiData.count).map(EmojiData::emoji)
        assertEquals(all.size, all.toSet().size)
        assertFalse(all.any { it.isEmpty() || it.contains(' ') })
        assertFalse(all.any { e -> e.codePoints().anyMatch { it in 0x1F3FB..0x1F3FF } })
        assertTrue("🫩" in all)   // Emoji 16.0
        assertTrue("🫪" in all)   // Emoji 17.0
        val vers = (0 until EmojiData.count).map(EmojiData::version)
        assertEquals(170, vers.max())
        assertEquals(6, vers.min())
    }

    @Test fun testGlyphFilter() {
        EmojiData.trusted = EmojiData.trustedVersion(36)
        val asked = ArrayList<String>()
        EmojiData.glyphCheck = { e -> asked += e; e != "🫪" }   // máy giả: thiếu 🫪
        val shown = EmojiData.categories.flatMap { it.emoji }
        assertFalse("🫪" in shown)
        assertTrue("🫩" in shown)
        assertTrue("😀" in shown)
        // chỉ hỏi font cho emoji mới hơn mức tin cậy (API 36 → > 15.0)
        assertTrue(asked.isNotEmpty())
        val idOf = (0 until EmojiData.count).associateBy(EmojiData::emoji)
        assertTrue(asked.all { EmojiData.version(idOf.getValue(it)) > 150 })
        assertFalse("🫪" in EmojiSearch.search("méo", limit = 500))
        // bậc tin cậy tăng theo API
        assertTrue(EmojiData.trustedVersion(26) < EmojiData.trustedVersion(30))
        assertTrue(EmojiData.trustedVersion(30) < EmojiData.trustedVersion(36))
    }

    @Test fun testFold() {
        assertEquals("cho", EmojiSearch.fold("Chó"))
        assertEquals("duong cuoi", EmojiSearch.fold("Đường  cười!"))
        assertEquals("co viet nam", EmojiSearch.fold("cờ: Việt Nam"))
    }

    @Test fun testSearchVietnamese() {
        assertTrue("❤️" in EmojiSearch.search("tim"))
        assertTrue(EmojiSearch.search("chó").take(5).any { it == "🐶" || it == "🐕" })
        assertTrue(EmojiSearch.search("cười").take(10).any { it == "😂" || it == "😀" })
        assertTrue(EmojiSearch.search("yêu").isNotEmpty())
        assertTrue("🇻🇳" in EmojiSearch.search("việt nam"))
        assertTrue("🇻🇳" in EmojiSearch.search("viet"))
    }

    @Test fun testSearchWithoutDiacritics() {
        assertTrue(EmojiSearch.search("cho").any { it == "🐶" || it == "🐕" })
        assertTrue(EmojiSearch.search("cuoi").any { it == "😂" || it == "😀" })
        assertTrue(EmojiSearch.search("cu").isNotEmpty())
        val i = EmojiSearch.search("chó").indexOfFirst { it == "🐶" || it == "🐕" }
        assertTrue(i in 0..2)
        assertTrue(EmojiSearch.search("").isEmpty())
        assertTrue(EmojiSearch.search("  ").isEmpty())
        assertTrue(EmojiSearch.search("zzqxj").isEmpty())
        val r = EmojiSearch.search("mặt", limit = 200)
        assertEquals(r.size, r.toSet().size)
        assertTrue(EmojiSearch.ids("tim") { false }.isEmpty())
        assertTrue(EmojiSearch.keyCount > 5000)
    }

    @Test fun testEmoticonSearch() {
        val want = listOf(":)" to "😊", ":D" to "😄", ":(" to "☹️", ";)" to "😉", ":P" to "😛", "<3" to "❤️",
            "=))" to "😂", ":))" to "😆", "^_^" to "😊", "-_-" to "😑", ":o" to "😮", "xD" to "😆", ":'(" to "😢")
        for ((q, e) in want) assertEquals(q, e, EmojiSearch.search(q).firstOrNull())
        // hoa thường / space hai đầu như nhau; không trùng
        assertEquals(EmojiSearch.search(":p"), EmojiSearch.search(" :P "))
        assertEquals("😆", EmojiSearch.search("XD").first())
        val r = EmojiSearch.search("xd")
        assertEquals(r.size, r.toSet().size)
        assertEquals(2, EmojiSearch.search(":)", limit = 2).size)
        // mọi emoji trong bảng có trong emoji.bin (đúng dạng, kể cả FE0F)
        val all = (0 until EmojiData.count).map(EmojiData::emoji).toSet()
        for ((k, v) in EmojiSearch.EMOTICONS) {
            assertEquals("khoá viết thường: $k", k.lowercase(), k)
            for (e in v) assertTrue("$k → $e", e in all)
        }
        // câu tìm thường không đổi
        assertEquals(EmojiSearch.ids("tim").map(EmojiData::emoji), EmojiSearch.search("tim"))
        assertTrue(EmojiSearch.emoticon("tim").isEmpty())
        // gõ emoticon qua ô tìm (Telex) ra đúng khoá
        for (q in listOf(":D", "xD", ":o", ":P", "^_^", ":'(")) {
            val s = EmojiSearchSession()
            for (c in q) s.type(c)
            assertTrue("$q → ${s.query}", EmojiSearch.emoticon(s.query).isNotEmpty())
        }
    }

    @Test fun testSessionTelex() {
        val s = EmojiSearchSession()
        for (c in "chos") s.type(c)
        assertEquals("chó", s.query)
        s.backspace()
        assertEquals("ch", s.query)   // ⌫ xoá cả "ó" như ô nhập thật
        s.clear()
        for (c in "cuwowif") s.type(c)
        assertEquals("cười", s.query)
        s.space()
        for (c in "Vui") s.type(c)
        assertEquals("cười vui", s.query)
        repeat(20) { s.backspace() }
        assertEquals("", s.query)
    }

    @Test fun testKaomoji() {
        val g = EmojiData.kaomoji
        assertEquals(listOf("vui", "buồn", "yêu", "động vật", "ký hiệu"), g.map { it.name })
        for (grp in g) {
            assertTrue(grp.items.size >= 10)
            assertEquals(grp.items.size, grp.items.toSet().size)
            assertFalse(grp.items.any { it.isEmpty() })
        }
        val sym = g.last().items
        assertTrue("₫" in sym); assertTrue("→" in sym); assertTrue("“”" in sym); assertTrue("★" in sym)
        assertTrue("♥︎" in sym)
        assertTrue("¯\\_(ツ)_/¯" in g[0].items)
        assertTrue("( ͡° ͜ʖ ͡°)" in g[0].items)   // kaomoji có space giữ nguyên
    }
}
