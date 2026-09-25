package com.viettelex.keyboard

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.io.File
import java.nio.file.Files
import java.text.Normalizer
import java.util.concurrent.Executor

/** Port iOS FeatureRegressionTests.swift. */
class EmojiBlobTests {
    @Before fun setUp() = TestAssets.install()

    @Test fun testPoopEmoji() {
        assertEquals(listOf("💩"), EmojiSuggest.emojis("cứt"))
        assertEquals(listOf("💩"), EmojiSuggest.emojis("shit"))
    }

    @Test fun testKnownKeysSurviveBlobification() {
        assertEquals(listOf("✂️"), EmojiSuggest.emojis("cut"))
        assertEquals(listOf("🍎"), EmojiSuggest.emojis("apple"))
        assertFalse(EmojiSuggest.emojis("anh trai").isEmpty())
    }

    @Test fun testCaseAndUnicodeNormalization() {
        assertEquals(listOf("💩"), EmojiSuggest.emojis("SHIT"))
        assertEquals(listOf("💩"), EmojiSuggest.emojis(Normalizer.normalize("cứt", Normalizer.Form.NFD)))
    }

    @Test fun testMisses() {
        assertEquals(emptyList<String>(), EmojiSuggest.emojis(""))
        assertEquals(emptyList<String>(), EmojiSuggest.emojis("zzzkhongco"))
        assertEquals(emptyList<String>(), EmojiSuggest.emojis("cứ"))
    }
}

class SettingsRegressionTests {
    @Test fun testHapticDefaultOffAndReadable() {
        assertFalse(KeyboardSettings.load { null }.hapticFeedback)
        assertTrue(KeyboardSettings.load { if (it == Keys.HAPTIC_FEEDBACK) true else null }.hapticFeedback)
    }

    @Test fun testLearnFollowsSuggestions() {
        val s = KeyboardSettings.load { if (it == Keys.SHOW_SUGGESTIONS) false else null }
        assertFalse(s.showSuggestions)
        assertFalse(s.learnWords)
    }

    @Test fun testRowHeightClampedAndResetAt() {
        val s = KeyboardSettings.load { when (it) { Keys.ROW_HEIGHT_ADJUST -> 42; Keys.USERLM_RESET_AT -> 7L; else -> null } }
        assertEquals(10, s.rowHeightAdjust)
        assertEquals(7L, s.userlmResetAt)
    }
}

class BridgeContractTests {
    @Before fun setUp() = TestAssets.install()

    @Test fun testPredictedCommitMatchesBoundary() {
        for (word in listOf("his", "vieejt", "google", "loss", "ddaayj", "toans")) {
            val proxy = MockProxy()
            val bridge = EngineBridge(KeyboardSettings())
            for (ch in word) bridge.letter(ch, proxy)
            val predicted = bridge.predictedCommit
            val committed = bridge.boundary(" ", proxy)
            assertEquals("peek lệch commit cho $word", predicted, committed)
        }
    }

    /**
     * iOS test FAIL sẵn trên clean tree: kỳ vọng "loss" được restore, nhưng engine hiện tại
     * (POLICY V2: trailing cancel "ss" → "los") chốt "los" = composed. Pin theo engine thật;
     * ca restore thật cho backspace-undo dùng "google" (gôgle → google).
     */
    @Test fun testRestorePairForUndo() {
        val proxy = MockProxy()
        val bridge = EngineBridge(KeyboardSettings())
        for (ch in "his") bridge.letter(ch, proxy)
        assertEquals("hí", bridge.composedWord)
        assertEquals("hí", bridge.boundary(" ", proxy))   // collision thật → Việt thắng
        val p2 = MockProxy(); val b2 = EngineBridge(KeyboardSettings())
        for (ch in "loss") b2.letter(ch, p2)
        assertEquals("los", b2.composedWord)
        assertEquals("los", b2.boundary(" ", p2))
        val p3 = MockProxy(); val b3 = EngineBridge(KeyboardSettings())
        for (ch in "google") b3.letter(ch, p3)
        assertEquals("gôgle", b3.composedWord)
        assertNotEquals(b3.composedWord, b3.boundary(" ", p3))
    }
}

class TopWordsCacheTests {
    @Test fun testTopWordsCacheInvalidatesOnRecord() {
        val m = UserLangModel(); m.isKnownWord = { true }
        m.record("một", null, null, 5)
        m.topWords(3)
        m.record("hai", null, null, 50)
        assertEquals("hai", m.topWords(1).first())
    }

    @Test fun testEraseAllClearsTopWords() {
        val m = UserLangModel(); m.isKnownWord = { true }
        m.record("xin", null, null, 9)
        m.topWords(3)
        m.eraseAll()
        assertTrue(m.topWords(3).isEmpty())
    }
}

class SuggestionFillTests {
    @Test fun testAlreadyEnoughTruncates() =
        assertEquals(listOf("a", "b", "c"), SuggestionFill.pad(listOf("a", "b", "c", "d"), listOf("x"), 3))
    @Test fun testPadsToNeed() =
        assertEquals(listOf("em", "anh", "là"), SuggestionFill.pad(listOf("em"), listOf("anh", "là", "một"), 3))
    @Test fun testDedupCaseInsensitive() =
        assertEquals(listOf("Em", "anh", "là"), SuggestionFill.pad(listOf("Em"), listOf("em", "anh", "ANH", "là"), 3))
    @Test fun testExcludesTypedWord() =
        assertEquals(listOf("xin", "bạn"), SuggestionFill.pad(emptyList(), listOf("xin", "chào", "bạn"), 3, "Chào"))
    @Test fun testUnderfilledReturnsWhatExists() =
        assertEquals(listOf("a", "b"), SuggestionFill.pad(listOf("a"), listOf("b"), 3))
    @Test fun testEmptyBaseFillsThree() =
        assertEquals(listOf("một", "hai", "ba"), SuggestionFill.pad(emptyList(), listOf("một", "hai", "ba", "bốn"), 3))
}

class DoubleSpacePeriodTests {
    @Test fun testAfterWord() = assertTrue(TypingHeuristics.doubleSpaceMakesPeriod("xin chào ", true))
    @Test fun testRequiresLastWasSpace() = assertFalse(TypingHeuristics.doubleSpaceMakesPeriod("xin chào ", false))
    @Test fun testNoPeriodAtStart() = assertFalse(TypingHeuristics.doubleSpaceMakesPeriod(" ", true))
    @Test fun testNoDoublePunctuation() {
        for (c in listOf(".", "!", "?", ","))
            assertFalse("sau '$c'", TypingHeuristics.doubleSpaceMakesPeriod("hết$c ", true))
    }
    @Test fun testNeedsTrailingSpace() = assertFalse(TypingHeuristics.doubleSpaceMakesPeriod("chào", true))
    @Test fun testVietnameseLetterCounts() = assertTrue(TypingHeuristics.doubleSpaceMakesPeriod("việt ", true))
}

class MemoryBudgetTests {
    @Before fun setUp() = TestAssets.install()

    private fun usedMB(): Double {
        val r = Runtime.getRuntime()
        repeat(3) { System.gc(); Thread.sleep(20) }
        return (r.totalMemory() - r.freeMemory()) / 1_048_576.0
    }

    /** Heap delta khi ép load toàn bộ cấu trúc dữ liệu (lexicon mmap, emoji, seed model). */
    @Test fun testDataStructuresStayUnderBudget() {
        val before = usedMB()
        EmojiSuggest.emojis("yêu")
        VNSuggest.matches("nguoi")
        val m = UserLangModel()
        m.seedIfEmpty(SeedData.unigrams, SeedData.bigrams)
        m.topWords(6)
        val delta = usedMB() - before
        println("MemoryBudget: data structures heap delta = %.2f MB".format(delta))
        assertTrue("phình bất thường ($delta MB)", delta < 8.0)
        assertTrue(m.uniSize > 0)
    }
}

/** Port UserLangModelSaveNowTests: file thật, io + main đồng bộ trong test. */
class UserLangModelSaveNowTests {
    private val dir: File = Files.createTempDirectory("userlm").toFile()
    private val file = File(dir, Keys.USERLM_FILE)
    private val direct = Executor { it.run() }
    private val main = ImmediateMainThread()

    private fun loadedModel(): UserLangModel {
        var ready = false
        val m = UserLangModel(file, main, direct)
        m.isKnownWord = { true }
        m.onReady = { ready = true }
        // io + main đồng bộ ⇒ load xong ngay trong constructor (onReady gắn sau)
        assertFalse(ready)
        return m
    }

    @Test fun testSaveNowPersists() {
        val m = loadedModel()
        m.record("việt", null, null, 7)
        assertTrue(m.hasPendingSave)
        m.saveNow()
        assertEquals(7, loadedModel().count("việt"))
    }

    @Test fun testSaveNowSkipsWhenNothingPending() {
        val m = loadedModel()
        m.record("nam", null, null, 3)
        m.saveNow()
        assertEquals(3, loadedModel().count("nam"))
        file.delete()
        m.saveNow()
        assertFalse(file.exists())
    }

    @Test fun testSaveNowThenSaveKeepsNewestSnapshot() {
        val m = loadedModel()
        m.record("một", null, null, 1)
        m.saveNow()
        m.record("một", null, null, 4)
        m.save()
        assertEquals(5, loadedModel().count("một"))
    }

    @Test fun testCoalescedSaveFiresFromScheduler() {
        val m = loadedModel()
        m.record("ba", null, null, 2)
        assertFalse(file.exists())
        main.runPending()
        assertEquals(2, loadedModel().count("ba"))
    }

    @Test fun testRoundTripNestedTables() {
        val m = loadedModel()
        repeat(2) { m.record("ơn", "cảm") }
        repeat(3) { m.record("nhiều", "ơn", "cảm") }
        m.save()
        assertEquals(listOf("nhiều"), loadedModel().nextWords("ơn", "cảm", 1))
    }

    @Test fun testReloadAfterExternalEraseNeverWritesStaleData() {
        val m = loadedModel()
        m.seedIfEmpty(mapOf("seedword" to 5), emptyList())
        m.record("riêng", null, null, 9)
        m.save()
        // app bấm "Xóa từ đã học": xoá file + đổi userlmResetAt
        file.delete()
        m.record("riêng", null, null, 1)            // có ghi chờ (5 s) từ trước lúc reload
        m.reloadAfterExternalErase()
        assertFalse(m.hasPendingSave)
        main.runPending()
        assertEquals(0, m.count("riêng"))
        assertEquals(5, m.count("seedword"))          // seed lại
        assertEquals(0, loadedModel().count("riêng"))
    }

    @Test fun testDecayWeekly() {
        val m = loadedModel()
        m.record("tuần", null, null, 10)
        m.setLastDecayForTest(System.currentTimeMillis() - 15L * 86_400_000L)
        m.decayIfDue()
        assertEquals(4, m.count("tuần"))              // 10 × 0.7² = 4.9 → 4
    }

    @Test fun testCorruptFileIgnored() {
        file.writeBytes(byteArrayOf(1, 2, 3))
        val m = loadedModel()
        assertEquals(0, m.count("x"))
    }
}
