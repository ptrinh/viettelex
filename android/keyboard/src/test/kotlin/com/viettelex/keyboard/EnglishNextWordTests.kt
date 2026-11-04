package com.viettelex.keyboard

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * #146: sau một từ tiếng Anh ("they" + dấu cách) thanh gợi ý hiện "the / of / and" — đó là
 * top unigram tiếng Anh (SwipeEnglish.top) dùng để ĐỆM ô trống, không phải ngữ cảnh. Từ trước
 * tiếng Anh ⇒ không đệm từ phổ biến; cặp cá nhân trước, rồi bảng từ kế tiếp tiếng Anh [EnglishNext]
 * (Tatoeba, Scripts/english-next.tsv). Âm tiết Việt và đầu ô giữ nguyên hành vi. Song sinh iOS
 * EnglishNextWordTests.swift. Kỳ vọng lấy từ BẢNG (không chép cứng — bảng sinh lại được).
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

    /** Từ kế tiếp mong đợi sau [prev] khi không có cặp cá nhân: đúng bảng, tối đa 3. */
    private fun tableNext(prev: String) = EnglishNext.next(prev).map { it.lowercase() }.take(3)

    @Test fun tableShape() {
        val h = EnglishNext.heads
        assertEquals(h.size, EnglishNext.followers.size)
        assertTrue(h.size in 300..500)
        for (i in 1 until h.size) assertTrue("đã sắp: ${h[i - 1]} < ${h[i]}", h[i - 1] < h[i])
        for (f in EnglishNext.followers) assertTrue(f, f.split(' ').size in 1..3)
        assertTrue(EnglishNext.next("they").isNotEmpty())
        assertEquals(EnglishNext.next("they"), EnglishNext.next("They"))
        assertTrue(EnglishNext.next("kubernetes").isEmpty())
        assertTrue(EnglishNext.next("").isEmpty())
    }

    @Test fun englishNextFillPure() {
        val table = listOf("are", "were", "have")
        assertEquals(listOf("are", "were", "have"), SuggestRank.englishNextFill(emptyList(), table, 3))
        assertEquals("cá nhân trước, bỏ trùng", listOf("were", "are", "have"),
            SuggestRank.englishNextFill(listOf("were"), table, 3))
        assertEquals("bảng rỗng ⇒ không đệm gì", listOf("x"), SuggestRank.englishNextFill(listOf("x"), emptyList(), 3))
        assertEquals("lọc nhạy cảm", listOf("are", "have"),
            SuggestRank.englishNextFill(emptyList(), table, 3, filter = { l -> l.filter { it != "were" } }))
        assertEquals("đủ ô ⇒ giữ nguyên", listOf("a", "b", "c"),
            SuggestRank.englishNextFill(listOf("a", "b", "c", "d"), table, 3))
    }

    @Test fun englishModeTheyUsesTable() {
        SwipeEnglish.top
        val s = session(); val p = MockProxy()
        s.restoreLanguage("en", p)
        assertTrue(s.bridge.englishMode)
        // đầu ô vẫn đệm từ Anh phổ biến (hành vi cũ)
        assertEquals(3, s.suggestionsNow(p)!!.nextWords.size)
        s.type(p, "they ")
        assertEquals("they ", p.text)
        val next = s.suggestionsNow(p)!!.nextWords.map { it.lowercase() }
        assertEquals("đúng bảng EnglishNext: $next", tableNext("they"), next)
        assertTrue("không đệm the/of/and ngoài bảng: $next", next.none { it in generic && it !in tableNext("they") })
    }

    @Test fun englishModeKeepsPersonalPairsFirst() {
        SwipeEnglish.top
        val lm = UserLangModel().apply { isKnownWord = { true } }
        // một từ KHÔNG nằm trong bảng sau "they" ⇒ chắc chắn đứng đầu nhờ là cặp cá nhân
        val mine = listOf("love", "like", "want", "go").first { it !in tableNext("they") }
        repeat(3) { lm.record(mine, "they") }
        val s = KeyboardSession(lm, null) { 0L }
        s.startInput(KeyboardSettings(spaceSwipeLanguage = true), FieldTraits())
        val p = MockProxy()
        s.restoreLanguage("en", p)
        s.type(p, "they ")
        val next = s.suggestionsNow(p)!!.nextWords.map { it.lowercase() }
        assertEquals(mine, next.first())
        assertEquals(listOf(mine) + tableNext("they").take(2), next)
    }

    @Test fun englishModeWordNotInTableStaysEmpty() {
        SwipeEnglish.top
        val s = session(); val p = MockProxy()
        s.restoreLanguage("en", p)
        s.type(p, "kubernetes ")
        val next = s.suggestionsNow(p)!!.nextWords
        assertTrue("không đệm từ phổ biến: $next", next.isEmpty())
    }

    @Test fun vietnameseModeEnglishWordUsesTable() {
        SwipeEnglish.top
        val s = session(); val p = MockProxy()
        s.type(p, "they ")
        assertEquals("they ", p.text)
        val next = s.suggestionsNow(p)!!.nextWords.map { it.lowercase() }
        assertEquals("sau \"they\" giữa câu Việt: bảng, không top unigram: $next", tableNext("they"), next)
    }

    @Test fun capitalIFollowerShowsUppercase() {
        val head = EnglishNext.heads.indices.first { "I" in EnglishNext.followers[it].split(' ') }
        assertTrue(EnglishNext.next(EnglishNext.heads[head]).contains("I"))
        assertTrue(EnglishNext.followers.none { "i" in it.split(' ') })
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

    /** Cụm người Việt hay dùng (chọn tay): "check" giữa câu Việt ⇒ seed trước, lấp bằng bảng. */
    @Test fun vietnameseModeCheckUsesTable() {
        SwipeEnglish.top
        val s = session(); val p = MockProxy()
        s.type(p, "check ")
        val next = s.suggestionsNow(p)!!.nextWords.map { it.lowercase() }
        // cặp cá nhân / seed (check lại…) đứng trước, phần còn lại lấp từ bảng, không the/of/and
        assertEquals(3, next.size)
        assertTrue("$next", next.any { it in tableNext("check") })
        assertTrue("$next", next.none { it in generic && it !in tableNext("check") })
    }

    /** Từ lóng / thương mại thêm vào enlexicon 04/11/2026 (SUPPLEMENT) — gợi ý hoàn thành từ được. */
    @Test fun slangInEnglishLexicon() {
        for (w in listOf("flex", "cringe", "slay", "rizz", "simp", "skincare", "freeship", "livestream", "chill", "vibe"))
            assertTrue(w, SwipeEnglish.contains(w))
    }

    /** Cặp trộn Việt–Anh chỉ cho vuốt / gợi ý đang gõ (CuratedPairs.nextOnly), không phải từ kế tiếp. */
    @Test fun mixedCuratedPairsAreSwipeOnly() {
        assertTrue("trình" in CuratedPairs.next("out", null))
        assertTrue(CuratedPairs.swipe(null, "đu", "trend"))
        assertFalse("không cho Thêm dấu", CuratedPairs.has(null, "out", "trình"))
    }
}
