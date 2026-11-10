package com.viettelex.keyboard

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.io.File
import java.util.Locale

/**
 * Gõ vuốt giai đoạn 3 — từ tiếng Anh xen câu Việt. Cùng bộ ca với
 * iOS/KeyboardTests/SwipeEnglishTests.swift; fixture parity: Fixtures/swipe-paths-en.txt.
 */
class SwipeEnglishTests {
    @Before fun setUp() = TestAssets.install()

    private val layout = SwipeLayout.qwerty(keyWidth = 40f, rowHeight = 54f)
    private fun decoder() = SwipeDecoder().also { it.setLayout(layout) }

    /** n từ tiếng Anh phổ biến nhất (≥ 2 phím sau gộp lặp), tần suất giảm dần rồi chữ cái. */
    private fun englishCorpus(n: Int = 1000): List<String> {
        val e = SwipeEnglish.lexicon
        return (0 until e.count)
            .filter { SwipeSim.collapse(e.word(it)).length >= 2 }
            .sortedWith(compareBy({ -e.freq(it) }, { e.word(it) }))
            .take(n).map { e.word(it) }
    }

    /** 500 dạng Việt phổ biến nhất — cùng bộ SwipeDecoderTests. */
    private fun vnCorpus(n: Int = 500): List<String> {
        val f = SwipeLexicon.forms
        return (0 until f.count)
            .filter { SwipeSim.collapse(f.folded[it]).length >= 2 }
            .sortedWith(compareBy({ -f.freq[it] }, { f.folded[it] }))
            .take(n).map { f.folded[it] }
    }

    private fun enAccuracy(d: SwipeDecoder, words: List<String>, prior: SwipeEnglishPrior, seed: Long = 42,
                           sigma: Double = 0.25): Pair<Double, Double> {
        val sim = SwipeSim(seed)
        var t1 = 0; var t3 = 0
        for (w in words) {
            val r = d.decode(sim.path(w, layout, sigma), 3, context = null, english = prior)
            if (r.firstOrNull()?.let { it.lang == SwipeLang.EN && it.folded == w } == true) t1++
            if (r.any { it.lang == SwipeLang.EN && it.folded == w }) t3++
        }
        return t1.toDouble() / words.size to t3.toDouble() / words.size
    }

    private fun vnAccuracy(d: SwipeDecoder, words: List<String>, prior: SwipeEnglishPrior?, seed: Long,
                           sigma: Double = 0.25, endOffset: Double = 0.0): Pair<Double, Double> {
        val sim = SwipeSim(seed)
        var t1 = 0; var t3 = 0
        for (w in words) {
            val r = d.decode(sim.path(w, layout, sigma, endOffset), 3, context = null, english = prior)
            if (r.firstOrNull()?.let { it.lang == SwipeLang.VI && it.folded == w } == true) t1++
            if (r.any { it.lang == SwipeLang.VI && it.folded == w }) t3++
        }
        return t1.toDouble() / words.size to t3.toDouble() / words.size
    }

    @Test fun lexiconLoadsAndBuckets() {
        val l = SwipeEnglish.lexicon
        val e = l.swipe
        assertTrue("${e.count}", e.count in 10_000..20_100)   // 20.000 + SUPPLEMENT của gen-enlexicon
        assertTrue(SwipeEnglish.contains("check") && SwipeEnglish.contains("mail") && SwipeEnglish.contains("the"))
        assertTrue(!SwipeEnglish.contains("a") && !SwipeEnglish.contains("fuck"))   // 1 chữ / tục bị lọc
        assertEquals(e.count, e.bucketStart[676])
        // hello → phím gộp lặp "helo"
        val i = SwipeEnglish.indexOf("hello")
        val keys = (e.keyStart[i] until e.keyStart[i + 1]).map { ('a' + e.keys[it].toInt()) }.joinToString("")
        assertEquals("helo", keys)
    }

    @Test fun classifyContext() {
        assertEquals(SwipeLangContext.Kind.VI, SwipeLangContext.classify("tôi"))
        assertEquals(SwipeLangContext.Kind.EN, SwipeLangContext.classify("check"))
        assertEquals(SwipeLangContext.Kind.EN, SwipeLangContext.classify("The"))       // mở mạch (EnglishContextWords)
        assertEquals(SwipeLangContext.Kind.NEUTRAL, SwipeLangContext.classify("email")) // từ mượn: giữ mạch
        assertEquals(SwipeLangContext.Kind.VI, SwipeLangContext.classify("anh"))
        assertEquals(SwipeLangContext.Kind.NEUTRAL, SwipeLangContext.classify(null))
        assertEquals(SwipeLangContext.Kind.EN, SwipeLangContext.classify("thế", swipedEnglish = true))
        assertEquals(SwipeLangContext.ENGLISH, SwipeLangContext.prior(SwipeLangContext.Kind.EN, SwipeLangContext.Kind.VI))
        assertEquals(SwipeLangContext.DEFAULT, SwipeLangContext.prior(SwipeLangContext.Kind.NEUTRAL, SwipeLangContext.Kind.NEUTRAL))
    }

    /** Tiền nghiệm liên tục ngôn ngữ (SwipeLangContext.prior(kinds)) — cùng ca với bản Swift. */
    @Test fun continuityPrior() {
        val V = SwipeLangContext.Kind.VI; val E = SwipeLangContext.Kind.EN; val N = SwipeLangContext.Kind.NEUTRAL
        fun p(vararg k: SwipeLangContext.Kind) = SwipeLangContext.prior(k.toList())
        // không có ngữ cảnh / toàn trung tính / mạch Việt ⇒ y hệt DEFAULT (từ rời không đổi)
        assertEquals(SwipeLangContext.DEFAULT, p())
        assertEquals(SwipeLangContext.DEFAULT, p(N, N, N))
        assertEquals(SwipeLangContext.DEFAULT, p(V))
        assertEquals(SwipeLangContext.DEFAULT, p(V, V, V))
        // một từ Anh liền trước ⇒ ENGLISH; mạch dài hơn ⇒ mạnh hơn, có trần
        assertEquals(SwipeLangContext.ENGLISH, p(E))
        assertEquals(SwipeLangContext.ENGLISH, p(E, V, E))                  // từ Việt cắt mạch
        assertEquals(0.5f, p(E, E).bias, 1e-4f)
        assertEquals(0.68f, p(E, E, E).bias, 1e-4f)
        assertEquals(0f, p(E, E, E).margin, 0f)
        assertTrue(p(E, E, E, E).bias <= p(E, E, E).bias + 1e-6f)          // chỉ xét 3 từ
        // từ Anh cách một từ trung tính: nghiêng Anh vừa phải, nội suy giữa DEFAULT và ENGLISH
        val far = p(N, E)
        assertTrue(far.bias > SwipeLangContext.DEFAULT.bias && far.bias < SwipeLangContext.ENGLISH.bias)
        assertTrue(far.margin > 0f && far.margin < SwipeLangContext.DEFAULT.margin)
        assertTrue(p(N, E, E).bias > far.bias)
        // từ Việt liền trước cắt mạch Anh phía xa ("check mail cho …")
        assertEquals(SwipeLangContext.DEFAULT, p(V, E, E))
        // trần: bias Anh không vượt enBias + enGain·(enCap − 1)
        val c = SwipeLangContext.CONTINUITY
        assertTrue(p(E, E, E).bias <= c.enBias + c.enGain * (c.enCap - 1f) + 1e-6f)
    }

    @Test fun continuityKinds() {
        val V = SwipeLangContext.Kind.VI; val E = SwipeLangContext.Kind.EN; val N = SwipeLangContext.Kind.NEUTRAL
        val none: (String?) -> Boolean = { false }
        // đã chốt "tôi thích check" (cũ → mới) ⇒ gần nhất trước
        assertEquals(listOf(E, V, V), SwipeLangContext.kinds(false, null, false, listOf("tôi", "thích", "check"), none))
        // đang soạn từ mới ⇒ đứng đầu, tối đa 3
        assertEquals(listOf(V, E, V), SwipeLangContext.kinds(true, "này", false, listOf("tôi", "thích", "check"), none))
        // đang soạn nhưng không học được (số…) ⇒ trung tính, vẫn tính khoảng cách
        assertEquals(listOf(N, E), SwipeLangContext.kinds(true, null, false, listOf("check"), none))
        // nhãn "vừa vuốt ra như tiếng Anh" thắng từ điển ("the" vuốt Anh)
        assertEquals(listOf(E), SwipeLangContext.kinds(false, null, false, listOf("to"), { it == "to" }))
        assertEquals(listOf(E), SwipeLangContext.kinds(true, "can", true, emptyList(), none))
        assertEquals(emptyList<SwipeLangContext.Kind>(), SwipeLangContext.kinds(false, null, false, emptyList(), none))
    }

    /** Đường sạch qua tâm phím (sigma 0). */
    private fun clean(w: String) = SwipeSim(1).path(w, layout, 0.0, jitter = 0.0)

    @Test fun collisionPrefersVietnameseAndOffersEnglish() {
        val d = decoder()
        // sau "tôi" (Việt): "the" → dạng Việt "the" (thế) top-1, "the" tiếng Anh vẫn trong danh sách
        val prior = SwipeLangContext.prior(SwipeLangContext.classify("tôi"), SwipeLangContext.Kind.NEUTRAL)
        val r = d.decode(clean("the"), 5, context = null, english = prior)
        assertEquals(SwipeCandidate::class, r[0]::class)
        assertEquals("the", r[0].folded); assertEquals(SwipeLang.VI, r[0].lang)
        assertTrue(r.toString(), r.any { it.lang == SwipeLang.EN && it.folded == "the" })
        // trong mạch tiếng Anh ("check") vuốt "mail" → mail
        val en = SwipeLangContext.prior(SwipeLangContext.classify("check"), SwipeLangContext.Kind.VI)
        val m = d.decode(clean("mail"), 5, context = null, english = en)
        assertEquals("mail", m[0].folded); assertEquals(SwipeLang.EN, m[0].lang)
        assertTrue(m.toString(), m.any { it.lang == SwipeLang.VI })            // phương án chéo
        // chữ lặp: hello, good
        for (w in listOf("hello", "good", "meeting", "check", "file")) {
            val h = d.decode(clean(w), 5, context = null, english = SwipeLangContext.ENGLISH)
            assertTrue("$w: $h", h.any { it.lang == SwipeLang.EN && it.folded == w })
        }
    }

    @Test fun arbitrateMarginAndCrossLanguage() {
        val en = SwipeCandidate("the", 3.0f, SwipeLang.EN)
        val vi = SwipeCandidate("the", 2.7f)
        val vi2 = SwipeCandidate("tha", 2.0f)
        assertEquals(listOf(vi, en), SwipeDecoder.arbitrate(listOf(en, vi), 2, 0.5f))      // kém < margin ⇒ Việt lên
        assertEquals(listOf(en, vi), SwipeDecoder.arbitrate(listOf(en, vi), 2, 0.2f))      // thắng rõ ⇒ giữ
        assertEquals(listOf(en, vi), SwipeDecoder.arbitrate(listOf(en, vi), 2, 0f))
        // top-K toàn tiếng Việt ⇒ phần tử cuối nhường cho tiếng Anh tốt nhất
        assertEquals(listOf(vi, vi2, en), SwipeDecoder.arbitrate(listOf(vi, vi2, en), 2, 0.5f))
    }

    /** Kết quả câu trộn: đúng ngôn ngữ top-1, đúng từ top-1, đúng từ trong top-3 (trên n từ). */
    private data class Mixed(val lang: Int, val top1: Int, val top3: Int, val n: Int, val enTop1: Int, val enTop3: Int, val enN: Int)

    /** Câu trộn: mỗi từ vuốt (σ 0.25) với ngữ cảnh = 2 từ đã ra trước đó (như tích hợp). */
    private fun sentenceAccuracy(d: SwipeDecoder, sentences: List<List<Pair<String, SwipeLang>>>,
                                 trials: Int = 10): Mixed {
        var lang = 0; var t1 = 0; var t3 = 0; var n = 0; var e1 = 0; var e3 = 0; var en = 0
        val sim = SwipeSim(77)
        repeat(trials) {
            for (s in sentences) {
                var p1: SwipeLangContext.Kind = SwipeLangContext.Kind.NEUTRAL
                var p2: SwipeLangContext.Kind = SwipeLangContext.Kind.NEUTRAL
                for ((w, l) in s) {
                    val r = d.decode(sim.path(w, layout, 0.25), 5, context = null, english = SwipeLangContext.prior(p1, p2))
                    val top = r.first()
                    n++
                    if (top.lang == l) lang++
                    val hit1 = top.folded == w && top.lang == l
                    val hit3 = r.take(3).any { it.folded == w && it.lang == l } ||
                        r.any { it.folded == w && it.lang == l && it.lang != top.lang }   // slot chéo ngôn ngữ
                    if (hit1) t1++
                    if (hit3) t3++
                    if (l == SwipeLang.EN) { en++; if (hit1) e1++; if (hit3) e3++ }
                    if (!hit1 && System.getenv("SWIPE_DEBUG") == "1") println("MISS $w/$l ← ${r.take(3)} p1=$p1")
                    // từ Việt vuốt ra đã bung dấu ⇒ Việt; từ Anh mang nhãn EN
                    p2 = p1
                    p1 = if (top.lang == SwipeLang.EN) SwipeLangContext.Kind.EN else SwipeLangContext.Kind.VI
                }
            }
        }
        return Mixed(lang, t1, t3, n, e1, e3, en)
    }

    private val V = SwipeLang.VI
    private val E = SwipeLang.EN
    private val mixed = listOf(
        listOf("minh" to V, "dang" to V, "check" to E, "mail" to E),
        listOf("gui" to V, "file" to E, "cho" to V, "anh" to V),
        listOf("the" to V, "end" to E),                       // đầu câu trùng chuỗi ⇒ ưu tiên thế
        listOf("em" to V, "gui" to V, "email" to E, "cho" to V, "sep" to V),
        listOf("toi" to V, "nay" to V, "co" to V, "meeting" to E, "khong" to V),
        listOf("update" to E, "app" to E, "chua" to V),
        listOf("share" to E, "link" to E, "cho" to V, "minh" to V),
        listOf("deadline" to E, "la" to V, "thu" to V, "sau" to V),
    )

    @Test fun measureEnglishAndVietnamese() {
        SlowTests.assume()
        val d = decoder()
        val en = englishCorpus()
        val vn = vnCorpus()
        val (e1d, e3d) = enAccuracy(d, en, SwipeLangContext.DEFAULT)
        val (e1e, e3e) = enAccuracy(d, en, SwipeLangContext.ENGLISH)
        val (b1, b3) = vnAccuracy(d, vn, null, 42)
        val (v1, v3) = vnAccuracy(d, vn, SwipeLangContext.DEFAULT, 42)
        val (bb1, _) = vnAccuracy(d, vn, null, 7, sigma = 0.3)
        val (vb1, _) = vnAccuracy(d, vn, SwipeLangContext.DEFAULT, 7, sigma = 0.3)
        val (bc1, _) = vnAccuracy(d, vn, null, 42, endOffset = 0.5)
        val (vc1, _) = vnAccuracy(d, vn, SwipeLangContext.DEFAULT, 42, endOffset = 0.5)
        val mx = sentenceAccuracy(d, mixed)
        println(String.format(Locale.ROOT,
            "SWIPE-EN top1000 Anh: ngữ cảnh Việt top1 %.3f top3 %.3f | mạch Anh top1 %.3f top3 %.3f", e1d, e3d, e1e, e3e))
        println(String.format(Locale.ROOT,
            "SWIPE-EN top500 Việt σ0.25: tắt EN %.3f/%.3f → bật EN %.3f/%.3f | σ0.3 %.3f→%.3f | lệch 0.5 %.3f→%.3f",
            b1, b3, v1, v3, bb1, vb1, bc1, vc1))
        println(String.format(Locale.ROOT,
            "SWIPE-EN câu trộn (%d từ): đúng ngôn ngữ %d, đúng từ top1 %d top3 %d | riêng %d từ Anh: top1 %d top3 %d",
            mx.n, mx.lang, mx.top1, mx.top3, mx.enN, mx.enTop1, mx.enTop3))
        assertTrue("VN top1 giảm quá 1 điểm: $b1 → $v1", v1 >= b1 - 0.01)
        assertTrue("VN σ0.3 giảm quá 1 điểm: $bb1 → $vb1", vb1 >= bb1 - 0.01)
        assertTrue("VN lệch 0.5 giảm quá 1 điểm: $bc1 → $vc1", vc1 >= bc1 - 0.01)
        assertTrue(v1 >= 0.85 && v3 >= 0.98)
        assertTrue("EN mạch Anh top3 $e3e", e3e >= 0.85)
        assertTrue("EN mạch Anh top1 $e1e", e1e >= 0.65)
        assertTrue("EN ngữ cảnh Việt top3 $e3d", e3d >= 0.80)
        assertTrue("câu trộn đúng ngôn ngữ $mx", mx.lang >= mx.n * 0.9)
        assertTrue("câu trộn từ Anh top3 $mx", mx.enTop3 >= mx.enN * 0.9)
    }

    /** Quét hằng số (chỉ khi SWIPE_SWEEP=1) — cách đã chọn DEFAULT/ENGLISH. */
    @Test fun sweepPriors() {
        if (System.getenv("SWIPE_SWEEP") != "1") return
        val d = decoder()
        val en = englishCorpus(); val vn = vnCorpus()
        val coll = en.filter { SwipeLexicon.indexOf(it) >= 0 }
        for (bias in listOf(-0.3f, -0.6f, -0.9f, -1.2f, -1.5f)) for (margin in listOf(0.3f, 0.6f, 0.9f)) {
            val pr = SwipeEnglishPrior(bias, margin)
            val (e1, e3) = enAccuracy(d, en, pr)
            val (v1, v3) = vnAccuracy(d, vn, pr, 42)
            val collVi = coll.count { d.decode(clean(it), 3, context = null, english = pr).first().lang == SwipeLang.VI }
            println(String.format(Locale.ROOT, "SWEEP bias %.1f margin %.1f: EN %.3f/%.3f VN %.3f/%.3f trùng→Việt %d/%d",
                bias, margin, e1, e3, v1, v3, collVi, coll.size))
        }
        for (bias in listOf(0.0f, 0.2f, 0.3f, 0.5f, 0.6f)) {
            val pr = SwipeEnglishPrior(bias, 0f)
            val (e1, e3) = enAccuracy(d, en, pr)
            val (v1, v3) = vnAccuracy(d, vn, pr, 42)
            println(String.format(Locale.ROOT, "SWEEP-EN bias %.1f: EN %.3f/%.3f VN %.3f/%.3f", bias, e1, e3, v1, v3))
        }
    }

    @Test fun benchmarkWithEnglish() {
        SlowTests.assume()
        val d = decoder()
        d.prepare()
        val t0 = System.nanoTime(); SwipeEnglish.lexicon; val load = (System.nanoTime() - t0) / 1e6
        val sim = SwipeSim(11)
        val paths = (vnCorpus(100) + englishCorpus(100)).map { sim.path(it, layout) }
        repeat(3) { for (p in paths) d.decode(p, 5, context = null, english = SwipeLangContext.DEFAULT) }
        val t1 = System.nanoTime()
        for (p in paths) d.decode(p, 5, context = null, english = SwipeLangContext.DEFAULT)
        val per = (System.nanoTime() - t1) / 1e6 / paths.size
        val t2 = System.nanoTime()
        for (p in paths) d.decode(p, 5)
        val base = (System.nanoTime() - t2) / 1e6 / paths.size
        println(String.format(Locale.ROOT, "SWIPE-EN benchmark JVM: nạp từ điển %.1f ms, decode %.3f ms/đường (không EN %.3f)",
            load, per, base))
        assertTrue("decode $per ms", per < 8.0)
    }

    // ---- Fixture parity Swift ↔ Kotlin ----

    private fun fixtureFile(): File =
        listOf("../../iOS", "../iOS", "iOS").map { File(it, "KeyboardTests/Fixtures/swipe-paths-en.txt") }
            .firstOrNull { it.parentFile.exists() } ?: error("không thấy iOS/KeyboardTests/Fixtures")

    private fun priorOf(tag: String) = if (tag == "en") SwipeLangContext.ENGLISH else SwipeLangContext.DEFAULT

    /** Ghi lại: SWIPE_WRITE_FIXTURE=1 ./gradlew :keyboard:test --tests '*SwipeEnglishTests*'. */
    @Test fun fixtureParity() {
        val d = decoder()
        val file = fixtureFile()
        if (System.getenv("SWIPE_WRITE_FIXTURE") == "1") {
            val sim = SwipeSim(2027)
            val sb = StringBuilder("# swipe-paths-en v1 — layout qwerty(keyWidth 40, rowHeight 54). " +
                "Sinh bởi SwipeEnglishTests.kt (SWIPE_WRITE_FIXTURE=1). word<TAB>prior vi|en<TAB>top1 lang:word<TAB>x,y;x,y…\n")
            val cases = englishCorpus(60).map { it to "vi" } + englishCorpus(60).map { it to "en" } +
                vnCorpus(40).map { it to "vi" } +
                listOf("the", "can", "to", "me", "long", "chat", "song", "top", "hot", "hello", "good").map { it to "vi" }
            for ((w, tag) in cases) {
                val p = sim.path(w, layout, 0.25)
                val xs = FloatArray(p.count) { String.format(Locale.ROOT, "%.2f", p.xs[it]).toFloat() }
                val ys = FloatArray(p.count) { String.format(Locale.ROOT, "%.2f", p.ys[it]).toFloat() }
                val top = d.decode(xs, ys, p.count, 3, context = null, english = priorOf(tag)).first()
                sb.append(w).append('\t').append(tag).append('\t')
                    .append(if (top.lang == SwipeLang.EN) "en:" else "vi:").append(top.folded).append('\t')
                for (i in 0 until p.count) {
                    if (i > 0) sb.append(';')
                    sb.append(String.format(Locale.ROOT, "%.2f,%.2f", xs[i], ys[i]))
                }
                sb.append('\n')
            }
            file.writeText(sb.toString())
        }
        var n = 0; var same = 0
        for (line in file.readLines()) {
            if (line.startsWith("#") || line.isBlank()) continue
            val (_, tag, top, pts) = line.split('\t')
            val pp = pts.split(';').map { it.split(',') }
            val xs = FloatArray(pp.size) { pp[it][0].toFloat() }
            val ys = FloatArray(pp.size) { pp[it][1].toFloat() }
            n++
            val r = d.decode(xs, ys, xs.size, 3, context = null, english = priorOf(tag)).first()
            if ((if (r.lang == SwipeLang.EN) "en:" else "vi:") + r.folded == top) same++
        }
        assertTrue(n >= 150)
        assertEquals("top-1 khớp fixture", n, same)
    }
}
