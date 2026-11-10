package com.viettelex.keyboard

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * RAM-AUDIT #7 (10/11/2026): enlexicon đọc TẠI CHỖ trên buffer mmap (IntArray vị trí, String chỉ
 * cho từ trả ra) thay vì ~20k String. Chốt: (1) kết quả tra Y HỆT bản cũ trên TOÀN BỘ từ điển;
 * (2) đường main thread (tô nền sửa / tự sửa) không bao giờ nạp từ điển; (3) bảng gõ vuốt chỉ dựng
 * khi vuốt tiếng Anh cần; (4) Vocab vuốt nhả được.
 */
class EnglishLexiconInPlaceTests {
    @Before fun setUp() = TestAssets.install()

    private val buf get() = KeyboardData.buffer(Keys.ASSET_EN_LEXICON)
    private val legacy by lazy { LegacyEnglishLexicon.parse(buf)!! }
    private val lex by lazy { SwipeEnglish.parse(buf)!! }

    // MARK: parity cũ ↔ mới

    @Test fun wordsAndFrequenciesIdentical() {
        assertEquals(legacy.words.size, lex.count)
        assertTrue(lex.count > 10_000)
        for (i in 0 until lex.count) {
            assertEquals(legacy.words[i], lex.word(i))
            assertEquals(legacy.freq[i], lex.freq(i))
            assertEquals(legacy.words[i].length, lex.length(i))
        }
    }

    @Test fun membershipAndIndexIdentical() {
        val probes = ArrayList<String>()
        for (w in legacy.words) {
            probes += w; probes += w + "z"; probes += w.dropLast(1); probes += w.uppercase()
            probes += w.replaceFirstChar { it.uppercaseChar() }; probes += w + "ệ"
        }
        probes += listOf("", "a", "z", "zzzzzz", "việt", "đi", "a1", "hello world", "\u0000", "~", "{")
        for (p in probes) assertEquals(p, legacy.indexOf(p), lex.indexOf(p))
        for ((i, w) in legacy.words.withIndex()) assertEquals(i, lex.indexOf(w))
    }

    @Test fun completionsIdentical() {
        val prefixes = LinkedHashSet<String>()
        for ((i, w) in legacy.words.withIndex()) {
            for (k in 1..minOf(3, w.length)) prefixes += w.substring(0, k)
            if (i % 7 == 0) for (k in 4..w.length) prefixes += w.substring(0, k)
        }
        val extra = listOf("Hel", "HEL", "Th", "việt", "", "a1", "zzz", "qx")
        var n = 0
        for (p in prefixes + extra) for (limit in intArrayOf(24, 6)) {
            val want = legacy.completions(p, limit).map { it.word to it.freq }
            val got = SwipeEnglish.completions(p, limit, lex).map { it.word to it.freq }
            assertEquals(p, want, got); n++
        }
        assertTrue("$n", n > 5_000)
        assertEquals(legacy.topWords(60), SwipeEnglish.topWords(60, lex))
    }

    @Test fun typoCorrectionsIdentical() {
        var n = 0
        for ((i, w) in legacy.words.withIndex()) {
            if (i % 23 != 0 || w.length < EnglishAssist.TYPO_MIN_LEN) continue
            val mid = w.length / 2
            for (q in listOf(w.removeRange(mid, mid + 1), w.substring(0, mid) + w[mid + 1] + w[mid] + w.substring(mid + 2),
                    w.substring(0, mid) + 'q' + w.substring(mid + 1), w + "x", w.substring(0, w.length - 1))) {
                if (q.length < EnglishAssist.TYPO_MIN_LEN) continue
                assertEquals(q, legacy.corrections(q), EnglishAssist.corrections(q, lex)); n++
            }
        }
        assertTrue("$n", n > 1_000)
    }

    @Test fun swipeTablesIdentical() {
        val s = lex.swipe
        assertArrayEquals(legacy.freq, s.freq)
        assertArrayEquals(legacy.keys, s.keys)
        assertArrayEquals(legacy.keyStart, s.keyStart)
        assertArrayEquals(legacy.order, s.order)
        assertArrayEquals(legacy.bucketStart, s.bucketStart)
        assertEquals(legacy.words.size, s.count)
    }

    @Test fun corruptBlobsRejectedLikeBefore() {
        fun blob(vararg entries: ByteArray, count: Int = entries.size): java.nio.ByteBuffer {
            val o = java.io.ByteArrayOutputStream()
            o.write(byteArrayOf(0x56, 0x54, 0x45, 0x31)); o.write(byteArrayOf(count.toByte(), (count shr 8).toByte(), (count shr 16).toByte(), (count shr 24).toByte()))
            for (e in entries) o.write(e)
            return java.nio.ByteBuffer.wrap(o.toByteArray())
        }
        fun e(w: String, f: Int) = byteArrayOf(w.length.toByte(), f.toByte()) + w.toByteArray()
        val cases = listOf(
            blob(e("ab", 1), e("cd", 2)), blob(e("ab", 1), e("c1", 2)), blob(e("ab", 1), count = 3),
            blob(byteArrayOf(0, 5)), blob(e("Ab", 1)), java.nio.ByteBuffer.wrap(byteArrayOf(1, 2, 3)),
            blob(count = 0), blob(e("ab", 1), byteArrayOf(9, 1, 97)),
        )
        for ((k, b) in cases.withIndex()) {
            val old = LegacyEnglishLexicon.parse(b)
            val new = SwipeEnglish.parse(b)
            assertEquals("case $k", old == null, new == null)
            if (old != null) assertEquals(old.words.toList(), (0 until new!!.count).map { new.word(it) })
        }
    }

    // MARK: main thread không nạp

    @Test fun mainThreadCheckNeverLoads() {
        SwipeEnglish.release()
        val loads = SwipeEnglish.loads
        assertNull(SwipeEnglish.containsOrNull("cat"))
        assertFalse(SwipeEnglish.containsIfLoaded("cat"))
        assertNull("3 chữ, chưa nạp ⇒ chưa biết", AutoCorrect.isEnglishIfLoaded("cat"))
        assertFalse(SwipeEnglish.isLoaded)
        assertEquals(loads, SwipeEnglish.loads)
        SwipeEnglish.warm()
        assertEquals(true, AutoCorrect.isEnglishIfLoaded("cat"))
        assertEquals(false, AutoCorrect.isEnglishIfLoaded("xqzv"))
    }

    /** isEnglish đảo thứ tự (bảng hằng trước): cùng kết quả với bản cũ trên mọi từ thử. */
    @Test fun isEnglishOrderSwapIsIdentical() {
        val words = legacy.words.filterIndexed { i, _ -> i % 5 == 0 } +
            listOf("the", "and", "with", "check", "mail", "anh", "toi", "việt", "abcxyz", "ok", "laptop")
        for (w in words) {
            val old = SwipeEnglish.contains(w) || com.viettelex.telexcore.EnglishContextLookup.opensEnglishRun(w)
            assertEquals(w, old, AutoCorrect.isEnglish(w))
            assertEquals(w, old, AutoCorrect.isEnglishIfLoaded(w))
        }
    }

    private val center = AutoCorrect.Touch(0f, 0f)

    /** Từ 3 chữ có trong enlexicon mà (nếu không biết là tiếng Anh) sẽ bị tự sửa sang tiếng Việt. */
    private fun englishWordAtRiskOfCorrection(): String {
        val b = EngineBridge(KeyboardSettings())
        for (w in legacy.words) {
            if (w.length != 3 || com.viettelex.telexcore.EnglishContextLookup.opensEnglishRun(w)) continue
            val plan = AutoCorrect.plan(w, compose = { b.composeTrial(it) }, frequency = { VNSuggest.frequency(it) },
                hasCompletion = { VNSuggest.matches(it, poolLimit = 1).isNotEmpty() }) ?: continue
            if (AutoCorrect.decide(plan, List(3) { center }, isKnown = { false }) != null) return w
        }
        error("không tìm thấy từ thử")
    }

    /**
     * Tô nền sửa (mặc định khi bật gợi ý) với từ 3 chữ — EnglishAssist (≥ 4 phím) không nạp từ điển.
     * Trước: completeSuggestions (MAIN) → isKnownForAutoCorrect → SwipeEnglish.contains ⇒ parse trên
     * main. Giờ: compute() (worker) nạp khi có plan; main chỉ tra không nạp; nhả giữa chừng ⇒ không sửa.
     */
    @Test fun threeLetterWordLoadsOnWorkerNotMain() {
        val w = englishWordAtRiskOfCorrection()
        fun session() = KeyboardSession(UserLangModel(), null).also {
            it.startInput(KeyboardSettings(autoCorrect = false, showSuggestions = true), FieldTraits())
        }
        // 1) đường bình thường: worker nạp, main không nạp thêm, từ tiếng Anh không bị tô sửa
        SwipeEnglish.release()
        var s = session(); var p = MockProxy()
        for (c in w) s.handle(Key.Letter(c), p, center)
        var job = (s.requestSuggestions(p) as SuggestionPlan.Background).job
        var result: SuggestJob.Result? = null
        Thread { result = job.compute() }.apply { start(); join() }
        assertNotNull("có plan sửa", result!!.plan)
        assertTrue("worker đã nạp", SwipeEnglish.isLoaded)
        val loads = SwipeEnglish.loads
        var set = s.completeSuggestions(job, result!!, p)!!
        assertEquals(loads, SwipeEnglish.loads)
        assertFalse("$w là tiếng Anh ⇒ không tô sửa", set.correction)
        // 2) nhả (hẹn giờ ẩn) giữa compute và complete: main KHÔNG nạp, và không sửa nhầm
        s = session(); p = MockProxy()
        for (c in w) s.handle(Key.Letter(c), p, center)
        job = (s.requestSuggestions(p) as SuggestionPlan.Background).job
        Thread { result = job.compute() }.apply { start(); join() }
        SwipeEnglish.release()
        val loads2 = SwipeEnglish.loads
        set = s.completeSuggestions(job, result!!, p)!!
        assertFalse("main không nạp", SwipeEnglish.isLoaded)
        assertEquals(loads2, SwipeEnglish.loads)
        assertFalse("chưa biết ⇒ không sửa", set.correction)
    }

    // MARK: bảng gõ vuốt lười

    @Test fun swipeTablesOnlyWhenEnglishSwipeNeeds() {
        SwipeEnglish.release()
        val l = SwipeEnglish.lexicon
        assertFalse(l.hasSwipe)
        // gợi ý / hoàn thành / sửa chính tả / phân loại ngữ cảnh: không dựng bảng vuốt
        SwipeEnglish.completions("hel", 6)
        EnglishAssist.corrections("helllo", l)
        SwipeEnglish.top
        SwipeLangContext.classify("hello")
        val layout = SwipeLayout.qwerty(keyWidth = 40f, rowHeight = 54f)
        val d = SwipeDecoder().also { it.setLayout(layout) }
        val path = SwipeSim(3).path("tieng", layout)
        d.decode(path, 3, context = null, english = null)
        assertFalse("tắt vuốt tiếng Anh ⇒ không dựng bảng", l.hasSwipe)
        val r = d.decode(SwipeSim(3).path("hello", layout), 3, context = null, english = SwipeLangContext.ONLY_ENGLISH)
        assertTrue(l.hasSwipe)
        assertTrue(r.any { it.lang == SwipeLang.EN && it.folded == "hello" })
        SwipeEnglish.release()
        SwipeEnglish.warm(swipe = true)
        assertTrue(SwipeEnglish.lexicon.hasSwipe)
    }

    @Test fun swipeVocabReleaseRebuildsSame() {
        val a = SwipeVocab.current
        assertTrue(SwipeVocab.isCached)
        SwipeVocab.release()
        assertFalse(SwipeVocab.isCached)
        val b = SwipeVocab.current
        assertTrue(a !== b)
        assertEquals(a.forms.count, b.forms.count)
        assertArrayEquals(a.forms.keys, b.forms.keys)
        assertEquals(a.words.keys, b.words.keys)
    }
}

/** Bản CŨ (trước 10/11/2026) — giữ nguyên văn làm chuẩn so sánh: ~20k String + bảng vuốt dựng ngay. */
internal class LegacyEnglishLexicon(
    val words: Array<String>, val freq: IntArray, val keys: ByteArray, val keyStart: IntArray,
    val order: IntArray, val bucketStart: IntArray,
) {
    fun indexOf(word: String): Int {
        val a = words
        var lo = 0; var hi = a.size
        while (lo < hi) { val mid = (lo + hi) / 2; if (a[mid] < word) lo = mid + 1 else hi = mid }
        return if (lo < a.size && a[lo] == word) lo else -1
    }

    fun completions(typed: String, limit: Int): List<VNSuggest.Match> {
        val low = typed.lowercase()
        if (low.isEmpty() || limit <= 0 || low.any { it !in 'a'..'z' }) return emptyList()
        val a = words
        var lo = 0; var hi = a.size
        while (lo < hi) { val mid = (lo + hi) / 2; if (a[mid] < low) lo = mid + 1 else hi = mid }
        val hits = ArrayList<Int>()
        var i = lo
        while (i < a.size && a[i].startsWith(low)) { if (a[i] != low) hits.add(i); i++ }
        hits.sortWith { x, y -> if (freq[x] != freq[y]) freq[y] - freq[x] else x - y }
        return hits.take(limit).map { VNSuggest.Match(SwipeEnglish.matchCase(a[it], typed), freq[it]) }
    }

    fun topWords(limit: Int): List<String> =
        freq.indices.sortedWith { x, y -> if (freq[x] != freq[y]) freq[y] - freq[x] else x - y }.take(limit).map { words[it] }

    private fun lowerBound(key: String): Int {
        var lo = 0; var hi = words.size
        while (lo < hi) { val mid = (lo + hi) / 2; if (words[mid] < key) lo = mid + 1 else hi = mid }
        return lo
    }

    private class Hit(val d: Int, val whole: Boolean, val f: Int, val i: Int)

    fun corrections(low: String, limit: Int = EnglishAssist.TYPO_LIMIT): List<String> {
        val n = low.length
        if (n < EnglishAssist.TYPO_MIN_LEN) return emptyList()
        val maxD = if (n >= EnglishAssist.TYPO_LONG_LEN) 2 else 1
        val a = words
        val first = low[0]
        val start = lowerBound(first.toString())
        val end = if (first >= 'z') a.size else lowerBound((first + 1).toString())
        val hits = ArrayList<Hit>()
        val rows = IntArray(3 * (n + 1))
        val out = IntArray(2)
        for (i in start until end) {
            val f = freq[i]
            if (f < EnglishAssist.TYPO_MIN_FREQ) continue
            val w = a[i]
            val m = w.length
            if (m < n - maxD) continue
            EnglishAssist.distance(w, low, maxD, rows, out)
            val full = out[0]; val prefix = out[1]
            if (full in 1..maxD) hits.add(Hit(full, true, f, i))
            else if (m > n && prefix in 1..maxD) hits.add(Hit(prefix, false, f, i))
        }
        hits.sortWith { x, y ->
            when {
                x.whole != y.whole -> if (x.whole) -1 else 1
                x.d != y.d -> x.d - y.d
                x.f != y.f -> y.f - x.f
                else -> x.i - y.i
            }
        }
        return hits.take(limit).map { a[it.i] }
    }

    companion object {
        fun parse(buf: java.nio.ByteBuffer): LegacyEnglishLexicon? {
            val b = ByteArray(buf.capacity())
            val d = buf.duplicate(); d.position(0); d.get(b)
            if (b.size < 8 || b[0] != 0x56.toByte() || b[1] != 0x54.toByte() || b[2] != 0x45.toByte() || b[3] != 0x31.toByte()) return null
            val n = (b[4].toInt() and 255) or ((b[5].toInt() and 255) shl 8) or
                ((b[6].toInt() and 255) shl 16) or ((b[7].toInt() and 255) shl 24)
            val words = arrayOfNulls<String>(n)
            val freq = IntArray(n)
            val keys = ByteArray(b.size)
            val keyStart = IntArray(n + 1)
            val first = IntArray(n); val last = IntArray(n)
            var kc = 0
            var p = 8
            for (i in 0 until n) {
                if (p + 2 > b.size) return null
                val len = b[p].toInt() and 255
                val f = b[p + 1].toInt() and 255
                if (len == 0 || p + 2 + len > b.size) return null
                var prev = -1
                for (j in 0 until len) {
                    val k = (b[p + 2 + j].toInt() and 255) - 97
                    if (k !in 0 until 26) return null
                    if (k != prev) { keys[kc++] = k.toByte(); prev = k }
                }
                first[i] = keys[keyStart[i]].toInt(); last[i] = keys[kc - 1].toInt()
                keyStart[i + 1] = kc
                words[i] = String(b, p + 2, len, Charsets.US_ASCII)
                freq[i] = f
                p += 2 + len
            }
            val bucketStart = IntArray(677)
            for (i in 0 until n) bucketStart[first[i] * 26 + last[i] + 1]++
            for (bk in 0 until 676) bucketStart[bk + 1] += bucketStart[bk]
            val fill = bucketStart.copyOf(676)
            val order = IntArray(n)
            for (i in 0 until n) { val bk = first[i] * 26 + last[i]; order[fill[bk]++] = i }
            @Suppress("UNCHECKED_CAST")
            return LegacyEnglishLexicon(words as Array<String>, freq, keys.copyOf(kc), keyStart, order, bucketStart)
        }
    }
}
