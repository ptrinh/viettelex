package com.viettelex.keyboard

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/** Port iOS EngineBridgeTests.swift (EngineBridgeTests + SuggestionTests + UserLangModelTests + …). */
class EngineBridgeTests {
    @Before fun setUp() = TestAssets.install()

    private fun type(keys: String, secure: Boolean = false, settings: KeyboardSettings = KeyboardSettings()): String {
        val proxy = MockProxy(secure)
        val bridge = EngineBridge(settings)
        for (ch in keys) when (ch) {
            ' ' -> bridge.boundary(" ", proxy)
            '⌫' -> bridge.backspace(proxy)
            else -> bridge.letter(ch, proxy)
        }
        return proxy.text
    }

    @Test fun testBasicVietnamese() {
        assertEquals("việt ", type("vieetj "))
        assertEquals("Tiếng Việt rất hay ", type("Tieengs Vieetj raats hay "))
        assertEquals("đường ", type("dduwowngf "))
    }

    /**
     * iOS test này FAIL sẵn trên clean tree ở "off" (engine hiện tại chốt khác) — kỳ vọng
     * "off" ở đây chốt theo hành vi THẬT của engine (xem [testOffActualEngineBehaviour]).
     */
    @Test fun testAutoRestoreAndCollisions() {
        assertEquals("google ", type("google "))
        assertEquals("hí ", type("his "))          // collision THẬT: tiếng Việt thắng
        assertEquals("Default ", type("Deffault "))  // cancel keeps composed
    }

    @Test fun testOffActualEngineBehaviour() {
        // iOS kỳ vọng "off " nhưng engine hiện tại (TelexCore, POLICY V2 31/07: trailing
        // cancel thắng dict) cho "of " — pin theo engine thật.
        assertEquals("of ", type("off "))
    }

    @Test fun testBackspace() {
        assertEquals("việ", type("vieetj⌫"))
        assertEquals("tóa", type("toans⌫"))
        assertEquals("", type("a⌫"))
        assertEquals("", type("⌫"))
    }

    @Test fun testSecureFieldBypassesEngine() {
        assertEquals("vieejt ", type("vieejt ", secure = true))
    }

    @Test fun testPassthroughBypassesEngine() {
        val p = MockProxy(); val b = EngineBridge(); b.passthrough = true
        for (c in "vieejt") b.letter(c, p)
        b.boundary(" ", p)
        assertEquals("vieejt ", p.text)
    }

    @Test fun testResetDropsComposition() {
        // reEdit tắt: bật thì "e" ngay sau "vie" nạp lại từ trên màn hình (ReEditTests).
        val proxy = MockProxy().also { it.reEdit = false }
        val bridge = EngineBridge(KeyboardSettings())
        for (ch in "vie") bridge.letter(ch, proxy)
        bridge.reset()
        for (ch in "em") bridge.letter(ch, proxy)
        bridge.boundary(" ", proxy)
        assertEquals("vieem ", proxy.text)
    }

    @Test fun testSettingsRespected() {
        val s = KeyboardSettings()
        s.simpleTelex = true
        assertEquals("cw ", type("cw ", settings = s))
        s.simpleTelex = false
        assertEquals("như ", type("nhw ", settings = s))
    }

    @Test fun testContextualEnglish() {
        val s = KeyboardSettings()
        assertTrue(s.contextualEnglish)
        assertEquals("he is ", type("he is ", settings = s))
        assertEquals("sao í ", type("sao is ", settings = s))
        s.contextualEnglish = false
        assertEquals("he í ", type("he is ", settings = s))
    }

    @Test fun testTeencodeToggle() {
        val s = KeyboardSettings()
        assertFalse(s.teencode)
        assertEquals("was ", type("was ", settings = s))
        assertEquals("kos ", type("kos ", settings = s))
        s.teencode = true
        assertEquals("wá ", type("was ", settings = s))
        assertEquals("kó ", type("kos ", settings = s))
        assertEquals("thík ", type("thiks ", settings = s))
    }

    @Test fun testDefaultsMatchIOS() {
        val s = KeyboardSettings()
        assertTrue(s.simpleTelex && s.freeMarking && s.liveSpellCheck && s.autoRestore)
        assertFalse(s.quickTelex || s.modernTone || s.teencode || s.hapticFeedback)
        assertTrue(s.contextualEnglish && s.autoFixAdjacent && s.showSuggestions && s.filterSensitive)
    }
}

class SuggestionTests {
    @Before fun setUp() = TestAssets.install()

    @Test fun testEmojiSameForViAndEn() {
        assertEquals(3, EmojiSuggest.emojis("love").size)
        assertEquals(EmojiSuggest.emojis("love"), EmojiSuggest.emojis("yêu"))
        assertEquals(EmojiSuggest.emojis("cat"), EmojiSuggest.emojis("mèo"))
        assertTrue(EmojiSuggest.emojis("").isEmpty())
    }

    @Test fun testInlineDiacriticCompatibleMatch() {
        val to = VNSuggest.matches("to").map { it.word }
        assertTrue(to.contains("tôi")); assertTrue(to.contains("toàn"))
        val toCirc = VNSuggest.matches("tô").map { it.word }
        assertTrue(toCirc.contains("tôi"))
        assertTrue(toCirc.contains("tối") || toCirc.contains("tồi") || toCirc.contains("tội"))
        assertFalse(toCirc.contains("toàn")); assertFalse(toCirc.contains("tơi"))
        val toGrave = VNSuggest.matches("tò").map { it.word }
        assertTrue(toGrave.contains("tòa"))
        assertFalse(toGrave.contains("tôi")); assertFalse(toGrave.contains("tới"))
        assertTrue(VNSuggest.matches("t").map { it.word }.contains("tôi"))
        assertEquals("người", VNSuggest.matches("nguoi").first().word)
        assertTrue(VNSuggest.contains("người"))
        assertFalse(VNSuggest.contains("nguo"))
    }
}

class UserLangModelTests {
    @Before fun setUp() = TestAssets.install()

    private fun freshModel() = UserLangModel().apply { isKnownWord = { true } }

    @Test fun testLearnAndSuggest() {
        val m = freshModel()
        repeat(3) { m.record("anh", null) }
        repeat(3) { m.record("ơi", "anh") }
        m.record("đang", "anh")
        m.record("chào", null)
        assertEquals(listOf("anh"), m.topWords(1))
        val next = m.nextWords("anh", limit = 4)
        assertEquals("ơi", next.first())
        assertTrue(next.contains("đang"))
        assertEquals(listOf("ơn"), freshModel().nextWords("cảm", limit = 1))
        val m2 = freshModel()
        m2.record("xong", "cảm")
        assertEquals(listOf("ơn"), m2.nextWords("cảm", limit = 1))
        m.record("abc123", "anh")
        assertEquals(0, m.count("abc123"))
        assertFalse(UserLangModel.learnable("heeeyyy"))
    }

    @Test fun testTrigramContext() {
        val m = freshModel()
        repeat(2) { m.record("ơn", "cảm") }
        repeat(3) { m.record("nhiều", "ơn", "cảm") }
        m.record("anh", "ơn", "cảm")
        assertEquals(listOf("nhiều"), m.nextWords("ơn", "cảm", 1))
    }

    @Test fun testUnknownWordThreshold() {
        val m = UserLangModel()
        m.record("blib", null); m.record("blib", null)
        assertTrue(m.topWords(3).isEmpty())
        m.record("blib", null)
        assertEquals(listOf("blib"), m.topWords(3))
    }

    @Test fun testTriggerExpansion() {
        assertEquals(EmojiSuggest.emojis("đúng"), EmojiSuggest.emojis("done"))
        assertEquals(EmojiSuggest.emojis("đúng"), EmojiSuggest.emojis("xong"))
        assertEquals(EmojiSuggest.emojis("đúng"), EmojiSuggest.emojis("hoàn thành"))
        assertEquals(EmojiSuggest.emojis("sai"), EmojiSuggest.emojis("failed"))
        assertFalse(EmojiSuggest.emojis("trời ơi").isEmpty())
        assertFalse(EmojiSuggest.emojis("hoan thanh").isEmpty())
    }

    @Test fun testEmojiFoldedKeys() {
        assertEquals(EmojiSuggest.emojis("yêu"), EmojiSuggest.emojis("yeu"))
        assertFalse(EmojiSuggest.emojis("meo").isEmpty())
    }
}

class SeedDataTests {
    @Before fun setUp() = TestAssets.install()

    @Test fun testSeedInjection() {
        val m = UserLangModel()
        m.seedIfEmpty(SeedData.unigrams, SeedData.bigrams)
        assertFalse(m.topWords(3).isEmpty())
        assertTrue(m.nextWords("cảm", limit = 2).contains("ơn"))
        assertTrue(m.nextWords("hôm", limit = 2).contains("nay"))
        val before = m.count("không")
        m.seedIfEmpty(mapOf("xxx" to 99), emptyList())
        assertEquals(before, m.count("không"))
        assertEquals(0, m.count("xxx"))
        assertTrue((SeedData.unigrams.values.maxOrNull() ?: 0) <= 50)
    }

    @Test fun testSeedSizesMatchIOS() {
        val s = SeedData.load()
        assertEquals(882, s.unigrams.size)
        assertEquals(509, s.bigrams.size)
    }
}

class DisplayCaseTests {
    @Test fun testProperNounDisplay() {
        assertEquals("SenPrints", DisplayCase.apply("senprints"))
        assertEquals("Printik", DisplayCase.apply("printik"))
        assertEquals("iPhone", DisplayCase.apply("iphone"))
        assertEquals("macOS", DisplayCase.apply("macos"))
        assertEquals("Nguyễn", DisplayCase.apply("nguyễn"))
        assertEquals("GitHub", DisplayCase.apply("github"))
        assertEquals("ChatGPT", DisplayCase.apply("chatgpt"))
        assertEquals("Claude", DisplayCase.apply("claude"))
        assertEquals("cảm", DisplayCase.apply("cảm"))
        assertEquals("trang", DisplayCase.apply("trang"))
        assertEquals("Nội", DisplayCase.apply("nội", "hà"))
        assertEquals("Nội", DisplayCase.apply("nội", "Hà"))
        assertEquals("nội", DisplayCase.apply("nội"))
        assertEquals("Trang", DisplayCase.apply("trang", "nha"))
        assertEquals("Văn", DisplayCase.apply("văn", "nguyễn"))
        assertEquals("văn", DisplayCase.apply("văn"))
        assertEquals("vũ", DisplayCase.apply("vũ"))
    }

    @Test fun testLearningStaysCaseFolded() {
        val m = UserLangModel()
        m.record("SenPrints", null)
        assertEquals(1, m.count("senprints"))
        assertEquals(1, m.count("SenPrints"))
    }
}

class SensitiveWordsTests {
    @Test fun testFilterGate() {
        val words = listOf("vcl", "vui", "đcm", "cảm")
        assertEquals(listOf("vui", "cảm"), SensitiveWords.filter(words, true))
        assertEquals(words, SensitiveWords.filter(words, false))
        assertEquals(listOf("cướp", "giết"), SensitiveWords.filter(listOf("cướp", "giết"), true))
    }
}

class SeedOrderTests {
    @Before fun setUp() = TestAssets.install()

    @Test fun testEmptyFieldTop3() {
        val m = UserLangModel()
        m.isKnownWord = { true }
        m.seedIfEmpty(SeedData.unigrams, SeedData.bigrams)
        assertEquals(listOf("em", "anh", "tôi"), m.topWords(3))
    }
}
