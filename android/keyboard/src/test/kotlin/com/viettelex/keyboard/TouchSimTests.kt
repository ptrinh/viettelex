package com.viettelex.keyboard

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.util.Random

/**
 * Chọn phím theo ngữ cảnh (TouchTarget) — đo bằng mô phỏng gõ chạm (TouchSim).
 * Test thường: hợp đồng + số đo rút gọn làm hồi quy (câu Tatoeba giữ lại, nửa TEST).
 * TOUCHSIM=1: bảng đầy đủ (TEST, 3 seed, 2 hình học); TOUCHSIM_TUNE=1: dò tham số trên DEV.
 */
class TouchSimTests {
    @Before fun setUp() = TestAssets.install()

    private val g = TouchSim.Geo()
    private val all by lazy { TouchSim.heldout() }
    private val dev by lazy { all.filterIndexed { i, _ -> i % 2 == 0 } }
    private val test by lazy { all.filterIndexed { i, _ -> i % 2 == 1 } }
    private val prior by lazy { TelexKeyPrior.fromLexicon() }
    private val careful = TouchSim.PROFILES[0]
    private val mid = TouchSim.PROFILES[1]

    private fun wer(st: TouchSim.Stats) = 100.0 * st.wordErr / st.words
    private fun ter(st: TouchSim.Stats) = 100.0 * st.tapErr / st.taps

    // MARK: hợp đồng

    @Test fun variantsComposeBack() {
        var ok = 0; var n = 0
        for (s in all.flatten().toSet()) { n++; if (TouchSim.validVariants(s).isNotEmpty()) ok++ }
        assertTrue("$ok/$n", ok >= n * 0.98)
        assertEquals(listOf("tieengs" to 0.6f, "tieesng" to 0.4f), TelexSpell.variants("tiếng"))
        assertEquals(listOf("dduwowcj" to 0.3f, "dduwowjc" to 0.2f, "dduowcj" to 0.3f, "dduowjc" to 0.2f),
            TelexSpell.variants("được"))
        assertEquals(listOf("hoaf" to 1f), TelexSpell.variants("hòa"))
        assertNull(TelexSpell.variants("a1"))
    }

    @Test fun priorFollowsLexicon() {
        val p0 = prior.forRaw("")!!
        assertTrue(p0('t')!! > p0('z')!! * 20)
        val th = prior.forRaw("th")!!
        assertTrue("th→a > th→s", th('a')!! > th('s')!!)
        val ko = prior.forRaw("k")!!
        assertTrue("seed chat: k→o có trọng số", ko('o')!! > 0f)
        assertNull("chuỗi ngoài trie ⇒ không biết", prior.forRaw("qqq"))
        assertNull("VNI: trie theo phím Telex ⇒ router cũ", prior.forTyping("tie", vniMode = true))
        assertEquals(prior.forRaw("tie")!!('e'), prior.forTyping("tie", vniMode = false)!!('e'))
        assertNull(prior.forRaw("a".repeat(TelexKeyPrior.MAX_RAW + 1)))
        assertTrue(prior.trie.nodeCount in 20_000..400_000)
    }

    /** Số chốt parity với iOS TouchTargetTests.parityWithKotlin — đổi dữ liệu/tham số thì cập nhật cả hai. */
    @Test fun parityNumbers() {
        val cases = listOf("" to 't', "" to 'z', "th" to 'a', "ng" to 'u', "k" to 'o', "tie" to 'e', "dd" to 'u', "hel" to 'l')
        val got = cases.map { (r, c) -> prior.forRaw(r)!!(c)!! }
        println("TOUCHSIM parity nodes=${prior.trie.nodeCount} " + cases.zip(got).joinToString { "${it.first}=${it.second}" })
        assertEquals(PARITY_NODES, prior.trie.nodeCount)
        for ((i, v) in got.withIndex()) assertEquals("${cases[i]}", PARITY_P[i], v, PARITY_P[i] * 1e-3f)
    }

    @Test fun keyCenterAlwaysWins() {
        // Prior cực lệch (chỉ phím kề có xác suất) — chạm trong lõi phím vẫn ra phím đó.
        val iQ = g.index['q' - 'a']; val iW = g.index['w' - 'a']
        val onlyW: (Char) -> Float? = { if (it == 'w') 1f else 0f }
        val c = g.center(iQ)
        assertEquals(iQ, TouchTarget.choose(c, g.rects, g.keys, iQ, onlyW))
        val r = g.rects[iQ]; val w = r.right - r.left
        // Sát mép phải của q (vùng biên) — prior đẩy sang w.
        val edge = KPoint(r.right - 0.05f * w, c.y)
        assertEquals(iW, TouchTarget.choose(edge, g.rects, g.keys, iQ, onlyW))
        // Không biết ngữ cảnh ⇒ không đổi.
        assertEquals(iQ, TouchTarget.choose(edge, g.rects, g.keys, iQ, { null }))
        // Prior đều ⇒ không đổi (margin).
        assertEquals(iQ, TouchTarget.choose(edge, g.rects, g.keys, iQ, { 1f / 26 }))
    }

    /** Chỉ phím chữ: "." cạnh "m" không bao giờ bị đổi sang chữ (hay ngược lại), kể cả prior cho '.' điểm. */
    @Test fun punctuationNeverRerouted() {
        val iM = g.index['m' - 'a']; val m = g.rects[iM]; val w = m.right - m.left
        val dot = KRect(m.right + 6f, m.top, m.right + 6f + w, m.bottom)
        val rects = g.rects + dot; val iDot = rects.size - 1
        val keys = g.keys + '.'
        val nearDot = KPoint(dot.left + 0.05f * w, (m.top + m.bottom) / 2)
        val nearM = KPoint(m.right - 0.05f * w, (m.top + m.bottom) / 2)
        // nearest = "." + prior chỉ cho m ⇒ vẫn "."
        assertEquals(iDot, TouchTarget.choose(nearDot, rects, keys, iDot, { if (it == 'm') 1f else 0f }))
        // nearest = m + prior chỉ cho "." ⇒ vẫn m
        assertEquals(iM, TouchTarget.choose(nearM, rects, keys, iM, { if (it == '.') 1f else 0f }))
        // đối chứng: cùng hình học, phím đó là CHỮ thì đổi được (test trên không rỗng)
        val keysZ = g.keys + 'z'
        assertEquals(iDot, TouchTarget.choose(nearM, rects, keysZ, iM, { if (it == 'z') 1f else 0f }))
        assertEquals(iM, TouchTarget.choose(nearDot, rects, keysZ, iDot, { if (it == 'm') 1f else 0f }))
    }

    /** Độ trễ lúc touchDown (forRaw + choose, chạm vùng biên) và cỡ trie. */
    @Test fun latencyAndSize() {
        SlowTests.assume()
        val t0 = System.nanoTime()
        val p = TelexKeyPrior.fromLexicon()
        val buildMs = (System.nanoTime() - t0) / 1e6
        val rng = Random(1)
        val raws = test.flatten().take(3000).mapNotNull { TouchSim.pickVariant(it, rng) }.map { it.take(rng.nextInt(it.length)) }
        val pts = List(4096) { TouchSim.tap(g, rng.nextInt(26), TouchSim.PROFILES[2], rng) }
        var sink = 0
        fun once(i: Int) {
            val q = TouchGeometry.keySelectionPoint(pts[i and 4095])
            val n = KeyRouter.nearestLetter(q, g.rects, 0f) ?: return
            val f = p.forRaw(raws[i % raws.size]) ?: return
            sink += TouchTarget.choose(q, g.rects, g.keys, n, f)
        }
        repeat(200_000) { once(it) }                  // JIT
        val n = 80_000
        var us = Double.MAX_VALUE                     // lô nhanh nhất / 5: máy bận không làm chập chờn
        repeat(5) {
            val t1 = System.nanoTime()
            repeat(n) { once(it) }
            us = minOf(us, (System.nanoTime() - t1) / 1e3 / n)
        }
        println("TOUCHSIM trie ${p.trie.nodeCount} nút, dựng ${"%.0f".format(buildMs)} ms; router+prior ${"%.2f".format(us)} µs/chạm (sink $sink)")
        assertTrue("≤ 20 µs/chạm: $us", us <= 20.0)
    }

    // MARK: hồi quy theo số đo (rút gọn: 400 câu TEST, 1 seed)

    @Test fun reducesSlipsWithoutHurtingCarefulTypists() {
        val sub = test.take(400)
        val base = TouchSim.baseline(g); val bay = TouchSim.bayes(g, prior, TouchTarget.DEFAULT)
        val aMid = TouchSim.run(sub, g, mid, 3L, base); val bMid = TouchSim.run(sub, g, mid, 3L, bay)
        val aCar = TouchSim.run(sub, g, careful, 3L, base); val bCar = TouchSim.run(sub, g, careful, 3L, bay)
        println("TOUCHSIM hồi quy vừa: a $aMid\n                  b $bMid\n  cẩn thận: a $aCar\n            b $bCar")
        assertTrue("lỗi phím giảm ≥ 40%: ${ter(aMid)} → ${ter(bMid)}", ter(bMid) <= ter(aMid) * 0.6)
        assertTrue("lỗi từ giảm ≥ 40%: ${wer(aMid)} → ${wer(bMid)}", wer(bMid) <= wer(aMid) * 0.6)
        assertTrue("đổi nhầm ≤ 0.15% phím: $bMid", bMid.badOverride * 1000 <= bMid.taps * 1.5)
        assertTrue("người gõ chuẩn không tệ hơn", bCar.wordErr <= aCar.wordErr)
    }

    @Test fun englishAndChatNotWorse() {
        val en = TouchSim.englishWords(1500, Random(5))
        val chat = TouchSim.chatWords(1500, Random(6))
        val oov = TouchSim.oovWords(10)
        val base = TouchSim.baseline(g); val bay = TouchSim.bayes(g, prior, TouchTarget.DEFAULT)
        for ((name, set) in listOf("EN" to en, "chat" to chat, "oov" to oov)) {
            val a = TouchSim.run(set, g, careful, 4L, base, english = true)
            val b = TouchSim.run(set, g, careful, 4L, bay, english = true)
            val am = TouchSim.run(set, g, mid, 4L, base, english = true)
            val bm = TouchSim.run(set, g, mid, 4L, bay, english = true)
            println("TOUCHSIM $name cẩn thận a ${wer(a)} b ${wer(b)} | vừa a ${wer(am)} b ${wer(bm)}")
            // từ lạ: cho phép lệch ≤ 1 từ / 0.5% (nhiễu mẫu nhỏ)
            assertTrue("$name cẩn thận", b.wordErr <= a.wordErr + maxOf(1, a.words / 200))
            if (name != "oov") assertTrue("$name vừa", bm.wordErr <= am.wordErr)
        }
    }

    // MARK: thử nghiệm đầy đủ (TOUCHSIM=1)

    private val geos = listOf(
        TouchSim.Geo(),
        TouchSim.Geo(pitchX = 66f, faceW = 60f, pitchY = 40f, faceH = 32f, name = "iPhone ngang"),
    )

    @Test fun experiment() {
        if (System.getenv("TOUCHSIM") == null) return
        val seeds = listOf(11L, 22L, 33L)
        val slowLearner = { TouchSim.OffsetLearner(rate = 0.01f, minSamples = 100, dead = 1.5f) }
        for (geo in geos) {
            println("==== TEST ${test.size} câu × ${seeds.size} seed — ${geo.name} ====")
            for (pr in TouchSim.PROFILES) {
                val methods = listOf<Pair<String, (Long) -> TouchSim.Stats>>(
                    "a gần nhất " to { s -> TouchSim.run(test, geo, pr, s, TouchSim.baseline(geo)) },
                    "b bayes    " to { s -> TouchSim.run(test, geo, pr, s, TouchSim.bayes(geo, prior, TouchTarget.DEFAULT)) },
                    "c học lệch " to { s -> TouchSim.run(test, geo, pr, s, TouchSim.baseline(geo), TouchSim.OffsetLearner()) },
                    "c2 học chậm" to { s -> TouchSim.run(test, geo, pr, s, TouchSim.baseline(geo), slowLearner()) },
                    "b+c2       " to { s -> TouchSim.run(test, geo, pr, s, TouchSim.bayes(geo, prior, TouchTarget.DEFAULT), slowLearner()) },
                )
                for ((mn, f) in methods) println("${pr.name} | $mn | ${merge(seeds.map(f))}")
            }
        }
    }

    @Test fun robustness() {
        if (System.getenv("TOUCHSIM") == null) return
        val seeds = listOf(11L, 22L, 33L)
        val en = TouchSim.englishWords(6000, Random(5))
        val chat = TouchSim.chatWords(6000, Random(6))
        val oov = TouchSim.oovWords(40)
        println("==== ROBUST (oov ${oov.size / 40} từ) ====")
        for (pr in TouchSim.PROFILES) {
            for ((label, set, eng, free) in listOf(
                Quad("từ Anh    ", en, true, false),
                Quad("chat/tắt  ", chat, true, false),
                Quad("từ lạ OOV ", oov, true, false),
                Quad("dấu tự do ", test, false, true),
            )) {
                val a = merge(seeds.map { TouchSim.run(set, g, pr, it, TouchSim.baseline(g), english = eng, free = free) })
                val b = merge(seeds.map { TouchSim.run(set, g, pr, it, TouchSim.bayes(g, prior, TouchTarget.DEFAULT), english = eng, free = free) })
                println("${pr.name} | $label | a: $a")
                println("${pr.name} | $label | b: $b")
            }
        }
    }

    /** (d) gợi ý sửa từ Việt HỢP LỆ trên thanh (AdjacentKeyFixer hiện chỉ lo từ không phải tiếng Việt). */
    @Test fun suggestionExperiment() {
        if (System.getenv("TOUCHSIM") == null) return
        val seeds = listOf(11L, 22L)
        println("==== (d) gợi ý sửa — TEST ====")
        for (pr in TouchSim.PROFILES.take(3)) for ((rn, router) in listOf("a" to TouchSim.baseline(g), "b" to TouchSim.bayes(g, prior, TouchTarget.DEFAULT))) {
            for (tau in listOf(1f, 2f, 3f)) {
                val st = merge(seeds.map { TouchSim.run(test, g, pr, it, router, suggester = TouchSim.vnFixer(g, tau, onlyValid = true)) })
                println("${pr.name} | router $rn | τ=$tau | ${st.sugString()}")
            }
        }
    }

    /**
     * Dò σ ngang/dọc của mô hình chạm (TOUCHSIM_SIGMA=1): người thật lệch dọc ít hơn ngang
     * (theo bề cao phím) ⇒ thử σy nhỏ hơn. In tap / khác-hàng / từ / đổi-nhầm, gộp 5 người gõ.
     */
    @Test fun sigmaSweep() {
        if (System.getenv("TOUCHSIM_SIGMA") == null) return
        val split = if (System.getenv("TOUCHSIM_SIGMA") == "test") test else dev
        val seeds = listOf(11L, 22L)
        val en = TouchSim.englishWords(3000, Random(7))
        val chat = TouchSim.chatWords(3000, Random(8))
        fun row(name: String, m: (KPoint, String) -> Int) {
            val per = TouchSim.PROFILES.map { pr -> merge(seeds.map { TouchSim.run(split, g, pr, it, m) }) }
            val tot = merge(per)
            val e = merge(listOf(careful, mid).flatMap { pr -> seeds.map { TouchSim.run(en, g, pr, it, m, english = true) } })
            val c = merge(listOf(careful, mid).flatMap { pr -> seeds.map { TouchSim.run(chat, g, pr, it, m, english = true) } })
            fun f(st: TouchSim.Stats) = "%.3f/%.3f/%.2f".format(ter(st), 100.0 * st.crossRow / st.taps, wer(st))
            println("SIGMA $name | gộp tap/khác-hàng/từ ${f(tot)} đổi-nhầm ${"%.3f".format(100.0 * tot.badOverride / tot.taps)} | " +
                per.joinToString(" | ") { f(it) } + " | EN từ ${"%.2f".format(wer(e))} chat từ ${"%.2f".format(wer(c))}")
        }
        println("SIGMA split=${split.size} câu × ${seeds.size} seed; cột người gõ: ${TouchSim.PROFILES.joinToString { it.name.trim() }}")
        row("gần nhất     ", TouchSim.baseline(g))
        for (sx in listOf(0.30f, 0.33f, 0.35f)) for (sy in listOf(0.30f, 0.27f, 0.25f, 0.22f)) {
            row("sx=$sx sy=$sy", TouchSim.bayes(g, prior, TouchTarget.DEFAULT.copy(sigmaX = sx, sigmaY = sy)))
        }
    }

    /** Dò tham số trên DEV (1 seed). */
    @Test fun tune() {
        if (System.getenv("TOUCHSIM_TUNE") == null) return
        val sub = dev.take(500)
        val en = TouchSim.englishWords(2500, Random(7))
        val chat = TouchSim.chatWords(2500, Random(8))
        val oov = TouchSim.oovWords(20)
        val fast = TouchSim.PROFILES[2]
        fun f2(l: List<Double>) = l.joinToString { "%.2f".format(it) }
        fun eval(m: (KPoint, String) -> Int): String {
            val vi = listOf(careful, mid, fast).map { wer(TouchSim.run(sub, g, it, 1L, m)) }
            val e = listOf(careful, mid).map { wer(TouchSim.run(en, g, it, 1L, m, english = true)) }
            val c = listOf(careful, mid).map { wer(TouchSim.run(chat, g, it, 1L, m, english = true)) }
            val o = listOf(careful, mid).map { wer(TouchSim.run(oov, g, it, 1L, m, english = true)) }
            return "vi=${f2(vi)} en=${f2(e)} chat=${f2(c)} oov=${f2(o)}"
        }
        println("TUNE baseline | ${eval(TouchSim.baseline(g))}")
        for (lam in listOf(0.05f, 0.06f, 0.07f)) for (gam in listOf(0.1f, 0.2f)) {
            val pri = TelexKeyPrior.fromLexicon(lam, gam)
            for (sig in listOf(0.3f)) for (margin in listOf(0.5f, 1.0f, 1.5f)) for (floor in listOf(0.05f, 0.1f, 0.2f)) {
                val q = TouchTargetParams(sig, sig, 0.25f, 0.25f, 0.45f, margin, floor)
                println("TUNE lam=$lam gam=$gam sig=$sig margin=$margin floor=$floor | ${eval(TouchSim.bayes(g, pri, q))}")
            }
        }
    }

    private companion object {
        const val PARITY_NODES = 63370
        val PARITY_P = floatArrayOf(0.16052505f, 2.420141e-5f, 0.25838506f, 0.49238884f, 0.002160288f, 0.99860436f, 0.17761526f, 0.17500657f)
    }

    private data class Quad<A, B, C, D>(val a: A, val b: B, val c: C, val d: D)

    private fun merge(xs: List<TouchSim.Stats>) = TouchSim.Stats().also { t -> xs.forEach(t::add) }
}
