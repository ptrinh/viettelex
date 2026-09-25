package com.viettelex.keyboard

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.nio.file.Files

class TemplatesTests {
    @Before fun setUp() = TestAssets.install()

    @Test fun testParseDefaultsFile() {
        val items = Templates.parseYAML(KeyboardData.text(Keys.ASSET_TEMPLATES_YAML))
        assertEquals(TemplateItem("👋", "Chào buổi sáng"), items.first())
        assertEquals(TemplateItem("IP❓", "https://api.ipify.org"), items.last())
        assertTrue(Templates.isDynamic(items.last().text))
    }

    @Test fun testParseFormats() {
        val y = "# c\n- \"a | b\"\n- plain\n- \"say \\\"hi\\\"\"\n-nodash\n- \"x | \"\n\n"
        assertEquals(listOf(TemplateItem("a", "b"), TemplateItem("", "plain"), TemplateItem("", "say \"hi\"")),
            Templates.parseYAML(y))
    }

    @Test fun testExportRoundTrip() {
        val items = listOf(TemplateItem("😀", "Chào \"bạn\""), TemplateItem("", "Không label"))
        val y = Templates.exportYAML(items)
        assertTrue(y.startsWith("# VietTelex — mẫu câu (2)\n"))
        assertEquals(items, Templates.parseYAML(y))
    }

    @Test fun testJsonRoundTripAndLoad() {
        val items = listOf(TemplateItem("a\"b", "line1\nline2 \\ ✓"), TemplateItem("", "x"))
        assertEquals(items, Templates.fromJson(Templates.toJson(items)))
        assertEquals(items, Templates.load(Templates.toJson(items)) { null })
        assertEquals(Templates.fallback, Templates.load(null) { null })
        assertEquals(listOf(TemplateItem("", "y")), Templates.fromJson("""[{"text":"y","other":[1,{"a":2}]},{"label":"z"}]"""))
        assertNull(Templates.fromJson("not json"))
    }

    @Test fun testMergeNoticeAndAdd() {
        val cur = listOf(TemplateItem("", "a"))
        val (out, notice) = Templates.merge(cur, listOf(TemplateItem("", "a"), TemplateItem("", "b")))
        assertEquals(2, out.size)
        assertEquals("Đã thêm 1/2 mẫu (trùng bị bỏ qua).", notice)
        assertEquals("Đã thêm 1/1 mẫu.", Templates.merge(cur, listOf(TemplateItem("", "c"))).second)
        assertNull(Templates.add(cur, "", " a "))
        assertEquals(TemplateItem("👋", "b"), Templates.add(cur, " 👋 ", " b\n")!!.last())
    }

    @Test fun testDynamicBody() {
        assertEquals("1.2.3.4", Templates.bodyFromResponse("  1.2.3.4\n".toByteArray()))
        assertNull(Templates.bodyFromResponse("   ".toByteArray()))
        assertEquals(1000, Templates.bodyFromResponse(ByteArray(3000) { 'a'.code.toByte() })!!.length)
    }
}

class KeyRouterTests {
    // hàng phím chữ giả lập: 3 phím rộng 30, cao 40, khe 6
    private val keys = listOf(KRect(0f, 100f, 30f, 140f), KRect(36f, 100f, 66f, 140f), KRect(72f, 100f, 102f, 140f))

    @Test fun testInsideAndGapGoesToExpandedKey() {
        assertEquals(1, KeyRouter.nearestLetter(KPoint(50f, 120f), keys, 95f))
        assertEquals(0, KeyRouter.nearestLetter(KPoint(32f, 120f), keys, 95f))   // khe: nở dx 3
        assertEquals(0, KeyRouter.nearestLetter(KPoint(10f, 144f), keys, 95f))   // dưới: nở dy 5.5
    }

    @Test fun testNearestWithin21() {
        assertEquals(2, KeyRouter.nearestLetter(KPoint(120f, 120f), keys, 0f))  // 18 dp
        assertNull(KeyRouter.nearestLetter(KPoint(130f, 120f), keys, 0f))       // 28 dp
        assertNull(KeyRouter.nearestLetter(KPoint(10f, 90f), keys, 95f))        // strip gợi ý
    }

    @Test fun testCoreContainsAndDensity() {
        assertTrue(KeyRouter.letterCoreContains(KPoint(1f, 101f), keys, 95f))
        val px = keys.map { KRect(it.left * 3, it.top * 3, it.right * 3, it.bottom * 3) }
        assertEquals(0, KeyRouter.nearestLetter(KPoint(32f * 3, 120f * 3), px, 95f * 3, 3f))
    }
}

class EmojiDataTests {
    @Before fun setUp() = TestAssets.install()

    @Test fun testCategories() {
        val c = EmojiData.categories
        assertEquals(listOf("smileys", "animals", "food", "activity", "travel", "objects", "symbols", "flags"), c.map { it.name })
        assertEquals("🇻🇳", c.last().emoji.first())
        assertEquals("CỜ", EmojiData.displayName("flags"))
    }

    @Test fun testToneVariants() {
        val v = EmojiData.toneVariants("👍")!!
        assertEquals(6, v.size)
        assertEquals("👍🏻", v[1])
        assertNull(EmojiData.toneVariants("😀"))
        val zwj = EmojiData.toneVariants("🧑‍🤝‍🧑")!!
        assertEquals("\uD83E\uDDD1\uD83C\uDFFD\u200D\uD83E\uDD1D\uD83C\uDFFD\u200D\uD83E\uDDD1\uD83C\uDFFD", zwj[3])   // 🤝 cũng là modifier base (Unicode 14+)
    }

    @Test fun testRecents() {
        var r = emptyList<String>()
        for (i in 0 until 35) r = EmojiRecents.noteUsed(r, "e$i")
        assertEquals(30, r.size); assertEquals("e34", r.first())
        r = EmojiRecents.noteUsed(r, "e20")
        assertEquals("e20", r.first()); assertEquals(30, r.size)
        assertEquals(r, EmojiRecents.decode(EmojiRecents.encode(r)))
        assertEquals(emptyList<String>(), EmojiRecents.decode(null))
    }
}

class TouchLogTests {
    @Test fun testNeverRecordsCharactersInRelease() {
        val f = Files.createTempFile("touchlog", ".txt").toFile()
        TouchLog.synchronous = true
        TouchLog.configure(f, recordsCharacters = false)
        TouchLog.enabled = true
        TouchLog.key("letter", true, 0.1, "q")
        TouchLog.edit(1, 1, "ệ")
        TouchLog.touchBegan(1, 1, 2.0, true, 10.0, "w")
        val text = f.readText()
        assertTrue(text.contains("key=letter") && text.contains("edit bs=1 ins=1"))
        assertTrue(!text.contains("[q]") && !text.contains("ệ") && !text.contains("[w]"))
        TouchLog.configure(f, recordsCharacters = true)
        TouchLog.key("letter", true, 0.1, "z")
        assertTrue(f.readText().contains("[z]"))
        assertTrue(TouchLog.tail(1).contains("[z]"))
        TouchLog.enabled = false
        TouchLog.key("letter", true, 0.1, "y")
        assertTrue(!f.readText().contains("[y]"))
        TouchLog.clear(); TouchLog.configure(null, false); TouchLog.synchronous = false
    }

    @Test fun testCapKeepsNewerHalf() {
        val f = Files.createTempFile("touchlog", ".txt").toFile()
        f.writeText("x".repeat(310_000))
        TouchLog.synchronous = true
        TouchLog.configure(f, false); TouchLog.enabled = true
        TouchLog.write("tail-line")
        assertTrue(f.length() < 160_000)
        assertTrue(f.readText().endsWith("tail-line\n"))
        TouchLog.enabled = false; TouchLog.configure(null, false); TouchLog.synchronous = false
    }
}

/** Chạm để sửa mẫu câu (26/09/2026) — Templates.edit. */
class TemplatesEditTests {
    private val base = listOf(TemplateItem("👋", "Chào"), TemplateItem("", "Hẹn gặp"))
    @org.junit.Test fun editReplacesRow() {
        val r = Templates.edit(base, 1, " 🙂 ", " Hẹn gặp lại ")!!
        kotlin.test.assertEquals(TemplateItem("🙂", "Hẹn gặp lại"), r[1])
        kotlin.test.assertEquals(base[0], r[0])
    }
    @org.junit.Test fun editRejectsEmptyDuplicateOrBadIndex() {
        kotlin.test.assertNull(Templates.edit(base, 1, "", "  "))
        kotlin.test.assertNull(Templates.edit(base, 1, "", "Chào"))
        kotlin.test.assertNull(Templates.edit(base, 5, "", "x"))
        kotlin.test.assertNotNull(Templates.edit(base, 0, "", "Chào"))   // giữ nguyên câu của chính nó
    }
}
