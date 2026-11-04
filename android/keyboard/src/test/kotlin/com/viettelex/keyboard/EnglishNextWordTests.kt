package com.viettelex.keyboard

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * #146: sau một từ tiếng Anh ("they" + dấu cách) thanh gợi ý hiện "the / of / and" — đó là
 * top unigram tiếng Anh (SwipeEnglish.top) dùng để ĐỆM ô trống, không phải ngữ cảnh. Từ trước
 * tiếng Anh ⇒ không đệm từ phổ biến; chỉ giữ bằng chứng thật (cặp cá nhân / seed). Âm tiết Việt
 * và đầu ô giữ nguyên hành vi. Song sinh iOS EnglishNextWordTests.swift.
 */
class EnglishNextWordTests {
    @Before fun setUp() = TestAssets.install()

    private val generic = setOf("the", "of", "and")

    private fun session(): KeyboardSession {
        val s = KeyboardSession(UserLangModel(), null) { 0L }
        s.startInput(KeyboardSettings(spaceSwipeLanguage = true), FieldTraits())
        return s
    }

    private fun KeyboardSession.type(p: TextProxy, keys: String) {
        for (c in keys) handle(if (c == ' ') Key.Space else Key.Letter(c), p)
    }

    @Test fun gatePure() {
        val en = { w: String -> w in setOf("they", "can", "hello") }
        val vi = { w: String -> w in setOf("can", "tôi") }
        assertTrue("đầu ô: đệm như cũ", SuggestRank.padsWithTopWords(null, true, en, vi))
        assertTrue(SuggestRank.padsWithTopWords(null, false, en, vi))
        assertFalse("chế độ Tiếng Anh sau một từ", SuggestRank.padsWithTopWords("they", true, en, vi))
        assertFalse("từ Anh giữa câu Việt", SuggestRank.padsWithTopWords("They", false, en, vi))
        assertTrue("âm tiết Việt", SuggestRank.padsWithTopWords("tôi", false, en, vi))
        assertTrue("trùng Anh–Việt (can/can) ⇒ coi là Việt", SuggestRank.padsWithTopWords("can", false, en, vi))
        assertTrue("từ lạ không phải Anh ⇒ như cũ", SuggestRank.padsWithTopWords("xyzq", false, en, vi))
    }

    @Test fun gateRealLexicons() {
        SwipeEnglish.top    // hâm nóng như IME
        assertFalse(SuggestRank.padsWithTopWords("they", false))
        assertTrue(SuggestRank.padsWithTopWords("tôi", false))
        assertTrue(SuggestRank.padsWithTopWords("the", false))      // "the" cũng là âm tiết Việt
    }

    @Test fun englishModeTheyHasNoGenericFill() {
        SwipeEnglish.top
        val s = session(); val p = MockProxy()
        s.restoreLanguage("en", p)
        assertTrue(s.bridge.englishMode)
        // đầu ô vẫn đệm từ Anh phổ biến (hành vi cũ)
        assertEquals(3, s.suggestionsNow(p)!!.nextWords.size)
        s.type(p, "they ")
        assertEquals("they ", p.text)
        val next = s.suggestionsNow(p)!!.nextWords
        assertTrue("không còn the/of/and: $next", next.none { it.lowercase() in generic })
    }

    @Test fun englishModeKeepsPersonalPairs() {
        SwipeEnglish.top
        val lm = UserLangModel().apply { isKnownWord = { true } }
        repeat(3) { lm.record("are", "they") }
        val s = KeyboardSession(lm, null) { 0L }
        s.startInput(KeyboardSettings(spaceSwipeLanguage = true), FieldTraits())
        val p = MockProxy()
        s.restoreLanguage("en", p)
        s.type(p, "they ")
        val next = s.suggestionsNow(p)!!.nextWords
        assertEquals(listOf("are"), next.map { it.lowercase() })
    }

    @Test fun vietnameseModeEnglishWordHasNoGenericFill() {
        SwipeEnglish.top
        val s = session(); val p = MockProxy()
        s.type(p, "they ")
        assertEquals("they ", p.text)
        val next = s.suggestionsNow(p)!!.nextWords
        assertTrue("không đệm từ phổ biến sau \"they\": $next", next.none { it.lowercase() in generic })
        assertTrue(next.isEmpty())
    }

    @Test fun vietnameseSyllableStillGetsBigram() {
        SwipeEnglish.top
        val s = session(); val p = MockProxy()
        s.type(p, "xin ")
        val next = s.suggestionsNow(p)!!.nextWords
        assertEquals(3, next.size)
        assertTrue(next.isNotEmpty())
        // nextFill thuần: bigram tĩnh vẫn lấp sau âm tiết Việt
        assertTrue(SuggestRank.bigramNext("xin", 6).isNotEmpty())
        assertEquals(3, SuggestRank.nextFill("xin", null, emptyList(), { 0 }).size)
    }
}
