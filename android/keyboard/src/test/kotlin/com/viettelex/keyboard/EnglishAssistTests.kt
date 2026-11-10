package com.viettelex.keyboard

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.io.File
import java.text.Normalizer
import java.util.Locale

/**
 * Góp ý người dùng 19/10/2026 ("phần gợi ý cũng nên bổ sung thêm gợi ý tiếng anh vì nhiều khi có từ
 * tiếng anh dài mà không nhớ cách viết") — [EnglishAssist]. Song sinh iOS EnglishAssistTests.swift.
 */
class EnglishAssistTests {
    @Before fun setUp() = TestAssets.install()

    private val bridge = EngineBridge()

    private fun assist(raw: String): EnglishAssist.Result? {
        val composed = bridge.composeTrial(raw)
        val pool = VNSuggest.matches(composed, 24, composed.lowercase())
        return EnglishAssist.suggest(raw, composed, pool, VNSuggest.frequency(composed))
    }

    private fun session(): KeyboardSession = KeyboardSession(UserLangModel()).also { it.startInput(KeyboardSettings(), FieldTraits()) }
    private fun KeyboardSession.typeKeys(p: TextProxy, keys: String) {
        for (c in keys) handle(if (c == ' ') Key.Space else Key.Letter(c), p)
    }
    private fun SuggestionSet.words() = listOfNotNull(word, word2) + moreWords

    // MARK: hoàn thành

    @Test fun longEnglishPrefixesComplete() {
        for ((raw, want) in listOf("accom" to "accommodation", "enviro" to "environment", "responsib" to "responsibility",
                                   "necess" to "necessary", "definit" to "definitely", "keyb" to "keyboard")) {
            val r = assist(raw)
            assertEquals(raw, EnglishAssist.Kind.COMPLETION, r?.kind)
            assertTrue("$raw → ${r?.words}", r!!.words.contains(want))
        }
    }

    @Test fun completionsRankedByFrequency() {
        val w = assist("accom")!!.words
        val lex = SwipeEnglish.lexicon
        val f = w.map { lex.freq(EnglishAssist.indexOf(it, lex)) }
        assertEquals(w.toString(), f.sortedDescending(), f)
        assertTrue(w.size <= EnglishAssist.COMPLETION_LIMIT)
    }

    @Test fun mergeEnglishLeadsThenVietnamese() {
        val r = EnglishAssist.Result(listOf("person", "personal", "personality"), EnglishAssist.Kind.COMPLETION)
        assertEquals(listOf("person", "personal", "pé", "personality"), EnglishAssist.merge(listOf("pé", "Person"), r))
        val fix = EnglishAssist.Result(listOf("environment"), EnglishAssist.Kind.CORRECTION)
        assertEquals(listOf("nhiều", "environment"), EnglishAssist.merge(listOf("nhiều"), fix))
        assertEquals(listOf("a"), EnglishAssist.merge(listOf("a"), null))
    }

    /** Qua cả phiên bàn phím (SuggestJob nền + composingSuggestions): từ Anh lên thanh, chạm = chèn nguyên văn. */
    @Test fun sessionShowsAndInsertsEnglishRaw() {
        val s = session(); val p = MockProxy()
        s.typeKeys(p, "accom")
        val set = s.suggestionsNow(p)!!
        val en = assist("accom")!!.words
        assertEquals("${set.words()}", en.take(2), set.words().take(2))   // tiếng Việt không khớp ⇒ từ Anh dẫn
        val pick = set.words().first()
        s.acceptSuggestion(pick, p)
        assertEquals("$pick ", p.text)          // không bị Telex bỏ dấu lại
        // sai chính tả cả từ
        val t = session(); val q = MockProxy()
        t.typeKeys(q, "Enviroment")
        assertTrue("${t.suggestionsNow(q)!!.words()}", "Environment" in t.suggestionsNow(q)!!.words())
    }

    // MARK: tiếng Việt không đổi

    @Test fun clearlyVietnameseNeverTouchesEnglish() {
        var touched = 0
        for (raw in listOf("nguowif", "ddeens", "thaatj", "chuyeenj", "khoong", "dduowcj", "thin", "chan", "tooi")) {
            val composed = bridge.composeTrial(raw)
            val pool = VNSuggest.matches(composed, 24, composed.lowercase())
            assertNull(raw, EnglishAssist.suggest(raw, composed, pool, VNSuggest.frequency(composed)) { touched++; SwipeEnglish.lexicon })
        }
        assertFalse(EnglishAssist.eligible("cas"))
        assertFalse(EnglishAssist.eligible("abc1"))
        assertFalse(EnglishAssist.eligible("a".repeat(25)))
        assertTrue(EnglishAssist.eligible("Accom"))
        assertTrue("từ rõ là tiếng Việt không đọc lexicon tiếng Anh", touched <= 2)
        // phiên thật: gõ tiếng Việt thường ⇒ thanh không có từ tiếng Anh nào
        val s = session(); val p = MockProxy()
        s.typeKeys(p, "nguowi")
        for (w in s.suggestionsNow(p)!!.words()) assertFalse(w, w.all { it in 'a'..'z' } && SwipeEnglish.contains(w) && w.length > 6)
    }

    /** Mọi tiền tố ≥ 4 phím của âm tiết Việt trong câu heldout: có âm tiết Việt khớp ⇒ không trộn tiếng Anh. */
    @Test fun neverFiresOnVietnameseHeldout() {
        val f = listOf("../../iOS", "../iOS", "iOS").map { File(it, "KeyboardTests/Fixtures/bigram-heldout.txt") }.first { it.exists() }
        val syllables = f.readLines().filter { it.isNotBlank() && !it.startsWith("#") }.flatMap { it.split(' ') }.toSet()
        var checked = 0
        val fired = ArrayList<String>()
        for (s in syllables) {
            val raws = telexVariants(s).filter { it.length >= 4 }.flatMap { v -> (4..v.length).map { v.take(it) } }.toMutableList()
            val t = toneless(s)
            if (t.length >= 4) raws += t
            for (raw in raws) {
                val composed = bridge.composeTrial(raw)
                val pool = VNSuggest.matches(composed, 24, composed.lowercase())
                if (pool.isEmpty()) continue
                checked++
                EnglishAssist.suggest(raw, composed, pool, VNSuggest.frequency(composed))?.let { fired += "$raw/$composed→${it.words.first()}" }
            }
        }
        println("ENGLISH-ASSIST vietnamese prefixes checked $checked, fired ${fired.size}: ${fired.take(10)}")
        assertTrue(checked > 1000)
        assertEquals(emptyList<String>(), fired)
    }

    // MARK: sửa chính tả

    @Test fun misspellingsCorrected() {
        for ((raw, want) in listOf("acommodation" to "accommodation", "enviroment" to "environment",
                                   "responsability" to "responsibility", "neccessary" to "necessary",
                                   "definately" to "definitely", "recieve" to "receive", "spellnig" to "spelling")) {
            val r = assist(raw)
            assertEquals(raw, EnglishAssist.Kind.CORRECTION, r?.kind)
            assertEquals("$raw → ${r?.words}", want, r!!.words.first())
            assertTrue(r.words.size <= EnglishAssist.TYPO_LIMIT)
        }
    }

    @Test fun misspelledPrefixWhileTyping() {
        assertTrue("${assist("acomm")?.words}", assist("acomm")!!.words.any { it.startsWith("accomm") })
    }

    @Test fun noCorrectionForRealWordsShortOrFar() {
        assertNull(assist("hello"))
        assertNull(assist("zzqxv"))
        assertTrue(EnglishAssist.corrections("abcd", SwipeEnglish.lexicon).isEmpty())
    }

    // MARK: lọc + hoa/thường

    @Test fun sensitiveFilter() {
        val r = EnglishAssist.Result(listOf("fucking", "fun"), EnglishAssist.Kind.COMPLETION)
        assertEquals(listOf("fun"), EnglishAssist.filtered(r, null, null, true)?.words)
        assertEquals(listOf("fucking", "fun"), EnglishAssist.filtered(r, null, null, false)?.words)
        assertNull(EnglishAssist.filtered(EnglishAssist.Result(listOf("shit"), EnglishAssist.Kind.CORRECTION), null, null, true))
        for (raw in listOf("fuck", "shitt", "bitc", "motherfuc"))
            for (w in assist(raw)?.words ?: emptyList()) assertFalse("$raw → $w", SensitiveWords.filter(listOf(w), true).isEmpty())
    }

    @Test fun casing() {
        fun shown(raw: String): List<String> {
            val composed = bridge.composeTrial(raw)
            return (assist(raw)?.words ?: emptyList()).map {
                SuggestionCase.display(DisplayCase.resolve(it, null), SuggestionCase.Shift.OFF, composed)
            }
        }
        assertTrue("${shown("Accom")}", "Accommodation" in shown("Accom"))
        assertTrue("${shown("ACCOM")}", "ACCOMMODATION" in shown("ACCOM"))
        assertTrue("${shown("singa")}", "Singapore" in shown("singa"))
        assertTrue("${shown("Enviroment")}", "Environment" in shown("Enviroment"))
    }

    // MARK: độ trễ

    /** Chi phí thêm mỗi phím trong SuggestJob (nền). In "ENGLISH-ASSIST LAT JVM". */
    @Test fun latencyBounds() {
        SwipeEnglish.lexicon
        val vn = ("xin chaof moij nguowif hoom nay tooi ddi lamf vieecj owr coong ty mowis vaf gawpj nhieeuf ddoongf " +
            "nghieepj raats vui veer chungs tooi cungf nhau baanf veef keees hoachj sanr phaamr cho nawm sau").split(' ')
        val en = listOf("accommodation", "environment", "responsibility", "acommodation", "enviroment",
                        "responsability", "neccessary", "definately", "information", "experience")
        fun keys(ws: List<String>) = ws.flatMap { w -> (1..w.length).map { w.take(it) } }.map { it to bridge.composeTrial(it) }
        val vk = keys(vn); val ek = keys(en)
        fun time(k: List<Pair<String, String>>, assist: Boolean): Double {
            var best = Double.MAX_VALUE
            repeat(9) { r ->
                val t = System.nanoTime()
                for ((raw, composed) in k) {
                    val pool = VNSuggest.matches(composed, 24, composed.lowercase())
                    SuggestRank.inlinePmi(pool, null, prev2 = null)
                    if (assist && EnglishAssist.eligible(raw)) EnglishAssist.suggest(raw, composed, pool, VNSuggest.frequency(composed))
                }
                if (r >= 2) best = minOf(best, (System.nanoTime() - t) / 1e3 / k.size)
            }
            return best
        }
        val vb = time(vk, false); val va = time(vk, true); val eb = time(ek, false); val ea = time(ek, true)
        var worst = 0.0
        repeat(3) {
            for ((raw, composed) in ek) if (EnglishAssist.eligible(raw)) {
                val pool = VNSuggest.matches(composed, 24, composed.lowercase())
                val t = System.nanoTime()
                EnglishAssist.suggest(raw, composed, pool, VNSuggest.frequency(composed))
                if (it > 0) worst = maxOf(worst, (System.nanoTime() - t) / 1e6)
            }
        }
        var reads = 0
        for ((raw, composed) in vk) EnglishAssist.suggest(raw, composed, VNSuggest.matches(composed, 24, composed.lowercase()),
            VNSuggest.frequency(composed)) { reads++; SwipeEnglish.lexicon }
        println("ENGLISH-ASSIST phím tiếng Việt chạm lexicon Anh: $reads / ${vk.size}")
        println(String.format(Locale.ROOT, "ENGLISH-ASSIST LAT JVM (µs/phím, nền): tiếng Việt %.1f → %.1f (×%.2f) | tiếng Anh %.1f → %.1f | chậm nhất một phím %.2f ms",
            vb, va, va / vb, eb, ea, worst))
        assertTrue("tiếng Việt: gần như không thêm chi phí", va < vb * 1.3 + 5)
        assertTrue("một phím tiếng Anh ≪ ngân sách", worst < 10)
    }

    // MARK: phím Telex của âm tiết (= AppTests TelexKeys)

    private fun telexVariants(syllable: String): List<String> {
        val chars = ArrayList<String>()
        var tone: Char? = null
        for (u in Normalizer.normalize(syllable.lowercase(), Normalizer.Form.NFD)) {
            when (u.code) {
                0x302 -> { val k = chars.lastOrNull() ?: return emptyList(); chars[chars.size - 1] = k + k }
                0x306, 0x31B -> { val k = chars.lastOrNull() ?: return emptyList(); chars[chars.size - 1] = k + "w" }
                0x301 -> tone = 's'
                0x300 -> tone = 'f'
                0x309 -> tone = 'r'
                0x303 -> tone = 'x'
                0x323 -> tone = 'j'
                0x111 -> chars += "dd"
                in 0x61..0x7A -> chars += u.toString()
                else -> return emptyList()
            }
        }
        if (chars.isEmpty()) return emptyList()
        val all = chars.joinToString("")
        val t = tone ?: return listOf(all)
        var lastVowel = -1
        for ((i, c) in chars.withIndex()) if (c[0] in "aeiouy") lastVowel = i
        if (lastVowel < 0 || lastVowel >= chars.size - 1) return listOf(all + t)
        return listOf(all + t, chars.subList(0, lastVowel + 1).joinToString("") + t + chars.subList(lastVowel + 1, chars.size).joinToString(""))
    }

    private fun toneless(s: String): String =
        Normalizer.normalize(s.lowercase().replace("đ", "d"), Normalizer.Form.NFD).filter { it.code < 0x300 || it.code > 0x36F }
}
