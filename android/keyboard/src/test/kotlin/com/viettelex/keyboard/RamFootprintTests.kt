package com.viettelex.keyboard

import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.lang.management.ManagementFactory

/**
 * Đo RAM (JVM, xấp xỉ ART): heap GIỮ LẠI của từng cấu trúc dữ liệu bàn phím + byte cấp phát
 * mỗi phím trên đường nóng. In số cho android/docs/RAM-AUDIT.md; [fixedFootprints] chốt ngưỡng các fix.
 *
 * Chạy: `VT_SLOW_TESTS=1 ./gradlew --offline :keyboard:test --tests '*RamFootprintTests*' -i | grep RAM`
 *
 * Retained = chênh used-heap sau GC trước/sau khi dựng (giữ tham chiếu). JVM HotSpot 64-bit
 * compressed oops ≈ ART (header 8–12 B, ref 4 B); String Latin-1 compact như ART ⇒ sai số ±15 %.
 */
class RamFootprintTests {
    @Before fun setUp() = TestAssets.install()

    private fun used(): Long {
        val rt = Runtime.getRuntime()
        var last = Long.MAX_VALUE
        repeat(6) {
            System.gc(); Thread.sleep(40)
            val u = rt.totalMemory() - rt.freeMemory()
            if (u < last) last = u
        }
        return last
    }

    private val keep = ArrayList<Any?>()

    /** In + trả (KB giữ lại, MB cấp phát lúc dựng). */
    private fun retained(label: String, build: () -> Any?): Pair<Double, Double> {
        val before = used()
        val t0 = System.nanoTime(); val a0 = allocated()
        keep += build()
        val ms = (System.nanoTime() - t0) / 1e6; val garbage = allocated() - a0
        val after = used()
        println(String.format("RAM retained %-34s %8.1f KB  (build %.0f ms, cấp phát tạm %.1f MB)",
            label, (after - before) / 1024.0, ms, garbage / 1_048_576.0))
        return (after - before) / 1024.0 to garbage / 1_048_576.0
    }

    /**
     * Ngưỡng sau các fix RAM-AUDIT #1/#3/#6/#7 (JVM ≈ ART ±15 %): trie chọn phím thông minh đọc
     * asset mmap (trước: 0.86 MB giữ + 31 MB rác mỗi lần dựng); từ điển Anh / FUTO nhả được.
     */
    @Test fun fixedFootprints() {
        SlowTests.assume()
        TelexKeyPrior.release()
        val (kpKeep, kpGarbage) = retained("TelexKeyPrior.warmUp (asset mmap)") { TelexKeyPrior.warmUp() }
        assertTrue("trie mmap không vào heap: $kpKeep KB", kpKeep < 64)
        assertTrue("trie mmap không dựng rác: $kpGarbage MB", kpGarbage < 0.5)

        fun freed(label: String, load: () -> Any?, release: () -> Unit): Double {
            val base = used()
            load(); val loaded = used()
            release(); val after = used()
            println(String.format("RAM release %-35s nạp +%.1f KB, nhả còn +%.1f KB", label, (loaded - base) / 1024.0, (after - base) / 1024.0))
            return (after - base) / 1024.0
        }
        SwipeEnglish.release()
        assertTrue("SwipeEnglish.release trả heap", freed("SwipeEnglish.lexicon", { SwipeEnglish.lexicon }, SwipeEnglish::release) < 150)
        val f = FutoSwipe { KeyboardData.buffer(Keys.ASSET_FUTO) }
        assertTrue("FutoSwipe.release trả weights", freed("FutoSwipe model", { f.load() }, f::release) < 150)
        EmojiData.releaseCategories()
        assertTrue("emoji categories nhả được", freed("EmojiData.categories", { EmojiData.categories }, EmojiData::releaseCategories) < 60)
    }

    /**
     * RAM-AUDIT #7 (10/11/2026): enlexicon tại chỗ (IntArray vị trí) vs bản cũ (~20k String + bảng
     * vuốt dựng ngay). Bảng vuốt chỉ dựng khi vuốt tiếng Anh bật ⇒ đo riêng.
     */
    @Test fun englishLexiconInPlace() {
        SlowTests.assume()
        val buf = KeyboardData.buffer(Keys.ASSET_EN_LEXICON)
        repeat(3) { LegacyEnglishLexicon.parse(buf); SwipeEnglish.parse(buf)!!.swipe }   // JIT
        val (oldKeep, oldGarbage) = retained("enlexicon CŨ (String + bảng vuốt)") { LegacyEnglishLexicon.parse(buf) }
        val (newKeep, newGarbage) = retained("enlexicon tại chỗ (chỉ offsets)") { SwipeEnglish.parse(buf) }
        val lex = SwipeEnglish.parse(buf)!!
        val (swKeep, swGarbage) = retained("enlexicon .swipe (vuốt tiếng Anh)") { lex.swipe }
        println(String.format("RAM enlexicon count=%d: cũ %.1f KB (+%.2f MB rác) → mới %.1f KB (+%.2f MB rác); bảng vuốt %.1f KB (+%.2f MB rác)",
            lex.count, oldKeep, oldGarbage, newKeep, newGarbage, swKeep, swGarbage))
        fun ms(n: Int, f: () -> Unit): Double { val t = System.nanoTime(); repeat(n) { f() }; return (System.nanoTime() - t) / 1e6 / n }
        println(String.format("RAM enlexicon nạp: cũ %.2f ms, mới %.2f ms, bảng vuốt %.2f ms",
            ms(20) { LegacyEnglishLexicon.parse(buf) }, ms(20) { SwipeEnglish.parse(buf) }, ms(20) { SwipeEnglish.parse(buf)!!.swipe }))
        val old = LegacyEnglishLexicon.parse(buf)!!
        val words = (0 until lex.count step 7).map { lex.word(it) } + (0 until lex.count step 7).map { lex.word(it) + "q" }
        repeat(3) { for (w in words) { old.indexOf(w); lex.indexOf(w) } }
        val tOld = ms(5) { for (w in words) old.indexOf(w) } / words.size * 1e6
        val tNew = ms(5) { for (w in words) lex.indexOf(w) } / words.size * 1e6
        println(String.format("RAM enlexicon indexOf: cũ %.0f ns, mới %.0f ns", tOld, tNew))
        assertTrue("tại chỗ giữ ≤ ~100 KB: $newKeep", newKeep < 160)
        assertTrue("không dựng String: $newGarbage MB", newGarbage < 0.3)
    }

    private val mx = ManagementFactory.getThreadMXBean() as com.sun.management.ThreadMXBean
    private fun allocated() = mx.getThreadAllocatedBytes(Thread.currentThread().id)

    @Test fun retainedFootprint() {
        SlowTests.assume()
        retained("VNLexicon2 offsets (blob)") { VNLexicon2Data.blob }
        retained("SyllableLM.shared (mmap)") { SyllableLM.shared }
        retained("EmojiSuggest (mmap)") { EmojiSuggest.emojis("vui") }
        retained("UserLangModel seeded") { UserLangModel().also { it.seedIfEmpty() } }
        retained("UserLangModel full caps") {
            UserLangModel().also { m ->
                m.isKnownWord = { true }
                var prev: String? = null; var prev2: String? = null
                // từ thật (vnlexicon), 2 thứ tự khác nhau × lặp 4 lần ⇒ chạm UNI/BI/TRI cap như máy dùng lâu
                val n = VNLexicon2Data.count
                for (order in intArrayOf(7919, 104729)) repeat(4) {
                    for (i in 0 until 3200) {
                        val w = VNSuggest.display((i.toLong() * order % n).toInt()).lowercase()
                        m.record(w, prev, prev2); prev2 = prev; prev = w
                    }
                }
                println("RAM userlm uni=${m.uniSize}")
            }
        }
        retained("TelexKeyPrior.fromLexicon (tham chiếu)") { TelexKeyPrior.fromLexicon() }
        retained("TelexKeyPrior.fromAsset (IME, mmap)") { TelexKeyPrior.fromAsset() }
        retained("SwipeLexicon.forms") { SwipeLexicon.forms }
        retained("SwipeDecoder templates") {
            SwipeDecoder().also { it.setLayout(SwipeLayout.qwerty(keyWidth = 108f, rowHeight = 150f)); it.prepare() }
        }
        retained("SwipeEnglish.lexicon") { SwipeEnglish.lexicon }
        retained("FutoSwipeModel fp16→FloatArray") { FutoSwipeModel.load(KeyboardData.buffer(Keys.ASSET_FUTO)) }
        retained("EmojiData.categories (strings)") { EmojiData.categories }
        retained("EmojiData.kaomoji") { EmojiData.kaomoji }
        retained("EmojiSearch index + 1 query") { EmojiSearch.search("tim") }
        println("RAM keep=${keep.size}")
    }

    @Test fun allocationPerKey() {
        SlowTests.assume()
        val text = "xin chaof cacs banj hoom nay trowif ddepj quas tooi ddi hocj tieengs vieetj "
        fun run(settings: KeyboardSettings, label: String, suggest: Boolean) {
            val s = KeyboardSession(UserLangModel(), NoClip)
            s.startInput(settings, FieldTraits(capSentences = true))
            val p = MockProxy()
            fun burst(n: Int) {
                for (i in 0 until n) {
                    val c = text[i % text.length]
                    s.handle(if (c == ' ') Key.Space else Key.Letter(c), p)
                    s.updateAutoShift(p)
                    if (suggest) s.suggestionsNow(p)
                    // IcProxy giữ ≤ CONTEXT_CAP (256) ký tự trước con trỏ — mô phỏng cỡ đó
                    if (p.sb.length > 256) p.sb.delete(0, p.sb.length - 200)
                }
            }
            burst(3000)   // JIT + cache
            val a0 = allocated(); val n = 5000
            burst(n)
            val per = (allocated() - a0).toDouble() / n
            println(String.format("RAM alloc/key %-28s %8.0f B/key  (%.1f MB / 1000 phím)", label, per, per * 1000 / 1_048_576))
            if (!System.getenv("VT_JFR").isNullOrEmpty()) jfrTop(label) { burst(20_000) }
        }
        run(KeyboardSettings(), "default + suggestions", true)
        run(KeyboardSettings(), "engine only (no bar)", false)
        run(KeyboardSettings().apply { showSuggestions = false; liveSpellCheck = false; autoFixAdjacent = false },
            "all off", false)
    }

    /** JFR ObjectAllocationSample: gộp trọng số theo frame đầu tiên thuộc com.viettelex (VT_JFR=1). */
    private fun jfrTop(label: String, body: () -> Unit) {
        val rec = jdk.jfr.Recording()
        rec.enable("jdk.ObjectAllocationSample").withStackTrace().with("throttle", "20000/s")
        rec.start(); body(); rec.stop()
        val f = java.io.File.createTempFile("vt-alloc", ".jfr"); rec.dump(f.toPath()); rec.close()
        val bySite = HashMap<String, Long>(); val byType = HashMap<String, Long>()
        var total = 0L
        for (e in jdk.jfr.consumer.RecordingFile.readAllEvents(f.toPath())) {
            if (e.eventType.name != "jdk.ObjectAllocationSample") continue
            if (e.thread?.javaThreadId != Thread.currentThread().id) continue
            val w = e.getLong("weight"); total += w
            val frames = e.stackTrace?.frames ?: continue
            val site = frames.firstOrNull { it.method.type.name.startsWith("com.viettelex") && !it.method.type.name.contains("RamFootprint") }
            val key = site?.let { "${it.method.type.name.substringAfterLast('.')}.${it.method.name}:${it.lineNumber}" } ?: "?"
            bySite.merge(key, w, Long::plus)
            byType.merge(e.getClass("objectClass").name, w, Long::plus)
        }
        f.delete()
        println("RAM jfr [$label] top sites (share of sampled bytes):")
        bySite.entries.sortedByDescending { it.value }.take(15).forEach {
            println(String.format("RAM jfr   %5.1f%%  %s", 100.0 * it.value / total, it.key))
        }
        byType.entries.sortedByDescending { it.value }.take(8).forEach {
            println(String.format("RAM jfr   type %5.1f%%  %s", 100.0 * it.value / total, it.key))
        }
    }

    private object NoClip : ClipboardSource {
        override val changeCount = 0
        override fun hasText() = false
        override fun readText(): String? = null
    }
}
